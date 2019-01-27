import typetraits, variant, json
import core / flow / flow
export flow
import nimx / matrixes
import rod / node
import falconserver / map / building / builditem
import shafa / game / [ message_types ]
import core / helpers / reward_helper
import tournaments.tournament

type
    WindowFlowState*            = ref object of BaseFlowState
    LevelUpWindowFlowState*     = ref object of BaseFlowState
    VipLevelUpWindowFlowState*     = ref object of BaseFlowState
        level*: int
    GiveRewardWindowFlowState*  = ref object of BaseFlowState
        boxKind*: RewardWindowBoxKind
        rewards*: seq[Reward]
        isForVip*: bool
    GiveQuestRewardFlowState*  = ref object of BaseFlowState
    CompleteTaskFlowState*      = ref object of BaseFlowState
    ServerMessageFlowState*     = ref object of BaseFlowState
        msg*: Message
    SpecialOfferFlowState*      = ref object of BaseFlowState
        offerBundleID*: string
    OfferFromActionFlowState*   = ref object of BaseFlowState
        offerJson*: JsonNode
    OfferFromTimerFlowState*    = ref object of BaseFlowState
        source*: string

    MaintenanceFlowState*       = ref object of BaseFlowState
    MapQuestUpdateFlowState*    = ref object of BaseFlowState
    TournamentShowFinishFlowState* = ref object of BaseFlowState
    TournamentShowWindowFlowState* = ref object of BaseFlowState
    RateUsFlowState*            = ref object of BaseFlowState
    NewQuestBarFlowState*       = ref object of BaseFlowState
    CollectConfigFlowState*     = ref object of BaseFlowState
    BetConfigFlowState*         = ref object of BaseFlowState
    ExpirienceFlowState*        = ref object of BaseFlowState
    UpdateTaskProgresState*     = ref object of BaseFlowState
    ZoomMapFlowState*           = ref object of BaseFlowState
        targetPos*: Vector3
        onComplete*: proc()

    LoadingFlowState*           = ref object of BaseFlowState
    MapFlowState*               = ref object of BaseFlowState
    SlotFlowState*              = ref object of BaseFlowState
        target*: BuildingId
        currentBet*: int
        tournament*: Tournament

    SpinFlowState*              = ref object of BaseFlowState
    SlotNextEventFlowState*     = ref object of BaseFlowState

    TutorialFlowState* = ref object of BaseFlowState
        target*: Node
        action*: proc()

method getType*(state: WindowFlowState): FlowStateType = WindowFS
method getType*(state: LevelUpWindowFlowState): FlowStateType = WindowFS
method getType*(state: VipLevelUpWindowFlowState): FlowStateType = WindowFS
method getType*(state: GiveRewardWindowFlowState): FlowStateType = RewardsFS
method getType*(state: GiveQuestRewardFlowState): FlowStateType = RewardsFS
method getType*(state: CompleteTaskFlowState): FlowStateType = WindowFS
method getType*(state: ServerMessageFlowState): FlowStateType = WindowFS
method getType*(state: SpecialOfferFlowState): FlowStateType = WindowFS
method getType*(state: OfferFromActionFlowState): FlowStateType = WindowFS
method getType*(state: OfferFromTimerFlowState): FlowStateType = WindowFS

method getType*(state: MaintenanceFlowState): FlowStateType = WindowFS
method getType*(state: MapQuestUpdateFlowState): FlowStateType = MapQuestFS
method getType*(state: TournamentShowFinishFlowState): FlowStateType = TournamentFinishFS
method getType*(state: TournamentShowWindowFlowState): FlowStateType = TournamentWindowFS
method getType*(state: RateUsFlowState): FlowStateType = WindowFS
method getType*(state: NewQuestBarFlowState): FlowStateType = MapMessageBarFS
method getType*(state: CollectConfigFlowState): FlowStateType = ConfigFS
method getType*(state: BetConfigFlowState): FlowStateType = ConfigFS
method getType*(state: ExpirienceFlowState): FlowStateType = ConfigFS
method getType*(state: UpdateTaskProgresState): FlowStateType = UpdateSlotTaskProgresFS
method getType*(state: ZoomMapFlowState): FlowStateType = ZoomMapFS

method getType*(state: LoadingFlowState): FlowStateType = LoadingFS
method getType*(state: MapFlowState): FlowStateType = MapFS
method getType*(state: SlotFlowState): FlowStateType = SlotFS

method getType*(state: SpinFlowState): FlowStateType = SpinFS
method getType*(state: SlotNextEventFlowState): FlowStateType = SpinFS


method getFilters*(state: WindowFlowState): seq[FlowStateType] = return @[NarrativeFS, UpdateSlotTaskProgresFS]
method getFilters*(state: LevelUpWindowFlowState): seq[FlowStateType] = return @[RewardsFS]
method getFilters*(state: VipLevelUpWindowFlowState): seq[FlowStateType] = return @[RewardsFS]
method getFilters*(state: GiveRewardWindowFlowState): seq[FlowStateType] = return @[]
method getFilters*(state: GiveQuestRewardFlowState): seq[FlowStateType] = return @[RewardsFS]
method getFilters*(state: CompleteTaskFlowState): seq[FlowStateType] = return @[]
method getFilters*(state: ServerMessageFlowState): seq[FlowStateType] = return @[RewardsFS]
method getFilters*(state: SpecialOfferFlowState): seq[FlowStateType] = return @[]
method getFilters*(state: OfferFromActionFlowState): seq[FlowStateType] = return @[]

method getFilters*(state: MaintenanceFlowState): seq[FlowStateType] = return @[]
method getFilters*(state: MapQuestUpdateFlowState): seq[FlowStateType] = return @[]
method getFilters*(state: TournamentShowFinishFlowState): seq[FlowStateType] = return @[]
method getFilters*(state: TournamentShowWindowFlowState): seq[FlowStateType] = return @[]
method getFilters*(state: RateUsFlowState): seq[FlowStateType] = return @[]
method getFilters*(state: NewQuestBarFlowState): seq[FlowStateType] = return @[]
method getFilters*(state: CollectConfigFlowState): seq[FlowStateType] = return @[]
method getFilters*(state: BetConfigFlowState): seq[FlowStateType] = return @[]
method getFilters*(state: ExpirienceFlowState): seq[FlowStateType] = return @[]
method getFilters*(state: ZoomMapFlowState): seq[FlowStateType] = return @[ZoomMapFS]

method getFilters*(state: LoadingFlowState): seq[FlowStateType] = return @[]
method getFilters*(state: MapFlowState): seq[FlowStateType] = return @[WindowFS, TutorialFS, RewardsFS, MapQuestFS, TournamentWindowFS, MapMessageBarFS, ConfigFS, ZoomMapFS, NarrativeFS]
method getFilters*(state: SlotFlowState): seq[FlowStateType] = return @[WindowFS, TutorialFS, RewardsFS, SlotRoundFS, SpinFS, TournamentFinishFS, ConfigFS, UpdateGUIFS, NarrativeFS, UpdateSlotTaskProgresFS]

method getFilters*(state: SpinFlowState): seq[FlowStateType] = return @[]
method getFilters*(state: SlotNextEventFlowState): seq[FlowStateType] = return @[]


type OpenFreeRoundsResultWindowFlowState* = ref object of BaseFlowState
    zone*: Variant

method appearsOn*(state: OpenFreeRoundsResultWindowFlowState, current: BaseFlowState): bool = current.name == "SlotFlowState"
