import rod.node
import rod.viewport
import rod.component
import rod.component.ui_component
import rod.component.particle_system
import nimx.animation
import nimx.matrixes
import nimx.types
import nimx.view
import witch_win_screen
import witch_slot_view
import witch_sound
import shared.game_scene
import shared.gui.slot_gui
import utils.node_animations
import utils.sound_manager
import shared.win_popup
import core.slot.base_slot_machine_view
import shared.window.button_component

type WitchResultScreen* = ref object of WitchWinScreen
    titleResultIn: Animation
    titleResultOut: Animation
    resultPositions: seq[Vector3]
    resController: Node

method destroy*(wr: WitchResultScreen) =
    wr.node.sceneView.BaseMachineView.onWinDialogClose()

    let anim = newAnimation()
    let v = wr.numbers.sceneView()
    var curPosResult: seq[Vector3] = @[]
    var curPosTitle: seq[Vector3] = @[]

    wr.destroyed = true
    wr.stop.enabled = false
    wr.gold.component(ParticleSystem).stop()
    for c in wr.resController.children:
        let wa = c.getComponent(WiggleAnimation)

        curPosResult.add(c.position)
        if not wa.isNil:
            c.getComponent(WiggleAnimation).enabled = false
    for c in wr.lettersController.children:
        let wa = c.getComponent(WiggleAnimation)

        curPosTitle.add(c.position)
        if not wa.isNil:
            c.getComponent(WiggleAnimation).enabled = false

    anim.loopDuration = 0.3
    anim.numberOfLoops = 1
    anim.onAnimate = proc(p: float) =
        for i in 0..<wr.resController.children.len:
            wr.resController.children[i].position = interpolate(curPosResult[i], wr.resultPositions[i], p)
        for i in 0..<wr.lettersController.children.len:
            wr.lettersController.children[i].position = interpolate(curPosTitle[i], wr.titlePositions[i], p)
    v.addAnimation(anim)
    anim.onComplete do():
        v.addAnimation(wr.titleResultOut)
        v.WitchSlotView.slotGUI.enableWindowButtons(true)
        wr.removeScreenElements()

proc animateStart(v: WitchSlotView, wr: WitchResultScreen, number: int64) =
    v.animateBase(wr)
    wr.effectsIn.addLoopProgressHandler 0.15, true, proc() =
        v.addAnimation(wr.titleIn)
        v.addAnimation(wr.titleResultIn)
        wr.titleIn.onComplete do():
            wr.titlePositions = wr.lettersController.getLettersPositions()
            wr.resultPositions = wr.resController.getLettersPositions()
            wr.lettersController.addWiggleToLetters()
            wr.resController.addWiggleToLetters()

        let anim = v.interpolateAmount(wr, 0'i64, number)
        anim.onComplete do():
            wr.readyForClose = true
            wr.stop.enabled = true
            v.onWinDialogShowAnimationComplete()

proc startResultScreen*(v: WitchSlotView, number: int64, isBonus: bool, onDestroy: proc()): WitchResultScreen {.discardable.} =
    result.new()

    var rune: Node
    var caustics: Node
    var title: Node
    var titleResult: Node
    let res = result

    res.node = v.specialWinParent.newChild("result_screen")
    res.effects = newNodeWithResource("slots/witch_slot/special_win/precomps/scene_effects.json")
    res.numbers = newNodeWithResource("slots/witch_slot/special_win/precomps/numbers_branding_black.json")
    res.glow = newNodeWithResource("slots/witch_slot/special_win/precomps/scene_glow.json")
    res.effectsIn = res.effects.animationNamed("in")
    res.effectsIdle = res.effects.animationNamed("idle")
    res.effectsOut = res.effects.animationNamed("out")
    res.numbersIn = res.numbers.animationNamed("in")
    res.numbersOut = res.numbers.animationNamed("out")
    res.glowAnim = res.glow.animationNamed("play")
    res.onDestroy = onDestroy

    if isBonus:
        rune = newNodeWithResource("slots/witch_slot/special_win/precomps/rune_3_crystal.json")
        title = newNodeWithResource("slots/witch_slot/special_win/precomps/bonus_game_result_title.json")
        v.soundManager.sendEvent("BONUS_GAME_RESULTS")
    else:
        rune = newNodeWithResource("slots/witch_slot/special_win/precomps/rune_2_scatter.json")
        title = newNodeWithResource("slots/witch_slot/special_win/precomps/free_spins_result_title.json")
        v.soundManager.sendEvent("FREE_SPINS_RESULTS")
    caustics = rune.findNode("caustics_rune")
    titleResult = title.findNode("result_main")
    res.runeIn = rune.animationNamed("in")
    res.runeOut = rune.animationNamed("out")
    res.causticsAnim = caustics.animationNamed("play")
    res.titleIn = title.animationNamed("in")
    res.titleOut = title.animationNamed("out")
    res.titleResultIn = titleResult.animationNamed("in")
    res.titleResultOut = titleResult.animationNamed("out")

    res.node.addChild(rune)

    res.gold = newNodeWithResource("slots/witch_slot/particles/gold_particles_main.json")
    res.node.addChild(res.gold)
    res.gold.position = newVector3(v.viewportSize.width / 2, v.viewportSize.height / 2)

    res.node.addChild(res.numbers)
    res.node.addChild(title)
    res.node.addChild(res.effects)
    res.node.addChild(res.glow)

    let buttonParent = res.node.newChild("button_parent")
    res.stop = buttonParent.createButtonComponent(newRect(0, 0, v.viewportSize.width, v.viewportSize.height))
    res.stop.enabled = false
    res.stop.onAction do():
        res.destroy()

    res.effects.alpha = 0
    res.lettersController = title.findNode("letters_controller")
    res.resController = title.findNode("result_controller")
    res.numbersPos = res.numbers.childNamed("numbers_controller").position
    v.animateStart(res, number)
    v.slotGUI.enableWindowButtons(false)
    v.playBackgroundMusic(MusicType.Main)
