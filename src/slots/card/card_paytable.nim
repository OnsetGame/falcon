import rod.node
import rod.component
import rod.component.text_component
import shared.paytable_general
import card_slot_view

type CardPaytable* = ref object of PaytableGeneral

method onInit*(pt: CardPaytable) =
    procCall pt.PaytableGeneral.onInit()

    let v = pt.rootNode.sceneView.CardSlotView

    for i in 1..5:
        pt.addSlide("slots/card_slot/paytable/precomps/slide_" & $i)

    if v.pd.paytableSeq.len != 0:
        for i in 0..v.pd.paytableSeq.high - 1:
            for num in 1..v.pd.paytableSeq[i].high - 3:
                pt.slides[0].childNamed($i & "_" & $num & "_@noloc").component(Text).text = $v.pd.paytableSeq[i][num]

    pt.addSlide("common/gui/paytable/precomps/slide_paylines_1")
    pt.fillPaylinesSlide(5, v.lines[0..9], "cardSlot")
    pt.setPaylinesSlideNumbers(5, 1, 10)
    pt.setPaylinesSlideDesc(5, "PAYTABLE_LEFT_TO_RIGHT")

    pt.addSlide("common/gui/paytable/precomps/slide_paylines_1")
    pt.fillPaylinesSlide(6, v.lines[10..19], "cardSlot")
    pt.setPaylinesSlideNumbers(6, 11, 20)
    pt.setPaylinesSlideDesc(6, "PAYTABLE_LEFT_TO_RIGHT")


registerComponent(CardPaytable, "paytable")
