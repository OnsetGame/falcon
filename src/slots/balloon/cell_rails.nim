import tables
import sequtils
import strutils
import random

import nimx.context
import nimx.animation
import nimx.window
import nimx.timer
import nimx.portable_gl

import rod.scene_composition
import rod.rod_types
import rod.node
import rod.viewport
import rod.component
import rod.component.mesh_component
import rod.quaternion

import balloon_composition

const FLY_IN_TIME* = 1.75
const FLY_OUT_TIME* = 1.0

type CellRail* = ref object
    anchor*: Node
    carriage*: Node

    animInNode*: Node
    animOutNode*: Node

    animIn*: Animation
    animOut*: Animation

    balloon: BalloonComposition

proc translation*(cr: CellRail): Vector3 = result = cr.anchor.position

proc `translation=`*(cr: CellRail, translation :Vector3) =
    cr.anchor.position = translation

proc newCellRailWithResource*(res: string, id: int8): CellRail =
    result.new()
    var anchor: Node
    var carriage: Node
    var animInNode: Node
    var animOutNode: Node
    var animIn: Animation
    var animOut: Animation

    loadSceneAsync res, proc(n: Node) =
        anchor = n
        anchor.name = "cell_" & $id

        for name, child in anchor.children:
            if child.name.contains("in"):
                animInNode = child

            if child.name.contains("out"):
                animOutNode = child

            if not isNil(child.animations):
                for name, anim in child.animations:
                    if name.contains("in"):
                        animIn = anim
                        animIn.numberOfLoops = 1
                        animIn.cancelBehavior = cbJumpToEnd
                        animIn.loopDuration = FLY_IN_TIME+rand(2000.Coord)/2000.0
                        animIn.removeHandlers()
                    if name.contains("out"):
                        animOut = anim
                        animOut.numberOfLoops = 1
                        animOut.cancelBehavior = cbJumpToEnd
                        animOut.loopDuration = FLY_OUT_TIME+rand(2000.Coord)/2000.0
                        animOut.removeHandlers()

    result.anchor = anchor
    result.anchor.addChild(animInNode)
    result.anchor.addChild(animOutNode)
    carriage = anchor.newChild("carriage")

    result.carriage = carriage
    result.animInNode = animInNode
    result.animOutNode = animOutNode
    result.animIn = animIn
    result.animOut = animOut

proc playIn*(cr: CellRail, callback: proc() = proc() = discard) =
    let view = cr.anchor.sceneView()
    if not view.isNil:
        cr.animInNode.addChild(cr.carriage)
        view.addAnimation(cr.animIn)
        cr.balloon.balloonNode.alpha = 1.0 # show if it was hidden after destroy
        cr.animIn.removeHandlers()
        # cr.animIn.onComplete do():
        #     callback()

proc playOut*(cr: CellRail, callback: proc() = proc() = discard) =
    let view = cr.anchor.sceneView()
    if not view.isNil:
        cr.animOutNode.addChild(cr.carriage)
        view.addAnimation(cr.animOut)
        cr.animOut.removeHandlers()
        # cr.animOut.onComplete do():
        #     callback()

proc playIdle*(cr: CellRail) =
    let view = cr.anchor.sceneView()
    view.addAnimation(cr.balloon.animIdle)

proc playSlowIdle*(cr: CellRail) =
    let view = cr.anchor.sceneView()
    view.addAnimation(cr.balloon.animIdleSlow)

proc playFastIdle*(cr: CellRail) =
    let view = cr.anchor.sceneView()
    view.addAnimation(cr.balloon.animIdleFast)

proc stopIdle*(cr: CellRail) =
    cr.balloon.animIdleFast.cancel()
    cr.balloon.animIdleSlow.cancel()
    cr.balloon.animIdle.cancel()

proc addChild*(cr: CellRail, n: Node) =
    cr.carriage.addChild(n)

proc removeAllChildren*(cr: CellRail) =
    cr.carriage.removeAllChildren()

proc swap*(first, second: CellRail) =
    if not first.balloon.isNil and not second.balloon.isNil:
        let firstChild = first.balloon.anchor
        firstChild.removeFromParent()

        let secondChild = second.balloon.anchor
        secondChild.removeFromParent()

        first.carriage.addChild(secondChild)
        second.carriage.addChild(firstChild)

        swap(first.balloon, second.balloon)
    else:
        echo("SWAP ERROR")

proc balloon*(cr: CellRail): BalloonComposition =
    result = cr.balloon

proc `balloon=`*(cr: CellRail, b: BalloonComposition) =
    if not cr.balloon.isNil:
        cr.balloon.anchor.removeFromParent()
    cr.balloon = b
    cr.addChild(b.anchor)
