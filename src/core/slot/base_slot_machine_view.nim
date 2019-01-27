import rod / [ node, viewport, rod_types, component, quaternion ]
import rod / component / [ camera, ui_component, text_component, particle_emitter ]
import nimx / [ view, button, font, context, view_event_handling, animation, gesture_detector, notification_center ]
import utils / [ sound, sound_manager, pause, helpers,
                game_state, timesync ]

import falconserver / slot / [ machine_base_types ]

import shared / [ localization_manager, director, chips_animation, cheats_view, tutorial,
     game_scene, game_flow, user, fb_share_button, alerts, paytable_general, deep_links ]

import shared / window / [ window_manager, special_offer_window, button_component, window_component, new_task_event ]
import windows / store / store_window

import shared / gui / [ gui_pack, gui_module_types, slot_gui, total_bet_panel_module,
                        win_panel_module, autospins_switcher_module, player_info_module,
                        spin_button_module, menu_button_module, side_timer_panel ]
import shared / gui / slot_progress_modules / [ slot_progress_module, quests_progress_panel_module, tournaments_progress_panel_module, free_rounds_progress_panel_module ]

import core.net.server

import
    falconserver.auth.profile_types, falconserver.map.building.builditem, falconserver.common.game_balance, falconserver.purchases.product_bundles_shared,
    #
    shared.message_box,
    #
    shafa.slot.slot_data_types,
    #
    shared.win_popup,
    #
    math, json, strutils, logging, algorithm, tables, times,
    #
    core.slot.slot_types
import slots / [bet_config, slot_machine_registry]
import quest / [ quests, quest_helpers, quests_actions ]
import tournaments / [ tournament, tournament_info_view ]

import core / flow / flow_state_types
import platformspecific.purchase_helper
import utils / falcon_editors
import core / features / [booster_feature, slot_feature]
import core / zone
import map / collect_resources

export game_flow
export game_scene
export BuildingId
export SlotGUI
export helpers
export slot_types
export paytable_general

const BONUS_ID = 2
const SCATTER_ID = 1

type BaseMachineView* = ref object of ModedBaseMachineView
    winDialogWindow*: WinDialogWindow
    currentBet: int
    betConfig: BetConfig
    freeSpinsLeft*: int
    gLines*: int
    lines*: seq[Line]
    paidLines*: seq[PaidLine]
    actionButtonState*: SpinButtonState
    slotMachine*: SlotMachine
    lastField*: seq[int8]
    animSettings*:seq[RotationAnimSettings]
    onComplete*: proc()
    tapGesture*: TapGestureDetector
    gameFlow*: GameFlow
    slotGUI*: SlotGUI
    data*: JsonNode

    multBig*: int64
    multHuge*: int64
    multMega*: int64
    sessionTotalWin*: int64
    sessionTotalSpend*: int64
    slotSpins*: int
    slotBonuses*: int
    freespinsTriggered*: int
    slotSpinsOnAutospinStart: int
    lastActionSpins*: int

    spinRotate*: Animation
    balanceCountUpAnim: Animation
    canAutospinClick*: bool
    paytable*: string

    tournament: Tournament
    tournamentInfoView2: TournamentInfoView2
    tournamentCheatsView: View
    reasonOfExit: string
    hasResponse*: bool
    stage: GameStage
    freespinsStage*: string

    # TODO: Refactoring. Hotfix. Have to use mode instead of freeRounds flag
    freeRounds*: bool

method onGameStageChanged*(v: BaseMachineView, prevStage: GameStage) {.base.}

proc stage*(v: BaseMachineView): GameStage =
    v.stage

proc `stage=`*(v: BaseMachineView, newStage: GameStage) =
    if v.stage != newStage:
        let prevStage = v.stage
        v.stage = newStage
        v.onGameStageChanged(prevStage)

proc getTournPartId*(v: BaseMachineView): string =
    if not v.tournament.isNil:
        result = v.tournament.participationId

proc getRTP*(v: BaseMachineView): float64 =
    if v.sessionTotalSpend == 0:
        return v.sessionTotalWin.float64
    result = round(v.sessionTotalWin.float64 / v.sessionTotalSpend.float64, 2) #todo: check this round

proc getTotalRTP*(v: BaseMachineView): float =
    var win: int64
    var spent: int64

proc getPaytableData*(res: JsonNode): seq[seq[int]] =
    if res.hasKey("paytable"):
        var paytable = res["paytable"]
        let table = paytable["table"]

        result = @[]
        for i in countup(0, table.len-1):
            let row = table[i]
            var rowSeq: seq[int] = @[]
            for el in row:
                rowSeq.add(el.getInt())
            result.add(rowSeq)

proc prepareGUIForPaytable*(v: BaseMachineView, enable: bool) =
    let gui = v.slotGUI
    let fade = gui.rootNode.findNode("lower_black_bg")

    fade.enabled = enable
    gui.spinButtonModule.setVisible(enable)
    gui.autospinsSwitcherModule.setVisible(enable)
    gui.progressPanel.setVisible(enable)
    gui.totalBetPanelModule.setVisible(enable)
    gui.winPanelModule.setVisible(enable)
    gui.playerInfo.setVisible(enable)
    gui.moneyPanelModule.setVisible(enable)
    gui.menuButton.setVisible(enable)
    gui.collectButton.setVisible(enable)
    gui.sideTimePanel.setVisible(enable)

proc closeActiveWindow*(v: BaseMachineView) =
    sharedWindowManager().hideAll()

