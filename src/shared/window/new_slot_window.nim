import rod / [rod_types, node, viewport, component, asset_bundle]
import rod / component / [text_component, ui_component, ae_composition, clipping_rect_component, gradient_fill]
import nimx / [matrixes, property_visitor, types, animation]
import core / notification_center
import utils / [helpers, falcon_analytics, game_state, sound_manager, color_segments]
import shared / [localization_manager, game_scene, director]
import shared / window / [window_component, button_component]
import quest.quests, sequtils, strutils, tables
import core.zone
import falconserver.map.building.builditem
import core / helpers / color_segments_helper
import core / flow / [flow, flow_state_types]
import narrative.narrative_character

const SLOT_COMPOSITION_PATH = "windows/newslot/precomps/"
const SHOW_EXCEPTIONS_NODES = @["button_blue_wide_01","button_close"]

type NewSlotWindow* = ref object of AsyncWindowComponent
    window*:Node
    character: NarrativeCharacter
    onUnlock*: proc()

type SlotWindowConfig = object
    text: string
    compBaseName: string

var sConfigs = newTable[BuildingId,SlotWindowConfig]()

sConfigs[candySlot] = SlotWindowConfig(text:"NFP_CANDY_SLOT_DESC",compBaseName:"candy")
sConfigs[candySlot2] = SlotWindowConfig(text:"NFP_CANDY2_SLOT_DESC",compBaseName:"candy2")
sConfigs[balloonSlot] = SlotWindowConfig(text:"NFP_BALLOONS_SLOT_DESC",compBaseName:"balloon")
sConfigs[witchSlot] = SlotWindowConfig(text:"NFP_WITCH_SLOT_DESC",compBaseName:"witch")
sConfigs[mermaidSlot] = SlotWindowConfig(text:"NFP_MERMAID_SLOT_DESC",compBaseName:"mermaid")
sConfigs[ufoSlot] = SlotWindowConfig(text:"NFP_UFO_SLOT_DESC",compBaseName:"ufo")
sConfigs[groovySlot] = SlotWindowConfig(text:"NFP_GROOVY_SLOT_DESC",compBaseName:"groovy")

proc playAEAnim(n:Node, animName:string, cb: proc() = nil, exceptions: seq[string] = @[]) =
    let aeComp = n.getComponent(AEComposition)
    let aeAnim = aeComp.play(animName, exceptions)
    if not cb.isNil:
        aeAnim.onComplete do():
            cb()


method hideStrategy*(nsw: NewSlotWindow): float =
    nsw.character.hide(0.3)
    nsw.node.hide(0.5)
    nsw.window.playAEAnim("out")

    return 1.0

proc setupSlot*(nsw: NewSlotWindow, z:Zone) =
    let bid = parseEnum[BuildingId](z.name)
    let cfg = sConfigs[bid]
    let scene = nsw.node.sceneView.GameScene

    nsw.window = newLocalizedNodeWithResource(SLOT_COMPOSITION_PATH&"new_slot_"&cfg.compBaseName)

    nsw.canMissClick = false
    nsw.anchorNode.addChild(nsw.window)

    let imageBack = nsw.window.findNode("unlock_images")
    let gf = imageBack.findNode(cfg.compBaseName).component(GradientFill)
    gf.localCoords = true
    gf.startPoint.y = -208
    imageBack.removeChildrensExcept(@["circle_component_shadow.png","back",cfg.compBaseName])

    let bg = nsw.window.findNode("bg_slot")
    bg.removeChildrensExcept(@["bg_"&cfg.compBaseName])

    nsw.node.alpha = 1.0
    nsw.window.playAEAnim("in",proc() = nsw.window.findNode("rewards_glow").addRotateAnimation(40),SHOW_EXCEPTIONS_NODES)

    let rx = -1920 / 2.0
    let ry = 1080*0.27 / 2.0
    let rw = 1920*2.0
    let rh = 1080*0.73
    nsw.window.findNode("bg_slot").component(ClippingRectComponent).clippingRect = newRect(rx, ry, rw, rh)

    nsw.window.findNode("TAB_active").getComponent(Text).text = localizedString("NFP_NEW_SLOT_TITLE")
    nsw.window.findNode("TAB_inactive").getComponent(Text).text = localizedString("NFP_NEW_SLOT_TITLE")
    let msgText = nsw.window.findNode("message_text").getComponent(Text)
    msgText.text = localizedString(cfg.text)
    msgText.lineSpacing = -10.0

    nsw.window.findNode("text_build").getComponent(Text).text = localizedString("NFP_BUILD_TO")
    nsw.window.findNode("text_complete").getComponent(Text).text = localizedString("NFP_SLOT_FEATURE_PLAY")
    let circleShapeNode = nsw.window.findNode("circle_shader")
    circleShapeNode.alpha = 1.0
    circleShapeNode.colorSegmentsForNode()

    let bttnUnlock = nsw.window.findNode("button_blue_wide_01").component(ButtonComponent)
    bttnUnlock.bounds = newRect(0,0,394,84)
    bttnUnlock.title = localizedString("NFP_UNLOCK_BUTTON")
    bttnUnlock.onAction do():
        if not nsw.onUnlock.isNil:
            nsw.onUnlock()
        bttnUnlock.enabled = false
        currentNotificationCenter().postNotification("SET_EXIT_FROM_SLOT_REASON", newVariant("wnd_upgrade_city"))
        directorMoveToMap()

    let bttnClose = nsw.window.findNode("button_close").component(ButtonComponent)
    bttnClose.bounds = newRect(0,0,124,124)
    bttnClose.onAction do():
        currentNotificationCenter().postNotification("TASK_WINDOW_ANALYTICS_SOURCE", newVariant("wnd_upgrade_city"))
        nsw.closeButtonClick()

    let slotState = findActiveState(SlotFlowState).SlotFlowState
    if not slotState.isNil:
        sharedAnalytics().wnd_upgrade_city(sharedQuestManager().totalStageLevel(), slotState.target, sharedQuestManager().slotStageLevel(slotState.target), z.name)
    setGameState("SHOW_BACK_TO_CITY", true)
    scene.soundManager.sendEvent("COMMON_NEW_FEATURE_EVENT")


method showStrategy*(nsw: NewSlotWindow) =
    nsw.character = nsw.node.addComponent(NarrativeCharacter)
    nsw.character.kind = NarrativeCharacterType.WillFerris
    nsw.character.bodyNumber = 9
    nsw.character.headNumber = 6
    nsw.character.shiftPos(-1053, -540)
    nsw.character.show(0.0)


method assetBundles*(nsw: NewSlotWindow): seq[AssetBundleDescriptor] =
    const BUNDLES = [
        assetBundleDescriptor("windows/newslot"),
        assetBundleDescriptor("loading_screens/candySlot"),
        assetBundleDescriptor("loading_screens/balloonSlot"),
        assetBundleDescriptor("loading_screens/mermaidSlot"),
        assetBundleDescriptor("loading_screens/witchSlot"),
        assetBundleDescriptor("loading_screens/ufoSlot"),
        assetBundleDescriptor("loading_screens/groovySlot"),
        assetBundleDescriptor("loading_screens/candySlot2"),
    ]
    result = @BUNDLES

proc hasWindowForSlot*(z:Zone): bool =
    sConfigs.hasKey(parseEnum[BuildingId](z.name))


registerComponent(NewSlotWindow, "windows")
