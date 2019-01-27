import typetraits, tables
import nimx / [ view, types, notification_center, view_event_handling, mini_profiler, class_registry, timer ]
from nimx.assets.abstract_asset_bundle import nil
import nimx.assets.asset_manager

import rod / [ rod_types, viewport, node, asset_bundle ]

import utils / [ pause, sound_manager, helpers, console, falcon_analytics, falcon_analytics_helpers, game_state ]
import shared / [ message_box, user ]
import loading_info
import sequtils
export helpers
import logging
import core / flow / flow

const VIEWPORT_SIZE* = newSize(1920, 1080)


type
    GameSceneAction* = ref object of RootObj
        body: proc(g: GameScene, data: Variant, onComplete: proc(success: bool))
        onComplete: proc(success: bool)

    GameScene* = ref object of SceneView
        pauseManager*: PauseManager
        soundManager*: SoundManager
        savedMusicGain, savedSoundGain: float
        mViewportSize: Size
        mLoadingInfo: LoadingInfo
        notificationCenter*: NotificationCenter
        actions*: Table[string, GameSceneAction]
        flowDebugSpeed*: float32

proc new*(T: typedesc[GameSceneAction], body: proc(g: GameScene, data: Variant, onComplete: proc(success: bool)), onComplete: proc(success: bool) = nil): T =
    result = T.new()
    result.body = body
    result.onComplete = onComplete

template viewportSize*(gs:GameScene): Size =
    gs.mViewportSize

proc setTimeout*(v: GameScene, interval: float, callback: proc(), activeInSoftPause: bool = false): ControlledTimer {.discardable.} =
    if v.isNil or v.pauseManager.isNil:
        callback()
        result = nil
    else:
        result = setTimeout(v.pauseManager, interval, callback, activeInSoftPause)

proc setInterval*(v: GameScene, interval: float, callback: proc(), activeInSoftPause: bool = false): ControlledTimer {.discardable.} =
    if v.pauseManager.isNil:
        callback()
        result = nil
    else:
        result = setInterval(v.pauseManager, interval, callback, activeInSoftPause)

proc clearTimer*(v: GameScene, timer: ControlledTimer) =
    timer.timer.clear()
    v.pauseManager.deleteTimer(timer)

method sceneID*(v: GameScene): string {.base.} = v.name

method acceptsFirstResponder(v: GameScene): bool = true

method onFocusEnter*(gs: GameScene, args: Variant){.base.} =
    info "AW_FOCUS_ENTER"
    if not gs.window.isNil and not gs.pauseManager.isNil:
        if gs.pauseManager.paused:
            gs.pauseManager.resume()
            gs.soundManager.settings.soundGain = gs.savedSoundGain
            gs.soundManager.settings.musicGain = gs.savedMusicGain
            gs.soundManager.resumeMusic()
            gs.soundManager.resumeSounds()

method onFocusLeave*(gs: GameScene, args: Variant){.base.} =
    info "AW_FOCUS_LEAVE"
    if not gs.window.isNil and not gs.pauseManager.isNil:
        if not gs.pauseManager.paused and not gs.soundManager.isNil:
            gs.savedSoundGain = gs.soundManager.settings.soundGain
            gs.savedMusicGain = gs.soundManager.settings.musicGain
            gs.soundManager.settings.soundGain = 0
            gs.soundManager.settings.musicGain = 0
            gs.pauseManager.pause(false)
            gs.soundManager.pauseMusic()
            gs.soundManager.pauseSounds()

method canHandleDeepLinks*(v: GameScene): bool {.base.} =
    return true

proc pause*(v: GameScene, soft: bool = false) =
    if not v.pauseManager.isNil:
        v.pauseManager.pause(soft)
    if not v.soundManager.isNil and not soft:
        v.soundManager.pause()

proc resume*(v: GameScene) =
    if not v.pauseManager.isNil:
        v.pauseManager.resume()
    if not v.soundManager.isNil:
        v.soundManager.resume()

