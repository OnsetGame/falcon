import rod.node
import rod.viewport
import rod.component
import rod.component.ui_component
import rod.component.color_balance_hls
import rod.component.particle_system
import rod.quaternion
import nimx.animation
import nimx.types
import nimx.button
import nimx.matrixes
import nimx.view
import nimx.timer
import core / notification_center
import falconserver.slot.machine_witch_types
import utils.fade_animation
import utils.node_animations
import utils.sound_manager
import core.slot.base_slot_machine_view
import shared.gui.gui_pack
import shared.gui.gui_module_types
import shared.gui.gui_module
import shared.gui.candy_bonus_rules_module
import shared.gui.win_panel_module
import shared.localization_manager
import shared.gui.slot_gui
import shared.gui.spin_button_module
import shared.game_flow
import shared.chips_animation
import shared.director
import shared.window.button_component
import shared.game_scene
import random
import strutils
import witch_slot_view
import witch_line_numbers
import witch_pot_anim
import witch_result_screen
import witch_sound
import tables

# TODO displacement
# TODO replace elements
# TODO "define symbols" in common

const PREFIX = "slots/witch_slot/bonus/precomps/"

type TVector5[T] = TVector[5, T]
type Vector5 = TVector5[Coord]
proc newVector5(x, y, z, w, v: Coord = 0): Vector5 = [x, y, z, w, v]

type Ingredient = enum
    Acorn,
    Clover,
    Shell,
    Raspberry,
    Eye

type BonusGame* = ref object of RootObj
    idleBack: Animation
    idleDop: Animation
    idleFire: Animation
    idleBubbles: Animation
    idleCauldron: Animation
    winEndCauldron:Animation
    idleSmokeColor: Animation
    idleSmokeBack: Animation
    idleIntro: Animation
    spinAnim: Animation
    winBack: Animation
    winIdleBack: Animation
    winEndBack: Animation
    winShockwave: Animation
    winGeneral: Animation
    winCauldron: Animation
    appearGeneral: Animation
    disappearGeneral: Animation
    outIntro: Animation
    fade: FadeAnimation
    initialFade: FadeSolidAnimation
    currentRound: int
    rounds: int
    totalWin: int64
    fields: seq[seq[Ingredient]]
    winningIngredients: Table[Ingredient, int64]
    bigsmoke: Node
    loplop: Node
    loopAnims: seq[Animation]
    winModule: WinPanelModule
    sb: SpinButtonModule
    highlightNodes: seq[Node]
    winHighlightAnimation: Animation
    winAnimationsRepeating: bool

proc appearElements(v: WitchSlotView, bg: BonusGame)

proc getRounds(v: WitchSlotView): int =
    var cl = v.bonusField.len
    var amount = v.pd.bonusElementsStartAmount

    while cl > 0:
        cl -= amount
        result.inc()
        amount.dec()

proc getRoundFieldPos(v: WitchSlotView, round: int): tuple[first: int, last: int] =
    var amount = v.pd.bonusElementsStartAmount
    for i in 2..round:
        result.first = result.first + amount
        amount.dec()
    result.last = result.first + amount - 1

proc getRoundField(v: WitchSlotView, round: int): seq[int8] =
    let pos = v.getRoundFieldPos(round)

    result = @[]
    for i in pos.first..pos.last:
        result.add(v.bonusField[i])

proc getRoundPayout*(v: WitchSlotView, round: int): int64 =
    let field = v.getRoundField(round)
    result = getRoundPayout(v.pd.bonusElementsPaytable, field) * v.bonusTotalBet

proc setWinningIngredients(v: WitchSlotView, bg: BonusGame) =
    let field = bg.fields[bg.currentRound - 1]
    var check: seq[int] = @[0, 0, 0, 0, 0]

    bg.winningIngredients = initTable[Ingredient, int64]()
    for i in 0..<field.len:
        check[field[i].int].inc()
    for i in 0..<5:
        let elems = check[i]
        if elems >= 3:
            let payoutForSpecificElement = v.pd.bonusElementsPaytable[i][elems - 3]
            bg.winningIngredients[i.Ingredient] = payoutForSpecificElement.int64 * v.bonusTotalBet

