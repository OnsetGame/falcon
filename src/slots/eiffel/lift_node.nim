import rod.rod_types
import rod.node
import rod.component

import nimx.types
import nimx.animation

import utils.lights_cluster
import utils.helpers

proc newLiftNode*(): Node2D =
    result = newLocalizedNodeWithResource("slots/eiffel_slot/eiffel_slot/precomps/LIFT.json")

    let vertLc = LightsCluster.new()
    const lightsPerDoor = 8

    vertLc.intensity = linearCenterYIntensityFunction(60 + 3 * 14, 45, 8 * 14)

    vertLc.coords = proc(i: int): Point =
        result.x = if i > lightsPerDoor - 1: -53 else: 53
        result.y = Coord(i mod lightsPerDoor) * 14 + 60

    vertLc.count = lightsPerDoor * 2

    let lcNode = result.newChild("lc")
    lcNode.setComponent "lc", newComponentWithDrawProc(proc() =
        if not vertLc.isNil: vertLc.draw()
    )

    let anim = result.animationNamed("open")
    anim.chainOnAnimate proc(p: float) =
        vertLc.animationValue = p
