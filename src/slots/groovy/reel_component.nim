import nimx / [types, property_visitor, animation, matrixes, context, render_to_image, image]
import rod / [node, component, viewport, component.camera]
import utils.helpers
import algorithm, tables, random, math
import cell_component
import tables

const TEXTURE_SIZE = newSize(512, 512)
const EDGE_OFFSET = 600
const MOVEOUT_OFFSET = 200

type MoveState = enum
    MoveStop
    MoveIn
    MoveIdle
    MoveOut

type TimingFunctionProperty* = ref object
    args*: array[4, float]

type RotationElement = tuple
    position: float
    id: int
    uid: int
    tailLen: int
    onElementStop: proc(uid: int, reelID: int, deathType: int)
    skipDraw: bool

type StopHandler* = tuple
    progress: float
    handler: proc()

type ReelComponent* = ref object of Component
    id*: int
    state*: MoveState
    prototype*: Node
    elems*: seq[Node]

    onIndexedStop*: proc()
    mStopHandler: StopHandler

    shiftSpeed*: float32

    reelsStack: seq[int]
    rotationStack: seq[RotationElement]
    availableStack: seq[int]

    exceptions*: seq[int]

    onSpawn: Table[int, proc(uid: int, reelID: int, pos: Vector3, shiftSpeed: float32)]
    onUpdate: Table[int, proc(uid: int, reelID: int, position: float)]
    onElementStop: Table[int, proc(uid: int, reelID: int, deathType: int)]
    onReelLand: Table[float32, proc(reelID: int)]  # when reel stops but easings is not applied yet   
    onReelStop: proc(reelID: int, nextProc: proc())  # when reel fully stops

    velocity: float
    rotationOffset*: float
    reelOffset*: float

    cellTextureCache*: TableRef[int, SelfContainedImage]
    cellTextureOffset*: Vector3

    inOutTimer: float
    elemOffset*: float
    inDuration*: float
    outDuration*: float
    inTimingFunction*: TimingFunctionProperty
    outTimingFunction*: TimingFunctionProperty

    inAnimation: Animation
    idleAnimation: Animation
    outAnimation: Animation

proc function(tfp: TimingFunctionProperty): TimingFunction =
    if tfp.args.len == 4:
        result = bezierTimingFunction(tfp.args[0], tfp.args[1], tfp.args[2], tfp.args[3])
    else:
        result = linear

template dlog(rl: ReelComponent, body: untyped)=
    if rl.id == 0:
        body

method isPosteffectComponent*(rl: ReelComponent): bool = rl.state != MoveStop

method init*(rl: ReelComponent) =
    procCall rl.Component.init()
    rl.reelsStack = @[]
    rl.inTimingFunction = new(TimingFunctionProperty)
    rl.outTimingFunction = new(TimingFunctionProperty)
    rl.inDuration = 0.25
    rl.outDuration = 0.25
    rl.exceptions = @[]
    rl.onSpawn = initTable[int, proc(id: int, nodeID: int, pos: Vector3, shiftSpeed: float32)]()
    rl.onUpdate = initTable[int, proc(uid: int, reelID: int, position: float)]()
    rl.onElementStop = initTable[int, proc(uid: int, reelID: int, deathType: int)]()
    rl.onReelLand = initTable[float32, proc(reelID: int)]()
    rl.onReelStop = nil

proc rotationHeight(rl: ReelComponent): float = rl.elemOffset * rl.rotationStack.len.float
proc reelstackHeight(rl: ReelComponent): float = max(3, rl.reelsStack.len).float * rl.elemOffset

proc getSortedChildren(parent: Node): seq[Node] =
    var cells = newSeq[Node]()
    for ch in parent.children: cells.add(ch)
    cells.sort do (n1, n2: Node) -> int:
        let wpos1 = n1.worldPos()
        let wpos2 = n2.worldPos()
        result = cmp(wpos1.x, wpos2.x) or cmp(wpos1.y, wpos2.y) or cmp(wpos1.z, wpos2.z)
    result = cells

proc sortElems*(rl: ReelComponent) =
    rl.elems = getSortedChildren(rl.node)
    rl.node.children = rl.elems

template `[]`*(rl: ReelComponent, i: int): Node =
    rl.elems[i]

