import random
import strutils
import json
import algorithm

import nimx.types
import nimx.property_visitor
import nimx.animation
import nimx.matrixes
import nimx.image

import rod.node
import rod.rod_types
import rod.viewport
import rod.component
import rod.tools.serializer
import rod.component.sprite

import reel_loop_component
import utils.helpers
import utils.motion_blur

const enableEditor = not defined(release)

when enableEditor:
    import nimx.property_editors.propedit_registry
    import nimx.property_editors.standard_editors
    import nimx.numeric_text_field
    import nimx.view
    import nimx.text_field
    import nimx.linear_layout

proc findFirstSpriteComponent*(n: Node): Sprite =
    result = n.componentIfAvailable(Sprite)
    if result.isNil:
        for ch in n.children:
            result = ch.findFirstSpriteComponent()

proc getBottomNode(n: Node): Node =
    if n.children.len > 0:
        for ch in n.children:
            result = ch.getBottomNode()
    else:
        result = n

proc hideCellElements(n : Node) =
    for cl in n.children:
        let chIdle = cl.findNode("idle")
        if not chIdle.isNil and chIdle.alpha > 0:
            chIdle.hide()
            let anim = chIdle.animationNamed("play")
            if not anim.isNil: anim.cancel()
        let chWin = cl.findNode("win")
        if not chWin.isNil and chWin.alpha > 0:
            chWin.hide()
            let anim = chIdle.animationNamed("play")
            if not anim.isNil: anim.cancel()

#---------------------------------------------------------------------------------------------------------------------

type Reelset* = ref object of Component
    rootNode*: Node

    reelsStack*: seq[seq[int]]
    reelsStopper*: seq[bool]

    reels*: seq[Node]

    mReelsAnimationInNode*: seq[Node]
    mReelsAnimationOutNode*: seq[Node]
    mReelsAnimationSpinInNode*: seq[Node]
    mReelsAnimationSpinOutNode*: seq[Node]

    mReelAnimationInName*: string
    mReelAnimationOutName*: string
    mReelAnimationSpinInName*: string
    mReelAnimationSpinOutName*: string

    elementsName*: seq[tuple[name: string, index: int]]

    spinRandomFrom*: int
    spinRandomTo*: int

    stopCellFromTop*: int

    mNumCols: int
    mNumRows: int

    mStepX: float32
    mStepY: float32

    mReelPath: string
    mCellPath: string

    mIsLocalized: bool

    mShiftSpeed: float32

    requirements: array[7, bool]
    requirementsDone: bool
    inited: bool

    mIsSpin*: bool
    canStopSpin*: bool

    sortedCells: seq[Node]

method init*(rl: Reelset) =
    procCall rl.Component.init()

    rl.mShiftSpeed = -20.0

    rl.reelsStack = newSeq[seq[int]](rl.mNumCols)
    for i in 0..<rl.mNumCols:
        rl.reelsStack[i] = newSeq[int](3)
        for j in 0..<3:
            rl.reelsStack[i][j] = rl.spinRandomFrom + j

proc tryGetElementIndex*(rl: Reelset, name: string, res: var int): bool =
    for el in rl.elementsName:
        if el.name == name:
            res = el.index
            return true
    return false

proc elementName*(rl: Reelset, index: int): string =
    for el in rl.elementsName:
        if el.index == index:
            return el.name

proc nameSimplify*(n: Node, nodeModifier: proc(n: Node) = nil) =
    if n.name.contains("idle"):
        n.name = "idle"

        let idleAnim = n.animationNamed("play")
        if not idleAnim.isNil:
            idleAnim.numberOfLoops = -1

        if not nodeModifier.isNil:
            n.nodeModifier()
    elif n.name.contains("win"):
        n.name = "win"
        if not nodeModifier.isNil:
            n.nodeModifier()
    else:
        for ch in n.children:
            ch.nameSimplify(nodeModifier)

proc forAll*(n: Node, p: proc(n: Node)) =
    p(n)
    for c in n.children:
        c.forAll(p)

proc cancelAnims(n: Node) =
    template cancel(nd: Node, name: string) =
        let anim = nd.animationNamed(name)
        if not anim.isNil and not anim.finished:
            anim.cancel()
            anim.onProgress(0.0)

    n.forAll do(nd: Node):
        if nd.name.contains("idle"):
            nd.cancel("play")
        elif nd.name.contains("win"):
            nd.cancel("play")


