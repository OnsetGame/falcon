import rod.node
import rod.component
import rod.component.text_component
import shared.paytable_general
import core.slot.base_slot_machine_view
import shared.localization_manager
import strutils
import witch_slot_view

type WitchPaytable* = ref object of PaytableGeneral

method onInit*(pt: WitchPaytable) =
    procCall pt.PaytableGeneral.onInit()
    let v = pt.rootNode.sceneView.WitchSlotView

    for i in 1..6:
        pt.addSlide("slots/witch_slot/paytable/precomps/slide_" & $i)

    pt.slides[1].childNamed("witch_paytable_scatter_text_1").component(Text).text = localizedString("witch_paytable_scatter_text_1").format(v.pd.freespinsAllCount)
    pt.slides[1].childNamed("witch_x_free_spins").component(Text).text = localizedString("witch_x_free_spins").format(v.pd.freespinsAllCount)

    pt.addSlide("common/gui/paytable/precomps/slide_paylines_1")
    pt.fillPaylinesSlide(6, v.lines[0..9], $v.buildingId())
    pt.setPaylinesSlideNumbers(6, 1, 10)
    pt.setPaylinesSlideDesc(6, "PAYTABLE_LEFT_TO_RIGHT")

    pt.addSlide("common/gui/paytable/precomps/slide_paylines_1")
    pt.fillPaylinesSlide(7, v.lines[10..19], $v.buildingId())
    pt.setPaylinesSlideNumbers(7, 11, 20)
    pt.setPaylinesSlideDesc(7, "PAYTABLE_LEFT_TO_RIGHT")

    if v.pd.paytableSeq.len != 0:
        for i in 0..v.pd.paytableSeq.len - 2:
            for num in 2..v.pd.paytableSeq[i].high:
                pt.slides[0].childNamed($i & "_" & $num & "_@noloc").component(Text).text = $v.pd.paytableSeq[i][num]

    if v.pd.bonusElementsPaytable.len != 0:
        for i in 0..v.pd.bonusElementsPaytable.high:
            for j in 0..v.pd.bonusElementsPaytable[i].high:
                pt.slides[4].childNamed($i & "_" & $j & "_@noloc").component(Text).text = $v.pd.bonusElementsPaytable[i][j]


registerComponent(WitchPaytable, "paytable")
