import tables
import strutils
import sequtils
import logging
import random
import algorithm

import nimx.types
import nimx.matrixes
import nimx.animation
import nimx.button
import nimx.timer

import rod.rod_types
import rod.node
import rod.component
import rod.component.text_component
import rod.component.ui_component

import utils.helpers
import utils.sound_manager
import utils.animation_controller
import utils.fade_animation
import utils.pause

import shared.gui.slot_gui
import shared.gui.gui_module_types
import shared.gui.win_panel_module
import shared.game_scene
import core.slot.base_slot_machine_view

import eiffel_slot_view

const viewportSize = newSize(1920, 1080)
const DISHES_COUNT = 8
const GENERAL_PREFIX = "slots/eiffel_slot/"

type BonusDishes*  = enum
    X2,
    X3,
    X4,
    Croissant,
    Soup,
    Ratatouille,
    Cheese,
    CremeBrulee

type EiffelBonusGameView* = ref object of RootObj
    numberOfMisses: int
    openDishes: seq[bool]
    moneyWon: int64
    isClickActive: bool
    isWelcomeScreenActive*: bool
    tempFade: FadeSolidAnimation
    chefController: AnimationController
    winTextNodes: seq[Node]
    currentClick: int
    dishesOpened:seq[int]
    visibleOpenedDishes: seq[int]
    dishesPrepared: seq[Node]
    gameResult: seq[int]
    gameBet: int64
    winModule: WinPanelModule
    buttonsDish: seq[UIComponent]
    bonusConfigRelation: seq[int]
    rootNode*: Node
    soundManager: SoundManager
    onComplete: proc()
    scene: EiffelSlotView
    interval: ControlledTimer

proc glintDishes(v: EiffelBonusGameView)
proc onDishClicked(v: EiffelBonusGameView, dishIndex: int)

proc getDishPrice*(v: EiffelBonusGameView, dish: BonusDishes): int64 =
    result = if v.bonusConfigRelation.len != 0: v.bonusConfigRelation[dish.int] else: 0

let foodOffset = {
    "Ratatouille": newVector3(5, 5),
    "Cheese": newVector3(15, 30),
    "CremeBrulee": newVector3(35, 20),
    "Soup": newVector3(30, 5),
    "Croissant": newVector3(5, 5)
    }.toTable()

let foodScale = {
    "Ratatouille": newVector3(1, 1, 1),
    "Cheese": newVector3(0.9, 0.9, 1),
    "CremeBrulee": newVector3(0.95, 0.95, 1),
    "Soup": newVector3(0.85, 0.85, 1),
    "Croissant": newVector3(0.9, 0.9, 1)
    }.toTable()

proc setFoodSettings(v: EiffelBonusGameView, foodNode: Node, dishNode: Node, foodName: string) =
    const OFFSET_X = 50
    const OFFSET_Y = 350

    foodNode.positionX = OFFSET_X + foodOffset[foodName].x
    foodNode.positionY = OFFSET_Y + foodOffset[foodName].y
    foodNode.scale = foodScale[foodName]
    dishNode.children.setLen(dishNode.children.len - 1)
    dishNode.children.insert(foodNode, 0)

proc placeFoodUnderDish(v: EiffelBonusGameView, dishIndex: int, foodName: string ): Node {.discardable.} =
    let dishNode = v.rootNode.findNode("Cloche" & $dishIndex)
    var foodNode:Node
    for i, node in v.dishesPrepared:
        if node.name == foodName:
            foodNode = node
            v.dishesPrepared.delete(i)
            break

    doAssert(foodName.len != 0, "Server send incorect bonus game field")
    dishNode.addChild(foodNode)
    v.setFoodSettings(foodNode, dishNode, foodName)
    result = foodNode

proc animateTextMultiply(v: EiffelBonusGameView, n: Node, multiplier: int)=
    var text = n.component(Text)
    var prevVal:int64 = parseBiggestInt(text.text).int64

    var toVal:int64 =  prevVal * multiplier
    var prevSize = text.font.scale
    var nextSize = text.font.scale * 1.1

    var anim = newAnimation()
    anim.numberOfLoops = 1
    anim.loopDuration = 0.25
    anim.onAnimate = proc(p: float) =
        text.text = $interpolate(prevVal, toVal, p)

    var scaleUp = newAnimation()
    scaleUp.numberOfLoops = 1
    scaleUp.loopDuration = 0.25
    scaleUp.onAnimate = proc(p: float)=
        text.font.scale = interpolate(prevSize, nextSize, elasticEaseIn(p, 5.0) )

    var meta = newMetaAnimation(anim, scaleUp)
    meta.numberOfLoops = 1
    meta.parallelMode = true

    v.rootNode.addAnimation(meta)