template `[]=`*(rl: ReelComponent, i: int; x: Node) =
    rl.sortElems()
    rl.elems[i].removeFromParent()
    rl.node.addChild(x)
    rl.elems[i] = x

proc setOnSpawnProc*(rc: ReelComponent, indices: seq[int], cb: proc(uid: int, reelID: int, pos: Vector3, shiftSpeed: float32)) =
    for i in indices:
        if not cb.isNil:
            rc.onSpawn[i] = cb
        else:
            if rc.onSpawn.hasKey(i):
                rc.onSpawn.del(i)
proc setOnUpdateProc*(rc: ReelComponent, indices: seq[int], cb: proc(uid: int, reelID: int, position: float)) =
    for i in indices:
        if not cb.isNil:
            rc.onUpdate[i] = cb
        else:
            if rc.onUpdate.hasKey(i):
                rc.onUpdate.del(i)
proc setOnElementStopProc*(rc: ReelComponent, indices: seq[int], cb: proc(uid: int, reelID: int, deathType: int)) =
    for i in indices:
        if not cb.isNil:
            rc.onElementStop[i] = cb
        else:
            if rc.onElementStop.hasKey(i):
                rc.onElementStop.del(i)

proc setOnReelLandProc*(rc: ReelComponent, progress: float32, cb: proc(reelID: int)) =
    if not cb.isNil:
        rc.onReelLand[progress] = cb
    else:
        if rc.onReelLand.hasKey(progress):
            rc.onReelLand.del(progress)    

proc setOnReelStopProc*(rc: ReelComponent, cb: proc(reelID: int, nextProc: proc())) =
    rc.onReelStop = cb

proc onStopProgress*(rl: ReelComponent, p: float, cb: proc())=
    var handler: StopHandler
    handler.progress = p
    handler.handler = cb
    rl.mStopHandler = handler

proc initSpin(rl: ReelComponent) =
    if rl.node.children.len == 0:
        raiseAssert("wrong parent node")

    rl.sortElems()

    rl.rotationOffset = 0.0
    rl.reelOffset = 0.0

    rl.elemOffset = rl.node.children[1].positionY - rl.node.children[0].positionY
    rl.availableStack = @[]

    for k, v in rl.node.children[0].component(CellComponent).idToNodeRelation:
        var isException: bool = false
        for i in rl.exceptions:
            if i == k:
                isException = true
                break
        if isException == false:
            rl.availableStack.add(k)

    randomize()
    rl.availableStack.shuffle()

    let maxSymbols = rl.node.children[0].component(CellComponent).idToNodeRelation.len
    var index: int = 0

    rl.rotationStack = @[]
    if rl.availableStack.len != 0:
        for i in 0 ..< maxSymbols:
            var re: RotationElement
            re.uid = i
            re.skipDraw = false
            re.id = rl.availableStack[index]
            if (rl.availableStack.len - 1) > index: inc index else: index = 0
            re.position = i.float * rl.elemOffset

            if rl.onSpawn.hasKey(re.id):
                rl.onSpawn[re.id](re.uid, rl.id,
                    newVector3(rl.node.positionX, re.position + rl.rotationOffset, rl.node.children[0].positionZ), rl.shiftSpeed)

            rl.rotationStack.add(re)

        randomize()
        rl.rotationStack.shuffle()

proc afterStop(rl: ReelComponent) =
    rl.state = MoveStop

    rl.rotationStack.setLen(0)
    if not rl.onIndexedStop.isNil:
        rl.onIndexedStop()
    rl.outAnimation = nil

proc setExceptions*(rl: ReelComponent, expts: seq[int]) =
    rl.exceptions = expts

proc getCellTexture(rl: ReelComponent, id: int): SelfContainedImage=
    result = rl.cellTextureCache.getOrDefault(id)

proc initTextureCache*(rl: ReelComponent)=
    var ids = newSeq[int]()
    var needRebuild = false
    for k, v in rl.node.children[0].component(CellComponent).idToNodeRelation:
        if not needRebuild:
            needRebuild = rl.getCellTexture(k).isNil
        ids.add(k)

    if not needRebuild: return

    var cell = rl.prototype.component(CellComponent)
    rl.node.addChild(rl.prototype)

    let prevScale = cell.node.scale
    cell.node.scale = newVector3(1920 / TEXTURE_SIZE.width, 1080 / TEXTURE_SIZE.height, 1)
    assert(not rl.node.sceneView.isNil, "ReelComponent: Scene is nil!")

    for i in ids:
        cell.show(i)

        var img = imageWithSize(TEXTURE_SIZE)
        img.Image.draw do():
            cell.node.children[0].recursiveDraw()
        rl.cellTextureCache[i] = img

    cell.node.scale = prevScale

    cell.node.removeFromParent()