proc playIdle*(rl: Reelset, n: Node, index: int, bPlayIdle: bool = true) =
    let cellNode = n.findNode(rl.elementName(index))
    n.hideCellElements()

    if not cellNode.isNil:
        for ch in cellNode.parent.children:
            ch.hide()
        cellNode.show()

        let currIdleNode = cellNode.findNode("idle")
        if not currIdleNode.isNil:

            currIdleNode.show()

            if bPlayIdle:
                n.cancelAnims()
                # currIdleNode.showReq()
                let idleAnim = currIdleNode.animationNamed("play")
                idleAnim.onProgress(0.0)
                n.addAnimation(idleAnim)
                let idleSpriteNode = currIdleNode.findNode("idle")

                if not idleSpriteNode.isNil:
                    let sprt = idleSpriteNode.findFirstSpriteComponent()
                    if not sprt.isNil:
                        sprt.node.show()
                        sprt.node.parent.show()
                        # let mb = sprt.node.component(MotionBlur)

proc playWin*(rl: Reelset, n: Node, index: int, callback: proc() = nil): float {.discardable.} =
    let cellNode = n.findNode(rl.elementName(index))
    n.hideCellElements()
    if not cellNode.isNil:
        let currWinNode = cellNode.findNode("win")
        if not currWinNode.isNil:
            currWinNode.show()
            currWinNode.parent.show()
            let winNdAnim = currWinNode.animationNamed("play")
            winNdAnim.onProgress(0.0)
            n.addAnimation(winNdAnim)
            winNdAnim.onComplete do():
                if not callback.isNil: callback()
            result = winNdAnim.loopDuration

proc getSortedNodes*(rl: Reelset, reelIndex: int): seq[Node] =
    let reelNodeAnchor = rl.reels[reelIndex]

    if rl.sortedCells.len != reelNodeAnchor.children.len:
        rl.sortedCells = newSeq[Node](reelNodeAnchor.children.len)

    for i, ch in reelNodeAnchor.children:
        rl.sortedCells[i] = ch

    rl.sortedCells.sort do (n1, n2: Node) -> int:
        result = cmp(n1.worldPos.y, n2.worldPos.y)

    result = rl.sortedCells

proc tryInit(rl: Reelset)
proc checkRequirements(rl: Reelset) =
    rl.requirements[0] = rl.mStepX > 0
    rl.requirements[1] = rl.mStepY > 0
    rl.requirements[2] = rl.mNumCols > 0
    rl.requirements[3] = rl.mNumRows > 0
    rl.requirements[4] = rl.mReelPath.len > 0
    rl.requirements[5] = rl.mCellPath.len > 0
    rl.requirements[6] = not rl.rootNode.isNil

    for i, rq in rl.requirements:
        if not rq: break
        if i == rl.requirements.len-1:
            rl.requirementsDone = true

    rl.tryInit()

proc findNodeWithAnimNamed(n: Node, name: string): Node =
    if not n.animationNamed(name).isNil:
        result = n
    else:
        for ch in n.children:
            result = ch.findNodeWithAnimNamed(name)

proc initReelAnims(rl: Reelset, reelNode: Node) =
    if rl.mReelAnimationInName.len > 0:
        let nd = reelNode.findNodeWithAnimNamed(rl.mReelAnimationInName)
        if not nd.isNil:
            rl.mReelsAnimationInNode.add(nd)
    if rl.mReelAnimationOutName.len > 0:
        let nd = reelNode.findNodeWithAnimNamed(rl.mReelAnimationOutName)
        if not nd.isNil:
            rl.mReelsAnimationOutNode.add(nd)
    if rl.mReelAnimationSpinInName.len > 0:
        let nd = reelNode.findNodeWithAnimNamed(rl.mReelAnimationSpinInName)
        if not nd.isNil:
            rl.mReelsAnimationSpinInNode.add(nd)
    if rl.mReelAnimationSpinOutName.len > 0:
        let nd = reelNode.findNodeWithAnimNamed(rl.mReelAnimationSpinOutName)
        if not nd.isNil:
            rl.mReelsAnimationSpinOutNode.add(nd)

method setInitialElems*(rl: Reelset) {.base.} =
    for col in 0..<rl.mNumCols:
        let srtNds = rl.getSortedNodes(col)
        let offset = rl.mNumRows div 2 - 1 # TODO use manual setted offset
        const NUM_ROWS = 3
        for row in offset..<offset+NUM_ROWS:
            let cell = srtNds[row]
            if rl.spinRandomFrom < rl.spinRandomTo:
                rl.playIdle(cell, rand(rl.spinRandomFrom..rl.spinRandomTo))
            else:
                rl.playIdle(cell, rl.spinRandomFrom)

