import
    strutils,nimx.matrixes,nimx.view,nimx.window,nimx.animation,nimx.image,nimx.timer,nimx.font,nimx.types,rod.rod_types,rod.node,
    rod.viewport,rod.component.text_component,rod.component.particle_emitter,rod.component.sprite,rod.component.solid,rod.component,
    rod.component.visual_modifier,tables,core.slot.base_slot_machine_view,shared.win_popup,utils.sound,utils.sound_manager

export win_popup

type EiffelWinDialogWindow* = ref object of WinDialogWindow
    scene: SceneView
    skipped: bool
    coinsFieldText: Text
    currentWinAnim: Animation
    currentCountAnimation: Animation

const EiffelMessagesCompositionsPrefix = "slots/eiffel_slot/eiffel_messages/"
const EiffelSoundPrefix = "slots/eiffel_slot/eiffel_sound/"
var EWDWCache = TableRef[string, Node]()

proc setDefaultFontSettings(n: Node, offsetX, offsetY: float)=
    var t = n.component(Text)
    # n.positionY = n.positionY + offsetY
    # n.positionX = n.positionX + offsetX
    # t.font.size = t.font.size * 1.3
    t.shadowX = 1.0
    t.shadowY = 4.0
    t.strokeSize = 3.5
    t.isColorGradient = true
    t.colorFrom = newColor(255/255, 218/255, 168/255)
    t.colorTo   = newColor(255/255, 253/255, 251/255)

proc skip*(winDialog: EiffelWinDialogWindow)=
    if not winDialog.isNil:
        if not winDialog.currentWinAnim.isNil:
            winDialog.currentWinAnim.cancelBehavior = cbJumpToEnd
            winDialog.currentWinAnim.cancel()

        winDialog.skipped = true

method destroy*(winAnim: EiffelWinDialogWindow) =
    if not winAnim.destroyed:
        winAnim.scene.BaseMachineView.onWinDialogClose()

        winAnim.destroyed = true
        var hideAnim = newAnimation()
        hideAnim.numberOfLoops = 1
        hideAnim.loopDuration = 0.25
        hideAnim.onAnimate = proc(p: float) =
            winAnim.node.alpha = interpolate(1.0, 0.0, p)
        hideAnim.onComplete do():
            winAnim.node.removeFromParent()
            if not winAnim.onDestroy.isNil:
                winAnim.onDestroy()
        winAnim.scene.addAnimation(hideAnim)

proc createUWin():Node =
    result = EWDWCache[EiffelMessagesCompositionsPrefix & "YouWin.json"]

proc addBlink(a: Animation, n: Node, s, p: string)=
    a.addLoopProgressHandler 0.2, true, proc()=
        # echo "s: ", s, " p: ", p
        let fn = n.findNode("blink_parent")
        if not fn.isNil:
            fn.removeFromParent()
        var blink_parent = newLocalizedNodeWithResource(p)
        discard blink_parent.component(VisualModifier)
        n.findNode(s).addChild(blink_parent)

proc showMessage(v: BaseMachineView, parent: Node, compPath: string, blinkpath: string, onDestroy: proc() = nil): EiffelWinDialogWindow=
    var res = new(EiffelWinDialogWindow)
    var pNode = parent.newChild("specialWin")
    pNode.component(Solid).color = newColor(0.0,0.0,0.0,0.5)
    pNode.component(Solid).size = newSize(1920,1080)
    var node = EWDWCache[compPath]
    pNode.addChild(node)
    var animPlay = node.animationNamed("play")
    v.addAnimation(animPlay)

    animPlay.onComplete do():
        res.readyForClose = true
        res.destroy()
        if not compPath.contains("Five.json") and not compPath.contains("_intro.json"):
            v.onWinDialogShowAnimationComplete()

    addBlink(animPlay, node, "stage$AUX", blinkpath)

    result = res
    result.node = pNode
    result.onDestroy = onDestroy
    result.readyForClose = false
    result.destroyed = false
    result.scene = v

proc showFiveInARow*(v: BaseMachineView, parent: Node, onDestroy: proc() = nil): EiffelWinDialogWindow=
    result = v.showMessage(parent, EiffelMessagesCompositionsPrefix & "Five.json",
        EiffelMessagesCompositionsPrefix & "blinkFive.json", onDestroy)

