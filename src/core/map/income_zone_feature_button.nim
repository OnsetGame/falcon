import variant
import rod / [ node, component ]
import shared / window / button_component
import shared / [ user, chips_animation, game_scene, tutorial ]
import core / zone
import core / map / zone_feature_button
import core.net.server
import utils / [ sound_manager, game_state ]

import falconserver / map / building / builditem

import map / collect_resources
import core / flow / flow_state_types

const SHOW_CHIPS_VALLUE = 0.1
type IncomeZoneFeatureButton* = ref object of ZoneFeatureButton
    currency: Currency

method componentNodeWasAddedToSceneView*(c: IncomeZoneFeatureButton) =
    procCall c.ZoneFeatureButton.componentNodeWasAddedToSceneView()

method onUpdate*(c: IncomeZoneFeatureButton) =
    if c.zone.feature.kind == FeatureType.IncomeChips:
        c.currency = Chips
        c.chipsIco.alpha = 1.0
        c.shadowRed.alpha = 1.0
    if c.zone.feature.kind == FeatureType.IncomeBucks:
        c.currency = Bucks
        c.bucksIco.alpha = 1.0
        c.shadowGreen.alpha = 1.0

    if sharedResCollectConfig().resources.len > 0 and c.zone.isActive():
        let availableRes = availableResources(c.currency)
        let progress = resourceCapacityProgress(c.currency)

        if not c.isShowed and progress >= SHOW_CHIPS_VALLUE:
            c.show()
            c.zone.feature.hasBonus = true
            if c.currency == Chips:
                addTutorialFlowState(tsRestaurantCollectRes, front = true)
            else:
                addTutorialFlowState(tsGasStationCollectRes, front = true)

        if c.isShowed and progress < SHOW_CHIPS_VALLUE:
            c.hide()
            c.zone.feature.hasBonus = false

            let u = currentUser()
            let scene = c.node.sceneView.GameScene
            scene.soundManager.sendEvent("COMMON_GUI_CLICK")
            if not scene.isNil:
                var gui_parent = scene.rootNode.findNode("GUI")
                if gui_parent.isNil:
                    gui_parent = scene.rootNode.findNode("gui_parent")

                if c.currency == Chips:
                    scene.soundManager.sendEvent("COLLECT_CHIPS")
                    scene.chipsAnim(c.node, scene.rootNode.findNode("money_panel").findNode("chips_placeholder"), gui_parent, 5, u.chips, u.chips + availableRes)
                else:
                    scene.soundManager.sendEvent("COLLECT_BUCKS")
                    scene.bucksAnim(c.node, scene.rootNode.findNode("money_panel").findNode("bucks_placeholder"), gui_parent, 5, u.bucks, u.bucks + availableRes)

proc collectResources*(currency: Currency) =
    sharedServer().collectResources($currency) do(jn: JsonNode):
        let u = currentUser()
        let pc = u.chips
        let pb = u.bucks

        if "wallet" in jn:
            u.updateWallet(jn["wallet"])

proc attachCollectActionToButton*(btn: ButtonComponent, currency: Currency) =
    btn.onAction do():
        currency.collectResources()

method setBttnAction*(c: IncomeZoneFeatureButton) =
    if c.zone.feature.kind == FeatureType.IncomeChips:
        c.currency = Chips
    elif c.zone.feature.kind == FeatureType.IncomeBucks:
        c.currency = Bucks
    attachCollectActionToButton(c.bttn, c.currency)

registerComponent(IncomeZoneFeatureButton)
