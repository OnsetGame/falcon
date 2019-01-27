import strutils, logging, json, tables, times, macros

import nimx / [ button, view, mini_profiler, notification_center, autotest, app, http_request ]
import nimx / private / text_drawing

when defined(runAutoTests) or not defined(release):
    import ../../tests/test_runner

import shared / [ director, user, login, staging, alerts, deep_links ]
import core.net.server
import core / flow / flow
import screens / [splash_screen, gdpr_screen]

import utils.falcon_analytics_utils
import slots.all_slot_machines

import facebook_sdk.facebook_sdk
import facebook_sdk.facebook_login
import facebook_sdk.facebook_graph_request
import falconserver.auth.profile_types

import map.tiledmap_view
import shared.window.window_manager
import shared.window.alert_window
import shared.window.button_component

import utils.falcon_analytics_helpers
import utils.falcon_analytics
import utils.game_state
import nimx.assets.asset_manager

when defined(emscripten): # This is for emscripten target only
    import jsbind
    import jsbind.emscripten
    import nimx.pathutils
    import utils / [ falcon_analytics, js_helpers ]

const scene {.strdefine.}: string = ""
const DEFAULT_FIRST_SCENE = "SplashScreen"

proc hideFacebookSplashScreen() {.inline.} =
    # In emscripten build the splash screen itself is never shown. Instead we show
    # some nice background defined in main.html. All we have to do is reveal
    # the canvas when the loading screen is ready to show up.
    when defined(emscripten):
        discard EM_ASM_INT """
        document.getElementById("nimx_canvas0").style.left = 0;
        document.getElementById("background").style.display = "none";
        """

proc startGame() =
    when scene.len != 0:
        # we don't have a splash screen which is responsible for loading the
        # first scene, so we're loading it here manually.
        currentDirector().preloadCommonResources do():
            currentDirector().moveToScene(scene)
    else:
        directorLoadFirstScene()

    when defined(emscripten):
        let href = getCurrentHref()
        info "href = ", href
        let notificationID = href.uriParam("notificationID")
        if notificationID.len > 0:
            info "notificationID = '", notificationID, "',  user level = ", currentUser().level
            sharedAnalytics().run_from_notification(notificationID)

    startTimeCount()

    when defined(runAutoTests) or not defined(release):
        if haveTestsToRun():
            sharedProfiler().enabled = true
            startFalconAutotests()

proc gdprStartGame() =
    if true:
        startGame()
        return

    when scene.len != 0:
        startGame()
        return

    when defined(runAutoTests) or not defined(release):
        if haveTestsToRun():
            startGame()
            return

    if currentUser().gdpr:
        startGame()
    else:
        let gdprScene = currentDirector().moveToScene("GdprScreen").GdprScreen
        gdprScene.onSuccess = proc() =
            startGame()

proc loginAndStart() {.inline.} =
    # Start game after get initial user data from server.
    var splashScreen: SplashScreen
    if scene.len == 0:
        splashScreen = SplashScreen.new(zeroRect)
        currentDirector().moveToScene(splashScreen) # Show splash screen

    let onSplashAndCommonResourcesLoaded = proc() =
        hideFacebookSplashScreen()
        enableTextSubpixelDrawing(false)

        if haveTestsToRun():
            initialServerRequest do():
                gdprStartGame()
        else:
            when facebookSupported:
                prepareFacebook() do():
                    gdprStartGame()
            else:
                initialServerRequest do():
                    gdprStartGame()

    if not splashScreen.isNil:
        splashScreen.proceed(onSplashAndCommonResourcesLoaded)
    else:
        onSplashAndCommonResourcesLoaded()

const prodFBApp = (id: "1235026969865805", name: "Reel Valley™ — Spin & Build!")
const stageFBApp = (id: "156481611480832", name: "Falcon-test")
const localFBApp = (id: "540635482801018", name: "http­:­/­/­l­o­c­a­l­h­o­s­t­:­5000")

when defined(emscripten): # This is for emscripten target only
    import jsbind.emscripten
    import nimx.pathutils

    proc facebookAppId(): string =
        let href = getCurrentHref()
        if href.find("game.onsetgame.com") != -1:
            result = prodFBApp.id
        elif href.find("localhost") != -1:
            result = localFBApp.id
        else:
            result = stageFBApp.id

