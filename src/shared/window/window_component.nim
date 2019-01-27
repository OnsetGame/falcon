import json
import typetraits
import macros
import logging

import nimx.types
import nimx.context
import nimx.property_visitor
import nimx.timer
import nimx.animation
import core / notification_center
import nimx.view
import nimx.button
import nimx.event
import nimx.view_event_handling

import rod.rod_types
import rod.node
import rod.tools.serializer
import rod.component
import rod.component.text_component
import rod.component.ui_component
import rod.viewport

import utils.helpers
import shared.game_scene
import shared.window.button_component
import utils.falcon_analytics_helpers
import utils.sound_manager

import core / flow / flow_state_types


type WindowComponent* = ref object of Component
    onClose*: proc()
    anchorNode*: Node
    isInitialized*: bool
    hasFade*: bool
    processClose*: bool
    isBusy*: bool
    isTapAnywhere*: bool
    canMissClick*: bool
    startPos*: Vector3
    destPos*: Vector3
    timer*: Timer
    setMoneyPanelOnTop: bool
    mpBtnBucksState : bool
    mpBtnChipsState : bool

    lockTouchesNode*: Node
    lockTouchesView*: ButtonComponent
    curr_state: WindowFlowState

const TIME_TO_SHOW_WINDOW* = 0.3

method onInit*(w: WindowComponent) {.base.} = discard
method initWindowComponent*(w: WindowComponent) {.base.} = w.onInit()
method setup*(w: WindowComponent, cb: proc()) {.base.} = cb()


#TODO: This is workaround for money panel on top logic.
#       Move this to money_panel_module after game_scene gui_pack will be accessible from game_scene instance...
proc removeMoneyPanelFromTop*(wc: WindowComponent) =
    wc.setMoneyPanelOnTop = false
    if not wc.anchorNode.isNil and not wc.anchorNode.sceneView.isNil:
        let mp = wc.anchorNode.sceneView.rootNode.findNode("money_panel")

        let guiNode = mp.parent
        guiNode.insertChild(mp, 0)
        let addChipsBttn = mp.findNode("chips_add")
        let addBucksBttn = mp.findNode("bucks_add")
        addChipsBttn.getComponent(UIComponent).enabled = wc.mpBtnChipsState
        addBucksBttn.getComponent(UIComponent).enabled = wc.mpBtnBucksState

#TODO: This is workaround for money panel on top logic.
#       Move this to money_panel_module after scene gui_pack will be accessible from scene instance...
proc putMoneyPanelOnTop*(wc: WindowComponent) =
    let mp = wc.anchorNode.sceneView.rootNode.findNode("money_panel")
    let guiNode = mp.parent
    guiNode.addChild(mp)

    let addChipsBttn = mp.findNode("chips_add")
    let addBucksBttn = mp.findNode("bucks_add")
    wc.mpBtnBucksState = addBucksBttn.getComponent(UIComponent).enabled
    wc.mpBtnChipsState = addChipsBttn.getComponent(UIComponent).enabled
    addChipsBttn.getComponent(UIComponent).enabled = false
    addBucksBttn.getComponent(UIComponent).enabled = false


proc createLockTouchesView*(w: WindowComponent, rect: Rect) =
    w.lockTouchesNode = newNode("lock_touches_node")
    w.lockTouchesNode.positionX = - rect.width/2.0
    w.lockTouchesNode.positionY = - rect.height/2.0
    w.anchorNode.parent.insertChild(w.lockTouchesNode, 0)
    w.lockTouchesView = w.lockTouchesNode.createButtonComponent(rect)

method componentNodeWasAddedToSceneView*(w: WindowComponent) =
    if w.isInitialized:
        return

    let winSize = VIEWPORT_SIZE
    w.anchorNode = newNode("WindowAnchor")
    w.anchorNode.positionX = -winSize.width / 2
    w.anchorNode.positionY = -winSize.height / 2
    w.node.addChild(w.anchorNode)

    w.node.alpha = 0.0
    w.isInitialized = true
    w.hasFade = true
    w.canMissClick = true

    w.initWindowComponent()
    # if w.isTapAnywhere == false and w.lockTouchesNode.isNil:
    #     let box = w.anchorNode.nodeBounds()
    #     let x = box.minPoint.x
    #     let y = box.minPoint.y
    #     let width = box.minPoint.x + box.maxPoint.x
    #     let height = box.minPoint.y + box.maxPoint.y
    #     w.createLockTouchesView(newRect(x, y, width, height))

method beforeRemove*(w: WindowComponent) {.base.} =
    if w.setMoneyPanelOnTop:
        w.removeMoneyPanelFromTop()

method onMissClick*(w: WindowComponent) {.base.} = discard

proc onClosed*(w: WindowComponent) =
    if not w.onClose.isNil:
        w.onClose()
    w.beforeRemove()
    currentNotificationCenter().postNotification("WINDOW_COMPONENT_CLOSED", newVariant(w))
    w.curr_state.pop()
    w.curr_state = nil

method close*(w: WindowComponent) {.base.} =
    currentNotificationCenter().postNotification("WINDOW_COMPONENT_TO_CLOSE", newVariant(w))

proc closeButtonClick*(w: WindowComponent) =
    setClosedByButtonAnalytics(true)
    w.close()

method missClick*(w: WindowComponent) {.base.} =
    w.onMissClick()
    setClosedByButtonAnalytics(true)
    w.close()