proc prepareGUItoBonus*(v: BaseMachineView, to: bool) =
    let fade = v.slotGUI.rootNode.findNode("lower_black_bg")

    fade.enabled = not to
    if to:
        v.closeActiveWindow()
    v.slotGUI.spinButtonModule.setVisible(not to)
    v.slotGUI.totalBetPanelModule.setVisible(not to)
    v.slotGUI.autospinsSwitcherModule.setVisible(not to)
    v.slotGUI.winPanelModule.setVisible(not to)
    v.slotGUI.collectButton.setVisible(not to)
    v.slotGUI.menuButton.setVisible(not to)
    v.slotGUI.moneyPanelModule.setVisible(not to)
    v.slotGUI.playerInfo.setVisible(not to)
    v.slotGUI.sideTimePanel.setVisible(not to)
    v.slotGUI.progressPanel.setVisible(not to)

method showPaytable*(v: BaseMachineView) {.base.} = discard

proc setTournament*(v: BaseMachineView, t: Tournament) =
    v.tournament = t

proc experienceAnimation*(v: BaseMachineView) =
    discard
    # let sbm = v.slotGUI.spinButtonModule
    # let rolAnim = sbm.rootNode.animationNamed("city_points")
    # let cpNode = sbm.rootNode.findNode("citypoints")

    # let cpAnim = cpNode.animationNamed("play")
    # rolAnim.onComplete do():
    #     let cpProfile = newNodeWithResource("common/gui/precomps/profile_citypoint.json")
    #     let cpShine = newNodeWithResource("common/gui/precomps/profile_cp_shine.json")
    #     v.slotGUI.playerInfo.rootNode.addChild(cpProfile)
    #     v.slotGUI.playerInfo.rootNode.addChild(cpShine)
    #     cpProfile.position = newVector3(138.0, 44.0, 0.0)
    #     let anim = cpProfile.animationNamed("play")
    #     v.addAnimation(anim)

    #     anim.onComplete do():
    #         cpProfile.removeFromParent()
    #         cpShine.removeFromParent()

    # rolAnim.addLoopProgressHandler 0.1, false, proc() =
    #     cpNode.alpha = 1.0
    #     v.addAnimation cpAnim

    # cpAnim.onComplete do():
    #     cpNode.alpha = 0.0

    # v.addAnimation(rolAnim)

proc rotateSpinButton*(v: BaseMachineView, sbm: SpinButtonModule) =
    let spinRotate = newAnimation()
    spinRotate.loopDuration = 1.0
    spinRotate.numberOfLoops = 1
    spinRotate.onAnimate = proc(p:float)=
        sbm.arrowParent.rotation = newQuaternionFromEulerXYZ(0.0, 0.0, interpolate(0.0, 360.0, p))
    v.spinRotate = spinRotate
    v.addAnimation(v.spinRotate)

proc totalBet*(v: BaseMachineView): int64

method buildingId*(v: BaseMachineView) : BuildingId {.base.} =
    discard

method spinSound*(v: BaseMachineView): string {.base.} =
    "COMMON_SPIN_CLICK"

method onSpinClick*(v: BaseMachineView) {.base.} =
    v.soundManager.sendEvent(v.spinSound)

    if v.actionButtonState == SpinButtonState.Spin:# and getCurrentState() of SlotFlowState:
        # pushFront(SpinFlowState)

        v.slotGUI.winPanelModule.setNewWin(0)
        if not v.balanceCountUpAnim.isNil:
            v.balanceCountUpAnim.cancel()
        v.rotateSpinButton(v.slotGUI.spinButtonModule)

proc currentBalance*(v: BaseMachineView): int64 =
    currentUser().chips

proc registerTapDetector*(v: BaseMachineView)
proc unregisterTapDetector*(v: BaseMachineView)

proc totalBet*(v: BaseMachineView): int64 =
    if v.betConfig.hardBets > 0:
        result = v.betConfig.serverBet

    elif v.currentBet in 0 ..< v.betConfig.bets.len:
        result = v.betConfig.bets[v.currentBet]

proc countSymbols*(v: BaseMachineView, sym: int): int =
    for i, val in v.lastField:
        if val == sym:
            result.inc()

method removeWinAnimationWindow*(v: BaseMachineView, fast: bool = true): bool {.base, discardable.} =
    if not v.winDialogWindow.isNil:
        if v.winDialogWindow.readyForClose or fast:
            v.winDialogWindow.destroy()
            return true
        else:
            return false
    return true

proc updateTotalBetPanel*(v: BaseMachineView) =

    let fs = v.stage == GameStage.FreeSpin
    let switcher = v.slotGUI.autospinsSwitcherModule

    if v.actionButtonState == SpinButtonState.Spin and v.tournament.isNil and not fs and not v.freeRounds:
        if v.currentBet == v.betConfig.bets.high:
            v.slotGUI.totalBetPanelModule.plusEnabled = false

            if v.betConfig.bets.len > 0:
                v.slotGUI.totalBetPanelModule.minusEnabled = true
            if v.currentBet < currentUser().betLevels.high and v.tournament.isNil:
                v.slotGUI.totalBetPanelModule.showLock(true)
        elif v.currentBet == 0:
            v.slotGUI.totalBetPanelModule.plusEnabled = true
            v.slotGUI.totalBetPanelModule.minusEnabled = false
            v.slotGUI.totalBetPanelModule.showLock(false)
        else:
            v.slotGUI.totalBetPanelModule.plusEnabled = true
            v.slotGUI.totalBetPanelModule.minusEnabled = true
            v.slotGUI.totalBetPanelModule.showLock(false)
    else:
        v.slotGUI.totalBetPanelModule.plusEnabled = false
        v.slotGUI.totalBetPanelModule.minusEnabled = false

proc updateBetInUI(v: BaseMachineView)=
    v.slotGUI.totalBetPanelModule.setBetCount(v.totalBet.int)
    v.updateTotalBetPanel()

method onBetClicked*(v: BaseMachineView) =
    v.removeWinAnimationWindow()
    if v.actionButtonState == SpinButtonState.Spin:

        v.updateBetInUI()
        v.updateTotalBetPanel()

