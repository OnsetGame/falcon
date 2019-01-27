import nimx / [ matrixes, button ]
import rod / [ node, viewport ]
import rod.component.ui_component
import rod.component.color_balance_hls
import test_utils
import core.slot.base_slot_machine_view
import shared.window.button_component
import slots.witch.witch_slot_view

proc getBonusSpinButton*(): Point =
    let spn = slotView.rootNode.findNode("witch_spin_bonus").localToWorld(newVector3(10, 10))
    let sp = slotView.worldToScreenPoint(spn)
    result = newPoint(sp.x, sp.y)

proc checkNewBonusRound(): bool =
    return slotView.WitchSlotView.canSpinBonus == true

proc canCloseWinPopup(): bool =
    let popup = slotView.WitchSlotView.winDialogWindow
    return not popup.isNil and popup.readyForClose == true and not slotView.rootNode.findNode("result_screen").isNil

proc isReadyForNextSpin(): bool =
    let state = slotView.actionButtonState == SpinButtonState.Spin
    let gotLastField = slotView.lastField.len > 0
    return state and gotLastField

uiTest witchTest:
    waitUntil(mapLoaded(), waitUntilSceneLoaded)
    startSLot(witchSlot)

    waitUntil(slotLoaded(), waitUntilSceneLoaded)
    waitUntil(slotView.actionButtonState == SpinButtonState.Spin and slotView.slotGUI.spinButtonModule.button.enabled == true, waitUntilSpinState)

    ## paytable
    pressButton(getDropDownMenu())
    discard
    waitUntil(findPaytableButton().enabled == true, 15)
    discard
    pressButton(getPaytableBtn())
    waitUntil(nodeExists("slides_anchor"))
    discard
    clickPaytableBtn(true)
    discard
    clickPaytableBtn(true)
    discard
    clickPaytableBtn(true)
    discard
    clickPaytableBtn(true)
    discard
    clickPaytableBtn(false)
    discard
    clickPaytableBtn(false)
    discard
    clickPaytableBtn(false)
    discard
    pressButton(findButton("new_close.png"))
    waitUntil(paytableNotClosed())
    waitUntil(slotView.actionButtonState == SpinButtonState.Spin and slotView.slotGUI.spinButtonModule.button.enabled == true, waitUntilSpinState)


    # regular spin
    slotView.slotGUI.spinButtonModule.button.sendAction()
    waitUntil(isReadyForNextSpin(), waitUntilSpinState)

    ## bonus spin
    slotView.slotGUI.spinButtonModule.button.sendAction()
    waitUntil(isReadyForNextSpin(), waitUntilSpinState)
    slotView.slotGUI.spinButtonModule.button.sendAction()
    waitUntil(isReadyForNextSpin(), waitUntilSpinState)
    slotView.slotGUI.spinButtonModule.button.sendAction()
    waitUntil(isReadyForNextSpin(), waitUntilSpinState)
    discard
    slotView.slotGUI.spinButtonModule.button.sendAction()
    discard
    waitUntil(nodeExists("bonus_button.png"))
    slotView.rootNode.findNode("start_button_parent").getComponent(UIComponent).view.Button.sendAction()
    waitUntil(checkNewBonusRound())
    pressButton(getBonusSpinButton())
    waitUntil(checkNewBonusRound())
    pressButton(getBonusSpinButton())
    waitUntil(checkNewBonusRound())
    pressButton(getBonusSpinButton())
    waitUntil(checkNewBonusRound())
    pressButton(getBonusSpinButton())
    waitUntil(canCloseWinPopup())
    pressButton(getSpinButton())
    waitUntil(slotView.actionButtonState == SpinButtonState.Spin, waitUntilSpinState)

    ## spin freespin
    slotView.slotGUI.spinButtonModule.button.sendAction()
    waitUntil(canCloseWinPopup())
    pressButton(getSpinButton())
    waitUntil(slotView.actionButtonState == SpinButtonState.Spin and slotView.slotGUI.spinButtonModule.button.enabled == true, waitUntilSpinState)
    # pressButton(getMapButton())
    discard
    loadMap()
    discard

registerTest(witchTest)
