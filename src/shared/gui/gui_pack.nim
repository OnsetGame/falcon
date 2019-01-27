import rod.rod_types
import rod.node
import rod.ray
import rod.viewport
import rod.component
import rod.component.solid
import rod.component.ui_component

import nimx.animation
import nimx.matrixes
import nimx.view
import nimx.button
import nimx.gesture_detector
import nimx.notification_center
import utils.helpers

import gui_module_types
import gui_module

import spin_button_module, player_info_module, money_panel_module, map_buttons_module, paytable_open_button_module,
        win_panel_module, autospins_switcher_module, total_bet_panel_module, balloon_free_spins_module, candy_bonus_rules_module,
        fullscreen_button_module, menu_button_module, side_timer_panel, boosters_side_panel

import shared / gui / features / map / [map_button_quests, map_button_collect, map_button_tournaments, map_bottom_menu]
import shared / gui / features / slot / [slot_bottom_menu]

import shared.game_scene
import utils.sound_manager

import sequtils, logging

import utils.falcon_analytics_helpers

export gui_module

const start_scale = newVector3(0.0, 0.0, 1.0)
var dest_scale = newVector3(1.0, 1.0, 1.0)
const start_alpha = 0.0
const dest_alpha = 1.0

type
    GuiPopup* = ref object of GUIModule
        node*: Node
        readyForClose*: bool

    GUIPack* = ref object of RootObj
        rootNode*: Node
        modules*: seq[GUIModule]
        allowActions*: bool
        popups*: seq[GuiPopup]
        solid*: Solid
        gameEventsProcessing*: bool
        tapDetector: TapGestureDetector

    Relation* = enum
        TopLeft
        TopMid
        TopRight

        BottomLeft
        BottomMid
        BottomRight

        MiddleRight
        MiddleLeft

        FlexTop
        FlexBottom

proc getModule*(pack: GUIPack, moduleType: GUIModuleType): GUIModule
proc removeModule*(pack: GUIPack, moduleType: GUIModuleType, immediately: bool = false)

proc createGuiPopup*(n: Node, mt: GUIModuleType): GuiPopup=
    result.new()
    result.node = n
    result.moduleType = mt

proc guiScale*(r: Rect): Vector3=
    const targetRatio = 1920.0/1080.0
    let currentRatio  = r.width/r.height
    let scaleRatio    = currentRatio / targetRatio
    result = newVector3(scaleRatio, scaleRatio, 1.0)
    if result.x > 1.0:
        result = newVector3(1.0,1.0,1.0)

proc onClicked*(pack: GUIPack, p: Point)=
    if pack.popups.len > 0:
        let lastPopup = pack.popups[pack.popups.len - 1]
        let r = pack.rootNode.sceneView.rayWithScreenCoords(p)
        var castResult = newSeq[RayCastInfo]()
        lastPopup.node.rayCast(r, castResult)
        if castResult.len > 0 and lastPopup.moduleType != mtTutorial:
            discard
        elif lastPopup.readyForClose:
            # ANALYTICS
            setClosedByButtonAnalytics(false)

            pack.removeModule(lastPopup.moduleType)

proc isModulePopup(module: GUIModule): bool =
    case module.moduleType:
    of mtRewardsPopup, mtLevelUp, mtSpeedUpBuild, mtRemoveBuild,
        mtUpgradeBuild, mtOutOfCurrency, mtQuestWindow, mtExchangePopup, mtProfileInfo,
        mtSelectAvatar, mtSoundSettings, mtStorePopup, mtNotAvailableSpots, mtTutorial,
        mtSelectSlot, mtSelectExchange:
        result = true
    else:
        result = false

template v*(pack:GUIPack): SceneView = pack.rootNode.sceneView

proc playEvent*(pack: GUIPack, event: string)=
    pack.v.GameScene.soundManager.sendEvent(event)

proc attachCloseHandler*(popup: GuiPopup, pack: GUIPack)=
    var tapDetView = newView(newRect(0,0,1920,1080))
    popup.node.component(UIComponent).view = tapDetView
    pack.tapDetector = newTapGestureDetector( proc(p: Point )=
        pack.onClicked(p)
        )
    tapDetView.addGestureDetector(pack.tapDetector)

proc removeCloseHandler*(popup: GuiPopup)=
    popup.node.removeComponent("UIComponent")

