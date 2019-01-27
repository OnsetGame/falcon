import tables
import sequtils
import strutils
import math

import nimx.view
import nimx.image
import nimx.context
import nimx.animation
import nimx.window
import nimx.timer
import nimx.portable_gl

import rod.scene_composition
import rod.rod_types
import rod.node
import rod.viewport
import rod.component
import rod.component.sprite
import rod.component.particle_emitter
import rod.component.visual_modifier
import rod.component.mesh_component
import rod.component.material
import rod.animated_image

import utils.pause
import core.slot.base_slot_machine_view

import win_numbers

# const BETWEEN_CELL_STEP = 15

type
    LineComposition* = ref object
        anchor*: Node
        number*: Node
        anim*: Animation
        width*: float32
        height*: float32

proc findSpriteComponent(n: Node): Sprite =
    for node in n.children:
        let sprite = node.componentIfAvailable(Sprite)
        if not sprite.isNil:
            return sprite
        else:
            return node.findSpriteComponent()

proc newLineCompositionWithResource*(res: string, lineName: string, pivotShift: float32 = 0.0, numberRootNode: Node): LineComposition =
    result.new()
    if res.len > 0:
        let anchor = newLocalizedNodeWithResource(res)
        var animation: Animation

        if not isNil(anchor.animations):
            for name, a in anchor.animations:
                if name.contains("play"):
                    animation = a
                    anchor.registerAnimation("play", a)

        let sprite = anchor.findSpriteComponent()
        if not sprite.isNil:
            result.width = sprite.image.size.width
            result.height = sprite.image.size.height

        anchor.name = lineName
        anchor.alpha = 0.0

        let numNode = numberRootNode.newChild("num_" & lineName)
        numNode.translateY = pivotShift

        result.number = numNode
        result.anchor = anchor
        result.anim = animation
        result.anim.numberOfLoops = 1
    else:
        result.number = numberRootNode.newChild("num_" & lineName)
        result.anchor = newNode(lineName)
        result.anim = newAnimation()
        result.anim.numberOfLoops = 1

proc play*(lc: LineComposition, awaitDuration, animDuration: float32, callback: proc() = proc() = discard) =
    lc.anchor.sceneView.BaseMachineView.setTimeout awaitDuration, proc() =
        lc.anchor.alpha = 1.0
        lc.anim.loopDuration = animDuration
        lc.anchor.sceneView().addAnimation(lc.anim)
        lc.anim.onComplete do():
            lc.anchor.alpha = 0.0
            callback()

proc playNumber*(lc: LineComposition, payout: int64, awaitDuration, animDuration: float32, callback: proc() = proc() = discard) =
    let v = lc.anchor.sceneView
    v.BaseMachineView.setTimeout awaitDuration, proc() =
        let strDigitsLen = ($payout).len
        let centerFront = 950.0
        let stepFront = SMALL_FONT_STEP
        let digitsFrontLen = (strDigitsLen div 2).float32 * stepFront
        let modFrontShift = if ((strDigitsLen mod 2) == 0) : (stepFront/2.0) else: 0

        let numNode = newWinNumbersNode(payout, FontSize.SmallFont)
        numNode.positionX = centerFront - digitsFrontLen + modFrontShift
        let anims = numNode.winNumbersAnimation()
        anims.inAnim.loopDuration = animDuration/6.0
        anims.outAnim.loopDuration = animDuration/8.0
        let waitDuration = animDuration - anims.inAnim.loopDuration - anims.outAnim.loopDuration

        lc.number.addChild(numNode)
        v.addAnimation(anims.inAnim)
        anims.inAnim.onComplete do():
            anims.inAnim.removeHandlers()

            v.BaseMachineView.setTimeout waitDuration, proc() =
                v.addAnimation(anims.outAnim)
                anims.outAnim.onComplete do():
                    anims.outAnim.removeHandlers()
                    callback()

