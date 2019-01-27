import rod.node
import rod.viewport
import rod.component
import rod.component.color_balance_hls
import rod.component.tint
import rod.component.channel_levels
import rod.component.clipping_rect_component
import nimx.matrixes
import nimx.types
import nimx.animation
import nimx.timer
import utils.helpers
import utils.sound_manager
import shared.game_scene
import core.slot.base_slot_machine_view
import witch_slot_view
import random
import sequtils

const PREFIX = "slots/witch_slot/elements/precomps/"

proc setBeforeFallRuneColor(n: Node, et: ElementType) =
    let overTintEffect = Tint.new()
    let overLevelsEffect = ChannelLevels.new()
    let redLevelsEffect = ChannelLevels.new()
    let redTintEffect = Tint.new()
    let redHLSEffect = ColorBalanceHLS.new()
    let greenLevelsEffect = ChannelLevels.new()
    let greenHLSEffect = ColorBalanceHLS.new()

    overLevelsEffect.init()
    redLevelsEffect.init()
    greenLevelsEffect.init()
    redHLSEffect.init()
    greenHLSEffect.init()

    case et
    of ElementType.Green:
        overTintEffect.white = newColor(0.94186848402023, 1.0, 0.45098036527634, 1.0)
        overTintEffect.black = newColor(0.0, 0.0, 0.0, 1.0)
        overTintEffect.amount = 0.75

        overLevelsEffect.inWhite = 0.86274509803922
        overLevelsEffect.inBlack = 0.2156862745098

        greenLevelsEffect.inGamma = 0.39444059467173

        greenHLSEffect.hue = -0.325
        greenHLSEffect.saturation = 0.0
    of ElementType.Yellow:
        overTintEffect.white = newColor(0.99724930524826, 1.0, 0.41960781812668, 1.0)
        overTintEffect.black = newColor(0.0, 0.0, 0.0, 1.0)
        overTintEffect.amount = 0.75

        overLevelsEffect.inBlack = 0.14509803921569
    of ElementType.Red:
        overTintEffect.white = newColor(0.97647058963776, 0.63921570777893, 0.12156862765551, 1.0)
        overTintEffect.black = newColor(0.0, 0.0, 0.0, 1.0)
        overTintEffect.amount = 0.5

        overLevelsEffect.inWhite = 0.86274509803922
        overLevelsEffect.inBlack = 0.2156862745098

        redLevelsEffect.inGamma = 0.3

        redTintEffect.white = newColor(1.0, 0.80000007152557, 0.0, 1.0)
        redTintEffect.black = newColor(1.0, 0.0, 0.14117635786533, 1.0)
        redTintEffect.amount = 0.38

        redHLSEffect.hue = -0.0361
        redHLSEffect.saturation = 0.64
        redHLSEffect.lightness = 0.1
    else:
        discard

    if et != ElementType.Blue:
        n.findNode("crystal_over").setComponent("Tint", overTintEffect)
        n.findNode("crystal_over").setComponent("ChannelLevels", overLevelsEffect)
    if et == ElementType.Red:
        n.findNode("yellow_red").findNode("parent").setComponent("ColorBalanceHLS", redHLSEffect)
        n.findNode("yellow_red").findNode("parent").setComponent("Tint", redTintEffect)
        n.findNode("yellow_red").findNode("parent").setComponent("ChannelLevels", redLevelsEffect)
    if et == ElementType.Green:
        n.findNode("blue_green").findNode("parent").setComponent("ColorBalanceHLS", greenHLSEffect)
        n.findNode("blue_green").findNode("parent").setComponent("ChannelLevels", greenLevelsEffect)


    if et == ElementType.Yellow or et == ElementType.Red:
        n.findNode("blue_green").enabled = false
    else:
        n.findNode("yellow_red").enabled = false


