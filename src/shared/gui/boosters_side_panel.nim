import nimx / [ types, animation, matrixes, timer ]
import core / notification_center
import rod / [ node, viewport, component ]
import rod / component / [ text_component, color_fill ]
import rod / utils / text_helpers
import shared / window / [ button_component, window_manager ]
import shared / [ game_flow, user, localization_manager, game_scene ]
import utils / [ helpers, timesync, icon_component ]
import strutils, times, tables, logging
import gui_module, gui_module_types
import node_proxy / proxy
import core / components / timer_component
import core / helpers / color_segments_helper
import core / flow / flow_state_types
import core / features / booster_feature
import core / zone

const OFFSET_Y = 170.0
const MULTIPLIER_FONT_SIZE = 28.0

const SECONDS_IN_DAY = 60 * 60 * 24
const SECONDS_FOR_EXPIRE = 2 * SECONDS_IN_DAY

const TimerBackColorConf = (
    angle1: 90.0,
    angle2: 90.0,
    colors: [
        fromHexColor("ff9800ff"),
        fromHexColor("ffc21eff"),
        fromHexColor("ffad0fff"),
        fromHexColor("ffd72dff")
    ]
)

const ActiveBackColorConf* = (
    angle1: 90.0,
    angle2: 90.0,
    colors: [
        newColor(19.0/255.0, 234.0/255.0, 253.0/255.0, 1.0),
        newColor(14.0/255.0, 212.0/255.0, 250.0/255.0, 1.0),
        newColor(8.0/255.0, 190.0/255.0, 247.0/255.0, 1.0),
        newColor(3.0/255.0, 169.0/255.0, 244.0/255.0, 1.0)
    ]
)

const TIMER_BACK_STROKE_COLOR = newColor(1.0,0.92,0.23,1.0)
const BUTTON_RECT = newRect(0.0, -50.0, 170.0, 115.0)

nodeProxy SidePanleProxy:
    multiplierText* Text {onNode: "tittle"}
    iconNode* Node {withName: "reward_icon"}
    bttnBlueNode* Node {withName: "blue_bttn"}
    blueBttn* ButtonComponent {withValue: np.node.findNode("blue_bttn").createButtonComponent(BUTTON_RECT)}
    bttnBlueText* Text {onNode: "title"}

    bttnGreenNode* Node {withName: "green_bttn"}
    greenBttn* ButtonComponent {withValue: np.node.findNode("green_bttn").createButtonComponent(BUTTON_RECT)}
    bttnGreenText* Text {withValue: np.bttnGreenNode.findNode("title").component(Text)}

    bttnRedNode* Node {withName: "red_bttn"}
    redBttn* ButtonComponent {withValue: np.node.findNode("red_bttn").createButtonComponent(BUTTON_RECT)}
    bttnRedText* Text {withValue: np.bttnRedNode.findNode("title").component(Text)}

    stateActiveNode* Node {withName: "active_state"}:
        enabled = false
    stateActiveText* Text {onNode: "active_state_text"}
    stateTimerNode* Node {withName: "timer_state"}:
        enabled = false
    stateTimerTextNode* Node {withName: "timer_text"}
    timer* TextTimerComponent {onNodeAdd: stateTimerTextNode}
    onPanelClick* proc()
    activeSwitchTimer* Timer

type ActionButtonKind = enum
    Free,
    Boost,
    Expired

type BoostersSidePanel* = ref object of GUIModule
    expPanel: SidePanleProxy
    incPanel: SidePanleProxy
    tpPanel:  SidePanleProxy
    feature: Feature
    gs: GameScene
    onFeatureUpdate: proc()
    onClickAnywhere*: proc()

proc setupTimerState(spp:SidePanleProxy, expire: float) =
    spp.bttnBlueNode.enabled = false
    spp.bttnGreenNode.enabled = false
    spp.bttnRedNode.enabled = false
    spp.stateActiveNode.enabled = false

    spp.stateTimerNode.enabled = true
    spp.stateTimerNode.findNode("timer_back").colorSegmentsForNode(TimerBackColorConf)
    spp.stateTimerNode.findNode("timer_back_outline").getComponent(ColorFill).color = TIMER_BACK_STROKE_COLOR
    spp.timer.timeToEnd = expire

proc setupActiveState(spp:SidePanleProxy) =
    spp.stateTimerNode.enabled = false
    spp.bttnBlueNode.enabled = false
    spp.bttnRedNode.enabled = false
    spp.bttnGreenNode.enabled = false

    spp.stateActiveNode.enabled = true
    spp.stateActiveNode.findNode("active_back").colorSegmentsForNode(ActiveBackColorConf)
    spp.stateActiveText.text = localizedString("BOOSTER_BTTN_ACTIVATE")

proc setupBttn(spp:SidePanleProxy, abk:ActionButtonKind) =
    spp.stateActiveNode.enabled = false
    spp.stateTimerNode.enabled = false

    spp.bttnBlueNode.enabled        = abk == Free
    spp.bttnGreenNode.enabled       = abk == Boost or abk == Expired
    spp.bttnRedNode.enabled         = false

