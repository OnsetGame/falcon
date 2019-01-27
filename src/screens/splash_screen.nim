import nimx / [view, timer]
import rod / [viewport, node, asset_bundle]
import shared / [director, game_scene, user]
import facebook_sdk.facebook_sdk
import utils.helpers
import logging

type
    SplashScreen* = ref object of GameScene
        mLogoSprite: Node
        proceedCallback: proc()
        initCoplete: bool

method init*(ss: SplashScreen, r: Rect) =
    procCall ss.GameScene.init(r)
    ss.addDefaultOrthoCamera("Camera")

method name*(ss: SplashScreen): string = "SplashScreen"

when defined(emscripten):
    import jsbind.emscripten

proc proceed(ss: SplashScreen) =
    debug "SplashScreen proceeds"
    # directorLoadFirstScene()
    ss.proceedCallback()

proc onInitComplete(ss: SplashScreen) =
    debug "SplashScreen init done"
    ss.initCoplete = true
    if not ss.proceedCallback.isNil:
        ss.proceed()

method initAfterResourcesLoaded*(ss: SplashScreen) =
    proc preloadResources() =
        currentDirector().preloadCommonResources do():
            when facebookSupported:
                loadFbImage() do():
                    ss.onInitComplete()
            else:
                ss.onInitComplete()

    when defined(emscripten):
        preloadResources()
    else:
        ss.rootNode.addChild(newNodeWithResource("splash_screen/precomps/splash_screen.json"))
        ss.mLogoSprite = ss.rootNode.findNode("logo")
        setTimeout 0.7, preloadResources

proc proceed*(ss: SplashScreen, handler: proc()) =
    debug "SplashScreen may proceed"
    ss.proceedCallback = handler
    if ss.initCoplete:
        ss.proceed()

method canHandleDeepLinks*(v: SplashScreen): bool =
    return false

when not defined(emscripten):
    #const abd = assetBundleDescriptor("splash_screen")
    # method sceneResources*(ss: SplashScreen): seq[string] =
    #     result = RESOURCES

    method assetBundles*(v: SplashScreen): seq[AssetBundleDescriptor] =
        const allAssetBundles = [
            assetBundleDescriptor("splash_screen")
        ]
        result = @allAssetBundles

registerClass(SplashScreen)