proc showGameModeIntro*(v: BaseMachineView, mode: string, parent: Node, onDestroy: proc() = nil): EiffelWinDialogWindow=
    result = v.showMessage(parent, EiffelMessagesCompositionsPrefix & mode & "_intro.json",
        EiffelMessagesCompositionsPrefix & "blink" & mode & "_intro.json", onDestroy)
    var uwin = createUWin()
    v.addAnimation(uwin.animationNamed("play"))
    result.node.addChild(uwin)

proc gameModeResults(winDialog: EiffelWinDialogWindow, to: int64, dur: float): Node=
    var res = EWDWCache[EiffelMessagesCompositionsPrefix & "Results_free_and_bonus.json"]
    var counter = res.findNode("textField")

    var counterText = counter.component(Text)
    var countAnim = newAnimation()
    countAnim.loopDuration = dur
    countAnim.numberOfLoops = 1
    countAnim.onAnimate = proc(p: float)=
        counterText.text =  $interpolate(0.int64, to, p)

    res.registerAnimation("countUp", countAnim)
    winDialog.currentWinAnim = countAnim
    result = res

proc showGameModeOutro*(v: BaseMachineView, mode: string, parent: Node, totalWin: int64, onDestroy: proc() = nil): EiffelWinDialogWindow=
    var res = new(EiffelWinDialogWindow)
    var node = EWDWCache[EiffelMessagesCompositionsPrefix & mode & "_result.json"]
    var pNode = parent.newChild("gameModeOutro")
    pNode.component(Solid).color = newColor(0.0,0.0,0.0,0.5)
    pNode.component(Solid).size = newSize(1920,1080)
    pNode.addChild(node)
    let playAnim = node.animationNamed("play")

    var countUp = gameModeResults(res, totalWin, playAnim.loopDuration)
    pNode.addChild(countUp)

    let countUpAnim = countUp.animationNamed("countUp")
    var coinsSound: Sound
    countUpAnim.addLoopProgressHandler 0.08, true, proc()=
        coinsSound = v.soundManager.playSFX(EiffelSoundPrefix & "coins_count")
        coinsSound.trySetLooping(true)

    countUpAnim.onComplete do():
        if not coinsSound.isNil:
            coinsSound.stop()
            v.soundManager.playSFX(EiffelSoundPrefix & "coin_count_end")

        v.soundManager.stopSFX(2.0)
        res.readyForClose = true
        v.onWinDialogShowAnimationComplete()

    v.addAnimation(playAnim)
    v.addAnimation(countUp.animationNamed("play"))
    v.addAnimation(countUpAnim)
    v.addAnimation(countUp.findNode("counter").animationNamed("play"))
    v.addAnimation(countUp.findNode("chips1").animationNamed("play"))
    v.addAnimation(countUp.findNode("chips0").animationNamed("play"))
    v.addAnimation(countUp.findNode("result1").animationNamed("play"))

    addBlink(playAnim, node, "stage$AUX", EiffelMessagesCompositionsPrefix & "blink" & mode & "_result.json")

    result = res
    result.node = pNode
    result.destroyed = false
    result.readyForClose = false
    result.onDestroy = onDestroy
    result.scene = v

proc createResultsWin(winDialog: EiffelWinDialogWindow,to: int64, dur: float): Node =
    result = newLocalizedNodeWithResource(EiffelMessagesCompositionsPrefix & "Results_win.json")
    var textField = result.findNode("textField")
    var chips0 = result.findNode("chipsText").findNode("eiffel_window_chips")
    var chips1 = result.findNode("chipsText2").findNode("eiffel_window_chips")

    textField.setDefaultFontSettings(-0.0, 50.0)
    chips1.setDefaultFontSettings(-15.0, 30.0)
    chips0.setDefaultFontSettings(-15.0, 30.0)

    winDialog.coinsFieldText = textField.component(Text)

proc newCountUp(winDialog: EiffelWinDialogWindow, start, to: int64, dur: float): Animation {.discardable.} =
    result = newAnimation()
    result.loopDuration = dur
    result.numberOfLoops = 1

    result.onAnimate = proc(p: float) =
        winDialog.coinsFieldText.text = formatThousands(interpolate(start, to, p))

    if not winDialog.currentCountAnimation.isNil:
        winDialog.currentCountAnimation.cancelBehavior = cbJumpToEnd
        winDialog.currentCountAnimation.cancel()

    winDialog.currentCountAnimation = result
    winDialog.scene.addAnimation(result)

