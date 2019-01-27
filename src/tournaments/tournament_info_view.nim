import tables
import times

import nimx.view
import nimx.button
import nimx.matrixes
import nimx.text_field
import nimx.panel_view
import nimx.animation

import rod.rod_types
import rod.viewport
import rod.node
import rod.component

import json

import unicode

import rod.component.ui_component
import nimx.table_view
import nimx.scroll_view
import nimx.event
import strutils
import core / notification_center

import nimx.formatted_text

import shared.user
import core.net.server
import shared.director
import shared.game_scene
import shared.shared_gui
import shared.window.window_component
import shared.window.button_component
import shared.window.window_manager
import shared.chips_animation
import shared.tutorial

import utils.falcon_analytics
import utils.helpers

import algorithm

import nimx.utils.lower_bound
import utils.timesync

import tournament

import rod.component.text_component
import shared.window.button_component

import shared.localization_manager

import falconserver.tournament.rewards
import falconserver.map.building.builditem

import rod.component.solid
import nimx.types
import utils.icon_component

import shared.gui.gui_module
import shared.gui.gui_module_types

import core / flow / flow_state_types
import core / helpers / boost_multiplier
import core / zone
import core / features / booster_feature


const showCompetitorsCount = 4

type ParticipantView* = ref object
    participation: Participation
    node: Node
    place: Text
    name: Text
    score: Text
    placeMine: Text
    nameMine: Text
    scoreMine: Text
    stripe: Node
    crownMine: Node
    crown: Node


proc newParticipantView(node: Node): ParticipantView =
    result.new()
    result.node = node

    result.place = node.mandatoryNode("curr_place").getComponent(Text)
    result.name = node.mandatoryNode("other_name").getComponent(Text)
    result.score = node.mandatoryNode("score").getComponent(Text)

    result.placeMine = node.mandatoryNode("curr_place").getComponent(Text)
    result.nameMine = node.mandatoryNode("player_name").getComponent(Text)
    result.scoreMine = node.mandatoryNode("score").getComponent(Text)

    result.crownMine = node.mandatoryNode("crown_s")
    result.crown = node.mandatoryNode("crown_s$2")

    result.stripe = node.mandatoryNode("stripe")

type RewardItem = ref object
    node: Node
    place: Text
    reward: Text
    placeMine: Text
    rewardMine: Text

proc newRewardItem(node: Node, t: Tournament): RewardItem =
    result.new()
    result.node = node

    result.reward = node.mandatoryNode("not_win_numbers").getComponent(Text)
    result.rewardMine = node.mandatoryNode("win_numbers").getComponent(Text)
    if t.prizeFundBucks > 0:
        node.mandatoryNode("bucks_placeholder").alpha = 1.0
        node.mandatoryNode("chips_placeholder").alpha = 0.0
    else:
        node.mandatoryNode("chips_placeholder").alpha = 1.0
        node.mandatoryNode("bucks_placeholder").alpha = 0.0

type TournamentInfoView2* = ref object of GUIModule
    tournament: Tournament
    participantSlots: seq[ParticipantView]
    rewardSlots: seq[RewardItem]
    title: Text
    participantsCount: Text
    totalPlaces: Text
    fullView: Node

    compactView: Node
    compactPlace: Text
    compactScore: Text

    participantsTab: Node
    participantsTabHighlight: Node
    participantsTabContent: Node
    prizesTab: Node
    prizesTabHighlight: Node
    prizesTabContent: Node

    competitorsUpdateTime: int
    competitorsTimer: int

    finished: bool

