import logging, tables

import nimx / [timer, window, class_registry, assets/asset_manager]
from nimx.assets.abstract_asset_bundle import nil

import shared / [ loading_scene, game_scene, loading_info, localization_manager,
                  scene_transition, deep_links ]
import utils / analytics
import rod / [component, node, asset_bundle]
import core / notification_center
import core.net.server
import core / flow / flow_state_types

type
    Director* = ref object
        ## Manages game scenes
        window:                   Window
        currentScene*:            GameScene
        sceneToLoad:              GameScene
        startSceneName:           string
        onSceneAddedWithDeepLink: proc()
        currState: LoadingFlowState

var
    globalDirector: Director = nil

const transitionTime = 0.5

proc newDirector*(w: Window = nil): Director =
    ## Constructs new director
    result.new()
    result.window = w
    info "[Director] Initialized"

proc attachToWindow*(d: Director, w: Window) =
    ## Attach scene director to window
    d.window = w
    info "[Director] Attached to window"

proc currentDirector*(): Director =
    ## Get director for window
    if globalDirector.isNil():
        globalDirector = newDirector()
    return globalDirector

proc gameScene*(d: Director): GameScene =
    result = d.currentScene

proc removeCurrentScene*(d: Director) =
    if not d.currentScene.isNil:
        sharedNotificationCenter().postNotification("DIRECTOR_ON_SCENE_REMOVE", newVariant(d.currentScene))
        setCurrentNotificationCenter(nil)
        d.currentScene.rootNode.removeAllChildren()
        d.currentScene.removeFromSuperview()
        d.currentScene.clearSceneResourcesCache()
        d.currentScene = nil
        d.sceneToLoad = nil
        requestGCFullCollect()

proc showNextScene(d: Director, newScene: GameScene) =
    d.window.insertSubview(newScene, 0)
    newScene.setFrame(d.window.bounds)
    newScene.resizeSubviews(d.window.bounds.size) #Hack
    assert(newScene.name.len != 0)
    analyticsEvent("scene_entered_" & newScene.name, nil, false)

proc showLoadingScene(d: Director, nextSceneView: GameScene, animated: bool) =
    var transition: FadeTransition
    proc switchScene =
        if sharedServer().hasActiveRequests:
            setTimeout(0.5) do():
                info " > try to switch scene from ", d.currentScene.name
                switchScene()
            return

        if not transition.isNil:
            transition.removeFromSuperview()
        d.removeCurrentScene()
        d.currentScene = nextSceneView
        d.sceneToLoad = nil
        d.currentScene.hidden = false
        setCurrentNotificationCenter(nextSceneView.notificationCenter)
        d.currentScene.didBecomeCurrentScene()
        sharedNotificationCenter().postNotification("DIRECTOR_ON_SCENE_ADD", newVariant(nextSceneView))
        if not d.currState.isNil:
            d.currState.pop()
            d.currState = nil

    if animated:
        transition = d.window.newFadeTransition(d.currentScene, nextSceneView, transitionTime)
        d.showNextScene(nextSceneView)
        transition.onTransitionDone = proc() =
            # d.window.addSubview(nextSceneView)
            switchScene()
    else:
        d.showNextScene(nextSceneView)
        switchScene()


proc showNextScene(d: Director, nextSceneView: GameScene, animated: bool) =
    var transition: FadeTransition
    proc switchScene =
        if sharedServer().hasActiveRequests:
            setTimeout(0.5) do():
                info " > try to switch scene to ", nextSceneView.name
                switchScene()
            return

        var transitionDone = proc() =
            if not transition.isNil:
                transition.removeFromSuperview()
            # Clean flow state before scene will be loaded
            closeAllActiveStates()
            d.removeCurrentScene()
            d.currentScene = nextSceneView
            d.sceneToLoad = nil
            d.currentScene.hidden = false
            setCurrentNotificationCenter(nextSceneView.notificationCenter)
            d.currentScene.didBecomeCurrentScene()
            sharedNotificationCenter().postNotification("DIRECTOR_ON_SCENE_ADD", newVariant(nextSceneView))
            if not d.currState.isNil:
                d.currState.pop()
                d.currState = nil

            if nextSceneView.canHandleDeepLinks():
                sharedDeepLinkRouter().saveDeepLink(nextSceneView.createDeepLink())

                if not d.onSceneAddedWithDeepLink.isNil:
                    d.onSceneAddedWithDeepLink()

        if animated:
            transition = d.window.newFadeTransition(d.currentScene, nextSceneView, transitionTime)
            d.showNextScene(nextSceneView)
            transition.onTransitionDone = transitionDone
        else:
            d.showNextScene(nextSceneView)
            transitionDone()

    switchScene()

