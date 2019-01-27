import rod / [ node, viewport ]
import nimx / [ types, matrixes ]
import core.slot.base_slot_machine_view
import test_utils
import slots.balloon.balloon_slot_view

proc bonusCell(s: string): Point =
    let cell = slotView.rootNode.findNode(s).findNode("carriage_button")
    let sp = slotView.worldToScreenPoint(cell.worldPos)
    result = newPoint(sp.x + 10, sp.y - 10)

uiTest balloonTest:
    waitUntil(mapLoaded(), waitUntilSceneLoaded)
    startSlot(balloonSlot)

    waitUntil(slotLoaded(), waitUntilSceneLoaded)
    waitUntil(nodeExists("root") and (not slotView.soundManager.isNil))
    discard
    discard
    waitUntil(slotView.actionButtonState == SpinButtonState.Spin, waitUntilSpinState)
    # pressButton(getSpinButton())
    slotView.onSpinClick()

    waitUntil(slotView.rootNode.findNode("BonusGame_text").alpha == 1.0)
    waitUntil(nodeExists("scr_button"))

    clickScreen()

    waitUntil(slotView.rootNode.findNode("cell_6").findNode("carriage_button") != nil)

    pressButton(bonusCell("cell_6"))
    pressButton(bonusCell("cell_8"))
    pressButton(bonusCell("cell_10"))

    discard
    discard

    waitUntil(BalloonSlotView(slotView).winWindowReadyForDestroy == true)

    clickScreen()

    waitUntil(slotView.actionButtonState == SpinButtonState.Spin)

    # pressButton(getMapButton())
    slotView.onComplete()

registerTest(balloonTest)
