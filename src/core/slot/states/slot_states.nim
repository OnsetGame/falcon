import core / flow / [ flow, flow_macro, flow_state_types ]
import core / slot / [ state_slot_types, base_slot_machine_view ]
import core.notification_center

import core.net.server
import rod.viewport
import nimx.animation

import shafa.slot.slot_data_types
import utils.pause

import json, logging

import shared.gui / [ slot_gui, win_panel_module, money_panel_module,
    spin_button_module, autospins_switcher_module, total_bet_panel_module ]

import shared / [ user, win_popup, game_scene ]

type SlotRoundState* = ref object of AbstractSlotState

type SlotRoundComplete* = ref object of AbstractSlotState
type SlotRestoreState* = ref object of SlotRoundState
    restoreData*: JsonNode

type SlotRoundEnd* = ref object of AbstractSlotState

type SlotRoundPause* = ref object of AbstractSlotState

type SlotStageState* = ref object of AbstractSlotState
    stageData*: JsonNode

type SlotStageEndState* = ref object of SlotStageState
type SpinStageState* = ref object of SlotStageState
type BonusStageState* = ref object of SlotStageState
type BonusStageStateEnd* = ref object of SlotStageState
type FreespinStageState* = ref object of SlotStageState
type RespinStageState* = ref object of SlotStageState

type ShowSpecialWinState* = ref object of AbstractSlotState

type SpecialWinState* = ref object of AbstractSlotState
    winKind*: WinType
    amount*: int64

type ShowWinningLine* = ref object of AbstractSlotState
    line*: PaidLine
    i*: int
    totalPayout*: int64
    inIdle*: bool

type WinLinesState* = ref object of AbstractSlotState
    winLines*: seq[PaidLine]
    linesStates*: seq[ShowWinningLine]
    totalPayout*: int64

type WinLinesIdleState* = ref object of WinLinesState

type NoWinState* = ref object of AbstractSlotState

type StartShowAllWinningLines* = ref object of AbstractSlotState

type EndShowAllWinningLines* = ref object of AbstractSlotState
    amount*: int64

type ChipsAnimationState* = ref object of AbstractSlotState
    amount*: int64
    stage*: string

type FreespinEnterState* = ref object of AbstractSlotState
    count*: int

type RespinsEnterState* = ref object of AbstractSlotState
    count*: int

type FreespinExitState* = ref object of AbstractSlotState
    amount*: int64

type BonusGameExitState* = ref object of AbstractSlotState
    amount*: int64

type FiveInARowState* = ref object of SpecialWinState
type MultiWinState* = ref object of SpecialWinState

type SpinAnimationState* = ref object of AbstractSlotState
type SpinInAnimationState* = ref object of SpinAnimationState
type SpinIdleAnimationState* = ref object of SpinAnimationState
    waitAnim*: Animation

type SpinOutAnimationState* = ref object of SpinAnimationState

type CoreSlotFlow* = ref object of AbstractSlotState
type SpinSlotFlow* = ref object of CoreSlotFlow
type FreespinSlotFlow* = ref object of CoreSlotFlow
type RespinSlotFlow* = ref object of CoreSlotFlow
type SpinRequestState* = ref object of AbstractSlotState

type UpdateTask = ref object of AbstractSlotState

type
    UpdateBalanceImmediately* = ref object of AbstractSlotState
    UpdateBalanceCountUp* = ref object of AbstractSlotState

type SlotNotEnoughtChipsState* = ref object of AbstractSlotState