proc betPlus*(v: BaseMachineView) =
    if v.actionButtonState == SpinButtonState.Spin:
        if v.betConfig.hardBets == 0 and v.currentBet < v.betConfig.bets.high:
            let prevBet = v.totalBet()

            inc v.currentBet
            v.updateTotalBetPanel()
            v.soundManager.sendEvent("COMMON_BET_SELECT")
        else:
            v.soundManager.sendEvent("COMMON_BET_LIMIT")
    v.onBetClicked()

proc betMinus*(v: BaseMachineView) =
    if v.actionButtonState == SpinButtonState.Spin:
        if v.betConfig.hardBets == 0 and v.currentBet > 0:
            let prevBet = v.totalBet()

            dec v.currentBet
            v.updateTotalBetPanel()
            v.soundManager.sendEvent("COMMON_BET_SELECT")
        else:
            v.soundManager.sendEvent("COMMON_BET_LIMIT")
    v.onBetClicked()

method onGameStageChanged*(v: BaseMachineView, prevStage: GameStage) {.base.} = discard

proc initQuestTranscations*(v: BaseMachineView)=
    let notif = v.notificationCenter

    notif.addObserver("QuestOpenRewards", v) do(args: Variant):
        let id = args.get(int)
        v.slotGUI.completeQuestById(id)

proc stopAutospin*(v: BaseMachineView, reason: AutospinStopReason) =
    let switcher = v.slotGUI.autospinsSwitcherModule

    if switcher.isOn:
        setController(aNone)
        switcher.switchOff()

proc balanceCountUp(v: BaseMachineView, oldBalance, newBalance: int64): Animation =
    result = newAnimation()

    result.loopDuration = 0.5
    result.numberOfLoops = 1
    result.cancelBehavior = cbJumpToEnd
    result.onAnimate = proc(p: float) =
        let b = interpolate(oldBalance, newBalance, p)
        let curBalance = v.slotGUI.moneyPanelModule.chips

        v.slotGUI.moneyPanelModule.setBalance(curBalance, b, false)
    v.addAnimation(result)


method onSceneAdded*(v: BaseMachineView) {.base.} =
    let state = newFlowState(SlotFlowState)
    state.target = v.buildingId()
    state.currentBet = v.slotGUI.totalBetPanelModule.count
    state.tournament = v.tournament
    pushFront(state)

    v.slotGUI.progressPanel.checkPanel(true)
    sharedServer().checkMessage("slot")

    if v.freeRounds:
        let state = NewTaskFlowState.newFlowState()
        state.quest = generateFreeRoundsQuestFor(v.buildingId)
        pushBack(state)
    else:
        let quests = sharedQuestManager().activeTasks()
        if quests.len() > 0:
            let state = NewTaskFlowState.newFlowState()
            state.quest = quests[0]
            pushBack(state)

            if not isFrameClosed($tsSpinButton):
                tsSpinButton.addTutorialFlowState()
                pushBack(SpinFlowState) # dirty hack. don't touch!!!
                tsTaskProgressPanel.addTutorialFlowState()

    if not v.tournament.isNil:
        let tp = v.slotGui.progressPanel.TournamentsProgressPanelModule
        let parent = newNode("tournament_info_view")
        sharedWindowManager().insertNodeBeforeWindows(parent)

        v.tournamentInfoView2 = newTournamentInfoView2(parent, v.tournament)
        v.slotGui.layoutModule(v.tournamentInfoView2, 0, -540, Relation.MiddleLeft)
        discard v.tournamentInfoView2.update()
        v.setInterval 1, proc() =
            tp.update()
            if v.tournamentInfoView2.update():
                v.slotGUI.autospinsSwitcherModule.switchOff()
        v.tournamentCheatsView = newTournamentCheatsView(v, v.tournamentInfoView2, v.tournament)

        tsTournamentInfoBar.addTutorialFlowState()
        tsTournamentSpin.addTutorialFlowState()

proc getActiveTaskProgress*(v: BaseMachineView): float =
    var activeTaskProgress = 0.0

    for t in sharedQuestManager().activeTasks():
        if t.tasks[0].target.BuildingId == v.buildingId():
            result = t.getProgress()
            break

proc userCanStartSpin*(v: BaseMachineView): bool =
    v.actionButtonState != SpinButtonState.Blocked and
        not sharedWindowManager().hasVisibleWindows()

proc applyBetChanges*(v: BaseMachineView) =
    v.updateBetInUI()


proc applyBetConfig*(v: BaseMachineView, bc: BetConfig)=
    assert(bc.bets.len > 0)
    var initial = v.betConfig.bets.len == 0

    v.betConfig = bc
    v.betConfig.serverBet *= v.lines.len

    if initial or bc.hardBets > 0:
        var bets = bc.bets
        bets.sort do(a, b: int) -> int: cmp(abs(a - v.betConfig.serverBet), abs(b - v.betConfig.serverBet))
        v.currentBet = clamp(bc.bets.find(bets[0]), 0, bc.bets.len)
        v.applyBetChanges()
        v.updateTotalBetPanel()

        v.betConfig.hardBets = 0

