import logging, tables, sequtils, typetraits, variant, times, opengl, strutils
import rod / [ component, viewport, node ]
import rod / tools / debug_draw
import nimx / [ matrixes, types, formatted_text, font ]
import secureHash, math, random, hashes


type FlowStateType* = enum
    BaseFS
    LoadingFS
    WindowFS
    MapFS
    SlotFS
    TutorialFS
    RewardsFS
    MapQuestFS
    TournamentFinishFS
    TournamentWindowFS
    MapMessageBarFS
    ConfigFS
    ZoomMapFS
    NarrativeFS

    # slot's states
    SlotRoundFS
    SlotRoundEndFS
    UpdateGUIFS
    UpdateSlotTaskProgresFS
    ServerRequestFS
    SpinAnimationFS
    SlotStageFS
    StageActionFS

    ForceStopFS

    SpinFS
    FreespinFS
    RespinFS


type
    FlowStateRecord = ref object of RootObj
        startTime: float
        stopTime: float
        name: string
        level: int
        toClose: bool
        weakClose: bool
        hidenInDebug: bool

    FlowStateRecordComponent* = ref object of Component
        manager*: FlowManager
        textSize*: float32
        speed*: float32

    BaseFlowState* = ref object of RootObj
        name*: string
        data*: Variant
        parent*: BaseFlowState
        child*: BaseFlowState
        weakClose: bool
        toClose: bool
        record: FlowStateRecord

    FlowManager* = ref object
        name*: string
        currentState*: BaseFlowState
        pendingStates*: seq[BaseFlowState]
        flowRecords*: seq[FlowStateRecord]



method getType*(state: BaseFlowState): FlowStateType {.base.} = BaseFS
method getFilters*(state: BaseFlowState): seq[FlowStateType] {.base.} = return @[LoadingFS, MapFS, SlotFS]
method wakeUp*(state: BaseFlowState) {.base.} = discard
method wakeUp*(state: BaseFlowState, manager: FlowManager) {.base.} = discard
method appearsOn*(state: BaseFlowState, current: BaseFlowState): bool {.base.} = state.getType() in current.getFilters()

template dlog(body: untyped)=
    when defined(debugFlow):
        body

# ======== FlowRecords =============
const maxFlowRecords = 400

proc getStateLevel(state: BaseFlowState, level: var int) =
    if not state.parent.isNil:
        level.inc
        state.parent.getStateLevel(level)

proc getTextWidth(text: string, size: float ): float32 =
    let font = systemFontOfSize(size)
    result = font.sizeOfString(text).width

proc addFlowRecord(manager: FlowManager, state: BaseFlowState): FlowStateRecord =
    var rec = FlowStateRecord.new()
    rec.startTime = epochTime()
    rec.name = state.name
    state.getStateLevel(rec.level)
    if manager.flowRecords.len > maxFlowRecords:
        var alive = newSeq[FlowStateRecord]()
        for rec in manager.flowRecords:
            if not rec.hidenInDebug:
                alive.add(rec)

        manager.flowRecords = alive

    manager.flowRecords.add(rec)
    result = rec

# var prevTextBounds: Vector4
const startX = 1200.0
proc colorFromName(n: string): Color =
    let nameHash = $n.secureHash()
    let r = parseHexInt(nameHash[1 .. 2]) / 255
    let g = parseHexInt(nameHash[3 .. 4]) / 255
    let b = parseHexInt(nameHash[6 .. 7]) / 255

    result = newColor(r,g,b,1.0)

proc drawFlowRecord(rec: FlowStateRecord, v: SceneView, textSize: float32, speed: float32, prevTextBounds: var Vector4) =

    let step = 35.0

    let text = rec.name.replace("FlowState", "FS")
    let currTime = epochTime()
    let y = rec.level.float32 * step + 20.0
    let point1 = newVector3(startX + (rec.startTime - currTime) * speed, y, 0.0)
    var point2 = newVector3(startX, y, 0.0)
    if rec.stopTime > 0:
        point2.x = startX + (rec.stopTime - currTime) * speed

    var wp1 = v.screenToWorldPoint(point1)
    var wp2 = v.screenToWorldPoint(point2)
    wp1.z = 0.0
    wp2.z = 0.0

    let textW = getTextWidth(text, textSize)
    var color = newColor(1.0, 0.0, 0.0, 1.0)

    if rec.weakClose:
        color = newColor(1.0, 1.0, 0.0, 1.0)

    if rec.toClose or rec.stopTime > 0:
        color = newColor(1.0, 1.0, 1.0, 1.0)

    # var isShort = false
    var textY = wp1.y - textSize - 2.0

    var curTextBounds = newVector4(wp2.x - textW, textY, textW, textSize)
    if prevTextBounds.y > 0.0:
        if curTextBounds.y <= prevTextBounds.y + 1 and curTextBounds.x < prevTextBounds.x + prevTextBounds.z:
            textY = prevTextBounds.y + textSize

    var textCol = colorFromName(rec.name)
    if curTextBounds.x + textW < 0.0:
        rec.hidenInDebug = true
        return
    else:
        textCol.a = (curTextBounds.x + textW) / startX
        color.a = v.screenToWorldPoint(point2).x / startX

    glLineWidth(4.0)
    DDdrawLine(v.screenToWorldPoint(point1), v.screenToWorldPoint(point2), color)
    glLineWidth(1.0)
    DDdrawText(text, newPoint(wp2.x - textW, textY), textSize, textCol)

    prevTextBounds = newVector4(wp2.x - textW, textY, textW, textSize)

