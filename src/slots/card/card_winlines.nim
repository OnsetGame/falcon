import nimx / [matrixes, types, animation]
import rod / [ node, quaternion ]
import rod.component
import rod.component / [ gradient_fill, ae_composition, text_component ]
import node_proxy.proxy
import utils.helpers
import sequtils
import core.slot.base_slot_machine_view
import core.slot.slot_types
import core.slot.sound_map
import core.components.render_order
import card_slot_view, card_types
import slots.groovy.reelset_component
import slots.groovy.cell_component
import math
import card_highlights

const
    SYMBOL_SIZE_HEIGHT* = Coord(232) #Distance to pivot + half of element 225
    SYMBOL_SIZE_WIDTH* = Coord(176) #Distance to pivot + half of element 210
    SYMBOL_SIZE_HEIGHT_OFFSET* = Coord(140) #Distance to pivot + half of element 225
    SYMBOL_SIZE_WIDTH_OFFSET* = Coord(168) #Distance to pivot + half of element 210

    EFFECT_SIZE_HEIGHT* = Coord(134)
    EFFECT_SIZE_WIDTH* = Coord(198)
    EFFECT_SCALE* = Coord(1.3)

nodeProxy SlotWinNumber:
    aeComp AEComposition {onNode: node}
    playAnim Animation {withValue: np.aeComp.compositionNamed("play")}
    numbers seq[Node] {withValue: toSeq(1..3).map(proc(i: int): Node = np.node.findNode("counter_" & $i & "_@noloc"))}

proc playSlotWinNumber*(parent: Node, amount: int64, index: int, cb: proc() = nil) =
    let yOffsets = @[-250.0, 0.0, 250.0]
    let swn = new(SlotWinNumber, newLocalizedNodeWithResource("slots/card_slot/branding/precomps/small_win"))
    swn.node.positionX = -265

    parent.addChild(swn.node)

    for i in 0..2:
        swn.numbers[i].getComponent(GradientFill).startPoint.y = -150
        swn.numbers[i].getComponent(GradientFill).endPoint.y = 0
        swn.numbers[i].getComponent(Text).text = $amount
    swn.node.positionY = swn.node.positionY + yOffsets[index]
    swn.node.addAnimation(swn.playAnim)
    swn.playAnim.onComplete do():
        swn.node.removeFromParent()
        if not cb.isNil:
            cb()

proc initWinLinesNodesTree(v: CardSlotView) =
    v.fireLinesGroup = v.winlineParent.findNode("fireline_parent")

    if v.fireLinesGroup.isNil:
        v.fireLinesGroup = newNode("fireline_parent")
        v.winlineParent.addChild(v.fireLinesGroup)

    var fireLineName: string

    for i in 0 .. < v.lines.len:
        fireLineName = "fireline_sequence" & $i
        var fireLine = v.fireLinesGroup.findNode(fireLineName)
        if fireLine.isNil:
            fireLine = newNode(fireLineName)
            v.fireLinesGroup.addChild(fireLine)

proc addWinLineBeams(v: CardSlotView, index: int, amount:int = 8) =
    #max 8 beams

    if v.fireLinesGroup.isNil:
        return

    proc createBeamNode():Node =
        result = newNodeWithResource("slots/card_slot/specials/precomps/winning_line_element")
        result.name = "winline_element"
        result.position = newVector3(0.0,0.0,0.0)
        result.anchor = newVector3(99.0,67.0,0.0)
        result.scale = newVector3(1.5,1.5,0.0)
        result.alpha = 1.0

    let fpChildName: string = "fireline_sequence" & $index
    var fireLine = v.fireLinesGroup.findNode(fpChildName)

    var nodesRequired = amount
    if nodesRequired == 0:
        nodesRequired = 1

    if not fireLine.isNil:
        for i in 1..nodesRequired:
            let newBeamNode = createBeamNode()
            fireLine.addChild(newBeamNode)
    else:
        raise

