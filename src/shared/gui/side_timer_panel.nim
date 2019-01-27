import nimx / [ types, animation, matrixes, timer, app, event ]
import core / notification_center
import rod / [ node, viewport, component ]
import rod / component / [text_component, ae_composition, vector_shape]
import rod / utils / text_helpers
import shared / window / [ button_component, window_manager ]
import shared / [ director, game_flow ]
import utils / [ helpers, timesync, icon_component ]
import strutils, times, tables, logging
import gui_module, gui_module_types
import node_proxy / proxy
import core / components / timer_component
import core / helpers / color_segments_helper
import core / flow / flow_state_types

const MAX_TIMERS = 3
const Y_OFFSET = 160.0
const MOVE_TIME = 0.3

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

const BucksColorConf = (
        color: newColorB(28,103,53),
        stroke: newColorB(35,125,65)
    )

const EnergyColorConf = (
        color: fromHexColor("47bfd9ff"),
        stroke: fromHexColor("53e0ffff")
    )

nodeProxy SideTimerProxy:
    timerTextNode* Node {withName: "timer_text"}
    timer* TextTimerComponent {onNodeAdd: timerTextNode}
    comps* AEComposition {onNode: node}
    iconNode* Node {withName: "reward_icon_placeholder"}
    promoText* Text {onNode: "promo_text"}
    timerBackNode* Node {withName: "timer_back"}
    promoBackShape* VectorShape {onNode: "offer_ph_in"}
    actionBttn ButtonComponent {withValue: np.node.findNode("reward_icon_placeholder").createButtonComponent(newRect(0.0, 0.0, 300.0, 115.0))}
    visible bool
    bid string
    posIndex int
    minimized bool
    shineAnim Animation

type SideTimerPanel* = ref object of GUIModule
    proxyTimers: seq[SideTimerProxy]
    visible: bool
    hasAnyClickHandler: bool

proc show(spp:SideTimerProxy, onShowComplete: proc()) =
    if not spp.visible:
        spp.node.positionY = spp.posIndex.Coord * Y_OFFSET
        let showAnim = spp.comps.play("in")
        showAnim.onComplete do():
            spp.visible = true
            if not onShowComplete.isNil:
                onShowComplete()

proc hide(spp:SideTimerProxy, callback:proc() = nil) =
    if spp.visible:
        spp.visible = false
        let hideAnim = spp.comps.play("in")
        hideAnim.loopPattern = lpEndToStart
        hideAnim.onComplete do():
            if not callback.isNil:
                callback()

        if not spp.shineAnim.isNil:
            spp.shineAnim.cancel()
            spp.shineAnim = nil

proc updateTimersPos(panel: SideTimerPanel) =
    for i,pt in panel.proxyTimers:
        if pt.posIndex != i:
            let initPos = pt.node.position
            let destPos = newVector3(initPos.x, 0.0 + Y_OFFSET*i.Coord)
            pt.node.moveTo(destPos, MOVE_TIME)
            pt.posIndex = i

proc deleteAtPos*(panel: SideTimerPanel, posIndex:int) =
    if posIndex < 0 or posIndex >= MAX_TIMERS:
        return
    let proxyAtPos = panel.proxyTimers[posIndex]
    if proxyAtPos.posIndex != posIndex:
        warn "Trying to remove wrong timer!"
        return

    proxyAtPos.node.removeFromParent()
    panel.proxyTimers.delete(posIndex)
    panel.updateTimersPos()

proc applyCustomColors(timerProxy: SideTimerProxy, colors:string) =
    #Expected colors in hex in following order: [text color] [BG color] [BG stroke color]
    let colorsHexSet = colors.split()
    if colorsHexSet.len >= 3:
        let textHexColor = colorsHexSet[0]
        let bgHexColor = colorsHexSet[1]
        let bgStrokeHexColor = colorsHexSet[2]
        if textHexColor.len == 8:
            timerProxy.promoText.color = fromHexColor(textHexColor)
        if bgHexColor.len == 8:
            timerProxy.promoBackShape.color = fromHexColor(bgHexColor)
        if bgStrokeHexColor.len == 8:
            timerProxy.promoBackShape.strokeColor = fromHexColor(bgStrokeHexColor)

proc minimizeAll(panel: SideTimerPanel) =
    for pt in panel.proxyTimers:
        closureScope:
            let cachedPt = pt

            if not cachedPt.minimized and cachedPt.visible:
                cachedPt.minimized = true
                let minimizeAnim = cachedPt.comps.play("minimize")
                minimizeAnim.onComplete do():
                    if cachedPt.shineAnim.isNil:
                        cachedPt.shineAnim = cachedPt.comps.play("shine")
                        cachedPt.shineAnim.loopDuration = 2.0
                        cachedPt.shineAnim.numberOfLoops = -1

proc addAnyClickHandler(panel: SideTimerPanel) =
    panel.hasAnyClickHandler = true
    mainApplication().pushEventFilter do(e: var Event, control: var EventFilterControl) -> bool:
        result = false

        if e.buttonState == bsDown:
            control = efcBreak
            panel.minimizeAll()
            panel.hasAnyClickHandler = false

proc addTimer*(panel: SideTimerPanel, sod: SpecialOfferData) =
    let nextPosIndex = panel.proxyTimers.len
    if nextPosIndex >= MAX_TIMERS:
        warn "Max offers timers ", MAX_TIMERS, " already shown. Couldn't add timer for offer ", sod.bid
        return

    for t in panel.proxyTimers:
        if t.bid == sod.bid:
            warn "Timer for offer " & t.bid & " exists!"
            return

    let offerProxy = SideTimerProxy.new(newLocalizedNodeWithResource("common/gui/ui2_0/offer_side_panel"))
    panel.rootNode.addChild(offerProxy.node)

    offerProxy.bid = sod.bid
    offerProxy.posIndex = nextPosIndex
    let bundle = getPurchaseHelper().productBundles()[offerProxy.bid]
    #bundle.products = @[ProductItem(currencyType: Bucks,amount: 2600)]
    #bundle.promoText = "60% OFF"
    let currencyType = bundle.products[0].currencyType

    offerProxy.timer.timeToEnd = sod.expires
    offerProxy.timer.onComplete do():
        offerProxy.hide(proc() = panel.deleteAtPos(offerProxy.posIndex))

    offerProxy.iconNode.addCurrencyIcon($currencyType)
    offerProxy.promoText.text = bundle.sideText
    offerProxy.timerBackNode.colorSegmentsForNode(TimerBackColorConf)

    offerProxy.setupPromoBack(currencyType)

    if bundle.sideColors.len > 0:
        offerProxy.applyCustomColors(bundle.sideColors)

    offerProxy.actionBttn.onAction do():
        if offerProxy.visible:
            if offerProxy.timer.timeToEnd > 1.0:
                let state = newFlowState(OfferFromTimerFlowState)
                state.sod = sod
                state.source = currentDirector().currentScene.name
                pushBack(state)

            offerProxy.hide(proc() = panel.deleteAtPos(offerProxy.posIndex))

    let onShowComplete = proc() =
        if not panel.hasAnyClickHandler:
            panel.addAnyClickHandler()

    offerProxy.show(onShowComplete)
    panel.proxyTimers.add(offerProxy)



proc createSidePanel*(parent: Node): SideTimerPanel =
    result.new()
    result.rootNode = newNode()
    result.rootNode.name = "side_timer_panel"
    parent.insertChild(result.rootNode, 0)
    result.moduleType = mtSidePanel
    result.proxyTimers = @[]
