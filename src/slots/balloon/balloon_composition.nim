import tables
import strutils
import math, random

import nimx.view
import nimx.image
import nimx.matrixes
import nimx.animation
import nimx.timer

import rod.scene_composition
import rod.rod_types
import rod.node
import rod.viewport
import rod.component
import rod.component.sprite
import rod.component.visual_modifier
import rod.component.mesh_component
import rod.component.material
import rod.component.particle_system
import rod.animated_image

import utils.pause
import utils.helpers

import soft_billboard
import hard_billboard

import core.slot.base_slot_machine_view

const WILD_INDEX = 0

const resPath = "slots/balloon_slot/"

type
    DestroyAnimComposition* = ref object
        splash*: AnimatedImage
        splashAnim*: Animation

        # fireworkNode*: Node
        # fireworkAnim*: Animation

        confettiNode*: Node
        confettiAnim*: Animation

    BalloonComposition* = ref object
        anchor*: Node
        animRotationNode*: Node
        balloonParent*: Node
        balloonNode*: Node

        animIdle*: Animation
        animIdleSlow*: Animation
        animIdleFast*: Animation
        animRotation*: Animation

        destroy*: DestroyAnimComposition

        shiftCells*: int8
        meshIndex*: int8
        destroyed*: bool

        backAnchorNode*: Node

        frontSpriteWrapperNode*: Node
        backSpriteWrapperNode*: Node

        backWrapperAnim*: Animation
        frontWrapperAnim*: Animation

        frontSpriteWrapperDestroyNode*: Node
        backSpriteWrapperDestroyNode*: Node

        backWrapperDestroyAnim*: Animation
        frontWrapperDestroyAnim*: Animation

proc getFirstNodeWithMesh(n: Node): Node =
    for child in n.children:
        let mesh = child.componentIfAvailable(MeshComponent)
        if not mesh.isNil:
            return mesh.node
        return getFirstNodeWithMesh(child)

proc newDestroyAnimComposition*(splashImgs: seq[Image]): DestroyAnimComposition =
    # , fireworkImgs: seq[Image]): DestroyAnimComposition =
    result.new()
    result.splash.new()
    result.splash.images = splashImgs

    let splashFrames = splashImgs.len - 1
    result.splashAnim = result.splash.frameAnimation(splashFrames)
    result.splashAnim.numberOfLoops = 1

    # let fireworkSpriteScale = 0.125
    # let fireworkSpriteSize = 256.0
    # let fireworkYShift = -2.0

    let confettiNode = newLocalizedNodeWithResource(resPath & "particles/destr/root_confetti.json")
    confettiNode.alpha = 0.0

    result.confettiNode = confettiNode

    var maxAnimDuration = 0.0
    for ch in confettiNode.children:
        let psc = ch.componentIfAvailable(ParticleSystem)
        if not psc.isNil:
            if maxAnimDuration < psc.lifetime:
                maxAnimDuration = psc.lifetime

    let psHolderComp = confettiNode.componentIfAvailable(PSHolder)

    result.confettiAnim = newAnimation()
    result.confettiAnim.loopDuration = maxAnimDuration
    result.confettiAnim.continueUntilEndOfLoopOnCancel = true
    result.confettiAnim.numberOfLoops = 1
    result.confettiAnim.onComplete do():
        confettiNode.alpha = 0.0
        psHolderComp.played = false

    # result.fireworkNode = newNode("firework_node")
    # result.fireworkNode.alpha = 0.0
    # result.fireworkNode.scale = newVector3(fireworkSpriteScale, fireworkSpriteScale, 0.0)
    # result.fireworkNode.position = newVector3(-fireworkSpriteSize*fireworkSpriteScale/2.0, -fireworkSpriteSize*fireworkSpriteScale/2.0 + fireworkYShift, 0.0)
    ## let modifier = result.fireworkNode.component(VisualModifier)
    ## modifier.blendMode = COLOR_ADD

    # let targetNode = result.fireworkNode.newChild("firework")

    # let fireworkSprite = targetNode.component(Sprite)
    # fireworkSprite.images = fireworkImgs

    # result.fireworkAnim = newAnimation()
    # const fps = 1.0 / 30.0
    # let fireworkFrames = fireworkImgs.len - 1
    # result.fireworkAnim.loopDuration = float(fireworkFrames + 1) * fps
    # result.fireworkAnim.continueUntilEndOfLoopOnCancel = true
    # result.fireworkAnim.numberOfLoops = 1
    # result.fireworkAnim.onAnimate = proc(p: float) =
    #     fireworkSprite.currentFrame = int(float(fireworkFrames) * p)

