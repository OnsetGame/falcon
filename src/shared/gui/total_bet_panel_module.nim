import rod.node
import rod.component
import rod.component.text_component
import rod.component.ui_component

import nimx.types
import nimx.matrixes
import nimx.animation

import gui_module
import gui_module_types
import shared.window.button_component

import core / flow / [flow, flow_state_types]

type TotalBetPanelModule* = ref object of GUIModule
    buttonMinus*: ButtonComponent
    buttonPlus*: ButtonComponent
    count*: int
    countText: Text
    enabled: bool

proc showLock*(tbp: TotalBetPanelModule, show: bool) =
    tbp.rootNode.findNode("lock_shape_plus").alpha = show.float

proc createTotalBetPanel*(parent: Node): TotalBetPanelModule =
    result.new()
    result.rootNode = newLocalizedNodeWithResource("common/gui/ui2_0/total_bet_panel")
    parent.addChild(result.rootNode)
    result.moduleType = mtTotalBetPanel
    result.countText = result.rootNode.findNode("bet_value_text").component(Text)
    result.showLock(false)
    result.enabled = true

    let minusAnim = result.rootNode.animationNamed("minus")
    result.buttonMinus = result.rootNode.findNode("minus_button").createButtonComponent(minusAnim, newRect(0.0, 0.0, 150.0, 107.0))

    let plusAnim = result.rootNode.animationNamed("plus")
    result.buttonPlus = result.rootNode.findNode("plus_button").createButtonComponent(plusAnim, newRect(0.0, 0.0, 150.0, 107.0))

proc setBetCount*(tbp: TotalBetPanelModule, count: int) =
    tbp.count = count
    let st = findActiveState(SlotFlowState).SlotFlowState
    if not st.isNil:
        st.currentBet = count
    tbp.countText.text = formatThousands(count)

proc enableButton(tbp: TotalBetPanelModule, anim: Animation, enabled: bool) =
    if enabled:
        anim.loopPattern = lpEndToStart
    else:
        anim.loopPattern = lpStartToEnd
    tbp.rootNode.addAnimation(anim)

proc `plusEnabled=`*(tbp: TotalBetPanelModule, enabled: bool) =
    if tbp.buttonPlus.enabled != enabled:
        let anim = tbp.rootNode.findNode("plus_button").animationNamed("disable")

        tbp.buttonPlus.enabled = enabled
        tbp.enableButton(anim, enabled)

proc `minusEnabled=`*(tbp: TotalBetPanelModule, enabled: bool) =
    if tbp.buttonMinus.enabled != enabled:
        let anim = tbp.rootNode.findNode("minus_button").animationNamed("disable")

        tbp.buttonMinus.enabled = enabled
        tbp.enableButton(anim, enabled)

