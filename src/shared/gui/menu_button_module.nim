import logging, json, tables
import gui_module, gui_module_types
import rod / [ node, viewport ]
import rod / component
import rod / component / [ ui_component, text_component, comp_ref, sprite, solid ]
import nimx / [ types, matrixes, animation, control, event, button, app, view ]
import core / notification_center
import shared / [game_scene, director]
import quest / quests
import utils / [ falcon_analytics, game_state, helpers, icon_component ]
import shared / window / [button_component, window_manager]
import core / flow / [flow, flow_state_types]

type MenuButton* = enum
    mbMenuOpen
    mbMenuClose
    mbSettings = "settings_button_in_dropdown"
    mbBackToCity = "back_to_city_button_in_dropdown"
    mbPlay = "play_button_in_dropdown"
    mbSupport = "email_button_in_dropdown"
    mbFullscreen = "fullscreen_button_in_dropmenu"
    mbPayTable = "paytable_button_in_dropmenu"

type MenuButtonText* = enum
    mbtSettings = (mbSettings.int, "Settings")
    mbtBackToCity = (mbBackToCity.int, "Back to City")
    mbtPlay = (mbPlay.int, "Change Task")
    mbtSupport = (mbSupport.int, "Support")
    mbtFullscreen = (mbFullscreen.int, "Fullscreen")
    mbtPayTable = (mbPayTable.int, "PayTable")


type ActionButton = ref object
    rootNode: Node
    bttn: ButtonComponent
    animation: Animation
    kind: MenuButton
    fadeNode: Node

var isButtonEnabled = initTable[MenuButton, proc(): bool]()

isButtonEnabled[mbBackToCity] = proc():bool =
    result = hasGameState("SHOW_BACK_TO_CITY") and getBoolGameState("SHOW_BACK_TO_CITY")

isButtonEnabled[mbPlay] = proc():bool =
    result = isButtonEnabled[mbBackToCity]()
    # if result:
    #     result = sharedQuestManager().activeTasks().len == 0

proc isEnabled(ab: ActionButton): bool =
    let isEn = isButtonEnabled.getOrDefault(ab.kind)
    if isEn.isNil: return true
    else: return isEn()

proc new(T: typedesc[ActionButton], kind: MenuButton, rootNode: Node): T =
    T(
        kind: kind,
        rootNode: rootNode,
        bttn: rootNode.createButtonComponent(newRect(0, 0, 360.0, 153.0)) #rootNode.animationNamed("press"),
    )


proc show(b: ActionButton, duration, timeout: float) =
    b.bttn.enabled = false
    if not b.animation.isNil:
        b.animation.cancel()
    b.rootNode.alpha = 1.0
    let node = b.rootNode
    var pauseAnimation = newAnimation()
    pauseAnimation.loopDuration = timeout
    pauseAnimation.numberOfLoops = 1
    var showAnimation = node.animationNamed("in")
    showAnimation.loopPattern = lpStartToEnd
    var animation = newCompositAnimation(false, pauseAnimation, showAnimation)
    animation.numberOfLoops = 1
    animation.onComplete proc() =
        b.bttn.enabled = true
        b.animation = nil
    node.addAnimation(animation)
    b.animation = animation


proc hide(b: ActionButton, duration, timeout: float) =
    if not b.animation.isNil:
        b.animation.cancel()
    let node = b.rootNode
    var pauseAnimation = newAnimation()
    pauseAnimation.loopDuration = timeout
    pauseAnimation.numberOfLoops = 1
    var hideAnimation = node.animationNamed("in")
    hideAnimation.loopPattern = lpEndToStart
    var animation = newCompositAnimation(false, pauseAnimation, hideAnimation)
    animation.numberOfLoops = 1
    animation.onComplete proc() =
        b.rootNode.alpha = 0.0
        b.animation = nil
    node.addAnimation(animation)
    b.animation = animation
    b.bttn.enabled = false


type GMenuButton* = ref object of GUIModule
    bttnUp*: ButtonComponent
    actionButtons: seq[ActionButton]
    control: EventFilterControl
    flowState: WindowFlowState

const SHOW_HIDE_DURATION = 0.5
const BUTTON_SIZE = newSize(153.0, 153.0)

proc showBttns*(bttn: GMenuButton) =
    bttn.flowState = newFlowState(WindowFlowState)
    bttn.flowState.name = "MenuFlowState"
    bttn.flowState.execute()

    let k = SHOW_HIDE_DURATION / (bttn.actionButtons.len + 1).float
    var i = 0
    for b in bttn.actionButtons:
        if b.isEnabled():
            b.show(k, (i + 1).float * k)
            inc i
        else:
            b.bttn.enabled = false


proc hideBttns*(bttn: GMenuButton) =
    bttn.flowState.pop()
    let bttnsCount = bttn.actionButtons.len
    let k = SHOW_HIDE_DURATION / (bttnsCount + 1).float
    var i = 0
    for b in bttn.actionButtons:
        if b.isEnabled():
            b.hide(k, (bttnsCount - i - 1).float * k)
            inc i
        else:
            b.bttn.enabled = false

