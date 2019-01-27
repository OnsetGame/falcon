import rod / [ viewport, node, rod_types ]
import rod / component / [ solid, ae_composition, sprite, clipping_rect_component, color_balance_hls, text_component, tint, particle_system, particle_helpers ]
import utils / [ helpers, sound_manager ]
import nimx / [ animation, types, matrixes, timer ]
import shared / [ game_scene ]
import core.slot.base_slot_machine_view

import shared / gui / [ win_panel_module, spin_button_module, slot_gui ]
import shared.window.button_component
import random, json, strutils, tables
import falconserver.slot.machine_ufo_types

type
    SpinState {.pure.} = enum
        READY_FOR_NEXT,
        IN_PROGRESS

    FillOrder* = tuple [
       index: int,
       pipes: seq[int],
       info: seq[int]
    ]

    UfoBonusGame* = ref object of RootObj
        bonusRoot*: Node
        mainRoot: Node
        linesRoot: Node
        onGameEnd: proc()
        active: bool
        nextSpinNumber: int
        loppedAnims: seq[Animation]
        connectorsAnim: seq[Animation]
        sceneView: BaseMachineView
        pipesPlaceholders: seq[Node]
        spinState: SpinState
        fields: seq[seq[int]]
        fillOrders: seq[seq[FillOrder]]
        payouts: seq[int64]
        double: seq[bool]
        currentPipesState: seq[int]
        onCompleteHandler: proc()
        bonusIntro: Node
        parentMilkFlask: Node
        milkSplash: Node
        roundWin: Node
        currentWin: int64
        totalSpins: int

const
    BONUS_RES_PATH = "slots/ufo_slot/bonus/bonus_scene"
    TOTAL_PIPES = 9
    TOTAL_PIPE_TYPES = 7
    WIN_PANEL_OFFSET = newVector3(-230, 0)
    MILK_FILL_SIZE = 300

proc spinsLeft(ubg: UfoBonusGame): int =
    result = ubg.totalSpins + 1 - ubg.nextSpinNumber

proc startBackgroundAnimations*(ubg: UfoBonusGame) =
    assert(ubg.loppedAnims.len == 0)
    ubg.connectorsAnim = @[]

    let bgUpperAnim = ubg.bonusRoot.findNode("bg_upper_part").animationNamed("play")
    bgUpperAnim.numberOfLoops = -1
    ubg.loppedAnims.add(bgUpperAnim)

    let blueGlowAnim = ubg.bonusRoot.findNode("blue_glow").animationNamed("play")
    blueGlowAnim.numberOfLoops = -1
    ubg.loppedAnims.add(blueGlowAnim)

    let bgBottomAnim = ubg.bonusRoot.findNode("bg_down_part").component(AEComposition).compositionNamed("play")
    bgBottomAnim.numberOfLoops = -1
    ubg.loppedAnims.add(bgBottomAnim)

    let flaskAnim = ubg.bonusRoot.findNode("flask_with_milk").component(AEComposition).compositionNamed("idle")
    flaskAnim.numberOfLoops = -1
    ubg.loppedAnims.add(flaskAnim)

    let frontIdleAnim = ubg.bonusRoot.findNode("bg_up").animationNamed("play")
    frontIdleAnim.numberOfLoops = -1
    ubg.loppedAnims.add(frontIdleAnim)

    ubg.bonusIntro = ubg.bonusRoot.findNode("bonus_intro")

    let bonusIntroAnim = ubg.bonusIntro.animationNamed("idle")
    bonusIntroAnim.numberOfLoops = -1
    ubg.bonusRoot.addAnimation(bonusIntroAnim)

    for anim in ubg.loppedAnims:
        ubg.sceneView.addAnimation(anim)

proc getRedEffect(): ColorBalanceHLS =
    result = ColorBalanceHLS.new()
    result.init()
    result.hue = 0.538
    result.saturation = 0
    result.lightness = 0
    result.init()

proc flyDrone(ubg: UfoBonusGame, index: int) =
    let anim = ubg.bonusRoot.findNode("dron" & $index).animationNamed("play")
    let rand = rand(8..15)

    ubg.bonusRoot.addAnimation(anim)
    ubg.sceneView.setTimeout rand.float, proc() =
        if ubg.active:
            ubg.flyDrone(index)

