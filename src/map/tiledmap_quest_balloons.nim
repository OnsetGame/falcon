import boolseq, tables, variant
import nimx / [types, matrixes]
import rod / node

import tiledmap_actions
import balloons / [quest_balloon, quest_ready_balloon, quest_inprogress_balloon, quest_goalachieved_balloon, quest_completed_balloon]

import quest / [quests, quests_actions]
import core / [zone, notification_center]
import core / helpers / sound_helper

import shared / [user, game_scene, tutorial]
import windows / store / store_window
import utils / [helpers, falcon_analytics, game_state]

import platformspecific / android / rate_manager

import shared / window / [window_manager, rewards_window, button_component]

type MapQuestMenuItem = ref object
    questId: int
    questInd: int
    status: QuestProgress
    zonePosition: Vector3
    questPosition: Vector3
    balloon: QuestBalloon


proc `scale=`*(m: MapQuestMenuItem, sc: Vector3) =
    if not m.balloon.isNil:
        m.balloon.node.scale = sc


proc show*(m: MapQuestMenuItem, cb: proc() = nil) =
    if not m.balloon.isNil:
        m.balloon.show(cb)
    else:
        if not cb.isNil:
            cb()


proc hide*(m: MapQuestMenuItem, cb: proc() = nil) =
    if not m.balloon.isNil:
        m.balloon.hide(cb)
    else:
        if not cb.isNil:
            cb()


proc destroy*(m: MapQuestMenuItem, cb: proc() = nil) =
    if not m.balloon.isNil:
        m.balloon.destroy(cb)
        m.balloon = nil
    else:
        if not cb.isNil:
            cb()


proc newMapQuestMenuItem(parent: Node, q: Quest, questxy, zonexy, scale: Vector3): MapQuestMenuItem =
    result = MapQuestMenuItem.new()
    result.questId = q.id
    result.questInd = q.config.id - 1
    result.status = q.status
    result.zonePosition = zonexy
    result.questPosition = questxy

    let item = result
    case q.status:
        of QuestProgress.Ready:
            item.balloon = newQuestReadyBalloon(parent, q)
            item.balloon.onAction = proc() =
                item.balloon.node.dispatchAction(OpenQuestCardAction, newVariant(q))

        of QuestProgress.InProgress:
            item.balloon = newQuestInProgressBalloon(parent, q)
            item.balloon.onAction = proc() =
                item.balloon.node.dispatchAction(OpenQuestCardAction, newVariant(q))

        of QuestProgress.GoalAchieved:
            item.balloon = newQuestGoalAchievedBalloon(parent, q)
            item.balloon.onAction = proc() =
                item.balloon.hide()
                item.balloon.node.dispatchAction(TryToCompleteQuestAction, newVariant(q)) do(success: bool):
                    if not success:
                        item.balloon.show()

        of QuestProgress.Completed:
            item.balloon = newQuestCompletedBalloon(parent, q)
            item.balloon.onAction = proc() =
                item.balloon.hide()
                item.balloon.node.dispatchAction(TryToGetRewardsQuestAction, newVariant(q)) do(success: bool):
                    if not success:
                        item.balloon.show()

        else:
            return

    result.balloon.node.position = questxy
    result.balloon.node.scale = scale


type MapQuestBubbles* = ref object
    items*: Table[string, MapQuestMenuItem]
    scale: Vector3
    node*: Node
    onOpenCard*: proc()


proc `scale=`*(m: MapQuestBubbles, sc: Vector3) =
    # let sc = newVector3(sc.x * 0.75, sc.y * 0.75, sc.z)

    m.scale = sc
    for item in m.items.values():
        item.scale = sc


proc createBubbleFor*(m: MapQuestBubbles, quest: Quest, questxy, zonexy: Vector3, cb: proc(created: bool) = nil) =
    var created = false
    let zone = quest.config.targetName
    var item = m.items.getOrDefault(zone)
    let completedQuests = currentUser().questsState

    if item.isNil:
        # Balloon for quest does not exists
        let item = newMapQuestMenuItem(m.node, quest, questxy, zonexy, m.scale)
        item.balloon.node.name = item.balloon.node.name & "_" & zone
        m.items[zone] = item
        if not cb.isNil:
            cb(true)
        created = true
    elif
        # Balloon has been destroyed
            item.balloon.isNil or
        # Balloon for quest has been absolete
            (item.questId == quest.id and item.status != quest.status) or
        # Quest has been completed show other balloon for this zone
            (item.questId != quest.id and completedQuests.len > item.questInd and completedQuests[item.questInd]):
        let b = newMapQuestMenuItem(m.node, quest, questxy, zonexy, m.scale)
        b.balloon.node.name = b.balloon.node.name & "_" & zone
        created = true
        m.items[zone] = b
        item.destroy() do():
            if not cb.isNil:
                cb(true)

    # Hide balloons for completed quests
    var i = 0
    for key, item in m.items:
        if item.balloon.isNil or (completedQuests.len > item.questInd and completedQuests[item.questInd]):
            item.destroy()
            m.items.del(key)
        else:
            i.inc

    if not created:
        cb(false)


proc isBubbleOpenedFor*(m: MapQuestBubbles, quest: Quest): bool =
    let targetName = quest.config.targetName
    let item = m.items.getOrDefault(targetName)
    if item.isNil:
        return
    result = item.status == quest.status and not item.balloon.isHidden


proc showBubbleFor*(m: MapQuestBubbles, quest: Quest, cb: proc() = nil) =
    var item = m.items.getOrDefault(quest.config.targetName)
    if not item.isNil:
        item.show(cb)
        quest.openTutorialStep()
    else:
        if not cb.isNil:
            cb()


proc hideBubbleFor*(m: MapQuestBubbles, q: Quest, cb: proc() = nil) =
    let item = m.items.getOrDefault(q.config.targetName)
    if not item.isNil:
        item.hide(cb)
    elif not cb.isNil:
        cb()


proc newMapQuestBubbles*(parent: Node): MapQuestBubbles =
    let node = newNode("hints")
    parent.addChild(node)
    result = MapQuestBubbles.new()
    result.node = node
    result.items = initTable[string, MapQuestMenuItem]()

    let m = result

