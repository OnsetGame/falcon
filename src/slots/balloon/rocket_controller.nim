import nimx.view
import nimx.context
import nimx.button
import nimx.animation
import nimx.image
import rod.animated_image
import rod.scene_composition
import rod.rod_types
import rod.node
import rod.viewport
import rod.component
import rod.component.sprite
import rod.component.trail
import rod.component.ui_component
import rod.component.mesh_component
import rod.component.visual_modifier
import rod.component.particle_system
import rod.component.material
import rod.ray
import rod.quaternion
import math, random
import tables
import strutils

import utils.pause
import core.slot.base_slot_machine_view

import balloon_composition
import sprite_number_controller
import cell_rails

const BETWEEN_CELL_STEP = 15

proc createButton*(parent: Node, width, height: float, action: proc()) =
    var buttonParent = parent.newChild(parent.name & "_button")
    buttonParent.positionX = -BETWEEN_CELL_STEP/2.0
    buttonParent.positionY = -BETWEEN_CELL_STEP/2.0
    let button = newButton(newRect(0, 0, width, height))
    buttonParent.component(UIComponent).view = button
    button.hasBezel = false
    # button.backgroundColor = newColor(0.0, 0.0, 1.0, 0.25)

    button.onAction do():
        buttonParent.removeComponent(UIComponent)
        buttonParent.removeFromParent()
        buttonParent = nil
        action()

proc gaussSolver(mat: seq[float32]): Vector3 =
    result = newVector3()

    var n = 3

    var a = newSeq[Vector4]()
    var row0 = newVector4(mat[0], mat[1], mat[2], mat[3])
    var row1 = newVector4(mat[4], mat[5], mat[6], mat[7])
    var row2 = newVector4(mat[8], mat[9], mat[10], mat[11])
    a.add(row0)
    a.add(row1)
    a.add(row2)

    for i in 0..<n:
        var maxEl = abs(a[i][i])
        var maxRow = i
        # Search for maximum in this column
        var k = i + 1
        while k < n:
            if abs(a[k][i]) > maxEl:
                maxEl = abs(a[k][i])
                maxRow = k
            inc k

        # Swap maximum row with current row (column by column)
        k = i
        while k < n+1:
            let tmp = a[maxRow][k]
            a[maxRow][k] = a[i][k]
            a[i][k] = tmp
            inc k

        # Make all rows below this one 0 in current column
        k = i + 1
        while k < n:
            var c = -a[k][i]/a[i][i]
            var j = i
            while j < n+1:
                if i == j:
                    a[k][j] = 0
                else:
                    a[k][j] += c * a[i][j]
                inc j
            inc k

    var x = newVector3()
    var i = n-1

    while i >= 0:
        x[i] = a[i][n]/a[i][i]
        var k = i - 1
        while k >= 0:
            a[k][n] -= a[k][i] * x[i]
            dec k
        dec i

    result = x

proc makeLinearAnimFromPoints*(node: Node, start, dest: Vector3): Animation =
    let anim = newAnimation()
    let direction = dest-start
    let distance = direction.length()
    let speed = 175.0
    anim.loopDuration = distance / speed
    anim.numberOfLoops = 1

    var destMatrix: Matrix4
    var scale: Vector3
    var rotation: Vector4

    destMatrix.lookAt(dest, start, newVector3(0,1,0))
    discard destMatrix.tryGetScaleRotationFromModel(scale, rotation)
    node.rotation = newQuaternion(rotation[0], rotation[1], rotation[2], rotation[3])

    anim.animate val in start .. dest:
        node.position = val
    result = anim

proc playAlpha*(node: Node, start, dest: float32, duration: float32, callback: proc() = proc() = discard) =
    let anim = newAnimation()
    anim.loopDuration = duration
    anim.numberOfLoops = 1
    anim.animate val in start .. dest:
        node.alpha = val
    anim.onComplete do():
        callback()
    node.addAnimation(anim)

proc playAlpha*(node: Node, dest: float32, duration: float32, callback: proc() = proc() = discard) =
    node.playAlpha(node.alpha, dest, duration, callback)