proc drawPendingState(state: BaseFlowState, i: int, v: SceneView, textSize: float32) =
    let startX = startX + 20.0
    let point = newVector3(startX, i.float32 * 20.0 + 20, 0.0)
    var wp = v.screenToWorldPoint(point)
    wp.z = 0.0

    DDdrawRect(newRect(wp.x, wp.y, 25.0, 25.0), newColor(1.0, 0.0, 0.0, 1.0))
    DDdrawText(state.name, newPoint(wp.x + 35.0, wp.y), textSize, colorFromName(state.name))

method beforeDraw*(c: FlowStateRecordComponent, index: int): bool =
    var prevTextBounds = newVector4(0.0)
    for rec in c.manager.flowRecords:
        if not rec.hidenInDebug:
            rec.drawFlowRecord(c.node.sceneView, c.textSize, c.speed, prevTextBounds)

    for i, v in c.manager.pendingStates:
        v.drawPendingState(i, c.node.sceneView, c.textSize)

registerComponent(FlowStateRecordComponent, "Falcon")


proc newFlowState*(T: typedesc): T =
    var res: T
    res.new()
    res.name = typetraits.name(T)
    result = res


proc newFlowState*(T: typedesc, data: Variant): T =
    var res: T
    res.new()
    res.name = typetraits.name(T)
    res.data = data
    result = res


proc newFlowManager*(name: string): FlowManager =
    result = FlowManager(
        name: name,
        pendingStates: @[],
        flowRecords: @[],
        currentState: BaseFlowState.newFlowState()
    )
    result.currentState.record = result.addFlowRecord(result.currentState)

# ======== FlowStates =============

proc execute*(manager: FlowManager, state: BaseFlowState)
method onClose*(state: BaseFlowState) {.base.} = discard
proc removeState(manager: FlowManager, state: BaseFlowState)

proc closeUnactiveStates(manager: FlowManager) =
    if manager.currentState.toClose and manager.currentState.child.isNil:
        if not manager.currentState.parent.isNil:
            dlog:
                info " > ", manager.name, " > closeUnactiveStates ", manager.currentState.name

            manager.removeState(manager.currentState)
            manager.closeUnactiveStates()

proc onFlowChanged(manager: FlowManager) =
    manager.closeUnactiveStates()
    var exec = false
    var curr = manager.currentState

    var index = 0
    while index < manager.pendingStates.len:
        let state = manager.pendingStates[index]
        if state.appearsOn(manager.currentState):
            manager.pendingStates.delete(index)
            manager.execute(state)
            manager.onFlowChanged()
            exec = true
        else:
            inc index

    if not exec and curr.weakClose:
        curr.toClose = true
        if not curr.record.isNil:
            curr.record.toClose = true
        manager.onFlowChanged()

proc removeState(manager: FlowManager, state: BaseFlowState) =
    assert(not state.isNil)
    state.onClose()
    if not state.record.isNil:
        state.record.stopTime = epochTime()
        state.record = nil
    manager.currentState = state.parent
    manager.currentState.child = nil

proc pop*(manager: FlowManager, state: BaseFlowState) =
    dlog:
        info " > ", manager.name, " > pop ", state.name
    let index = manager.pendingStates.find(state)
    if index > -1:
        manager.pendingStates.delete(index)
        return

    assert(not state.parent.isNil, "Try to pop base FlowState")

    if not state.child.isNil:
        state.toClose = true
        state.record.toCLose = true
    elif not state.toClose:
        manager.removeState(state)
        manager.onFlowChanged()

proc weakPop*(manager: FlowManager, state: BaseFlowState)=
    state.weakClose = true
    if not state.record.isNil:
        state.record.weakClose = true
    manager.onFlowChanged()

proc execute*(manager: FlowManager, state: BaseFlowState) =
    dlog:
        info " > ", manager.name, " > execute ", state.name

    let index = manager.pendingStates.find(state)
    if index > -1:
        manager.pendingStates.delete(index)

    let prewState = manager.currentState
    manager.currentState = state
    manager.currentState.parent = prewState
    prewState.child = manager.currentState

    manager.currentState.record = manager.addFlowRecord(manager.currentState)
    manager.currentState.wakeUp()
    manager.currentState.wakeUp(manager)

