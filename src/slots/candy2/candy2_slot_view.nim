import core.slot.states / [
    slot_states
]
import core.slot / [ state_slot_machine, base_slot_machine_view, slot_types, sound_map ]
import core.flow.flow

import shared.game_scene
import nimx / [ matrixes, types, animation, font, timer, button ]

import rod / [ node, viewport, asset_bundle ]
import rod / component / [ ui_component, text_component, ae_composition ]
import utils/ [ sound, pause, sound_manager, animation_controller ]
import json, strutils, sequtils
import candy2_types, candy2_background, candy2_interior, candy2_top,
    candy2_stage_intro, candy2_winline, candy2_anticipation,
    candy2_win_numbers


let GENERAL_PREFIX = "slots/candy2_slot/"

type Candy2WildBlow = ref object of AbstractSlotState

type Candy2SlotView* = ref object of StateSlotMachine
    interior*: Interior
    background*: Background
    shakeParent*: ShakeParent
    top*: Top
    bonus*: BonusProxy
    pd*: Candy2PaytableServerData
    boyController*: AnimationController
    startBoyPosX*: float
    spinData*: Candy2SpinData
    wildParticles*: seq[Node]
    boxes*: seq[Box]
    bonusReady*: bool
    bonusBusy*: bool

method appearsOn*(s: Candy2WildBlow, o: AbstractSlotState): bool =
    return o.name == "SpinOutAnimationState"

method wakeUp*(s: Candy2WildBlow) =
    let hasReaction = s.slot.react(s)
    if not hasReaction:
        s.finish()

type MusicType* {.pure.} = enum
    Main,
    Bonus,
    Freespins

proc playBackgroundMusic*(v: Candy2SlotView, m: MusicType) =
    case m
    of MusicType.Main:
        v.sound.play("GAME_BACKGROUND_MUSIC")
    of MusicType.Freespins:
        v.sound.play("FREE_SPINS_MUSIC")
    of MusicType.Bonus:
        v.sound.play("BONUS_GAME_MUSIC")

import candy2_bonus
import candy2_boy
import candy2_win_popup
import candy2_wild
import slots.candy.candy_win_popup

method getStateForStopAnim*(v: Candy2SlotView): WinConditionState =
    const MINIMUM_BONUSES = 2
    const MINIMUM_SCATTERS = 2
    const MINIMAL_LINE = 2
    const SCATTER = 1
    const BONUS = 2

    let scatterCount = v.countSymbols(SCATTER)
    let bonusCount = v.countSymbols(BONUS)

    result = WinConditionState.NoWin
    if v.getLastWinLineReel() >= MINIMAL_LINE:
        result = WinConditionState.Line
    if scatterCount >= MINIMUM_SCATTERS:
        result =  WinConditionState.Scatter
    if bonusCount >= MINIMUM_BONUSES:
        let bonusReels = v.getWinConReels(BONUS)
        let scatterReels = v.getWinConReels(SCATTER)

        if not (bonusReels.len == MINIMUM_BONUSES and bonusReels[1] == 4):
            result = WinConditionState.Bonus
        if scatterCount >= bonusCount and scatterReels[0] > bonusReels[0]:
            result = WinConditionState.Scatter

method allowHighlightLine*(v: Candy2SlotView, paidLine: PaidLine): bool =
    var symsid = v.getSymbolIndexesForLine(paidLine.index)
    symsid.setLen(paidLine.winningLine.numberOfWinningSymbols)

    let cmp = proc(a: int): bool =
        result = a notin symsid

    let res = v.spinData.wildIndexes.all(cmp)
    result = v.spinData.wildActivator notin symsid and res

