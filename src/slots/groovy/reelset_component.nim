import random, strutils, json, algorithm, tables

import nimx / [image, types, property_visitor, animation, matrixes, timer]

import rod / [node, rod_types, viewport, component, component.solid, tools.serializer]

import utils.helpers
import shared.game_scene
import reel_component
import cell_component

type ReelsetComponent* = ref object of Component
    mRows: int
    mCols: int

    mRowsOffset*: int

    mStepX: float32
    mStepY: float32

    mReelsPositions: array[5, Vector3]
    mReelAnchor: Vector3

    mShiftSpeed: float32

    reels*: seq[ReelComponent]
    cellsWpos*: seq[seq[Vector3]]
    cellsPos*: seq[seq[Vector3]]
    cellTextureCache: TableRef[int, SelfContainedImage]
    mCellTextureOffset: Vector3
    startTimings*: seq[float32]
    stopTimings*: seq[float32]

    canStop*: bool

    pathToCellComp: string

    fadeNode*: Node
    frontNode*: Node

    stopAnims: seq[Animation]

    exceptions: seq[seq[int]]

    mInDuration: float
    mOutDuration: float
    mInTimingFunction: TimingFunctionProperty
    mOutTimingFunction: TimingFunctionProperty

method init*(rc: ReelsetComponent) =
    procCall rc.Component.init()
    rc.reels = @[]
    rc.startTimings = @[]
    rc.stopTimings = @[]

    rc.mInTimingFunction = new(TimingFunctionProperty)
    rc.mOutTimingFunction = new(TimingFunctionProperty)
    rc.cellTextureCache = newTable[int, SelfContainedImage]()

    rc.exceptions = newSeq[seq[int]](5)

proc checkReq(rc: ReelsetComponent): bool =
    rc.pathToCellComp.len > 0 and rc.mRows != 0 and rc.mCols != 0 and rc.mShiftSpeed != 0

proc update*(rc: ReelsetComponent) =
    if rc.checkReq():
        rc.node.removeAllChildren()
        var colCounter = 0
        rc.reels = @[]

        rc.cellsWpos = newSeq[seq[Vector3]](rc.mCols)
        rc.cellsPos = newSeq[seq[Vector3]](rc.mCols)
        for col in 0..<rc.mCols:
            let reelNode = rc.node.newChild("reel_" & $col)

            rc.cellsWpos[col] = newSeq[Vector3](rc.mRows)
            rc.cellsPos[col] = newSeq[Vector3](rc.mRows)
            reelNode.position = rc.mReelsPositions[col]
            reelNode.anchor = rc.mReelAnchor

            for row in 0..<rc.mRows+rc.mRowsOffset:
                let cellNode = newNodeWithResource(rc.pathToCellComp)
                cellNode.position = newVector3(0.0, rc.mStepY * row.float32, 0.0)
                reelNode.addChild(cellNode)
                let cellComponent = cellNode.getComponent(CellComponent)

                if row >= 0 and row < rc.mRows and col >= 0 and col < rc.mCols:
                    if not cellComponent.isNil:
                        discard cellComponent.debugPlay(OnIdle, -1, rc.exceptions[col], nil, true)

                    rc.cellsWpos[col][row] = cellNode.worldPos()
                    rc.cellsPos[col][row] = cellNode.position

            let reelComponent = reelNode.addComponent(ReelComponent)
            reelComponent.id = col
            reelComponent.prototype = newNodeWithResource(rc.pathToCellComp)
            reelComponent.prototype.position = newVector3(0.0, 0.0, 0.0) #rc.mStepX * col.float32
            # reelComponent.rowOffset = rc.mRowsOffset
            reelComponent.shiftSpeed = rc.mShiftSpeed
            # reelComponent.idleSpinAnim = rc.mIdleSpinAnim
            reelComponent.cellTextureCache = rc.cellTextureCache
            reelComponent.cellTextureOffset = rc.mCellTextureOffset
            reelComponent.inDuration = rc.mInDuration
            reelComponent.outDuration = rc.mOutDuration
            reelComponent.inTimingFunction = rc.mInTimingFunction
            reelComponent.outTimingFunction = rc.mOutTimingFunction
            reelComponent.sortElems()

            # reelComponent.stopIndex = rc.mStopIndex

            rc.reels.add(reelComponent)

            if rc.startTimings.len == colCounter:
                rc.startTimings.add(0.0)

            if rc.stopTimings.len == colCounter:
                rc.stopTimings.add(0.0)

            inc colCounter

        rc.fadeNode = rc.node.newChild("fade")
        let solid = rc.fadeNode.addComponent(Solid)
        rc.fadeNode.worldPos = newVector3(0,0,0)
        rc.fadeNode.alpha = 0.0
        solid.size = newSize(1920, 1080)
        solid.color = newColor(0,0,0,0.35)
        rc.frontNode = rc.node.newChild("front_anchor")
        rc.frontNode.worldPos = newVector3(0,0,0)

