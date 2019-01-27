import tables
import math
import strutils

import nimx.animation
import nimx.matrixes

import nimx.timer

import rod.rod_types
import rod.node
import rod.viewport
import rod.component.ae_composition

import utils.helpers

type Completion* = ref object
    finalizers: seq[proc()]

proc newCompletion*(): Completion =
    result.new()
    result.finalizers = @[]

proc to*(c: Completion, finalizer: proc()) =
    c.finalizers.add(finalizer)

proc finalize*(c: Completion) =
    for job in c.finalizers:
        job()
    c.finalizers = @[]

proc waitUntil*(v: SceneView, bVal: proc(): bool, callback: proc()) =
    if bVal():
        callback()
    else:
        var a = newAnimation()
        a.loopDuration = 0.1
        a.numberOfLoops = -1
        a.onAnimate = proc(p: float) =
            if not a.isCancelled():
                if bVal(): a.cancel()
        a.onComplete do():
            callback()
            a = nil
        v.addAnimation(a)

proc doForAllBranch*(n: Node, job: proc(nd: Node)) =
    n.job()
    for ch in n.children:
        ch.job()
        ch.doForAllBranch(job)

proc getChildrenWithSubname*(n: Node, subname: string): seq[Node] =
    result = @[]
    for c in n.children:
        if c.name.contains(subname):
            result.add(c)

proc getAllChildrenWithSubname*(n: Node, subname: string): seq[Node] =
    var nodes = newSeq[Node]()
    result = nodes
    proc getChSubname(nd: Node) =
        if nd.name.contains(subname):
            nodes.add(nd)
        for c in nd.children:
            c.getChSubname()
    n.getChSubname()

proc getFirstChildrenWithSubname*(n: Node, subname: string): Node =
    n.findNode proc(nd: Node): bool = nd.name.contains(subname)

proc addAnim(n: Node, anim: Animation) =
    if not anim.isNil and anim.isCancelled():
        n.addAnimation(anim)
        anim.onComplete do():
            anim.removeHandlers()
            anim.cancel()

proc cancelAnims*(n: Node) =
    n.doForAllBranch do(nd: Node):
        if not nd.animations.isNil:
            for name, a in nd.animations:
                a.removeHandlers()
                a.cancel()

proc animateRecursively*(n: Node, rootAnimName: string, includedAnimsName: string) =
    let anim = n.animationNamed(rootAnimName)
    n.cancelAnims()
    n.addAnim(anim)
    anim.chainOnAnimate do(p: float):
        n.doForAllBranch do(nd: Node):
            if nd.alpha > 0.01:
                var anm = nd.animationNamed(includedAnimsName)
                if anm.isNil: anm = nd.animationNamed(rootAnimName)
                nd.addAnim(anm)

proc playBounceAnim(n: Node) =
    # var bounceEndAnim = newAnimation()
    # bounceEndAnim.loopDuration = 2.0
    # bounceEndAnim.numberOfLoops = -1
    # var amplitude = 65.0
    # let fade = 0.3
    # let startPosY = n.positionY
    # bounceEndAnim.animate val in 0.0 .. (2.0 * PI):
    #     n.positionY = startPosY + amplitude * sin(val)
    #     amplitude -= fade

    #     if amplitude < 0.01:
    #         bounceEndAnim.cancel()
    #         n.positionY = startPosY

    # n.addAnimation(bounceEndAnim)
    # bounceEndAnim.onComplete do():
    #     bounceEndAnim.removeHandlers()
    #     bounceEndAnim = nil
    var bounceEndAnim = newAnimation()
    bounceEndAnim.loopDuration = 0.25
    bounceEndAnim.numberOfLoops = 1
    var amplitude = 70.0
    let startPosY = n.positionY
    bounceEndAnim.animate val in 0.0 .. (PI):
        n.positionY = startPosY - amplitude * cos(val)

    n.addAnimation(bounceEndAnim)
    bounceEndAnim.onComplete do():
        bounceEndAnim.removeHandlers()
        bounceEndAnim = nil

proc doUpAnim*(node: Node, startY, destY, moveTime: float32): Animation =
    var anim = newAnimation()
    anim.loopDuration = moveTime
    anim.numberOfLoops = 1
    anim.onAnimate = proc(p: float) =
        node.positionY = interpolate(startY, destY, p)
    node.addAnimation(anim)
    anim.onComplete do():
        anim.removeHandlers()
        anim = nil
    result = anim

proc doUpAnim*(fromNode, toNode: tuple[pos: Vector3, node: Node], moveTime: float32): Animation =
    var anim = newAnimation()
    let startY = fromNode.pos[1]
    let destY = toNode.pos[1]
    fromNode.node.doUpAnim(startY, destY, moveTime)

proc playComposition*(n: Node, name: string, callback: proc() = nil): Animation {.discardable.} =
    let aeComp = n.component(AEComposition)
    let anim = aeComp.compositionNamed(name)
    if not callback.isNil:
        anim.onComplete(callback)
    if not n.sceneView.isNil:
        n.addAnimation(anim)
    result = anim

proc playComposition*(n: Node, callback: proc() = nil): Animation {.discardable.} =
    result = n.playComposition("aeAllCompositionAnimation", callback)
