import nimx.view
import nimx.matrixes
import nimx.animation

import rod.rod_types
import rod.node
import rod.viewport
import rod.component
import rod.component.clipping_rect_component
import rod.component.particle_system
import rod.component.visual_modifier
import rod.quaternion

import random
import utils.helpers
import utils.fade_animation
import utils.sound_manager
import core.slot.base_slot_machine_view

proc randomizeDrops(placeholder: Node): Node =
    result = placeholder.findNode("spin_drops")
    var rotations: seq[Quaternion] = @[]
    var positions: seq[Vector3] = @[]
    var scales: seq[Vector3] = @[]
    var nums: seq[int] = @[0, 1, 2, 3]
    var nums2:seq[int] = @[]
    for c in result.children:
        rotations.add(c.rotation)
        positions.add(c.position)
        scales.add(c.scale)

    for i in 0..<3:
        let r = rand(nums.len - 1)
        nums2.add(nums[r])
        nums.del(r)
    nums2.add(nums[0])

    for i in 0..<result.children.len:
        let c = result.children[i]
        c.rotation = rotations[nums2[i]]
        c.position = positions[nums2[i]]
        c.scale = scales[nums2[i]]


proc playWinAnim*(placeholder: Node, sym: int) =
    if sym != 2:
        let drops = randomizeDrops(placeholder)
        drops.alpha = 1.0
        for c in drops.children:
            let anim = c.animationNamed("play")
            placeholder.sceneView().addAnimation(anim)
            anim.onComplete do():
                drops.alpha = 0

proc startLollipop*(rootNode: Node): Animation {.discardable.} =
    let lollipop = rootNode.findNode("lollipop")
    result = lollipop.animationNamed("play")
    let parent = lollipop.findNode("parent")

    result.numberOfLoops = -1
    rootNode.sceneView().addAnimation(result)
    parent.component(ClippingRectComponent).clippingRect = newRect(0, 0, 300, 400)

proc startAirplane*(rootNode: Node): Animation {.discardable.} =
    let airplane = rootNode.findNode("airplane")
    result = airplane.animationNamed("play")
    result.numberOfLoops = -1
    rootNode.sceneView().addAnimation(result)

proc startLights*(rootNode: Node): Animation {.discardable.} =
    result = rootNode.animationNamed("play")
    result.numberOfLoops = -1
    rootNode.sceneView().addAnimation(result)

proc setRouletteScissor*(rootNode: Node) =
    let parent = rootNode.findNode("roulette_parent")
    parent.component(ClippingRectComponent).clippingRect = newRect(0, -50, 2000, 0)

proc moveRoulette*(v:BaseMachineView,  down: bool): Animation {.discardable.} =
    let roulette = v.rootNode.findNode("roulette")
    result = roulette.animationNamed("play")
    let parent = roulette.findNode("roulette_parent")

    v.soundManager.playSFX("slots/candy_slot/candy_sound/candy_curtain_shuts")
    if down:
        result.loopPattern = LoopPattern.lpStartToEnd
        chainOnAnimate result, proc(p: float) =
            let scissorY = (interpolate(0, 850, p)).Coord
            parent.component(ClippingRectComponent).clippingRect = newRect(0, -10, 2000, scissorY + 8)
    else:
        result.loopPattern = LoopPattern.lpEndToStart
    v.addAnimation(result)

proc addSteam*(rootNode: Node) =
    let trains = @["start", "front", "end"]

    for trainName in trains:
        let loco = rootNode.findNode("train_" & trainName).findNode("train_01.png")
        let particle = newLocalizedNodeWithResource("slots/candy_slot/particles/steam_train.json")

        loco.addChild(particle)
        particle.position = newVector3(165, 17)

proc startSteam*(rootNode: Node, trainName: string) =
    let steam = rootNode.findNode(trainName).findNode("par")
    steam.component(ParticleSystem).start()
    steam.alpha = 1

proc stopSteam*(rootNode: Node, trainName: string) =
    let steam = rootNode.findNode(trainName).findNode("par")
    let anim = newAnimation()

    anim.loopDuration = 1.5
    anim.numberOfLoops = 1
    rootNode.sceneView().addAnimation(anim)
    anim.onComplete do():
        steam.alpha = 0
    steam.component(ParticleSystem).stop()

proc addCarriage*(rootNode: Node, index: int, show: bool) =
    let carriage = rootNode.findNode("scatter_jello_train_" & $index & ".png")

    if show:
        carriage.alpha = 1
    else:
        carriage.alpha = 0

