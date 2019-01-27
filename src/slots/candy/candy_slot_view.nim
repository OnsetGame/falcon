import
    nimx.view, nimx.context, nimx.button, nimx.animation, nimx.window,
    nimx.timer, nimx.view_event_handling, nimx.notification_center,
    #
    rod.rod_types, rod.node, rod.viewport, rod.component, rod.component.channel_levels, rod.component.particle_system,
    rod.asset_bundle,
    #
    falconserver.slot.machine_candy_types,
    #
    shafa.slot.slot_data_types,
    #
    tables, random, json, strutils, sequtils, algorithm, logging, variant,
    #
    core.net.server, shared.user, core.slot.base_slot_machine_view,
    shared.chips_animation,
    #
    utils.sound, utils.sound_manager, utils.helpers, utils.pause, utils.falcon_analytics_utils,
    utils.animation_controller, utils.fade_animation, utils.falcon_analytics, utils.falcon_analytics_helpers, utils.game_state,
    #
    candy_bonus_game_view, candy_spin_anim, candy_freespin_intro, candy_line_numbers, candy_win_popup, candy_aux_animations,
    candy_win_line, candy_five_in_a_row,
    #
    shared.gui.gui_module, shared.gui.gui_pack, shared.gui.gui_module_types, shared.gui.win_panel_module,
    shared.gui.total_bet_panel_module, shared.gui.paytable_open_button_module, shared.gui.spin_button_module,
    shared.gui.money_panel_module, shared.gui.candy_bonus_rules_module, shared.gui.autospins_switcher_module,
    shared.gui.slot_gui, quest.quests, shared.window.button_component, shared.window.window_manager

import core / flow / flow_state_types

const GENERAL_PREFIX = "slots/candy_slot/"
const SOUND_PATH_PREFIX = GENERAL_PREFIX & "candy_sound/"
const CARRIAGES = 5
const SCATTER = 1'i8
const BONUS = 2'i8
const SECONDARY_WILD = 11'i8

type Symbols {.pure.} = enum
    Wild,
    Scatter,
    Bonus,
    Cake1,
    Cake2,
    Cake3,
    Cake4,
    Candy1,
    Candy2,
    Candy3,
    Candy4

type MusicType {.pure.} = enum
    Main,
    Bonus,
    Freespins

type TrainStatus {.pure.} = enum
    Empty,
    Start,
    Back,
    End

type CandyPaytableServerData* = tuple
    paytableSeq: seq[seq[int]]
    freespinsAllCount: int

type CandySlotView* = ref object of BaseMachineView
    shakeRoot: Node
    sharedLayer: Node
    mainLayer: Node
    bonusLayer: Node
    backLayer: Node
    topLayer: Node
    trainStartParent: Node
    trainStart: Node
    trainBack: Node
    trainEnd: Node
    lineParent: Node
    numbersParent: Node
    specialWinParent: Node
    bonusField: seq[int8]
    dishesValue:seq[int]
    wildIndexes:seq[int]
    startField: seq[int8]
    bonusGame: CandyBonusGame
    totalFreeSpinsWinning: int64
    scatters: int
    freeSpinsCount: int
    betForSpin: int64
    symbolAnimations:seq[CandySymbolAnimation]
    stopTimers: array[0..NUMBER_OF_REELS-1, ControlledTimer]
    endAnimFinished: array[0..NUMBER_OF_REELS-1, bool]
    gotSpinResponse: bool
    animReadyForStop: bool
    lineAnims:seq[Animation]
    lineTimers: seq[ControlledTimer]
    bonusPayout: int64
    lollipopAnim: Animation
    airplaneAnim: Animation
    lightsAnim: Animation
    mainForHide: seq[string]
    bonusForHide: seq[string]
    boyAnticipating: bool
    boy: Node
    boyController: AnimationController
    startBoyPosX: float
    boxesUp: Node
    boxesDown: Node
    moveBoxesUpAnim: Animation
    moveBoxesDownAnim: Animation
    wildParticles: seq[Node]
    lights: Node
    fadeFreespin: FadeAnimation
    freespinLightsAnim: Animation
    highlights: seq[Node]
    winningAnims: seq[Animation]
    spinSound, riser: Sound
    trainStatus: TrainStatus
    prevTrainStatus: TrainStatus
    endTrainComing: bool
    anticipationParticles: seq[Node]
    inBonusNow: bool
    betFromMode: int
    guiPopupVisible: bool
    linesStopped: bool
    closeBigwin: Button
    repeatNumbersAnim: Animation
    pd*: CandyPaytableServerData

proc startSpin(v: CandySlotView)
proc playScatterAnim(v: CandySlotView)

proc onLevelUp(v: CandySlotView) =
    discard
    # let event = sharedGameEventsQueue().getEvent(GameEventType.LevelUpEv)
    # if not event.isNil and v.slotGUI.gameEventsProcessing == false:
    #     let lvl = event.data.get(int)
    #     let cb = proc () =
    #         v.guiPopupVisible = false
    #         sharedGameEventsQueue().delete(event)

    #         if v.stage == GameStage.Spin:
    #             v.setSpinButtonState(SpinButtonState.Spin)
    #         v.slotGUI.processGameEvents()
    #     v.guiPopupVisible = true
    #     v.setSpinButtonState(SpinButtonState.Blocked)
    #     v.slotGUI.showLevelUpPopup(lvl, cb)

method setSpinButtonState*(v: CandySlotView,  state: SpinButtonState) =
    if not v.guiPopupVisible:
        if state == SpinButtonState.Spin:
            v.slotGUI.spinButtonModule.button.enabled = true
        procCall v.BaseMachineView.setSpinButtonState(state)

proc playBackgroundMusic(v: CandySlotView, m: MusicType) =
    var music: FadingSound
    case m
    of MusicType.Main:
        v.soundManager.sendEvent("GAME_BACKGROUND_MUSIC")
    of MusicType.Freespins:
        v.soundManager.sendEvent("FREE_SPINS_MUSIC")
    of MusicType.Bonus:
        v.soundManager.sendEvent("BONUS_GAME_MUSIC")

proc startFreespinLight(v: CandySlotView) =
    let freespinLights = v.rootNode.findNode("lights_freespin")

    v.fadeFreespin = addFadeSolidAnim(v, v.rootNode.findNode("freespin_fade_parent"), blackColor(), VIEWPORT_SIZE, 0.0, 0.15, 1.0)
    v.freespinLightsAnim = freespinLights.animationNamed("play")

    freespinLights.alpha = 1
    v.freespinLightsAnim.numberOfLoops = -1
    v.addAnimation(v.freespinLightsAnim)

proc stopFreespinLight(v: CandySlotView) =
    let freespinLights = v.rootNode.findNode("lights_freespin")

    if not v.fadeFreespin.isNil:
        v.fadeFreespin.changeFadeAnimMode(0, 1.0)
        v.fadeFreespin.animation.onComplete do():
            v.fadeFreespin.removeFromParent()
    freespinLights.alpha = 0
    v.freespinLightsAnim.cancel()

proc showGUIButtons(v: CandySlotView, enable: bool) =
    v.slotGUI.totalBetPanelModule.setVisible(enable)
    v.slotGUI.totalBetPanelModule.setVisible(enable)
    v.slotGUI.spinButtonModule.setVisible(enable)

proc hideLayers(v: CandySlotView, isMain: bool) =
    for layerName in v.mainForHide:
        v.rootNode.findNode(layerName).alpha = (not isMain).float
    for layerName in v.bonusForHide:
        v.rootNode.findNode(layerName).alpha = isMain.float

proc showLayers(v: CandySlotView) =
    for layerName in v.mainForHide:
        v.rootNode.findNode(layerName).alpha = 1
    for layerName in v.bonusForHide:
        v.rootNode.findNode(layerName).alpha = 1

