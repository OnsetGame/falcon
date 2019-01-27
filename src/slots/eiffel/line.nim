import algorithm, tables, math, random
import nimx / [ context, portable_gl, types, composition, font, animation, timer ]
import rod / [ component, node, viewport ]
import rod.component.text_component

import falconserver.slot.machine_base_types

import symbol_highlight

import utils / [ sound_manager, pause, fade_animation, helpers ]
import core.slot.base_slot_machine_view
import shared.gui.win_panel_module

type Symbols* = enum
    Wild,       #0
    Scatter,    #1
    Bonus,      #2
    Chef,       #3
    Woman,      #4
    Frenchman,  #5
    Painter,    #6
    Ace,        #7
    Queen,      #8
    Jack,       #9
    Ten,        #10
    Nine        #11

type SymbolComponent* = ref object of Component
    sym*:Symbols
registerComponent(SymbolComponent)

type LinesComponent* = ref object of Component
    view*: BaseMachineView
    animationValue*: float
    lineCoords*: seq[seq[Point]]
    curLine*: int
    reelNodes*: seq[Node]
    isRepeating*: bool
    onAnimateLine*: proc(lineIndex: int)
    onLinesAnimationComplete*: proc()
    symbolHighlightController*: SymbolHighlightController
    repeatingLinesTimer: ControlledTimer
    mNumbersNode: Node
    mLeftProjNode, mRightProjNode: Node # Projectors that are shown on the ends of the winning line
    linesAnimation*: Animation
    enabled*: bool
    soundManager*: SoundManager
    lineQueue: seq[int]
    lineIndex: int

registerComponent(LinesComponent)

const OFFSET_X = -320
const OFFSET_Y = -180
const FADE_SIZE = newSize(1920, 1080)
const DURATION = 1.1
const DURATION_LINE = 0.8
const FADE_OFFSET = 0.16
const FLASH_DURATION = 0.15

var lineComposition = newComposition """
#define MAX_LEN 7
uniform vec2 uPoints[MAX_LEN];
uniform int uLen;
uniform vec2 viewportSize;
uniform float innerWidth;

float distToLine(vec2 pt1, vec2 pt2, vec2 testPt) {
    vec2 lineDir = pt2 - pt1;
    vec2 perpDir = vec2(lineDir.y, -lineDir.x);
    vec2 dirToPt1 = pt1 - testPt;
    return abs(dot( normalize(perpDir), dirToPt1 ));
}

float isPointProjectionOnSegment(vec2 a, vec2 b, vec2 p) {
    vec2 e1 = b - a;
    float recArea = dot(e1, e1);
    vec2 e2 = p - a;
    float val = dot(e1, e2);
    return (val > 0.0 && val < recArea) ? 1.0 : 0.0;
}

float distToSegment(vec2 a, vec2 b, vec2 p) {
    float dist = distToLine(a, b, p);
    //float isOnSeg = isPointProjectionOnSegment(a, b, p);
    //if (isOnSeg > 0.5) { return dist; }

    """ &   # код скопирован с ф-и isPointProjectionOnSegment
            # на некоторых андройдах иначе не работает (видать уперлись в ограничение регистров в шейдера)
    """
    vec2 e1 = b - a;
    float recArea = dot(e1, e1);
    vec2 e2 = p - a;
    float val = dot(e1, e2);

    if (val > 0.0 && val < recArea) { return dist; }
    return 9999.0;
}

float drawLine(vec2 p1, vec2 p2, float uStrokeWidth) {
  vec2 va = p2 - p1;
  vec2 vb = vPos - p1;
  vec2 vc = vPos - p2;

  vec3 tri = vec3(distance(p1, p2), distance(vPos, p1), distance(vPos, p2));
  float p = (tri.x + tri.y + tri.z) / 2.0;
  float h = 2.0 * sqrt(p * (p - tri.x) * (p - tri.y) * (p - tri.z)) / tri.x;

  vec2 angles = acos(vec2(dot(normalize(-va), normalize(vc)), dot(normalize(va), normalize(vb))));
  vec2 anglem = 1.0 - step(PI / 2.0, angles);
  float pixelValue = 1.0 - smoothstep(0.0, uStrokeWidth, h);

  float res = anglem.x * anglem.y * pixelValue;
  return res;
}

vec2 fbUv(vec4 imgTexCoords) {
    vec2 p = gl_FragCoord.xy;
    p.y = viewportSize.y - p.y;
    return imgTexCoords.xy + (imgTexCoords.zw - imgTexCoords.xy) * (p / viewportSize);
}

void compose() {
    float dist = distance(uPoints[0], vPos);
    if (0 < uLen - 1)
    {
        dist = min(dist, distToSegment(uPoints[0], uPoints[1], vPos));
        dist = min(dist, distance(uPoints[1], vPos));
    }
    if (1 < uLen - 1)
    {
        dist = min(dist, distToSegment(uPoints[1], uPoints[2], vPos));
        dist = min(dist, distance(uPoints[2], vPos));
    }
    if (2 < uLen - 1)
    {
        dist = min(dist, distToSegment(uPoints[2], uPoints[3], vPos));
        dist = min(dist, distance(uPoints[3], vPos));
    }
    if (3 < uLen - 1)
    {
        dist = min(dist, distToSegment(uPoints[3], uPoints[4], vPos));
        dist = min(dist, distance(uPoints[4], vPos));
    }
    if (4 < uLen - 1)
    {
        dist = min(dist, distToSegment(uPoints[4], uPoints[5], vPos));
        dist = min(dist, distance(uPoints[5], vPos));
    }
    if (5 < uLen - 1)
    {
        dist = min(dist, distToSegment(uPoints[5], uPoints[6], vPos));
        dist = min(dist, distance(uPoints[6], vPos));
    }

    float burnWidth = 20.0;

    float sm_alpha = 1.0 - smoothstep(burnWidth - 1.0, burnWidth, dist);
    gl_FragColor = vec4(sm_alpha);
}
"""

