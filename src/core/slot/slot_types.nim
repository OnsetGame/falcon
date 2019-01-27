#[ SERVER ]#
import falconserver / slot / [ machine_base_types ]
import falconserver.map.building.builditem
import shafa / slot / slot_data_types
# # import falconserver.common.game_balance

export machine_base_types, builditem

# #[ NIMX ]#
# import nimx / [ matrixes, types, animation, notification_center ]
# export matrixes, types, animation, notification_center

# #[ ROD ]#
# import rod / [ node, component ]
# import rod / component / [ camera, text_component ]

# #[ FALCON ]#
# import shared / [game_scene]
# import shared / gui / [ gui_pack, gui_module_types, slot_gui, quests_progress_panel_module, tournaments_progress_panel_module, total_bet_panel_module,
#     win_panel_module, autospins_switcher_module, player_info_module, spin_button_module, menu_button_module, side_timer_panel]

# export game_scene, gui_module_types, slot_gui, quests_progress_panel_module, tournaments_progress_panel_module, total_bet_panel_module,
#     win_panel_module, autospins_switcher_module, player_info_module, spin_button_module, menu_button_module, side_timer_panel

import shared / cheats_view

import json

const NUMBER_OF_REELS* = 5
const NUMBER_OF_ROWS* = 3
const ELEMENTS_COUNT* = 15
const SERVER_RESPONSE_TIMEOUT* = 8.0 # If the server does not reply within this value, the game is likely to exit.

type GameStage* {.pure.}  = enum
    Spin,
    FreeSpin,
    Respin,
    Bonus

type SpinButtonState* = enum
    Spin
    Blocked,
    Stop,
    ForcedStop,
    StopAnim

type ReelsAnimMode* = enum
    Short,
    Long

type WinConditionState* {.pure.} = enum
    Bonus,
    Scatter,
    Line,
    NoWin

type WinType* {.pure.} = enum
    Simple,
    FiveInARow,
    Big,
    Huge,
    Mega,
    Jackpot

type BigWinType* {.pure.} = enum
    Big,
    Huge,
    Mega

type PaidLine* = ref object of RootObj
    index*: int
    winningLine*: WinningLine

type RotationAnimSettings* = tuple[time: float, boosted: bool, highlight: seq[int]]
type BonusScatterReels* = tuple[bonusReels: seq[int], scatterReels: seq[int]]

proc parsePaidLines*(jn: JsonNode): seq[PaidLine]=
    result = @[]
    for item in jn.items:
        let line = PaidLine.new()
        line.winningLine.numberOfWinningSymbols = item["symbols"].getInt()
        line.winningLine.payout = item["payout"].getBiggestInt()
        line.index = item["index"].getInt()
        result.add(line)

proc indexToPlace*(index: int): tuple[x: int, y: int] =
    result.y = index div NUMBER_OF_REELS
    result.x = index mod NUMBER_OF_REELS

proc reelToIndexes*(reel: int): seq[int] =
    result = @[]
    for i in countup(reel, ELEMENTS_COUNT - 1, NUMBER_OF_REELS):
        result.add(i)


type ModedBaseMachineView* = ref object of GameSceneWithCheats
    mode*: SlotModeKind