proc addPopup(pack: GUIPack, module: GUIModule)=
    # let closeNodes = pack.rootNode.findNodesContains("close", false)
    # for cl in closeNodes:
    #     cl.removeFromParent()

    dest_scale = guiScale(pack.rootNode.sceneView.window.frame)
    pack.rootNode.uiComponentsState(false)
    pack.playEvent("COMMON_POPUP_SHOW")
    let popupSolid = pack.rootNode.newChild()

    let popupAUX = popupSolid.newChild("AUX")
    popupAUX.positionX = 960.0
    popupAUX.positionY = 540.0
    popupAUX.scale = start_scale

    let curPopup = module.rootNode
    popupAUX.addChild(curPopup)
    curPopup.uiComponentsState(false)
    curPopup.positionX = -960
    curPopup.positionY = -540

    var prevPopup: GuiPopup
    if pack.popups.len > 0:
        prevPopup = pack.popups[pack.popups.len - 1]
        prevPopup.node.removeComponent("Solid")
        prevPopup.removeCloseHandler()

    let popup = createGuiPopup(popupSolid, module.moduleType)
    popup.attachCloseHandler(pack)
    pack.popups.add(popup)

    popupSolid.alpha = if prevPopup.isNil: start_alpha else: dest_alpha
    curPopup.alpha = if prevPopup.isNil: dest_alpha else: start_alpha

    popupSolid.setComponent("Solid", pack.solid)

    let showAnim = newAnimation()
    showAnim.loopDuration = 0.25
    showAnim.numberOfLoops = 1
    showAnim.onAnimate = proc(p: float)=
        if prevPopup.isNil:
            popupSolid.alpha = interpolate(start_alpha, dest_alpha, p)
        else:
            curPopup.alpha = interpolate(start_alpha, dest_alpha, p)
        popupAUX.scale = interpolate(start_scale, dest_scale, p)

    showAnim.onComplete do():
        curPopup.uiComponentsState(true)

    let delayAnim = newAnimation()
    delayAnim.loopDuration = 3.0
    delayAnim.numberOfLoops = 1
    delayAnim.onComplete do():
        popup.readyForClose = true

    let metaAnim = newMetaAnimation(showAnim, delayAnim)
    metaAnim.numberOfLoops = 1

    pack.rootNode.addAnimation(metaAnim)
    module.onAdded()
    curPopup.uiComponentsState(true)

proc removePopup(pack: GUIPack, module: GUIModule)=
    if pack.popups.len == 0:
        info "GUIPack::removePopup: pack.popups.len == 0"

    dest_scale = guiScale(pack.rootNode.sceneView.window.frame)

    var popupToRemove: GuiPopup
    for i, p in pack.popups:
        if p.moduleType == module.moduleType:
            popupToRemove = p
            pack.popups.del(i)
            break
    if popupToRemove.isNil:
        return
    popupToRemove.removeCloseHandler()
    popupToRemove.node.uiComponentsState(false)
    pack.playEvent("COMMON_POPUP_HIDE")

    var prevPopup: GuiPopup
    if pack.popups.len > 0:
        if not popupToRemove.node.componentIfAvailable(Solid).isNil:
            popupToRemove.node.removeComponent(Solid)
        prevPopup = pack.popups[pack.popups.len - 1]
        prevPopup.node.setComponent("Solid", pack.solid)
        prevPopup.attachCloseHandler(pack)

    let animNode = popupToRemove.node.findNode("AUX")

    let hideAnim = newAnimation()
    hideAnim.loopDuration = 0.25
    hideAnim.numberOfLoops = 1
    hideAnim.onAnimate = proc(p: float)=
        if prevPopup.isNil:
            popupToRemove.node.alpha = interpolate(dest_alpha, start_alpha, p)
        else:
            animNode.alpha = interpolate(dest_alpha, start_alpha, p)
        animNode.scale = interpolate(dest_scale, start_scale, p)

    hideAnim.onComplete do():
        popupToRemove.node.removeFromParent()
        if not prevPopup.isNil:
            prevPopup.node.uiComponentsState(true)

        if pack.popups.len == 0:
            pack.allowActions = true
            pack.rootNode.uiComponentsState(true)

    pack.rootNode.addAnimation(hideAnim)

proc addModule*(pack: GUIPack, moduleType: GUIModuleType): GUIModule {.discardable.} =
    case moduleType:
    of mtSpinButton:               result = createSpinButton(pack.rootNode)
    of mtPlayerInfo:               result = createPlayerInfo(pack.rootNode)
    of mtMoneyPanel:               result = createMoneyPanel(pack.rootNode)
    of mtMenuButton:               result = createMenuButton(pack.rootNode)
    of mtQuestsButton:             result = createQuestsButton(pack.rootNode)
    of mtWinPanel:                 result = createWinPanel(pack.rootNode)
    of mtAutospinsSwitcher:        result = createAutospinsSwitcher(pack.rootNode)
    of mtTotalBetPanel:            result = createTotalBetPanel(pack.rootNode)
    of mtBalloonFreeSpins:         result = createBalloonFreeSpins(pack.rootNode)
    of mtCandyBonusRules:          result = createCandyBonusRules(pack.rootNode)
    of mtPlayButton:               result = createPlayButton(pack.rootNode)
    of mtMapBottomMenu:            result = createMapBottomMenu(pack.rootNode)
    of mtFullscreenButton:         result = createFullscreenButton(pack.rootNode)
    of mtSidePanel:                result = createSidePanel(pack.rootNode)
    of mtCollectButton:            result = createCollectButton(pack.rootNode)
    of mtTournamentsButton:        result = createTournamentsButton(pack.rootNode)
    of mtSlotBottomMenu:           result = createSlotBottomMenu(pack.rootNode)
    of mtBoostersPanel:            result = createBoostersPanel(pack.rootNode)
    else:
        # ANALYTICS
        setCurrPopupAnalytics(mtNone)

    if result.isModulePopup():
        # ANALYTICS
        setCurrPopupAnalytics(moduleType)

        pack.removeModule(moduleType, true)
        pack.addPopup(result)

    echo "ADD MODULE: ", moduleType

    pack.modules.add(result)

