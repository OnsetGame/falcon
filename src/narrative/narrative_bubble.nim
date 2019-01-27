import strutils, unicode
import node_proxy / proxy
import rod / [ rod_types, node, component ]
import rod / component / [ text_component, ae_composition, comp_ref ]
import nimx / [ property_visitor, matrixes, types, animation ]

import shared / window / button_component
import shared / [ director, game_scene ]
import utils / [ helpers, sound_manager, sound ]
import core / helpers / narrative_helpers

nodeProxy NarrativeBubbleProxy:
    anchor      Node {withName:"anchor"}
    bubble      Node {withName:"tutorial_holder_01"}
    skip        Node {withName:"skip_button"}
    speaker     Node {withName:"speaker_title"}
    speakerName Text {onNode: np.speaker.findNode("title")}
    skipBttn    ButtonComponent {onNode:"skip_button"}
    animComp    AEComposition {onNode:node}
    text        Text {onNode:"text"}:
        bounds = newRect(-670, -110, 1380, 179)
        horizontalAlignment = haCenter
        verticalAlignment = vaCenter

    secondText Text {onNode:"bttn_title"}:
        bounds = newRect(-920, -12, 955, 0)
        horizontalAlignment = haRight
        verticalAlignment = vaCenter

type NarrativeBubble* = ref object of Component
    proxy: NarrativeBubbleProxy
    content*: Node
    isRight: bool
    isBottom: bool
    onTextTyped*: proc()
    onClose*: proc()
    typeSound: Sound

const ANCHOR_LEFT_X = 1160
const ANCHOR_RIGHT_X = 740

const ANCHOR_TOP_Y = 310
const SPEAKER_TOP_Y = -46
const TEXT_TOP_Y = -158
const SKIP_TOP_Y = -88

const ANCHOR_BOTTOM_Y = 775
const SPEAKER_BOTTOM_Y = 55
const TEXT_BOTTOM_Y = 190
const SKIP_BOTTOM_Y = 250

const BUBBLE_TEXT_TYPE_SOUND_PATH = "common/sounds/text_type_sound"
const TEXT_ANIM_SPEED = 0.04

proc `rightPos=`*(c: NarrativeBubble, right: bool) =
    c.isRight = right
    if right:
        c.proxy.bubble.scaleX = -1.0
        c.proxy.anchor.positionX = ANCHOR_RIGHT_X
    else:
        c.proxy.bubble.scaleX = 1.0
        c.proxy.anchor.positionX = ANCHOR_LEFT_X

proc rightPos*(c: NarrativeBubble): bool =
    result = c.isRight

proc `bottomPos=`*(c: NarrativeBubble, bottom: bool) =
    c.isBottom = bottom
    if bottom:
        c.proxy.bubble.scaleY = -1.0
        c.proxy.anchor.positionY = ANCHOR_BOTTOM_Y
        c.proxy.speaker.positionY = SPEAKER_BOTTOM_Y
        c.proxy.text.node.positionY = TEXT_BOTTOM_Y
        c.proxy.skip.positionY = SKIP_BOTTOM_Y
    else:
        c.proxy.bubble.scaleY = 1.0
        c.proxy.anchor.positionY = ANCHOR_TOP_Y
        c.proxy.speaker.positionY = SPEAKER_TOP_Y
        c.proxy.text.node.positionY = TEXT_TOP_Y
        c.proxy.skip.positionY = SKIP_TOP_Y

proc bottomPos*(c: NarrativeBubble): bool =
    result = c.isBottom

proc skipTyping*(c: NarrativeBubble) =
    let a = c.node.animationNamed("bubbleTextAnim_new", false)
    if not a.isNil:
        a.cancelBehavior = cbJumpToEnd
        a.cancel()

proc animateText(c: NarrativeBubble) =
    if c.proxy.text.mText.len() == 0:
        return

    let a = c.node.animationNamed("bubbleTextAnim")
    a.removeHandlers()
    var prevPos = -1
    let newA = a.addOnAnimate do(p: float):
        let pos = interpolate(0, c.proxy.text.text.runeLen, p)
        if prevPos != pos:
            c.proxy.text.mText.setTextAlphaInRange(0, pos, 1.0)
            prevPos = pos
            if pos == c.proxy.text.text.runeLen:
                if not c.typeSound.isNil:
                    c.typeSound.stop()
                c.proxy.skip.show(0.2)
                if not c.onTextTyped.isNil:
                    c.onTextTyped()

    newA.loopDuration = c.proxy.text.text.runeLen.float * TEXT_ANIM_SPEED
    c.node.registerAnimation("bubbleTextAnim_new", newA)
    c.node.addAnimation(newA)

proc `speaker=`*(c: NarrativeBubble, speaker: NarrativeCharacterType) =
    if speaker == None:
        c.proxy.speaker.alpha = 0.0
    else:
        c.proxy.speaker.alpha = 1.0
        c.proxy.speakerName.text = speaker.name

proc `text=`*(c: NarrativeBubble, text: string) =
    c.proxy.skip.hide()
    c.proxy.text.text = text
    for i in 1 .. c.proxy.text.text.runeLen:
        c.proxy.text.mText.setTextAlphaInRange(0, i, 1.0)

    c.proxy.text.mText.setTextAlphaInRange(0, -1, 0.0)
    c.animateText()

    if not currentDirector().currentScene.isNil:
        c.typeSound = currentDirector().currentScene.soundManager.playSFX(BUBBLE_TEXT_TYPE_SOUND_PATH)
        c.typeSound.trySetLooping(true)

proc `secondText=`*(c: NarrativeBubble, text: string) =
    c.proxy.secondText.text = text

proc show*(c: NarrativeBubble) =
    let showAnim = c.proxy.animComp.play("show")
    if not currentDirector().currentScene.isNil:
        currentDirector().currentScene.soundManager.sendEvent("NARRATIVE_BUBBLE_SHOW")

proc hide*(c: NarrativeBubble) =
    if not c.typeSound.isNil:
        c.typeSound.stop()
    let hideAnim = c.proxy.animComp.play("hide")
    hideAnim.onComplete do():
        if not c.onClose.isNil:
            c.onClose()

method componentNodeWasAddedToSceneView*(c: NarrativeBubble) =
    if c.proxy.isNil:
        c.proxy = new(NarrativeBubbleProxy, newNodeWithResource("common/gui/precomps/narrative_buble"))
        c.content = c.proxy.anchor
        c.node.addChild(c.proxy.node)
        c.rightPos = false
        c.proxy.skipBttn.enabled = false

        var a = newAnimation()
        a.loopDuration = 2.0#TEXT_ANIM_SPEED
        a.numberOfLoops = 1
        c.node.registerAnimation("bubbleTextAnim", a)

method visitProperties*(c: NarrativeBubble, p: var PropertyVisitor) =
    p.visitProperty("rightPos", c.rightPos)
    p.visitProperty("bottomPos", c.bottomPos)

method getBBox*(c: NarrativeBubble): BBox =
    let bodyNode = c.proxy.bubble
    let bbox = bodyNode.getComponent(CompRef).getBBox()

    result.minPoint = newVector3(bodyNode.position.x - bodyNode.anchor.x, bbox.minPoint.y)
    result.maxPoint = newVector3(bbox.maxPoint.x - bbox.minPoint.x + result.minPoint.x, bbox.maxPoint.y)

registerComponent(NarrativeBubble, "Narrative")
