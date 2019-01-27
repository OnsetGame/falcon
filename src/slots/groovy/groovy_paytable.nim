import nimx.matrixes
import rod.node
import rod.component
import rod.component.text_component
import shared.paytable_general
import shared.localization_manager
import core.slot.base_slot_machine_view
import groovy_slot_view
import strutils

type GroovyPaytable* = ref object of PaytableGeneral

method onInit*(pt: GroovyPaytable) =
    procCall pt.PaytableGeneral.onInit()

    let v = pt.rootNode.sceneView.GroovySlotView

    for i in 1..4:
        pt.addSlide("slots/groovy_slot/paytable/precomps/slide_" & $i)

    if v.pd.paytableSeq.len != 0:
        for i in 0..v.pd.paytableSeq.high - 1:
            for num in 1..v.pd.paytableSeq[i].high - 2:
                # todo: fix naming in composition!
                let nid = (if num == 2: 4 elif num == 4: 2 else: num)
                let chn = pt.slides[0].childNamed($i & "_" & $nid & "_@noloc")
                chn.component(Text).text = $v.pd.paytableSeq[i][num]

    for c in pt.slides[0].children:
        if c.name.contains("_@noloc"):
            c.component(Text).verticalAlignment = vaBottom

    pt.slides[1].childNamed("gr_pt_x3").component(Text).text = localizedString("GR_PT_X3").format($v.pd.paytableSeq[2][11])
    pt.slides[1].childNamed("gr_pt_777_freespins").component(Text).text = localizedString("GR_PT_777_FREESPINS").format($v.pd.totalSevensFreespinCount)

    let OFFSET_SLIDE_1 = 48.0
    for i in 0..3:
        let chn = pt.slides[1].childNamed("x" & $i & "_@noloc")
        chn.component(Text).text = $(v.pd.paytableSeq[i][^1])
        chn.positionY = 755.0 + OFFSET_SLIDE_1 * i.float

    let OFFSET_SLIDE_2 = 38.5
    for i in 0..11:
        let chn = pt.slides[2].childNamed("bar_" & $i & "_@noloc")
        chn.component(Text).text = $(v.pd.barsPayout[15 - (i)])
        chn.positionY = 445.0 + OFFSET_SLIDE_2 * i.float
    pt.slides[2].childNamed("gr_pt_bar_freespins").component(Text).text = localizedString("GR_PT_BAR_FREESPINS").format($v.pd.totalBarsFreespinCount)

    pt.addSlide("common/gui/paytable/precomps/slide_paylines_2")
    pt.fillPaylinesSlide(4, v.lines[0..14], "groovySlot")
    pt.setPaylinesSlideNumbers(4, 1, 15)
    pt.setPaylinesSlideDesc(4, "PAYTABLE_LEFT_TO_RIGHT")

    pt.addSlide("common/gui/paytable/precomps/slide_paylines_1")
    pt.fillPaylinesSlide(5, v.lines[15..24], "groovySlot")
    pt.setPaylinesSlideNumbers(5, 16, 25)
    pt.setPaylinesSlideDesc(5, "PAYTABLE_LEFT_TO_RIGHT")


registerComponent(GroovyPaytable, "paytable")