proc startTrain*(rootNode: Node, sm: SoundManager): Animation {.discardable.} =
    let startTrain = rootNode.findNode("train_start")
    let backTrain = rootNode.findNode("train_front")
    let endTrain = rootNode.findNode("train_end")

    result = startTrain.animationNamed("move")

    startTrain.alpha = 1
    backTrain.alpha = 0
    endTrain.alpha = 0
    sm.playSFX("slots/candy_slot/candy_sound/candy_train")
    rootNode.sceneView().addAnimation(result)
    rootNode.startSteam("train_start")
    result.onComplete do():
        rootNode.stopSteam("train_start")
        startTrain.alpha = 0
        backTrain.alpha = 1

proc backTrain*(rootNode: Node, sm: SoundManager): Animation {.discardable.} =
    let startTrain = rootNode.findNode("train_start")
    let backTrain = rootNode.findNode("train_front")

    result = backTrain.animationNamed("move")
    sm.playSFX("slots/candy_slot/candy_sound/candy_train")
    backTrain.alpha = 1
    rootNode.sceneView().addAnimation(result)
    rootNode.startSteam("train_front")
    result.onComplete do():
        rootNode.stopSteam("train_front")
        backTrain.alpha = 0
        startTrain.alpha = 0

proc endTrain*(rootNode: Node): Animation {.discardable.} =
    let endTrain = rootNode.findNode("train_end")

    result = endTrain.animationNamed("move")
    rootNode.sceneView().addAnimation(result)
    result.addLoopProgressHandler 0.1, false, proc() =
        endTrain.alpha = 1
    result.addLoopProgressHandler 0.3, false, proc() =
        rootNode.startSteam("train_end")
    result.addLoopProgressHandler 0.7, false, proc() =
        rootNode.stopSteam("train_end")

proc startCandyFirework*(parent: Node, index: int, wildAnim: Animation) =
    let v = parent.sceneView()
    var positions: seq[Vector3] = @[]

    positions.add(newVector3(700, -370))
    positions.add(newVector3(700, -170))
    positions.add(newVector3(700, 30))

    wildAnim.addLoopProgressHandler 0.35, false, proc() =
        let firework = newLocalizedNodeWithResource("slots/candy_slot/boy/precomps/firework.json")
        firework.position = newVector3(-170, -20)

        let s = firework.position
        let e = positions[index]
        let c1 = newVector3((260).float, (-400).float)
        let c2 = newVector3((550).float, (-400).float)
        let fly = newAnimation()
        fly.numberOfLoops = 1
        fly.loopDuration = 0.55
        fly.onAnimate = proc(p: float) =
            let t = interpolate(0.0, 1.0, p)
            let point = calculateBezierPoint(t, s, e, c1, c2)
            firework.position = point

        let anim = firework.animationNamed("play")
        v.addAnimation(anim)
        anim.onComplete do():
            v.addAnimation(fly)
            v.addAnimation(firework.animationNamed("go"))

        let animPetard = firework.findNode("petard").animationNamed("play")
        let trail = newLocalizedNodeWithResource("slots/candy_slot/slot/precomps/trail_petard.json")
        anim.addLoopProgressHandler 0.15, false, proc() =
            firework.findNode("sparks_3").addChild(trail)
            discard firework.findNode("parent_trail_petard").component(VisualModifier)
            v.addAnimation(animPetard)

        animPetard.addLoopProgressHandler 0.47, false, proc() =
            let fade = addFadeSolidAnim(v, v.rootNode, whiteColor(), VIEWPORT_SIZE, 1.0, 0.0, 0.3)
            let lights = v.rootNode.findNode("lights")
            let shakeAnim = lights.animationNamed("shake")
            let boomLight = v.rootNode.findNode("boom_light")
            let boom = newAnimation()

            boomLight.alpha = 1
            boom.numberOfLoops = 1
            boom.loopDuration = 3.0
            boom.onAnimate = proc(p: float) =
                boomLight.alpha = interpolate(1.0, 0.0, cubicEaseIn(p))
            v.addAnimation(boom)
            v.addAnimation(v.rootNode.findNode("shake_root").parent.animationNamed("shake"))
            v.addAnimation(shakeAnim)
            shakeAnim.onComplete do():
                lights.startLights()
            v.addAnimation(v.rootNode.findNode("vases").animationNamed("shake"))

            fade.animation.onComplete do():
                fade.removeFromParent()
        animPetard.onComplete do():
            firework.removeFromParent()
        parent.addChild(firework)
