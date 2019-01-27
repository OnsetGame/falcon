import nimx / [ view, context, button, animation, window, timer, types, matrixes,
                notification_center ]
import rod / [ component, rod_types, node, viewport, quaternion, asset_bundle ]
import rod / component / [ solid, sprite, ui_component, text_component, visual_modifier,
                            ae_composition, clipping_rect_component, trail ]

import core.slot.base_slot_machine_view
import shared / [ user, director]
import shared / window / [ window_manager, button_component ]
import shared / gui / [ gui_module, win_panel_module, total_bet_panel_module, paytable_open_button_module,
                         spin_button_module, money_panel_module, slot_gui, win_panel_module ]
import utils / [sound, sound_manager, falcon_analytics, falcon_analytics_utils, pause,
                 console, animation_controller, and_gate, fade_animation, helpers]
import core.net.server
import falconserver / slot / [slot_data_types, machine_base_types ]

import logging, tables, random, json, strutils, sequtils, algorithm, times, macros, math, quest.quests

import ufo_types, ufo_aliens, ufo_bonus_game, ufo_msgs, ufo_anticipation
import ufo_paytable , ufo_colorize, ufo_particles
import core / flow / flow_state_types

const RichAnimationSymbols = [Symbols.Bonus, Symbols.Dog, Symbols.Elk, Symbols.Pig, Symbols.Barrow]
const REEL_STOP_EVENT_NAME = "reel_"

proc fillAnimReels(v: UfoSlotView)
proc startSpinAnimationForReel(v: UfoSlotView, reelIndex: int, cb: proc() = nil)
proc startSpinAnimation(v: UfoSlotView, cb: proc())
proc startSpin(v: UfoSlotView, cb: proc())
proc startIdleAnims(v: UfoSlotView)
proc findNodeStartsWith*(n: Node, pref: string, res: var seq[Node])

proc isWildSymbol(sym:Symbols): bool =
    result = (sym == Symbols.Wild_Red) or (sym == Symbols.Wild_Green)

proc fadeInAndOutWithSomeLogicInside(v: UfoSlotView, duration:float, inTheMiddle:proc() = nil, inTheEnd: proc() = nil) =
    v.fadeAnim.animation.onComplete do():
        if not inTheMiddle.isNil:
            inTheMiddle()
        v.fadeAnim.animation.removeHandlers()
        v.fadeAnim.animation.onComplete do():
            if not inTheEnd.isNil:
                inTheEnd()
            v.fadeAnim.animation.removeHandlers()
        v.fadeAnim.changeFadeAnimMode(0.0, duration / 2.0)

    v.fadeAnim.changeFadeAnimMode(1.0, duration / 2.0)

proc getScaleForSymb(n: Node, inUfo: bool = true): Vector3 =
    const
        sv = newVector3(0.8,0.8,0.8)
        dv = newVector3(1.0,1.0,1.0)
    let
        dst = SYMBOL_SIZE * NUMBER_OF_ROWS
        wp = n.worldPos().y
        trig = SYMBOL_SIZE + SYMBOL_SIZE/2.0
    if wp > SYMBOL_SIZE * 5  or wp < -SYMBOL_SIZE:
        result = dv
    else:
        result = interpolate(sv, dv, wp / dst.float)
        # let ufop = wp + n.parent.parent.worldPos().y
        if wp < trig and inUfo:
            let vs = newVector3(0.5, 1.8, 0.8)
            result = interpolate(vs, result, wp / trig)

proc clearElementForPlaceholder(v: UfoSlotView, placeholderIndex: int) =
    let allElems = v.placeholders[placeholderIndex].findNode("all_elements")
    for ch in allElems.children:
        if ch.alpha > 0.9:
            let symId:Symbols = parseEnum[Symbols](ch.name)
            let  curAnimation = v.symbolsAC[placeholderIndex][symId].curAnimation
            if not curAnimation.isNil:
                curAnimation.removeHandlers()
                curAnimation.cancel()
        ch.alpha = 0.0

proc restoreWildesOnField(v: UfoSlotView) =
    for jn in v.wp:
        var pos = jn["pos"]
        var index = 0
        if pos.len > 0:
            let x = pos[index].getInt()
            let y = pos[index+1].getInt()
            let wild_id = jn["id"].getInt()
            var real_wild_id = 0
            if wild_id == 4:
                real_wild_id = 1
            let wild_pos_on_field = x + y * NUMBER_OF_REELS
            v.lastField[wild_pos_on_field] = real_wild_id.int8
            v.clearElementForPlaceholder(wild_pos_on_field)

proc stopAnticipation(v: UfoSlotView) =
    if not v.anticipator.isNil:
        v.anticipator.stop()
        v.anticipator = nil
        v.startIdleAnims()
        v.stopAnticipationParticle()

proc startAnticipation(v: UfoSlotView) =
    if v.anticipator.isNil:
        v.soundManager.sendEvent("ANTICIPATION_RINGS")
        if not v.alienLeft.inWild:
            v.alienLeft.setAnimState(AlienAnimStates.Anticipation)
        if not v.alienRight.inWild:
            v.alienRight.setAnimState(AlienAnimStates.Anticipation)
        v.anticipator = v.anticipate()
        v.addAnticipationParticle()

proc clearReels(v: UfoSlotView)=
    for i,plac in v.placeholders:
        v.clearElementForPlaceholder(i)

proc fillReels(v: UfoSlotView, field: openarray[int8])=
    doAssert(field.len == ELEMENTS_COUNT)

    v.clearReels()
    for i, val in field:
        closureScope:
            var index = i
            var capVal = val
            var placeholder = v.placeholders[index]
            let reel = indexToPlace(i).x


            if isWildSymbol(capVal.Symbols):
                if v.meetIndex == i:
                    capVal = Portal.int8
                else:
                    if capVal == Wild_Red.int8:
                        capVal = TargetRed.int8
                    elif capVal == Wild_Green.int8:
                        capVal = TargetBlue.int8

            var symb = placeholder.findNode($capVal.Symbols)
            if not symb.isNil:
                symb.alpha = 1.0
                v.symbolsAC[i][capVal.Symbols].playIdles(true)
            else:
                info "sym not found ", val.Symbols

            if isWildSymbol(capVal.Symbols):
                placeholder.scale = newVector3(1.0,1.0,1.0)
            else:
                placeholder.scale = placeholder.getScaleForSymb()


proc playRandomWinLineSound(v: UfoSlotView) =
    let randIndex = rand(1..3)
    let sound = "WIN_LINE_"& $randIndex
    v.soundManager.sendEvent(sound)

proc constructWinLineFromBeams(v: UfoSlotView, line_index:int = 19): Animation

proc clearWinNumbers(v: UfoSlotView) =
    for n in v.winLineNumbers:
        n.removeFromParent()
    v.winLineNumbers.setLen(0)

proc winElemenstsHighlightsToIdle(v: UfoSlotView) =
    for i in 0..v.lastField.high:
        let symOnField = v.lastField[i.int8].Symbols
        if symOnField in Symbols.Pig..Symbols.Pumpkin:
            let ac = v.symbolsAC[i][symOnField]
            if not ac.curAnimation.isNil and ac.curAnimation.tag == "h":
                ac.curAnimation.continueUntilEndOfLoopOnCancel = false
                ac.curAnimation.cancel()

proc hideBonusElementsHighlights(v: UfoSlotView) =
    for elNode in v.bonusElementSmokeHighlights:
        elNode.hide(0.3, proc() = elNode.removeFromParent())
    v.bonusElementSmokeHighlights = @[]

proc clearHighlights(v: UfoSlotView) =
    v.winElemenstsHighlightsToIdle()
    for hl in v.elementSmokeHighlights:
        hl.hide(0.3, proc() = hl.removeFromParent())
    v.elementSmokeHighlights = @[]

    v.hideBonusElementsHighlights()

    for ha in v.elementHighlightsAnims:
        ha.cancel
    v.elementHighlightsAnims.setLen(0)

proc addSmokeHighLightToElement(v: UfoSlotView, elementNode: Node, pos: Vector3, symId: Symbols) =
    let highlightElement = newNodeWithResource("slots/ufo_slot/slot/scene/highlight_element")

    discard highlightElement.component(VisualModifier)

    if v.isForceStop and v.havePotential:
        if symId != Symbols.Bonus:
            return

    if v.isForceStop and v.haveBonusPotential:
        if symId == Symbols.Bonus:
            return

    highlightElement.alpha = 0
    elementNode.insertChild(highlightElement, 0)
    highlightElement.position = pos
    let anim = highlightElement.animationNamed("start")
    anim.numberOfLoops = -1
    v.addAnimation(anim)
    highlightElement.show(0.5)
    if symId == Symbols.Bonus:
        v.bonusElementSmokeHighlights.add(highlightElement)
    else:
        v.elementSmokeHighlights.add(highlightElement)


proc addLineWinningNumbers(v: UfoSlotView, amount: int64, lineIndex: int) =
    const MIDDLE_REEL = 2
    const OFFSET = newVector3(470, 90)
    let numbers = newNodeWithResource("slots/ufo_slot/shared/precomps/ufo_count")
    let indexes = reelToIndexes(MIDDLE_REEL)
    let anim = numbers.animationNamed("start")
    let row = v.lines[lineIndex][MIDDLE_REEL]

    for i in 1..2:
        for j in 1..5:
            numbers.findNode("numbers_" & $i).findNode("count_" & $j).getComponent(Text).text = $amount

    v.addAnimation(anim)
    numbers.anchor = OFFSET
    v.ufoReels[MIDDLE_REEL].reelNode.findNode("placeholder_" & $indexes[row]).addChild(numbers)
    numbers.reattach(v.winLineNumbersParent)
    anim.onComplete do():
        numbers.removeFromParent()
    v.winLineNumbers.add(numbers)

proc createBonusSymbolsHighlights(v: UfoSlotView) =
    if v.stage == GameStage.Bonus:
        for i,sym in v.lastField:
            if sym == Symbols.Bonus.int8:
                let ri = i mod NUMBER_OF_REELS
                v.highlightReelSymbols[ri].add(i.int)
    else:
        var bonusSymbolsPos = newSeq[int]()
        for i in 0..NUMBER_OF_ROWS-1:
            let indexInFirstReel = i * NUMBER_OF_REELS
            let indexInLastReel = NUMBER_OF_REELS-1 + i * NUMBER_OF_REELS
            if v.lastField[indexInFirstReel] == Symbols.Bonus.int8:
                bonusSymbolsPos.add(indexInFirstReel)

            if v.lastField[indexInLastReel] == Symbols.Bonus.int8:
                bonusSymbolsPos.add(indexInLastReel)

        if bonusSymbolsPos.len == 2:
            v.haveBonusPotential = true
            v.highlightReelSymbols[0].add(bonusSymbolsPos[0])
            v.highlightReelSymbols[1].add(bonusSymbolsPos[1])

proc createWinLineSymbolsHighlights(v: UfoSlotView) =
    var linesWithPayout = newSeq[PaidLine]()
    for line in v.paidLines:
        if line.winningLine.payout > 0:
            linesWithPayout.add(line)

    let firstReverseLineIndex = 10

    for ri in 0..v.highlightReelSymbols.high:
        v.highlightReelSymbols[ri] = newSeq[int]()

    if linesWithPayout.len > 0:
        for paidLine in linesWithPayout:
            let lineIsReverse = paidLine.index >= (v.lines.len div 2)
            let winLine = v.lines[paidLine.index]
            for i in 0..<NUMBER_OF_REELS:
                var reelIndex = i
                if lineIsReverse:
                    reelIndex = NUMBER_OF_REELS-1 - i
                if i >= paidLine.winningLine.numberOfWinningSymbols:
                    break
                let symPosIndex = reelIndex + winLine[reelIndex]*NUMBER_OF_REELS
                if symPosIndex notin v.highlightReelSymbols[reelIndex]:
                    v.highlightReelSymbols[reelIndex].add(symPosIndex)
    else:
        if not v.isForceStop:
            for i in 0..<firstReverseLineIndex:
                let line = v.lines[i]
                let sym1Index = line[0]*NUMBER_OF_REELS
                let sym1 = v.lastField[sym1Index]
                let sym2Index = 1 + line[1]*NUMBER_OF_REELS
                let sym2 = v.lastField[sym2Index]
                if sym1==sym2:
                    if sym1Index notin v.highlightReelSymbols[0]:
                        v.highlightReelSymbols[0].add(sym1Index)
                    if sym2Index notin v.highlightReelSymbols[1]:
                        v.highlightReelSymbols[1].add(sym2Index)

            for i in firstReverseLineIndex..v.lines.high:
                let line = v.lines[i]
                let sym1Index = 3 + line[3]*NUMBER_OF_REELS
                let sym1 = v.lastField[sym1Index]
                let sym2Index = 4 + line[4]*NUMBER_OF_REELS
                let sym2 = v.lastField[sym2Index]
                #echo "[$#] $#,$# $#".format($i,$sym1,$sym2,sym1==sym2)
                if sym1==sym2:
                    if sym1Index notin v.highlightReelSymbols[3]:
                        v.highlightReelSymbols[3].add(sym1Index)
                    if sym2Index notin v.highlightReelSymbols[4]:
                        v.highlightReelSymbols[4].add(sym2Index)

            v.havePotential = any(v.highlightReelSymbols, proc(s:seq[int]):bool = s.len > 0)

    v.createBonusSymbolsHighlights()

