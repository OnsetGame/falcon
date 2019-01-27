import nimx / [ view, view_event_handling, gesture_detector, event, matrixes, animation, notification_center ]
import rod / [ viewport, component, rod_types, node ]
import rod / component / [ clipping_rect_component, ui_component ]

import utils.helpers
import math, times, algorithm

const alignDurat = 0.2

type
    NodeScrollDirection* {.pure.} = enum
        vertical, horizontal, all, none

    NodeScrollGesture* = ref object of OnScrollListener
        contentPosition: Vector3
        prevPosition: Point
        nodeScroll: NodeScroll
        accelP: Point

    NodeScroll* = ref object of View
        scrollGesture : ScrollDetector
        content: Node
        contentParent: Node
        mZeroChild: Node
        mContentBack: Node
        mContentFront: Node
        scrollRect: Rect
        customSize*: Size
        mNodeSize: Size
        scrollDirection*: NodeScrollDirection
        bounces*: bool
        pading*: bool
        mLooped: bool
        onActionStart*: proc()
        onActionEnd*: proc()
        onActionProgress*: proc()
        alignAnim: Animation
        lasScrollTime: float
        notDrawInvisible*: bool
        mScrollX: float
        mScrollY: float
        when not defined(macosx):
            prevScrollTime: float
            scrollSpeed:float

proc setClippingEnabled*(ns: NodeScroll, enabled: bool)=
    assert(not ns.content.isNil)
    let node = ns.content.parent
    if enabled and node.componentIfAvailable(ClippingRectComponent).isNil:
        node.component(ClippingRectComponent).clippingRect = ns.scrollRect
    else:
        node.removeComponent(ClippingRectComponent)

proc createNodeScroll*(r: Rect, node: Node): NodeScroll=
    result = new(NodeScroll, r)
    result.autoResizingMask = {afFlexibleWidth, afFlexibleHeight}
    result.scrollRect = r

    let gest = new(NodeScrollGesture)
    gest.nodeScroll = result
    result.scrollGesture = newScrollGestureDetector(gest)
    result.addGestureDetector(result.scrollGesture)

    node.component(ClippingRectComponent).clippingRect = r
    node.component(UIComponent).view = result

    result.contentParent = node.newChild("NodeScrollContentParent")
    result.mContentBack = result.contentParent.newChild("NodeScrollContentBack")
    result.content = result.contentParent.newChild("NodeScrollContent")
    result.mContentFront = result.contentParent.newChild("NodeScrollContentFront")
    result.mNodeSize = newSize(0, 0)

proc looped*(ns: NodeScroll): bool = ns.mLooped

proc contentBackNode*(ns: NodeScroll): Node= ns.mContentBack
proc contentFrontNode*(ns: NodeScroll): Node= ns.mContentFront

proc contentSize(ns: NodeScroll): Size =
    if ns.customSize.width == 0 and ns.customSize.height == 0:
        if not ns.looped: # todo: check this
            var minx, miny: Coord = 0xFFF
            var maxx, maxy: Coord = 0

            for ch in ns.content.children:
                let x = ch.positionX
                let y = ch.positionY
                if x < minx:
                    minx = x
                if x > maxx:
                    maxx = x
                if y < miny:
                    miny = y
                if y > maxy:
                    maxy = y

            const offset = 5.0
            result = newSize(maxx + ns.mNodeSize.width + offset, maxy + ns.mNodeSize.height + offset)
        else:
            if ns.scrollDirection == NodeScrollDirection.horizontal:
                result = newSize(ns.mNodeSize.width * ns.content.children.len.float, ns.mNodeSize.height)
            elif ns.scrollDirection == NodeScrollDirection.vertical:
                result = newSize(ns.mNodeSize.width, ns.mNodeSize.height * ns.content.children.len.float)
            elif ns.scrollDirection == NodeScrollDirection.all:
                # not supported
                raise

    else:
        result = ns.customSize

proc `contentOffset=`*(ns: NodeScroll, s: Vector3)=
    ns.contentParent.position = s

proc `nodeSize=`*(ns: NodeScroll, s: Size)=
    ns.mNodeSize = s

proc removeAllChildren*(ns: NodeScroll)=
    ns.content.removeAllChildren()

proc addChild*(ns: NodeScroll, n: Node)=
    ns.content.addChild(n)

proc insertChild*(ns: NodeScroll, n: Node, i: Natural) =
    ns.content.insertChild(n, i)