proc fillFields(v: WitchSlotView, bg: BonusGame) =
    bg.fields = @[]
    for i in 1..bg.rounds:
        var field: seq[Ingredient] = @[]
        let rf = v.getRoundField(i)

        for e in rf:
            field.add(e.Ingredient)
        bg.fields.add(field)

proc addBonusElementNode(v: WitchSlotView, pos: int, element: Ingredient) =
    let parent = v.bonusParent.findNode("elements_parent_" & $pos)
    let elementNode = newNodeWithResource(PREFIX & "elem_" & ($element).toLowerAscii() & ".json")

    parent.addChild(elementNode)

proc fillCauldron(v: WitchSlotView, bg: BonusGame) =
    var start: seq[int] = @[]
    var count = v.pd.bonusElementsStartAmount - bg.currentRound + 1

    for i in 1..v.pd.bonusElementsStartAmount:
        start.add(i)

    for i in 1..count:
        let r = rand(start.len - 1)
        let element = bg.fields[bg.currentRound - 1][i - 1].Ingredient

        if r < start.len:
            v.addBonusElementNode(start[r], element)
            start.del(r)

proc showLoplop(v: WitchSlotView, show: bool) =
    let anim = newAnimation()

    anim.loopDuration = 0.3
    anim.numberOfLoops = 1
    anim.onAnimate = proc(p: float) =
        if show:
            v.bonusParent.findNode("loplop_parent").alpha = interpolate(0.0, 1.0, p)
        else:
            v.bonusParent.findNode("loplop_parent").alpha = interpolate(1.0, 0.0, p)

    v.addAnimation(anim)

proc elementsResurfaceAnimation(v: WitchSlotView, bg: BonusGame) =
    for i in 1..v.pd.bonusElementsStartAmount:
        closureScope:
            let index = i
            let parent = v.bonusParent.findNode("elements_parent_" & $index)

            if parent.children.len > 1:
                let elem = parent.children[1]
                let animIn = elem.animationNamed("in")
                let animIdle = elem.animationNamed("idle")

                v.addAnimation(animIn)
                animIn.loopPattern = lpStartToEnd
                animIn.onComplete do():
                    v.setTimeout 0.05 * index.float, proc() =
                        v.addAnimation(animIdle)
                        animIdle.numberOfLoops = -1
                bg.loopAnims.add(animIdle)
    v.soundManager.sendEvent("BONUS_ELEMENTS_RESURFACE")

proc elementsSinkAnimation(v: WitchSlotView, bg: BonusGame) =
    for i in 1..v.pd.bonusElementsStartAmount:
        let parent = v.bonusParent.findNode("elements_parent_" & $i)
        let firstChild = parent.children[0]
        var elem: Node

        if firstChild.children.len > 0:
            elem = firstChild.children[0]
        else:
            if parent.children.len > 1:
                elem = parent.children[1]

        if not elem.isNil:
            let animIn = elem.animationNamed("in")
            let animIdle = elem.animationNamed("idle")

            animIdle.cancel()
            animIn.loopPattern = lpEndToStart
            v.addAnimation(animIn)
    v.soundManager.sendEvent("BONUS_ELEMENTS_SINK")

proc spinCauldron(v: WitchSlotView, bg: BonusGame) =
    v.showLoplop(false)

    bg.spinAnim.removeHandlers()
    bg.spinAnim.addLoopProgressHandler 0.9, false, proc() =
        v.appearElements(bg)
        v.showLoplop(true)
    v.addAnimation(bg.spinAnim)

    v.soundManager.sendEvent("BONUS_GAME_SPIN")

