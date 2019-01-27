import nimx.types
import nimx.context
import nimx.portable_gl
import nimx.property_visitor
import nimx.image
import nimx.view
import nimx.render_to_image
import nimx.composition

import rod.node
import rod.component
import rod.component.text_component
import rod.component.solid
import rod.viewport
import rod.tools.serializer

import opengl
import json

type TextMask* = ref object of Component
    resolution: Rect
    image: SelfContainedImage
    solidColor*: Color
    textColor*: Color
    solid*: Solid
    text*: seq[Text]
    bBlend*: bool
    bBlendMultiply*: bool
    bUseSameClor*: bool

proc recursiveDrawText(n: Node) =
    if n.alpha < 0.0000001: return
    let c = currentContext()
    var mvp = n.mSceneView.viewProjMatrix * n.worldTransform()
    let oldAlpha = c.alpha
    c.alpha *= n.alpha
    c.withTransform mvp:
        var hasPosteffectComponent = false
        if n.components.len != 0:
            let txt = n.componentIfAvailable(Text)
            if not txt.isNil:
                txt.draw()
                hasPosteffectComponent = hasPosteffectComponent or txt.isPosteffectComponent()
    if not hasPosteffectComponent:
        for c in n.children: c.recursiveDrawText()
    c.alpha = oldAlpha

var imageColorComposition = newComposition """
uniform Image uImage;
uniform vec4 uColor;
uniform float uAlpha;

void compose() {
    vec2 destuv = (vPos - bounds.xy) / bounds.zw;
    vec2 duv = uImage.texCoords.zw - uImage.texCoords.xy;
    vec2 srcxy = uImage.texCoords.xy;
    vec2 srczw = uImage.texCoords.xy + duv;
    vec2 uv = srcxy + (srczw - srcxy) * destuv;
    float a = texture2D(uImage.tex, uv).a;
    a = (1.0 - a) * uAlpha;
    gl_FragColor = uColor * a;
}
"""

proc drawImageColor(c: GraphicsContext, i: Image, toRect: Rect, color: Color) =
    if i.isLoaded:
        let s = i.size
        imageColorComposition.draw toRect:
            setUniform("uImage", i)
            setUniform("uAlpha", c.alpha)
            setUniform("uColor", color)

proc getFirstSolid(n: Node, solid: var Solid) =
    let s = n.componentIfAvailable(Solid)
    if not s.isNil:
        solid = s
    for c in n.children:
        c.getFirstSolid(solid)

proc getFirstText(n: Node, text: var seq[Text]) =
    let t = n.componentIfAvailable(Text)
    if not t.isNil:
        text.add(t)
    for c in n.children:
        c.getFirstText(text)

proc checkResolution(tm: TextMask) =
    let vp = tm.node.sceneView
    let currWidth = vp.bounds.width
    let currHeight = vp.bounds.height
    if currWidth != tm.resolution.width or currHeight != tm.resolution.height:
        tm.resolution = vp.bounds

        if not tm.image.isNil:
            let gl = currentContext().gl
            gl.deleteFramebuffer(tm.image.framebuffer)
            gl.deleteTexture(tm.image.texture)
            tm.image.framebuffer = invalidFrameBuffer
            tm.image.texture = invalidTexture
            tm.image = nil

        if tm.image.isNil:
            tm.image = imageWithSize(newSize(tm.resolution.width, tm.resolution.height))

proc checkText(tm: TextMask) =
    if tm.text.len == 0:
        tm.node.getFirstText(tm.text)
        for txt in tm.text:
            let alpha = txt.node.getGlobalAlpha()
            if alpha > 0.0001:
                tm.textColor = txt.color * alpha
                return
    else:
        for txt in tm.text:
            let alpha = txt.node.getGlobalAlpha()
            if alpha > 0.0001:
                tm.textColor = txt.color * alpha
                return

proc checkSolid(tm: TextMask) =
    if tm.solid.isNil:
        tm.node.getFirstSolid(tm.solid)
        if not tm.solid.isNil:
            tm.solidColor = tm.solid.color * tm.solid.node.getGlobalAlpha()
    else:
        tm.solidColor = tm.solid.color * tm.solid.node.getGlobalAlpha()

method init*(tm: TextMask) =
    procCall tm.Component.init()
    tm.bBlendMultiply = true
    tm.bUseSameClor = true
    tm.text = @[]

method draw*(tm: TextMask) =
    let c = currentContext()
    let gl = c.gl

    tm.checkSolid()

    if not tm.bUseSameClor:
        tm.checkText()

    tm.checkResolution()

    var mvp = tm.node.sceneView.getViewProjectionMatrix() * tm.node.worldTransform()

    if tm.bBlendMultiply:
        gl.enable(gl.BLEND)
        gl.blendFuncSeparate(gl.DST_COLOR, gl.ONE_MINUS_SRC_ALPHA, gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
        # gl.blendFuncSeparate(gl.DST_COLOR, gl.ZERO, gl.ZERO, gl.SRC_ALPHA)
    elif tm.bBlend:
        gl.enable(gl.BLEND)
        gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

    c.withTransform mvp:
        let oldColor = tm.solid.color
        tm.solid.color = if tm.bUseSameClor: tm.solidColor else: tm.textColor
        tm.solid.draw()
        tm.solid.color = oldColor

    tm.image.draw proc() =
        c.withTransform mvp:
            let txt = tm.node.componentIfAvailable(Text)
            if not txt.isNil: txt.draw()
            for n in tm.node.children: n.recursiveDrawText()

    c.withTransform ortho(tm.resolution.x, tm.resolution.width, tm.resolution.height, tm.resolution.y, -1, 1):
        c.drawImageColor(tm.image, tm.resolution, tm.solidColor)
        tm.image.flipVertically()

    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

method isPosteffectComponent*(tm: TextMask): bool = true

method visitProperties*(tm: TextMask, p: var PropertyVisitor) =
    p.visitProperty("color", tm.solidColor)
    p.visitProperty("color", tm.textColor)
    p.visitProperty("blend", tm.bBlend)
    p.visitProperty("mult", tm.bBlendMultiply)
    p.visitProperty("same color", tm.bUseSameClor)

registerComponent(TextMask)
