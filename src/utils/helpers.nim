import nimx / [ view, image, animation, matrixes, button, notification_center, animation_runner ]
import rod / [ rod_types, node, viewport, quaternion, component ]
import rod / component / [ sprite, text_component, ui_component, solid, camera, rti ]
import sequtils, times

import shared / [localization_manager]
import falconserver.common.currency

import math, strutils, random, logging, tables

export viewport # for addAnimation template

proc mandatoryNode*(parent: Node, name: string): Node =
    result = parent.findNode(name)
    assert(not result.isNil, "Node '" & name & "' not found")

proc mandatoryChildNamed*(parent: Node, name: string): Node =
    result = parent.childNamed(name)
    assert(not result.isNil, "Node '" & name & "' not found")

proc addAnimation*(n: Node, a: Animation) =
    let sv = n.sceneView
    if not sv.isNil and not a.isNil:
        sv.addAnimation(a)
    else:
        warn "Animation isNil: " , a.isNil , " on scene isNil " , sv.isNil

proc removeChildrensExcept*(parent:Node, exceptions:seq[string]) =
    var del = newSeq[Node]()
    for ch in parent.children:
        if ch.name notin exceptions:
            del.add(ch)

    map[Node](del, proc(n:var Node) = n.removeFromParent())

proc startAnimatedTimer*(v: SceneView, timeout: float, callback: proc(), loops: int = 1): Animation {.discardable.} =
    result = newAnimation()
    result.loopDuration = timeout
    result.numberOfLoops = loops
    v.addAnimation(result)
    result.addLoopProgressHandler(1.0, false, callback)

#t is time(value of 0.0f-1.0f; 0 is the start 1 is the end)
proc calculateBezierPoint*(t: float, s, e, c1, c2: Vector3): Vector3 =
    var u = 1 - t
    var tt = t * t
    var uu = u * u
    var uuu = uu * u
    var ttt = tt * t

    result = newVector3(s.x * uuu, s.y * uuu)
    result.x += 3 * uu * t * c1.x
    result.y += 3 * uu * t * c1.y
    result.x += 3 * u * tt * c2.x
    result.y += 3 * u * tt * c2.y
    result.x += ttt * e.x
    result.y += ttt * e.y
    result.z = e.z

proc formatThousands*(value: int64): string =
    result = ($value).insertSep(',', 3)

proc parseThousands*(value: string): int64 =
    result = parseBiggestInt(replace(value, ",")).int64


proc startNumbersAnim*(v: SceneView, start, to: int64, duration: float, textComp: Text, format: bool = true) =
    let animVal = newAnimation()

    animVal.numberOfLoops = 1
    animVal.loopDuration = duration

    animVal.animate val in start .. to:
        if format:
            textComp.text = formatThousands(val)
        else:
            textComp.text = $val
    v.addAnimation(animVal)


proc onSpriteClick*(sv:SceneView, vector:Vector3, nodeName: string, parentNode:Node = nil): bool =
    var n: Node

    if parentNode.isNil:
        n = sv.rootNode.findNode(nodeName)
    else:
        n = parentNode.findNode(nodeName)

    let sprite = n.component(Sprite)
    let size = sprite.image.size

    var local: Vector3
    try:
        local = n.worldToLocal(vector)
    except:
        return false

    if local.x > 0 and local.x < size.width and local.y > 0 and local.y < size.height:
        return true
    return false

proc createHide(n: Node, duration: float = 0.0, callBack: proc() = nil): Animation {.inline.} =
    let oldAnim = n.animationNamed("helpersShowHideAnim")
    if not oldAnim.isNil:
        oldAnim.cancel()
    let cb = proc()=
        if not callback.isNil:
            callback()
        n.alpha = 0.0

    if n.alpha > 0.0:
        if duration < 0.0001:
            n.alpha = 0.0
            if not callBack.isNil:
                callBack()
            return

        var a = newAnimation()
        a.loopDuration = duration
        a.numberOfLoops = 1
        a.animate val in n.alpha .. 0.0:
            n.alpha = val

        a.onComplete(cb)
        n.registerAnimation("helpersShowHideAnim", a)
        result = a
    elif not oldAnim.isNil:
        oldAnim.onComplete(cb)
    else:
        cb()

proc hide*(n: Node, duration: float, callBack: proc()) =
    let a = createHide(n, duration, callBack)
    if not a.isNil:
        n.addAnimation(a)

