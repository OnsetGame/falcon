import json, strutils, logging, tables, typetraits

import nimx.types
import nimx.timer
import nimx.animation
import core / notification_center
import nimx.button
import nimx.matrixes
import nimx.event

import rod.rod_types
import rod.node
import rod.viewport
import rod.component
import rod.component.ui_component
import rod.component.solid
import rod.component.sprite
import rod.component.ae_composition

import shared.window.window_component
import shared / [ director, game_scene, deep_links]
import utils.falcon_analytics_helpers
import utils.sound_manager
import utils.helpers
import core / flow / flow_state_types
import falconserver.tutorial.tutorial_types

type WindowManager* = ref object
    windowNode: Node
    windowsAnchor: Node
    alertsAnchor: Node
    narrativeAnchor: Node

    mCurrentWindow: WindowComponent
    currentAlert: WindowComponent
    fadeNode: Node
    closeBttn: Button

    nextWindowAction: proc()
    nextAlertAction: proc()

    soundManager*: SoundManager
    badConnectionNode: Node

    onSceneAddedWithDeepLink*: proc()

var gWindowManager: WindowManager


proc createButton(parent: Node, rect: Rect): Button=
    result = new(Button, rect)
    result.init(rect)
    parent.component(UIComponent).view = result
    result.hasBezel = false

proc hide*(wm: WindowManager, window: WindowComponent)
proc `currentWindow=`*(wm: WindowManager, window: WindowComponent) =
    wm.mCurrentWindow = window

proc showBadConnection*(wm: WindowManager)
proc hideBadConnection*(wm: WindowManager)

proc currentWindow*(wm: WindowManager): WindowComponent =
    result = wm.mCurrentWindow

proc topWindow(wm: WindowManager): WindowComponent =
    if not wm.currentAlert.isNil :
        result = wm.currentAlert
    elif not wm.currentWindow.isNil:
        result = wm.currentWindow

proc checkWindowNode(wm: WindowManager): bool =
    result = true
    if currentDirector().currentScene.isNil or currentDirector().currentScene.rootNode.isNil:
        return false

    let winNode = currentDirector().currentScene.rootNode.findNode("WindowsNodeRoot")
    if winNode.isNil:
        wm.mCurrentWindow = nil
        wm.currentAlert = nil

        wm.windowNode = newNode("WindowsNodeRoot")
        wm.windowsAnchor    = wm.windowNode.newChild("windowsAnchor")
        wm.narrativeAnchor  = wm.windowNode.newChild("narrativeAnchor")
        wm.alertsAnchor     = wm.windowNode.newChild("alertsAnchor")
        discard wm.windowNode.newChild("rewardsFlyParent")

        var gui = currentDirector().currentScene.rootNode.findNode("GUI")
        if gui.isNil:
            gui = currentDirector().currentScene.rootNode.findNode("gui_parent")
        if gui.isNil:
            warn "WindowsNode attached on root"
            gui = currentDirector().currentScene.rootNode

        gui.addChild(wm.windowNode)

        var winSize = VIEWPORT_SIZE
        let pos_x = -(winSize.width * 1.5 - winSize.width) / 2.0
        winSize.width *= 1.5
        winSize.height *= 1.5
        wm.fadeNode = newNode("fade_node")
        wm.fadeNode.positionX = pos_x
        wm.fadeNode.alpha = 0.0
        wm.windowNode.insertChild(wm.fadeNode, 0)
        wm.closeBttn = wm.fadeNode.createButton(newRect(0, 0, winSize.width, winSize.height))
        wm.fadeNode.getComponent(UIComponent).enabled = false
        let sceneView = wm.windowNode.sceneView

        wm.closeBttn.onAction do(e: Event):
            let topWin = wm.topWindow
            if not topWin.isNil and not topWin.isBusy:
                if topWin.isTapAnywhere:
                    topWin.missClick()
                else:
                    let castedNode = sceneView.rayCastFirstNode(wm.windowNode, e.position)
                    if castedNode.isNil or castedNode.name == "fade_node":
                        if topWin.canMissClick: topWin.missClick()

        let solid = wm.fadeNode.addComponent(Solid)
        solid.size = winSize
        solid.color = newColor(0.0, 0.0, 0.0, 0.75)

