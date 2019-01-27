# import tables
# import sequtils
# import strutils
# import math

# import nimx.view
# import nimx.image
# import nimx.context
# import nimx.animation
# import nimx.window
# import nimx.timer
# import nimx.portable_gl

# import rod.scene_composition
# import rod.rod_types
# import rod.node
# import rod.viewport
# import rod.component
# import rod.component.sprite
# import rod.component.particle_emitter
# import rod.component.visual_modifier
# import rod.component.mesh_component
# import rod.component.material
# import rod.animated_image

# import utils.pause
# import shared.base_slot_machine_view

# import rocket_controller

# import soft_billboard

# const resPathSpin = "slots/balloon_slot/2d/numbers_gold/"
# const resPathFreeSpin = "slots/balloon_slot/2d/numbers_blue/"
# type
#     NumberType* = enum
#         SpinNumber,
#         FreespinNumber

# var numbersSeq: seq[Image]
# var numbersSeqFreespin: seq[Image]
# let scale = 0.05
# var glyphWidth*: float32
# var glyphHeight*: float32

# proc initSpriteNumbers() =
#     let imgsNumbersCount = 10
#     numbersSeq = newSeq[Image](imgsNumbersCount+2) # plus one as "X" symbol
#     for i in 0 ..< imgsNumbersCount+1:
#         let res = resPathSpin & $i & ".png"
#         numbersSeq[i] = imageWithResource(res)

#     numbersSeqFreespin = newSeq[Image](imgsNumbersCount+1)
#     for i in 0 ..< imgsNumbersCount:
#         let res = resPathFreeSpin & $i & ".png"
#         numbersSeqFreespin[i] = imageWithResource(res)

# proc newNodeWithNumber*(val: string = "", numType: NumberType = SpinNumber): Node =
#     result = newNode(val)
#     var step = 0.0'f32
#     var dist = 0.0'f32

#     if val[0] == '-':
#         echo "negative balance detected from number controller"
#     else:
#         for i in val:
#             let c = result.newChild($i)
#             var s = c.componentIfAvailable(Sprite)
#             if s.isNil: s = c.component(Sprite)
#             let num = parseInt($i)
#             if num >= 0 and num <= 9:
#                 if numbersSeq.isNil or numbersSeqFreespin.isNil: initSpriteNumbers()
#                 s.image = if numType == SpinNumber: numbersSeq[num] else: numbersSeqFreespin[num]
#             else:
#                 echo "WRONG NUMBER"
#             var w = s.image.size.width
#             w = w-w/5.0
#             step = w
#             c.position = newVector3(step + dist, 0, 0)
#             dist += step
#             glyphWidth = w*scale
#             glyphHeight = s.image.size.width*scale

#     result.position = newVector3(-dist*scale/2.0, 0, 0)
#     result.scale = newVector3(scale, -scale, scale)

# proc setNumber*(n: Node, val: string = "", numType: NumberType = SpinNumber) =
#     var indx = 0
#     var dist = 0.0'f32

#     if not n.isNil and not n.children.isNil:
#         for c in n.children:
#             if val[0] == '-':
#                 echo "negative balance detected from number controller"
#             else:
#                 if val.len > indx:
#                     let num = parseInt($val[indx])
#                     c.alpha = 1.0
#                     var s = c.componentIfAvailable(Sprite)
#                     if s.isNil: s = c.component(Sprite)
#                     if numbersSeq.isNil or numbersSeqFreespin.isNil: initSpriteNumbers()
#                     s.image = if numType == SpinNumber: numbersSeq[num] else: numbersSeqFreespin[num]
#                     dist += s.image.size.width
#                     inc indx
#                 else:
#                     c.alpha = 0.0
#         # n.positionX = -dist*scale/2.0

# proc playRoundNumber*(parent: Node, numStart, numDest: int, numType: NumberType = SpinNumber, slotSpeed: float32 = 1.0): Node =
#     var roundNumber = newNodeWithNumber($numDest)
#     result = roundNumber
#     parent.addChild(roundNumber)
#     let shiftDivisor = 0.5
#     parent.alpha = 0.0
#     parent.positionX = 0.0

