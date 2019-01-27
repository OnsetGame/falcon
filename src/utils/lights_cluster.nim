import nimx.types
import nimx.animation
import nimx.composition
import nimx.view

import math

type
    LightsCluster* = ref object
        count*: int
        coords*: proc(index: int): Point
        intensity*: LightsClusterIntensityFunction
        animationValue*: float

    LightsClusterIntensityFunction = proc(index: int, coords: Point, lc: LightsCluster): float

var lightComposition = newComposition"""
uniform float uIntensity;

void compose() {
    vec2 center = bounds.xy + bounds.zw / 2.0;
    float radius = min(bounds.z, bounds.w) / 2.0;
    radius *= uIntensity;
    drawShape(sdCircle(center, radius), vec4(0.98, 0.62, 0.23, 0.30));
    drawShape(sdCircle(center, radius * 0.5), vec4(0.99, 0.84, 0.45, 0.58));
    drawShape(sdCircle(center, radius * 0.3), vec4(1.0, 1.0, 1.0, 1.0));
}
"""

#big 1.0, 0.25, 0.08
#middle 1.0, 0.76, 0.55

proc radialLightsCoords*(center: Point, radius: Coord, num: int): proc(index: int): Point =
    var pts = newSeq[Point](num)
    let angleStep = 2 * PI / num.float
    for i in 0 ..< num:
        let angle = angleStep * i.float
        pts[i].x = center.x + radius * cos(angle)
        pts[i].y = center.y + radius * sin(angle)
    result = proc(index: int): Point =
        pts[index]

template dist[T](a, b: T): auto = max(a, b) - min(a, b)

proc radialDependantIntensityFunction*(minVal: float = -0.15, step: float = 0.13, interval: int = 8): LightsClusterIntensityFunction =
    result = proc(index: int, coords: Point, lc: LightsCluster): float =
        var finish = interpolate(0, lc.count, lc.animationValue)
        result = minVal

        let delta = abs(finish - index)
        let remainder = delta mod interval
        let even = delta /% interval mod 2 == 0

        if even:
            result += remainder.float * step
        else:
            result += (interval - remainder).float * step

proc halfRadialDependantIntensityFunction*(step: float = 0.2): LightsClusterIntensityFunction =
    result = proc(index: int, coords: Point, lc: LightsCluster): float =
        var max = interpolate(0, lc.count, lc.animationValue)

        let delta = abs(max - index)
        result = 1.0 - delta.float * step

proc radialDependantIntensityFunction2*(step:float = 0.07): LightsClusterIntensityFunction =
    result = proc(index: int, coords: Point, lc: LightsCluster): float =
        var max = interpolate(0, lc.count, lc.animationValue)

        var delta = max - index
        if index > max:
            delta = delta + lc.count
        result = 1.0 - delta.float * step


proc indexDependantIntensityFunction*(spread: float = 25): LightsClusterIntensityFunction =
    result = proc(index: int, coords: Point, lc: LightsCluster): float =
        let overlap = spread / 2.0 / lc.count.float
        let animVal = interpolate(-overlap, 1.0 + overlap, lc.animationValue)
        let middle = animVal * lc.count.float
        result = 1.0 - dist(index.float, middle) / (spread / 2)

proc linearCenterYIntensityFunction*(centerY, spread, radius: Coord = 0): LightsClusterIntensityFunction =
    result = proc(index: int, coords: Point, lc: LightsCluster): float =
        let middle = interpolate(-spread, radius + spread, lc.animationValue)
        var d1 = dist(coords.y, centerY + middle)
        var d2 = dist(coords.y, centerY - middle)
        if d1 < spread and centerY > coords.y: d1 = (radius + spread) * 2
        if d2 < spread and centerY < coords.y: d2 = (radius + spread) * 2
        let d = min(d1, d2)
        result = 1.0 - d / spread

proc linearCenterXIntensityFunction*(centerX, spread, radius: Coord = 0): LightsClusterIntensityFunction =
    result = proc(index: int, coords: Point, lc: LightsCluster): float =
        let middle = interpolate(-spread, radius + spread, lc.animationValue)
        var d1 = dist(coords.y, centerX + middle)
        var d2 = dist(coords.y, centerX - middle)
        if d1 < spread and centerX > coords.x: d1 = (radius + spread) * 2
        if d2 < spread and centerX < coords.x: d2 = (radius + spread) * 2
        let d = min(d1, d2)
        result = 1.0 - d / spread

proc constantIntensityFunction*(intensity: float = 1.0): LightsClusterIntensityFunction =
    result = proc(index: int, coords: Point, lc: LightsCluster): float = intensity

proc waveAnimation*(lc: LightsCluster, dur: float = 2.0): Animation =
    result = newAnimation()
    result.numberOfLoops = 1
    result.loopDuration = dur
    result.onAnimate = proc(p: float) =
        lc.animationValue = p

proc draw*(lc: LightsCluster) =
    var r = zeroRect
    r.size.width = 36.0
    r.size.height = 36.0

    if lc.intensity.isNil:
        lc.intensity = indexDependantIntensityFunction()

    for i in 0 ..< lc.count:
        r.origin = lc.coords(i)
        r.origin.x -= r.width / 2.0
        r.origin.y -= r.height / 2.0
        let intensity = lc.intensity(i, r.origin, lc)
        if intensity > 0:
            lightComposition.draw r:
                setUniform("uIntensity", intensity)