proc getPlaceholder(v:CandySlotView, index: int): Node =
    let place = indexToPlace(index)
    result = v.rootNode.findNode("placeholder_" & $(place.x) & "_" & $(place.y))

proc getScatterOnField(v: CandySlotView): Node =
    let indexes = reelToIndexes(NUMBER_OF_REELS - 1)
    for i in indexes:
        if v.lastField[i] == SCATTER:
            let placeholder = v.getPlaceholder(i)
            let startSymbol = placeholder.findNode("start_symbol")

            if not startSymbol.isNil:
                result = placeholder.findNode("start_symbol").findNode("elem_1")
                return

method getStateForStopAnim*(v:CandySlotView): WinConditionState =
    const MINIMUM_BONUSES = 2
    const MINIMAL_LINE = 2

    result = WinConditionState.NoWin
    if v.getLastWinLineReel() >= MINIMAL_LINE:
        result = WinConditionState.Line
    if v.countSymbols(Symbols.Bonus.int) >= MINIMUM_BONUSES:
        result = WinConditionState.Bonus

proc addSymbolToPlaceholder(v: CandySlotView, placeholderIndex: int, symbol: Symbols) =
    let placeholder = v.getPlaceholder(placeholderIndex)
    let s = v.createCandyInitialSymbol(placeholder, symbol.int)

    v.symbolAnimations.add(s)
    placeholder.removeAllChildren()
    placeholder.addChild(s.root)

proc firstFill(v: CandySlotView) =
    v.startField = @[]
    for i in 0..<ELEMENTS_COUNT:
        let rand = rand(Symbols.Cake1.int .. high(Symbols).int)
        v.addSymbolToPlaceholder(i, rand.Symbols)
        v.startField.add(rand.int8)

proc setTestAlpha(v: CandySlotView, alpha: float) =
    for i in 0..<NUMBER_OF_REELS * NUMBER_OF_ROWS:
        let placeholder = v.getPlaceholder(i)
        placeholder.alpha = alpha

proc revealScattersFly*(v: CandySlotView, show: bool) =
    let parent = v.getScatterOnField()
    if not parent.isNil:
        for c in parent.children:
                c.alpha = show.float

proc startReelAnim(v: CandySlotView, reelIndex: int) =
    let reelIndexes = reelToIndexes(reelIndex)

    if reelIndex == NUMBER_OF_REELS - 1:
        v.setTimeout 1.5, proc() =
            if v.lastField.len > 0:
                v.revealScattersFly(true)
        v.setTimeout 0.6, proc() =
            v.animReadyForStop = true
    for index in reelIndexes:
        let sym = v.startField[index]
        v.startSpinAnim(v.symbolAnimations[index], sym)

proc addAnticipateOnReel(v: CandySlotView, reelIndex: int) =
    var startParticleIndex = 0

    if reelIndex == 4:
        startParticleIndex = 3
    if v.riser.isNil:
        v.riser = v.soundManager.playSFX(SOUND_PATH_PREFIX & "candy_anticipation_sound")
        v.riser.trySetLooping(true)

    for i in startParticleIndex..startParticleIndex + 2:
        let particle = v.anticipationParticles[i]
        for child in particle.children:
            child.component(ParticleSystem).start()

proc removeAnticipationOnReel(v: CandySlotView, reelIndex: int) =
    if reelIndex > 2:
        var startParticleIndex = 0

        if reelIndex == 4:
            startParticleIndex = 3
        for i in startParticleIndex..startParticleIndex + 2:
            let particle = v.anticipationParticles[i]
            for child in particle.children:
                child.component(ParticleSystem).stop()

proc stopReelAnim(v: CandySlotView, reelIndex: int) =
    let reelIndexes = reelToIndexes(reelIndex)
    let nextIndex = reelIndex + 1

    v.soundManager.sendEvent("SPIN_END_" & $rand(1 .. 3))
    v.removeAnticipationOnReel(reelIndex)
    v.endAnimFinished[reelIndex] = true
    if nextIndex < NUMBER_OF_REELS and v.animSettings[nextIndex].boosted:
        if not v.boyAnticipating:
            let anim = v.boyController.setImmediateAnimation("anticipation")
            anim.addLoopProgressHandler 0.2, false, proc() =
                v.soundManager.sendEvent("BOY_CLAPS")
            v.boyAnticipating = true
        v.addAnticipateOnReel(nextIndex)
    else:
        v.setTimeout 0.2, proc() =
            if not v.riser.isNil:
                v.riser.stop()
                v.riser = nil
                v.soundManager.sendEvent("ANTICIPATION_SOUND_ENDS")
    for i in 0..<reelIndexes.len:
        closureScope:
            let index = i
            v.setTimeout 0.1 * index.float(), proc() =
                v.endSpinAnim(v.symbolAnimations[reelIndexes[index]], v.lastField[reelIndexes[index]], v.scatters)

            v.setTimeout 0.4, proc() =
                if v.lastField[reelIndexes[index]] == BONUS:
                    v.soundManager.sendEvent("BONUS_STOP")
                elif v.lastField[reelIndexes[index]] == SCATTER:
                    v.soundManager.sendEvent("SCATTER_APPEAR")

proc updateFlyingScatters(v: CandySlotView) =
    let indexes = reelToIndexes(NUMBER_OF_REELS - 1)
    for index in indexes:
        let placeholder = v.getPlaceholder(index)
        let scatter = placeholder.findNode("start_symbol").findNode("elem_1")
        scatter.removeAllChildren()
        for i in 1..CARRIAGES:
            let newFly = newLocalizedNodeWithResource("slots/candy_slot/slot/precomps/scatter_fly.json")
            scatter.addChild(newFly)
            newFly.name = "scatter_fly_" & $i

    for i in 1..CARRIAGES:
        let parent = v.rootNode.findNode("parent_scatter_" & $i)
        let node = parent.childNamed("scatter_fly_" & $i)
        if not node.isNil:
            node.removeFromParent()

proc prepareTrains(v: CandySlotView): Animation {.discardable.} =
    result = v.trainStart.animationNamed("prepare")
    v.addAnimation(result)
    result.onComplete do():
        v.trainStart.alpha = 1
        v.trainEnd.alpha = 0

proc startTrainCycle(v: CandySlotView) =
    if v.trainStatus == TrainStatus.Back:
        v.prevTrainStatus = TrainStatus.Start
        v.trainStatus = TrainStatus.End
        let anim = backTrain(v.rootNode, v.soundManager)
        if not anim.isNil:
            anim.onComplete do():
                v.startTrainCycle()
    elif v.trainStatus == TrainStatus.End:
        v.endTrainComing = true
        let anim = endTrain(v.rootNode)
        v.prevTrainStatus = TrainStatus.Back
        v.trainStatus = TrainStatus.Start
        if not anim.isNil:
            anim.onComplete do():
                let prepare = v.prepareTrains()
                prepare.onComplete do():
                    v.startTrainCycle()
                for i in 1..CARRIAGES:
                    addCarriage(v.rootNode, i, false)
    elif v.trainStatus == TrainStatus.Start:
        v.endTrainComing = false
        v.prevTrainStatus = TrainStatus.End
        v.trainStatus = TrainStatus.Back
        let anim = v.rootNode.startTrain(v.soundManager)
        anim.onComplete do():
            v.updateFlyingScatters()
            v.startTrainCycle()
    elif v.trainStatus == TrainStatus.Empty and not v.endTrainComing:
        let anim = endTrain(v.rootNode)
        if not anim.isNil:
            anim.onComplete do():
                v.prepareTrains()

