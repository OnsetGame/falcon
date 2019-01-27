import logging, variant
import core / notification_center
import utils / [ game_state ]
import shared / [ user, shared_gui, tutorial ]
import shared / window / [ window_component, window_manager, levelup_window, rewards_window, new_task_event, task_complete_event, tasks_window, compensation_window,
     welcome_window, alert_window, maintenance_window, rate_window, button_component, special_offer_window, vip_levelup_window, free_rounds_result]
import tournaments / [ tournaments_view, tournament_info_view, tournament ]
import quest / [ quests, quests_actions ]
import shafa / game / message_types

import core / zone
import core / flow / flow_state_types
import core / net / server
import core / features / vip_system
import core / helpers / reward_helper
export flow_state_types

import falconserver.map.building.builditem
import platformspecific.android.rate_manager

proc showRewards(box: RewardWindowBoxKind, rew: seq[Reward], forVip: bool = false) =
    let rewState = GiveRewardWindowFlowState.new()
    rewState.name = "GiveRewardWindowFlowState"
    rewState.boxKind =  box
    rewState.rewards =  rew
    rewState.isForVip = forVip
    pushFront(rewState)


method wakeUp*(state: LevelUpWindowFlowState) =
    let expState = findPendingState(ExpirienceFlowState)
    if not expState.isNil:
        execute(expState)

    let user = currentUser()
    let lvl = user.level
    let lw = sharedWindowManager().show(LevelUPWindow)
    lw.setUp(lvl)

    lw.onClose = proc() =
        showRewards(RewardWindowBoxKind.blue, lw.rewards)
        state.pop()

method wakeUp*(state: VipLevelUpWindowFlowState) =
    let lw = sharedWindowManager().show(VipLevelUPWindow)
    lw.setUp(state.level)

    lw.onClose = proc() =
        let rews = sharedVipConfig().getLevel(state.level).rewards.filterVipRewards()
        showRewards(RewardWindowBoxKind.blue, rews, true)
        state.pop()


method wakeUp*(state: GiveRewardWindowFlowState) =
    let rewWindow = sharedWindowManager().show(RewardWindow)

    if not rewWindow.isNil:
        rewWindow.boxKind   = state.boxKind
        rewWindow.rewards   = state.rewards
        rewWindow.forVip(state.isForVip)

        rewWindow.onClose = proc() =
            sharedQuestManager().getQuestRewards(qttLevelUp.int)
            state.pop()
    else:
        state.pop()

method wakeUp*(state: GiveQuestRewardFlowState) =
    let qid = state.data.get(int)
    let q = sharedQuestManager().questById(qid)

    if not q.isNil:
        let cb = proc() =
            showRewards(RewardWindowBoxKind.grey, q.rewards)
            state.weakPop()
        sharedQuestManager().getQuestRewards(qid, cb)
    else:
        state.pop()

method wakeUp*(state: CompleteTaskFlowState) =
    proc cb() = state.pop()
    let quest = state.data.get(Quest)

    var needShowUpgradeWindow = false
    let storyQuests = sharedQuestManager().activeStories()
    let task = quest.tasks[0]

    if not getBoolGameState("MAP_SHOWED"):
        needShowUpgradeWindow = true

    let tce = sharedWindowManager().show(TaskCompleteEvent)
    currentNotificationCenter().postNotification("TASKS_COMPLETE_EVENT")
    tce.setUpQuestData(quest.rewards[0].amount.int)
    tce.onClose = proc() =
        sharedQuestManager().getQuestRewards(quest.id) do():
            for sq in storyQuests:
                if sq.config.price <= currentUser().parts and sq.status == QuestProgress.Ready:
                    needShowUpgradeWindow = true
                    break

            if needShowUpgradeWindow:
                showUpgradeOrNewFeatureWindow(cb)
            else:
                let tw = sharedWindowManager().show(TasksWindow)
                tw.setTargetSlot()
                tw.onClose = cb

