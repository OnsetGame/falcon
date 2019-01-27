import slot_machine_registry
import shared / window / window_manager
export BuildingId

import candy / [candy_slot_view, candy_paytable]
method showPaytable*(v: CandySlotView) =
    discard sharedWindowManager().show(CandyPaytable)
registerSlot(candySlot, CandySlotView)

import eiffel / [eiffel_slot_view, eiffel_paytable]
method showPaytable*(v: EiffelSlotView) =
    discard sharedWindowManager().show(EiffelPaytable)
registerSlot(dreamTowerSlot, EiffelSlotView)

import mermaid / [mermaid_slot_view, mermaid_paytable]
method showPaytable(v: MermaidMachineView) =
    discard sharedWindowManager().show(MermaidPaytable)
registerSlot(mermaidSlot, MermaidMachineView)

import balloon / [balloon_slot_view, balloon_paytable]
method showPaytable*(v: BalloonSlotView) =
    discard sharedWindowManager().show("BalloonPaytable")
registerSlot(balloonSlot, BalloonSlotView)

import ufo / [ufo_types, ufo_slot_view, ufo_paytable]
method showPaytable(v: UfoSlotView) =
    discard sharedWindowManager().show(UfoPaytable)
registerSlot(ufoSlot, UfoSlotView)

import witch / [witch_slot_view, witch_paytable]
method showPaytable(v: WitchSlotView) =
    discard sharedWindowManager().show(WitchPaytable)
registerSlot(witchSlot, WitchSlotView)

import candy2 / [candy2_slot_view, candy2_paytable]
method showPaytable*(v: Candy2SlotView) =
    discard sharedWindowManager().show(Candy2Paytable)
registerSlot(candySlot2, Candy2SlotView)

import groovy / [groovy_slot_view, groovy_paytable]
method showPaytable*(v: GroovySlotView) =
    discard sharedWindowManager().show(GroovyPaytable)
registerSlot(groovySlot, GroovySlotView)

import card / [ card_slot_view, card_paytable ]
method showPaytable*(v: CardSlotView) =
    discard sharedWindowManager().show(CardPaytable)
registerSlot(cardSlot, CardSlotView)

when not defined(release):
    import test.test_slot_view
    registerSlot(testSlot, TestSlotView)