proc multiplier(v: EiffelBonusGameView, multiplier: int, multNode: Node)=
    multNode.findNode("textField").getComponent(Text).text = "X" & $multiplier
    for wn in v.winTextNodes:
        v.animateTextMultiply( wn.findNode("textField") , multiplier)

proc initButtons(v: EiffelBonusGameView) =
    let buttonStart = newButton(newRect(0, 0, 400, 200))

    buttonStart.hasBezel = false
    v.rootNode.findNode("start").component(UIComponent).view = buttonStart
    proc onStartClick() =

        let welcomeScreen = v.rootNode.findNode("Welcome Screen")
        let orange1 = v.rootNode.findNode("orange_1")
        let orange2 = v.rootNode.findNode("orange_2")
        let white1 = v.rootNode.findNode("white_1")
        let white2 = v.rootNode.findNode("white_2")
        let hideAnim = welcomeScreen.animationNamed("hide")

        v.soundManager.sendEvent("BONUS_GAME_MENU_SELECT")
        v.soundManager.sendEvent("BONUS_GAME_WHOOP_2")
        v.rootNode.addAnimation(hideAnim)
        v.isWelcomeScreenActive = false
        v.isClickActive = true
        buttonStart.enabled = false
        hideAnim.onComplete do():
            welcomeScreen.removeFromParent()
            orange1.removeFromParent()
            orange2.removeFromParent()
            white1.removeFromParent()
            white2.removeFromParent()

            v.winModule = createWinPanel(v.rootNode)
            v.winModule.setWinText("TOTAL WIN")
            v.winModule.setNewWin(0)
            v.winModule.rootNode.position = newVector3(800, 950)
            v.scene.showGUI()

    buttonStart.onAction do():
        onStartClick()

    v.buttonsDish = @[]
    for i in 0 ..< DISHES_COUNT:
        closureScope:
            let buttonDish = newButton(newRect(25, 200, 270, 300))
            let index = i
            buttonDish.hasBezel = false
            v.rootNode.findNode("Cloche" & $index).component(UIComponent).view = buttonDish
            buttonDish.onAction do():
                info "Cloche ", index, " active ", v.isClickActive
                if v.isClickActive:
                    buttonDish.enabled = false
                    v.onDishClicked(index)
            v.buttonsDish.add(v.rootNode.findNode("Cloche" & $index).component(UIComponent))

template isDishOpen(v: EiffelBonusGameView, dishIndex: int): bool = v.openDishes[dishIndex]
template setDishOpen(v: EiffelBonusGameView, dishIndex: int) = v.openDishes[dishIndex] = true

proc playSmokeNearDish(v: EiffelBonusGameView, n: Node) =
    let smokeNode = v.rootNode.findNode("Smoke_comp")
    smokeNode.reparentTo(v.rootNode)
    smokeNode.position = n.localToWorld(newVector3(-50, 50))
    let anim = smokeNode.animationNamed("play")
    anim.numberOfLoops = 1
    v.rootNode.addAnimation(anim)

proc getDishesForGlint(v:EiffelBonusGameView): seq[Node] =
    var res = newSeq[Node]()

    for i in 0 ..< DISHES_COUNT:
        if not v.isDishOpen(i):
            let n = v.rootNode.findNode("Cloche" & $i)
            res.add(n)

    res.sort do (n1, n2: Node) -> int:
        result = cmp(n1.localToWorld(newVector3()).x, n2.localToWorld(newVector3()).x)

    return res

proc glintDishes(v: EiffelBonusGameView) =
    if v.numberOfMisses < 2:
        let dishes =  v.getDishesForGlint()
        var delay = 0.0

        for dish in dishes:
            closureScope:
                let d = dish

                v.scene.setTimeout  delay, proc() =
                    if d in v.getDishesForGlint():
                        var animLight = d.animationNamed("light")
                        animLight.cancelBehavior = cbJumpToStart
                        v.rootNode.addAnimation(animLight)
                delay += 0.1

