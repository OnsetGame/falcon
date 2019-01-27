import nimx / [ timer, animation, formatted_text, matrixes, types ]
import core / notification_center
import nimx / [ button, image ]
import rod / [ rod_types, node, component, viewport ]
import rod / component / [ text_component, ui_component, sprite ]

import shared / gui / [ gui_module_types, gui_pack ]
import shared / window / [ window_manager, window_component, button_component ]
import windows / quests / quest_window
import shared / [ game_scene, localization_manager, user, director ]
import quest / [ quests, quest_helpers, quest_icon_component ]

import utils / [ pause, rounded_component, falcon_analytics ]

import tilemap / tile_map


type NewQuestMessage* = ref object
    quest*: Quest
    scene*: GameScene
    message: Node
    timer: ControlledTimer
    observers: bool
    locKey: string
    idleAnim: Animation
    inAnim: Animation
    particle: Node

type QuestMessageController* = ref object
    messages: seq[NewQuestMessage]
    curMessage: NewQuestMessage
    lifeTimer: ControlledTimer

proc show*(nqm: NewQuestMessage, cb: proc(cancelled: bool) = nil)
proc hide*(nqm: NewQuestMessage, cb: proc(cancelled: bool) = nil)

proc newQuestMessageController*(nc: NotificationCenter): QuestMessageController =
    result = QuestMessageController.new()
    result.messages = newSeq[NewQuestMessage]()

    let qmc = result
    nc.addObserver("WINDOW_COMPONENT_TO_SHOW", qmc) do(v: Variant):
        if v.get(WindowComponent) of QuestWindow:
            qmc.messages.setLen(0)
            if not qmc.lifeTimer.isNil:
                qmc.curMessage.scene.clearTimer(qmc.lifeTimer)
                qmc.lifeTimer = nil

            if not qmc.curMessage.isNil:
                qmc.curMessage.hide()
                qmc.curMessage = nil

proc add*(qmc: QuestMessageController, message: NewQuestMessage) =
    qmc.messages.add(message)

proc deleteMessage(qmc: QuestMessageController, message: NewQuestMessage) =
    for i, m in qmc.messages:
        if m == message:
            qmc.messages.delete(i)
            return

proc update*(qmc: QuestMessageController) =
    if qmc.curMessage.isNil and qmc.messages.len() > 0:
        qmc.curMessage = qmc.messages[0]
        qmc.curMessage.show()

        qmc.lifeTimer = qmc.curMessage.scene.setTimeout(3.0) do():
            qmc.lifeTimer = nil
            let cb = proc(cancelled: bool) =
                qmc.deleteMessage(qmc.curMessage)
                qmc.curMessage = nil
                qmc.update()

            qmc.curMessage.hide(cb)


proc newNewQuestMessage*(rootNode: Node, quest: Quest): NewQuestMessage =
    result = NewQuestMessage.new()
    result.quest = quest
    let anchor = sharedWindowManager().windowsRoot()
    result.scene = rootNode.sceneView.GameScene

    let message = newNodeWithResource("common/gui/popups/precomps/new_quest_event.json")
    let glow = message.findNode("ltp_glow_copy")

    message.findNode("new_quest_text").getComponent(Text).text = localizedString("NQ_NEW_QUEST")
    var locKey = $quest.id
    if not quest.config.isNil:
        locKey = quest.config.name
    let titleTextNode = message.findNode("title_text")
    let titleText = titleTextNode.getComponent(Text)
    titleText.boundingSize = newSize(235.0, 90.0)
    titleText.truncationBehavior = tbEllipsis
    titleTextNode.anchor = newVector3(117.0, 40.0, 0)
    titleText.text = localizedString(locKey & "_TITLE")

    anchor.insertChild(message, 3)

    let container = message.findNode("container_quest")
    let comp = container.component(quest_icon_component.QuestIconComponent)
    comp.configure do():
        comp.quest = quest
        comp.iconImageType = qiitSingle
        comp.mainRect = newRect(0.0, 0.0, 200.0, 200.0)

    result.message = message
    result.locKey = locKey
    result.idleAnim = glow.animationNamed("idle")
    result.inAnim = glow.animationNamed("in")
    result.idleAnim.numberOfLoops = -1

    let card = message.findNode("new_quest_event_pp.png")
    let bttn = card.createButtonComponent(nil, newRect(0, 0, 256, 380))
    # bttn.onAction do():
    #     card.removeComponent(bttn)
    #     currentNotificationCenter().postNotification("NewQuestMessage_click")


proc hide*(nqm: NewQuestMessage, cb: proc(cancelled: bool) = nil) =
    if nqm.message.isNil:
        return

    if not nqm.timer.isNil:
        nqm.scene.clearTimer(nqm.timer)
        nqm.timer = nil

    let anim = nqm.message.animationNamed("hide")
    anim.onComplete do():
        nqm.message.removeFromParent()
        if not cb.isNil:
            cb(anim.isCancelled)
    nqm.scene.addAnimation(anim)
    nqm.idleAnim.cancel()
    nqm.inAnim.cancel()


proc show*(nqm: NewQuestMessage, cb: proc(cancelled: bool) = nil) =
    if nqm.message.isNil:
        return

    if not nqm.timer.isNil:
        nqm.scene.clearTimer(nqm.timer)
        nqm.timer = nil

    let anim = nqm.message.animationNamed("show")
    anim.onComplete do():
        if not cb.isNil:
            cb(anim.isCancelled)
        nqm.scene.addAnimation(nqm.inAnim)
        nqm.particle = newNodeWithResource("common/particles/prt_glow_scene.json")
        nqm.message.findNode("particle_anchor").addChild(nqm.particle)
        nqm.inAnim.onComplete do():
            nqm.scene.addAnimation(nqm.idleAnim)

    nqm.scene.addAnimation(anim)
    sharedAnalytics().quest_show(nqm.locKey, currentUser().parts)