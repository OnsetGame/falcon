
import logging, hashes, tables, random, json, strutils, sequtils, times
import nimx / [ view, image, context, button, animation, timer, notification_center ]
import rod / [ rod_types, node, viewport, component, ray, asset_bundle ]
import rod / component / [ sprite, particle_emitter, camera, overlay, solid,
        channel_levels, text_component, clipping_rect_component ]
import shared / [ user, chips_animation, director ]

import core.slot.base_slot_machine_view
import core.slot.state_slot_machine

import shared / gui / [ gui_module, win_panel_module, total_bet_panel_module,
        paytable_open_button_module, spin_button_module, money_panel_module, slot_gui, autospins_switcher_module ]
import falconserver / slot / [ machine_base_types, slot_data_types ]

import utils / [ lights_cluster, fade_animation, sound, sound_manager, animation_controller,
        falcon_analytics_utils, game_state, helpers, pause, falcon_analytics, falcon_analytics_helpers ]

import line, rope, symbol_highlight, eiffel_win_popup,
        pigeon_animation, lift_node, info_panel, tower_lights, alpha_blur,
        quest.quests
import core.net.server
import shared.window.window_manager
import shared.window.button_component
import core / flow / flow_state_types

const
    symbolWidth = Coord(196)
    symbolHeight = Coord(196)
    AFKDelay = 5.0
    GENERAL_PREFIX = "slots/eiffel_slot/"
    SOUND_PATH_PREFIX = GENERAL_PREFIX & "eiffel_sound/"
    NUMBER_OF_ROTATING_NODES = 12
    symVerticalSpacing = 240.Coord
    BETWEEN_SPINS_TIMEOUT = 1.0
    GAME_FLOW = ["GF_SHOW_WIN", "GF_SPECIAL", "GF_BONUS", "GF_RESPINS", "GF_FREESPINS", "GF_LEVELUP", "GF_SPIN"]

type
    LightAnims{.pure.} = enum
        towerLeft,
        towerRight,
        towerMidLeft,
        towerMidRight,
        towerMidLeftReverse,
        towerMidRightReverse,
        lightAnims_len

    EiffelPaytableServerData* = tuple
        itemset: seq[string]
        paytableSeq: seq[seq[int]]
        freespTriggerId: string
        freespRelation: seq[tuple[triggerCount: int, freespinCount: int]]
        bonusTriggerId: string
        bonusCount: int

    EiffelSlotView* = ref object of BaseMachineView
        spinSound, riser: Sound
        lightLeft, lightRight, rope : Image
        mimeController: AnimationController
        popupHolder: Node
        reelHighlightNode: Node
        singleImagesNode: Node

        symbolHighlightController: SymbolHighlightController

        nextFreeSpinsLeft: int
        freeSpinsTotalWin, totalWin, bonusWin, roundWin: int64
        rotationBaseSpeed, bonusCount, scattersCount: int
        lastPlayerActivity: float

        isInFreeSpins: bool
        isRedAnimActive: bool
        inBonus: bool

        infoPanel: InfoPanel
        fadeAnim: FadeSolidAnimation

        lightClusters: array[LightAnims.lightAnims_len.int, LightsCluster]
        lightAnims: seq[LightAnims]
        rotationAnimBoosted: seq[bool]
        ropeAnimationOffset:seq[float32]
        rotationAnims: seq[Animation]
        ropesAnims: seq[Animation]
        reelSpinAnimations: seq[Animation]
        auxAnimations : seq[Animation]
        bonusResult*: seq[int]
        reelNodes: seq[Node]
        rotatingReels: seq[Node]
        highlightedBonuses:seq[Node]
        highlightedScatters:seq[Node]
        firstWinningSymbols:seq[Node]
        cachedSymbols: Table[Symbols, seq[Node]]
        freeSpinsOnEnter: bool
        pd*: EiffelPaytableServerData
        bonusConfigRelation*: seq[int]

proc getSlotGUI*(v: EiffelSlotView): SlotGUI =
    v.slotGUI

proc hideGUI*(v: EiffelSlotView) =
    v.slotGUI.rootNode.enabled = false

proc showGUI*(v: EiffelSlotView) =
    v.slotGUI.rootNode.enabled = true

import eiffel_bonus_game_view

proc putSymbolNodeToCache*(v: EiffelSlotView, n: Node): Symbols {.discardable.}=
    let sc = n.componentIfAvailable(SymbolComponent)
    if not sc.isNil:
        result = sc.sym
        if sc.sym in v.cachedSymbols and sc.sym != Symbols.Scatter:
            v.cachedSymbols[sc.sym].add(n)

proc stopAnimNamed(n:Node, an: string)=
    if n.isNil: return
    var a = n.animationNamed(an)
    if not a.isNil and not a.onAnimate.isNil:
        a.onAnimate(0)
        a.cancel()
        a.onComplete do():
            a.onAnimate(0)

proc removeNodeChildrenAndPutSymbolsToCache*(n: Node, v: EiffelSlotView) =
    for c in n.children:
        var sym = v.putSymbolNodeToCache(c)
        c.stopAnimNamed("play")
        if sym == Symbols.Bonus:
            var ch = c.findNode("symbol")
            if not ch.isNil:
                ch.stopAnimNamed("open")
    n.removeAllChildren()

proc startSpin(v: EiffelSlotView)
proc startAnimationForReel(v: EiffelSlotView, reelIndex: int)
proc removeThrillHighlights(v: EiffelSlotView)
proc startFreeSpinsAnimation(v: EiffelSlotView, showIntro: bool = false)

proc playBackgroundMusic(v: EiffelSlotView) =
    v.soundManager.sendEvent("BACKGROUND_MUSIC")

proc getStateForStopAnim*(v:EiffelSlotView): WinConditionState =
    const MINIMUM_BONUSES = 2
    const MINIMUM_SCATTERS = 2
    const MINIMAL_LINE = 2
    let scatterCount = v.countSymbols(Symbols.Scatter.int)
    let bonusCount = v.countSymbols(Symbols.Bonus.int)

    result = WinConditionState.NoWin
    if v.getLastWinLineReel() >= MINIMAL_LINE:
        result = WinConditionState.Line
    if scatterCount >= MINIMUM_SCATTERS:
        result =  WinConditionState.Scatter
    if bonusCount >= MINIMUM_BONUSES:
        let bonusReels = v.getWinConReels(Symbols.Bonus.int)
        let scatterReels = v.getWinConReels(Symbols.Scatter.int)

        if not (bonusReels.len == MINIMUM_BONUSES and bonusReels[1] == 4):
            result = WinConditionState.Bonus
        if scatterCount >= bonusCount and scatterReels[0] > bonusReels[0]:
            result = WinConditionState.Scatter

proc centerOfSymbolInReel(v: EiffelSlotView, s, reelIndex: int): Point =
    let n = v.reelNodes[reelIndex].findNode("Field").findNode($(s + 1))
    let p = n.localToWorld(newVector3(symbolWidth/2, symbolHeight/2))
    result.x = p.x
    result.y = p.y + 30

proc isPlayerActive*(v: EiffelSlotView): bool =
    var curt = epochTime()
    result = (v.lastPlayerActivity + AFKDelay) > curt

proc linesComponent(v: EiffelSlotView): LinesComponent =
    v.rootNode.findNode("lines_unique").component(LinesComponent)

proc pushLightAnims(v: EiffelSlotView, anims_set: set[LightAnims])=
    v.lightAnims.setLen(0)
    for anim in anims_set:
        v.lightAnims.add(anim)

proc playLightAnims(v:EiffelSlotView, dur: float = 2.0, timeout: float = 0.0)=
    v.setTimeout timeout, proc()=
        for anim in v.lightAnims:
            v.addAnimation(v.lightClusters[anim.int].waveAnimation())

proc showInactiveText(v: EiffelSlotView) =
    const d = 5.0

    proc inactiveAnimation(v: EiffelSlotView, delay: float) =
        v.setTimeout delay, proc()=
            if not v.isPlayerActive():
                if v.infoPanel.showRandomText():
                    v.pushLightAnims({LightAnims.towerLeft..LightAnims.towerMidRight})
                    v.playLightAnims(dur = 4.0, timeout = 0.0)

                v.inactiveAnimation(delay)

    if v.lastPlayerActivity == -1:
        v.inactiveAnimation(d)
    else:
        v.setTimeout AFKDelay - d, proc()=
            v.inactiveAnimation(d)

proc startIdleAnimations(v: EiffelSlotView) =
    for r in v.reelNodes:
        let field = r.findNode("Field")
        for c in field.children:
            let sym = c.findNode("SYMBOL_PLACEHOLDER").children[0]
            let anim = sym.animationNamed("idle")
            if not anim.isNil:
                v.auxAnimations.add(anim)
    for a in v.auxAnimations:
        v.addAnimation(a)
    v.linesComponent.startRepeatingLines()
    v.linesComponent.soundManager = v.soundManager

