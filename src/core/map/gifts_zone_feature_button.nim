import nimx / animation

import rod / [ component, node ]
import rod / component / [ text_component, ae_composition ]

import core / zone
import core / map / zone_feature_button
import core / features / gifts_feature

import utils / helpers

type GiftsZoneFeatureButton* = ref object of ZoneFeatureButton

proc updateGiftsCount(c: GiftsZoneFeatureButton, f: GiftsFeature) =
    let giftsCount = f.giftsCount()
    c.alertSmall.findNode("alert_text_@noloc").component(Text).text = $giftsCount

method componentNodeWasAddedToSceneView*(c: GiftsZoneFeatureButton) =
    procCall c.ZoneFeatureButton.componentNodeWasAddedToSceneView()
    c.featureIco.alpha = 1.0
    c.shadowBlack.alpha = 1.0
    c.alertSmall.alpha = 1.0

    let remainderAnim = c.alertSmall.component(AEComposition)
    let anim = newAnimation()
    anim.numberOfLoops = -1
    anim.loopDuration = 5.0
    anim.addLoopProgressHandler(1.0, false) do():
        remainderAnim.play("remainder")

    c.node.addAnimation(anim)

method onUpdate*(c: GiftsZoneFeatureButton) =
    if c.zone.isActive():
        let feature = c.zone.feature.GiftsFeature
        if not c.isShowed and feature.hasGifts:
            updateGiftsCount(c, feature)
            c.show()
        if c.isShowed and not feature.hasGifts:
            c.hide()

registerComponent(GiftsZoneFeatureButton)
