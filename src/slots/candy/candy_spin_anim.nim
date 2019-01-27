import nimx.view
import nimx.context
import nimx.animation
import nimx.window
import nimx.timer

import rod.quaternion
import rod.rod_types
import rod.node
import rod.viewport
import rod.component
import rod.component.channel_levels

import core.slot.base_slot_machine_view

import utils.helpers
import utils.pause

import random
import strutils

const CARAMEL_COUNT = 6
const COLOR_SPIN_COUNT = 6
const SPIN_ELEMENTS_COUNT = 11
const CREAM_COUNT = 2

type CandySymbolAnimation* = ref object of RootObj
    root*: Node
    topAnchor: Node
    bottomAnchor: Node
    startSymbol: Node
    drops: Node
    loopedAnims: seq[Animation]
    startTableAnim: Animation
    spinTableAnim: Animation
    endTableAnim: Animation
    startSymbolAnim: Animation
    endSymbolAnim: Animation
    caramelPool: seq[Node]
    spinPool: seq[Node]
    creamPool: seq[Node]
    colorSpinPool: seq[Node]

proc createCaramelPool(): seq[Node] =
    result = @[]

    for i in 0..<CARAMEL_COUNT:
        let caramel1 = newLocalizedNodeWithResource("slots/candy_slot/slot/precomps/caramel_spin_1.json")
        let caramel2 = newLocalizedNodeWithResource("slots/candy_slot/slot/precomps/caramel_spin_2.json")
        let caramel3 = newLocalizedNodeWithResource("slots/candy_slot/slot/precomps/caramel_spin_3.json")

        result.add(caramel1)
        result.add(caramel2)
        result.add(caramel3)
    return result

proc createSpinPool(): seq[Node] =
    result = @[]

    for i in 1..SPIN_ELEMENTS_COUNT:
        let spin = newLocalizedNodeWithResource("slots/candy_slot/slot/precomps/spin_" & $i & ".json")
        result.add(spin)

proc createColorSpinPool(): seq[Node] =
    result = @[]

    for i in 1..COLOR_SPIN_COUNT:
        let colorSpin = newLocalizedNodeWithResource("slots/candy_slot/slot/precomps/color_spin_" & $i & ".json")
        result.add(colorSpin)

proc createCreamPool(): seq[Node] =
    result = @[]

    for i in 1..CREAM_COUNT:
        let cream = newLocalizedNodeWithResource("slots/candy_slot/slot/precomps/cream.json")
        result.add(cream)

proc hideElements(n: Node, sym: int) =
    for c in n.findNode("elements_anchor").children:
        if c.name != "elem_" & $sym:
            c.alpha = 0
        else:
            c.alpha = 1

proc createCandyInitialSymbol*(v:BaseMachineView, parent: Node, sym: int): CandySymbolAnimation =
    result.new()
    result.loopedAnims = @[]
    result.root = parent.newChild("symbol")

    let table = newLocalizedNodeWithResource("slots/candy_slot/slot/precomps/table.json")
    result.startTableAnim = table.animationNamed("start")
    result.spinTableAnim = table.animationNamed("spin")
    result.endTableAnim = table.animationNamed("end")

    result.startTableAnim.loopDuration = result.startTableAnim.loopDuration / 1.5
    result.spinTableAnim.loopDuration = result.spinTableAnim.loopDuration / 1.5
    result.endTableAnim.loopDuration = result.endTableAnim.loopDuration / 1.5

    result.startSymbol = newLocalizedNodeWithResource("slots/candy_slot/slot/precomps/start_symbol.json")
    result.startSymbol.hideElements(sym)

    result.bottomAnchor = result.root.newChild("bottom_anchor")
    result.topAnchor = result.root.newChild("top_anchor")

    result.drops = newLocalizedNodeWithResource("slots/candy_slot/slot/precomps/spin_drops.json")
    result.bottomAnchor.addChild(result.drops)
    result.drops.position = newVector3(-15, -110)

    result.caramelPool = createCaramelPool()
    result.spinPool = createSpinPool()
    result.creamPool = createCreamPool()
    result.colorSpinPool = createColorSpinPool()

    discard result.bottomAnchor.newChild("highlight_anchor")
    result.bottomAnchor.addChild(table)
    result.bottomAnchor.addChild(result.startSymbol)

    result.bottomAnchor.position = newVector3(0, 35)
    result.topAnchor.position = newVector3(0, -35)
    result.startSymbol.position = newVector3(-15, -140)

proc randomizeCaramel(n: Node, forWild: bool = false) =
    let comp =  n.component(ChannelLevels)
    if forWild:
        comp.inGamma = 1.0
        comp.outBlack = 0.0
        comp.outWhite = 1.0
        return

    const CHANCE = 0.7
    const ROTATION = newQuaternion()

    let angle = ROTATION * aroundZ(rand(-6..6).Coord)
    let randLevels = rand(1.0)

    if randLevels < CHANCE:
        comp.inGamma = 4.07
        comp.outBlack = 4.3
        comp.outWhite = 1.47
    else:
        comp.inGamma = 1.0
        comp.outBlack = 0.0
        comp.outWhite = 1.0
    n.rotation = angle