proc removeChild*(ns: NodeScroll, n: Node)=
    n.removeFromParent()

proc len*(ns: NodeScroll): int =
    result = ns.content.children.len

proc calcOffset(fp, ap, cp: Coord, allSize, inSize: Coord, bounces: bool): Coord=
    result = fp + ap
    if allSize + result < inSize:
        if bounces:
            let bounceOffset = inSize - (allSize + cp)
            let coof = 1.0 - bounceOffset / inSize
            result = fp + ap * coof
        else:
            result = -(allSize - inSize)
    elif result > 0:
        if bounces:
            let coof = 1.0 - cp / inSize
            result = fp + ap * coof
        else:
            result = 0

proc hideInvisible(ns: NodeScroll)=
    if ns.notDrawInvisible:
        var cbx, cby = 0
        if ns.scrollDirection in [NodeScrollDirection.horizontal, NodeScrollDirection.all]:
            for ch in ns.content.children:
                if ch.positionX + ns.content.positionX >= -(ns.scrollRect.width - ns.mNodeSize.width) and
                    ch.positionX + ns.content.positionX <= ns.scrollRect.width + ns.mNodeSize.width:

                    ch.alpha = 1.0
                else:
                    ch.alpha = 0.0
                    inc cbx

        if ns.scrollDirection in [NodeScrollDirection.vertical, NodeScrollDirection.all]:
            for ch in ns.content.children:
                if ch.positionY + ns.content.positionY >= -(ns.scrollRect.height - ns.mNodeSize.height) and
                    ch.positionY + ns.content.positionY <= ns.scrollRect.height + ns.mNodeSize.height:

                    ch.alpha = 1.0
                else:
                    ch.alpha = 0.0
                    inc cby

proc calcOffsetLooped(ns: NodeScroll, fp, ap: Coord, allSize, inSize: Coord): Coord=
    let isVer = ns.scrollDirection == NodeScrollDirection.vertical

    result = fp + ap

    # var cp      = if isVer: ns.content.positionY  else: ns.content.positionX
    # let allSize = if isVer: ns.contentSize.height else: ns.contentSize.width
    # let inSize  = if isVer: ns.scrollRect.height  else: ns.scrollRect.width

    var nodeDir = ns.content.children[1].position - ns.content.children[0].position
    proc firstP(): float =
        result = if isVer:
                    ns.content.children[0].positionY + ns.content.positionY
                else:
                    ns.content.children[0].positionX + ns.content.positionX

    proc lastP() : float =
        result = if isVer:
                    ns.content.children[^1].positionY + ns.content.positionY
                else:
                    ns.content.children[^1].positionX + ns.content.positionX

    let dd = ns.mNodeSize.width * 2.0
    let maxIters = ns.content.children.len div 2
    var idx = 0
    var p = ns.content.children[^1].position
    while lastP() < dd and idx < maxIters:
        ns.content.children[idx].position = p + nodeDir
        p = ns.content.children[idx].position
        inc idx

    idx = 0
    p = ns.content.children[0].position
    while firstP() > -dd and idx < maxIters:
        ns.content.children[^(idx + 1)].position = p - nodeDir
        p = ns.content.children[^(idx + 1)].position
        inc idx

    if idx != 0:
        ns.content.children.sort do(a,b: Node) -> int:
            if isVer:
                result = cmp(a.positionY, b.positionY)
            else:
                result = cmp(a.positionX, b.positionX)

proc setContentX*(ns: NodeScroll, fx, ax: Coord)=
    if not ns.looped:
        ns.content.positionX = calcOffset(fx, ax, ns.content.positionX, ns.contentSize.width, ns.scrollRect.width, ns.bounces)
        ns.mScrollX = abs(min(ns.content.positionX / (ns.scrollRect.size.width - ns.mNodeSize.width * ns.content.children.len.float), 1.0))
    else:
        ns.content.positionX = ns.calcOffsetLooped(fx, ax, ns.contentSize.width, ns.scrollRect.width)
    ns.hideInvisible()

proc setContentY*(ns: NodeScroll, fy, ay: Coord)=
    if not ns.looped:
        ns.content.positionY = calcOffset(fy, ay, ns.content.positionY, ns.contentSize.height, ns.scrollRect.height, ns.bounces)
        ns.mScrollY = abs(min(ns.content.positionY / (ns.scrollRect.size.height - ns.mNodeSize.height * ns.content.children.len.float), 1.0))
    else:
        ns.content.positionY = ns.calcOffsetLooped(fy, ay, ns.contentSize.height, ns.scrollRect.height)
    ns.hideInvisible()