proc moveToBonus(v: CandySlotView, to: bool, prevStage: GameStage) =
    const OFFSET = 1870
    var anims: seq[Animation] = @[]

    proc addAnim(n: Node) =
        const ANIM_NAME = "move"
        anims.add(n.animationNamed(ANIM_NAME))

    addAnim(v.mainLayer)
    addAnim(v.bonusLayer)
    addAnim(v.sharedLayer)
    addAnim(v.backLayer)
    addAnim(v.topLayer)

    let trainAnim = newAnimation()

    trainAnim.loopDuration = anims[0].loopDuration
    trainAnim.numberOfLoops = 1
    trainAnim.onAnimate = proc(p: float) =
        v.trainStartParent.positionX = v.mainLayer.findNode("transition").positionX - OFFSET
    v.addAnimation(trainAnim)
    v.showLayers()

    if to:
        v.boxesUp = v.rootNode.findNode("boxes_up")
        v.boxesDown = v.rootNode.findNode("boxes_down")
        if not v.boxesUp.isNil:
            v.boxesUp.removeFromParent()
            v.boxesUp = nil
        if not v.boxesDown.isNil:
            v.boxesDown.removeFromParent()
            v.boxesDown = nil
        v.inBonusNow = true
        v.rootNode.stopSteam("train_front")
        v.rootNode.stopSteam("train_end")
        v.rootNode.stopSteam("train_start")
        v.boxesUp = newLocalizedNodeWithResource(GENERAL_PREFIX & "bonus/precomps/boxes_up.json")
        v.moveBoxesUpAnim = v.boxesUp.animationNamed("move")
        var positionBoxesUpAnim = v.boxesUp.animationNamed("position")
        v.sharedLayer.findNode("boxes_up_parent").addChild(v.boxesUp)

        v.boxesDown = newLocalizedNodeWithResource(GENERAL_PREFIX & "bonus/precomps/boxes_down.json")
        v.moveBoxesDownAnim = v.boxesDown.animationNamed("move")
        var positionBoxesDownAnim = v.boxesDown.animationNamed("position")
        v.bonusLayer.addChild(v.boxesDown)

        positionBoxesUpAnim.loopPattern = lpStartToEnd
        anims.add(v.moveBoxesUpAnim)
        v.moveBoxesUpAnim.onComplete do():
            v.addAnimation(positionBoxesUpAnim)

        positionBoxesDownAnim.loopPattern = lpStartToEnd
        anims.add(v.moveBoxesDownAnim)

        v.moveBoxesDownAnim.onComplete do():
            v.addAnimation(positionBoxesDownAnim)
        positionBoxesDownAnim.onComplete do():
            if not v.boxesUp.isNil:
                for c in v.boxesUp.children:
                    c.removeComponent(ChannelLevels)
            if not v.boxesDown.isNil:
                for c in v.boxesDown.children:
                    c.removeComponent(ChannelLevels)

        var runLoop: Animation
        var topLayerAnim = v.topLayer.animationNamed("move")
        let startMove = v.boyController.setImmediateAnimation("gotobonus", false)

        startMove.addLoopProgressHandler 0.47, false, proc() =
            v.soundManager.sendEvent("CANDY_BOY_BONUS_GAME_WALK_FALL")
        startMove.onComplete do():
            runLoop = v.boyController.setImmediateAnimation("run_loop_start", false)
            runLoop.numberOfLoops = -1
        topLayerAnim.addLoopProgressHandler 0.58, false, proc() =
            runLoop.cancel()
            v.boyController.setImmediateAnimation("run_loop_end")
        topLayerAnim.addLoopProgressHandler 0.8, false, proc() =
            let shakeLights = v.lights.animationNamed("shake")

            v.addAnimation(v.shakeRoot.parent.animationNamed("shake"))
            v.addAnimation(shakeLights)
            v.addAnimation(v.bonusLayer.findNode("vases").animationNamed("shake"))
            shakeLights.onComplete do():
                v.lights.startLights()
                v.rootNode.findNode("lights_freespin").startLights()
        topLayerAnim.addLoopProgressHandler 0.85, false, proc() =
            let smoke = v.topLayer.findNode("smoke")
            let anim = smoke.animationNamed("play")
            v.addAnimation(anim)
            let module = v.slotGUI.addModule(mtCandyBonusRules)
            module.rootNode.position = newVector3(540, 950)

        for anim in anims:
            anim.loopPattern = lpStartToEnd

        v.bonusGame = initCandyBonusGame(v.bonusField, v.dishesValue, v.betForSpin, v.rootNode, v.pauseManager, v.soundManager, v.boyController)
        v.slotBonuses.inc()
        v.lastActionSpins = 0

        let spinsFromLast = saveNewBonusgameLastSpins(v.name)
        sharedAnalytics().bonusgame_start(v.name, v.slotSpins, v.totalBet, currentUser().chips, spinsFromLast)
        v.bonusGame.onComplete = proc() =
            let startMove = v.boyController.setImmediateAnimation("gotobonus", false)

            v.onBonusGameEnd()
            v.slotGUI.removeModule(mtCandyBonusRules)
            startMove.onComplete do():
                let posX = v.boy.positionX
                let anim = newAnimation()
                let thresholds = @[v.multBig, v.multHuge, v.multMega]

                anim.loopDuration = 2.7
                anim.numberOfLoops = 1
                anim.onAnimate = proc(p: float) =
                    v.boy.positionX = interpolate(posX, posX + 2200, p)
                v.addAnimation(anim)
                anim.onComplete do():
                    v.boy.positionX = v.startBoyPosX
                    v.boy.alpha = 0
                runLoop = v.boyController.setImmediateAnimation("run_loop_start", false)
                runLoop.numberOfLoops = -1
                v.bonusGame.removeLabels()
                v.bonusGame = nil
                v.onBonusGameEnd()
                proc move() =
                    v.moveToBonus(false, prevStage)
                    v.closeBigwin.removeFromSuperview()
                v.slotGUI.winPanelModule.setNewWin(v.bonusPayout)
                v.winDialogWindow = showBigwins(v.specialWinParent, v.bonusPayout, v.totalBet, v.soundManager, GENERAL_PREFIX, thresholds, move, true, v.closeBigwin)
                #v.addSubview(v.closeBigwin)
    else:
        v.inBonusNow = false
        v.boxesUp.reattach(v.bonusLayer)
        for anim in anims:
            anim.loopPattern = lpEndToStart
        v.moveBoxesUpAnim.loopPattern = lpEndToStart
        v.moveBoxesDownAnim.loopPattern = lpEndToStart

        let second_anchor = v.bonusLayer.findNode("second_anchor")
        for i in 1..9:
            let box = v.bonusLayer.findNode("box" & $i)
            if not box.isNil:
                box.reattach(second_anchor)
                box.removeComponent(ChannelLevels)
        v.addAnimation(v.moveBoxesUpAnim)
        v.addAnimation(v.moveBoxesDownAnim)
        v.moveBoxesUpAnim.onComplete do():
            v.boy.alpha = 1
            v.boxesUp.removeFromParent()
            v.boxesDown.removeFromParent()
            v.boxesUp = nil
            v.boxesDown = nil
            v.onLevelUp()

    for anim in anims:
        v.addAnimation(anim)
    anims[0].onComplete do():
        if to:
            v.hideLayers(false)
            v.setTimeout 0.5, proc() =
                v.bonusGame.createButtons()
        else:
            v.hideLayers(true)
            proc updateState() =
                let oldBalance = v.slotGUI.moneyPanelModule.getBalance()
                v.chipsAnim(v.rootNode.findNode("total_bet_panel"), oldBalance.int64, v.currentBalance.int64, "Bonus")

            proc afterFreeSpin() =
                v.canAutospinClick = true
                v.slotGUI.spinButtonModule.button.enabled = true
                updateState()
                v.moveRoulette(false)
                v.betForSpin = v.totalBet()
                v.applyBetChanges()
                v.slotGUI.enableWindowButtons(true)
            if v.stage == GameStage.Spin:
                if prevStage == GameStage.Spin:
                    updateState()
                else:
                    v.soundManager.sendEvent("CANDY_BONUS_GAME_RESULT")
                    v.stopFreespinLight()
                    v.slotGUI.spinButtonModule.stopFreespins()
                    v.prepareTrains()
                    v.trainStatus = TrainStatus.Empty
                    v.onFreeSpinsEnd()
                    v.onFreeSpinsEnd()
                    v.slotGUI.enableWindowButtons(false)
                    v.slotGUI.spinButtonModule.button.enabled = false
                    v.setTimeout 0.5, proc() =
                        v.winDialogWindow = showFreespinsResult(v.specialWinParent, v.totalFreeSpinsWinning, v.soundManager, GENERAL_PREFIX, afterFreeSpin)
    if not to:
        anims[0].addLoopProgressHandler 0.8, false, proc() =
            let enter = v.boyController.setImmediateAnimation("enter")
            enter.onComplete do():
                v.prepareGUItoBonus(false)
                v.showGUIButtons(true)

                if v.stage == GameStage.Spin:
                    v.setSpinButtonState(SpinButtonState.Spin)
                v.rootNode.findNode("numbers_parent").alpha = 1
                for h in v.highlights:
                    for c in h.children:
                        let emitter = c.component(ParticleSystem)
                        emitter.start()

                if v.stage == GameStage.FreeSpin:
                    v.startSpin()
                    v.sharedLayer.findNode("train_end").alpha = 0
                    v.sharedLayer.findNode("train_front").alpha = 0
                    v.trainStatus = TrainStatus.Start
                    v.startTrainCycle()