proc setFallRuneColor(n: Node, et: ElementType) =
    let overTintEffect = Tint.new()
    let overLevelsEffect = ChannelLevels.new()
    let redLevelsEffect = ChannelLevels.new()
    let redTintEffect = Tint.new()
    let redHLSEffect = ColorBalanceHLS.new()
    let greenLevelsEffect = ChannelLevels.new()
    let greenHLSEffect = ColorBalanceHLS.new()
    let blurFlareHLSEffect = ColorBalanceHLS.new()
    let blurFlareTintEffect = Tint.new()

    overLevelsEffect.init()
    redLevelsEffect.init()
    greenLevelsEffect.init()

    redHLSEffect.init()
    greenHLSEffect.init()
    blurFlareHLSEffect.init()

    case et
    of ElementType.Green:
        overTintEffect.white = newColor(0.94186848402023, 1.0, 0.45098036527634, 1.0)
        overTintEffect.black = newColor(0.0, 0.0, 0.0, 1.0)
        overTintEffect.amount = 0.75

        overLevelsEffect.inWhite = 0.86274509803922
        overLevelsEffect.inBlack = 0.2156862745098

        greenLevelsEffect.inGamma = 0.39444059467173

        greenHLSEffect.hue = -0.325
        greenHLSEffect.saturation = 0.0
        greenHLSEffect.lightness = -0.18

        blurFlareHLSEffect.hue = -0.25
        blurFlareHLSEffect.saturation = 0.0
        blurFlareHLSEffect.lightness = 0.0
    of ElementType.Yellow:
        overTintEffect.white = newColor(0.99724930524826, 1.0, 0.41960781812668, 1.0)
        overTintEffect.black = newColor(0.0, 0.0, 0.0, 1.0)
        overTintEffect.amount = 0.75

        overLevelsEffect.inBlack = 0.14509803921569

        blurFlareTintEffect.white = newColor(0.98576617240906, 1.0, 0.61568629741669, 1.0)
        blurFlareTintEffect.black = newColor(1.0, 0.5467289686203, 0.0, 1.0)
        blurFlareTintEffect.amount = 1.0
    of ElementType.Red:
        overTintEffect.white = newColor(0.97647058963776, 0.63921570777893, 0.12156862765551, 1.0)
        overTintEffect.black = newColor(0.0, 0.0, 0.0, 1.0)
        overTintEffect.amount = 0.5

        overLevelsEffect.inWhite = 0.86274509803922
        overLevelsEffect.inBlack = 0.2156862745098

        redLevelsEffect.inGamma = 0.3

        redTintEffect.white = newColor(1.0, 0.80000007152557, 0.0, 1.0)
        redTintEffect.black = newColor(1.0, 0.0, 0.14117635786533, 1.0)
        redTintEffect.amount = 0.38

        redHLSEffect.hue = -0.0361
        redHLSEffect.saturation = 0.64
        redHLSEffect.lightness = 0.1

        blurFlareTintEffect.white = newColor(1.0, 0.94004476070404, 0.47450977563858, 1.0)
        blurFlareTintEffect.black = newColor(1.0, 0.0, 0.03333333134651, 1.0)
        blurFlareTintEffect.amount = 1.0
    else:
        discard

    if et != ElementType.Blue:
        n.findNode("crystal_over").setComponent("Tint", overTintEffect)
        n.findNode("crystal_over").setComponent("ChannelLevels", overLevelsEffect)
        n.findNode("crystal_over2").setComponent("Tint", overTintEffect)
        n.findNode("crystal_over2").setComponent("ChannelLevels", overLevelsEffect)
    if et == ElementType.Red:
        n.findNode("yellow_red").findNode("parent").setComponent("ColorBalanceHLS", redHLSEffect)
        n.findNode("yellow_red").findNode("parent").setComponent("Tint", redTintEffect)
        n.findNode("yellow_red").findNode("parent").setComponent("ChannelLevels", redLevelsEffect)
    if et == ElementType.Green:
        n.findNode("blue_green").findNode("parent").setComponent("ColorBalanceHLS", greenHLSEffect)
        n.findNode("blue_green").findNode("parent").setComponent("ChannelLevels", greenLevelsEffect)
        n.findNode("crystal_flare").setComponent("ColorBalanceHLS", blurFlareHLSEffect)
        n.findNode("crystal_blur").setComponent("ColorBalanceHLS", blurFlareHLSEffect)
    if et == ElementType.Yellow or et == ElementType.Red:
        n.findNode("crystal_flare").setComponent("Tint", blurFlareTintEffect)
        n.findNode("crystal_blur").setComponent("Tint", blurFlareTintEffect)
        n.findNode("blue_green").enabled = false
    else:
        n.findNode("yellow_red").enabled = false


