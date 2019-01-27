import json
import strutils

import nimx.types
import nimx.context
import nimx.property_visitor
import nimx.timer
import nimx.animation
import nimx.notification_center
import nimx.view
import nimx.button
import nimx.event

import rod.rod_types
import rod.node
import rod.tools.serializer
import rod.component
import rod.component.text_component
import rod.component.ui_component
import rod.component.color_balance_hls
import rod.viewport
import rod / utils / [ property_desc, serialization_codegen ]

import utils.helpers
import shared.game_scene
import utils.falcon_analytics_helpers


type
    NXButton* = ref object of Button
        rootNode*: Node
        anim*: Animation
        inFocus: bool
        focusEnterAnim: Animation
        focusLeaveAnim: Animation

    ButtonComponent* = ref object of UIComponent
        mTitle: Text
        upState*: Node
        downState*: Node
        enableState*: Node
        nxButton*: NXButton
        actionHandler: proc()
        visibleDisable*: bool

ButtonComponent.properties:
    bounds:
        phantom: Rect

proc validateSize(r: Rect): Rect =
    let limit = 120.Coord
    var newSize = r.size
    var shift: Point

    if newSize.width < limit:
        shift.x = (limit - newSize.width) / 2
        newSize.width = 120

    if newSize.height < limit:
        shift.y = (limit - newSize.height) / 2
        newSize.height = 120

    result = newRect(r.origin - shift, newSize)

proc addAnimation(b: NXButton, a: Animation)=
    b.rootNode.addAnimation(a)

method onTouchEv*(b: NXButton, e: var Event): bool =
    let prevState = b.enabled

    if prevState:
        result = procCall b.Button.onTouchEv(e)
        if not b.anim.isNil and b.state == bsUp:
            b.addAnimation(b.anim)
        else:
            if b.state == bsUp:
                if b.inFocus and not b.focusLeaveAnim.isNil:
                    b.addAnimation(b.focusLeaveAnim)
                b.inFocus = false
            elif b.state == bsDown:
                # ANALYTICS
                setCurrGUIModuleAnalytics( if not b.rootNode.parent.isNil: b.rootNode.parent.name else: b.rootNode.name )

                if not b.inFocus and not b.focusEnterAnim.isNil:
                    b.addAnimation(b.focusEnterAnim)
                b.inFocus = true

proc setUpAnimations(b: NXButton)=
    if not b.anim.isNil:
        b.focusEnterAnim = newAnimation()
        b.focusEnterAnim.numberOfLoops = 1
        b.focusEnterAnim.loopDuration = b.anim.loopDuration / 2.0
        b.focusEnterAnim.onAnimate = proc(p: float)=
            b.anim.onProgress(interpolate(0.0, p * 0.5, p))

        b.focusLeaveAnim = newAnimation()
        b.focusLeaveAnim.numberOfLoops = 1
        b.focusLeaveAnim.loopDuration = b.anim.loopDuration / 2.0
        b.focusLeaveAnim.onAnimate = proc(p: float) =
            b.anim.onProgress(interpolate(0.5, p * 0.5 + 0.5, p))
    else:
        b.focusEnterAnim = nil
        b.focusLeaveAnim = nil

proc setButtonParts(b: ButtonComponent) =
    for ch in b.node.children:
        if ch.name.find("_on") > -1 or ch.name.find("_down") > -1:
            b.downState = ch
        elif ch.name.find("_off") > -1 or ch.name.find("_up") > -1:
            b.upState = ch
        elif ch.name.find("title") > -1 and not ch.getComponent(Text).isNil:
            b.mTitle = ch.getComponent(Text)

proc `bounds=`*(b: ButtonComponent, rect: Rect) =
    let r = validateSize(rect)
    b.nxButton.setFrame(r)

proc bounds*(b: ButtonComponent): Rect =
    result = b.nxButton.frame()

proc `animation=`*(b: ButtonComponent, a: Animation) =
    b.nxButton.anim = a
    b.nxButton.setUpAnimations()

proc animation*(b: ButtonComponent): Animation =
    result = b.nxButton.anim

proc `pressAnim=`*(b: ButtonComponent, a: Animation)=
    b.nxButton.anim = a
    b.nxButton.setUpAnimations()

proc `title=`*(b: ButtonComponent, text: string) =
    if b.mTitle.isNil:
        b.setButtonParts()
        assert(not b.mTitle.isNil)
    b.mTitle.text = text

proc title*(b: ButtonComponent): string =
    if not b.mTitle.isNil:
        result = b.mTitle.text

