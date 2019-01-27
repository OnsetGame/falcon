import rod.node
import rod.component
import rod.component.text_component
import shared.paytable_general
import shared.localization_manager
import core.slot.base_slot_machine_view
import strutils
import balloon_slot_view

type BalloonPaytable* = ref object of PaytableGeneral


method onInit*(pt: BalloonPaytable) =
    procCall pt.PaytableGeneral.onInit()
    let v = pt.rootNode.sceneView.BalloonSlotView

    let pd = v.pd
    pt.totalRTP = v.getTotalRTP()

    for i in 1..4:
        pt.addSlide("slots/balloon_slot/paytable/precomps/slide_" & $i)

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

    pt.slides[2].childNamed("BALLOON_PAYTABLE_2_4").component(Text).text = localizedString("BALLOON_PAYTABLE_2_4").format(pd.bonusCount)
    pt.slides[2].childNamed("BALLOON_PAYTABLE_2_5").component(Text).text = localizedString("BALLOON_PAYTABLE_2_5").format(pd.minRockets, pd.maxRockets)
    pt.slides[2].childNamed("BALLOON_PAYTABLE_2_6").component(Text).text = localizedString("BALLOON_PAYTABLE_2_6").format(pd.freespRelation[0].freespinCount,
                                                                                                                   pd.freespRelation[1].freespinCount,
                                                                                                                   pd.freespRelation[2].freespinCount,
                                                                                                                   pd.freespRelation[3].freespinCount,
                                                                                                                   pd.freespRelation[4].freespinCount)
    pt.slides[2].childNamed("BALLOON_PAYTABLE_2_7").component(Text).text = localizedString("BALLOON_PAYTABLE_2_7").format(pd.freespRelation[0].triggerCount,
                                                                                                                   pd.freespRelation[1].triggerCount,
                                                                                                                   pd.freespRelation[2].triggerCount,
                                                                                                                   pd.freespRelation[3].triggerCount,
                                                                                                                   pd.freespRelation[4].triggerCount)

registerComponent(BalloonPaytable, "paytable")