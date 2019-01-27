import rod.rod_types
import rod.node
import rod.viewport
import rod.component
import rod.component.text_component
import rod.component.ui_component
import rod.component.solid
import rod.quaternion

import nimx.button
import nimx.property_visitor
import nimx.animation
import nimx.matrixes
import nimx.notification_center

import utils.helpers
import shared.localization_manager
import shared.window.window_component
import shared.window.button_component
import quest.quests
import quest.quest_helpers

import utils.falcon_analytics
import utils.game_state
import falconserver.quest.quest_types

type CompleteQuestMsgWindow* = ref object of WindowComponent
    window: Node
    cards: Node
    quest: Quest
    isGoClicked: bool
    giveReward*: proc()
    cardsDestPos*: Vector3

proc goclick*(nq: CompleteQuestMsgWindow)

method onInit*(nq: CompleteQuestMsgWindow) =
    nq.isTapAnywhere = true
    nq.hasFade = true
    # nq.window = newLocalizedNodeWithResource("common/gui/popups/precomps/complete_quest.json")
    nq.anchorNode.addChild(nq.window)
    nq.window.findNode("NQ_TAP_TO_CCONTINUE").enabled = false

    let showWinAnim = nq.window.animationNamed("show")
    nq.window.addAnimation(showWinAnim)

    let barComplete = nq.window.findNode("questbar_story_completed")
    let showbarAnim = barComplete.animationNamed("play")
    nq.window.addAnimation(showbarAnim)

    nq.cards = nq.window.findNode("Quest_Card_Anim")
    let showCardsAnim = nq.cards.animationNamed("show")
    nq.window.addAnimation(showCardsAnim)
    nq.window.findNode("Light_Effect_Null").addRotateAnimation(40)

    showCardsAnim.onComplete do():
        nq.isBusy = false
        let idleCardsAnim = nq.cards.animationNamed("idle")
        idleCardsAnim.numberOfLoops = -1
        if not nq.window.sceneView.isNil:
            nq.window.addAnimation(idleCardsAnim)

        let idleWinAnim = nq.window.animationNamed("idle")
        idleWinAnim.numberOfLoops = -1
        if not nq.window.sceneView.isNil:
            nq.window.addAnimation(idleWinAnim)

    let btnGoNode = nq.window.findNode("button_green_yellow_")
    btnGoNode.findNode("title").component(Text).text = localizedString("CQ_GET_REWARD")
    let btnGo = btnGoNode.createButtonComponent(btnGoNode.animationNamed("press"), newRect(5,5,300,90))
    btnGo.onAction do():
        nq.isGoClicked = true
        nq.goclick()

    nq.createLockTouchesView(newRect(0, 0, 1000, 800))

proc setUpQuest*(nq: CompleteQuestMsgWindow, q: Quest) =
    nq.quest = q
    var locKey = $q.id
    if not q.config.isNil:
        locKey = q.config.name
    nq.window.findNode("NQ_QuestNameText").getComponent(Text).text = localizedString(locKey & "_TITLE")
    nq.window.findNode("NQ_QuestDescText").getComponent(Text).text = localizedString(locKey & "_SHORT_DESC_END")

    let icons = nq.cards.findNode("quest_card")
    for ch in icons.children:
        if ch.name != "bg" and ch.name != storyQuestIcon(q.id):
            ch.alpha = 0.0

proc goclick*(nq: CompleteQuestMsgWindow) =
    nq.isBusy = true

    let hideWinAnim = nq.window.animationNamed("hide")
    nq.window.addAnimation(hideWinAnim)

    let hideCardsAnim = nq.cards.animationNamed("hide")
    nq.window.addAnimation(hideCardsAnim)
    nq.window.findNode("Light_Effect_Null").addRotateAnimation(40)

    hideCardsAnim.onComplete do():
        nq.node.alpha = 0.0
        nq.closeButtonClick()

    # fly cards to target
    hideCardsAnim.addLoopProgressHandler(0.5, false) do():
        let move_anim = newAnimation()
        move_anim.numberOfLoops = 1
        move_anim.loopDuration = 0.5 * hideCardsAnim.loopDuration
        let first_card = nq.window.findNode("Null 29")
        let second_card = nq.window.findNode("Null 30")
        let first_start_pos = first_card.position
        let second_start_pos = second_card.position
        var dst_pos = nq.cardsDestPos + newVector3(55, 100, 0)
        dst_pos.z = 0
        move_anim.onAnimate = proc(p: float) =
            first_card.position = interpolate(first_start_pos, dst_pos, p)
            second_card.position = interpolate(second_start_pos, dst_pos, p)

        nq.window.addAnimation(move_anim)

method beforeRemove*(nq: CompleteQuestMsgWindow) =
    if nq.isGoClicked and not nq.giveReward.isNil:
        nq.giveReward()

method onShowed*(nq: CompleteQuestMsgWindow) =
    discard

method hideStrategy*(nq: CompleteQuestMsgWindow): float =
    return TIME_TO_SHOW_WINDOW

method visitProperties*(nq: CompleteQuestMsgWindow, p: var PropertyVisitor) =
    p.visitProperty("isGoClicked", nq.isGoClicked)

registerComponent(CompleteQuestMsgWindow, "windows")