proc showParticipant(v: TournamentInfoView2, pv: ParticipantView, index: int) =
    if index < 0 or index >= v.tournament.sortedParticipants.len:
        pv.participation = nil
        pv.node.enabled = false
        return

    pv.node.enabled = true
    let p = v.tournament.sortedParticipants[index]
    var name = p.name
    let nameLen = name.runeLen()
    if nameLen <= 0:
        name = "Player"
    if nameLen > 7:
        name = name.runeSubStr(0, 6) & "..."

    pv.participation = p

    if p.id == v.tournament.participationId:
        pv.stripe.alpha = 1.0

        pv.name.node.alpha = 0.0
        pv.nameMine.node.alpha = 1.0
        pv.crown.alpha = 0.0
        pv.crownMine.alpha = 1.0

        pv.placeMine.text = $(index + 1)
        pv.nameMine.text = name
        pv.scoreMine.text = $p.score

    else:
        pv.stripe.alpha = 0.0

        pv.name.node.alpha = 1.0
        pv.nameMine.node.alpha = 0.0
        pv.crown.alpha = 1.0
        pv.crownMine.alpha = 0.0

        pv.place.text = $(index + 1)
        pv.name.text = name
        pv.score.text = $p.score


proc showReward(v: TournamentInfoView2, rew: RewardItem, placeFrom: int, placeTo: int, chipsReward: int64, isLast: bool = false) =
    rew.node.enabled = true
    var placeRangeText = "#" & (if placeFrom == placeTo: $placeFrom  else: $placeFrom & "-" & $placeTo)
    var suff = "#" & $placeFrom
    var alpha = 1.0
    if placeFrom != placeTo and placeFrom > 3:
        suff = if not isLast: "#4" else: "#5"
        alpha = 0.6


    for i in 1..5: rew.node.mandatoryNode("#" & $i).alpha = 0.0
    let numNode = rew.node.mandatoryNode(suff)
    numNode.alpha = alpha
    numNode.getComponent(Text).text = placeRangeText

    if placeFrom <= v.tournament.place and v.tournament.place <= placeTo:
        rew.rewardMine.text = $chipsReward
        rew.rewardMine.node.enabled = true
        rew.rewardMine.node.alpha = alpha
        rew.reward.node.enabled = false
    else:
        rew.reward.text = $chipsReward
        rew.rewardMine.node.enabled = false
        rew.reward.node.enabled = true
        rew.reward.node.alpha = alpha

proc calcReward(t: Tournament, place: int): int64 =
    if t.prizeFundBucks > 0:
        result = calcRewardCurrency(t.prizeFundBucks, t.participants.len, place)
    else:
        result = calcRewardCurrency(t.prizeFundChips, t.participants.len, place)

proc updateRewardsList(v: TournamentInfoView2) =
    var rewards = newSeq[int64]()
    var rewardPlaces = newSeq[int]()
    rewards.add(calcReward(v.tournament, 1))
    rewardPlaces.add(1)
    for place in 2 .. v.tournament.participants.len:
        let reward = calcReward(v.tournament, place)
        if reward == 0:
            break
        if rewards[^1] != reward:
            rewards.add(reward)
            rewardPlaces.add(place)
        else:
            rewardPlaces[^1] = place

    let silver = v.prizesTabContent.mandatoryNode("crown_silver")
    silver.enabled = false
    let bronze = v.prizesTabContent.mandatoryNode("crown_bronze")
    bronze.enabled = false

    v.showReward(v.rewardSlots[0], 1, rewardPlaces[0], rewards[0])
    var lim = min(rewards.len, v.rewardSlots.len)
    for i in 1 ..< lim:
        if i == 1: silver.enabled = true
        elif i == 2: bronze.enabled = true
        v.showReward(v.rewardSlots[i], rewardPlaces[i-1] + 1, rewardPlaces[i], rewards[i], i == lim-1)
    for i in lim ..< v.rewardSlots.len:
        v.rewardSlots[i].node.enabled = false

proc updatePlayersList(v: TournamentInfoView2) =
    v.tournament.sortParticipants()
    v.participantsCount.text = $v.tournament.playersCount
    v.totalPlaces.text = $v.tournament.playersCount

    let pos = v.tournament.place - 1
    var fromPos = max(pos - showCompetitorsCount div 2, 0)
    var toPos = fromPos + showCompetitorsCount + 1
    if toPos > v.tournament.sortedParticipants.len:
        fromPos = fromPos - (toPos - v.tournament.sortedParticipants.len)
        toPos = v.tournament.sortedParticipants.len
    for pos in fromPos ..< toPos:
        let slotIndex = pos - fromPos
        v.showParticipant(v.participantSlots[slotIndex], pos)

    v.compactPlace.text = $v.tournament.place
    v.compactScore.text = $v.tournament.sortedParticipants[pos].score

