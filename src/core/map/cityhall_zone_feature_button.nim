import nimx / animation
import rod / [ component, node ]
import rod / component / [ text_component, ae_composition ]
import shared / window / button_component
import shared / [ game_scene, tutorial ]
import utils / [ helpers, timesync ]
import core / zone
import core / net / server
import core / map / zone_feature_button
import core / features / booster_feature
import strutils
import windows / store / store_window

type CityHallZoneFeatureButton* = ref object of ZoneFeatureButton
    alertAnim: Animation
    feature: Feature
    gs: GameScene
    onFeatureUpdate: proc()

proc setMultipliersText*(c: CityHallZoneFeatureButton) =
    let incomeTC = c.boostersAll.mandatoryNode("boost_txt_01").getComponent(Text)
    let tournamentTC = c.boostersAll.mandatoryNode("boost_txt_02").getComponent(Text)
    let expTC = c.boostersAll.mandatoryNode("boost_txt_03").getComponent(Text)
    incomeTC.text = boostMultiplierText(btIncome)
    tournamentTC.text = boostMultiplierText(btTournamentPoints)
    expTC.text = boostMultiplierText(btExperience)

method componentNodeWillBeRemovedFromSceneView(c: CityHallZoneFeatureButton) =
    procCall c.ZoneFeatureButton.componentNodeWillBeRemovedFromSceneView()

    if not c.feature.isNil:
        c.feature.unsubscribe(c.gs, c.onFeatureUpdate)
        c.feature = nil

proc showFreeAlert(c: CityHallZoneFeatureButton) =
    if not c.alertAnim.isNil:
        return
    c.alertSmall.alpha = 1.0

    let remainderAnim = c.alertSmall.getComponent(AEComposition)
    c.alertAnim = newAnimation()
    c.alertAnim.numberOfLoops = -1
    c.alertAnim.loopDuration = 5.0
    c.alertAnim.addLoopProgressHandler(1.0, false) do():
        remainderAnim.play("remainder")

    c.node.addAnimation(c.alertAnim)

proc hideFreeAlert(c: CityHallZoneFeatureButton) =
    if not c.alertAnim.isNil:
        c.alertAnim.cancel()
        c.alertAnim = nil

    c.alertSmall.alpha = 0.0

proc subscribeOnFeatureUpdate*(c: CityHallZoneFeatureButton) =
    let scene = c.node.sceneView.GameScene
    let feature = c.zone.feature.BoosterFeature
    let onFeatureUpdate = proc() =
        if c.zone.isActive():
            let bta = feature.boosterToActivate
            if not c.isShowed and bta.kind.len > 0:
                c.show()
                tsBoosterFeatureButton.addTutorialFlowState()
                if bta.isFree:
                    c.showFreeAlert()
                else:
                    c.hideFreeAlert()

            if c.isShowed:
                if bta.kind.len == 0:
                    c.hide()
                    c.hideFreeAlert()
                else:
                    if bta.isFree:
                        c.showFreeAlert()
                    else:
                        c.hideFreeAlert()

    c.feature = feature
    c.gs = c.node.sceneView.GameScene
    c.onFeatureUpdate = onFeatureUpdate

    feature.subscribe(c.node.sceneView.GameScene, onFeatureUpdate)
    onFeatureUpdate()

method setBttnAction*(c: CityHallZoneFeatureButton) =
    c.bttn.onAction do():
        showStoreWindow(StoreTabKind.Boosters, "cityhall_bubble")

method componentNodeWasAddedToSceneView*(c: CityHallZoneFeatureButton) =
    procCall c.ZoneFeatureButton.componentNodeWasAddedToSceneView()

    c.setMultipliersText()

    c.boostersAll.alpha = 1.0
    c.shadowBlack.alpha = 1.0

    c.alertSmall.findNode("alert_text_@noloc").getComponent(Text).text = "FREE"

registerComponent(CityHallZoneFeatureButton)