proc boundsOfPoints*(points: openarray[Point]): Rect =
    var
        minX: Coord = 9999999
        minY: Coord = 9999999
        maxX: Coord = 0
        maxY: Coord = 0

    for p in points:
        if p.x < minX:
            minX = p.x
        if p.x > maxX:
            maxX = p.x
        if p.y < minY:
            minY = p.y
        if p.y > maxY:
            maxY = p.y

    result.origin.x = minX
    result.origin.y = minY
    result.size.width = maxX - minX
    result.size.height = maxY - minY

proc dist(p1, p2: Point): Coord =
    let a = p2.x - p1.x
    let b = p2.y - p1.y
    result = sqrt(a * a + b * b)

var animatedPoints = newSeq[Point](7)
var distances = newSeq[Coord](7)

proc drawLineWithPoints(lc: LinesComponent, points: openarray[Point]) =
    var totalLen = Coord(0)
    distances.setLen(points.len)
    for i in 0 ..< points.len - 1:
        distances[i] = dist(points[i], points[i + 1])
        totalLen += distances[i]

    let fromDist = -totalLen
    let toDist = totalLen

    var startDist = fromDist + (toDist - fromDist) * lc.animationValue
    var endDist = startDist + totalLen

    animatedPoints.setLen(0)
    var startFound = false
    var distCovered = Coord(0)

    var i = 0
    while i < points.len:
        let d = distances[i]
        if startFound:
            animatedPoints.add(points[i])
            if distCovered + d > endDist and i != points.len - 1:
                # End found
                animatedPoints.add(newPoint(points[i].x, points[i].y))
                let p = (endDist - distCovered) / d
                animatedPoints[^1].x += (points[i + 1].x - points[i].x) * p
                animatedPoints[^1].y += (points[i + 1].y - points[i].y) * p
                break
        else:
            if distCovered + d > startDist:
                startFound = true
                animatedPoints.add(newPoint(points[i].x, points[i].y))
                if startDist > distCovered:
                    let p = (startDist - distCovered) / d
                    animatedPoints[^1].x += (points[i + 1].x - points[i].x) * p
                    animatedPoints[^1].y += (points[i + 1].y - points[i].y) * p
                else:
                    if distCovered + d > endDist:
                        # End found
                        animatedPoints.add(newPoint(points[i].x, points[i].y))
                        let p = (endDist - distCovered) / d
                        animatedPoints[^1].x += (points[i + 1].x - points[i].x) * p
                        animatedPoints[^1].y += (points[i + 1].y - points[i].y) * p
                        break

        distCovered += d
        inc i

    var bounds = boundsOfPoints(animatedPoints)
    bounds = bounds.inset(-20, -20)
    let vpbounds = currentContext().gl.getViewport()
    let vpSize = newSize(vpbounds[2].Coord, vpbounds[3].Coord)

    if animatedPoints.len > 1:
        lineComposition.draw bounds:
            setUniform("uPoints", animatedPoints)
            setUniform("uLen", GLint(animatedPoints.len))
            setUniform("viewportSize", vpSize)
            setUniform("innerWidth", 8.0)

