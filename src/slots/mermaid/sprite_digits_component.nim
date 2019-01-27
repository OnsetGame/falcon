import strutils, json, algorithm, logging

import nimx.types
import nimx.property_visitor
import nimx.animation
import nimx.matrixes
import nimx.image

import rod.node
import rod.rod_types
import rod.viewport
import rod.component
import rod.tools.serializer
import rod.component.sprite
import rod.utils.image_serialization

import utils.helpers

import anim_helpers

#---------------------------------------------------------------------------------------------------------------------

type SpriteDigits* = ref object of Component
    offset*: Point
    frameOffsets*: seq[Point]
    images*: seq[Image]
    currentFrame*: int
    mRespath: string
    mFixedStep: float32
    mValue: string

proc `sprite=`*(s: SpriteDigits, sprite: Sprite) =
    if not sprite.isNil:
        s.frameOffsets = @[]
        for soff in sprite.frameOffsets: s.frameOffsets.add(soff)
        s.images = @[]
        for img in sprite.images: s.images.add(img)
        s.offset = sprite.offset
        s.currentFrame = sprite.currentFrame

proc findFirstSprite*(n: Node): Sprite=
    result = n.componentIfAvailable(Sprite)
    if result.isNil:
        for ch in n.children:
            result = ch.findFirstSprite()

proc loadNodeFromUrl*(url: string, onComplete: proc(n: Node) = nil) =
    var nd  = newNode()
    nd.loadComposition(url) do():
        onComplete(nd)

proc `respath=`*(s: SpriteDigits, val: string) =
    if val.len > 0:
        try:
            loadNodeFromUrl(val) do(donorNode: Node):
                s.mRespath = val
                s.sprite = donorNode.findFirstSprite()
        except:
            info "Wrong path, composition not found: ", val

template respath*(s: SpriteDigits): string = s.mRespath

template `value`*(s: SpriteDigits): string = s.mValue

proc `value=`*(s: SpriteDigits, valStr: string) =
    s.node.removeAllChildren()

    var prevStep = newVector3(0,0,0)
    var stepX, stepY = 0.0
    for v in valStr:
        let num = parseInt($v)
        if num >= 0 and num <= 9:
            let digitNode = s.node.newChild($v)
            digitNode.position = prevStep

            var digitSprite = digitNode.component(Sprite)
            digitSprite.frameOffsets = s.frameOffsets
            digitSprite.images = s.images
            digitSprite.offset = s.offset
            digitSprite.currentFrame = num

            if not digitSprite.image.isNil:
                stepX += (if s.mFixedStep == 0: digitSprite.image.size.width else: s.mFixedStep - digitSprite.getOffset()[0])
                stepY += digitSprite.image.size.height
                prevStep = newVector3(stepX, prevStep.y, prevStep.z)

    s.node.anchor = newVector3(stepX/2.0,stepY/valStr.len.float32/2.0,0)

    s.mValue = valStr

proc `fixedStep=`*(s: SpriteDigits, val: float32) =
    s.mFixedStep = val
    var prevStep = newVector3(0,0,0)
    var stepX, stepY = 0.0
    for ch in s.node.children:
        ch.position = prevStep
        var digitSprite = ch.componentIfAvailable(Sprite)
        stepX += (if s.mFixedStep == 0: digitSprite.image.size[0] else: s.mFixedStep - digitSprite.getOffset()[0])
        stepY += digitSprite.image.size[1]
        prevStep = newVector3(stepX, prevStep.y, prevStep.z)
    s.node.anchor = newVector3(stepX/2.0,stepY/s.mValue.len.float32/2.0,0)

template fixedStep*(s: SpriteDigits): float32 = s.mFixedStep

method init*(s: SpriteDigits) =
    procCall s.Component.init()

method serialize*(s: SpriteDigits, serializer: Serializer): JsonNode =
    var chNodes = newSeq[Node]()
    while s.node.children.len > 0:
        chNodes.add(s.node.children[0])
        s.node.children[0].removeFromParent()

    result = newJObject()
    result.add("respath", serializer.getValue(s.respath))
    result.add("fixedStep", serializer.getValue(s.fixedStep))

    s.node.sceneView.wait(0.5) do():
        for ch in chNodes:
            s.node.addChild(ch)

method deserialize*(s: SpriteDigits, j: JsonNode, serializer: Serializer) =
    var path: string
    serializer.deserializeValue(j, "respath", path)
    s.respath = serializer.toAbsoluteUrl(path)
    serializer.deserializeValue(j, "fixedStep", s.fixedStep)

method visitProperties*(s: SpriteDigits, p: var PropertyVisitor) =
    p.visitProperty("value", s.value)
    p.visitProperty("respath", s.respath)
    p.visitProperty("fixed step", s.fixedStep)
registerComponent(SpriteDigits)
