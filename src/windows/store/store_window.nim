import strutils, tables, logging, json

import node_proxy / proxy
import rod / [component, node]
import rod / component / text_component
import nimx / [animation, types, matrixes]

import shared / window / [window_component, button_component, window_manager]
import shared / [director, deep_links, localization_manager, user, tutorial]
import utils / [falcon_analytics, helpers, progress_bar]
import core / flow / [flow, flow_state_types]
import core / [ notification_center, zone ]
import core / features / [booster_feature, vip_system]

import store_tab, store_boosters, store_vip
export StoreTabKind

const TABLE_TITLE_WIDTH = 445.0
# Title width with margin
const TABLE_TITLE_MARGIN_WIDTH = 335.0


nodeProxy StoreWindowTitleProxy:
    txt Text {onNode: "text_content"}:
        node.alpha = 0.5
    bttn ButtonComponent {withValue: np.node.createButtonComponent(newRect(0, 0, TABLE_TITLE_WIDTH, 108))}
    activeBg Node {withName: "active_bg"}:
        alpha = 0.0
    inactiveBg Node {withName: "inactive_bg"}


proc activate(title: StoreWindowTitleProxy) =
    let parent = title.node.parent

    title.activeBg.alpha = 1.0
    title.inactiveBg.alpha = 0.0
    title.txt.node.alpha = 1.0

    parent.addChild(title.node)


proc deactivate(title: StoreWindowTitleProxy) =
    title.activeBg.alpha = 0.0
    title.inactiveBg.alpha = 1.0
    title.txt.node.alpha = 0.5


nodeProxy VipProgress:
    vipLevelText Text {onNode: "vip_level_txt"}:
        text = localizedString("VIP_LEVEL_PROGRESS")
        lineSpacing = -8.0
    vipPoints Text {onNode: "vip_points"}
    vipLevel Text {onNode: "vip_level"}
    animationCrystal Animation {forNode: node, withKey: "crystal"}
    progressBar ProgressBar {onNodeAdd: "progress_parent"}:
        node.positionX = 65.0

    onClick proc()

    bttn ButtonComponent {withValue: np.node.createButtonComponent(newRect(0, 0, 1650, 144))}:
        onAction do():
            np.onClick()


proc update(np: VipProgress, user: User) =
    let lvl = user.vipLevel
    np.vipLevel.text = $lvl
    let currentVipLevel = sharedVipConfig().getLevel(lvl)

    let start = currentVipLevel.pointsRequired
    var percent: float
    var next: int

    if lvl < sharedVipConfig().len - 1:
        next = sharedVipConfig().getLevel(lvl + 1).pointsRequired
        percent = (user.vipPoints - start) / (next - start)
    else:
        next = start
        percent = 1.0

    np.vipPoints.text = formatThousands(min(user.vipPoints, next)) & " / " & formatThousands(next)
    np.progressBar.progress = percent


nodeProxy StoreWindowProxy:
    inAnimation Animation {withKey: "in"}
    tabsBody Node {withName: "tabs_parent"}
    tabsTitle Node {withName: "tabs_title_parent"}
    closeBttn ButtonComponent {withValue: np.node.findNode("button_close").createButtonComponent(newRect(0, -2, 120, 120))}
    vipProgress VipProgress {withValue: VipProgress.new(np.node.findNode("vip_progress_bar"))}


type StoreWindow = ref object of WindowComponent
    source: string
    onCloseSpecialOfferBundleId: string
    currTaskProgress: float

    proxy: StoreWindowProxy
    currentTab: StoreTab
    currentTabKind: StoreTabKind
    titles: array[StoreTabKind.low .. StoreTabKind.high, StoreWindowTitleProxy]

    body: Node


proc setActiveTab(store: StoreWindow, kind: StoreTabKind) =
    if not store.currentTab.isNil and store.currentTabKind == kind:
        return

    let feature = findFeature(BoosterFeature)

    store.titles[store.currentTabKind].deactivate()
    store.titles[kind].activate()

    if not store.currentTab.isNil:
        store.currentTab.remove()

    store.currentTabKind = kind

    case kind:
        of StoreTabKind.Boosters:
            if feature.kind.isFeatureEnabled:
                store.currentTab = createBoostersTab(store.body, store.source, store.currTaskProgress)
                if not isFrameClosed($tsBoosterWindow):
                    store.removeMoneyPanelFromTop()
            else:
                store.currentTab = createBoostersStubTab(store.body, store.source, store.currTaskProgress)
        of StoreTabKind.Vip:
            store.currentTab = createVipTab(store.body, store.source, store.currTaskProgress)
        else:
            discard

    sharedAnalytics().wnd_tab_changed($kind, store.source, store.currTaskProgress)