proc runWinAnimation(v: EiffelSlotView, compositionName: string, toValue: int64, onDestroy:proc()=nil): EiffelWinDialogWindow =
    proc onWinAnimDestroy() =
        if not v.fadeAnim.isNil:
            v.fadeAnim.changeFadeAnimMode(0, 1.0)
            v.setTimeout 1.0, proc() =
                v.fadeAnim.removeFromParent()

        let oldBalance = v.currentBalance - v.totalWin
        v.notificationCenter.postNotification("chips_animation", newVariant( (oldBalance: oldBalance, currentBalance: v.currentBalance) ) )

        if compositionName == "FreeSpin":
            v.gameFlow.nextEvent()

            var isFreespinsFailed = v.freeSpinsTotalWin == 0

            if isFreespinsFailed:
                v.notificationCenter.postNotification("mime_play_loose_anim")
            v.freeSpinsTotalWin = 0

        elif compositionName == "BonusGame":
            v.gameFlow.nextEvent()

        if not onDestroy.isNil:
            onDestroy()

    v.removeWinAnimationWindow(true)
    result = v.showGameModeOutro(compositionName, v.popupHolder, toValue, onWinAnimDestroy)

proc showBonusWin(v: EiffelSlotView, moneyWon: int64, callback: proc()) =
    v.slotGUI.moneyPanelModule.setBalance(v.currentBalance - moneyWon, v.currentBalance)
    if not v.fadeAnim.isNil:
        v.fadeAnim.removeFromParent()
        v.notificationCenter.postNotification("chips_animation_bonus", newVariant( (oldBalance: v.currentBalance - moneyWon, currentBalance: v.currentBalance) ) )

    v.winDialogWindow = v.runWinAnimation("BonusGame", moneyWon, callback)

proc getBonusPlaceForAnim(v: EiffelSlotView): tuple[x: int, y: int] =
    var counter = 0
    for i in 0..<NUMBER_OF_REELS:
        for r in 0..<NUMBER_OF_ROWS:
            let index = r * NUMBER_OF_REELS + i
            let val = v.lastField[index]
            if val == Symbols.Bonus.int:
                if counter < 1:
                    inc counter
                else:
                    return indexToPlace(index)

proc startBonusGame(v: EiffelSlotView) =
    let onComplete = proc() =
        v.onBonusGameEnd()
        v.rootNode.alpha = 1.0
        v.slotGUI.winPanelModule.setNewWin(v.bonusWin)

        v.inBonus = false
        v.mimeController.playIdles()
        v.showBonusWin(v.bonusWin) do():
            if v.isInFreeSpins:
                v.soundManager.sendEvent("FREE_SPIN_MUSIC")
            else:
                v.playBackgroundMusic()
            v.soundManager.sendEvent("AMBIENCE")
        v.bonusResult = @[]
        v.soundManager.sendEvent("BONUS_GAME_RESULTS")
        v.prepareGUItoBonus(false)
        v.slotGUI.menuButton.setVisible(true)

    v.inBonus = true
    v.soundManager.stopSFX(1.0)
    v.hideGUI()
    v.prepareGUItoBonus(true)
    v.slotGUI.menuButton.setVisible(false)
    createBonusScene(v, v.totalBet div v.gLines, onComplete)

proc startBonusAnimation(v: EiffelSlotView) =
    v.lastPlayerActivity = epochTime()

    const FADE_TIME = 2.0
    var bonusAnim : MetaAnimation
    let place = v.getBonusPlaceForAnim()
    let symbol = v.reelNodes[place.x].findNode("Field").findNode($(place.y + 1)).findNode("symbol")
    let delayMimeAnim = newAnimation()
    let liftAnimation = symbol.animationNamed("open")
    let cameraAnimation = newAnimation()

    let startCameraTranslation = v.camera.node.position
    let startCameraScale = v.camera.node.scale
    var newCameraTranslation = symbol.localToWorld(newVector3(0, symbolHeight/2 ,startCameraTranslation.z)) #hardcode
    let newCameraScale = newVector3(0.3, 0.3, 1.0)

    delayMimeAnim.loopDuration = 0.5
    delayMimeAnim.numberOfLoops = -1

    cameraAnimation.loopDuration = liftAnimation.loopDuration * 2
    cameraAnimation.numberOfLoops = liftAnimation.numberOfLoops
    cameraAnimation.loopPattern = lpStartToEnd
    cameraAnimation.onAnimate = proc(p: float) =
        v.camera.node.position = interpolate(startCameraTranslation, newCameraTranslation, p)
        v.camera.node.scale = interpolate(startCameraScale, newCameraScale, p)

    cameraAnimation.addLoopProgressHandler 0.9, false, proc()=
        v.soundManager.sendEvent("BONUS_GAME_DOOR")
        v.soundManager.stopAmbient(liftAnimation.loopDuration + FADE_TIME)

    liftAnimation.onComplete do():
        v.fadeAnim = addFadeSolidAnim(v, v.rootNode, blackColor(), v.viewportSize, 0.0, 1.0, FADE_TIME)

        proc startBonusGame() =
            v.notificationCenter.removeObserver("cancel_bonus_game", v)
            v.camera.node.position = startCameraTranslation
            v.camera.node.scale = startCameraScale
            if not v.fadeAnim.isNil:
                v.fadeAnim.removeFromParent()

            v.startBonusGame()
            v.rootNode.alpha = 1.0
            symbol.stopAnimNamed("open")

        v.setTimeout FADE_TIME, proc()=
            startBonusGame()

    bonusAnim = newMetaAnimation(delayMimeAnim, cameraAnimation, liftAnimation)
    bonusAnim.numberOfLoops = 1

    v.soundManager.sendEvent("PRE_BONUS_GAME")

    var onBonusIntroComplete = proc()=
        v.notificationCenter.postNotification("mime_play_win_anim")

        let mimeAnim = v.mimeController.setNextAnimation("bonus", false)
        mimeAnim.addLoopProgressHandler 0.2, true, proc() =
            v.soundManager.sendEvent("FOOTSTEPS_2")

        v.setTimeout 0.1,  proc() =
            v.soundManager.sendEvent("EIFFEL_PRE_BONUS_GAME_MIME_DANCE")
        mimeAnim.onComplete do():
            delayMimeAnim.cancel()

        v.notificationCenter.addObserver("cancel_bonus_game", v, proc(args: Variant) =
            bonusAnim.cancel()
            v.notificationCenter.removeObserver("cancel_bonus_game", v)
            )
        v.addAnimation(bonusAnim)

    discard v.showGameModeIntro("BonusGame", v.popupHolder, onBonusIntroComplete)

proc showFreespinsBG(v: EiffelSlotView, isVisible: bool)=
    var bg = v.rootNode.findNode("BG_Free.png")
    var lil = v.rootNode.findNode("Tower_Free_L")
    var lir = v.rootNode.findNode("Tower_Free_R")
    var lit = v.rootNode.findNode("Tower_Free_T")
    let balpha = if isVisible: 0.0
                         else: 1.0
    let ealpha = if isVisible: 1.0
                         else: 0.0
    var showAnim = newAnimation()
    showAnim.loopDuration = 0.25
    showAnim.numberOfLoops = 1
    showAnim.onAnimate = proc(p: float) =
        bg.alpha  = interpolate(balpha, ealpha, p)
        lil.alpha = interpolate(balpha, ealpha, p)
        lir.alpha = interpolate(balpha, ealpha, p)
        lit.alpha = interpolate(balpha, ealpha, p)
    v.addAnimation(showAnim)

proc startFreeSpinsAnimation(v: EiffelSlotView, showIntro: bool = false) =

    proc startProj4Animation(nodeName: string) =
        let n = v.rootNode.findNode(nodeName)
        let startAnim = n.animationNamed("free_spins")
        let loopAnim = n.animationNamed("loop")
        let endAnim = n.animationNamed("end")


        startAnim.onComplete do():
            v.addAnimation(loopAnim)
        loopAnim.onComplete do():
            v.addAnimation(endAnim)
        v.addAnimation(startAnim)

    discard v.rootNode.findNode("Overlay").component(Overlay)

    var oldPositions = newSeq[Vector3]()
    for i in 0 ..< v.reelNodes.len:
        oldPositions.add(v.reelNodes[i].position)

    v.showFreespinsBG(true)
    v.setSpinButtonState(SpinButtonState.Blocked)
    v.addAnimation(v.rootNode.findNode("Bottom").children[0].animationNamed("sprite"))

    let delay = 0.4
    var startTimeout = 4.0

    var onFreeSpinIntroComplete = proc()=
        startProj4Animation("Proj4_1")
        startProj4Animation("Proj4_2")

        v.setTimeout 0.1, proc() =
            if v.lastField.len > 0:
                for i in 0 ..< NUMBER_OF_REELS:
                    for j in 0 ..< NUMBER_OF_ROWS:
                        let s = v.lastField[j * v.reelNodes.len + i]
                        if s == Symbols.Scatter.int:
                            v.soundManager.sendEvent("PRE_FREE_SPIN")
                            createPigeonAnim(v.reelNodes, v.singleImagesNode, v, i, j)

            v.symbolHighlightController.clearSymbolHighlights()
            for i in 0 ..< v.reelNodes.len:
                closureScope:
                    let index = i
                    let anim  = newAnimation()
                    anim.numberOfLoops = 1
                    anim.loopDuration = delay
                    anim.animate val in v.reelNodes[index].positionY .. oldPositions[index].y:
                        v.reelNodes[index].positionY = val
                    v.addAnimation(anim)

            v.setTimeout delay + 0.1, proc() =
                v.gameFlow.nextEvent()
                v.soundManager.sendEvent("FREE_SPIN_MUSIC")
    if showIntro:
        v.soundManager.sendEvent("FREE_SPIN")
        discard v.showGameModeIntro("FreeSpin", v.popupHolder, onFreeSpinIntroComplete)
    else:
        onFreeSpinIntroComplete()

