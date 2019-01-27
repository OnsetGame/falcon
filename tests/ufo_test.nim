import rod / [ node, viewport ]
import nimx / [ types, matrixes, view, timer ]
import core.slot.base_slot_machine_view
import test_utils

const maxWaitTries = 1500

proc getBttnPos(firstNd, secondNd: string): Point =
    let bttnNd = slotView.rootNode.findNode(firstNd).findNode(secondNd)
    let sp = slotView.worldToScreenPoint(bttnNd.worldPos)
    result = newPoint(sp.x + 10, sp.y + 10)

uiTest ufoTest:
    waitUntil(mapLoaded(), waitUntilSceneLoaded)
    startSlot(ufoSlot)

    waitUntil(slotLoaded(), waitUntilSceneLoaded)
    waitUntil(nodeExists("main_scene_anchor") and (not slotView.soundManager.isNil))
    waitUntil(slotView.actionButtonState == SpinButtonState.Spin, waitUntilSpinState)
    slotView.onSpinClick()

    let pos = slotView.worldToScreenPoint(slotView.rootNode.findNode("gui_parent").findNode("spin_button").worldPos)
    let bttnNdPos = newPoint(pos.x + 10, pos.y + 10)
    let t = setInterval(0.1) do():
        if not slotView.isNil:
            pressButton(bttnNdPos)

    waitUntil(nodeExists("play_button.png"), maxWaitTries)
    pressButton(getBttnPos("bonus_intro", "play_button.png"))

    waitUntil((not slotView.rootNode.findNode("bonus_scene").enabled), maxWaitTries)
    waitUntil(nodeExists("branding_not_bonus"), maxWaitTries)
    waitUntil(slotView.rootNode.findNode("branding_not_bonus").alpha == 1.0, maxWaitTries)
    waitUntil(nodeExists("free_and_bonus_results") and slotView.rootNode.findNode("free_and_bonus_results").alpha == 1.0, maxWaitTries)
    waitUntil((not nodeExists("branding_not_bonus")), maxWaitTries)

    t.pause()
    t.clear()

    waitUntil(slotView.actionButtonState == SpinButtonState.Spin, maxWaitTries)
    pressButton(bttnNdPos)

    waitUntil(slotView.actionButtonState == SpinButtonState.Spin, maxWaitTries)
    loadMap()

registerTest(ufoTest)
