import rod.node
import rod.component
import rod.component.text_component
import shared.paytable_general
import shared.localization_manager
import core.slot.base_slot_machine_view
import candy_slot_view
import strutils

type CandyPaytable* = ref object of PaytableGeneral


method onInit*(pt: CandyPaytable) =
    procCall pt.PaytableGeneral.onInit()
    let v = pt.rootNode.sceneView.CandySlotView

    for i in 1..5:
        pt.addSlide("slots/candy_slot/paytable/precomps/slide_" & $i)

    pt.addSlide("common/gui/paytable/precomps/slide_paylines_1")
    pt.fillPaylinesSlide(5, v.lines[0..9], $v.buildingId())
    pt.setPaylinesSlideNumbers(5, 1, 10)
    pt.setPaylinesSlideDesc(5, "PAYTABLE_LEFT_TO_RIGHT")

    pt.addSlide("common/gui/paytable/precomps/slide_paylines_1")
    pt.fillPaylinesSlide(6, v.lines[10..19], $v.buildingId())
    pt.setPaylinesSlideNumbers(6, 11, 20)
    pt.setPaylinesSlideDesc(6, "PAYTABLE_LEFT_TO_RIGHT")

    pt.slides[1].childNamed("candy_paytable_text_4").component(Text).text = localizedString("candy_paytable_text_4").format(v.pd.freespinsAllCount)
    if v.pd.paytableSeq.len != 0:
        for i in 0..v.pd.paytableSeq.len - 2:
            for num in 3..v.pd.paytableSeq[i].high:
                pt.slides[0].childNamed($i & "_" & $num & "_@noloc").component(Text).text = $v.pd.paytableSeq[i][num]

    for i in 0..2:
        pt.slides[0].childNamed($i & "_11_@noloc").component(Text).text = $v.pd.paytableSeq[i][0]

registerComponent(CandyPaytable, "paytable")