proc scrollX*(ns: NodeScroll): float =
    assert(not ns.looped, "Available only for non-looped scroll")
    result = ns.mScrollX

proc scrollY*(ns: NodeScroll): float =
    assert(not ns.looped, "Available only for non-looped scroll")
    result = ns.mScrollY

proc `looped=`*(ns: NodeScroll, val: bool)=
    ns.mLooped = val
    if ns.content.isNil or ns.content.children.len < 2:
        raise

    ns.mZeroChild = ns.content.children[0]
    ns.setContentX(0,0)

proc alignPosition(ns: NodeScroll): Vector3=
    if ns.looped:# and not ns.pading:
        return ns.content.position

    # if ns.pading and ns.content.children.len > 0:
    #     let contentP = ns.content.position
    #     var prevDiff: float
    #     var index = 0
    #     for i, ch in ns.content.children:
    #         let diffPos = contentP - (ch.position + contentP)
    #         var diff: float
    #         if ns.scrollDirection == NodeScrollDirection.vertical:
    #             diff = clamp(ns.mNodeSize.height - abs(diffPos.y), 0, high(float))
    #         elif ns.scrollDirection == NodeScrollDirection.horizontal:
    #             diff = clamp(ns.mNodeSize.width - abs(diffPos.x), 0, high(float))

    #         if diff != 0.0:
    #             if prevDiff == 0.0:
    #                 prevDiff = diff
    #                 index = i
    #             elif diff < prevDiff:
    #                 index = i
    #                 break
    #             else:
    #                 break

    #     result = ns.content.position
    #     if index >= 0:
    #         result += ns.content.children[index].position
    if false:
        discard
    else:
        result = newVector3()
        if ns.content.positionY >= 0:
            result.y = 0
        elif ns.contentSize.height + ns.content.positionY < ns.scrollRect.height:
            result.y = -(ns.contentSize.height - ns.scrollRect.height)
        else:
            result.y = ns.content.positionY

        if ns.content.positionX >= 0:
            result.x = 0
        elif ns.contentSize.width + ns.content.positionX < ns.scrollRect.width:
            result.x = -(ns.contentSize.width - ns.scrollRect.width)
        else:
            result.x = ns.content.positionX

proc scrollToIndex*(ns: NodeScroll, i: int, d: float = 0.25)=
    if i >= ns.content.children.len: return

    if not ns.onActionStart.isNil:
        ns.onActionStart()

    if not ns.alignAnim.isNil:
        ns.alignAnim.cancel()

    var axis = ns.scrollDirection != NodeScrollDirection.horizontal
    let fropP = if axis: ns.content.positionY else: ns.content.positionX
    let toP   = if axis: -ns.content.children[i].positionY else: -ns.content.children[i].positionX

    ns.alignAnim = newAnimation()
    ns.alignAnim.numberOfLoops = 1
    ns.alignAnim.loopDuration = d
    ns.alignAnim.cancelBehavior = cbJumpToEnd
    ns.alignAnim.onAnimate = proc(p: float) =
        var am  = interpolate(fropP, toP, p) - fropP
        if axis:
            ns.setContentY(fropP, am)
        else:
            ns.setContentX(fropP, am)
        if not ns.onActionProgress.isNil:
            ns.onActionProgress()
    ns.alignAnim.onComplete do():
        if not ns.onActionProgress.isNil:
            ns.onActionProgress()
        if not ns.onActionEnd.isNil:
            ns.onActionEnd()

    ns.content.addAnimation(ns.alignAnim)

