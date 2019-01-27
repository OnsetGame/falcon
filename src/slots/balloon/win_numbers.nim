import nimx.animation, nimx.types, nimx.matrixes, nimx.font, nimx.formatted_text
import rod.node
import rod.component.text_component
import rod.viewport

import nimx.view
import nimx.timer

import rocket_controller
import tables
import core.slot.base_slot_machine_view

var cacheBig = initTable[string, Node]()
var cacheMedium = initTable[string, Node]()
var cacheSmall = initTable[string, Node]()

const SMALL_FONT_STEP* = 140.0*0.7
const MEDIUM_FONT_STEP* = 140.0
const BIG_FONT_STEP* = 420.0

type FontSize* = enum
    SmallFont
    MediumFont
    BigFont

proc getText(n: Node, text: var seq[Text]) =
    let t = n.componentIfAvailable(Text)
    if not t.isNil:
        text.add(t)
    for c in n.children:
        c.getText(text)

proc nodeForBigText(i, j: int): Node =
    var nd = cacheBig.getOrDefault($i & $j)
    if nd.isNil:
        nd = newLocalizedNodeWithResource("slots/balloon_slot/2d/compositions/numbers_big_export.json")
        cacheBig[$i & $j] = nd
    result = nd

proc nodeForMediumText(i, j: int): Node =
    var nd = cacheMedium.getOrDefault($i & $j)
    if nd.isNil:
        nd = newLocalizedNodeWithResource("slots/balloon_slot/2d/compositions/numbers_medium_export.json")
        cacheMedium[$i & $j] = nd
    result = nd

proc nodeForSmallText(i, j: int): Node =
    var nd = cacheSmall.getOrDefault($i & $j)
    if nd.isNil:
        nd = newLocalizedNodeWithResource("slots/balloon_slot/2d/compositions/numbers_small_export.json")
        cacheSmall[$i & $j] = nd
    result = nd

proc winNumbersAnimation*(n: Node, speedMultiplier: float32 = 1.0): tuple[inAnim: Animation, outAnim: Animation] =
    result.inAnim = newAnimation()
    result.outAnim = newAnimation()
    let root = n.findNode("win_text_root")

    # Offsets in seconds
    const digitStartOffset = 0.1

    var resIn = result.inAnim
    var resOut = result.outAnim
    var maxDurationIn = 0.0
    var maxDurationOut = 0.0

    for i, layer in root.children:
        var p = float(i) * digitStartOffset
        for j, digit in layer.children:
            let offset = (p + float(j) * digitStartOffset)
            # * speedMultiplier
            let digitInAnim = digit.animationNamed("in")
            digitInAnim.loopDuration = digitInAnim.loopDuration
            # * speedMultiplier
            let durIn = digitInAnim.loopDuration + offset
            if durIn > maxDurationIn: maxDurationIn = durIn
            let digitOutAnim = digit.animationNamed("out")
            let durOut = digitOutAnim.loopDuration + offset
            digitOutAnim.loopDuration = digitOutAnim.loopDuration
            # * speedMultiplier
            if durOut > maxDurationOut: maxDurationOut = durOut


    for i, layer in root.children:
        var p = float(i) * 0.1
        for j, digit in layer.children:
            let offset = p + float(j) * digitStartOffset
            # * speedMultiplier
            closureScope:
                let d = digit
                resIn.addLoopProgressHandler(offset / maxDurationIn, true) do():
                    if not d.sceneView.isNil:
                        d.addAnimation(d.animationNamed("in"))
                resOut.addLoopProgressHandler(offset / maxDurationOut, true) do():
                    if not d.sceneView.isNil:
                        d.addAnimation(d.animationNamed("out"))

    result.inAnim.numberOfLoops = 1
    result.inAnim.loopDuration = maxDurationIn * speedMultiplier

    result.outAnim.numberOfLoops = 1
    result.outAnim.loopDuration = maxDurationOut * speedMultiplier