proc exitFreeSpins(v: EiffelSlotView) =
    v.isInFreeSpins = false
    v.soundManager.sendEvent("FS_RESULT")
    v.winDialogWindow = v.runWinAnimation("FreeSpin", v.freeSpinsTotalWin)
    v.slotGUI.winPanelModule.setNewWin(v.freeSpinsTotalWin, false)
    v.showFreespinsBG(false)
    let tower = v.rootNode.findNode("TOWER")
    let anim = tower.animationNamed("free_spins_exit")
    v.rootNode.findNode("Proj4_1").animationNamed("loop", true).cancel()
    v.rootNode.findNode("Proj4_2").animationNamed("loop", true).cancel()
    v.addAnimation(anim)
    v.freeSpinsOnEnter = false
    v.onFreeSpinsEnd()
    anim.onComplete do():
        let a = tower.animationNamed("spins_back")
        a.loopPattern = LoopPattern.lpEndToStart
        v.addAnimation(a)
        a.onComplete do():
            v.playBackgroundMusic()

proc startRepeatingWinningAnims(v: EiffelSlotView) =

    proc onAnimateLine(line: int) =
        for ln in v.paidLines:
            if ln.index == line:
                for j in 0 ..< ln.winningLine.numberOfWinningSymbols:
                    let vPos = v.lines[ln.index][j]
                    let field = v.linesComponent.reelNodes[j].findNode("Field").childNamed($(vPos + 1))

                    if not field.isNil:
                        let n = field.findNode("symbol")

                        if not n.isNil:
                            let anim = n.animationNamed("play")
                            if not anim.isNil:
                                v.addAnimation(anim)
                break

    v.linesComponent.onAnimateLine = onAnimateLine

proc stopSpin(v: EiffelSlotView) =
    for i, a in v.reelSpinAnimations:
        if not a.isNil: a.cancel()

proc createCharacterNode(sym: Symbols): Node =
    result = newLocalizedNodeWithResource(GENERAL_PREFIX & "eiffel_slot/Characters/" & $sym & "_character.json")

proc createStaticSymbolNode(v: EiffelSlotView, sym: Symbols): Node =
    result = newNode()
    result.component(Sprite).image = v.singleImagesNode.findNode($(sym.int) & "_symbol.png").component(Sprite).image

proc createNodeForSymbol(v: EiffelSlotView, sym: Symbols): Node =
    case sym
    of Symbols.Chef..Symbols.Painter:
        result = createCharacterNode(sym)
        result.position = newVector3(-117, -29)
        if sym == Symbols.Painter:
            result.animationNamed("play").loopDuration -= 0.2
    of Symbols.Wild:
        result = newLocalizedNodeWithResource(GENERAL_PREFIX & "eiffel_slot/precomps/Wild.comp.json")
        result.position = newVector3(-117, -340)
    of Symbols.Bonus: result = newLiftNode()
    of Symbols.Scatter:
        result = newLocalizedNodeWithResource(GENERAL_PREFIX & "eiffel_slot/precomps/CAGE.json")
        result.position = newVector3(-99, -39)
    of Symbols.Ace..Symbols.Nine:
        result = createCharacterNode(sym)
        result.position = newVector3(-128, -45)
        result.animationNamed("play").loopDuration /= 2
    else:
        discard

    let comp = result.component(SymbolComponent)
    comp.sym = sym
    result.name = "symbol"

proc getSymbolFromCache(v: EiffelSlotView, sym: Symbols): Node =
    proc popOrNil[T](s: var seq[T]): T =
        if s.len > 0: result = s.pop()
    if sym in v.cachedSymbols:
        result = v.cachedSymbols[sym].popOrNil()
    if result.isNil:
        result = v.createNodeForSymbol(sym)

proc getSymbolForSpinAnim(v: EiffelSlotView): Symbols =
    result = rand((Symbols.Nine).int).Symbols

proc firstFill(v: EiffelSlotView, n: Node, reelIndex: int, bonuses, scatters: var int) =
    var haveOneBonus = false
    var haveOneScatter = false

    for i in 1..3:
        var symOrRandom = v.getSymbolForSpinAnim()

        if rand(5) == 1 or symOrRandom == Symbols.Bonus:
            if not haveOneBonus and bonuses < 2:
                symOrRandom = Symbols.Bonus
                haveOneBonus = true
                inc bonuses
            else:
                while symOrRandom == Symbols.Scatter or symOrRandom == Symbols.Bonus:
                    symOrRandom = v.getSymbolForSpinAnim()

        if symOrRandom == Symbols.Scatter:
            if haveOneScatter or scatters >= 2:
                while symOrRandom == Symbols.Scatter or symOrRandom == Symbols.Bonus:
                    symOrRandom = v.getSymbolForSpinAnim()
            else:
                haveOneScatter = true
                inc scatters

        let placeholder = n.childNamed($i).findNode("SYMBOL_PLACEHOLDER")
        placeholder.removeAllChildren()
        placeholder.addChild(v.getSymbolFromCache(symOrRandom.Symbols))

proc cancelAuxAnimations(v: EiffelSlotView) =
    for a in v.auxAnimations:
        a.cancel()
    v.auxAnimations.setLen(0)
    v.linesComponent.stopRepeatingLines()

proc onSpinAnimationComplete(v: EiffelSlotView) =

    var allRotSymbols = newSeq[Node]()

    for rotNode in v.rotatingReels:
        for ch in rotNode.children:
            allRotSymbols.add(ch)
        rotNode.removeAllChildren()

    proc popRandomSymbol(): Node =
        # echo allRotSymbols.high, " len ", allRotSymbols.len
        # if allRotSymbols.len == 0: return
        var index = rand(allRotSymbols.high)
        result = allRotSymbols[index]
        allRotSymbols.delete(index)

    for rotNode in v.rotatingReels:
        for i in 0..<NUMBER_OF_ROTATING_NODES:
            var symb = popRandomSymbol()
            rotNode.addChild(symb)
            symb.positionY = i.Coord * symVerticalSpacing

    proc callback()=
        v.cancelAuxAnimations()
        v.gameFlow.start()

    if v.scattersCount > 2 or v.bonusCount > 2:
        v.setTimeout 0.5, callback
    else:
        callback()

proc setHighlights(v:EiffelSlotView, reelIndex: int) =
    let field = v.reelNodes[reelIndex].findNode("Field")

    proc specialHighlight(node, nodePrev: Node) =
        let animNode = node.animationNamed("light")
        let animNodePrev = nodePrev.animationNamed("light")

        animNode.continueUntilEndOfLoopOnCancel = true
        animNodePrev.continueUntilEndOfLoopOnCancel = true

        v.addAnimation(animNode)
        v.addAnimation(animNodePrev)

        v.symbolHighlightController.setSymbolHighlighted(node, true, true)
        v.symbolHighlightController.setSymbolHighlighted(nodePrev, true, true)

    var i = 1

    while true:
        let symNode = field.childNamed($i)
        if symNode.isNil:
            break
        else:
            let symbolIndex = v.lastField[v.reelNodes.len * (i - 1) + reelIndex].Symbols
            if symbolIndex == Symbols.Bonus:
                v.bonusCount.inc()
                v.highlightedBonuses.add(symNode)
                if v.bonusCount == 1 and v.scattersCount == 0:
                    v.infoPanel.showText(IPMessageType.Bonus)
                if v.bonusCount >= 2:
                    specialHighlight(symNode, v.highlightedBonuses[0])
            elif symbolIndex == Symbols.Scatter:
                v.scattersCount.inc()
                v.highlightedScatters.add(symNode)
                if v.scattersCount == 1 and v.bonusCount == 0:
                    if v.isInFreeSpins:
                        v.infoPanel.showText(IPMessageType.ScatterInFreeSpins)
                    else:
                        v.infoPanel.showText(IPMessageType.Scatter)
                if v.scattersCount >= 2:
                    specialHighlight(symNode, v.highlightedScatters[0])
            inc i

            if v.bonusCount >= 3 or (v.scattersCount >= 3 and not v.isInFreeSpins):
                v.soundManager.stopMusic( (NUMBER_OF_REELS - reelIndex).float * 1.5)

    for i, ln in v.paidLines:
        for j in 0 ..< ln.winningLine.numberOfWinningSymbols:
            # closureScope:
            let vPos = v.lines[ln.index][j]
            let n = v.reelNodes[j].findNode("Field").childNamed($(vPos + 1))

            if reelIndex == j:
                if j == 0:
                    v.firstWinningSymbols.add(n)
                # else:
                v.symbolHighlightController.setSymbolHighlighted(n, true)
                for s in v.firstWinningSymbols:
                    v.symbolHighlightController.setSymbolHighlighted(s, true)

