import strutils
import rod / [ rod_types, node, component ]
import rod / component / ae_composition
import nimx / [ property_visitor, matrixes, animation ]
import shared / [ director, game_scene ]
import utils / [ helpers, sound_manager ]

import shafa / game / narrative_types
export narrative_types


type NarrativeCharacter* = ref object of Component
    bodyNum: int
    headNum: int
    content*: Node
    animation: AEComposition
    isRightPos: bool
    rootNode: Node
    partsShowTime: float32
    mKind: NarrativeCharacterType

const LEFT_POS  = newVector3(0, 0, 0)
const RIGHT_POS = newVector3(1920, 0, 0)

proc show*(c: NarrativeCharacter, time: float32)
method init*(c: NarrativeCharacter) =
    c.mKind = NarrativeCharacterType.None

proc hideBodies(n: Node, time: float32) =
    for b in n.children:
        if b.name.find("body") > -1:
            b.hide(time)


proc hideBodyHeads(n: Node, time: float32) =
    for head in  n.children:
        if head.name.find("_head_") > 0:
            head.hide(time)


proc createContent(c: NarrativeCharacter) =
    if c.mKind == NarrativeCharacterType.None:
        return

    if not c.rootNode.isNil:
        c.rootNode.removeFromParent()

    echo "createContent ", $c.mKind
    let res = newNodeWithResource("common/will_ferris/precomps/" & $c.mKind)
    c.content = res.findNode("anchor")
    c.animation = res.getComponent(AEComposition)
    c.rootNode = c.node.newChild("narrative_character_root")
    c.rootNode.addChild(res)

    res.hideBodies(0.0)
    for body in c.content.children:
        body.hideBodyHeads(0.0)


proc kind*(c: NarrativeCharacter): NarrativeCharacterType =
    result = c.mKind

proc `kind=`*(c: NarrativeCharacter, t: NarrativeCharacterType) =
    if c.mKind != t:
        c.mKind = t
        c.createContent()


proc `bodyNumber=`*(c: NarrativeCharacter, num: int) =
    c.bodyNum = num
    for ch in c.content.children:
        if ch.name.find($c.bodyNum) > 0:
            c.content.hideBodies(c.partsShowTime)
            ch.show(c.partsShowTime)

proc bodyNumber*(c: NarrativeCharacter): int =
    result = c.bodyNum

proc `headNumber=`*(c: NarrativeCharacter, num: int) =
    c.headNum = num
    for body in c.content.children:
        for head in body.children:
            if head.name.find("_head_0" & $c.headNum) > 0:
                body.hideBodyHeads(c.partsShowTime)
                head.show(c.partsShowTime)
                break

proc headNumber*(c: NarrativeCharacter): int =
    result = c.headNum

proc `rightPos=`*(c: NarrativeCharacter, right: bool) =
    c.isRightPos = right
    if right:
        c.rootNode.position = RIGHT_POS
        c.rootNode.scaleX = -1.0
    else:
        c.rootNode.position = LEFT_POS
        c.rootNode.scaleX = 1.0

proc rightPos*(c: NarrativeCharacter): bool =
    result = c.isRightPos

proc shiftPos*(c: NarrativeCharacter, offX: float, offY: float = 0.0) =
    var pos = c.rootNode.position
    pos.x += offX
    pos.y += offY
    c.rootNode.position = pos

proc show*(c: NarrativeCharacter, time: float32) =
    c.content.show(time)
    let showAnim = c.animation.play("show")
    showAnim.onComplete do():
        c.partsShowTime = 0.2

    if not currentDirector().currentScene.isNil:
        currentDirector().currentScene.soundManager.sendEvent("NARRATIVE_CHARACTER_SHOW")

proc hide*(c: NarrativeCharacter, time: float32) =
    c.content.hide(time)

method componentNodeWasAddedToSceneView*(c: NarrativeCharacter) =
    if c.rootNode.isNil:
        c.createContent()
    # c.bodyNumber = 0
    # c.headNumber = 0

method visitProperties*(c: NarrativeCharacter, p: var PropertyVisitor) =
    p.visitProperty("bodyNumber", c.bodyNumber)
    p.visitProperty("headNumber", c.headNumber)
    p.visitProperty("rightPos", c.rightPos)
    p.visitProperty("kind", c.kind)

method getBBox*(c: NarrativeCharacter): BBox =
    var bodyNode: Node

    let bodyNum = if c.bodyNum < 10: "0" & $c.bodyNum else: $c.bodyNum
    for child in c.content.children:
        if child.name.find(bodyNum) > -1:
            bodyNode = child
            break
    
    if bodyNode.isNil:
        return

    let minX = bodyNode.positionX - bodyNode.anchor.x
    let minY = bodyNode.positionY - bodyNode.anchor.y

    result.minPoint = newVector3(minX, minY)
    result.maxPoint = newVector3(minX + bodyNode.anchor.x * 2, minY + bodyNode.anchor.y * 2)

registerComponent(NarrativeCharacter, "Narrative")