proc makeParabolaAnimFromPoints*(node: Node, start, pivot, dest: Vector3): Animation =
    let anim = newAnimation()
    var direction = dest-start
    var distance = direction.length()
    var speed = 50.0
    anim.loopDuration = distance / speed
    anim.numberOfLoops = 1

    var input = newSeq[float32](12)

    input[0] = start[0]*start[0]
    input[1] = start[0]
    input[2] = 1
    input[3] = start[2]

    input[4] = pivot[0]*pivot[0]
    input[5] = pivot[0]
    input[6] = 1
    input[7] = pivot[2]

    input[8] = dest[0]*dest[0]
    input[9] = dest[0]
    input[10] = 1
    input[11] = dest[2]

    var resultsZ = gaussSolver(input)

    let stepFroward = 0.01
    var destMatrix: Matrix4

    anim.animate val in start .. dest:
        node.position = val
        node.positionZ = resultsZ[0] * val[0] * val[0] + resultsZ[1] * val[0] + resultsZ[2]

        # var eye = val
        # eye[0] += (if direction[0] >= 0: stepFroward else: -stepFroward)
        # eye[1] += (if direction[1] >= 0: stepFroward else: -stepFroward)
        # eye[2] = resultsZ[0] * eye[0] * eye[0] + resultsZ[1] * eye[0] + resultsZ[2]
        # destMatrix.lookAt(eye, node.position, newVector3(0,0,1))

        destMatrix.lookAt(node.sceneView.camera.node.worldPos(), node.worldPos(), newVector3(0,1,0))
        destMatrix.transpose()

        var scale: Vector3
        var rotation: Vector4
        discard destMatrix.tryGetScaleRotationFromModel(scale, rotation)

        node.rotation = newQuaternion(rotation[0], rotation[1], rotation[2], rotation[3])

    result = anim

proc playWave*(n: Node) =
    # var anim = newAnimation()
    # var start = -2.0
    # var dest = 2.0
    # var waveAMP = 5.0
    # var diffAMP = 0.005

    # anim.loopDuration = 7.0
    # anim.numberOfLoops = 1
    # anim.continueUntilEndOfLoopOnCancel = true

    # anim.animate val in start .. dest:
    #     if waveAMP > 0:
    #         waveAMP -= diffAMP
    #     else:
    #         anim.cancel()
    #     n.positionZ = waveAMP * sin(2.0 * PI * val)

    # n.addAnimation(anim)
    discard

const resPath = "slots/balloon_slot/"
const srcPathRocketAnim = resPath & "anim/rocket.dae"

proc createAndPrepareSmoke*(root: Node, animImage: AnimatedImage, bigestLifetime: var float32): Node =
    let smokeNode = newLocalizedNodeWithResource(resPath & "particles/rocket/smoke.json")
    root.addChild(smokeNode)

    bigestLifetime = 2.float32
    for c in smokeNode.children:
        let trailComp = c.componentIfAvailable(Trail)
        if not trailComp.isNil:
            trailComp.image = animImage
            root.addAnimation(animImage.frameAnimation())
        let particleComp = c.componentIfAvailable(ParticleSystem)
        if not particleComp.isNil:
            if bigestLifetime < particleComp.lifeTime:
                bigestLifetime = particleComp.lifeTime
    result = smokeNode

proc hideSmoke*(n: Node) =
    for c in n.children:
        let particleComp = c.componentIfAvailable(ParticleSystem)
        if not particleComp.isNil:
            particleComp.stop()
        let trailComp = c.componentIfAvailable(Trail)
        if not trailComp.isNil:
            c.alpha = 0.0
        for ch in c.children:
            ch.alpha = 0.0

proc showSmoke*(n: Node) =
    for c in n.children:
        let particleComp = c.componentIfAvailable(ParticleSystem)
        if not particleComp.isNil:
            particleComp.start()
        let trailComp = c.componentIfAvailable(Trail)
        if not trailComp.isNil:
            c.alpha = 1.0
        for ch in c.children:
            ch.alpha = 1.0

proc initCircleRocketAnim*(root: Node, mcRocket: MeshComponent, animImage: AnimatedImage ,callback: proc() = proc() = discard): Animation =
    var rocketPlaceholder = newNode("rocket_placeholder")
    var rocketAnim: Animation
    loadSceneAsync srcPathRocketAnim, proc(nd: Node) =
        let randY = rand(40'f32)
        nd.position = newVector3(115,-37,-10-randY)
        nd.scale = newVector3(0.75,0.75,0.5)

        let randXRot = rand(10'f32)/100.0
        nd.rotation = newQuaternion(randXRot,0,0,1)
        root.addChild(nd)

        var rocket = nd.children[0]
        for anim in rocket.animations.values():
            rocket.registerAnimation("play", anim)
            anim.numberOfLoops = 1
            anim.loopDuration = 1.5
        var rocketChildNode = rocket.newChild("rkt")
        rocketChildNode.scale = newVector3(2,2,2)
        var rocketChildNodeMC = rocketChildNode.component(MeshComponent)
        rocketChildNodeMC.fromMeshComponent(mcRocket)

        var bigestLifetime = 2.float32
        var smokeNode = rocket.createAndPrepareSmoke(animImage, bigestLifetime)

        rocketAnim = rocket.animationNamed("play")
        rocketAnim.onComplete do():

            smokeNode.hideSmoke()

            root.sceneView.BaseMachineView.setTimeout bigestLifetime, proc() =
                smokeNode.removeFromParent()
                nd.removeFromParent()
                rocket.removeFromParent()

            callback()

    result = rocketAnim
