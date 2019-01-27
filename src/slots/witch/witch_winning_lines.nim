import rod.node
import rod.viewport
import rod.quaternion
import nimx.types
import nimx.matrixes
import nimx.animation
import core.slot.base_slot_machine_view
import shared.gui.win_panel_module
import shared.gui.money_panel_module
import shared.gui.spin_button_module
import utils.sound_manager
import witch_slot_view
import witch_line_numbers
import witch_character
import witch_elements
import random
import sets
import strutils

proc removeSymbolGlare(v: WitchSlotView, index: int, immediately: bool = false) =
    if v.currentElements.len != 0:
        for c in v.currentElements[index].glareNode.children:
            if c.name == "symbol_glare":
                if immediately:
                    c.removeAllChildren()
                else:
                    var c = v.currentElements[index].glareNode.childNamed("symbol_glare")

                    if c.isNil and v.isSecondaryElement(index):
                        c = v.elementsParent.findNode("element_" & $(index + 1) & "_2").findNode("symbol_glare")

                    if not c.isNil:
                        let idle = c.animationNamed("idle")
                        let anim = c.animationNamed("out")

                        idle.cancel()
                        v.addAnimation(anim)
                        anim.addLoopProgressHandler 1.0, true, proc() =
                            c.removeFromParent()

proc stopAllGlares*(v: WitchSlotView, immediately: bool = false) =
    for i in 0..<ELEMENTS_COUNT:
        v.removeSymbolGlare(i, immediately)

proc lightSymbolGlare(v: WitchSlotView, index: int) =
    var parent = v.currentElements[index].glareNode
    let glare = newNodeWithResource("slots/witch_slot/winning_line/precomps/symbol_glare.json")
    let animIn = glare.animationNamed("in")
    let animIdle = glare.animationNamed("idle")
    let rotationParent = glare.findNode("rune_rotation")
    let rotAnim = newAnimation()

    if v.isSecondaryElement(index):
        parent = v.elementsParent.findNode("element_" & $(index + 1) & "_2").findNode("glare_parent")

    rotAnim.loopDuration = 40
    rotAnim.numberOfLoops = 1
    rotAnim.onAnimate = proc(p: float) =
        rotationParent.rotation = newQuaternionFromEulerXYZ(0.0, 0.0, interpolate(0.0, 360.0, p))

    if not parent.isNil:
        parent.addChild(glare)
        v.addAnimation(animIn)
        v.addAnimation(rotAnim)
        animIn.onComplete do():
            v.addAnimation(animIdle)
            animIdle.numberOfLoops = -1

proc lightLineGlare(v: WitchSlotView, pl: PaidLine) =
    const DELAY = 0.1
    let allSymbols = v.getSymbolIndexesForLine(v.lines[pl.index])

    for i in 0..<pl.winningLine.numberOfWinningSymbols:
        closureScope:
            let index = i

            v.setTimeout index.float * DELAY, proc() =
                let curIndex = allSymbols[index]
                v.lightSymbolGlare(curIndex)

proc createLinePool(v: WitchSlotView, pIndex: seq[int], angles: seq[float], scl: seq[float], offsets: seq[Vector3]): seq[Node] =
    result = @[]
    for i in 0..<pIndex.len:
        let parent = v.currentElements[pIndex[i]].glareNode
        let line = newNodeWithResource("slots/witch_slot/winning_line/precomps/line.json")

        parent.addChild(line)
        line.findNode("line_rotation").rotation = newQuaternionFromEulerXYZ(0.0, 0.0, angles[i])
        line.position = parent.position + newVector3(960, 588) + offsets[i]
        line.findNode("line_rotation").scaleX = scl[i]
        result.add(line)


proc playLinePool(v: WitchSlotView, lines: seq[Node], curIndex: int = 0) =
    let anim = lines[curIndex].animationNamed("play")
    let duration = 1.5 / lines.len.float

    anim.loopDuration = duration
    anim.addLoopProgressHandler 0.7, false, proc() =
        if curIndex + 1 < lines.len:
            v.playLinePool(lines, curIndex + 1)
    anim.onComplete do():
        lines[curIndex].removeFromParent()
    v.addAnimation(anim)

