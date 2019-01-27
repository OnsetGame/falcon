import strutils, json
import rod / [ rod_types, node, component, quaternion ]
import rod / component / ui_component
import rod.tools.serializer
# import rod / utils / [ property_desc, serialization_codegen ]
import nimx / [ property_visitor, matrixes, types, animation, timer, button, event, view, view_event_handling ]

import narrative / [ narrative_bubble, narrative_character ]
import shared / localization_manager
import shared / window / [ button_component, window_manager ]
import utils / [ helpers, falcon_analytics ]

import core / flow / [ flow, flow_state_types ]
import falconserver.tutorial.tutorial_types

type TutButton* = ref object of Button

type ArrowType* = enum
    arrNone
    arrDown
    arrLeft
    arrRight
    arrUp

type NarrativeFrame* = object
    right*: bool
    bottom*: bool
    needZoom*: bool
    withoutAction*: bool
    showDelay*: float32
    text*: string
    secondText*: string
    characterBody*: int
    characterHead*: int
    targetName*: string
    arrowType*: ArrowType

type Narrative* = ref object of Component
    analyticName: string
    isRight: bool
    isBottom: bool
    nextBttn: TutButton
    mCurrFrame: int

    # mArrowType: ArrowType
    mTarget: Node
    arrow: Node

    character: NarrativeCharacter
    bubble: NarrativeBubble
    mFrames: seq[NarrativeFrame]
    onClose*: proc()
    isBusy: bool
    actionOnComplete*: bool

type NarrativeState* = ref object of BaseFlowState
    composName*: string
    frames*: seq[NarrativeFrame]
    target*: Node
    onClose*: proc()

method onScroll*(b: TutButton, e: var Event): bool =
    result = true

proc createTutButton(parent: Node, rect: Rect): TutButton=
    result = new(TutButton, rect)
    result.init(rect)
    parent.addComponent(UIComponent).view = result
    result.hasBezel = false


method getType*(state: NarrativeState): FlowStateType = NarrativeFS
method getFilters*(state: NarrativeState): seq[FlowStateType] = return @[ZoomMapFS]

proc `right=`*(c: Narrative, right: bool) =
    c.isRight = right
    c.character.rightPos = right
    c.bubble.rightPos = right

proc right*(c: Narrative): bool =
    result = c.isRight

proc `bottom=`*(c: Narrative, bottom: bool) =
    c.isBottom = bottom
    c.bubble.bottomPos = bottom

proc bottom*(c: Narrative): bool =
    result = c.isBottom

proc setUpArrow(c: Narrative, target: Node, kind: ArrowType) =
    if target.isNil or c.arrow.isNil or kind == arrNone:
        c.isBusy = false
        return

    let arrow = c.arrow
    arrow.show(0.2) do():
        c.isBusy = false

    var a = newAnimation()
    a.loopDuration = 1.0
    a.numberOfLoops = -1
    a.loopPattern = lpStartToEndToStart

    let oldAnim = arrow.animationNamed("narrativeArrowAnimation")
    if not oldAnim.isNil:
        oldAnim.cancel()

    var tBB = target.nodeBounds()
    let arrNode = arrow.findNode("arrow_tutorial.png")
    arrNode.position = newVector3(0.0)
    let wldBounds = absVector(tBB.maxPoint - tBB.minPoint)
    case kind
        of arrUp:
            arrow.scale = newVector3(1, -1, 1)
            arrow.rotation = newQuaternion(0.0, 0.0, 0.0)
            arrow.worldPos = newVector3(tBB.minPoint.x + wldBounds.x / 2.0, tBB.maxPoint.y, 0.0)
        of arrLeft:
            arrow.scale = newVector3(1, -1, 1)
            arrow.rotation = newQuaternion(0.0, 0.0, -90.0)
            arrow.worldPos = newVector3(tBB.minPoint.x, tBB.minPoint.y + wldBounds.y / 2.0, 0.0)
        of arrRight:
            arrow.scale = newVector3(1, 1, 1)
            arrow.rotation = newQuaternion(0.0, 0.0, -90.0)
            arrow.worldPos = newVector3(tBB.maxPoint.x, tBB.minPoint.y + wldBounds.y / 2.0, 0.0)
        else:
            arrow.scale = newVector3(1, 1, 1)
            arrow.rotation = newQuaternion(0.0, 0.0, 0.0)
            arrow.worldPos = newVector3(tBB.minPoint.x + wldBounds.x / 2.0, tBB.minPoint.y, 0.0)

    a.animate val in arrNode.positionY() .. arrNode.positionY() - 30.0:
        arrNode.positionY = val
    arrow.addAnimation(a)
    arrow.registerAnimation("narrativeArrowAnimation", a)