method init*(v: Candy2SlotView, r: Rect)=
    procCall v.StateSlotMachine.init(r)
    v.addDefaultOrthoCamera("Camera")
    v.gLines = 20
    v.soundEventsPath = "slots/candy2_slot/candy_sound/candy2"
    v.timingConfig.spinIdleDuration = 1.0
    v.reelsInfo = (bonusReels: @[0, 1, 2, 3, 4], scatterReels: @[0, 1, 2, 3, 4])

    v.registerReaction("SlotRestoreState") do(state: AbstractSlotState):
        let data = state.SlotRestoreState.restoreData

        if data.hasKey("paytable"):
            var pd: Candy2PaytableServerData
            let paytable = data["paytable"]
            let fsRelation = paytable["freespins_relation"]
            let bRelation = paytable["bonus_relation"]
            let bonusMultipliers = paytable["bonus_possible_multipliers"]

            pd.paytableSeq = data.getPaytableData()
            pd.freespinsRelation = @[]
            pd.bonusRelation = @[]
            pd.bonusPossibleMultipliers = @[]
            for p in fsRelation.pairs:
                pd.freespinsRelation.add((p.key.parseInt(), p.val.getInt()))
            for p in bRelation.pairs:
                pd.bonusRelation.add((p.key.parseInt(), p.val.getInt()))
            for item in bonusMultipliers.items:
                pd.bonusPossibleMultipliers.add(item.getFloat())

            v.pd = pd
        v.setupBoy()
        v.boyEnter()
        state.finish()

    v.registerReaction("SpinInAnimationState") do(state: AbstractSlotState):
        v.boySpin()
        v.sound.play("CANDY_SPIN")
        v.interior.anticipationStopped = false
        v.interior.spinIn() do():
            state.finish()

    v.registerReaction("SpinRequestState") do(state: AbstractSlotState):
        v.setupSpinData()
        state.finish()

    v.registerReaction("SpinOutAnimationState") do(state: AbstractSlotState):
        let so = state.SpinOutAnimationState

        so.cancel = proc()=
            v.interior.antBack.removeAllChildren()
            v.interior.anticipationStopped = true
            for anim in v.interior.antAnims:
                anim.cancel()

        v.interior.prepareBackLights(v.animSettings)

        v.interior.spinOut(v.animSettings, v.spinData, v.boyController) do():
            var blowState = v.newSlotState(Candy2WildBlow)
            pushBack(blowState)
            v.sound.stop("CANDY_SPIN")
            state.finish()
            v.interior.removeBacklights() do():
                discard

    v.registerReaction("Candy2WildBlow") do(state: AbstractSlotState):
        v.playBlowingWilds do():
            state.finish()

    v.registerReaction("NoWinState") do(state: AbstractSlotState):
        v.sound.stop("CANDY_SPIN")
        v.boyNowin()
        state.finish()

    v.registerReaction("StartShowAllWinningLines") do(state: AbstractSlotState):
        v.sound.stop("CANDY_SPIN")
        v.boyWin()
        state.finish()

    v.registerReaction("ShowWinningLine") do(state: AbstractSlotState):
        if state of ShowWinningLine:
            let wl = state.ShowWinningLine
            let coords = v.lines[wl.line.index]
            let numberOfElements = wl.line.winningLine.numberOfWinningSymbols
            var indexes = newSeq[int]()

            v.sound.play("CANDY_WIN_LINE")
            var winLineAnim = playWinLine(v.interior.winlineParent, wl.line.index)
            winLineAnim.onComplete do():
                v.sound.play("CANDY_CHOCO_SPLASH")
                if winLineAnim.isCancelled:
                    state.finish()
                else:
                    v.interior.winlineParent.playSlotWinNumber(wl.totalPayout, coords[2]).onComplete do():
                        state.finish()

            for i in 0 ..< numberOfElements:
                let c = coords[i] * 5 + i
                indexes.add(c)

            let anim = v.interior.showWinLine(indexes)
            anim.cancelBehavior = cbJumpToEnd

            wl.cancel = proc()=
                winLineAnim.cancel()
                anim.cancel()

    v.registerReaction("MultiWinState") do(state:AbstractSlotState):
        v.sound.stop("CANDY_SPIN")
        let mw = state.MultiWinState
        let thresholds = @[v.multBig, v.multHuge, v.multMega]
        let ba = v.boyMultiwin()

        ba.addLoopProgressHandler 0.8, true, proc() =
            let w = showBigwins(v.rootNode, mw.amount, v.totalBet, v.sound, GENERAL_PREFIX, thresholds) do():
                state.finish()

            v.winDialogWindow = w
            mw.cancel = proc() =
                if v.winDialogWindow == w:
                    v.winDialogWindow = nil
                if not w.isNil:
                    w.destroy()

    v.registerReaction("FreespinExitState") do(state: AbstractSlotState):
        if state of FreespinExitState:
            let fe = state.FreespinExitState
            v.interior.moveRoulette(false, false)

            let w = showFreespinsResult(v.rootNode, fe.amount, v.sound, GENERAL_PREFIX) do():
                v.sound.play("GAME_BACKGROUND_MUSIC")
                state.finish()

            v.winDialogWindow = w

            fe.cancel = proc() =
                if v.winDialogWindow == w:
                    v.winDialogWindow = nil
                if not w.isNil:
                    w.destroy()

    v.registerReaction("FreespinEnterState") do(state: AbstractSlotState):
        if state of FreespinEnterState:
            var freeEnter = createFreespinIntro()
            v.rootNode.addChild(freeEnter.node)
            v.interior.moveRoulette(true, false)
            let a = freeEnter.playAnim
            a.onComplete do():
                freeEnter.node.removeFromParent()
                v.playBackgroundMusic(MusicType.Freespins)
                state.finish()
            v.sound.play("CANDY_FREE_SPINS_ANNOUNCE")
            v.addAnimation(a)

    v.registerReaction("BonusStageState") do(state: AbstractSlotState):
        let bs = state.BonusStageState
        var bonusEnter = createBonusIntro()

        v.rootNode.addChild(bonusEnter.node)
        v.prepareGUItoBonus(true)
        let a = bonusEnter.playAnim

        a.addLoopProgressHandler 0.89, false, proc() =
            discard v.boyToBonus()
        a.onComplete do():
            v.playBackgroundMusic(MusicType.Bonus)
            discard v.startBonusGame(bs.stageData) do():
                state.finish()

        v.sound.play("CANDY_BONUS_ANNOUNCE")
        v.rootNode.addAnimation(a)

    v.registerReaction("FiveInARowState") do(state: AbstractSlotState):
        var five = createFiveInARow()
        v.rootNode.addChild(five.node)

        let a = five.playAnim
        a.onComplete do():
            five.node.removeFromParent()
            state.finish()
        v.sound.play("CANDY_FIVE_IN_A_ROW")
        v.rootNode.addAnimation(a)

    v.registerReaction("BonusGameExitState") do(state: AbstractSlotState):
        if state of BonusGameExitState:
            let be = state.BonusGameExitState
            let thresholds = @[v.multBig, v.multHuge, v.multMega]

            proc onDestroy() =
                v.sound.play("GAME_BACKGROUND_MUSIC")

                let moveFrom = v.moveFromBonusAnim()
                v.rootNode.addAnimation(moveFrom)
                moveFrom.onComplete do():
                    v.putBoxesBack()
                    v.boyEnter()
                    v.prepareGUItoBonus(false)
                    state.finish()

            let w = showBigwins(v.rootNode, be.amount, v.totalBet, v.sound, GENERAL_PREFIX, thresholds, onDestroy, true)
            v.sound.play("CANDY_BONUS_GAME_RESULT")
            v.winDialogWindow = w
            v.playBackgroundMusic(MusicType.Main)
            be.cancel = proc() =
                v.sound.stop("CANDY_BONUS_GAME_RESULT")
                if v.winDialogWindow == w:
                    v.winDialogWindow = nil
                if not w.isNil:
                    w.destroy()

