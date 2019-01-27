import nimx / [ matrixes, button ]
import rod / [ node, viewport ]
import rod.component.ui_component

import utils.game_state
import core.slot.base_slot_machine_view
import slots.candy.candy_slot_view
import slots.candy.candy_win_popup

import test_utils

proc waitBonusIntro(): bool = nodeExists("bonus_button_parent")
proc waitFreespinResultsScreen(): bool = nodeExists("freespin_res")
proc waitFreespinResultsScreenClose(): bool = not nodeExists("freespin_res")
proc winScatter(): bool =
    slotView.actionButtonState == SpinButtonState.Spin and not hasGameState("CANDY_SCATTER_FLY")

proc winPopupReadyToClose(): bool =
    CandySlotView(slotView).winDialogWindow.readyForClose

proc bonusButtonEnabled(i: int): bool =
    view(slotView.rootNode.findNode("box" & $i).findNode("bonus_button_parent").getComponent(UIComponent)).Button.enabled

proc getBox*(indx: int): Point =
    let boxName = "box" & $indx & "$AUX"
    findButton(boxName)

uiTest candyTest:
    waitUntil(mapLoaded(), waitUntilSceneLoaded)
    startSlot(candySlot)

    waitUntil(slotLoaded(), waitUntilSceneLoaded)
    waitUntil(slotView.actionButtonState == SpinButtonState.Spin and slotView.slotGUI.spinButtonModule.button.enabled == true, waitUntilSpinState)
    # regular spin
    pressButton(getSpinButton())
    waitUntil(slotView.actionButtonState == SpinButtonState.Spin, waitUntilSpinState)
    ## bonus spin
    pressButton(getSpinButton())
    waitUntil(waitBonusIntro())
    pressButton(getBox(2))
    waitUntil(bonusButtonEnabled(3))
    pressButton(getBox(3))
    waitUntil(bonusButtonEnabled(4))
    pressButton(getBox(4))
    waitUntil(nodeExists("bigwin") and slotView.rootNode.findNode("bigwin").enabled)
    clickScreen()

    ## spin freespin
    waitUntil(winScatter())
    pressButton(getSpinButton())
    waitUntil(winScatter())
    pressButton(getSpinButton())
    waitUntil(winScatter())
    pressButton(getSpinButton())
    waitUntil(winScatter())
    pressButton(getSpinButton())
    waitUntil(winScatter())
    pressButton(getSpinButton())
    waitUntil(waitFreespinResultsScreen())
    waitUntil(winPopupReadyToClose())
    clickScreen()
    waitUntil(waitFreespinResultsScreenClose())

    ## paytable
    waitUntil(slotView.actionButtonState == SpinButtonState.Spin, waitUntilSpinState)

    pressButton(getDropDownMenu())
    waitUntil(findPaytableButton().enabled == true, 15)
    pressButton(getPaytableBtn())
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
    discard
    loadMap()

registerTest(candyTest)