proc initGame*()

proc resetGame() =
    sharedAssetManager().unmountAll()
    currentDirector().clear()
    sharedDeepLinkRouter().restoreDeepLink()

proc quitOrRestart() =
    removeAllFlowStates()
    sharedServer().setSharedServer()
    when defined(emscripten) or defined(js):
        reloadWindow()
    else:
        resetGame()
        initGame()

proc setupCriticalAlertHandlers() =
    setupAlertHandlers()

    sharedNotificationCenter().addObserver("HAVE_TO_RESTART_APP", 1) do(args: Variant):
        quitOrRestart()

    sharedNotificationCenter().addObserver("SHOW_BAD_CONNECTION", 1, proc(args: Variant) =
        sharedWindowManager().showBadConnection()
        )

    sharedNotificationCenter().addObserver("HIDE_BAD_CONNECTION", 1, proc(args: Variant) =
        sharedWindowManager().hideBadConnection()
        )

when defined(android):
    import nimx.utils.android
    import android.provider.settings
    import android.content.context

    proc isTestMode(): bool {.inline.} =
        let cr = mainActivity().getContentResolver()

        proc hasMarker(s: string): bool =
            const marker = "falcontest"
            s.toLowerAscii().find(marker) != -1

        System.getString(cr, "device_name").hasMarker() or
            Secure.getString(cr, "bluetooth_name").hasMarker()

    {.push stackTrace: off.}
    proc Java_com_onsetgame_reelvalley_MainActivity_onActivityDestroy(env: pointer, this: pointer) {.exportc.} =
        sharedServer().setSharedServer()
        resetGame()
    {.pop.}


    proc createButtonsToChooseServer(cb: proc()) {.inline.} =
        var x = 25'f32
        var bttnsCount = 1
        var allButtons = newSeq[Button]()
        let wnd = mainApplication().keyWindow()

        proc removeButtons() =
            for b in allButtons: b.removeFromSuperview()

        proc addButton(title, url: string) =
            let ind = float32(int(bttnsCount / 7))
            let y = 25'f32 + 175'f32 * ind
            let b = Button.new(newRect(x - ind*7*175, y, 150, 150))
            x += 175
            bttnsCount.inc()
            b.title = title.replace("stage-", "")
            b.onAction do():
                removeButtons()
                if url.len > 0:
                    gServerUrl = url
                    isStage = true
                    info "serverUrl: ", gServerUrl
                    fbSDK.setApplicationId(stageFBApp.id)
                    fbSDK.setApplicationName(stageFBApp.name)
                cb()
            wnd.addSubview(b)
            allButtons.add(b)

        sendRequest("GET", "https://stage-api.onsetgame.com/branches-list", "", []) do(r: Response):
            let STAGE_URL = "https://stage-api.onsetgame.com/"
            let STAGE_MASTER = "stage-master"
            addButton("prod", "")
            addButton("stage", STAGE_URL & STAGE_MASTER)
            for branch in r.body.splitLines():
                let b = branch.strip()
                if b.len > 0 and b != "stage-master":
                    addButton(b, STAGE_URL & b)

    template prelaunch(body: untyped) =
        proc cb() = body
        if not haveTestsToRun() and isTestMode():
            createButtonsToChooseServer(cb)
        else:
            cb()
else:
    template prelaunch(body: untyped) = body

import nimx.timer

proc initGame*() =
    prelaunch:
        # declare all state keys in preferences
        updateAnalyticStates()
        setupCriticalAlertHandlers()

        when defined(emscripten) or defined(android):
            if not haveTestsToRun():
                when defined(emscripten):
                    let params = %*{
                        "appId": facebookAppId(),
                        "status": true,
                        "xfbml": false,
                        "version": "v2.9"
                    }
                    # fbSDK.init(params) do():
                    #     discard
                    fbSDK.params = params

                when defined(android):
                    when defined(local):
                        fbSDK.setApplicationId(localFBApp.id)
                        fbSDK.setApplicationName(localFBApp.name)
                    elif defined(stage):
                        fbSDK.setApplicationId(stageFBApp.id)
                        fbSDK.setApplicationName(stageFBApp.name)

        loginAndStart()