proc windowsRoot*(wm: WindowManager): Node =
    discard wm.checkWindowNode()
    result = wm.windowNode

proc getNarrativeAnchor*(wm: WindowManager): Node =
    discard wm.checkWindowNode()
    result = wm.narrativeAnchor

proc insertNodeBeforeWindows*(wm: WindowManager, n: Node) =
    let nodes = wm.windowsRoot.parent.children
    var i = nodes.high
    while i > -1 and nodes[i] != wm.windowNode:
        i.dec
    if i > -1:
        wm.windowNode.parent.insertChild(n, i)

proc scaleRatioForWindowSize(wm: WindowManager): float=
    let r = gWindowManager.windowsRoot()
    if not r.isNil:
        let sc = r.sceneView
        if not sc.isNil:
            const defRatio = VIEWPORT_SIZE.width/VIEWPORT_SIZE.height
            let curRatio = sc.bounds.width / sc.bounds.height
            result = curRatio / defRatio

proc downScaleWindowComponent(wm: WindowManager, scale: float)=
    let scaleV = newVector3(scale, scale, 1.0)

    if not wm.currentAlert.isNil:
        wm.currentAlert.node.scale = scaleV

    if not wm.currentWindow.isNil:
        wm.currentWindow.node.scale = scaleV

proc upscaleWindowComponent(wm: WindowManager, scale: float)=
    let defScale = newVector3(1.0, 1.0, 1.0)
    var spriteComps = newSeq[Sprite]()
    var solidComps = newSeq[Solid]()

    if not wm.currentAlert.isNil:
        wm.currentAlert.node.scale = defScale
        componentsInNode[Sprite](wm.currentAlert.node, spriteComps)
        componentsInNode[Solid](wm.currentAlert.node, solidComps)

    if not wm.currentWindow.isNil:
        wm.currentWindow.node.scale = defScale
        componentsInNode[Sprite](wm.currentWindow.node, spriteComps)
        componentsInNode[Solid](wm.currentWindow.node, solidComps)

    if wm.fadeNode.children.len == 0:
        wm.fadeNode.scale = newVector3(scale * 1.2, scale * 1.2, 1.0)
        wm.fadeNode.positionX = (VIEWPORT_SIZE.width - VIEWPORT_SIZE.width * scale) * 0.5 - 100.0

    for sol in solidComps:
        if sol.size.width >= VIEWPORT_SIZE.width:
            if sol.node.children.len == 0:
                sol.size.width = VIEWPORT_SIZE.width * scale * 2.0
                sol.node.positionX = (VIEWPORT_SIZE.width - sol.size.width) * 0.5

    for sp in spriteComps:
        if abs(sp.node.scale.x) > 10.0:
            let sw = sp.effectiveSize().width
            let tw = sw * abs(sp.node.scale.x)
            if tw >= VIEWPORT_SIZE.width - 10.0:
                sp.node.scale.x = (VIEWPORT_SIZE.width * scale) / sw + 5.0

proc activeWindowLayersCount*(wm: WindowManager): int =
    result = int(not wm.currentAlert.isNil and not wm.currentAlert.processClose) +
        int(not wm.currentWindow.isNil and not wm.currentWindow.processClose)

proc updateWindowComponentScale(wm: WindowManager)=
    let scale = wm.scaleRatioForWindowSize()
    if abs(scale - 0.01) > 0.0:
        if scale < 1.0:
            wm.downScaleWindowComponent(scale)
        else:
            wm.upscaleWindowComponent(scale)