proc playWinningLine(v: WitchSlotView, index: int) =
    var lines: seq[Node]

    case index
    of 0:
        lines = v.createLinePool(@[5, 7], @[0.0, 0.0], @[1.0, 1.0], @[newVector3(-50.0, 20.0), newVector3(-50.0, 20.0)])
    of 1:
        lines = v.createLinePool(@[0, 2], @[0.0, 0.0], @[1.0, 1.0], @[newVector3(-50.0, 20.0), newVector3(-50.0, 20.0)])
    of 2:
        lines = v.createLinePool(@[10, 12], @[0.0, 0.0], @[1.0, 1.0], @[newVector3(-50.0, 20.0), newVector3(-50.0, 20.0)])
    of 3:
        lines = v.createLinePool(@[0, 12], @[40.0, -37.0], @[1.0, 1.0], @[newVector3(0.0, 0.0), newVector3(0.0, 0.0)])
    of 4:
        lines = v.createLinePool(@[10, 2], @[-35.0, 37.0], @[1.0, 1.0], @[newVector3(0.0, 0.0), newVector3(0.0, 0.0)])
    of 5:
        lines = v.createLinePool(@[5, 1, 13], @[-37.0, 37.0, -37.0], @[0.5, 1.0, 0.5], @[newVector3(0.0, 0.0), newVector3(0.0, 0.0), newVector3(0.0, 0.0)])
    of 6:
        lines = v.createLinePool(@[5, 11, 3], @[43.0, -35.0, 40.0], @[0.5, 1.0, 0.5], @[newVector3(0.0, 0.0), newVector3(0.0, 0.0), newVector3(0.0, 0.0)])
    of 7:
        lines = v.createLinePool(@[0, 1, 13], @[0.0, 37.0, 0.0], @[0.5, 1.0, 0.5], @[newVector3(-50.0, 20.0), newVector3(0.0, 0.0), newVector3(-50.0, 20.0)])
    of 8:
        lines = v.createLinePool(@[10, 11, 3], @[0.0, -35.0, 0.0], @[0.5, 1.0, 0.5], @[newVector3(-50.0, 20.0), newVector3(0.0, 0.0), newVector3(-50.0, 20.0)])
    of 9:
        lines = v.createLinePool(@[0, 6, 2, 8], @[37.0, -37.0, 37.0, -37.0], @[0.5, 0.5, 0.5, 0.5], @[newVector3(0.0, 0.0), newVector3(0.0, 0.0), newVector3(0.0, 0.0), newVector3(0.0, 0.0)])
    of 10:
        lines = v.createLinePool(@[10, 6, 12, 8], @[-37.0, 37.0, -37.0, 40.0], @[0.5, 0.5, 0.5, 0.5], @[newVector3(0.0, 0.0), newVector3(0.0, 0.0), newVector3(0.0, 0.0), newVector3(0.0, 0.0)])
    of 11:
        lines = v.createLinePool(@[5, 1, 3], @[-37.0, 0.0, 37.0], @[0.5, 1.0, 0.5], @[newVector3(0.0, 0.0), newVector3(-100.0, 20.0), newVector3(0.0, 0.0)])
    of 12:
        lines = v.createLinePool(@[5, 11, 13], @[40.0, 0.0, -37.0], @[0.5, 1.0, 0.5], @[newVector3(0.0, 0.0), newVector3(-100.0, 20.0), newVector3(0.0, 0.0)])
    of 13:
        lines = v.createLinePool(@[0, 6, 8], @[40.0, 0.0, -37.0], @[0.5, 1.0, 0.5], @[newVector3(0.0, 0.0), newVector3(-100.0, 20.0), newVector3(0.0, 0.0)])
    of 14:
        lines = v.createLinePool(@[10, 6, 8], @[-37.0, 0.0, 37.0], @[0.5, 1.0, 0.5], @[newVector3(0.0, 0.0), newVector3(-100.0, 20.0), newVector3(0.0, 0.0)])
    of 15:
        lines = v.createLinePool(@[5, 6, 2, 8], @[0.0, -37.0, 37.0, 0.0], @[0.5, 0.5, 0.5, 0.5], @[newVector3(-100.0, 20.0), newVector3(0.0, 0.0), newVector3(0.0, 0.0), newVector3(-100.0, 20.0)])
    of 16:
        lines = v.createLinePool(@[5, 6, 12, 8], @[0.0, 37.0, -37.0, 0.0], @[0.5, 0.5, 0.5, 0.5], @[newVector3(-100.0, 20.0), newVector3(0.0, 0.0), newVector3(0.0, 0.0), newVector3(-100.0, 20.0)])
    of 17:
        lines = v.createLinePool(@[0, 11, 2, 13], @[60.0, -55, 55.0, -60.0], @[0.8, 0.8, 0.8, 0.8], @[newVector3(0.0, 0.0), newVector3(0.0, 0.0), newVector3(0.0, 0.0), newVector3(0.0, 0.0)])
    of 18:
        lines = v.createLinePool(@[10, 1, 12, 3], @[-60.0, 55.0, -55.0, 60.0], @[0.8, 0.8, 0.8, 0.8], @[newVector3(0.0, 2.0), newVector3(0.0, 0.0), newVector3(0.0, 0.0), newVector3(0.0, 0.0)])
    of 19:
        lines = v.createLinePool(@[10, 1, 7, 3], @[-60.0, 37.0, -37.0, 60.0], @[0.8, 0.5, 0.5, 0.8], @[newVector3(0.0, 2.0), newVector3(0.0, 0.0), newVector3(0.0, 0.0), newVector3(0.0, 0.0)])
    else:
        discard
    v.playLinePool(lines)