proc colorizeSmokeParticle(v: WitchSlotView, bg: BonusGame, to: bool) =
    if to:
        bg.bigsmoke.component(ParticleSystem).colorSeq = @[newVector5(0.0, 0.54, 0.34, 0.82, 0.0), newVector5(0.4, 0.54, 0.34, 0.82, 0.1), newVector5(0.7, 0.54, 0.34, 0.82, 0.25), newVector5(1.0, 0.54, 0.34, 0.82, 0.0)]
    else:
        bg.bigsmoke.component(ParticleSystem).colorSeq = @[newVector5(0.0, 0.42, 0.63, 0.27, 0.0), newVector5(0.4, 0.42, 0.63, 0.27, 0.1), newVector5(0.7, 0.42, 0.63, 0.27, 0.25), newVector5(1.0, 0.42, 0.63, 0.27, 0.0)]

proc colorizeLoplop(v: WitchSlotView, bg: BonusGame, to: bool) =
    if to:
        bg.loplop.component(ParticleSystem).colorSeq = @[newVector5(0.0, 0.31, 0.14, 0.77, 0.0), newVector5(0.15, 0.31, 0.14, 0.77, 0.8), newVector5(0.9, 0.31, 0.14, 0.77, 0.7), newVector5(1.0, 0.31, 0.14, 0.77, 0.0)]
    else:
        bg.loplop.component(ParticleSystem).colorSeq = @[newVector5(0.0, 0.62, 0.88, 0.43, 0.0), newVector5(0.15, 0.62, 0.88, 0.43, 0.8), newVector5(0.9, 0.62, 0.88, 0.43, 0.7), newVector5(1.0, 0.62, 0.88, 0.43, 0.0)]

proc playRound(v: WitchSlotView, bg: BonusGame) =
    v.fillCauldron(bg)
    v.spinCauldron(bg)

proc playIntroSpin(v: WitchSlotView, bg: BonusGame) =
    block createRandomField:
        var initialField = @[0,1,2,3,4,0,1,2]
        initialField.shuffle()
        for i, elemIndex in initialField:
            v.addBonusElementNode(i+1, elemIndex.Ingredient)

    v.elementsResurfaceAnimation(bg)
    v.canSpinBonus = true

proc colorizeSmoke(v: WitchSlotView, bg: BonusGame, to: bool) =
    let smokeColor = v.bonusParent.findNode("smoke_color")
    let smokeBack = v.bonusParent.findNode("smoke_back")
    var effectSmoke = ColorBalanceHLS.new()
    let anim = newAnimation()

    if to:
        smokeColor.removeComponent(ColorBalanceHLS)
        smokeBack.removeComponent(ColorBalanceHLS)
        effectSmoke.init()
        smokeColor.setComponent("ColorBalanceHLS", effectSmoke)
        smokeBack.setComponent("ColorBalanceHLS", effectSmoke)

    anim.loopDuration = 0.4
    anim.numberOfLoops = 1
    anim.onAnimate = proc(p: float) =
        if to:
            effectSmoke.hue = interpolate(0.0, 0.5, p)
            effectSmoke.hue = interpolate(0.0, 0.5, p)
        else:
            smokeColor.getComponent(ColorBalanceHLS).hue = interpolate(0.5, 0.0, p)
            smokeBack.getComponent(ColorBalanceHLS).hue = interpolate(0.5, 0.0, p)

    v.addAnimation(anim)

proc clearParents(v: WitchSlotView) =
    for i in 1..v.pd.bonusElementsStartAmount:
        let parent = v.bonusParent.findNode("elements_parent_" & $i)
        let ch = parent.children

        if ch.len > 1:
            ch[1].removeFromParent()
        ch[0].removeAllChildren()