stateMachine SlotFlowState:
    - SlotRoundState:
        - SlotRoundEnd
        - SlotRoundPause

        > SpinSlotFlow:
            - SpinRequestState:
                - SpinAnimationState:
                    - UpdateBalanceImmediately
                    - SpinInAnimationState
                    - SpinIdleAnimationState:
                        @ ForceStopState
                    - SpinOutAnimationState:
                        @ ForceStopState

            - UpdateBalanceCountUp
            - WinLinesState:
                - StartShowAllWinningLines
                - ShowWinningLine:
                    @ ForceStopState
                - ShowSpecialWinState:
                    - MultiWinState:
                        @ ForceStopState

                    - FiveInARowState
                - ChipsAnimationState

            - EndShowAllWinningLines
            - NoWinState
            - FreespinEnterState
            - FreespinExitState:
                @ ForceStopState
            - RespinsEnterState
            - SlotStageEndState

            - SpinStageState
            - FreespinStageState
            - RespinStageState
            - BonusStageState
            - UpdateTask

        > FreespinSlotFlow:
            - SpinRequestState:
                - SpinAnimationState:
                    - UpdateBalanceImmediately
                    - SpinInAnimationState
                    - SpinIdleAnimationState:
                        @ ForceStopState
                    - SpinOutAnimationState:
                        @ ForceStopState
                - ChipsAnimationState

            - UpdateBalanceCountUp

            - WinLinesState:
                - StartShowAllWinningLines
                - ShowWinningLine:
                    @ ForceStopState
                - ShowSpecialWinState:
                    - MultiWinState:
                        @ ForceStopState

                    - FiveInARowState

            - EndShowAllWinningLines
            # - ChipsAnimationState
            - NoWinState
            - FreespinEnterState
            - FreespinExitState:
                @ ForceStopState
            - RespinsEnterState
            - SlotStageEndState

            - SpinStageState
            - FreespinStageState
            - RespinStageState
            - BonusStageState
            - UpdateTask

        > RespinSlotFlow:
            - SpinRequestState:
                - SpinAnimationState:
                    - UpdateBalanceImmediately
                    - SpinInAnimationState
                    - SpinIdleAnimationState:
                        @ ForceStopState
                    - SpinOutAnimationState:
                        @ ForceStopState

            - UpdateBalanceCountUp
            - WinLinesState:
                - StartShowAllWinningLines
                - ShowWinningLine:
                    @ ForceStopState
                - ShowSpecialWinState:
                    - MultiWinState:
                        @ ForceStopState

                    - FiveInARowState
                - ChipsAnimationState
            - EndShowAllWinningLines
            # - ChipsAnimationState
            - NoWinState
            - FreespinEnterState
            - FreespinExitState:
                @ ForceStopState
            - RespinsEnterState
            - SlotStageEndState

            - SpinStageState
            - FreespinStageState
            - RespinStageState
            - BonusStageState
            - UpdateTask

        - BonusStageStateEnd:
            - BonusGameExitState:
                @ ForceStopState
            - ChipsAnimationState
            - UpdateBalanceCountUp

    - SlotRestoreState:
        - SlotRoundEnd
        - SlotRoundPause
        - SpinSlotFlow
        - FreespinSlotFlow
        - RespinSlotFlow

    - SlotRoundComplete:
        - SlotRoundPause

    - SlotNotEnoughtChipsState

    - WinLinesIdleState:
        - ShowWinningLine:
            @ ForceStopState
        @ ForceStopState

SpinOutAnimationState.dummySlotAwake
SlotStageState.dummySlotAwake
SlotStageEndState.dummySlotAwake
BonusStageStateEnd.dummySlotAwake
EndShowAllWinningLines.dummySlotAwake
StartShowAllWinningLines.dummySlotAwake
FiveInARowState.dummySlotAwake
NoWinState.dummySlotAwake

proc onForceStopSpinIdle(state: SpinIdleAnimationState) =
    if state.slot.animSettings.len != 0:
        for i in 0..<NUMBER_OF_REELS:
            state.slot.animSettings[i].time = 0
            state.slot.animSettings[i].boosted = false
        state.waitAnim.cancel()

proc onForceStopSpinOut(state: SpinOutAnimationState) =
    if not state.cancel.isNil:
        state.cancel()

proc onForceStopShowWinningLine(state: ShowWinningLine) =
    cleanPendingStates(ShowWinningLine)

    if not state.onFinish.isNil:
        state.onFinish = nil

    if not state.cancel.isNil:
        let cb: proc() = state.cancel
        state.cancel = nil
        if not cb.isNil:
            cb()

    if state.parent of WinLinesState:
        let wl = state.parent.WinLinesState #may be nil: wtf?
        if not state.inIdle:
            let fs = findActiveState(FreespinSlotFlow)
            if fs.isNil:
                state.slot.slotGui.winPanelModule.setNewWin(wl.totalPayout.int, false)
            else:
                state.slot.slotGui.winPanelModule.setNewWin(state.slot.freespinsTotalWin, false)
        else:
            if not wl.cancel.isNil:
                wl.cancel()

    elif state.parent of WinLinesIdleState:
        let wl = state.parent.WinLinesIdleState
        if not wl.cancel.isNil:
            wl.cancel()