proc updateFromParticipantsResponse(v: TournamentInfoView2, res: JsonNode) =
    v.tournament.updateFromParticipantsResponse(res["response"], preserveScore = true)
    v.updatePlayersList()
    v.updateRewardsList()

proc newTournamentCheatsView*(superView: View, targetView: TournamentInfoView2, tournament: Tournament): View =
    if not currentUser().cheatsEnabled:
        return nil

    result.new

    let timerLabelH = 30.Coord
    let timerGapH = 15.Coord
    let labelH = 20.Coord
    let gapH = 5.Coord
    let bottomH = 40.Coord
    let serviceButtonW = 140.Coord
    let gapW = 10.Coord
    let h = gapH + timerLabelH + timerGapH + (showCompetitorsCount + 1) * (labelH + gapH) + gapH + bottomH
    let w = (serviceButtonW + gapW) * 3 - gapW

    result.init(newRect(200.Coord, 100.Coord, w, h))
    superView.addSubview(result)

    var x = 0.Coord
    var y = gapH

    let v = result
    let gainTournamentScoreBt = newButton(newRect(x, y, serviceButtonW, bottomH))
    gainTournamentScoreBt.title = "Gain score"
    result.addSubview(gainTournamentScoreBt)
    gainTournamentScoreBt.onAction do():
        sharedServer().gainTournamentScore(tournament.participationId, tournament.sinceTime, proc(res: JsonNode) =
            targetView.updateFromParticipantsResponse(res) )

    x += serviceButtonW + gapW

    let finishTournamentBt = newButton(newRect(x, y, serviceButtonW, bottomH))
    finishTournamentBt.title = "Finish tournament"
    result.addSubview(finishTournamentBt)
    finishTournamentBt.onAction do():
        sharedServer().finishTournament(tournament.id, proc(res: JsonNode) =
            targetView.updateFromParticipantsResponse(res) )

    x += serviceButtonW + gapW

    let inviteBotBt = newButton(newRect(x, y, serviceButtonW, bottomH))
    inviteBotBt.title = "Invite bot"
    result.addSubview(inviteBotBt)
    inviteBotBt.onAction do():
        sharedServer().inviteTournamentBots(tournament.id, proc(res: JsonNode) =
            targetView.updateFromParticipantsResponse(res) )


proc switchToPrizes(v: TournamentInfoView2, showPrizes: bool) =
    v.prizesTabContent.enabled = showPrizes
    v.participantsTabContent.enabled = not showPrizes

