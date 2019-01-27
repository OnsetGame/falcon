import tables
import times
import sequtils
import algorithm

import nimx.view
import nimx.button
import nimx.matrixes
import nimx.text_field
import nimx.panel_view
import core / notification_center

import rod.rod_types
import rod.viewport
import rod.node
import rod.component

import json

import rod.component.ui_component
import nimx.table_view
import nimx.scroll_view
import strutils

import utils.pause
import utils.timesync

import nimx.formatted_text

import core.net.server
import shared.director
import shared.user

import falconserver.map.building.builditem
import core.slot.base_slot_machine_view
import slots.slot_machine_registry
import quest.quest_helpers

import tournament

import shared.window.rewards_window
import shared.window.window_component
import tournaments.tournament_result_window
import shared.window.button_component
import rod.component.text_component
import shared.window.window_manager
import utils.node_scroll
import shared.gui.gui_module
import shared.tutorial

import shared.localization_manager

import utils.falcon_analytics

import rod.component.solid
import utils.icon_component
import core / helpers / [ boost_multiplier, reward_helper ]
import core / features / booster_feature
import core / zone


type RoundedLabel = ref object
    node: Node
    activeLabel: Text
    inactiveLabel: Text

proc newRoundedLabel(node: Node): RoundedLabel =
    result.new
    result.node = node
    result.activeLabel = node.mandatoryNode("active").getComponent(Text)
    result.inactiveLabel = node.mandatoryNode("inactive").getComponent(Text)

proc setText(lbl: RoundedLabel, text: string, active: bool) =
    lbl.activeLabel.text = text
    lbl.inactiveLabel.text = text
    lbl.activeLabel.node.enabled = active
    lbl.inactiveLabel.node.enabled = not active


type IconButton = ref object
    node: Node
    button: ButtonComponent
    label: Text
    chips_Icon: Node
    lock_Icon: Node

proc newIconButton(node: Node, rect: Rect): IconButton =
    result.new
    result.node = node
    result.button = node.createButtonComponent(rect)
    result.label = node.mandatoryNode("title").getComponent(Text)
    let icons = node.findNode("icon_join")
    if not icons.isNil:
        result.chips_Icon = icons.mandatoryNode("ltp_chips_2.png")
        result.chips_Icon.enabled = false
        result.lock_Icon = icons.mandatoryNode("ltp_closed.png")
        result.lock_Icon.enabled = false



type TournamentWindowItem* = ref object of RootObj
    node: Node
    tournament: Tournament
    title: Text
    timeToEnd: Text
    timeEnded: Text
    players: Text
    bet: Text
    prizeFund: Text
    participationHighlight: Node

    comingSoon_Button: IconButton
    comingSoon_Label: Text

    join_Button: IconButton
    join_Label: Text

    locked_Button: IconButton
    locked_Label: Text

    continue_Button: IconButton
    score_Label: Text
    scoreValue_Label: Text

    reward_Button: IconButton
    reward_Image: Node

    # locationIcons: ref Table[string, Node]

    finished_Icon: Node
    progressFiller: Node
    progressFillerFullScale: float
    noProgressFiller: Node
    chips_Icon: Node
    bucks_Icon: Node
    chips_Label: RoundedLabel
    players_Label: RoundedLabel
    time_Label: RoundedLabel

    icoComp: IconComponent


proc update(i: TournamentWindowItem, t: Tournament)


proc gainReward*(t: Tournament) =
    let tResultWindow = sharedWindowManager().show(TournamentResultWindow)
    tResultWindow.setUpTournament(t)
    sharedServer().claimTournamentReward(t.participationId, proc(res: JsonNode) =
        echo res
        if res["status"].getStr() == "Ok":
            t.participationId = ""
            t.rewardIsClaimed = true
            let chips = res["response"]["chips"].getBiggestInt()
            let bucks = res["response"]{"bucks"}.getBiggestInt()
            let tournPoints = res["response"]["tourPoints"].getBiggestInt()
            let ufoFreeRounds = res["response"]{"freeRounds"}.getBiggestInt()

            tResultWindow.onClose = proc() =
                var rew = newSeq[Reward]()
                if chips > 0:
                    rew.add(createReward(RewardKind.chips, chips))
                if bucks > 0:
                    rew.add(createReward(RewardKind.bucks, bucks))
                if tournPoints > 0:
                    rew.add(createReward(RewardKind.tourPoints, tournPoints))
                if ufoFreeRounds > 0:
                    let r = createReward(RewardKind.freeRounds, ufoFreeRounds, $ufoSlot)
                    rew.add(r)

                let rewWindow = sharedWindowManager().show(RewardWindow)
                rewWindow.boxKind = RewardWindowBoxKind.red
                rewWindow.rewards = rew
                rewWindow.onClose = proc() =
                    currentNotificationCenter().postNotification("SHOW_TOURNAMENTS_WINDOW")
    )


