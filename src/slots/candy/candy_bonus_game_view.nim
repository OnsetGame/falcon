import nimx.view
import nimx.button
import nimx.matrixes
import nimx.animation
import nimx.font
import nimx.timer

import rod.rod_types
import rod.node
import rod.viewport
import rod.component
import rod.component.ui_component
import rod.component.particle_system
import rod.component.text_component

import utils.helpers
import utils.pause
import utils.animation_controller
import utils.sound_manager

import strutils
import random
import tables

const BOXES_COUNT = 9

type CandyBonusGame* = ref object of RootObj
    currentIndex, readyCounter: int
    sweets:seq[string]
    vases:Table[string, int]
    field: seq[int8]
    rootNode: Node
    pm: PauseManager
    sm: SoundManager
    onComplete*: proc()
    boyController: AnimationController
    buttons: seq[Button]
    labels:seq[Node]
    dishesValue:seq[int]
    totalBet: int64
    particles:seq[Node]
    idleAnims:seq[Animation]
    idleAnimation: Animation

proc enableButtons*(c: CandyBonusGame, enable: bool) =
    for i in 1..BOXES_COUNT:
        let parent = c.rootNode.findNode("box" & $i).findNode("bonus_button_parent")
        if not parent.isNil:
            c.buttons[i-1].enabled = enable
            parent.component(UIComponent).enabled = enable


proc removeLabels*(c: CandyBonusGame) =
    for label in c.labels:
        label.removeFromParent()

proc createLabels(c: CandyBonusGame)=
    c.labels = @[]

    for i in 0..<3:
        let label = newLocalizedNodeWithResource("slots/candy_slot/bonus/precomps/label.json")
        let t = label.component(Text)
        let font = newFontWithFace("BoyzRGross", 54)

        c.labels.add(label)
        t.font = font
        t.text = "x " & $(c.dishesValue[i].int64 div c.totalBet)
        c.rootNode.findNode("transition_scene").addChild(label)
    c.labels[0].position = newVector3(1688, 165)
    c.labels[1].position = newVector3(1695, -68)
    c.labels[2].position = newVector3(1667, 405)