proc setAfterFallRuneColor(n: Node, et: ElementType) =
    let parent = n.findNode("parent_2")
    let overTintEffect = Tint.new()
    let overLevelsEffect = ChannelLevels.new()
    let parentHLSEffect = ColorBalanceHLS.new()

    overLevelsEffect.init()
    parentHLSEffect.init()

    case et
    of ElementType.Green:
        overTintEffect.white = newColor(0.94186848402023, 1.0, 0.45098036527634, 1.0)
        overTintEffect.black = newColor(0.0, 0.0, 0.0, 1.0)
        overTintEffect.amount = 0.75

        overLevelsEffect.inWhite = 0.86274509803922
        overLevelsEffect.inBlack = 0.2156862745098

        parentHLSEffect.hue = -0.25
        parentHLSEffect.saturation = 0.0
        parentHLSEffect.lightness = 0.0

    of ElementType.Yellow:
        overTintEffect.white = newColor(0.99724930524826, 1.0, 0.41960781812668, 1.0)
        overTintEffect.black = newColor(0.0, 0.0, 0.0, 1.0)
        overTintEffect.amount = 0.75

        overLevelsEffect.inBlack = 0.14509803921569

        parentHLSEffect.hue = -0.38888888888889
        parentHLSEffect.saturation = 0.05
        parentHLSEffect.lightness = 0.17
    of ElementType.Red:
        overTintEffect.white = newColor(0.97647058963776, 0.63921570777893, 0.12156862765551, 1.0)
        overTintEffect.black = newColor(0.0, 0.0, 0.0, 1.0)
        overTintEffect.amount = 0.5

        overLevelsEffect.inWhite = 0.86274509803922
        overLevelsEffect.inBlack = 0.2156862745098

        parentHLSEffect.hue = -0.56944444444444
        parentHLSEffect.saturation = 0.3
        parentHLSEffect.lightness = 0.0
    else:
        discard

    if et != ElementType.Blue:
        n.findNode("crystal_over").setComponent("Tint", overTintEffect)
        n.findNode("crystal_over").setComponent("ChannelLevels", overLevelsEffect)
        parent.setComponent("ColorBalanceHLS", parentHLSEffect)


proc createCrystalFall(et: ElementType): Node =
    result = newNodeWithResource(PREFIX & "crystal/rune_fall.json")
    setFallRuneColor(result, et)


proc createCrystalBeforeFall(et: ElementType): Node =
    result = newNodeWithResource(PREFIX & "crystal/rune_before_fall.json")
    setBeforeFallRuneColor(result, et)


proc createCrystalAfterFall(et: ElementType): Node =
    result = newNodeWithResource(PREFIX & "crystal/rune_after_fall.json")
    setAfterFallRuneColor(result, et)