proc getNextStage(v: CandySlotView): GameStage =
    result = GameStage.Spin
    if v.scatters >= CANDY_MAX_SCATTERS or v.freeSpinsCount > 0:
        result = GameStage.FreeSpin

proc cleanLineTimers(v: CandySlotView) =
    for t in v.lineTimers:
        v.pauseManager.clear(t)

proc playBoyMultiwin(v: CandySlotView) =
    let jumpAnim = v.boyController.setImmediateAnimation("multiwin")
    jumpAnim.addLoopProgressHandler 0.2, false, proc() =
        v.soundManager.sendEvent("CANDY_BOY_JUMP")

proc playWinBoyAnim(v: CandySlotView) =
    let totalWin = v.getPayoutForLines()

    if v.lastField.contains(SCATTER):
        let scatterAnim = v.boyController.setImmediateAnimation("scatter")
        let scatterFly = v.getScatterOnField().findNode("scatter_fly_" & $v.scatters)

        if not scatterFly.isNil:
            let rays1 = scatterFly.findNode("rays_1")
            let rays2 = scatterFly.findNode("rays_2")

            v.addAnimation(rays1.animationNamed("start"))
            v.addAnimation(rays2.animationNamed("start"))
        scatterAnim.addLoopProgressHandler 0.2, false, proc() =
            v.soundManager.sendEvent("CANDY_BOY_FALL_ON_BUTT")
        scatterAnim.addLoopProgressHandler 0.4, false, proc() =
            let shakeLights = v.lights.animationNamed("shake")

            v.playScatterAnim()
            v.addAnimation(v.shakeRoot.parent.animationNamed("shake"))
            v.addAnimation(v.topLayer.animationNamed("shake"))
            v.addAnimation(shakeLights)
            shakeLights.onComplete do():
                v.lights.startLights()
                v.rootNode.findNode("lights_freespin").startLights()
        return
    if totalWin >= v.multBig * v.totalBet or v.paidLines.len > 1 or v.dishesValue.len > 0:
        v.playBoyMultiwin()
        return
    if v.paidLines.len == 1:
        let winAnim = v.boyController.setImmediateAnimation("win")
        winAnim.addLoopProgressHandler 0.45, false, proc() =
            v.soundManager.sendEvent("CANDY_BOY_YES")
    else:
        v.soundManager.sendEvent("CANDY_BOY_DONT_KNOW")
        v.boyController.setImmediateAnimation("nowin")

proc updateCarriages(v: CandySlotView) =
    for i in 1..v.scatters:
        addCarriage(v.rootNode, i, true)
    for i in v.scatters + 1..CARRIAGES:
        addCarriage(v.rootNode, i, false)

proc playScatterAnim(v: CandySlotView) =
    let parent = v.getScatterOnField()

    if not parent.isNil:
        let node = parent.findNode("scatter_fly_" & $v.scatters)
        let rays = node.findNode("rays_1")
        let particle = newLocalizedNodeWithResource("slots/candy_slot/particles/root_jelly_fx.json")

        v.revealScattersFly(false)
        node.alpha = 1.0
        node.addChild(particle)
        particle.position = newVector3(-200, 115)
        let anim = node.animationNamed("win_start")
        let positions = [
            newVector3(-110, -106),
            newVector3(-110, -105),
            newVector3(-116, -102),
            newVector3(-112, -126),
            newVector3(-120, -116)
        ]

        v.addAnimation(anim)
        anim.addLoopProgressHandler 0.3, false, proc() =
            particle.reattach(rays)
        node.reattach(v.rootNode.findNode("parent_scatter_" & $v.scatters))
        let s = node.position
        let e = positions[v.scatters-1]
        let c1 = newVector3((-300 + v.scatters * 50).float, (-750 + v.scatters * 50).float)
        let c2 = newVector3((-300 + v.scatters * 50).float, (-750 + v.scatters * 50).float)
        let loop = node.animationNamed("loop")
        let fly = newAnimation()
        let flySound = v.soundManager.playSFX(SOUND_PATH_PREFIX & "candy_scatter_fly")

        flySound.trySetLooping(true)
        loop.numberOfLoops = CARRIAGES - v.scatters + 1
        fly.numberOfLoops = 1
        fly.loopDuration = loop.loopDuration * loop.numberOfLoops.float
        fly.onAnimate = proc(p: float) =
            let t = interpolate(0.0, 1.0, p)
            let point = calculateBezierPoint(t, s, e, c1, c2)
            node.position = point
        fly.onComplete do():
            flySound.trySetLooping(false)
            for c in particle.children:
                let emitter = c.component(ParticleSystem)
                emitter.stop()
            let down = node.animationNamed("down")
            for i in 1..4:
                closureScope:
                    let index = i
                    let dropAnim = node.findNode("special_drop_" & $index).animationNamed("play")
                    down.addLoopProgressHandler 0.1 * index.float, false, proc() =
                        v.addAnimation(dropAnim)
            v.addAnimation(down)
            down.addLoopProgressHandler 0.3, false, proc() =
                v.soundManager.sendEvent("CANDY_SCATTER_IN_THE_TRAIN")
            down.onComplete do():
                removeGameState("CANDY_SCATTER_FLY")
                if v.slotGUI.autospinsSwitcherModule.isOn:
                    v.onSpinClick()
        v.addAnimation(loop)
        v.addAnimation(fly)

proc addHighlightToSymbol(v: CandySlotView, placeholder: Node) =
    var highlight = placeholder.findNode("highlight_particle")

    if  highlight.isNil:
        highlight = newLocalizedNodeWithResource(GENERAL_PREFIX & "particles/root_choko_highlight.json")
        highlight.name = "highlight_particle"
        placeholder.addChild(highlight)
        highlight.position = newVector3(290, 220)
    else:
        for c in highlight.children:
            let emitter = c.component(ParticleSystem)
            emitter.start()
    v.highlights.add(highlight)

proc showLinesNumbers(v: CandySlotView, allSymbols: openarray[int], payout: int64, speedUp: bool = false) =
    let nums = v.createCandyLineNumbers(v.numbersParent, payout, speedUp)
    let place = getRowByIndex(allSymbols[2])
    let y = (-180 + 200 * place).float
    var timer = 1.0

    if speedUp:
        timer = 0.5
        nums.findNode("drops_line_numbers").removeFromParent()
    if ($payout).len mod 2 == 0:
        nums.position = newVector3(-270, y)
    else:
        nums.position = newVector3(-220, y)

    v.setTimeout timer, proc() =
        nums.removeFromParent()

