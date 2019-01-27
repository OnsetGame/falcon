import rod.rod_types
import rod.node
import rod.viewport
import rod.component
import rod.component.text_component
import rod.component.ui_component
import rod.component.solid
import rod.component.sprite
import rod.component.ae_composition

import nimx.button
import nimx.matrixes
import nimx.animation
import nimx.notification_center
import nimx.formatted_text
import nimx.font
import quest / [quests, quests_actions]
import quest.quest_helpers
import falconserver.quest.quest_types
import falconserver.common.currency
# import falconserver.map.building.builditem
# import falconserver.quest.quests_config
import gui_module

import shared.user
import core.net.server
import shared.localization_manager
import shared.window.button_component

import utils.falcon_analytics
import utils.game_state
import utils.helpers
import utils.timesync
import utils.icon_component
import times

import quest.quest_icon_component

const whiteColor = newColor(1.0, 1.0, 1.0)
const guiColor   = newColor(1.0, 0.87, 0.56)
const btnRect = newRect(10, 10, 260, 80)

type
    QuestBar* = ref object of RootObj
        node*: Node
        quest*: Quest
        btnGo*: ButtonComponent
        onQuestUpdated*: proc(q: Quest)

    QuestBarDaily* = ref object of QuestBar
    QuestBarStory* = ref object of QuestBar
        timerAnim*: Animation


method init*(qb: QuestBar) {.base.} = discard
method applyQuestState*(qb: QuestBar, q: Quest, onBtnClicked: proc(q: Quest)) {.base.} = discard
method onRemove*(qb: QuestBar) {.base.} = discard

proc createQuestBar*(q: Quest): QuestBar=
    var compPath:string
    result = new(QuestBarStory)
    compPath = "common/gui/popups/precomps/quest_placeholder.json" #questbar_Story

    result.node = newLocalizedNodeWithResource(compPath)
    result.quest = q

proc sendOpenQuestAnalytic(quest: Quest) =
    let user = currentUser()
    var id: string

    if quest.kind == QuestKind.Story:
        id = $quest.id
    else:
        if not hasGameState($quest.id & SINCE_QUESTS_OPENED, ANALYTICS_TAG):
            var initVal: int
            setGameState($quest.id & SINCE_QUESTS_OPENED, initVal, ANALYTICS_TAG)
        id = quest.getIDForTask()

    let state = $quest.id & BUTTON_GO_QUEST_CLICKED
    if not hasGameState(state, ANALYTICS_TAG):
        sharedAnalytics().quest_paid(quest.config.name, "panel", sharedQuestManager().activeQuestsCount(), user.chips, user.parts, user.bucks)
        setGameState(state, true, ANALYTICS_TAG)

method init*(qb: QuestBarStory)=
    let quest = qb.quest
    var locKey = $quest.id
    if not quest.config.isNil:
        locKey = quest.config.name
    qb.node.findNode("text_title").component(Text).text = localizedString(locKey & "_TITLE")
    qb.node.findNode("text_description").component(Text).text = getFullDescription(quest.description)

    if not quest.config.isMain:
        qb.node.findNode("main_back").removeFromParent()
        qb.node.findNode("window_back_main").alpha = 0.0
    else:
        qb.node.findNode("window_back").alpha = 0.0

    let rewardsNode = qb.node.findNode("reward_icon")

    let container = qb.node.findNode("ellipse_paper_inactive")
    let comp = container.addComponent(QuestIconComponent)
    comp.configure do():
        comp.quest = quest
        comp.iconImageType = qiitDouble
        comp.mainNode = qb.node.findNode("ellipse_paper_big")
        comp.mainRect = newRect(130.0, 90.0, 280.0, 280.0)
        comp.secondaryNode = qb.node.findNode("ellipse_paper_small")
        comp.secondaryRect = newRect(86.0, 79.0, 90.0, 90.0)

proc setCompleted(qb: QuestBarStory, show: bool)=
    # qb.node.findNode("rewards_shape").removeFromParent()
    let rewards = qb.node.findNode("reward_icon")
    let completed = newLocalizedNodeWithResource("common/gui/popups/precomps/questbar_story_completed.json")
    completed.position = newVector3(-110.0, -30.0, 0.0)
    rewards.addChild(completed)

    let scene = qb.node.sceneView
    var shapes = newSeq[Node]()
    for i in 0..9:
        let shape = completed.findNode("shape" & $i)
        if not shape.isNil:
            shapes.add(shape)

    let complAnim = completed.animationNamed("play")
    if show:
        var delayAnim = newAnimation()
        delayAnim.loopDuration = 0.5
        delayAnim.numberOfLoops = 1

        var metaAnim = newMetaAnimation(delayAnim, complAnim)
        metaAnim.numberOfLoops = 1

        complAnim.chainOnAnimate do(p:float):
            for shape in shapes:
                if shape.alpha > 0.0 and shape.animationNamed("play").startTime == 0.0:
                    scene.addAnimation(shape.animationNamed("play"))


        scene.addAnimation(metaAnim)
    else:
        complAnim.onProgress(1.0)

method onRemove*(qb: QuestBarStory)=
    if not qb.timerAnim.isNil:
        qb.timerAnim.cancel()


