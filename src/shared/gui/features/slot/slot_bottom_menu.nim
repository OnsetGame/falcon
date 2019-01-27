import boolseq, logging
import nimx / [types, animation, matrixes]
import rod / [rod_types, node, viewport]
import rod / component / [solid, text_component]
import shared / window / [button_component, window_manager]
import shared / gui / [gui_module, gui_module_types]
import shared / gui / features / [button_feature, button_exchange, button_gifts, button_wheel_of_fortune, collect_button]
import shared / [localization_manager, game_scene, user, tutorial]
import utils / falcon_analytics
import quest.quests
import core / flow / [flow, flow_state_types]
import core / helpers / boost_multiplier

type ButtonSlotCollect* = ref object of ButtonFeature
    status: int
    fade: Node
    fadeButton: ButtonComponent
    fadeDuration: float
    buttons*: seq[ButtonFeature]
    collect*: CollectButton
    hints: seq[bool]
    chipsOnShow*: int64
    flowState: WindowFlowState
    boostMultiplier*: BoostMultiplier

proc hintsCount*(bf: ButtonSlotCollect): int =
    for i in bf.hints:
        if i:
            result.inc

proc onRemoved*(bf: ButtonSlotCollect) =
    if not bf.boostMultiplier.isNil:
        bf.boostMultiplier.onRemoved()
        bf.boostMultiplier = nil

proc animButton(bf: ButtonSlotCollect, node: Node, loopPattern: LoopPattern, i: int, l: int) =
    node.enabled = true
    let pauseAnim = newAnimation()
    pauseAnim.numberOfLoops = 1
    if loopPattern == lpStartToEnd:
        pauseAnim.loopDuration = bf.fadeDuration * (i / l)
    else:
        pauseAnim.loopDuration = bf.fadeDuration * ((l - i - 1) / l)

    let showAnim = newAnimation()
    showAnim.numberOfLoops = 1
    showAnim.loopDuration = bf.fadeDuration - pauseAnim.loopDuration
    showAnim.loopPattern = loopPattern

    showAnim.onAnimate = proc(p: float) =
        if p < 0.6:
            let k = p / 0.6
            node.scale = newVector3(1.1, 1.1, 1.1) * newVector3(k, k, k)
        else:
            let k = (p - 0.6) / 0.4
            node.scale = newVector3(1.1, 1.1, 1.1) - newVector3(0.1, 0.1, 0.1) * newVector3(k, k, k)

    let anim = newCompositAnimation(false, pauseAnim, showAnim)
    anim.numberOfLoops = 1
    if loopPattern == lpEndToStart:
        anim.onComplete do():
            node.enabled = false
    bf.rootNode.addAnimation(anim)


proc animButtons(bf: ButtonSlotCollect, loopPattern: LoopPattern) =
    let len = bf.buttons.len + 1
    bf.animButton(bf.collect.rootNode, loopPattern, 0, len)
    for i, button in bf.buttons:
        bf.animButton(button.rootNode, loopPattern, i + 1, len)

template showButtons(bf: ButtonSlotCollect) =
    bf.animButtons(lpStartToEnd)

template hideButtons(bf: ButtonSlotCollect) =
    bf.animButtons(lpEndToStart)


proc hide(bf: ButtonSlotCollect)


proc createFade(bf: ButtonSlotCollect) =
    var winSize = VIEWPORT_SIZE
    let pos_x = -winSize.width - 100
    winSize.width *= 3
    let pos_y = -winSize.height - 100
    winSize.height *= 3

    var fadeNode = newNode("fade_node")
    bf.rootNode.insertChild(fadeNode, 0)
    fadeNode.position = newVector3(pos_x, pos_y)
    fadeNode.alpha = 0.0

    let solid = fadeNode.addComponent(Solid)
    solid.size = winSize + newSize(200, 200)
    solid.color = newColor(0.0, 0.0, 0.0, 0.75)

    bf.fade = fadeNode
    bf.fadeButton = fadeNode.createButtonComponent(nil, newRect(0.0, 0.0, solid.size.width, solid.size.height))
    bf.fadeButton.onAction do():
        bf.onAction(bf.enabled)