proc clearLastRoundResults(v: WitchSlotView, bg: BonusGame) =
    v.elementsSinkAnimation(bg)
    if bg.highlightNodes.len > 0:
        for highlightNode in bg.highlightNodes:
            highlightNode.removeFromParent()
        bg.highlightNodes = @[]

    if bg.currentRound == 1: # Clear initial random elements.
        v.setTimeout 1.0, proc() =
            v.clearParents()
            v.playRound(bg)
    else:
        v.addAnimation(bg.disappearGeneral)

        if not bg.winHighlightAnimation.isNil:
            let temp = bg.winHighlightAnimation
            bg.winHighlightAnimation = nil
            temp.cancel()

        bg.winAnimationsRepeating = false

        bg.disappearGeneral.addLoopProgressHandler 0.8, false, proc() =
            bg.winIdleBack.cancel()

        bg.disappearGeneral.onComplete do():
            bg.disappearGeneral.removeHandlers()
            v.clearParents()
            v.playRound(bg)

proc bubblesElement(v: WitchSlotView, index: int) =
    let under_element = newNodeWithResource("slots/witch_slot/particles/under_element.json")
    let bubbles = newNodeWithResource("slots/witch_slot/particles/bubbles.json")
    let under = v.bonusParent.findNode("under_element_" & $index)
    let particle = bubbles.getComponent(ParticleSystem)

    under.addChild(under_element)
    under_element.position = newVector3(120.0, 120.0)
    under.addChild(bubbles)
    bubbles.position = newVector3(120.0, 120.0)
    bubbles.reattach(v.bonusParent)
    v.setTimeout particle.duration + particle.lifetime, proc() =
        bubbles.removeFromParent()

proc createWinHighlightAnimations(v: WitchSlotView, bg: BonusGame) =
    var winHighlightAnimations = newSeq[Animation]()

    for ingr, payout in bg.winningIngredients.pairs:
        closureScope:
            let name = $ingr
            let closePayout = payout

            var currentElementHighlights = newSeq[Animation]()

            for i in 1..v.pd.bonusElementsStartAmount:
                closureScope:
                    let closeI = i
                    let elementParent = v.bonusParent.findNode("elements_parent_" & $closeI)

                    if elementParent.children.len > 1:
                        let elem = elementParent.children[1]
                        if elem.name == "elem_" & name.toLowerAscii():
                            let parent = v.bonusParent.findNode("highlight_parent_" & $closeI)
                            let highlightNode = newNodeWithResource(PREFIX & "highlight.json")
                            parent.addChild(highlightNode)
                            highlightNode.position = newVector3(-65.0, -65.0)
                            let highlightAnim = highlightNode.animationNamed("play")
                            highlightAnim.addLoopProgressHandler 0.0, false, proc() =
                                highlightNode.alpha = 1.0
                                v.bubblesElement(closeI)
                            highlightAnim.onComplete do():
                                highlightNode.alpha = 0.0
                            bg.highlightNodes.add(highlightNode)
                            currentElementHighlights.add(highlightAnim)
                            elem.reattach(elementParent.children[0])

            let ca = newCompositAnimation(true, currentElementHighlights)
            ca.numberOfLoops = 1
            ca.loopDuration = 2.0
            ca.addLoopProgressHandler 0.0, false, proc()=
                v.createWinLineNumbers(v.bonusParent, closePayout, true)
                if not bg.winAnimationsRepeating:
                    v.soundManager.sendEvent("BONUS_GAME_WIN") # Will be played once, for the first win highlight loop.

            winHighlightAnimations.add(ca)

    if winHighlightAnimations.len > 0:
        bg.winHighlightAnimation = newCompositAnimation(false, winHighlightAnimations)
        bg.winHighlightAnimation.numberOfLoops = 1


proc reapeatWinElementsHighlighting(v: WitchSlotView, bg: BonusGame) =
    if not bg.winHighlightAnimation.isNil:
        bg.winAnimationsRepeating = true
        bg.winHighlightAnimation.removeHandlers()
        bg.winHighlightAnimation.onComplete do():
            v.reapeatWinElementsHighlighting(bg)
        v.addAnimation(bg.winHighlightAnimation)