proc fallRune*(v: WitchSlotView,  el: WitchElement, callback: proc() = nil): Animation {.discardable.} =
    let fall = el.node.findNode("rune_fall")
    let before = el.node.findNode("rune_before_fall")
    let after = el.node.findNode("rune_after_fall")
    let play = fall.animationNamed("play")
    let ia = before.animationNamed("idle")
    let afterIdle = after.animationNamed("idle")
    let next = v.potsState[el.index.indexToPlace().x]
    var rect = newRect(0, 0, 1500, 1200)
    var deltaY = 400
    var duration = 0.5
    result = newAnimation()
    let res = result

    if el.index >= 10:
        rect = newRect(0, 0, 1500, 800)
        deltaY = 100
        duration = 0.4
    elif el.index >= 5:
        rect = newRect(0, 0, 1500, 1000)
        deltaY = 600
        duration = 0.8

    el.node.component(ClippingRectComponent).clippingRect = rect
    ia.cancel()

    afterIdle.numberOfLoops = -1
    v.elementIdles.add(afterIdle)
    before.enabled = false
    fall.enabled = true
    v.addAnimation(play)
    if next < 4:
        v.soundManager.sendEvent("FALL_RUNE")

    play.addLoopProgressHandler 0.4, false, proc() =
        after.enabled = true
        v.addAnimation(afterIdle)
        res.loopDuration = duration
        res.numberOfLoops = 1

        let posY = fall.positionY
        res.onAnimate = proc(p: float) =
            let cubic = cubicEaseInOut(p)
            fall.positionY = interpolate(posY, posY + deltaY.float, cubic)
        v.addAnimation(res)
        res.addLoopProgressHandler 0.6, false, proc() =
            fall.enabled = false
            if not callback.isNil:
                callback()

proc createCrystal*(v: WitchSlotView,  el: var WitchElement, et: ElementType) =
    let before = createCrystalBeforeFall(et)
    let after = createCrystalAfterFall(et)
    let fall = createCrystalFall(et)

    el.node = newNode("rune_root")
    el.node.addChild(before)
    el.node.addChild(after)
    el.node.addChild(fall)
    fall.enabled = false
    after.enabled = false

proc createScatter(el: var WitchElement) =
    el.node = newNodeWithResource(PREFIX & "scatter/scatter.json")

proc createPredator(el: var WitchElement) =
    el.node = newNodeWithResource(PREFIX & "predator/predator.json")
    el.anims.add(ElementAnimation.Enter)
    el.anims.add(ElementAnimation.IdleOut)

proc createMushroom(el: var WitchElement) =
    el.node = newNodeWithResource(PREFIX & "mushroom/mushroom.json")

proc createMandragora(el: var WitchElement) =
    el.node = newNodeWithResource(PREFIX & "mandragora/mandragora.json")

proc createHive(el: var WitchElement) =
    el.node = newNodeWithResource(PREFIX & "hive/hive.json")

proc createFeather(el: var WitchElement) =
    el.node = newNodeWithResource(PREFIX & "feather/feather.json")

proc createSpider(el: var WitchElement) =
    el.node = newNodeWithResource(PREFIX & "spider/spider.json")
    el.anims.add(ElementAnimation.Enter)

proc createElement*(v: WitchSlotView, t: ElementType, index: int): WitchElement =
    result.new()
    result.anims = @[]
    result.index = index

    case t
    of ElementType.Wild:
        result.createSpider()
    of ElementType.Red:
        v.createCrystal(result, ElementType.Red)
    of ElementType.Yellow:
        v.createCrystal(result, ElementType.Yellow)
    of ElementType.Green:
        v.createCrystal(result, ElementType.Green)
    of ElementType.Blue:
        v.createCrystal(result, ElementType.Blue)
    of ElementType.Scatter:
        result.createScatter()
    of ElementType.Predator:
        result.createPredator()
    of ElementType.Mushroom:
        result.createMushroom()
    of ElementType.Mandragora:
        result.createMandragora()
    of ElementType.Hive:
        result.createHive()
    of ElementType.Feather:
        result.createFeather()

    result.eType = t
    result.anims.add(ElementAnimation.Idle)
    result.anims.add(ElementAnimation.Win)