proc newWrapperNodeFromImgSeq(name: string, imgs: seq[Image]): tuple[node: Node, parent: Node] =
    let animImage = newAnimatedImageWithImageSeq(imgs)

    let nodeImg = newNode(name)
    nodeImg.scale = newVector3(0.18, 0.18, 0.18)
    nodeImg.registerAnimation("play", animImage.frameAnimation())
    nodeImg.alpha = 0.0

    let nodeImgParent = newNode(name & "_prnt")
    nodeImgParent.addChild(nodeImg)

    # let modifier = nodeImgParent.component(VisualModifier)
    # modifier.blendMode = COLOR_ADD

    let billboard = nodeImg.component(SoftBillboard)
    billboard.image = animImage

    result.node = nodeImg
    result.parent = nodeImgParent

proc newBalloonCompositionWithResource*(resRotation, resBounce: string,
                                        splashImgs,
                                        # fireworkImgs,
                                        backImg, frontImg,
                                        backDestImg, frontDestImg: seq[Image],
                                        id: int8): BalloonComposition =
    result.new()

    let anchor = newNode($id)
    var animRotationNode: Node
    var balloonParent: Node
    var backAnchorNode: Node
    var balloonNode: Node
    var animRotation: Animation
    var animIdle: Animation
    var animIdleSlow: Animation
    var animIdleFast: Animation
    var animBounce: Animation

    # load rotation before destroy anim
    loadSceneAsync resRotation, proc(n: Node) =
        for child in n.children:
            if child.name.contains("rotation"):
                animRotationNode = child

            if not isNil(child.animations):
                for name, anim in child.animations:
                    if name.contains("rotation"):
                        animRotation = anim
    # load bounce anim
    loadSceneAsync resBounce, proc(n: Node) =
        for child in n.children:
            if child.name.contains("bounce"):
                balloonParent = child

            if not isNil(child.animations):
                for name, anim in child.animations:
                    if name.contains("bounce"):
                        animBounce = anim
                        animBounce.numberOfLoops = 1
                        animBounce.loopDuration = 1.0
                        balloonParent.registerAnimation("bounce", animBounce)

    balloonParent.name = "parent_balloon"
    balloonNode = newNode("balloon")
    discard balloonNode.component(MeshComponent)
    result.meshIndex = -1

    backAnchorNode = newNode("balloon_anchor")
    result.backAnchorNode = backAnchorNode.newChild("back_anchor")
    backAnchorNode.addChild(balloonNode)

    animIdle = newAnimation()
    var toVal = 360.0
    animIdle.loopDuration = 500.0 + rand(400.Coord)
    animIdle.animate val in 0.0..toVal:
        backAnchorNode.positionX = sin(val)/1.5
        backAnchorNode.positionY = sin(val)/1.5
        backAnchorNode.positionZ = sin(val)*2.0

        backAnchorNode.rotationX = sin(val)/5.0
        backAnchorNode.rotationY = cos(val)/5.0
        # discard
    backAnchorNode.registerAnimation("idle", animIdle)

    animIdleSlow = newAnimation()
    toVal = 360.0
    animIdleSlow.loopDuration = 200.0 + rand(200.Coord)
    animIdleSlow.animate val in 0.0..toVal:
        backAnchorNode.positionY = sin(val)/4.0
        backAnchorNode.positionZ = sin(val)*2.0
        # discard
    backAnchorNode.registerAnimation("idle_slow", animIdleSlow)

    animIdleFast = newAnimation()
    toVal = 360.0
    animIdleFast.loopDuration = 500.0 + rand(400.Coord)
    animIdleFast.animate val in 0.0..toVal:
        backAnchorNode.positionX = sin(rand(1+val.int).Coord)/3.0
        backAnchorNode.positionY = sin(rand(1+val.int).Coord)/3.0
        backAnchorNode.positionZ = sin(rand(1+val.int).Coord)/3.0

        backAnchorNode.rotationX = sin(val)/5.0
        # discard
    backAnchorNode.registerAnimation("idle_fast", animIdleFast)

    result.anchor = anchor
    result.animRotationNode = animRotationNode
    result.animRotation = animRotation
    result.destroy = newDestroyAnimComposition(splashImgs)
        # , fireworkImgs)
    result.shiftCells = 0

    result.balloonParent = balloonParent
    result.balloonNode = balloonNode
    result.animIdle = animIdle
    result.animIdleSlow = animIdleSlow
    result.animIdleFast = animIdleFast
    result.anchor.addChild(balloonParent)
    result.anchor.addChild(animRotationNode)
    result.anchor.addChild(result.destroy.confettiNode)
    # result.anchor.addChild(result.destroy.fireworkNode)

    if backImg.len != 0:
        var wrapper = newWrapperNodeFromImgSeq("back_wrapper", backImg)
        result.backSpriteWrapperNode = wrapper.node
        result.backWrapperAnim = result.backSpriteWrapperNode.animationNamed("play")
        balloonParent.addChild(wrapper.parent)

    if backDestImg.len != 0:
        var wrapper = newWrapperNodeFromImgSeq("back_wrapper_destroy", backDestImg)
        result.backSpriteWrapperDestroyNode = wrapper.node
        result.backWrapperDestroyAnim = result.backSpriteWrapperDestroyNode.animationNamed("play")
        result.backWrapperDestroyAnim.numberOfLoops = 1
        balloonParent.addChild(wrapper.parent)

    balloonParent.addChild(backAnchorNode)

    if frontImg.len != 0:
        var wrapper = newWrapperNodeFromImgSeq("front_wrapper", frontImg)
        result.frontSpriteWrapperNode = wrapper.node
        result.frontWrapperAnim = result.frontSpriteWrapperNode.animationNamed("play")
        balloonParent.addChild(wrapper.parent)

    if frontDestImg.len != 0:
        var wrapper = newWrapperNodeFromImgSeq("front_wrapper_destroy", frontDestImg)
        result.frontSpriteWrapperDestroyNode = wrapper.node
        result.frontWrapperDestroyAnim = result.frontSpriteWrapperDestroyNode.animationNamed("play")
        result.frontWrapperDestroyAnim.numberOfLoops = 1
        balloonParent.addChild(wrapper.parent)