proc init(i: TournamentWindowItem, w: WindowComponent) =
    i.title = i.node.mandatoryNode("title_tournament").getComponent(Text)
    i.timeToEnd = i.node.mandatoryNode("time").getComponent(Text)
    i.timeEnded = i.node.mandatoryNode("tr_time_ended").getComponent(Text)
    i.players = i.node.mandatoryNode("players").getComponent(Text)
    i.bet = i.node.mandatoryNode("bet").getComponent(Text)
    i.prizeFund = i.node.mandatoryNode("prizepool").getComponent(Text)
    i.participationHighlight = i.node.mandatoryNode("ltp_light_in_menu.png")
    i.progressFiller = i.node.mandatoryNode("ltp_small_progress_bar_part.png")
    i.progressFillerFullScale = i.progressFiller.scaleX
    i.noProgressFiller = i.node.mandatoryNode("ltp_small_progress_bar_noprogress.png")
    i.finished_Icon = i.node.mandatoryNode("Finished.png")

    i.chips_Icon = i.node.mandatoryNode("1_chips_icon.png")
    i.bucks_Icon = i.node.mandatoryNode("1_bucks_icon.png")
    i.chips_Label = newRoundedLabel(i.node.mandatoryNode("chips_label"))
    i.chips_Label.setText(localizedString("TR_PRIZE_POOL_TITLE"), false)

    i.players_Label = newRoundedLabel(i.node.mandatoryNode("players_label"))
    i.players_Label.setText(localizedString("TR_PLAYERS_TITLE"), false)

    i.time_Label = newRoundedLabel(i.node.mandatoryNode("time_label"))
    i.time_Label.setText(localizedString("TR_TIME_TO_END"), false)

    # tournament not started yet
    i.comingSoon_Button = newIconButton(i.node.mandatoryNode("grey_button"), newRect(0, 0, 300, 84))
    i.comingSoon_Button.lock_Icon.enabled = true
    i.comingSoon_Label = i.node.mandatoryNode("TR_COMING_SOON").getComponent(Text)

    # may enter and has enough chips
    i.join_Button = newIconButton(i.node.mandatoryNode("orange_button_bicolor"), newRect(0, 0, 300, 84))
    i.join_Label = i.node.mandatoryNode("TR_JOIN!").getComponent(Text)

    # may enter, but has not enough chips
    i.locked_Button = newIconButton(i.node.mandatoryNode("grey_button_bicolor"), newRect(0, 0, 300, 84))
    i.locked_Button.label.text = localizedString("TR_LOCKED")
    i.locked_Button.lock_Icon.enabled = true
    i.locked_Label = i.node.mandatoryNode("locked_chips_title").getComponent(Text)

    # to continue already joined tournament
    i.continue_Button = newIconButton(i.node.mandatoryNode("Button_blue"), newRect(0, 0, 300, 84))
    i.continue_Button.label.text = localizedString("TR_CONTINUE")
    i.score_Label = i.node.mandatoryNode("TR_YOUR_SCORE").getComponent(Text)
    i.scoreValue_Label = i.node.mandatoryNode("score_value").getComponent(Text)

    i.reward_Button = newIconButton(i.node.mandatoryNode("Yellow_middle_button_tournaments"), newRect(0, 0, 300, 84))
    i.reward_Button.label.text = localizedString("TR_GET_REWARD")
    i.reward_Image = i.node.mandatoryNode("reward_tournament")

    i.node.mandatoryNode("Friends").enabled = false

    # i.locationIcons = newTable[string, Node]()
    # i.locationIcons["dreamTowerSlot"] = i.node.mandatoryNode("ltp_dream_tower_slot_1.png")
    # i.locationIcons["balloonSlot"] = i.node.mandatoryNode("ltp_windy_day_slot_copy_2.png")
    # i.locationIcons["candySlot"] = i.node.mandatoryNode("ltp_candy_shop_slot_copy.png")

    let scoreStars_Icon = i.node.mandatoryNode("Score.png")
    scoreStars_Icon.enabled = false

    let icoPlaceholder = i.node.findNode("placeholder")
    let icoSolid = icoPlaceholder.getComponent(Solid)
    icoSolid.color = newColor(0,0,0,0)
    i.icoComp = icoPlaceholder.component(IconComponent)
    i.icoComp.prefix = "common/lib/icons/precomps"
    i.icoComp.composition = "slot_logos_icons"
    i.icoComp.rect = newRect(newPoint(0, 0), icoSolid.size)
    # icoPlaceholder.removeComponent(Solid)


    i.join_Button.button.onAction do():
        if w.processClose:
            return
        sendEvent("tournament_open", %*{
            "chips_left": %currentUser().chips,
            "current_tournament_id": i.tournament.title,
            "time_to_current_tournament": timeLeft(i.tournament.endDate).int})

        w.closeButtonClick()
        sharedServer().joinTournament(i.tournament.id, proc(res: JsonNode) =
                echo res
                if res["status"].str == "Ok" and res.hasKey("partId"):
                    i.tournament.participationId = res["partId"].str
                    i.tournament.updateFromParticipantsResponse(res, preserveScore = false)
                    #i.update()
                    currentUser().updateWallet(res["chips"].getBiggestInt())

                    let scene = startSlotMachineGame(parseEnum[BuildingId](i.tournament.slotName), smkTournament)
                    scene.BaseMachineView.setTournament(i.tournament)
            )

    i.continue_Button.button.onAction do():
        if w.processClose:
            return
        sendEvent("tournament_reopen", %*{
            "chips_left": %currentUser().chips,
            "current_tournament_id": i.tournament.title,
            "time_to_current_tournament": timeLeft(i.tournament.endDate).int,
            "current_position": i.tournament.place,
            "is_prize": i.tournament.isPrizePlace()})

        w.closeButtonClick()
        let scene = startSlotMachineGame(parseEnum[BuildingId](i.tournament.slotName), smkTournament)
        scene.BaseMachineView.setTournament(i.tournament)

    i.reward_Button.button.onAction do():
        if w.processClose:
            return
        i.tournament.gainReward()

    # result.playBt.onAction do():
    #     var slotClassName = buildingIdToClassName[parseEnum[BuildingId](t.slotName)]
    #     let scene = currentDirector().moveToScene(slotClassName)
    #     scene.BaseMachineView.tournament = t


