import nimx.animation
import rod.node
import utils / [ animation_controller, sound_manager, sound, fade_animation ]
import candy2_slot_view, candy2_top, candy2_interior
import shared.gui / [ slot_gui, spin_button_module ]
import shared.window.button_component
import core.slot.base_slot_machine_view
import core.slot.sound_map
import random

proc setupBoy*(v: Candy2SlotView) =
    v.boyController = newAnimationControllerForNode(v.top.boy)
    v.boyController.addIdles(["idle"])

proc boyEnter*(v: Candy2SlotView) =
    let enterAnim = v.boyController.setImmediateAnimation("enter")

    v.boyController.pauseless.add(enterAnim)
    v.startBoyPosX = v.boyController.node.positionX
    enterAnim.addLoopProgressHandler 0.2, true, proc() =
        v.boyController.node.alpha = 1.0

proc boySpin*(v: Candy2SlotView) =
    let rnd = rand(1..3)
    let boyJump = v.boyController.setImmediateAnimation("spin_" & $rnd)

    if rnd == 2:
        boyJump.addLoopProgressHandler 0.2, false, proc() =
            v.sound.play("CANDY_BOY_JUMP_TURNES_LEFT")
    elif rnd == 3:
        v.sound.play("CANDY_BOY_EYES_ROLL")

proc boyNowin*(v: Candy2SlotView): Animation {.discardable.} =
    v.sound.play("CANDY_BOY_DONT_KNOW")
    result = v.boyController.setImmediateAnimation("nowin")

proc boyWin*(v: Candy2SlotView) =
    let winAnim = v.boyController.setImmediateAnimation("win")

    winAnim.addLoopProgressHandler 0.45, false, proc() =
        v.sound.play("CANDY_BOY_YES")

proc boyMultiwin*(v: Candy2SlotView): Animation =
    result = v.boyController.setImmediateAnimation("multiwin")
    result.addLoopProgressHandler 0.2, false, proc() =
        v.sound.play("CANDY_BOY_JUMP")

proc boyToBonus*(v: Candy2SlotView): Animation =
    let startMove = v.boyController.setImmediateAnimation("gotobonus", false)
    var runLoop: Animation

    startMove.addLoopProgressHandler 0.47, false, proc() =
        v.sound.play("CANDY_BOY_BONUS_GAME_WALK_FALL")
    startMove.onComplete do():
        runLoop = v.boyController.setImmediateAnimation("run_loop_start", false)
        runLoop.numberOfLoops = -1
    v.top.move.addLoopProgressHandler 0.42, false, proc() =
        runLoop.cancel()
        v.boyController.setImmediateAnimation("run_loop_end")
    v.top.move.addLoopProgressHandler 0.6, false, proc() =
        v.rootNode.addAnimation(v.shakeParent.shake)

proc boyFromBonus*(v: Candy2SlotView): Animation =
    let posX = v.boyController.node.positionX
    result = newAnimation()

    result.loopDuration = 2.0
    result.numberOfLoops = 1
    result.onAnimate = proc(p: float) =
        v.boyController.node.positionX = interpolate(posX, posX + 1800, p)
    v.boyController.setImmediateAnimation("run_loop_start", false)
    v.rootNode.addAnimation(result)