proc setGreenWin(ubg: UfoBonusGame, enable: bool) =
    let anim = newAnimation()
    let cs = ubg.bonusRoot.findNode("color_screen")
    let cg = ubg.bonusRoot.findNode("color_green")
    let cbg = ubg.bonusRoot.findNode("flask_with_milk").findNode("color_balance_green")
    let greenWin = ubg.bonusRoot.findNode("green_win")
    let greenWinAnim = greenWin.animationNamed("play")
    let emptyHLSEffect = ColorBalanceHLS.new()
    let emptyTintEffect = Tint.new()
    let greenHLSEffect = ColorBalanceHLS.new()
    let greenTintEffect = Tint.new()

    anim.numberOfLoops = 1
    anim.loopDuration = 0.5

    greenHLSEffect.init()
    emptyHLSEffect.init()
    greenHLSEffect.hue = -0.325
    greenHLSEffect.saturation = 0.0

    greenTintEffect.white = newColor(0.15294118225574, 0.79607844352722, 0.5137255191803, 1.0)
    greenTintEffect.black = newColor(0.15294118225574, 0.79607844352722, 0.5137255191803, 1.0)
    greenTintEffect.amount = 1.0

    if enable:
        ubg.bonusRoot.addAnimation(greenWinAnim)
        greenWin.alpha = 1.0
        greenWinAnim.onComplete do():
            greenWin.alpha = 0

        cs.setComponent("ColorBalanceHLS", emptyHLSEffect)
        cbg.setComponent("ColorBalanceHLS", emptyHLSEffect)
        cg.setComponent("Tint", emptyTintEffect)

        anim.onAnimate = proc(p: float)=
            cs.getComponent(ColorBalanceHLS).hue = interpolate(emptyHLSEffect.hue, greenHLSEffect.hue, p)
            cbg.getComponent(ColorBalanceHLS).hue = interpolate(emptyHLSEffect.hue, greenHLSEffect.hue, p)
            cg.getComponent(Tint).white = interpolate(emptyTintEffect.white, greenTintEffect.white, p)
            cg.getComponent(Tint).black = interpolate(emptyTintEffect.black, greenTintEffect.black, p)
            cg.getComponent(Tint).amount = interpolate(emptyTintEffect.amount, greenTintEffect.amount, p)
    else:
        anim.onAnimate = proc(p: float)=
            cs.getComponent(ColorBalanceHLS).hue = interpolate(greenHLSEffect.hue, emptyHLSEffect.hue, p)
            cbg.getComponent(ColorBalanceHLS).hue = interpolate(greenHLSEffect.hue, emptyHLSEffect.hue, p)
            cg.getComponent(Tint).white = interpolate(greenTintEffect.white, emptyTintEffect.white, p)
            cg.getComponent(Tint).black = interpolate(greenTintEffect.black, emptyTintEffect.black, p)
            cg.getComponent(Tint).amount = interpolate(greenTintEffect.amount, emptyTintEffect.amount, p)

        anim.onComplete do():
            cs.removeComponent(ColorBalanceHLS)
            cbg.removeComponent(ColorBalanceHLS)
            cg.removeComponent(Tint)
    ubg.bonusRoot.addAnimation(anim)

proc lightRightButtons(ubg: UfoBonusGame, on: bool) =
    let but = ubg.bonusRoot.findNode("parent_x").findNode("ltp_but_right.png")

    but.removeComponent(ColorBalanceHLS)
    if not on:
        but.setComponent("ColorBalanceHLS", getRedEffect())

proc lightLeftButton(ubg: UfoBonusGame, on: bool) =
    let light = ubg.bonusRoot.findNode("parent_x").findNode("ltp_but_lef.png")

    light.removeComponent(ColorBalanceHLS)
    if not on:
        light.setComponent("ColorBalanceHLS", getRedEffect())

proc stopBackgroundAnimations*(ubg: UfoBonusGame) =
    for anim in ubg.loppedAnims:
        anim.cancel()
    ubg.loppedAnims = @[]

proc stopConnectorAnimations(ubg: UfoBonusGame) =
    for anim in ubg.connectorsAnim:
        anim.cancel()
    ubg.connectorsAnim = @[]