proc hide*(n: Node, duration: float) =
    n.hide(duration, nil)

proc createShow(n: Node, duration = 0.0, callBack: proc() = nil): Animation {.inline.} =
    let oldAnim = n.animationNamed("helpersShowHideAnim")
    if not oldAnim.isNil:
        oldAnim.cancel()

    let cb = proc()=
        if not callback.isNil:
            callback()
        n.alpha = 1.0

    if n.alpha < 1.0:
        if duration < 0.0001:
            n.alpha = 1.0
            if not callBack.isNil:
                callBack()
            return

        var a = newAnimation()
        a.loopDuration = duration
        a.numberOfLoops = 1
        a.animate val in n.alpha .. 1.0:
            n.alpha = val

        a.onComplete(cb)
        # n.addAnimation(a)
        n.registerAnimation("helpersShowHideAnim", a)
        result = a

    elif not oldAnim.isNil:
        oldAnim.onComplete(cb)
    else:
        cb()

proc show*(n: Node, duration = 0.0, callBack: proc()) =
    let a = createShow(n, duration, callBack)
    if not a.isNil:
        n.addAnimation(a)

proc show*(n: Node, duration: float) =
    n.show(duration, nil)

template show*(n: Node) = n.alpha = 1.0
template hide*(n: Node) = n.alpha = 0.0

proc createMoveTo(node: Node, start, dest: Vector3, duration: float32, callback: proc() = nil): Animation {.inline.} =
    let anim = newAnimation()
    anim.loopDuration = duration
    anim.numberOfLoops = 1
    anim.animate val in start .. dest:
        node.position = val
    if not callback.isNil: anim.onComplete(callback)
    result = anim

proc createMoveTo(node: Node, dest: Vector3, duration: float32, callback: proc() = nil): Animation {.inline.} =
    result = createMoveTo(node, node.position, dest, duration, callback)

proc moveTo*(node: Node, start, dest: Vector3, duration: float32, callback: proc() = nil) =
    let anim = createMoveTo(node, start, dest, duration, callback)
    node.addAnimation(anim)

proc moveTo*(node: Node, dest: Vector3, duration: float32, callback: proc() = nil) =
    node.moveTo(node.position, dest, duration, callback)

proc createScaleTo(n: Node, destScale: Vector3, duration = 0.0, callback: proc() = nil): Animation {.inline.} =
    let oldAnim = n.animationNamed("helpersScaleToAnim")
    if not oldAnim.isNil:
        oldAnim.cancel()

    if duration < 0.0001:
        n.scale = destScale
        if not callback.isNil:
            callback()
        return

    var a = newAnimation()
    a.loopDuration = duration
    a.numberOfLoops = 1
    a.animate val in n.scale .. destScale:
        n.scale = val
    if not callback.isNil: a.onComplete(callback)
    n.registerAnimation("helpersScaleToAnim", a)
    result = a

proc scaleTo*(n: Node, destScale: Vector3, duration = 0.0, callback: proc() = nil) =
    let a = createScaleTo(n, destScale, duration, callback)
    n.addAnimation(a)

proc wait*(v: SceneView, time: float32, callback: proc()) =
    ## Executes `callback` upon completion of dummy animation with duration `time`
    ## It is not clear if its a good idea to use this approach...
    if not v.isNil and time > 0.001:
        var a = newAnimation()
        a.loopDuration = time
        a.numberOfLoops = 1
        a.onComplete do():
            callback()
            a = nil
        v.addAnimation(a)
    else:
        callback()

proc RTIfreezeEffect*(node:Node, state:bool) =
    doAssert(not node.isNil)
    if not node.isNil:
        if state:
            let rti = node.component(RTI)
            node.sceneView.wait(0.1) do():
                rti.bFreezeBounds = true
            rti.bFreezeChildren = true
            rti.bBlendOne = true
        else:
            node.removeComponent(RTI)

template blockTouch(v: View) = v.touchBlocked = true
template releaseTouch(v: View) = v.touchBlocked = false


proc componentsInNode*[T](n:Node, res: var seq[T])=
    let comp = n.componentIfAvailable(T)
    if not comp.isNil:
        res.add(comp)

    for ch in n.children:
        ch.componentsInNode(res)

proc uiComponentsState*(n: Node, enabled: bool) =
    var uiCompos = newSeq[UIComponent]()
    n.componentsInNode(uiCompos)
    for com in uiCompos:
        com.enabled = enabled