proc fillReelWithSpinResults(v: EiffelSlotView, reelIndex: int) =
    let field = v.reelNodes[reelIndex].findNode("Field")
    doAssert(v.lastField.len > 0)

    var i = 1
    while true:
        let symNode = field.childNamed($i)
        if symNode.isNil:
            break
        else:
            let placeholder = symNode.findNode("SYMBOL_PLACEHOLDER")
            let symbolIndex = v.lastField[v.reelNodes.len * (i - 1) + reelIndex]

            placeholder.removeNodeChildrenAndPutSymbolsToCache(v)
            placeholder.addChild(v.getSymbolFromCache(symbolIndex.Symbols))
            inc i

proc allocateRandomSymNode(v: EiffelSlotView): Node =
    let randomSymbol = v.getSymbolForSpinAnim()
    result = newLocalizedNodeWithResource(GENERAL_PREFIX & "eiffel_slot/precomps/SYMBOL_CONTAINER.json")
    result.findNode("PivotOffset").removeComponent(ChannelLevels)
    result.findNode("SYMBOL_PLACEHOLDER").addChild(v.createNodeForSymbol(randomSymbol))

proc prepareRotatingNodes(v: EiffelSlotView) =
    v.rotatingReels = @[]
    for i in 0..<NUMBER_OF_REELS:

        var rotNode = v.rootNode.findNode("reelsClip").newChild("rotNode_" & $i)
        rotNode.position = v.reelNodes[i].position

        for s in 0..<NUMBER_OF_ROTATING_NODES:
            var ch = v.allocateRandomSymNode()
            # discard ch.component(AlphaBlur)
            rotNode.addChild(ch)
            ch.position = newVector3(0, s.Coord * symVerticalSpacing, 0)

        rotNode.alpha = 0.0
        v.rotatingReels.add(rotNode)

proc addThrillHighlightToReel(v: EiffelSlotView, reelIndex: int) =
    if v.reelHighlightNode.isNil:
        v.reelHighlightNode = newLocalizedNodeWithResource(GENERAL_PREFIX & "eiffel_slot/precomps/Highlight2.json")
    v.reelHighlightNode.position = newVector3(700 + 202.5 * reelIndex.Coord, 1080)
    discard v.reelHighlightNode.component(Overlay)
    v.rootNode.findNode("reelsParent").addChild(v.reelHighlightNode)

    if v.riser.isNil:
        v.riser = v.soundManager.playSFX(SOUND_PATH_PREFIX & "riser")
        v.riser.trySetLooping(true)
    v.addAnimation(v.reelHighlightNode.animationNamed("loop"))

proc startAnimationForReel(v: EiffelSlotView, reelIndex: int) =
    var maxDuration = 5.0

    let rotNode = v.rotatingReels[reelIndex]
    let reelNode = v.reelNodes[reelIndex]
    let spinRotNode = reelNode.findNode("SpinRoot")
    var startAnim = reelNode.animationNamed("start")
    let loopTicAnim = reelNode.animationNamed("loopTic")
    let loopTacAnim = reelNode.animationNamed("loopTac")
    let stopAnim = reelNode.animationNamed("end")

    rotNode.alpha = 1.0
    var startRotY = spinRotNode.worldPos().y
    if reelNode.positionY < 200 or reelNode.positionY > 400:
        # We have started free spins and the node is somewhere out of screen.
        # Start animation has to be changed
        startAnim = newAnimation()
        startAnim.numberOfLoops = 1
        startAnim.loopDuration = 0.2
        reelNode.positionY = 280
        startRotY = -800
        startAnim.animate val in -800.0 .. 1111.0:
            spinRotNode.positionY = val

    startAnim.continueUntilEndOfLoopOnCancel = true
    loopTicAnim.continueUntilEndOfLoopOnCancel = true
    loopTacAnim.continueUntilEndOfLoopOnCancel = true
    stopAnim.continueUntilEndOfLoopOnCancel = true

    rotNode.positionY = -(NUMBER_OF_ROTATING_NODES * symVerticalSpacing) + startRotY

    var rotStep = spinRotNode.worldPos().y
    var startRotAnim = newAnimation()
    startRotAnim.loopDuration = startAnim.loopDuration
    startRotAnim.numberOfLoops = startAnim.numberOfLoops
    startRotAnim.onAnimate = proc(p: float)=
        var curStep = spinRotNode.worldPos().y
        var diff = curStep - rotStep
        rotStep = curStep
        rotNode.positionY = rotNode.positionY + diff

        for child in rotNode.children:
            let childPos = child.worldPos()
            if childPos.y > v.viewportSize.height or childPos.y < 0:
                child.alpha = 0.0
            else:
                child.alpha = 1.0

    v.reelSpinAnimations[reelIndex] = startAnim

    var field = reelNode.findNode("Field")

    for i in 1..3:
        var symb = field.findNode($i).findNode("symbol")
        symb.stopAnimNamed("play")

    var rotationSpeed = v.rotationBaseSpeed.Coord  * symVerticalSpacing
    var rotationBoostedSpeed = rotationSpeed * 1.5

    var prevP: float = 0
    var prevLoop: int = 0

    let rotationAnim = v.rotationAnims[reelIndex]
    rotationAnim.onAnimate = proc(p: float) =
        var delta = p - prevP
        var deltaLoop = rotationAnim.curLoop - prevLoop

        if p < prevP:
            delta += float(deltaLoop)
        prevP = p
        prevLoop = rotationAnim.curLoop

        var offsetSpeed: Coord
        if not v.rotationAnimBoosted[reelIndex]:
            offsetSpeed += delta * rotationSpeed
        else:
            offsetSpeed += delta * rotationBoostedSpeed

        for child in rotNode.children:
            child.positionY = child.positionY + offsetSpeed
            let childPos = child.worldPos()
            if childPos.y > symVerticalSpacing * 5:
                child.positionY = child.positionY - symVerticalSpacing * NUMBER_OF_ROTATING_NODES
            if childPos.y > v.viewportSize.height or childPos.y < 0:
                child.alpha = 0.0
            else:
                child.alpha = 1.0

    startAnim.onComplete do():
        reelNode.alpha = 0.0
        startRotY = reelNode.positionY
        v.addAnimation(rotationAnim)
        if v.actionButtonState == SpinButtonState.ForcedStop:
            rotationAnim.cancel()
        else:
            v.reelSpinAnimations[reelIndex] = rotationAnim

    let animTop = v.rootNode.findNode("TOWER_RED_TOP").animationNamed("start")
    let animBottom = v.rootNode.findNode("TOWER_RED_BOTTOM").animationNamed("start")

    var stopRotAnim = newAnimation()
    const stopFromY = -1149.Coord
    rotationAnim.onComplete do():
        v.notificationCenter.postNotification("EiffelReelsStartStoping")
        const reelHeight = 3

        const stopToY = stopFromY + (symVerticalSpacing * reelHeight.Coord)
        var neeresToStop = 0.Coord
        var childMoved = 0
        for i, ch in rotNode.children:
            let wp = ch.worldPos()
            if wp.y > stopFromY and wp.y < stopToY and childMoved < reelHeight:
                if neeresToStop == 0:
                    neeresToStop = wp.y - stopFromY
                    rotNode.positionY = rotNode.positionY - neeresToStop
                ch.positionY = stopFromY * i.Coord
                inc childMoved

        reelNode.alpha = 1.0
        spinRotNode.positionY = stopFromY
        rotStep = stopFromY
        v.addAnimation(stopRotAnim)
        v.addAnimation(stopAnim)
        v.setTimeout 0.3, proc() =
            v.soundManager.sendEvent("SPIN_STOP" & $rand(1..3))
            if reelIndex == NUMBER_OF_REELS - 1:
                if not v.spinSound.isNil:
                    v.spinSound.stop()

        if reelIndex < NUMBER_OF_REELS - 1 and v.rotationAnimBoosted[reelIndex+1]:
            v.removeThrillHighlights()
            v.addThrillHighlightToReel(reelIndex + 1)

            let state = v.getStateForStopAnim()

            if state == WinConditionState.Scatter or state == WinConditionState.Bonus:
                if not v.isRedAnimActive:
                    animTop.loopPattern = LoopPattern.lpStartToEnd
                    animBottom.loopPattern = LoopPattern.lpStartToEnd
                    v.addAnimation(animTop)
                    v.addAnimation(animBottom)
                    v.isRedAnimActive = true

        v.reelSpinAnimations[reelIndex] = stopAnim
        v.fillReelWithSpinResults(reelIndex)

        let incoming = v.reelNodes[reelIndex].findNode("Field")
        for n in incoming.children:
            v.addAnimation(n.animationNamed("shake"))

    stopRotAnim.loopDuration = stopAnim.loopDuration
    stopRotAnim.numberOfLoops = stopAnim.numberOfLoops
    stopRotAnim.onAnimate = proc(p: float)=
        var curStep = spinRotNode.worldPos().y
        var diff = curStep - rotStep
        rotStep = curStep
        rotNode.positionY = rotNode.positionY + diff

        for i, ch in rotNode.children:
            let wp = ch.worldPos()
            if wp.y > v.viewportSize.height or wp.y < symVerticalSpacing:
                ch.alpha = 0.0
            else:
                ch.alpha = 1.0

    stopAnim.onComplete do():
        var endT = epochTime()
        stopRotAnim.cancel()
        if reelIndex < NUMBER_OF_REELS:
            v.setHighlights(reelIndex)

        rotNode.alpha = 0.0

        v.reelSpinAnimations[reelIndex] = nil
        v.rotationAnims[reelIndex] = nil

        v.ropesAnims[reelIndex].cancel()
        var allFinished = true
        for a in v.reelSpinAnimations:
            if not a.isNil:
                allFinished = false
                break
        if allFinished:

            if not v.riser.isNil:
                v.soundManager.sendEvent("LOOSE")
                v.riser.stop()
                v.riser = nil

            v.removeThrillHighlights()
            for i in 0..<NUMBER_OF_REELS:
                v.rotationAnimBoosted[i] = false
            if v.isRedAnimActive:
                animTop.loopPattern = LoopPattern.lpEndToStart
                v.addAnimation(animTop)
                animBottom.loopPattern = LoopPattern.lpEndToStart
                v.addAnimation(animBottom)
            v.animSettings = @[]
            v.onSpinAnimationComplete()

    v.addAnimation(startAnim)
    v.addAnimation(startRotAnim)