proc initControls*(v: BaseMachineView) =
    let gui = v.slotGUI
    let switcher = gui.autospinsSwitcherModule
    gui.spinButtonModule.button.onAction do():
        if gui.spinButtonModule.button.nxButton.value == 1:
            setController(aAutospin)

            v.slotSpinsOnAutospinStart = v.slotSpins
            if v.userCanStartSpin():
                v.onSpinClick()
            switcher.switchOn()

            if v.currentBalance <= v.totalBet():
                v.stopAutospin(AutospinStopReason.NotEnoughChips)
        else:
            if switcher.isOn:
                v.stopAutospin(AutospinStopReason.Player)
            else:
                v.onSpinClick()
    v.updateBetInUI()
    v.slotGUI.winPanelModule.setNewWin(0, false)

    gui.autospinsSwitcherModule.onStateChanged = proc(state: bool) =
        if state:
            gui.spinButtonModule.startAutospins()
        else:
            gui.spinButtonModule.stopAutospins()

    gui.playerInfo.avatar = currentUser().avatar

    v.registerTapDetector()
    let notif = v.notificationCenter

    notif.addObserver("MENU_CLICK_BUTTON", v) do(args: Variant):
        let bttn = args.get(MenuButton)

        case bttn:
            of mbBackToCity:
                v.onComplete()
            of mbPayTable:
                v.showPaytable()
            else:
                discard

    notif.addObserver("CHIPS_PARTICLE_ANIMATION_STARTED", v) do(args: Variant):
        let (oldBalance, newBalance) = args.get(tuple[oldBalance: int64, newBalance: int64])
        v.balanceCountUpAnim = v.balanceCountUp(oldBalance, newBalance)

    notif.addObserver("SharedGuiExperienceEv", v) do(args: Variant):
        v.experienceAnimation()

    notif.addObserver("SET_EXIT_FROM_SLOT_REASON", v) do(args: Variant):
        v.reasonOfExit = args.get(string)

    sharedNotificationCenter().addObserver("DIRECTOR_ON_SCENE_ADD", v) do(args: Variant):
        if args.get(GameScene) == v:
            v.onSceneAdded()

    notif.addObserver("NEED_SHOW_CHIPS_STORE", v) do(args: Variant):
        var activeTaskProgress = v.getActiveTaskProgress()
        showStoreWindow(StoreTabKind.Chips, "user_from_slot", activeTaskProgress)

    notif.addObserver("NEED_SHOW_BUCKS_STORE", v) do(args: Variant):
        var activeTaskProgress = v.getActiveTaskProgress()
        showStoreWindow(StoreTabKind.Bucks, "user_from_slot", activeTaskProgress)

    notif.addObserver("STOP_AUTOSPINS", v) do(args: Variant):
        let reason = args.get(AutospinStopReason)
        v.stopAutospin(reason)

    notif.addObserver("ShowSpecialOfferWindow", v) do(args: Variant):
        let sod = args.get(SpecialOfferData)

        let offerWindow = sharedWindowManager().createWindow(SpecialOfferWindow)
        offerWindow.prepareForBundle(sod)
        offerWindow.source = $v.buildingId
        sharedWindowManager().show(offerWindow)


    notif.addObserver("BetConfigEv", v) do(args: Variant):
        if v.tournament.isNil:
            v.applyBetConfig(args.get(BetConfig))

    notif.addObserver("ShowSpecialOfferTimer", v) do(args: Variant):
        let sod = args.get(SpecialOfferData)
        v.slotGui.getModule(mtSidePanel).SideTimerPanel.addTimer(sod)

    v.initQuestTranscations()
    discard sharedWindowManager()

proc incLastActionSpins*(v: BaseMachineView) =
    if v.lastActionSpins > -1:
        v.lastActionSpins.inc()

proc handleResponseTimeout(v: BaseMachineView) =
    v.prepareForCriticalError()
    error "Response timeout"
    showLostConnectionAlert()

method getLines*(v: BaseMachineView, res: JsonNode) : seq[Line] {.base.} =
    result = @[]
    if res.hasKey($srtLines):
        var line: seq[int16] = @[]
        for item in res[$srtLines].items:
            line.setLen(0)
            for i in item:
                line.add(i.getInt().int16)
            result.add(line)

method restoreState*(v: BaseMachineView, res: JsonNode) {.base.} =
    # Get win lines combinations.
    v.lines = v.getLines(res)

    var bc = parseBetConfig(res)
    v.applyBetConfig(bc)
    v.updateTotalBetPanel()

method sceneID*(v: BaseMachineView): string = $v.buildingId

proc getMode*(v: BaseMachineView): JsonNode =
    let tournPartId = v.getTournPartId()
    if tournPartId.len > 0:
        return %{"kind": %smkTournament.int, "tournPartId": %tournPartId}
    if v.freeRounds:
        return %{"kind": %smkFreeRound.int}
    return %{"kind": %smkDefault.int}

proc requestState(v: BaseMachineView, callback: proc()) {.inline.} =
    sharedServer().getMode($v.buildingId, v.getMode()) do(res: JsonNode):
        info "restoreState: ", res
        v.restoreState(res)
        if not callback.isNil:
            callback()

proc handleTournamentScoreGain*(v: BaseMachineView, resp: JsonNode) =
    let tournScoreTime = resp{"tournScoreTime"}
    if tournScoreTime.isNil:
        info "No proper tournament response from server"
    else:
        for s in resp["stages"]:
            let gain = s{"tournScoreGain"}
            if not gain.isNil:
                v.tournament.addPendingScoreGain(s["stage"].str, gain.getInt(), tournScoreTime.getFloat())

proc handleSpinResponse(v: BaseMachineView, resp: JsonNode) =
    if not v.tournament.isNil:
        v.handleTournamentScoreGain(resp)
    elif "betsConf" in resp:
        var bc = parseBetConfig(resp)
        v.applyBetConfig(bc)

proc sendSpinRequest*(v: BaseMachineView, bet: int64, handler: proc(j: JsonNode)) =
    v.hasResponse = false

    sharedServer().spin(bet div v.gLines, v.gLines, $v.buildingId, v.getMode(), v.data) do(r: JsonNode):
        v.hasResponse = true
        v.handleSpinResponse(r)
        if v.GameScene == currentDirector().currentScene:
            handler(r)

method clickScreen*(v: BaseMachineView) {.base.} =
    raise new(ErrorNotImplemented)

