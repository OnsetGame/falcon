import json

import node_proxy / proxy
import nimx / [ types, matrixes ]
import rod / [ component, node ]
import rod / component / text_component

import shared / [ deep_links, localization_manager ]
import core / net / server
import core / zone
import core / features / slot_feature
import utils / [ icon_component, helpers, falcon_analytics ]

import window_component, button_component


nodeProxy FreeRoundsResultWindowProxy:
    title Text {onNode: "TR_TOURNAMENT_IS_OVER"}
    desc Text {onNode: "TR_NAMED_TOURNAMENT_IS_OVER"}
    result Text {onNode: "TR_RESULT_PUBLISHED_SOON"}
    icon IconComponent {onNodeAdd: "icon_placeholder"}:
        composition = "slot_logos_icons"
    button ButtonComponent {withValue: np.node.findNode("black_button_long").createButtonComponent(newRect(0, 0, 222*2, 42*2))}
    buttonTitle Text {onNode: "TR_BACK_TO_TOURNAMENTS"}


type FreeRoundsResultWindow* = ref object of WindowComponent
    proxy: FreeRoundsResultWindowProxy
    zone: Zone


method onInit*(w: FreeRoundsResultWindow) =
    w.canMissClick = false

    let proxy = FreeRoundsResultWindowProxy.new(newNodeWithResource("common/gui/popups/precomps/Tournament_over"))
    w.anchorNode.addChild(proxy.node)
    proxy.node.playAnimation("appear")

    proxy.button.onAction do():
        w.closeButtonClick()
    proxy.title.text = localizedString("FREE_ROUNDS_RESULT_TITLE")
    proxy.result.node.removeFromParent()
    proxy.buttonTitle.text = localizedString("FREE_ROUNDS_RESULT_BUTTON_TITLE")

    w.proxy = proxy


method beforeRemove*(w: FreeRoundsResultWindow) =
    procCall w.WindowComponent.beforeRemove()
    sharedDeepLinkRouter().handle("/scene/TiledMapView/window/TasksWindow")


proc setZone*(w: FreeRoundsResultWindow, zone: Zone) =
    let slotFeature = zone.feature.SlotFeature
    w.zone = zone
    w.proxy.icon.name = zone.name
    w.proxy.desc.text = localizedFormat("FREE_ROUNDS_RESULT_DESC", slotFeature.totalRoundsWin.formatThousands())
    sharedServer().completeFreeRounds(zone.name)
    sharedAnalytics().freerounds_end(zone.name, slotFeature.totalRoundsWin, slotFeature.passedRounds)

registerComponent(FreeRoundsResultWindow, "windows")