proc tryInit(rl: Reelset) =
    if not rl.requirementsDone:
        return
    if not rl.inited:
        if rl.rootNode.children.len > 0:
            for ch in rl.rootNode.children:
                if not ch.isNil: ch.removeFromParent()
        try:
            rl.reels = @[]
            for col in 0..<rl.mNumCols:
                let reel = if rl.mIsLocalized: newLocalizedNodeWithResource(rl.mReelPath) else: newNodeWithResource(rl.mReelPath)
                reel.name = "reel_" & $col
                reel.positionX = col.float32 * rl.mStepX
                rl.rootNode.addChild(reel)

                var reelAnchor = reel.getBottomNode()
                rl.reels.add(reelAnchor)

                rl.initReelAnims(reel)

                for row in 0..<rl.mNumRows:
                    let cell = if rl.mIsLocalized: newLocalizedNodeWithResource(rl.mCellPath) else: newNodeWithResource(rl.mCellPath)
                    cell.positionY = row.float32 * rl.mStepY
                    cell.name = $row
                    reelAnchor.addChild(cell)

                    if rl.elementsName.len == 0:
                        for i, ch in cell.children:
                            rl.elementsName.add( (ch.name, i) )

                    cell.nameSimplify do(n: Node): n.hide()

            rl.setInitialElems()

            rl.inited = true
        finally:
            discard