proc runTimeLeft(t: Tournament): float =
    if t.endDate < 0:
        result = t.duration  # always running if no endDate set
    else:
        result = timeLeft(t.endDate)


proc timerText(time: float): string =
    #result = time.fromSeconds().getGMTime().format("hh:mm:ss")
    result = $(time.int div 3600) & (time.int mod 3600).fromSeconds().getGMTime().format(":mm:ss")  # because we need 24+ hours duration to be handled too


proc hasStarted(t: Tournament): bool = timeLeft(t.startDate) < 0
proc isRunning(t: Tournament): bool = t.hasStarted and t.runTimeLeft > 0 and not t.isClosed
proc hasEnoughChips(t: Tournament): bool = currentUser().chips >= t.entryFee
proc slotIsAvailable(t: Tournament): bool = parseEnum[BuildingId](t.slotName) in activeSlots()  or  t.endDate < 0  # tutorial tournament
proc alreadyJoined(t: Tournament): bool = t.participationId.len != 0
proc isOpen(t: Tournament): bool = t.isRunning and not t.alreadyJoined
proc joinConditionsMet(t: Tournament): bool = t.hasEnoughChips and t.slotIsAvailable
proc mayContinue(t: Tournament): bool = t.isRunning and t.alreadyJoined
proc mayClaimReward(t: Tournament): bool = t.isClosed and t.alreadyJoined and not t.rewardIsClaimed