proc bigwinNumbersNode*(value: int64, duration: float32): Node =
    proc getPos(strDigitsLen: int): Vector3 =
        let centerFront = 960.0
        let stepFront = MEDIUM_FONT_STEP
        let digitsFrontLen = (strDigitsLen div 2).float32 * stepFront
        let modFrontShift = if ((strDigitsLen mod 2) == 0) : (stepFront/2.0) else: 0
        result = newVector3(centerFront - digitsFrontLen + modFrontShift, 602.0, 0.0)

    let numNode = newNode("bigwin")
    let textComp = numNode.component(Text)
    textComp.font = newFontWithFace("AlfaSlabOne-Regular", 200)
    textComp.color = newColor(1,1,1,1)

    var prevTxtLen: int = 0
    var anim = newAnimation()
    anim.numberOfLoops = 1
    anim.loopDuration = duration
    anim.onAnimate = proc(p: float)=

        let val = interpolate(0'i64, value, p)
        let txt =  $val
        textComp.text = txt

        if prevTxtLen != txt.len:
            numNode.position = getPos(txt.len)
        prevTxtLen = txt.len

    numNode.registerAnimation("play", anim)

    result = numNode

proc bonusgameNumbersNode*(value: int64, duration: float32): Node =
    let numNode = newNode("bigwin")
    numNode.scaleY = -1.0
    numNode.scaleZ = -1.0
    let textComp = numNode.component(Text)
    textComp.font = newFontWithFace("AlfaSlabOne-Regular", 7)
    textComp.color = newColor(1,1,1,1)
    textComp.horizontalAlignment = HorizontalTextAlignment.haCenter

    var anim = newAnimation()
    anim.numberOfLoops = 1
    anim.loopDuration = duration
    anim.onAnimate = proc(p: float)=
        let val = interpolate(0'i64, value, p)
        let txt =  $val
        textComp.text = txt

    numNode.registerAnimation("play", anim)

    result = numNode

proc playUpBonusNumber*(n: Node, valTo: int64, timeout: float32, slotSpeed: float32, callback: proc()) =
    let vp = n.sceneView.BaseMachineView
    vp.setTimeout timeout, proc() =
        if valTo > 0'i64:
            let numNode = bonusgameNumbersNode(valTo, 0.5 * slotSpeed)
            n.addChild(numNode)

            let shiftY = 20.0.Coord
            let destTranslation = newVector3(numNode.positionX, numNode.positionY + shiftY, numNode.positionZ)

            let anim = numNode.animationNamed("play")
            vp.addAnimation(anim)
            numNode.moveTo(destTranslation, 1.5 * slotSpeed)

            vp.setTimeout 0.75 * slotSpeed, proc() =
                numNode.playAlpha(0.0, 0.75 * slotSpeed, proc() =
                    numNode.removeFromParent()
                    n.removeFromParent()
                    callback()
                )

proc numbersNodeWithColor(value: string, color: Color, j: int, fontType: FontSize): Node =
    result = newNode()
    var x = 0.float32
    for i, c in value:
        var n: Node
        var tc: Text
        var shift: float32

        case fontType
        of SmallFont:
            n = nodeForSmallText(i, j)
            shift = SMALL_FONT_STEP
        of MediumFont:
            n = nodeForMediumText(i, j)
            shift = MEDIUM_FONT_STEP
        of BigFont:
            n = nodeForBigText(i, j)
            shift = BIG_FONT_STEP
        else:
            discard

        tc = n.findNode("text").component(Text)
        tc.text = $c
        tc.color = color
        n.positionX = x
        x += shift

        result.addChild(n)

proc newWinNumbersNode*(value: int64, fontType: FontSize): Node =
    let s = $value
    result = newNode("win_text_root")
    # result.positionY = -480 #-617
    let colors = if fontType == BigFont: [newColor(0.94, 0.76, 0.20), newColor(0.94, 0.76, 0.20), newColor(0.94, 0.76, 0.20)]
                 else:                   [newColor(0.99, 0.89, 0.54), newColor(0.94, 0.76, 0.20), newColor(1, 1, 1)]

    for j, c in colors:
        result.addChild(numbersNodeWithColor(s, c, j, fontType))