proc sharedWindowManager*(): WindowManager =
    if gWindowManager.isNil:
        gWindowManager = WindowManager.new()
        discard gWindowManager.checkWindowNode()

        if gWindowManager.soundManager.isNil:
            gWindowManager.soundManager = newSoundManager(nil)
            gWindowManager.soundManager.loadEvents("common/sounds/common")


        sharedNotificationCenter().addObserver("DIRECTOR_ON_SCENE_REMOVE", gWindowManager, proc(args: Variant) =
            gWindowManager.windowsRoot().removeFromParent()

            if not gWindowManager.currentWindow.isNil and not gWindowManager.currentWindow.timer.isNil:
                gWindowManager.currentWindow.timer.clear()

            if not gWindowManager.currentAlert.isNil and not gWindowManager.currentAlert.timer.isNil:
                gWindowManager.currentAlert.timer.clear()

            gWindowManager.currentWindow = nil
            gWindowManager.currentAlert = nil

            gWindowManager.windowNode = nil
            gWindowManager.fadeNode = nil
            gWindowManager.closeBttn = nil
            gWindowManager.windowsAnchor = nil
            gWindowManager.alertsAnchor = nil
            gWindowManager.narrativeAnchor = nil

            gWindowManager.nextWindowAction = nil
            gWindowManager.nextAlertAction = nil

            gWindowManager.badConnectionNode = nil
        )

        sharedNotificationCenter().addObserver("GAME_SCENE_RESIZE", gWindowManager) do(args: Variant):
            gWindowManager.updateWindowComponentScale()

        sharedNotificationCenter().addObserver("DIRECTOR_ON_SCENE_ADD", gWindowManager) do(args: Variant):
            currentNotificationCenter().addObserver("WINDOW_COMPONENT_CLOSED", gWindowManager, proc(args: Variant) =
                let window = args.get(WindowComponent)
                window.node.removeFromParent()
                if window == gWindowManager.currentAlert: gWindowManager.currentAlert = nil
                elif window == gWindowManager.currentWindow: gWindowManager.currentWindow = nil

                if not gWindowManager.nextAlertAction.isNil:
                    gWindowManager.nextAlertAction()
                    gWindowManager.nextAlertAction = nil
                elif not gWindowManager.nextWindowAction.isNil:
                    gWindowManager.nextWindowAction()
                    gWindowManager.nextWindowAction = nil

                if gWindowManager.activeWindowLayersCount() == 0:
                    gWindowManager.fadeNode.getComponent(UIComponent).enabled = false

                )

            currentNotificationCenter().addObserver("WINDOW_COMPONENT_TO_CLOSE", gWindowManager, proc(args: Variant) =
                let window = args.get(WindowComponent)
                gWindowManager.hide(window)
                )

            currentNotificationCenter().addObserver("WINDOW_COMPONENT_PLAY_SOUND", gWindowManager, proc(args: Variant) =
                let ev = args.get(string)
                gWindowManager.soundManager.sendEvent(ev)
                )

            if args.get(GameScene).canHandleDeepLinks():
                if not gWindowManager.onSceneAddedWithDeepLink.isNil:
                    gWindowManager.onSceneAddedWithDeepLink()

    result = gWindowManager

proc playSound*(wm: WindowManager, evName: string) =
    wm.soundManager.sendEvent(evName)

proc hasVisibleWindows*(wm: WindowManager): bool = wm.activeWindowLayersCount > 0

proc hide*(wm: WindowManager, window: WindowComponent) =
    if window.processClose:
        return

    # we need only one active window to hide fade
    if wm.activeWindowLayersCount() == 1:
        let cb = proc () =
            discard
            # wm.fadeNode.getComponent(UIComponent).enabled = false

        if not wm.fadeNode.isNil:
            wm.fadeNode.hide(TIME_TO_SHOW_WINDOW, cb)

    elif not wm.currentWindow.isNil:
        wm.windowNode.insertChild(wm.fadeNode, 0)

    window.hide()

    info "[WindowManager] hideWindow ", window.className()

proc hideAll*(wm: WindowManager) =
    if not wm.currentAlert.isNil:
        wm.hide(wm.currentAlert)
        wm.nextAlertAction = proc() = wm.hideAll()
        wm.nextWindowAction = nil
    elif not wm.currentWindow.isNil:
        wm.hide(wm.currentWindow)

proc createWindow(wm: WindowManager, winName: string): WindowComponent =
    let rootNode = newNode(winName)
    rootNode.positionX = VIEWPORT_SIZE.width / 2
    rootNode.positionY = VIEWPORT_SIZE.height / 2

    result = rootNode.addComponent(winName).WindowComponent
    result.startPos = rootNode.position
    result.destPos = rootNode.position

proc createWindow*(wm: WindowManager, T: typedesc): T =
    type TT = T
    result = wm.createWindow(T.name).TT

proc showWindow(wm: WindowManager, window: WindowComponent) =
    wm.fadeNode.show(TIME_TO_SHOW_WINDOW) do():
        wm.fadeNode.getComponent(UIComponent).enabled = true

    wm.fadeNode.getComponent(UIComponent).enabled = true
    wm.currentWindow = window
    window.show()

    wm.updateWindowComponentScale()