proc showSpecialWin*(v: BaseMachineView, parent: Node, totalWin: int64, winType: WinType, onDestroy:proc() = nil): EiffelWinDialogWindow =
    var res = new(EiffelWinDialogWindow)
    result = res
    result.onDestroy = onDestroy
    result.destroyed = false
    result.readyForClose = false
    result.skipped = false
    result.scene = v

    let thresholds = [
        v.totalBet() * v.multBig,
        v.totalBet() * v.multHuge
    ]

    proc resetAlpha(n: Node)=
        n.findNode("win_sprite").alpha = 1.0
        n.findNode("stage_sprite").alpha = 1.0
        n.animationNamed("play").onAnimate(0)

    proc hideAnim(n: Node): Animation =
        let bWinN = n.findNode("win_sprite")
        let bStaN = n.findNode("stage_sprite")
        let bPar  = n.findNode("blink_parent")
        bPar.removeFromParent()
        result = newAnimation()
        result.loopDuration = 0.5
        result.numberOfLoops = 1
        result.onAnimate = proc(p: float)=
            bWinN.alpha = interpolate(1.0, 0.0, p)
            bStaN.alpha = interpolate(1.0, 0.0, p)

    proc animCounterScale(n: Node): Animation=
        let f = n.scale
        let t = n.scale * 1.14
        result = newAnimation()
        result.loopDuration = 0.5
        result.numberOfLoops = 1
        result.onAnimate = proc(p: float) =
            n.scale = interpolate(f, t, bounceEaseOut(p))

    var bigPlay, hugePlay, megaPlay: Animation
    var bigWin, hugeWin, megaWin: Node
    var soundName = "big_win"
    var pNode = parent.newChild("specialWin")
    pNode.component(Solid).color = newColor(0.0,0.0,0.0,0.5)
    pNode.component(Solid).size = newSize(1920,1080)
    var countDur = 0.0
    bigWin = EWDWCache[EiffelMessagesCompositionsPrefix & "BigWin.json"]
    var countUp = createResultsWin(result, totalWin, countDur)
    bigWin.resetAlpha()
    bigPlay = bigWin.animationNamed("play")
    countDur += bigPlay.loopDuration
    pNode.addChild(bigWin)
    addBlink(bigPlay, bigWin, "stage_sprite$AUX", EiffelMessagesCompositionsPrefix & "blinkBigWin.json")
    result.currentWinAnim = bigPlay

    var whichOnComplete = bigPlay

    if winType > WinType.Big:
        hugeWin = EWDWCache[EiffelMessagesCompositionsPrefix & "HugeWin.json"]
        hugeWin.resetAlpha()
        hugeWin.alpha = 0.0
        hugePlay = hugeWin.animationNamed("play")
        countDur += hugePlay.loopDuration
        bigPlay.onComplete do():
            hugeWin.alpha = 1.0
            v.addAnimation(hugePlay)
            v.addAnimation(bigWin.hideAnim())
            res.currentWinAnim = hugePlay
            let start =
                if res.skipped:
                    thresholds[0]
                else:
                    res.coinsFieldText.text.replace(",").parseInt()
            res.skipped = false
            let toValue =
                if winType > WinType.Huge:
                    thresholds[1]
                else:
                    totalWin.int
            res.newCountUp(
                start,
                toValue,
                hugePlay.loopDuration
            )
        pNode.addChild(hugeWin)

        hugePlay.addLoopProgressHandler 0.2, false, proc()=
            v.addAnimation(countUp.findNode("numbers_white").animCounterScale())
        addBlink(hugePlay, hugeWin, "stage_sprite$AUX", EiffelMessagesCompositionsPrefix & "blinkHugeWin.json")
        soundName = "huge_win"
        whichOnComplete = hugePlay

    if winType > WinType.Huge:
        megaWin = EWDWCache[EiffelMessagesCompositionsPrefix & "MegaWin.json"]
        megaWin.resetAlpha()
        megaWin.alpha = 0.0
        megaPlay = megaWin.animationNamed("play")
        countDur += megaPlay.loopDuration
        hugePlay.onComplete do():
            megaWin.alpha = 1.0
            v.addAnimation(megaPlay)
            v.addAnimation(hugeWin.hideAnim())
            res.currentWinAnim = megaPlay
            let start =
                if res.skipped:
                    thresholds[1]
                else:
                    res.coinsFieldText.text.replace(",").parseInt()
            res.skipped = false
            res.newCountUp(
                start,
                totalWin.int,
                megaPlay.loopDuration
            )
        pNode.addChild(megaWin)
        megaPlay.addLoopProgressHandler 0.2, false, proc()=
            v.addAnimation(countUp.findNode("numbers_white").animCounterScale())
        addBlink(megaPlay, megaWin, "stage_sprite$AUX", EiffelMessagesCompositionsPrefix & "blinkMegaWin.json")
        soundName = "mega_win"
        whichOnComplete = megaPlay

    pNode.addChild(countUp)

    let
        chips0 = countUp.findNode("chipsText")
        chips1 = countUp.findNode("chipsText2")
        resTex = countUp.findNode("resultText")
        countPlay = countUp.animationNamed("play")

    var coinsSound: Sound

    v.soundManager.playSFX(EiffelSoundPrefix & soundName)

    bigPlay.addLoopProgressHandler 0.08, true, proc()=
        coinsSound = v.soundManager.playSFX(EiffelSoundPrefix & "coins_count")
        coinsSound.trySetLooping(true)

    whichOnComplete.onComplete do():
        if not res.currentCountAnimation.isNil:
            res.currentCountAnimation.cancelBehavior = cbJumpToEnd
            res.currentCountAnimation.cancel()

        if not coinsSound.isNil:
            coinsSound.stop()
            v.soundManager.playSFX(EiffelSoundPrefix & "coin_count_end")

        v.soundManager.stopSFX(2.0)
        res.readyForClose = true
        v.onWinDialogShowAnimationComplete()

    v.addAnimation(chips0.animationNamed("play"))
    v.addAnimation(chips1.animationNamed("play"))
    v.addAnimation(resTex.animationNamed("play"))
    v.addAnimation(countPlay)
    v.addAnimation(bigPlay)
    var toValue = totalWin
    if winType > WinType.Big:
        toValue = thresholds[0]
    result.newCountUp(0.int64, toValue, bigPlay.loopDuration)

    result.node = pNode