method init*(v: BaseMachineView, r: Rect)  =
    procCall v.GameScene.init(r)
    cleanPendingStates(TutorialFlowState)
    v.lastActionSpins = -1
    v.pauseManager = newPauseManager(v)
    v.canAutospinClick = true

    v.onComplete = proc() =
        directorMoveToMap()

    let chipsIncomeFullPercent = (resourceCapacityProgress(Currency.Chips) * 100).int
    let bucksIncomeFullPercent = (resourceCapacityProgress(Currency.Bucks) * 100).int

proc initGUI(v: BaseMachineView) =
    v.slotGUI = v.rootNode.createSlotGUI(v)

    if not v.tournament.isNil:
        v.slotGUI.progressPanel = createTournamentsProgressPanel(v.slotGUI.rootNode, v.tournament)
    elif v.freeRounds:
        let zone = findZone($v.buildingId())
        let panel = createFreeRoundsProgressPanel(v.slotGUI.rootNode)

        let feature = zone.feature.SlotFeature
        feature.subscribe(v) do():
            let state = FreeRoundsProgressPanelModuleFlowState.newFlowState()
            state.action = proc() =
                panel.proxy.setProgress(zone)
                if feature.totalRounds == feature.passedRounds:
                    v.slotGUI.autospinsSwitcherModule.switchOff()
                    v.slotGUI.spinButtonModule.stopAutospins()
            state.pushBack()
        panel.proxy.setProgress(zone)

        v.slotGUI.progressPanel = panel
    else:
        v.slotGUI.progressPanel = createQuestsProgressPanel(v.slotGUI.rootNode)

    var buttons = newSeq[MenuButton]()
    buttons.add(@[mbSettings, mbSupport, mbPayTable, mbBackToCity])
    if v.tournament.isNil:
        buttons.add(mbPlay)
    # when not defined(andoid) and not defined(ios):
    #     buttons.add(mbFullscreen)

    v.slotGUI.menuButton.setButtons(buttons, false)
    v.initControls()


method preloadSceneResources*(v: BaseMachineView, onComplete: proc() = nil, onProgress: proc(p:float) = nil) =
    proc afterResourcesLoaded() =
        sharedNotificationCenter().postNotification("SLOT_BEFORE_INIT", newVariant(v))
        v.initGUI()
        v.requestState(onComplete)

    procCall v.GameScene.preloadSceneResources(afterResourcesLoaded, onProgress)

proc getRowByIndex*(index: int): int =
    return index div NUMBER_OF_REELS

proc getPayoutForLines*(v: BaseMachineView): int64 = #instead of getWinningForStage
    for line in v.paidLines:
        result += line.winningLine.payout

proc check5InARow*(v: BaseMachineView): bool =
    for line in v.paidLines:
        if line.winningLine.numberOfWinningSymbols == 5:
            return true

proc getWinType*(v: BaseMachineView, payout:int64): WinType =
    if payout >= v.totalBet() * v.multMega:
        return WinType.Mega

    if payout >= v.totalBet() * v.multHuge:
        return WinType.Huge

    if payout >= v.totalBet() * v.multBig:
        return WinType.Big

    if v.check5InARow():
        return WinType.FiveInARow

    return WinType.Simple

proc getWinType*(v: BaseMachineView, isJackpot: bool = false): WinType =
    if isJackpot:
        return WinType.Jackpot

    let payout = v.getPayoutForLines()

    return v.getWinType(payout)

proc getSymbolIndexesForLine*(v:BaseMachineView, line: Line): seq[int] =
    #returns sequence of symbols indexes for line
    result = @[]
    for i, index in line:
        result.add(i + index * NUMBER_OF_REELS)

proc getSymbolIndexesForLine*(v: BaseMachineView, lineIndex: int): seq[int]=
    let line = v.lines[lineIndex]
    result = v.getSymbolIndexesForLine(line)

proc getSymbolIdInLine*(v: BaseMachineView, lineIndex, symbIndex: int): int =
    let symbs = v.getSymbolIndexesForLine(lineIndex)
    if symbIndex < symbs.len:
        result = symbs[symbIndex]

proc getWinConReels*(v:BaseMachineView, symbolId: int): seq[int]  =
    result = @[]
    for i in 0 ..< NUMBER_OF_REELS:
        for j in 0 ..< NUMBER_OF_ROWS:
            let s = v.lastField[j * NUMBER_OF_REELS + i]
            if s == symbolId:
                result.add(i)
    return result

proc getLastWinLineReel*(v:BaseMachineView): int  =
    let winningLines = v.paidLines
    var lastLineWinningReel = -1
    for line in winningLines:
        if line.winningLine.payout > 0:
            lastLineWinningReel = max(lastLineWinningReel, line.winningLine.numberOfWinningSymbols - 1)
    return lastLineWinningReel



proc sortWinningLines*(v: BaseMachineView, lines: seq[PaidLine]): seq[PaidLine] =
    var lines = lines
    lines.sort do(a, b: PaidLine) -> int:
        result = cmp(b.winningLine.payout, a.winningLine.payout)
        if result == 0:
            result = cmp(b.winningLine.numberOfWinningSymbols, a.winningLine.numberOfWinningSymbols)
            if result == 0:
                let sa = v.getSymbolIdInLine(a.index, 0)
                let sb = v.getSymbolIdInLine(b.index, 0)
                result = cmp(sa, sb)
                if result == 0:
                    result = cmp(a.index, b.index)
    result = lines

proc getSortedWinningLines*(v: BaseMachineView)=
    v.paidLines = v.sortWinningLines(v.paidLines)

method getStateForStopAnim*(v:BaseMachineView): WinConditionState {.base.} =
    raise new(ErrorNotImplemented)