proc newTournamentInfoView2*(parent: Node, tournament: Tournament): TournamentInfoView2 =
    result.new
    result.tournament = tournament
    result.competitorsUpdateTime = 15
    result.competitorsTimer = 0

    result.rootNode = newNodeWithResource("common/gui/tournaments/precomps/tournamets.json")

    # ARROWS UP DOWN DISABLED
    result.rootNode.mandatoryNode("bar_full_list").mandatoryNode("down_button").enabled = false
    result.rootNode.mandatoryNode("bar_full_list").mandatoryNode("up_button").enabled = false


    parent.addChild(result.rootNode)

    result.fullView = result.rootNode.mandatoryNode("bar_full")
    result.compactView = result.rootNode.mandatoryNode("bar_compact")
    let r = result
    if tournament.boosted:
        let tpMult = r.compactView.addBoostMultiplier(newVector3(-16.0, -47, 0), 0.6)
        tpMult.text = boostMultiplierText(BoosterTypes.btTournamentPoints)
    else:
        let feature = findFeature(BoosterFeature)
        let activateBoost = proc() =
            for booster in feature.boosters:
                if booster.kind == BoosterTypes.btTournamentPoints and booster.isActive:
                    discard r.compactView.addBoostMultiplier(newVector3(-16.0, -47, 0), 0.6)
        feature.subscribe(parent.sceneView.GameScene, activateBoost)

    result.participantsCount = result.fullView.mandatoryNode("total_players").mandatoryChildNamed("total_players").getComponent(Text)
    result.totalPlaces = result.compactView.mandatoryNode("total_place").getComponent(Text)

    let tabs = result.fullView.mandatoryNode("bar_full")
    result.participantsTab = tabs.mandatoryNode("bar_full_list")
    result.participantsTab.alpha = 1.0
    result.participantsTabHighlight = result.participantsTab.mandatoryNode("bar_full_list").mandatoryNode("TOURNAMENTS_LIST")
    result.participantsTabContent = result.fullView.mandatoryNode("bar_full_list")
    if tournament.boosted:
        let tpMult = r.participantsTabContent.addBoostMultiplier(newVector3(217.0, -6, 0), 0.6)
        tpMult.text = boostMultiplierText(BoosterTypes.btTournamentPoints)
    else:
        let feature = findFeature(BoosterFeature)
        let activateBoost = proc() =
            for booster in feature.boosters:
                if booster.kind == BoosterTypes.btTournamentPoints and booster.isActive:
                    let tpMult = r.participantsTabContent.addBoostMultiplier(newVector3(217.0, -6, 0), 0.6)
                    tpMult.text = boostMultiplierText(BoosterTypes.btTournamentPoints)
        feature.subscribe(parent.sceneView.GameScene, activateBoost)

    result.prizesTab = tabs.mandatoryNode("bar_full_prizes")
    result.prizesTab.alpha = 1.0
    result.prizesTabHighlight = result.prizesTab.mandatoryNode("bar_full_prizes").mandatoryNode("TOURNAMENTS_PRIZES")
    result.prizesTabContent = result.fullView.mandatoryNode("bar_full_prizes")

    result.compactPlace = result.compactView.mandatoryNode("curr_place").getComponent(Text)
    result.compactScore = result.compactView.mandatoryNode("points").getComponent(Text)

    let v = result
    let buttonParticipants = result.participantsTab.mandatoryNode("list_prizes_button")
    buttonParticipants.createButtonComponent(newRect(120, -1.5, 130, 60)).onAction do():
        v.switchToPrizes(true)

    let buttonPrizes = result.prizesTab.mandatoryNode("list_prizes_button")
    buttonPrizes.createButtonComponent(newRect(-1, -1.5, 130, 60)).onAction do():
        v.switchToPrizes(false)

    result.switchToPrizes(false)

    let toggleAnim = result.rootNode.mandatoryNode("tournamets").animationNamed("toggle")
    var busy = false
    proc addTogleAnim(n: Node, lpPattern: LoopPattern = lpStartToEnd, cb: proc() = nil) =
        toggleAnim.loopPattern = lpPattern
        n.addAnimation(toggleAnim)
        busy = true
        toggleAnim.onComplete do():
            if not cb.isNil: cb()
            busy = false
            toggleAnim.removeHandlers()

    let compactView = result.compactView
    compactView.enabled = false

    let btnMinimize1 = result.prizesTab.mandatoryNode("collapse_button")
    let buttonMinimize1 = btnMinimize1.createButtonComponent(newRect(0, 0, 90.0, 136.0))
    buttonMinimize1.onAction do():
        if not busy:
            compactView.enabled = true
            btnMinimize1.addTogleAnim()
    let btnMinimize2 = result.participantsTab.mandatoryNode("collapse_button")
    let buttonMinimize2 = btnMinimize2.createButtonComponent(newRect(0, 0, 90.0, 136.0))
    buttonMinimize2.onAction do():
        if not busy:
            compactView.enabled = true
            btnMinimize2.addTogleAnim()
    let btnMaximize = result.compactView.mandatoryNode("sh_crown_stroke")
    let buttonMaximize = btnMaximize.createButtonComponent(newRect(-70,-70,140,140))
    buttonMaximize.onAction do():
        if not busy:
            btnMaximize.addTogleAnim(lpEndToStart) do():
                compactView.enabled = false

    result.participantSlots = @[]
    for i in 1..5:
        let v = newParticipantView(result.participantsTabContent.mandatoryNode("player_" & $i))
        result.participantSlots.add(v)
        v.nameMine.text = $i
        v.name.text = $i

    result.rewardSlots = @[]
    for i in 1..5:
        let r = newRewardItem(result.prizesTabContent.mandatoryNode("winner_" & $i), tournament)
        result.rewardSlots.add(r)

    result.updatePlayersList()
    result.updateRewardsList()

