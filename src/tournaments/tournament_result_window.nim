import times
import json
import strutils

import nimx.matrixes
import nimx.formatted_text

import rod.rod_types
import rod.viewport
import rod.node
import rod.component
import rod.component.text_component
import rod.component.ae_composition
import rod.component.ui_component

import falconserver.map.building.builditem

import tournament

import shared.user
import shared.localization_manager
import shared.window.window_component
import shared.window.button_component
import shared.window.window_manager

import utils.falcon_analytics
import utils.helpers

import rod.component.solid
import nimx.types
import utils.icon_component

type TournamentResultWindow* = ref object of WindowComponent
    window*: Node
    tournament: Tournament
    currInfoPanel: Node


proc setUpTournament*(w: TournamentResultWindow, t: Tournament)


proc hideAllTournamentInfo(w: TournamentResultWindow) =
    w.window.mandatoryNode("rest").alpha = 0.0
    w.window.mandatoryNode("silver").alpha = 0.0
    w.window.mandatoryNode("winner").alpha = 0.0


method onInit*(w: TournamentResultWindow) =
    let win = newLocalizedNodeWithResource("common/gui/popups/precomps/tournament_results.json")
    w.anchorNode.addChild(win)
    w.window = win
    win.mandatoryNode("Tournament_results_title").getComponent(Text).text = localizedString("TR_RW_TITLE")
    win.mandatoryNode("ltp_glow").addRotateAnimation(40)

    let bttnReward = win.mandatoryNode("get_reward_orange_button").getComponent(ButtonComponent)
    bttnReward.title = localizedString("LEVELUP_GETREWARD")
    bttnReward.onAction do():
        sharedAnalytics().tournament_get_reward(w.tournament.title, w.tournament.place, w.tournament.rewardPoints, w.tournament.rewardChips, w.tournament.rewardBucks)
        w.closeButtonClick()

    w.hideAllTournamentInfo()


proc showTournamentInfo(w: TournamentResultWindow, place: int) =
    if place == 1:
        w.currInfoPanel = w.window.mandatoryNode("winner")
    elif place > 1 and place < 5:
        w.currInfoPanel = w.window.mandatoryNode("silver")
    else:
        w.currInfoPanel = w.window.mandatoryNode("rest")
    w.currInfoPanel.alpha = 1.0


proc setUpTournament*(w: TournamentResultWindow, t: Tournament) =
    w.tournament = t

    sendEvent("tournament_result_show", %*{
        "current_tournament_id": w.tournament.title,
        "current_position": w.tournament.place,
        "is_prize": w.tournament.isPrizePlace(),
        "chips_reward": w.tournament.rewardChips})

    let myName = if currentUser().name.len() <= 0: "Player" else: currentUser().name
    w.window.mandatoryNode("txt_tournament_name").getComponent(Text).text = t.title
    w.window.mandatoryNode("txt_tournament_data").getComponent(Text).text = t.startDate.fromSeconds().getLocalTime().format("d MMM yyyy")

    w.showTournamentInfo(t.place)
    w.currInfoPanel.mandatoryNode("txt_place").getComponent(Text).text = "# $1<span style=\"color:FFDF90FF;fontSize:24\">/$2</span>" % [$t.place, $t.playersCount]
    w.currInfoPanel.mandatoryNode("txt_score").getComponent(Text).text = $t.myScore
    w.currInfoPanel.mandatoryNode("congratText").getComponent(Text).text = localizedFormat("TR_RW_CONGRAT", myName)

    # w.window.mandatoryNode("CANDYSLOT").alpha = (t.slotName == $candySlot).float32
    # w.window.mandatoryNode("BALLOONSLOT").alpha = (t.slotName == $balloonSlot).float32
    # w.window.mandatoryNode("DREAMTOWERSLOT").alpha = (t.slotName == $dreamTowerSlot).float32
    w.window.findNode("icon_placeholder").component(IconComponent).composition = "slot_logos_icons"
    w.window.findNode("icon_placeholder").component(IconComponent).name = $t.slotName


method showStrategy*(w: TournamentResultWindow) =
    w.node.alpha = 1.0
    let showWinAnimCompos = w.window.getComponent(AEComposition)
    showWinAnimCompos.play("show")


method hideStrategy*(w: TournamentResultWindow): float =
    result = 0.5
    w.node.hide(0.5)
    let hideWinAnimCompos = w.window.getComponent(AEComposition)
    hideWinAnimCompos.play("hide")


registerComponent(TournamentResultWindow, "windows")
