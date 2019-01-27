import logging, tables, sequtils, typetraits, variant, times, opengl, strutils
import rod / [ component, viewport, node ]
import rod / tools / debug_draw
import nimx / [ matrixes, types, formatted_text, font ]
import secureHash, math, random, hashes

import flow_manager
export flow_manager


var gManager: FlowManager
proc getGlobalFlowManager*(): FlowManager =
    if gManager.isNil:
        gManager = newFlowManager("global")
    result = gManager


method init*(c: FlowStateRecordComponent) =
    if c.manager.isNil:
        c.manager = getGlobalFlowManager()

proc pop*(state: BaseFlowState) =
    getGlobalFlowManager().pop(state)

proc weakPop*(state: BaseFlowState)=
    getGlobalFlowManager().weakPop(state)

proc execute*(state: BaseFlowState) =
    getGlobalFlowManager().execute(state)

proc pushBack*(state: BaseFlowState) =
    getGlobalFlowManager().pushBack(state)

proc pushBack*(state: typedesc) =
    getGlobalFlowManager().pushBack(state)

proc pushFront*(state: BaseFlowState) =
    getGlobalFlowManager().pushFront(state)

proc pushFront*(state: typedesc) =
    getGlobalFlowManager().pushFront(state)

proc findActiveState*(kind: typedesc): BaseFlowState =
    result = getGlobalFlowManager().findActiveState(kind)

proc findActiveState*(ff: proc(state: BaseFlowState): bool): BaseFlowState =
    result = getGlobalFlowManager().findActiveState(ff)

proc findPendingState*(kind: typedesc): BaseFlowState =
    getGlobalFlowManager().findPendingState(kind)

proc findFlowState*(kind: typedesc): BaseFlowState =
    getGlobalFlowManager().findFlowState(kind)

proc getCurrentState*(): BaseFlowState =
    getGlobalFlowManager().currentState

proc closeAllActiveStates*() =
    getGlobalFlowManager().closeAllActiveStates()

proc cleanPendingStates*(state: typedesc) =
    getGlobalFlowManager().cleanPendingStates(state)

proc removeAllFlowStates*() =
    getGlobalFlowManager().removeAllFlowStates()

proc pendingFlowStates*(): seq[BaseFlowState] =
    getGlobalFlowManager().pendingStates

proc currentFlowState*(): BaseFlowState =
    getGlobalFlowManager().currentState

# DEBUGING
proc dumpActive*()=
    getGlobalFlowManager().dumpActive()

proc dumpPending*()=
    getGlobalFlowManager().dumpPending()

proc dumpRecords*(count: int) =
    getGlobalFlowManager().dumpRecords(count)

proc printFlowStates*() =
    getGlobalFlowManager().printFlowStates()