method setSpinButtonState*(v: BaseMachineView,  state: SpinButtonState) {.base.} =
    if state == SpinButtonState.ForcedStop:
        if not v.hasResponse:
            return

    if state == SpinButtonState.Blocked and getCurrentState() of SlotFlowState:
        pushFront(SpinFlowState)

    let spinFlow = findActiveState(SpinFlowState)
    if state == SpinButtonState.Spin and not spinFlow.isNil:
        spinFlow.pop()

    let stateSpin = state == SpinButtonState.Spin

    v.actionButtonState = state
    if not v.slotGUI.isNil:
        let switcher = v.slotGUI.autospinsSwitcherModule

        if stateSpin and switcher.isOn:
            if v.currentBalance >= v.totalBet():
                if v.canAutospinClick:
                    v.onSpinClick()
            else:
                v.slotGUI.outOfCurrency("chips")
                v.stopAutospin(AutospinStopReason.NotEnoughChips)

        v.updateTotalBetPanel()

proc getSymbolIndexes(v: BaseMachineView, id: int): seq[int]=
    result = @[]
    if v.lastField.len == 0: return
    for i, s in v.lastField:
        if s == id:
            result.add(i)

method allowHighlightLine*(v: BaseMachineView, paidLine: PaidLine): bool = true

proc fillReelsHighlightSettings(v: BaseMachineView, state: WinConditionState)=
    if v.lastField.len == 0: return

    let wireel = NUMBER_OF_REELS div 2
    var highlighted = newSeq[int]()

    for line in v.paidLines:
        if v.allowHighlightLine(line):
            let coords = v.lines[line.index]
            for ni in 0 ..< line.winningLine.numberOfWinningSymbols:
                let elid = coords[ni] * NUMBER_OF_REELS + ni
                if elid notin highlighted:
                    if ni < wireel:
                        v.animSettings[wireel].highlight.add(elid)
                    else:
                        v.animSettings[ni].highlight.add(elid)
                    highlighted.add(elid)

    for state in [WinConditionState.Bonus, WinConditionState.Scatter]:
        var symbid = if state == WinConditionState.Bonus: BONUS_ID else: SCATTER_ID
        let symbols = v.getSymbolIndexes(symbid)
        let reels = v.getWinConReels(symbid)
        var curreel: int

        for i in 0 ..< reels.len:
            if symbols.len == 1 and reels[i] >= wireel: break
            if i != 0:
                for j in 0.. < symbols.len:
                    curreel = symbols[j] mod NUMBER_OF_REELS
                    if i == 1:
                        if reels[0] == curreel or reels[1] == curreel:
                            v.animSettings[reels[1]].highlight.add(symbols[j])
                    else:
                        if reels[i] == curreel:
                            v.animSettings[reels[i]].highlight.add(symbols[j])

proc setRotationAnimSettings*(v:BaseMachineView, mode: ReelsAnimMode, state: WinConditionState, reelsInfo: BonusScatterReels, timeDiff: float = 0.0) =
    const DELAY_SHORT = 0.125
    const DELAY_LONG = 0.375
    const MINIMAL_ROTATION_TIME = 1.5
    const MIN_REEL_INDEX_FOR_BOOST = 3
    const DELAY_BOOST_LINE_MULTIPLIER = 3
    const DELAY_BOOST_MULTIPLIER = 5

    var delay: float
    var lastWinLineReel: int
    var winConReels: seq[int]
    var lastReelIndex = NUMBER_OF_REELS - 1 #4

    v.animSettings = @[]
    if mode == ReelsAnimMode.Short:
        delay = DELAY_SHORT
    else:
        delay = DELAY_LONG

    for i in 0..<NUMBER_OF_REELS:
        var settings: RotationAnimSettings
        settings.time = MINIMAL_ROTATION_TIME + delay * float(i)
        settings.boosted = false
        settings.highlight = @[]
        v.animSettings.add(settings)

    if state == WinConditionState.Bonus:
        winConReels = v.getWinConReels(BONUS_ID)
    elif state == WinConditionState.Scatter:
        winConReels = v.getWinConReels(SCATTER_ID)

    if state == WinConditionState.Bonus or state == WinConditionState.Scatter:
        var allSymbolReels: seq[int]
        let secondWinConIndex = winConReels[1]

        if state == WinConditionState.Bonus:
            allSymbolReels = reelsInfo.bonusReels
        elif state == WinConditionState.Scatter:
            allSymbolReels = reelsInfo.scatterReels

        for i in secondWinConIndex + 1..lastReelIndex:
            if allSymbolReels.contains(i):
                v.animSettings[i].time = v.animSettings[i - 1].time + delay * DELAY_BOOST_MULTIPLIER
                v.animSettings[i].boosted = true
            else:
                v.animSettings[i].time = v.animSettings[i - 1].time + delay
                v.animSettings[i].boosted = false

    elif state == WinConditionState.Line:
        lastWinLineReel = v.getLastWinLineReel()
        var nextLine = lastWinLineReel + 1

        if nextLine > lastReelIndex:
            nextLine = lastReelIndex
        if nextLine >= MIN_REEL_INDEX_FOR_BOOST:
            for i in MIN_REEL_INDEX_FOR_BOOST..nextLine:
                v.animSettings[i].time = v.animSettings[i - 1].time + delay * DELAY_BOOST_LINE_MULTIPLIER
                v.animSettings[i].boosted = true

            if nextLine + 1 < NUMBER_OF_REELS:
                for i in nextLine + 1..lastReelIndex:
                    v.animSettings[i].time = v.animSettings[i - 1].time + delay
                    v.animSettings[i].boosted = false

    for i in 0..<NUMBER_OF_REELS:
        v.animSettings[i].time += timeDiff

    v.fillReelsHighlightSettings(state)