proc getTournamentParticleTarget(v: TournamentInfoView2): Node =
    for slot in v.participantSlots:
        if not slot.participation.isNil and slot.participation.id == v.tournament.participationId:
            return slot.node.mandatoryNode("player_info").mandatoryNode("score")

proc showScoreGain*(v: TournamentInfoView2, gs: GameScene, fromNode, parent: Node, stage: string) =
    v.updatePlayersList()
    v.updateRewardsList()
    let p = v.tournament.participants[v.tournament.participationId]
    let diff = v.tournament.scoreGain[stage]

    if diff > 0:
        let toNode = v.getTournamentParticleTarget()
        if not toNode.isNil:
            discard gs.tournamentPointsAnim(fromNode, toNode, parent, particlesCount = diff, oldBalance = p.score, newBalance = p.score + diff) do():
                v.tournament.applyOneScoreGain(stage)
                v.updatePlayersList()
        else:
            v.tournament.applyWholeScoreGain(stage)
            v.updatePlayersList()
            discard gs.tournamentPointsAnim(fromNode, v.participantsTabHighlight, parent, particlesCount = diff, oldBalance = p.score, newBalance = p.score + diff)

        tsTournamentInfoBarPoints.addTutorialFlowState()


proc requestCompetitorsUpdate(v: TournamentInfoView2) =
    sharedServer().getTournamentInfo(v.tournament.participationId, v.tournament.sinceTime, proc(res: JsonNode) =
        v.updateFromParticipantsResponse(res)
    )

type TournamentBlockerWindow* = ref object of WindowComponent
    content: Node
    goToMap: bool
    discard

method onInit*(w: TournamentBlockerWindow) =
    w.canMissClick = false
    w.content = newLocalizedNodeWithResource("common/gui/popups/precomps/Tournament_over.json")
    w.anchorNode.addChild(w.content)
    w.content.addAnimation(w.content.animationNamed("appear"))
    w.content.mandatoryNode("black_button_long").createButtonComponent(newRect(0, 0, 222*2, 42*2)).onAction do():
        currentNotificationCenter().postNotification("SET_EXIT_FROM_SLOT_REASON", newVariant("exit_tournament"))
        w.goToMap = true
        w.closeButtonClick()

method beforeRemove*(w: TournamentBlockerWindow) =
    procCall w.WindowComponent.beforeRemove()
    if w.goToMap:
        pushBack(TournamentShowWindowFlowState)
        directorMoveToMap()

proc setup*(w: TournamentBlockerWindow, t: Tournament) =
    let icoPlaceholder = w.content.findNode("icon_placeholder")
    let icoSolid = icoPlaceholder.getComponent(Solid)
    let icoComp = icoPlaceholder.component(IconComponent)
    icoComp.prefix = "common/lib/icons/precomps"
    icoComp.composition = "slot_logos_icons"
    icoComp.name = $t.slotName
    icoComp.rect = newRect(newPoint(0, 0), icoSolid.size)
    icoPlaceholder.removeComponent(Solid)
    w.content.findNode("TR_NAMED_TOURNAMENT_IS_OVER").getComponent(Text).text = localizedFormat("TR_NAMED_TOURNAMENT_IS_OVER", $t.title)

registerComponent(TournamentBlockerWindow, "windows")

proc update*(v: TournamentInfoView2): bool =
    let left = timeLeft(v.tournament.endDate)
    if left > 0:
        v.competitorsTimer.inc
        if v.competitorsTimer >= v.competitorsUpdateTime:
            v.competitorsTimer = 0
            v.requestCompetitorsUpdate()
    else:
        if not v.finished:
            v.finished = true
            sendEvent("tournament_end_popup_show", %*{
                "chips_left": %currentUser().chips,
                "current_tournament_id": v.tournament.title,
                "current_position": v.tournament.place,
                "is_prize": v.tournament.isPrizePlace()})

            let state = newFlowState(TournamentShowFinishFlowState, newVariant(v.tournament))
            pushBack(state)
            result = true