proc drawRepeatingLine(lc: LinesComponent, points: openarray[Point]) =
    var bounds = boundsOfPoints(points)
    bounds = bounds.inset(-20, -20)
    let vpbounds = currentContext().gl.getViewport()
    let vpSize = newSize(vpbounds[2].Coord, vpbounds[3].Coord)

    lineComposition.draw bounds:
        setUniform("uPoints", points)
        setUniform("uLen", GLint(points.len))
        setUniform("viewportSize", vpSize)
        setUniform("innerWidth", 0.0)

method draw(lc: LinesComponent) =
    if lc.enabled:
        # lc.node.sceneView.swapCompositingBuffers()
        if lc.curLine < 20:
            let c = currentContext()
            c.gl.enable(c.gl.BLEND)
            c.gl.blendFunc(c.gl.DST_COLOR, c.gl.ONE) # бленд оверлей

            if lc.isRepeating:
                lc.drawRepeatingLine(lc.lineCoords[lc.curLine])
            else:
                lc.drawLineWithPoints(lc.lineCoords[lc.curLine])

            c.gl.blendFunc(c.gl.SRC_ALPHA, c.gl.ONE_MINUS_SRC_ALPHA)

proc setDefaultFontSettings(n: Node, offsetX, offsetY: float)=
    var t = n.component(Text)
    # n.positionY = n.positionY + offsetY
    # n.positionX = n.positionX + offsetX
    # t.font.size = t.font.size * 1.3
    t.shadowX = 1.0
    t.shadowY = 4.0
    t.strokeSize = 3.5
    t.isColorGradient = true
    t.colorFrom = newColor(255/255, 218/255, 168/255)
    t.colorTo   = newColor(255/255, 253/255, 251/255)

proc numbersNode(lc: LinesComponent): Node =
    if lc.mNumbersNode.isNil:
        lc.mNumbersNode = newLocalizedNodeWithResource("slots/eiffel_slot/eiffel_messages/small_win.json")
        lc.mNumbersNode.findNode("textField").setDefaultFontSettings(0.0, 25.0)
    if lc.mNumbersNode.parent.isNil:
        lc.node.addChild(lc.mNumbersNode)
    result = lc.mNumbersNode

proc payoutForLine(lc: LinesComponent, lineNo: int): int64 =
    for pLine in lc.view.paidLines:
        if pLine.index == lineNo:
            return pLine.winningLine.payout

proc nextLine(lc: LinesComponent) =
    lc.curLine = lc.lineQueue[lc.lineIndex]
    if lc.lineIndex < lc.lineQueue.len - 1:
        inc lc.lineIndex
    else:
        lc.lineIndex = 0

proc resetLines*(lc: LinesComponent) =
    lc.lineQueue.setLen(0)
    lc.lineIndex = 0
    lc.curLine = -1

proc rewindLine(lc: LinesComponent) =
    lc.curLine = -1
    lc.lineIndex = 0
    lc.lineQueue = @[]
    var payout_table = newCountTable[int64]()
    var bet = lc.view.totalBet()
    for i, ln in lc.view.paidLines:
        for j in 0 ..< ln.winningLine.numberOfWinningSymbols:
            let vPos = lc.view.lines[ln.index][j]
            let n = lc.reelNodes[j].findNode("Field").childNamed($(vPos + 1)).findNode("symbol")
            let symb = n.component(SymbolComponent).sym
            var pay_p = ((ln.winningLine.payout.int64 div bet).float / ln.winningLine.numberOfWinningSymbols.float) * 1000
            var sym_p = (((Symbols.Nine.int + 1) - symb.int) / (6 - ln.winningLine.numberOfWinningSymbols)) * 100
            var line = 20 - ln.index
            payout_table.inc(ln.index , pay_p.int + sym_p.int + line)

    lc.lineQueue = newSeq[int]()
    payout_table.sort()

    for k, v in payout_table:
        lc.lineQueue.add(k.int)

    payout_table = nil
    lc.nextLine()

proc numberOfWinningLines(lc: LinesComponent): int =
    return lc.view.paidLines.len