proc update(i: TournamentWindowItem, t: Tournament) =
    assert(not t.isNil)
    i.tournament = t

    #echo i.tournament.title, " - isRunning = ", isRunning, ",  mayJoin = ", mayJoin, ",  mayContinue = ", mayContinue, ",  mayClaimReward = ", mayClaimReward
    #echo "  runTimeLeft = ", runTimeLeft, ",  i.tournament.isClosed = ", i.tournament.isClosed

    i.participationHighlight.enabled = i.tournament.isRunning
    i.timeToEnd.node.enabled = not i.tournament.isClosed
    i.timeEnded.node.enabled = i.tournament.isClosed
    i.progressFiller.enabled = i.tournament.isRunning
    i.noProgressFiller.enabled = not i.tournament.isRunning
    i.players.node.enabled = i.tournament.hasStarted

    i.title.text = i.tournament.title
    #levelLabel.text = "L " & $t.level
    i.bet.text = $(i.tournament.bet div 1000) & "K"
    i.join_Button.chips_Icon.enabled = (i.tournament.entryFee > 0)
    i.comingSoon_Button.chips_Icon.enabled = (i.tournament.entryFee > 0)

    var entryFeeText: string
    if not t.slotIsAvailable:
        entryFeeText = localizedString("TR_LOCKED")
        i.locked_Label.text = localizedString("TR_BUILD_SLOT_TO_PLAY")
    elif i.tournament.entryFee > 0:
        entryFeeText = $(i.tournament.entryFee div 1000) & "K"
        i.locked_Label.text = localizedFormat("TR_AVAILABLE_WITH_CHIPS", entryFeeText)
    else:
        entryFeeText = localizedString("TR_FREE")

    i.comingSoon_Button.label.text = entryFeeText
    i.join_Button.label.text = entryFeeText

    if i.tournament.prizeFundBucks > 0:
        i.bucks_Icon.enabled = true
        i.chips_Icon.enabled = false
        i.prizeFund.text = $(i.tournament.prizeFundBucks)
    else:
        i.bucks_Icon.enabled = false
        i.chips_Icon.enabled = true
        i.prizeFund.text = $(i.tournament.prizeFundChips div 1000) & "K"

    if i.tournament.participationId.len != 0 and i.tournament.isRunning:
        i.scoreValue_Label.text = $i.tournament.myScore
    else:
        i.score_Label.node.enabled = false
        i.scoreValue_Label.node.enabled = false

    if i.tournament.participationId.len != 0 and not i.tournament.participants.isNil:
        i.tournament.sortParticipants()
        i.players.text = "<span style=\"color:FFFFFFFF\">$1</span><span style=\"fontSize:24\">/$2</span>" % [$i.tournament.place, $i.tournament.playersCount]
    else:
        i.players.text = $i.tournament.playersCount

    i.icoComp.name = $i.tournament.slotName

    if i.tournament.isRunning:
        i.time_Label.setText(localizedString("TR_TIME_TO_END"), false)
        i.timeToEnd.text = i.tournament.runTimeLeft.timerText()
        if i.tournament.endDate < 0:
            i.progressFiller.scaleX = 0.0
        else:
            i.progressFiller.scaleX = i.progressFillerFullScale * (1.0 - i.tournament.runTimeLeft / (i.tournament.endDate - i.tournament.startDate))
    elif not i.tournament.hasStarted:
         i.time_Label.setText(localizedString("TR_TIME_TO_START"), true)
         i.timeToEnd.text = timeLeft(i.tournament.startDate).timerText()

    let comingSoonEnabled = not i.tournament.hasStarted
    i.comingSoon_Button.node.enabled = comingSoonEnabled
    i.comingSoon_Button.button.enabled = comingSoonEnabled
    i.comingSoon_Label.node.enabled = comingSoonEnabled

    let joinEnabled = i.tournament.isOpen and i.tournament.joinConditionsMet
    i.join_Button.node.enabled = joinEnabled
    i.join_Button.button.enabled = joinEnabled
    i.join_Label.node.enabled = joinEnabled

    let lockEnabled = i.tournament.isOpen and not i.tournament.joinConditionsMet
    i.locked_Button.node.enabled = lockEnabled
    i.locked_Button.button.enabled = lockEnabled
    i.locked_Label.node.enabled = lockEnabled

    i.continue_Button.node.enabled = i.tournament.mayContinue
    i.continue_Button.button.enabled = i.tournament.mayContinue
    i.score_Label.node.enabled = i.tournament.mayContinue

    i.reward_Button.node.enabled = i.tournament.mayClaimReward
    i.reward_Button.button.enabled = i.tournament.mayClaimReward
    i.reward_Image.enabled = i.tournament.mayClaimReward

    i.finished_Icon.enabled = i.tournament.runTimeLeft <= 0 or i.tournament.isClosed

    #i.claimBt.enabled = i.tournament.isClosed and not i.tournament.rewardIsClaimed