method wakeUp*(state: ServerMessageFlowState) =
    let msg = state.msg

    if msg.kind == "compensation":
        let cw = sharedWindowManager().show(CompensationWindow)
        cw.setupData(msg.data)
        cw.onClose = proc() =
            sharedServer().removeMessage(msg.kind)
            showRewards(RewardWindowBoxKind.gold, msg.rewards)
            state.pop()

    elif msg.kind == "vip_level_compensation":
        let oldLvl = msg.data["oldVipLvl"].getInt()
        let newLvl = msg.data["newVipLvl"].getInt()
        for l in oldLvl+1 .. newLvl:
            pushBack(VipLevelUpWindowFlowState(level: l, name: "VipLevelUpWindowFlowState"))

        sharedServer().removeMessage(msg.kind)
        state.pop()

    else:
        let ww = sharedWindowManager().show(WelcomeWindow)
        try:
            if msg.title.len > 0:
                ww.title = msg.title
            ww.description = msg.text
        except:
            error "Invalid text. Exception in msg: ", msg.kind

        if msg.hasLinks:
            ww.showPrivacy()
            ww.showFaq()

        if msg.bodyNumber > 0 and msg.headNumber > 0:
            ww.character = msg.character
            ww.bodyNumber = msg.bodyNumber
            ww.headNumber = msg.headNumber

        ww.onClose = proc() =
            sharedServer().removeMessage(msg.kind)
            if msg.rewards.len > 0:
                showRewards(RewardWindowBoxKind.gold, msg.rewards)
            state.pop()

method wakeUp*(state: MaintenanceFlowState) =
    let cb = proc() = state.pop()
    let timeout = state.data.get(float)
    openMaintenanceWindowIfNeed(timeout, cb)

method wakeUp*(state: MapQuestUpdateFlowState) =
    currentNotificationCenter().postNotification("UPDATE_QUEST", state.data)
    state.pop()

method wakeUp*(state: TournamentShowFinishFlowState) =
    let w = sharedWindowManager().show(TournamentBlockerWindow)
    w.setup(state.data.get(Tournament))
    w.onClose = proc() = state.pop()

method wakeUp*(state: TournamentShowWindowFlowState) =
    let w = sharedWindowManager().show(TournamentsWindow)
    w.onClose = proc() = state.pop()

method wakeUp*(state: RateUsFlowState) =
    if canRate():
        let w = sharedWindowManager().show(RateWindow)
        w.onClose = proc() = state.pop()
    else:
        state.pop()

method wakeUp*(state: NewQuestBarFlowState) =
    currentNotificationCenter().postNotification("ADD_NEW_QUEST", state.data)
    state.pop()

method wakeUp*(state: CollectConfigFlowState) =
    currentNotificationCenter().postNotification("CollectConfigEv")
    state.pop()

method wakeUp*(state: BetConfigFlowState) =
    currentNotificationCenter().postNotification("BetConfigEv", state.data)
    state.pop()

method wakeUp*(state: UpdateTaskProgresState) =
    if not currentNotificationCenter().isNil:
        currentNotificationCenter().postNotification(QUESTS_UPDATED_EVENT)
    state.pop()


method wakeUp*(state: SpecialOfferFlowState) =
    if state.offerBundleID.len == 0:
        state.pop()
        echo "Can't do SpecialOfferFlowState with offersBundleId nil. "
        return

    proc cb() = state.pop()
    tryStartSpecialOffer(state.offerBundleID, cb)

method wakeUp*(state: OfferFromTimerFlowState) =
    let sod = state.sod
    let offerWindow = sharedWindowManager().createWindow(SpecialOfferWindow)
    offerWindow.prepareForBundle(sod)
    offerWindow.source = state.source
    sharedWindowManager().show(offerWindow)

    state.pop()

method wakeUp*(state: OfferFromActionFlowState) =
    if state.offerJson.isNil:
        state.pop()
        echo "Can't do SpecialOfferFlowState with offersBundleId nil. "
        return

    proc cb() = state.pop()
    tryStartSpecialOfferFromAction(state.offerJson, cb)

method wakeUp*(state: ExpirienceFlowState) =
    let (toLevelExp, currentExp) = state.data.get(tuple[toLevelExp:int, currentExp:int])
    if currentUser().currentExp != currentExp:
        currentNotificationCenter().postNotification("SharedGuiExperienceEv")
    currentUser().toLevelExp = toLevelExp
    currentUser().currentExp = currentExp
    state.pop()

method wakeUp*(state: SlotNextEventFlowState) =
    state.pop()
    let gf = state.data.get(proc())
    if not gf.isNil:
        gf()


method wakeUp*(state: OpenFreeRoundsResultWindowFlowState) =
    let win = sharedWindowManager().show(FreeRoundsResultWindow)
    win.setZone(state.zone.get(Zone))
    win.onClose = proc() =
        state.pop()
