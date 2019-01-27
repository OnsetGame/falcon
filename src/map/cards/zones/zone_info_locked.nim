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


nodeProxy ZoneInfoLocked of MapZoneCard:
    lock Hint {withValue: np.lockComp.newHint()}


proc newZoneInfoLocked*(parent: Node, zone: Zone): ZoneInfoLocked =
    result = ZoneInfoLocked.new(MapZoneCardBgStyle.BottomMiddle, parent)
    result.bg.bgColor.backgroundForZone(zone)

    result.titleText.text = localizedString(zone.name & "_NAME")
    result.titleBg.tintForZone(zone)

    result.zoneIconNode.alpha = 1.0
    result.bigIconBgNode.backgroundForZone(zone)

    result.zoneIcon.iconForZone(zone)

    result.descriptionWithIncomeNode.alpha = 1.0
    result.descriptionWithIncomeText.text = localizedString(zone.name & "_DESC")
    result.descriptionWithIncomeText.bounds = newRect(-175.0, -40.0, 350.0, 200.0)


proc lockWithVipLevel*(i: ZoneInfoLocked, lvl: int) =
    i.activateButton(i.buttonUnlock):
        i.buttonUnlock.title = localizedFormat("OPEN_SLOT_ON_VIP", $lvl)
        i.buttonShadow.alpha = 0.0

proc lockWithLevel*(i: ZoneInfoLocked, lvl: int) =
    i.activateButton(i.buttonUnlock):
        i.buttonUnlock.title = localizedFormat("MAP_UNLOCK_BUILDING", $lvl)
        i.buttonShadow.alpha = 0.0


proc lockWithQuest*(i: ZoneInfoLocked) =
    i.activateButton(i.buttonUnlock):
        i.buttonUnlock.title = localizedString("MAP_COMPLETE_TO_UNLOCK2")
        i.buttonShadow.alpha = 0.0


method show(i: ZoneInfoLocked, cb: proc() = nil) =
    proc mycb() =
        i.lock.show(cb)
    procCall i.MapZoneCard.show(mycb)