proc startWinLinesAnim(v: UfoSlotView, callback: proc() = nil)=

    proc highlightWild(ma:MainAlien, phIndex:int) =
        for wa in ma.activeWilds:
            if wa.curPlaceIndex == phIndex and not wa.isMoving and not v.isForceStop and wa.curAnimationState != AlienAnimStates.WildToPortal:
                wa.setAnimState(AlienAnimStates.WildWin)
                break

    var linesWithPayout = newSeq[PaidLine]()
    var isRepeat = false
    for line in v.paidLines:
        if line.winningLine.payout > 0:
            linesWithPayout.add(line)

    proc winAnimationsForLines(winLines:seq[PaidLine]):seq[Animation] =
        var anims = newSeq[Animation]()
        v.elementHighlightsAnims = newSeq[Animation]()

        if winLines.len > 0:
            for paidLine in winLines:
                closureScope:
                    let closePaidLine = paidLine
                    let winLine = v.lines[closePaidLine.index]
                    let winLineAnim = v.constructWinLineFromBeams(closePaidLine.index)
                    let payout = closePaidLine.winningLine.payout
                    let lineIndex = closePaidLine.index

                    winLineAnim.addLoopProgressHandler 0.0, false, proc()=
                        let lineIsReverse = closePaidLine.index >= (v.lines.len div 2)

                        #v.clearHighlights()
                        #echo "lineIsReverse - ", lineIsReverse
                        v.addLineWinningNumbers(payout, lineIndex)
                        for j, reelNode in v.reels:
                            let reelIndex = j
                            var highlightSymIdx = reelIndex
                            if lineIsReverse:
                                highlightSymIdx = v.reels.high - reelIndex
                            if reelIndex >= closePaidLine.winningLine.numberOfWinningSymbols:
                                break
                            let placeholderIndex = highlightSymIdx + winLine[highlightSymIdx]*NUMBER_OF_REELS
                            let currentSymInPlaceholder = v.lastField[placeholderIndex].Symbols

                            if v.symbolsAC[placeholderIndex].hasKey(currentSymInPlaceholder):
                                var anim = v.symbolsAC[placeholderIndex][currentSymInPlaceholder].setImmediateAnimation("highlight")
                                anim.tag = "h"
                                v.elementHighlightsAnims.add(anim)
                                #v.addSmokeHighLightToElement(v.symbolsAC[placeholderIndex][currentSymInPlaceholder].node, newVector3(-50, -50))
                            else:
                                if currentSymInPlaceholder == Symbols.Wild_Red:
                                    highlightWild(v.alienLeft, placeholderIndex)
                                elif currentSymInPlaceholder == Symbols.Wild_Green:
                                    highlightWild(v.alienRight, placeholderIndex)
                                info "No AC for key ", $currentSymInPlaceholder

                        v.playRandomWinLineSound()
                    winLineAnim.addLoopProgressHandler 0.3, false, proc() =
                        if not isRepeat and not v.isForceStop:
                            v.slotGUI.winPanelModule.addToWin(payout, true)

                    anims.add(winLineAnim)

        result = anims

    proc repeatWinLineAnims() =
        isRepeat = true
        if not v.repeatWinLineAnims.isNil:
            v.clearWinNumbers()
            v.winLinesAnim = newCompositAnimation(false, winAnimationsForLines(linesWithPayout))
            v.winLinesAnim.numberOfLoops = 1
            v.winLinesAnim.cancelBehavior = CancelBehavior.cbJumpToEnd
            v.winLinesAnim.addLoopProgressHandler 1.0, true, proc()=
                repeatWinLineAnims()
            v.addAnimation(v.winLinesAnim)

    var wlAnims = winAnimationsForLines(linesWithPayout)

    if wlAnims.len > 0:
        v.winLinesAnim = newCompositAnimation(false, wlAnims)
        v.winLinesAnim.numberOfLoops = 1
        v.winLinesAnim.cancelBehavior = CancelBehavior.cbJumpToEnd
        v.winLinesAnim.addLoopProgressHandler 1.0, true, proc() =
            echo "winLinesAnim.onComplete"
            v.repeatWinLineAnims = repeatWinLineAnims
            if not callback.isNil:
                callback()

        v.addAnimation(v.winLinesAnim)
    else:
        if not callback.isNil:
            callback()

proc showFiveInARow(v: UfoSlotView, cb: proc()) =
    if v.check5InARow:
        v.winDialogWindow = show5InARow(v.rootNode.findNode("msgs_anchor"), v.rootNode.findNode("main_scene"), v.rootNode.findNode("main_scene_anchor"), cb)
    else:
        if not cb.isNil:
            cb()

proc cleanWinLineBeams(v: UfoSlotView)


proc updateCurrentBalance(v: UfoSlotView) =
    if v.totalWin > 0:
        let chipsFrom = v.currentBalance - v.totalWin - v.bonusWin
        let chipsTo = v.currentBalance - v.bonusWin
        let animated = not v.isForceStop


        if v.stage == GameStage.Respin or v.stageAfterBonus == GameStage.Respin:
            v.slotGUI.winPanelModule.setNewWin(v.reSpinsTotalWin, animated)
        else:
            v.slotGUI.winPanelModule.setNewWin(v.totalWin, false)
            v.chipsAnim(v.rootNode.findNode("total_bet_panel"), chipsFrom, chipsTo, "")

proc showWinning(v: UfoSlotView, cb: proc()) =
    if v.paidLines.len == 0:
        v.cleanWinLineBeams()

    if v.totalWin > 0:
        if not v.alienLeft.inWild:
            v.alienLeft.setAnimState(AlienAnimStates.Win)
        if not v.alienRight.inWild:
            v.alienRight.setAnimState(AlienAnimStates.Win)

    v.showFiveInARow do():
        v.startWinLinesAnim proc() =
            v.updateCurrentBalance()
            cb()

proc spawnNewWildAliens(v:UfoSlotView, callback: proc() = nil)

proc switchToBonus(v:UfoSlotView) =
    proc inTheMiddle() =
        v.bonusGame.prepareGame(v.sd.bonusSpins)
        v.soundManager.sendEvent("BONUS_GAME_MUSIC")
        v.soundManager.sendEvent("UFO_BONUS_AMBIENCE")
        v.mainLayer.enabled = false
    proc inTheEnd() =
        v.bonusGame.startGame()
        v.setSpinButtonState(SpinButtonState.Spin)

    v.fadeInAndOutWithSomeLogicInside(BONUS_TRANSITION_ANIM_TIME,inTheMiddle,inTheEnd)

proc isAllReelsStopped(v: UfoSlotView): bool =
    var isAllDone = true
    for b in v.reelsBusy:
        if b:
            isAllDone = not b
            break

    result = isAllDone

proc highlightWildSymbol(v: UfoSlotView, ma:MainAlien, phIndex:int) =
    for wa in ma.activeWilds:
        if wa.curPlaceIndex == phIndex and not wa.isMoving:
            v.addSmokeHighLightToElement(wa.node, newVector3(70, 170), wa.wildSymbolId)
            break

proc highlightSymbolsOnReel(v: UfoSlotView, reelIndex: int) =
    for i in 0..v.highlightReelSymbols[reelIndex].high:
        let index = v.highlightReelSymbols[reelIndex][i]
        let currentSymInPlaceholder = v.lastField[index].Symbols
        if v.symbolsAC[index].hasKey(currentSymInPlaceholder):
            v.addSmokeHighLightToElement(v.symbolsAC[index][currentSymInPlaceholder].node, newVector3(-50, -50), currentSymInPlaceholder)
        else:
            var ma:MainAlien = nil
            if currentSymInPlaceholder == Symbols.Wild_Red:
                ma = v.alienLeft
            elif currentSymInPlaceholder == Symbols.Wild_Green:
                ma = v.alienRight
            v.highlightWildSymbol(ma, index)

proc showSpecialWinMsg(v: UfoSlotView, winAmount:int64, cb: proc()) =
    let cipsBeforeWin = v.currentBalance - v.totalWin - v.bonusWin - v.reSpinsTotalWin
    let winType = v.getWinType(winAmount)

    if winType > WinType.Simple:
        if not v.alienLeft.inWild:
            v.alienLeft.setAnimState(AlienAnimStates.BigWin)
        if not v.alienRight.inWild:
            v.alienRight.setAnimState(AlienAnimStates.BigWin)


    case winType
    of WinType.Mega:
        v.onBigWinHappend(BigWinType.Mega, cipsBeforeWin)
        v.soundManager.sendEvent("MEGA_WIN")
        v.winDialogWindow = showMegaWin(v.rootNode.findNode("msgs_anchor"), v.rootNode.findNode("main_scene"), v.rootNode.findNode("main_scene_anchor"), winAmount, cb)
    of WinType.Huge:
        v.onBigWinHappend(BigWinType.Huge, cipsBeforeWin)
        v.soundManager.sendEvent("HUGE_WIN")
        v.winDialogWindow = showHugeWin(v.rootNode.findNode("msgs_anchor"), v.rootNode.findNode("main_scene"), v.rootNode.findNode("main_scene_anchor"), winAmount, cb)
    of WinType.Big:
        v.onBigWinHappend(BigWinType.Big, cipsBeforeWin)
        v.soundManager.sendEvent("BIG_WIN")
        v.winDialogWindow = showBigWin(v.rootNode.findNode("msgs_anchor"), v.rootNode.findNode("main_scene"), v.rootNode.findNode("main_scene_anchor"), winAmount, cb)
    else:
        cb()

proc showSpecialWinMsg(v: UfoSlotView, cb: proc()) =
    if v.stage == GameStage.Respin and v.reSpinsTotalWin > 0:
        cb()
    else:
        v.showSpecialWinMsg(v.totalWin, cb)

proc onAllReelsStopped(v: UfoSlotView, cb: proc()) =
    let randSpinEndSoundIndex = rand(1..3)
    v.soundManager.sendEvent("SPIN_END_"& $randSpinEndSoundIndex)

    v.spinSound.stop()
    v.stopAnticipation()

    if v.paidLines.len == 0:
        for hl in v.elementSmokeHighlights:
            hl.hide(0.3, proc() = hl.removeFromParent())
        v.elementSmokeHighlights = @[]
    else:
        if v.isForceStop:
            for elNode in v.elementSmokeHighlights:
                elNode.alpha = 1.0

    if v.haveBonusPotential and v.stage != GameStage.Bonus:
        v.hideBonusElementsHighlights()

    if v.stage == GameStage.Bonus and v.isForceStop:
        for elNode in v.bonusElementSmokeHighlights:
            elNode.alpha = 1.0

    cb()

proc onReelAnimationComplete(v: UfoSlotView, reelIndex: int) =
    doAssert(reelIndex < NUMBER_OF_REELS)

    v.reelsBusy[reelIndex] = false
    v.reelAnimAg.event(REEL_STOP_EVENT_NAME& $reelIndex)

proc canStopSpinAnimation(v: UfoSlotView):bool =
    # v.responseRecieved and v.allReelsAnimationsStarted and not v.isWildsMoving

    v.responseRecieved and v.allReelsAnimationsStarted and not v.isWildsPortIn and not v.isWildsPortOut

proc completeSpin(v: UfoSlotView, forced: bool = false)

proc tryForceStop(v: UfoSlotView) =
    # echo "FORCE STOP SPIN"
    if v.canStopSpinAnimation():
        # echo "FORCE completeSpin"
        v.completeSpin(true)

    if not v.winLinesAnim.isNil:
        v.winElemenstsHighlightsToIdle()
        v.winLinesAnim.cancel()
        v.winLinesAnim = nil
        #v.repeatWinLineAnims = nil

proc stopAnimWithDelay(v: UfoSlotView, a: Animation, d: float) =
    v.setTimeout d, proc()=
        if not a.isNil:
            a.cancel()

proc completeSpin(v: UfoSlotView, forced: bool = false) =
    const STOP_DELAY_MULTIPLYER:float = 0.75
    const FORCE_STOP_DELAY_MULTIPLYER:float = 0.1
    let delay = if v.isForceStop : FORCE_STOP_DELAY_MULTIPLYER else: STOP_DELAY_MULTIPLYER
    if v.canStopSpinAnimation():
        v.allReelsAnimationsStarted = false
        echo "completeSpin forced - ", forced
        var reelIndex = 0
        var symetricReelIndex = 4

        while reelIndex < symetricReelIndex:
            var finalDelay = delay * reelIndex.float
            v.stopAnimWithDelay(v.rotAnims[reelIndex], finalDelay)
            v.stopAnimWithDelay(v.rotAnims[symetricReelIndex], finalDelay)
            reelIndex.inc
            symetricReelIndex.dec

        # Reel in the middle
        var finalDelay = delay * reelIndex.float
        if not v.isForceStop:
            if v.totalWin > 0 or v.havePotential or v.stage == GameStage.Bonus:
                v.rotAnims[reelIndex - 1].onComplete proc() =
                    v.startAnticipation()
                finalDelay += 1.0
        v.stopAnimWithDelay(v.rotAnims[reelIndex], finalDelay)

        v.rotAnims.setLen(0)
        v.fillReels(v.lastField)

proc getReelsAnimElements(v: UfoSlotView, reelIndex: int): seq[int] =
    result = newSeq[int]()
    for i in Symbols.Pig..Symbols.Pumpkin:
        result.add(i.int)

    if v.stage == GameStage.Spin and (reelIndex notin {1,3}): # according default math bonus symbols can't be present on reels 1,3
        result.add(Symbols.Bonus.int)

    if reelIndex == 0 and not v.alienLeft.inWild:
        result.add(Symbols.TargetRed.int)

    if reelIndex == 4 and not v.alienRight.inWild:
        result.add(Symbols.TargetBlue.int)

proc fillAnimReels(v: UfoSlotView) =
    for i in 0..<v.animReels.len:
        let elems = v.getReelsAnimElements(i)
        for j in 0..<SYMS_IN_ROTATING:
            var rnd_sym = rand(elems).Symbols
            var plac = v.animReels[i].findNode("placeholder_" & $j)
            if not plac.isNil:
                for ch in plac.children:
                    if ch.name != $rnd_sym:
                        ch.alpha = 0.0
                    else:
                        ch.alpha = 1.0

                plac.positionY = j.Coord * SYMBOL_SIZE
            else:
                info "fillAnimReels plac ", j, " not found"

proc playStopAnimForElementsOnReel(v: UfoSlotView, reelIndex: int) =
    var reelColumnIndexes:seq[int] = newSeq[int]()
    var index = reelIndex
    reelColumnIndexes.add(index)
    for i in 1..<NUMBER_OF_ROWS:
        index += NUMBER_OF_REELS
        reelColumnIndexes.add(index)

    for i in reelColumnIndexes:
        let activeSymbol = v.lastField[i].Symbols
        if activeSymbol in Bonus..Pumpkin:
            #echo "playStopAnimForElementsOnReel ", activeSymbol
            let anim = v.symbolsAC[i][activeSymbol].setImmediateAnimation("twitch")
            #anim.loopDuration *= 0.3
            anim.loopPattern = lpEndToStart

