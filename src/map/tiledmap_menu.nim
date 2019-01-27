import nimx / [matrixes, types, button, animation]
import core / notification_center
import rod / [node, rod_types, component, viewport]
import rod / component / [ ui_component, text_component, channel_levels, color_balance_hls, ae_composition, tint ]

import falconserver / map / building / [ builditem, jsonbuilding ]
import falconserver.quest.quest_types
import falconserver / common / [ game_balance, currency ]
import falconserver.tutorial.tutorial_types
import tilemap.tile_map

import shared / window / [ button_component, window_manager ]
import windows / quests / quest_window
import windows / store / store_window
import utils / [ timesync, falcon_analytics, game_state, helpers, icon_component ]

import strutils, tables, json, logging
import shared / [ user, shared_gui, game_scene, chips_animation, localization_manager, tutorial, director ]
import core / net / server

import map_gui, collect_resources
import quest / [ quest_icon_component, quests, quest_helpers, quests_actions ]
import times
import core / [ zone, zone_helper ]
import core / map / [zone_feature_button, slot_zone_feature_button, income_zone_feature_button, wheel_zone_feature_button, exchange_zone_feature_button, gifts_zone_feature_button ]
import core / helpers / color_segments_helper
import core / flow / flow

import platformspecific.android.rate_manager

import tiledmap_quest_balloons, tiledmap_quest_card, tiledmap_zone_info_card, tiledmap_zone_info_balloons
import tiledmap_actions

import narrative / [ quest_narrative, narrative_character ]


type TiledMapMenu* = ref object
    zoneInfoBalloons: MapZoneInfoBallons
    questBubbles*: MapQuestBubbles
    questCard*: MapQuestCard
    zoneInfoCard: MapZoneInfoCard
    tileMap: TileMap
    tutorialTouchLocker: Node
    scale: Vector3
    lastQuest*: Quest


proc mapScaleChanged*(m: TiledMapMenu, sc: Vector3)=
    m.scale = sc
    m.questBubbles.scale = sc
    m.questCard.scale = sc
    m.zoneInfoCard.scale = sc
    m.zoneInfoBalloons.scale = sc


proc xyForTarget(m: TiledMapMenu, target: string): tuple[questxy, zonexy: Vector3] =
    var zoneHasPosition = false
    var questxy, zonexy: Vector3

    let zonelayers = itemsForPropertyValue[BaseTileMapLayer, string](m.tileMap, "target", target)
    for item in zonelayers:
        if "QuestMenuXY" in item.obj.properties:
            var splxy = item.obj.properties["QuestMenuXY"].str.split(",")
            var tx = splxy[0].parseInt()
            var ty = splxy[1].parseInt()
            questxy = m.tileMap.positionAtTileXY(tx, ty)
            zoneHasPosition = true
            break

    for item in zonelayers:
        if "ZoneXY" in item.obj.properties:
            var splxy = item.obj.properties["ZoneXY"].str.split(",")
            var tx = splxy[0].parseInt()
            var ty = splxy[1].parseInt()
            zonexy = m.tileMap.positionAtTileXY(tx, ty)
            break

    if not zoneHasPosition:
        questxy = newVector3(1500.0, 1500.0)
        zonexy = newVector3(1500.0, 1500.0)

    result = (questxy, zonexy)


proc createTiledMapMenu*(n: Node, tm: TileMap, mg: MapGUI): TiledMapMenu =
    result.new()
    result.zoneInfoBalloons = newMapZoneInfoBallons(n, tm)
    result.questBubbles = newMapQuestBubbles(n)
    result.questCard = newMapQuestCard(n)
    result.zoneInfoCard = newMapZoneInfoCard(n)
    result.tileMap = tm

    let m = result


proc showBubbleForQuest*(m: TiledMapMenu, q: Quest, onShow: proc()) =
    let (questxy, zonexy) = m.xyForTarget(q.config.targetName)
    m.questBubbles.createBubbleFor(q, questxy, zonexy) do(created: bool):
        m.questBubbles.showBubbleFor(q, onShow)


proc hideBubbleForQuest*(m: TiledMapMenu, q: Quest, onHide: proc()) =
    m.questBubbles.hideBubbleFor(q, onHide)


proc clear*(m: TiledMapMenu) =
    # m.questCard.hideCard()
    m.zoneInfoCard.hideCard()


proc showCardForQuest*(m: TiledMapMenu, q: Quest, onShow: proc()) =
    if m.questCard.isCardOpenedFor(q):
        onShow()
        return

    m.clear()

    let (questxy, zonexy) = m.xyForTarget(q.config.targetName)
    m.questCard.createCard(q, questxy, zonexy)
    m.questCard.showCard(onShow)

    m.lastQuest = q


proc hideCardForQuest*(m: TiledMapMenu, q: Quest, onHide: proc()) =
    if m.questCard.isCardOpenedFor(q):
        m.questCard.hideCard(onHide)
    else:
        onHide()

proc showCardForZone*(m: TiledMapMenu, z: Zone, onShow: proc() = nil) =
    m.clear()

    let (questxy, zonexy) = m.xyForTarget(z.name)
    m.zoneInfoCard.showCard(z, questxy, zonexy, onShow)

proc showCardForZone*(m: TiledMapMenu, z: Zone, p: Vector3, onShow: proc() = nil) =
    m.clear()

    let (_, zonexy) = m.xyForTarget(z.name)
    m.zoneInfoCard.showCard(z, p, zonexy, onShow)