template reelsAnchor(rc: ReelsetComponent): Vector3 = rc.mReelAnchor
template `reelsAnchor =`(rc: ReelsetComponent, v: Vector3) =
    rc.mReelAnchor = v
    for r in rc.reels:
        r.node.anchor = v

template cellTextureOffset(rc: ReelsetComponent): Vector3 = rc.mCellTextureOffset
template `cellTextureOffset=`(rc: ReelsetComponent, v: Vector3) =
    rc.mCellTextureOffset = v
    for reel in rc.reels:
        reel.cellTextureOffset = v

template inTimingFunction(rc: ReelsetComponent): TimingFunctionProperty = rc.mInTimingFunction
template `inTimingFunction=`(rc: ReelsetComponent, v: TimingFunctionProperty)=
    rc.mInTimingFunction = v
    for reel in rc.reels:
        reel.inTimingFunction = v

template outTimingFunction(rc: ReelsetComponent): TimingFunctionProperty = rc.mOutTimingFunction
template `outTimingFunction=`(rc: ReelsetComponent, v: TimingFunctionProperty)=
    rc.mOutTimingFunction = v
    for reel in rc.reels:
        reel.outTimingFunction = v

template inDuration(rc: ReelsetComponent): float32 = rc.mInDuration
template `inDuration=`(rc: ReelsetComponent, v: float32) =
    rc.mInDuration = v
    for reel in rc.reels:
        reel.inDuration = v

template outDuration(rc: ReelsetComponent): float32 = rc.mOutDuration
template `outDuration=`(rc: ReelsetComponent, v: float32) =
    rc.mOutDuration = v
    for reel in rc.reels:
        reel.outDuration = v

template rows*(rc: ReelsetComponent): int = rc.mRows
template `rows=`*(rc: ReelsetComponent, v: int) =
    rc.mRows = v

template cols*(rc: ReelsetComponent): int = rc.mCols
template `cols=`*(rc: ReelsetComponent, v: int) =
    rc.mCols = v

template rowsOffset*(rc: ReelsetComponent): int = rc.mRowsOffset
template `rowsOffset=`*(rc: ReelsetComponent, v: int) =
    rc.mRowsOffset = v

template stepX*(rc: ReelsetComponent): float32 = rc.mStepX
template `stepX=`*(rc: ReelsetComponent, v: float32) =
    rc.mStepX = v

template stepY*(rc: ReelsetComponent): float32 = rc.mStepY
template `stepY=`*(rc: ReelsetComponent, v: float32) =
    rc.mStepY = v

template shiftSpeed*(rc: ReelsetComponent): float32 = rc.mShiftSpeed
template `shiftSpeed=`*(rc: ReelsetComponent, v: float32) =
    rc.mShiftSpeed = v
    for reel in rc.reels:
        reel.shiftSpeed = rc.mShiftSpeed

