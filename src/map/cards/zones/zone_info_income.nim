import rod / [rod_types, node]
import rod / component / [text_component]
import nimx / [types, matrixes]

import node_proxy / proxy
import .. / map_zone_card

import core / zone
import core / helpers / [zone_card_helper, hint_helper]

import shared / [localization_manager]
import shared / window / button_component
import utils / [icon_component, helpers]
import map / collect_resources


nodeProxy ZoneInfoIncome of MapZoneCard:
    incomeChips Node {withName: "income_holder_red"}:
        alpha = 0.0
    incomeBucks Node {withName: "income_holder_green"}:
        alpha = 0.0

    incomeText Text {onNode: "zone_income_value"}


proc newZoneInfoIncome*(parent: Node, zone: Zone): ZoneInfoIncome =
    result = ZoneInfoIncome.new(MapZoneCardBgStyle.BottomMiddle, parent)
    result.bg.bgColor.backgroundForZone(zone)

    result.titleText.text = localizedString(zone.name & "_NAME")
    result.titleBg.tintForZone(zone)

    result.zoneIconNode.alpha = 1.0
    result.bigIconBgNode.backgroundForZone(zone)

    result.zoneIcon.iconForZone(zone)

    result.descriptionWithIncomeNode.alpha = 1.0
    result.descriptionWithIncomeText.text = localizedString(zone.name & "_DESC")
    result.descriptionWithIncomeText.bounds = newRect(-175.0, -45.0, 350.0, 125.0)
    result.descriptionWithIncomeText.fontSize = 31

    result.income.alpha = 1.0
    if zone.feature.kind == IncomeBucks:
        result.incomeBucks.alpha = 1.0
        result.incomeText.text = localizedFormat("FEATURE_IncomeInHour", resourcePerHour(Currency.Bucks).formatThousands())
    else:
        result.incomeChips.alpha = 1.0
        result.incomeText.text = localizedFormat("FEATURE_IncomeInHour", resourcePerHour(Currency.Chips).formatThousands())

    let i = result
    i.activateButton(i.buttonCollect):
        i.buttonCollect.icon = ("reward_icons", "income")
        i.buttonCollect.title = localizedString("FEATURE_" & $zone.feature.kind & "_ACTION")