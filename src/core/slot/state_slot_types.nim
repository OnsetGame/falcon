import core.flow.flow
import base_slot_machine_view
import json, tables
import sound_map

export sound_map

export flow
export base_slot_machine_view

type
    AbstractSlotState* = ref object of BaseFlowState
        slot*: StateSlotMachine
        onFinish*: proc()
        cancel*: proc()
        onForceStop*: proc()

    ForceStopState* = ref object of AbstractSlotState

    StateSlotTimingConfig* = tuple
        spinIdleDuration: float
        startIdleWinLines: float
        idleWinLine: float
        pauseBetweenSpins: float

    StateSlotMachine* = ref object of BaseMachineView
        timingConfig*: StateSlotTimingConfig
        sound*: SoundMap
        lastResponce*: JsonNode
        freespinsCount*: int
        respinsCount*: int
        reactions: TableRef[string, Reaction]
        statesToCleanup: seq[AbstractSlotState]
        reelsInfo*: tuple[bonusReels: seq[int], scatterReels: seq[int]]
        chipsBeforeSpin*: int64
        freespinsTotalWin*: int64
        soundEventsPath*: string

    Reaction* = ref object of RootObj
        name*: string
        slot*: StateSlotMachine
        execute: proc(state: AbstractSlotState)

proc newSlotReaction(ss: StateSlotMachine, cb: proc(state: AbstractSlotState)): Reaction =
    var react = new(Reaction)
    react.slot = ss
    react.execute = cb
    result = react

proc finish*(state: AbstractSlotState) =
    if not state.isNil:
        state.weakPop()
        state.slot.statesToCleanup.add(state)

        if not state.onFinish.isNil():
            state.onFinish()

method cleanup*(state: AbstractSlotState) {.base.}=
    state.slot = nil
    state.onFinish = nil

proc cleanupStates*(ss: StateSlotMachine)=
    for s in ss.statesToCleanup:
        if not s.isNil:
            s.cleanup()

    ss.statesToCleanup.setLen(0)

proc registerReaction*(ss: StateSlotMachine, stateName: string, cb: proc(state: AbstractSlotState))=
    let r = ss.newSlotReaction(cb)
    if ss.reactions.isNil:
        ss.reactions = newTable[string, Reaction]()

    assert(stateName notin ss.reactions, "Trying to override slotState " & stateName)

    ss.reactions[stateName] = r

proc react*(ss: StateSlotMachine, state: AbstractSlotState): bool=
    if ss.reactions.isNil: return

    let reaction = ss.reactions.getOrDefault(state.name)
    if not reaction.isNil:
        reaction.execute(state)
        result = true

proc newSlotState*(ss: StateSlotMachine, T: typedesc[AbstractSlotState]): T =
    result = newFlowState(T)
    result.slot = ss

method createForceStopState*(ss: StateSlotMachine): ForceStopState =
    result = ss.newSlotState(ForceStopState)
