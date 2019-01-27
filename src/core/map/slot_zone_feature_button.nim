import strutils

import rod / component
import shared / window / button_component
import shared / user
import core / zone
import core / map / zone_feature_button
import core / features / slot_feature

type SlotZoneFeatureButton* = ref object of ZoneFeatureButton

method componentNodeWasAddedToSceneView*(c: SlotZoneFeatureButton) =
    procCall c.ZoneFeatureButton.componentNodeWasAddedToSceneView()
    c.freeIco.alpha  = 1.0
    c.freeShadow.alpha = 1.0

method onUpdate*(c: SlotZoneFeatureButton) =
    let f = c.zone.feature.SlotFeature
    if f.hasFreeRounds() and not c.isShowed:
        c.show()

registerComponent(SlotZoneFeatureButton)
