import rod / [rod_types, node, viewport, component, asset_bundle]
import rod / component / [text_component, ui_component, ae_composition]
import nimx / [matrixes, property_visitor, types, animation]
import core / notification_center
import utils / [helpers, falcon_analytics, game_state, sound_manager, color_segments]
import shared / [localization_manager, game_scene, director]
import shared / window / [window_component, button_component]
import quest.quests, sequtils, strutils, tables
import core / [ zone ]
import core / helpers / color_segments_helper
import core / flow / [flow, flow_state_types]
import narrative.narrative_character


const FEATURE_COMPOSITION_PATH = "windows/newfeature/precomps/NewFeatureWindow/feature_"
const SHOW_EXCEPTIONS_NODES = @["features_bg/blue_button_04","features_bg/button_close"]

type FeatureKey {.pure.} = enum
    barbershop,
    gifts,
    facebook,
    gs_purple,
    gs_red,
    bank,
    wheel,
    stadium,
    restaurant

type NewFeatureWindow* = ref object of AsyncWindowComponent
    window: Node
    character: NarrativeCharacter
    onUnlock*: proc()

type FeatureConfig = object
    text: string
    fKey: FeatureKey
    setup: proc(nfw:NewFeatureWindow)

method hideStrategy*(nfw: NewFeatureWindow): float =
    nfw.character.hide(0.3)
    nfw.node.hide(0.5)
    let showWinAnimCompos = nfw.window.getComponent(AEComposition)
    showWinAnimCompos.play("out")
    return 1.0

method showStrategy*(nfw: NewFeatureWindow) =
    nfw.character = nfw.node.addComponent(NarrativeCharacter)
    nfw.character.kind = NarrativeCharacterType.WillFerris
    nfw.character.bodyNumber = 9
    nfw.character.headNumber = 6
    nfw.character.shiftPos(-1053, -540)
    nfw.character.show(0.0)

proc commonSetup(nfw: NewFeatureWindow) =
    let win = nfw.window

    let bttnClose = win.findNode("button_close").component(ButtonComponent)
    bttnClose.bounds = newRect(0,0,124,124)
    bttnClose.onAction do():
        currentNotificationCenter().postNotification("TASK_WINDOW_ANALYTICS_SOURCE", newVariant("wnd_upgrade_city"))
        nfw.closeButtonClick()

    let bttnUnlock = win.findNode("blue_button_04").component(ButtonComponent)
    bttnUnlock.bounds = newRect(0,0,394,84)
    bttnUnlock.onAction do():
        if not nfw.onUnlock.isNil:
            nfw.onUnlock()

        bttnUnlock.enabled = false
        currentNotificationCenter().postNotification("SET_EXIT_FROM_SLOT_REASON", newVariant("wnd_upgrade_city"))
        directorMoveToMap()

    let circleShapeNode = win.findNode("circle_shader")
    circleShapeNode.alpha = 1.0
    circleShapeNode.colorSegmentsForNode()

    let textHeader = win.findNode("title_tab").findNode("text_content_active").getComponent(Text)
    let inactiveTextHeader = win.findNode("title_tab").findNode("text_content_inactive").getComponent(Text)
    textHeader.text = localizedString("NFP_UNLOCK_FEATURE")
    inactiveTextHeader.text = localizedString("NFP_UNLOCK_FEATURE")

proc setupRestaurant(nfw:NewFeatureWindow) =
    let chips_sum = nfw.window.findNode("collect_btn").findNode("summ").getComponent(Text)
    chips_sum.text = "2550"
    nfw.commonSetup()

proc setupGasStation(nfw:NewFeatureWindow) =
    let bucks_sum = nfw.window.findNode("collect_btn").findNode("summ").getComponent(Text)
    bucks_sum.text = "350"
    nfw.commonSetup()

var fConfigs = newTable[FeatureType,FeatureConfig]()

fConfigs[IncomeChips]   = FeatureConfig(text:"NFP_CHIPS_DESC",fKey:restaurant,setup:setupRestaurant)
fConfigs[IncomeBucks]   = FeatureConfig(text:"NFP_BUCKS_1_DESC",fKey:gs_red,setup:setupGasStation)
fConfigs[Exchange]      = FeatureConfig(text:"NFP_EXCHANGE_DESC",fKey:bank,setup:commonSetup)
fConfigs[Tournaments]   = FeatureConfig(text:"NFP_TOURNAMENTS_DESC",fKey:stadium,setup:commonSetup)
fConfigs[Wheel]         = FeatureConfig(text:"NFP_WOF_DESC",fKey:wheel,setup:commonSetup)
fConfigs[Gift]          = FeatureConfig(text:"NFP_GIFTS_DESC",fKey:gifts, setup:commonSetup)
fConfigs[Friends]       = FeatureConfig(text:"NFP_FRIENDS_DESC",fKey:facebook, setup:commonSetup)

proc hasWindowForFeature*(z:Zone): bool =
    fConfigs.hasKey(z.feature.kind)

proc setupFeature*(nfw: NewFeatureWindow, z: Zone) =
    let fKind = z.feature.kind
    let scene = nfw.node.sceneView.GameScene
    assert(fConfigs.hasKey(fKind))
    let cfg = fConfigs[fKind]

    let win = newLocalizedNodeWithResource(FEATURE_COMPOSITION_PATH&($cfg.fKey))
    nfw.window = win
    nfw.canMissClick = false
    nfw.anchorNode.addChild(win)

    if not cfg.setup.isNil:
        cfg.setup(nfw)

    block hack:
        for n in win.children:
            if n.name.contains("_text"): # Hack for missing text linespacing export from AE
                for ch in n.children:
                    let textComp = ch.getComponent(Text)
                    if not textComp.isNil:
                        textComp.lineSpacing = -29.0
                if n.children.len == 3: # Hack for wrong anchor position of rotated text.
                    var anchorFixed = n.children[1].anchor
                    anchorFixed.y = -40.0
                    n.children[1].anchor = anchorFixed

    block textMessage:
        let buildingsNode = nfw.window.findNode("buildings")
        let featureText = nfw.window.findNode("FEATURE_TEXT").getComponent(Text)

        removeChildrensExcept(buildingsNode, @[$cfg.fKey])
        featureText.text = localizedString(cfg.text)

    block show:
        nfw.node.alpha = 1.0
        let showWinAnimCompos = win.getComponent(AEComposition)
        let inAnim = showWinAnimCompos.play("in", SHOW_EXCEPTIONS_NODES)
        inAnim.onComplete do():
            win.findNode("rewards_glow").addRotateAnimation(40)

    #echo "fKind", fKind
    #echo "z.name", z.name
    let slotState = findActiveState(SlotFlowState).SlotFlowState
    if not slotState.isNil:
        sharedAnalytics().wnd_upgrade_city(sharedQuestManager().totalStageLevel(), slotState.target, sharedQuestManager().slotStageLevel(slotState.target), $fKind&z.name)
    setGameState("SHOW_BACK_TO_CITY", true)
    scene.soundManager.sendEvent("COMMON_NEW_FEATURE_EVENT")

method assetBundles*(nfw: NewFeatureWindow): seq[AssetBundleDescriptor] =
    const BUNDLES = [
        assetBundleDescriptor("windows/newfeature")
    ]
    result = @BUNDLES

registerComponent(NewFeatureWindow, "windows")