proc registerTapDetector*(v: BaseMachineView) =
    v.tapGesture = newTapGestureDetector( proc(p: Point )=
        v.clickScreen()
        )
    v.addGestureDetector( v.tapGesture)

proc unregisterTapDetector*(v: BaseMachineView) =
    v.removeGestureDetector( v.tapGesture)

method onKeyDown*(v: BaseMachineView, e: var Event): bool =
    case e.keyCode
    of VirtualKey.Space:
        setController(aSpace)

        result = true
        if v.userCanStartSpin() and v.slotGUI.spinButtonModule.button.enabled and getCurrentState() of NarrativeState == false:
            v.onSpinClick()
    else: discard

    if currentUser().isCheater():
        if not result and e.modifiers.anyOsModifier():
            result = true
            var cmd = ""
            case e.keyCode
            of VirtualKey.F:
                cmd = "freespins"
            of VirtualKey.B:
                cmd = "bonus"
            of VirtualKey.H:
                cmd = "hugewin"
            of VirtualKey.M:
                cmd = "bigwin"
            of VirtualKey.G:
                cmd = "respin"
            of VirtualKey.J:
                cmd = "jackpot"
            of VirtualKey.N:
                cmd = "custom"
            of VirtualKey.Y:
                discard complete_task(@[])
                result = false
            else:
                result = false

            if result:
                info "hotkey send cheat cmd ", cmd
                sendCheatCommand(cmd, $v.buildingId)

    if not result:
        result = procCall v.GameSceneWithCheats.onKeyDown(e)

method resizeSubviews*(v: BaseMachineView, oldSize: Size) =
    procCall v.GameScene.resizeSubviews(oldSize)
    v.slotGUI.layoutGUI()
    if not v.tournamentInfoView2.isNil:
        v.slotGui.layoutModule(v.tournamentInfoView2, 0, -540, Relation.MiddleLeft)

    sharedNotificationCenter().postNotification("GAME_SCENE_RESIZE")

method setupCameraForGui*(v: BaseMachineView) {.base.}=
    v.camera.zNear = -10.0
    var guiScale = v.slotGUI.rootNode.scale
    guiScale.z = 0.01
    v.slotGUI.rootNode.scale = guiScale

proc setupCheats(v: BaseMachineView) {.inline.} =
    if currentUser().isCheater():
        sharedServer().getCheatsConfig do(j: JsonNode):
            if not j.isNil and j.kind != JNull:
                v.cheatsView = createCheatsView(j, v.frame)
                v.cheatsView.extraFields = %*{"mode": v.getMode()}
                v.addSubview(v.cheatsView)
                v.cheatsView.showCheats("slot", $v.buildingId)

        let notifCenter = sharedNotificationCenter()
        notifCenter.addObserver($srtChips, v) do(args: Variant):
            let jn = args.get(JsonNode)
            if jn.hasKey($srtChips):
                let chips = jn[$srtChips].getBiggestInt()
                currentUser().updateWallet(chips)
                v.slotGUI.moneyPanelModule.setBalance(v.currentBalance, chips)

        notifCenter.addObserver("parts", v) do(args: Variant):
            let jn = args.get(JsonNode)
            if jn.hasKey("parts"):
                let parts = jn["parts"].getBiggestInt()
                currentUser().updateWallet(parts = parts)
                v.slotGUI.moneyPanelModule.parts = parts

        notifCenter.addObserver("spin", v) do(args: Variant):
            let jn = args.get(JsonNode)
            if jn.hasKey($srtSuccess) and jn[$srtSuccess].getBool():
                v.onSpinClick()


method didBecomeCurrentScene*(v: BaseMachineView)=
    if not v.gameFlow.isNil:
        doAssert(not v.gameFlow.isStarted(), "GAME FLOW STARTED")
        echo "StartGF ", v.notificationCenter.isNil
        if v.freeSpinsLeft > 0:
            v.gameFlow.start()

method viewOnEnter*(v: BaseMachineView) =
    procCall v.GameScene.viewOnEnter()
    v.slotGUI.layoutGUI()
        let sa = activeSlots().len
        let properBids = [v.buildingId(), BuildingId.noBuilding, BuildingId.anySlot]
        var currentActiveTaskType = ""

        for aq in sharedQuestManager().activeQuests:
            if properBids.contains(aq.tasks[0].target.BuildingId):
                currentActiveTaskType = $aq.tasks[0].taskType

        sharedAnalytics().slot_opened($v.buildingId(), sa, currentUser().chips, v.getTotalRTP(), currentActiveTaskType, v.freeRounds)

    if not v.slotGUI.isNil:
        v.slotGUI.totalBetPanelModule.buttonMinus.onAction do():
            v.betMinus()

        v.slotGUI.totalBetPanelModule.buttonPlus.onAction do():
            v.betPlus()

    v.setupCameraForGui()
    v.setupCheats()

    #ANALYTICS
    isInSlotAnalytics = true

method viewOnExit*(v: BaseMachineView) =
    procCall v.GameScene.viewOnExit()

    if v.triggerSlotAnalyticEvents:
        sharedAnalytics().slot_closed(v.name, v.reasonOfExit, v.slotSpins, v.slotBonuses, v.freespinsTriggered, v.lastActionSpins, v.getRTP(), currentUser().chips)
        if not v.tournament.isNil:
            sendEvent("tournament_left", %*{
                "chips_left": %currentUser().chips,
                "current_tournament_id": v.tournament.title,
                "time_to_current_tournament": timeLeft(v.tournament.endDate).int,
                "current_position": v.tournament.place,
                "is_prize": v.tournament.isPrizePlace(),
                "spins_count": v.slotSpins})
        v.stopAutospin(AutospinStopReason.ExitSlot)
    sharedLocalizationManager().removeStrings(v.name)

method draw*(v: BaseMachineView, r: Rect) =
    procCall v.GameScene.draw(r)

