import strutils, math
import nimx / [ animation, matrixes, button ]
import rod / [ node, viewport, quaternion ]
import shared / [ win_popup, game_scene ]
import utils / [ node_animations, fade_animation, sound_manager, helpers ]
import witch_slot_view
import shared.window.button_component

const SYMBOLS_COUNT* = 11
const SYMBOL_OFFSET* = 75

type WitchWinScreen* = ref object of WinDialogWindow
    runeIn*: Animation
    runeOut*: Animation
    causticsAnim*: Animation
    rotateRune*: Animation
    titleIn*: Animation
    titleOut*: Animation
    numbersIn*: Animation
    numbersOut*: Animation
    effectsIn*: Animation
    effectsIdle*: Animation
    effectsOut*: Animation
    glowAnim*: Animation
    titlePositions*: seq[Vector3]
    numbers*: Node
    glow*: Node
    effects*: Node
    numbersPos*: Vector3
    lettersController*: Node
    stop*: ButtonComponent
    gold*: Node

proc showSymbolInPlace*(parent: Node, num: int64) =
    for i in 0..9:
        parent.findNode($i).alpha = 0
    parent.findNode($num).alpha = 1

proc getLettersPositions*(parent: Node): seq[Vector3] =
    result = @[]
    for c in parent.children:
        result.add(c.position)

proc addWiggleToSymbol*(n: Node): WiggleAnimation {.discardable.} =
    var wiggle = n.getComponent(WiggleAnimation)

    if wiggle.isNil:
        wiggle = n.addComponent(WiggleAnimation).WiggleAnimation
        wiggle.octaves = 4
        wiggle.persistance = 0.5
        wiggle.amount = 70
        wiggle.propertyType = NAPropertyType.position2d
        if not wiggle.animation.isNil:
            wiggle.enabled = true
            wiggle.animation.loopDuration = 1.5
    return wiggle

proc addWiggleToLetters*(parent: Node) =
    for c in parent.children:
        if c.name.contains("letter"):
            c.addWiggleToSymbol()

proc showAmount*(v: WitchSlotView, ww: WitchWinScreen, number: int64) =
    let symbols = defineCountSymbols(number, SYMBOLS_COUNT)
    let nc = ww.numbers.childNamed("numbers_controller")
    var power = (symbols.symbolsCount - 1).float
    var num = number

    for i in 1..SYMBOLS_COUNT:
        let sym = ww.numbers.findNode("numbers_" & $i)

        if i < symbols.firstSymbol or i >= symbols.firstSymbol + symbols.symbolsCount:
            sym.alpha = 0
        else:
            sym.alpha = 1
            showSymbolInPlace(sym, num div pow(10, power).int64)
            num = num mod pow(10, power).int64
            power -= 1
    if symbols.symbolsCount mod 2 == 0:
        nc.position = ww.numbersPos + newVector3(SYMBOL_OFFSET, 0)
    else:
        nc.position = ww.numbersPos

proc rotateBigRune*(v: WitchSlotView, ww: WitchWinScreen) =
    let rune = ww.node.findNode("rune_controller")

    ww.rotateRune = newAnimation()
    ww.rotateRune.loopDuration = 30.0
    ww.rotateRune.numberOfLoops = -1
    ww.rotateRune.onAnimate = proc(p: float) =
        rune.rotation = newQuaternionFromEulerXYZ(0.0, 0.0, interpolate(0.0, 360.0, p))
    v.addAnimation(ww.rotateRune)

proc interpolateAmount*(v: WitchSlotView, ww: WitchWinScreen, start, to: int64): Animation {.discardable.} =
    result = newAnimation()

    v.soundManager.sendEvent("COUNT_WIN")
    result.loopDuration = 3
    result.numberOfLoops = 1
    result.onAnimate = proc(p: float) =
        let val = interpolate(start, to, p)
        v.showAmount(ww, val)
    v.addAnimation(result)

proc animateBase*(v: WitchSlotView, ww: WitchWinScreen) =
    v.initialFade.changeFadeAnimMode(0.3, 0.5)
    v.rotateBigRune(ww)
    ww.glow.alpha = 1
    ww.effects.alpha = 1
    v.addAnimation(ww.effectsIn)
    ww.effectsIn.addLoopProgressHandler 0.05, true, proc() =
        ww.glowAnim.numberOfLoops = -1
        v.addAnimation(ww.glowAnim)
    ww.effectsIn.addLoopProgressHandler 0.1, true, proc() =
        ww.causticsAnim.numberOfLoops = -1
        v.addAnimation(ww.runeIn)
        v.addAnimation(ww.causticsAnim)
    ww.effectsIn.onComplete do():
        ww.effectsIdle.numberOfLoops = -1
        v.addAnimation(ww.effectsIdle)
    ww.effectsIn.addLoopProgressHandler 0.75, true, proc() =
        v.addAnimation(ww.numbersIn)
    ww.effects.alpha = 1.0

proc removeScreenElements*(ww: WitchWinScreen) =
    let v = ww.numbers.sceneView()
    let hide = newAnimation()

    v.GameScene.soundManager.sendEvent("RESULT_SCREEN_OUT")
    v.addAnimation(ww.runeOut)
    v.addAnimation(ww.titleOut)
    ww.glowAnim.cancelBehavior = cbContinueUntilEndOfLoop
    ww.glowAnim.cancel()
    hide.loopDuration = 0.5
    hide.numberOfLoops = 1
    hide.onAnimate = proc(p: float) =
        ww.glow.alpha = interpolate(1.0, 0.0, p)
    v.addAnimation(hide)
    v.addAnimation(ww.effectsOut)
    ww.effectsIdle.cancel()
    ww.rotateRune.cancel()
    ww.causticsAnim.cancel()
    v.addAnimation(ww.numbersOut)
    ww.titleOut.onComplete do():
        ww.node.sceneView().WitchSlotView.winDialogWindow = nil
        ww.onDestroy()
        ww.node.removeFromParent()