proc findNodesContains*(n: Node, substr: string, firstOnly: bool = true): seq[Node]=
    result = @[]

    for ch in n.children:
        if substr in ch.name:
            result.add(ch)
            if firstOnly:
                break
        else:
            let chRes = ch.findNodesContains(substr, firstOnly)
            if chRes.len > 0:
                result.add(chRes)
                if firstOnly:
                    break

proc minVector(a,b: Vector3):Vector3=
    result = newVector3(min(a.x, b.x), min(a.y, b.y), min(a.z, b.z))

proc maxVector(a,b:Vector3):Vector3=
    result = newVector3(max(a.x, b.x), max(a.y, b.y), max(a.z, b.z))

proc toRect*(bb: BBox): Rect=
    let minP = minVector(bb.minPoint, bb.maxPoint)
    let maxP = maxVector(bb.minPoint, bb.maxPoint)
    result = newRect(minP.x, minP.y, maxP.x - minP.x, maxP.y - minP.y)

proc nodeBounds2d*(n: Node, minP: var Vector3, maxP: var Vector3) =
    let wrldMat = n.worldTransform()

    var wp0, wp1, wp2, wp3: Vector3

    var i = 0
    while i < n.components.len:
        let comp = n.components[i]
        inc i

        let bb = comp.getBBox()
        let diff = bb.maxPoint - bb.minPoint
        if abs(diff.x) > 0 and abs(diff.y) > 0:

            wp0 = wrldMat * bb.minPoint
            wp1 = wrldMat * newVector3(bb.minPoint.x, bb.maxPoint.y, 0.0)
            wp2 = wrldMat * bb.maxPoint
            wp3 = wrldMat * newVector3(bb.maxPoint.x, bb.minPoint.y, 0.0)

            minP = minVector(minP, wp0)
            minP = minVector(minP, wp1)
            minP = minVector(minP, wp2)
            minP = minVector(minP, wp3)

            maxP = maxVector(maxP, wp0)
            maxP = maxVector(maxP, wp1)
            maxP = maxVector(maxP, wp2)
            maxP = maxVector(maxP, wp3)

    for ch in n.children:
        if ch.enabled:
            ch.nodeBounds2d(minP, maxP)

proc compareBoundsWithViewport*(vp: SceneView, minP: var Vector3, maxP: var Vector3) =
    let absBounds = vp.convertRectToWindow(vp.bounds)
    let vpWorldOrig = vp.screenToWorldPoint(newVector3(vp.bounds.x.float, vp.bounds.y.float, 0.0))
    let vpWorldSize = vp.screenToWorldPoint(newVector3(absBounds.width.float, absBounds.height.float, 0.0))
    minP = maxVector(minP, vpWorldOrig)
    maxP = maxVector(maxP, vpWorldOrig)
    minP = minVector(minP, vpWorldSize)
    maxP = minVector(maxP, vpWorldSize)

const absMinPoint = newVector3(high(int).Coord, high(int).Coord, high(int).Coord)
const absMaxPoint = newVector3(low(int).Coord, low(int).Coord, low(int).Coord)

proc nodeBounds*(n: Node, compareWithViewport: bool = false): BBox=
    var minP = absMinPoint
    var maxP = absMaxPoint
    n.nodeBounds2d(minP, maxP)
    if minP != absMinPoint and maxP != absMaxPoint:
        if compareWithViewport:
            n.sceneView.compareBoundsWithViewport(minP, maxP)
        result.minPoint = minP
        result.maxPoint = maxP

proc dimension*(bb: BBox): Vector3 =
    result = bb.maxPoint - bb.minPoint

proc normalizeName(name: string): string = #because we can have few text layers in ae composition with the same value. Names of these strings
    # are equal except of "$" and number after it
    let index = name.find("$")
    if index == -1:
        return name
    return name.substr(0, index - 1)

proc textToLocalized*(root: Node) =
    for c in root.children:
        if not c.getComponent("Text").isNil and not c.name.contains("@noloc"):
            let normalizedName = c.name.normalizeName()
            let newText = localizedString(normalizedName)
            c.component(Text).text = newText

        c.textToLocalized()

proc newLocalizedNodeWithResource*(name: string): Node =
    result = newNodeWithResource(name)
    result.textToLocalized()

