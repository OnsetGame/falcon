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

type ReelSpin* = ref object of Sprite
    sources*: seq[Sprite]
    mSourcesPos*: seq[tuple[curr: Point, prev: Point]]


    image: Image

    cacheImg: Image

    mSize: Size

    currImg: bool

    fade: float32

    needUpdate: bool
    needUpdateCondition*: proc(): bool

template image*(s: ReelSpin): Image = s.image
proc `image=`*(s: ReelSpin, i: Image) =
    s.image = i
    s.needUpdate = true


template sourcesPos*(s: ReelSpin): Point = s.mSourcesPos[0].curr
proc `sourcesPos=`*(s: ReelSpin, p: Point) =
    # s.mSourcesPos[0].prev = s.mSourcesPos[0].curr
    s.mSourcesPos[0].curr = p

template size*(s: ReelSpin): Size = s.mSize
proc `size=`*(s: ReelSpin, sz: Size) =
    s.mSize = sz
    s.image = nil
    s.needUpdate = true

method init*(s: ReelSpin) =
    s.fade = 0.000002
    s.needUpdate = true
    s.needUpdateCondition = proc(): bool =
        return false

    procCall s.Sprite.init()

var reelSpinComposition = newComposition """
uniform sampler2D uImage;
uniform vec4 uImageTexCoords;
uniform float uFade;

uniform sampler2D uImage0;
uniform vec4 uImageTexCoords0;
uniform vec4 imgBounds0;
uniform vec2 uVelocity0;

uniform sampler2D uImage1;
uniform vec4 uImageTexCoords1;
uniform vec4 imgBounds1;
uniform vec2 uVelocity1;

uniform sampler2D uImage2;
uniform vec4 uImageTexCoords2;
uniform vec4 imgBounds2;
uniform vec2 uVelocity2;

uniform float uAlpha;

const int numSamples = 8;

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
    vec4 color = texture2D(image, uvs);
    color.a *= rect_alpha(uvs, texCoord);

    for (int i = 1; i < numSamples; ++i) {
        vec2 offset = velocity * (float(i) / float(numSamples - 1) - 0.5);
        vec2 currUv = uvs + offset;
        color += texture2D(image, currUv);
        color.a *= rect_alpha(currUv, texCoord);
    }
    color /= float(numSamples);

    return color;
}

vec4 blur5(sampler2D image, vec2 uv, vec2 resolution, vec2 direction) {
  vec4 color = vec4(0.0);
  vec2 off1 = vec2(1.3333333333333333) * direction;
  color += texture2D(image, uv) * 0.29411764705882354;
  color += texture2D(image, uv + (off1 / resolution)) * 0.35294117647058826;
  color += texture2D(image, uv - (off1 / resolution)) * 0.35294117647058826;
  return color;
}

vec4 blur5(sampler2D image, vec2 uv, vec2 resolution, vec2 direction, vec4 texCoord) {
  vec4 color = vec4(0.0);
  vec2 off1 = vec2(1.3333333333333333) * direction;
  vec4 currColor = vec4(0.0);
  vec2 currUv = vec2(0.0);
  color += texture2D(image, uv) * 0.29411764705882354;

  currUv = uv + (off1 / resolution);
  currColor = texture2D(image, currUv) * 0.35294117647058826;
  currColor.a *= rect_alpha(currUv, texCoord);
  if (currColor.a < 0.001) {
    color *= 0.35294117647058826;
  }
  color += currColor;

  currUv = uv - (off1 / resolution);
  currColor = texture2D(image, currUv) * 0.35294117647058826;
  currColor.a *= rect_alpha(currUv, texCoord);
  if (currColor.a < 0.001) {
    color *= 0.35294117647058826;
  }
  color += currColor;

  return color;
}

vec4 blur9(sampler2D image, vec2 uv, vec2 resolution, vec2 direction) {
  vec4 color = vec4(0.0);
  vec2 off1 = vec2(1.3846153846) * direction;
  vec2 off2 = vec2(3.2307692308) * direction;
  color += texture2D(image, uv) * 0.2270270270;
  color += texture2D(image, uv + (off1 / resolution)) * 0.3162162162;
  color += texture2D(image, uv - (off1 / resolution)) * 0.3162162162;
  color += texture2D(image, uv + (off2 / resolution)) * 0.0702702703;
  color += texture2D(image, uv - (off2 / resolution)) * 0.0702702703;
  return color;
}

void compose() {
    vec2 uv = get_uv(uImageTexCoords, bounds);
    vec4 bkg_color = blur5(uImage, uv, bounds.zw, vec2(1,1)+uVelocity0);
    bkg_color.a -= max(uFade, 0.0);

    vec2 uv0 = get_uv(uImageTexCoords0, imgBounds0);
    vec4 color0 = texture2D(uImage0, uv0);
    color0.a *= rect_alpha(uv0, uImageTexCoords0);

    vec3 col = bkg_color.rgb * (1.0 - color0.a) + color0.rgb * color0.a;

    float resAlpha = max(color0.a, bkg_color.a);

    vec4 color = vec4(col, resAlpha);

    gl_FragColor = color;
    gl_FragColor.a *= uAlpha;
}
"""

proc getSize(s: ReelSpin) =
    for sz in s.sources:
        if s.mSize.width < sz.image.size.width: s.mSize.width = sz.image.size.width
        if s.mSize.height < sz.image.size.height: s.mSize.height = sz.image.size.height

