import rod / [ node, viewport, rod_types, component, asset_bundle ]
import rod.component.camera
import rod.component.text_component
import rod.tools.serializer
import nimx / [ view, font, context,  types ]

import game_scene
import json, random
import loading_info
import tables

import utils.falcon_analytics_helpers
import utils.falcon_analytics
import utils.game_state

import shared / [ user ]
import shared.localization_manager
# Loading Scene w/ Progress

const tips = [
    "LOADING_TIPS_1",
    "LOADING_TIPS_2",
    "LOADING_TIPS_3",
    "LOADING_TIPS_4",
    "LOADING_TIPS_5",
    "LOADING_TIPS_6"
]

type LoadingScene* = ref object of GameScene
    mTitle: string
    mLoadingImage: string
    mProgress: float32
    progressNode: Node
    titleNode: Node
    imageParentNode: Node
    backgroundParentNode: Node

type ProgressBarComponent = ref object of Component
    size: Size
    progress: float32

method draw(p: ProgressBarComponent) =
    const outerStroke = 5
    let c = currentContext()
    c.fillColor = newColor(0, 0, 0, 0.6)
    c.strokeColor = newColor(255/255, 255/255, 255/255, 102/255)
    c.strokeWidth = outerStroke
    c.drawRoundedRect(newRect(0, 0, p.size.width, p.size.height), 10)

    c.fillColor = whiteColor()
    c.strokeWidth = 0
    c.drawRoundedRect(newRect(outerStroke, outerStroke, max((p.size.width - outerStroke * 2) * p.progress, 20), p.size.height - outerStroke * 2), 5)

registerComponent(ProgressBarComponent)

proc progress*(ls: LoadingScene, p: float) =
    ls.mProgress = p
    if not ls.progressNode.isNil:
        if p < 0:
            ls.progressNode.alpha = 0
        else:
            ls.progressNode.alpha = 1
            ls.progressNode.component(ProgressBarComponent).progress = p
        ls.setNeedsDisplay()

method init*(ls: LoadingScene, r: Rect) =
    procCall ls.GameScene.init(r)

    ls.addDefaultOrthoCamera("Camera")

    if not isAnalyticEventDone(FIRST_RUN_TUTORIAL_BEGIN):
        sharedAnalyticsTimers()[FIRST_RUN_TUTORIAL_BEGIN].start()
        sharedAnalyticsTimers()[FIRST_RUN_LOADSCREEN_50_COMPLETE].start()

var nimLogoShown = false

method initAfterResourcesLoaded*(ls: LoadingScene) =
    var n = newLocalizedNodeWithResource("loading_screens/" & ls.mTitle & "/precomps/loading_screen_" & ls.mTitle)
    ls.rootNode.addChild(n)

    if nimLogoShown:
        n.findNode("nim_logo").alpha = 0
    else:
        nimLogoShown = true

    ls.imageParentNode = n.findNode("image_parent")
    ls.backgroundParentNode = n.findNode("background_parent")
    ls.progressNode = n.findNode("progressbar_parent")

    let pr = ls.progressNode.component(ProgressBarComponent)
    pr.size = newSize(768, 20)
    ls.progress(ls.mProgress)

    var tipNode = ls.rootNode.findNode("tip_text")
    if not tipNode.isNil:
        # tipNode = tipNode.findNode("tip_text")
        tipNode.component(Text).text = localizedString(rand(tips))

    # ANALYTICS
    var capturator = proc(): float64 = return ls.mProgress.float64
    var progressBreakpoints = @[0.5, 0.99]

    if not isAnalyticEventDone(FIRST_RUN_TUTORIAL_BEGIN):
        sharedAnalytics().first_run_loadscreen_begin(sharedAnalyticsTimers()[FIRST_RUN_LOADSCREEN_BEGIN].diff().int)
        setGameState($FIRST_RUN_LOADSCREEN_BEGIN, true, ANALYTICS_TAG)

        let duration50 = sharedAnalyticsTimers()[FIRST_RUN_LOADSCREEN_50_COMPLETE].diff().int
        let duration100 = sharedAnalyticsTimers()[FIRST_RUN_TUTORIAL_BEGIN].diff().int
        ls.noteProgressTime(capturator, progressBreakpoints) do(results: seq[float64]):
            sharedAnalytics().first_run_loadscreen_50_complete(results[0].int+duration50)
            setIsBeforeTutorialAnalytics(false)
            sharedAnalyticsTimers()[FIRST_RUN_PRESS_EXCHANGE_CHIPS].start()

    if not isAnalyticEventDone(FIRST_RUN_RETURN_TO_CITY) and isInSlotAnalytics:
        sharedAnalyticsTimers()[FIRST_RUN_RETURN_TO_CITY].start()
        ls.noteProgressTime(capturator, progressBreakpoints) do(results: seq[float64]):
            sharedAnalytics().first_run_return_to_city(sharedAnalyticsTimers()[FIRST_RUN_RETURN_TO_CITY].diff().int)

const emptyTemplate = "template"
const allAssetBundles = {
    "dreamTowerSlot": assetBundleDescriptor("loading_screens/dreamTowerSlot"),
    "candySlot": assetBundleDescriptor("loading_screens/candySlot"),
    "candySlot2": assetBundleDescriptor("loading_screens/candySlot2"),
    "map": assetBundleDescriptor("loading_screens/map"),
    "groovySlot": assetBundleDescriptor("loading_screens/groovySlot"),
    "balloonSlot": assetBundleDescriptor("loading_screens/balloonSlot"),
    "mermaidSlot": assetBundleDescriptor("loading_screens/mermaidSlot"),
    "ufoSlot": assetBundleDescriptor("loading_screens/ufoSlot"),
    "witchSlot": assetBundleDescriptor("loading_screens/witchSlot"),
    "cardSlot": assetBundleDescriptor("loading_screens/cardSlot"),
    emptyTemplate: assetBundleDescriptor("loading_screens/template")
}.toTable()

method assetBundles*(v: LoadingScene): seq[AssetBundleDescriptor] =
    if v.mTitle in allAssetBundles:
        result = @[allAssetBundles[v.mTitle]]
    else:
        v.mTitle = emptyTemplate
        v.mLoadingImage = emptyTemplate
        result = @[allAssetBundles[v.mTitle]]

method canHandleDeepLinks*(v: LoadingScene): bool =
    return false

proc newLoadingScene*(li: LoadingInfo) : LoadingScene =
    result.new()
    result.name = "Loading scene"
    result.mTitle = li.title
    result.mLoadingImage = li.imageName
