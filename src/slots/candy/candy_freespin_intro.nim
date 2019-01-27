import nimx.window
import nimx.animation

import rod.node
import rod.viewport
import rod.component
import rod.component.particle_system
import core.slot.base_slot_machine_view
import shared.gui.spin_button_module

import utils.fade_animation

proc startCandyIntroAnim*(v: BaseMachineView, parent: Node, isBonus: bool, onDestroy: proc() = nil) =
    let anchor = newNode("freeSpinsAnchor")
    let main = newLocalizedNodeWithResource("slots/candy_slot/free_spin_intro/free_spins.json")
    let shadow = newLocalizedNodeWithResource("slots/candy_slot/free_spin_intro/precomps/shadow.json")
    let shadowLines = shadow.findNode("free_spins_lines")
    let lines = main.findNode("free_spins_lines")
    let animLines = lines.animationNamed("play")
    let animShadowLines = shadowLines.animationNamed("play")
    let bonus = main.findNode("bonus_game_intro")
    let freeSpins = main.findNode("free_spin_intro")
    let animBonus = bonus.animationNamed("play")
    let animFreeSpins = freeSpins.animationNamed("play")

    parent.addChild(anchor)

    let particleDonuts = newLocalizedNodeWithResource("slots/candy_slot/particles/win_particles_donuts.json")

    let fade = addFadeSolidAnim(v, anchor, blackColor(), v.viewportSize, 0.0, 0.5, 1.0)
    anchor.addChild(shadow)
    anchor.addChild(main)
    shadowLines.addChild(particleDonuts)
    let childrenDonuts = particleDonuts.children
    for c in childrenDonuts:
        let emitter = c.component(ParticleSystem)
        emitter.start()
    parent.sceneView().addAnimation(animLines)
    parent.sceneView().addAnimation(animShadowLines)

    if isBonus:
        parent.sceneView().addAnimation(animBonus)
    else:
        parent.sceneView().addAnimation(animFreeSpins)

    animLines.addLoopProgressHandler 0.8, false, proc() =
        fade.changeFadeAnimMode(0, 0.5)
        for c in childrenDonuts:
            let emitter = c.component(ParticleSystem)
            emitter.stop()
        let anim = newAnimation()
        anim.loopDuration = 0.5
        anim.numberOfLoops = 1
        anim.onAnimate = proc(p: float) =
            for c in particleDonuts.children:
                c.alpha = interpolate(1.0, 0.0, p)
        parent.sceneView().addAnimation(anim)

    animLines.addLoopProgressHandler 1.0, true, proc() =
        anchor.removeFromParent()
        if not onDestroy.isNil:
            onDestroy()

proc startCandyFreeSpinIntroAnim*(v: BaseMachineView, parent: Node, freeSpinsCount: int, onDestroy: proc() = nil) =
    if freeSpinsCount == 0:
        v.slotGUI.spinButtonModule.startFreespins(15)
    else:
        v.slotGUI.spinButtonModule.startFreespins(freeSpinsCount)
    v.startCandyIntroAnim(parent, false, onDestroy)

proc startCandyBonusIntroAnim*(v: BaseMachineView, parent: Node, onDestroy: proc() = nil) =
    v.startCandyIntroAnim(parent, true, onDestroy)