proc startSpinAnimationForReel(v: UfoSlotView, reelIndex: int, cb: proc() = nil) =
    var reel = v.reels[reelIndex]
    var anim_reel = v.animReels[reelIndex]
    var rotAnim = newAnimation()

    proc updateScaleForReel(r: Node, replace: bool = true) : Node =
        const ships_pos = 120
        const fade_dst = 60
        for ch in r.children:
            let wp = ch.worldPos()
            if wp.y < - SYMBOL_SIZE or wp.y > SYMBOL_SIZE * 5:
                ch.alpha = 0.0
            # elif wp.y < ships_pos + fade_dst:
            #     var p = (wp.y - ships_pos) / fade_dst
            #     ch.alpha = interpolate(1.0, 0.0, 1.0 - p)
            else:
                ch.alpha = 1.0
                ch.scale = ch.getScaleForSymb()

            if wp.y < -(SYMBOL_SIZE * 3) and replace:
                ch.positionY = ch.positionY + SYMBOL_SIZE * SYMS_IN_ROTATING

            if result.isNil:
                result = ch
            elif result.positionY < ch.positionY:
                result = ch

    block reparentSymbs:
        anim_reel.positionY = SYMBOL_SIZE * 5
        anim_reel.alpha = 1.0
        # reel.alpha = 0.0
        for i in 0..<NUMBER_OF_ROWS:
            var plac_name = "placeholder_"
            var plac_in_anim = anim_reel.findNode(plac_name & $i)
            var palc_in_reel = reel.findNode(plac_name & $(reelIndex + i * NUMBER_OF_REELS))
            var ch = palc_in_reel.children[0]

            # plac_in_anim.removeNodeChildrenAndPutSymbolsToCache(v)
            # ch.reparentTo(plac_in_anim)
            # ch.position = SYMBOL_ANCHOR
            plac_in_anim.scale = plac_in_anim.getScaleForSymb()

    block rotating:
        if v.isForceStop:
            rotAnim.loopDuration = 0.3
        else:
            rotAnim.loopDuration = 1.2

        rotAnim.numberOfLoops = -1
        rotAnim.onAnimate = proc(p: float) =
            var speed: float
            if rotAnim.curloop == 0:
                speed = p * 100
            else:
                speed = 100

            anim_reel.positionY = anim_reel.positionY - speed
            reel.positionY = reel.positionY - speed
            discard anim_reel.updateScaleForReel()

    v.addAnimation(rotAnim)
    v.rotAnims[reelIndex] = rotAnim

    rotAnim.addLoopProgressHandler 1.0, true, proc()=
        v.completeSpin()

    block stopSpin:
        rotAnim.onComplete do():
            const syms_to_stop = 10
            var last_in_rot = anim_reel.updateScaleForReel(false)
            var syms_to_complete = last_in_rot.worldPos().y / SYMBOL_SIZE
            anim_reel.positionY = anim_reel.positionY - (syms_to_complete - syms_to_stop) * SYMBOL_SIZE
            var from_y = anim_reel.positionY
            reel.positionY = SYMBOL_SIZE * 4

            var completeAnim = newAnimation()

            if v.isForceStop:
                completeAnim.loopDuration = 0.5
            else:
                completeAnim.loopDuration = 1.4
            completeAnim.numberOfLoops = 1
            completeAnim.onAnimate = proc(p: float) =
                reel.alpha = 1.0
                anim_reel.positionY = interpolate(from_y, from_y - SYMBOL_SIZE*(syms_to_stop + 1) - SYMBOL_SIZE, expoEaseOut( p ))
                discard anim_reel.updateScaleForReel(false)
                const reel_prog = 0.15
                if p > reel_prog:
                    var pp = (p - reel_prog) / (1.0 - reel_prog)
                    reel.positionY = interpolate(SYMBOL_SIZE * 4, REEL_Y_OFFSET, backEaseOut(pp) ).float32
                    for ch in reel.children:
                        ch.scale = ch.getScaleForSymb(false)

            completeAnim.addLoopProgressHandler 0.7, true, proc()=
                v.highlightSymbolsOnReel(reelIndex)

            completeAnim.addLoopProgressHandler 0.15, true, proc()=
                v.playStopAnimForElementsOnReel(reelIndex)

            completeAnim.onComplete do():
                anim_reel.alpha = 0.0
                anim_reel.positionY = REEL_Y_OFFSET.Coord
                for i, ch in anim_reel.children:
                    ch.positionY = SYMBOL_SIZE * i.Coord
                    if i == 0:
                        ch.positionY = (SYMBOL_SIZE/10).Coord
                v.onReelAnimationComplete(reelIndex)
                # v.onReelAnimationComplete(reelIndex) do():
                #     if not cb.isNil:
                #         cb()

            v.addAnimation(completeAnim)

proc startSpinAnimation(v: UfoSlotView, cb: proc()) =
    let mid = NUMBER_OF_REELS/2

    var reelsStopEvents = newSeq[string]()
    for i in 0..<NUMBER_OF_REELS:
        reelsStopEvents.add(REEL_STOP_EVENT_NAME& $i)

    v.reelAnimAg = newAndGate(reelsStopEvents, proc() = v.onAllReelsStopped(cb))

    for i in 0..mid.int:
        closureScope:
            let index = i
            v.setTimeout (mid - index.float) * SPIN_DELAY, proc () =
                if index == 0:
                    echo "DELAY ", (mid - index.float) * SPIN_DELAY + 0.3, " for CENTRAL"
                    v.startSpinAnimationForReel(mid.int)
                    v.allReelsAnimationsStarted = true
                else :
                    echo "DELAY ",(mid - index.float) * SPIN_DELAY," for ",mid.int - index ," and ", mid.int + index
                    v.startSpinAnimationForReel(mid.int - index)
                    v.startSpinAnimationForReel(mid.int + index)


proc startIdleAnims(v: UfoSlotView)=
    if not v.alienLeft.inWild:
        v.alienLeft.setAnimState(AlienAnimStates.Idle)
    if not v.alienRight.inWild:
        v.alienRight.setAnimState(AlienAnimStates.Idle)

proc stopIdleAnims(v: UfoSlotView)=
    for plac in v.placeholders:
        var anim = plac.animationNamed("idle")
        if not anim.isNil:
            info "anim canceled"
            anim.cancel()
            anim.onAnimate(0)

proc addArrowBehindWild(v: UfoSlotView, wsa:WildSymbolAlien) =
    assert(wsa.curPlaceIndex >= 0)
    let nodeArrow = createNodeWithArrow(wsa)
    v.placeholders[wsa.curPlaceIndex].insertChild(nodeArrow, 0)
    let aeComp = nodeArrow.component(AEComposition)
    let arrowAnim = aeComp.compositionNamed("wild_to_portal")
    arrowAnim.numberOfLoops = -1

    arrowAnim.onComplete do():
        hide(nodeArrow, 0.3, proc() = nodeArrow.removeFromParent())

    wsa.activeArrowAnim = arrowAnim
    v.addAnimation(arrowAnim)

proc playActiveWildsPortIn(v: UfoSlotView, cb: proc()) =

    proc afterWildesPortIn() =
        info "afterWildesPortIn"
        v.isWildsPortIn = false
        cb()

    if v.meetIndex >= 0 and v.stage == GameStage.FreeSpin:
        afterWildesPortIn()
        return

    v.isWildsPortIn = true

    proc onWildPortInFinish(wsa:WildSymbolAlien, ag:AndGate) =
        if not wsa.activeArrowAnim.isNil:
            wsa.activeArrowAnim.cancel()
            wsa.activeArrowAnim = nil

        let eventName = wsa.node.name&"_move"
        echo "onWildPortInFinish for ", eventName
        ag.event(eventName)

    var allWildsMoveEvents = newSeq[string]()

    for aw in v.alienLeft.activeWilds:
        let eventName = aw.node.name&"_move"
        allWildsMoveEvents.add(eventName)

    for aw in v.alienRight.activeWilds:
        let eventName = aw.node.name&"_move"
        allWildsMoveEvents.add(eventName)

    echo "allWildsMoveEvents - ", allWildsMoveEvents.len

    if allWildsMoveEvents.len == 0:
        afterWildesPortIn()
    else:
        let ag = newAndGate(allWildsMoveEvents, afterWildesPortIn)

        for aw in v.alienLeft.activeWilds:
            closureScope:
                let closeAw = aw
                closeAw.isMoving = true
                closeAw.setAnimState(AlienAnimStates.WildToPortal, proc() = onWildPortInFinish(closeAw, ag))

        for aw in v.alienRight.activeWilds:
            closureScope:
                let closeAw = aw
                closeAw.isMoving = true
                closeAw.setAnimState(AlienAnimStates.WildToPortal, proc() = onWildPortInFinish(closeAw, ag))

proc checkWildOnPos(v: UfoSlotView, posIndex: int, wildSym:Symbols): bool =
    let symInPos = v.lastField[posIndex].Symbols
    result = symInPos == wildSym

    if not result and v.meetIndex >= 0:
        if posIndex == v.meetIndex:
            result = true
        if wildSym == Symbols.Wild_Green:
            if posIndex+1 == v.meetIndex:
                result = true


proc hideWildsTarget(v: UfoSlotView, phNode:Node) =
    let anim = newAnimation()
    let blue = phNode.findNode("targetBlue")
    let red = phNode.findNode("targetRed")
    var n: Node

    if blue.alpha > 0:
        n = blue
    elif red.alpha > 0:
        n = red

    if not n.isNil:
        n.hide(0.7)

proc portOutActiveWilds(v: UfoSlotView, cb: proc()) =
    v.isWildsPortOut = true

    proc onWildsPortOutFinish() =
        echo "onWildsPortOutFinish"
        v.isWildsPortOut = false
        cb()

    proc updateActiveWildsPosition(ma:MainAlien, wildSym:Symbols, callback: proc() = nil) =
        var removed = newSeq[int]()
        for i,aw in ma.activeWilds:
            if aw.nextPlaceIndex < 0 or not v.checkWildOnPos(aw.nextPlaceIndex, wildSym):
                removed.add(i)
            else:
                if v.meetIndex >= 0 and wildSym == Symbols.Wild_Green and aw.curPlaceIndex == v.meetIndex:
                    echo "Skip move of green wild from meeting point"
                    aw.suspended = true
                else:
                    let nextPos = v.placeholdersPositions[aw.nextPlaceIndex]
                    aw.node.worldPos = nextPos
                    aw.curPlaceIndex = aw.nextPlaceIndex
                    aw.setNextPosIndex()

        for rIndex in removed:
            if rIndex in ma.activeWilds.low..ma.activeWilds.high:
                let releasedWild = ma.activeWilds[rIndex]
                releasedWild.isMoving = false
                ma.activeWilds.del(rIndex)
                ma.wildsPool.insert(releasedWild, 0)

        if ma.activeWilds.len == 0 and ma.inWild:
            ma.inWild = false
            ma.setAnimState(AlienAnimStates.Intro)

        var allWildsMoveEvents = newSeq[string]()

        proc afterPortInMeetPortal(wsa:WildSymbolAlien, ag:AndGate) =
            if v.stage == GameStage.Respin:
                let releasedWild = ma.activeWilds[0]
                ma.activeWilds.del(0)
                ma.wildsPool.insert(releasedWild, 0)
                ma.inWild = false
                ma.setAnimState(AlienAnimStates.Intro)
            elif wildSym == Symbols.Wild_Green and wsa.suspended:
                wsa.suspended = false
                let nextPos = v.placeholdersPositions[wsa.nextPlaceIndex]
                wsa.node.worldPos = nextPos
                wsa.curPlaceIndex = wsa.nextPlaceIndex
                wsa.setNextPosIndex()

            ag.event(wsa.node.name&"_move")

        proc onWildPortOutAnimComplete(wsa:WildSymbolAlien, ag:AndGate) =
            if v.meetIndex >= 0 and wsa.curPlaceIndex == v.meetIndex:
                wsa.setAnimState(AlienAnimStates.WildToPortal, proc() = afterPortInMeetPortal(wsa, ag))
            else:
                ag.event(wsa.node.name&"_move")

        for aw in ma.activeWilds: allWildsMoveEvents.add(aw.node.name&"_move")

        if allWildsMoveEvents.len == 0:
            if not callback.isNil:
                callback()
        else:
            let ag = newAndGate(allWildsMoveEvents, callback)

            for aw in ma.activeWilds:
                closureScope:
                    let closeAw = aw
                    closeAw.isMoving = false
                    closeAw.setAnimState(AlienAnimStates.WildAppear, proc() = onWildPortOutAnimComplete(closeAw, ag))

    proc portRightOutWilds() =
        updateActiveWildsPosition(v.alienRight, Symbols.Wild_Green, onWildsPortOutFinish)

    updateActiveWildsPosition(v.alienLeft, Symbols.Wild_Red, portRightOutWilds)

proc playFreespinButton(v: UfoSlotView) =
    if v.prevFreespinCount == 0:
        v.slotGUI.spinButtonModule.startFreespins(v.freeSpinsLeft.int - v.messages.newFreeSpins)
    else:
        v.slotGUI.spinButtonModule.setFreespinsCount(v.freeSpinsLeft.int - v.messages.newFreeSpins)

    v.prevFreespinCount = v.freeSpinsLeft

proc onSpinResponse(v: UfoSlotView) =
    v.createWinLineSymbolsHighlights()
    v.responseRecieved = true
    if v.stage == GameStage.Freespin and v.freeSpinsLeft >= 1:
        v.playFreespinButton()
        v.prevFreespinCount = v.freeSpinsLeft

proc switchFsMode(v:UfoSlotView, m:bool)

proc printUfoField(field: seq[int8]) =
    for i in 0..NUMBER_OF_ROWS-1:
        let rowFirstIndex = NUMBER_OF_REELS * i
        var rowStr = ""
        for j in 0..NUMBER_OF_REELS-1:
            let symIndex = field[rowFirstIndex+j]
            var symStr = $symIndex
            if symIndex == Wild_Red.int8:
                symStr = "L"
            elif symIndex == Wild_Green.int8:
                symStr = "R"
            rowStr &= symStr
            if j < NUMBER_OF_REELS-1:
                rowStr &= ","
        echo rowStr