method spin*(rl: Reelset, reelIndex: int, onCanStop: proc() = nil, onStop: proc() = nil) {.base.} =
    let animIn = if rl.mReelsAnimationInNode.len == rl.reels.len: rl.mReelsAnimationInNode[reelIndex].animationNamed(rl.mReelAnimationInName) else: nil
    let animOut = if rl.mReelsAnimationOutNode.len == rl.reels.len: rl.mReelsAnimationOutNode[reelIndex].animationNamed(rl.mReelAnimationOutName) else: nil
    let animSpinIn = if rl.mReelsAnimationSpinInNode.len == rl.reels.len: rl.mReelsAnimationSpinInNode[reelIndex].animationNamed(rl.mReelAnimationSpinInName) else: nil
    let animSpinOut = if rl.mReelsAnimationSpinOutNode.len == rl.reels.len: rl.mReelsAnimationSpinOutNode[reelIndex].animationNamed(rl.mReelAnimationSpinOutName) else: nil

    # TODO implement animSpinIn animSpinOut

    let reelNode = rl.reels[reelIndex].parent
    let reelNodeAnchor = rl.reels[reelIndex] # also can be anim node
    let v = rl.rootNode.sceneView

    var reelLoopComp = reelNodeAnchor.componentIfAvailable(ReelLoop)
    if reelLoopComp.isNil:
        reelLoopComp = reelNodeAnchor.component(ReelLoop)
    else:
        reelLoopComp.handleReel()

    var doMove = false
    var stopCounter = 0
    var jumps = 0
    var bStop = false

    # ADD INIT JUMP ANIM
    if not animIn.isNil:
        if reelNodeAnchor.positionX != 0 or reelNodeAnchor.positionY != 0 or reelNodeAnchor.positionZ != 0: # swap translation betwen animated node and stable parent node
            reelNode.position = reelNode.position + reelNodeAnchor.position
            reelNodeAnchor.position = newVector3(0,0,0)

        v.addAnimation(animIn)
        animIn.onComplete do():
            animIn.removeHandlers()
            doMove = true
    else:
        doMove = true


    let onJump = proc(n: Node) =
        let jumsLimit = rl.mNumRows

        if jumps == jumsLimit:
            if not onCanStop.isNil:
                onCanStop()
        inc jumps

        # TODO STOP AFTER PREV
        # let isPrevReelStoppped = (reelIndex != 0 and not rl.reelsStopper[reelIndex-1]) or reelIndex == 0
        # if stopCounter == 0 and (not rl.reelsStopper[reelIndex] or jumps < jumsLimit or not isPrevReelStoppped):

        if not rl.reelsStopper[reelIndex] or jumps < jumsLimit:
            # if not rl.reelsStopper.isNil and rl.reelsStopper[reelIndex] and not rl.reelsStack.isNil:
            #     rl.playIdle(n, rl.reelsStack[reelIndex][stopCounter], false)
            #     inc stopCounter
            # else:
            #     if rl.spinRandomFrom < rl.spinRandomTo:
            #         rl.playIdle(n, rand(rl.spinRandomFrom..rl.spinRandomTo), false)
            #     else:
            #         rl.playIdle(n, rl.spinRandomFrom, false)

            if reelIndex == rl.reels.len-1 and jumps < jumsLimit:
                rl.canStopSpin = false

            if rl.spinRandomFrom < rl.spinRandomTo:
                rl.playIdle(n, rand(rl.spinRandomFrom..rl.spinRandomTo), false)
            else:
                rl.playIdle(n, rl.spinRandomFrom, false)
        else:
            if stopCounter < rl.reelsStack[reelIndex].len:
                rl.playIdle(n, rl.reelsStack[reelIndex][stopCounter])
                inc stopCounter
            else:
                if not bStop:

                    bStop = true
                    reelLoopComp.anim.cancel()

                    # DO ALIGN
                    reelNodeAnchor.position = newVector3(0,0,0)
                    reelNode.position = newVector3(0,0,0)

                    let reelNodes = rl.getSortedNodes(reelIndex)
                    for i, nd in reelNodes:
                        nd.worldPos = reelLoopComp.worldPosElems[i]

                        # FILL REEL WITH RIGHT ELEMS
                        if i >= rl.stopCellFromTop:
                            rl.playIdle(nd, rl.reelsStack[reelIndex][i - rl.stopCellFromTop])

                    # HIDE TOP NODE
                    let overTopNode = reelNodes[reelNodes.len-rl.stopCellFromTop]
                    let an = newAnimation()
                    an.loopDuration = 0.15
                    an.numberOfLoops = 1
                    an.animate val in overTopNode.worldPos .. reelLoopComp.worldPosElems[1]:
                        overTopNode.worldPos = val
                    an.onComplete do():
                        overTopNode.hideCellElements()
                        overTopNode.worldPos = reelLoopComp.worldPosElems[1]
                    v.addAnimation(an)

                    # JUMP ON TWO CELLS ANIM

                    proc onComplete() =
                        overTopNode.worldPos = reelLoopComp.worldPosElems[1]
                        for i in 0..<rl.stopCellFromTop:
                            reelNodes[i].hideCellElements()
                        if not onStop.isNil:
                            onStop()

                    if not animOut.isNil:
                        v.addAnimation(animOut)
                        animOut.onComplete do():
                            animOut.removeHandlers()
                            # SET AT PLACE AND HIDE
                            onComplete()
                    else:
                        onComplete()

    reelLoopComp.onJump = onJump

    let onUpdate = proc(p: float) =
        if not bStop and doMove:
            # 0.006079196929931641 fps: 280
            # 0.3325271606445312 fps: 3
            # 0.2332890033721924 fps: 4
            # 0.1628761291503906 fps: 6
            # 0.1056699752807617 fps: 9 -> almoust normal spin
            var delta = getDeltaTime()
            if delta > 0.1: delta = 0.1
            reelNode.positionY = reelNode.positionY + rl.mShiftSpeed * delta

    reelLoopComp.onUpdate = onUpdate

proc startSpin*(rl: Reelset, onCanStop: proc() = nil, onStop: proc() = nil, onFinish: proc() = nil) =
    let v = rl.rootNode.sceneView
    rl.mIsSpin = true
    rl.canStopSpin = false
    rl.reelsStopper = newSeq[bool](rl.mNumCols)
    let deltaWait = 0.125 # TODO need to be user manually setted
    var startTime = 0.0

    var onCanStopCounter = 0
    let onCanStopReel = proc() =
        inc onCanStopCounter
        if onCanStopCounter == rl.reels.len:
            rl.canStopSpin = true
            if not onCanStop.isNil: onCanStop()

    var onStopCounter = 0
    let onStopReel = proc() =
        if not onStop.isNil: onStop()
        inc onStopCounter

        if onStopCounter == rl.reels.len:
            rl.mIsSpin = false
            if not onFinish.isNil:
                onFinish()

    let anim = newAnimation()
    anim.numberOfLoops = 1
    for i in 0..<rl.reels.len:
        closureScope:
            let index = i
            anim.addLoopProgressHandler startTime, false, proc() =
                rl.spin(index, onCanStopReel, onStopReel)
            startTime += deltaWait

    anim.loopDuration = startTime
    v.addAnimation(anim)

proc setStop*(rl: Reelset, reelIndex: int = 0, waitTime: float32 = 0.0) =
    let v = rl.rootNode.sceneView
    if waitTime > 0:
        v.wait(waitTime) do():
            rl.reelsStopper[reelIndex] = true
    else:
        rl.reelsStopper[reelIndex] = true