proc playWinningSymbols(v: WitchSlotView, pl: PaidLine) =
    const DELAY = 0.1
    let allSymbols = v.getSymbolIndexesForLine(v.lines[pl.index])

    for i in 0..<pl.winningLine.numberOfWinningSymbols:
        closureScope:
            if v.lastField.len == ELEMENTS_COUNT:
                let index = i
                let curIndex = allSymbols[index]
                let sym = v.lastField[curIndex]
                var node = v.currentElements[curIndex].node
                var animAdded: Animation

                if v.isSecondaryElement(curIndex):
                    node = v.elementsParent.findNode("element_" & $(curIndex + 1) & "_2").children[1]

                var anim = node.animationNamed("win")
                if sym == Symbols.Wild.int8:
                    let inside = node.findNode("spider_inside")

                    anim = inside.animationNamed("win")
                    inside.findNode("glow_wild").enabled = true
                elif sym >= Symbols.Red.int8 and sym <= Symbols.Blue.int8:
                    if node.findNode("rune_after_fall").enabled:
                        anim = node.findNode("rune_after_fall").animationNamed("win")
                    else:
                        anim = node.findNode("rune_before_fall").animationNamed("win")
                    if sym == Symbols.Red.int8 or sym == Symbols.Yellow.int8:
                        animAdded = node.findNode("yellow_red").animationNamed("win")
                    else:
                        animAdded = node.findNode("blue_green").animationNamed("win")
                elif sym == Symbols.Mandragora.int8:
                        v.soundManager.sendEvent("HIGLIGHT_WINNING_MANDRAGORA")
                elif sym == Symbols.Plant.int8:
                    v.soundManager.sendEvent("HIGLIGHT_WINNING_PLANT")

                v.setTimeout index.float * DELAY, proc() =
                    v.addAnimation(anim)
                    if sym == Symbols.Plant.int8:
                        let spittles = node.findNode("spittles")

                        if not spittles.isNil:
                            spittles.enabled = false
                    anim.onComplete do():
                        v.playElementIdle(v.currentElements[curIndex])
                    if not animAdded.isNil:
                        v.addAnimation(animAdded)

proc playAllWinning(v: WitchSlotView, pl: PaidLine): Animation {.discardable.} =
    result = newAnimation()

    result.numberOfLoops = 1
    result.loopDuration = 2.0
    v.playWinningLine(pl.index)
    v.playWinningSymbols(pl)
    v.addAnimation(result)

proc addNumbers(v: WitchSlotView, pl: PaidLine) =
    let middle = v.getSymbolIndexesForLine(v.lines[pl.index])[2]
    let nums = v.createWinLineNumbers(v.winNumbersParent, pl.winningLine.payout)
    var offset = newVector3(0, -300)

    if middle == 7:
        offset = newVector3(0, -100)
    elif middle == 12:
        offset = newVector3(0, 120)
    nums.position = nums.position + offset

proc playScattersWin*(v: WitchSlotView): Animation {.discardable.} =
    for i in 0..<v.currentElements.len:
        var node = v.currentElements[i].node

        if v.lastField[i] == Symbols.Scatter.int8:
            v.lightSymbolGlare(i)
            if v.isSecondaryElement(i):
                node = v.elementsParent.findNode("element_" & $(i + 1) & "_2").children[1]

            var anim = node.animationNamed("win")
            v.addAnimation(anim)
            result = anim

proc scatterPlus(v: WitchSlotView) =
    if v.fsStatus == FreespinStatus.Yes:
        let scatters = v.countSymbols(Symbols.Scatter.int8)

        if scatters > 0:
            assert(scatters >= 1 and scatters <= 5)
            let anim = v.freespinsPlus.animationNamed("play")

            v.playScattersWin()
            for c in v.freespinsPlus.children:
                if c.name.contains("number_"):
                    c.enabled = false
            v.freespinsPlus.childNamed("number_" & $scatters).enabled = true
            v.addAnimation(anim)
            anim.addLoopProgressHandler 0.4, false, proc() =
                v.slotGUI.spinButtonModule.setFreespinsCount(v.freeSpinsCount)

proc playRandomWinSound(v: WitchSlotView) =
    let random_sound_index = rand(1 .. 3)
    v.soundManager.sendEvent("WIN_SOUND_" & $random_sound_index)