proc playWin(v: WitchSlotView, bg: BonusGame) =
    assert(not bg.winHighlightAnimation.isNil)
    bg.idleCauldron.cancel()

    bg.winBack.onComplete do():
        bg.winBack.removeHandlers()
        bg.winIdleBack.onComplete do():
            bg.winIdleBack.removeHandlers()
            v.addAnimation(bg.winEndCauldron)

            bg.winEndCauldron.onComplete do():
                bg.winEndCauldron.removeHandlers()
                v.addAnimation(bg.idleCauldron)

            bg.winEndBack.addLoopProgressHandler 0.6, true, proc() =
                # Here we should change color from win to normal
                v.colorizeSmoke(bg, false)
                v.colorizeSmokeParticle(bg, false)
                v.colorizeLoplop(bg, false)
            bg.winEndBack.onComplete do():
                bg.winEndBack.removeHandlers()
                v.addAnimation(bg.idleBack)
            v.addAnimation(bg.winEndBack)
        v.addAnimation(bg.winIdleBack)

    v.addAnimation(bg.winGeneral)
    v.addAnimation(bg.winBack)
    v.addAnimation(bg.winCauldron)

    bg.winHighlightAnimation.onComplete do():
        if not bg.winHighlightAnimation.isNil:
            bg.winHighlightAnimation.removeHandlers()
            v.reapeatWinElementsHighlighting(bg)

    v.addAnimation(bg.winHighlightAnimation)

proc playExitBonusGame(v: WitchSlotView, bg: BonusGame, delay:float) =
    v.onBonusGameEnd()
    v.slotGUI.winPanelModule.setNewWin(v.currentWin+v.bonusPayout)
    v.setTimeout delay, proc() =
        bg.initialFade.changeFadeAnimMode(1, 0.5)
        v.setTimeout 0.5, proc() =
            for anim in bg.loopAnims:
                anim.cancel()
            v.mainParent.enabled = true
            v.prepareGUItoBonus(false)
            currentNotificationCenter().removeObserver("WITCH_BONUS_SPACE_CLICK", v)
            v.bonusParent.removeAllChildren()
            v.slotGUI.removeModule(mtCandyBonusRules)
            bg.winModule.rootNode.removeFromParent()
            bg.sb.rootNode.removeFromParent()
            proc onDestroy() =
                let oldBalance = v.slotGUI.moneyPanelModule.getBalance().int64

                v.specialWinParent.removeAllChildren()
                v.initialFade.changeFadeAnimMode(0, 0.5)
                v.chipsAnim(v.rootNode.findNode("total_bet_panel"), oldBalance, oldBalance + v.bonusPayout, "Bonus")
                v.canSpinBonus = false
                v.gameFlow.nextEvent()

            v.winDialogWindow = v.startResultScreen(v.bonusPayout, true, onDestroy)

proc appearElements(v: WitchSlotView, bg: BonusGame) =
    bg.appearGeneral.removeHandlers()
    v.addAnimation(bg.appearGeneral)
    v.setWinningIngredients(bg)
    if bg.winningIngredients.len == 0:
        v.bonusParent.findNode("svet.png").removeFromParent()
    v.elementsResurfaceAnimation(bg)

    v.createWinHighlightAnimations(bg)

    bg.appearGeneral.addLoopProgressHandler 0.9, false, proc() =
        if bg.winningIngredients.len > 0:
            v.colorizeSmoke(bg, true)
            v.colorizeSmokeParticle(bg, true)
            v.colorizeLoplop(bg, true)
            v.addAnimation(bg.winShockwave)

    bg.appearGeneral.addLoopProgressHandler 1.0, false, proc() =
        if bg.winningIngredients.len > 0:
            v.playWin(bg)
        else:
            v.playExitBonusGame(bg, 2.5)

