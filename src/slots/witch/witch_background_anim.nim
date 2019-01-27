import nimx.animation
import rod.node
import rod.viewport
import witch_slot_view
import core.slot.base_slot_machine_view
import utils.pause
import random

proc startBackgroundIdleAnimations*(v: WitchSlotView) =
    let leaffallAnim = v.mainScene.findNode("leaffall").animationNamed("play")
    let interval = leaffallAnim.loopDuration + 2.0
    let fogSecondPlan = v.mainScene.findNode("fog_second_plan")
    let fogBackground = v.mainScene.findNode("fog_bg_plan")
    let secondPlanMiddleAnim = v.mainScene.findNode("second_middle_plan_animation").animationNamed("play")
    let middlePlan = v.mainScene.findNode("middle_plan_animation")
    let middlePlanAnim = middlePlan.animationNamed("play")
    let smokeMiddlePlan = middlePlan.findNode("smoke_middle_plan")
    let leafTimer = v.setInterval(interval, proc() =
        v.addAnimation(leaffallAnim)
    )

    secondPlanMiddleAnim.numberOfLoops = -1
    v.addAnimation(secondPlanMiddleAnim)
    v.backgroundIdleAnims.add(secondPlanMiddleAnim)

    middlePlanAnim.numberOfLoops = -1
    v.addAnimation(middlePlanAnim)
    v.backgroundIdleAnims.add(middlePlanAnim)

    v.backgroundIdleTimers.add(leafTimer)
    for i in 1..5:
        let anim = fogSecondPlan.findNode("smk_" & $i).animationNamed("play")
        anim.numberOfLoops = -1
        v.addAnimation(anim)
        v.backgroundIdleAnims.add(anim)
    for i in 1..16:
        let anim = fogBackground.findNode("smk_" & $i).animationNamed("play")
        anim.numberOfLoops = -1
        v.addAnimation(anim)
        v.backgroundIdleAnims.add(anim)
    for i in 1..9:
        let anim = smokeMiddlePlan.findNode("smk_" & $i).animationNamed("play")
        anim.numberOfLoops = -1
        v.addAnimation(anim)
        v.backgroundIdleAnims.add(anim)

proc clearBackgroundIdleAnimations*(v: WitchSlotView) =
    for t in v.backgroundIdleTimers:
        v.pauseManager.clear(t)
    for anim in v.backgroundIdleAnims:
        anim.cancel()
    v.backgroundIdleTimers.setLen(0)
    v.backgroundIdleAnims.setLen(0)