proc invalidate(v: GameScene) =
    if not v.soundManager.isNil:
        v.soundManager.stop()
    if not v.pauseManager.isNil:
        v.pauseManager.invalidate()

    v.notificationCenter = nil
    sharedNotificationCenter().removeObserver(v)

method viewOnEnter*(v: GameScene) =
    if not v.soundManager.isNil:
        v.soundManager.start()

    when defined(android) or defined(ios):
        sharedNotificationCenter().addObserver("AW_FOCUS_LEAVE", v) do(args: Variant):
            v.pause()

        sharedNotificationCenter().addObserver("AW_FOCUS_ENTER", v) do(args: Variant):
            v.resume()

    sharedNotificationCenter().addObserver("resetProgress", v) do(args: Variant):
        showMessageBox("Restart required", "Game progress reseted", MessageBoxType.Error) do():
            currentUser().cheatsEnabled = false
            currentUser().sessionId = ""
            resetAnalytics()
            removeAllStates()
            system.quit()

    discard v.makeFirstResponder()

method viewOnExit*(v: GameScene) =
    v.invalidate()

method initAfterResourcesLoaded*(v:GameScene){.base.} = discard
method assetBundles*(v: GameScene): seq[AssetBundleDescriptor] {.base.} = discard
method loadingInfo*(v:GameScene): LoadingInfo{.base.} = discard

proc centerOrthoCameraPosition*(gs: GameScene) =
    assert(not gs.camera.isNil, "GameSceneBase's camera is nil")
    let cameraNode = gs.camera.node

    cameraNode.positionX = gs.mViewportSize.width / 2
    cameraNode.positionY = gs.mViewportSize.height / 2

proc addDefaultOrthoCamera*(gs: GameScene, cameraName: string) =
    let cameraNode = gs.rootNode.newChild(cameraName)
    let camera = cameraNode.component(Camera)

    camera.projectionMode = cpOrtho
    camera.viewportSize = gs.mViewportSize
    cameraNode.positionZ = 1
    gs.centerOrthoCameraPosition()

proc addDefaultPerspectiveCamera*(gs: GameScene, cameraName: string) =
    let cameraNode = gs.rootNode.newChild(cameraName)
    let camera = cameraNode.component(Camera)
    camera.viewportSize = gs.mViewportSize
    camera.zFar = 8000.0


method initActions*(g: GameScene) {.base.} =
    echo "INIT ACTIONS BASE"
    discard

method init*(v: GameScene, r: Rect) =
    procCall v.SceneView.init(r)
    v.flowDebugSpeed = 20.0
    v.actions = initTable[string, GameSceneAction]()
    v.notificationCenter = newNotificationCenter()
    v.mViewportSize = VIEWPORT_SIZE
    v.rootNode = newNode("root")
    if v.name.len == 0:
        v.name = v.className()
    v.initActions()

method name*(v: GameScene):string =
    result = v.className()


method preloadSceneResources*(gs:GameScene, onComplete: proc() = nil, onProgress: proc(p:float) = nil){.base.} =
    proc afterResourcesPreloaded() =
        gs.initAfterResourcesLoaded()
        if not onComplete.isNil:
            onComplete()

    let abd = gs.assetBundles()
    if abd.len > 0:
        abd.loadAssetBundles() do(mountPaths: openarray[string], abs: openarray[AssetBundle], err: string):
            if err.len == 0:
                let am = sharedAssetManager()
                for i in 0 ..< mountPaths.len:
                    am.mount(mountPaths[i], abs[i])
                var newAbs = newSeq[abstract_asset_bundle.AssetBundle](abs.len)
                for i, ab in abs: newAbs[i] = abs[i]
                am.loadAssetsInBundles(newAbs, onProgress, afterResourcesPreloaded)

            else:
                error "loadAssetBundles for ", gs.name, " error: ", err
                sharedNotificationCenter().postNotification("SHOW_RESOURCE_LOADING_ALERT")
    else:
        afterResourcesPreloaded()

method clearSceneResourcesCache*(gs:GameScene) {.base.} =
    ## Normally should be called after scene view is removed from superview.
    for ab in gs.assetBundles():
        sharedAssetManager().unmount(ab.path)

