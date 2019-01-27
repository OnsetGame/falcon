import rod.node
import rod.component
import rod.component.text_component
import shared.paytable_general
import shared.localization_manager
import core.slot.base_slot_machine_view
import strutils
import mermaid_slot_view

type MermaidPaytable* = ref object of PaytableGeneral


method onInit*(pt: MermaidPaytable) =
    procCall pt.PaytableGeneral.onInit()
    let v = pt.rootNode.sceneView.MermaidMachineView
    let pd = v.pd

    for i in 1..4:
        pt.addSlide("slots/mermaid_slot/paytable/precomps/slide_" & $i)

    if v.lines.len >= 14:
        pt.addSlide("common/gui/paytable/precomps/slide_paylines_2")
        pt.fillPaylinesSlide(4, v.lines[0..14], $v.buildingId())
        pt.setPaylinesSlideNumbers(4, 1, 15)
        pt.setPaylinesSlideDesc(4, "PAYTABLE_LEFT_TO_RIGHT")
    if v.lines.len >= 24:
        pt.addSlide("common/gui/paytable/precomps/slide_paylines_1")
        pt.fillPaylinesSlide(5, v.lines[15..24], $v.buildingId())
        pt.setPaylinesSlideNumbers(5, 16, 25)
        pt.setPaylinesSlideDesc(5, "PAYTABLE_LEFT_TO_RIGHT")

    for i, item in pd.itemset:
        for j in 0..<pd.paytableSeq.len:
            let pay = pd.paytableSeq[j][i]
            if pay > 0:
                let nd = pt.slides[0].childNamed($j & "_" & item & "_@noloc")
                if not nd.isNil:
                    nd.component(Text).text = $pay

    pt.slides[2].childNamed("SLIDE_3_TEXT_1").component(Text).text = localizedString("SLIDE_3_TEXT_1").format(pd.freespRelation[0].triggerCount,
                                                                                                       pd.freespRelation[1].triggerCount,
                                                                                                       pd.freespRelation[2].triggerCount)

    pt.slides[2].childNamed("SLIDE_3_TEXT_2").component(Text).text = localizedString("SLIDE_3_TEXT_2").format(pd.freespRelation[0].freespinCount,
                                                                                                       pd.freespRelation[1].freespinCount,
                                                                                                       pd.freespRelation[2].freespinCount)

    pt.slides[2].childNamed("SLIDE_3_TEXT_3").component(Text).text = localizedString("SLIDE_3_TEXT_3").format(pd.bonusCount)

    pt.slides[2].childNamed("SLIDE_3_TEXT_4").component(Text).text = localizedString("SLIDE_3_TEXT_4").format(pd.freespRelation[2].triggerCount)


registerComponent(MermaidPaytable, "paytable")