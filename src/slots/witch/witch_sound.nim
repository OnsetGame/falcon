import utils.sound_manager
import witch_slot_view
import sequtils

type MusicType* {.pure.} = enum
    Main,
    Bonus,
    Freespins

proc playBackgroundMusic*(v: WitchSlotView, m: MusicType) =
    case m
    of MusicType.Main:
        v.soundManager.sendEvent("GAME_BACKGROUND_MUSIC")
        v.soundManager.sendEvent("GAME_BACKGROUND_AMBIENCE")
    of MusicType.Freespins:
        v.soundManager.sendEvent("FREE_SPINS_MUSIC")
        v.soundManager.sendEvent("FREE_SPINS_AMBIENCE")
    of MusicType.Bonus:
        v.soundManager.sendEvent("BONUS_GAME_MUSIC")
        v.soundManager.sendEvent("BONUS_GAME_AMBIENCE")

proc ifWinFreespinsSound*(v: WitchSlotView) =
    if v.fsStatus == FreespinStatus.Before:
        v.soundManager.sendEvent("SCATTERS_WIN")
    elif v.lastField.contains(Symbols.Scatter.int8):
        v.soundManager.sendEvent("SCATTERS_APPEARANCE")