proc createMenuButton*(parent: Node): GMenuButton =
    result.new()
    result.moduleType = mtMenuButton
    result.actionButtons = @[]
    let bttn = result

    result.rootNode = newNode("menu_button")
    parent.addChild(result.rootNode)

    var winSize = VIEWPORT_SIZE
    let pos_x = -winSize.width - 100
    winSize.width *= 3
    let pos_y = -winSize.height - 100
    winSize.height *= 3
    var fadeNode = newNode("fade_node")
    result.rootNode.addChild(fadeNode)
    fadeNode.position = newVector3(pos_x, pos_y)
    fadeNode.alpha = 0.0
    var fadeNodeAnimation: Animation

    let solid = fadeNode.addComponent(Solid)
    solid.size = winSize + newSize(200, 200)
    solid.color = newColor(0.0, 0.0, 0.0, 0.75)

    let bttnDownNode = newLocalizedNodeWithResource("common/gui/ui2_0/menu_button")
    result.rootNode.addChild(bttnDownNode)

    let bttnUpNode = newLocalizedNodeWithResource("common/gui/ui2_0/menu_button_item_button")
    bttnUpNode.findNode("icon_button_placeholder").component(IconComponent).name = "close_dropmenu"
    result.rootNode.addChild(bttnUpNode)

    let dropDownBttnAnim = bttnDownNode.animationNamed("press")
    let dropDownBttn = bttnDownNode.createButtonComponent(dropDownBttnAnim, newRect(zeroPoint, BUTTON_SIZE))

    let dropUpBttnAnim = bttnUpNode.animationNamed("press")
    let dropUpBttn = bttnUpNode.createButtonComponent(dropUpBttnAnim, newRect(zeroPoint, BUTTON_SIZE))

    result.bttnUp = dropUpBttn

    let fadeNodeBttn = fadeNode.createButtonComponent(newRect(zeroPoint, winSize))
    fadeNodeBttn.enabled = false
    fadeNodeBttn.onAction do():
        dropUpBttn.sendAction()

    dropDownBttn.onAction do():
        bttn.rootNode.removeFromParent()
        sharedWindowManager().insertNodeBeforeWindows(bttn.rootNode)

        currentNotificationCenter().postNotification("MENU_CLICK_BUTTON", newVariant(mbMenuOpen))
        bttn.showBttns()
        sharedAnalytics().menubutton_inout("show", bttn.rootNode.sceneView.name)

        dropDownBttn.enabled = false
        fadeNodeBttn.enabled = true
        bttnDownNode.sceneView.GameScene.setTimeout(dropDownBttnAnim.loopDuration) do():
            bttnDownNode.enabled = false
            bttnUpNode.enabled = true

        if not fadeNodeAnimation.isNil:
            fadeNodeAnimation.cancel()
        fadeNodeAnimation = newAnimation()
        fadeNodeAnimation.loopDuration = SHOW_HIDE_DURATION
        fadeNodeAnimation.numberOfLoops = 1
        fadeNodeAnimation.onComplete do():
            fadeNodeAnimation = nil
            dropUpBttn.enabled = true
        let startOpacity = fadeNode.alpha
        fadeNodeAnimation.onAnimate = proc(f: float) =
            fadeNode.alpha = startOpacity + f * (1 - startOpacity)
        fadeNode.addAnimation(fadeNodeAnimation)

    bttnUpNode.enabled = false
    dropUpBttn.enabled = false
    dropUpBttn.onAction do():
        currentNotificationCenter().postNotification("MENU_CLICK_BUTTON", newVariant(mbMenuClose))
        bttn.hideBttns()
        sharedAnalytics().menubutton_inout("hide", bttn.rootNode.sceneView.name)

        dropUpBttn.enabled = false
        fadeNodeBttn.enabled = false
        bttnUpNode.sceneView.GameScene.setTimeout(dropUpBttnAnim.loopDuration) do():
            bttnUpNode.enabled = false
            bttnDownNode.enabled = true

        if not fadeNodeAnimation.isNil:
            fadeNodeAnimation.cancel()
        fadeNodeAnimation = newAnimation()
        fadeNodeAnimation.loopDuration = SHOW_HIDE_DURATION
        fadeNodeAnimation.numberOfLoops = 1
        fadeNodeAnimation.onComplete do():
            fadeNodeAnimation = nil
            dropDownBttn.enabled = true
        let startOpacity = fadeNode.alpha
        fadeNodeAnimation.onAnimate = proc(f: float) =
            fadeNode.alpha = startOpacity * (1 - f)
        fadeNode.addAnimation(fadeNodeAnimation)

proc setButtons*(bttn: GMenuButton, buttons: openarray[MenuButton], enabled: bool = false) =
    if bttn.actionButtons.len > 0:
        for button in bttn.actionButtons:
            if not button.animation.isNil:
                button.animation.cancel()
            button.rootNode.removeFromParent()
        bttn.actionButtons.setLen(0)

    let parent = bttn.rootNode
    var top = BUTTON_SIZE.height * 3 / 2
    let left = BUTTON_SIZE.width / 2

    for button in buttons:
        let buttonParent = newNodeWithResource("common/gui/ui2_0/menu_button_item")
        buttonParent.findNode("icon_button_placeholder").component(IconComponent).name = $button
        buttonParent.findNode("button_name").component(Text).text = $button.MenuButtonText
        parent.addChild(buttonParent)
        bttn.actionButtons.add(ActionButton.new(button, buttonParent))

    for i, button in bttn.actionButtons:
        button.bttn.enabled = enabled
        button.rootNode.anchor = button.rootNode.findNode("menu_button_item_button").position
        button.rootNode.position = newVector3(left, top)

        closureScope:
            let b = button
            b.bttn.onAction do():
                bttn.bttnUp.sendAction()
                bttn.rootNode.sceneView.GameScene.notificationCenter.postNotification("MENU_CLICK_BUTTON", newVariant(b.kind))

        top += BUTTON_SIZE.height

template setButtons*(bttn: GMenuButton, buttons: varargs[MenuButton]) =
    bttn.setButtons(buttons, false)

proc setVisible*(bttn: GMenuButton, visible: bool) =
    bttn.rootNode.enabled = visible
