import nimx.view
import nimx.context
import nimx.animation
import nimx.window
import nimx.timer
import nimx.button

import rod.rod_types
import rod.node
import rod.viewport
import rod.component
import rod.component.particle_system
import rod.component.ui_component

import math
import strutils
import tables

import shared.win_popup
import core.slot.base_slot_machine_view
import core.slot.sound_map
import utils.fade_animation
import utils.sound_manager
import utils.sound
import utils.helpers

const SYMBOLS_COUNT = 11

export win_popup

type Win {.pure.} = enum
    Bonus = -1,
    Bigwin,
    Hugewin,
    Megawin

type CandyWinDialogWindow* = ref object of WinDialogWindow
    moveLinesAnim: Animation
    endLinesAnim: Animation
    moveShadowsAnim: Animation
    endShadowsAnim: Animation
    countDisplayEndAnim: Animation
    numbersLoopAnim: Animation
    boys: Node
    countDisplay: Node
    parentNumbers: Node
    particleDonuts: Node
    particleChips: Node
    particleBoom: Node
    boysAnim: Animation
    boysEndAnim: Animation
    fade: FadeAnimation
    posX: float
    payout: int64
    # stop: Button
    countAnim: Animation
    sm: SoundMap
    resourcePath: string
    restoreMusic: string

proc showSymbolInPlace(parent: Node, num: int64) =
    for i in 0..10:
        parent.findNode("number_" & $i).alpha = 0
    parent.findNode("number_" & $num).alpha = 1

proc hideStages(csv: CandyWinDialogWindow) =
    for i in 0..2:
        let node = csv.node.findNode(($(i.Win)).toLowerAscii())
        node.alpha = 0

proc showNumbers*(csv: CandyWinDialogWindow, number: int64, withRemove: bool = false)  =
    const OFFSET = 50

    let symbols = defineCountSymbols(number, SYMBOLS_COUNT)
    var power = (symbols.symbolsCount - 1).float
    var num = number
    let limit = symbols.firstSymbol + symbols.symbolsCount

    for i in 1..SYMBOLS_COUNT:
        let sym = csv.node.findNode("win_number_" & $i)

        if not sym.isNil:
            if i < symbols.firstSymbol or i >= limit:
                if not withRemove:
                    sym.alpha = 0
                else:
                    sym.removeFromParent()
            else:
                sym.alpha = 1
                showSymbolInPlace(sym, num div pow(10, power).int64)
                num = num mod pow(10, power).int64
                power -= 1

    if ($number).len mod 2 == 0:
        csv.parentNumbers.positionX = csv.posX + OFFSET
    else:
        csv.parentNumbers.positionX = csv.posX

proc setReadyForClose(csv: CandyWinDialogWindow) =
    csv.sm.stop("POINTS_COUNT_SOUND")
    csv.readyForClose = true
    csv.sm.play(csv.restoreMusic)
    csv.restoreMusic = ""

    if not csv.numbersLoopAnim.isNil:
        csv.node.addAnimation(csv.numbersLoopAnim)
    csv.showNumbers(csv.payout, true)
    for c in csv.particleBoom.children:
        let emitter = c.component(ParticleSystem)
        emitter.start()

    csv.node.sceneView().BaseMachineView.onWinDialogShowAnimationComplete()

proc findCurrentMusic(s: SoundMap): string =
    if s.activeSounds.hasKey("FREE_SPINS_MUSIC"):
        return "FREE_SPINS_MUSIC"
    else:
        return "GAME_BACKGROUND_MUSIC"

proc showStage(csv: CandyWinDialogWindow, start, to: int64, win: Win, sm: SoundMap): Animation {.discardable.}  =
    let parentBoys = csv.boys.findNode("parent")
    let boy = parentBoys.findNode("parent_" & ($win).toLowerAscii())
    let soundPath = csv.resourcePath & "candy_sound/"

    for c in parentBoys.children:
        c.alpha = 0
    boy.alpha = 1
    csv.node.addAnimation(csv.boysAnim)
    csv.sm = sm

    if csv.restoreMusic.len == 0:
        csv.restoreMusic = sm.findCurrentMusic()

    case win
    of Win.Bigwin:
        sm.play("BIG_WIN_MUSIC")
    of Win.Hugewin:
        sm.play("HUGE_WIN_MUSIC")
    of Win.Megawin:
        sm.play("MEGA_WIN_MUSIC")
    else:
        discard

    result = newAnimation()
    result.loopDuration = 3
    result.numberOfLoops = 1
    var node = csv.node.findNode(($win).toLowerAscii())
    var animNode = node.animationNamed("play")

    csv.node.addAnimation(animNode)
    node.alpha = 1

    sm.play("POINTS_COUNT_SOUND")
    result.onAnimate = proc(p: float) =
        let val = interpolate(start, to, p)
        csv.showNumbers(val)
    csv.node.addAnimation(result)