proc drawReelSpin*(s: ReelSpin, img: Image) =
    let gl = currentContext().gl

    var toRect = newRect(0.Coord, 0.Coord, s.size.width, s.size.height)

    reelSpinComposition.draw toRect:
        let cc = gl.getCompiledComposition(reelSpinComposition)

        gl.uniform1f(gl.getUniformLocation(cc.program, "uAlpha"), currentContext().alpha)

        var texQuad : array[4, GLfloat]
        for i in 0..2:
            gl.activeTexture(GLenum(int(gl.TEXTURE0) + i))
            gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(s.sources[i].image, gl, texQuad))
            gl.uniform4fv(gl.getUniformLocation(cc.program, "uImageTexCoords" & $i), texQuad)
            gl.uniform1i(gl.getUniformLocation(cc.program, "uImage" & $i), i.GLint)
            let bounds = newVector4(s.mSourcesPos[i].curr.x, s.mSourcesPos[i].curr.y, s.sources[i].image.size.width, s.sources[i].image.size.height)
            gl.uniform4fv(gl.getUniformLocation(cc.program, "imgBounds" & $i), bounds)


            if s.mSourcesPos[i].prev.x != s.mSourcesPos[i].curr.x:
                let diff = if (s.mSourcesPos[i].prev.x < s.mSourcesPos[i].curr.x): (s.mSourcesPos[i].curr.x-s.mSourcesPos[i].prev.x)/2.0 else: -(s.mSourcesPos[i].prev.x-s.mSourcesPos[i].curr.x)/2.0
                s.mSourcesPos[i].prev.x += diff
            if s.mSourcesPos[i].prev.y != s.mSourcesPos[i].curr.y:
                let diff = if s.mSourcesPos[i].prev.y < s.mSourcesPos[i].curr.y: (s.mSourcesPos[i].curr.y-s.mSourcesPos[i].prev.y)/2.0 else: -(s.mSourcesPos[i].prev.y-s.mSourcesPos[i].curr.y)/2.0
                s.mSourcesPos[i].prev.y += diff

            let pos = [s.mSourcesPos[i].curr.x-s.mSourcesPos[i].prev.x, s.mSourcesPos[i].curr.y-s.mSourcesPos[i].prev.y]
            gl.uniform2fv(gl.getUniformLocation(cc.program, "uVelocity" & $i), pos)

        gl.uniform1f(gl.getUniformLocation(cc.program, "uFade"), s.fade)

        gl.activeTexture(GLenum(int(gl.TEXTURE0) + 3))
        gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(img, gl, texQuad))
        gl.uniform4fv(gl.getUniformLocation(cc.program, "uImageTexCoords"), texQuad)
        gl.uniform1i(gl.getUniformLocation(cc.program, "uImage"), 3.GLint)

method draw*(s: ReelSpin) =
    if s.needUpdate:
        if s.image.isNil:
            if s.mSize.width == 0 or s.mSize.height == 0:
                s.getSize()
            s.image = imageWithSize(s.mSize)
            s.cacheImg = imageWithSize(s.mSize)

            s.image.SelfContainedImage.flipVertically()
            s.cacheImg.SelfContainedImage.flipVertically()

            let oldAlpha = currentContext().alpha
            let oldFade = s.fade
            s.fade = 1.0
            currentContext().alpha = 0.0

            s.image.draw proc() =
              s.drawReelSpin(s.cacheImg)
              s.image.SelfContainedImage.flipVertically()

            s.cacheImg.draw proc() =
                s.drawReelSpin(s.image)
                s.cacheImg.SelfContainedImage.flipVertically()

            currentContext().alpha = oldAlpha
            s.fade = oldFade

        s.needUpdate = s.needUpdateCondition()

    if s.currImg:
        s.image.draw proc() =
            s.drawReelSpin(s.cacheImg)
            s.image.SelfContainedImage.flipVertically()
    else:
        s.cacheImg.draw proc() =
            s.drawReelSpin(s.image)
            s.cacheImg.SelfContainedImage.flipVertically()

    s.currImg = not s.currImg

    var toRect = newRect(0.Coord, 0.Coord, s.size.width, s.size.height)
    if s.currImg:
        currentContext().drawImage(s.image, toRect, zeroRect)
    else:
        currentContext().drawImage(s.cacheImg, toRect, zeroRect)

proc createFrameAnimation(s: Sprite) {.inline.} =
    let a = newAnimation()
    const fps = 1.0 / 30.0
    a.loopDuration = float(s.images.len) * fps
    a.continueUntilEndOfLoopOnCancel = true
    a.onAnimate = proc(p: float) =
        s.currentFrame = int(float(s.images.len - 1) * p)
    s.node.registerAnimation("sprite", a)

method visitProperties*(s: ReelSpin, p: var PropertyVisitor) =
    p.visitProperty("img", s.image)

    p.visitProperty("ch_img", s.cacheImg)

    p.visitProperty("size", s.size)
    p.visitProperty("fade", s.fade)
    p.visitProperty("pos0", s.sourcesPos)
    # p.visitProperty("pos1", s.mSourcesPos[1])
    # p.visitProperty("pos2", s.mSourcesPos[2])

registerComponent(ReelSpin)