method resizeSubviews*(gs: GameScene, oldSize: Size) =
    procCall gs.SceneView.resizeSubviews(oldSize)

    if gs.camera.projectionMode == cpOrtho:
        gs.centerOrthoCameraPosition()

proc setFlowSpeed(v: GameScene, speed:float) =
    v.flowDebugSpeed = speed
    var debuger = v.rootNode.findNode("FlowStateDebug")
    if not debuger.isNil:
        let dc = debuger.getComponent(FlowStateRecordComponent)
        if not dc.isNil:
            dc.speed = speed

proc enableFlowStateDebug*(v: GameScene, speed:float)=
    var debuger = v.rootNode.findNode("FlowStateDebug")
    if debuger.isNil:
        debuger = v.rootNode.newChild("FlowStateDebug")
    let dc = debuger.component(FlowStateRecordComponent)
    dc.textSize = 20
    dc.speed = speed
    if v.name == "TiledMapView": dc.textSize = 64

proc disableFlowStateDebug*(v: GameScene)=
    let node = v.rootNode.findNode("FlowStateDebug")
    if not node.isNil:
        node.removeFromParent()

method onKeyDown*(gs: GameScene, e: var Event): bool =
    when editorEnabled:
        if e.keyCode == VirtualKey.E:
            if not gs.editing:
                discard startEditor(gs)
            result = true
        
        elif e.keyCode == VirtualKey.L:
            if not gs.pauseManager.isNil:
                if gs.pauseManager.paused:
                    gs.pauseManager.resume()
                else:
                    gs.pauseManager.pause()
            result = true
            
    case e.keyCode
    of VirtualKey.P:
        let p = sharedProfiler()
        p.enabled = not p.enabled
        result = true

    of VirtualKey.NonUSBackSlash, VirtualKey.Backtick:
        result = true
        when not defined(emscripten):
            showConsole(gs.superview)

    of VirtualKey.Q:
        info "Toggle flow debuging"
        let dn = gs.rootNode.findNode("FlowStateDebug")
        if dn.isNil:
            gs.enableFlowStateDebug(gs.flowDebugSpeed)
        else:
            gs.disableFlowStateDebug()
        result = true

    of VirtualKey.KeypadPlus:
        gs.setFlowSpeed(gs.flowDebugSpeed + 10.0)

    of VirtualKey.KeypadMinus:
        gs.setFlowSpeed(gs.flowDebugSpeed - 10.0)

    else:   
        discard

method createDeepLink*(gs: GameScene): seq[tuple[id: string, route: string]] {.base.} =
    result = @{"scene": gs.name}

method didBecomeCurrentScene*(gs: GameScene) {.base.} = discard

proc prepareForCriticalError*(v: GameScene) =
    ## Stop all animations, timers, sounds. The scene will still be able to
    ## display the critical error alert, but is not intended to return back
    ## to valid state.
    v.invalidate()


template registerAction*[T](g: GameScene, action: T) =
    echo "REGISTER: ", action.type.name
    g.actions[action.type.name] = action


proc dispatchAction*(g: GameScene, T: typedesc[GameSceneAction], data: Variant, onComplete: proc(success: bool) = nil) =
    let action = g.actions.getOrDefault(T.name)
    if not action.isNil:
        action.body(g, data) do(success: bool):
            if not action.onComplete.isNil:
                action.onComplete(success)
            if not onComplete.isNil:
                onComplete(success)

template dispatchAction*(g: GameScene, T: typedesc[GameSceneAction], onComplete: proc(success: bool) = nil) =
    g.dispatchAction(T, newVariant(), onComplete)

template dispatchAction*(n: Node, T: typedesc[GameSceneAction], data: Variant, onComplete: proc(success: bool) = nil) =
    n.sceneView.GameScene.dispatchAction(T, data, onComplete)

template dispatchAction*(n: Node, T: typedesc[GameSceneAction], onComplete: proc(success: bool) = nil) =
    n.dispatchAction(T, newVariant(), onComplete)