proc playNumber*(root, parent: Node, position: Vector3, payout: int64, animDuration: float32) =
    let v = parent.sceneView
    let strDigitsLen = ($payout).len
    let stepFront = SMALL_FONT_STEP
    let digitsFrontLen = (strDigitsLen div 2).float32 * stepFront
    let modFrontShift = if ((strDigitsLen mod 2) == 0) : (stepFront/2.0) else: 0

    let numNode = newWinNumbersNode(payout, FontSize.SmallFont)

    let reparentNd = root.newChild()
    reparentNd.position = position
    reparentNd.reparentTo(parent)
    let posFront = reparentNd.position + newVector3(-digitsFrontLen + modFrontShift, 0.0, 0.0)
    reparentNd.removeFromParent()

    numNode.position = posFront
    parent.addChild(numNode)

    numNode.position = numNode.position + newVector3(0, -970.0, 0.0)

    let anims = numNode.winNumbersAnimation()
    anims.inAnim.loopDuration = animDuration/6.0
    anims.outAnim.loopDuration = animDuration/8.0
    let waitDuration = animDuration - anims.inAnim.loopDuration - anims.outAnim.loopDuration


    v.addAnimation(anims.inAnim)
    anims.inAnim.onComplete do():
        anims.inAnim.removeHandlers()

        v.BaseMachineView.setTimeout waitDuration, proc() =
            v.addAnimation(anims.outAnim)
            anims.outAnim.onComplete do():
                anims.outAnim.removeHandlers()
                numNode.removeFromParent()


const UP_NUMBER = -690.0
const MID_NUMBER = -450.0
const DOWN_NUMBER = -200.0