proc nextFrame(c: Narrative)

proc createContent(c: Narrative) =
    c.character = c.node.component(NarrativeCharacter)
    c.character.kind = NarrativeCharacterType.WillFerris
    c.bubble = c.node.component(NarrativeBubble)
    c.bubble.speaker = NarrativeCharacterType.WillFerris
    c.right = false

    c.node.sceneView.cancelAllTouches()
    c.nextBttn = c.node.createTutButton(newRect(-500, -500, 3000, 2000))
    c.nextBttn.onAction do():
        if not c.isBusy:
            c.nextFrame()
        else:
            c.bubble.skipTyping()

proc isUseTutorBufferForAnalytics*(name: string): bool =
    result = not (name == $tsSpinButton or name == $tsTaskProgressPanel)

proc `target=`*(c: Narrative, target: Node) =
    c.mTarget = target

proc target*(c: Narrative): Node =
    result = c.mTarget

proc setupFrame(c: Narrative) =
    if c.mCurrFrame < c.mFrames.len:
        let frame = c.mFrames[c.mCurrFrame]
        sharedAnalytics().tutorial_step(c.analyticName, c.mCurrFrame+1, isUseTutorBufferForAnalytics(c.analyticName))

        c.right = frame.right
        c.bottom = frame.bottom
        c.bubble.text = localizedString(frame.text)

        c.character.headNumber = frame.characterHead
        c.character.bodyNumber = frame.characterBody
        c.bubble.onTextTyped = proc() =
            if frame.targetName.len > 0:
                let target = c.node.sceneView.rootNode.findNode(frame.targetName)
                if not target.isNil:
                    c.target = target
                    c.setUpArrow(target, frame.arrowType)
                else:
                    c.isBusy = false
            else:
                c.isBusy = false

        if frame.targetName.len > 0 and frame.needZoom:
            let target = c.node.sceneView.rootNode.findNode(frame.targetName)
            if not target.isNil:
                c.target = target
                let zoomState = newFlowState(ZoomMapFlowState)
                zoomState.targetPos = target.worldPos
                execute(zoomState)

        if frame.secondText.len == 0:
            c.bubble.secondText = "Next"
        else:
            c.bubble.secondText = localizedString(frame.secondText)

proc `currFrame=`*(c: Narrative, frame: int) =
    c.mCurrFrame = frame
    c.isBusy = true
    let delay = c.mFrames[c.mCurrFrame].showDelay
    setTimeout(delay) do():
        if c.mCurrFrame == 0:
            c.character.show(0.0)
            setTimeout(0.3) do():
                c.bubble.show()
        c.setupFrame()

proc currFrame*(c: Narrative): int =
    result = c.mCurrFrame

proc doTargetAction(c: Narrative) =
    if not c.mTarget.isNil:
        var bttns = newSeq[ButtonComponent]()
        c.mTarget.componentsInNode(bttns)
        if bttns.len > 0:
            bttns[0].sendAction()

proc nextFrame(c: Narrative) =
    c.isBusy = true
    c.arrow.hide(0.2)
    if not c.mFrames[c.mCurrFrame].withoutAction:
        c.doTargetAction()

    c.mCurrFrame = c.mCurrFrame + 1
    if c.mCurrFrame < c.mFrames.len:
        let delay = c.mFrames[c.mCurrFrame].showDelay
        setTimeout(delay) do():
            c.setupFrame()

    else:
        c.character.hide(0.3)
        c.bubble.hide()
        c.bubble.onClose = proc() =
            if not c.onClose.isNil:
                c.onClose()

            c.node.removeFromParent()
            c.isBusy = false