proc drawRotationElement(rl: ReelComponent, el: RotationElement, drawp: Vector3)=
    let texture = rl.getCellTexture(el.id)
    if texture.isNil:
        return

    var drawp = drawp + rl.cellTextureOffset
    if false:
        let steps = 5
        var vel = (rl.velocity - rl.rotationOffset) * 2.0

        for i in 1 .. steps:
            let p  = i / steps
            currentContext().drawImage(texture,
                newRect(drawp.x, interpolate(drawp.y, drawp.y + vel, p), TEXTURE_SIZE.width, TEXTURE_SIZE.height),
                zeroRect,
                interpolate(1.2.float, 0.0.float, p)
                )
    else:
        currentContext().drawImage(texture, newRect(drawp.x, drawp.y, TEXTURE_SIZE.width, TEXTURE_SIZE.height))
       
proc drawRotation(rl: ReelComponent)=
    let cell = rl.prototype.component(CellComponent)
    let vh = rl.node.sceneView.camera.viewportSize.height + EDGE_OFFSET
    var idx = 0

    while idx < rl.rotationStack.len:
        var el = rl.rotationStack[idx]

        let p = cell.node.position
        var drawp = newVector3(p.x, el.position + rl.rotationOffset)
        var needDraw = true

        if rl.state == MoveOut:
            let reelH = rl.reelstackHeight()

            var topCorner: bool = false
            var botCorner: bool = false
            if sgn(rl.shiftSpeed) > 0:
                topCorner = drawp.y > reelH + EDGE_OFFSET
                botCorner = drawp.y < rl.reelOffset + reelH + MOVEOUT_OFFSET
            elif sgn(rl.shiftSpeed) < 0:
                topCorner = drawp.y + rl.elemOffset < -EDGE_OFFSET
                botCorner = drawp.y + rl.elemOffset > rl.reelOffset

            if topCorner or botCorner:
                needDraw = false
                el.skipDraw = false

            if rl.shiftSpeed > 0.0:
                if drawp.y + rl.elemOffset < rl.reelOffset:
                    needDraw = false

            if el.skipDraw == true: needDraw = false

        if needDraw:
            if not rl.onSpawn.hasKey(el.id):
                rl.drawRotationElement(el, drawp)

        let needJumpUp = rl.shiftSpeed > 0.0 and el.position + rl.rotationOffset > vh
        let needJumpDown = rl.shiftSpeed < 0.0 and el.position + rl.elemOffset + rl.rotationOffset < -EDGE_OFFSET
        if needJumpUp or needJumpDown:
            var dstp = el.position - rl.rotationStack.len.float * rl.elemOffset * sgn(rl.shiftSpeed).float
            if rl.state == MoveOut:
                dstp += rl.reelstackHeight() * sgn(rl.shiftSpeed).float

            el.position = dstp

            if rl.onElementStop.hasKey(el.id) and rl.state != MoveOut:
                rl.onElementStop[el.id](el.uid, rl.id, 0)

            el.id = rl.availableStack.random()

            if rl.onSpawn.hasKey(el.id) and rl.state != MoveOut:
                rl.onSpawn[el.id](el.uid, rl.id,
                    newVector3(rl.node.positionX, el.position + rl.rotationOffset, rl.node.children[0].positionZ), rl.shiftSpeed)

            rl.rotationStack[idx] = el

        if rl.onUpdate.hasKey(el.id):
            rl.onUpdate[el.id](el.uid, rl.id, el.position + rl.rotationOffset)

        inc idx

method beforeDraw*(rl: ReelComponent, index: int): bool =
    case rl.state:
    of MoveIn, MoveOut:
        rl.drawRotation()
        for i, ch in rl.node.children: #redo
            let p = ch.position
            ch.position = p + newVector3(0.0, rl.reelOffset)

            currentContext().withTransform ch.worldTransform():
                ch.recursiveDraw()

            if i < rl.reelsStack.len: #0..2 < 3
                let index = rl.reelsStack.len - i - 1
                if rl.onUpdate.hasKey(rl.reelsStack[index]): #1..3
                    rl.onUpdate[rl.reelsStack[index]](-i - 1, rl.id, ch.position.y + 115)

            ch.position = p

        result = true

    of MoveIdle:
        rl.drawRotation()

        result = true
    else:
        result = false

