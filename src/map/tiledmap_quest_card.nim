import sequtils, variant
import nimx / matrixes
import rod / node

import cards / map_zone_card
import cards / quests / [quest_ready_card, quest_inprogress_card]

import shared / user
import quest / quests

import shared / game_scene
import tiledmap_actions


type MapQuestCard* = ref object
    questId: int
    card: MapZoneCard
    node: Node
    scale: Vector3


proc hideCard*(i: MapQuestCard, cb: proc() = nil) =
    if not i.card.isNil:
        let card = i.card

        i.card = nil

        card.destroy() do():
            if not cb.isNil:
                cb()
    else:
        if not cb.isNil:
            cb()


proc isCardOpenedFor*(i: MapQuestCard, q: Quest): bool =
    result = not i.card.isNil and i.questId == q.id


proc `scale=`*(i: MapQuestCard, sc: Vector3) =
    i.scale = sc
    if not i.card.isNil:
        i.card.rootNode.scale = sc


proc createCard*(i: MapQuestCard, q: Quest, questxy: Vector3, zonexy: Vector3) =
    i.questId = q.id

    if not i.card.isNil:
        i.hideCard()

    var card: MapZoneCard
    case q.status:
        of QuestProgress.Ready:
            card = newQuestReadyCard(i.node, q)
            card.onAction = proc() =
                card.onAction = proc() = discard
                i.node.dispatchAction(TryToStartQuestAction, newVariant(q))

        of QuestProgress.InProgress:
            card = newQuestInProgressCard(i.node, q)
            card.onAction = proc() =
                card.onAction = proc() = discard
                i.node.dispatchAction(TryToSpeedupQuestAction, newVariant(q))

        else:
            return

    card.rootNode.position = questxy
    card.rootNode.scale = i.scale

    i.card = card


proc showCard*(i: MapQuestCard, cb: proc() = nil) =
    if not i.card.isNil:
        i.card.show(cb)


proc newMapQuestCard*(parent: Node): MapQuestCard =
    result = MapQuestCard.new()
    result.node = parent.newChild("quest_card")