template showFade(bf: ButtonSlotCollect) =
    if bf.fade.isNil:
        bf.createFade()

    let anim = newAnimation()
    anim.loopDuration = bf.fadeDuration
    anim.numberOfLoops = 1
    anim.onAnimate = proc(p: float) =
        bf.fade.alpha = p
        bf.fadeButton.enabled = true
    bf.rootNode.addAnimation(anim)


template hideFade(bf: ButtonSlotCollect) =
    if bf.fade.isNil:
        return

    let anim = newAnimation()
    anim.loopDuration = bf.fadeDuration
    anim.numberOfLoops = 1
    anim.onAnimate = proc(p: float) =
        bf.fade.alpha = 1.0 - p
        bf.fadeButton.enabled = false
    bf.rootNode.addAnimation(anim)


proc pushAnim(bf: ButtonSlotCollect, loopPattern: LoopPattern, nextStatus: int) =
    bf.status = 0
    let pushAnim = bf.rootNode.animationNamed("push")
    pushAnim.numberOfLoops = 1
    pushAnim.loopPattern = loopPattern

    let pauseAnim = newAnimation()
    pauseAnim.loopDuration = max(bf.fadeDuration, pushAnim.loopDuration) - pushAnim.loopDuration
    pauseAnim.numberOfLoops = 1

    let anim = newCompositAnimation(false, pushAnim, pauseAnim)
    anim.numberOfLoops = 1
    anim.onComplete do():
        bf.status = nextStatus
    bf.rootNode.addAnimation(anim)

method sendAnalEvents(bf: ButtonSlotCollect, isOpen: bool) {.base.} =
    proc getSlotName(): string =
        if not bf.rootNode.isNil and not bf.rootNode.sceneView.isNil:
            result = bf.rootNode.sceneView.name

    let hints = bf.hintsCount()

    let slotState = findActiveState(SlotFlowState).SlotFlowState
    if slotState.isNil:
        printFlowStates()
    if isOpen:
        info "SLOT BOTTOM MENU: slotState.isNil=", slotState.isNil
        info "SLOT BOTTOM MENU: bf.chipsOnShow=", bf.chipsOnShow
        info "SLOT BOTTOM MENU: hints.int64=", hints.int64
        info "SLOT BOTTOM MENU: getSlotName()=", getSlotName()
        info "SLOT BOTTOM MENU: sharedQuestManager().totalStageLevel()=", sharedQuestManager().totalStageLevel()
        info "SLOT BOTTOM MENU: slotState.target=", slotState.target
        info "SLOT BOTTOM MENU: sharedQuestManager().slotStageLevel(slotState.target)=", sharedQuestManager().slotStageLevel(slotState.target)
        sharedAnalytics().collect_slot_open(bf.chipsOnShow, hints.int64, getSlotName(), sharedQuestManager().totalStageLevel(), slotState.target, sharedQuestManager().slotStageLevel(slotState.target))
    else:
        sharedAnalytics().collect_slot_closed(currentUser().chips, currentUser().chips - bf.chipsOnShow, getSlotName(), sharedQuestManager().totalStageLevel(), slotState.target, sharedQuestManager().slotStageLevel(slotState.target))

proc show(bf: ButtonSlotCollect) =
    bf.flowState = newFlowState(WindowFlowState)
    bf.flowState.name = "SlotCollectFlowState"
    bf.flowState.execute()
    bf.pushAnim(lpStartToEnd, 2)
    bf.showFade()
    bf.showButtons()
    bf.chipsOnShow = currentUser().chips

    bf.sendAnalEvents(true)

proc hide(bf: ButtonSlotCollect) =
    bf.flowState.pop()
    bf.pushAnim(lpEndToStart, 1)
    bf.hideFade()
    bf.hideButtons()
    bf.sendAnalEvents(false)

method onInit*(bf: ButtonSlotCollect) =
    bf.composition = "common/gui/ui2_0/collect_in_slot_button"
    bf.rect = newRect(0.0, 0.0, 224.0, 201.0)
    bf.title = localizedString("GUI_COLLECT")
    bf.status = 1
    bf.fadeDuration = 0.5

    bf.onAction = proc(enabled: bool) =
        if enabled:
            bf.playClick()
            case bf.status:
                of 1:
                    bf.show()
                of 2:
                    bf.hide()
                else:
                    discard

