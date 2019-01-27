import nimx / animation

import rod / [ component, node ]
import rod / component / ae_composition

import core / zone
import core / map / zone_feature_button
import core / features / exchange_feature

import utils / helpers
import shared / tutorial

type ExchangeZoneFeatureButton* = ref object of ZoneFeatureButton

method componentNodeWasAddedToSceneView*(c: ExchangeZoneFeatureButton) =
    procCall c.ZoneFeatureButton.componentNodeWasAddedToSceneView()
    c.featureIco.alpha = 1.0
    c.shadowBlack.alpha = 1.0
    c.alertBig.alpha = 1.0

    let remainderAnim = c.alertBig.component(AEComposition)
    let anim = newAnimation()
    anim.numberOfLoops = -1
    anim.loopDuration = 5.0
    anim.addLoopProgressHandler(1.0, false) do():
        remainderAnim.play("remainder_alert")

    c.node.addAnimation(anim)

method onUpdate*(c: ExchangeZoneFeatureButton) =
    if c.zone.isActive():
        let feature = c.zone.feature.ExchangeFeature
        if not c.isShowed and feature.hasDiscountedExchange:
            c.show()
            if isFrameClosed($tsBankQuestReward):
                addTutorialFlowState(tsBankFeatureBttn)
        if c.isShowed and not feature.hasDiscountedExchange:
            c.hide()

registerComponent(ExchangeZoneFeatureButton)