proc playBackFrontIdle*(bc: BalloonComposition, timing: float32) =
    let view = bc.anchor.sceneView()
    bc.frontSpriteWrapperNode.alpha = 1.0
    bc.backSpriteWrapperNode.alpha = 1.0

    bc.backWrapperAnim.loopDuration = timing
    bc.frontWrapperAnim.loopDuration = timing

    view.addAnimation(bc.backWrapperAnim)
    view.addAnimation(bc.frontWrapperAnim)

proc hideBackFrontIdle*(bc: BalloonComposition) =
    # bc.backWrapperAnim.cancel()
    # bc.frontWrapperAnim.cancel()
    bc.frontSpriteWrapperNode.alpha = 0.0
    bc.backSpriteWrapperNode.alpha = 0.0

proc playBackFrontDestroy*(bc: BalloonComposition, timing: float32) =
    let view = bc.anchor.sceneView()
    bc.hideBackFrontIdle()
    bc.frontSpriteWrapperDestroyNode.alpha = 1.0
    bc.backSpriteWrapperDestroyNode.alpha = 1.0

    bc.backWrapperDestroyAnim.loopDuration = timing
    bc.frontWrapperDestroyAnim.loopDuration = timing

    view.addAnimation(bc.backWrapperDestroyAnim)
    view.addAnimation(bc.frontWrapperDestroyAnim)