const resPath = "slots/balloon_slot/"
proc initLinesLibWithResources*(rootNumbers, rootLines: Node): seq[LineComposition] =
    var linesLib = newSeq[LineComposition]()

    # let line1 = newLineCompositionWithResource(resPath & "2d/compositions/Straight-line.json", "1", MID_NUMBER, rootNumbers)# 1,1,1,1,1
    # line1.anchor.position = newVector3(0,-30,0)
    # linesLib.add(line1)
    # rootLines.addChild(line1.anchor)

    # let line0 = newLineCompositionWithResource(resPath & "2d/compositions/Straight-line.json", "0", UP_NUMBER, rootNumbers)# 0,0,0,0,0
    # line0.anchor.position = newVector3(0,50,0)
    # linesLib.add(line0)
    # rootLines.addChild(line0.anchor)

    # let line2 = newLineCompositionWithResource(resPath & "2d/compositions/Straight-line.json", "2", DOWN_NUMBER, rootNumbers)# 2,2,2,2,2
    # line2.anchor.position = newVector3(0,-95,0)
    # linesLib.add(line2)
    # rootLines.addChild(line2.anchor)

    # let line3 = newLineCompositionWithResource(resPath & "2d/compositions/V-line.json", "3", DOWN_NUMBER, rootNumbers) # 0,1,2,1,0
    # line3.anchor.position = newVector3(80,100,0)
    # line3.anchor.scale.y = -1
    # linesLib.add(line3)
    # rootLines.addChild(line3.anchor)

    # let line4 = newLineCompositionWithResource(resPath & "2d/compositions/V-line.json", "4", UP_NUMBER, rootNumbers) # 2,1,0,1,2
    # line4.anchor.position = newVector3(80,-80,0)
    # linesLib.add(line4)
    # rootLines.addChild(line4.anchor)

    # let line5 = newLineCompositionWithResource(resPath & "2d/compositions/S-line.json", "5", MID_NUMBER, rootNumbers) # 0,0,1,2,2
    # line5.anchor.position = newVector3(15,110,0)
    # line5.anchor.scale.y = -1
    # linesLib.add(line5)
    # rootLines.addChild(line5.anchor)

    # let line6 = newLineCompositionWithResource(resPath & "2d/compositions/S-line.json", "6", MID_NUMBER, rootNumbers) # 2,2,1,0,0
    # line6.anchor.position = newVector3(15,-100,0)
    # linesLib.add(line6)
    # rootLines.addChild(line6.anchor)

    # let line7 = newLineCompositionWithResource(resPath & "2d/compositions/small_U-line.json", "7", UP_NUMBER, rootNumbers) # 1,0,0,0,1
    # line7.anchor.position = newVector3(45,-30,0)
    # linesLib.add(line7)
    # rootLines.addChild(line7.anchor)

    # let line8 = newLineCompositionWithResource(resPath & "2d/compositions/small_U-line.json", "8", DOWN_NUMBER, rootNumbers) # 1,2,2,2,1
    # line8.anchor.position = newVector3(45,50,0)
    # line8.anchor.scale.y = -1
    # linesLib.add(line8)
    # rootLines.addChild(line8.anchor)

    # let line9 = newLineCompositionWithResource(resPath & "2d/compositions/W-line.json", "9", UP_NUMBER, rootNumbers) # 0,1,0,1,0
    # line9.anchor.position= newVector3(65,120,0)
    # line9.anchor.scale.y = -1.0
    # linesLib.add(line9)
    # rootLines.addChild(line9.anchor)

    # let line10 = newLineCompositionWithResource(resPath & "2d/compositions/W-line.json", "10", DOWN_NUMBER, rootNumbers) # 2,1,2,1,2
    # line10.anchor.position= newVector3(65,-100,0)
    # linesLib.add(line10)
    # rootLines.addChild(line10.anchor)

    # let line11 = newLineCompositionWithResource(resPath & "2d/compositions/U-line.json", "11", DOWN_NUMBER, rootNumbers) # 0,2,2,2,0
    # line11.anchor.position = newVector3(65,110,0)
    # line11.anchor.scale.y = -1.0
    # linesLib.add(line11)
    # rootLines.addChild(line11.anchor)

    # let line12 = newLineCompositionWithResource(resPath & "2d/compositions/U-line.json", "12", UP_NUMBER, rootNumbers) # 2,0,0,0,2
    # line12.anchor.position = newVector3(65,-90,0)
    # linesLib.add(line12)
    # rootLines.addChild(line12.anchor)

    # let line13 = newLineCompositionWithResource(resPath & "2d/compositions/Z-line.json", "13", MID_NUMBER, rootNumbers) # 1,0,1,2,1
    # line13.anchor.position = newVector3(40,110,0)
    # line13.anchor.scale.y = -1
    # linesLib.add(line13)
    # rootLines.addChild(line13.anchor)

    # let line14 = newLineCompositionWithResource(resPath & "2d/compositions/Z-line.json", "14", MID_NUMBER, rootNumbers) # 1,2,1,0,1
    # line14.anchor.position = newVector3(40,-90,0)
    # linesLib.add(line14)
    # rootLines.addChild(line14.anchor)

    # for i in 15..24:
    #     let line = newLineCompositionWithResource("", $i, MID_NUMBER, rootNumbers)
    #     line.anchor.position = newVector3(0,-500,0)
    #     linesLib.add(line)
    #     rootLines.addChild(line.anchor)


    # let line15 = newLineCompositionWithResource(resPath & "2d/compositions/small_Peak-line.json", "15", -BETWEEN_CELL_STEP, rootNumbers) # 0,0,1,0,0
    # line15.anchor.position= newVector3(30,-15,0)
    # linesLib.add(line15)
    # rootLines.addChild(line15.anchor)

    # let line16 = newLineCompositionWithResource(resPath & "2d/compositions/small_Peak-line.json", "16", 0.0, rootNumbers) # 2,2,1,2,2
    # line16.anchor.position= newVector3(30,50,0)
    # line16.anchor.scale.y = -1.0
    # linesLib.add(line16)
    # rootLines.addChild(line16.anchor)

    # let line17 = newLineCompositionWithResource(resPath & "2d/compositions/small_Peak-line.json", "17", BETWEEN_CELL_STEP, rootNumbers) # 1,1,0,1,1
    # line17.anchor.position= newVector3(30,120,0)
    # line17.anchor.scale.y = -1.0
    # linesLib.add(line17)
    # rootLines.addChild(line17.anchor)

    # let line18 = newLineCompositionWithResource(resPath & "2d/compositions/small_Peak-line.json", "18", -BETWEEN_CELL_STEP, rootNumbers) # 1,1,2,1,1
    # line18.anchor.position= newVector3(30,-90,0)
    # linesLib.add(line18)
    # rootLines.addChild(line18.anchor)

    # let line19 = newLineCompositionWithResource(resPath & "2d/compositions/W-line.json", "19", BETWEEN_CELL_STEP, rootNumbers) # 0,2,0,2,0
    # line19.anchor.position= newVector3(65,170,0)
    # line19.anchor.scale.y = -1.9
    # linesLib.add(line19)
    # rootLines.addChild(line19.anchor)

    result = linesLib