proc checkAlertsAndShow(wm: WindowManager, win: WindowComponent) =
    # echo "show"
    # echo "wm.currentAlert.isNil ", wm.currentAlert.isNil
    # echo "wm.currentWindow.isNil ", wm.currentWindow.isNil
    wm.windowsAnchor.insertChild(wm.fadeNode, 0)

    if not wm.currentAlert.isNil:
        wm.hide(wm.currentAlert)
        wm.nextAlertAction = proc() =
            wm.checkAlertsAndShow(win)

    elif not wm.currentWindow.isNil:
        wm.hide(wm.currentWindow)
        wm.nextWindowAction = proc() =
            wm.showWindow(win)

    else:
        wm.showWindow(win)

proc show*(wm: WindowManager, win: WindowComponent) =
    if wm.checkWindowNode():
        wm.windowsAnchor.addChild(win.node)
        wm.checkAlertsAndShow(win)

proc show*(wm: WindowManager, winName: string): WindowComponent =
    if wm.checkWindowNode():
        result = wm.createWindow(winName)
        wm.windowsAnchor.addChild(result.node)
        wm.checkAlertsAndShow(result)

proc show*(wm: WindowManager, T: typedesc): T =
    type TT = T
    info "[WindowManager] showWindow ", T.name
    result = wm.show(T.name).TT

proc showFromPos*(wm: WindowManager, T: typedesc, pos: Vector3): T =
    result = wm.createWindow(T)
    result.startPos = pos
    wm.windowsAnchor.addChild(result.node)
    wm.checkAlertsAndShow(result)


# ======== Alerts ========

proc showAlertWindow(wm: WindowManager, window: WindowComponent) =
    wm.fadeNode.show(TIME_TO_SHOW_WINDOW)
    wm.fadeNode.getComponent(UIComponent).enabled = true

    wm.currentAlert = window
    window.show()
    wm.updateWindowComponentScale()

proc showAlert*(wm: WindowManager, T: typedesc): T =
    if wm.checkWindowNode():
        wm.alertsAnchor.addChild(wm.fadeNode)
        var win = wm.createWindow(T)
        wm.alertsAnchor.addChild(win.node)

        info "[WindowManager] showAlert ", win.className()
        if wm.currentAlert.isNil:
            wm.showAlertWindow(win)
        else:
            wm.hide(wm.currentAlert)
            wm.nextAlertAction = proc() =
                wm.showAlertWindow(win)

        result = win


proc showBadConnection*(wm: WindowManager) =
    if wm.checkWindowNode() and wm.badConnectionNode.isNil:
        info "[WindowManager] showBadConnection "
        wm.badConnectionNode = newNodeWithResource("common/gui/precomps/connnection_problems")
        wm.windowNode.addChild(wm.badConnectionNode)
        discard wm.badConnectionNode.createButton(newRect(-1000, -1000, 3000, 3000))

        let fade = newNode("badConnectionFade")
        let solid = fade.addComponent(Solid)
        solid.size = newSize(3000, 3000)
        solid.color = newColor(0.0, 0.0, 0.0, 0.5)
        wm.badConnectionNode.insertChild(fade, 0)

        wm.badConnectionNode.show(0.2) do():
            let anim = wm.badConnectionNode.getComponent(AEComposition).play("idle")
            anim.numberOfLoops = -1

proc hideBadConnection*(wm: WindowManager) =
    if not wm.badConnectionNode.isNil:
        info "[WindowManager] hideBadConnection "
        wm.badConnectionNode.removeFromParent()
        wm.badConnectionNode = nil

sharedDeepLinkRouter().registerHandler(
    "window"
    , onHandle = proc(route: string, next: proc()) =
        let wm = sharedWindowManager()
        if not wm.checkWindowNode():
            wm.onSceneAddedWithDeepLink = proc() =
                wm.onSceneAddedWithDeepLink = nil
                discard wm.show(route)
                next()
        else:
            discard wm.show(route)
            next()
    , shouldBeQueued = proc(route: var string) =
        if not (isClassRegistered(route)):
            error "`" & route & "`" & " has not been found in class registry"
            route = ""
)