proc setFrames*(c: Narrative, fr: seq[NarrativeFrame]) =
    if c.character.isNil:
        c.createContent()

    c.mFrames = fr
    c.currFrame = 0

proc `frames=`(c: Narrative, fr: seq[NarrativeFrame]) =
    if c.character.isNil:
        c.createContent()

    c.mFrames = fr
    c.currFrame = c.mCurrFrame

proc frames(c: Narrative): seq[NarrativeFrame] =
    result = c.mFrames


method componentNodeWasAddedToSceneView*(c: Narrative) =
    if not c.nextBttn.isNil:
        return

    c.arrow = newNodeWithResource("common/gui/precomps/arrow_tutorial")
    c.arrow.findNode("arrow_tutorial.png").position = newVector3(0.0)
    c.arrow.alpha = 0.0
    c.node.addChild(c.arrow)

method wakeUp*(state: NarrativeState) =
    let anchor = sharedWindowManager().getNarrativeAnchor()
    var narrNode: Node
    try:
        narrNode = newNodeWithResource("common/narrative_frames/" & state.composName)
    except:
        narrNode = newNodeWithResource("common/narrative_frames/default")
    anchor.addChild(narrNode)
    let narrative = narrNode.component(Narrative)
    narrative.target = state.target
    narrative.analyticName = state.composName

    narrative.createContent()
    narrative.currFrame = 0

    narrative.onClose = proc() =
        if not state.onClose.isNil:
            state.onClose()
        state.pop()


method deserialize*(c: Narrative, j: JsonNode, s: Serializer) =
    if j.isNil:
        return
    # s.deserializeValue(j, "actionOnComplete", c.actionOnComplete)
    let frames = j["frames"]
    var frSeq = newSeq[NarrativeFrame]()
    for frame in frames:
        var fr: NarrativeFrame
        s.deserializeValue(frame, "right", fr.right)
        s.deserializeValue(frame, "bottom", fr.bottom)
        s.deserializeValue(frame, "needZoom", fr.needZoom)
        s.deserializeValue(frame, "withoutAction", fr.withoutAction)
        s.deserializeValue(frame, "showDelay", fr.showDelay)
        s.deserializeValue(frame, "text", fr.text)
        s.deserializeValue(frame, "secondText", fr.secondText)
        s.deserializeValue(frame, "characterBody", fr.characterBody)
        s.deserializeValue(frame, "characterHead", fr.characterHead)
        s.deserializeValue(frame, "targetName", fr.targetName)
        s.deserializeValue(frame, "arrowType", fr.arrowType)
        frSeq.add(fr)

    c.mFrames = frSeq

method serialize*(c: Narrative, s: Serializer): JsonNode =
    result = newJObject()
    # result.add("actionOnComplete", s.getValue(c.actionOnComplete))

    let jframes = newJArray()
    result["frames"] = jframes
    for frame in c.frames:
        var jFrame = newJObject()
        jFrame.add("right", s.getValue(frame.right))
        jFrame.add("bottom", s.getValue(frame.bottom))
        jFrame.add("needZoom", s.getValue(frame.needZoom))
        jFrame.add("withoutAction", s.getValue(frame.withoutAction))
        jFrame.add("showDelay", s.getValue(frame.showDelay))
        jFrame.add("text", s.getValue(frame.text))
        jFrame.add("secondText", s.getValue(frame.secondText))
        jFrame.add("characterBody", s.getValue(frame.characterBody))
        jFrame.add("characterHead", s.getValue(frame.characterHead))
        jFrame.add("targetName", s.getValue(frame.targetName))
        jFrame.add("arrowType", s.getValue(frame.arrowType))
        jframes.add(jFrame)

method visitProperties*(c: Narrative, p: var PropertyVisitor) =
    p.visitProperty("right", c.right)
    p.visitProperty("bottom", c.bottom)
    # p.visitProperty("actionOnComplete", c.actionOnComplete)
    p.visitProperty("currFrame", c.currFrame)
    p.visitProperty("frames", c.frames)
    var comp = c
    p.visitProperty("save", comp)

registerComponent(Narrative, "Narrative")