proc pushBack*(manager: FlowManager, state: BaseFlowState) =
    if state.name.len == 0:
        state.name = typetraits.name(state.type)
        error "State `" & state.name & "` has no name. Please use constructor `newFlowState`"
    dlog:
        info " > ", manager.name, " > pushBack ", state.name
    manager.pendingStates.add(state)
    manager.onFlowChanged()

proc pushBack*(manager: FlowManager, state: typedesc) =
    var res: state
    res.new()
    res.name = typetraits.name(state)
    manager.pushBack(res)

proc pushFront*(manager: FlowManager, state: BaseFlowState) =
    if state.name.len == 0:
        state.name = typetraits.name(state.type)
        error "State `" & state.name & "` has no name. Please use constructor `newFlowState`"
    dlog:
        info " > ", manager.name, " > pushFront ", state.name
    manager.pendingStates.insert(state, 0)
    manager.onFlowChanged()

proc pushFront*(manager: FlowManager, state: typedesc) =
    var res: state
    res.new()
    res.name = typetraits.name(state)
    manager.pushFront(res)

proc findActiveStateRecursive*(manager: FlowManager, state: BaseFlowState, ff: proc(state: BaseFlowState): bool): BaseFlowState =
    if ff(state):
        return state
    elif not state.parent.isNil:
        return manager.findActiveStateRecursive(state.parent, ff)

proc findActiveState*(manager: FlowManager, kind: typedesc): BaseFlowState =
    result = manager.findActiveStateRecursive(manager.currentState) do(state: BaseFlowState) -> bool:
        result = state of kind

proc findActiveState*(manager: FlowManager, ff: proc(state: BaseFlowState): bool): BaseFlowState =
    result = manager.findActiveStateRecursive(manager.currentState, ff) 

proc findPendingState*(manager: FlowManager, kind: typedesc): BaseFlowState =
    for state in manager.pendingStates:
        if state of kind:
            return state

proc findFlowState*(manager: FlowManager, kind: typedesc): BaseFlowState =
    result = manager.findActiveState(kind)
    if result.isNil:
        result = manager.findPendingState(kind)

proc closeAllActiveStatesRecursive(state: BaseFlowState) =
    dlog:
        info " > closeAllActiveStatesRecursive ", state.name
    if state.parent.isNil:
        return

    state.toClose = true
    state.weakClose = false
    if not state.parent.isNil:
        state.parent.closeAllActiveStatesRecursive()
        # onFlowChanged()

proc closeAllActiveStates*(manager: FlowManager) =
    dlog:
        info " > ", manager.name, " > closeAllActiveStates "
    manager.currentState.closeAllActiveStatesRecursive()
    manager.onFlowChanged()

proc cleanPendingStates*(manager: FlowManager, state: typedesc) =
    var index = 0
    while index < manager.pendingStates.len:
        let v = manager.pendingStates[index]
        if v of state:
            v.weakClose = false
            manager.pendingStates.delete(index)
        else:
            inc index

proc removeAllFlowStates*(manager: FlowManager) =
    manager.pendingStates.setLen(0)
    manager.closeAllActiveStates()

# DEBUGING
proc dumpActiveRecursive(state: BaseFlowState) =
    info "\tactiveState ", state.name, " close ", state.toClose, "  weakClose ", state.weakClose

    if not state.parent.isNil:
        state.parent.dumpActiveRecursive()

proc dumpActive*(manager: FlowManager)=
    info "\n", manager.name, ":\n"
    info " ALL_ACTIVE_STATES "
    if not manager.currentState.isNil:
        manager.currentState.dumpActiveRecursive()

proc dumpPending*(manager: FlowManager)=
    info "\n", manager.name, ":\n"
    info " ALL_PENDING_STATES "
    for i, v in manager.pendingStates:
        info "\tpendingState ", v.name

proc dumpRecords*(manager: FlowManager, count: int) =
    info "\n", manager.name, ":\n"
    info " FLOW RECORDS "
    var startPos = manager.flowRecords.len() - count
    if manager.flowRecords.len() <= count:
        startPos = 0

    for i in startPos ..< manager.flowRecords.len():
        let rec = manager.flowRecords[i]
        var shift = ""
        for _ in 1 .. rec.level:
            shift &= "\t"

        var diff = rec.stopTime - rec.startTime
        if diff < 0.01: diff = 0.0
        info shift, " name ", rec.name, " level ", rec.level
        info shift, " startTime ", rec.startTime, " stopTime ", rec.stopTime, "  diff  ", diff
        info shift, " toClose ", rec.toClose, " weakClose ", rec.weakClose, "  stoped ", rec.stopTime > 0.0
        info "\n"

proc printFlowStates*(manager: FlowManager) =
    info "\n", manager.name, ":\n"
    info " >> CURRENT FLOW << "
    manager.dumpActive()
    manager.dumpPending()
    manager.dumpRecords(30)