proc sendSpinRequest(v: UfoSlotView, cb: proc()) =
    v.rotAnims = newSeq[Animation](NUMBER_OF_REELS)
    v.stopIdleAnims()
    v.fillAnimReels()

    if v.stage == GameStage.Freespin or v.stage == GameStage.Respin:
        v.rotateSpinButton(v.slotGUI.spinButtonModule)

    v.startSpinAnimation do():
        cb()

    let anticipationParticle = v.rootNode.findNode("anticipation_up")
    if not anticipationParticle.isNil:
        anticipationParticle.removeFromParent()

    let rIndex = rand(1..3)
    v.spinSound = v.soundManager.playSFX(SOUND_PREFIX & "ufo_spin_"& $rIndex)
    v.spinSound.trySetLooping(true)

    v.sendSpinRequest(v.totalBet) do(res: JsonNode):
        v.clearWinNumbers()
        v.clearHighlights()

        v.lastField = @[]
        v.paidLines = @[]

        var stages = res["stages"]
        let firstStage = stages[0]
        for j in firstStage["field"].items:
            v.lastField.add(j.getInt().int8)

        #printUfoField(v.lastField)

        if "fc" in res:
            v.freeSpinsLeft = res["fc"].getInt()

        for item in firstStage["lines"].items:
            let line = PaidLine.new()
            line.winningLine.numberOfWinningSymbols = item["symbols"].getInt()
            line.winningLine.payout = item["payout"].getBiggestInt()
            line.index = item["index"].getInt()
            v.paidLines.add(line)

        var wasSpinStage = false
        for stage in stages:
            if "meetIndex" in stage:
                v.meetIndex = stage["meetIndex"].getInt()
            case stage["stage"].str
            of "FreeSpin":
                if "ftw" in stage:
                    v.freeSpinsTotalWin = stage["ftw"].getBiggestInt()
                if v.stage == GameStage.Freespin:
                    if v.prevFreespinCount > 0 and v.freeSpinsLeft > v.prevFreespinCount:
                        v.messages.newFreeSpins = v.sd.freespinsAdditionalCount
                        v.prevFreespinCount = v.freeSpinsLeft
                else:
                    v.onFreeSpinsStart()
                v.stage = GameStage.Freespin
            of "Respin":
                if v.stage == GameStage.Spin:
                    wasSpinStage = true
                if v.stage != GameStage.Respin:
                    v.reSpinsTotalWin = 0
                    v.messages.respins = true
                if v.stage == GameStage.Freespin:
                    v.onFreeSpinsEnd()
                    v.messages.freespinsResult = true

                if v.freeSpinsLeft > 0:
                    v.messages.freespins = true

                v.stage = GameStage.Respin
            of "Spin":
                if v.stage == GameStage.Respin:
                    v.slotGUI.spinButtonModule.stopRespins()
                    v.rootNode.colorizePlates(GameStage.Spin)
                v.stage = GameStage.Spin
                wasSpinStage = true
            of "Bonus":
                var payouts: seq[int64] = @[]
                var fields: seq[seq[int]] = @[]
                var fillOrders: seq[seq[FillOrder]] = @[]
                var double: seq[bool] = @[]

                v.stageAfterBonus = v.stage
                v.stage = GameStage.Bonus
                v.bonusWin = stage["bonusData"]["payout"].getBiggestInt()
                for item in stage["bonusData"]["sr"].items:
                    var field: seq[int] = @[]
                    var fos: seq[FillOrder] = @[]

                    for pipe in item["field"]:
                        field.add(pipe.getInt())

                    for i in 0..<item["fo"].len:
                        var fo: FillOrder = (index: i, pipes: @[], info: @[])

                        for p in item["fo"][i]:
                            fo.pipes.add(p[0].getInt())
                            fo.info.add(p[1].getInt())
                        fos.add(fo)

                    fields.add(field)
                    fillOrders.add(fos)
                    payouts.add(item["w"].getBiggestInt())
                    double.add(item["d"].getBool())
                v.bonusGame.setResponseData(payouts, fields, fillOrders, double)
                v.onBonusGameEnd()
            else:
                discard

        if v.reSpinsTotalWin == 0:
            v.slotGUI.winPanelModule.setNewWin(0, false)

        v.totalWin = v.getPayoutForLines()

        if wasSpinStage and v.freeSpinsTotalWin == 0 and v.reSpinsTotalWin == 0 and not v.freeRounds:
            currentUser().updateWallet(currentUser().chips - v.totalBet)

        if v.stage == GameStage.Respin or v.stageAfterBonus == GameStage.Respin:
            v.reSpinsTotalWin += v.totalWin

        let oldChips = currentUser().chips
        currentUser().chips = res["chips"].getBiggestInt()

        var spent = v.totalBet
        var win: int64 = 0
        let noWithdraw = v.stage == GameStage.FreeSpin or v.stageAfterBonus == GameStage.FreeSpin or
                            v.stage == GameStage.Respin  or v.stageAfterBonus == GameStage.Respin
        if noWithdraw:
            spent = 0
        if currentUser().chips > oldChips:
            win = currentUser().chips - oldChips
        v.spinAnalyticsUpdate(win, noWithdraw)

        v.onSpinResponse()

proc clearLastSpinStates(v: UfoSlotView) =
    v.totalWin = 0
    v.bonusWin = 0
    v.responseRecieved = false
    v.havePotential = false
    v.haveBonusPotential = false

    if not v.repeatWinLineAnims.isNil:
        v.repeatWinLineAnims = nil

    if not v.winLinesAnim.isNil:
        let wlAnim = v.winLinesAnim
        v.winLinesAnim = nil
        wlAnim.cancel()

    v.isWildsMoving = false
    v.isNewWildsAdded = false
    v.isForceStop = false
    v.allReelsAnimationsStarted = false

proc startSpin(v: UfoSlotView, cb: proc()) =
    for i in 0..<NUMBER_OF_REELS:
        v.reelsBusy[i] = true

    v.meetIndex = -1

    v.sendSpinRequest do():
        cb()

    if not v.alienLeft.inWild:
        v.alienLeft.setAnimState(AlienAnimStates.Spin)
    if not v.alienRight.inWild:
        v.alienRight.setAnimState(AlienAnimStates.Spin)

method onSpinClick*(v: UfoSlotView) =
    if v.bonusGame.isActive:
        v.bonusGame.onSpinPress()
        return

    procCall v.BaseMachineView.onSpinClick()

    if v.actionButtonState == SpinButtonState.Spin:
        if not v.freeRounds:
            if not currentUser().withdraw(v.totalBet()):
                v.slotGUI.outOfCurrency("chips")
                echo "Not enouth chips..."
                return

        v.setSpinButtonState(SpinButtonState.Blocked)

        v.clearLastSpinStates()

        v.playActiveWildsPortIn do():
            v.startSpin do():
                v.gameFlow.start()

    elif v.actionButtonState == SpinButtonState.Blocked:
        v.isForceStop = true
        v.tryForceStop()

    v.removeWinAnimationWindow()

proc initPlaceholders(v: UfoSlotView) =
    var index = 0
    v.placeholdersPositions = newSeq[Vector3](ELEMENTS_COUNT)
    for reel in v.reels:
        for i in 0..<NUMBER_OF_ROWS:
            var
                pl_i  = index + i * NUMBER_OF_REELS
                plac = newNode("placeholder_" & $pl_i )
                xp = 0.Coord
                yp = Coord(i + 1) * SYMBOL_SIZE + SYMBOL_SIZE/2.0
                zp = 0.Coord

            # info "reel rot:", reel.parent.rotation
            let pR: Quaternion = reel.parent.rotation
            plac.rotationZ = pR.z * -1.0

            reel.addChild(plac)
            plac.position = newVector3(xp, yp, zp)
            plac.addChild(newLocalizedNodeWithResource(ALL_ELEMENTS_PATH))
            v.placeholders[pl_i] = plac
        inc index

proc initSymbolsAnimations(v: UfoSlotView) =
    for i, ph in v.placeholders:
        v.symbolsAC[i] = initTable[Symbols,AnimationController]()
        let allSymbolsNode = v.placeholders[i].findNode("all_elements")
        for symId in Symbols.Bonus..Symbols.Portal:
            let symNode = allSymbolsNode.findNode($symId)
            let synAnimCtrl = newAnimationControllerForNode(symNode)

            var idleAnims = newSeq[string]()
            idleAnims.add("idle")
            let secondIdleAnim = symNode.animationNamed("idle_2")
            if not secondIdleAnim.isNil:
                idleAnims.add("idle_2")
            synAnimCtrl.addIdles(idleAnims)

            v.symbolsAC[i][symId] = synAnimCtrl

    info "v.symbolsAC ", v.symbolsAC.len, " with ", v.symbolsAC[0].len

proc initWinLinesCoords(v: UfoSlotView) =
    v.linesCoords = @[]
    const view_center = 960
    for i in 0..<v.lines.len:
        var coords = newSeq[Vector3]()
        for j in 0..<NUMBER_OF_REELS:
            let vpos = v.lines[i][j]
            let node = v.reels[j].children[vpos]
            var wp = node.worldPos()
            let isReverse = i >= 5
            if isReverse:
                wp.x -= view_center
                wp.x *= -1
                wp.x += view_center

                wp.x = 2*view_center - wp.x

            if j == 0:
                let st = wp + newVector3(if isReverse: 1 else: -1, 0, 0) * SYMBOL_SIZE
                coords.add(st)

            coords.add(wp)

            if j == NUMBER_OF_REELS - 1:
                let en = wp + newVector3(if isReverse: -1 else: 1, 0, 0) * SYMBOL_SIZE
                coords.add(en)
        v.linesCoords.add coords

proc showUfoRays(v:UfoSlotView, cb: proc())

proc reelsAppearAnimation(v:UfoSlotView, moveInTime: float = 0.0, cb: proc())

proc ufoAppearingAnimation(v:UfoSlotView, fadeinTime:float = 0.0, moveInTime: float = 0.0, cb: proc())

method getLines*(v: UfoSlotView, res: JsonNode) : seq[Line] =
    result = procCall v.BaseMachineView.getLines(res)
    for i in 0..result.high:
        result.add(result[i].reversed)

proc initZsmParams(v: UfoSlotView, res: JsonNode) =
    if res.hasKey("paytable"):
        var sd: UfoServerData
        let paytable = res["paytable"]

        sd.paytableSeq = res.getPaytableData()
        sd.freespinsAllCount = paytable{"freespinsAllCount"}.getInt()
        sd.freespinsAdditionalCount = paytable{"freespinsAdditionalCount"}.getInt()
        sd.bonusSpins = paytable{"bonusSpins"}.getInt()

        v.sd = sd

method didBecomeCurrentScene*(v: UfoSlotView) =
    discard

method restoreState*(v: UfoSlotView, res: JsonNode) =
    procCall v.BaseMachineView.restoreState(res)
    v.initZsmParams(res)

    if res.hasKey($srtChips):
        currentUser().updateWallet(res[$srtChips].getBiggestInt())
        v.slotGUI.moneyPanelModule.setBalance(0, v.currentBalance, false)

    v.lastField = @[]
    for i in 0 ..< ELEMENTS_COUNT:
        v.lastField.add((rand(Symbols.Bone.int) + 3).int8)

    for areel in v.animReels:
        for i in 0 ..< SYMS_IN_ROTATING:
            let allElems = newLocalizedNodeWithResource(ALL_ELEMENTS_PATH)
            allElems.name = "placeholder_" & $i
            areel.addChild(allElems)
            allElems.rotationZ = areel.parent.rotation.z.Coord * -1.0
            allElems.positionY = i.Coord * SYMBOL_SIZE
            let targetRedNode = allElems.findNode($Symbols.TargetRed)
            targetRedNode.animationNamed("idle").onAnimate(0.5)
            let targetBlueNode = allElems.findNode($Symbols.TargetBlue)
            targetBlueNode.animationNamed("idle").onAnimate(0.5)

    if res.hasKey($sdtFreespinCount) and res[$sdtFreespinCount].getInt() > 0:
        v.stage = GameStage.Freespin
        v.messages.freespins = true
        if res.hasKey("ftw") and res["ftw"].getBiggestInt() > 0'i64:
            v.freeSpinsTotalWin = res["ftw"].getBiggestInt()
        v.freeSpinsLeft = res[$sdtFreespinCount].getInt()
        if v.freeSpinsLeft == 1: v.freeSpinsLeft.inc()

    if res.hasKey("wp"):
        var wp = res["wp"]
        if wp.kind != JNull:
            v.wp = wp
            v.restoreWildesOnField()
            if v.stage != GameStage.Freespin:
                v.stage = GameStage.Respin
                v.messages.respins = true

    v.fillReels(v.lastField)
    v.fillAnimReels()

    v.initWinLinesCoords()

    v.ufoAppearingAnimation(0.7, 1.5) do():
        v.showUfoRays do():
            v.reelsAppearAnimation(0.7) do():
                v.addRaysBack()
                v.gameFlow.start()

proc activateUfoShootAnimations(v: UfoSlotView)

proc switchFsMode(v:UfoSlotView, m:bool)=
    let fsAnim = newAnimation()
    fsAnim.loopDuration = 0.25
    fsAnim.numberOfLoops = 1
    if m:
        fsAnim.onAnimate = proc(p:float)=
            for ch in v.showOnFreespinsNodes:
                ch.alpha = interpolate(0.0, 1.0, p)
            for ch in v.hideOnFreeSpinsNodes:
                ch.alpha = interpolate(1.0, 0.0, p)
    else:
        fsAnim.onAnimate = proc(p:float)=
            for ch in v.showOnFreespinsNodes:
                ch.alpha = interpolate(1.0, 0.0, p)
            for ch in v.hideOnFreeSpinsNodes:
                ch.alpha = interpolate(0.0, 1.0, p)

    if m:
        v.soundManager.sendEvent("FREE_SPINS_MUSIC")
    else:
        v.soundManager.sendEvent("MAIN_GAME_MUSIC")

    v.addAnimation(fsAnim)

    if m:
        v.activateUfoShootAnimations()
        v.mainLayer.findNode("ufo_shoot").alpha = 1.0
    else:
        v.fsBgAnimationActive = false
        fsAnim.onComplete do():
            v.mainLayer.findNode("ufo_shoot").alpha = 0.0

