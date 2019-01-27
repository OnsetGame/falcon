import nimx / [ types, matrixes, animation ]
import rod.node
import rod.component
import rod.component.text_component
import shared / [ localization_manager, game_scene, window.button_component ]
import core.slot.slot_types
import shared / window / window_component
import shared.gui.gui_module
import falconserver.slot.machine_base_types
import utils / [ helpers, icon_component, falcon_analytics, falcon_analytics_utils, sound_manager ]
import strutils

const SLIDE_OFFSET = 1470
const ANIM_DURATION = 0.5

type PaytableGeneral* = ref object of WindowComponent
    parent*: Node
    rootNode*: Node
    currSlide: int
    slides*: seq[Node]
    buttonLeft: ButtonComponent
    buttonRight: ButtonComponent
    totalRTP*: float

template gameScene*(pt: PaytableGeneral): GameScene = pt.parent.sceneView.GameScene

proc addSlide*(pt: PaytableGeneral, path: string) =
    let slide = newLocalizedNodeWithResource(path)

    pt.rootNode.findNode("slides_anchor").addChild(slide)

    if pt.slides.len > 0:
        slide.enabled = false
    pt.slides.add(slide)

proc fillPaylinesSlide*(pt: PaytableGeneral, index: int, lines: seq[Line], iconName: string) =
    for c in pt.slides[index].children:
        if c.name.contains("payline_placehodler"):
            discard c.addPaylinesIcon(iconName)
            c.enabled = false

    for i in 0..<lines.len:
        for j in 0..NUMBER_OF_REELS - 1:
            let indexes = reelToIndexes(j)
            let row = lines[i][j]

            pt.slides[index].childNamed("payline_placehodler_" & $(indexes[row] + i * ELEMENTS_COUNT + 1)).enabled = true

proc setPaylinesSlideNumbers*(pt: PaytableGeneral, index, start, to: int) =
    pt.slides[index].findNode("paylines_number").component(Text).text = $start & "-" & $to

proc setPaylinesSlideDesc*(pt: PaytableGeneral, index: int, key: string) =
    pt.slides[index].findNode("win_combination_text").component(Text).text = localizedString(key)

proc slide(pt: PaytableGeneral, index: int, start: float, forward, enableOnEnd, backToStart: bool) =
    let anim = newAnimation()
    var to = start + SLIDE_OFFSET

    pt.buttonRight.enabled = false
    pt.buttonLeft.enabled = false
    if not forward:
        to = start - SLIDE_OFFSET
    anim.loopDuration = ANIM_DURATION
    anim.numberOfLoops = 1
    anim.onAnimate = proc(p: float)=
        pt.slides[index].positionX = interpolate(start, to, p)
    anim.onComplete do():
        pt.slides[index].enabled = enableOnEnd
        pt.buttonRight.enabled = true
        pt.buttonLeft.enabled = true

        if backToStart:
            pt.slides[index].positionX = start
    pt.rootNode.addAnimation(anim)
    pt.gameScene.soundManager.sendEvent("COMMON_PAYTABLE_SLIDE")

proc forward(pt: PaytableGeneral) =
    let oldSlide = pt.currSlide

    pt.currSlide.inc()
    if pt.currSlide == pt.slides.len:
        pt.currSlide = 0
    pt.slides[pt.currSlide].enabled = true

    pt.slide(oldSlide, pt.slides[oldSlide].positionX, false, false, true)
    pt.slide(pt.currSlide, pt.slides[pt.currSlide].positionX + SLIDE_OFFSET, false, true, false)

proc back(pt: PaytableGeneral) =
    let oldSlide = pt.currSlide

    pt.currSlide.dec()
    if pt.currSlide < 0:
        pt.currSlide = pt.slides.len - 1
    pt.slides[pt.currSlide].enabled = true

    pt.slide(oldSlide, pt.slides[oldSlide].positionX, true, false, true)
    pt.slide(pt.currSlide, pt.slides[pt.currSlide].positionX - SLIDE_OFFSET, true, true, false)

method showStrategy*(pt: PaytableGeneral) =
    pt.gameScene.soundManager.sendEvent("COMMON_PAYTABLE_OPEN")
    let enter = saveNewPaytableEnter(pt.gameScene.name)
    sharedAnalytics().paytable_open(pt.gameScene.sceneID(), getCountedEvent(pt.gameScene.name & TOTAL_SPINS), enter, pt.totalRTP)

    pt.node.alpha = 1.0
    pt.rootNode.alpha = 1.0
    let animation = pt.rootNode.animationNamed("in")
    pt.rootNode.addAnimation(animation)

method hideStrategy*(pt: PaytableGeneral): float =
    pt.gameScene.soundManager.sendEvent("COMMON_PAYTABLE_CLOSE")

    let animation = pt.rootNode.animationNamed("out")
    pt.rootNode.addAnimation(animation)
    return animation.loopDuration

method onInit*(pt: PaytableGeneral) =
    pt.canMissClick = false

    pt.rootNode = newLocalizedNodeWithResource("common/gui/paytable/precomps/paytable")
    pt.rootNode.findNode("text_content_active").component(Text).text = localizedString("PAYTABLE_GENERAL")
    pt.rootNode.findNode("text_content_inactive").component(Text).text = localizedString("PAYTABLE_GENERAL")
    pt.slides = @[]
    pt.parent = pt.anchorNode
    pt.parent.addChild(pt.rootNode)

    let btnClose = pt.rootNode.findNode("button_close")
    let bc = btnClose.createButtonComponent(btnClose.animationNamed("press"), newRect(10,10,100,100))
    let btnRight =  pt.rootNode.findNode("button_right")
    let btnLeft =  pt.rootNode.findNode("button_left")

    discard pt.rootNode.findNode("slot_logos_icons@2x_placeholder").addSlotLogos2x(pt.gameScene.sceneID())

    pt.buttonRight = btnRight.createButtonComponent(btnRight.animationNamed("press"), newRect(10,10,100,100))
    pt.buttonLeft = btnLeft.createButtonComponent(btnLeft.animationNamed("press"), newRect(10,10,100,100))

    bc.onAction do():
        pt.close()
    pt.buttonRight.onAction do():
        pt.forward()
    pt.buttonLeft.onAction do():
        pt.back()
