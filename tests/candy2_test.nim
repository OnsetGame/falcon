import rod / [ node, viewport ]
import nimx / [ types, matrixes, view ]
import core.slot.base_slot_machine_view
import test_utils
import core.slot.states / [ slot_states ]
import core.flow.flow
import core.components.bitmap_text
import slots.candy2.candy2_slot_view
import shared.win_popup

proc findBoxButton(name: string): Point =
    let wp = slotView.rootNode.findNode(name).localToWorld(newVector3(200, 200, 0))
    let sp = slotView.worldToScreenPoint(wp)
    newPoint(sp.x, sp.y)

proc getBox*(indx: int): Point =
    let boxName = "box" & $indx
    findBoxButton(boxName)

uiTest candy2Test:
    waitUntil(mapLoaded(), waitUntilSceneLoaded)

    startSlot(candySlot2)
    waitUntil(slotLoaded(), waitUntilSceneLoaded)

    # regular spin
    waitUntil(slotView.slotGUI.spinButtonModule.button.enabled)
    waitUntil(findFlowState(SlotRoundState).isNil, waitUntilSpinState)
    slotView.onSpinClick()
    waitUntil(slotView.userCanStartSpin(), waitUntilSpinState)

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
    waitUntil(slotView.userCanStartSpin(), waitUntilSpinState)

    ## bonus
    slotView.onSpinClick()
    waitUntil(slotView.Candy2SlotView.bonusReady == true)
    pressButton(getBox(2))
    waitUntil(slotView.Candy2SlotView.bonusBusy == false)
    pressButton(getBox(5))
    waitUntil(slotView.Candy2SlotView.bonusBusy == false)
    pressButton(getBox(7))
    waitUntil(slotView.Candy2SlotView.bonusBusy == false)
    pressButton(getBox(9))
    waitUntil(not slotView.Candy2SlotView.winDialogWindow.isNil and slotView.Candy2SlotView.winDialogWindow.readyForClose)
    clickScreen()

    ## freespins
    waitUntil(slotView.userCanStartSpin(), waitUntilSpinState)
    slotView.onSpinClick()
    waitUntil(not slotView.Candy2SlotView.winDialogWindow.isNil and slotView.Candy2SlotView.winDialogWindow.readyForClose)
    clickScreen()
    loadMap()

registerTest(candy2Test)