proc layoutModule*(pack: GUIPack, module: GUIModule, offsetX, offsetY: float, rel: Relation) =
    var ray: Ray

    let maxCorner = pack.rootNode.sceneView().bounds.maxCorner

    case rel:
    of Relation.TopLeft:        ray = pack.rootNode.sceneView().rayWithScreenCoords(zeroPoint)
    of Relation.BottomRight:    ray = pack.rootNode.sceneView().rayWithScreenCoords(maxCorner)
    of Relation.BottomLeft:     ray = pack.rootNode.sceneView().rayWithScreenCoords(newPoint(zeroPoint.x, maxCorner.y))
    of Relation.TopRight:       ray = pack.rootNode.sceneView().rayWithScreenCoords(newPoint(maxCorner.x, zeroPoint.y))
    of Relation.MiddleLeft:     ray = pack.rootNode.sceneView().rayWithScreenCoords(newPoint(zeroPoint.x, maxCorner.y * 0.5))
    of Relation.MiddleRight:    ray = pack.rootNode.sceneView().rayWithScreenCoords(newPoint(maxCorner.x, maxCorner.y * 0.5))
    of Relation.BottomMid:      ray = pack.rootNode.sceneView().rayWithScreenCoords(newPoint(maxCorner.x * 0.5, maxCorner.y))
    of Relation.TopMid:         ray = pack.rootNode.sceneView().rayWithScreenCoords(newPoint(maxCorner.x * 0.5, zeroPoint.y))
    of Relation.FlexBottom: ray = pack.rootNode.sceneView().rayWithScreenCoords(newPoint(offsetX * maxCorner.x, maxCorner.y))
    of Relation.FlexTop:    ray = pack.rootNode.sceneView().rayWithScreenCoords(newPoint(offsetX * maxCorner.x, zeroPoint.y))

    var vector: Vector3
    if ray.intersectWithPlane(newVector3(0, 0, 1), pack.rootNode.localToWorld(newVector3()), vector):
        vector = pack.rootNode.worldToLocal(vector)

        let win = pack.rootNode.sceneView().window
        var gs = 1.0
        if not win.isNil:
            let scale = guiScale(win.frame)
            module.rootNode.scale = scale
            gs = scale.x

        case rel:
            of Relation.FlexBottom, Relation.FlexTop:
                module.rootNode.positionX = vector.x
                module.rootNode.positionY = vector.y + offsetY * gs
            else:
                module.rootNode.positionX = vector.x + offsetX * gs
                module.rootNode.positionY = vector.y + offsetY * gs


proc removeModule*(pack: GUIPack, moduleType: GUIModuleType, immediately: bool = false) =
    var newPack: seq[GUIModule] = @[]
    for m in pack.modules:
        if m.moduleType != moduleType:
            newPack.add(m)
        else:
            m.onRemoved()
            if m.isModulePopup() and not immediately:
                pack.removePopup(m)
            else:
                m.rootNode.removeFromParent()
    pack.modules = newPack

proc getModule*(pack: GUIPack, moduleType: GUIModuleType): GUIModule =
    for m in pack.modules:
        if m.moduleType == moduleType:
            return m

proc activeModule*(pack: GUIPack): GUIModule =
    if pack.popups.len() > 0:
        return pack.popups[pack.popups.len - 1]

    return nil

proc playClickSound*(pack: GUIPack)=
    pack.playEvent("COMMON_GUI_CLICK")

proc initGui*(pack: GUIPack)=
    pack.modules = @[]
    pack.popups = @[]
    pack.solid = createComponent[Solid]()
    pack.solid.color = newColor(0.0, 0.0, 0.0, 0.75)
    pack.solid.size = newSize(1920.0*2.0, 1080.0*2.0)
    pack.allowActions = true

proc createGUIPack*(rn: Node): GUIPack =
    result.new()
    result.rootNode = rn
    result.initGui()