proc hideAllElements(qb: QuestBarStory) =
    qb.node.findNode("bttn_get_reward").alpha = 0.0
    qb.node.findNode("bttn_green").alpha = 0.0
    qb.node.findNode("bttn_orange").alpha = 0.0
    qb.node.findNode("bttn_complete").alpha = 0.0

    qb.node.findNode("bttn_get_reward").getComponent(ButtonComponent).enabled = false
    qb.node.findNode("bttn_green").getComponent(ButtonComponent).enabled = false
    qb.node.findNode("bttn_orange").getComponent(ButtonComponent).enabled = false
    qb.node.findNode("bttn_complete").getComponent(ButtonComponent).enabled = false

    qb.node.findNode("timer_holder").alpha = 0.0
    qb.node.findNode("complete_anchor").alpha = 0.0
    qb.node.findNode("txt_speed_up").alpha = 0.0
    qb.node.findNode("reward_anchor").alpha = 0.0

method clickGo*(qb: QuestBar) {.base.} =
    qb.btnGo.sendAction()

method applyQuestState*(qb: QuestBarStory, quest: Quest, onBtnClicked: proc(q: Quest))=
    let btnReward = qb.node.findNode("bttn_get_reward").getComponent(ButtonComponent)
    let btnGo = qb.node.findNode("bttn_green").getComponent(ButtonComponent)
    let btnSpeedUp = qb.node.findNode("bttn_orange").getComponent(ButtonComponent)
    let btnComplete = qb.node.findNode("bttn_complete").getComponent(ButtonComponent)
    let q = quest
    qb.btnGo = btnGo

    # let questIconsNode = qb.node.findNode("Quest_Icon") #not_used
    let scene = qb.node.sceneView
    let showAnim = qb.node.animationNamed("show")
    if quest.id in sharedQuestManager().preferences.newStory:
        scene.addAnimation(showAnim)
    else:
        showAnim.onProgress(1.0)

    # if not qb.timerAnim.isNil:
    #     qb.timerAnim.cancel()

    qb.hideAllElements()

    case quest.status:
    of QuestProgress.Ready:
        btnGo.node.alpha = 1.0
        btnGo.enabled = true

        if q.config.currency == Currency.Parts:
            btnGo.node.findNode("icon_placeholder").component(IconComponent).name = "parts"
        else:
            btnGo.node.findNode("icon_placeholder").component(IconComponent).name = "tourPoints"
        btnGo.node.findNode("icon_placeholder").component(IconComponent).hasOutline = true

        btnGo.title = $q.config.price
        btnGo.onAction do():
            sharedAnalytics().quest_open(quest.config.name, currentUser().parts, quest.config.price)
            onBtnClicked(q)

        if q.config.time == 0.0:
            qb.node.findNode("timer_holder").enabled = false
            btnGo.node.positionY = 0.0
        else:
            btnGo.node.positionY = 44.0
            let timerNode = qb.node.findNode("timer_holder")
            timerNode.alpha = 1.0
            timerNode.findNode("ltp_clock").alpha = 1.0
            timerNode.findNode("ltp_clock_flash").alpha = 0.0
            timerNode.findNode("text_title_timer").component(Text).text = buildTimerString(formatDiffTime(q.config.time))

    of QuestProgress.InProgress:
        btnSpeedUp.node.alpha = 1.0
        btnSpeedUp.enabled = true
        qb.node.findNode("timer_holder").alpha = 1.0
        qb.node.findNode("txt_speed_up").alpha = 1.0
        qb.node.findNode("txt_speed_up").getComponent(Text).text = localizedString("SUW_BTTN_SPEEDUP")

        var initTime = q.config.time
        let timerNode = qb.node.findNode("timer_holder")
        timerNode.findNode("ltp_clock").alpha = 0.0
        timerNode.findNode("ltp_clock_flash").alpha = 1.0
        let timerText = timerNode.findNode("text_title_timer").component(Text)

        timerText.text = buildTimerString(formatDiffTime(initTime))
        btnSpeedUp.onAction do():
            onBtnClicked(q)

        btnSpeedUp.title = $q.speedUpPrice()

        if q.config.timeToEnd > 0.0 and qb.timerAnim.isNil:
            var timerAnim = newAnimation()
            timerAnim.loopDuration = q.config.timeToEnd
            timerAnim.numberOfLoops = 1
            timerAnim.onAnimate = proc(p: float)=
                timerText.text = buildTimerString(formatDiffTime(q.config.timeToEnd))
                btnSpeedUp.title = $q.speedUpPrice()

            qb.node.addAnimation(timerAnim)
            timerAnim.addLoopProgressHandler(1.0, false) do():
                if not qb.onQuestUpdated.isNil:
                    sharedQuestManager().updateQuests() do():
                        qb.onQuestUpdated(q)

            qb.timerAnim = timerAnim
        # else:
        #     sharedQuestManager().updateQuests() do():
        #         if not qb.onQuestUpdated.isNil:
        #             qb.onQuestUpdated(q)

    of QuestProgress.GoalAchieved:
        btnComplete.node.alpha = 1.0
        btnComplete.enabled = true
        btnComplete.title = "Complete!"
        btnComplete.onAction do():
            onBtnClicked(q)

        qb.node.findNode("complete_anchor").alpha = 1.0

    of QuestProgress.Completed:
        btnReward.node.alpha = 1.0
        btnReward.enabled = true
        qb.node.findNode("reward_anchor").alpha = 1.0

        qb.setCompleted(q.showCompleted)
        q.showCompleted = false
        btnReward.title = localizedString("QM_GET_REWARD")
        btnReward.onAction do():
            sharedAnalytics().quest_get_reward(quest.config.name, "quests_window")
            onBtnClicked(q)
    else:
        discard

