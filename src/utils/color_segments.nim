import math

import nimx / [ types, context, composition, property_visitor, view ]
import rod / [ rod_types, node, component, viewport ]
import rod / utils / [ property_desc, serialization_codegen ]

import utils.helpers

var colorSegments = newPostEffect("""
void angle_effect(vec2 center, float tangle1, float tangle2, vec4 color1, vec4 color2, vec4 color3, vec4 color4)
{
    float a = gl_FragColor.a;
    float x_angle = (gl_FragCoord.y - center.y) * tangle1;
    float y_angle = (gl_FragCoord.x - center.x) * tangle2;

    vec4 mixTop = mix(color1, color2, step(center.x + x_angle, gl_FragCoord.x));
    vec4 mixBot = mix(color3, color4, step(center.x + x_angle, gl_FragCoord.x));
    gl_FragColor = mix(mixBot, mixTop, step(center.y + y_angle, gl_FragCoord.y));

    gl_FragColor.a *= a;
}
""", "angle_effect", ["vec2", "float", "float", "vec4", "vec4", "vec4", "vec4"])

type ColorSegments* = ref object of Component
    center: Point
    angle1*, angle2*: float32
    color1*, color2*, color3*, color4*: Color

ColorSegments.properties:
    angle1
    angle2
    color1
    color2
    color3
    color4

method init(c: ColorSegments) =
    c.angle1 = 0.0
    c.angle2 = 0.0
    c.color1 = newColor(1.0, 0.0, 0.0, 1.0)
    c.color2 = newColor(0.0, 1.0, 0.0, 1.0)
    c.color3 = newColor(0.0, 0.0, 1.0, 1.0)
    c.color4 = newColor(1.0, 1.0, 1.0, 1.0)

method beforeDraw*(c: ColorSegments, index: int): bool =
    let bbox = c.node.nodeBounds()
    var size = newVector3(bbox.maxPoint.x - bbox.minPoint.x, bbox.maxPoint.y - bbox.minPoint.y, 0.0)
    size = size / 2.0

    let fromInWorld = c.node.sceneView.worldToScreenPoint(bbox.minPoint + size)
    var winFromPos = c.node.sceneView.convertPointToWindow(newPoint(fromInWorld.x, fromInWorld.y))
    let pr = c.node.sceneView.window.pixelRatio
    let winSize = c.node.sceneView.window.bounds.size

    c.center = newPoint(winFromPos.x * pr, (winSize.height - winFromPos.y) * pr )

    pushPostEffect(colorSegments, c.center, tan(degToRad(c.angle1)), tan(degToRad(c.angle2)), c.color1, c.color2, c.color3, c.color4)

method afterDraw*(c: ColorSegments, index: int) =
    popPostEffect()

method visitProperties*(c: ColorSegments, p: var PropertyVisitor) =
    p.visitProperty("center", c.center)
    p.visitProperty("angle1", c.angle1)
    p.visitProperty("angle2", c.angle2)
    p.visitProperty("color1", c.color1)
    p.visitProperty("color2", c.color2)
    p.visitProperty("color3", c.color3)
    p.visitProperty("color4", c.color4)

genSerializationCodeForComponent(ColorSegments)
registerComponent(ColorSegments, "Falcon")
