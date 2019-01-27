import nimx.types
import nimx.image
import nimx.context
import nimx.composition
import nimx.portable_gl
import nimx.property_visitor

import json

import rod.node
import rod.viewport
import rod.component
import rod.component.sprite
import rod.tools.serializer

type MotionBlur* = ref object of Component
    prevWorldPos: Vector3
    sprite: Sprite
    bNeedBlur: bool

var effect = newPostEffect("""

#define numSamples 4

float rect_alpha(vec2 uvs, vec4 texCoord) {
    if (uvs.x < texCoord.x || uvs.x > texCoord.z || uvs.y < texCoord.y || uvs.y > texCoord.w) {
        return 0.0;
    } else {
        return 1.0;
    }
}

vec2 get_uv(vec4 texCoord, vec4 resolution) {
    vec2 destuv = (vPos - resolution.xy) / resolution.zw;
    return texCoord.xy + (texCoord.zw - texCoord.xy) * destuv;
}

vec4 blur_motion(sampler2D image, vec4 texCoord, vec4 resolution, vec2 direction) {
    vec2 uvs = get_uv(texCoord, resolution);
    vec2 velocity = direction / resolution.zw;
    vec4 color = texture2D(image, uvs, 2.0);

    color.a *= rect_alpha(uvs, texCoord);

    for(int i = 1; i < numSamples; ++i) {
        vec2 offset = velocity * (float(i) / float(numSamples - 1) - 0.5);
        vec2 currUv = uvs + offset;
        vec4 currCol = texture2D(image, currUv, 2.0);
        currCol.a *= rect_alpha(currUv, texCoord);
        color += currCol;
    }
    color /= float(numSamples);

    // if (rect_alpha(uvs, texCoord) < 0.9) {
    //     color = vec4(1,0,0,1);
    // }

    return color;
}

void motion_blur_effect(sampler2D uImage, vec4 texCoords, vec2 direction, vec4 imgBounds) {
    gl_FragColor = blur_motion(uImage, texCoords, imgBounds, direction);
}
""", "motion_blur_effect", ["sampler2D", "vec4", "vec2", "vec4"])

method deserialize*(c: MotionBlur, j: JsonNode, s: Serializer) =
    discard

var expandX = 5.0
var expandY = 50.0

method beforeDraw*(c: MotionBlur, index: int): bool =
    if c.sprite.isNil:
        let sprite = c.node.componentIfAvailable(Sprite)
        if sprite.isNil:
            return
        c.sprite = sprite

        c.prevWorldPos = c.node.worldPos()

    let currPos = c.node.worldPos()
    let diffPos = (c.prevWorldPos - currPos) / 32.0
    let direction = newSize(diffPos.x, diffPos.y)

    c.bNeedBlur = not ((diffPos.x > -1.0 and diffPos.x < 1.0) and (diffPos.y > -1.0 and diffPos.y < 1.0))

    if c.bNeedBlur:
        let gl = currentContext().gl
        var texQuad : array[4, GLfloat]
        let tex = getTextureQuad(c.sprite.image, gl, texQuad)
        let texRect = newRect(texQuad[0], texQuad[1], texQuad[2], texQuad[3])

        pushPostEffect(effect, tex, texRect, direction, newRect(c.sprite.getOffset(), c.sprite.image.size))

    c.prevWorldPos = currPos

method draw*(s: MotionBlur) =
    let c = currentContext()

    let i = s.sprite.image
    if not i.isNil:
        var r: Rect
        r.origin = s.sprite.getOffset()
        r.size = i.size
        if s.bNeedBlur:

            let oldOrg = r.origin
            let oldSize = r.size

            r.origin[0] = oldOrg[0] - expandX/2.0
            r.origin[1] = oldOrg[1] - expandY/2.0
            r.size[0] = oldSize[0] + expandX * 1.5
            r.size[1] = oldSize[1] + expandY * 1.5

            c.drawImage(i, r, zeroRect)

            r.origin = oldOrg
            r.size = oldSize
        else:
            c.drawImage(i, r, zeroRect)


method afterDraw*(c: MotionBlur, index: int) =
    if c.sprite.isNil or not c.bNeedBlur:
        return
    popPostEffect()

method isPosteffectComponent*(c: MotionBlur): bool = true

method visitProperties*(c: MotionBlur, p: var PropertyVisitor) =
    discard

registerComponent(MotionBlur, "Effects")