proc onForceStopWinLinesIdle(state: WinLinesIdleState) =
    cleanPendingStates(ShowWinningLine)
    if not state.cancel.isNil:
        state.cancel()

proc onForceStopMultiWin(state: MultiWinState) =
    if not state.cancel.isNil:
        state.cancel()

proc onForceStopBonusGameExit(state: BonusGameExitState) =
    if not state.cancel.isNil:
        state.cancel()

proc onForceStopFreespinExit(state: FreespinExitState) =
    if not state.cancel.isNil:
        state.cancel()

# type UpdateTask = ref object of AbstractSlotState
method wakeUp*(state:UpdateTask) =
    currentNotificationCenter().postNotification("OnQuestsUpdated")
    state.weakPop()

method wakeUp*(s: SlotRoundComplete)=
    let uc = currentUser().chips
    let pc = s.slot.slotGui.moneyPanelModule.chips
    if uc != pc:
        echo "Balance sync failure! "
        echo "User chips ", uc
        echo "Panel chips ", pc
        echo ""

    if s.slot.paidLines.len > 0:
        var idle = s.slot.newSlotState(WinLinesIdleState)
        idle.winLines = s.slot.paidLines
        idle.onForceStop = proc() =
            onForceStopWinLinesIdle(idle)
        pushBack(idle)

    s.slot.actionButtonState = SpinButtonState.Spin
    s.slot.updateTotalBetPanel()
    # s.slot.slotGUI.totalBetPanelModule.plusEnabled = true
    # s.slot.slotGUI.totalBetPanelModule.minusEnabled = true

    let hasReaction = s.slot.react(s)
    if not hasReaction:
        s.weakPop()

method wakeUp*(s: SlotRoundState)=
    let hasReaction = s.slot.react(s)
    cleanPendingStates(ShowWinningLine)

    var spinFlow = s.slot.newSlotState(SpinSlotFlow)
    pushBack(spinFlow)

    var roundEnd = s.slot.newSlotState(SlotRoundEnd)
    pushBack(roundEnd)

    if not hasReaction:
        s.weakPop()

method cleanup*(s: SlotRestoreState)=
    procCall s.AbstractSlotState.cleanup()
    s.restoreData = nil

method wakeUp*(s: SlotRestoreState)=
    let r = s.restoreData

    if "bmt" in r:
        s.slot.multBig = r["bmt"][0].getNum().int
        s.slot.multHuge = r["bmt"][1].getNum().int
        s.slot.multMega = r["bmt"][2].getNum().int
    if "fc" in r:
        s.slot.freespinsCount = r["fc"].getNum().int

        if s.slot.freespinsCount > 0:
            var nfree = s.slot.newSlotState(FreespinEnterState)
            nfree.count = s.slot.freespinsCount
            pushBack(nfree)

            var freeFlow = s.slot.newSlotState(FreespinSlotFlow)
            pushBack(freeFlow)

            var roundEnd = s.slot.newSlotState(SlotRoundEnd)
            pushBack(roundEnd)

    if "rc" in r:
        s.slot.respinsCount = r["rc"].getNum().int

        if s.slot.respinsCount > 0:
            var freeFlow = s.slot.newSlotState(RespinSlotFlow)
            pushBack(freeFlow)

            var roundEnd = s.slot.newSlotState(SlotRoundEnd)
            pushBack(roundEnd)

    if not s.slot.react(s):
        s.weakPop()


SlotRoundPause.awake:
    if state.slot.timingConfig.pauseBetweenSpins > 0.0:
        let ct = state.slot.setTimeout(state.slot.timingConfig.pauseBetweenSpins) do():
            state.pop()
    else:
        state.pop()