method serialize*(rc: ReelsetComponent, s: Serializer): JsonNode =
    var chNodes = newSeq[Node]()
    while rc.node.children.len > 0:
        chNodes.add(rc.node.children[0])
        rc.node.children[0].removeFromParent()

    result = newJObject()
    result.add("cols", s.getValue(rc.cols))
    result.add("rows", s.getValue(rc.rows))
    result.add("rowsOffset", s.getValue(rc.rowsOffset))
    result.add("stepX", s.getValue(rc.stepX))
    result.add("stepY", s.getValue(rc.stepY))
    result.add("shiftSpeed", s.getValue(rc.shiftSpeed))
    result.add("startTimings", s.getValue(rc.startTimings))
    result.add("stopTimings", s.getValue(rc.stopTimings))
    result.add("pathToCellComp", s.getValue(rc.pathToCellComp))
    result.add("textureOffset", s.getValue(rc.mCellTextureOffset))
    result.add("inDuration", s.getValue(rc.inDuration))
    result.add("outDuration", s.getValue(rc.outDuration))
    result.add("inTimingFunction", s.getValue(rc.mInTimingFunction.args))
    result.add("outTimingFunction", s.getValue(rc.mOutTimingFunction.args))

    for i, pos in rc.mReelsPositions:
        result.add("reelPos" & $i, s.getValue(pos))
    result.add("reelsAnchor", s.getValue(rc.mReelAnchor))

    rc.node.sceneView.wait(0.5) do():
        for ch in chNodes:
            rc.node.addChild(ch)

method deserialize*(rc: ReelsetComponent, j: JsonNode, s: Serializer) =
    s.deserializeValue(j, "cols", rc.cols)
    s.deserializeValue(j, "rows", rc.rows)
    s.deserializeValue(j, "rowsOffset", rc.rowsOffset)
    s.deserializeValue(j, "stepX", rc.stepX)
    s.deserializeValue(j, "stepY", rc.stepY)
    s.deserializeValue(j, "shiftSpeed", rc.shiftSpeed)
    s.deserializeValue(j, "startTimings", rc.startTimings)
    s.deserializeValue(j, "stopTimings", rc.stopTimings)
    s.deserializeValue(j, "pathToCellComp", rc.pathToCellComp)
    s.deserializeValue(j, "textureOffset", rc.cellTextureOffset)
    s.deserializeValue(j, "inDuration", rc.inDuration)
    s.deserializeValue(j, "outDuration", rc.outDuration)
    s.deserializeValue(j, "reelsAnchor", rc.mReelAnchor)

    for i in 0 ..< rc.mReelsPositions.len:
        var v: Vector3
        s.deserializeValue(j, "reelPos" & $i, v)
        rc.mReelsPositions[i] = v

    var inta: Vector4
    s.deserializeValue(j, "inTimingFunction", inta)
    for i, v in inta:
        rc.mInTimingFunction.args[i] = v

    var outa: Vector4
    s.deserializeValue(j, "outTimingFunction", outa)
    for i, v in outa:
        rc.mOutTimingFunction.args[i] = v

    rc.update()

template `[]`*(rc: ReelsetComponent, i: int): ReelComponent =
    rc.reels[i]

template `[]=`*(rc: ReelsetComponent, i: int; x: ReelComponent) =
    rc.reels[i] = x

iterator cells*(rc: ReelsetComponent): CellComponent =
    for i in 0..<rc.cols:
        let colCh = rc.reels[i].node.children
        for cn in colCh:
            let c = cn.getComponent(CellComponent)
            yield c

proc cellAt(rc: ReelsetComponent, i: int): CellComponent =
    let reel = rc.reels[i mod rc.reels.len]
    return reel.node.children[i div rc.reels.len].getComponent(CellComponent)

proc `field=`*(rc: ReelsetComponent, field:seq[int])=
    for i in 0..<rc.cols:
        for j in 0..<rc.rows:
            let idx = j * rc.cols + i
            let cell = rc.cellAt(idx)
            cell.play(field[idx], OnIdle)

proc setExceptions*(rc: ReelsetComponent, expts: seq[seq[int]] = @[]) =
    rc.exceptions = expts

proc rebuildTextureCache*(rc: ReelsetComponent) =
    if not rc.cellTextureCache.isNil:
        rc.cellTextureCache.clear()

    for i in rc.reels:
        i.initTextureCache()

