import json
import nimx / [types, context, image, composition, property_visitor ]

import rod.rod_types
import rod.node
import rod.component
import rod.component.sprite
import rod.viewport
import rod.utils.serialization_codegen

var outlineComposition = newComposition """
uniform Image uImage;
uniform vec4 uOutlineColor;
uniform float uAlpha;
uniform float uRadius;
const int uSteps = 12;

vec4 uvForvPos(vec2 v) {
    vec2 destuv = (v - bounds.xy - uRadius) / (bounds.zw - vec2(uRadius * 2.0));
    vec2 uv = uImage.texCoords.xy + (uImage.texCoords.zw - uImage.texCoords.xy) * destuv;

    vec2 mask = step(bounds.xy + uRadius, v) * step(v, bounds.xy + bounds.zw - uRadius);
    return texture2D(uImage.tex, uv) * mask.x * mask.y;
}

void compose()
{
    vec4 image = uvForvPos(vPos);
    float stroke = 0.0;

    for(int i = 0; i < uSteps; i++)
    {
        float r = radians(float((i * 2 + 1) * 180 / uSteps));
        vec2 offset = vec2(cos(r), -sin(r)) * uRadius;
        stroke += uvForvPos(vPos + offset).a;
    }

    stroke = smoothstep(0.0, 1.0, stroke / 2.0);
    vec3 f = mix(uOutlineColor.rgb, image.rgb, image.a);
    gl_FragColor = mix(vec4(f, 0.0), vec4(f, 1.0), stroke);
    gl_FragColor.a *= uAlpha;
}
"""

type Outline* = ref object of Component
    mRadius: float32
    color: Color
    image*: Image
    spriteOffset: Point

proc radius*(c: Outline): float32 = c.mRadius
proc `radius=`*(c: Outline, r: float32) =
    c.mRadius = r

method init(c: Outline) =
    c.mRadius = 4.0
    c.color = newColor(1.0, 1.0, 1.0, 1.0)

proc globalScale(n: Node): float32 =
    result = 1.0
    var p = n
    while not p.isNil and p.getComponent(Camera).isNil:
        result *= p.scale.x
        p = p.parent

method beforeDraw*(c: Outline, index: int): bool =
    let spr = c.node.getComponent(Sprite)
    if not spr.isNil:
        c.image = spr.image
        c.spriteOffset = spr.getOffset()
    result = true

proc drawOutlinedSprite(c: Outline, toRect: Rect, fromRect: Rect = zeroRect, alpha: ColorComponent = 1.0) =
    let i = c.image
    if not i.isNil and i.isLoaded:
        outlineComposition.draw toRect:
            setUniform("uAlpha", currentContext().alpha)
            setUniform("uImage", i)
            setUniform("uOutlineColor", c.color)
            setUniform("uRadius", c.mRadius / globalScale(c.node))

method draw*(c: Outline) =
    let scale = globalScale(c.node)
    if not c.image.isNil and scale > 0.0:
        let scaledRadius = c.mRadius / scale
        drawOutlinedSprite(c, newRect(newPoint(-scaledRadius, -scaledRadius) + c.spriteOffset, c.image.size + newSize(scaledRadius, scaledRadius) * 2.0))

method visitProperties*(c: Outline, p: var PropertyVisitor) =
    p.visitProperty("radius", c.mRadius)
    p.visitProperty("color", c.color)
    p.visitProperty("image", c.image)

genSerializationCodeForComponent(Outline)
registerComponent(Outline, "Falcon")