method wakeUp*(state: SlotRoundEnd)=

    cleanPendingStates(ForceStopState)

    #var pause = state.slot.newSlotState(SlotRoundPause)
    #pushBack(pause)
    var taskCompl = findPendingState(CompleteTaskFlowState)

    if state.slot.freespinsCount > 1:
        # state.slot.slotGui.spinButtonModule.startFreespins(state.slot.freespinsCount)

        var pause = state.slot.newSlotState(SlotRoundPause)
        pushBack(pause)

        var freeFlow = state.slot.newSlotState(FreespinSlotFlow)
        pushBack(freeFlow)

        var roundEnd = state.slot.newSlotState(SlotRoundEnd)
        pushBack(roundEnd)

    elif state.slot.respinsCount > 0:

        state.slot.slotGui.spinButtonModule.stopFreespins()

        var pause = state.slot.newSlotState(SlotRoundPause)
        pushBack(pause)

        var freeFlow = state.slot.newSlotState(RespinSlotFlow)
        pushBack(freeFlow)

        var roundEnd = state.slot.newSlotState(SlotRoundEnd)
        pushBack(roundEnd)

    elif state.slot.slotGui.autospinsSwitcherModule.isOn and taskCompl.isNil:
        state.slot.slotGUI.spinButtonModule.stopRespins()
        state.slot.slotGui.spinButtonModule.stopFreespins()

        var pause = state.slot.newSlotState(SlotRoundPause)
        pushBack(pause)

        var nextSpin = state.slot.newSlotState(SlotRoundState)
        state.slot.sound.play("SPIN_BUTTON_SFX")
        pushBack(nextSpin)

    else:
        state.slot.slotGUI.spinButtonModule.stopRespins()
        state.slot.slotGui.spinButtonModule.stopFreespins()
        var src = state.slot.newSlotState(SlotRoundComplete)
        pushBack(src)

    state.slot.cleanupStates()

    if not state.slot.react(state):
        state.weakPop()

method wakeUp*(state:ForceStopState) =
    let slotState = findActiveState() do(state: BaseFlowState)->bool:
        if state of AbstractSlotState:
            let slotState = state.AbstractSlotState
            return (not slotState.cancel.isNil) or (not slotState.onForceStop.isNil)

    if not slotState.isNil:
        let slotState = slotState.AbstractSlotState
        if not slotState.onForceStop.isNil:
            slotState.onForceStop()
        else:
            slotState.cancel()

    weakPop(state)

method cleanup*(s: SlotStageState)=
    procCall s.AbstractSlotState.cleanup()
    s.stageData = nil

method wakeUp*(s: BonusStageState)=
    let hasReaction = s.slot.react(s)
    let bonusWin =  s.stageData["payout"].getNum().int64

    var bonusEnd = s.slot.newSlotState(BonusStageStateEnd)
    pushBack(bonusEnd)

    var bonusExit = s.slot.newSlotState(BonusGameExitState)
    bonusExit.onForceStop = proc() =
        onForceStopBonusGameExit(bonusExit)

    bonusExit.amount = bonusWin
    s.slot.onBonusGameStart()
    pushBack(bonusExit)

    if not hasReaction:
        s.weakPop()

method cleanup*(s: WinLinesState)=
    # procCall s.SkipableWinPresentation.cleanup()
    s.winLines.setLen(0)
    s.linesStates.setLen(0)

method wakeUp*(state: WinLinesIdleState) =
    let payout = state.slot.getPayoutForLines()
    state.totalPayout = payout

    proc genLines()=
        state.linesStates = @[]
        for i, line in state.winLines:
            var showLine = state.slot.newSlotState(ShowWinningLine)
            showLine.line = line
            showLine.i = i
            showLine.inIdle = true
            showLine.totalPayout = line.winningLine.payout

            closureScope:
                let sls = showLine
                showLine.onForceStop = proc() =
                    onForceStopShowWinningLine(sls)

            pushBack(showLine)
            state.linesStates.add(showLine)

        if state.linesStates.len > 0:
            state.linesStates[^1].onFinish = proc()=
                genLines()

    let ct = state.slot.setTimeout(state.slot.timingConfig.startIdleWinLines) do():
        genLines()

    state.cancel = proc()=
        state.slot.pauseManager.clear(ct)
        cleanPendingStates(ShowWinningLine)
        state.finish()

method wakeUp*(state: ShowSpecialWinState) =
    if state.slot.paidLines.len > 0:
        let payout = state.slot.getPayoutForLines()

        if state.slot.check5InARow():
            var fiar = state.slot.newSlotState(FiveInARowState)
            fiar.winKind = WinType.FiveInARow
            pushBack(fiar)

        var special: SpecialWinState
        let wt = state.slot.getWinType(payout)
        case wt:
        of WinType.Mega, WinType.Jackpot, WinType.Big, WinType.Huge:
            special = state.slot.newSlotState(MultiWinState)
            special.onForceStop = proc() =
                onForceStopMultiWin(special.MultiWinState)
        else:
            special = nil

        if not special.isNil:
            special.winKind = wt
            special.amount = payout
            pushBack(special)

    state.weakPop()