proc playElementIdle*(v: WitchSlotView, element: WitchElement): Animation {.discardable.} = #create order - enter, idle, win
    if element.anims.contains(ElementAnimation.Idle):
        result = element.node.animationNamed("idle")

        if element.eType == ElementType.Wild:
            result = element.node.findNode("spider_inside").animationNamed("idle")
        elif element.eType >= ElementType.Red and element.eType <= ElementType.Blue:
            let beforeFall = element.node.findNode("rune_before_fall")
            var anim: Animation

            if element.eType == ElementType.Red or element.eType == ElementType.Yellow:
                anim = beforeFall.findNode("yellow_red").animationNamed("idle")
            else:
                anim = beforeFall.findNode("blue_green").animationNamed("idle")
            v.addAnimation(anim)
            anim.numberOfLoops = -1
            v.elementIdles.add(anim)

            result = beforeFall.animationNamed("idle")
        elif element.eType == ElementType.Predator:
            element.node.findNode("spittles").enabled = true
        v.addAnimation(result)
        result.numberOfLoops = -1
        v.elementIdles.add(result)

proc startSpittles*(v: WitchSlotView, element: WitchElement): seq[Animation] {.discardable.} =
    if element.eType == ElementType.Predator:
        let spittles = element.node.findNode("spittles")
        let enterSpittles = spittles.animationNamed("enter")
        var res: seq[Animation] = @[]

        v.addAnimation(enterSpittles)

        for i in 1..4:
            closureScope:
                let index = i
                let spittle = spittles.findNode("spittle_" & $index)
                let t = index.float - 1.0
                let anim = spittle.animationNamed("play")

                res.add(anim)
                v.elementIdles.add(anim)
                v.setTimeout t / 24.0, proc() =
                    v.addAnimation(anim)
                    anim.numberOfLoops = -1
        return res

proc playElementEnter(v: WitchSlotView, index: int, newPos: float = 0): float {.discardable.} =
    let element = v.currentElements[index]

    if element.anims.contains(ElementAnimation.Enter):
        if element.eType == ElementType.Wild:
            let inside = element.node.findNode("spider_inside")
            let enterSpider = element.node.animationNamed("enter")
            let enterSpiderInside = inside.animationNamed("enter")
            let down = newAnimation()

            v.soundManager.sendEvent("WILD_APPEARS")
            element.node.enabled = false
            enterSpider.addLoopProgressHandler 0.1, false, proc() =
                element.node.enabled = true
            down.loopDuration = 0.75
            down.numberOfLoops = 1
            v.addAnimation(enterSpider)
            v.addAnimation(enterSpiderInside)
            enterSpider.onComplete do():
                let posY = inside.positionY

                down.onAnimate = proc(p: float) =
                    let interp = bounceEaseOut(p)
                    inside.positionY = interpolate(posY, posY + newPos, interp)
                v.addAnimation(down)
            result = enterSpider.loopDuration + down.loopDuration - 0.2

        if element.eType == ElementType.Predator:
            let enter = element.node.animationNamed("idle")

            v.addAnimation(enter)
            enter.addLoopProgressHandler 0.75, false, proc() =
                v.startSpittles(element)
            result = enter.loopDuration


############ ---- MAGIC SPIN -------- #############

proc clearMagicParents*(v: WitchSlotView) =
    for i in 0..2:
        let reelIndexes = reelToIndexes(i)
        for j in 0..<reelIndexes.len:
            let parent = v.elementsParent.findNode("element_" & $(reelIndexes[j] + 1) & "_2")
            parent.removeAllChildren()

proc clearParentsOnReel(v: WitchSlotView, index: int) =
    let reelIndexes = reelToIndexes(index)
    for i in 0..<reelIndexes.len:
        let parent = v.elementsParent.findNode("element_" & $(reelIndexes[i] + 1))
        parent.removeAllChildren()