proc initBonusScene(ubg: UfoBonusGame) =
    block enableNullParents:
        ubg.linesRoot = ubg.bonusRoot.findNode("lines")
        ubg.pipesPlaceholders = newSeq[Node]()
        for lineNode in ubg.linesRoot.children:
            lineNode.alpha = 1.0

        for i in 0..TOTAL_PIPES-1:
            let pipesNode = ubg.linesRoot.findNode("pipes_" & $i)
            ubg.pipesPlaceholders.add(pipesNode)

proc newBonusGame*(mainSceneNode: Node, sceneView: BaseMachineView): UfoBonusGame =
    result.new()
    result.mainRoot = mainSceneNode
    result.sceneView = sceneView
    let bonusGameParentNode = newLocalizedNodeWithResource(BONUS_RES_PATH)

    bonusGameParentNode.enabled = false
    mainSceneNode.addChild(bonusGameParentNode)
    result.bonusRoot = bonusGameParentNode
    result.initBonusScene()

proc pipesMoveAnimation(ubg: UfoBonusGame, name:string) : Animation =
    var exceptions = newSeq[string]()
    for i in 0..TOTAL_PIPES-1:
        exceptions.add("pipes_"& $i)
    result = ubg.linesRoot.component(AEComposition).compositionNamed(name, exceptions)

proc playSpinInSound(ubg: UfoBonusGame) =
    let randSpinSoundIndex = rand(1..3)
    ubg.sceneView.soundManager.sendEvent("BONUS_SPIN_" & $randSpinSoundIndex)

proc playSpinOutSound(ubg: UfoBonusGame) =
    let randSpinSoundIndex = rand(1..3)
    ubg.sceneView.soundManager.sendEvent("BONUS_SPIN_END_" & $randSpinSoundIndex)


proc playFillMilkSound(ubg: UfoBonusGame) =
    let randSpinSoundIndex = rand(1..3)
    ubg.sceneView.soundManager.sendEvent("BOUNUS_FILL_MILK_" & $randSpinSoundIndex)

proc playIntroAnimations(ubg: UfoBonusGame) =
    let cowPortalIntroAnim = ubg.bonusRoot.findNode("cow_bg").component(AEComposition).compositionNamed("play")
    cowPortalIntroAnim.numberOfLoops = 1
    let cowPortalIdleAnim = ubg.bonusRoot.findNode("cow_bg").component(AEComposition).compositionNamed("idle")
    cowPortalIdleAnim.numberOfLoops = -1
    cowPortalIntroAnim.onComplete do():
        if ubg.loppedAnims.len != 0: # XXX: Strange...
            ubg.loppedAnims.add(cowPortalIdleAnim)
            ubg.sceneView.addAnimation(cowPortalIdleAnim)

    let firstMoveIn = ubg.pipesMoveAnimation("moveIn")
    ubg.spinState = SpinState.IN_PROGRESS
    firstMoveIn.onComplete do():
        ubg.spinState = SpinState.READY_FOR_NEXT

    ubg.sceneView.addAnimation(cowPortalIntroAnim)
    ubg.playSpinInSound()
    ubg.sceneView.addAnimation(firstMoveIn)

proc clearPipes(ubg: UfoBonusGame) =
    for pipePlaceholder in ubg.pipesPlaceholders:
        for i,node in pipePlaceholder.children:
            node.alpha = 0.0
            if i < TOTAL_PIPE_TYPES:
                node.component(AEComposition).compositionNamed("fill").onAnimate(0.0)

proc setPipesState(ubg: UfoBonusGame, states:seq[int]) =
    assert(states.len == TOTAL_PIPES)
    for i,state in states:
        ubg.pipesPlaceholders[i].children[state].alpha = 1.0
    ubg.currentPipesState = states

proc setResponseData*(ubg: UfoBonusGame, roundsPayout: seq[int64], fields: seq[seq[int]], fillOrders: seq[seq[FillOrder]], double: seq[bool]) =
    ubg.fields = fields
    ubg.payouts = roundsPayout
    ubg.fillOrders = fillOrders
    ubg.double = double

proc shiftWinPanel(ubg: UfoBonusGame, back: bool) =
    let sg = ubg.sceneView.slotGUI
    let pos =sg.winPanelModule.rootNode.position
    if back:
        sg.winPanelModule.rootNode.position = pos - WIN_PANEL_OFFSET
    else:
        sg.winPanelModule.rootNode.position = pos + WIN_PANEL_OFFSET