proc initWinLinesCoords*(v: CardSlotView) =

    var winLines: array[0..19, WinLine]
    var beamsQuantity: int = 0

    let reelsetStepX = v.reelset.stepX() #float32
    let reelsetStepY = v.reelset.stepY() #float32
    let scaler: float32 = (reelsetStepX / EFFECT_SIZE_WIDTH) * EFFECT_SCALE

    v.initWinLinesNodesTree()

    let fp = v.fireLinesGroup

    proc getOffsetByFlipAngle(flipAng: float32): float32 =
        if flipAng == 1:
            result = -20
        else:
            result = 20

    #const view_center = 960
    for i in 0..<v.lines.len:   #[ {0,1,2,1,2}, {1,2,1,2,1}, ..., {} x19]#

        #---Beams per reel---#
        beamsQuantity = 0
        var lineBeams: int = 0

        #---Rotation of odd beams---#
        var flipAngle: float32 = 1

        #-----------Animation setup-----------#
        var animationsMarkers = newSeq[ComposeMarker]()
        var nextAnimDelay = 0.0
        #-------Animation setup finish--------#

        let frChildName: string = "fireline_sequence" & $i
        let frChild = fp.findNode(frChildName)

        for j in 1.. <NUMBER_OF_REELS: #[1..4]#

            let reelSetNodePrev = v.reelset.reels[j-1].elems[v.lines[i][j-1]] #[Previous reel beamNode indexed by lines mask]#

            lineBeams = v.lines[i][j] - v.lines[i][j-1]
            beamsQuantity += (if lineBeams == 0: 1 else: abs(lineBeams))

            #For reels 1-X add Y lineBeams. 0 lineBeams add 1 beam.
            v.addWinLineBeams(i, abs(lineBeams))

            let beamNode: Node = frChild.children[frChild.children.len - 1] #pick last added element

            beamNode.scale = newVector(scaler, scaler, 1.0)

            let multiplier: float = 1.0

            case abs(lineBeams)
                of 0: #straight beam
                    let x_offset = SYMBOL_SIZE_WIDTH_OFFSET + (SYMBOL_SIZE_WIDTH + reelsetStepX) * 0.5
                    let y_offset = SYMBOL_SIZE_HEIGHT_OFFSET + SYMBOL_SIZE_HEIGHT * 0.5 + getOffsetByFlipAngle(flipAngle)
                    beamNode.worldPos = reelSetNodePrev.worldPos() + newVector3(x_offset, y_offset, 0) * multiplier
                    beamNode.scale *= (newVector3(1.0, flipAngle, 1.0) * 1.3)
                    flipAngle = -flipAngle
                of 1: #downpointing beam
                    beamNode.scale *= (newVector3(1.0, flipAngle, 1.0) * 1.3) * (sqrt(reelsetStepX * reelsetStepX + reelsetStepY * reelsetStepY) / reelsetStepX)
                    beamNode.rotation = aroundZ((lineBeams / abs(lineBeams)) * radToDeg(arctan2(reelsetStepY,reelsetStepX)))

                    let x_offset = SYMBOL_SIZE_WIDTH_OFFSET + (SYMBOL_SIZE_WIDTH + reelsetStepX) * 0.5
                    let y_offset = SYMBOL_SIZE_HEIGHT_OFFSET + (SYMBOL_SIZE_HEIGHT + reelsetStepY * (lineBeams / abs(lineBeams))) * 0.5 + getOffsetByFlipAngle(flipAngle)
                    beamNode.worldPos = reelSetNodePrev.worldPos() + newVector3(x_offset, y_offset, 0) * multiplier
                    flipAngle = -flipAngle
                of 2:
                    let beamNodePrev: Node = frChild.children[frChild.children.len - 2] #pick before last added element
                    var scaleLen: float = sqrt(reelsetStepX * reelsetStepX + reelsetStepY * reelsetStepY) * 0.8
                    beamNode.scale *= (newVector3(1.0, flipAngle, 1.0) * 1.3) * (scaleLen / reelsetStepX)
                    beamNodePrev.scale *= (newVector3(1.0, flipAngle, 1.0) * 1.3) * (scaleLen / reelsetStepX)
                    beamNode.rotation = aroundZ(radToDeg(arctan2(reelsetStepY,reelsetStepX / 2)) * (lineBeams / abs(lineBeams)))
                    flipAngle = -flipAngle
                    beamNodePrev.rotation = aroundZ(radToDeg(arctan2(reelsetStepY,reelsetStepX / 2)) * (lineBeams / abs(lineBeams)))
                    flipAngle = -flipAngle
                    var x_offset = SYMBOL_SIZE_WIDTH_OFFSET + (SYMBOL_SIZE_WIDTH + reelsetStepX * 0.5 ) * 0.5
                    var y_offset = SYMBOL_SIZE_HEIGHT_OFFSET + (SYMBOL_SIZE_HEIGHT + reelsetStepY * (lineBeams / abs(lineBeams))) * 0.5 + getOffsetByFlipAngle(flipAngle)
                    beamNodePrev.worldPos = reelSetNodePrev.worldPos() + newVector3(x_offset, y_offset, 0) * multiplier

                    x_offset = SYMBOL_SIZE_WIDTH_OFFSET + (SYMBOL_SIZE_WIDTH + reelsetStepX * 1.5) * 0.5
                    y_offset = SYMBOL_SIZE_HEIGHT_OFFSET + (SYMBOL_SIZE_HEIGHT + reelsetStepY * 3.0 * (lineBeams / abs(lineBeams))) * 0.5 + getOffsetByFlipAngle(flipAngle)
                    beamNode.worldPos = reelSetNodePrev.worldPos() + newVector3(x_offset, y_offset, 0) * multiplier
                else:
                    raise

        frChild.enabled = false

        #-----------Animation setup-----------#
        var delayIncStep = 0.1
        let partAnimDuration = frChild.children[0].animationNamed("winline_run").loopDuration #00:30
        let totalWinLineAnimDuration = partAnimDuration + beamsQuantity.float * delayIncStep

        for ani in 0 .. < beamsQuantity:
            let element = frChild.children[ani]
            let anim = element.animationNamed("winline_run")
            anim.cancelBehavior = cbJumpToStart
            anim.addLoopProgressHandler 0.0, false, proc() =
                element.alpha = 1.0
            let markerValue = nextAnimDelay/totalWinLineAnimDuration
            let cm = newComposeMarker(markerValue,1.0,anim)
            animationsMarkers.add(cm)
            nextAnimDelay += delayIncStep
            element.addAnimation(anim)
            anim.cancel()

        let winLineAnim = newCompositAnimation(totalWinLineAnimDuration, animationsMarkers)
        winLineAnim.numberOfLoops = 1
        winLineAnim.cancelBehavior = CancelBehavior.cbJumpToStart
        #-------Animation setup finish--------#

        winLines[i] = (animComposite: winLineAnim)

    v.winlinesArray.lines = winLines