proc showLines(v: WitchSlotView, index: int = 0) =
    if v.paidLines.len > 0:
        let pl = v.paidLines[index]
        let next = index + 1
        v.playRandomWinSound()
        let anim = v.playAllWinning(pl)
        v.actionButtonState = SpinButtonState.StopAnim

        v.addNumbers(pl)
        if v.currWinningWitchAnim.isNil or v.currWinningWitchAnim.finished:
            v.currWinningWitchAnim = v.playWitchWin()
            v.currWinningWitchAnim.cancelBehavior = cbContinueUntilEndOfLoop
        v.currentWin += pl.winningLine.payout
        v.slotGUI.winPanelModule.setNewWin(v.currentWin)
        anim.addLoopProgressHandler 0.7, false, proc() =
            if  next < v.paidLines.len and not v.interruptLinesAnim:
                v.showLines(next)
            else:
                let oldBalance = v.slotGUI.moneyPanelModule.getBalance()

                v.stopAllGlares()
                v.scatterPlus()
                v.chipsAnim(v.rootNode.findNode("total_bet_panel"), oldBalance, oldBalance + v.linesWin, "Spin")
                v.actionButtonState = SpinButtonState.Blocked
                if v.currWinningWitchAnim.finished:
                    v.pushNextState()
                else:
                    v.currWinningWitchAnim.onComplete do():
                        v.startIdle()
                        v.pushNextState()
                    v.currWinningWitchAnim.cancel()
    else:
        v.scatterPlus()
        v.pushNextState()

proc lightFieldGlares(v: WitchSlotView): float =
    let TIMEOUT = 0.2
    let SCATTERS_WIN_COUNT = 3

    var winningSymbols = initSet[int]()

    for pl in v.paidLines:
        let allSymbols = v.getSymbolIndexesForLine(v.lines[pl.index])

        for i in 0..<pl.winningLine.numberOfWinningSymbols:
            winningSymbols.incl(allSymbols[i])

    if v.countSymbols(Symbols.Scatter.int8) >= SCATTERS_WIN_COUNT:
        for i in 0..<v.lastField.len:
            if v.lastField[i] == Symbols.Scatter.int8:
                winningSymbols.incl(i)

    for i in 0..<NUMBER_OF_REELS:
        closureScope:
            let ii = i
            v.setTimeout TIMEOUT * ii.float(), proc() =
                let indexes = reelToIndexes(ii)
                for index in indexes:
                    if winningSymbols.contains(index):
                        v.lightSymbolGlare(index)

    result = v.getLastWinLineReel().float * TIMEOUT

proc showLinesAndGlares*(v: WitchSlotView, index: int = 0) =
    let timeout = v.lightFieldGlares()

    v.setTimeout timeout, proc() =
        v.showLines()

proc showRepeatingSymbols*(v: WitchSlotView) =
    const DELAY = 3.0

    v.repeatWinAnim = newAnimation()
    v.repeatWinAnim.loopDuration = DELAY * v.paidLines.len.float
    v.repeatWinAnim.numberOfLoops = -1
    for i in 0..<v.paidLines.len:
        closureScope:
            let index = i
            let symProgress = 1.0 / v.paidLines.len.float * index.float
            let numsProgress = symProgress + 0.3 / v.paidLines.len.float
            let pl = v.paidLines[index]
            let allSymbols = v.getSymbolIndexesForLine(v.lines[pl.index])
            let sym = v.currentElements[allSymbols[0]].eType.int8
            let rndRune = rand(1 .. 2)

            v.repeatWinAnim.addLoopProgressHandler symProgress, false, proc() =
                v.stopAllGlares(true)
                v.lightLineGlare(pl)
                v.playWinningSymbols(pl)
                v.playWinningLine(pl.index)
                if sym == Symbols.Web.int8:
                    v.soundManager.sendEvent("HIGHLIGHT_WINNING_WEB")
                elif sym >= Symbols.Red.int8 and sym <= Symbols.Blue.int8:
                    v.soundManager.sendEvent("HIGHLIGHT_WINNING_RUNE_" & $rndRune)
                elif sym == Symbols.Mandragora.int8:
                    v.soundManager.sendEvent("HIGLIGHT_WINNING_MANDRAGORA")
                elif sym == Symbols.Plant.int8:
                    v.soundManager.sendEvent("HIGLIGHT_WINNING_PLANT")
                else:
                    v.soundManager.sendEvent("HIGHLIGHT_WINNING")
            v.repeatWinAnim.addLoopProgressHandler numsProgress, false, proc() =
                v.addNumbers(pl)
    v.addAnimation(v.repeatWinAnim)