proc restoreInitialFlaskState(ubg: UfoBonusGame) =
    let r = ubg.parentMilkFlask.getComponent(ClippingRectComponent).clippingRect
    let milkOffset = MILK_FILL_SIZE / ubg.totalSpins.Coord

    ubg.milkSplash.positionY = ubg.milkSplash.positionY + milkOffset
    ubg.parentMilkFlask.getComponent(ClippingRectComponent).clippingRect = newRect(1800, r.y + milkOffset, 600, 500)

proc showWinForRound(ubg: UfoBonusGame) =
    if ubg.payouts.len != 0:
        let rWin = ubg.payouts[ubg.nextSpinNumber - 1]

        ubg.currentWin += rWin
        ubg.sceneView.slotGUI.winPanelModule.setNewWin(ubg.currentWin, true)

proc onSpinEnd(ubg: UfoBonusGame) =
    if ubg.nextSpinNumber < ubg.totalSpins:
        ubg.nextSpinNumber.inc()
        ubg.spinState = SpinState.READY_FOR_NEXT
    else:
        ubg.sceneView.GameScene.setTimeout(2.0) do():
            ubg.sceneView.BaseMachineView.onBonusGameEnd()
            ubg.onCompleteHandler()
            ubg.currentWin = 0
            ubg.sceneView.prepareGUItoBonus(false)
            ubg.shiftWinPanel(true)

proc winMilk(ubg: UfoBonusGame) =
    let double = ubg.double[ubg.nextSpinNumber - 1]

    ubg.lightRightButtons(double)
    ubg.sceneView.soundManager.sendEvent("BONUS_WIN_ROUND")
    ubg.sceneView.addAnimation(ubg.roundWin.animationNamed("start"))
    ubg.showWinForRound()

    proc complete() =
        ubg.lightLeftButton(false)
        ubg.lightRightButtons(false)
        ubg.onSpinEnd()

    for i in 1..2:
        let node = ubg.bonusRoot.findNode("numbers_" & $i)
        let payout = ubg.payouts[ubg.nextSpinNumber - 1]

        for j in 1..5:
            node.findNode("count_" & $j).getComponent(Text).text = $payout


    if double:
        let anim = newAnimation()
        let r = ubg.parentMilkFlask.getComponent(ClippingRectComponent).clippingRect
        let winAnim = ubg.bonusRoot.findNode("flask_with_milk").component(AEComposition).compositionNamed("win")
        let splashStartPosY = ubg.milkSplash.positionY
        let milkOffset = MILK_FILL_SIZE / ubg.totalSpins
        let splashEndPosY = ubg.milkSplash.positionY - milkOffset

        ubg.sceneView.addAnimation(winAnim)
        winAnim.addLoopProgressHandler 0.3, false, proc() =
            anim.numberOfLoops = 1
            anim.loopDuration = 1.0
            anim.onAnimate = proc(p: float)=
                let scissorY = (interpolate(r.y, r.y - milkOffset, p)).Coord

                ubg.parentMilkFlask.getComponent(ClippingRectComponent).clippingRect = newRect(1800, scissorY, 600, 500)
                ubg.milkSplash.positionY = interpolate(splashStartPosY, splashEndPosY, p)
            ubg.bonusRoot.addAnimation(anim)
        ubg.setGreenWin(true)
        winAnim.onComplete do():
            complete()
            ubg.setGreenWin(false)
    else:
        let notwin = ubg.bonusRoot.findNode("notwin_glow")
        let notwinAnim = notwin.animationNamed("play")

        ubg.bonusRoot.addAnimation(notwinAnim)
        notwin.alpha = 1.0
        notwinAnim.onComplete do():
            notwin.alpha = 0
        complete()