proc scrollEnd(ns: NodeScroll, accelP: Point)=
    let accel = sqrt(accelP.x * accelP.x + accelP.y * accelP.y)
    var accelAnim: Animation
    if accel > 1.0:
        var toPos = newVector3()
        var accelAnimDur = 0.5

        if ns.scrollDirection == NodeScrollDirection.vertical or ns.scrollDirection == NodeScrollDirection.all:
            toPos.y = -accelP.y

        if ns.scrollDirection == NodeScrollDirection.horizontal or ns.scrollDirection == NodeScrollDirection.all:
            toPos.x = -accelP.x

        if accelAnimDur > 0.0:
            accelAnim = newAnimation()
            accelAnim.loopDuration = accelAnimDur
            accelAnim.numberOfLoops = 1
            accelAnim.onAnimate = proc(p: float) =
                let dst = toPos * (1.0 - p)
                if ns.scrollDirection == NodeScrollDirection.vertical:
                    ns.setContentY(ns.content.positionY, dst.y)
                elif ns.scrollDirection == NodeScrollDirection.horizontal:
                    ns.setContentX(ns.content.positionX, dst.x)
                elif ns.scrollDirection == NodeScrollDirection.all:
                    ns.setContentY(ns.content.positionY, dst.y)
                    ns.setContentX(ns.content.positionX, dst.x)

                if not ns.onActionProgress.isNil() and ns.scrollDirection != NodeScrollDirection.none:
                    ns.onActionProgress()

            if not ns.content.sceneView.isNil:
                ns.content.addAnimation(accelAnim)

            ns.alignAnim = accelAnim

    let alignAnim = newAnimation()
    alignAnim.loopDuration = alignDurat
    alignAnim.numberOfLoops = 1

    template doAccelAnim() =
        let fromPos = ns.content.position
        var toPos = ns.alignPosition()
        if fromPos != toPos:
            alignAnim.onAnimate = proc(p: float)=
                let am = interpolate(fromPos, toPos, p) - fromPos
                ns.setContentY(fromPos.y, am.y)
                ns.setContentX(fromPos.x, am.x)

                if not ns.onActionProgress.isNil() and ns.scrollDirection != NodeScrollDirection.none:
                    ns.onActionProgress()

            if not ns.content.sceneView.isNil:
                ns.content.addAnimation(alignAnim)

    if accelAnim.isNil:
       doAccelAnim()
    else:
        accelAnim.onComplete do():
            doAccelAnim()

proc getTopChildIndex*(ns: NodeScroll): int =
    let contentY = ns.content.positionY
    for i, ch in ns.content.children:
        if ch.positionY + contentY >= -20:
            return i

proc getLeftChildIndex*(ns: NodeScroll): int =
    let contentX = ns.content.positionX
    for i, ch in ns.content.children:
        if ch.positionX + contentX >= 0:
            return i

#[
    when axis true - positionY else positionX
    if direction > 0.0 - direction right/down else left/up
]#
proc pageAxis(ns: NodeScroll, axis:bool, direction: float)=
    if not ns.alignAnim.isNil:
        ns.alignAnim.cancel()

    let childIndex = if axis: ns.getTopChildIndex() else: ns.getLeftChildIndex()
    let nextChildIndex = if direction > 0.0: childIndex - 1 else: childIndex + 1

    template checkCond(body: untyped)=
        if ns.looped:
            body
        else:
            if axis:
                if direction > 0.0 and childIndex > 0:
                    body
                elif direction < 0.0 and childIndex < ns.len - (ns.scrollRect.height / ns.mNodeSize.height).int:
                    body
                else: discard
            else:
                if direction > 0.0 and childIndex > 0:
                    body
                elif direction < 0.0 and childIndex < ns.len - (ns.scrollRect.width / ns.mNodeSize.width).int:
                    body
                else: discard

    checkCond:
        let fropP = if axis: ns.content.positionY else: ns.content.positionX
        let toP   = if axis: -ns.content.children[nextChildIndex].positionY else: -ns.content.children[nextChildIndex].positionX

        ns.alignAnim = newAnimation()
        ns.alignAnim.numberOfLoops = 1
        ns.alignAnim.loopDuration = alignDurat
        ns.alignAnim.cancelBehavior = cbJumpToEnd
        ns.alignAnim.onAnimate = proc(p: float)=
            var am  = interpolate(fropP, toP, p) - fropP
            if axis:
                ns.setContentY(fropP, am)
            else:
                ns.setContentX(fropP, am)

        ns.alignAnim.addLoopProgressHandler(1.0, false) do():
            if not ns.onActionEnd.isNil and ns.scrollDirection != NodeScrollDirection.none:
                ns.onActionEnd()

        if not ns.onActionStart.isNil and ns.scrollDirection != NodeScrollDirection.none:
            ns.onActionStart()

        ns.content.addAnimation(ns.alignAnim)

proc indexOf*(ns: NodeScroll, n: Node): int =
    result = ns.content.children.find(n)

proc pageDown(ns: NodeScroll)=
    ns.pageAxis(true, -1.0)

