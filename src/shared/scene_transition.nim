import nimx.types
import nimx.animation
import nimx.matrixes
import nimx.view
import nimx.view_render_to_image
import nimx.render_to_image
import nimx.image
import nimx.context
import nimx.window
import nimx.timer
import nimx.composition

import logging

var crossFadeComposition = newComposition """
uniform Image uImgOne;
uniform Image uImgTwo;
uniform float uProg;
uniform vec4 uFromRect;

void compose()
{
    vec2 destuv = (vPos - bounds.xy) / bounds.zw;
    vec2 duv = uImgOne.texCoords.zw - uImgOne.texCoords.xy;
    vec2 srcxy = uImgOne.texCoords.xy + duv * uFromRect.xy;
    vec2 srczw = uImgOne.texCoords.xy + duv * uFromRect.zw;
    vec2 uv = srcxy + (srczw - srcxy) * destuv;
    vec4 t0 = texture2D(uImgOne.tex, uv);
    vec4 t1 = texture2D(uImgTwo.tex, uv);

    //gl_FragColor = (1.0 - uProg) * t0 + uProg * t1;
    gl_FragColor = mix(t0, t1, uProg);
}
"""

type Transition* = ref object of View
    onTransitionDone*: proc()
    duration: float

type ImageTransition* = ref object of Transition
    imageFrom: SelfContainedImage
    imageTo: SelfContainedImage
    viewFrom: View
    viewTo: View
    renderCount: int

type FadeTransition* = ref object of ImageTransition
    currProgress: float
    imageToAlpha: float
    imageFromAlpha: float

proc makeViewImages(t: ImageTransition)=
    if not t.viewFrom.isNil:
        t.viewFrom.hidden = false
        t.viewFrom.renderToImage(t.imageFrom)
        t.viewFrom.hidden = true

    if not t.viewTo.isNil:
        t.viewTo.hidden = false
        t.viewTo.renderToImage(t.imageTo)
        t.viewTo.hidden = true

    inc t.renderCount

proc initImageTransition(t: ImageTransition, viewFrom, viewTo: View, duration: float)=
    var initialized = false
    t.renderCount = 0

    if not viewTo.isNil:
        t.viewTo = viewTo
        t.viewTo.hidden = true
        if not initialized:
            t.init(viewTo.frame)
            initialized = true
        t.imageTo = imageWithSize(t.viewTo.bounds.size)

    if not viewFrom.isNil:
        t.viewFrom = viewFrom
        t.viewFrom.hidden = true
        t.init(viewFrom.frame)
        initialized = true
        t.imageFrom = imageWithSize(t.viewFrom.bounds.size)
    else:
        t.imageFrom = imageWithSize(t.viewTo.bounds.size)
        t.imageFrom.draw do():
            let c = currentContext()
            c.fillColor = newColor(0.0, 0.0, 0.0, 1.0)
            c.drawRect(newRect(0, 0, t.viewTo.bounds.width, t.viewTo.bounds.height))

    t.makeViewImages()

    assert(initialized)

    t.backgroundColor = newColor(0.0, 0.0, 0.0, 1.0)
    t.duration = duration

proc newFadeTransition*(w: Window, viewFrom, viewTo: View, duration: float): FadeTransition=
    let r = new(FadeTransition)

    viewTo.window = w #hack
    r.initImageTransition(viewFrom, viewTo, duration)
    viewTo.window = nil

    let transitionAnim = newAnimation()
    transitionAnim.numberOfLoops = 1
    transitionAnim.loopDuration = duration
    transitionAnim.cancelBehavior = cbJumpToEnd
    transitionAnim.onAnimate = proc(p: float)=
        r.currProgress = p
        r.imageToAlpha = interpolate(0.0, 1.0, p)
        r.imageFromAlpha = interpolate(1.0, 0.0, p)

    transitionAnim.onComplete do():
        # r.removeFromSuperview()
        if not r.onTransitionDone.isNil:
            r.onTransitionDone()

    w.addSubview(r)
    w.addAnimation(transitionAnim)
    result = r

import times

method draw*(it: FadeTransition, rect: Rect) =
    let c = currentContext()
    if it.backgroundColor.a > 0.001:
        c.fillColor = it.backgroundColor
        c.strokeWidth = 0
        c.drawRect(it.bounds)

        var st = epochTime()
        let gl = c.gl
        it.makeViewImages()
        if epochTime() - st > 0.05:
            info "renderToImage stuck ", epochTime() - st

        st = epochTime()

        gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA)

        var fr = newRect(0, 0, 1, 1)
        crossFadeComposition.draw rect:
            setUniform("uImgOne", it.imageFrom)
            setUniform("uImgTwo", it.imageTo)
            setUniform("uProg", it.currProgress)
            setUniform("uFromRect", fr)

        gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

        if epochTime() - st > 0.05:
            info "renderImage stuck ", epochTime() - st
