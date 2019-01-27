import rod.node
import rod.viewport
import rod.component
import rod.component.ui_component
import rod.component.particle_system
import nimx.types
import nimx.animation
import nimx.matrixes
import shared.gui.slot_gui
import shared.game_scene
import core.slot.base_slot_machine_view
import utils.node_animations
import utils.sound_manager
import utils.helpers
import sound.sound
import witch_win_screen
import witch_slot_view
import shared.win_popup
import shared.window.button_component

type WitchBigwinScreen* = ref object of WitchWinScreen
    witchIn: Animation
    witchCaustic: Node
    witch: Node
    level: BigWinType
    curLevel: BigWinType
    amount: int64
    moreGold: Node
    currentSound: Sound

proc blinkWitch(wr: WitchBigwinScreen, hide: bool = false) =
    let anim = newAnimation()

    anim.loopDuration = 0.6
    anim.numberOfLoops = 1
    anim.onAnimate = proc(p: float) =
        if p < 0.5:
            wr.witchCaustic.alpha = p * 2
        else:
            wr.witchCaustic.alpha = (1.0 - p) * 2
    wr.witchCaustic.alpha = 1.0
    wr.node.addAnimation(anim)
    if hide:
        anim.onComplete do():
            let ha = newAnimation()

            ha.loopDuration = 0.5
            ha.numberOfLoops = 1
            ha.onAnimate = proc(p: float) =
                wr.witch.alpha = interpolate(1.0, 0.0, p)
            wr.node.addAnimation(ha)

proc hideLetters(v: SceneView, wr: WitchBigwinScreen): Animation =
    var curPosTitle: seq[Vector3] = @[]

    result = newAnimation()
    for c in wr.lettersController.children:
        curPosTitle.add(c.position)
        if not c.getComponent(WiggleAnimation).isNil:
            c.getComponent(WiggleAnimation).enabled = false
    result.loopDuration = 0.3
    result.numberOfLoops = 1
    result.onAnimate = proc(p: float) =
        for i in 0..<wr.lettersController.children.len:
            wr.lettersController.children[i].position = interpolate(curPosTitle[i], wr.titlePositions[i], p)
    v.addAnimation(result)

proc moveToNextLevel(v: WitchSlotView, wr: WitchBigwinScreen) =
    let anim = v.hideLetters(wr)
    anim.onComplete do():
        wr.blinkWitch(true)
        v.addAnimation(wr.titleOut)

proc showNextLevel(v: WitchSlotView, wr: WitchBigwinScreen) =
    var title: Node

    wr.currentSound.stop()
    if wr.curLevel == BigWinType.Huge:
        title = newNodeWithResource("slots/witch_slot/special_win/precomps/huge_win_title.json")
        wr.witch = newNodeWithResource("slots/witch_slot/special_win/precomps/witch_pose_2.json")
        wr.witch.scale.x = -1
        wr.witch.translation.x = v.viewportSize.width
        if wr.level == BigWinType.Huge:
            v.interpolateAmount(wr, v.totalBet * TRESHOLDS[0], wr.amount)
        else:
            v.interpolateAmount(wr, v.totalBet * TRESHOLDS[0], v.totalBet * TRESHOLDS[1])
        wr.currentSound = v.soundManager.playSFX("slots/witch_slot/sound/witch_huge_win")
    else:
        title = newNodeWithResource("slots/witch_slot/special_win/precomps/mega_win_title.json")
        wr.witch = newNodeWithResource("slots/witch_slot/special_win/precomps/witch_pose_3.json")
        v.interpolateAmount(wr, v.totalBet * TRESHOLDS[1], wr.amount)
        wr.currentSound = v.soundManager.playSFX("slots/witch_slot/sound/witch_mega_win")
    wr.moreGold.component(ParticleSystem).start()
    wr.witchCaustic = wr.witch.findNode("witch_pose_caustiс_in_out")
    wr.titleIn = title.animationNamed("in")
    wr.titleOut = title.animationNamed("out")
    wr.witchIn = wr.witch.animationNamed("in")
    v.specialWinParent.findNode("title_parent").addChild(title)
    v.specialWinParent.findNode("witch_parent").addChild(wr.witch)
    v.addAnimation(wr.witchCaustic.animationNamed("in"))
    wr.blinkWitch()
    v.addAnimation(wr.titleIn)
    v.addAnimation(wr.witchIn)

    wr.titleIn.addLoopProgressHandler 1.0, true, proc() =
        wr.lettersController = title.findNode("letters_controller")
        wr.titlePositions = wr.lettersController.getLettersPositions()
        wr.lettersController.addWiggleToLetters()

        if wr.curLevel < wr.level:
            wr.curLevel.inc()
            v.moveToNextLevel(wr)
            wr.titleOut.onComplete do():
                v.showNextLevel(wr)
        else:
            wr.stop.enabled = true