proc jumpSymbol(v: CandySlotView, placeholder, element: Node, sym: int, allSymbols: seq[int] = @[], payout: int64 = 0, withHighlight: bool = true): Animation {.discardable.} =
    if element.isNil:
        return

    if withHighlight:
        v.addHighlightToSymbol(placeholder.findNode("highlight_anchor"))
    result = element.animationNamed("win")
    if not result.isNil:
        result.numberOfLoops = -1
        v.winningAnims.add(result)

        let res = result
        res.addLoopProgressHandler 0.4, false, proc() =
            if res.curLoop == 0 and v.lastField.len > sym and element.name != "elem_2":
                playWinAnim(placeholder, v.lastField[sym])
        res.addLoopProgressHandler 0.1, false, proc() =
            if element.name == "elem_2" and not v.inBonusNow:
                v.soundManager.sendEvent("CANDY_BONUS_BOX_JUMP")
        v.addAnimation(res)

proc startChipsAnim(v: CandySlotView) =
    let oldBalance = v.slotGUI.moneyPanelModule.getBalance()
    let totalWin = v.getPayoutForLines()

    v.chipsAnim(v.rootNode.findNode("total_bet_panel"), oldBalance, oldBalance + totalWin, "Spin")

proc processSpecialWin(v: CandySlotView, after: proc()) =
    let totalWin = v.getPayoutForLines()

    if totalWin < v.multBig * v.totalBet:
        if v.check5InARow():
            let anim = v.shakeRoot.showFiveInARow()
            anim.onComplete do():
                after()
        else:
            after()
    else:
        var bwt = BigWinType.Big
        let thresholds = @[v.multBig, v.multHuge, v.multMega]

        if totalWin >= v.multMega * v.totalBet:
            bwt = BigWinType.Mega
        elif totalWin >= v.multHuge * v.totalBet:
            bwt = BigWinType.Huge
        v.onBigWinHappend(bwt ,v.currentBalance - totalWin)
        if v.check5InARow():
            let anim = v.shakeRoot.showFiveInARow()
            anim.onComplete do():
                v.slotGUI.enableWindowButtons(false)
                v.winDialogWindow = showBigwins(v.specialWinParent, totalWin, v.totalBet, v.soundManager, GENERAL_PREFIX, thresholds, after)
        else:
            v.slotGUI.enableWindowButtons(false)
            v.winDialogWindow = showBigwins(v.specialWinParent, totalWin, v.totalBet, v.soundManager, GENERAL_PREFIX, thresholds, after)

proc stopLinesAnim(v: CandySlotView) =
    if not v.linesStopped:
        v.linesStopped = true
        let totalWin = v.getPayoutForLines()
        v.setTestAlpha(1.0)
        v.setSpinButtonState(SpinButtonState.Blocked)
        v.slotGUI.winPanelModule.setNewWin(totalWin)
        for anim in v.lineAnims:
            anim.cancel()

        let oldStage = v.stage
        v.stage = v.getNextStage()
        if v.dishesValue.len > 0:
            let announce = v.soundManager.playMusic(SOUND_PATH_PREFIX & "candy_bonus_game_announce", 0.4)

            v.prepareGUItoBonus(true)
            announce.sound.onComplete do():
                v.playBackgroundMusic(MusicType.Bonus)

            proc onDestroyIntro() =
                v.moveToBonus(true, oldStage)
            v.showGUIButtons(false)
            v.trainStatus = TrainStatus.Empty

            var animDuration: float
            for index, elem in v.lastField:
                if elem == BONUS:
                    let placeholder = v.getPlaceholder(index)
                    let bonus = placeholder.findNode("elem_" & $v.lastField[index])

                    let anim = v.jumpSymbol(placeholder, bonus, 2, @[], 0, false)
                    animDuration = anim.loopDuration

            v.setTimeout animDuration, proc() =
                v.rootNode.findNode("numbers_parent").alpha = 0
                for h in v.highlights:
                    for c in h.children:
                        let emitter = c.component(ParticleSystem)
                        emitter.stop()
                v.startCandyBonusIntroAnim(v.specialWinParent, onDestroyIntro)
        elif v.stage == GameStage.FreeSpin:
            proc afterSpecialWins() =

                proc onDestroyIntro() =
                    v.trainStatus = TrainStatus.Start
                    v.startTrainCycle()
                    v.startFreespinLight()
                    v.moveRoulette(true)
                    v.playBoyMultiwin()
                    v.setSpinButtonState(SpinButtonState.Blocked)
                    v.setTimeout 2.0, proc() =
                        proc startcb() =
                            v.slotGUI.spinButtonModule.button.enabled = true
                            v.startSpin()
                        let spinFlow = findActiveState(SpinFlowState)
                        if not spinFlow.isNil:
                            spinFlow.pop()
                        let state = newFlowState(SlotNextEventFlowState, newVariant(startcb))
                        pushBack(state)

                if v.freeSpinsCount == v.pd.freespinsAllCount: #when first free spin is incoming
                    v.slotGUI.spinButtonModule.button.enabled = false
                    v.freespinsTriggered.inc()
                    v.lastActionSpins = 0

                    let spinsFromLast = saveNewFreespinLastSpins(v.name)
                    sharedAnalytics().freespins_start(v.name, v.slotSpins, v.totalBet, currentUser().chips, spinsFromLast)
                    v.setTimeout 3.0, proc() =
                        let announce = v.soundManager.playMusic(SOUND_PATH_PREFIX & "candy_free_spins_announce", 0.4)
                        announce.sound.onComplete do():
                            v.playBackgroundMusic(MusicType.Freespins)
                        v.startCandyFreeSpinIntroAnim(v.specialWinParent, v.freeSpinsCount, onDestroyIntro)
                else:
                    v.setTimeout 1.5, proc() =
                        proc startcb() =
                            v.startSpin()
                        let spinFlow = findActiveState(SpinFlowState)
                        if not spinFlow.isNil:
                            spinFlow.pop()
                        let state = newFlowState(SlotNextEventFlowState, newVariant(startcb))
                        pushBack(state)
            v.processSpecialWin(afterSpecialWins)

        else:
            proc showSpinResults() =
                proc updateState() =
                    v.canAutospinClick = true
                    v.onLevelUp()
                    if v.lastField.contains(SCATTER):
                        v.setTimeout 3.0, proc() =
                            v.setSpinButtonState(SpinButtonState.Spin)
                    else:
                        v.setTimeout 0.4, proc() =
                            v.setSpinButtonState(SpinButtonState.Spin)
                    if oldStage == GameStage.FreeSpin:
                        v.moveRoulette(false)
                    v.slotGUI.enableWindowButtons(true)
                if oldStage == GameStage.Spin:
                    updateState()
                else:
                    v.applyBetChanges()
                    v.stopFreespinLight()
                    v.betForSpin = v.totalBet()
                    let announce = v.soundManager.playMusic(SOUND_PATH_PREFIX & "candy_bonus_game_result", 0.4)

                    announce.sound.onComplete do():
                        v.playBackgroundMusic(MusicType.Main)
                    v.slotGUI.spinButtonModule.stopFreespins()
                    v.trainStatus = TrainStatus.Empty
                    v.onFreeSpinsEnd()
                    v.slotGUI.enableWindowButtons(false)
                    v.winDialogWindow = showFreespinsResult(v.specialWinParent, v.totalFreeSpinsWinning, v.soundManager, GENERAL_PREFIX, updateState)
                    v.slotGUI.winPanelModule.setNewWin(v.totalFreeSpinsWinning, false)
            v.processSpecialWin(showSpinResults)

proc removeHighlights(v: CandySlotView) =
    for h in v.highlights:
        for c in h.children:
            let emitter = c.component(ParticleSystem)
            emitter.stop()
    for anim in v.winningAnims:
        anim.cancelBehavior = cbContinueUntilEndOfLoop
        anim.cancel()
    v.highlights = @[]