proc clickOnButton(c: CandyBonusGame, index: int) =
    if c.currentIndex >= c.field.len:
        return
    let sweetName = c.sweets[c.field[c.currentIndex]]
    let box = c.rootNode.findNode("box" & $index)
    let particle = newLocalizedNodeWithResource("slots/candy_slot/particles/root_new_confetti.json")
    let boxAnim = box.animationNamed("play")
    let rnd = rand(1..3)
    let parent = box.findNode("bonus_button_parent")

    box.animationNamed("idle").cancel()
    c.rootNode.findNode("bonus").addChild(particle)
    c.particles.add(particle)
    particle.position = box.localToWorld(newVector3(300, 300))
    c.enableButtons(false)
    parent.removeFromParent()
    boxAnim.addLoopProgressHandler 0.15, false, proc() =
        c.sm.playSFX("slots/candy_slot/candy_sound/candy_unwrap_" & $rnd)
    boxAnim.addLoopProgressHandler 0.48, false, proc() =
        particle.alpha = 1.0
        for child in particle.children:
            child.component(ParticleSystem).start()
    for i in 1..10:
        let boxView = box.findNode("box_view_" & $i)
        if boxView.alpha < 1.0:
            boxView.removeFromParent()
            boxAnim.onComplete do():
                boxView.reattach(box)
                for child in particle.children:
                    let emitter = child.component(ParticleSystem)
                    emitter.stop()
                    let anim = newAnimation()
                    anim.numberOfLoops = 1
                    anim.loopDuration = 0.5
                    anim.onAnimate = proc(p: float) =
                        child.alpha = p
                    c.rootNode.sceneView().addAnimation(anim)

    let parent_sweets = box.findNode("parent_sweets")
    var node: Node
    if sweetName == "cake":
        node = newLocalizedNodeWithResource("slots/candy_slot/slot/precomps/elem_3.json")
        node.scale = newVector3(0.85, 0.85, 1.0)
        node.position = newVector3(50, 55)
    elif sweetName == "candy":
        node = newLocalizedNodeWithResource("slots/candy_slot/slot/precomps/elem_10.json")
        node.position = newVector3(0, 3)
    else:
        node = newLocalizedNodeWithResource("slots/candy_slot/slot/precomps/elem_5.json")
    parent_sweets.addChild(node)
    c.rootNode.sceneView().addAnimation(boxAnim)

    let flyParticle = newLocalizedNodeWithResource("slots/candy_slot/particles/root_bonus_trans.json")
    flyParticle.position = node.position + newVector3(280, 260)
    parent_sweets.addChild(flyParticle)
    flyParticle.alpha = 0

    boxAnim.addLoopProgressHandler 0.3, false, proc() =
        c.currentIndex.inc()
        c.enableButtons(true)
    boxAnim.addLoopProgressHandler 0.5, false, proc() =
        let win = node.animationNamed("win")

        c.rootNode.sceneView().addAnimation(win)
        flyParticle.reattach(c.rootNode)
        node.reattach(c.rootNode)
        win.addLoopProgressHandler 0.7, false, proc() =
            win.cancel()
            flyParticle.alpha = 1

            let s = flyParticle.position
            let e = c.rootNode.findNode("bonus_" & $sweetName).position + newVector3(120, 180)
            let c1 = newVector3(1150.0, 50)
            let c2 = newVector3(1450.0, 50)
            let fly = newAnimation()
            let scale = flyParticle.scale

            fly.numberOfLoops = 1
            fly.loopDuration = 1.0
            fly.onAnimate = proc(p: float) =
                let t = interpolate(0.0, 1.0, p)
                let point = calculateBezierPoint(t, s, e, c1, c2)
                let scaleX = interpolate(scale.x, 0.8, p)
                let scaleY = scaleX
                flyParticle.position = point
                flyParticle.scale = newVector3(scaleX, scaleY, 1.0)
            c.rootNode.sceneView().addAnimation(fly)

            let oldStage = c.rootNode.findNode("bonus_" & sweetName & "_" & $(c.vases[sweetName]) & ".png")
            let newStage = c.rootNode.findNode("bonus_" & sweetName & "_" & $(c.vases[sweetName] + 1) & ".png")

            let drops = newLocalizedNodeWithResource("slots/candy_slot/slot/precomps/drops_line_numbers.json")
            let dropsAnim = drops.animationNamed("play")

            drops.scale = newVector3(0.5, 0.5, 1)

            fly.addLoopProgressHandler 0.7, false, proc() =
                let p = c.rootNode.findNode("bonus_" & sweetName & "_" & $(c.vases[sweetName] + 1) & ".png")

                if not p.isNil and not drops.isNil:
                    p.addChild(drops)
                    drops.position = newVector3(-180, -30)
                    c.rootNode.sceneView().addAnimation(dropsAnim)
                    dropsAnim.onComplete do():
                        drops.removeFromParent()


            fly.addLoopProgressHandler 0.8, false, proc() =
                let vases = c.rootNode.findNode("vases")
                let tornado = vases.findNode("tornado")
                let tornadoAnim = tornado.animationNamed("play")
                let tornadoParent = vases.findNode("tornado_parent_" & sweetName)

                tornadoParent.addChild(tornado)
                tornado.position = newVector3(0, 0)
                c.rootNode.sceneView().addAnimation(tornadoAnim)

            fly.onComplete do():
                c.sm.playSFX("slots/candy_slot/candy_sound/candy_bonus_game_glass_jar_" & $rand(1 .. 3))
                if c.currentIndex >= c.field.len:
                    for p in c.particles:
                        p.removeFromParent()
                oldStage.alpha = 0
                newStage.alpha = 1
                c.vases[sweetName] = c.vases[sweetName] + 1
                node.reattach(parent_sweets)
                for child in flyParticle.children:
                    let emitter = child.component(ParticleSystem)
                    emitter.stop()

                let delAnim = newAnimation()
                delAnim.numberOfLoops = 1
                delAnim.loopDuration = 1.5
                c.rootNode.sceneView().addAnimation(delAnim)
                delAnim.onComplete do():
                    flyParticle.removeFromParent()
                c.readyCounter.inc()
                if c.currentIndex >= c.field.len and c.readyCounter >= c.field.len:
                    let anim = c.boyController.setImmediateAnimation("multiwin")

                    c.enableButtons(false)
                    c.sm.playSFX("slots/candy_slot/candy_sound/candy_bonus_game_result")
                    anim.onComplete do():
                        c.idleAnimation.cancel()
                        c.onComplete()

    if c.currentIndex >= c.field.len:
        for i in 1..BOXES_COUNT:
            if not parent.isNil:
                parent.removeFromParent()