method assetBundles*(v: EiffelSlotView): seq[AssetBundleDescriptor] =
    const allAssetBundles = [
        assetBundleDescriptor("slots/eiffel_slot/eiffel_bonus"),
        assetBundleDescriptor("slots/eiffel_slot/eiffel_bonus_chef"),
        assetBundleDescriptor("slots/eiffel_slot/eiffel_messages"),
        assetBundleDescriptor("slots/eiffel_slot/eiffel_mime"),
        assetBundleDescriptor("slots/eiffel_slot/eiffel_paytable"),
        assetBundleDescriptor("slots/eiffel_slot/eiffel_slot"),
        assetBundleDescriptor("slots/eiffel_slot/eiffel_sound")
    ]
    result = @allAssetBundles

proc startSpinAnimation(v: EiffelSlotView) =
    v.cancelAuxAnimations()

    for i in 0 ..< v.reelNodes.len:
        let rotationAnim = newAnimation()
        rotationAnim.numberOfLoops = -1
        rotationAnim.loopDuration = 0.5
        rotationAnim.continueUntilEndOfLoopOnCancel = false
        v.rotationAnims[i] = rotationAnim

    v.bonusCount = 0
    v.scattersCount = 0
    v.highlightedBonuses = @[]
    v.highlightedScatters = @[]

    v.firstWinningSymbols = @[]

    v.auxAnimations.add(v.rootNode.findNode("Bottom").children[0].animationNamed("sprite"))
    v.auxAnimations.add(v.rootNode.findNode("Top").children[0].animationNamed("sprite"))
    v.auxAnimations.add(v.rootNode.findNode("Wheel1").children[0].animationNamed("sprite"))
    v.auxAnimations.add(v.rootNode.findNode("Wheel2").children[0].animationNamed("sprite"))
    v.auxAnimations.add(v.rootNode.findNode("Wheel3").children[0].animationNamed("sprite"))
    v.auxAnimations.add(v.rootNode.findNode("Wheel4").children[0].animationNamed("sprite"))

    v.ropesAnims = @[]
    for i in 0 .. v.reelNodes.len - 1:
        closureScope:
            let ropesAnim = newAnimation()
            let index = i

            ropesAnim.animate val in 0.0 .. 1.0:
                v.ropeAnimationOffset[index] = val
            v.auxAnimations.add(ropesAnim)
            v.ropesAnims.add(ropesAnim)

    for a in v.auxAnimations:
        v.addAnimation(a)

    var i = 0
    var t: ControlledTimer
    t = v.setInterval(0.2, proc() =
        if i < v.reelNodes.len:
            v.startAnimationForReel(i)
        inc i
        if i >= v.reelNodes.len:
            v.pauseManager.clear(t)
        )

proc removeThrillHighlights(v: EiffelSlotView) =
    if not v.reelHighlightNode.isNil and not v.reelHighlightNode.parent.isNil:
        v.reelHighlightNode.animationNamed("loop").cancel()
        v.reelHighlightNode.removeFromParent()

proc onSpinResponse(v: EiffelSlotView) =
    var state = v.getStateForStopAnim()
    #echo "STATE ", state
    var reelsInfo = (bonusReels: @[0, 1, 2, 3, 4], scatterReels: @[0, 1, 2, 3, 4])
    v.setRotationAnimSettings(ReelsAnimMode.Long, state, reelsInfo)

    for i in 0..<NUMBER_OF_REELS:
        v.rotationAnimBoosted[i] = v.animSettings[i].boosted
        closureScope:
            let index = i
            let currTime = v.animSettings[index].time
            let anim = v.rotationAnims[index]
            v.setTimeout currTime, proc() =
                if not anim.isNil:
                    if anim.startTime > 0:
                        anim.cancel()
                    else:
                        anim.curLoop = 0
                        anim.numberOfLoops = 1

    let win = v.getPayoutForLines()

    if v.actionButtonState == SpinButtonState.ForcedStop:
        v.stopSpin()
    else:
        v.setSpinButtonState(SpinButtonState.Stop)


    var notifCenter = v.notificationCenter
    notifCenter.removeObserver("mime_play_win_anim", v)
    notifCenter.removeObserver("chips_animation", v)
    notifCenter.removeObserver("mime_play_loose_anim", v)
    notifCenter.removeObserver("EiffelReelsStartStoping", v)

    notifCenter.addObserver("mime_play_win_anim", v, proc(args: Variant)=
        notifCenter.removeObserver("mime_play_win_anim", v)
        let anim = v.mimeController.setImmediateAnimation("bingo")
        anim.addLoopProgressHandler 0.2, true, proc() =
            v.soundManager.sendEvent("FOOTSTEPS_1")
        )

    notifCenter.addObserver("mime_play_loose_anim", v, proc(args: Variant)=
        notifCenter.removeObserver("mime_play_loose_anim", v)
        v.mimeController.setImmediateAnimation("sad")
        )

    notifCenter.addObserver("chips_animation", v, proc(args: Variant)=
        notifCenter.removeObserver("chips_animation", v)
        var (oldBalance, currentBalance) = args.get(tuple[oldBalance:int64, currentBalance:int64])
        v.chipsAnim(v.rootNode.findNode("total_bet_panel"), oldBalance, currentBalance, "Spin")
        )

    notifCenter.addObserver("chips_animation_bonus", v, proc(args: Variant)=
        notifCenter.removeObserver("chips_animation_bonus", v)
        var (oldBalance, currentBalance) = args.get(tuple[oldBalance:int64, currentBalance:int64])
        v.chipsAnim(v.rootNode.findNode("total_bet_panel"), oldBalance, currentBalance, "Bonus")
        )

    notifCenter.addObserver("EiffelReelsStartStoping", v, proc(args: Variant)=
        notifCenter.removeObserver("EiffelReelsStartStoping", v)
        v.infoPanel.removeTotalWinAnim()
        if v.isInFreeSpins and v.freeSpinsLeft == 1:
            v.soundManager.stopMusic()
        )