proc playWinningNumbers(v: CandySlotView) =
    let anim = newAnimation()

    anim.loopDuration = v.paidLines.len.float * 1.5
    anim.numberOfLoops = -1
    for i in 0..<v.paidLines.len:
        closureScope:
            let index = i
            let delay = 1.0 / v.paidLines.len.float * (index + 1).float
            let lineIndex = v.paidLines[index].index
            let allSymbols = v.getSymbolIndexesForLine(v.lines[lineIndex])
            let payout = v.paidLines[index].winningLine.payout

            anim.addLoopProgressHandler delay, false, proc() =
                v.showLinesNumbers(allSymbols, payout, true)
    v.addAnimation(anim)
    v.repeatNumbersAnim = anim

proc showWinningLines(v: CandySlotView) =
    const LINE_TIME = 1.0
    const SYM_DELAY = LINE_TIME / NUMBER_OF_REELS
    let lines = v.paidLines

    v.spinSound.stop()
    v.playWinBoyAnim()
    v.lineAnims = @[]
    v.lineTimers = @[]
    var totalWin: int64
    v.getSortedWinningLines()
    v.setSpinButtonState(SpinButtonState.Blocked)
    if not v.lastField.contains(SCATTER):
        v.setTimeout 0.1, proc() =
            v.setSpinButtonState(SpinButtonState.StopAnim)

    v.playWinningNumbers()

    for i, value in lines:
        closureScope:
            let lineIndex = value.index
            let delay = i.float * LINE_TIME
            let symbolsCount = value.winningLine.numberOfWinningSymbols
            let allSymbols = v.getSymbolIndexesForLine(v.lines[lineIndex])
            let payout = value.winningLine.payout
            let timer = v.setTimeout(delay, proc() =
                v.soundManager.sendEvent("CANDY_WIN_LINE")
                for anim in v.lineAnims:
                    anim.cancel()
                totalWin += payout
                v.slotGUI.winPanelModule.setNewWin(totalWin)
                v.lineAnims = @[]
                v.createCandyWinningLine(v.lineParent, LINE_TIME, lineIndex)

                for i in 0..<ReelCountCandy:
                    closureScope:
                        let index = i
                        let sym = allSymbols[index]
                        let placeholder = v.getPlaceholder(sym)
                        let ls = v.lastField
                        if index < symbolsCount:
                            v.setTimeout index.float * SYM_DELAY, proc() =
                                if sym < ls.len:
                                    let wild = placeholder.findNode("elem_11")
                                    if not wild.isNil and wild.alpha > 0:
                                        v.jumpSymbol(placeholder, wild, sym, allSymbols, payout)
                                    else:
                                        v.jumpSymbol(placeholder, placeholder.findNode("elem_" & $v.lastField[sym]), sym, allSymbols, payout)
            )
            v.lineTimers.add(timer)

    v.startChipsAnim()
    let t = v.setTimeout(lines.len.float * LINE_TIME, proc() =
        v.stopLinesAnim()
    )
    v.lineTimers.add(t)

proc createWildParticles(v: CandySlotView) =
    const COUNT = ELEMENTS_COUNT - 1

    v.wildParticles = @[]
    for i in 0..<COUNT:
        v.wildParticles.add(newLocalizedNodeWithResource("slots/candy_slot/particles/root_choko_symbol.json"))

proc replaceWilds(v: CandySlotView, parentWild: int) =
    for i, value in v.wildIndexes:
        closureScope:
            let index = value
            let num = i
            let sym = v.lastField[index]
            let sa = v.symbolAnimations[index]
            let s = v.getPlaceholder(parentWild).localToWorld(newVector3(250, 270))
            let wildParticle = v.wildParticles[num]
            let e = v.getPlaceholder(index).localToWorld(newVector3(250, 270))
            let c1 = newVector3(s.x - (s.x - e.x) / 2, e.y - 200)
            let c2 = c1

            v.rootNode.addChild(wildParticle)
            wildParticle.position = s
            for c in wildParticle.children:
                let emitter = c.component(ParticleSystem)
                emitter.start()

            let fly = newAnimation()
            fly.numberOfLoops = 1
            fly.loopDuration = 1.0
            fly.onAnimate = proc(p: float) =
                let t = interpolate(0.0, 1.0, p)
                let point = calculateBezierPoint(t, s, e, c1, c2)
                wildParticle.position = point
            v.addAnimation(fly)
            v.soundManager.sendEvent("CANDY_WILD_SPRINKLE")
            fly.onComplete do():
                for c in wildParticle.children:
                    let emitter = c.component(ParticleSystem)
                    emitter.stop()
                v.startSpinAnim(sa, sym, true)
                v.setTimeout 2.5, proc() =
                    v.endSpinAnim(sa, SECONDARY_WILD, v.scatters, true)
                    v.startField[index] = SECONDARY_WILD
                    wildParticle.removeFromParent()
    v.setTimeout 3.5, proc() =
        v.showWinningLines()


proc stopReel(v: CandySlotView, index: int) =
    if v.stopTimers.len > 0 and v.animSettings.len > 0:
        if v.lastField.contains(SCATTER):
            setGameState("CANDY_SCATTER_FLY", true)
        v.stopTimers[index] = v.setTimeout(v.animSettings[index].time, proc() =
            v.stopReelAnim(index)
            if index == NUMBER_OF_REELS - 1:
                if v.wildIndexes.len == 0:
                    v.setTimeout 0.8, proc() =
                        v.showWinningLines()
                else:
                    v.setSpinButtonState(SpinButtonState.Blocked)
                    v.setTimeout 0.5, proc() =
                        v.setSpinButtonState(SpinButtonState.Blocked)
                        let reelIndexes = reelToIndexes(index)

                        for ri in reelIndexes:
                            if v.lastField[ri] == 0'i8:
                                let wildAnim = v.boyController.setImmediateAnimation("wild")
                                let placeholder = v.getPlaceholder(ri)
                                let oldWild = placeholder.findNode("elem_0")
                                let anim = oldWild.animationNamed("win")

                                v.soundManager.sendEvent("CANDY_WILD_APPEAR")
                                startCandyFirework(v.topLayer, getRowByIndex(ri), wildAnim)
                                v.addAnimation(anim)
                                anim.addLoopProgressHandler 0.65, false, proc() =
                                    let drops = newLocalizedNodeWithResource(GENERAL_PREFIX & "slot/precomps/brown_wild_drops.json")
                                    let dropsAnim = drops.animationNamed("play")
                                    drops.scale.x = 0.3
                                    drops.scale.y = 0.3
                                    drops.position = newVector3(100, 100)

                                    placeholder.addChild(drops)
                                    v.addAnimation(dropsAnim)
                                    dropsAnim.onComplete do():
                                        drops.removeFromParent()

                                v.soundManager.sendEvent("CANDY_BOY_THROW_FIREWORK")
                                wildAnim.addLoopProgressHandler 0.65, false, proc() =
                                    let newWild = placeholder.findNode("elem_11")
                                    newWild.alpha = 1
                                    oldWild.alpha = 0
                                    v.addAnimation(newWild.animationNamed("win"))

                                wildAnim.addLoopProgressHandler 0.85, false, proc() =
                                    v.soundManager.sendEvent("CANDY_WILD_EXPLODES")
                                wildAnim.addLoopProgressHandler 1.0, false, proc() =
                                    v.replaceWilds(ri)
                                break
        )

proc onSpinResponse(v: CandySlotView) =
    for i in 0..<NUMBER_OF_REELS:
        if not v.endAnimFinished[i]:
            if v.animReadyForStop and v.actionButtonState == SpinButtonState.Blocked and v.animSettings.len > 0:
                v.animSettings[i].time = 0
                v.animSettings[i].boosted = false
            v.stopReel(i)

