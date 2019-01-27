import rod / [node, component, viewport]
import nimx / animation
import tables

type AnimatorState = enum
    asIn
    asIdle
    asOut
    asEnd

type Animator* = ref object of Component
    autostart*: bool
    mInAnimation: Animation
    mIdleAnimation: Animation
    mOutAnimation: Animation
    state: AnimatorState

proc `inAnimation=`*(c: Animator, a: Animation)=
    c.mInAnimation = a

proc inAnimation*(c: Animator): Animation = c.mInAnimation

proc `idleAnimation=`*(c: Animator, a: Animation)=
    c.mIdleAnimation = a

proc idleAnimation*(c: Animator): Animation = c.mIdleAnimation

proc `outAnimation=`*(c: Animator, a: Animation)=
    c.mOutAnimation = a

proc outAnimation*(c: Animator): Animation = c.mOutAnimation

proc stop*(c: Animator)=
    var a: Animation
    case c.state:
    of asIn:
        a = c.mInAnimation
    of asIdle:
        a = c.mIdleAnimation
    of asOut:
        a = c.mOutAnimation
    else:
        return

    if not a.isNil:
        a.cancel()

proc incState(s: AnimatorState): AnimatorState = clamp(int(s) + 1, 0, asEnd.int).AnimatorState

proc start*(c: Animator, state = asIn)=
    if c.node.isNil or c.node.sceneView.isNil: return
    var a: Animation
    case state:
    of asIn:
        a = c.mInAnimation
    of asIdle:
        a = c.mIdleAnimation
    of asOut:
        a = c.mOutAnimation
    else:
        return

    let st = state
    if not a.isNil:
        a.onComplete do():
            c.state = st
            c.start(state.incState())
        c.node.sceneView.addAnimation(a)
    else:
        c.start(state.incState())

method componentNodeWasAddedToSceneView*(c: Animator)=
    if c.autostart:
        c.start()

method componentNodeWillBeRemovedFromSceneView*(c: Animator)=
    c.stop()

registerComponent(Animator, "Falcon")