method destroy*(wr: WitchBigwinScreen) =
    wr.node.sceneView.BaseMachineView.onWinDialogClose()
    let v = wr.numbers.sceneView()
    let anim = v.hideLetters(wr)

    wr.gold.component(ParticleSystem).stop()
    wr.destroyed = true
    wr.stop.enabled = false
    wr.blinkWitch(true)
    anim.onComplete do():
        wr.removeScreenElements()

proc animateStart(v: WitchSlotView, wr: WitchBigwinScreen) =
    v.animateBase(wr)
    v.addAnimation(wr.witchIn)
    v.addAnimation(wr.witchCaustic.animationNamed("in"))
    wr.blinkWitch()
    wr.currentSound = v.soundManager.playSFX("slots/witch_slot/sound/witch_big_win")
    wr.effectsIn.addLoopProgressHandler 0.15, true, proc() =
        v.addAnimation(wr.titleIn)
        wr.titleIn.addLoopProgressHandler 0.9, true, proc() =
            wr.titlePositions = wr.lettersController.getLettersPositions()
            wr.readyForClose = true
            wr.lettersController.addWiggleToLetters()
            v.onWinDialogShowAnimationComplete()

            if wr.curLevel < wr.level:
                wr.curLevel.inc()
                v.moveToNextLevel(wr)
                wr.titleOut.onComplete do():
                    v.showNextLevel(wr)
            else:
                wr.stop.enabled = true
    wr.effectsIn.addLoopProgressHandler 0.4, true, proc() =
        if wr.level == BigWinType.Big:
            v.interpolateAmount(wr, 0, wr.amount)
        else:
            v.interpolateAmount(wr, 0, v.totalBet * TRESHOLDS[0])


proc startBigwinScreen*(v: WitchSlotView, number: int64, onDestroy: proc()): WitchBigwinScreen {.discardable.} =
    result.new()
    let res = result

    res.node = v.specialWinParent.newChild("bigwin_screen")
    res.onDestroy = onDestroy

    var rune: Node
    var caustics: Node
    var title: Node

    res.witch = newNodeWithResource("slots/witch_slot/special_win/precomps/witch_pose_1.json")
    res.effects = newNodeWithResource("slots/witch_slot/special_win/precomps/scene_effects.json")
    res.numbers = newNodeWithResource("slots/witch_slot/special_win/precomps/numbers_branding_green.json")
    res.glow = newNodeWithResource("slots/witch_slot/special_win/precomps/scene_glow.json")
    rune = newNodeWithResource("slots/witch_slot/special_win/precomps/rune_1_clover.json")
    title = newNodeWithResource("slots/witch_slot/special_win/precomps/big_win_title.json")
    caustics = rune.findNode("caustics_rune")
    res.witchCaustic = res.witch.findNode("witch_pose_caustiс_in_out")
    res.runeIn = rune.animationNamed("in")
    res.runeOut = rune.animationNamed("out")
    res.causticsAnim = caustics.animationNamed("play")
    res.effectsIn = res.effects.animationNamed("in")
    res.effectsIdle = res.effects.animationNamed("idle")
    res.effectsOut = res.effects.animationNamed("out")
    res.numbersIn = res.numbers.animationNamed("in")
    res.numbersOut = res.numbers.animationNamed("out")
    res.glowAnim = res.glow.animationNamed("play")
    res.titleIn = title.animationNamed("in")
    res.titleOut = title.animationNamed("out")
    res.witchIn = res.witch.animationNamed("in")

    res.node.addChild(rune)

    res.gold = newNodeWithResource("slots/witch_slot/particles/gold_particles_main.json")
    res.node.addChild(res.gold)
    res.gold.position = newVector3(v.viewportSize.width / 2, v.viewportSize.height / 2)

    res.moreGold = newNodeWithResource("slots/witch_slot/particles/gold_particles_add.json")
    res.node.addChild(res.moreGold)
    res.moreGold.position = newVector3(v.viewportSize.width / 2, v.viewportSize.height / 2)

    let witchParent = res.node.newChild("witch_parent")
    witchParent.addChild(res.witch)
    res.node.addChild(res.numbers)

    let titleParent = res.node.newChild("title_parent")
    titleParent.addChild(title)

    res.node.addChild(res.effects)
    res.node.addChild(res.glow)
    res.effects.alpha = 0
    res.glow.alpha = 0
    res.amount = number
    res.level = v.getBigWinType()

    let buttonParent = res.node.newChild("button_parent")
    res.stop = button_parent.createButtonComponent(newRect(0, 0, v.viewportSize.width, v.viewportSize.height))
    res.stop.enabled = false
    res.stop.onAction do():
        res.destroy()

    res.lettersController = title.findNode("letters_controller")
    res.numbersPos = res.numbers.childNamed("numbers_controller").position
    v.showAmount(res, 1)
    v.animateStart(res)
    v.slotGUI.enableWindowButtons(false)