proc stop*(rl: Reelset, stopTimeouts: openarray[float32] = []) =
    if stopTimeouts.len == 0:
        for i in 0..<rl.reelsStopper.len:
            rl.reelsStopper[i] = true
    else:
        doAssert(stopTimeouts.len == rl.reelsStopper.len)
        for i in 0..<rl.reelsStopper.len:
            rl.setStop(i, stopTimeouts[i])

proc stopFirstReel*(rl: Reelset) =
    rl.setStop()

template stepX*(rl: Reelset): float32 = rl.mStepX
template `stepX=`*(rl: Reelset, v: float32) =
    rl.mStepX = v
    rl.checkRequirements()

template stepY*(rl: Reelset): float32 = rl.mStepY
template `stepY=`*(rl: Reelset, v: float32) =
    rl.mStepY = v
    rl.checkRequirements()

template numCols*(rl: Reelset): int = rl.mNumCols
template `numCols=`*(rl: Reelset, v: int) =
    rl.mNumCols = v
    rl.checkRequirements()

template numRows*(rl: Reelset): int = rl.mNumRows
template `numRows=`*(rl: Reelset, v: int) =
    rl.mNumRows = v
    rl.checkRequirements()

template reelPath*(rl: Reelset): string = rl.mReelPath
template `reelPath=`*(rl: Reelset, respath: string) =
    rl.mReelPath = respath
    rl.checkRequirements()

template cellPath*(rl: Reelset): string = rl.mCellPath
template `cellPath=`*(rl: Reelset, respath: string) =
    rl.mCellPath = respath
    rl.checkRequirements()

template isLocalized*(rl: Reelset): bool = rl.mIsLocalized
template `isLocalized=`*(rl: Reelset, v: bool) =
    rl.mIsLocalized = v
    rl.checkRequirements()

template isSpin*(rl: Reelset): bool = rl.mIsSpin
template `isSpin=`*(rl: Reelset, v: bool) =
    if not rl.mIsSpin:
        rl.startSpin()
    else:
        var deltaWait = 0.25
        var startTime = 0.0
        var timings = newSeq[float32]()
        for i in 0..<rl.reelsStopper.len:
            timings.add(startTime)
            startTime += deltaWait
        rl.stop(timings)
    rl.mIsSpin = v

template shiftSpeed*(rl: Reelset): float32 = rl.mShiftSpeed
template `shiftSpeed=`*(rl: Reelset, v: float32) =
    rl.mShiftSpeed = v

method componentNodeWasAddedToSceneView*(rl: Reelset) =
    rl.rootNode = rl.node
    rl.checkRequirements()

method componentNodeWillBeRemovedFromSceneView*(rl: Reelset) =
    discard

method serialize*(rl: Reelset, s: Serializer): JsonNode =
    var chNodes = newSeq[Node]()
    while rl.rootNode.children.len > 0:
        chNodes.add(rl.rootNode.children[0])
        rl.rootNode.children[0].removeFromParent()

    result = newJObject()
    result.add("cols", s.getValue(rl.numCols))
    result.add("rows", s.getValue(rl.numRows))
    result.add("stepX", s.getValue(rl.stepX))
    result.add("stepY", s.getValue(rl.stepY))
    result.add("reelPath", s.getValue(rl.reelPath))
    result.add("cellPath", s.getValue(rl.cellPath))
    result.add("isLocalized", s.getValue(rl.isLocalized))
    result.add("spinRandomFrom", s.getValue(rl.spinRandomFrom))
    result.add("spinRandomTo", s.getValue(rl.spinRandomTo))
    result.add("shiftSpeed", s.getValue(rl.shiftSpeed))
    result.add("stopCellFromTop", s.getValue(rl.stopCellFromTop))

    result.add("reelAnimationInName", s.getValue(rl.mReelAnimationInName))
    result.add("reelAnimationOutName", s.getValue(rl.mReelAnimationOutName))
    result.add("reelAnimationSpinInName", s.getValue(rl.mReelAnimationSpinInName))
    result.add("reelAnimationSpinOutName", s.getValue(rl.mReelAnimationSpinOutName))

    var elNames = newJArray()
    for value in rl.elementsName:
        var cell = newJArray()
        cell.add(%value.name)
        cell.add(%value.index)
        elNames.add(cell)
    result.add("elementsName", elNames)

    rl.rootNode.sceneView.wait(0.5) do():
        for ch in chNodes:
            rl.rootNode.addChild(ch)