method wakeUp*(state: MultiWinState) =
    let hasReaction = state.slot.react(state)
    let s = state.slot
    let totalWin = s.getPayoutForLines()
    var bwt = BigWinType.Big


    if totalWin >= s.multMega * s.totalBet:
        bwt = BigWinType.Mega
    elif totalWin >= s.multHuge * s.totalBet:
        bwt = BigWinType.Huge

    s.onBigWinHappend(bwt, s.chipsBeforeSpin)
    if not hasReaction:
        state.weakPop()

method wakeUp*(state: WinLinesState) =
    state.linesStates = @[]
    state.winLines = state.slot.sortWinningLines(state.winLines)

    let payout = state.slot.getPayoutForLines()
    state.totalPayout = payout
    var startShowWl = state.slot.newSlotState(StartShowAllWinningLines)
    pushBack(startShowWl)

    for i, line in state.winLines:
        var showLine = state.slot.newSlotState(ShowWinningLine)
        showLine.line = line
        showLine.i = i
        showLine.totalPayout = line.winningLine.payout

        closureScope:
            let sls = showLine
            showLine.onForceStop = proc() =
                onForceStopShowWinningLine(sls)

        pushBack(showLine)
        state.linesStates.add(showLine)

    state.cancel = proc()=
        for ls in state.linesStates:
            if not ls.cancel.isNil:
                ls.cancel()

            if not ls.parent.isNil:
                pop(ls)
            else:
                cleanPendingStates(ShowWinningLine)

        state.linesStates.setLen(0)

    var showSw = state.slot.newSlotState(ShowSpecialWinState)
    pushBack(showSw)

    var endShowWl = state.slot.newSlotState(EndShowAllWinningLines)
    endShowWl.amount = payout
    pushBack(endShowWl)

    var chipsParticles = state.slot.newSlotState(ChipsAnimationState)
    chipsParticles.amount = state.slot.getPayoutForLines()
    chipsParticles.stage = "Spin"
    pushBack(chipsParticles)

    state.weakPop()

method wakeUp*(state: ShowWinningLine)=
    proc cb() =
        let hasReaction = state.slot.react(state)

        let hasFreespins = findActiveState(FreespinSlotFlow)

        if not state.inIdle:
            if state.i == 0 and hasFreespins.isNil:
                state.slot.slotGui.winPanelModule.setNewWin(state.line.winningLine.payout, true)
            else:
                state.slot.slotGui.winPanelModule.addToWin(state.line.winningLine.payout, true)

        if not hasReaction:
            state.pop()

    if state.inIdle:
        let ct = state.slot.setTimeout(state.slot.timingConfig.idleWinLine) do():
            cb()

        var can = state.cancel
        state.cancel = proc()=
            if not can.isNil:
                can()
                state.slot.pauseManager.clear(ct)
    else:
        cb()

method wakeUp*(s: ChipsAnimationState) =
    let hasReaction = s.slot.react(s)

    let cc = s.slot.slotGui.moneyPanelModule.chips
    s.slot.chipsAnim(s.slot.rootNode, cc, cc + s.amount, s.stage)

    if not hasReaction:
        s.pop()

method wakeUp*(s: FreespinEnterState)=
    let hasReaction = s.slot.react(s)
    s.slot.slotGui.spinButtonModule.startFreespins(s.count)

    s.slot.onFreeSpinsStart()
    if not hasReaction:
        s.pop()

method wakeUp*(s: FreespinExitState)=
    let hasReaction = s.slot.react(s)

    s.slot.slotGui.spinButtonModule.stopFreespins()
    s.slot.onFreeSpinsEnd()
    if not hasReaction:
        s.pop()

method wakeUp*(s: BonusGameExitState)=
    let hasReaction = s.slot.react(s)
    var chipsAnimState = s.slot.newSlotState(ChipsAnimationState)
    chipsAnimState.stage = "Bonus"

    s.slot.slotGui.winPanelModule.addToWin(s.amount.int, true)
    s.slot.onBonusGameEnd()
    chipsAnimState.amount = s.amount
    pushBack(chipsAnimState)

    if not hasReaction:
        s.pop()


