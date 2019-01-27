import rod.rod_types
import rod.node
import rod.viewport
import rod.component
import rod.component.text_component
import rod.component.ui_component
import rod.component.ae_composition

import nimx.button
import nimx.matrixes
import nimx.animation
import nimx.control
import nimx.notification_center

import shared.user
import shared.game_scene
# import shared.base_slot_machine_view
import shared.localization_manager
import shared.window.window_component
import shared.window.button_component
import shared.director
import shafa / game / reward_types

import utils.sound_manager
import utils.helpers
import utils.falcon_analytics
import utils.game_state

import quest / [quest_helpers, quests, quests_actions]

import falconserver.auth.profile_types
import falconserver.common.game_balance

import strutils, logging

import narrative.narrative_character


type LevelUPWindow* = ref object of WindowComponent
    buttonReward*: ButtonComponent
    enabled*: bool
    window: Node
    rewards*: seq[Reward]
    character: NarrativeCharacter


method onInit*(luw: LevelUPWindow) =
    luw.enabled = true
    currentDirector().gameScene.setTimeout 1.0, proc() = luw.isBusy = false
    let win = newLocalizedNodeWithResource("common/gui/popups/precomps/level_up.json")
    luw.anchorNode.addChild(win)
    luw.window = win

    win.findNode("tab_middle").findNode("title").getComponent(Text).text = localizedString("LEVELUP_TITLE")

    let scene = luw.anchorNode.sceneView.GameScene
    scene.soundManager.sendEvent("COMMON_LEVELUP")

    luw.buttonReward = win.findNode("get_reward_orange_button").getComponent(ButtonComponent)
    luw.buttonReward.title = localizedString("LEVELUP_GETREWARD")
    luw.buttonReward.onAction do():
        luw.buttonReward.enabled = false

        var chips: int64
        var bucks: int64

        for r in luw.rewards:
            if r.kind == RewardKind.chips:
                chips = r.amount
            if r.kind == RewardKind.bucks:
                bucks = r.amount

        sharedAnalytics().level_up_get_reward(chips, bucks)

        sharedQuestManager().getLevelUpRewards(scene.sceneID()) do():
            luw.closeButtonClick()

    luw.character = luw.window.addComponent(NarrativeCharacter)
    luw.character.kind = NarrativeCharacterType.WillFerris
    luw.character.bodyNumber = 4
    luw.character.headNumber = 1


proc generateRewards*(w: LevelUPWindow, level: int) =
    let gb = sharedGameBalance()
    let lvlData = gb.levelProgress[level - 1]

    w.rewards = lvlData.rewards
    
    # check maxBet
    var maxBet: int64 = 0
    var maxBetIndex = -1
    for i, ol in gb.betsFromLevel:
        if level == ol:
            maxBetIndex = i
            break

        elif ol > level:
            maxBetIndex = -1
            break

    if maxBetIndex > 0 and maxBetIndex < gb.bets.len:
        maxBet = gb.bets[maxBetIndex]

    if maxBet > 0:
        w.rewards.add(createReward(RewardKind.maxBet, maxBet))

proc setUp*(w: LevelUPWindow, level: int) =
    let stn = w.window.findNode("level_up_stars")
    stn.findNode("text_lvl_prev").getComponent(Text).text = $(level - 1)
    stn.findNode("text_lvl_cur").getComponent(Text).text = $level

    w.generateRewards(level)

    let state = QUESTS_ON_LEVEL & $(level - 1)
    var questsOnLevel: int

    if hasGameState(state, ANALYTICS_TAG):
        questsOnLevel = getIntGameState(state,  ANALYTICS_TAG)

    sharedAnalytics().level_reached(level, activeSlots().len, questsOnLevel)

method showStrategy*(w: LevelUPWindow) =
    w.node.alpha = 1.0
    let showWinAnimCompos = w.window.getComponent(AEComposition)
    showWinAnimCompos.play("show")
    w.character.show(0.0)

method hideStrategy*(w: LevelUPWindow): float =
    w.character.hide(0.3)
    result = 0.3

method onShowed*(w: LevelUPWindow) =
    discard

registerComponent(LevelUPWindow, "windows")