proc setDishTextValue(v: EiffelBonusGameView, n: Node, value: string) =
    let textNode = n.findNode("textField")
    let animatedText = textNode.component(Text)
    animatedText.text = value

proc onDishClicked(v: EiffelBonusGameView, dishIndex: int) =
    if v.isDishOpen(dishIndex): return
    v.setDishOpen(dishIndex)
    let n = v.rootNode.findNode("Cloche" & $dishIndex)

    let currentResult = v.gameResult[v.currentClick].BonusDishes

    v.currentClick.inc()
    v.dishesOpened.add(dishIndex)
    proc successfulClick() =
        v.playSmokeNearDish(n)
        v.placeFoodUnderDish(dishIndex, $currentResult)
        let win = v.getDishPrice(currentResult) * v.gameBet
        v.setDishTextValue(n, $win)
        v.winTextNodes.add(n)
        v.moneyWon += win

        let chiefBingo = v.chefController.setNextAnimation("bingo")
        chiefBingo.addLoopProgressHandler 0.5, true, proc() =
            v.soundManager.sendEvent("BONUS_GAME_KISS")

    if currentResult > X4:
        successfulClick()
    else:
        v.setDishTextValue(n, $currentResult)
        v.moneyWon *= v.getDishPrice(currentResult)
        v.multiplier(v.getDishPrice(currentResult).int, v.rootNode.findNode("Cloche" & $dishIndex))

        let rnd = rand(1..2)
        let chiefSad = v.chefController.setNextAnimation("sad")

        inc v.numberOfMisses
        chiefSad.addLoopProgressHandler 0.2, true, proc() =
            v.soundManager.sendEvent("BONUS_GAME_SAD_" & $rnd)

    let animLight = n.animationNamed("light")

    let anim = n.animationNamed("open")
    anim.continueUntilEndOfLoopOnCancel = true

    if not animLight.finished:
        animLight.cancel()
        animLight.onComplete do():
            v.rootNode.addAnimation(anim)
    else:
        v.rootNode.addAnimation(anim)

    let smallWin = n.findNode("small_win")
    let numbersAnim =  smallWin.animationNamed("play")

    v.rootNode.addAnimation(numbersAnim)
    numbersAnim.addLoopProgressHandler 0.75, true, proc() =
        numbersAnim.cancel()
    v.soundManager.sendEvent("BONUS_GAME_PLATE_OPEN_" & $rand(1..4))

    anim.onComplete do():
        v.winModule.setNewWin(v.moneyWon)
        v.soundManager.sendEvent("BONUS_GAME_DISAPPEAR")

    if v.numberOfMisses == 2:
        const DELAY = 1
        const FADE_DURATION = 1
        v.isClickActive = false

        var dishesAnims = newSeq[Animation]()
        for i in 0 ..< DISHES_COUNT:
            if not v.isDishOpen(i):
                closureScope:
                    v.setDishOpen(i)
                    var dish = v.rootNode.findNode("Cloche" & $i)
                    var clashe = dish.findNode("Clashe")
                    var la = dish.animationNamed("light")

                    if not la.finished:
                        la.cancel()

                    if v.dishesPrepared.len > 0:
                        var food = v.dishesPrepared.pop()
                        dish.addChild(food)
                        v.setFoodSettings(food, dish, food.name)

                    var anim = newAnimation()
                    anim.loopDuration = 0.25
                    anim.numberOfLoops = 1
                    anim.onAnimate = proc(p: float)=
                        clashe.alpha = interpolate(1.0, 0.6, p)
                    dishesAnims.add(anim)

        var delayAnim = newAnimation()
        delayAnim.loopDuration = 2.0
        delayAnim.numberOfLoops = 1
        dishesAnims.add(delayAnim)

        var metaAnim = newMetaAnimation(dishesAnims)
        metaAnim.numberOfLoops = 1

        metaAnim.onComplete do():
            v.soundManager.stopMusic(4)
            v.soundManager.stopAmbient(4)
            v.scene.setTimeout DELAY, proc() =
                discard addFadeSolidAnim(v.rootNode.sceneView, v.rootNode, blackColor(), viewportSize, 0.0, 1.0, FADE_DURATION)
            v.scene.setTimeout DELAY + FADE_DURATION, proc() =
                v.onComplete()

        v.rootNode.addAnimation(metaAnim)

var bg: EiffelBonusGameView

