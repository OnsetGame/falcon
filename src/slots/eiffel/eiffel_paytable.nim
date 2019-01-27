import rod.node
import rod.component
import rod.component.text_component
import core.slot.base_slot_machine_view
import shared.paytable_general
import shared.localization_manager
import eiffel_slot_view
import strutils

type EiffelPaytable* = ref object of PaytableGeneral


method onInit*(pt: EiffelPaytable) =
    procCall pt.PaytableGeneral.onInit()
    let v = pt.rootNode.sceneView.EiffelSlotView

    pt.addSlide("slots/eiffel_slot/eiffel_paytable/precomps/slide_1")
    pt.addSlide("slots/eiffel_slot/eiffel_paytable/precomps/slide_2")
    pt.addSlide("slots/eiffel_slot/eiffel_paytable/precomps/slide_3")

    pt.addSlide("common/gui/paytable/precomps/slide_paylines_1")
    pt.fillPaylinesSlide(3, v.lines[0..9], $v.buildingId())
    pt.setPaylinesSlideNumbers(3, 1, 10)
    pt.setPaylinesSlideDesc(3, "PAYTABLE_LEFT_TO_RIGHT")

    pt.addSlide("common/gui/paytable/precomps/slide_paylines_1")
    pt.fillPaylinesSlide(4, v.lines[10..19], $v.buildingId())
    pt.setPaylinesSlideNumbers(4, 11, 20)
    pt.setPaylinesSlideDesc(4, "PAYTABLE_LEFT_TO_RIGHT")

    if v.pd.paytableSeq.len != 0:
        for i in 0..v.pd.paytableSeq.len - 1:
            for num in 3..6:
                pt.slides[0].childNamed($i & "_" & $num & "_@noloc").component(Text).text = $v.pd.paytableSeq[i][num]

        for i in 0..v.pd.paytableSeq.len - 2:
            for num in 7..v.pd.paytableSeq[i].high:
                pt.slides[0].childNamed($i & "_" & $num & "_@noloc").component(Text).text = $v.pd.paytableSeq[i][num]

        pt.slides[1].childNamed("eiffel_bonus_symbols").component(Text).text = localizedString("EIFFEL_BONUS_SYMBOLS").format(v.pd.bonusCount)
        pt.slides[1].childNamed("x5_wild").component(Text).text = $v.pd.paytableSeq[0][0]
        pt.slides[1].childNamed("x4_wild").component(Text).text = $v.pd.paytableSeq[1][0]
        pt.slides[1].childNamed("x3_wild").component(Text).text = $v.pd.paytableSeq[2][0]
        pt.slides[1].childNamed("x2_wild").component(Text).text = $v.pd.paytableSeq[3][0]
        pt.slides[1].childNamed("x5_freespins").component(Text).text = localizedString("EIFFEL_FREE_SPINS_NUM").format(v.pd.freespRelation[0].freespinCount)
        pt.slides[1].childNamed("x4_freespins").component(Text).text = localizedString("EIFFEL_FREE_SPINS_NUM").format(v.pd.freespRelation[1].freespinCount)
        pt.slides[1].childNamed("x3_freespins").component(Text).text = localizedString("EIFFEL_FREE_SPINS_NUM").format(v.pd.freespRelation[2].freespinCount)


registerComponent(EiffelPaytable, "paytable")