proc `textColor=`*(b: ButtonComponent, newTextColor:Color) =
    if not b.mTitle.isNil:
        b.mTitle.color = newTextColor

method enabled*(b: ButtonComponent): bool =
    result = procCall b.UIComponent.enabled() and b.nxButton.enabled

method `enabled=`*(b: ButtonComponent, state: bool) =
    procCall b.UIComponent.`enabled=`(state)
    b.nxButton.enabled = state
    if b.visibleDisable:
        if not b.downState.isNil:
            b.downState.component(ColorBalanceHLS).saturation = if not state: -1.0 else: 0.0
        if not b.upState.isNil:
            b.upState.component(ColorBalanceHLS).saturation = if not state: -1.0 else: 0.0

proc onAction*(b: ButtonComponent, handler: proc()) =
    b.actionHandler = handler

proc sendAction*(b: ButtonComponent) =
    if not b.actionHandler.isNil and b.enabled:
        b.actionHandler()

method init(b: ButtonComponent) =
    procCall b.UIComponent.init()
    # var bbox = b.node.nodeBounds()
    # let rect = newRect(0, 0, bbox.maxPoint.x - bbox.minPoint.x, bbox.maxPoint.y - bbox.minPoint.y)
    let rect = newRect(0,0,1,1)
    b.nxButton = new(NXButton, rect)

method componentNodeWasAddedToSceneView*(b: ButtonComponent) =
    procCall b.UIComponent.componentNodeWasAddedToSceneView()
    b.nxButton.rootNode = b.node
    b.nxButton.hasBezel = false
    if b.nxButton.View != b.view:
        b.view = b.nxButton

    b.setButtonParts()

    if not b.node.animationNamed("button_down").isNil:
        b.nxButton.focusEnterAnim = b.node.animationNamed("button_down")
    if not b.node.animationNamed("button_up").isNil:
        b.nxButton.focusLeaveAnim = b.node.animationNamed("button_up")

    b.nxButton.onAction do():
        if not b.actionHandler.isNil:
            b.actionHandler()

proc createButtonComponent*(parent: Node, a: Animation, rect: Rect): ButtonComponent=
    let r = validateSize(rect)
    result = parent.addComponent(ButtonComponent)
    result.nxButton.init(r)
    result.nxButton.hasBezel = false
    result.nxButton.anim = a
    result.nxButton.setUpAnimations()
    result.visibleDisable = true
    result.setButtonParts()

proc createButtonComponent*(parent: Node, rect: Rect): ButtonComponent =
    let r = validateSize(rect)
    result = parent.addComponent(ButtonComponent)
    result.nxButton.init(r)
    result.nxButton.hasBezel = false
    result.nxButton.focusEnterAnim = parent.animationNamed("button_down")
    result.nxButton.focusLeaveAnim = parent.animationNamed("button_up")
    result.visibleDisable = true
    result.setButtonParts()

    # if result.nxButton.focusEnterAnim.isNil:
    #     parent.scaleTo(newVector3(0.8), 0.2)

    # if result.nxButton.focusLeaveAnim.isNil:
    #     parent.scaleTo(newVector3(1.0), 0.2)

proc createHoldButtonComponent*(parent: Node, a: Animation, rect: Rect, holdDuration: float): ButtonComponent =
    let r = validateSize(rect)
    result = parent.addComponent(ButtonComponent)
    result.nxButton.init(r)
    result.nxButton.behavior = bbHold
    result.nxButton.holdDuration = holdDuration
    result.nxButton.hasBezel = false
    result.nxButton.anim = a
    result.nxButton.setUpAnimations()
    result.visibleDisable = true
    result.setButtonParts()

method serialize*(b: ButtonComponent, s: Serializer): JsonNode =
    result = newJObject()
    result.add("bounds", s.getValue(b.bounds))

method deserialize*(b: ButtonComponent, j: JsonNode, s: Serializer) =
    if j.isNil: return
    s.deserializeValue(j, "bounds", b.bounds)

proc toPhantom(b: ButtonComponent, p: var object) =
    p.bounds = b.bounds

proc fromPhantom(b: ButtonComponent, p: object) =
    b.bounds = p.bounds

method visitProperties*(b: ButtonComponent, p: var PropertyVisitor) =
    if not b.mTitle.isNil:
        p.visitProperty("title", b.title)
    p.visitProperty("upState", b.upState)
    p.visitProperty("downState", b.downState)
    p.visitProperty("bounds", b.bounds)

    b.view.visitProperties(p)

genSerializationCodeForComponent(ButtonComponent)
registerComponent(ButtonComponent, "Falcon")