method viewOnExit*(v:UfoSlotView) =
    procCall v.BaseMachineView.viewOnExit()
    clearWinDialogsCache()

proc reelsAppearAnimation(v:UfoSlotView, moveInTime: float = 0.0, cb: proc()) =
    var reelAnims = newSeq[Animation]()
    for reel in v.reels:
        closureScope:
            var curReel = reel
            let reelInitialPosition = curReel.position
            var offsetPosition = reelInitialPosition
            offsetPosition.y += REEL_APPEARING_OFFSET
            curReel.position = offsetPosition
            curReel.alpha = 1.0

            let moveInAnim = newAnimation()
            moveInAnim.loopDuration = moveInTime
            moveInAnim.numberOfLoops = 1
            moveInAnim.onAnimate = proc(p: float) =
                curReel.position = interpolate(offsetPosition, reelInitialPosition, p)

            reelAnims.add(moveInAnim)

    proc setPlaceholdersPositions() =
        for i,ph in v.placeholders:
            v.placeholdersPositions[i] = ph.worldPos
        echo "v.placeholdersPositions ", v.placeholdersPositions
        cb()

    let ca = newCompositAnimation(true, reelAnims)
    ca.numberOfLoops = 1
    ca.onComplete do():
        v.alienLeft.setAnimState(AlienAnimStates.Intro)
        v.alienRight.setAnimState(AlienAnimStates.Intro, setPlaceholdersPositions)

    v.addAnimation(ca)

proc aliensIntroAnimation(v:UfoSlotView, delay:float = 0.0 , fadeIn: float = 0.1, callback:proc() = nil) =
    let alienFirst = v.mainLayer.findNode("alien1")
    let alienTwo = v.mainLayer.findNode("alien2")

    alienFirst.alpha = 0.0
    alienTwo.alpha = 0.0

    var node1Shine:Node = nil
    var node2Shine:Node = nil

    node1Shine = alienFirst.findNode("portal_anim")
    node2Shine = alienTwo.findNode("portal_anim")

    if node1Shine.isNil:
        node1Shine = newLocalizedNodeWithResource(GENERAL_PREFIX & "slot/aliens/Shine.json")
        node1Shine.name = "portal_anim"
        node1Shine.position = newVector3(-150.0, 180.0, 0.0)
        alienFirst.addChild(node1Shine)

    if node2Shine.isNil:
        node2Shine = newLocalizedNodeWithResource(GENERAL_PREFIX & "slot/aliens/Shine.json")
        node2Shine.name = "portal_anim"
        node2Shine.position = newVector3(-20.0, 118.0, 0.0)
        alienTwo.insertChild(node2Shine,0)

    let portal1Anim = node1Shine.animationNamed("play")
    let portal2Anim = node2Shine.animationNamed("play")

    v.setTimeout delay, proc() =
        let fadeInAnim = newAnimation()
        fadeInAnim.loopDuration = fadeIn
        fadeInAnim.numberOfLoops = 1

        fadeInAnim.onAnimate = proc(p:float)=
            alienFirst.alpha = interpolate(0.0, 1.0, p)
            alienTwo.alpha = interpolate(0.0, 1.0, p)

        fadeInAnim.onComplete do():
            v.addAnimation(portal1Anim)
            v.addAnimation(portal2Anim)

        v.addAnimation(fadeInAnim)


proc showUfoRays(v:UfoSlotView, cb: proc()) =
    let ufoParent = v.mainLayer.findNode("ufo_parent")
    for i in 1..<NUMBER_OF_REELS+1:
        var nodeName = "ufo$#_front".format(i)
        if i == 3:
            nodeName = "ufo3"

        let ufoFrontNode = ufoParent.findNode(nodeName)
        let ufoRayNode = ufoFrontNode.findNode("ufo_ray")
        let ufoRayAnim = ufoRayNode.animationNamed("show")
        v.addAnimation(ufoRayAnim)

    v.soundManager.sendEvent("UFO_RAYS")
    v.setTimeout 1.0, proc() =
        cb()

proc ufoAppearingAnimation(v:UfoSlotView, fadeinTime:float = 0.0, moveInTime: float = 0.0, cb: proc()) =
    var ufoParent = v.mainLayer.findNode("ufo_parent")

    ufoParent.alpha = 0.0

    v.mainLayer.findNode("alien1").alpha = 0.0
    v.mainLayer.findNode("alien2").alpha = 0.0

    for reel in v.reels:
        reel.alpha = 0.0

    let initialPosition = ufoParent.position
    var offsetPosition = initialPosition
    offsetPosition.y -= UFO_APPEARING_OFFSET

    ufoParent.position = offsetPosition

    var moveInAnim = newAnimation()
    moveInAnim.numberOfLoops = 1
    moveInAnim.loopDuration = moveInTime
    moveInAnim.onAnimate = proc(p: float) =
        ufoParent.position = interpolate(offsetPosition, initialPosition, p)

    moveInAnim.onComplete do():
        cb()

    let fadeInAnim = newAnimation()
    fadeInAnim.loopDuration = fadeinTime
    fadeInAnim.numberOfLoops = 1

    fadeInAnim.onAnimate = proc(p:float)=
        ufoParent.alpha = interpolate(0.0, 1.0, p)

    fadeInAnim.onComplete do():
        v.addAnimation(moveInAnim)

    v.addAnimation(fadeInAnim)

proc initBeamsAnimations(v:UfoSlotView) =
    for i in 0..ELEMENTS_COUNT-1:
        closureScope:
            let closeI = i
            if v.beams[closeI].isNil:
                var newLightningPartNode = newLocalizedNodeWithResource(GENERAL_PREFIX & "slot/scene/beam.json")
                newLightningPartNode.name = "beam"
                newLightningPartNode.scale = newVector3(0.7,0.7,0.0)
                newLightningPartNode.anchor = newVector3(360.0,180.0,0.0)
                newLightningPartNode.alpha = 0
                if closeI mod 2 != 0:
                    newLightningPartNode.scaleX = newLightningPartNode.scaleX * -1.0

                v.placeholders[closeI].addChild(newLightningPartNode)
                v.beams[closeI] = newLightningPartNode

proc testNewLightning*(v:UfoSlotView, delay:float = 0.1, delayHighlight = 0.01) =
    for i in 0..NUMBER_OF_REELS-1:
        closureScope:
            let closeI = i
            if v.beams[closeI].isNil:
                var newLightningPartNode = newLocalizedNodeWithResource(GENERAL_PREFIX & "slot/scene/beam.json")
                newLightningPartNode.name = "beam"
                newLightningPartNode.scale = newVector3(0.7,0.7,0.0)
                newLightningPartNode.anchor = newVector3(360.0,180.0,0.0)
                if closeI mod 2 != 0:
                    newLightningPartNode.scaleX = newLightningPartNode.scaleX * -1.0

                v.placeholders[closeI].addChild(newLightningPartNode)
                v.beams[closeI] = newLightningPartNode

            let beamAnim = v.beams[closeI].animationNamed("play")
            v.beams[closeI].alpha = 1.0
            beamAnim.numberOfLoops = 1
            v.setTimeout closeI.Coord * delay, proc () =
                v.addAnimation(beamAnim)
                v.setTimeout closeI.Coord * delayHighlight, proc() =
                    let symbol = v.lastField[closeI].Symbols
                    var anim = v.symbolsAC[closeI][symbol].setImmediateAnimation("highlight")
                    anim.numberOfLoops = 1

    v.playRandomWinLineSound()

proc addWinLineBeams(v: UfoSlotView, amount:int = 10) =
    var lp = v.rootNode.findNode("lightning_parent")

    if lp.isNil:
        lp = newNode("lightning_parent")
        v.rootNode.addChild(lp)

    var activeBeamsParent = lp.findNode("active_beams_parent")
    var freeBeamsParent = lp.findNode("free_beams_parent")

    if activeBeamsParent.isNil:
        activeBeamsParent = newNode("active_beams_parent")
        lp.addChild(activeBeamsParent)
    if freeBeamsParent.isNil:
        freeBeamsParent = newNode("free_beams_parent")
        lp.addChild(freeBeamsParent)
        freeBeamsParent.alpha = 0.0

    proc createBeamNode():Node =
        result = newLocalizedNodeWithResource(GENERAL_PREFIX & "slot/scene/beam.json")
        result.name = "beam"
        result.children[0].position = newVector3(0.0,0.0,0.0)
        result.children[0].anchor = newVector3(80.0,100.0,0.0)
        result.children[0].scale = newVector3(1.0,1.0,0.0)
        result.alpha = 0.0

    for i in 0..amount:
        let newBeamNode = createBeamNode()
        freeBeamsParent.addChild(newBeamNode)
        v.freeWinLineParts.add(newBeamNode)

proc freeWinLineBeamNode(beamNode:Node, freeBeamsParent:Node, freeParts: var seq[Node]) =
    freeParts.insert(beamNode)
    beamNode.children[0].anchor = newVector3(80.0,100.0,0.0)
    beamNode.rotation = aroundZ(0.0)
    beamNode.scaleX = 1.0
    beamNode.alpha = 0.0
    beamNode.reattach(freeBeamsParent)

proc cleanWinLineBeams(v: UfoSlotView) =
    let lp = v.rootNode.findNode("lightning_parent")

    if lp.isNil:
        return

    let activeBeamsParent = lp.findNode("active_beams_parent")
    let freeBeamsParent = lp.findNode("free_beams_parent")

    if activeBeamsParent.isNil or freeBeamsParent.isNil:
        return

    var chIndex = 0
    while chIndex < activeBeamsParent.children.len:
        freeWinLineBeamNode(activeBeamsParent.children[chIndex],freeBeamsParent,v.freeWinLineParts)
        inc chIndex

proc constructWinLineFromBeams(v: UfoSlotView, line_index:int = 19): Animation =

    var beamsInLine = 4

    let straightLinesInexes = @[0,1,2,10,11,12]
    let lineIsStraight = line_index in straightLinesInexes
    let lineIsReverse = line_index >= (v.lines.len div 2)
    if lineIsStraight:
        beamsInLine = 5

    let winLine = v.lines[line_index]
    var lineCoords = newSeq[Vector3]()
    for i,rowIndex in winLine:
        let phIndex = i + rowIndex*NUMBER_OF_REELS
        lineCoords.add(v.placeholders[phIndex].worldPos)

    var winLineBeamNodes = newSeq[Node]()

    if v.freeWinLineParts.len < beamsInLine:
        v.addWinLineBeams()

    let lp = v.rootNode.findNode("lightning_parent")
    var activeBeamsParent = lp.findNode("active_beams_parent")
    var freeBeamsParent = lp.findNode("free_beams_parent")

    for i in 0..beamsInLine-1:
        var reelIndex = i
        if not lineIsStraight and lineIsReverse:
            reelIndex += 1
        let nextFreeNode = v.freeWinLineParts.pop()
        nextFreeNode.worldPos = lineCoords[reelIndex]
        if lineIsStraight:
            nextFreeNode.children[0].anchor = newVector3(210.0,100.0,0.0)
            if lineIsReverse:
                nextFreeNode.rotation = aroundZ(180.0)

        nextFreeNode.reattach(activeBeamsParent)
        winLineBeamNodes.add(nextFreeNode)

    var delayIncStep = 0.1
    let partAnimDuration = winLineBeamNodes[0].animationNamed("play").loopDuration
    let totalWinLineAnimDuration = partAnimDuration + beamsInLine.float * delayIncStep

    var animationsMarkers = newSeq[ComposeMarker]()
    var nextAnimDelay = 0.0

    if lineIsReverse:
        nextAnimDelay = (beamsInLine-1).float * delayIncStep
        delayIncStep = -delayIncStep

    for i,beamNode in winLineBeamNodes:
        closureScope:
            let index = i
            let closeBeamNode = beamNode
            let anim = closeBeamNode.animationNamed("play")

            if lineIsStraight:
                if line_index == 2 or line_index == 12: # Crutch for the third line animation, because its widther
                    closeBeamNode.scaleX = closeBeamNode.scaleX*1.05
            else:
                let thisRowIndex = winLine[index]
                let nextRowIndex = winLine[index+1]

                if thisRowIndex != nextRowIndex:
                    var phReelIndex = index
                    if lineIsReverse:
                        phReelIndex = index + 1

                    let phIndex = index + winLine[phReelIndex]*NUMBER_OF_REELS
                    let distance = (lineCoords[index+1] - lineCoords[index]).length
                    let originLen = (v.placeholders[phIndex].worldPos - v.placeholders[phIndex+1].worldPos).length

                    var currentReelIndex = index
                    var nextReelIndex = index+1
                    if lineIsReverse:
                        swap(currentReelIndex,nextReelIndex)

                    let x = lineCoords[nextReelIndex].x - lineCoords[currentReelIndex].x# - 45.0#correction
                    let y = lineCoords[nextReelIndex].y - lineCoords[currentReelIndex].y
                    var angleDeg:float = radToDeg(arctan2(y,x))

                    closeBeamNode.rotation = aroundZ(angleDeg)
                    let newScaleX = distance / originLen
                    closeBeamNode.scaleX = newScaleX
                else:
                    if lineIsReverse:
                        closeBeamNode.rotation = aroundZ(180.0)

            anim.addLoopProgressHandler 0.0, false, proc() =
                closeBeamNode.alpha = 1.0

            let markerValue = nextAnimDelay/totalWinLineAnimDuration
            let cm = newComposeMarker(markerValue,1.0,anim)
            animationsMarkers.add(cm)
            nextAnimDelay += delayIncStep


    let winLineAnim = newCompositAnimation(totalWinLineAnimDuration, animationsMarkers)
    winLineAnim.numberOfLoops = 1

    proc onCompleteAction() =
        for beamNode in winLineBeamNodes:
            freeWinLineBeamNode(beamNode, freeBeamsParent, v.freeWinLineParts)
        winLineBeamNodes.setLen(0)

    winLineAnim.addLoopProgressHandler 1.0, true, proc () =
        onCompleteAction()

    result = winLineAnim

proc spawnPortalOnField(v: UfoSlotView, pos: int)