proc sendSpinRequest(v: CandySlotView) =
    const minStopTimeout = 1.5 # Stop button will be enabled as soon as server replies but not sooner than this value.

    var stopTimeoutElapsed = false

    if v.lastField.len > 0:
        v.startField = v.lastField
    for index in v.wildIndexes:
        v.startField[index] = SECONDARY_WILD

    v.gotSpinResponse = false
    v.animReadyForStop = false
    v.bonusField = @[]
    v.dishesValue = @[]
    v.wildIndexes = @[]
    v.animSettings = @[]
    v.paidLines = @[]
    v.highlights = @[]
    v.lastField = @[]

    for i in 0..<NUMBER_OF_REELS:
        v.endAnimFinished[i] = false
        closureScope:
            let index = i
            v.setTimeout index.float * 0.2, proc() =
                v.stopTimers[i] = ControlledTimer.new()
                v.startReelAnim(index)

    v.betForSpin = v.totalBet
    v.sendSpinRequest(v.betForSpin) do(res: JsonNode):
        let firstStage = res[$srtStages][0]
        let oldChips = currentUser().chips

        v.gotSpinResponse = true
        v.betForSpin = v.totalBet()
        v.scatters = res[$srtScatters].getInt()
        v.freeSpinsCount = res[$srtFreespinCount].getInt()
        v.totalFreeSpinsWinning = res[$srtFreespinTotalWin].getBiggestInt()

        if res[$srtStages].len > 1:
            let bonusStage = res[$srtStages][1]

            v.bonusPayout = bonusStage[$srtPayout].getBiggestInt()
            for j in bonusStage[$srtField].items:
                v.bonusField.add(j.getInt().int8)
            for j in bonusStage[$srtDishesValue].items:
                v.dishesValue.add(j.getInt())
        for j in firstStage[$srtField].items:
            v.lastField.add(j.getInt().int8)
        for j in firstStage[$srtWildIndexes].items:
            v.wildIndexes.add(j.getInt().int8)

        v.paidLines = firstStage[$srtLines].parsePaidLines()

        # for item in firstStage[$srtLines].items:
        #     let line = PaidLine.new()
        #     line.winningLine.numberOfWinningSymbols = item["symbols"].getInt()
        #     line.winningLine.payout = item["payout"].getInt()
        #     line.index = item["index"].getInt()
        #     v.paidLines.add(line)
        currentUser().chips = res[$srtChips].getBiggestInt()

        var spent = v.betForSpin
        var win: int64 = 0
        if v.stage == GameStage.FreeSpin or v.freeRounds:
            spent = 0

        if currentUser().chips > oldChips - spent:
            win = currentUser().chips - oldChips + spent

        if v.scatters >= CANDY_MAX_SCATTERS or v.freeSpinsCount > 0:
            v.canAutospinClick = false

        v.spinAnalyticsUpdate(win, v.stage == GameStage.FreeSpin)

        let state = v.getStateForStopAnim()
        var reelsInfo = (bonusReels: @[0, 2, 4], scatterReels: @[4])
        v.setRotationAnimSettings(ReelsAnimMode.Long, state, reelsInfo)
        if v.stage == GameStage.FreeSpin:
            v.slotGUI.spinButtonModule.setFreespinsCount(v.freeSpinsCount)
        if stopTimeoutElapsed:
            v.onSpinResponse()

    proc onResponse() =
        v.setSpinButtonState(SpinButtonState.ForcedStop)
        if v.lastField.len > 0:
            v.onSpinResponse()
        stopTimeoutElapsed = true
    v.startAnimatedTimer(minStopTimeout, onResponse)

proc startSpin(v: CandySlotView) =
    v.removeHighlights()
    v.boyAnticipating = false
    v.removeWinAnimationWindow(true)

    if v.stage == GameStage.Spin and not v.freeRounds:
        if not currentUser().withdraw(v.totalBet):
            v.setSpinButtonState(SpinButtonState.Spin)
            v.slotGUI.outOfCurrency("chips")
            return
        let beforeSpinChips = currentUser().chips
        v.setTimeout 0.5, proc() =
            v.slotGUI.moneyPanelModule.setBalance(beforeSpinChips, beforeSpinChips - v.totalBet, false)

    let rnd = rand(1..3)
    v.spinSound = v.soundManager.playSFX(SOUND_PATH_PREFIX & "candy_spin_3")
    v.spinSound.trySetLooping(true)

    v.setSpinButtonState(SpinButtonState.Blocked)
    let boyJump = v.boyController.setImmediateAnimation("spin_" & $rnd)

    if rnd == 2:
        boyJump.addLoopProgressHandler 0.2, false, proc() =
            v.soundManager.sendEvent("CANDY_BOY_JUMP_TURNES_LEFT")
    elif rnd == 3:
        v.soundManager.sendEvent("CANDY_BOY_EYES_ROLL")
    v.sendSpinRequest()
    v.linesStopped = false
    v.slotGUI.winPanelModule.setNewWin(0)

    if not v.repeatNumbersAnim.isNil:
        v.repeatNumbersAnim.cancel()
        v.repeatNumbersAnim = nil

method onSpinClick*(v: CandySlotView) =
    procCall v.BaseMachineView.onSpinClick()
    if not v.removeWinAnimationWindow(): return
    if v.actionButtonState == SpinButtonState.Spin:
        if hasGameState("CANDY_SCATTER_FLY"):
            v.spinRotate.cancel()
        else:
            v.startSpin()
    elif v.actionButtonState == SpinButtonState.ForcedStop:
        v.setSpinButtonState(SpinButtonState.Blocked)
        if v.animReadyForStop:
            for i in 0..<NUMBER_OF_REELS:
                if v.gotSpinResponse and not v.endAnimFinished[i]:
                    v.pauseManager.clear(v.stopTimers[i])
                    v.animSettings[i].time = 0
                    v.animSettings[i].boosted = false
                    v.stopReel(i)
    elif v.actionButtonState == SpinButtonState.StopAnim:
        v.setSpinButtonState(SpinButtonState.Blocked)
        v.cleanLineTimers()
        v.stopLinesAnim()

method clickScreen(v: CandySlotView) =
    if not v.winDialogWindow.isNil and v.winDialogWindow.readyForClose:
        info "CLOSE FROM CLICKSCREEN"
        v.winDialogWindow.destroy()
    else:
        discard v.makeFirstResponder()

proc setInitialData(v: CandySlotView) =
    v.slotGUI.moneyPanelModule.setBalance(v.currentBalance, v.currentBalance, false)
    if v.scatters >= CANDY_MAX_SCATTERS or v.freeSpinsCount > 0:
        v.canAutospinClick = false
        v.stage = GameStage.FreeSpin
        v.slotGUI.spinButtonModule.button.enabled = false
        v.setTimeout 1, proc() =
            proc onDestroyIntro() =
                let animRoulette = v.moveRoulette(true)

                v.trainStatus = TrainStatus.Start
                v.startTrainCycle()
                v.startFreespinLight()
                animRoulette.onComplete do():
                    v.slotGUI.spinButtonModule.button.enabled = true
                    v.startSpin()
            v.playBackgroundMusic(MusicType.Freespins)
            v.soundManager.sendEvent("CANDY_FREE_SPINS_ANNOUNCE")
            v.startCandyFreeSpinIntroAnim(v.specialWinParent, v.freeSpinsCount, onDestroyIntro)
    else:
        v.stage = GameStage.Spin
        v.setSpinButtonState(SpinButtonState.Spin)
    v.betForSpin = v.totalBet()