method onShowed*(w: WindowComponent) {.base.} =
    w.isBusy = false

method showStrategy*(w: WindowComponent) {.base.} =
    w.node.alpha = 0.0
    w.node.scale = newVector3(0.0)
    w.node.show(TIME_TO_SHOW_WINDOW)
    w.node.scaleTo(newVector3(1.0, 1.0, 1.0), TIME_TO_SHOW_WINDOW)
    w.node.moveTo(w.startPos, w.destPos, TIME_TO_SHOW_WINDOW)

method show*(w: WindowComponent) {.base.} =
    if w.curr_state.isNil:
        w.curr_state = WindowFlowState.new()
        w.curr_state.name = w.className()
        execute(w.curr_state)

    let nc = currentNotificationCenter()
    if not nc.isNil: nc.postNotification("WINDOW_COMPONENT_TO_SHOW", newVariant(w))

    setCurrWindowAnalytics(w.className())
    w.showStrategy()
    w.isBusy = true
    w.timer = setTimeOut(TIME_TO_SHOW_WINDOW) do():
        if not w.processClose:
            w.onShowed()

    if w.setMoneyPanelOnTop:
        w.putMoneyPanelOnTop()

    if not nc.isNil: nc.postNotification("WINDOW_COMPONENT_PLAY_SOUND", newVariant("COMMON_POPUP_SHOW"))

method hideStrategy*(w: WindowComponent): float {.base.} =
    w.node.hide(TIME_TO_SHOW_WINDOW)
    w.node.scaleTo(newVector3(0.0, 0.0, 0.0), TIME_TO_SHOW_WINDOW)
    return TIME_TO_SHOW_WINDOW

proc hide*(w: WindowComponent)  =
    if w.processClose:
        return
    w.processClose = true
    let hideTime = w.hideStrategy()
    w.timer = setTimeOut(hideTime, proc() = w.onClosed())

    currentNotificationCenter().postNotification("WINDOW_COMPONENT_PLAY_SOUND", newVariant("COMMON_POPUP_HIDE"))


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

proc setPopupTitle*(w: WindowComponent, title: string)=
    w.anchorNode.findNode("popup_title").setPopupTitle(title)

proc mapFreeze*(w: WindowComponent, state:bool) =
    let rtiNode = w.anchorNode.sceneView.rootNode.findNode("map_parent")
    if not rtiNode.isNil:
        RTIfreezeEffect(rtiNode,state)

proc moneyPanelOnTop*(w: WindowComponent):bool =
    w.setMoneyPanelOnTop

proc `moneyPanelOnTop=`*(w: WindowComponent, state: bool) =
    w.setMoneyPanelOnTop = state

registerComponent(WindowComponent, "windows")

import rod.asset_bundle
from nimx.assets.abstract_asset_bundle import nil
import nimx.assets.asset_manager

type AsyncWindowComponent* = ref object of WindowComponent
    onWindowReady: proc()
    ready: bool

method assetBundles*(w: AsyncWindowComponent): seq[AssetBundleDescriptor] {.base.} = nil
method initWindowComponent*(w: AsyncWindowComponent) =
    let am = sharedAssetManager()
    let abd = w.assetBundles()

    if abd.len > 0:
        abd.loadAssetBundles() do(mountPaths: openarray[string], abs: openarray[AssetBundle], err: string):
            if err.len == 0:
                for i in 0 ..< mountPaths.len:
                    am.mount(mountPaths[i], abs[i])
                var newAbs = newSeq[abstract_asset_bundle.AssetBundle](abs.len)
                for i, ab in abs: newAbs[i] = abs[i]
                am.loadAssetsInBundles(newAbs, nil) do():
                    if not w.processClose:
                        w.ready = true
                        w.onInit()
                        if not w.onWindowReady.isNil:
                            w.onWindowReady()
                            w.onWindowReady = nil

            else:
                error "loadAssetBundles for ", w.node.name, " error: ", err
                sharedNotificationCenter().postNotification("SHOW_RESOURCE_LOADING_ALERT")
    else:
        w.ready = true
        w.onInit()
        if not w.onWindowReady.isNil:
            w.onWindowReady()
            w.onWindowReady = nil

proc `onReady=`*(w: AsyncWindowComponent, cb: proc()) =
    if w.ready:
        cb()
        return

    if w.onWindowReady.isNil:
        w.onWindowReady = cb
        return

    let onWindowReady = w.onWindowReady
    w.onWindowReady = proc() =
        onWindowReady()
        cb()

method setup*(w: AsyncWindowComponent, cb: proc()) =
    w.onReady = cb

method show*(w: AsyncWindowComponent) =
    w.node.sceneView.cancelAllTouches()
    if w.ready:
        procCall w.WindowComponent.show()
        return

    w.curr_state = WindowFlowState.new()
    w.curr_state.name = w.className()
    execute(w.curr_state)

    let canMissClick = w.canMissClick
    w.canMissClick = false
    w.node.alpha = 1.0
    let spinner = newNodeWithResource("common/lib/precomps/loading.json")
    w.node.addChild(spinner)
    let spinAnim = spinner.animationNamed("spin")
    spinAnim.numberOfLoops = -1
    w.node.addAnimation(spinAnim)

    w.onReady = proc() =
        spinAnim.cancel()
        spinner.removeFromParent()
        w.node.alpha = 0.0
        w.canMissClick = canMissClick
        procCall w.WindowComponent.show()

registerComponent(AsyncWindowComponent, "windows")