proc startBoxIdle(c: CandyBonusGame) =
    proc startIdle() =
        let rnd = rand(0..8)
        let anim = c.idleAnims[rnd]

        proc startAnim() =
            let box = c.rootNode.findNode("box" & $(rnd+1))
            if not box.isNil and not box.childNamed("parent_box_idle").isNil and c.buttons.len != 0 and not c.buttons[rnd].isNil:
                if box.childNamed("parent_box_idle").alpha > 0 and c.buttons[rnd].enabled:
                    c.rootNode.addAnimation(anim)

        startAnimatedTimer(c.rootNode.sceneView(), rand(1.0), startAnim, 1)
    c.idleAnimation = startAnimatedTimer(c.rootNode.sceneView(), 1.0, startIdle, -1)

proc refreshView(c: CandyBonusGame) =
    for i in 1..BOXES_COUNT:
        let box = c.rootNode.findNode("box" & $(i))
        let idle_parent = box.childNamed("parent_box_idle")

        c.idleAnims.add(box.animationNamed("idle"))
        for c in idle_parent.children:
            c.alpha = 0
        idle_parent.findNode("box_view_" & $rand(1 .. 9)).alpha = 1

    for sweetName in c.sweets:
        let parent = c.rootNode.findNode("bonus_" & sweetName)
        for level in parent.children:
            if level.name == "bonus_" & sweetName & "_0.png":
                level.alpha = 1
            else:
                level.alpha = 0
    setTimeout 3.5, proc() =
        c.startBoxIdle()

proc createButtons*(c: CandyBonusGame) =
    c.buttons = @[]
    for i in 1..BOXES_COUNT:
        let box = c.rootNode.findNode("box" & $i)
        let buttonParent = box.newChild("bonus_button_parent")
        let button = newButton(newRect(0, 0, 250, 250))

        c.buttons.add(button)
        button.hasBezel = false
        buttonParent.position = newVector3(200, 200)
        buttonParent.component(UIComponent).view = button
        closureScope:
            let index = i
            button.onAction do():
                c.clickOnButton(index)

proc initCandyBonusGame*(field: seq[int8], dishesValue:seq[int], totalBet: int64, rootNode: Node, pm: PauseManager,
        sm: SoundManager, boyController: AnimationController): CandyBonusGame {.discardable.} =
    result.new()
    result.rootNode = rootNode
    result.field = field
    result.pm = pm
    result.sm = sm
    result.boyController = boyController
    result.dishesValue = dishesValue
    result.totalBet = totalBet
    result.idleAnims = @[]

    result.sweets = @["icecream", "candy", "cake"]

    result.particles = @[]
    result.vases = initTable[string, int]()
    for sweet in result.sweets:
        result.vases[sweet] = 0

    result.refreshView()
    result.createLabels()