proc pageUp(ns: NodeScroll)=
    ns.pageAxis(true, 1.0)

proc pageLeft(ns: NodeScroll)=
    ns.pageAxis(false, 1.0)

proc pageRight(ns: NodeScroll)=
    ns.pageAxis(false, -1.0)

proc moveRight*(ns: NodeScroll)=
    ns.pageRight()

proc moveLeft*(ns: NodeScroll)=
    ns.pageLeft()

proc moveUp*(ns: NodeScroll)=
    ns.pageUp()

proc moveDown*(ns: NodeScroll)=
    ns.pageDown()

method draw*(s: NodeScroll, r: Rect) =
    discard

method onTapDown*(lis : NodeScrollGesture, e : var Event) =
    lis.contentPosition = lis.nodeScroll.content.position
    lis.prevPosition = e.localPosition
    if not lis.nodeScroll.onActionStart.isNil() and lis.nodeScroll.scrollDirection != NodeScrollDirection.none:
        lis.nodeScroll.onActionStart()

    # if not lis.nodeScroll.alignAnim.isNil and (lis.nodeScroll.alignAnim.startTime > 0 and not lis.nodeScroll.alignAnim.finished):
    lis.nodeScroll.content.sceneView.removeAnimation(lis.nodeScroll.alignAnim)

method onTapUp*(lis: NodeScrollGesture, dx, dy : float32, e : var Event) =
    if not lis.nodeScroll.onActionEnd.isNil() and lis.nodeScroll.scrollDirection != NodeScrollDirection.none:
        lis.nodeScroll.onActionEnd()

    lis.nodeScroll.scrollEnd(lis.accelP)


method onScrollProgress*(lis: NodeScrollGesture, dx, dy : float32, e : var Event) =
    let
        sp = lis.contentPosition
        nd = lis.nodeScroll

    if nd.scrollDirection == NodeScrollDirection.vertical or
        nd.scrollDirection == NodeScrollDirection.all:

        nd.setContentY(sp.y, dy)

    if nd.scrollDirection == NodeScrollDirection.horizontal or
        nd.scrollDirection == NodeScrollDirection.all:

        nd.setContentX(sp.x , dx)

    lis.accelP = lis.prevPosition - e.localPosition
    lis.prevPosition = e.localPosition

    if not lis.nodeScroll.onActionProgress.isNil() and lis.nodeScroll.scrollDirection != NodeScrollDirection.none:
        lis.nodeScroll.onActionProgress()

method onScroll*(ns: NodeScroll, e: var Event): bool =
    if not ns.onActionStart.isNil() and ns.scrollDirection != NodeScrollDirection.none:
        ns.onActionStart()

    let ct = epochTime()
    if ns.lasScrollTime <= 0.1:
        ns.lasScrollTime = ct - 1.0

    ns.lasScrollTime = ct

    let cp = ns.content.position
    let prevBounces = ns.bounces

    ns.bounces = false
    if ns.scrollDirection == NodeScrollDirection.vertical or
        ns.scrollDirection == NodeScrollDirection.all:

        ns.setContentY(cp.y, -e.offset.y)

    if ns.scrollDirection == NodeScrollDirection.horizontal or
        ns.scrollDirection == NodeScrollDirection.all:

        ns.setContentX(cp.x , e.offset.x)
    ns.bounces = prevBounces

    if not ns.onActionProgress.isNil() and ns.scrollDirection != NodeScrollDirection.none:
        ns.onActionProgress()

    if not ns.onActionEnd.isNil() and ns.scrollDirection != NodeScrollDirection.none:
        ns.onActionEnd()

    # lis.nodeScroll.scrollEnd(lis.accelP)

    return true


proc resize*(ns: NodeScroll, size: Size) =
    let rect = newRect(ns.frame.origin, size)
    ns.scrollRect = rect
    ns.contentParent.parent.component(ClippingRectComponent).clippingRect = ns.scrollRect

    let cp = ns.content.position
    ns.setContentX(cp.x, 0.0)
    ns.setContentY(cp.y, 0.0)


method viewWillMoveToSuperview*(ns: NodeScroll, s: View)=
    if s.isNil:
        sharedNotificationCenter().removeObserver(ns)
    else:
        sharedNotificationCenter().addObserver("GAME_SCENE_RESIZE", ns) do(args: Variant):
            try:
                let r = args.get(Rect)
                echo "NodeScroll resize ", r
            except:
                discard
