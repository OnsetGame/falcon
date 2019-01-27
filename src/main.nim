import strutils, logging, json, tables, times
import nimx / [ view, window, mini_profiler, timer ]
import rod / [ node, viewport ]
import shared / [ localization_manager, game_init, message_box, director, deep_links ]
import utils / [ console_commands, falcon_analytics_helpers, falcon_analytics, helpers ]

# import utils.analytics.debug_analytics # Uncomment this to log analytics events to console

const isMobile = defined(ios) or defined(android)

when defined(android):
    import utils.crashlytics_logger # Should be imported to register crashlytics
    import utils.analytics.flurry_analytics
    import rod.asset_bundle

import utils.analytics.appsflyer_analytics
when defined(emscripten) or defined(android):
    import utils.analytics.devtodev_analytics
    import utils.analytics.deltadna_analytics
when defined(android):
    import utils.analytics.firebase_analytics

const loc {.strdefine.}: string = "en"

when defined(emscripten) or defined(js):
    import jsbind
    import platformspecific.js_prequel
    when defined(emscripten):
        import jsbind.emscripten
        import utils.analytics.facebook_analytics

        setupUnhandledExceptionHandler()

        outOfMemHook = proc() =
            discard EM_ASM_INT("""throw new Error("Out of Memory");""")

when defined(android):
    proc c_raise(sig: cint): cint {.importc:"raise".}
    const SIGABRT = 6
    outOfMemHook = proc() =
        crashlyticsLog("Out of Memmory")
        discard c_raise(SIGABRT)

    onUnhandledException = proc(errorMsg: string) =
        error "onUnhandledException ", errorMsg
        discard c_raise(SIGABRT)


var profilerUpdateTimer: Timer

proc startApplication() =
    const ver = "Client version: " & staticExec("git rev-parse HEAD")
    info ver

    when defined(js) or defined(emscripten):
        prepareJsPrequel()
    elif defined(android):
        getURLForAssetBundle = proc(s: string): string =
            "https://game.onsetgame.com/mobassets/" & s & ".gz"

    # Create application's main window
    var mainWindow : Window

    try:
        when isMobile:
            mainWindow = newFullScreenWindow()
        else:
            mainWindow = newWindow(newRect(40, 40, 1280, 720))
    except:
        when defined(emscripten):
            let msg = getCurrentExceptionMsg()
            showMessageBox("Could not initialize WebGL.", "Ooops! You are challenging performance issues. Please make sure that you do not have excessive number of tabs or browsers and you are using recent browser version.", Error) do():
                sendEvent("webgl_init_fail", %*{"message": msg})
        else:
            showMessageBox("Could not create window.", "", Error)

    when defined(emscripten):
        # In emscripten mode we want to postpone canvas appearance until
        # loading screen is ready to show up. Until then we just show some
        # animated background defined in main.html. The canvas is later
        # shown from splash_screen.nim
        discard EM_ASM_INT """
        document.getElementById("nimx_canvas0").style.left = "-1000%";
        """

    mainWindow.title = "Test MyGame"
    mainWindow.backgroundColor = blackColor()

    # Attach director to window
    currentDirector().attachToWindow(mainWindow)

    if loc.len == 0:
        sharedLocalizationManager().localization = DEFAULT_LOC
    else:
        sharedLocalizationManager().localization = loc

    handleInitialDeepLinks()
    initGame()

    when not defined(js):
        let profiler = sharedProfiler()
        profilerUpdateTimer = setInterval(3.0) do():
            if profiler.enabled:
                profiler["RAM"] = getOccupiedMem() div (1024 * 1024)
                if not currentDirector().currentScene.isNil:
                    profiler["NODES"] = numberOfNodesInTree(currentDirector().currentScene.rootNode) + 1
                    profiler["ENODES"] = numberOfEnabledNodes(currentDirector().currentScene.rootNode)
                    profiler["LAnims"] = numberOfForeverAnims(currentDirector().currentScene)
                when defined(emscripten):
                    let heap = EM_ASM_INT "return HEAP8.length;"
                    profiler["Heap"] = heap div(1024 * 1024)

    mapLoadingTimer = setInterval(1.0) do():
        mapLoadingTime.inc()

runApplication:
    startApplication()