proc sendSpinRequest(v: EiffelSlotView) =
    const serverSpinResponseTimeout = 8.0 # If the server does not reply within this value, the game is likely to exit.
    const minStopTimeout = 1.5 # Stop button will be enabled as soon as server replies but not sooner than this value.

    var stopTimeoutElapsed = false
    var autoStopTimeoutElapsed = false

    if v.stage == GameStage.Freespin or v.stage == GameStage.Respin:
        v.rotateSpinButton(v.slotGUI.spinButtonModule)

    v.paidLines = @[]
    v.lastField = @[]
    v.sendSpinRequest(v.totalBet) do(res: JsonNode):
        var stages = res[$srtStages]
        let firstStage = stages[0]
        for j in firstStage[$srtField].items:
            v.lastField.add(j.getInt().int8)

        v.paidLines = firstStage[$srtLines].parsePaidLines()

        # for item in firstStage[$srtLines].items:
        #     let line = PaidLine.new()
        #     line.winningLine.numberOfWinningSymbols = item["symbols"].getInt()
        #     line.winningLine.payout = item["payout"].getInt()
        #     line.index = item["index"].getInt()
        #     v.paidLines.add(line)

        let oldChips = currentUser().chips
        let nFc = res[$srtFreespinCount].getInt()

        if v.isInFreeSpins and v.freeSpinsLeft < nFc:
            v.nextFreeSpinsLeft = nFc
        else:
            v.freeSpinsLeft = nFc

        for stage in stages:
            if stage[$srtStage].str == "Bonus":
                v.bonusResult = @[]
                v.slotBonuses.inc()
                v.lastActionSpins = 0

                let spinsFromLast = saveNewBonusgameLastSpins(v.name)
                sharedAnalytics().bonusgame_start(v.name, v.slotSpins, v.totalBet, currentUser().chips, spinsFromLast)
                for st in stage[$srtField].items:
                    v.bonusResult.add(st.getInt())
                v.bonusWin = stage[$srtPayout].getBiggestInt()
            elif stage[$srtStage].str == "FreeSpin":
                v.freeSpinsTotalWin = stage[$srtFreespinTotalWin].getBiggestInt()
                v.stage = GameStage.FreeSpin
            elif stage[$srtStage].str == "Spin":
                v.stage = GameStage.Spin

        var spent = v.totalBet
        var win: int64 = 0

        currentUser().chips = res[$srtChips].getBiggestInt()
        if v.stage == GameStage.FreeSpin or v.freeRounds:
            spent = 0
        if currentUser().chips > oldChips - spent:
            win = currentUser().chips - oldChips + spent

        v.spinAnalyticsUpdate(win, v.stage == GameStage.FreeSpin)

        if stopTimeoutElapsed:
            v.onSpinResponse()

        if "introWin" in res:
            if res["introWin"].getBool() == true:
                v.slotGUI.rootNode.removeFromParent()
                v.setTimeout 3.0, proc() =
                    discard #currentDirector().moveTo("intro-2", SceneChangeMode.FreeAll, false)

    v.setTimeout minStopTimeout, proc() =
        if v.lastField.len > 0:
            v.onSpinResponse()
        stopTimeoutElapsed = true

proc startSpin(v: EiffelSlotView) =
    v.totalWin = 0
    v.bonusWin = 0
    v.removeWinAnimationWindow(true)
    v.linesComponent.stopRepeatingLines()
    v.linesComponent.resetLines()
    v.symbolHighlightController.clearSymbolHighlights()

    v.lastPlayerActivity = epochTime()

    if v.freeSpinsLeft == 0 and not v.isInFreeSpins and not v.freeRounds:
        if not currentUser().withdraw(v.totalBet):
            var retrySpin = proc() =
                if currentUser().withdraw(v.totalBet):
                    v.startSpin()
            v.setSpinButtonState(SpinButtonState.Spin)
            v.slotGUI.outOfCurrency("chips", retrySpin)
            return

        let beforeSpinChips = currentUser().chips
        v.setTimeout 0.5, proc() =
            v.slotGUI.moneyPanelModule.setBalance(beforeSpinChips, beforeSpinChips - v.totalBet, false)

    v.spinSound = v.soundManager.playSFX(SOUND_PATH_PREFIX & "spin")
    if not v.spinSound.isNil:
        v.spinSound.trySetLooping(true)

    v.setTimeout 1.0, proc() =
        if v.freeSpinsLeft > 0 and v.isInFreeSpins:
            v.infoPanel.showText(IPMessageType.FreeSpinsLeft, v.freeSpinsLeft)
        else:
            discard v.infoPanel.showRandomText()

    let mimePush = v.mimeController.setImmediateAnimation("push_spin")
    mimePush.addLoopProgressHandler 0.5, true, proc() =
        v.soundManager.sendEvent("AIR_BUTTON")
    mimePush.onComplete do():
            let rnd = rand(1..2)

            if rnd == 1:
                v.mimeController.setImmediateAnimation("idle_spin" & $rnd)
            else:
                let back = v.mimeController.setImmediateAnimation("back_idle", false)
                back.loopPattern = lpEndToStart
                back.onComplete do():
                    let idleSpin = v.mimeController.setImmediateAnimation("idle_spin" & $rnd, false)
                    idleSpin.onComplete do():
                        let backEnd = v.mimeController.setImmediateAnimation("back_idle")
                        backEnd.loopPattern = lpStartToEnd

    v.setSpinButtonState(SpinButtonState.Blocked)
    v.sendSpinRequest()
    v.startSpinAnimation()

proc lightClusterTower(op: Point, rot:bool, dir:bool, arr: auto): LightsCluster =
    result.new()
    result.count = arr.len
    result.coords = proc(i:int): Point =
        var p = if dir: arr[i]
                  else: arr[arr.len - 1 - i]
        p.x = if rot: p.x
                  else: p.x * -1
        result = p
        result.x += op.x
        result.y += op.y

proc createLightClusters(v: EiffelSlotView): Node =
    result = newNode()
    const leftP = newPoint(29,29)
    const rightP = newPoint(1920-29,29)

    v.lightClusters[LightAnims.towerLeft.int] = lightClusterTower(rightP, rot = false, dir = true, tower_lights_coords)
    v.lightClusters[LightAnims.towerRight.int] = lightClusterTower(leftP,  rot = true,  dir = true, tower_lights_coords)
    v.lightClusters[LightAnims.towerMidLeft.int] = lightClusterTower(rightP, rot = false, dir = false, tower_lights_mid_coords)
    v.lightClusters[LightAnims.towerMidRight.int] = lightClusterTower(leftP,  rot = true,  dir = false, tower_lights_mid_coords)
    v.lightClusters[LightAnims.towerMidLeftReverse.int] = lightClusterTower(rightP, rot = false, dir = true, tower_lights_mid_coords)
    v.lightClusters[LightAnims.towerMidRightReverse.int] = lightClusterTower(leftP,  rot = true,  dir = true, tower_lights_mid_coords)

    result.setComponent "lightClusters", newComponentWithDrawProc(proc() =
        for anim in v.lightClusters:
            if not anim.isNil: anim.draw()
    )

proc addSwitcher(v: EiffelSlotView) =
    let switcher = v.rootNode.newChild("switcher")
    let sprite = switcher.component(Sprite)

    sprite.image = v.singleImagesNode.findNode("Switch.png").component(Sprite).image
    switcher.position = newVector3(1550, 689)

method onSpinClick*(v: EiffelSlotView) =
    procCall v.BaseMachineView.onSpinClick()
    if not v.removeWinAnimationWindow(false): return
    if not v.winDialogWindow.isNil:
        v.winDialogWindow.EiffelWinDialogWindow.skip()
    if v.actionButtonState == SpinButtonState.Stop:
        v.setSpinButtonState(SpinButtonState.Blocked)
        v.stopSpin()
    elif v.actionButtonState == SpinButtonState.Spin:
        v.startSpin()
        v.soundManager.sendEvent("TRIGGER")
    elif v.actionButtonState == SpinButtonState.StopAnim:
        v.setSpinButtonState(SpinButtonState.Blocked)
    elif v.actionButtonState == SpinButtonState.Blocked:
        v.setSpinButtonState(SpinButtonState.ForcedStop)

    v.notificationCenter.postNotification("cancel_bonus_game")

    v.linesComponent.clearAnimation(proc()=
        v.slotGUI.winPanelModule.setNewWin(v.totalWin, false)
        )

method clickScreen(v: EiffelSlotView) =
    v.lastPlayerActivity = epochTime()
    v.notificationCenter.postNotification("cancel_bonus_game")
    if v.removeWinAnimationWindow(false):
        if v.slotGUI.autospinsSwitcherModule.isOn:
            v.onSpinClick()
    else:
        if not v.winDialogWindow.isNil:
            v.winDialogWindow.EiffelWinDialogWindow.skip()
        discard v.makeFirstResponder()

proc setLinesComponent(v: EiffelSlotView) =
    let lines = v.rootNode.findNode("lines_unique").component(LinesComponent)
    lines.reelNodes = v.reelNodes
    lines.symbolHighlightController = v.symbolHighlightController
    lines.view = v

    lines.lineCoords = newSeq[seq[Point]]()
    for i in 0 ..< 20:
        var ln = newSeq[Point]()
        ln.add(v.centerOfSymbolInReel(v.lines[i][0], 0))
        ln[0].x += - symbolWidth / 2 + 10
        for r in 0 ..< v.reelNodes.len:
            ln.add(v.centerOfSymbolInReel(v.lines[i][r], r))
        ln.add(v.centerOfSymbolInReel(v.lines[i][v.reelNodes.len - 1], v.reelNodes.len - 1))
        ln[^1].x += symbolWidth / 2
        lines.lineCoords.add(ln)

