import times, variant
import button_feature
import quest / quests
import shared / [game_scene, localization_manager, tutorial ]
import rod / node
import utils / [ pause, timesync ]
import shared / window / window_manager
import wheel / wheel

import core / [zone, notification_center]
import core / features / wheel_feature
import core / flow / flow_state_types

type ButtonWheelOfFortune* = ref object of ButtonFeature

method onInit*(bf: ButtonWheelOfFortune) =
    bf.icon = "Wheel"
    bf.title = localizedString("GUI_WHEEL_BUTTON")
    bf.zone = "wheeloffortune"

method onCreate*(bf: ButtonWheelOfFortune) =
    let zone = findZone(bf.zone)
    let feature = zone.feature.WheelFeature
    let scene = bf.rootNode.sceneView.GameScene

    proc update() =
        if not zone.isActive():
            bf.hideHint()
            bf.disable()
            return

        bf.enable()

        if feature.hasFreeSpin:
            bf.hint("FREE")
        else:
            bf.hideHint()

    feature.subscribe(scene, update)
    update()

    bf.onAction = proc(enabled: bool) =
        if enabled:
            bf.playClick()
            let w = sharedWindowManager().show(WheelWindow)
            if not w.isNil:
                w.source = bf.source

    bf.rootNode.addObserver("QUEST_COMPLETED", bf) do(arg: Variant):
        update()

    bf.rootNode.name = "wheel_map_bottom_menu"

method enable*(bf: ButtonWheelOfFortune) =
    procCall bf.ButtonFeature.enable()

template newButtonWheelOfFortune*(parent: Node): ButtonWheelOfFortune =
    ButtonWheelOfFortune.new(parent)