proc createBonusScene*(view: EiffelSlotView, gameBet: int64, callback: proc()) =
    bg = EiffelBonusGameView.new()

    bg.bonusConfigRelation = view.bonusConfigRelation
    bg.gameResult = view.bonusResult
    bg.gameBet = gameBet
    bg.onComplete = proc() =
        bg.scene.clearTimer(bg.interval)
        bg.soundManager.stopMusic(1.0)
        bg.chefController.stopIdles()
        bg.rootNode.removeAllChildren()
        bg.rootNode.removeFromParent()
        bg = nil
        callback()
    bg.scene = view
    bg.rootNode = newNode("bonus_game_root")
    # bonus game must lay before gui to make it visible
    for i, c in view.rootNode.children:
        if c.name == "popupHolder":
            view.rootNode.insertChild(bg.rootNode, i - 1)
            break
    bg.isWelcomeScreenActive = false
    bg.moneyWon = 0

    bg.openDishes = newSeq[bool](8)
    const INIT_DELAY = 0.01
    bg.tempFade = addFadeSolidAnim(bg.rootNode.sceneView, bg.rootNode, blackColor(), viewportSize, 1.0, 1.0, INIT_DELAY)

    bg.soundManager = view.soundManager
    bg.soundManager.loadEvents(GENERAL_PREFIX & "eiffel_sound/eiffel")

    let rn = newLocalizedNodeWithResource(GENERAL_PREFIX & "eiffel_bonus/BONUS_GAME.json")
    bg.rootNode.addChild(rn)
    bg.rootNode.addAnimation(rn.findNode("Projectors").animationNamed("start"))

    let door1 = rn.findNode("DOOR1")
    let door2 = rn.findNode("DOOR2")
    let anim1 = door1.animationNamed("door_open")
    let anim2 = door2.animationNamed("door_open")

    bg.rootNode.addAnimation(anim1)
    bg.rootNode.addAnimation(anim2)
    anim1.onComplete do():
        door1.removeFromParent()
    anim2.onComplete do():
        door2.removeFromParent()

    let doorsOpenAnim = rn.animationNamed("doors_open")
    let showWelcomeScreenAnim = rn.findNode("Welcome Screen").animationNamed("show")
    let text = rn.findNode("eiffel_bonus_text_1").component(Text)
    text.boundingSize = newSize(800.0,0.0)
    text.node.anchor = newVector3(400.0)
    text.verticalAlignment = vaCenter

    bg.rootNode.addAnimation(doorsOpenAnim)
    doorsOpenAnim.onComplete do():
        bg.soundManager.sendEvent("BONUS_GAME_WHOOP_1")
        bg.rootNode.addAnimation(showWelcomeScreenAnim)
    showWelcomeScreenAnim.onComplete do():
        bg.isWelcomeScreenActive = true

    bg.scene.setTimeout(1.0, proc() =
        bg.tempFade.alpha = 0.0
    )

    bg.initButtons()

    bg.scene.setTimeout 2.0, proc() =
        bg.glintDishes()
        bg.interval = bg.scene.setInterval(5.0, proc() =
            bg.glintDishes()
        )
    bg.scene.setTimeout 0.15, proc() =
        bg.soundManager.sendEvent("BONUS_GAME_MUSIC")
        bg.soundManager.sendEvent("BONUS_GAME_AMBIENCE")
    doorsOpenAnim.addLoopProgressHandler 0.15, true, proc() =
        bg.soundManager.sendEvent("ELEVATOR")

    let chefNode = newLocalizedNodeWithResource(GENERAL_PREFIX & "eiffel_bonus_chef/Chef.json")
    bg.rootNode.findNode("ChefPlaceholder").addChild(chefNode)
    bg.chefController = newAnimationControllerForNode(chefNode)
    bg.chefController.addIdles(["idle1", "idle2"])
    bg.chefController.playIdles()
    bg.dishesOpened = @[]
    bg.visibleOpenedDishes = @[]
    bg.numberOfMisses = 0
    bg.currentClick = 0
    bg.winTextNodes = @[]

    bg.dishesPrepared = @[]
    for i in BonusDishes.Croissant.int..BonusDishes.CremeBrulee.int:
        var node = bg.rootNode.findNode($(i.BonusDishes))
        node.removeFromParent()
        bg.dishesPrepared.add(node)

    view.onBonusGameStart()

proc bonusGameView*(): EiffelBonusGameView =
    return bg