proc initTestButtons(v: UfoSlotView) =
    let msgs = [
        ( "bonus", proc() =
            v.winDialogWindow = showBonus(v.rootNode.findNode("msgs_anchor"), v.rootNode.findNode("main_scene"), v.rootNode.findNode("main_scene_anchor"))
            v.soundManager.sendEvent("BONUS_STARTED")),
        ( "freespins", proc() =
            v.winDialogWindow = showFreespins(v.rootNode.findNode("msgs_anchor"), v.rootNode.findNode("main_scene"), v.rootNode.findNode("main_scene_anchor"))
            v.soundManager.sendEvent("FREESPINS_STARTED")),
        ( "respins", proc() =
            v.winDialogWindow = showRespins(v.rootNode.findNode("msgs_anchor"), v.rootNode.findNode("main_scene"), v.rootNode.findNode("main_scene_anchor"))
            v.soundManager.sendEvent("RESPINS_STARTED")),
        ( "cnt freesp", proc() =
            v.winDialogWindow = showCountedFreespins(v.rootNode.findNode("msgs_anchor"), v.rootNode.findNode("main_scene"), v.rootNode.findNode("main_scene_anchor"), count = 5)
            v.soundManager.sendEvent("FREESPINS_PLUS")),
        ( "5inrow", proc() =
            v.winDialogWindow = show5InARow(v.rootNode.findNode("msgs_anchor"), v.rootNode.findNode("main_scene"), v.rootNode.findNode("main_scene_anchor"))
            v.soundManager.sendEvent("5_IN_A_ROW")),
        ( "free res", proc() =
            v.winDialogWindow = showFreespinsResult(v.rootNode.findNode("msgs_anchor"), v.rootNode.findNode("main_scene"), v.rootNode.findNode("main_scene_anchor"), totalWin = 50000)
            v.soundManager.sendEvent("FREESPINS_RESULT")),
        ( "bonus res", proc() =
            v.winDialogWindow = showBonusResult(v.rootNode.findNode("msgs_anchor"), v.rootNode.findNode("main_scene"), v.rootNode.findNode("main_scene_anchor"), totalWin = 50000)
            v.soundManager.sendEvent("BONUS_RESULT")),
        ( "bigwin", proc() =
            v.winDialogWindow = showBigWin(v.rootNode.findNode("msgs_anchor"), v.rootNode.findNode("main_scene"), v.rootNode.findNode("main_scene_anchor"), totalWin = 50000)
            v.soundManager.sendEvent("BIG_WIN")),
        ( "hugewin", proc() =
            v.winDialogWindow = showHugeWin(v.rootNode.findNode("msgs_anchor"), v.rootNode.findNode("main_scene"), v.rootNode.findNode("main_scene_anchor"), totalWin = 50000)
            v.soundManager.sendEvent("HUGE_WIN") ),
        ( "megawin", proc() =
            v.winDialogWindow = showMegaWin(v.rootNode.findNode("msgs_anchor"), v.rootNode.findNode("main_scene"), v.rootNode.findNode("main_scene_anchor"), totalWin = rand(1000000))
            v.soundManager.sendEvent("MEGA_WIN") ),
        ("anticipation", proc() =
            let a = v.anticipate()
            v.soundManager.sendEvent("ANTICIPATION_RINGS")
            v.setTimeout(2.0) do():
                a.stop()
        ),
        ("clicker", proc() =
            v.setInterval(0.01, proc() =
                v.UfoSlotView.onSpinClick()
            )
        )
        ]

    var posY = 250.0 - 20.0 * msgs.len.float32
    for el in msgs:
        closureScope:
            let element = el
            let bonusBttn = newButton(newRect(100.Coord, posY, 100.Coord, 20.Coord))
            bonusBttn.title = element[0]
            bonusBttn.onAction do():
                element[1]()
            v.addSubview bonusBttn
            posY += 20.0

    let testPortalBtn = newButton(newRect(40.Coord, 250.Coord, 100.Coord, 20.Coord))
    testPortalBtn.title = "test portal"
    testPortalBtn.onAction do():
        if v.portals.len > 0:
            for p in v.portals:
                p.animationIdle.cancel()
            v.portals.setLen(0)
        else:
            v.spawnPortalOnField(12)

    v.addSubview testPortalBtn

    let newLightBtn = newButton(newRect(40.Coord, 370.Coord, 50.Coord, 20.Coord))
    newLightBtn.title = "Beam"
    newLightBtn.onAction do():
        v.testNewLightning()

    v.addSubview newLightBtn

    let testBeamPartBtn = newButton(newRect(100.Coord, 370.Coord, 50.Coord, 20.Coord))
    testBeamPartBtn.title = "Check B"
    testBeamPartBtn.onAction do():
        discard v.constructWinLineFromBeams()

    v.addSubview testBeamPartBtn

    var a1BtnPosY = 400.0
    let totalBttns = ord(AlienAnimStates.GoWild)+1
    var a2BtnPosY = v.bounds.height.int - (totalBttns * 30 + 30)
    for ae in AlienAnimStates:
        closureScope:
            let closeAe = ae
            let aEventBtn = newButton(newRect(40.Coord, a1BtnPosY.Coord, 100.Coord, 20.Coord))
            aEventBtn.title = $closeAe
            aEventBtn.onAction do():
                v.alienLeft.setAnimState(closeAe)

            let aEventBtn2 = newButton(newRect(v.bounds.width - 120, a2BtnPosY.Coord, 100.Coord, 20.Coord))
            aEventBtn2.title = $closeAe
            aEventBtn2.autoresizingMask = { afFlexibleMinX, afFlexibleMinY }
            aEventBtn2.onAction do():
                v.alienRight.setAnimState(closeAe)
            a1BtnPosY += 30.0
            a2BtnPosY += 30
            v.addSubview(aEventBtn)
            v.addSubview(aEventBtn2)

proc bonusGameCompleteHandler(v: UfoSlotView) =
    proc inTheMiddle() =
        v.bonusGame.endGame()
        v.soundManager.sendEvent("MAIN_GAME_MUSIC")
        v.soundManager.sendEvent("UFO_AMBIENCE")
        v.mainLayer.enabled = true
    proc inTheEnd() =
        v.stage = v.stageAfterBonus

    v.fadeInAndOutWithSomeLogicInside(BONUS_TRANSITION_ANIM_TIME, inTheMiddle, inTheEnd)

proc debugToggleBonus(v: UfoSlotView) =
    echo "debugToggleBonus BG active - ", v.bonusGame.isActive
    if v.bonusGame.isActive:
        proc inTheMiddle() =
            v.bonusGame.endGame()
            v.soundManager.sendEvent("MAIN_GAME_MUSIC")

        v.fadeInAndOutWithSomeLogicInside(BONUS_TRANSITION_ANIM_TIME, inTheMiddle)
    else:
        proc inTheMiddle() =
            v.bonusGame.prepareGame(v.sd.bonusSpins)
            v.soundManager.sendEvent("BONUS_GAME_MUSIC")
        proc inTheEnd() =
            v.bonusGame.startGame()

        v.fadeInAndOutWithSomeLogicInside(BONUS_TRANSITION_ANIM_TIME, inTheMiddle, inTheEnd)

proc initDebugButtons(v: UfoSlotView)=
    var fsMode = false
    let fsModeBtn = newButton(newRect(20, 300, 100, 20))
    fsModeBtn.title = "FSMODE"
    fsModeBtn.onAction do():
        fsMode = not fsMode
        v.switchFsMode(fsMode)

    v.addSubview(fsModeBtn)

    block liAnimsDebug:
        var xof, yof = 0.0
        for i, li in v.lines:
            closureScope:
                let index = i
                let libtn = newButton(newRect(20.Coord, 420.Coord + 20.Coord * i.Coord, 20.Coord, 20.Coord))
                libtn.title = $index
                libtn.onAction do():
                    discard v.constructWinLineFromBeams(index)

                v.addSubview libtn

        var tglBonusBtn = newButton(newRect(20, 200, 100, 20))
        tglBonusBtn.title = "toggleBonus"
        tglBonusBtn.onAction do():
            v.debugToggleBonus()
        v.addSubview(tglBonusBtn)

proc highlightBonusSymbols(v: UfoSlotView, cb: proc()) =
    for i in 0..v.lastField.high:
        let symOnField = v.lastField[i.int8].Symbols
        if symOnField == Symbols.Bonus:
            v.symbolsAC[i][symOnField].setImmediateAnimation("highlight")

    v.setTimeout 1.7, proc() =
        cb()

proc checkBonusGameStage(v: UfoSlotView, cb: proc) =
    proc onMsgDialogDestroy() =
        v.bonusGame.prepareGame(v.sd.bonusSpins)
        v.soundManager.sendEvent("BONUS_GAME_MUSIC")
        v.soundManager.sendEvent("UFO_BONUS_AMBIENCE")
        v.mainLayer.enabled = false
        v.bonusGame.startGame()
        v.bonusGame.setOnCompleteHandler do():
            v.bonusGameCompleteHandler()
            v.soundManager.sendEvent("BONUS_RESULT")
            v.slotGUI.winPanelModule.setNewWin(v.bonusWin+v.totalWin, false)
            v.setTimeout 0.5, proc() =
                v.winDialogWindow = showBonusResult(v.rootNode.findNode("msgs_anchor"), v.rootNode.findNode("main_scene"), v.rootNode.findNode("main_scene_anchor"), v.bonusWin) do():
                    v.chipsAnim(v.rootNode.findNode("total_bet_panel"), v.currentBalance - v.bonusWin, v.currentBalance, "")
                    v.hideBonusElementsHighlights()
                    cb()
    if v.stage == GameStage.Bonus:
        v.highlightBonusSymbols do():
            v.soundManager.sendEvent("BONUS_STARTED")
            v.winDialogWindow = showBonus(v.rootNode.findNode("msgs_anchor"), v.rootNode.findNode("main_scene"), v.rootNode.findNode("main_scene_anchor"), onMsgDialogDestroy)
    else:
        cb()

proc showFSRSMessages(v: UfoSlotView, cb: proc) =
    proc recursive() =
        v.showFSRSMessages(cb)

    if (v.stage != GameStage.Respin or v.meetIndex >= 0) and v.reSpinsTotalWin > 0:
        proc onRespinResultShown() =
            let chipsFrom = v.currentBalance - v.reSpinsTotalWin - v.bonusWin - v.totalWin
            let chipsTo = v.currentBalance - v.bonusWin - v.totalWin
            v.chipsAnim(v.rootNode.findNode("total_bet_panel"), chipsFrom, chipsTo, "")
            v.reSpinsTotalWin = 0
            v.slotGUI.winPanelModule.setNewWin(0, true)
            recursive()
        v.showSpecialWinMsg(v.reSpinsTotalWin, onRespinResultShown)
    elif v.stage == GameStage.Freespin and v.freeSpinsLeft == 1:
        v.onFreeSpinsEnd() # v.stage become Spin here...
        v.switchFsMode(false)
        v.slotGUI.spinButtonModule.stopFreespins()
        v.rootNode.colorizePlates(v.stage)
        v.winDialogWindow = showFreespinsResult(v.rootNode.findNode("msgs_anchor"), v.rootNode.findNode("main_scene"), v.rootNode.findNode("main_scene_anchor"), v.freeSpinsTotalWin) do():
            v.prevFreespinCount = 0
            v.freeSpinsTotalWin = 0
            recursive()
    elif v.messages.respins:
        v.messages.respins = false
        v.soundManager.sendEvent("RESPINS_STARTED")
        v.rootNode.colorizePlates(GameStage.Respin)
        v.slotGUI.spinButtonModule.startRespins()
        v.winDialogWindow = showRespins(v.rootNode.findNode("msgs_anchor"), v.rootNode.findNode("main_scene"), v.rootNode.findNode("main_scene_anchor"), recursive)
    elif v.messages.freespins:
        v.messages.freespins = false
        v.switchFsMode(true)
        v.soundManager.sendEvent("FREESPINS_STARTED")
        v.rootNode.colorizePlates(GameStage.FreeSpin)
        v.winDialogWindow = showFreespins(v.rootNode.findNode("msgs_anchor"), v.rootNode.findNode("main_scene"), v.rootNode.findNode("main_scene_anchor")) do():
            v.slotGUI.spinButtonModule.startFreespins(v.freeSpinsLeft.int)
            recursive()
    elif v.messages.newFreeSpins > 0:
        v.soundManager.sendEvent("FREESPINS_PLUS")
        v.winDialogWindow = showCountedFreespins(v.rootNode.findNode("msgs_anchor"), v.rootNode.findNode("main_scene"), v.rootNode.findNode("main_scene_anchor"), v.messages.newFreeSpins) do():
            v.messages.newFreeSpins = 0
            v.slotGUI.spinButtonModule.startFreespins(v.freeSpinsLeft.int)
            recursive()
    else:
        cb()

proc initGameFlow(v: UfoSlotView) =
    let notif = v.notificationCenter

    notif.addObserver("GF_SPIN", v) do(args: Variant):
        v.gameFlow.nextEvent()

    notif.addObserver("GF_WILDS_HIDE", v) do(args: Variant):
        v.isForceStop = false
        v.portOutActiveWilds do():
            v.gameFlow.nextEvent()

    notif.addObserver("GF_WILDS_SPAWN", v) do(args: Variant):
        v.spawnNewWildAliens do():
            v.isNewWildsAdded = true
            v.gameFlow.nextEvent()

    notif.addObserver("GF_SHOW_FS_RS_MSG", v) do(args: Variant):
        v.showFSRSMessages do():
            v.gameFlow.nextEvent()

    notif.addObserver("GF_SHOW_WIN", v) do(args: Variant):
        v.showWinning do():
            v.gameFlow.nextEvent()

    notif.addObserver("GF_SPECIAL", v) do(args: Variant):
        v.showSpecialWinMsg do():
            v.gameFlow.nextEvent()

    notif.addObserver("GF_BONUS", v) do(args: Variant):
        v.checkBonusGameStage do():
            v.gameFlow.nextEvent()

    notif.addObserver("GF_RESPINS", v) do(args: Variant):
        if v.stage == GameStage.Respin:
            v.clearLastSpinStates()
            v.playActiveWildsPortIn do():
                v.startSpin do():
                    v.gameFlow.start()
        else:
            v.gameFlow.nextEvent()

    notif.addObserver("GF_FREESPINS", v) do(args: Variant):
        if v.stage == GameStage.Freespin and v.freeSpinsLeft > 1:
            v.clearLastSpinStates()
            v.playActiveWildsPortIn do():
                v.startSpin do():
                    v.gameFlow.start()
        else:
            v.gameFlow.nextEvent()

    notif.addObserver("GF_LEVELUP", v) do(args: Variant):
        let cp = proc() = v.gameFlow.nextEvent()
        let spinFlow = findActiveState(SpinFlowState)
        if not spinFlow.isNil:
            spinFlow.pop()
        let state = newFlowState(SlotNextEventFlowState, newVariant(cp))
        pushBack(state)

    notif.addObserver("GF_REPEAT_WIN_LINES", v) do(args: Variant):
        if not v.repeatWinLineAnims.isNil:
            v.repeatWinLineAnims()
        v.gameFlow.nextEvent()

    notif.addObserver("GF_CLEAN", v) do(args: Variant):
        v.setSpinButtonState(SpinButtonState.Spin)


