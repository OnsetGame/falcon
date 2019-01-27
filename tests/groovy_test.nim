import rod / [ node, viewport ]
import nimx / [ types, matrixes, view, timer ]
import core.slot.base_slot_machine_view
import test_utils
import core.slot.states / [ slot_states ]
import core.flow.flow
import core.components.bitmap_text
const maxWaitTries = 500
uiTest groovyTest:
    waitUntil(mapLoaded(), waitUntilSceneLoaded)
    startSlot(groovySlot)
    waitUntil(slotLoaded(), waitUntilSceneLoaded)
    waitUntil(nodeExists("scene_anchor") and (not slotView.soundManager.isNil))
    waitUntil(findFlowState(SlotRoundState).isNil, waitUntilSpinState)

    slotView.onSpinClick()

    waitUntil(nodeExists("line_sprite"))
    slotView.onSpinClick()
    waitUntil(not nodeExists("line_sprite"))

    waitUntil(nodeExists("big_win"))
    waitUntil(not slotView.rootNode.findNode("big_win").findNode("counter").isNil)
    proc cond(): bool =
        if not findFlowState(MultiWinState).isNil and findFlowState(MultiWinState).SpecialWinState.amount > 0: return true
    waitUntil(cond())
    waitUntil(slotView.rootNode.findNode("big_win").findNode("counter").getComponent(BmFont).text == $findFlowState(MultiWinState).SpecialWinState.amount)
    slotView.onSpinClick()
    waitUntil(not nodeExists("big_win"))

    waitUntil(nodeExists("line_sprite"))
    slotView.onSpinClick()
    waitUntil(not nodeExists("line_sprite"))

    waitUntil(nodeExists("big_win"))
    waitUntil(not slotView.rootNode.findNode("big_win").findNode("counter").isNil)
    waitUntil(cond())
    waitUntil(slotView.rootNode.findNode("big_win").findNode("counter").getComponent(BmFont).text == $findFlowState(MultiWinState).SpecialWinState.amount)
    slotView.onSpinClick()
    waitUntil(not nodeExists("big_win"))

    waitUntil(nodeExists("line_sprite"))
    slotView.onSpinClick()
    waitUntil(not nodeExists("line_sprite"))

    waitUntil(nodeExists("big_win"))
    waitUntil(not slotView.rootNode.findNode("big_win").findNode("counter").isNil)
    waitUntil(cond())
    waitUntil(slotView.rootNode.findNode("big_win").findNode("counter").getComponent(BmFont).text == $findFlowState(MultiWinState).SpecialWinState.amount)
    slotView.onSpinClick()
    waitUntil(not nodeExists("big_win"))

    waitUntil(nodeExists("line_sprite"))
    slotView.onSpinClick()
    waitUntil(not nodeExists("line_sprite"))

    waitUntil(nodeExists("mega_win"))
    waitUntil(not slotView.rootNode.findNode("mega_win").findNode("counter").isNil)
    waitUntil(cond())
    waitUntil(slotView.rootNode.findNode("mega_win").findNode("counter").getComponent(BmFont).text == $findFlowState(MultiWinState).SpecialWinState.amount)
    slotView.onSpinClick()
    waitUntil(not nodeExists("big_win"))

    waitUntil(findFlowState(SlotRoundState).isNil, maxWaitTries)
    loadMap()

registerTest(groovyTest)
