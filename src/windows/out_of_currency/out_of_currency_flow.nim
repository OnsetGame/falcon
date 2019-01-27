import core / flow / flow


type OutOfCurrencyFlowState* = ref object of BaseFlowState
    outOf*: string
    cb*: proc()
method getType*(state: OutOfCurrencyFlowState): FlowStateType = WindowFS
method getFilters*(state: OutOfCurrencyFlowState): seq[FlowStateType] = return @[]