type TournamentsWindow* = ref object of WindowComponent
    updateTimer: ControlledTimer
    updateCountdown: int
    updateSpan: int

    title: Text
    desc: Text
    #item: TournamentWindowItem
    items: seq[TournamentWindowItem]
    tournaments: seq[Tournament]
    #onRemove*: proc()
    itemsRoot: Node
    firstItemPos: Vector3
    itemAnchor: Vector3
    itemGap: Coord
    scroller: NodeScroll
    cheatView : View
    boostMultiplier*: BoostMultiplier


proc findActiveTournament(w: TournamentsWindow): Tournament =
    for ti in w.items:
        if not ti.isNil and timeLeft(ti.tournament.startDate) < 0 and timeLeft(ti.tournament.endDate) > 0:
            return ti.tournament


proc findNextTournament(w: TournamentsWindow): Tournament =
    for ti in w.items:
        if not ti.isNil and timeLeft(ti.tournament.startDate) >= 0:
            return ti.tournament


proc findRewardedTournament*(tournaments: seq[Tournament]): Tournament =
    for t in tournaments:
        if t.isClosed and t.participationId.len != 0 and not t.rewardIsClaimed:
            return t


proc findCurrentTournament(w: TournamentsWindow): Tournament =
    for ti in w.items:
        if not ti.isNil and ti.tournament.participationId.len != 0:
            return ti.tournament


proc newTournamentWindowItem(w: TournamentsWindow, index: int, t: Tournament): TournamentWindowItem =
    let content = newLocalizedNodeWithResource("common/gui/popups/precomps/Tournament_placeholder.json")
    #w.itemsRoot.addChild(resNode)
    w.scroller.addChild(content)
    result.new
    result.node = content
    result.tournament = t
    result.init(w)
    result.node.position = w.firstItemPos
    result.node.positionY = result.node.positionY + w.itemGap * index.Coord
    result.node.anchor = w.itemAnchor

    content.addAnimation(content.animationNamed("appear"))
    result.update(t)


proc importance(t: Tournament): int =
    if t.mayClaimReward:
        result = 1
    elif t.mayContinue:
        result = 2
    elif t.isRunning:
        result = 3
    else:
        result = 4


proc cmp(t1, t2: Tournament): int =
    result = cmp(t1.importance, t2.importance)
    if result != 0:
        return result

    if t1.isRunning:
        result = cmp(t2.slotIsAvailable, t1.slotIsAvailable)
        if result != 0:
            return result

        result = cmp(t2.prizeFundBucks, t1.prizeFundBucks)
        if result == 0:
            result = cmp(t2.prizeFundChips, t1.prizeFundChips)
        return result

    return cmp(t1.startDate, t2.startDate)


proc updateContentFromResponse*(w: TournamentsWindow, tournaments: seq[Tournament]) =
    w.tournaments = tournaments.filter(proc (t: Tournament): bool = t.shouldShowInWindow)
    w.tournaments.sort do(t1, t2: Tournament) -> int:
        result = cmp(t1, t2)

    for item in w.items:
        if not item.isNil:
            item.node.removeFromParent()
    w.items = newSeq[TournamentWindowItem]()
    for i in 0 ..< w.tournaments.len:
        w.items.add(w.newTournamentWindowItem(i, w.tournaments[i]))


proc updateOnTimer(w: TournamentsWindow) =
    w.updateCountdown.dec
    if w.updateCountdown <= 0:
        w.updateCountdown = w.updateSpan
        #v.requestUpdate()
    else:
        w.tournaments = w.tournaments.filter(proc (t: Tournament): bool = t.shouldShowInWindow)
        w.tournaments.sort do(t1, t2: Tournament) -> int:
            result = cmp(t1, t2)
        for i in 0 ..< w.tournaments.len:
            w.items[i].update(w.tournaments[i])
        for i in w.tournaments.len ..< w.items.len:
            if not w.items[i].isNil:
                w.items[i].node.removeFromParent()
                w.items[i].node = nil
                w.items[i] = nil


registerComponent(TournamentsWindow, "windows")


