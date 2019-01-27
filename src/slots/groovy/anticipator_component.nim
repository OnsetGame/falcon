import random
import strutils
import json
import algorithm

import nimx.types
import nimx.property_visitor
import nimx.animation
import nimx.matrixes
import nimx.timer

import rod.node
import rod.rod_types
import rod.viewport
import rod.component
import rod.tools.serializer

import utils.helpers

import cell_component


type AnticipatorComponent* = ref object of Component

    pathToComp*: string

    mRows*: int
    mCols*: int

    mStepX*: float32
    mStepY*: float32

    cells*: seq[seq[CellComponent]]
    cellsWpos*: seq[seq[Vector3]]
    cellsPos*: seq[seq[Vector3]]

method init*(ac: AnticipatorComponent) =
    procCall ac.Component.init()
    ac.cells = @[]

proc checkReq(ac: AnticipatorComponent): bool =
    ac.pathToComp.len > 0 and ac.mRows != 0 and ac.mCols != 0

proc update(ac: AnticipatorComponent) =
    if ac.checkReq():
        ac.node.removeAllChildren()
        ac.cells = @[]

        ac.cellsWpos = newSeq[seq[Vector3]](ac.mCols)
        ac.cellsPos = newSeq[seq[Vector3]](ac.mCols)

        var id: int = -1
        for col in 0..<ac.mCols:
            var rowCels:seq[CellComponent] = @[]

            ac.cellsWpos[col] = newSeq[Vector3](ac.mRows)
            ac.cellsPos[col] = newSeq[Vector3](ac.mRows)

            for row in 0..<ac.mRows:
                let cellNode = newNodeWithResource(ac.pathToComp)
                cellNode.position = newVector3(ac.mStepX * col.float32, ac.mStepY * row.float32, 0.0)
                ac.node.addChild(cellNode)
                let cellComponent = cellNode.getComponent(CellComponent)
                if not cellComponent.isNil:
                    if id == -1:
                        id = cellComponent.getAvailableRandomElem()
                    cellComponent.play(id, OnShow, lpStartToEnd) do(anim: Animation):
                        discard
                    rowCels.add(cellComponent)
                ac.cellsWpos[col][row] = cellNode.worldPos()
                ac.cellsPos[col][row] = cellNode.position
            ac.cells.add(rowCels)

template `[]`*(ac: AnticipatorComponent, i: int): seq[CellComponent] =
    ac.cells[i]

template `[]=`*(ac: AnticipatorComponent, i: int; x: seq[CellComponent]) =
    ac.cells[i] = x

iterator elems*(ac: AnticipatorComponent): CellComponent =
    for i in 0..<ac.mCols:
        let colCh = ac[i]
        for c in colCh:
            yield c

proc play*(s: seq[CellComponent], elemId: int, animId: AnimationType, loopPattern: LoopPattern = lpStartToEnd, cb: proc(anim: Animation) = nil) =
    for i, el in s:
        if i == s.len-1:
            el.play(elemId, animId, loopPattern, cb)
        else:
            el.play(elemId, animId, loopPattern)

proc play*(s: seq[CellComponent], animId: AnimationType, loopPattern: LoopPattern = lpStartToEnd, cb: proc(anim: Animation) = nil) =
    for i, el in s:
        if i == s.len-1:
            el.play(animId, loopPattern, cb)
        else:
            el.play(animId, loopPattern)

proc play*(ac: AnticipatorComponent, elemId: int, animId: AnimationType, loopPattern: LoopPattern = lpStartToEnd, cb: proc(anim: Animation) = nil) =
    for col in 0..<ac.cells.len:
        if col == ac.cells.len-1:
            ac.cells[col].play(elemId, animId, loopPattern, cb)
        else:
            ac.cells[col].play(elemId, animId, loopPattern)

proc play*(ac: AnticipatorComponent, animId: AnimationType, loopPattern: LoopPattern = lpStartToEnd, cb: proc(anim: Animation) = nil) =
    for col in 0..<ac.cells.len:
        if col == ac.cells.len-1:
            ac.cells[col].play(animId, loopPattern, cb)
        else:
            ac.cells[col].play(animId, loopPattern)

proc play*(ac: AnticipatorComponent, rs: seq[seq[AnimationType]], loopPattern: LoopPattern = lpStartToEnd, cb: proc(anim: Animation) = nil) =
    for i, col in rs:
        for j, row in col:
            if i == rs.len-1 and j == col.len-1:
                ac.cells[i][j].play(row, loopPattern, cb)
            else:
                ac.cells[i][j].play(row, loopPattern)

proc play*(ac: AnticipatorComponent, rs: seq[seq[tuple[elemId: int, animId: AnimationType]]], loopPattern: LoopPattern = lpStartToEnd, cb: proc(anim: Animation) = nil) =
    for i, col in rs:
        for j, row in col:
            if i == rs.len-1 and j == col.len-1:
                ac.cells[i][j].play(row.elemId, row.animId, loopPattern, cb)
            else:
                ac.cells[i][j].play(row.elemId, row.animId, loopPattern)

method serialize*(ac: AnticipatorComponent, s: Serializer): JsonNode =
    var chNodes = newSeq[Node]()
    while ac.node.children.len > 0:
        chNodes.add(ac.node.children[0])
        ac.node.children[0].removeFromParent()

    result = newJObject()
    result.add("pathToComp", s.getValue(ac.pathToComp))
    result.add("mRows", s.getValue(ac.mRows))
    result.add("mCols", s.getValue(ac.mCols))
    result.add("mStepX", s.getValue(ac.mStepX))
    result.add("mStepY", s.getValue(ac.mStepY))

    ac.node.sceneView.wait(0.5) do():
        for ch in chNodes:
            ac.node.addChild(ch)


method deserialize*(ac: AnticipatorComponent, j: JsonNode, s: Serializer) =
    s.deserializeValue(j, "pathToComp", ac.pathToComp)
    s.deserializeValue(j, "mRows", ac.mRows)
    s.deserializeValue(j, "mCols", ac.mCols)
    s.deserializeValue(j, "mStepX", ac.mStepX)
    s.deserializeValue(j, "mStepY", ac.mStepY)

    ac.update()

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


    method visitProperties*(ac: AnticipatorComponent, p: var PropertyVisitor) =
        p.visitProperty("pathToComp", ac.pathToComp)
        p.visitProperty("mRows", ac.mRows)
        p.visitProperty("mCols", ac.mCols)
        p.visitProperty("mStepX", ac.mStepX)
        p.visitProperty("mStepY", ac.mStepY)



        var msg: InfoBoolString
        msg.new()
        msg.val = "play"

        proc isPlay(ac: AnticipatorComponent): InfoBoolString = msg
        proc `isPlay=`(ac: AnticipatorComponent, msg: InfoBoolString) =
            var res: seq[seq[tuple[elemId: int, animId: AnimationType]]] = @[]
            for i, reel in ac.cells:
                var reelSeq: seq[tuple[elemId: int, animId: AnimationType]] = @[]
                for cc in reel:
                    reelSeq.add((cc.getAvailableRandomElem(), cc.getRandomAnimType()))
                res.add(reelSeq)

            ac.play(res)


        p.visitProperty("spin", ac.isPlay)


        var msg2: InfoBoolString
        msg2.new()
        msg2.val = "update"
        proc needUpdate(ac: AnticipatorComponent): InfoBoolString = msg2
        proc `needUpdate=`(ac: AnticipatorComponent, msg: InfoBoolString) =
            ac.update()
        p.visitProperty("update", ac.needUpdate)


registerComponent(AnticipatorComponent, "ReelsetComponents")