proc play*(rc: ReelsetComponent, cb: proc() = nil) =
    for i in rc.reels:
        i.initTextureCache()

    rc.canStop = false
    var started = 0
    proc onStart()=
        inc started
        if started == rc.startTimings.len and not cb.isNil():
            rc.canStop = true
            cb()

    let gs = rc.node.sceneView.GameScene
    for i, t in rc.startTimings:
        closureScope:
            let it = i
            gs.setTimeout(t) do():
                if rc.exceptions.len > it:
                    rc.reels[it].setExceptions(rc.exceptions[it])
                rc.reels[it].play() do():
                    onStart()

proc stopWithTimings(rc: ReelsetComponent, cb: proc(reelIndex: int)) =
    rc.stopAnims = @[]
    for i, t in rc.stopTimings:
        closureScope:
            let it = i
            var anim = newAnimation()
            anim.loopDuration = t
            anim.numberOfLoops = 1
            rc.node.addAnimation(anim)
            anim.onComplete do():
                cb(it)
            rc.stopAnims.add(anim)

proc stop*(rc: ReelsetComponent, rs: seq[seq[int]], cb: proc(reelIndex: int)= nil) =
    if not rc.canStop:
        return
        
    rc.stopWithTimings do(reelId: int):
        rc.reels[reelId].stop(rs[reelId]) do():
            cb(reelId)

proc stop*(rc: ReelsetComponent, rs: seq[seq[int]], cb: proc()) =
    if not rc.canStop:
        return

    var reelStopperCounter = 0
    rc.stop(rs) do(reelIndex: int):
        inc reelStopperCounter
        if reelStopperCounter == rc.cols:
            cb()

import random
proc shuffledStop*(rc: ReelsetComponent, rs: seq[seq[int]], cb: proc(reelIndex: int) = nil)=
    if not rc.canStop:
        return

    var reels = rc.reels
    reels.shuffle()

    var ri = 0
    while ri < reels.len - 1:
        var r1 = rc.reels[reels[ri].id]
        ri.inc
        var r2 = rc.reels[reels[ri].id]
        var p1 = r1.node.position
        var p2 = r2.node.position
        swap(p1, p2)

        r1.node.position = p1
        r2.node.position = p2

    reels.sort do(r1, r2: ReelComponent) -> int: cmp(r1.node.positionX, r2.node.positionX)
    rc.stopWithTimings do(reelId: int):
        let ori = reels[reelId].id
        reels[reelId].stop(rs[ori]) do():
            cb(reelId)

proc sortReels*(rc: ReelsetComponent, cb: proc(), move: proc(r1, r2: Node, cb: proc())) =
    rc.reels.sort do(r1, r2: ReelComponent) -> int: cmp(r1.id, r2.id)

    var reelsTomove = newSeq[tuple[a: int, b: int]]()

    proc movePair()=
        var reels = rc.reels
        reels.sort do(r1, r2: ReelComponent) -> int: cmp(r1.node.positionX, r2.node.positionX)

        for i, r in rc.reels:
            if r.id != reels[i].id:
                let ab = (a: r.id, b: reels[i].id)
                reelsTomove.add(ab)
                break

        if reelsTomove.len > 0:
            let (a, b) = reelsTomove[0]
            reelsTomove.delete(0)

            echo "swap ", a, " >> ", b
            move(rc.reels[a].node, rc.reels[b].node) do():
                movePair()
        else:
            cb()

    movePair()

proc forceStop*(rc: ReelsetComponent) =
    for anim in rc.stopAnims:
        anim.cancel()

proc setOnReelsLandProc*(rc: ReelsetComponent, time: float32, cb: proc(reelID: int)) =
    for reel in rc.reels:
        reel.setOnReelLandProc(time, cb)