method viewOnEnter*(v:UfoSlotView)=
    procCall v.BaseMachineView.viewOnEnter()

    when defined(ufodebug):
        #v.initDebugButtons()
        v.initTestButtons()
    v.initGameFlow()

proc findNodeStartsWith*(n: Node, pref: string, res: var seq[Node])=
    if n.name.startsWith(pref):
        res.add(n)
    # else:
    for ch in n.children:
        ch.findNodeStartsWith(pref, res)

proc myTests(v:UfoSlotView, ms:Node) =
    let fanNode = ms.findNode("background")
    let fAnim = fanNode.animationNamed("idle")
    fAnim.numberOfLoops = -1
    v.addAnimation(fAnim)

proc setupShowOnFreeSpinsNodes(n: Node, res: var seq[Node]) =
    let bg = n.findNode("background")
    let barn_light = n.findNode("fs_saraj_light")
    let fs_solid_top = n.findNode("fs_top")
    let fs_solid_bottom = n.findNode("fs_bottom")

    res = res.concat(@[barn_light, fs_solid_top, fs_solid_bottom])

    n.findNode("bottles").findNodeStartsWith("fs_", res)
    n.findNode("wind_fan").findNodeStartsWith("wind_free", res)

    for ch in res:
        ch.alpha = 0.0


proc setupHideOnFreeSpinsNodes(n: Node, res: var seq[Node]) =
    n.findNode("wind_fan").findNodeStartsWith("wind_main", res)

proc alienForSymbolID(v:UfoSlotView,s: Symbols): MainAlien =
    result = nil
    if s == Symbols.Wild_Green:
        result = v.alienRight
    elif s == Symbols.Wild_Red:
        result = v.alienLeft
    else:
        doAssert(false, "Undefined behaivor.Trying to get alien for symbol " & $s)

method spinSound*(v:UfoSlotView): string =
    result = "UFO_SPIN_SOUND"

proc showWildsArrows(v:UfoSlotView) =
    if v.freeSpinsLeft > 1:
        for wsa in v.alienLeft.activeWilds:
            if wsa.nextPlaceIndex > 0 and wsa.curPlaceIndex != v.meetIndex:
                v.addArrowBehindWild(wsa)

        for wsa in v.alienRight.activeWilds:
            if wsa.nextPlaceIndex > 0 and wsa.curPlaceIndex != v.meetIndex:
                v.addArrowBehindWild(wsa)

proc spawnNewWildAliens(v:UfoSlotView, callback: proc() = nil) =
    var leftAlienWildsIndexes = newSeq[int]()
    var rightAlienWildsIndexes = newSeq[int]()

    # Get placeholder indexes for all wilds symbols on current field.
    for i,symId in v.lastField:
        if symId == Symbols.Wild_Green.int:
            rightAlienWildsIndexes.add(i)
        elif symId == Symbols.Wild_Red.int:
            if v.meetIndex < 0 or (i mod NUMBER_OF_REELS) == 0:
                leftAlienWildsIndexes.add(i)

    # Check if wilds already exists on field, we don't need to create it.
    if leftAlienWildsIndexes.len > 0:
        for aw in v.alienLeft.activeWilds:
            let currentPosIndex = aw.curPlaceIndex#if aw.isMoving: aw.nextPlaceIndex else: aw.curPlaceIndex
            let iToDel = leftAlienWildsIndexes.find(currentPosIndex)
            if iToDel > -1:
                leftAlienWildsIndexes.del(iToDel)

    if rightAlienWildsIndexes.len > 0:
        for aw in v.alienRight.activeWilds:
            let currentPosIndex = aw.curPlaceIndex#if aw.isMoving: aw.nextPlaceIndex else: aw.curPlaceIndex
            let iToDel = rightAlienWildsIndexes.find(currentPosIndex)
            if iToDel > -1:
                rightAlienWildsIndexes.del(iToDel)


    proc spawnNewWildsAtPos(ma:MainAlien, positions:seq[int], ag: AndGate) =
        proc portInAfterMeet(wsa: WildSymbolAlien, cb:proc()) =
            wsa.setAnimState(AlienAnimStates.WildToPortal, cb)

        proc afterSpawn(index:int, ag: AndGate) =
            let wsa = ma.activeWilds[0]
            if v.meetIndex >= 0 and wsa.curPlaceIndex == v.meetIndex:
                portInAfterMeet(wsa, proc() = ag.event("wild_spawned_"& $index))
            else:
                ag.event("wild_spawned_"& $index)

        for p in positions:
            ma.addWildOnField(p, proc() = afterSpawn(p, ag))

    info "New Wilds left total - " & $leftAlienWildsIndexes.len
    info "New Wilds right total - " & $rightAlienWildsIndexes.len

    proc onWildsSpawnComplete() =
        echo "onWildsSpawnComplete"
        v.showWildsArrows()
        for p in v.placeholders:
            v.hideWildsTarget(p)
        if not callback.isNil:
            callback()

    proc spawnRightWilds() =
        if rightAlienWildsIndexes.len > 0:
            var rightWildsSpawnEvents = newSeq[string]()
            for i in rightAlienWildsIndexes:
                rightWildsSpawnEvents.add("wild_spawned_"& $i)
            if not v.alienRight.inWild:
                rightWildsSpawnEvents.add("alien_goes_in_portal")

            let ag = newAndGate(rightWildsSpawnEvents, onWildsSpawnComplete)

            if not v.alienRight.inWild:
                proc onEnd() =
                    ag.event("alien_goes_in_portal")
                    spawnNewWildsAtPos(v.alienRight, rightAlienWildsIndexes, ag)
                v.alienRight.inWild = true
                v.alienRight.setAnimState(AlienAnimStates.InPortal, onEnd)
            else:
                spawnNewWildsAtPos(v.alienRight, rightAlienWildsIndexes, ag)
        else:
            onWildsSpawnComplete()

    if leftAlienWildsIndexes.len > 0:
        var leftWildsSpawnEvents = newSeq[string]()
        for i in leftAlienWildsIndexes:
            leftWildsSpawnEvents.add("wild_spawned_"& $i)
        if not v.alienLeft.inWild:
            leftWildsSpawnEvents.add("alien_goes_in_portal")

        let ag = newAndGate(leftWildsSpawnEvents, spawnRightWilds)

        if not v.alienLeft.inWild:
            proc onEnd() =
                ag.event("alien_goes_in_portal")
                spawnNewWildsAtPos(v.alienLeft, leftAlienWildsIndexes, ag)
            v.alienLeft.inWild = true
            v.alienLeft.setAnimState(AlienAnimStates.InPortal, onEnd)
        else:
            spawnNewWildsAtPos(v.alienLeft, leftAlienWildsIndexes, ag)
    else:
        spawnRightWilds()

    # if not callback.isNil:
    #     if leftAlienWildsIndexes.len + rightAlienWildsIndexes.len == 0:
    #         callback()
    #     else:
    #         var totalDelay = totalToPortalAnims.float * time_to_portal + totalWildsAppearAnims.float * time_for_wilds_appear
    #         echo "Wilds appear anim time is ", totalDelay
    #         v.setTimeout totalDelay, proc() =
    #            callback()

proc newMainAlien(resPath:string, v:UfoSlotView, md: MoveDirection): MainAlien =
    info "Creating alien with res " & resPath
    result.new()
    result.node = newLocalizedNodeWithResource(resPath)
    result.resourcePath = resPath
    result.inWild = false
    #result.setupAnimationController(@[$CharAnim.Idle_1, $CharAnim.Idle_2])
    result.curAnimation = nil
    result.curAnimationState = AlienAnimStates.None
    result.sceneView = v
    result.moveDirection = md
    result.wildsParent = newNode(result.node.name&"WildsParent")
    result.activeWilds = newSeq[WildSymbolAlien]()

proc createMainAlien(v: UfoSlotView, node_name, index: string, md: MoveDirection): MainAlien =
    let origAlienNode = v.mainLayer.findNode(node_name)

    let alienResPath = GENERAL_PREFIX & "slot/aliens/" & node_name

    result = newMainAlien(alienResPath, v, md)

    result.node.position = origAlienNode.position
    result.node.anchor = origAlienNode.anchor
    result.index = index


    v.mainLayer.addChild(result.wildsParent)

    result.extendsWildsPool()

    v.mainLayer.addChild(result.node)

    origAlienNode.removeFromParent()


proc spawnPortalOnField(v: UfoSlotView, pos: int) =
    var pIntroNode = newLocalizedNodeWithResource(GENERAL_PREFIX & "slot/symbols/tunnel_intro.json")
    var pIdleNode = newLocalizedNodeWithResource(GENERAL_PREFIX & "slot/symbols/tunnel_loop.json")
    var pNode = newNode("portal_" & $pos)

    pIdleNode.alpha = 0.0

    v.mainLayer.findNode("portals_parent").addChild(pNode)

    pNode.anchor = newVector3(128.0, 128.0, 0.0)
    pNode.addChild(pIntroNode)
    pNode.addChild(pIdleNode)

    pNode.scale = newVector3(2.5,2.5,1.0)
    pNode.worldPos = v.placeholdersPositions[pos]

    var portal = new(MeetPortal)
    portal.node = pNode
    portal.idleSoundAcitve = false

    proc createAnimationForNodeAlpha(n:Node, t:float, ffrom:float, tto:float): Animation =
        result = newAnimation()
        result.loopDuration = t
        result.numberOfLoops = 1

        result.onAnimate = proc(p:float) =
            n.alpha = interpolate(ffrom, tto, p)

    var idleFadeInAnim = createAnimationForNodeAlpha(pIdleNode, 0.1, 0.0, 1.0)
    var idleFadeOutAnim = createAnimationForNodeAlpha(pIdleNode, 0.2, 1.0, 0.0)

    var introAnim = pIntroNode.animationNamed("play")
    introAnim.onComplete do():
        pIntroNode.alpha = 0.0
        if introAnim.loopPattern == LoopPattern.lpEndToStart:
            echo "remove ", pNode.name
            pNode.removeFromParent()
        else:
            portal.idleSoundAcitve = true


    var idleAnim = pIdleNode.animationNamed("play")
    idleAnim.numberOfLoops = -1
    idleAnim.addLoopProgressHandler 0.0, false, proc () =
        if portal.idleSoundAcitve:
            v.soundManager.sendEvent("PORTAL_IDLE")
            echo "playing sound PORTAL_IDLE"

    idleAnim.onComplete do():
        portal.idleSoundAcitve = false
        introAnim.prepare(0.0)
        introAnim.loopPattern = LoopPattern.lpEndToStart
        pIntroNode.alpha = 1.0
        v.addAnimation(introAnim)
        v.addAnimation(idleFadeOutAnim)
        v.soundManager.sendEvent("PORTAL_CLOSE")
        echo "playing sound PORTAL_CLOSE"

    let cm1 = newComposeMarker(0.0, 1.0, introAnim)
    let cm2 = newComposeMarker(0.7, 1.0, idleFadeInAnim)

    let introCA = newCompositAnimation(introAnim.loopDuration, @[cm1,cm2])
    introCA.numberOfLoops = 1

    portal.animationIdle = idleAnim

    v.portals.add(portal)

    v.addAnimation(introCA)
    v.addAnimation(idleAnim)
    v.soundManager.sendEvent("PORTAL_OPENS")
    echo "playing sound PORTAL_OPENS"

proc initPortals(v: UfoSlotView) =
    var nodePosIndex = -1
    for i,n in v.mainLayer.children:
        if n.name == "ufo_parent":
            nodePosIndex = i

    nodePosIndex += 1
    assert(nodePosIndex > 0)

    echo "nodePosIndex", nodePosIndex

    v.mainLayer.insertChild(newNode("portals_parent"), nodePosIndex)

    v.portals = newSeq[MeetPortal]()

proc onAllFsUfoShootAnimationsFinished(v: UfoSlotView) =
    echo "ALL Fs Ufo Shoot Animations Finished!!!"

proc playNextUfoShootAnim(v: UfoSlotView) =
    if v.fsBgAnimationActive:
        v.nextFsUfoAnimIndex = v.nextFsUfoAnimIndex mod FS_UFO_ORDER.len
        let nextShootAnimSuffix = FS_UFO_ORDER[v.nextFsUfoAnimIndex]
        let nextAnimSeqIndex = nextShootAnimSuffix - 1
        v.ufoFSAnims[nextAnimSeqIndex].onProgress(0.0)
        v.activeFsUfoShootAnimations.add("shoot_"& $nextShootAnimSuffix)
        v.addAnimation(v.ufoFSAnims[nextAnimSeqIndex])
        v.nextFsUfoAnimIndex.inc

proc activateUfoShootAnimations(v: UfoSlotView) =
    v.fsBgAnimationActive = true
    var delay = 0.0
    for i in 0..2:
        v.setTimeout delay, proc() =
            v.playNextUfoShootAnim()
        delay += 1.0

proc onUfoShootAnimationComplete(v: UfoSlotView, anim_id:string) =
    let my_id = v.activeFsUfoShootAnimations.find(anim_id)
    if my_id != -1:
        v.activeFsUfoShootAnimations.del(my_id)
    v.playNextUfoShootAnim()
    if v.activeFsUfoShootAnimations.len == 0:
        v.onAllFsUfoShootAnimationsFinished()