method wakeUp*(s: SpinAnimationState) =
    let hasReaction = s.slot.react(s)

    var si = s.slot.newSlotState(SpinInAnimationState)
    pushBack(si)

    if not hasReaction:
        weakPop(s)

method wakeUp*(s: SpinInAnimationState)=
    let hasReaction = s.slot.react(s)

    var idle = s.slot.newSlotState(SpinIdleAnimationState)
    idle.onForceStop = proc() =
        onForceStopSpinIdle(idle)

    pushBack(idle)

    if not hasReaction:
        s.weakPop()

method cleanup*(s:SpinIdleAnimationState)=
    procCall s.AbstractSlotState.cleanup()
    s.waitAnim = nil

method cleanup*(s:SpinOutAnimationState)=
    procCall s.AbstractSlotState.cleanup()
    s.cancel = nil

method wakeUp*(s: SpinIdleAnimationState)=
    s.waitAnim = newAnimation()
    s.waitAnim.loopDuration = s.slot.timingConfig.spinIdleDuration
    s.waitAnim.numberOfLoops = 1

    let hasReaction = s.slot.react(s)
    if not hasReaction:
        s.weakPop()

method wakeUp*(s: CoreSlotFlow)=
    s.slot.actionButtonState = SpinButtonState.Blocked
    s.slot.updateTotalBetPanel()
    # s.slot.slotGUI.totalBetPanelModule.plusEnabled = false
    # s.slot.slotGUI.totalBetPanelModule.minusEnabled = false

    s.slot.lastResponce = nil
    s.slot.rotateSpinButton(s.slot.slotGUI.spinButtonModule)

    var sr = s.slot.newSlotState(SpinRequestState)
    pushBack(sr)

    var spinAnimFlow = s.slot.newSlotState(SpinAnimationState)
    pushBack(spinAnimFlow)