method viewOnEnter*(v: Candy2SlotView) =
    procCall v.StateSlotMachine.viewOnEnter()
    v.interior.sound = v.sound
    v.playBackgroundMusic(MusicType.Main)
    v.sound.play("CANDY_AMBIENCE")

proc createTestButton(v: Candy2SlotView, action: proc()) =
    let button = newButton(newRect(50, 550, 100, 50))
    button.title = "Test"
    button.onAction do():
        if not action.isNil:
            action()
    v.addSubview(button)

method initAfterResourcesLoaded(v: Candy2SlotView) =
    v.shakeParent = createShakeParent()
    v.background = createBackground()
    v.interior = createInterior()
    v.top = createTop()
    v.bonus = createBonus()
    v.rootNode.addChild(v.shakeParent.node)
    v.shakeParent.shakeNode.addChild(v.background.node)
    v.shakeParent.shakeNode.addChild(v.interior.node)
    v.shakeParent.shakeNode.addChild(v.bonus.node)
    v.shakeParent.shakeNode.addChild(v.top.node)

    v.interior.setRouletteScissor()
    v.interior.startLollipop()
    v.interior.firstFill()
    v.top.startAirplane()
    v.createWildParticles()
    v.soundManager = newSoundManager(v)

    proc test() =
        echo "TROLOLO"

    when defined(debug):
        v.createTestButton(test)

method assetBundles*(v: Candy2SlotView): seq[AssetBundleDescriptor] =
    const ASSET_BUNDLES = [
        assetBundleDescriptor("slots/candy2_slot/background"),
        assetBundleDescriptor("slots/candy2_slot/interior"),
        assetBundleDescriptor("slots/candy2_slot/candy_sound"),
        assetBundleDescriptor("slots/candy2_slot/top"),
        assetBundleDescriptor("slots/candy2_slot/win_present"),
        assetBundleDescriptor("slots/candy2_slot/elements"),
        assetBundleDescriptor("slots/candy2_slot/bonus"),
        assetBundleDescriptor("slots/candy2_slot/particles"),
        assetBundleDescriptor("slots/candy2_slot/special_win"),
        assetBundleDescriptor("slots/candy2_slot/paytable"),
        assetBundleDescriptor("slots/candy2_slot/winlines"),
        assetBundleDescriptor("slots/candy2_slot/numbers"),
        assetBundleDescriptor("slots/candy2_slot/boy")
    ]
    result = @ASSET_BUNDLES
