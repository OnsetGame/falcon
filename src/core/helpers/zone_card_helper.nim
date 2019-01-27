import rod / node
import core / zone

import utils / [color_segments, icon_component]

import color_segments_helper
export CardStyle


proc getCardStyle*(z: Zone): CardStyle =
    if not z.isActive():
        return CardStyle.Grey
    
    if z.feature.kind == Slot:
        return CardStyle.Aqua

    return CardStyle.Coffee


var configs: array[CardStyle.low .. CardStyle.high, ColorSegmentsConf]
configs[Coffee] = Coffee2SegmentsConf
configs[Aqua] = AquaCardSegmentsConf
configs[Grey] = GraySegmentsConf


var tints: array[CardStyle.low .. CardStyle.high, proc(node: Node)]
tints[Coffee] = coffeeColorSlotNameRect
tints[Aqua] = aquaColorSlotNameRect
tints[Grey] = grayColorSlotNameRect


proc backgroundForZone*(n: Node, z: Zone) =
    n.colorSegmentsForNode(configs[getCardStyle(z)])


proc tintForZone*(n: Node, z: Zone) =
    tints[getCardStyle(z)](n)


proc iconForZone*(c: IconComponent, z: Zone) =
    if z.feature.kind == Slot:
        c.setup:
            c.composition = "slot_logos_icons"
            c.name = z.name
            c.hasOutline = true
    else:
        c.setup:
            c.composition = "buildings_icons"
            c.name = z.name
            c.hasOutline = true