proc startAnimation*(linesComp: LinesComponent) =
    linesComp.enabled = true
    linesComp.rewindLine()

    var sum: int64 = 0
    let linesNode = linesComp.node

    let winningBlackoutNode = linesNode.sceneView.rootNode.findNode("WinBlackout")
    doAssert(not winningBlackoutNode.isNil)

    var returnSymbolsToNodes = newSeq[tuple[sym, node: Node]]()

    type WinNode = tuple[node: Node, line: int]
    let numReels = linesComp.reelNodes.len
    var winningLineMatrix = newTable[int, seq[Node]]()

    let fade = addFadeSolidAnim(linesNode.sceneView, winningBlackoutNode, blackColor(), FADE_SIZE, 0.0, 0.0, 0.2)
    for i, ln in linesComp.view.paidLines:
        var winSeq = newSeq[Node]()

        for j in 0 ..< ln.winningLine.numberOfWinningSymbols:
            let vPos = linesComp.view.lines[ln.index][j]
            let n = linesComp.reelNodes[j].findNode("Field").childNamed($(vPos + 1))
            if not n.isNil:
                winSeq.add(n)
                returnSymbolsToNodes.add((n, n.parent))

        if not winningLineMatrix.hasKey(ln.index):
            winningLineMatrix[ln.index] = winSeq

    for k, v in winningLineMatrix:
        for n in v:
            n.reparentTo(winningBlackoutNode)

    let numbersNode = linesComp.numbersNode
    let numbersText = numbersNode.findNode("textField").component(Text)
    let numbersAnim = numbersNode.animationNamed("play")

    let lineAnim = newAnimation()

    lineAnim.addLoopProgressHandler 0.0, true, proc() =
        linesComp.view.setTimeout FADE_OFFSET, proc() =
            fade.color = whiteColor()
            fade.alpha = 1.0
            fade.changeFadeAnimMode(0.0, FLASH_DURATION)
            linesComp.view.setTimeout FLASH_DURATION, proc() =
                fade.color = blackColor()
                fade.alpha = 1.0
                fade.changeFadeAnimMode(0.0, DURATION - FADE_OFFSET - FLASH_DURATION)

    lineAnim.addLoopProgressHandler 0.25, true, proc() =
        linesComp.soundManager.sendEvent("WIN_LINE" & $rand(1..3))

    var toValue: int64 = 0
    var fromValue = 0

    lineAnim.animate val in 0.0 .. 1.0:
        linesComp.animationValue = val
        # if val < 0.9:
            # numbersText.text = $interpolate(fromValue, toValue, val)

    numbersAnim.loopDuration = DURATION_LINE
    lineAnim.loopDuration = DURATION_LINE
    # lineAnim.loopDuration = numbersAnim.loopDuration
    lineAnim.numberOfLoops = linesComp.numberOfWinningLines()
    lineAnim.addLoopProgressHandler 1.0, false, proc() =
        linesComp.nextLine()

    lineAnim.addLoopProgressHandler 0.9, false, proc() =
        numbersText.text = $toValue

    lineAnim.addLoopProgressHandler 0.0, false, proc() =
        let winningLine = linesComp.curLine
        let reelsCount = linesComp.reelNodes.len
        let p = linesComp.lineCoords[winningLine][int(reelsCount / 2) + 1]
        toValue = linesComp.payoutForLine(winningLine)
        if not numbersText.isNil:
            numbersText.text = $toValue
            numbersNode.positionX = p.x + OFFSET_X
            numbersNode.positionY = p.y + OFFSET_Y
            linesNode.addAnimation(numbersAnim)
            linesComp.view.slotGUI.winPanelModule.setNewWin(sum + toValue, true)
            sum += toValue

    lineAnim.onComplete do():
        numbersNode.removeFromParent()
        for s in returnSymbolsToNodes:
            s.sym.reparentTo(s.node)
        linesComp.onLinesAnimationComplete()

    proc addShakeSymbolAnim(p: float, reelIndex: int) =
        proc shakeSymbol() =
            var winningLine = linesComp.curLine
            var winNode: Node
            if winningLineMatrix.hasKey(winningLine) and winningLineMatrix[winningLine].len > reelIndex:
                var winSeq = winningLineMatrix[winningLine]
                winNode = winSeq[reelIndex]

            if not winNode.isNil:
                let anim = winNode.animationNamed("shake_win")
                linesNode.addAnimation(anim)
                let animatedSym = winNode.findNode("symbol")
                let playAnim = animatedSym.animationNamed("play")
                if not playAnim.isNil:
                    let delay = reelIndex.float * 0.15
                    linesComp.view.setTimeout delay, proc() =
                        linesNode.addAnimation(playAnim)

        lineAnim.addLoopProgressHandler(p, false, shakeSymbol)

    if linesComp.mLeftProjNode.isNil:
        linesComp.mLeftProjNode = newLocalizedNodeWithResource("slots/eiffel_slot/eiffel_slot/precomps/ProjLightTex.json")
    if linesComp.mRightProjNode.isNil:
        linesComp.mRightProjNode = newLocalizedNodeWithResource("slots/eiffel_slot/eiffel_slot/precomps/ProjLightTex.json")

    proc addProjectorAnim(p: float, start: bool, projNode: Node) =
        proc proj() =
            if linesComp.curLine >= linesComp.lineCoords.len: return
            let pos = if start:
                    linesComp.lineCoords[linesComp.curLine][0]
                else:
                    linesComp.lineCoords[linesComp.curLine][^1]

            projNode.position = newVector3(pos.x, pos.y, 0)
            projNode.scale = newVector3(5, 5, 1)
            linesNode.sceneView.rootNode.addChild(projNode)
            let anim = projNode.animationNamed("play")
            anim.onComplete do():
                projNode.removeFromParent()
            linesNode.addAnimation(anim)
        lineAnim.addLoopProgressHandler(p, false, proj)

    addProjectorAnim(0.0, true, linesComp.mLeftProjNode)
    addShakeSymbolAnim(0.0, 0)
    addShakeSymbolAnim(0.1, 1)
    addShakeSymbolAnim(0.20, 2)
    addShakeSymbolAnim(0.35, 3)
    addShakeSymbolAnim(0.6, 4)
    addProjectorAnim(0.4, false, linesComp.mRightProjNode)

    linesComp.linesAnimation = lineAnim
    linesNode.addAnimation(lineAnim)

