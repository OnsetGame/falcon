import strutils

import rod / [component , node ]
import shared / window / button_component
import shared / user
import core / zone
import core / map / zone_feature_button
import core / features / tournaments_feature
import utils / icon_component

type StadiumZoneFeatureButton* = ref object of ZoneFeatureButton

method componentNodeWasAddedToSceneView*(c: StadiumZoneFeatureButton) =
    procCall c.ZoneFeatureButton.componentNodeWasAddedToSceneView()

    c.freeIco.getComponent(IconComponent).name = "freeCup"
    c.freeIco.alpha  = 1.0
    c.freeShadow.alpha = 1.0

method onUpdate*(c: StadiumZoneFeatureButton) =
    if c.zone.isActive():
        let f = c.zone.feature.TournamentsFeature
        if f.hasFreeTournament:
            c.show()
        else:
            c.hide()

registerComponent(StadiumZoneFeatureButton)
