import nimx / [ matrixes, types, view_event_handling, animation ]
import rod / [ node ]

import core.net.server
import core.flow / [ flow_state_types, flow ]

import base_slot_machine_view
import slot_types, state_slot_types
import states / [
    # update_balance,
    # spin,
    slot_states
]

import utils.sound_manager
import shared.gui.slot_gui
import shared.gui.money_panel_module
import shared.user
import json, logging

import falconserver.auth.profile_types, falconserver.map.building.builditem,
    falconserver.common.game_balance, falconserver.purchases.product_bundles_shared

import falconserver / slot / [ machine_base_types ]

export StateSlotMachine, state_slot_types

const legacyEnbaled = true

method init*(v: StateSlotMachine, r: Rect)=
    procCall v.BaseMachineView.init(r)
    v.flowDebugSpeed = 77.0

    #[
        override base onComplete
        to clean all slots states
    ]#
    let baseOnComplete = v.onComplete
    v.onComplete = proc() =
        if not v.sound.isNil:
            v.sound.invalidate()
        cleanPendingStates(AbstractSlotState)
        baseOnComplete()

    v.timingConfig.spinIdleDuration = 3.0
    v.timingConfig.startIdleWinLines = 1.5
    v.timingConfig.idleWinLine = 1.0
    v.timingConfig.pauseBetweenSpins = 1.0

    v.registerReaction("SpinIdleAnimationState") do(state: AbstractSlotState):
        if state of SpinIdleAnimationState:
            let spinIdle = state.SpinIdleAnimationState

            spinIdle.waitAnim.removeHandlers()

            v.addAnimation(spinIdle.waitAnim)
            spinIdle.waitAnim.onComplete do():
                if v.lastResponce.isNil:
                    v.addAnimation(spinIdle.waitAnim)
                else:
                    state.finish()


method restoreState*(v: StateSlotMachine, res: JsonNode) =
    when legacyEnbaled:
        procCall v.BaseMachineView.restoreState(res)

    var rest = v.newSlotState(SlotRestoreState)
    rest.restoreData = res
    pushBack(rest)

proc tryPushForceStopState(v: StateSlotMachine)=
    let slotState = findActiveState() do(state: BaseFlowState)->bool:
        if state of AbstractSlotState:
            let slotState = state.AbstractSlotState
            return (not slotState.cancel.isNil) or (not slotState.onForceStop.isNil)

    if slotState.isNil: return

    let fs = findFlowState(ForceStopState)
    if fs.isNil:
        var fs = v.createForceStopState()
        pushBack(fs)

method onSpinClick*(v: StateSlotMachine) =
    let aca = findFlowState(SlotRoundState)
    let idle = findActiveState(WinLinesIdleState)
    v.sound.play("SPIN_BUTTON_SFX")
    if aca.isNil:
        var sa = v.newSlotState(SlotRoundState)
        pushBack(sa)
    
    if not aca.isNil or not idle.isNil:
        v.tryPushForceStopState()

method onSceneAdded*(v: StateSlotMachine) =
    procCall v.BaseMachineView.onSceneAdded()

method onBetClicked*(v: StateSlotMachine) =
    procCall v.BaseMachineView.onBetClicked()
    let aca = findFlowState(SlotRoundState)
    if aca.isNil:
        v.tryPushForceStopState()

method clickScreen*(v: StateSlotMachine)=
    let aca = findFlowState(SlotRoundState)
    if not aca.isNil:
        v.tryPushForceStopState()

method onKeyDown*(v: StateSlotMachine, e: var Event): bool =
    result = procCall v.BaseMachineView.onKeyDown(e)

method viewOnEnter*(v: StateSlotMachine) =
    procCall v.BaseMachineView.viewOnEnter()

    let mp = v.slotGui.moneyPanelModule
    mp.chips = currentUser().chips
    mp.parts = currentUser().parts
    mp.bucks = currentUser().bucks

    v.soundManager = newSoundManager(v)
    if v.soundEventsPath.len > 0:
        v.soundManager.loadEvents(v.soundEventsPath, "common/sounds/common")
    else:
        v.soundManager.loadEvents("common/sounds/common")

    v.sound = newSoundMap(v.soundManager)

    v.sound.play("GAME_BACKGROUND_MUSIC")
    v.sound.play("GAME_BACKGROUND_AMBIENCE")

method viewOnExit*(v: StateSlotMachine) =
    procCall v.BaseMachineView.viewOnExit()
    cleanPendingStates(AbstractSlotState)
    dumpPending()

when legacyEnbaled:
    #[
        LEGACy
    ]#
    method onGameStageChanged*(v: StateSlotMachine, prevStage: GameStage) =
        procCall v.BaseMachineView.onGameStageChanged(prevStage)

    method showPaytable*(v: StateSlotMachine) =
        procCall v.BaseMachineView.showPaytable()

    method buildingId*(v: StateSlotMachine) : BuildingId =
        result = procCall v.BaseMachineView.buildingId()

    method spinSound*(v: StateSlotMachine): string =
        result = procCall v.BaseMachineView.spinSound()

    method removeWinAnimationWindow*(v: StateSlotMachine, fast: bool = true): bool {.discardable.} =
        result = procCall v.BaseMachineView.removeWinAnimationWindow(fast)

    method getLines*(v: StateSlotMachine, res: JsonNode) : seq[Line] =
        result = procCall v.BaseMachineView.getLines(res)

    method sceneID*(v: StateSlotMachine): string =
        result = procCall v.BaseMachineView.sceneID()

    method preloadSceneResources*(v:StateSlotMachine, onComplete: proc() = nil, onProgress: proc(p:float) = nil)=
        procCall v.BaseMachineView.preloadSceneResources(onComplete, onProgress)

    method getStateForStopAnim*(v:StateSlotMachine): WinConditionState =
        result = procCall v.BaseMachineView.getStateForStopAnim()

    method setSpinButtonState*(v: StateSlotMachine,  state: SpinButtonState) =
        procCall v.BaseMachineView.setSpinButtonState(state)

    method resizeSubviews*(v: StateSlotMachine, oldSize: Size) =
        procCall v.BaseMachineView.resizeSubviews(oldSize)

    method setupCameraForGui*(v: StateSlotMachine) =
        procCall v.BaseMachineView.setupCameraForGui()

    method didBecomeCurrentScene*(v: StateSlotMachine)=
        procCall v.BaseMachineView.didBecomeCurrentScene()

    method draw*(v: StateSlotMachine, r: Rect) =
        procCall v.BaseMachineView.draw(r)

    method onBonusGameStart*(v: StateSlotMachine) =
        procCall v.BaseMachineView.onBonusGameStart()

    method onBonusGameEnd*(v: StateSlotMachine) =
        procCall v.BaseMachineView.onBonusGameEnd()

    method onFreeSpinsStart*(v: StateSlotMachine) =
        procCall v.BaseMachineView.onFreeSpinsStart()

    method onFreeSpinsEnd*(v: StateSlotMachine) =
        procCall v.BaseMachineView.onFreeSpinsEnd()

    method onBigWinHappend*(v: StateSlotMachine, bwt:BigWinType, chipsBeforeWin:int64) =
        procCall v.BaseMachineView.onBigWinHappend(bwt, chipsBeforeWin)

    method createDeepLink*(v: StateSlotMachine): seq[tuple[id: string, route: string]] =
        result = procCall v.BaseMachineView.createDeepLink()