proc showWinLines(v: EiffelSlotView)=
    v.setSpinButtonState(SpinButtonState.Blocked)
    v.totalWin = v.getPayoutForLines()

    let oldBalance = v.currentBalance - v.totalWin - v.bonusWin
    let linesComp = v.linesComponent

    for sym in v.highlightedBonuses:
        linesComp.symbolHighlightController.setSymbolHighlighted(sym, false)
        sym.animationNamed("light").cancel()
    for sym in v.highlightedScatters:
        linesComp.symbolHighlightController.setSymbolHighlighted(sym, false)
        sym.animationNamed("light").cancel()

    if v.totalWin > 0:
        v.roundWin += v.totalWin
        v.soundManager.sendEvent("APPLAUSE")
        linesComp.startAnimation()
        v.setSpinButtonState(SpinButtonState.StopAnim)

        v.pushLightAnims({LightAnims.towerLeft..LightAnims.towerRight, LightAnims.towerMidLeft..LightAnims.towerMidRight})
        v.playLightAnims(dur= 1.0)
        v.notificationCenter.postNotification("chips_animation", newVariant( (oldBalance: oldBalance, currentBalance: v.currentBalance - v.bonusWin)))
    else:
        v.gameFlow.nextEvent()

    if (v.scattersCount == 2 and v.bonusCount < 3) or (v.scattersCount == 2 and v.bonusCount < 2):
        v.notificationCenter.postNotification("mime_play_loose_anim")

    v.isRedAnimActive = false

    linesComp.onLinesAnimationComplete = proc() =
        v.slotGUI.winPanelModule.setNewWin(v.totalWin)
        v.startRepeatingWinningAnims()
        v.gameFlow.nextEvent()

    if v.getWinType() > WinType.Simple:
        linesComp.linesAnimation.addLoopProgressHandler( 0.2, true, proc()=
            v.notificationCenter.postNotification("mime_play_win_anim")
        )

proc showSpecialWin(v: EiffelSlotView)=
    let winType = v.getWinType()
    var special = false
    var delay: float

    proc callback()=
        v.gameFlow.nextEvent()
        if special:
            v.setTimeout delay, proc()=
                if v.isInFreeSpins:
                    v.soundManager.sendEvent("FREE_SPIN_MUSIC")
                else:
                    v.playBackgroundMusic()

    if winType == WinType.Jackpot:
        var winAnim = v.runWinAnimation("JACKPOT ANIMATION", v.totalWin, callback)
        special = true
        v.winDialogWindow = winAnim
        v.soundManager.sendEvent("JACKPOT")
        v.addAnimation(winAnim.node.findNode("rotatingChip").animationNamed("sprite"))
        v.pushLightAnims({LightAnims.towerLeft..LightAnims.towerRight, LightAnims.towerMidLeft..LightAnims.towerMidRight})
        v.playLightAnims(dur= 1.0)
        v.soundManager.stopMusic()
    elif winType > WinType.FiveInARow:
        special = true

        var bwt = BigWinType.Big
        if v.totalWin >= v.multMega * v.totalBet:
            bwt = BigWinType.Mega
        elif v.totalWin >= v.multHuge * v.totalBet:
            bwt = BigWinType.Huge

        v.onBigWinHappend(bwt, currentUser().chips - v.totalWin)
        v.winDialogWindow = v.showSpecialWin(v.popupHolder, v.totalWin, winType, callback)
        v.pushLightAnims({LightAnims.towerLeft..LightAnims.towerRight, LightAnims.towerMidLeft..LightAnims.towerMidRight})
        v.playLightAnims(dur= 1.0)
        delay = 3.0
        v.soundManager.stopMusic()
    elif winType == WinType.FiveInARow:
        special = true
        v.winDialogWindow = v.showFiveInARow(v.popupHolder, callback)
        v.pushLightAnims({LightAnims.towerLeft..LightAnims.towerRight, LightAnims.towerMidLeft..LightAnims.towerMidRight})
        v.playLightAnims(dur= 1.0)
        delay = 2.0
        v.soundManager.sendEvent("FIVE")
    else:
        callback()

proc showBonusGame(v: EiffelSlotView)=
    if v.bonusResult.len != 0:
        v.pushLightAnims({LightAnims.towerLeft..LightAnims.towerRight, LightAnims.towerMidLeft..LightAnims.towerMidRight})
        v.playLightAnims(dur= 1.0)
        v.startBonusAnimation()
        v.roundWin += v.bonusWin
        v.infoPanel.showText(IPMessageType.WinBonus)
    else:
        var oldBalance = v.currentBalance - v.totalWin - v.bonusWin
        v.gameFlow.nextEvent()

proc showFreespins(v: EiffelSlotView)=
    var enterFreeSpins = false
    var showIntro = false
    if (v.freeSpinsLeft > 0 and not v.isInFreeSpins) or (v.freeSpinsLeft < v.nextFreeSpinsLeft):
        if v.freeSpinsLeft < v.nextFreeSpinsLeft:
            v.freeSpinsLeft = v.nextFreeSpinsLeft
        showIntro = true

        v.nextFreeSpinsLeft = 0
        v.isInFreeSpins = true
        enterFreeSpins = true

    if enterFreeSpins:
        v.startFreeSpinsAnimation(showIntro)
        v.pushLightAnims({LightAnims.towerLeft..LightAnims.towerRight, LightAnims.towerMidLeft..LightAnims.towerMidRight})
        v.playLightAnims(dur= 1.0)
        if not v.freeSpinsOnEnter:
            v.freespinsTriggered.inc()
            v.lastActionSpins = 0

            let spinsFromLast = saveNewFreespinLastSpins(v.name)
            sharedAnalytics().freespins_start(v.name, v.slotSpins, v.totalBet, currentUser().chips, spinsFromLast)
        v.slotGUI.spinButtonModule.startFreespins(v.freeSpinsLeft)
    elif v.isInFreeSpins:
        dec v.freeSpinsLeft
        v.slotGUI.spinButtonModule.setFreespinsCount(v.freeSpinsLeft)
        if v.freeSpinsLeft == 0:
            v.setSpinButtonState(SpinButtonState.Blocked)
            v.slotGUI.spinButtonModule.stopFreespins()
            v.exitFreeSpins()
        elif v.freeSpinsLeft > 0:
            v.gameFlow.nextEvent()
    else:
        v.gameFlow.nextEvent()

proc spinReady(v: EiffelSlotView)=

    # v.slotGUI.winPanelModule.setNewWin(v.totalWin)

    if v.freeSpinsLeft > 0 and v.isInFreeSpins:
        if v.roundWin > 0 and (v.totalWin > 0 or v.bonusWin > 0):
            v.infoPanel.showText(IPMessageType.Win, v.roundWin)

        v.setTimeout BETWEEN_SPINS_TIMEOUT, proc()=
            v.setSpinButtonState(SpinButtonState.Spin)
            if not v.slotGUI.autospinsSwitcherModule.isOn:
                v.startSpin()

    else:
        if v.stage == GameStage.FreeSpin:
            v.stage = GameStage.Spin
        v.setSpinButtonState(SpinButtonState.Spin)
        if v.roundWin > 0:
            v.infoPanel.showText(IPMessageType.Win, v.roundWin)

        v.roundWin = 0
        v.startIdleAnimations()

        v.showInactiveText()

proc initGameFlow(v: EiffelSlotView)=
    proc gameFlow_Respins(args: Variant)=
        v.gameFlow.nextEvent()

    let notif = v.notificationCenter

    notif.addObserver("GF_SPIN", v) do(args: Variant):
        # v.slotGUI.updateQuestProgress()
        v.spinReady()

    notif.addObserver("GF_SHOW_WIN", v) do(args: Variant):
        v.showWinLines()

    notif.addObserver("GF_SPECIAL", v) do(args: Variant):
        v.showSpecialWin()

    notif.addObserver("GF_BONUS", v) do(args: Variant):
        v.showBonusGame()

    notif.addObserver("GF_RESPINS", v, gameFlow_Respins)

    notif.addObserver("GF_FREESPINS", v) do(args: Variant):
        v.showFreespins()

    if currentUser().isCheater():
        notif.addObserver($srtChips, v) do(args: Variant):
            let jn = args.get(JsonNode)
            if jn.hasKey($srtChips):
                let chips = jn[$srtChips].getInt()
                v.slotGUI.moneyPanelModule.setBalance(v.currentBalance, chips)
                currentUser().updateWallet(chips)

        notif.addObserver("spin", v) do(args: Variant):
            let jn = args.get(JsonNode)
            if jn.hasKey($srtSuccess) and jn[$srtSuccess].getBool():
                v.onSpinClick()

    notif.addObserver("GF_LEVELUP", v, proc(args: Variant) =
        let cp = proc() = v.gameFlow.nextEvent()

        if v.stage == GameStage.Spin:
            runFirstTask10TimesSpinAnalytics(v.getRTP().float32, currentUser().chips.int64, v.totalBet().int, v.name, v.getActiveTaskProgress())
        let spinFlow = findActiveState(SpinFlowState)
        if not spinFlow.isNil:
            spinFlow.pop()
        let state = newFlowState(SlotNextEventFlowState, newVariant(cp))
        pushBack(state)
        )