method deserialize*(rl: Reelset, j: JsonNode, s: Serializer) =
    s.deserializeValue(j, "cols", rl.numCols)
    s.deserializeValue(j, "rows", rl.numRows)
    s.deserializeValue(j, "stepX", rl.stepX)
    s.deserializeValue(j, "stepY", rl.stepY)
    s.deserializeValue(j, "reelPath", rl.reelPath)
    s.deserializeValue(j, "cellPath", rl.cellPath)
    s.deserializeValue(j, "isLocalized", rl.isLocalized)
    s.deserializeValue(j, "spinRandomFrom", rl.spinRandomFrom)
    s.deserializeValue(j, "spinRandomTo", rl.spinRandomTo)
    s.deserializeValue(j, "shiftSpeed", rl.shiftSpeed)
    s.deserializeValue(j, "stopCellFromTop", rl.stopCellFromTop)

    s.deserializeValue(j, "reelAnimationInName", rl.mReelAnimationInName)
    s.deserializeValue(j, "reelAnimationOutName", rl.mReelAnimationOutName)
    s.deserializeValue(j, "reelAnimationSpinInName", rl.mReelAnimationSpinInName)
    s.deserializeValue(j, "reelAnimationSpinOutName", rl.mReelAnimationSpinOutName)

    var v = j{"elementsName"}
    if not v.isNil:
        rl.elementsName = @[]
        for i in 0 ..< v.len:
            rl.elementsName.add( ( v[i][0].getStr(), ($v[i][1]).parseInt() ) )

    rl.reelsStack = newSeq[seq[int]](rl.mNumCols)
    for i in 0..<rl.mNumCols:
        rl.reelsStack[i] = newSeq[int](3)
        for j in 0..<3:
            rl.reelsStack[i][j] = rl.spinRandomFrom + j

when enableEditor:
    proc newSeqPropertyViewNew(setter: proc(s: seq[tuple[name: string, index: int]]), getter: proc(): seq[tuple[name: string, index: int]]): PropertyEditorView =
        var val = getter()
        var height = val.len() * (editorRowHeight + 2) + (editorRowHeight + 2)
        let pv = PropertyEditorView.new(newRect(0, 0, 208, height.Coord))

        proc onValChange() =
            setter(val)

        proc onSeqChange() =
            onValChange()
            if not pv.changeInspector.isNil:
                pv.changeInspector()

        var x = 0.Coord
        var y = (editorRowHeight + 2).float32
        for i in 0 ..< val.len:
            closureScope:
                let index = i
                x = 0.Coord

                let label = newLabel(newRect(x, y, 100, editorRowHeight))
                label.text = $val[index].name
                label.textColor = newGrayColor(0.9)
                pv.addSubview(label)

                x += 107
                let tf = newNumericTextField(newRect(x, y, 50, editorRowHeight))
                tf.font = editorFont()

                pv.addSubview(tf)
                tf.text = $val[index].index
                tf.onAction do():
                    if index < val.len:
                        val[index].index = tf.text.parseFloat().int
                        onValChange()

                y += editorRowHeight + 2

        result = pv

    registerPropertyEditor(newSeqPropertyViewNew)

method visitProperties*(rl: Reelset, p: var PropertyVisitor) =
    p.visitProperty("cols", rl.numCols)
    p.visitProperty("rows", rl.numRows)
    p.visitProperty("stepX", rl.stepX)
    p.visitProperty("stepY", rl.stepY)
    p.visitProperty("reelPath", rl.reelPath)
    p.visitProperty("cellPath", rl.cellPath)
    p.visitProperty("isLocalized", rl.isLocalized)

    p.visitProperty("anim in", rl.mReelAnimationInName)
    p.visitProperty("anim out", rl.mReelAnimationOutName)
    p.visitProperty("anim spinin", rl.mReelAnimationSpinInName)
    p.visitProperty("anim spinout", rl.mReelAnimationSpinOutName)

    p.visitProperty("elements", rl.elementsName)

    p.visitProperty("spinRandomFrom", rl.spinRandomFrom)
    p.visitProperty("spinRandomTo", rl.spinRandomTo)

    p.visitProperty("stop on index", rl.stopCellFromTop)

    p.visitProperty("shiftSpeed", rl.shiftSpeed)

    p.visitProperty("isSpin", rl.isSpin)

registerComponent(Reelset, "Falcon")
