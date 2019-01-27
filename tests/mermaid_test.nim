import rod / [ node, viewport ]
import nimx / [ types, matrixes, view ]
import core.slot.base_slot_machine_view
import test_utils

proc getBttnPos(firstNd, secondNd: string): Point =
    let bttnNd = slotView.rootNode.findNode(firstNd).findNode(secondNd)
    let sp = slotView.worldToScreenPoint(bttnNd.worldPos)
    result = newPoint(sp.x + 10, sp.y + 10)

proc bonusRulesPos(): Point =
    result = getBttnPos("bonus_rules", "mermaid_start_text")

proc clickScreen() =
    pressButton(newPoint(slotView.frame.width/2.0, slotView.frame.height/2.0))

const maxWaitTries = 500

uiTest mermaidTest:
    waitUntil(mapLoaded(), waitUntilSceneLoaded)
    startSlot(mermaidSlot)

    waitUntil(slotLoaded(), waitUntilSceneLoaded)

    waitUntil(nodeExists("root") and (not slotView.soundManager.isNil))
    discard
    waitUntil(slotView.actionButtonState == SpinButtonState.Spin, waitUntilSpinState)

    # first spin without win
    slotView.onSpinClick()

    # second spin with bonus game
    waitUntil(slotView.actionButtonState == SpinButtonState.Spin, waitUntilSpinState)
    slotView.onSpinClick()

    discard
    # wait until bonus game rules
    waitUntil(nodeExists("bonus_rules"), maxWaitTries)
    waitUntil(nodeExists("mermaid_start_text"), maxWaitTries)
    waitUntil(slotView.rootNode.findNode("mermaid_start_text").alpha == 1.0, maxWaitTries)
    pressButton(getBttnPos("bonus_rules", "mermaid_start_text"))

    waitUntil(slotView.rootNode.findNode("bonus_game_intro").isNil, maxWaitTries)

    # click bonus chests 3 times
    discard
    pressButton(getBttnPos("Chest1", "Chest1_button"))
    pressButton(getBttnPos("Chest2", "Chest2_button"))
    pressButton(getBttnPos("Chest3", "Chest3_button"))

    discard
    # wait untill show bonusresults title
    waitUntil(nodeExists("mermaid_msg"))
    waitUntil(nodeExists("game_results"))
    discard
    waitUntil(slotView.rootNode.findNode("game_results").alpha >= 0.9)
    waitUntil(nodeExists("Ribbon"))
    waitUntil(nodeExists("num_scale_anchor"))
    waitUntil(slotView.rootNode.findNode("num_scale_anchor").scaleX >= 0.94)

    # click show title results
    discard
    clickScreen()

    # click again to skip title results
    discard
    clickScreen()

    # third spin with freespin
    waitUntil(slotView.actionButtonState == SpinButtonState.Spin, waitUntilSpinState)
    slotView.onSpinClick()

    discard
    # wait untill show freespinsresults title
    waitUntil(nodeExists("mermaid_msg"), maxWaitTries)
    waitUntil(nodeExists("game_results"), maxWaitTries)
    waitUntil(slotView.rootNode.findNode("game_results").getGlobalAlpha() >= 0.9, maxWaitTries)
    waitUntil(nodeExists("Ribbon"), maxWaitTries)
    waitUntil(nodeExists("num_scale_anchor"), maxWaitTries)
    waitUntil(slotView.rootNode.findNode("num_scale_anchor").scaleX >= 0.94, maxWaitTries)

    # click to force show title results
    discard
    clickScreen()

    # click again to skip title results
    discard
    clickScreen()

    waitUntil(slotView.actionButtonState == SpinButtonState.Spin, waitUntilSpinState)
    slotView.onComplete()

registerTest(mermaidTest)