proc addGlareNode(v: WitchSlotView, el: WitchElement) =
    var elementName = "element_" & $(el.index + 1)

    if v.isSecondaryElement(el.index):
        elementName &= "_2"

    let parent = v.elementsParent.childNamed(elementName)
    el.glareNode = newNode("glare_parent")
    parent.addChild(el.glareNode)
    el.glareNode.position = SHIFT

proc magicSpin*(v: WitchSlotView) =
    if v.fsStatus != FreespinStatus.No:
        v.gameFlow.nextEvent()
        return
    if v.currentMagicSpinReel != -1:
        let reelIndexes = reelToIndexes(v.currentMagicSpinReel)
        let anim = v.elementsParent.animationNamed("magic_spin")
        var holdNodes: seq[Node] = @[]
        var holdPositions: seq[Vector3] = @[]

        v.addAnimation(v.magicSpinMessage.animationNamed("play"))
        for i in 0..<reelIndexes.len:
            let index = reelIndexes[i]
            let parent = v.elementsParent.findNode("element_" & $(index + 1) & "_2")
            let element = v.createElement(v.lastField[index].ElementType, index)

            v.addGlareNode(element)
            parent.addChild(element.node)
            element.node.position = SHIFT
            v.playElementIdle(element)
            v.currentElements[index] = element

        for i in 0..2:
            if i != v.currentMagicSpinReel:
                let reelIndexes = reelToIndexes(i)
                for j in 0..<reelIndexes.len:
                    let node = v.elementsParent.findNode("element_" & $(reelIndexes[j] + 1))

                    holdPositions.add(node.position)
                    holdNodes.add(node)

        proc hold(p: float) =
            for i in 0..<holdNodes.len:
                holdNodes[i].position = holdPositions[i]
        let ca = addOnAnimate(anim, hold)
        v.addAnimation(ca)
        ca.onComplete do():
            v.clearParentsOnReel(v.currentMagicSpinReel)
            v.gameFlow.nextEvent()
    else:
        v.gameFlow.nextEvent()

proc generateFakeSymbols*(v: WitchSlotView, index: int): seq[WitchElement] =
    var checkIndex = index - 1
    var fakeSeq = @[ElementType.Predator, ElementType.Mandragora, ElementType.Mushroom, ElementType.Feather, ElementType.Hive]

    if index == 0:
        checkIndex = 2

    let reelIndexes = reelToIndexes(checkIndex)
    for ri in reelIndexes:
        fakeSeq.keepIf(proc(x: ElementType): bool = x != v.lastField[ri].ElementType)

    result = @[]
    for ri in reelIndexes:
        result.add(v.createElement(rand(fakeSeq), ri))

proc isMagicSpin*(v: WitchSlotView): bool =
    if v.lastField.len != 0 and v.paidLines.len != 0 and not v.lastField.contains(ElementType.Wild.int8) and v.paidLines.len > 0 and v.fsStatus == FreespinStatus.No:
        if v.cheatMagicSpin:
            v.cheatMagicSpin = false
            return true
        let r = rand(100)
        if r < v.pd.magicSpinChance:
            return true

proc setMagicSpinIndex(v: WitchSlotView) =
    v.currentMagicSpinReel = rand(2)

############ ---- MAGIC SPIN END -------- #############

proc moveWildBack(v: WitchSlotView) =
    if v.wildChildIndex != -1:
        v.elementsParent.insertChild(v.elementsParent.children[0], v.wildChildIndex)
    for elem in v.currentElements:
        if elem.eType == ElementType.Wild:
            v.wildChildIndex = v.elementsParent.children.find(elem.node.parent)
            v.elementsParent.insertChild(elem.node.parent, 0)
            return
    v.wildChildIndex = -1


