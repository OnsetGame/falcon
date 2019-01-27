import strutils, json
import rod / [ rod_types, node, component, quaternion ]
import rod / component / ui_component
import rod.tools.serializer
# import rod / utils / [ property_desc, serialization_codegen ]
import nimx / [ app, property_visitor, matrixes, types, animation, timer, button, event, view, view_event_handling ]

import narrative / [ narrative_bubble, narrative_character ]
import shared / localization_manager
import shared / window / [ button_component, window_manager ]
import utils / [ helpers, falcon_analytics ]

import core / flow / [ flow, flow_state_types ]
import falconserver.tutorial.tutorial_types

import shafa / game / narrative_types

type QuestTutButton* = ref object of Button

type QuestNarrative* = ref object of Component
    isRight: bool
    isBottom: bool
    # nextBttn: QuestTutButton

    character: NarrativeCharacter
    bubble: NarrativeBubble
    onClose*: proc()
    isBusy: bool
    mKind: NarrativeCharacterType

type QuestNarrativeState* = ref object of BaseFlowState
    ndata*: NarrativeData
    narrative: QuestNarrative

method onScroll*(b: QuestTutButton, e: var Event): bool =
    result = true

proc createTutButton(parent: Node, rect: Rect): QuestTutButton=
    result = new(QuestTutButton, rect)
    result.init(rect)
    parent.addComponent(UIComponent).view = result
    result.hasBezel = false


method appearsOn*(state: QuestNarrativeState, cur: BaseFlowState): bool = cur of MapFlowState


proc `right=`*(c: QuestNarrative, right: bool) =
    c.isRight = right
    c.character.rightPos = right
    c.bubble.rightPos = right

proc right*(c: QuestNarrative): bool =
    result = c.isRight


proc `bottom=`*(c: QuestNarrative, bottom: bool) =
    c.isBottom = bottom
    c.bubble.bottomPos = bottom

proc bottom*(c: QuestNarrative): bool =
    result = c.isBottom


proc kind*(c: QuestNarrative): NarrativeCharacterType =
    result = c.mKind

proc `kind=`*(c: QuestNarrative, t: NarrativeCharacterType) =
    if not c.character.isNil:
        c.mKind = t
        c.character.kind = t


proc createContent(c: QuestNarrative) =
    c.character = c.node.component(NarrativeCharacter)
    c.bubble = c.node.component(NarrativeBubble)


proc show(c: QuestNarrative, t: float32) =
    c.character.show(t)
    c.bubble.show()

method wakeUp*(state: QuestNarrativeState) =
    let anchor = sharedWindowManager().getNarrativeAnchor()
    let narrNode = newNode("questNarrative")
    anchor.addChild(narrNode)

    let narrative = narrNode.component(QuestNarrative)
    narrative.createContent()
    narrative.kind = state.ndata.character
    narrative.bubble.text = state.ndata.bubbleText
    narrative.right = state.ndata.characterIsRight
    narrative.bottom = state.ndata.bubbleIsBottom
    narrative.character.bodyNumber = state.ndata.body.int
    narrative.character.headNumber = state.ndata.head.int
    narrative.bubble.speaker = state.ndata.character
    narrative.show(0.2)

    # block charStub:
    #     let bbox = narrative.character.getBBox()
    #     discard narrative.character.content.createButtonComponent(newRect(bbox.minPoint.x, bbox.minPoint.y, bbox.maxPoint.x - bbox.minPoint.x, bbox.maxPoint.y - bbox.minPoint.y))

    block bubbleStub:
        let bbox = narrative.bubble.getBBox()
        let width = bbox.maxPoint.x - bbox.minPoint.x
        let height = bbox.maxPoint.y - bbox.minPoint.y
        discard narrative.bubble.content.createButtonComponent(newRect(bbox.minPoint.x - width, bbox.minPoint.y, width * 3, height))

    mainApplication().pushEventFilter do(e: var Event, control: var EventFilterControl) -> bool:
        if e.buttonState == bsUp:
            state.pop()
            control = efcBreak

    state.narrative = narrative

    narrative.onClose = proc() =
        state.pop()

method onClose*(state: QuestNarrativeState) =
    if not state.narrative.isNil and not state.narrative.node.isNil:
        state.narrative.node.removeFromParent()
        state.narrative = nil

method visitProperties*(c: QuestNarrative, p: var PropertyVisitor) =
    p.visitProperty("right", c.right)
    p.visitProperty("bottom", c.bottom)
    p.visitProperty("kind", c.kind)

registerComponent(QuestNarrative, "QuestNarrative")