method viewOnEnter*(v: EiffelSlotView)=
    procCall v.BaseMachineView.viewOnEnter()
    v.initGameFlow()

    v.soundManager = newSoundManager(v)
    v.soundManager.loadEvents(SOUND_PATH_PREFIX & "eiffel", "common/sounds/common")
    v.mimeController.playIdles()
    v.showInactiveText()

    v.mimeController.curAnimation.tag = ACTIVE_SOFT_PAUSE

    v.playBackgroundMusic()
    v.soundManager.sendEvent("AMBIENCE")

    v.setLinesComponent()
    v.startIdleAnimations()
    initWinDialogs()

method viewOnExit*(v: EiffelSlotView)=
    # if not v.inBonus:
    # sharedNotificationCenter().removeObserver(v)
    clearWinDialogsCache()
    procCall v.BaseMachineView.viewOnExit()

method restoreState*(v: EiffelSlotView, res: JsonNode) =
    procCall v.BaseMachineView.restoreState(res)

    if res.hasKey("paytable"):
        var pd: EiffelPaytableServerData
        let paytable = res["paytable"]
        if paytable.hasKey("items"):
            pd.itemset = @[]
            for itm in paytable["items"]:
                pd.itemset.add(itm.getStr())
        pd.paytableSeq = res.getPaytableData()
        if paytable.hasKey("freespin_trigger"):
            pd.freespTriggerId = paytable["freespin_trigger"].getStr()
        if paytable.hasKey("freespin_count"):
            pd.freespRelation = @[]
            let fr = paytable["freespin_count"]
            for i in countdown(fr.len-1, 0):
                let rel = fr[i]
                if rel.hasKey("trigger_count") and rel.hasKey("freespin_count"):
                    pd.freespRelation.add((rel["trigger_count"].getInt(), rel["freespin_count"].getInt()))
        if paytable.hasKey("bonus_trigger"):
            pd.bonusTriggerId = paytable["bonus_trigger"].getStr()
        if paytable.hasKey("bonus_count"):
            pd.bonusCount = paytable["bonus_count"].getInt()
        if paytable.hasKey("bonus_config"):
            v.bonusConfigRelation = @[]
            for itm in paytable["bonus_config"]:
                v.bonusConfigRelation.add(itm.getInt())

        v.pd = pd

    if res.hasKey($sdtFreespinCount):
        v.freeSpinsLeft = res[$sdtFreespinCount].getInt()
        if v.freeSpinsLeft > 0:
            v.freeSpinsOnEnter = true
            v.stage = GameStage.FreeSpin
            v.setSpinButtonState(SpinButtonState.Blocked)

    if res.hasKey($sdtFreespinTotalWin):
        v.freeSpinsTotalWin = res[$sdtFreespinTotalWin].getBiggestInt()
        v.roundWin += v.freespinsTotalWin

    if res.hasKey($srtChips):
        currentUser().updateWallet(res[$srtChips].getBiggestInt())
        v.slotGUI.moneyPanelModule.setBalance(0, v.currentBalance, false)

    if "quests" in res:
        sharedQuestManager().proceedQuests(res["quests"])

method initAfterResourcesLoaded*(v: EiffelSlotView) =
    procCall v.BaseMachineView.initAfterResourcesLoaded()

    v.singleImagesNode = newLocalizedNodeWithResource(GENERAL_PREFIX & "eiffel_slot/precomps/Single_images.json")
    v.rope = v.singleImagesNode.findNode("Rope.png").component(Sprite).image
    v.lightLeft = v.singleImagesNode.findNode("Light_Left.png").component(Sprite).image
    v.lightRight = v.singleImagesNode.findNode("Light_Right.png").component(Sprite).image
    v.rootNode.addChild(newLocalizedNodeWithResource(GENERAL_PREFIX & "eiffel_slot/TOWER.json"))
    v.rootNode.findNode("TOWER").addChild(newLocalizedNodeWithResource(GENERAL_PREFIX & "eiffel_slot/precomps/TOWER_RED_TOP.json"))
    v.rootNode.findNode("TOWER_RED_TOP").translate = -v.rootNode.findNode("TOWER").position
    v.rootNode.findNode("BG").addChild(newLocalizedNodeWithResource(GENERAL_PREFIX & "eiffel_slot/precomps/TOWER_RED_BOTTOM.json"))

    var reelsParent = v.rootNode.findNode("Ropes").newChild("reelsParent")
    var reelsClip = reelsParent.newChild("reelsClip")

    v.reelNodes = newSeq[Node]()

    for i in 1..NUMBER_OF_REELS:
        let n = v.rootNode.findNode("Reel" & $i)
        v.reelNodes.add(n)
        n.reparentTo(reelsClip)

    reelsClip.component(ClippingRectComponent).clippingRect = newRect(0, 150, v.viewportSize.width, symVerticalSpacing * 4)

    v.prepareRotatingNodes()

    v.lightAnims = newSeq[LightAnims]()
    v.cachedSymbols = initTable[Symbols, seq[Node]]()

    for symb in 0..(Symbols.Nine.int):
        v.cachedSymbols[symb.Symbols] = newSeq[Node]()
        for i in 0..10:
            v.putSymbolNodeToCache(v.createNodeForSymbol(symb.Symbols))

    v.symbolHighlightController.new()
    v.symbolHighlightController.reelNodes = v.reelNodes
    v.reelSpinAnimations = newSeq[Animation](v.reelNodes.len)
    v.rotationAnims = newSeq[Animation](v.reelNodes.len)

    v.auxAnimations = @[]
    v.rotationAnimBoosted = @[]
    v.ropeAnimationOffset = @[]

    for i in 0..<NUMBER_OF_REELS:
        v.rotationAnimBoosted.add(false)
        v.ropeAnimationOffset.add(0)

    v.rotationBaseSpeed = 10

    v.isRedAnimActive = false
    v.rootNode.addChild(v.createLightClusters())

    let ropesNode = v.rootNode.findNode("Ropes")
    ropesNode.setComponent "ropes", newComponentWithDrawProc(proc() =
        for i in 0 ..< v.reelNodes.len:
            drawRope(v.rope, v.reelNodes[i].positionX + symbolWidth / 2, 200, 800, v.ropeAnimationOffset[i])
    )

    v.addSwitcher()
    let mimeNode = newLocalizedNodeWithResource(GENERAL_PREFIX & "eiffel_mime/comps/mime.json")
    v.rootNode.addChild(mimeNode)

    v.mimeController = newAnimationControllerForNode(mimeNode)
    v.mimeController.addIdles(["idle1", "idle2"])
    v.lastPlayerActivity = -1

    v.setNeedsDisplay()

    var ffBonuses, ffScatters = 0
    for i in 0 ..< v.reelNodes.len:
        v.firstFill(v.reelNodes[i].findNode("Field"), i, ffBonuses, ffScatters)

    v.rootNode.findNode("status").component(Text).text = ""

    let infoPanelAnchor = v.rootNode.findNode("Table.png")

    infoPanelAnchor.component(ClippingRectComponent).clippingRect = newRect(0, 0, 830, 90)
    v.infoPanel = newInfoPanel(newLocalizedNodeWithResource(GENERAL_PREFIX & "eiffel_slot/precomps/TOWER_STATUS.json"), v.rootNode)
    v.infoPanel.node.position = newVector3(-550, -150)
    v.infoPanel.lightAnimProc = proc(cluster: LightsCluster, timeout: float, animDur: float) =
        v.setTimeout timeout, proc() =
            v.addAnimation(cluster.waveAnimation(animDur))
    v.infoPanel.timeOutProc = proc(timeout: float, callback: proc()) =
        v.setTimeout timeout, callback
    infoPanelAnchor.addChild(v.infoPanel.node)

    discard v.rootNode.newChild("lines_unique")
    discard v.rootNode.newChild("paytable_anchor")
    v.popupHolder = newNode("popupHolder")
    v.rootNode.addChild(v.popupHolder)


method init*(v: EiffelSlotView, r: Rect) =
    procCall v.BaseMachineView.init(r)
    v.gameFlow = newGameFlow(GAME_FLOW)
    v.gLines = 20
    v.multBig = 10
    v.multHuge = 15
    v.multMega = 25

    v.addDefaultOrthoCamera("Camera")