proc startAnimatedTimer(sa: CandySymbolAnimation, timeout: float, callback: proc()) =
    if not sa.root.isNil and not sa.root.sceneView.isNil:
        let anim = startAnimatedTimer(sa.root.sceneView, timeout, callback,  -1)
        sa.loopedAnims.add(anim)

proc startSpinAnim*(v:BaseMachineView, sa: CandySymbolAnimation, sym: int, forWild: bool = false) =
    v.addAnimation(sa.startTableAnim)

    sa.startTableAnim.onComplete do():
        v.addAnimation(sa.spinTableAnim)
    proc phase1() =
        let nextCaramel1 = rand(sa.caramelPool)
        let nextCaramelAnim1 = nextCaramel1.animationNamed("play")
        var randTransition = rand(50'f32)
        var randScale = rand(0.6)
        let nextCaramel2 = rand(sa.caramelPool)
        let nextCaramelAnim2 = nextCaramel2.animationNamed("play")

        nextCaramel1.randomizeCaramel(forWild)
        nextCaramel2.randomizeCaramel(forWild)
        sa.topAnchor.addChild(nextCaramel1)
        nextCaramel1.position = newVector3(40, 160 + randTransition)
        nextCaramel1.scale = newVector3(1.3 + randScale, 1.3 + randScale, 1)
        randScale = rand(0.6)
        sa.topAnchor.addChild(nextCaramel2)
        nextCaramel2.position = newVector3(40, 160 + randTransition)
        nextCaramel2.scale = newVector3(1.3 + randScale, 1.3 + randScale, 1)
        nextCaramelAnim1.continueUntilEndOfLoopOnCancel = true
        nextCaramelAnim2.continueUntilEndOfLoopOnCancel = true
        v.addAnimation(nextCaramelAnim1)
        v.addAnimation(nextCaramelAnim2)
    startAnimatedTimer(sa, 0.17, phase1)

    proc phase2() =
        for i in 0..<3:
            let nextSpin = rand(sa.spinPool)
            let nextSpinAnim = nextSpin.animationNamed("play")

            sa.bottomAnchor.addChild(nextSpin)
            nextSpin.position = newVector3(15, 65)
            v.addAnimation(nextSpinAnim)
    startAnimatedTimer(sa, 0.25, phase2)

    proc phase3() =
        for i in 0..<2:
            let nextColorSpin = rand(sa.colorSpinPool)
            let nextColorSpinAnim = nextColorSpin.animationNamed("play")

            sa.bottomAnchor.addChild(nextColorSpin)
            nextColorSpin.position = newVector3(100, 85)
            v.addAnimation(nextColorSpinAnim)
    startAnimatedTimer(sa, 0.35, phase3)

    if sym != 1:
        sa.startSymbolAnim = sa.startSymbol.findNode("elem_" & $sym).animationNamed("start")
        v.addAnimation(sa.startSymbolAnim)
        sa.startSymbolAnim.onComplete do():
            sa.startSymbol.alpha = 0
            phase1()
            phase2()
            phase3()
    else:
        sa.startSymbol.alpha = 0
        phase1()
        phase2()
        phase3()
    v.addAnimation(sa.startSymbol.findNode("elements").animationNamed("start"))


proc endSpinAnim*(v:BaseMachineView, sa: CandySymbolAnimation, sym: int, scatters: int, forWild: bool = false) =
    sa.startSymbol.hideElements(sym)

    var node = sa.startSymbol.findNode("elem_" & $sym)
    if sym == 1:
        node = sa.startSymbol.findNode("scatter_fly_" & $scatters)

    if not node.isNil:
        sa.endSymbolAnim = node.animationNamed("finish")
    v.addAnimation(sa.startSymbol.findNode("elements").animationNamed("finish"))
    sa.startSymbol.findNode("elements").alpha = 1
    for anim in sa.loopedAnims:
        anim.cancel()
    sa.spinTableAnim.continueUntilEndOfLoopOnCancel = false
    sa.spinTableAnim.cancel()
    v.addAnimation(sa.endTableAnim)
    if not forWild:
        sa.bottomAnchor.addChild(sa.creamPool[0])
        sa.creamPool[0].position = newVector3(300, 175)
        sa.bottomAnchor.addChild(sa.creamPool[1])
        sa.creamPool[1].position = newVector3(300, 175)
        sa.creamPool[1].scale = newVector3(-1, 1)

        sa.endTableAnim.addLoopProgressHandler 0.2, false, proc() =
            v.addAnimation(sa.creamPool[0].animationNamed("play"))
            v.addAnimation(sa.creamPool[1].animationNamed("play"))

    sa.startSymbol.alpha = 1
    sa.endTableAnim.onComplete do():
        if not sa.endSymbolAnim.isNil:
            v.addAnimation(sa.endSymbolAnim)