proc initFsUfoAnimations(v: UfoSlotView) =
    let animsParentNode = v.mainLayer.findNode("ufo_shoot")
    let bg = v.mainLayer.findNode("background")
    let shoot_sounds_offsets = [
            0.32, # shoot_1
            0.30,
            0.32,
            0.32,
            0.32,
            0.32,
            0.32,
            0.32,
            0.32,
            0.315
        ]
    let boom_sounds_offsets = [
            0.36, # shoot_1
            0.38,
            0.39,
            0.39,
            0.4,
            0.4,
            0.41,
            0.38,
            0.38,
            0.39
        ]
    v.activeFsUfoShootAnimations = newSeq[string]()

    block reattachToBg:
        var reattachParentIndex = -1
        for i,ch in bg.children:
            if ch.name == "aniamtions_parent":
                reattachParentIndex = i
                break

        if reattachParentIndex != -1:
            animsParentNode.reattach(bg, reattachParentIndex)


    block initAnimationsSeq:
        v.ufoFSAnims = newSeq[Animation]()
        for shootNode in animsParentNode.children:
            closureScope:
                let closeShootNode = shootNode
                let aeComp = closeShootNode.component(AEComposition)
                let ca = aeComp.compositionNamed("boom")
                ca.addLoopProgressHandler 0.0, false, proc () =
                    # Fix strage component behavior on first run.
                    closeShootNode.findNode("trail").component(Trail).reset()
                v.ufoFSAnims.add(ca)

        echo "We have $# ufo freespin animations".format(v.ufoFSAnims.len)

    block setupSounds:
        for i,anim in v.ufoFSAnims:
            closureScope:
                let closeI = i
                anim.addLoopProgressHandler shoot_sounds_offsets[closeI], false, proc()=
                    let randIndex = rand(1..3)
                    let sound = "UFO_SHOOT_"& $randIndex
                    echo "Playing "&sound
                    v.soundManager.sendEvent(sound)

                anim.addLoopProgressHandler boom_sounds_offsets[closeI], false, proc()=
                    let randIndex = rand(1..3)
                    let sound = "BOOM_"& $randIndex
                    echo "Playing "&sound
                    v.soundManager.sendEvent(sound)

                anim.onComplete do():
                    v.onUfoShootAnimationComplete("shoot_"& $(closeI+1))


    v.ufoFSAnims[0].addLoopProgressHandler boom_sounds_offsets[0], false, proc() =
        let anim = v.mainLayer.findNode("fs_saraj_light").animationNamed("play")
        anim.prepare(0.0)
        v.addAnimation(anim)
        v.soundManager.sendEvent("BARNS_FIRE")

    animsParentNode.alpha = 0

proc addTrailToFSAnimations(v: UfoSlotView) =
    let ufoShootNode = v.mainLayer.findNode("ufo_shoot")
    for ch in ufoShootNode.children:
        let flyingSaucer = ch.findNode("flying_saucer")
        let trailNode = newLocalizedNodeWithResource(GENERAL_PREFIX & "slot/custom/trail.json")
        flyingSaucer.insertChild(trailNode,0)

proc shiftRayNode(ufoFrontNode:Node, ufoNumber:int) =
    var ufoRayNode = ufoFrontNode.findNode("ufo_ray")
    var fsUfoPos = 0
    for i,ch in ufoFrontNode.children:
        if ch.name == "fs_ufo":
            fsUfoPos = i
            break

    if ufoNumber == 3:
        ufoRayNode.position = newVector3(211.4,13.4)
        ufoRayNode.scale = newVector3(1.0,1.0)
    # if ufoNumber == 3:
    #     let oldPos = ufoRayNode.position
    #     let oldAnchor = ufoRayNode.anchor
    #     ufoRayNode.removeFromParent()
    #     ufoRayNode = newLocalizedNodeWithResource(GENERAL_PREFIX & "slot/ufos/ufo_ray_anticipation")
    #     ufoRayNode.name = "ufo_ray"
    #     ufoRayNode.position = oldPos
    #     ufoRayNode.anchor = oldAnchor

    ufoFrontNode.insertChild(ufoRayNode, fsUfoPos)

method initAfterResourcesLoaded(v: UfoSlotView) =
    block loadJSON:
        let ms = newLocalizedNodeWithResource(GENERAL_PREFIX & "slot/main_scene/main_scene.json")

        let msAnchor = newNode("main_scene_anchor")
        msAnchor.addChild(ms)
        v.rootNode.addChild(msAnchor)

        v.reels = @[]
        v.animReels = @[]
        v.showOnFreespinsNodes = @[]
        v.hideOnFreeSpinsNodes = @[]
        v.ufoReels = @[]

        setupShowOnFreeSpinsNodes(ms,v.showOnFreespinsNodes)
        setupHideOnFreeSpinsNodes(ms,v.hideOnFreeSpinsNodes)

        v.mainLayer = ms

        v.alienLeft = v.createMainAlien("alien1", "A1", MoveDirection.LTR)
        v.alienRight = v.createMainAlien("alien2", "A2", MoveDirection.RTL)

        v.alienLeft.node.alpha = 0.0
        v.alienRight.node.alpha = 0.0
        v.meetIndex = -1

        let bottles = ms.findNode("bottles")
        let bAnim = bottles.animationNamed("idle")
        bAnim.numberOfLoops = -1
        v.addAnimation(bAnim)
        let fanNode = ms.findNode("wind_fan")
        let fAnim = fanNode.animationNamed("wind")
        fAnim.numberOfLoops = -1
        v.addAnimation(fAnim)

        v.myTests(ms)

        v.stage = GameStage.Spin

        v.rootNode.findNode("ufo1_front").findNode("reel_parent").position = newVector3(220.0,80.0)

        for i in 1..5:
            let ufoReel = new(UfoReel)
            let nname = "ufo" & $i
            ufoReel.ufo = ms.findNode(nname)

            let ufoFront = ufoReel.ufo.findNode(nname & "_front")
            let ufoBack = ufoReel.ufo.findNode(nname & "_back")

            let ufa = ufoFront.animationNamed("idle")
            ufa.numberOfLoops = -1
            let ufb = ufoBack.animationNamed("idle")
            ufb.numberOfLoops = -1

            var ufoAnim:Animation = nil
            ufoAnim = ufoReel.ufo.animationNamed("idle")
            ufoAnim.numberOfLoops = -1
            v.addAnimation(ufoAnim)


            let reel = ufoReel.ufo.findNode("reel_parent")
            ufoReel.anticipationBackNode = reel.newChild("antiBack")
            ufoReel.reelNode = reel.newChild("reel" & $i)
            ufoReel.animReelNode = reel.newChild("animR" & $i)
            ufoReel.anticipationFrontNode = reel.newChild("antiFront")

            ufoReel.reelNode.alpha = 0.0
            v.addAnimation(ufa)
            v.addAnimation(ufb)

            v.reels.add(ufoReel.reelNode)
            v.animReels.add(ufoReel.animReelNode)
            v.ufoReels.add(ufoReel)

            ufoFront.insertChild(reel,0)
            ufoFront.insertChild(ufoBack,0)

            ufoBack.position = newVector3(0.0,0.0)
            shiftRayNode(ufoFront, i)

        for ch in v.animReels:
            ch.alpha = 0.0

        v.initPlaceholders()
        v.initSymbolsAnimations()
        v.initBeamsAnimations()
        v.addTrailToFSAnimations()
        v.initFsUfoAnimations()
        v.winLineNumbersParent = ms.newChild("winning_numbers_parent")
    block bonusGame:
        v.bonusGame = newBonusGame(v.rootNode.findNode("main_scene_anchor"), v)
        v.bonusGame.bonusRoot.adjustNodeByPaddings()
        v.bonusGame.setOnCompleteHandler(proc() = v.bonusGameCompleteHandler())
        v.fadeAnim = v.addFadeSolidAnim(v.rootNode, newColor(1.0,1.0,1.0), VIEWPORT_SIZE, 0.0, 0.0, 0.0)

        var ligthingParent = v.rootNode.newChild("lightning_parent")

    block sound:
        v.soundManager = newSoundManager(v)
        v.soundManager.loadEvents(SOUND_PREFIX & "ufo", "common/sounds/common")
        v.soundManager.sendEvent("MAIN_GAME_MUSIC")
        v.soundManager.sendEvent("UFO_AMBIENCE")

    block msgs:
        initWinDialogs(v.soundManager)

    v.freeWinLineParts = newSeq[Node]()

    v.initPortals()
    v.hideCircles()

    v.winLineNumbers = newSeq[Node]()
    v.elementSmokeHighlights = newSeq[Node]()
    v.bonusElementSmokeHighlights = newSeq[Node]()
    v.highlightReelSymbols = newSeq[seq[int]](NUMBER_OF_REELS)
    v.elementHighlightsAnims = newSeq[Animation]()

    discard v.rootNode.newChild("paytable_anchor")
    discard v.rootNode.newChild("msgs_anchor")

    v.rootNode.component(ClippingRectComponent).clippingRect = newRect(0, 0, VIEWPORT_SIZE.width, VIEWPORT_SIZE.height)
    fatal "test fatal"

method clickScreen(v: UfoSlotView) =
    v.removeWinAnimationWindow()

method init*(v: UfoSlotView, r: Rect)=
    procCall v.BaseMachineView.init(r)
    v.gameFlow = newGameFlow(UFO_GAME_FLOW)
    v.gLines = NUMBER_OF_LINES

    v.multBig = 10
    v.multHuge = 15
    v.multMega = 20

    v.messages.new()
    ##########
    v.addDefaultOrthoCamera("Camera")

    v.isForceStop = false
    v.isNewWildsAdded = false
    v.isWildsMoving = false
    v.setSpinButtonState(SpinButtonState.Blocked)

method resizeSubviews*(v: UfoSlotView, oldSize: Size) =
    const fr = 4/3
    const tr = 16/9
    let camera = v.camera
    var ratio = (tr - v.frame.width / v.frame.height) / (tr - fr)
    ratio = min(1.0, max(0.0, ratio))

    let diffY = 96 * ratio
    let viewportSize = newSize(1920, 1080 + diffY)

    camera.viewportSize = viewportSize

    procCall v.BaseMachineView.resizeSubviews(oldSize)

    camera.node.positionX = viewportSize.width / 2
    camera.node.positionY = viewportSize.height / 2

    v.mainLayer.positionY = -(96 - diffY)

proc playUfoIntro(args: seq[string]): string =
    let cs = currentDirector().currentScene
    echo "try playUfoIntro on scene ", cs.name

    if cs.name == "UfoSlotView":
        let csUfo = cs.UfoSlotView
        var fadeIn = 0.0
        var delay = 0.0
        try:
           fadeIn = args[0].parseFloat()
        except: discard

        try:
           delay = args[1].parseFloat()
        except: discard

        if delay > 0.0:
            csUfo.aliensIntroAnimation(fadeIn, delay)
        else:
            if fadeIn > 0.0:
                csUfo.aliensIntroAnimation(fadeIn)
            else:
                csUfo.aliensIntroAnimation()
        removeConsole()
    else:
        info "playUfoIntro works only in UfoSlotView"

registerConsoleComand(playUfoIntro, "playUfoIntro (delay, fadeIn:float)")

proc ufoIntro(args: seq[string]): string =
    let cs = currentDirector().currentScene
    if cs.name == "UfoSlotView":
        let csUfo = cs.UfoSlotView
        var fadeIn = 0.0
        var moveIn = 0.0

        template onRaysShown() =
            if csUfo.stage == GameStage.Freespin or csUfo.stage == GameStage.Respin:
                csUfo.playActiveWildsPortIn do():
                    csUfo.startSpin do():
                        csUfo.gameFlow.nextEvent()
            csUfo.gameFlow.start()

        template onReelsAppearingShown() =
            csUfo.showUfoRays do():
                csUfo.reelsAppearAnimation(0.7) do():
                    onRaysShown()
        try:
           fadeIn = args[0].parseFloat()
        except: discard

        try:
           moveIn = args[1].parseFloat()
        except: discard

        if moveIn > 0.0:
            csUfo.ufoAppearingAnimation(fadeIn, moveIn) do():
                onReelsAppearingShown()
        else:
            if fadeIn > 0.0:
                csUfo.ufoAppearingAnimation(fadeIn, 0) do():
                   onReelsAppearingShown()
            else:
                csUfo.ufoAppearingAnimation(0, 0) do():
                    onReelsAppearingShown()

        removeConsole()
    else:
        info "ufoIntro works only in UfoSlotView"

registerConsoleComand(ufoIntro, "ufoIntro (fadeIn, moveIn:float)")

proc testLightning(args: seq[string]): string =
    let cs = currentDirector().currentScene
    echo "try testLightning on scene ", cs.name

    if cs.name == "UfoSlotView":
        let csUfo = cs.UfoSlotView
        var delay = 0.1
        var delayHighlight = 0.03
        try:
            delay = args[0].parseFloat()
        except: discard

        try:
            delayHighlight = args[1].parseFloat()
        except: discard

        csUfo.testNewLightning(delay, delayHighlight)
        removeConsole()
    else:
        info "playUfoIntro works only in UfoSlotView"

registerConsoleComand(testLightning, "testLightning (delay, delayHighlight:float)")

method assetBundles*(v: UfoSlotView): seq[AssetBundleDescriptor] =
    const ASSET_BUNDLES = [
        assetBundleDescriptor("slots/ufo_slot/bonus"),
        assetBundleDescriptor("slots/ufo_slot/ufo_sound"),
        assetBundleDescriptor("slots/ufo_slot/slot/aliens"),
        assetBundleDescriptor("slots/ufo_slot/slot/custom"),
        assetBundleDescriptor("slots/ufo_slot/slot/main_scene"),
        assetBundleDescriptor("slots/ufo_slot/slot/scene"),
        assetBundleDescriptor("slots/ufo_slot/slot/symbols"),
        assetBundleDescriptor("slots/ufo_slot/slot/ufos"),
        assetBundleDescriptor("slots/ufo_slot/slot/particles"),
        assetBundleDescriptor("slots/ufo_slot/shared"),
        assetBundleDescriptor("slots/ufo_slot/paddings"),
        assetBundleDescriptor("slots/ufo_slot/msgs"),
        assetBundleDescriptor("slots/ufo_slot/paytable")
    ]
    result = @ASSET_BUNDLES
