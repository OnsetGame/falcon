import rod.node
import rod.viewport
import nimx.animation
import pause, random, logging, sequtils
import utils.helpers

type AnimationController* = ref object
    node*: Node
    curAnimation*: Animation
    idleAnims: seq[string]
    currentIdle: int
    pauseless*: seq[Animation]

proc newAnimationControllerForNode*(n: Node): AnimationController =
    result.new()
    result.node = n
    result.idleAnims = @[]
    result.currentIdle = 0
    result.pauseless = @[]

proc addIdles*(ac: AnimationController, idles: openarray[string]) =
    for idle in idles:
        ac.idleAnims.add(idle)

proc playAnimation(ac: AnimationController, name: string): Animation {.discardable.} =
    doAssert(not ac.node.sceneView.isNil)
    let newAnim = ac.node.animationNamed(name)
    newAnim.continueUntilEndOfLoopOnCancel = true

    if ac.curAnimation.isNil or ac.curAnimation.finished:
        ac.curAnimation = newAnim
        ac.node.addAnimation(newAnim)
    else:
        ac.curAnimation.removeHandlers()
        ac.curAnimation.onComplete do():
            ac.node.addAnimation(newAnim)

    result = ac.node.animationNamed(name)

proc playIdles*(ac: AnimationController, atRandom: bool = false) =
    if ac.idleAnims.len == 0:
        info "Idle animations were not found!"
        return
    let anim = ac.playAnimation(ac.idleAnims[ac.currentIdle])
    anim.tag = ACTIVE_SOFT_PAUSE
    anim.onComplete do():
        if ac.idleAnims.len > 1:
            if atRandom:
                ac.currentIdle = rand(ac.idleAnims.high)
            else:
                ac.currentIdle.inc()
                if ac.currentIdle == ac.idleAnims.len:
                    ac.currentIdle = 0

        ac.playIdles(atRandom)

proc stopIdles*(ac: AnimationController) =
    for animName in ac.idleAnims:
        let animation = ac.node.animationNamed(animName)
        if not animation.isNil:
            animation.cancelBehavior = cbNoJump
            animation.cancel()

proc setNextAnimation*(ac: AnimationController, name: string, returnToIdle: bool = true): Animation {.discardable.} =
    ## Start animation with corresponding name as soon as current animation
    ## ends.
    result = ac.playAnimation(name)
    if returnToIdle:
        result.onComplete do():
            ac.playIdles()

proc setImmediateAnimation*(ac: AnimationController, name: string, returnToIdle: bool = true): Animation {.discardable.} =
    ## Start animation with corresponding name immediately
    result = ac.node.animationNamed(name)

    if not ac.pauseless.contains(ac.curAnimation):
        if not ac.curAnimation.isNil:
            ac.curAnimation.continueUntilEndOfLoopOnCancel = false
            ac.curAnimation.removeHandlers()
            ac.curAnimation.cancel()
        ac.curAnimation = result
        ac.node.addAnimation(result)
        if returnToIdle:
            result.onComplete do():
                ac.playIdles()
        result.continueUntilEndOfLoopOnCancel = true
    else:
        info "You are trying to interrupt pauseless animation!"


