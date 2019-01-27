import rod / [ node, viewport ]
import nimx / [ types, matrixes, view ]
import core.slot.base_slot_machine_view
import test_utils
import core.slot.states / [ slot_states ]
import core.flow.flow
import core.components.bitmap_text
import slots.card.card_slot_view
import shared.window.button_component

uiTest cardTest:
    waitUntil(mapLoaded(), waitUntilSceneLoaded)
    startSlot(cardSlot)
    waitUntil(slotLoaded(), waitUntilSceneLoaded)

    ## regular spin
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

    ## freespins hidden
    slotView.onSpinClick()
    waitUntil(nodeExists("Bonus Choose"))

    waitUntil(nodeExists("buttonNode1") and nodeExists("buttonNode2") and nodeExists("buttonNode3"))

    slotView.rootNode.findNode("buttonNode1").getComponent(ButtonComponent).sendAction()
    waitUntil(not slotView.CardSlotView.winDialogWindow.isNil and slotView.CardSlotView.winDialogWindow.readyForClose)
    clickScreen()
    waitUntil(slotView.userCanStartSpin(), waitUntilSpinState)

    ## freespins multiplier
    slotView.onSpinClick()
    waitUntil(nodeExists("buttonNode1") and nodeExists("buttonNode2") and nodeExists("buttonNode3"))

    slotView.rootNode.findNode("buttonNode2").getComponent(ButtonComponent).sendAction()
    waitUntil(not slotView.CardSlotView.winDialogWindow.isNil and slotView.CardSlotView.winDialogWindow.readyForClose)
    clickScreen()
    waitUntil(slotView.userCanStartSpin(), waitUntilSpinState)

    ## freespins shuffle
    slotView.onSpinClick()
    waitUntil(nodeExists("buttonNode1") and nodeExists("buttonNode2") and nodeExists("buttonNode3"))

    slotView.rootNode.findNode("buttonNode3").getComponent(ButtonComponent).sendAction()
    waitUntil(not slotView.CardSlotView.winDialogWindow.isNil and slotView.CardSlotView.winDialogWindow.readyForClose)
    clickScreen()
    waitUntil(slotView.userCanStartSpin(), waitUntilSpinState)

    loadMap()

registerTest(cardTest)