proc hideBackFrontDestroy*(bc: BalloonComposition) =
    # bc.backWrapperDestroyAnim.cancel()
    # bc.frontWrapperDestroyAnim.cancel()
    bc.frontSpriteWrapperDestroyNode.alpha = 0.0
    bc.backSpriteWrapperDestroyNode.alpha = 0.0

proc playBonusDestroy*(bc: BalloonComposition, animImageSeg: seq[Image], timeout: float32 = 0.0) =
    let v = bc.anchor.sceneView.BaseMachineView
    discard v.setTimeout(timeout) do():
        var nodeImg = bc.anchor.newChild("salute")
        nodeImg.scale = newVector3(0.15, 0.15, 0.15)
        nodeImg.positionZ = 10.0
        var animImage = newAnimatedImageWithImageSeq(animImageSeg)
        var anim = animImage.frameAnimation()
        anim.loopDuration = 1.5
        v.addAnimation(anim)
        let billboard = nodeImg.component(SoftBillboard)
        billboard.image = animImage

        let translationAnim = newAnimation()
        translationAnim.loopDuration = 1.5
        translationAnim.numberOfLoops = 1
        translationAnim.animate val in 0.0 .. -9.0:
            nodeImg.positionX = val

        v.addAnimation(translationAnim)

        v.setTimeout(anim.loopDuration) do():
            nodeImg.removeFromParent()

# var items = ["Wild", "Bonus", "Snake", "Glider", "Kite", "Flag", "Red", "Yellow", "Green", "Blue"]

const byteColors = [
    [
        [206, 115, 46 ],# Wild Yellow
        [246, 207, 61 ],# Wild
        [207, 183, 136] # Wild
    ],
    [
        [173, 6, 35],# Bonus Red
        [232, 21, 41],# Bonus
        [243, 152, 95] # Bonus
    ],
    [
        [181, 45,  173],# Snake Violett
        [212, 158, 185],# Snake
        [207, 136, 183] # Snake
    ],
    [
        [ 3  , 107, 138],# Glider Blue
        [ 44 , 179, 161],# Glider
        [ 99 , 222, 172] # Glider
    ],
    [
        [206, 115, 46 ], # Kite Yellow
        [246, 207, 61 ],  # Kite
        [207, 183, 136]  # Kite
    ],
    [
        [104,130, 30 ],# Flag Green
        [169,184, 44 ],# Flag
        [212,209, 46 ] # Flag
    ],

    [
        [173, 6, 35],# Red
        [232, 21, 41],# Red
        [243, 152, 95] # Red
    ],
    [
        [206, 115, 46 ], # Yellow
        [246, 207, 61 ], # Yellow
        [207, 183, 136] # Yellow
    ],
    [
        [104, 130, 30 ],# Green
        [169, 184, 44 ],# Green
        [212, 209, 46 ] # Green
    ],
    [
        [ 3  , 107, 138],# Blue
        [ 44 , 179, 161],# Blue
        [ 99 , 222, 172] # Blue
    ]
]

proc toFloatColors(byteColors: openarray[array[3, array[3, int]]]): seq[array[3, array[3, Coord]]] =
    result = @[]
    for balloonColors in byteColors:
        var a: array[3, array[3, Coord]]
        for i, c in balloonColors:
            a[i] = [c[0].Coord / 256, c[1].Coord / 256, c[2].Coord / 256]
        result.add(a)

const colors = toFloatColors(byteColors)

const colorCount = 3