proc prepareGame*(ubg: UfoBonusGame, totalSpins: int) =
    let sg = ubg.sceneView.slotGUI
    var btn = ubg.bonusRoot.findNode("black_solid").createButtonComponent(newRect(0.0, 0.0, VIEWPORT_SIZE.width, VIEWPORT_SIZE.height))

    ubg.sceneView.BaseMachineView.onBonusGameStart()
    ubg.parentMilkFlask = ubg.bonusRoot.findNode("parent_milk")
    ubg.nextSpinNumber = 1
    ubg.totalSpins = totalSpins
    ubg.bonusRoot.enabled = true
    ubg.bonusRoot.findNode("cow_bg").component(AEComposition).compositionNamed("play").onProgress(0.0)
    ubg.sceneView.prepareGUItoBonus(true)

    ubg.parentMilkFlask.component(ClippingRectComponent).clippingRect = newRect(1800, 700, 600, 500)
    ubg.bonusRoot.findNode("milk_splash_parent").component(ClippingRectComponent).clippingRect = newRect(600, 420, 1500, 500)
    ubg.bonusRoot.findNode("energy_ball_parent").component(ClippingRectComponent).clippingRect = newRect(1900, 470, 150, 100)
    ubg.milkSplash = ubg.bonusRoot.findNode("milk_splash")
    ubg.roundWin = ubg.bonusRoot.findNode("ufo_count")
    btn.onAction do():
        ubg.bonusIntro.animationNamed("idle").cancel()
        ubg.bonusRoot.addAnimation(ubg.bonusIntro.animationNamed("play"))
        ubg.shiftWinPanel(false)
        sg.spinButtonModule.setVisible(true)
        sg.winPanelModule.setVisible(true)
        sg.winPanelModule.setNewWin(0)
        btn.enabled = false
        ubg.playIntroAnimations()
    ubg.clearPipes()
    ubg.pipesMoveAnimation("moveIn").onAnimate(0.0)

    sg.spinButtonModule.startFreespins(ubg.spinsLeft)
    ubg.lightRightButtons(false)
    ubg.lightLeftButton(false)
    ubg.startBackgroundAnimations()

    let smoke = newLocalizedNodeWithResource("slots/ufo_slot/bonus/particles/smoke")
    let smallSmoke = newLocalizedNodeWithResource("slots/ufo_slot/bonus/particles/smoke")
    let emitter = smallSmoke.component(ParticleSystem)
    let boxPSGenShape = smallSmoke.component(BoxPSGenShape)
    let screen = newLocalizedNodeWithResource("slots/ufo_slot/bonus/particles/screen")

    ubg.bonusRoot.addChild(screen)
    ubg.bonusRoot.addChild(smoke)
    ubg.bonusRoot.addChild(smallSmoke)
    smoke.position = newVector3(1293, 1174)
    boxPSGenShape.dimension.x = 50.0
    smallSmoke.position = newVector3(710, 385)
    emitter.birthRate = 3.0
    screen.position = newVector3(1293, 0)
    ubg.flyDrone(1)
    ubg.flyDrone(2)

    echo "Game prepared"

proc isActive*(ubg: UfoBonusGame): bool =
    ubg.active

proc endGame*(ubg: UfoBonusGame) =
    if ubg.isActive:
        echo "Game ends"
        ubg.stopBackgroundAnimations()
        ubg.stopConnectorAnimations()
        ubg.bonusRoot.enabled = false
        ubg.active = false
        ubg.restoreInitialFlaskState()

proc getOppositeConnector(connector: int): int =
    case connector:
    of 0:
        result = 2
    of 1:
        result = 3
    of 2:
        result = 0
    of 3:
        result = 1
    else:
        discard

proc addConnectorAnim(ubg: UfoBonusGame, connector: Node) =
    let play = connector.animationNamed("play")

    connector.enabled = true
    connector.alpha = 1
    play.numberOfLoops = -1
    ubg.bonusRoot.addAnimation(play)
    ubg.connectorsAnim.add(play)

