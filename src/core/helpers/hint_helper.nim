import random
import node_proxy / proxy
import utils / helpers
import nimx / [types, matrixes, animation]
import rod / [rod_types, node]
import rod / component / text_component


nodeProxy Hint:
    showHideAnimation Animation {withKey: "complete"}:
        loopPattern = lpStartToEnd
        cancelBehavior = cbJumpToEnd

    remainderAnimation Animation {withKey: "remainder"}:
        loopPattern = lpStartToEnd

    curAnimation Animation

    timeout float {withValue: 10.0}
    randTimeout float {withValue: 10.0}

    isHidden* bool

proc remaind*(h: Hint) =
    let timeout = h.timeout + rand(h.randTimeout)
    let pauseAnimation = newAnimation()
    pauseAnimation.numberOfLoops = 1
    pauseAnimation.loopDuration = timeout

    h.curAnimation = newCompositAnimation(false, pauseAnimation, h.remainderAnimation)
    h.curAnimation.numberOfLoops = 1
    h.curAnimation.onComplete do():
        if not h.curAnimation.isNil and not h.curAnimation.isCancelled:
            h.remaind()

    h.node.addAnimation(h.curAnimation)

proc show*(h: Hint, cb: proc() = nil) =
    if not h.isHidden:
        if not cb.isNil:
            if not h.curAnimation.isNil:
                h.curAnimation.onComplete(cb)
            else:
                cb()
        return
    h.isHidden = false

    if not h.curAnimation.isNil:
        h.curAnimation.cancel()
        h.curAnimation = nil

    h.node.alpha = 1.0
        
    h.showHideAnimation.removeHandlers()
    h.curAnimation = h.showHideAnimation
    h.curAnimation.loopPattern = lpStartToEnd
    h.curAnimation.onComplete do():
        if not h.curAnimation.isNil and not h.curAnimation.isCancelled:
            h.curAnimation = nil
            h.remaind()
            if not cb.isNil:
                cb()

    h.node.addAnimation(h.curAnimation)


proc hide*(h: Hint, cb: proc() = nil) =
    if h.isHidden:
        if not cb.isNil:
            if not h.curAnimation.isNil:
                h.curAnimation.onComplete(cb)
            else:
                cb()
        return
    h.isHidden = true

    if not h.curAnimation.isNil:
        h.curAnimation.cancel()
        h.curAnimation = nil

    h.showHideAnimation.removeHandlers()
    h.curAnimation = h.showHideAnimation
    h.curAnimation.loopPattern = lpEndToStart
    h.curAnimation.onComplete do():
        if not h.curAnimation.isNil and not h.curAnimation.isCancelled:
            h.curAnimation = nil
            h.node.alpha = 0.0
            if not cb.isNil:
                cb()

    h.node.addAnimation(h.curAnimation)


proc setVisible*(h: Hint, visible: bool) =
    if visible:
        h.show()
    else:
        h.hide()
        
    if not h.curAnimation.isNil:
        h.curAnimation.cancel()
        h.curAnimation = nil


proc newHint*(n: Node): Hint =
    result = Hint.new(n)
    result.isHidden = true
    result.node.alpha = 0.0


nodeProxy HintWithTitle of Hint:
    title* Text {onNode: "alert_text_@noloc"}:
        lineSpacing = -4.0
        bounds = newRect(-24.0, -39.0, 50.0, 50.0)
        verticalAlignment = vaCenter


proc `titleText=`*(h: HintWithTitle, txt: string) =
    h.title.text = txt
    case txt.len:
        of 1, 2:
            h.title.fontSize = 32
        of 3:
            h.title.fontSize = 28
        else:
            h.title.fontSize = 24


proc newHintWithTitle*(n: Node): HintWithTitle =
    result = HintWithTitle.new(n)
    result.isHidden = true
    result.node.alpha = 0.0