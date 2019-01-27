import rod.node
import rod.viewport
import nimx.animation
import witch_slot_view
import witch_pot_anim
import utils.fade_animation
import core.slot.base_slot_machine_view
import utils.sound_manager
import witch_bonus

proc startBonusIntro*(v: WitchSlotView) =
    let intro = newNodeWithResource("slots/witch_slot/special_win/precomps/bonus_game_main.json")
    let anim = intro.animationNamed("play")

    v.prepareGUItoBonus(true)
    v.initialFade.changeFadeAnimMode(1.0, 0.3)
    v.specialWinParent.addChild(intro)
    v.addAnimation(anim)
    v.addAnimation(intro.findNode("stones_1").animationNamed("play"))
    v.addAnimation(intro.findNode("stones_2").animationNamed("play"))
    v.soundManager.sendEvent("BONUS_GAME_ANNOUNCEMENT")
    anim.onComplete do():
        v.turnPurples("00000")
        v.initialFade.changeFadeAnimMode(0.0, 0.5)
        v.restoreAfterBonus()
        v.createBonusScene()
        v.specialWinParent.removeAllChildren()