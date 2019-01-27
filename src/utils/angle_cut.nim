import json
import math

import nimx.types
import nimx.context
import nimx.image
import nimx.composition
import nimx.property_visitor
import nimx.timer
import nimx.animation
import nimx.view

import rod.rod_types
import rod.node
import rod.tools.serializer
import rod.component
import rod.viewport

import utils.helpers

var angleCut = newPostEffect("""
void angle_effect(float whiteLineSize, float linePosX, float linePosY, float angle)
{
    vec4 image = gl_FragColor;
    float y = abs(gl_FragCoord.x - linePosX) * tan(angle) - linePosY; // angle = abs(x)
    y = y - gl_FragCoord.y;
    float y_white = y - whiteLineSize;
    y = smoothstep(0.0, 0.02, y);
    y_white = smoothstep(0.0, 0.02, y_white);

    gl_FragColor = (image.rgba + vec4(0.8, 0.8, 0.8, 0.0)) * (1.0 - y_white) + image.rgba * y_white;
    gl_FragColor.a = image.a * y;
}
""", "angle_effect", ["float", "float", "float", "float"])

type AngleCut* = ref object of Component
    progress: float
    angle: float
    offset*: Point
    whiteLineSize*: float
    image*: Image

method init(ac: AngleCut) =
    ac.whiteLineSize = 20.0
    ac.angle = 45.0

method beforeDraw*(c: AngleCut, index: int): bool =
    let bbox = c.node.nodeBounds()
    var size = newVector3(bbox.maxPoint.x - bbox.minPoint.x, bbox.maxPoint.y - bbox.minPoint.y, 0.0)
    size.x = size.x / 2.0

    let fromInWorld = c.node.sceneView.worldToScreenPoint(bbox.minPoint + size)
    var winFromPos = c.node.sceneView.convertPointToWindow(newPoint(fromInWorld.x, fromInWorld.y))
    let pr = c.node.sceneView.window.pixelRatio
    let winSize = c.node.sceneView.window.bounds.size

    pushPostEffect(angleCut, c.whiteLineSize, (winFromPos.x + c.offset.x) * pr,
                (winFromPos.y + c.offset.y - winSize.height + c.progress * winFromPos.y) * pr, degToRad(c.angle))

method afterDraw*(c: AngleCut, index: int) =
    popPostEffect()

proc animation*(c: AngleCut, dur: float): Animation=
    result = newAnimation()
    result.numberOfLoops = 1
    result.loopDuration = dur
    result.onAnimate = proc(p:float)=
        c.progress = interpolate(0.0, -1.0, p)

method deserialize*(c: AngleCut, j: JsonNode, serealizer: Serializer) =
    serealizer.deserializeValue(j, "whiteLineSize", c.whiteLineSize)
    serealizer.deserializeValue(j, "offset", c.offset)

method serialize*(c: AngleCut, serealizer: Serializer): JsonNode =
    result = newJObject()
    result.add("whiteLineSize", serealizer.getValue(c.whiteLineSize))
    result.add("offset", serealizer.getValue(c.offset))

method visitProperties*(c: AngleCut, p: var PropertyVisitor) =
    var played = false
    template play(c: AngleCut): bool = played
    template `play=`(c: AngleCut, f: bool) =
        played = f
        let anim = c.animation(2.0)
        c.node.addAnimation(anim)

    p.visitProperty("LineSize", c.whiteLineSize)
    p.visitProperty("angle", c.angle)
    p.visitProperty("offset", c.offset)
    p.visitProperty("play", c.play)

registerComponent(AngleCut, "Falcon")
