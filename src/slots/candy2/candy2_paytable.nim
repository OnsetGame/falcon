import rod.node
import rod.component
import rod.component.text_component
import shared.paytable_general
import shared.localization_manager
import core.slot.base_slot_machine_view
import candy2_slot_view
import strutils

type Candy2Paytable* = ref object of PaytableGeneral


method onInit*(pt: Candy2Paytable) =
    procCall pt.PaytableGeneral.onInit()
    let v = pt.rootNode.sceneView.Candy2SlotView

    for i in 1..5:
        pt.addSlide("slots/candy2_slot/paytable/precomps/slide_" & $i)

    for c in pt.slides[0].children:
        if c.name.contains("_@noloc"):
            c.component(Text).verticalAlignment = vaBottom

    pt.addSlide("common/gui/paytable/precomps/slide_paylines_1")
    pt.fillPaylinesSlide(5, v.lines[0..9], "candySlot")
    pt.setPaylinesSlideNumbers(5, 1, 10)
    pt.setPaylinesSlideDesc(5, "PAYTABLE_LEFT_TO_RIGHT")

    pt.addSlide("common/gui/paytable/precomps/slide_paylines_1")
    pt.fillPaylinesSlide(6, v.lines[10..19], "candySlot")
    pt.setPaylinesSlideNumbers(6, 11, 20)
    pt.setPaylinesSlideDesc(6, "PAYTABLE_LEFT_TO_RIGHT")

    pt.slides[1].childNamed("candy2_x_scatter").component(Text).text = localizedString("candy2_x_scatter").format(v.pd.freespinsRelation[2].triggerCount, v.pd.freespinsRelation[1].triggerCount, v.pd.freespinsRelation[0].triggerCount)
    pt.slides[1].childNamed("candy2_freespins_count").component(Text).text = localizedString("candy2_freespins_count").format(v.pd.freespinsRelation[2].freespinCount, v.pd.freespinsRelation[1].freespinCount, v.pd.freespinsRelation[0].freespinCount)
    pt.slides[1].childNamed("candy2_scatter_text").component(Text).text = localizedString("candy2_scatter_text").format(v.pd.freespinsRelation[0].triggerCount)
    pt.slides[3].childNamed("candy2_bonus_symbols").component(Text).text = localizedString("candy2_bonus_symbols").format(v.pd.bonusRelation[0].triggerCount)
    if v.pd.paytableSeq.len != 0:
        for i in 0..v.pd.paytableSeq.len - 2:
            for num in 3..v.pd.paytableSeq[i].high:
                pt.slides[0].childNamed($i & "_" & $num & "_@noloc").component(Text).text = $v.pd.paytableSeq[i][num]

    for i in 0..2:
        pt.slides[0].childNamed($i & "_11_@noloc").component(Text).text = $v.pd.paytableSeq[i][0]

registerComponent(Candy2Paytable, "paytable")