proc setupPanelWithBoosterData(bsp:BoostersSidePanel, spp:SidePanleProxy, bd: BoosterData) =
    if not spp.activeSwitchTimer.isNil:
        spp.activeSwitchTimer.clear()
        spp.activeSwitchTimer = nil

    if not bd.isNil and bd.isActive:
        if timeLeft(bd.expirationTime) > SECONDS_IN_DAY:
            spp.setupActiveState()
            spp.activeSwitchTimer = setTimeout(timeLeft(bd.expirationTime) - SECONDS_IN_DAY, proc() = bsp.onFeatureUpdate())
        else:
            spp.setupTimerState(bd.expirationTime)
    else:
        var abk = ActionButtonKind.Boost
        if not bd.isNil and bd.durationTime > 0.0 and bd.isFree:
            abk = ActionButtonKind.Free
        if not bd.isNil and bd.expirationTime > 0.0 and timeLeft(bd.expirationTime) > (-SECONDS_FOR_EXPIRE).float:
            abk = ActionButtonKind.Expired
        spp.setupBttn(abk)


proc createPanelProxy(bsp:BoostersSidePanel, rootNodeName, iconName, multiplierText:string, yOffset: float = 0.0): SidePanleProxy =
    result = SidePanleProxy.new(newLocalizedNodeWithResource("common/gui/ui2_0/boosters_panel/boosters_panel"))
    result.node.name = rootNodeName
    result.multiplierText.text = multiplierText
    result.multiplierText.fontSize = MULTIPLIER_FONT_SIZE
    result.setupBttn(ActionButtonKind.Boost)
    result.node.positionY = result.node.positionY + yOffset
    discard result.iconNode.addRewardIcon(iconName)
    let r = result
    result.blueBttn.onAction do():
        if not r.onPanelClick.isNil:
            r.onPanelClick()

    result.greenBttn.onAction do():
        if not r.onPanelClick.isNil:
            r.onPanelClick()

    result.redBttn.onAction do():
        if not r.onPanelClick.isNil:
            r.onPanelClick()

    result.stateActiveNode.createButtonComponent(BUTTON_RECT).onAction do():
        if not r.onPanelClick.isNil:
            r.onPanelClick()
    result.stateTimerNode.createButtonComponent(BUTTON_RECT).onAction do():
        if not r.onPanelClick.isNil:
            r.onPanelClick()

    result.timer.onComplete do():
        if not bsp.feature.isNil:
            bsp.onFeatureUpdate()

    result.bttnBlueText.text = localizedString("BOOSTER_BTTN_FREE")
    result.bttnGreenText.text = localizedString("BOOSTER_BTTN_BOOST")
    result.bttnRedText.text = localizedString("BOOSTER_BTTN_EXPIRED")

proc showIfHidden(bsp:BoostersSidePanel) =
    if not bsp.rootNode.enabled:
        bsp.rootNode.enabled = true
        bsp.rootNode.show(0.3)

proc createBoostersPanel*(parent: Node): BoostersSidePanel =
    result.new()
    result.rootNode = newNode()
    result.rootNode.name = "boosters_panel"
    parent.insertChild(result.rootNode, 0)
    result.moduleType = mtBoostersPanel
    result.rootNode.enabled = false
    result.rootNode.alpha = 0.0

    result.expPanel = result.createPanelProxy("expPanel","boosterExp",boostMultiplierText(btExperience))
    result.rootNode.addChild(result.expPanel.node)

    result.tpPanel = result.createPanelProxy("tpPanel","boosterTourPoints",boostMultiplierText(btTournamentPoints), OFFSET_Y)
    result.rootNode.addChild(result.tpPanel.node)

    result.incPanel = result.createPanelProxy("incPanel","boosterIncome",boostMultiplierText(btIncome), OFFSET_Y*2)
    result.rootNode.addChild(result.incPanel.node)

    let p = result

    result.tpPanel.onPanelClick = proc() =
                        if not p.onClickAnywhere.isNil:
                            p.onClickAnywhere()

    result.expPanel.onPanelClick = proc() =
                        if not p.onClickAnywhere.isNil:
                            p.onClickAnywhere()

    result.incPanel.onPanelClick = proc() =
                        if not p.onClickAnywhere.isNil:
                            p.onClickAnywhere()

    let feature = findFeature(BoosterFeature)
    let onFeatureUpdate = proc() =
        if feature.kind.isFeatureEnabled:
            p.showIfHidden()
        var tbBooster:BoosterData = nil
        var expBooster:BoosterData = nil
        var incBooster:BoosterData = nil

        for booster in feature.boosters:
            let b = booster
            case booster.kind
            of btTournamentPoints:
                tbBooster = b
            of btExperience:
                expBooster = b
            of btIncome:
                incBooster = b

        p.setupPanelWithBoosterData(p.tpPanel, tbBooster)
        p.setupPanelWithBoosterData(p.expPanel, expBooster)
        p.setupPanelWithBoosterData(p.incPanel, incBooster)

    result.feature = feature
    result.gs = parent.sceneView.GameScene
    result.onFeatureUpdate = onFeatureUpdate

    feature.subscribe(parent.sceneView.GameScene, onFeatureUpdate)
    onFeatureUpdate()

method onRemoved*(bsp: BoostersSidePanel) =
    if not bsp.feature.isNil:
        bsp.feature.unsubscribe(bsp.gs, bsp.onFeatureUpdate)
        bsp.feature = nil

    if not bsp.tpPanel.activeSwitchTimer.isNil:
        bsp.tpPanel.activeSwitchTimer.clear()
        bsp.tpPanel.activeSwitchTimer = nil

    if not bsp.expPanel.activeSwitchTimer.isNil:
        bsp.expPanel.activeSwitchTimer.clear()
        bsp.expPanel.activeSwitchTimer = nil

    if not bsp.incPanel.activeSwitchTimer.isNil:
        bsp.incPanel.activeSwitchTimer.clear()
        bsp.incPanel.activeSwitchTimer = nil