proc createCandyWinDialogWindowAnim(parent: Node, resourcePath: string, onDestroy: proc() = nil): CandyWinDialogWindow =
    result.new()
    result.onDestroy = onDestroy
    result.node = parent.newChild("candy_win_dialog_window")
    result.fade = addFadeSolidAnim(parent.sceneView(), result.node, blackColor(), VIEWPORT_SIZE, 0.0, 0.5, 1.0)
    result.resourcePath = resourcePath

    let shadows = newLocalizedNodeWithResource(resourcePath & "special_win/precomps/lines_shadow.json")
    let linesShadows = shadows.findNode("lines")
    let startShadowsAnim = linesShadows.animationNamed("start")
    result.moveShadowsAnim = linesShadows.animationNamed("move")
    result.endShadowsAnim = linesShadows.animationNamed("end")
    result.node.addChild(shadows)

    let lines = newLocalizedNodeWithResource(resourcePath & "special_win/precomps/lines.json")
    let startLinesAnim = lines.animationNamed("start")
    result.moveLinesAnim = lines.animationNamed("move")
    result.endLinesAnim = lines.animationNamed("end")
    result.node.addChild(lines)

    result.particleDonuts = newLocalizedNodeWithResource(resourcePath & "particles/win_particles_donuts.json")
    result.node.addChild(result.particleDonuts)

    result.particleChips = newLocalizedNodeWithResource(resourcePath & "particles/win_particles_cheaps.json")
    result.node.addChild(result.particleChips)

    result.particleBoom = newLocalizedNodeWithResource(resourcePath & "particles/root_win_boom.json")
    result.node.addChild(result.particleBoom)

    result.boys = newLocalizedNodeWithResource(resourcePath & "special_win/precomps/boys.json")
    result.boysAnim = result.boys.animationNamed("play")
    result.boysEndAnim = result.boys.animationNamed("end")
    result.node.addChild(result.boys)

    result.countDisplay = newLocalizedNodeWithResource(resourcePath & "special_win/precomps/count_display.json")
    let countDisplayStartAnim = result.countDisplay.animationNamed("start")
    result.node.addChild(result.countDisplay)
    result.countDisplayEndAnim = result.countDisplay.animationNamed("end")
    result.numbersLoopAnim = result.countDisplay.animationNamed("numbers_loop")
    result.numbersLoopAnim.numberOfLoops = -1

    parent.addAnimation(startLinesAnim)
    parent.addAnimation(startShadowsAnim)
    parent.addAnimation(countDisplayStartAnim)

    result.moveLinesAnim.numberOfLoops = -1
    result.moveLinesAnim.loopPattern = lpStartToEndToStart
    result.moveShadowsAnim.numberOfLoops = -1
    result.moveShadowsAnim.loopPattern = lpStartToEndToStart

    let ma = result.moveLinesAnim
    let msa = result.moveShadowsAnim

    let childrenChips = result.particleChips.children
    for c in childrenChips:
        let emitter = c.component(ParticleSystem)
        emitter.start()

    let childrenDonuts = result.particleDonuts.children
    startLinesAnim.onComplete do():
        parent.addAnimation(ma)
        parent.addAnimation(msa)
        for c in childrenDonuts:
            let emitter = c.component(ParticleSystem)
            emitter.start()

    result.parentNumbers = result.countDisplay.findNode("parent_numbers")
    result.posX = result.parentNumbers.positionX

    let btn = newButton(newRect(0, 0, VIEWPORT_SIZE.width, VIEWPORT_SIZE.height))
    btn.hasBezel = false
    result.node.component(UIComponent).view = btn

    let res = result
    btn.onAction do():
        if res.readyForClose:
            res.destroy()
        else:
            res.countAnim.cancel()
            res.showNumbers(res.payout)

