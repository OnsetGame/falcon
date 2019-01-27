import rod / node
import nimx / [matrixes]
import core / [zone, zone_helper]
import tilemap / tile_map
import shared / game_scene


import core / map / [slot_zone_feature_button, income_zone_feature_button, wheel_zone_feature_button,
                     exchange_zone_feature_button, gifts_zone_feature_button, cityhall_zone_feature_button, stadium_zone_feature_button, zone_feature_button]


import core / features / [exchange_feature, gifts_feature, wheel_feature, income_feature]

import tiledmap_actions


type MapZoneInfoBallons* = ref object
    node: Node


proc updateResources(m: MapZoneInfoBallons) =
    for fnode in m.node.children:
        let fbttn = fnode.getComponent(ZoneFeatureButton)
        if not fbttn.isNil:
            fbttn.onUpdate()


proc createFeatureButton(m: MapZoneInfoBallons, zone: Zone, featurePos: Vector3): Node =
    case zone.feature.kind:
        of FeatureType.Slot:
            result = m.node.newChild("ZoneFeatureButton_" & zone.name)
            let zoneButton = result.addComponent(SlotZoneFeatureButton)
            zoneButton.zone = zone
            result.position = featurePos

        of FeatureType.IncomeChips, FeatureType.IncomeBucks:
            result = m.node.newChild("ZoneFeatureButton_" & zone.name)
            let zoneButton = result.addComponent(IncomeZoneFeatureButton)
            zoneButton.zone = zone
            result.position = featurePos

        of FeatureType.Wheel:
            result = m.node.newChild("ZoneFeatureButton_" & zone.name)
            let zoneButton = result.addComponent(WheelZoneFeatureButton)
            zoneButton.zone = zone
            result.position = featurePos

        of FeatureType.Exchange:
            result = m.node.newChild("ZoneFeatureButton_" & zone.name)
            let zoneButton = result.addComponent(ExchangeZoneFeatureButton)
            zoneButton.zone = zone
            result.position = featurePos

        of FeatureType.Gift:
            result = m.node.newChild("ZoneFeatureButton_" & zone.name)
            let zoneButton = result.addComponent(GiftsZoneFeatureButton)
            zoneButton.zone = zone
            result.position = featurePos

        of FeatureType.Boosters:
            result = m.node.newChild("ZoneFeatureButton_" & zone.name)
            let zoneButton = result.addComponent(CityHallZoneFeatureButton)
            zoneButton.zone = zone
            zoneButton.subscribeOnFeatureUpdate()
            result.position = featurePos
        of FeatureType.Tournaments:
            result = m.node.newChild("ZoneFeatureButton_" & zone.name)
            let zoneButton = result.addComponent(StadiumZoneFeatureButton)
            zoneButton.zone = zone
            result.position = featurePos
        else:
            return

    zone.feature.subscribe(m.node.sceneView.GameScene) do():
        m.updateResources()

proc `scale=`*(m: MapZoneInfoBallons, sc: Vector3) =
    for fnode in m.node.children:
        fnode.scale = sc

proc newMapZoneInfoBallons*(parent: Node, map: TileMap): MapZoneInfoBallons =
    result = MapZoneInfoBallons.new()
    result.node = parent.newChild("map_features")
    for zone in getZones():
        discard result.createFeatureButton(zone, zone.getCollectAnchorPos(map))