proc playWinSymbol*(v: CardSlotView, node: Node, cardIndex: int) =
    let cellComponent = node.getComponent(CellComponent)
    if not cellComponent.isNil:
        let order = node.parent.component(RenderOrder)
        order.topNode = node
        cellComponent.play(cardIndex, OnWin, lpStartToEnd) do(anim: Animation):
            cellComponent.play(cardIndex, OnIdle, lpStartToEnd)

proc playWinLine*(v: CardSlotView, pl: PaidLine, symbols: seq[seq[int]] = @[], cb: proc() = nil)=
    let r = v.winlinesArray.lines[pl.index].animComposite

    r.removeHandlers()
    let winSymbols = pl.winningLine.numberOfWinningSymbols
    for reelIndex in 0 .. < winSymbols: #0..1, 2, 3, 4
        closureScope:
            let ri = reelIndex

            r.addLoopProgressHandler(reelIndex.float * 0.08 + 0.01, false) do():
                let index = ri + v.lines[pl.index][ri] * slot_types.NUMBER_OF_REELS
                let elemIndex = v.lines[pl.index][ri]

                let reelNode = v.reelset.reels[ri].node
                let cellElementNode = reelNode.children[elemIndex]
                v.hightlights.onHighlightAnim(cellElementNode, ri, false, "playWinLine")
                v.playWinSymbol(cellElementNode, symbols[ri][2-elemIndex])
                if ri == 0:
                    case symbols[ri][2-elemIndex]
                    of 0:
                        v.sound.play("WILD_WIN")
                    of 1, 5:
                        v.sound.play("ELEMENT_FIRE")
                    of 2, 6:
                        v.sound.play("ELEMENT_WIND")
                    of 3, 7:
                        v.sound.play("ELEMENT_NATURE")
                    of 4, 8:
                        v.sound.play("ELEMENT_WATER")
                    else: discard

            r.addLoopProgressHandler(0.9, false) do():
                v.hightlights.cleanUp()

    r.addLoopProgressHandler(0.95, false) do():
        v.winlineParent.playSlotWinNumber(pl.winningLine.payout, v.lines[pl.index][2], cb)
        v.sound.play("WIN_LINE_SCORE")

    let fpChildName: string = "fireline_sequence" & $pl.index
    let fp_child = v.fireLinesGroup.findNode(fpChildName)

    fp_child.enabled = true
    v.winlineParent.addAnimation(r)

proc playHighLight*(v: CardSlotView, reelsIndices: seq[int], indices: var array[15, bool], cb: proc() = nil) = #0..1, 2, 3, 4
    if v.freespinsStage != FREESPINSNAMES[3]:
        for reelIndex in reelsIndices:
            for index in 0..2:
                let fieldIndex = reelIndex + index * slot_types.NUMBER_OF_REELS
                if indices[fieldIndex]:
                    let reelNode = v.reelset.reels[reelIndex].node
                    let cellElementNode = reelNode.children[index]
                    v.hightlights.onHighlightAnim(cellElementNode, reelIndex, true, "onReelStop")
                    indices[fieldIndex] = false