proc addTabTitle(sw: StoreWindow, kind: StoreTabKind) =
    let title = StoreWindowTitleProxy.new(newNodeWithResource("common/gui/popups/precomps/store_window_title.json"))
    title.txt.text = localizedString($kind & "_SHOP")
    sw.proxy.tabsTitle.addChild(title.node)
    title.node.positionX = kind.float * 335.0
    title.bttn.onAction() do():
        if kind == StoreTabKind.Boosters:
            let feature = findFeature(BoosterFeature)
            if feature.kind.isFeatureEnabled:
                let freeBoostersAmount = feature.freeBoosters()
                sharedAnalytics().wnd_load_boosters_bank("bank_tab",freeBoostersAmount)
        sw.setActiveTab(kind)
    sw.titles[kind] = title


method onInit*(sw: StoreWindow) =
    sw.moneyPanelOnTop = true

    sw.proxy = StoreWindowProxy.new(newNodeWithResource("common/gui/popups/precomps/store_window_new.json"))
    sw.body = sw.proxy.tabsBody
    sw.anchorNode.addChild(sw.proxy.node)
    sw.proxy.closeBttn.onAction() do():
        sw.closeButtonClick()
    for kind in StoreTabKind.low .. StoreTabKind.high:
        sw.addTabTitle(kind)
    sw.proxy.tabsTitle.positionX = -(StoreTabKind.high.float * TABLE_TITLE_MARGIN_WIDTH + TABLE_TITLE_WIDTH) / 2

    sw.proxy.node.subscribe(currentUser()) do():
        sw.proxy.vipProgress.update(currentUser())
    sw.proxy.vipProgress.update(currentUser())
    sw.proxy.vipProgress.onClick = proc() =
        if sw.currentTab of VipTab:
            sw.currentTab.VipTab.scrollToCurrentLevel()
        else:
            sw.setActiveTab(StoreTabKind.Vip)


method hideStrategy*(sw: StoreWindow): float =
    let anim = sw.proxy.inAnimation
    anim.loopPattern = lpEndToStart
    sw.anchorNode.addAnimation(anim)
    if not sw.currentTab.isNil:
        sw.currentTab.remove(removeFromParent = false)
    return anim.loopDuration


method showStrategy*(sw: StoreWindow) =
    sw.node.alpha = 1.0
    let anim = sw.proxy.inAnimation
    anim.loopPattern = lpStartToEnd
    sw.anchorNode.addAnimation(anim)


method beforeRemove*(sw: StoreWindow) =
    procCall sw.WindowComponent.beforeRemove

    sharedAnalytics().wnd_bank_closed($sw.currentTabKind, sw.source, sw.currTaskProgress)
    let offerBundleID = sw.onCloseSpecialOfferBundleId

    # if offerBundleID.len > 0 and not getPurchaseHelper().profileOffers.hasKey(offerBundleID):
    #     let state = newFlowState(SpecialOfferFlowState)
    #     state.offerBundleID = offerBundleID
    #     pushBack(state)


proc showStoreWindow*(storeType: StoreTabKind, source: string, currTaskProgress: float = 0.0): StoreWindow {.discardable.} =
    result = sharedWindowManager().show(StoreWindow)
    if not result.isNil:
        result.source = source
        result.currTaskProgress = currTaskProgress
        result.setActiveTab(storeType)
        sharedAnalytics().wnd_load_bank($result.currentTabKind, result.source, result.currTaskProgress)
        if storeType == StoreTabKind.Boosters:
            let freeBoostersAmount = findFeature(BoosterFeature).freeBoosters()
            sharedAnalytics().wnd_load_boosters_bank(source,freeBoostersAmount)


sharedDeepLinkRouter().registerHandler(
    "store"
    , onHandle = proc(route: string, next: proc()) =
        let storeType = parseEnum[StoreTabKind](route, StoreTabKind.Bucks)
        let w = showStoreWindow(storeType, "deepLink")
        if w.isNil:
            sharedWindowManager().onSceneAddedWithDeepLink = proc() =
                sharedWindowManager().onSceneAddedWithDeepLink = nil
                showStoreWindow(storeType, "deepLink")
                next()
        else:
            next()
)


registerComponent(StoreWindow, "windows")