proc createBack*(v: WitchSlotView, bg: BonusGame): Node =
    result = newNodeWithResource(PREFIX & "back.json")

    bg.idleBack = result.animationNamed("idle")
    bg.winBack = result.animationNamed("win")
    bg.winIdleBack = result.animationNamed("win_idle")
    bg.winEndBack = result.animationNamed("win_end")
    bg.idleDop = result.findNode("dop_bg").animationNamed("play")
    bg.idleFire = result.findNode("bg_fire").animationNamed("play")
    bg.idleBubbles = result.findNode("bubbles").animationNamed("play")

    v.addAnimation(bg.idleBack)
    v.addAnimation(bg.idleDop)
    v.addAnimation(bg.idleFire)
    v.addAnimation(bg.idleBubbles)

    bg.winIdleBack.numberOfLoops = -1
    bg.idleBack.numberOfLoops = -1
    bg.idleDop.numberOfLoops = -1
    bg.idleFire.numberOfLoops = -1
    bg.idleBubbles.numberOfLoops = -1
    bg.loopAnims.add(bg.idleBack)
    bg.loopAnims.add(bg.idleDop)
    bg.loopAnims.add(bg.idleFire)
    bg.loopAnims.add(bg.idleBubbles)

proc createSpin*(v: WitchSlotView, bg: BonusGame): Node =
    result = newNodeWithResource(PREFIX & "spin.json")
    bg.spinAnim = result.animationNamed("play")

proc creatShockwave(v: WitchSlotView, bg: BonusGame): Node =
    result = newNodeWithResource(PREFIX & "shockwave.json")
    bg.winShockwave = result.animationNamed("play")

proc createGeneral(v: WitchSlotView, bg: BonusGame): Node =
    result = newNodeWithResource(PREFIX & "general.json")
    let cauldron = result.findNode("cauldron")

    bg.winGeneral = result.animationNamed("win")
    bg.winGeneral.onComplete do():
        let roundPayout = v.getRoundPayout(bg.currentRound)

        if roundPayout > 0:
            bg.totalWin += roundPayout
            bg.winModule.setNewWin(bg.totalWin)

        v.canSpinBonus = true

    bg.winCauldron = cauldron.animationNamed("win")
    bg.appearGeneral = result.animationNamed("appear")
    bg.disappearGeneral = result.animationNamed("disappear")
    bg.idleCauldron = cauldron.animationNamed("idle")
    bg.winEndCauldron = cauldron.animationNamed("win_end")
    bg.idleSmokeBack = cauldron.findNode("smoke_back").animationNamed("idle")
    bg.idleSmokeColor = cauldron.findNode("smoke_color").animationNamed("idle")
    bg.idleCauldron.numberOfLoops = -1
    bg.idleSmokeBack.numberOfLoops = -1
    bg.idleSmokeColor.numberOfLoops = -1
    bg.loopAnims.add(bg.idleCauldron)
    bg.loopAnims.add(bg.idleSmokeBack)
    bg.loopAnims.add(bg.idleSmokeColor)

proc startCauldronIdle(v: WitchSlotView, bg: BonusGame) =
    v.addAnimation(bg.idleCauldron)
    v.addAnimation(bg.idleSmokeBack)
    v.addAnimation(bg.idleSmokeColor)

proc createIntro(v: WitchSlotView, bg: BonusGame): Node = #fade
    result = newNode("intro")
    bg.fade = addFadeSolidAnim(v, result, blackColor(), v.viewportSize, 0.0, 0.25, 0)

    let intro = newNodeWithResource(PREFIX & "bonus_intro.json")
    result.addChild(intro)

    bg.idleIntro = intro.animationNamed("idle")
    bg.outIntro = intro.animationNamed("out")
    bg.idleIntro.numberOfLoops = -1
    bg.loopAnims.add(bg.idleIntro)
    v.addAnimation(bg.idleIntro)

proc clickBonusSpin*(v: WitchSlotView, bg: BonusGame) =
    if bg.currentRound <= bg.rounds and v.canSpinBonus:
        bg.currentRound.inc()
        v.clearLastRoundResults(bg)
        v.canSpinBonus = false
        v.rotateSpinButton(bg.sb)

