import strutils, tables
import nimx / matrixes

import core / [zone, notification_center]
import core.features.vip_system
import quest / quests
import shafa / game / reward_types
import shared / director
import falconserver / map / building / builditem
import tilemap / tile_map

proc openFeatureWindow*(z: Zone) =
    let notifCenter = currentNotificationCenter()
    case z.feature.kind:
    of FeatureType.Slot:
        notifCenter.postNotification("MapPlayFreeSlotClicked", newVariant(parseEnum[BuildingId](z.name)))
    of FeatureType.Tournaments:
        notifCenter.postNotification("BuildingMenuClick_stadium")
    of FeatureType.Exchange:
        notifCenter.postNotification("BuildingMenuClick_bank")
    of FeatureType.Boosters:
        notifCenter.postNotification("BuildingMenuClick_cityHall")
    of FeatureType.Wheel:
        notifCenter.postNotification("MapMenu_Wheel_Spin_pressed")
    of FeatureType.Gift:
        notifCenter.postNotification("MapMenu_Zeppelin_pressed")
    of FeatureType.Friends:
        notifCenter.postNotification("MapMenu_Facebook_pressed", newVariant("buildingInfo"))
    of FeatureType.Profile:
        notifCenter.postNotification("BuildingMenuClick_barberShop")
    else:
        discard


proc getCollectAnchorPos*(z: Zone, m: TileMap): Vector3 =
    let zonelayers = itemsForPropertyValue[BaseTileMapLayer, string](m, "target", z.name)
    for item in zonelayers:
        if "CollectXY" in item.obj.properties:
            var splxy = item.obj.properties["CollectXY"].str.split(",")
            var tx = splxy[0].parseInt()
            var ty = splxy[1].parseInt()
            result =  m.positionAtTileXY(tx, ty)
            break

proc getQuestAnchorPos*(z: Zone, m: TileMap): Vector3 =
    let zonelayers = itemsForPropertyValue[BaseTileMapLayer, string](m, "target", z.name)
    for item in zonelayers:
        if "ZoneXY" in item.obj.properties:
            var splxy = item.obj.properties["ZoneXY"].str.split(",")
            var tx = splxy[0].parseInt()
            var ty = splxy[1].parseInt()
            result = m.positionAtTileXY(tx, ty)
            break


proc isIncomeQuest*(q: Quest): bool =
    for rew in q.rewards:
        if rew.kind == RewardKind.incomeChips or rew.kind == RewardKind.incomeBucks:
            return true


proc isSlotQuest*(q: Quest): bool =
    for zone in getZones():
        if zone.feature.unlockQuestConf == q.config:
            return zone.isSlot()


proc isFeatureQuest*(q: Quest): bool =
    for zone in getZones():
        if zone.feature.unlockQuestConf == q.config:
            return zone.feature.kind != FeatureType.noFeature

proc getVipZoneLevel*(bid: BuildingId): int =
    let vipC = sharedVipConfig()

    for i, lc in vipC.levels:
        for r in lc.rewards:
            if r.kind == RewardKind.vipaccess and r.ZoneReward.zone == $bid:
                result = i

