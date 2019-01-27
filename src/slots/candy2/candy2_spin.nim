import rod / [ node, component ]
import rod.component / [ channel_levels ]
import nimx / [ matrixes, animation ]
import shared.game_scene
import candy2_types
import random, sequtils

proc createElement*(key: string): Element =
    result.new()
    result.node = newLocalizedNodeWithResource("slots/candy2_slot/elements/precomps/" & key)
    result.state = Prepared

proc createElement*(node: Node): Element =
    result.new()
    result.node = node
    result.state = Prepared

proc createPlaceholder*(parent: Node): Placeholder =
    const OFFSET = newVector3(-190, -530)

    result.new()
    result.node = parent.newChild("placeholder")
    result.table = parent
    result.node.position = OFFSET
    result.caramels = @[]
    result.motions = @[]
    result.curCaramels = @[]
    result.colorSpins = @[]
    result.curMotions = @[]
    result.curColorSpins = @[]

    for i in 1..9:
        for j in 1..3:
            let caramel = newLocalizedNodeWithResource("slots/candy2_slot/elements/precomps/caramel_spin_" & $j & ".json")
            result.caramels.add(caramel)
    for i in 1..3:
        for j in 1..6:
            let colorSpin = newLocalizedNodeWithResource("slots/candy2_slot/elements/precomps/color_spin_" & $j & ".json")
            result.colorSpins.add(colorSpin)
        for j in 1..7:
            let motion = newLocalizedNodeWithResource("slots/candy2_slot/elements/precomps/motion_" & $j & ".json")
            result.motions.add(motion)

proc choose(all: var seq[Node]): Node =
    if all.len > 0:
        let i = rand(all.high)
        result = all[i]
        all.del(i)

proc startCaramel(pl: Placeholder) =
    const OFFSET = newVector3(90, 350)
    const CHANCE = 0.2

    var anim = pl.node.animationNamed("startCaramel")
    if anim.isNil:
        anim = newAnimation()
        pl.node.registerAnimation("startCaramel", anim)

    let yOffset = @[20'f32, 40, 80, 100]

    anim.loopDuration = 1.0
    anim.numberOfLoops = -1

    for i in 1..14:
        anim.addLoopProgressHandler 0.07 * i.float, false, proc() =
            if pl.element.state == Idle:
                let n = choose(pl.caramels)
                if n.isNil:
                    return
                pl.curCaramels.add(n)

                let comp = n.component(ChannelLevels)
                let randLevels = rand(1.0)
                if randLevels < CHANCE:
                    comp.inGamma = 4.07
                    comp.outBlack = 4.3
                    comp.outWhite = 1.47
                else:
                    comp.inGamma = 1.0
                    comp.outBlack = 0.0
                    comp.outWhite = 1.0

                pl.node.addChild(n)

                let scale = rand(0.6)
                n.scale = newVector3(1.1 + scale, 1.1 + scale, 1)
                n.position = newVector3(OFFSET.x, OFFSET.y + rand(yOffset))

                let cAnim = n.animationNamed("play")
                pl.node.addAnimation(cAnim)
                cAnim.onComplete do():
                    var ind = pl.curCaramels.find(n)
                    if ind > -1:
                        pl.curCaramels.del(ind)
                        pl.caramels.add(n)
            else:
                anim.cancel()
    pl.node.addAnimation(anim)

proc startCarousel(pl: Placeholder, offset: Vector3, isMotion: bool) =
    var n: Node
    var r: int

    if isMotion:
        n = choose(pl.motions)
        pl.curMotions.add(n)
    else:
        n = choose(pl.colorSpins)
        pl.curColorSpins.add(n)

    if n.isNil:
        return

    let anim = n.animationNamed("play")

    pl.node.addChild(n)
    n.position = offset
    pl.node.addAnimation(anim)
    anim.onComplete do():
        n.removeFromParent()

        if isMotion:
            var idx = pl.curMotions.find(n)
            if idx > -1:
                pl.motions.add(n)
                pl.curMotions.del(idx)
        else:
            var idx = pl.curColorSpins.find(n)
            if idx > -1:
                pl.colorSpins.add(n)
                pl.curColorSpins.del(idx)

        if pl.element.state == Idle:
            pl.startCarousel(offset, isMotion)

proc startColorCarousel(pl: Placeholder) =
    pl.startCarousel(newVector3(67, 365), false)

proc startMotionCarousel(pl: Placeholder) =
    pl.startCarousel(newVector3(-80, 273), true)

proc startIdle(pl: Placeholder) =
    let anim = pl.table.animationNamed("idle")

    anim.numberOfLoops = -1
    pl.node.addAnimation(anim)
    pl.element.state = Idle
    pl.node.removeAllChildren()
    pl.startColorCarousel()
    pl.startMotionCarousel()
    pl.startCaramel()

proc spinInAnim*(pl: Placeholder): Animation =
    let elemAnim = pl.element.node.animationNamed("start")
    let tableAnim = pl.table.animationNamed("in")

    elemAnim.loopDuration = 0.15
    result = newCompositAnimation(true, elemAnim, tableAnim)
    result.numberOfLoops = 1
    pl.element.state = In
    tableAnim.addLoopProgressHandler 0.3, false, proc() =
        pl.startMotionCarousel()
        pl.startCaramel()
    tableAnim.addLoopProgressHandler 0.45, false, proc() =
        startIdle(pl)

proc spinOutAnim*(pl: Placeholder): Animation =
    pl.element.state = Out
    pl.table.animationNamed("idle").cancel()
    pl.node.animationNamed("startCaramel").cancel()

    result = pl.table.animationNamed("out")
    result.loopDuration = 0.2
    result.onComplete do():
        pl.element.state = Finished
