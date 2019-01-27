import rod / [rod_types, node]
import rod / component / [text_component]
import nimx / [types, matrixes]

import node_proxy / proxy
import .. / map_zone_card

import core / zone
import core / helpers / [zone_card_helper, hint_helper]

import shared / [localization_manager]
import shared / window / button_component
import utils / icon_component


nodeProxy ZoneInfoFeature of MapZoneCard


proc newZoneInfoFeature*(parent: Node, zone: Zone): ZoneInfoFeature =
    result = ZoneInfoFeature.new(MapZoneCardBgStyle.BottomMiddle, parent)
    result.bg.bgColor.backgroundForZone(zone)

    result.titleText.text = localizedString(zone.name & "_NAME")
    result.titleBg.tintForZone(zone)

    result.zoneIconNode.alpha = 1.0
    result.bigIconBgNode.backgroundForZone(zone)

    result.zoneIcon.iconForZone(zone)

    result.descriptionWithIncomeNode.alpha = 1.0
    result.descriptionWithIncomeText.text = localizedString(zone.name & "_DESC")
    result.descriptionWithIncomeText.bounds = newRect(-170.0, -40.0, 350.0, 190.0)
    result.descriptionWithIncomeText.fontSize = 30.5

    let i = result
    i.activateButton(i.buttonCollect):
        i.buttonCollect.title = localizedString("FEATURE_" & $zone.feature.kind & "_ACTION")