proc checkHints*(bf: ButtonSlotCollect) =
    let count = bf.hintsCount()
    if count > 0:
        bf.hint($count)
    else:
        bf.hideHint()


method onCreate(bf: ButtonSlotCollect) =
    bf.buttons = @[
        newButtonWheelOfFortune(bf.rootNode),
        newButtonExchange(bf.rootNode),
        newButtonGifts(bf.rootNode)
    ]
    bf.hints = newSeq[bool](bf.buttons.len + 1)

    bf.collect = newCollectButton(bf.rootNode)
    bf.collect.source = "collect_button"
    bf.collect.rootNode.anchor = newVector3(250.0, 225.0, 0.0)
    bf.collect.rootNode.position = newVector3(262.0, -80.0, 0.0)
    bf.collect.rootNode.scale = newVector3(0.0, 0.0, 0.0)
    bf.collect.onHint = proc(text: string) =
        bf.hints[0] = text.len != 0
        bf.checkHints()
    bf.collect.rootNode.enabled = false
    bf.hints[0] = bf.collect.hinted

    bf.boostMultiplier = bf.collect.rootNode.addIncomeBoostMultiplier(newVector3(405.0, 135, 0), 0.8)
    bf.boostMultiplier.keepSubscribe = true

    if bf.collect.enabled: # Button collect lock status
        #tsSlotBonusButton.addTutorialFlowState() # Temporary disabled.
        discard
    else:
        bf.disable()

    block buttons:
        let adjast = -5.0
        let xoff = 15.0
        let yoff = -220.0 + adjast

        for i, button in bf.buttons:
            let height = 150.0 - adjast * 2
            button.rect = newRect(0.0, 40.0 + adjast, 350.0, height)
            button.source = bf.source

            let centerX = 175.0
            let centerY = 150.0
            let xpos = xoff + centerX
            let ypos = yoff - i.float * height

            button.rootNode.anchor = newVector3(centerX, centerY, 0.0)
            button.rootNode.position = newVector3(xpos, ypos, 0.0)
            button.rootNode.scale = newVector3(0.0, 0.0, 0.0)
            button.rootNode.enabled = false

            let titleNode = button.rootNode.findNode("title")
            titleNode.position = newVector3(175.0, 40.0)
            let titleComp = titleNode.getComponent(Text)
            titleComp.horizontalAlignment = haLeft
            titleComp.verticalAlignment = vaCenter
            titleComp.boundingSize = newSize(175.0, 150.0)

            closureScope:
                let action = button.onAction
                button.onAction = proc(enabled: bool) =
                    action(enabled)
                    if enabled:
                        bf.onAction(bf.enabled)
                let ind = i + 1
                button.onHint = proc(text: string) =
                    bf.hints[ind] = text.len != 0
                    bf.checkHints()
                bf.hints[ind] = button.hinted
    bf.checkHints()

type GSlotBottomMenu* = ref object of GUIModule
    bttn*: ButtonSlotCollect

proc createSlotBottomMenu*(parent: Node): GSlotBottomMenu =
    result = GSlotBottomMenu.new()
    let rootNode = newNode("slot_bottom_menu")
    result.rootNode = rootNode
    result.moduleType = mtSlotBottomMenu
    parent.addChild(result.rootNode)

    result.bttn = ButtonSlotCollect.new(result.rootNode)
    result.bttn.source = "bottomSlotMenu"
    for b in result.bttn.buttons:
        b.source = "slotCollect"
    result.bttn.collect.source = "slotCollect"

    let action = result.bttn.onAction
    result.bttn.onAction = proc(enabled: bool) =
        rootNode.removeFromParent()
        sharedWindowManager().insertNodeBeforeWindows(rootNode)
        action(enabled)

method onRemoved*(gsbm: GSlotBottomMenu)=
    if not gsbm.bttn.isNil:
        gsbm.bttn.onRemoved()
