import rod.node
import rod.viewport
import nimx.animation
import witch_slot_view
import utils.fade_animation
import utils.sound_manager
import shared.game_flow

proc startFiveInARow*(v: WitchSlotView): Animation {.discardable.} =
    let comp = newNodeWithResource("slots/witch_slot/special_win/precomps/5_of_a_kind.json")
    result = comp.animationNamed("in")

    v.soundManager.sendEvent("5_IN_ROW")
    v.initialFade.changeFadeAnimMode(0.4, 0.3)
    v.specialWinParent.addChild(comp)
    v.addAnimation(result)
    result.addLoopProgressHandler 0.15, false, proc() =
        v.addAnimation(comp.findNode("scene_glow").animationNamed("play"))
    result.onComplete do():
        v.initialFade.changeFadeAnimMode(0.0, 0.5)
        v.specialWinParent.removeAllChildren()
        v.gameFlow.nextEvent()
