import nimx / [ types, matrixes, animation ]
import rod / [ node, component ]
import rod.component / [ ae_composition, visual_modifier, particle_system ]
import utils / [ animation_controller, sound_manager, fade_animation ]
import candy2_slot_view, candy2_interior, candy2_spin
import core.slot / [ base_slot_machine_view, sound_map ]
import shafa.slot.slot_data_types
import json

proc createWildParticles*(v: Candy2SlotView) =
    const COUNT = ELEMENTS_COUNT

    v.wildParticles = @[]
    for i in 0..<COUNT:
        v.wildParticles.add(newLocalizedNodeWithResource("slots/candy2_slot/particles/choko_fx"))

proc setupSpinData*(v: Candy2SlotView) =
    let stage = v.lastResponce["stages"][0]

    v.spinData.field = v.lastField
    v.spinData.wildIndexes = @[]
    if $srtWildIndexes in stage:
        for i in stage[$srtWildIndexes].items:
            v.spinData.wildIndexes.add(i.getNum().int)
        v.spinData.wildActivator = stage[$srtWildActivator].getNum().int

proc blowElement(v: Candy2SlotView, index: int, cb: proc() = nil) =
    let explosion = newLocalizedNodeWithResource("slots/candy2_slot/elements/precomps/wild_explosion")
    let plac = v.interior.placeholders[index]

    plac.node.addChild(explosion)
    explosion.position = newVector3(40.0, 175.0)

    let anim = explosion.animationNamed("play")
    plac.element.node.reparentTo(explosion.findNode("parent_element"))
    v.interior.node.addAnimation(anim)

    let wild = v.interior.getElem("elem_0")
    explosion.findNode("parent_wild").addChild(wild.node)
    wild.node.position = newVector3(-245.0, -380.0)
    plac.element = wild

    anim.onComplete do():
        if not cb.isNil:
            cb()

proc sendWildParticles(v: Candy2SlotView, cb: proc()) =
    for index in 0..v.spinData.wildIndexes.high:
        closureScope:
            let ind = index
            let i = v.spinData.wildIndexes[ind]
            let s = v.interior.tables[v.spinData.wildActivator].position + newVector3(-295, -175)
            let wildParticle = v.wildParticles[i]
            let e = v.interior.tables[i].position + newVector3(-295, -175)
            let c1 = newVector3(s.x - (s.x - e.x) / 2, e.y - 200)
            let c2 = c1

            v.rootNode.addChild(wildParticle)
            wildParticle.position = s
            for c in wildParticle.children:
                let emitter = c.component(ParticleSystem)
                emitter.start()

            let fly = newAnimation()
            fly.numberOfLoops = 1
            fly.loopDuration = 1.0
            fly.onAnimate = proc(p: float) =
                let t = interpolate(0.0, 1.0, p)
                let point = calculateBezierPoint(t, s, e, c1, c2)
                wildParticle.position = point
            v.interior.node.addAnimation(fly)
            v.sound.play("CANDY_WILD_EXPLODES")
            v.sound.play("CANDY_WILD_SPRINKLE")
            fly.onComplete do():
                if ind == v.spinData.wildIndexes.high:
                    v.blowElement(i, cb)
                else:
                    v.blowElement(i)
                for c in wildParticle.children:
                    let emitter = c.component(ParticleSystem)
                    emitter.stop()
                wildParticle.removeFromParent()

proc blowWild(v: Candy2SlotView, cb: proc()): Animation =
    let t = v.interior
    let plac = t.placeholders[v.spinData.wildActivator]
    let oldCake = plac.element.node
    let anim = oldCake.component(AEComposition).compositionNamed("boom")
    result = v.boyController.setImmediateAnimation("wild")

    result.addLoopProgressHandler 0.2, true, proc() =
        oldCake.reparentTo(t.node)
        t.node.addAnimation(anim)
        anim.addLoopProgressHandler 0.7, true, proc() =
            t.setElement(v.spinData.wildActivator, 0'i8)
            t.node.addAnimation(plac.element.node.component(AEComposition).compositionNamed("finish"))

            let fade = addFadeSolidAnim(v, v.rootNode, whiteColor(), VIEWPORT_SIZE, 1.0, 0.0, 0.3)
            v.rootNode.addAnimation(v.shakeParent.shake)
            v.sendWildParticles(cb)
            fade.animation.onComplete do():
                fade.removeFromParent()

        anim.onComplete do():
            oldCake.removeFromParent()

proc startCandyFirework(v: Candy2SlotView) =
    let firework = newLocalizedNodeWithResource("slots/candy2_slot/boy/precomps/firework")

    v.interior.tableField.addChild(firework)
    firework.position = newVector3(0, -150)

    let s = firework.position
    let e = v.interior.tables[v.spinData.wildActivator].position + newVector3(-740.0, -835.0)
    let c1 = newVector3((0).float, (-400).float)
    let c2 = newVector3((250).float, (-400).float)
    let fly = newAnimation()

    fly.numberOfLoops = 1
    fly.loopDuration = 0.55
    fly.onAnimate = proc(p: float) =
        let t = interpolate(0.0, 1.0, p)
        let point = calculateBezierPoint(t, s, e, c1, c2)
        firework.position = point

    let play = firework.component(AEComposition).compositionNamed("play")

    v.addAnimation(play)
    firework.reparentTo(v.rootNode)
    play.addLoopProgressHandler 0.20, false, proc() =
        v.addAnimation(fly)

    let trail = newLocalizedNodeWithResource("slots/candy2_slot/boy/precomps/trail_petard.json")
    play.addLoopProgressHandler 0.15, false, proc() =
        firework.findNode("sparks_3").addChild(trail)
        discard firework.findNode("parent_trail_petard").component(VisualModifier)

    play.onComplete do():
        firework.removeFromParent()

proc playBlowingWilds*(v: Candy2SlotView, cb: proc()) =
    if v.spinData.wildIndexes.len > 0:
        v.sound.play("CANDY_BOY_THROW_FIREWORK")
        let blow = v.blowWild(cb)
        blow.addLoopProgressHandler 0.37, false, proc() =
            v.startCandyFirework()
    else:
        cb()