proc initWinDialogs*()=
    EWDWCache = newTable[string, Node]()
    EWDWCache[EiffelMessagesCompositionsPrefix & "BigWin.json"] = newLocalizedNodeWithResource(EiffelMessagesCompositionsPrefix & "BigWin.json")
    EWDWCache[EiffelMessagesCompositionsPrefix & "HugeWin.json"] = newLocalizedNodeWithResource(EiffelMessagesCompositionsPrefix & "HugeWin.json")
    EWDWCache[EiffelMessagesCompositionsPrefix & "MegaWin.json"] = newLocalizedNodeWithResource(EiffelMessagesCompositionsPrefix & "MegaWin.json")
    EWDWCache[EiffelMessagesCompositionsPrefix & "BonusGame_result.json"] = newLocalizedNodeWithResource(EiffelMessagesCompositionsPrefix & "BonusGame_result.json")
    EWDWCache[EiffelMessagesCompositionsPrefix & "FreeSpin_result.json"] = newLocalizedNodeWithResource(EiffelMessagesCompositionsPrefix & "FreeSpin_result.json")
    EWDWCache[EiffelMessagesCompositionsPrefix & "BonusGame_intro.json"] = newLocalizedNodeWithResource(EiffelMessagesCompositionsPrefix & "BonusGame_intro.json")
    EWDWCache[EiffelMessagesCompositionsPrefix & "FreeSpin_intro.json"] = newLocalizedNodeWithResource(EiffelMessagesCompositionsPrefix & "FreeSpin_intro.json")
    EWDWCache[EiffelMessagesCompositionsPrefix & "YouWin.json"] = newLocalizedNodeWithResource(EiffelMessagesCompositionsPrefix & "YouWin.json")
    EWDWCache[EiffelMessagesCompositionsPrefix & "Five.json"] = newLocalizedNodeWithResource(EiffelMessagesCompositionsPrefix & "Five.json")

    var counterRes0 = newLocalizedNodeWithResource(EiffelMessagesCompositionsPrefix & "Results_free_and_bonus.json")
    EWDWCache[EiffelMessagesCompositionsPrefix & "Results_free_and_bonus.json"] = counterRes0

    block blockSetDefaultFontSettings:
        var chips0 = counterRes0.findNode("chips0").findNode("eiffel_window_chips")
        var chips1 = counterRes0.findNode("chips1").findNode("eiffel_window_chips")
        var result1 = counterRes0.findNode("result1").findNode("eiffel_window_result")
        var counter = counterRes0.findNode("textField")

        chips0.setDefaultFontSettings(-15.0, 30.0)
        chips1.setDefaultFontSettings(-15.0, 30.0)
        result1.setDefaultFontSettings(-50.0, 50.0)
        counter.setDefaultFontSettings(0.0, 50.0)

proc clearWinDialogsCache*() =
    EWDWCache = nil