proc formatDiffTime*(diff: float, formatStr = "d:h:m:s"): seq[string]=
    const hourSec = 3600.0
    const daySec = hourSec * 24.0
    const minutesSec = 60.0

    let days = diff / daySec
    var remDiff = 0.0
    if days >= 1.0:
        remDiff += days.int.float * daySec
    let hours = (diff - remDiff) / hourSec
    if hours >= 1.0:
        remDiff += hours.int.float * hourSec
    let minutes = (diff - remDiff) / minutesSec
    if minutes >= 1.0:
        remDiff += minutes.int.float * minutesSec
    let seconds = (diff - remDiff)

    result = @[]
    if "d" in formatStr:
        result.add($(days.int))
    if "h" in formatStr:
        #result.add(if hours < 10: "0" & $(hours.int) else: $(hours.int))
        result.add($(hours.int))
    if "m" in formatStr:
        #result.add(if minutes < 10: "0" & $(minutes.int) else: $(minutes.int))
        result.add($(minutes.int))
    if "s" in formatStr:
        result.add(if seconds < 10: "0" & $(seconds.int) else: $(seconds.int))

proc buildTimerString*(fmtTime: seq[string], formatStr = "d:h:m:s"): string=
    result = ""
    var startIndex = 0
    if "d" in formatStr:
        if fmtTime[0] != "0":
            var sKey = "TIMER_DAYS_ONLY"
            if fmtTime[0] == "1":
                sKey = "TIMER_DAY_ONLY"
            result = localizedFormat(sKey, fmtTime[0]) & " "
        startIndex = 1

    for i in startIndex..fmtTime.high:
        var nextToken = if fmtTime[i].len == 1: "0" & fmtTime[i]  else:  fmtTime[i]
        if i != startIndex:
            nextToken = ":" & nextToken
        result &= nextToken

    # var curAm = 0

    # var fts = ""
    # var sts = ""
    # result = ""
    # var hasDays = false
    # if fmtTime[0] != "0":
    #     hasDays = true
    #     fts = fmtTime[0]
    #     inc curAm

    # var hasHours = false
    # if fmtTime[1] != "0" or hasDays:
    #     hasHours = true
    #     if not hasDays:
    #         fts = fmtTime[1]
    #     else:
    #         sts = fmtTime[1]
    #     inc curAm

    # var hasMinutes = false
    # if ((fmtTime[2] != "0" or hasHours) and curAm < 2) or curAm == 0:
    #     hasMinutes = true
    #     if not hasHours:
    #         fts = fmtTime[2]
    #     else:
    #         sts = fmtTime[2]
    #     inc curAm

    # var hasSeconds = false
    # if curAm < 2:
    #     hasSeconds = true
    #     sts = fmtTime[3]

    # if hasSeconds and hasMinutes:
    #     result = localizedFormat("TIMER_MINUTES", fts, sts)
    # elif hasMinutes and hasHours:
    #     result = localizedFormat("TIMER_HOURS", fts, sts)
    # else:
    #     result = localizedFormat("TIMER_DAYS", fts, sts)

proc buildTimerString*(diff: float, formatStr = "d:h:m:s"):string =
    buildTimerString(formatDiffTime(diff, formatStr), formatStr)

proc addRotateAnimation*(n: Node, speed: float): Animation {.discardable.} =
    result = newAnimation()
    var targetAngle = 360.0
    result.loopDuration = abs(targetAngle / speed)
    targetAngle *= sgn(speed).float
    result.numberOfLoops = -1

    n.registerAnimation("addRotateAnimation", result)

    result.onAnimate = proc(p:float)=
        n.rotation = newQuaternionFromEulerXYZ(0.0, 0.0, interpolate(0.0, targetAngle, p))
    n.addAnimation(result)

proc playAnimationWithCb*(n: Node, animname:string, cb: proc())=
    let anim = n.animationNamed(animname)
    if not anim.isNil:
        n.addAnimation(anim)
        if not cb.isNil:
            anim.onComplete do():
                cb()
    else:
        echo "helpers.nim:playAnimation animation not found ", animname

proc playAnimation*(n: Node, animname:string) =
    n.playAnimationWithCb(animname, nil)

