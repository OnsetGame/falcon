import nimx.view
import nimx.image
import nimx.context
import nimx.animation

import rod.rod_types
import rod.viewport
import rod.node
import rod.component
import rod.component.sprite
import rod.component.solid

type FadeAnimation* = ref object of RootObj
   node*: Node
   view*: SceneView
   animation*: Animation

type FadeSpriteAnimation* = ref object of FadeAnimation
   sprite: Sprite

type FadeSolidAnimation* = ref object of FadeAnimation
   solid: Solid

proc newFadeAnim(v: SceneView, parentNode: Node, start, to: float, duration: float): FadeAnimation =
    let fade = newNode()
    let animation = newAnimation()

    animation.numberOfLoops = 1
    fade.alpha = start
    if duration == 0:
        fade.alpha = to
    else:
        animation.loopDuration = duration
        animation.onAnimate = proc(p: float) =
            fade.alpha = interpolate(start, to, p)
        v.addAnimation(animation)
    parentNode.addChild(fade)

    result.new()
    result.node = fade
    result.view = v
    result.animation = animation


proc addFadeSolidAnim*(v: SceneView, parentNode: Node, color: Color, size: Size, start, to: float, duration: float): FadeSolidAnimation =
    let fade = newFadeAnim(v, parentNode, start, to, duration)
    let solid = fade.node.component(Solid)

    fade.node.name = "FadeSolid"
    solid.color = color
    solid.size = size

    result.new()
    result.node = fade.node
    result.animation = fade.animation
    result.solid = solid
    result.view = v

proc addFadeSpriteAnim*(v: SceneView, parentNode: Node, fadingImage: string, start, to: float, duration: float): FadeSpriteAnimation =
    let fade = newFadeAnim(v, parentNode, start, to, duration)
    let sprite = fade.node.component(Sprite)

    fade.node.name = "FadeSprite"
    sprite.image  = imageWithResource(fadingImage)

    result.new()
    result.node = fade.node
    result.animation = fade.animation
    result.sprite = sprite
    result.view = v

proc `image=`*(fadeAnim: FadeSpriteAnimation, newImage: string) =
    fadeAnim.sprite.image  = imageWithResource(newImage)

proc `alpha=`*(fadeAnim: FadeAnimation, value: float) =
    fadeAnim.node.alpha = value

proc `color=`*(fadeAnim: FadeSolidAnimation, color: Color) =
    fadeAnim.solid.color = color

proc changeFadeAnimMode*(fadeAnim: FadeAnimation, to: float, duration: float) =
    let alpha = fadeAnim.node.alpha

    fadeAnim.animation.loopDuration = duration
    fadeAnim.animation.onAnimate = proc(p: float) =
        fadeAnim.node.alpha = interpolate(alpha, to, p)

    fadeAnim.view.addAnimation(fadeAnim.animation)

proc removeFromParent*(fadeAnim: FadeAnimation) =
    if not fadeAnim.node.isNil:
        fadeAnim.node.removeFromParent()
