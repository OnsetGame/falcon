import nimx.types
import nimx.matrixes
import rod.node
import rod.component
import rod.component.text_component
import shared.paytable_general
import strutils
import falconserver.slot.machine_base_types
import core.slot.base_slot_machine_view
import ufo_types

type UfoPaytable* = ref object of PaytableGeneral

method onInit*(pt: UfoPaytable) =
    procCall pt.PaytableGeneral.onInit()
    let v = pt.rootNode.sceneView.UfoSlotView

    for i in 1..5:
        pt.addSlide("slots/ufo_slot/paytable/precomps/slide_" & $i)

    pt.addSlide("common/gui/paytable/precomps/slide_paylines_1")
    pt.fillPaylinesSlide(5, v.lines[0..9], $v.buildingId())
    pt.setPaylinesSlideNumbers(5, 1, 10)
    pt.setPaylinesSlideDesc(5, "PAYTABLE_BOTH_DIR_TEXT")

    if v.sd.paytableSeq.len != 0:
        for i in 0..v.sd.paytableSeq.len - 2:
            for num in 3..v.sd.paytableSeq[i].high:
                pt.slides[0].childNamed($i & "_" & $num & "_@noloc").component(Text).text = $v.sd.paytableSeq[i][num]

        var text1 = pt.slides[2].childNamed("ufo_paytable_free_spins_text_1").component(Text)
        var text2 = pt.slides[2].childNamed("ufo_paytable_free_spins_text_2").component(Text)

        text1.text = text1.text % [$v.sd.freespinsAllCount]
        text2.text = text2.text % [$v.sd.freespinsAdditionalCount]


registerComponent(UfoPaytable, "paytable")
