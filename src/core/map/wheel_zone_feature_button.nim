import nimx / animation
import rod / [ component, node ]
import rod / component / [ text_component, ae_composition ]
import shared / window / button_component
import utils / [ helpers, timesync ]
import shared / user
import core / zone
import core / map / zone_feature_button
import core / features / wheel_feature

type WheelZoneFeatureButton* = ref object of ZoneFeatureButton

method componentNodeWasAddedToSceneView*(c: WheelZoneFeatureButton) =
    procCall c.ZoneFeatureButton.componentNodeWasAddedToSceneView()
    c.featureIco.alpha = 1.0
    c.shadowBlack.alpha = 1.0
    c.alertSmall.alpha = 1.0
    c.alertSmall.findNode("alert_text_@noloc").getComponent(Text).text = "FREE"

    let remainderAnim = c.alertSmall.getComponent(AEComposition)
    let anim = newAnimation()
    anim.numberOfLoops = -1
    anim.loopDuration = 5.0
    anim.addLoopProgressHandler(1.0, false) do():
        remainderAnim.play("remainder")

    c.node.addAnimation(anim)

method onUpdate*(c: WheelZoneFeatureButton) =
    if c.zone.isActive():
        let feature = c.zone.feature.WheelFeature
        if not c.isShowed and feature.hasFreeSpin:
            c.show()
        if c.isShowed and not feature.hasFreeSpin:
            c.hide()

registerComponent(WheelZoneFeatureButton)