proc addRewardFlyAnim*(sourceNode: Node, destNode: Node, scale: Vector3, parent: Node = nil): Animation {.discardable.} =
    const REWARDS_OUT_DURATION = 0.5
    var dst = destNode
    if dst.isNil:
        dst = sourceNode.sceneView.rootNode.findNode("rewardsFlyParent")

    if sourceNode.positionY > 500.0:
        sourceNode.positionY = 500.0

    var s = sourceNode.worldPos
    let e = if not dst.isNil: dst.worldPos else: s
    let p1 = (e - s) / 3 + s + newVector3(rand(-300.0 .. 300.0), rand(-300.0 .. 300.0), 0)
    let p2 = (e - s) * 2 / 3 + s + newVector3(rand(-300.0 .. 300.0), rand(-300.0 .. 300.0), 0)
    let c1 = newVector3(p1.x, p1.y, s.z)
    let c2 = newVector3(p2.x, p2.y, s.z)
    let initialScale = sourceNode.scale

    if not dst.isNil:
        sourceNode.reattach(if not parent.isNil: parent else: dst)

    result = newAnimation()
    result.loopDuration = REWARDS_OUT_DURATION
    result.numberOfLoops = 1
    result.onAnimate = proc(p:float) =
        let t = interpolate(0.0, 1.0, p)
        let point = calculateBezierPoint(t, s, e, c1, c2)
        sourceNode.scale = interpolate(initialScale, scale, p)
        sourceNode.worldPos = point

    result.onComplete do():
        sourceNode.removeFromParent()

    dst.addAnimation(result)

proc adjustNodeByPaddings*(n: Node) =
    const OFFSET = newVector3(-300, -180)
    n.position = n.position + OFFSET

proc affectsChildrenRec*(n: Node, state: bool)=
    n.affectsChildren = state
    for ch in n.children:
        ch.affectsChildrenRec(state)


import shared.user
# proc withdraw*(u: User, chips: int64 = 0, bucks: int64 = 0, parts: int64 = 0, source: string = ""): bool =
proc tryWithdraw*(u: User, c: Currency, a: int64): bool =
    case c:
    of Currency.Parts:
        result = u.withdraw(parts = a)

    of Currency.Chips:
        result = u.withdraw(chips = a)

    of Currency.Bucks:
        result = u.withdraw(bucks = a)

    of Currency.TournamentPoint:
        if u.tournPoints >= a:
            u.tournPoints -= a
            result = true
    else:
        result = false

proc absVector*(vec: Vector3): Vector3 =
    result = newVector3(abs(vec.x), abs(vec.y), abs(vec.z))

proc defineCountSymbols*(number: int64, max_symbols: int): tuple[firstSymbol: int, symbolsCount: int] =
    doAssert(number < (pow(10'f32, (max_symbols + 1).float32).int64))
    var digits = ($number).len
    var isEven = max_symbols mod 2 == 0
    var firstSymbol = max_symbols div 2

    if not isEven:
        firstSymbol.inc()
    for i in 1..max_symbols:
        if digits == i:
            return (firstSymbol, digits)
        if isEven:
            if i mod 2 == 0:
                firstSymbol.dec()
        else:
            if i mod 2 == 1:
                firstSymbol.dec()

proc getSize*(t: Text): Size =
    let bbox = t.getBBox()
    result = newSize(bbox.maxPoint.x - bbox.minPoint.x, bbox.maxPoint.y - bbox.minPoint.y)

proc numberOfNodesInTree*(n: Node): int =
    if n.isNil: return

    for ch in n.children:
        result += 1
        result += numberOfNodesInTree(ch)

proc numberOfEnabledNodes*(n: Node): int =
    if n.isNil or not n.enabled: return
    for ch in n.children:
        if ch.enabled:
            result += 1
            result += numberOfEnabledNodes(ch)


proc numberOfForeverAnims*(sc: SceneView): int =
    if sc.isNil: return
    for a in sc.animationRunner.animations:
        if a.numberOfLoops == -1:
            result += 1


const editorEnabled* = defined(editorEnabled) or not defined(release)
when editorEnabled:
    import rod.edit_view

    proc startEditor*(v: SceneView): Editor =
        result = startEditingNodeInView(v.rootNode, v)
        # let editorCamera = result.editorActiveCamera()
        # let sceneCamera = v.camera

        # if not editorCamera.isNil:
        #     echo " >> setup editor Camera"
        #     editorCamera.viewportSize = sceneCamera.viewportSize
        #     editorCamera.node.scale = sceneCamera.node.scale
        #     editorCamera.node.worldPos = sceneCamera.node.worldPos
        #     editorCamera.projectionMode = sceneCamera.projectionMode
        #     v.camera = editorCamera