proc playDestroy*(bc: BalloonComposition,
                                        # durationFirework = 1.0,
                                        durationRotation = 1.0,
                                        durationSplash = 1.0,
                                        timeoutSplash: float32 = 0.15,
                                        timeoutConfetti: float32 = 0.25,
                                        awaitTime: float32 = 0.0,
                                        callback: proc()) =
    template playConfetti() =
        let awaitTime = (timeoutSplash-0.2).float32
        v.setTimeout(awaitTime) do():
            bc.destroy.confettiNode.alpha = 1.0
            # hotfix
            v.setTimeout(0.2) do():
                let psHolderComp = bc.destroy.confettiNode.componentIfAvailable(PSHolder)
                psHolderComp.played = true

                v.addAnimation(bc.destroy.confettiAnim)

                for ind, ch in bc.destroy.confettiNode.children:
                    let psc = ch.componentIfAvailable(ParticleSystem)
                    if not psc.isNil:

                        let color = colors[bc.meshIndex]

                        var index = ind
                        if index >= colorCount:
                            index = colorCount - 1

                        psc.colorSeq[0][1] = color[index][0]
                        psc.colorSeq[0][2] = color[index][1]
                        psc.colorSeq[0][3] = color[index][2]

                        psc.colorSeq[1][1] = color[index][0]
                        psc.colorSeq[1][2] = color[index][1]
                        psc.colorSeq[1][3] = color[index][2]

                        psc.colorSeq[2][1] = color[index][0]
                        psc.colorSeq[2][2] = color[index][1]
                        psc.colorSeq[2][3] = color[index][2]

    let v = bc.anchor.sceneView.BaseMachineView
    v.setTimeout(awaitTime) do():
        if bc.meshIndex != WILD_INDEX:
            let mesh = bc.balloonNode.componentIfAvailable(MeshComponent)
            let material = mesh.material
            let blendState = material.blendEnable # use for splash anim to visualise back sides of balloon
            let cullingState = material.bEnableBackfaceCulling # use for splash anim to visualise back sides of balloon

            # bc.destroy.fireworkNode.alpha = 1.0
            # bc.destroy.fireworkAnim.loopDuration = durationFirework
            # bc.destroy.fireworkAnim.numberOfLoops = 1
            # bc.destroy.fireworkAnim.onComplete do():
            #     bc.destroy.fireworkNode.alpha = 0.0 # hide firework sprite after anim
            # v.addAnimation(bc.destroy.fireworkAnim)

            bc.animRotation.loopDuration = durationRotation
            bc.animRotation.numberOfLoops = 1
            bc.animRotationNode.addChild(bc.balloonParent)

            bc.animRotation.numberOfLoops = 1
            bc.animRotation.onComplete do():
                bc.anchor.addChild(bc.balloonParent)

            v.addAnimation(bc.animRotation)

            material.maskTexture = bc.destroy.splash
            material.blendEnable = true
            material.bEnableBackfaceCulling = false
            bc.destroy.splash.currentFrame = 0 # set splash anim to start
            bc.destroy.splashAnim.loopDuration = durationSplash
            bc.destroy.splashAnim.numberOfLoops = 1
            bc.destroy.splashAnim.onComplete do():
                bc.destroy.splash.currentFrame = 0
                bc.balloonNode.alpha = 0.0 # hide balloon after destroy
                material.blendEnable = blendState # restore
                material.bEnableBackfaceCulling = cullingState # restore
                v.setTimeout(0.1, callback)

            let destroyComposition = rand(["destroy", "boom"])
            var splashNode = bc.anchor.findNode(destroyComposition)
            if splashNode.isNil:
                splashNode = newLocalizedNodeWithResource(resPath & "2d/compositions/" & destroyComposition & ".json")
                discard splashNode.component(HardBillboard)
                let anim = splashNode.animationNamed("play")
                anim.loopDuration = durationSplash
                anim.onComplete do():
                    anim.removeHandlers()
                    splashNode.alpha = 0.0
                v.addAnimation(anim)
                bc.anchor.addChild(splashNode)
            else:
                splashNode.alpha = 1.0
                let anim = splashNode.animationNamed("play")
                anim.loopDuration = durationSplash
                anim.onComplete do():
                    anim.removeHandlers()
                    splashNode.alpha = 0.0
                v.addAnimation(anim)

            v.setTimeout(timeoutSplash) do():
                v.addAnimation(bc.destroy.splashAnim)

            playConfetti()
        else:
            bc.playBackFrontDestroy(durationRotation)

            var wildDestroyNode = bc.anchor.findNode("wild_destroy")
            if wildDestroyNode.isNil:
                wildDestroyNode = newLocalizedNodeWithResource(resPath & "2d/compositions/wild_destroy.json")
                discard wildDestroyNode.component(HardBillboard)
                let anim = wildDestroyNode.animationNamed("play")
                anim.loopDuration = durationSplash
                anim.onComplete do():
                    anim.removeHandlers()
                    wildDestroyNode.alpha = 0.0
                v.addAnimation(anim)
                bc.anchor.addChild(wildDestroyNode)
            else:
                wildDestroyNode.alpha = 1.0
                let anim = wildDestroyNode.animationNamed("play")
                anim.loopDuration = durationSplash
                anim.onComplete do():
                    anim.removeHandlers()
                    wildDestroyNode.alpha = 0.0
                v.addAnimation(anim)

            let mesh = bc.balloonNode.componentIfAvailable(MeshComponent)
            let material = mesh.material
            let blendState = material.blendEnable # use for splash anim to visualise back sides of balloon
            let cullingState = material.bEnableBackfaceCulling # use for splash anim to visualise back sides of balloon

            bc.animRotation.loopDuration = durationRotation
            bc.animRotation.numberOfLoops = 1
            bc.animRotationNode.addChild(bc.balloonParent)

            bc.animRotation.onComplete do():
                bc.anchor.addChild(bc.balloonParent)

            v.addAnimation(bc.animRotation)

            material.maskTexture = bc.destroy.splash
            material.blendEnable = true
            material.bEnableBackfaceCulling = false
            bc.destroy.splash.currentFrame = 0 # set splash anim to start
            bc.destroy.splashAnim.loopDuration = durationSplash
            bc.destroy.splashAnim.numberOfLoops = 1
            bc.destroy.splashAnim.onComplete do():
                bc.destroy.splash.currentFrame = 0
                bc.balloonNode.alpha = 0.0 # hide balloon after destroy
                material.blendEnable = blendState # restore
                material.bEnableBackfaceCulling = cullingState # restore
                v.setTimeout(0.1) do():
                    bc.hideBackFrontDestroy()
                    callback()

            v.setTimeout(timeoutSplash) do():
                v.addAnimation(bc.destroy.splashAnim)

            playConfetti()