#     let loopDuration = 1.0 * slotSpeed
#     let animAlpha = newAnimation()
#     animAlpha.loopDuration = loopDuration
#     animAlpha.numberOfLoops = 1
#     animAlpha.animate val in 0.0 .. 1.0:
#         if parent.isNil: return
#         parent.alpha = val
#     parent.sceneView().addAnimation(animAlpha)
#     # animAlpha.onComplete do():

#     let animSpinNumbers = newAnimation()
#     animSpinNumbers.loopDuration = 0.5 * slotSpeed
#     animSpinNumbers.numberOfLoops = 1
#     animSpinNumbers.animate val in numStart .. numDest:
#         if parent.isNil: return
#         if roundNumber.isNil: return
#         roundNumber.setNumber($val, numType)
#         roundNumber.positionX = -glyphWidth*($val.int).len.float32*shiftDivisor
#         parent.positionX = -glyphWidth*($val.int).len.float32*shiftDivisor
#     parent.sceneView().addAnimation(animSpinNumbers)
#     # animSpinNumbers.onComplete do():

#     let hideAfterTime = 0.75 * slotSpeed
#     setTimeout animSpinNumbers.loopDuration+hideAfterTime, proc() =
#         roundNumber.removeFromParent()
#         roundNumber = nil

# proc playFreespinNumber*(parent: Node, numStart, numDest: int, loopDuration: float32 = 0.5) =
#     var freespinNode = parent.findNode("frsp_num")
#     var nodeNumber: Node
#     if freespinNode.isNil:
#         freespinNode = parent.newChild("frsp_num")
#         nodeNumber = newNodeWithNumber("0123456789")
#         freespinNode.addChild(nodeNumber)
#     else:
#         nodeNumber = freespinNode.children[0]

#     let shiftDivisor = 0.5
#     let animSpinNumbers = newAnimation()
#     animSpinNumbers.loopDuration = loopDuration
#     animSpinNumbers.numberOfLoops = 1
#     animSpinNumbers.animate val in numStart .. numDest:
#         if nodeNumber.isNil: return
#         nodeNumber.setNumber($val, FreespinNumber)
#         nodeNumber.positionX = -glyphWidth*($val.int).len.float32*shiftDivisor
#     parent.sceneView().addAnimation(animSpinNumbers)

# proc playLineNumber*(n: Node, num: int, numType: NumberType = SpinNumber, awaitDuration, loopDuration: float32 = 0.5, callback: proc() = proc() = discard) =
#     n.sceneView.BaseMachineView.setTimeout awaitDuration, proc() =
#         if num > 0:
#             var nodeNumber = newNodeWithNumber($num)
#             n.addChild(nodeNumber)
#             let shiftDivisor = 0.5
#             n.alpha = 0.0

#             let animAlpha = newAnimation()
#             animAlpha.loopDuration = loopDuration
#             animAlpha.numberOfLoops = 1
#             animAlpha.animate val in 0.0 .. 1.0:
#                 n.alpha = val
#             n.sceneView().addAnimation(animAlpha)
#             # animAlpha.onComplete do():

#             let animSpinNumbers = newAnimation()
#             animSpinNumbers.loopDuration = loopDuration
#             animSpinNumbers.numberOfLoops = 1
#             let start = 0
#             let dest = num
#             animSpinNumbers.animate val in start .. dest:
#                 if nodeNumber.isNil: return
#                 nodeNumber.setNumber($val, numType)
#                 nodeNumber.positionX = -glyphWidth*($val).len.float32*shiftDivisor
#             n.sceneView().addAnimation(animSpinNumbers)
#             animSpinNumbers.onComplete do():
#                 setTimeout loopDuration, proc() =
#                     nodeNumber.removeFromParent()
#                     nodeNumber = nil
#                     callback()