const gapH = 5.Coord
const bottomH = 40.Coord

const gapW = 5.Coord
const serviceButtonW = 150.Coord


proc newTournamentsCheatButtons(v: View, w: TournamentsWindow) =
    var x = gapW
    let y = gapH

    let fastTournamentBt = Button.new(newRect(x, y, serviceButtonW, bottomH))
    fastTournamentBt.title = "Fast tournament"
    v.addSubview(fastTournamentBt)
    fastTournamentBt.onAction do():
        sharedServer().tournamentCreateFast proc(res: JsonNode) =
            echo "tournamentCreateFast = ", res
            w.updateContentFromResponse(parseTournamentsFromResponse(res["tournaments"]))


    x += serviceButtonW + gapW
    let tutorialTournamentBt = Button.new(newRect(x, y, serviceButtonW, bottomH))
    tutorialTournamentBt.title = "Tutorial tournament"
    v.addSubview(tutorialTournamentBt)
    tutorialTournamentBt.onAction do():
        sharedServer().getTutorialTournament proc(res: JsonNode) =
            echo "getTutorialTournament = ", res
            w.updateContentFromResponse(parseTournamentsFromResponse(res["tournaments"]))


# proc update(v: TournamentsView) =
#     v.updateCountdown.dec
#     if v.updateCountdown <= 0:
#         v.updateCountdown = v.updateSpan
#         #v.requestUpdate()
#     else:
#         for i in v.items:
#             i.update()

proc hasCompletedTutorialTournament(w: TournamentsWindow): bool =
    for t in w.tournaments:
        if t.level == 0 and t.isClosed and not t.rewardIsClaimed:
            return true
    return false

proc tutorialLogic(w: TournamentsWindow) =
    tsTournamentJoin.addTutorialFlowState(true)
    if isFrameClosed($tsTournamentJoin):
        if not isFrameClosed($tsFirstTournamentReward) and w.hasCompletedTutorialTournament():
            tsFirstTournamentReward.addTutorialFlowState(true)
        else:
            tsShowTpPanel.addTutorialFlowState(true)

# var tournamentsView : TournamentsView = nil
proc handleTournamentsResponse(w: TournamentsWindow, res: JsonNode) =
    if w.processClose:
        return
    let pv = currentDirector().currentScene
    #echo $res
    let tournaments = parseTournamentsFromResponse(res["tournaments"])
    # let rewardedT = tournaments.findRewardedTournament()
    # if not rewardedT.isNil:
    #     rewardedT.gainReward()
    # else:
    w.updateContentFromResponse(tournaments)
    let activeT = w.findActiveTournament()
    let nextT = w.findNextTournament()
    sharedAnalytics().wnd_tournaments_open(
        nextTournament = if nextT.isNil(): ""  else: nextT.title,
        activeTournament = if activeT.isNil(): ""  else: activeT.title,
        timeToNextTournament = if nextT.isNil(): -1  else: timeLeft(nextT.startDate).int,
        activeTournamentTimeLeft = if activeT.isNil(): -1  else: timeLeft(activeT.endDate).int)

    w.updateTimer = pv.setInterval( 1, proc() = w.updateOnTimer())

    if currentUser().cheatsEnabled and w.cheatView.isNil:
        w.cheatView.new()
        w.cheatView.init(newRect(250.Coord, gapH, gapW * 3 + serviceButtonW * 2, gapH*2 + bottomH))
        w.cheatView.newTournamentsCheatButtons(w)
        pv.addSubview(w.cheatView)

    w.tutorialLogic()

