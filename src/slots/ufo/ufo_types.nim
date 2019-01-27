import core  / slot / [base_slot_machine_view]
import rod   / [rod_types, node, viewport]
import nimx  / [animation, view, matrixes, types]
import utils / [sound, animation_controller, fade_animation, and_gate]
import tables, json

import ufo_bonus_game
import ufo_anticipation

const
    GENERAL_PREFIX* = "slots/ufo_slot/"
    SOUND_PREFIX* = GENERAL_PREFIX & "ufo_sound/"
    ALL_ELEMENTS_PATH* = GENERAL_PREFIX & "slot/symbols/all_elements.json"
    SYMBOL_SIZE* = Coord(245)
    REEL_Y_OFFSET* = Coord(0)
    SPIN_DELAY* = 0.2
    SYMS_IN_ROTATING* = 25
    NUMBER_OF_LINES* = 10
    UFO_APPEARING_OFFSET* = 400.0
    REEL_APPEARING_OFFSET* = 800.0
    WILDS_POOL_SIZE* = 5
    UFO_GAME_FLOW* = ["GF_SPIN", "GF_WILDS_HIDE", "GF_WILDS_SPAWN", "GF_SHOW_FS_RS_MSG", "GF_SHOW_WIN", "GF_SPECIAL", "GF_BONUS", "GF_LEVELUP", "GF_RESPINS", "GF_FREESPINS", "GF_REPEAT_WIN_LINES", "GF_CLEAN"]
    FS_UFO_ORDER* = [2, 10, 1, 3, 5, 4, 8, 7, 6, 9] # Order to play free spin baground ufo animations.
    BONUS_TRANSITION_ANIM_TIME* = 0.5

type
    Symbols* = enum
        Wild_Red, #0
        Wild_Green,   #1
        Bonus = "cow",      #2
        Pig = "piggie",     #3
        Dog = "dogy",        #4
        Scarecrow = "scarerow",  #5
        Elk = "elk",        #6
        Barrow = "barrow",     #7
        Bone = "bone",       #8
        Wheel = "wheal",      #9
        Hay = "hay",        #10
        Pumpkin = "pumpkin",    #11
        TargetRed = "targetRed",
        TargetBlue = "targetBlue",
        Portal = "portal" # 12,

    CharAnim* {.pure.} = enum
        Intro   = "intro",
        Idle_1  = "idle_1",
        Idle_2  = "idle_2",
        Spin    = "spin",
        AnticipationStart = "anticipation_start",
        AnticipationEnd    = "anticipation_end",
        AnticipationLoop = "anticipation_loop",
        Win             = "win",
        BigWin = "big_win",
        InPortal = "in_portal",
        WildAppear = "wild_appear",
        WildIdle = "wild_idle",
        WildMoveRight = "wild_move_right",
        WildWin = "wild_win",
        WildToPortal = "wild_to_portal"

    AlienAnimStates* {.pure.} = enum
        None,
        Idle,
        Intro,
        SpecialIdle,
        Spin,
        Anticipation,
        Win,
        BigWin,
        InPortal,
        WildAppear,
        WildIdle,
        WildMoveRight,
        WildWin,
        WildToPortal,
        GoWild

    MoveDirection* {.pure.} = enum
            RTL = -1,
            NONE = 0,
            LTR = 1

    BaseAlien* = ref object of RootObj
        #ac*:AnimationController
        curAnimation*: Animation
        curAnimationState*: AlienAnimStates
        node*:Node
        sceneView*: UfoSlotView
        index*:string
        moveDirection*: MoveDirection

    WildSymbolAlien* = ref object of BaseAlien
        wildSymbolId*:Symbols
        curPlaceIndex*:int
        nextPlaceIndex*:int
        isMoving*:bool
        activeArrowAnim*:Animation
        suspended*:bool

    MainAlien* = ref object of BaseAlien
        position*:Vector3
        inWild*:bool
        resourcePath*:string
        wildsParent*: Node
        wildsPool*:seq[WildSymbolAlien]
        activeWilds*:seq[WildSymbolAlien]

    UfoReel* = ref object of RootObj
        ufo*: Node
        reelNode*: Node
        animReelNode*: Node
        anticipationBackNode*: Node
        anticipationFrontNode*: Node
        ufoRayAnim*: Animation

    MeetPortal* = ref object of RootObj
        node*: Node
        animationIdle*:Animation
        idleSoundAcitve*:bool

    UfoEventMessages* = ref object of RootObj
        bigWin*: bool
        hugeWin*: bool
        megaWin*: bool
        respins*: bool
        bonus*: bool
        freespins*: bool
        freespinsResult*: bool
        newFreeSpins*: int
        fiveInARow*:bool
        bonusResult*:bool

    UfoServerData* = tuple
        paytableSeq: seq[seq[int]]
        freespinsAllCount: int
        freespinsAdditionalCount: int
        bonusSpins : int

    UfoSlotView* = ref object of BaseMachineView
        stageAfterBonus*:GameStage
        mainLayer*: Node
        popupHolder*: Node
        ufoReels*: seq[UfoReel]
        reels*: seq[Node]
        animReels*: seq[Node]
        showOnFreespinsNodes*: seq[Node]
        hideOnFreeSpinsNodes*: seq[Node]
        placeholders*: array[ELEMENTS_COUNT, Node]
        placeholdersPositions*: seq[Vector3]
        beams*: array[ELEMENTS_COUNT, Node]
        freeWinLineParts*:seq[Node]
        rotAnims*: seq[Animation]
        reelsBusy*: array[NUMBER_OF_REELS, bool]
        totalWin*: int64
        freeSpinsTotalWin*: int64
        reSpinsTotalWin*: int64
        bonusWin*: int64
        ligthing*: Node
        linesCoords*: seq[seq[Vector3]]
        winLinesAnim*:Animation
        spinSound*: Sound
        beamAnimChainDelay*: float

        ufoFSAnims*:seq[Animation]
        nextFsUfoAnimIndex*: int
        fsBgAnimationActive*: bool
        activeFsUfoShootAnimations*: seq[string]

        barnFSAnim*: Node
        portals*:seq[MeetPortal]

        alienLeft*: MainAlien
        alienRight*: MainAlien

        symbolsAC*:array[ELEMENTS_COUNT, Table[Symbols, AnimationController]]

        bonusGame*: UfoBonusGame
        fadeAnim*: FadeAnimation
        elementHighlightsAnims*: seq[Animation]
        elementSmokeHighlights*: seq[Node]
        bonusElementSmokeHighlights*: seq[Node]
        winLineNumbers*: seq[Node]
        isWildsMoving*: bool
        isNewWildsAdded*: bool
        isForceStop*:bool
        elementHighlights*: seq[Node]
        winLineNumbersParent*: Node
        responseRecieved*: bool
        anticipator*: Anticipator
        repeatWinLineAnims*: proc()
        highlightReelSymbols*: seq[seq[int]]
        havePotential*: bool
        haveBonusPotential*: bool
        prevFreespinCount*: int

        messages*: UfoEventMessages
        allReelsAnimationsStarted*: bool
        wp*: JsonNode
        isWildsPortIn*: bool
        isWildsPortOut*: bool
        sd*: UfoServerData
        meetIndex*:int
        reelAnimAg*: AndGate