proc clearAnimation*(lc: LinesComponent, cb: proc()) =
    lc.enabled = false
    if not lc.linesAnimation.isNil:
        if not lc.linesAnimation.finished:
            lc.linesAnimation.cancel()
            lc.linesAnimation.onComplete do():
                cb()
            lc.curLine = 20
            lc.linesAnimation.numberOfLoops = 0

proc getPaidLineByIndex(lc: LinesComponent, index: int): PaidLine =
    for line in lc.view.paidLines:
        if line.index == index:
            return line

proc startRepeatingLines*(lc: LinesComponent) =
    const REELS_NUM = 4
    const LINES_NUM = 3

    if lc.numberOfWinningLines() > 0:
        lc.enabled = true
        if not lc.repeatingLinesTimer.isNil():
            lc.view.pauseManager.clear(lc.repeatingLinesTimer)
            lc.repeatingLinesTimer = nil
        lc.isRepeating = true
        lc.curLine = -1

        proc switchRepeatingLine() =
            lc.nextLine()

            if lc.curLine >= 20:
                lc.rewindLine()

            if lc.curLine >= 20:
                return

            if not lc.onAnimateLine.isNil:
                lc.onAnimateLine(lc.curLine)

            let pLine = lc.getPaidLineByIndex(lc.curLine)
            lc.symbolHighlightController.clearSymbolHighlights()
            for j in 0 ..< pLine.winningLine.numberOfWinningSymbols:
                let vPos = lc.view.lines[lc.curLine][j]
                let n = lc.reelNodes[j].findNode("Field").childNamed($(vPos + 1))

                lc.symbolHighlightController.setSymbolHighlighted(n, true)

            let winningLine = lc.curLine
            let numbersNode = lc.numbersNode
            let reelsCount = lc.reelNodes.len
            let p = lc.lineCoords[winningLine][int(reelsCount / 2) + 1]
            numbersNode.positionX = p.x + OFFSET_X
            numbersNode.positionY = p.y + OFFSET_Y
            numbersNode.findNode("textField").component(Text).text = $(pLine.winningLine.payout)
            let anim = numbersNode.animationNamed("play")
            lc.node.addAnimation(anim)

        lc.repeatingLinesTimer = lc.view.setInterval(1.5, switchRepeatingLine)
        switchRepeatingLine()

proc stopRepeatingLines*(lc: LinesComponent) =
    lc.enabled = false
    if not lc.repeatingLinesTimer.isNil():
        lc.view.pauseManager.clear(lc.repeatingLinesTimer)
        lc.repeatingLinesTimer = nil
    lc.isRepeating = false
    lc.numbersNode.removeFromParent()