method onInit*(w: TournamentsWindow) =
    w.updateSpan = 30
    w.updateCountdown = w.updateSpan
    let content = newLocalizedNodeWithResource("common/gui/popups/precomps/Tournament_window_layout.json")
    w.anchorNode.addChild(content)

    let toRemove = content.findNode("Tournament_placeholder$5")
    toRemove.removeFromParent()

    let tab = content.mandatoryNode("tabactive492px")
    tab.enabled = true
    tab.mandatoryNode("title_unactive").enabled = false
    tab.mandatoryNode("title_active").getComponent(Text).text = localizedString("TR_BUTTON_TITLE")
    tab.positionX = (tab.positionX + content.mandatoryNode("tabactive492px$7").positionX) / 2

    content.mandatoryNode("tabactive492px$7").enabled = false
    content.mandatoryNode("button_down").enabled = false
    content.mandatoryNode("button_up").enabled = false
    content.mandatoryNode("button_circle").enabled = false
    content.mandatoryNode("scrollbar_tournament.png").enabled = false
    #content.mandatoryNode("ltp_scrollbar_part1.png").enabled = false
    content.mandatoryNode("button_black_long").enabled = false
    #let btnClose = win.findNode("button_close")

    w.boostMultiplier = content.mandatoryNode("ltp_rectangle_26_copy_2.png").addTpBoostMultiplier(newVector3(214.0, -27.0, 0.0), 0.8)

    let btnClose = content.findNode("button_close")
    let closeAnim = btnClose.animationNamed("press")
    let bcp = w.anchorNode.newChild("close_animButton_parent")
    let buttonClose = bcp.createButtonComponent(closeAnim, newRect(btnClose.positionX + 10.0, btnClose.positionY + 10.0, 80.0, 80.0))
    buttonClose.onAction do():
        let active = w.findActiveTournament()
        let activeName = if active.isNil: "" else: active.title
        let activeTimeLeft = timeLeft(if active.isNil: 0.0 else: active.endDate).int div 60
        let next = w.findNextTournament()
        let nextName = if next.isNil: "" else: next.title
        let timeToNext = timeLeft(if next.isNil: 0.0 else: next.startDate).int div 60
        sharedAnalytics().wnd_tournaments_closed(nextName, activeName, timeToNext, activeTimeLeft)

        w.closeButtonClick()

    let itemPlaceholder = content.findNode("Tournament_placeholder")
    w.itemsRoot = newNode()
    w.itemsRoot.name = "itemsRoot"
    w.itemsRoot.positionX = 240
    w.itemsRoot.positionY = 220
    #itemPlaceholder.parent.addChild(w.itemsRoot)
    itemPlaceholder.parent.insertChild(w.itemsRoot, 5)
    w.firstItemPos = itemPlaceholder.position - w.itemsRoot.position
    w.itemAnchor = itemPlaceholder.anchor
    w.itemGap = itemPlaceholder.anchor.y * 2
    itemPlaceholder.removeFromParent()

    w.scroller = createNodeScroll(newRect(0, 0, itemPlaceholder.anchor.x * 2, w.itemGap * 2), w.itemsRoot)
    w.scroller.nodeSize = newSize(itemPlaceholder.anchor.x * 2, w.itemGap)
    w.scroller.scrollDirection = NodeScrollDirection.vertical
    w.scroller.bounces = true
    w.scroller.notDrawInvisible = true

    let btnDown = content.findNode("button_down")
    let downAnim = btnDown.animationNamed("press")
    let bdp = w.anchorNode.newChild("down_animButton_parent")
    let buttonDown = bdp.createButtonComponent(downAnim, newRect(btnDown.positionX + 10.0, btnDown.positionY + 10.0, 80.0, 80.0))
    buttonDown.onAction do():
        echo "down"

    let btnUP = content.findNode("button_up")
    let upAnim = btnUP.animationNamed("press")
    let bup = w.anchorNode.newChild("up_animButton_parent")
    let buttonUp = bup.createButtonComponent(upAnim, newRect(btnUP.positionX + 10.0, btnUP.positionY + 10.0, 80.0, 80.0))
    buttonUp.onAction do():
        echo "up"

    let tp = currentUser().tournPoints
    content.findNode("tournament_points").component(Text).text = $tp

    if tp == 0:
        sharedServer().getTutorialTournament proc(res: JsonNode) =
            handleTournamentsResponse(w, res)
    else:
        sharedServer().getTournamentsList nil, proc(res: JsonNode) =
            handleTournamentsResponse(w, res)

    # tw.applyFrameData()


proc toggleTournamentsView*(pv: GameScene, s: Server) =
    let w = sharedWindowManager().show(TournamentsWindow)


method beforeRemove*(w: TournamentsWindow) =
    if not w.cheatView.isNil:
        w.cheatView.removeFromSuperview()
        w.cheatView = nil

    if not w.boostMultiplier.isNil:
        w.boostMultiplier.onRemoved()
        w.boostMultiplier = nil


method onShowed*(w: TournamentsWindow) =
    procCall w.WindowComponent.onShowed()
    # w.anchorNode.sceneView.GameScene.setTimeout(0.5) do():