proc moveToScene*(d: Director, gameScene: GameScene, animated: bool = true) =
    ## Main logic for switching game scenes.
    if d.currentScene == gameScene or d.sceneToLoad == gameScene: return
    var loadingScene: LoadingScene
    d.sceneToLoad = gameScene

    info "[Director] moveToScene: ", gameScene.name
    sharedLocalizationManager().currStringsName = gameScene.name

    proc onSceneResoucesLoaded() =
        d.showNextScene(gameScene, animated)

    proc loadingProgress(p:float) =
        ## Setting up loading progress callback for loading screen.
        loadingScene.progress(p)

    proc onLoadingSceneResourcesLoaded() =
        d.showLoadingScene(loadingScene, animated)
        gameScene.setFrame(d.window.bounds)
        setTimeout(transitionTime + 0.3) do(): # Small delay for letting loading screen being displayed before start of resource loading.
            gameScene.preloadSceneResources(onSceneResoucesLoaded, loadingProgress)

    var li = gameScene.loadingInfo()
    if li.isNil:
        ## No loading scene required.
        gameScene.setFrame(d.window.bounds)
        gameScene.preloadSceneResources(onSceneResoucesLoaded)
    else:
        loadingScene = newLoadingScene(li)
        loadingScene.init(d.window.bounds)
        loadingScene.autoresizingMask = { afFlexibleWidth, afFlexibleHeight }
        loadingScene.preloadSceneResources(onLoadingSceneResourcesLoaded)

proc moveToScene*(d: Director, sceneName: string, animated: bool = true): GameScene {.discardable.} =
    ## Main logic for switching game scenes.
    # if not d.currentScene.isNil and d.currentScene.name == sceneName: return d.currentScene

    closeAllActiveStates()
    d.currState = newFlowState(LoadingFlowState)
    pushFront(d.currState)
    let objFromName = newObjectOfClass(sceneName)
    assert(objFromName of GameScene, "[Director] moveToScene: scene is not derrived from GameScene: " & sceneName)
    let gameScene = objFromName.GameScene
    gameScene.init(d.window.bounds)
    gameScene.autoresizingMask = { afFlexibleWidth, afFlexibleHeight }
    d.moveToScene(gameScene, animated)
    result = gameScene

proc preloadCommonResources*(d: Director, cb: proc()) =
    const COMMON_RESOURCES = [
        assetBundleDescriptor("common")
    ]

    COMMON_RESOURCES.loadAssetBundles() do(mountPaths: openarray[string], abs: openarray[AssetBundle], err: string):
        if err.len == 0:
            let am = sharedAssetManager()
            for i in 0 ..< mountPaths.len:
                am.mount(mountPaths[i], abs[i])
            var newAbs = newSeq[abstract_asset_bundle.AssetBundle](abs.len)
            for i, ab in abs: newAbs[i] = abs[i]
            am.loadAssetsInBundles(newAbs, nil) do():
                info "[Director] Common resources loaded"
                if not cb.isNil:
                    cb()
        else:
            error "loadAssetBundles for COMMON_RESOURCES error: ", err
            sharedNotificationCenter().postNotification("SHOW_RESOURCE_LOADING_ALERT")

proc mapSceneName(): string {.inline.} =
    result = "TiledMapView"

proc directorMoveToMap*() {.inline.} =
    discard currentDirector().moveToScene(mapSceneName())

proc directorIsCurrentSceneMap*(): bool {.inline.} =
    result = not currentDirector().currentScene.isNil and currentDirector().currentScene.name == mapSceneName()

proc directorFirstSceneName*(sn: string) =
    currentDirector().startSceneName = sn

proc directorLoadFirstScene*() =
    let dir = currentDirector()
    dir.startSceneName = if dir.startSceneName.len == 0: mapSceneName() else: dir.startSceneName
    dir.moveToScene(dir.startSceneName)

    sharedDeepLinkRouter().registerHandler(
        "scene"
        , onHandle = proc(route: string, next: proc()) =
            dir.moveToScene(route)
            dir.onSceneAddedWithDeepLink = proc() =
                dir.onSceneAddedWithDeepLink = nil
                next()
        , shouldBeQueued = proc(route: var string) =
            if not (isClassRegistered(route)):
                error "`" & route & "`" & " has not been found in class registry"
                route = ""
    )

proc directorFirstSceneDeepLinksListener() =
    sharedDeepLinkRouter().registerHandler(
        "scene"
        , onHandle = proc(route: string, next: proc()) =
            let dir = currentDirector()
            let originalFirstSceneName = dir.startSceneName
            directorFirstSceneName(route)
            dir.onSceneAddedWithDeepLink = proc() =
                dir.onSceneAddedWithDeepLink = nil
                directorFirstSceneName(originalFirstSceneName)
                next()

        , shouldBeQueued = proc(route: var string) =
            if not (isClassRegistered(route)):
                error "`" & route & "`" & " has not been found in class registry"
                route = ""
    )

directorFirstSceneDeepLinksListener()

proc clear*(dir: Director) =
    currentDirector().removeCurrentScene()
    directorFirstSceneDeepLinksListener()