proc playDestroy*(bc: BalloonComposition, awaitTime: float32, animDurationMultiplier: float32 = 1.0, callback: proc() = proc() = discard) =
    # let durationFirework = 0.9 * animDurationMultiplier
    let durationRotation = 0.6 * animDurationMultiplier
    let durationSplash = 0.8 * animDurationMultiplier
    let timeoutSplash = 0.2 * animDurationMultiplier
    let timeoutConfetti = 0.3 * animDurationMultiplier
    let timeoutAwait = awaitTime * animDurationMultiplier

    bc.playDestroy(durationRotation, durationSplash, timeoutSplash, timeoutConfetti, timeoutAwait, callback)
    # bc.playDestroy(durationFirework, durationRotation, durationSplash, timeoutSplash, timeoutConfetti, timeoutAwait, callback)

proc fromMeshComponent*(self, other: MeshComponent) =
    self.vboData.indexBuffer = other.vboData.indexBuffer
    self.vboData.vertexBuffer = other.vboData.vertexBuffer
    self.vboData.numberOfIndices = other.vboData.numberOfIndices
    self.vboData.vertInfo = other.vboData.vertInfo
    self.vboData.minCoord = other.vboData.minCoord
    self.vboData.maxCoord = other.vboData.maxCoord

    self.bProccesPostEffects = true

    if self.material.isNil:
        self.material = newDefaultMaterial()

    self.material.albedoTexture = other.material.albedoTexture
    self.material.glossTexture = other.material.glossTexture
    self.material.specularTexture = other.material.specularTexture
    self.material.normalTexture = other.material.normalTexture
    self.material.bumpTexture = other.material.bumpTexture
    self.material.reflectionTexture = other.material.reflectionTexture
    self.material.falloffTexture = other.material.falloffTexture
    self.material.maskTexture = other.material.maskTexture
    self.material.matcapTextureR = other.material.matcapTextureR
    self.material.matcapTextureG = other.material.matcapTextureG
    self.material.matcapTextureB = other.material.matcapTextureB
    self.material.matcapTextureA = other.material.matcapTextureA
    self.material.matcapMaskTexture = other.material.matcapMaskTexture

    self.material.matcapPercentR = other.material.matcapPercentR
    self.material.matcapPercentG = other.material.matcapPercentG
    self.material.matcapPercentB = other.material.matcapPercentB
    self.material.matcapPercentA = other.material.matcapPercentA
    self.material.matcapMaskPercent = other.material.matcapMaskPercent
    self.material.albedoPercent = other.material.albedoPercent
    self.material.glossPercent = other.material.glossPercent
    self.material.specularPercent = other.material.specularPercent
    self.material.normalPercent = other.material.normalPercent
    self.material.bumpPercent = other.material.bumpPercent
    self.material.reflectionPercent = other.material.reflectionPercent
    self.material.falloffPercent = other.material.falloffPercent
    self.material.maskPercent = other.material.maskPercent


    self.material.rimDensity = other.material.rimDensity
    self.material.rimColor = other.material.rimColor
    self.material.isRIM = other.material.isRIM

    self.material.color = other.material.color

    self.material.isLightReceiver = other.material.isLightReceiver
    self.material.bEnableBackfaceCulling = other.material.bEnableBackfaceCulling
    self.material.blendEnable = other.material.blendEnable
    self.material.depthEnable = other.material.depthEnable
    self.material.isWireframe = other.material.isWireframe
    self.material.isRIM = other.material.isRIM
    self.material.isNormalSRGB = other.material.isNormalSRGB
    # self.material.rimDensity = other.material.rimDensity

    self.material.shader = other.material.shader
    self.material.useManualShaderComposing = true

    self.material.uniformLocationCache = other.material.uniformLocationCache