method destroy*(csv: CandyWinDialogWindow) =
    if not csv.destroyed:
        if not csv.readyForClose:
            csv.setReadyForClose()

        csv.node.sceneView().BaseMachineView.onWinDialogClose()

        csv.destroyed = true
        csv.node.addAnimation(csv.endLinesAnim)
        csv.node.addAnimation(csv.endShadowsAnim)
        csv.moveLinesAnim.cancel()
        csv.moveShadowsAnim.cancel()
        csv.node.addAnimation(csv.countDisplayEndAnim)
        csv.node.addAnimation(csv.endLinesAnim)
        csv.node.addAnimation(csv.boysEndAnim)
        csv.fade.changeFadeAnimMode(0, 1.0)
        csv.countDisplayEndAnim.onComplete do():
            csv.node.removeFromParent()
            if not csv.onDestroy.isNil:
                csv.onDestroy()

        let anim = newAnimation()
        anim.numberOfLoops = 1
        anim.loopDuration = 0.5
        anim.onAnimate = proc(p: float) =
            for c in csv.particleBoom.children:
                c.alpha = 1.0 - p
            for c in csv.particleChips.children:
                c.alpha = 1.0 - p
            for c in csv.particleDonuts.children:
                c.alpha = 1.0 - p
        csv.node.addAnimation(anim)

        for c in csv.particleBoom.children:
            let emitter = c.component(ParticleSystem)
            emitter.stop()

        for c in csv.particleChips.children:
            let emitter = c.component(ParticleSystem)
            emitter.stop()

        for c in csv.particleDonuts.children:
            let emitter = c.component(ParticleSystem)
            emitter.stop()


proc showFreespinsResult*(parent: Node, payout: int64, sm: SoundMap, resourcePath: string, onDestroy: proc() = nil): CandyWinDialogWindow =
    let res = createCandyWinDialogWindowAnim(parent, resourcePath, onDestroy)
    res.countAnim = newAnimation()
    res.countAnim.loopDuration = 3
    res.countAnim.numberOfLoops = 1
    var node: Node

    node = res.node.findNode("freespin_res")

    var animNode = node.animationNamed("play")

    res.payout = payout
    res.node.addAnimation(animNode)
    sm.play("POINTS_COUNT_SOUND")
    res.countAnim.onAnimate = proc(p: float) =
        let val = interpolate(0.int64, payout, p)
        res.showNumbers(val)
    res.countAnim.onComplete do():
        res.setReadyForClose()

    res.node.addAnimation(res.countAnim)
    result = res
    result.sm = sm

proc showBigwins*(parent: Node, payout, totalBet: int64, sm: SoundMap, resourcePath: string, thresholds: seq[int64], onDestroy: proc() = nil, isBonus: bool = false, closeButton: Button = nil): CandyWinDialogWindow =
    let res = createCandyWinDialogWindowAnim(parent, resourcePath, onDestroy)
    #let thresholds = @[totalBet * 9, totalBet * 11, totalBet * 13]
    var stage = 0
    var start: int64 = 0
    var to = thresholds[0] * totalBet
    var win = stage.Win
    let birthRateCandies = 10.0
    let birthRateChips = 20.0

    if isBonus:
        res.node.addAnimation(res.node.findNode("bonusgame_res").animationNamed("play"))
        res.node.findNode("bigwin").enabled = false
        stage = -1

    res.sm = sm
    res.payout = payout
    if payout < thresholds[1] * totalBet:
        to = payout

    res.countAnim = res.showStage(start, to, win, sm)
    proc next() =
        res.readyForClose = false
        res.node.findNode("bigwin").enabled = true

        let anim = newAnimation()
        let bonus = res.node.findNode("bonusgame_res")

        anim.loopDuration = 0.5
        anim.numberOfLoops = 1
        anim.onAnimate = proc(p: float) =
            let val = interpolate(1.0, 0.0, p)
            bonus.alpha = val
        anim.onComplete do():
            res.node.findNode("bonusgame_res").enabled = false
            res.sm.stop("CANDY_BONUS_GAME_RESULT")

        res.node.addAnimation(anim)

        for c in res.particleChips.children:
            let emitter = c.component(ParticleSystem)
            emitter.birthRate *= 2
        stage.inc()
        let candies = res.particleBoom.findNode("win_candy").component(ParticleSystem)
        let chips = res.particleBoom.findNode("win_cheaps").component(ParticleSystem)
        candies.birthRate = birthRateCandies * stage.float
        chips.birthRate = birthRateChips * stage.float

        if stage < thresholds.len and payout > thresholds[stage] * totalBet:
            res.hideStages()
            start = to
            to = payout
            if stage + 1 < thresholds.len and payout > thresholds[stage + 1] * totalBet:
                    to = thresholds[stage + 1] * totalBet
            win = stage.Win
            res.countAnim = res.showStage(start, to, win, sm)
            res.countAnim.onComplete do():
                next()
        else:
            if not closeButton.isNil and not res.node.sceneView().isNil:
                res.node.sceneView().addSubview(closeButton)
            res.setReadyForClose()

    res.countAnim.onComplete do():
        next()
    result = res
