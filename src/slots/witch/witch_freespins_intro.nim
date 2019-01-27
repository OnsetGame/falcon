import rod.node
import rod.viewport
import nimx.animation
import witch_slot_view
import witch_sound
import utils.fade_animation
import utils.sound_manager
import shared.game_flow

proc startFreespinsIntro*(v: WitchSlotView) =
    let title = newNodeWithResource("slots/witch_slot/special_win/precomps/free_spins_title.json")
    let rune = newNodeWithResource("slots/witch_slot/special_win/precomps/rune_2_scatter.json")
    let effects = newNodeWithResource("slots/witch_slot/special_win/precomps/scene_effects.json")
    let glow = newNodeWithResource("slots/witch_slot/special_win/precomps/scene_glow.json")
    let caustics = rune.findNode("caustics_rune")
    let titleAnimIn = title.animationNamed("in")
    let titleAnimOut = title.animationNamed("out")
    let causticsAnim = caustics.animationNamed("play")
    let runeIn = rune.animationNamed("in")
    let runeOut = rune.animationNamed("out")
    let effectsIn = effects.animationNamed("in")
    let effectsOut = effects.animationNamed("out")
    let glowAnim = glow.animationNamed("play")

    v.specialWinParent.addChild(rune)
    v.specialWinParent.addChild(title)
    v.specialWinParent.addChild(effects)
    v.specialWinParent.addChild(glow)

    causticsAnim.numberOfLoops = -1
    v.initialFade.changeFadeAnimMode(0.3, 0.3)
    v.soundManager.sendEvent("FREE_SPINS_ANNOUNCEMENT")
    v.addAnimation(effectsIn)
    effectsIn.addLoopProgressHandler 0.05, true, proc() =
        v.addAnimation(glowAnim)
    effectsIn.addLoopProgressHandler 0.1, true, proc() =
        v.addAnimation(runeIn)
        v.addAnimation(causticsAnim)
    effectsIn.addLoopProgressHandler 0.15, true, proc() =
        v.addAnimation(titleAnimIn)
    runeIn.onComplete do():
        v.addAnimation(runeOut)
    runeOut.onComplete do():
        causticsAnim.cancel()
    titleAnimIn.onComplete do():
        v.addAnimation(titleAnimOut)
    v.playBackgroundMusic(MusicType.Freespins)
    effectsIn.onComplete do():
        v.soundManager.sendEvent("RESULT_SCREEN_OUT")
        v.addAnimation(effectsOut)
        v.initialFade.changeFadeAnimMode(0.0, 0.5)
        effectsOut.onComplete do():
            v.gameFlow.nextEvent()
            v.specialWinParent.removeAllChildren()