method wakeUp*(s: SpinSlotFlow)=
    if s.slot.freeRounds:
        s.slot.slotGui.winPanelModule.setNewWin(0'i64)

        procCall s.CoreSlotFlow.wakeUp()

        var endStage = s.slot.newSlotState(SlotStageEndState)
        pushBack(endStage)

        weakPop(s)
    else:
        if currentUser().withdraw(chips = s.slot.totalBet()):
            currentUser().chips -= s.slot.totalBet()

            s.slot.slotGui.winPanelModule.setNewWin(0'i64)

            var withdraw = s.slot.newSlotState(UpdateBalanceImmediately)
            pushBack(withdraw)

            procCall s.CoreSlotFlow.wakeUp()

            var endStage = s.slot.newSlotState(SlotStageEndState)
            pushBack(endStage)

            weakPop(s)
        else:
            s.slot.slotGui.autospinsSwitcherModule.switchOff()
            var outOfChips = s.slot.newSlotState(SlotNotEnoughtChipsState)
            pushBack(outOfChips)
            pop(s)

method wakeUp*(s: FreespinSlotFlow)=
    let reacted = s.slot.react(s)
    let afterResponceFc = s.slot.freespinsCount - 1
    s.slot.slotGUI.spinButtonModule.setFreespinsCount(afterResponceFc)

    s.slot.slotGui.winPanelModule.setNewWin(s.slot.freespinsTotalWin)

    procCall s.CoreSlotFlow.wakeUp()

    var endStage = s.slot.newSlotState(SlotStageEndState)
    pushBack(endStage)

    if not reacted:
        weakPop(s)

method wakeUp*(s: RespinSlotFlow)=
    if s.slot.respinsCount > 0:
        s.slot.slotGUI.spinButtonModule.startRespins()

    procCall s.CoreSlotFlow.wakeUp()

    var endStage = s.slot.newSlotState(SlotStageEndState)
    pushBack(endStage)

    weakPop(s)

#[
    REQUEST
]#
method wakeUp*(srs: SpinRequestState)=
    let bet = srs.slot.totalBet()

    srs.slot.lastField = @[]
    srs.slot.chipsBeforeSpin = currentUser().chips
    sharedServer().spin(bet div srs.slot.gLines, srs.slot.gLines, $srs.slot.buildingId, srs.slot.getMode(), srs.slot.data) do(r: JsonNode):
        srs.slot.lastResponce = r

        let stages = r["stages"]
        var noWin = true

        echo "res ", r
        if "chips" in r:
            currentUser().chips = r["chips"].getNum().int64

        if $srtField in stages[0]:
            for i in stages[0][$srtField].items:
                srs.slot.lastField.add(i.getNum().int8)

        let pfc = srs.slot.freespinsCount
        if "fc" in r:
            srs.slot.freespinsCount = r["fc"].getNum().int

        if "rc" in r:
            srs.slot.respinsCount = r["rc"].getNum().int

        var ftw = 0'i64
        if "ftw" in r:
            ftw = r["ftw"].getNum().int64

        elif "ftw" in stages[0]:
            ftw = stages[0]["ftw"].getNum().int64

        srs.slot.freespinsTotalWin = ftw

        var outa = srs.slot.newSlotState(SpinOutAnimationState)
        outa.onForceStop = proc() =
            onForceStopSpinOut(outa)
        pushBack(outa)

        var slotStage: SlotStageState
        case stages[0]["stage"].getStr()
        of "Spin":
            slotStage = srs.slot.newSlotState(SpinStageState)
        of "FreeSpin":
            slotStage = srs.slot.newSlotState(FreespinStageState)
        of "Respin":
            slotStage = srs.slot.newSlotState(RespinStageState)
        else:
            warn "Invalid or unknown slot stage ", stages[0]

        if not slotStage.isNil:
            slotStage.stageData = stages[0]
            pushBack(slotStage)

        if "lines" in stages[0] and stages[0]["lines"].len > 0:
            noWin = false
            var winLine = srs.slot.newSlotState(WinLinesState)
            winLine.winLines = stages[0]["lines"].parsePaidLines()
            # winLine.stageData = stages[0]
            srs.slot.paidLines = winLine.winLines
            pushBack(winLine)

        else:
            srs.slot.paidLines = @[]

        if pfc < srs.slot.freespinsCount:
            noWin = false
            var nfree = srs.slot.newSlotState(FreespinEnterState)
            nfree.count = srs.slot.freespinsCount
            pushBack(nfree)

        if stages.len > 1 and cmp(stages[1]["stage"].getStr(), "Bonus") == 0:
            noWin = false
            var bonusStage = srs.slot.newSlotState(BonusStageState)
            bonusStage.stageData = stages[1]
            pushBack(bonusStage)

        if pfc > 1 and srs.slot.freespinsCount == 1:
            noWin = false
            var freend = srs.slot.newSlotState(FreespinExitState)
            freend.amount = ftw
            freend.onForceStop = proc() =
                onForceStopFreespinExit(freend)
            pushBack(freend)

        if noWin:
            pushBack(srs.slot.newSlotState(NoWinState))

        var updTask = srs.slot.newSlotState(UpdateTask)
        pushBack(updTask)

        if not srs.slot.react(srs):
            weakPop(srs)

        let state = srs.slot.getStateForStopAnim()
        srs.slot.setRotationAnimSettings(ReelsAnimMode.Long, state, srs.slot.reelsInfo, -1.5)
        srs.slot.spinAnalyticsUpdate(currentUser().chips - srs.slot.chipsBeforeSpin, slotStage of FreespinStageState)
        srs.slot.handleTournamentScoreGain(r)

method wakeUp*(ub: UpdateBalanceImmediately)=
    let mp = ub.slot.slotGui.moneyPanelModule
    mp.chips = currentUser().chips

    let ct = ub.slot.setTimeout(0.2) do():
        pop(ub)

method wakeUp*(ub: UpdateBalanceCountUp)=
    let mp = ub.slot.slotGui.moneyPanelModule
    mp.setBalance(mp.chips, currentUser().chips, true)

    let ct = ub.slot.setTimeout(1.0) do():
        pop(ub)

method wakeUp*(s: SlotNotEnoughtChipsState)=
    let autoSpinEnabled = s.slot.slotGui.autospinsSwitcherModule.isOn
    s.slot.slotGui.autospinsSwitcherModule.switchOff()
    let cb = proc() =
        discard
        # todo: call spin if autoSpinEnabled

    let hasReaction = s.slot.react(s)

    if not hasReaction:
        s.pop()

    s.slot.slotGUI.outOfCurrency("chips", cb)