proc chipsAnim*(v: BaseMachineView, parent: Node, oldBalance, newBalance: int64, stage: string): ParticleEmitter {.discardable.} =
    let tn = v.slotGUI.moneyPanelModule.rootNode.findNode("chips_placeholder")
    let fn = v.slotGUI.winPanelModule.winTextNode
    let diff = newBalance - oldBalance
    let chips_c = chipsCountForWin(diff, v.totalBet()).int

    if newBalance > oldBalance:
        if not v.tournamentInfoView2.isNil:
            if stage != "":
                v.tournamentInfoView2.showScoreGain(v, fn, parent, stage)
            else:
                v.tournamentInfoView2.showScoreGain(v, fn, parent, "Spin")
                v.tournamentInfoView2.showScoreGain(v, fn, parent, "Bonus")

        result = v.chipsAnim(fn, tn, parent, chips_c, oldBalance, newBalance)

method onBonusGameStart*(v: BaseMachineView) {.base.} =
    let spinsFromLast = saveNewBonusgameLastSpins(v.name)
    sharedAnalytics().bonusgame_start(v.name, v.slotSpins, v.totalBet, currentUser().chips, spinsFromLast)

method onBonusGameEnd*(v: BaseMachineView) {.base.} =
    sharedAnalytics().bonusgame_end(v.name, v.slotSpins, v.totalBet, v.getRTP(), currentUser().chips)

method onFreeSpinsStart*(v: BaseMachineView) {.base.} =
    let spinsFromLast = saveNewFreespinLastSpins(v.name)
    v.`stage=`(GameStage.FreeSpin)
    sharedAnalytics().freespins_start(v.name, v.slotSpins, v.totalBet, currentUser().chips, spinsFromLast)

    v.updateBetInUI()

method onFreeSpinsEnd*(v: BaseMachineView) {.base.} =
    v.`stage=`(GameStage.Spin)
    sharedAnalytics().freespins_end(v.name, v.slotSpins, v.totalBet, v.getRTP(), currentUser().chips, v.freespinsStage)

    v.updateBetInUI()

method onFreespinsModeSelect*(v: BaseMachineView) {.base.} =
    sharedAnalytics().freespins_start_select(v.name, v.slotSpins, v.totalBet, currentUser().chips, v.freespinsStage)

method onBigWinHappend*(v: BaseMachineView, bwt:BigWinType, chipsBeforeWin:int64) {.base.} =
    let occ = saveNewBigwin(v.name, $bwt)
    sharedAnalytics().bigwin_happened(v.buildingId(), bwt.int, chipsBeforeWin, v.totalBet, getCountedEvent(v.name & TOTAL_SPINS), occ)

proc spinAnalyticsUpdate*(v: BaseMachineView, winForSpin: int64, isFreeSpin: bool) =
    v.slotSpins.inc()
    saveTotalSpins(v.name)
    v.incLastActionSpins()

    var spentForSpin:int64 = v.totalBet()
    if isFreeSpin:
        spentForSpin = 0

    v.sessionTotalSpend += spentForSpin
    v.sessionTotalWin += winForSpin

    saveTotalWin(v.name, winForSpin)
    saveTotalSpent(v.name, spentForSpin)
    saveLastBet(v.name, v.totalBet)

    var lastRTP:float64 = 0.0
    if winForSpin > 0:
        lastRTP = winForSpin.float64/spentForSpin.float64

    setLastRTPAnalytics(lastRTP, v.getRTP())
    setStagesCountAnalytics(v.slotSpins, v.slotBonuses, v.freespinsTriggered)

proc onWinDialogShow*(v: BaseMachineView) = discard

proc onWinDialogShowAnimationComplete*(v: BaseMachineView) = discard
    # when defined(emscripten): # TODO: Enable me for other platforms
    #     let shareBttn = addFBShareButton(v.slotGUI.rootNode)
    #     shareBttn.onShareClick = proc() = v.removeWinAnimationWindow()
    #     sharedAnalytics().shared_screen_initiate(v.className())

proc onWinDialogClose*(v: BaseMachineView) =
    let shareBttn = v.slotGUI.rootNode.findNode("fb_share_button")
    if not shareBttn.isNil:
        shareBttn.getComponent(FBShareButton).hide()

import utils.console
proc gf_current_event(args: seq[string]): string =
    if currentDirector().currentScene of BaseMachineView:
        result = currentDirector().currentScene.BaseMachineView.gameFlow.currentEvent()
        info "current game flow event ", result

registerConsoleComand(gf_current_event, "gf_current_event()")

proc spinCityPoints(args: seq[string]): string =
    if currentDirector().currentScene of BaseMachineView:
        currentDirector().currentScene.BaseMachineView.experienceAnimation()
        result = "OK"
    else:
        result = "NOT IN SLOT VIEW!"

method createDeepLink*(v: BaseMachineView): seq[tuple[id: string, route: string]] =
    if v.freeRounds:
        result = @{"free-rounds": v.name}
    elif v.tournament.isNil:
        result = @{"scene": v.name}
    else:
        result = @{"scene": "TiledMapView", "window": "TournamentsWindow"}

registerConsoleComand(spinCityPoints, "spinCityPoints()")


sharedDeepLinkRouter().registerHandler(
    "free-rounds"
    , onHandle = proc(route: string, next: proc()) =
        let notificationCenter = sharedNotificationCenter()
        notificationCenter.addObserver("SLOT_BEFORE_INIT", notificationCenter) do(args: Variant):
            let scene = args.get(BaseMachineView)
            if scene.name == route:
                scene.mode = smkFreeRound
                scene.freeRounds = true
                notificationCenter.removeObserver("SLOT_BEFORE_INIT", notificationCenter)
        sharedDeepLinkRouter().handle("/scene/" & route)
        next()
)
