import rod.node
import rod.viewport

import nimx.event
import nimx.view
import nimx.button
import nimx.animation

import rod.component
import rod.component.ui_component
import rod.component.text_component

import gui_module_types
import utils.helpers
import utils.falcon_analytics_helpers
import utils.console
import strutils

export helpers

type GUIModule* = ref object of RootObj
    rootNode*: Node
    moduleType*: GUIModuleType

type AnimatedButton* = ref object of Button
    rootNode*: Node
    anim*: Animation
    playFullAnim*: bool
    inFocus: bool
    focusEnterAnim: Animation
    focusLeaveAnim: Animation

method clickAnim*(b: AnimatedButton): Animation {.base.} =
    result = b.anim

var guiBtnBezelDebug = false

method onRemoved*(gm: GUIModule){.base.} = discard # any gui_module
method onAdded*(gm: GUIModule){.base.} = discard # for popups

proc addAnimation(b: AnimatedButton, a: Animation) =
    b.rootNode.addAnimation(a)

method onTouchEv*(b: AnimatedButton, e: var Event): bool =
    let prevState = b.enabled

    if prevState:
        result = procCall b.Button.onTouchEv(e)
        if b.playFullAnim:
            if not b.inFocus and b.state == bsDown:
                b.inFocus = true
            elif b.state == bsUp and b.inFocus:
                if b.inFocus and e.buttonState == bsUp:
                    b.addAnimation(b.clickAnim)
                b.inFocus = false
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
proc setUpAnimations(b: AnimatedButton)=
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

proc setup(b: AnimatedButton, parent: Node, a: Animation, frame: Rect) =
    b.rootNode = parent
    b.anim = a
    b.setUpAnimations()
    b.init(frame)
    parent.component(UIComponent).view = b
    b.hasBezel = guiBtnBezelDebug

proc createAnimatedButton*(m: GUIModule, a: Animation, width, height: float, name: string, offsetWidth: float = 0, offsetHeight: float = 0): AnimatedButton =
    let buttonParent = m.rootNode.newChild(name & "_parent")
    let frame = newRect(offsetWidth, offsetHeight, width, height)

    result = new(AnimatedButton, frame)
    result.setup(buttonParent, a, frame)

proc createAnimatedButton*(parent: Node, a: Animation, rect: Rect): AnimatedButton=
    result = new(AnimatedButton, rect)
    result.setup(parent, a, rect)

proc createAnimatedButton*(parent: Node, rect: Rect): AnimatedButton=
    result = new(AnimatedButton, rect)
    result.rootNode = parent
    result.focusEnterAnim = parent.animationNamed("button_down")
    result.focusLeaveAnim = parent.animationNamed("button_up")

    result.init(rect)
    parent.component(UIComponent).view = result
    result.hasBezel = guiBtnBezelDebug

proc setPopupState*(popupTitle: Node, isActive: bool)=
    let activeAlpha = if isActive: 1.0 else: 0.0
    let unactiveAlpha = if isActive: 0.0 else: 1.0
    if not popupTitle.isNil:
        popupTitle.findNode("title_active").alpha = activeAlpha
        popupTitle.findNode("title_unactive").alpha = unactiveAlpha
        popupTitle.findNode("active").alpha = activeAlpha
        popupTitle.findNode("unactive").alpha = unactiveAlpha

proc setPopupTitle*(popupTitle: Node, title:string)=
    if not popupTitle.isNil:
        popupTitle.setPopupState(true)
        popupTitle.findNode("title_active").component(Text).text = title
        popupTitle.findNode("title_unactive").component(Text).text = title


proc setPopupTitle*(module: GUIModule, title: string)=
    module.rootNode.findNode("popup_title").setPopupTitle(title)

proc setPopupState*(module: GUIModule, isActive: bool)=
    module.rootNode.findNode("popup_title").setPopupState(isActive)


type MultiAnimatedButton* = ref object of AnimatedButton
    aIndex: int
    animations*: seq[Animation]

template index*(b: MultiAnimatedButton): int = b.aIndex
proc playIndex*(b: MultiAnimatedButton, index: int) =
    b.aIndex = index
    b.anim = b.animations[b.aIndex]
    b.setUpAnimations()

    b.addAnimation(b.clickAnim())

method nextIndex*(b: MultiAnimatedButton): int {.base.} =
    (b.aIndex + 1) mod b.animations.len

method clickAnim*(b: MultiAnimatedButton): Animation =
    result = procCall b.AnimatedButton.clickAnim()

    b.aIndex = b.nextIndex()
    b.anim = b.animations[b.aIndex]
    b.setUpAnimations()

proc createMultiAnimatedButton*(m: GUIModule, a: openarray[Animation], width, height: float, name: string, offsetWidth: float = 0, offsetHeight: float = 0): MultiAnimatedButton =
    let buttonParent = m.rootNode.newChild(name & "_parent")
    let frame = newRect(offsetWidth, offsetHeight, width, height)

    result = new(MultiAnimatedButton, frame)

    result.aIndex = 0
    result.animations = @a
    result.playFullAnim = true

    result.setup(buttonParent, a[0], frame)

proc createMultiAnimatedButton*(parent: Node, a: openarray[Animation], rect: Rect): MultiAnimatedButton =
    result = new(MultiAnimatedButton, rect)

    result.aIndex = 0
    result.animations = @a
    result.playFullAnim = true

    result.setup(parent, a[0], rect)


proc guiButtonsDebug(args: seq[string]): string=
    guiBtnBezelDebug = parseBool(args[0])
    result = "guiButtonsDebug switch: " & $guiBtnBezelDebug

method setVisible*(m: GUIModule, visible: bool) {.base.} =
    m.rootNode.alpha = visible.float
    m.rootNode.enabled = visible

registerConsoleComand(guiButtonsDebug, "guiButtonsDebug(enable: bool)")