const enableEditor = not defined(release)
when enableEditor:
    import nimx.property_editors.propedit_registry
    import nimx.property_editors.standard_editors
    import nimx.numeric_text_field
    import nimx.view
    import nimx.text_field
    import nimx.linear_layout
    import nimx.button

    import rod / component / text_component

    type InfoBoolString = ref object
        val: string

    proc newBoolStringInfoPropertyView(setter: proc(msg: InfoBoolString), getter: proc(): InfoBoolString): PropertyEditorView =
        result = PropertyEditorView.new(newRect(0, 0, 208, editorRowHeight))
        let cb = Button.new(newRect(0, 0, editorRowHeight*6, editorRowHeight))
        cb.title = getter().val
        cb.onAction do():
            setter(getter())
            cb.title = getter().val
        result.addSubview(cb)

    registerPropertyEditor(newBoolStringInfoPropertyView)


    proc newFloatSeqPropertyView(setter: proc(s: seq[float32]), getter: proc(): seq[float32]): PropertyEditorView =
        var val = getter()
        var height = val.len() * (editorRowHeight + 2) + (editorRowHeight + 2) * 2
        let pv = PropertyEditorView.new(newRect(0, 0, 208, height.Coord))
        var x = 0.Coord
        var y = (editorRowHeight + 2).float32
        for i in 0 ..< val.len:
            closureScope:
                let index = i
                x = 0.Coord
                let ntf = newNumericTextField(newRect(x, y, 50, editorRowHeight))
                pv.addSubview(ntf)
                ntf.text = $val[index]
                ntf.onAction do():
                    if index < val.len:
                        val[index] = ntf.text.parseFloat()
                        setter(val)
                y += editorRowHeight + 2
        result = pv

    registerPropertyEditor(newFloatSeqPropertyView)


    method visitProperties*(rc: ReelsetComponent, p: var PropertyVisitor) =
        template visitReelPosition(pos:int)=
            proc `reel pos`(rc: ReelsetComponent): Vector3 = rc.mReelsPositions[pos]
            proc `reel pos=`(rc: ReelsetComponent, v: Vector3) =
                rc.mReelsPositions[pos] = v
                rc.reels[pos].node.position = v

            p.visitProperty("reelPos " & $pos, rc.`reel pos`)

        visitReelPosition(0)
        visitReelPosition(1)
        visitReelPosition(2)
        visitReelPosition(3)
        visitReelPosition(4)

        p.visitProperty("reelsAnchor", rc.reelsAnchor)

        p.visitProperty("cols", rc.cols)
        p.visitProperty("rows", rc.rows)
        p.visitProperty("rows offset", rc.rowsOffset)
        p.visitProperty("stepX", rc.stepX)
        p.visitProperty("stepY", rc.stepY)
        p.visitProperty("shiftSpeed", rc.shiftSpeed)
        p.visitProperty("startTimings", rc.startTimings)
        p.visitProperty("stopTimings", rc.stopTimings)
        p.visitProperty("pathToCellComp", rc.pathToCellComp)
        p.visitProperty("textureOffset", rc.cellTextureOffset)
        p.visitProperty("inDuration", rc.inDuration)
        p.visitProperty("inEasing", rc.inTimingFunction)
        p.visitProperty("outDuration", rc.outDuration)
        p.visitProperty("outEasing", rc.outTimingFunction)



        if not rc.cellTextureCache.isNil:
            for k, c in rc.cellTextureCache:
                var valc = c.Image
                p.visitProperty("texture_" & $k, valc)

        var isPl = false
        var msg: InfoBoolString
        msg.new()
        msg.val = if isPl: "stop" else: "play"

        proc isPlay(rc: ReelsetComponent): InfoBoolString = msg
        proc `isPlay=`(rc: ReelsetComponent, msg: InfoBoolString) =

            if not isPl:
                msg.val = "stop"
                rc.play()
                isPl = not isPl
            else:
                msg.val = "play"

                var res: seq[seq[int]] = @[]
                for i, reel in rc.reels:
                    var reelSeq: seq[int] = @[]
                    for el in reel.elems:
                        reelSeq.add(el.getComponent(CellComponent).getAvailableRandomElem())
                    res.add(reelSeq)

                rc.stop(res) do(ri: int):
                    isPl = not isPl

        p.visitProperty("spin", rc.isPlay)


        var msg2: InfoBoolString
        msg2.new()
        msg2.val = "update"
        proc needUpdate(rc: ReelsetComponent): InfoBoolString = msg2
        proc `needUpdate=`(rc: ReelsetComponent, msg: InfoBoolString) =
            rc.update()
        p.visitProperty("update", rc.needUpdate)

registerComponent(ReelsetComponent, "ReelsetComponents")