# # proc playBonusNumber*(n: Node, num: int, numType: NumberType = SpinNumber, delay: float32 = 0.0, speedMultiplier: float32 = 1.0, callback: proc() = proc() = discard) =
# #     let vp = n.sceneView
# #     vp.BaseMachineView.setTimeout delay, proc() =
# #         if num > 0:
# #             var nodeNumber = newNodeWithNumber($num)
# #             n.addChild(nodeNumber)
# #             nodeNumber.translateY = glyphWidth/2.0

# #             let animSpinNumbers = newAnimation()
# #             animSpinNumbers.loopDuration = 0.5 * speedMultiplier
# #             animSpinNumbers.numberOfLoops = 1
# #             animSpinNumbers.animate val in 0 .. num:
# #                 nodeNumber.setNumber($val, numType)
# #                 nodeNumber.positionX = -glyphWidth*($val).len.float32
# #             vp.addAnimation(animSpinNumbers)

# #             nodeNumber.alpha = 0.0
# #             nodeNumber.playAlpha(1.0, duration = 0.5 * speedMultiplier)
# #             # animSpinNumbers.onComplete do():

# #             vp.BaseMachineView.setTimeout 0.25 * speedMultiplier, proc() =
# #                 let shiftY = 20.0.Coord
# #                 let destTranslation = newVector3(nodeNumber.positionX, nodeNumber.positionY + shiftY, nodeNumber.positionZ)
# #                 nodeNumber.moveTo(destTranslation, duration = 1.5 * speedMultiplier)

# #                 vp.BaseMachineView.setTimeout 0.75 * speedMultiplier, proc() =
# #                     nodeNumber.playAlpha(0.0, duration = 0.75 * speedMultiplier, proc() =
# #                         nodeNumber.removeFromParent()
# #                         n.removeFromParent()
# #                         callback()
# #                     )

# proc playMultiplierNumber*(n: Node, num: int, loopDuration: float32 = 0.5, callback: proc(), bPlayAlphaAnim: bool = true) =
#     var nodeNumber = newNode($num)

#     var step = 0.0'f32
#     var dist = 0.0'f32
#     let c = nodeNumber.newChild("x")
#     var s = c.componentIfAvailable(SoftBillboard)
#     if s.isNil: s = c.component(SoftBillboard)
#     if numbersSeq.isNil : initSpriteNumbers()
#     s.image = numbersSeq[10]
#     let w = s.image.size.width
#     step = w
#     c.position = newVector3(step + dist, 0, 0)
#     dist += step
#     glyphWidth = w*scale
#     glyphHeight = s.image.size.width*scale

#     for i in $num:
#         let c = nodeNumber.newChild($i)
#         var s = c.componentIfAvailable(SoftBillboard)
#         if s.isNil: s = c.component(SoftBillboard)
#         let digit = parseInt($i)
#         if digit >= 0 and digit <= 9:
#             if numbersSeq.isNil or numbersSeqFreespin.isNil: initSpriteNumbers()
#             s.image = numbersSeq[digit]
#         let w = s.image.size.width
#         step = w
#         c.position = newVector3(step + dist, 0, 0)
#         dist += step
#         glyphWidth = w*scale
#         glyphHeight = s.image.size.width*scale

#     nodeNumber.position = newVector3(-dist*scale/2, s.image.size.height*scale/2, 0)
#     nodeNumber.scale = newVector3(scale, -scale, scale)

#     n.addChild(nodeNumber)

#     if bPlayAlphaAnim:
#         n.alpha = 0.0

#         let animAlpha = newAnimation()
#         animAlpha.loopDuration = loopDuration
#         animAlpha.numberOfLoops = 1
#         animAlpha.animate val in 0.0 .. 1.0:
#             n.alpha = val
#         n.sceneView().addAnimation(animAlpha)

#         animAlpha.onComplete do():

#             # # TODO do not remove this node
#             # n.sceneView.BaseMachineView.setTimeout 1.0, proc() =
#             #     nodeNumber.removeFromParent()
#             #     nodeNumber = nil

#             callback()
#     else:
#         callback()