proc fillMilkAnimation(ubg: UfoBonusGame) =
    let currPipes = ubg.fillOrders[ubg.nextSpinNumber - 1]
    const DELAY = 0.55
    let goAnim = ubg.bonusRoot.findNode("cow_bg").component(AEComposition).compositionNamed("milk_go")
    ubg.bonusRoot.addAnimation(goAnim)

    var allIndexes: seq[int] = @[]
    for p in currPipes:
        for pp in p.pipes:
            allIndexes.add(pp)

    # {"field":[2,4,5,0,5,2,5,6,1],"fo":[[[3,0]],[[4,0]]],"w":10000,"d":false}

    ubg.lightLeftButton(true)
    for i in 0..<currPipes.len:
        closureScope:
            let index = i
            let currOrder = currPipes[index]
            ubg.sceneView.GameScene.setTimeout(DELAY  * index.float) do():
                for j in 0..<currOrder.pipes.len:
                    let pipeIndex = currOrder.pipes[j]
                    let pipeInfo = currOrder.info[j].MilkFillDirection
                    let pipe = ubg.bonusRoot.findNode("pipes_" & $pipeIndex)
                    let neighbours = getNeighborPipesIndexes(pipeIndex.int8)
                    var anim: Animation
                    var greenIndexes: seq[int] = @[]
                    let pipeType = ubg.fields[ubg.nextSpinNumber-1][pipeIndex].Pipes

                    for i in 0..<neighbours.len:
                        if index > 0:
                            if currPipes[index - 1].pipes.contains(neighbours[i]):
                                greenIndexes.add(i)

                                if neighbours[i] >= 0 and couldPipeProvideMilk(pipeType, i.PipeDirection):
                                    let connector = ubg.bonusRoot.findNode("pipes_" & $neighbours[i]).findNode("green_" & $getOppositeConnector(i))
                                    ubg.addConnectorAnim(connector)

                    for c in pipe.children:
                        if c.name.contains("pipe") and c.alpha > 0:
                            let connectors = pipesConnectors[parseEnum[Pipes](c.name)]

                            for i in 0..3:
                                if connectors[i] and (greenIndexes.contains(i) or pipeIndex == 5 ):
                                    ubg.addConnectorAnim(pipe.findNode("green_" & $i))

                            let milkDirect= c.findNode("milk_1")
                            let milkReverse = c.findNode("milk_2")

                            milkDirect.alpha = 1
                            if not milkReverse.isNil:
                                milkReverse.alpha = 1
                            if pipeInfo == direct:
                                if not milkReverse.isNil:
                                    milkReverse.alpha = 0
                            elif pipeInfo == indirect:
                                milkDirect.alpha = 0
                            anim = c.component(AEComposition).compositionNamed("fill")

                    if index == currPipes.len - 1 and j == currOrder.pipes.len - 1:
                        anim.onComplete do():
                            ubg.winMilk()
                    ubg.sceneView.addAnimation(anim)

proc startSpinAnimation(ubg: UfoBonusGame, pipesState:seq[int]) =
    ubg.spinState = SpinState.IN_PROGRESS
    let moveOut = ubg.pipesMoveAnimation("moveOut")
    let moveIn = ubg.pipesMoveAnimation("moveIn")

    ubg.sceneView.soundManager.sendEvent("PIPES_DOWN")
    moveIn.onComplete do():
        ubg.fillMilkAnimation()
        ubg.playFillMilkSound()

    moveOut.onComplete do():
        ubg.clearPipes()
        ubg.setPipesState(pipesState)
        ubg.sceneView.addAnimation(moveIn)
        ubg.playSpinInSound()

    ubg.sceneView.addAnimation(moveOut)
    ubg.playSpinOutSound()

proc setOnCompleteHandler*(ubg: UfoBonusGame, handler: proc()) =
    ubg.onCompleteHandler = handler

proc onSpinPress*(ubg: UfoBonusGame) =
    echo "Bonus spin ", ubg.nextSpinNumber
    if ubg.spinState == SpinState.READY_FOR_NEXT:
        var states:seq[int] = ubg.fields[ubg.nextSpinNumber-1]
        ubg.startSpinAnimation(states)
        ubg.sceneView.BaseMachineView.rotateSpinButton(ubg.sceneView.slotGUI.spinButtonModule)

        if ubg.nextSpinNumber < ubg.totalSpins:
            ubg.sceneView.slotGUI.spinButtonModule.setFreespinsCount(ubg.spinsLeft - 1)
        else:
            ubg.sceneView.slotGUI.spinButtonModule.stopFreespins()

    else:
        echo "Spin in progress"

proc setFirstPipesState(ubg: UfoBonusGame): seq[int] =
    result = @[]

    for i in 0..<TOTAL_PIPES:
        result.add(rand(0..6))
    result[3] = 0

proc startGame*(ubg: UfoBonusGame) =
    echo "Game started"

    let initPipesState = ubg.setFirstPipesState()
    ubg.setPipesState(initPipesState)

    ubg.active = true