proc startIdle(rl: ReelComponent)=
    rl.state = MoveIdle

    rl.reelOffset = -rl.reelOffset

    let a = newAnimation()
    a.onAnimate = proc(p: float) =
        let dt = getDeltaTime()
        rl.velocity = rl.rotationOffset
        rl.rotationOffset = rl.rotationOffset + dt * rl.shiftSpeed

    rl.idleAnimation = a
    rl.node.addAnimation(a)

proc play*(rl: ReelComponent, cb: proc() = nil)=
    rl.initSpin()

    var reeldst = rl.reelstackHeight()
    var rotdst = reeldst - rl.rotationHeight() + rl.elemOffset * 0.5
    var fr = -rl.rotationHeight() + rl.elemOffset * 0.5

    if rl.shiftSpeed < 0.0:
        fr = rl.reelstackHeight() + rl.elemOffset * 0.5
        rotdst = fr - rl.reelstackHeight()
        reeldst = -reeldst

    rl.state = MoveIn
    var firstTick = true

    let a = newAnimation()
    a.loopDuration = rl.inDuration
    a.numberOfLoops = 1
    a.timingFunction = rl.inTimingFunction.function()
    a.onAnimate = proc(p: float)=
        rl.velocity = rl.rotationOffset
        rl.rotationOffset = interpolate(fr, rotdst, p)

        if firstTick:
            rl.velocity = rl.rotationOffset
            firstTick = false

        rl.reelOffset = interpolate(0.0, reeldst, p)

    a.onComplete do():
        rl.startIdle()
        if not cb.isNil:
            cb()

    rl.inAnimation = a

    var ffr = fr + rl.elemOffset * -sgn(rl.shiftSpeed).float

    var startAnim = newAnimation()
    startAnim.loopDuration = 0.1
    startAnim.numberOfLoops = 1
    startAnim.onAnimate = proc(p: float)=
        rl.velocity = rl.rotationOffset
        rl.rotationOffset = interpolate(ffr, fr, p)

        if firstTick:
            rl.velocity = rl.rotationOffset
            firstTick = false

    startAnim.onComplete do():
        rl.node.addAnimation(a)

    rl.node.addAnimation(startAnim)

proc prepareReel(rl: ReelComponent)=
    rl.sortElems()

    #Notify all elements in texture atlas
    for elem in rl.rotationStack:
        if rl.onElementStop.hasKey(elem.id):
            rl.onElementStop[elem.id](elem.uid, rl.id, 2)

    for i, ch in rl.node.children: #0..3
        let cell = ch.component(CellComponent)
        if i < rl.reelsStack.len: #0..2
            let index = rl.reelsStack.len - i - 1
            if rl.onSpawn.hasKey(rl.reelsStack[index]): #10..11
                rl.onSpawn[rl.reelsStack[index]](-i - 1, rl.id,
                    newVector3(rl.node.positionX, rl.node.children[index].positionY + rl.reelOffset + 256, rl.node.children[0].positionZ), rl.shiftSpeed)
                rl.onElementStop[rl.reelsStack[index]](-i - 1, rl.id, 1)
            cell.play(rl.reelsStack[index], OnIdle, lpStartToEnd, nil, false, true)
        else:
            cell.hideElemWithAnim(OnBottomHide)