proc fillField*(v: WitchSlotView, field: seq[int8], firstFill: bool = false): Animation {.discardable.} =
    v.currentElements = @[]

    let ms = v.isMagicSpin()
    var riIndex: int
    var reelIndexes: seq[int] = @[]
    var fake: seq[WitchElement]

    if ms:
        v.setMagicSpinIndex()
        reelIndexes = reelToIndexes(v.currentMagicSpinReel)
        fake = v.generateFakeSymbols(v.currentMagicSpinReel)

    for i in 1..ELEMENTS_COUNT:
        closureScope:
            let index = i - 1
            var element: WitchElement

            if firstFill or not ms or (ms and not reelIndexes.contains(index)):
                element = v.createElement(field[index].ElementType, index)
            else:
                element = fake[riIndex]
                riIndex.inc()
            let parent = v.elementsParent.findNode("element_" & $i)

            parent.removeAllChildren()
            v.addGlareNode(element)
            parent.addChild(element.node)
            element.node.position = SHIFT
            v.currentElements.add(element)

            let t = v.playElementEnter(index, 150)
            var r: float = 0

            if element.eType != ElementType.Wild:
                r = rand(0.5)
            v.setTimeout t + r, proc() =
                v.playElementIdle(element)
    result = v.elementsParent.animationNamed("spin")
    v.addAnimation(result)
    result.loopDuration = 2.0
    result.addLoopProgressHandler 0.2, false, proc() =
        v.moveWildBack()

proc firstFill*(v: WitchSlotView) =
    var field: seq[int8] = @[]
    var hasRune: bool
    var hasScatter: bool
    var startElement = 1

    for i in 1..ELEMENTS_COUNT:
        let r = rand(startElement..10)

        if r == 1:
            hasScatter = true
        if r > 1 and r < 6:
            hasRune = true

        if hasScatter:
            startElement = 2
        if hasRune:
            startElement = 6
        field.add(r.int8)
    v.fillField(field, true)

    let anim = v.elementsParent.animationNamed("spin")
    anim.loopDuration = 0.1
    v.addAnimation(anim)

proc elementsOut*(v: WitchSlotView): Animation {.discardable.} =
    result = v.elementsParent.animationNamed("out")
    v.addAnimation(result)
    for elem in v.currentElements:
        if elem.eType == ElementType.Wild:
            let spider = elem.node
            spider.reattach(v.elementsParent, 0)
            let upAnim = newAnimation()

            let pY = spider.positionY
            upAnim.numberOfLoops = 1
            upAnim.loopDuration = 1.2
            upAnim.onAnimate = proc(p: float) =
                let ease = elasticEaseIn(p, 1.2)
                spider.positionY = interpolate(pY, pY - 900, ease)
            v.addAnimation(upAnim)
            upAnim.onComplete do():
                spider.removeFromParent()


proc elementToWeb*(v: WitchSlotView, index: int) =
    let hive = v.createElement(ElementType.Hive, index)
    let parent = v.elementsParent.findNode("element_" & $(index + 1))
    let cocoon = hive.node.animationNamed("cocoon")
    const DELAY_PROGRESS = 0.2

    proc scaleRec(n: Node, s: Vector3) =
        if n.children.len == 0:
            n.scale = s
        else:
            for c in n.children:
                c.scaleRec(s)

    v.addGlareNode(hive)
    parent.addChild(hive.node)
    hive.node.position = SHIFT
    hive.node.findNode("hive_idle").enabled = false
    hive.node.findNode("hive_win").enabled = false
    v.addAnimation(cocoon)
    cocoon.addLoopProgressHandler DELAY_PROGRESS, false, proc() =
        let anim = newAnimation()

        anim.numberOfLoops = 1
        anim.loopDuration = cocoon.loopDuration * 1.0 - DELAY_PROGRESS
        anim.onAnimate = proc(p: float) =
            let s = interpolate(newVector3(1.0, 1.0), newVector3(), p)
            scaleRec(v.currentElements[index].node, s)
        v.addAnimation(anim)
        anim.onComplete do():
            v.currentElements[index].node.removeFromParent()
            v.currentElements[index] = hive
            hive.node.findNode("hive_idle").enabled = true
            hive.node.findNode("hive_win").enabled = true
            v.playElementIdle(hive)
