import sequtils, strutils, variant
import nimx / matrixes
import rod / node

import core / [zone, zone_helper]

import cards / map_zone_card
import cards / zones / [zone_info_locked, zone_info_income, zone_info_feature]

import shared / user
import quest / quests

import shared / game_scene
import tiledmap_actions
import falconserver / map / building / builditem


type MapZoneInfoCard* = ref object
    card: MapZoneCard
    node: Node
    scale: Vector3


proc hideCard*(i: MapZoneInfoCard, cb: proc() = nil) =
    if not i.card.isNil:
        i.card.destroy(cb)
        i.card = nil


proc `scale=`*(i: MapZoneInfoCard, sc: Vector3) =
    i.scale = sc
    if not i.card.isNil:
        i.card.rootNode.scale = sc


proc showCard*(i: MapZoneInfoCard, z: Zone, p: Vector3, zonexy: Vector3, onShow: proc() = nil) =
    if not z.isActive():
        let card = newZoneInfoLocked(i.node, z)
        let lvl = z.getUnlockLevel()

        if z.isSlot() and getVipZoneLevel(parseEnum[BuildingId](z.name)) > currentUser().vipLevel:
            let vipLevel = getVipZoneLevel(parseEnum[BuildingId](z.name))
            card.lockWithVipLevel(vipLevel)
        elif lvl > currentUser().level:
            card.lockWithLevel(lvl)
        else:
            card.lockWithQuest()
            card.onAction = proc() =
                i.hideCard()
                for q in sharedQuestManager().activeStories():
                    if q.config.id == z.feature.unlockQuestConf.id:
                        case q.status:
                            of QuestProgress.Ready, QuestProgress.InProgress:
                                card.node.dispatchAction(OpenQuestCardAction, newVariant(q))
                            of QuestProgress.GoalAchieved:
                                card.node.dispatchAction(TryToCompleteQuestAction, newVariant(q))
                            else:
                                discard
                        return
                card.node.dispatchAction(OpenQuestsWindowWithZone, newVariant(z))

        i.card = card
    elif z.feature.kind == IncomeBucks or z.feature.kind == IncomeChips:
        i.card = newZoneInfoIncome(i.node, z)
        i.card.onAction = proc() =
            let currency = if z.feature.kind == IncomeBucks: Currency.Bucks else: Currency.Chips
            i.card.node.dispatchAction(CollectResourcesAction, newVariant(currency))
            i.hideCard()
    else:
        i.card = newZoneInfoFeature(i.node, z)
        i.card.onAction = proc() =
            if z.feature.kind == FeatureType.Slot:
                i.card.node.dispatchAction(PlaySlotWithZone, newVariant(z))
            else:
                i.card.node.dispatchAction(OpenFeatureWindowWithZone, newVariant(z))
            i.hideCard()

    i.card.rootNode.position = p
    i.card.rootNode.scale = i.scale
    i.card.show() do():
        if not onShow.isNil:
            onShow()


proc newMapZoneInfoCard*(parent: Node): MapZoneInfoCard =
    result = MapZoneInfoCard.new()
    result.node = parent.newChild("features_card")