proc createStartButton(v: WitchSlotView, bg: BonusGame, parent: Node) =
    let buttonParent = parent.newChild("start_button_parent")
    let button = newButton(newRect(0, 0, 350, 220))

    button.hasBezel = false
    buttonParent.position = newVector3(790, 690)
    buttonParent.component(UIComponent).view = button
    button.onAction do():
        let rules = v.slotGUI.addModule(mtCandyBonusRules).CandyBonusRulesModule
        rules.rootNode.position = newVector3(490, 100)

        let rulesText = localizedString("WITCH_BONUS_INTRO").replace("\n", " ")

        bg.winModule = v.slotGUI.addModule(mtWinPanel).WinPanelModule
        bg.winModule.rootNode.position = newVector3(800, 970)

        bg.winModule.setNewWin(0)
        rules.setRulesText(rulesText)
        button.enabled = false
        buttonParent.removeFromParent()
        bg.idleIntro.cancel()
        v.addAnimation(bg.outIntro)
        bg.outIntro.onComplete do():
            v.playIntroSpin(bg)
        bg.fade.changeFadeAnimMode(0, bg.outIntro.loopDuration)

        bg.sb = v.slotGUI.addModule(mtSpinButton).SpinButtonModule
        bg.sb.rootNode.position = newVector3(1645, 805)

        bg.sb.rootNode.reattach(v.bonusParent)
        bg.sb.rootNode.name = "witch_spin_bonus"
        bg.sb.button.onAction do():
            v.clickBonusSpin(bg)
        #v.canSpinBonus = true

proc addWiggle(n: Node) =
    var wiggle = n.getComponent(WiggleAnimation)

    wiggle = n.addComponent(WiggleAnimation).WiggleAnimation
    wiggle.octaves = 4
    wiggle.persistance = 9.0
    wiggle.amount = 1.0
    wiggle.propertyType = NAPropertyType.alpha
    if not wiggle.animation.isNil:
        wiggle.enabled = true
        wiggle.animation.loopDuration = 0.3

proc addWiggles(v: WitchSlotView) =
    v.bonusParent.findNode("kotel_shadow.png").addWiggle()
    v.bonusParent.findNode("glow_kotel.png").addWiggle()
    v.bonusParent.findNode("color_reflect.png").addWiggle()

proc createBonusScene*(v: WitchSlotView) =
    let bg = BonusGame.new()
    bg.loopAnims = @[]

    let back = v.createBack(bg)
    let spin = v.createSpin(bg)
    let shockwave = v.creatShockwave(bg)
    let general = v.createGeneral(bg)
    let intro = v.createIntro(bg)
    let turb = newNodeWithResource("slots/witch_slot/particles/turb.json")
    let turb2 = newNodeWithResource("slots/witch_slot/particles/turb2.json")

    bg.loplop = newNodeWithResource("slots/witch_slot/particles/loplop.json")
    bg.bigsmoke = newNodeWithResource("slots/witch_slot/particles/big_smoke.json")
    v.bonusParent.addChild(back)
    v.bonusParent.addChild(spin)
    v.bonusParent.addChild(shockwave)
    v.bonusParent.addChild(general)
    v.bonusParent.addChild(intro)
    v.startCauldronIdle(bg)
    v.createStartButton(bg, intro)
    bg.rounds = v.getRounds()
    bg.currentRound = 0
    bg.highlightNodes = @[]
    v.fillFields(bg)
    v.addWiggles()
    v.playBackgroundMusic(MusicType.Bonus)
    back.findNode("turb_parent").addChild(turb)
    back.findNode("turb_parent").addChild(turb2)
    v.bonusParent.findNode("loplop_parent").addChild(bg.loplop)
    v.bonusParent.addChild(bg.bigsmoke)
    v.colorizeSmokeParticle(bg, false)
    v.colorizeLoplop(bg, false)
    bg.initialFade = addFadeSolidAnim(v, v.bonusParent, blackColor(), v.viewportSize, 1.0, 0.0, 0.5)
    v.mainParent.enabled = false
    v.initPotLights(true)
    v.onBonusGameStart()

    currentNotificationCenter().addObserver("WITCH_BONUS_SPACE_CLICK", v) do(args: Variant):
        v.clickBonusSpin(bg)
