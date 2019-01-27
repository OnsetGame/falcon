import utils.sound_manager
import core.slot.base_slot_machine_view
import anim_helpers
import tables
import utils.sound
import random

const GENERAL_PREFIX = "slots/mermaid_slot/"
const SOUND_PATH_PREFIX = GENERAL_PREFIX & "sound/"

type MusicType* {.pure.} = enum
    Main,
    Bonus,
    Freespins


var prevMusicTupe* = MusicType.Main

proc playBackgroundMusic*(v: BaseMachineView, m: MusicType) =
    let sm = v.soundManager
    case m
    of MusicType.Main:
        sm.sendEvent("GAME_BACKGROUND_MUSIC")
        sm.sendEvent("GAME_BACKGROUND_AMBIENCE")
    of MusicType.Freespins:
        sm.sendEvent("FREE_SPINS_MUSIC")
        sm.sendEvent("FREE_SPINS_AMBIENCE")
    of MusicType.Bonus:
        sm.sendEvent("BONUS_GAME_MUSIC")
        sm.sendEvent("BONUS_GAME_AMBIENCE")

proc initSounds*(v: BaseMachineView) =
    v.soundManager = newSoundManager(v)
    v.soundManager.loadEvents(SOUND_PATH_PREFIX & "mermaid", "common/sounds/common")
    v.playBackgroundMusic(MusicType.Main)

proc playBonusOpenGoldChest*(v: BaseMachineView) =
    v.soundManager.sendEvent("BONUS_OPEN_GOLD_CHEST_SFX")

# proc playSpinButton*(v: BaseMachineView) =
#     v.soundManager.sendEvent("SPIN_BUTTON_MERMAID_SFX")

proc playReelStop*(v: BaseMachineView) =
    v.soundManager.sendEvent("REEL_STOP_SFX")

proc playScatterAppear*(v: BaseMachineView) =
    v.soundManager.sendEvent("SCATTER_APPEAR_SFX")

proc playBonusAppear*(v: BaseMachineView) =
    v.soundManager.sendEvent("BONUS_APPEAR_SFX")

proc playWildAppear*(v: BaseMachineView) =
    v.soundManager.sendEvent("WILD_APPEAR_SFX")

proc playAnticipationSound*(v: BaseMachineView, duration: float32) =
    let s = v.soundManager.sendSfxEvent("ANTICIPATION_SOUND_SFX")
    v.wait(duration) do():
        s.trySetLooping(false)
        s.stop()

proc playBonusWin*(v: BaseMachineView) =
    v.soundManager.sendEvent("BONUS_WIN_SFX")

proc playFreeSpinWin*(v: BaseMachineView) =
    v.soundManager.sendEvent("FREE_SPIN_WIN_SFX")

proc playWildWin*(v: BaseMachineView) =
    v.soundManager.sendEvent("WILD_WIN_SFX")

proc playBonusStartScreen*(v: BaseMachineView) =
    v.soundManager.sendEvent("BONUS_START_SCREEN_SFX")

proc playBonusResultScreen*(v: BaseMachineView) =
    v.soundManager.sendEvent("BONUS_RESULT_SCREEN_SFX")

proc playFreeSpinsStartScreen*(v: BaseMachineView) =
    v.soundManager.sendEvent("FREE_SPINS_START_SCREEN_SFX")

proc playFreeSpinsResultScreen*(v: BaseMachineView) =
    v.soundManager.sendEvent("FREE_SPINS_RESULT_SCREEN_SFX")

proc playRegularWinSound*(v: BaseMachineView) =
    let num = rand(2)
    v.soundManager.sendEvent("REGULAR_WIN_SOUND_" & $num & "_SFX")

proc playFreeSpinsWin*(v: BaseMachineView) =
    v.soundManager.sendEvent("FREE_SPINS_WIN_SFX")

proc playWinHighSymbolStar*(v: BaseMachineView) =
    v.soundManager.sendEvent("WIN_HIGH_SYMBOL_STAR_SFX")

proc playWinHighSymbolFish*(v: BaseMachineView) =
    v.soundManager.sendEvent("WIN_HIGH_SYMBOL_FISH_SFX")

proc playWinHighSymbolTurtle*(v: BaseMachineView) =
    v.soundManager.sendEvent("WIN_HIGH_SYMBOL_TURTLE_SFX")

proc playWinHighSymbolSeahorse*(v: BaseMachineView) =
    v.soundManager.sendEvent("WIN_HIGH_SYMBOL_SEAHORSE_SFX")

proc playWinHighSymbolDolphin*(v: BaseMachineView) =
    v.soundManager.sendEvent("WIN_HIGH_SYMBOL_DOLPHIN_SFX")

proc playBigWin*(v: BaseMachineView): Sound =
    result = v.soundManager.sendSfxEvent("BIG_WIN_SFX")

proc playHugeWin*(v: BaseMachineView): Sound =
    result = v.soundManager.sendSfxEvent("HUGE_WIN_SFX")

proc playMegaWin*(v: BaseMachineView): Sound =
    result = v.soundManager.sendSfxEvent("MEGA_WIN_SFX")

proc playMermaidHappy*(v: BaseMachineView) =
    v.soundManager.sendEvent("MERMAID_HAPPY_SFX")

proc playMermaidSwim*(v: BaseMachineView) =
    v.soundManager.sendEvent("MERMAID_SWIM_SFX")

proc playMermaidAnticipation*(v: BaseMachineView) =
    v.soundManager.sendEvent("MERMAID_ANTICIPATION_SFX")

proc playPaytableOpen*(v: BaseMachineView) =
    v.soundManager.sendEvent("PAYTABLE_OPEN_SFX")

proc playPaytableClose*(v: BaseMachineView) =
    v.soundManager.sendEvent("PAYTABLE_CLOSE_SFX")

proc playPaytableNavigate*(v: BaseMachineView) =
    v.soundManager.sendEvent("PAYTABLE_NAVIGATE_SFX")

proc playPaytablePaylines*(v: BaseMachineView) =
    v.soundManager.sendEvent("PAYTABLE_PAYLINES_SFX")

proc playPaytablePrince*(v: BaseMachineView) =
    v.soundManager.sendEvent("PAYTABLE_PRINCE_SFX")

proc playPaytable2*(v: BaseMachineView) =
    v.soundManager.sendEvent("PAYTABLE_2_SFX")

proc playPaytable3*(v: BaseMachineView) =
    v.soundManager.sendEvent("PAYTABLE_3_SFX")

proc playSpin*(v: BaseMachineView) =
    let rand_index = rand(1 .. 3)
    v.soundManager.sendEvent("SPIN_SOUND_" & $rand_index)

proc playOnAnticipationEnd*(v: BaseMachineView) =
    v.soundManager.sendEvent("ON_ANTICIPATION_END_SFX")

proc playFiveInARow*(v: BaseMachineView) =
    v.soundManager.sendEvent("FIVE_IN_A_ROW_SFX")

proc playCountupSFX*(v: BaseMachineView): Sound =
    result = v.soundManager.sendSfxEvent("MERMAID_COUNTUP_SFX")

proc playMermaidFrame*(v: BaseMachineView) =
    v.soundManager.sendEvent("MERMAID_FRAME_SFX")