proc stop*(rl: ReelComponent, rs:seq[int], cb: proc() = nil)=
    rl.idleAnimation.cancel()
    rl.reelsStack = rs
    rl.state = MoveOut

    rl.prepareReel()

    let rfr = -rl.reelstackHeight() * sgn(rl.shiftSpeed).float

    var mis = (rl.rotationOffset.int mod rl.elemOffset.int).float - rl.elemOffset * 0.5
    var ff = rl.elemOffset - mis

    var fr = rl.rotationOffset + ff
    let dst = (fr + abs(rfr) * sgn(rl.shiftSpeed).float) + sgn(rl.shiftSpeed).float * EDGE_OFFSET

    let a = newAnimation()
    a.loopDuration = rl.outDuration
    a.numberOfLoops = 1
    a.timingFunction = rl.outTimingFunction.function()    
    for time, callback in rl.onReelLand:
        closureScope:
            let timeSc = time
            let callBackSc = callBack
            a.addLoopProgressHandler(timeSc, true) do():
                callBackSc(rl.id)
    a.onAnimate = proc(p: float) =
        rl.velocity = rl.rotationOffset
        rl.rotationOffset = interpolate(fr, dst, p)
        rl.reelOffset = interpolate(rfr, 0.0, p)

    if not rl.mStopHandler.handler.isNil:
        a.addLoopProgressHandler(rl.mStopHandler.progress, true, rl.mStopHandler.handler)

    a.onComplete do():
        a.removeHandlers()
        rl.afterStop()
        if not cb.isNil():
            cb()

    rl.outAnimation = a
    rl.node.addAnimation(a)

const enableEditor = not defined(release)
when enableEditor:
    import nimx.property_editors.propedit_registry
    import nimx.property_editors.standard_editors
    import nimx.numeric_text_field
    import nimx.editor.bezier_view
    import nimx.view
    import nimx.text_field
    import nimx.linear_layout
    import nimx.button
    import nimx.timer
    import strutils
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

    proc newTimingFunctionProperty(setter: proc(tm: TimingFunctionProperty), getter: proc(): TimingFunctionProperty): PropertyEditorView =
        var v = PropertyEditorView.new(newRect(0, 0, 320, 400))
        result = v

        var tm = getter()

        var bezierView = new(BezierView, newRect(-50, 50, 250, 250))
        bezierView.p1 = tm.args[0]
        bezierView.p2 = tm.args[1]
        bezierView.p3 = tm.args[2]
        bezierView.p4 = tm.args[3]

        var bezierWp: array[4, float]
        var tfs = newSeq[TextField](4)

        let onTFChanged = proc(i: int):proc()=
            let index = i
            result = proc() =
                try:
                    bezierWp[i] = parseFloat(tfs[index].text)
                except:
                    bezierWp[i] = 0.0

                bezierView.p1 = bezierWp[0]
                bezierView.p2 = bezierWp[1]
                bezierView.p3 = bezierWp[2]
                bezierView.p4 = bezierWp[3]

        for i in 0 .. 3:
            var tf1 = newTextField(newRect(70 * (i).float, 0, 65, 20))
            tf1.text = "0.0"
            tf1.continuous = true
            tf1.onAction(onTFChanged(i))
            v.addSubview(tf1)
            tfs[i] = tf1

            if i != 3:
                discard newLabel(v, newPoint(70 * (i).float + 62.5, 0), newSize(10, 20), ",")

        bezierView.onAction do():
            bezierWp[0] = bezierView.p1
            bezierWp[1] = bezierView.p2
            bezierWp[2] = bezierView.p3
            bezierWp[3] = bezierView.p4

            for i, v in tfs:
                v.text = formatFloat(bezierWp[i], precision = 5)

            tm.args = bezierWp
            setter(tm)

        v.addSubview(bezierView)

    registerPropertyEditor(newTimingFunctionProperty)

    method visitProperties*(rl: ReelComponent, p: var PropertyVisitor) =

        var isPl = not rl.outAnimation.isNil
        var msg: InfoBoolString
        msg.new()
        msg.val = if isPl: "stop" else: "play"


        proc isPlay(rl: ReelComponent): InfoBoolString = msg
        proc `isPlay=`(rl: ReelComponent, msg: InfoBoolString) =

            if not isPl:
                msg.val = "stop"
                rl.play()
                isPl = not isPl
            else:
                msg.val = "play"
                rl.stop(@[0,1,2]) do():
                    isPl = not isPl

        p.visitProperty("spin", rl.isPlay)
        p.visitProperty("shift speed", rl.shiftSpeed)

        var isLowFps = false
        var t: Timer
        proc fps(rl: ReelComponent): bool = isLowFps
        proc `fps=`(rl: ReelComponent, v: bool) =
            isLowFps = v
            if isLowFps:
                t = setInterval(0.1) do():
                    for i in 0..5000:
                        for j in 0..2000:
                            var k = i * j
            else:
                t.pause()
                t.clear()

        p.visitProperty("isLowFps", rl.fps)

registerComponent(ReelComponent, "ReelsetComponents")
