import nimx.types
import nimx.context
import nimx.image
import nimx.composition
import nimx.portable_gl
import nimx.property_visitor
import nimx.render_to_image
import nimx.animation

import rod.component
import rod.component.sprite
import rod.tools.serializer
import rod.utils.image_serialization
import rod.node

import json, strutils

type RoundedSprite* = ref object of Sprite
    cachedImage*: Image
    discColor*: Color
    mBorderSize: float32
    mDiscRadius: float32
    discCenterSumDiff: Rect
    needUpdate: bool
    needUpdateCondition*: proc(): bool

template updateSumDiff(s: RoundedSprite) =
    s.discCenterSumDiff.size = newSize(s.mDiscRadius + s.mBorderSize, s.mDiscRadius - s.mBorderSize)
    s.needUpdate = true

template discCenter*(s: RoundedSprite): Point = s.discCenterSumDiff.origin
proc `discCenter=`*(s: RoundedSprite, v: Point) =
    s.discCenterSumDiff.origin = v
    s.needUpdate = true

template borderSize*(s: RoundedSprite): float32 = s.mBorderSize
proc `borderSize=`*(s: RoundedSprite, v: float32) =
    s.mBorderSize = v
    s.updateSumDiff()

template discRadius*(s: RoundedSprite): float32 = s.mDiscRadius
proc `discRadius=`*(s: RoundedSprite, v: float32) =
    s.mDiscRadius = v
    s.updateSumDiff()

template image*(s: RoundedSprite): Image = s.Sprite.image
proc `image=`*(s: RoundedSprite, i: Image) =
    s.Sprite.image = i
    s.needUpdate = true

method init*(s: RoundedSprite) =
    procCall s.Sprite.init()
    s.mBorderSize = -0.01
    s.mDiscRadius = 0.34
    s.discColor = newColor(1.0, 1.0, 1.0, 0.0)
    s.discCenter = newPoint(0.5, 0.5)
    s.needUpdate = true
    s.needUpdateCondition = proc(): bool =
        return false

var roundedSpriteComposition = newComposition """
uniform Image uImage;
uniform vec4 uFromRect;
uniform float uAlpha;
uniform vec4 uDiscColor;
uniform vec4 uDiscCenterSumDiff;

void compose() {
    vec2 destuv = (vPos - bounds.xy) / bounds.zw;
    vec2 duv = uImage.texCoords.zw - uImage.texCoords.xy;
    vec2 srcxy = uImage.texCoords.xy + duv * uFromRect.xy;
    vec2 srczw = uImage.texCoords.xy + duv * uFromRect.zw;
    vec2 uv = srcxy + (srczw - srcxy) * destuv;

    vec4 bkgColor = texture2D(uImage.tex, uv);

    duv = (uImage.texCoords.zw - uImage.texCoords.xy) * uDiscCenterSumDiff.xy;
    uv -= duv;

    float dist = sqrt(dot(uv, uv));
    float step = smoothstep(uDiscCenterSumDiff.z, uDiscCenterSumDiff.w, dist);

    gl_FragColor = mix(bkgColor, uDiscColor, step);
    gl_FragColor.a *= uAlpha;
}
"""

proc drawRoundedSprite*(c: GraphicsContext, s: RoundedSprite, toRect: Rect, fromRect: Rect = zeroRect, alpha: ColorComponent = 1.0) =
    let i = s.image
    if not i.isNil and i.isLoaded:
        var fr: Rect
        if fromRect == zeroRect:
            fr = newRect(0, 0, 1, 1)
        else:
            let sz = i.size
            fr = newRect(fromRect.x    / sz.width, fromRect.y    / sz.height,
                         fromRect.maxX / sz.width, fromRect.maxY / sz.height)
        roundedSpriteComposition.draw toRect:
            setUniform("uImage", i)
            setUniform("uAlpha", alpha * c.alpha)
            setUniform("uFromRect", fr)
            setUniform("uDiscColor", s.discColor )
            setUniform("uDiscCenterSumDiff", s.discCenterSumDiff)

method draw*(s: RoundedSprite) =
    if s.needUpdate:
        if s.cachedImage.isNil:
            let i = s.image
            if not i.isNil:
                s.cachedImage = imageWithSize(i.size)
            # s.cachedImage.SelfContainedImage.flipVertically()

        if not s.cachedImage.isNil:
            let gl = currentContext().gl
            let scissorState = gl.getParamb(gl.SCISSOR_TEST)
            if scissorState:
                gl.disable(gl.SCISSOR_TEST)

            s.cachedImage.draw proc() =
                if not s.image.isNil:
                    currentContext().drawRoundedSprite(s, newRect(s.offset, s.image.size))
                    # s.cachedImage.SelfContainedImage.flipVertically()
            if scissorState:
                gl.enable(gl.SCISSOR_TEST)

        s.needUpdate = s.needUpdateCondition()

    if not s.cachedImage.isNil:
        currentContext().drawImage(s.cachedImage, newRect(s.offset, s.cachedImage.size))

method deserialize*(s: RoundedSprite, j: JsonNode, serealizer: Serializer) =
    procCall s.Sprite.deserialize(j, serealizer)
    serealizer.deserializeValue(j, "discColor",  s.discColor )
    serealizer.deserializeValue(j, "discCenter", s.discCenter)
    serealizer.deserializeValue(j, "borderSize", s.borderSize)
    serealizer.deserializeValue(j, "discRadius", s.discRadius)

method serialize*(rs: RoundedSprite, s: Serializer): JsonNode =
    result = procCall rs.Sprite.serialize(s)
    result.add("discColor" , s.getValue(rs.discColor ))
    result.add("discCenter", s.getValue(rs.discCenter))
    result.add("borderSize", s.getValue(rs.borderSize))
    result.add("discRadius", s.getValue(rs.discRadius))

method visitProperties*(s: RoundedSprite, p: var PropertyVisitor) =
    p.visitProperty("source img", s.image)
    p.visitProperty("cached img", s.cachedImage)
    p.visitProperty("discColor ", s.discColor )
    p.visitProperty("discCenter", s.discCenter)
    p.visitProperty("borderSize", s.borderSize)
    p.visitProperty("discRadius", s.discRadius)

registerComponent(RoundedSprite)
