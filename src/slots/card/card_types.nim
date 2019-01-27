import nimx.animation
import core.slot.state_slot_types
import core.flow.flow_macro

type AnticipationPosition* {.pure.} = enum
    None = 0,
    Forth = 3,
    Fifth = 4,
    Both = 7

type
    WinLineType* = enum
        #                   #-----          #                   #-   -          #  -
        #-----              #               #                   # - -           # - -
        #                   #               #-----              #  -            #-   -
        MiddleLine,         TopLine,        BottomLine,         VLine,          CVLine,

        # -                 #   -           #--                 #   --          #- - -
        #- - -              #- - -          #  -                #  -            # - -
        #   -               # -             #   --              #--             #
        RhytmLine,          CRhytmLine,     UpDownLine,         DownUpLine,     WSLine,

        #                   # ---           #                   #-   -          #
        # - -               #-   -          #-   -              # ---           # ---
        #- - -              #               # ---               #               #-   -
        MSLine,             UpArchedLine,   DownConcaveLine,    UpConcaveLine,  DownArchedLine,

        #  -                #               #- - -              # - -           # - -
        #-- --              #-- --          #                   #               #  -
        #                   #  -            # - -               #- - -          #-   -
        UpHillLine,         DownHillLine,   BWLine,             BMLine,         SMLine

    WinLineDot* = tuple
        beams: int

    WinLine* = tuple
        #lineCoords: seq[WinLineDot]
        animComposite: Animation

    WinLinesArray* = ref object of RootObj
        lines*: array[0..19, WinLine] #coordinates of line spots

    CardPaytableServerData* = tuple
        paytableSeq: seq[seq[int]]

type SunMultiplierState* = ref object of AbstractSlotState

type SunBonusState* = ref object of AbstractSlotState
type TransitionState* = ref object of AbstractSlotState
type FreespinsModeSelection* = ref object of AbstractSlotState
type FreespinsMode* = ref object of AbstractSlotState

SunMultiplierState.dummySlotAwake
SunBonusState.dummySlotAwake
TransitionState.dummySlotAwake
FreespinsModeSelection.dummySlotAwake
FreespinsMode.dummySlotAwake

method appearsOn*(s: SunMultiplierState, o: AbstractSlotState): bool =
    return o.name in ["StartShowAllWinningLines", "NoWinState"]

method appearsOn*(s: SunBonusState, o: AbstractSlotState): bool =
    return o.name == "FreespinEnterState"

method appearsOn*(s: TransitionState, o: AbstractSlotState): bool =
    return o.name == "SunBonusState"

method appearsOn*(s: FreespinsModeSelection, o: AbstractSlotState): bool =
    return o.name == "TransitionState"

method appearsOn*(s: FreespinsMode, o: AbstractSlotState): bool =
    return o.name in ["FreespinsModeSelection", "TransitionState"]

type Sun* {.pure.} = enum
    Idle = 0
    X2 = 2
    X5 = 5
    X10 = 10
    Bonus