method restoreState*(v: CandySlotView, res: JsonNode) =
    procCall v.BaseMachineView.restoreState(res)

    echo "restore candy ", res

    currentUser().updateWallet(res[$srtChips].getBiggestInt())
    if res.hasKey($srtFreespinCount):
        v.freeSpinsCount = res[$srtFreespinCount].getInt()
    if res.hasKey($srtFreespinTotalWin):
        v.totalFreeSpinsWinning = res[$srtFreespinTotalWin].getBiggestInt()
    if res.hasKey($srtScatters):
        v.scatters = res[$srtScatters].getInt()
    if res.hasKey($srtBigwinMultipliers):
        v.multBig = res[$srtBigwinMultipliers][0].getInt()
        v.multHuge = res[$srtBigwinMultipliers][1].getInt()
        v.multMega = res[$srtBigwinMultipliers][2].getInt()

    if res.hasKey("paytable"):
        var pd: CandyPaytableServerData
        var paytable = res["paytable"]

        pd.paytableSeq = res.getPaytableData()
        pd.freespinsAllCount = paytable["freespin_count"].getInt()
        v.pd = pd

    v.setInitialData()
    v.updateCarriages()

method viewOnEnter*(v: CandySlotView) =
    procCall v.BaseMachineView.viewOnEnter()

    discard v.shakeRoot.newChild("paytable_anchor")
    v.lights = v.sharedLayer.findNode("lights")
    v.soundManager = newSoundManager(v)
    v.soundManager.loadEvents(SOUND_PATH_PREFIX & "candy", "common/sounds/common")

    v.slotGUI.totalBetPanelModule.buttonMinus.onAction do():
        v.betMinus()
        v.betForSpin = v.totalBet

    v.slotGUI.totalBetPanelModule.buttonPlus.onAction do():
        v.betPlus()
        v.betForSpin = v.totalBet

    v.lollipopAnim = v.mainLayer.startLollipop()
    v.lollipopAnim.tag = ACTIVE_SOFT_PAUSE
    v.airplaneAnim = v.topLayer.startAirplane()
    v.lightsAnim = v.lights.startLights()
    v.airplaneAnim.tag = ACTIVE_SOFT_PAUSE
    v.lightsAnim.tag = ACTIVE_SOFT_PAUSE
    v.hideLayers(true)
    v.sharedLayer.findNode("train_end").alpha = 0
    v.sharedLayer.findNode("train_front").alpha = 0

    v.slotGUI.spinButtonModule.button.enabled = false
    v.setTimeout 1, proc() =
        v.startBoyPosX = v.boy.positionX
        v.boy.alpha = 1
        let enterAnim = v.boyController.setImmediateAnimation("enter")
        enterAnim.onComplete do():
            v.slotGUI.spinButtonModule.button.enabled = true
    v.winningAnims = @[]
    v.playBackgroundMusic(MusicType.Main)
    v.soundManager.sendEvent("CANDY_AMBIENCE")
    v.specialWinParent = v.slotGUI.rootNode.newChild("special_win_parent")

method viewOnExit*(v: CandySlotView) =
    v.lollipopAnim.cancel()
    v.airplaneAnim.cancel()
    v.lightsAnim.cancel()

    if not v.freespinLightsAnim.isNil:
        v.freespinLightsAnim.cancel()

    for anim in v.winningAnims:
        anim.cancel()
    if not v.boyController.curAnimation.isNil:
        v.boyController.curAnimation.cancel()

    procCall v.BaseMachineView.viewOnExit()

proc addAnticipationParticles(v: CandySlotView) =
    v.anticipationParticles = @[]
    for i in 3..4:
        for j in 0..2:
            let parent = v.rootNode.findNode("placeholder_" & $i & "_" & $j)
            let anticipate = newLocalizedNodeWithResource(GENERAL_PREFIX & "particles/root_spiral.json")

            anticipate.position = newVector3(400, 370)
            parent.addChild(anticipate)
            v.anticipationParticles.add(anticipate)

method initAfterResourcesLoaded(v: CandySlotView) =
    procCall v.BaseMachineView.initAfterResourcesLoaded()
    let earthshake = newLocalizedNodeWithResource(GENERAL_PREFIX & "shared/precomps/earthshake.json")
    v.rootNode.addChild(earthshake)
    earthshake.position = newVector3(-960, -540)
    v.shakeRoot = earthshake.childNamed("shake_root")
    v.mainLayer = newLocalizedNodeWithResource(GENERAL_PREFIX & "slot/main.json")
    v.bonusLayer = newLocalizedNodeWithResource(GENERAL_PREFIX & "bonus/bonus.json")
    v.backLayer = newLocalizedNodeWithResource(GENERAL_PREFIX & "shared/back.json")
    v.topLayer = newLocalizedNodeWithResource(GENERAL_PREFIX & "shared/top.json")
    v.sharedLayer = newLocalizedNodeWithResource(GENERAL_PREFIX & "shared/shared.json")
    v.shakeRoot.addChild(v.backLayer)
    v.shakeRoot.addChild(v.mainLayer)
    v.trainStartParent = v.shakeRoot.newChild("train_start_parent")
    v.trainStart = newLocalizedNodeWithResource(GENERAL_PREFIX & "shared/precomps/train_start.json")
    v.trainStartParent.addChild(v.trainStart)
    v.shakeRoot.addChild(v.bonusLayer)
    v.shakeRoot.addChild(v.topLayer)
    v.shakeRoot.addChild(v.sharedLayer)
    v.firstFill()
    v.setSpinButtonState(SpinButtonState.Blocked)
    v.lineParent = v.shakeRoot.newChild("line_parent")
    v.numbersParent = v.shakeRoot.newChild("numbers_parent")
    v.boy = v.shakeRoot.findNode("boy")
    v.boyController = newAnimationControllerForNode(v.boy)
    v.boyController.addIdles(["idle"])
    v.boy.alpha = 0
    setRouletteScissor(v.mainLayer)

    for i in v.scatters + 1..CARRIAGES:
        addCarriage(v.rootNode, i, false)
    v.rootNode.addSteam()
    v.createWildParticles()

    v.trainBack = v.rootNode.findNode("train_front")
    v.trainEnd = v.rootNode.findNode("train_end")

    v.addAnticipationParticles()
    v.camera.zNear = -1000.0

    v.closeBigwin = newButton(newRect(0, 0, 1920, 1080))
    v.closeBigwin.onAction do():
        if not v.winDialogWindow.isNil and v.winDialogWindow.readyForClose:
            v.winDialogWindow.destroy()
    v.closeBigwin.hasBezel = false


method init*(v: CandySlotView, r: Rect) =
    procCall v.BaseMachineView.init(r)
    v.addDefaultOrthoCamera("Camera")
    v.gLines = 20
    v.symbolAnimations = @[]
    v.mainForHide = @["bonus", "top_svet_1.png", "top_svet_2.png", "top_svet_3.png", "top_svet_4.png", "foreground_3.png", "foreground_2.png",
    "foreground_box_2.png"]
    v.bonusForHide = @["main", "top_svet_6.png", "top_svet_7.png", "top_svet_8.png", "top_svet_9.png", "airplane", "foreground_zaplatka.png",
    "midground_table.png", "foreground_1.png", "top_parent"]
    if hasGameState("CANDY_SCATTER_FLY"):
        removeGameState("CANDY_SCATTER_FLY")

method assetBundles*(v: CandySlotView): seq[AssetBundleDescriptor] =
    const ASSET_BUNDLES = [
        assetBundleDescriptor("slots/candy_slot/bonus"),
        assetBundleDescriptor("slots/candy_slot/boy"),
        assetBundleDescriptor("slots/candy_slot/candy_sound"),
        assetBundleDescriptor("slots/candy_slot/five_in_a_row"),
        assetBundleDescriptor("slots/candy_slot/free_spin_intro"),
        assetBundleDescriptor("slots/candy_slot/particles"),
        assetBundleDescriptor("slots/candy_slot/paytable"),
        assetBundleDescriptor("slots/candy_slot/shared"),
        assetBundleDescriptor("slots/candy_slot/slot"),
        assetBundleDescriptor("slots/candy_slot/special_win")
    ]
    result = @ASSET_BUNDLES