proc setupMesh*(bc: BalloonComposition, m: MeshComponent) =
    let meshComp = bc.balloonNode.componentIfAvailable(MeshComponent)
    meshComp.fromMeshComponent(m)
    bc.destroyed = false

proc playBlinkAnim*(n: Node, speed: float32 = 1.0) =
    let startAlpha = n.alpha
    let destAlpha = 0.6
    let startScale = n.scale
    let destScale = n.scale + newVector3(0.125, 0.125, 0.125)
    let start = newVector4(startScale[0], startScale[1], startScale[2], startAlpha)
    let dest = newVector4(destScale[0], destScale[1], destScale[2], destAlpha)

    let anim = newAnimation()
    anim.loopDuration = speed
    anim.numberOfLoops = -1
    anim.loopPattern = lpStartToEndToStart
    anim.animate val in start .. dest:
        n.scale = newVector3(val[0], val[1], val[2])
        n.alpha = val[3]
    n.addAnimation(anim)

proc createLibElement(res: var seq[MeshComponent], root: Node, splashImages: seq[Image],
        nodeName, jsonName: string, isNormalSRGB: bool = false) =
    var n = newLocalizedNodeWithResource(resPath & "models/balloons/" & jsonName & ".json")
    n.name = nodeName
    root.addChild(n)
    let c = n.componentIfAvailable(MeshComponent)
    let mat = c.material
    if isNormalSRGB: mat.isNormalSRGB = true
    mat.maskTexture = newAnimatedImageWithImageSeq(splashImages)
    res.add(c)

proc setupBalloonsMaterilals*(root: Node, splashImages: seq[Image]): seq[MeshComponent] =
    result = @[]
    template c(nodeName, jsonName: string, isNormalSRGB: bool = false) =
        createLibElement(result, root, splashImages, nodeName, jsonName, isNormalSRGB)
    c("Green", "balloon_green")
    c("Red", "balloon_red")
    c("Blue", "balloon_blue")
    c("Yellow", "balloon_yellow")
    c("Snake", "balloon_dog")
    c("Glider", "balloon_heart", isNormalSRGB = true)
    c("Kite", "fish")
    c("Flag", "balloon_star")
    c("Bonus", "kite")
    c("Wild", "balloon_w")
