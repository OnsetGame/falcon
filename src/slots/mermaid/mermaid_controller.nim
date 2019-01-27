import random
import strutils
import tables

import nimx.matrixes
import nimx.animation
import nimx.timer

import rod.rod_types
import rod.node
import rod.component
import rod.component.sprite
import rod.component.color_balance_hls
import rod.component.mask
import rod.component.rti
import rod.viewport

import mermaid_response
import anim_helpers
import mermaid_sound
import core.slot.base_slot_machine_view

const PARENT_PATH = "slots/mermaid_slot/"


const multiWilds = [
    [posLeft, posCenterRight],
    [posLeft, posRight],
    [posCenterLeft, posRight],
    [posLeft, posCenterLeft],
    [posCenterLeft, posCenterRight],
    [posCenterRight, posRight]
]

proc inverseComp(n: Node) {.inline.} =
    if n.scaleX > 0:
        n.scaleX = -n.scaleX
    n.positionX = 1920.0

proc defaultComp(n: Node) {.inline.} =
    if n.scaleX < 0:
        n.scaleX = -n.scaleX
    n.positionX = 0.0

#--------------------------------------------------------------------------------------

type FrameType* = enum
    BigFrame
    SmallFrame
    DoubleFrame
    NoneFrame

type WildFrame* = ref object
    rootNode*: Node

    levelsNode*: Node

    frameType*: FrameType

    mermaidParentNode*: Node
    mermaidNode*: Node

proc newFrame*(fr: FrameType): Node =
    var resPath: string = PARENT_PATH & "compositions_mermaid/mermaid_frame/"
    case fr:
    of BigFrame: resPath &= "wild_frame.json"
    of SmallFrame: resPath &= "wild_small.json"
    of DoubleFrame: resPath &= "wild_x2.json"
    else: discard

    let frameNode = newNodeWithResource(resPath)
    #TODO use texture as mask
    if fr == SmallFrame:
        let alphaFrame = frameNode.findNode("Alpha_for_little_frame.png")
        alphaFrame.enabled = false

        let frame = frameNode.findNode("Frame_Background")
        let mask = frame.component(Mask)
        mask.maskNode = alphaFrame
        mask.maskType = tmAlpha

        let alphaWild = frameNode.findNode("ltp_gradient_map_13_copy_2.png")
        let wildMaskNode = frameNode.findNode("ltp_lightsweep_1.png")
        let maskWild = wildMaskNode.component(Mask)
        maskWild.maskNode = alphaWild
        maskWild.maskType = tmLuma

        let controllerNd = frameNode.findNode("Controller")
        let controllerMsk = controllerNd.addComponent(Mask)
        controllerMsk.maskNode = alphaFrame
        controllerMsk.maskType = tmAlpha

        let controllerMsk2 = controllerNd.addComponent(Mask)
        controllerMsk2.maskNode = frameNode.findNode("ltp_bottom_1.png$11")
        controllerMsk2.maskType = tmAlphaInverted

        let controllerMsk3 = controllerNd.addComponent(Mask)
        controllerMsk3.maskNode = frameNode.findNode("ltp_bottom_1.png")
        controllerMsk3.maskType = tmAlphaInverted
    elif fr == BigFrame:
        let alphaFrame = frameNode.findNode("Frame_Background_mult.png")

        let frame = frameNode.findNode("Light Rays")
        let mask = frame.component(Mask)
        mask.maskNode = alphaFrame
        mask.maskType = tmAlpha

        let alphaWild = frameNode.findNode("ltp_gradient_map_13_copy_2.png")
        let wildMaskNode = frameNode.findNode("ltp_lightsweep_1.png")
        let maskWild = wildMaskNode.component(Mask)
        maskWild.maskNode = alphaWild
        maskWild.maskType = tmLuma
    else:
        let alphaFrame1 = frameNode.findNode("wild_frame$6").findNode("Frame_Background_mult.png")
        let frame1 = frameNode.findNode("wild_frame$6").findNode("Light Rays")
        let mask1 = frame1.component(Mask)
        mask1.maskNode = alphaFrame1
        mask1.maskType = tmAlpha

        let alphaWild1 = frameNode.findNode("wild_frame$6").findNode("ltp_gradient_map_13_copy_2.png")
        let wildMaskNode1 = frameNode.findNode("wild_frame$6").findNode("ltp_lightsweep_1.png")
        let maskWild1 = wildMaskNode1.component(Mask)
        maskWild1.maskNode = alphaWild1
        maskWild1.maskType = tmLuma


        let alphaFrame2 = frameNode.findNode("wild_frame").findNode("Frame_Background_mult.png")
        let frame2 = frameNode.findNode("wild_frame").findNode("Light Rays")
        let mask2 = frame2.component(Mask)
        mask2.maskNode = alphaFrame2
        mask2.maskType = tmAlpha

        let alphaWild2 = frameNode.findNode("wild_frame").findNode("ltp_gradient_map_13_copy_2.png")
        let wildMaskNode2 = frameNode.findNode("wild_frame").findNode("ltp_lightsweep_1.png")
        let maskWild2 = wildMaskNode2.component(Mask)
        maskWild2.maskNode = alphaWild2
        maskWild2.maskType = tmLuma

    frameNode.doForAllBranch do(nd: Node):
        nd.affectsChildren = true

    result = frameNode

proc getFrameType(mpos: MermaidPosition): FrameType =
    if mpos.horizontal == posMiss or mpos.horizontal == posStand:
        return NoneFrame
    else:
        if mpos.vertical == posCenter:
            return BigFrame

        return SmallFrame

proc setFramePos(wf: WildFrame, pos: MermaidPosition) =
    var x: float32 = 0.0
    var y: float32 = 0.0

    if wf.frameType == SmallFrame:
        if pos.vertical == posUp:
            y = -80.0
        if pos.vertical == posDown:
            y = 160.0
        if pos.vertical == posCenter:
            raiseAssert("small frame in center")
    if wf.frameType == BigFrame:
        y = -60.0

    if pos.horizontal == posLeft:
        x = -250.0
    if pos.horizontal == posCenterLeft:
        x = -10.0
    if pos.horizontal == posCenterRight:
        x = 250.0
    if pos.horizontal == posRight:
        x = 520.0

    wf.rootNode.position = newVector3(x, y, 0)

proc setFramePos(wf: WildFrame, pos: seq[MermaidPosition]) =
    var x: float32 = 0.0
    var y: float32 = -60.0

    let minPos = min(pos[0].horizontal.int, pos[1].horizontal.int)

    # posLeft = 0
    # posCenterLeft
    # posCenterRight
    # posRight
    # posMiss
    # posStand

    case minPos:
    of 0: x = -250.0
    of 1: x = 20.0
    of 2: x = 250.0
    else: x = 0.0

    wf.rootNode.position = newVector3(x, y, 0)

proc newWildFrame*(mpos: MermaidPosition): WildFrame =
    result.new()
    result.frameType = getFrameType(mpos)
    result.rootNode = newFrame(result.frameType)
    if result.frameType == SmallFrame:
        result.levelsNode = result.rootNode.findNode("levels_effect")
    else:
        result.levelsNode = result.rootNode.findNode("levels_effect")
    result.setFramePos(mpos)

proc newMultiWildFrame*(mpos: seq[MermaidPosition]): WildFrame =
    result.new()
    result.frameType = DoubleFrame
    result.rootNode = newFrame(result.frameType)
    result.levelsNode = result.rootNode.findNode("levels_effect")
    result.setFramePos(mpos)

proc play*(wf: WildFrame, callback: proc() = nil) =
    wf.rootNode.animateRecursively("in", "play")
    let inAnim = wf.rootNode.animationNamed("in")

    # SOUND
    wf.rootNode.sceneView.BaseMachineView.playMermaidFrame()

    inAnim.onComplete do():
        wf.rootNode.animateRecursively("idle", "play")
    # wf.rootNode.sceneView.wait(inAnim.loopDuration/2.0) do():
        if not callback.isNil:
            callback()

proc stop*(wf: WildFrame, callback: proc() = nil) =
    if not wf.mermaidNode.isNil and not wf.mermaidParentNode.isNil:
        wf.mermaidNode.reattach(wf.mermaidParentNode)

    let outAnim = wf.rootNode.animationNamed("out")
    wf.rootNode.animateRecursively("out", "play")
    wf.rootNode.sceneView.wait(outAnim.loopDuration/2.0) do():
        if not callback.isNil:
            callback()

#--------------------------------------------------------------------------------------

type AnimType* = enum
    NotInit
    SimpleIdle
    SwimAnim
    SwimIdle
    SwimOut
    SwimIn
    SwimMiss
    SwimCircle
    SwimSwirl
    Jump
    Kiss
    Look

type MermaidAnimation* = tuple
    node: Node
    anim: Animation

type Mermaid* = ref object
    rootNode*: Node
    swimAnchorNode*: Node

    mInversed: bool

    currAnimType*: AnimType
    anims*: Table[AnimType, MermaidAnimation]

proc stopAndHideAll(mc: Mermaid) =
    for k, v in mc.anims:
        v.anim.cancel()
        v.node.hide(0)

proc newMermaid*(): Mermaid =
    result.new()
    result.rootNode = newNode("mermaid")
    result.currAnimType = NotInit
    result.mInversed = false

    let idleNode = newNodeWithResource(PARENT_PATH & "compositions_mermaid/mermaid_idle.json")
    let swimNode = newNodeWithResource(PARENT_PATH & "compositions_mermaid/mermaid_swim.json")
    let swimInNode = newNodeWithResource(PARENT_PATH & "compositions_mermaid/mermaind_in.json")
    let swimMissNode = newNodeWithResource(PARENT_PATH & "compositions_mermaid/mermaid_left_to_right.json")
    let swimCircleNode = newNodeWithResource(PARENT_PATH & "compositions_mermaid/circle.json")
    let swimSwirlNode = newNodeWithResource(PARENT_PATH & "compositions_mermaid/swirl.json")
    let jumpNode = newNodeWithResource(PARENT_PATH & "compositions_mermaid/wait_and_jump.json")
    let lookNode = newNodeWithResource(PARENT_PATH & "compositions_mermaid/look_at_me.json")

    result.swimAnchorNode = swimNode.findNode("anchor_parent")

    result.rootNode.addChild(idleNode)
    result.rootNode.addChild(swimNode)
    result.rootNode.addChild(swimInNode)
    result.rootNode.addChild(swimMissNode)
    result.rootNode.addChild(swimCircleNode)
    result.rootNode.addChild(swimSwirlNode)
    result.rootNode.addChild(jumpNode)
    result.rootNode.addChild(lookNode)

    result.anims = initTable[AnimType, MermaidAnimation]()

    result.anims[SimpleIdle] = (idleNode, idleNode.animationNamed("play"))
    result.anims[SwimAnim]   = (swimNode.findNode("anchor"), swimNode.animationNamed("in"))
    result.anims[SwimIdle]   = (swimNode.findNode("Marmeid_idle_front_B_[0001-0048].png"), swimNode.animationNamed("idle"))
    result.anims[Kiss]       = (swimNode.findNode("Marmeid_kiss_[00-20].png"), swimNode.animationNamed("kiss"))
    result.anims[SwimOut]    = (swimNode.findNode("anchor_out_parent"), swimNode.animationNamed("out"))
    result.anims[SwimIn]     = (swimInNode, swimInNode.animationNamed("play"))
    result.anims[SwimMiss]   = (swimMissNode, swimMissNode.animationNamed("play"))
    result.anims[SwimCircle] = (swimCircleNode, swimCircleNode.animationNamed("play"))
    result.anims[SwimSwirl]  = (swimSwirlNode, swimSwirlNode.animationNamed("play"))
    result.anims[Jump]       = (jumpNode, jumpNode.animationNamed("play"))
    result.anims[Look]       = (lookNode, lookNode.animationNamed("play"))

    result.stopAndHideAll()

proc standartPlay(mc: Mermaid, currAnimNode: tuple[node: Node, anim: Animation], callback: proc() = nil) =
    if mc.currAnimType != NotInit:
        let prevAnimNode = mc.anims.getOrDefault(mc.currAnimType)
        prevAnimNode.anim.removeHandlers()
        prevAnimNode.node.hide(0)
        prevAnimNode.anim.cancel()

    currAnimNode.node.show(0)
    currAnimNode.anim.onProgress(0.0)
    currAnimNode.node.addAnimation(currAnimNode.anim)
    if not callback.isNil:
        currAnimNode.anim.onComplete do():
            currAnimNode.anim.removeHandlers()
            callback()

proc `inversed=`*(mc: Mermaid, inv: bool) =
    if inv:
        mc.rootNode.inverseComp()
    else:
        mc.rootNode.defaultComp()

    mc.mInversed = inv

proc inversed*(mc: Mermaid): bool = mc.mInversed

proc isOnRight*(mc: Mermaid): bool = (mc.mInversed == false)

proc setRight*(mc: Mermaid) = mc.mInversed = false

proc setLeft*(mc: Mermaid) = mc.mInversed = true

proc play*(mc: Mermaid, animType: AnimType, callback: proc() = nil, playproc: proc() = nil) =
    let currAnimNode = mc.anims.getOrDefault(animType)
    if currAnimNode.node.isNil:
        raiseAssert("node not found for anim type: " & $animType)

    if playproc.isNil:
        mc.standartPlay(currAnimNode, callback)
    else:
        playproc()

    mc.currAnimType = animType

proc moveTo(n: Node, destPos: Vector3, moveTime: float32) =
    var anim = newAnimation()
    anim.loopDuration = moveTime
    anim.numberOfLoops = 1
    anim.onAnimate = proc(p: float) =
        n.position = interpolate(newVector3(1034.0, 432.0, 0.0), destPos, p)
    n.addAnimation(anim)
    anim.onComplete do():
        anim.removeHandlers()
        anim = nil

proc getHorisontalPos(mc: Mermaid, mhp: MermaidHorizontalPosition): float32 =
    if not mc.inversed:
        case mhp:
        of posLeft:
            return 720.0
        of posCenterLeft:
            return 990.0
        of posCenterRight:
            return 1250.0
        of posRight:
            return 1490.0
        else:
            return 1034.0
    else:
        case mhp:
        of posLeft:
            return 1490.0
        of posCenterLeft:
            return 1250.0
        of posCenterRight:
            return 990.0
        of posRight:
            return 720.0
        else:
            return 1034.0

proc getVerticalPos(mc: Mermaid, mvp: MermaidVerticalPosition): float32 =
    case mvp:
    of posCenter:
        return 420.0
    of posUp:
        return 420.0
    of posDown:
        return 640.0
    else:
        return 432.0

proc getPos(mc: Mermaid, mp: MermaidPosition): Vector3 =
    return newVector3(mc.getHorisontalPos(mp.horizontal), mc.getVerticalPos(mp.vertical), 0.0)

proc getMermaidAnimDuration(mc: Mermaid, mpos: MermaidPosition): float32 =
    result = 0.0
    if mc.currAnimType == SwimIdle or mc.currAnimType == Kiss:
        result += mc.anims[SwimOut].anim.loopDuration + mc.anims[SwimIn].anim.loopDuration
    # else:
    case mpos.horizontal:
    of posLeft, posCenterLeft, posCenterRight, posRight:
        result += mc.anims[SwimAnim].anim.loopDuration + mc.anims[Kiss].anim.loopDuration
    of posMiss:
        result += mc.anims[SwimMiss].anim.loopDuration
    of posStand:
        discard
    else:
        discard

proc playMermaid(mc: Mermaid, mpos: MermaidPosition, destPos: Vector3, callback: proc() = nil) =
    let v = mc.rootNode.sceneView

    case mpos.horizontal:
    of posLeft, posCenterLeft, posCenterRight, posRight:
        # # SOUND
        v.BaseMachineView.playMermaidSwim()

        mc.swimAnchorNode.moveTo(destPos, mc.anims[SwimAnim].anim.loopDuration)
        mc.play(SwimAnim) do():
            mc.play(SwimIdle)
            v.wait(0.5) do():
                # SOUND
                v.BaseMachineView.playWildWin()

                mc.play(Kiss) do():
                    mc.play(SwimIdle)
        v.wait(mc.anims[SwimAnim].anim.loopDuration*0.5) do():
            if not callback.isNil: callback()
    of posMiss:
        # # SOUND
        v.BaseMachineView.playMermaidSwim()

        mc.play(SwimMiss) do():
            mc.anims[SwimMiss].anim.onProgress(0.0)
            mc.inversed = not mc.inversed
            mc.play(SimpleIdle)

        v.wait(mc.anims[SwimMiss].anim.loopDuration*0.5) do():
            if not callback.isNil: callback()
    of posStand:
        if not callback.isNil: callback()
    else:
        if not callback.isNil: callback()

proc play*(mc: Mermaid, mpos: MermaidPosition, destPos: Vector3, callback: proc() = nil) =

    if mc.currAnimType == SwimIdle or mc.currAnimType == Kiss:
        let v = mc.rootNode.sceneView

        mc.play(SwimOut) do():
            mc.inversed = not mc.inversed
            mc.play(SwimIn) do():
                # SOUND
                v.BaseMachineView.playWildAppear()
                mc.play(SimpleIdle)
                playMermaid(mc, mpos, destPos, callback)
    else:
        playMermaid(mc, mpos, destPos, callback)

proc play*(mc: Mermaid, mpos: MermaidPosition, callback: proc() = nil) =
    if mc.currAnimType == SwimIdle or mc.currAnimType == Kiss:
        # SOUND
        let v = mc.rootNode.sceneView
        # v.BaseMachineView.playWildWin()

        mc.play(SwimOut) do():
            mc.inversed = not mc.inversed
            mc.play(SwimIn) do():
                # SOUND
                v.BaseMachineView.playWildAppear()
                mc.play(SimpleIdle)
                playMermaid(mc, mpos, mc.getPos(mpos), callback)
    else:
        playMermaid(mc, mpos, mc.getPos(mpos), callback)

#--------------------------------------------------------------------------------------

type MermaidController* = ref object
    rootNode*: Node
    frameNode*: Node
    foregroundNode*: Node

    standartMermaid*: Mermaid
    freespinMermaid*: Mermaid

    prevMpos*: seq[MermaidPosition]
    currMpos*: seq[MermaidPosition]

    bCanPlayMermaidAnticipation*: bool

proc newMermaidController*(parent: Node): MermaidController =
    result.new()
    result.rootNode = newNode("mermaid_controller")

    parent.addChild(result.rootNode)

    result.frameNode = newNode("frame")
    result.rootNode.addChild(result.frameNode)

    result.standartMermaid = newMermaid()
    result.standartMermaid.rootNode.name = "standart_mermaid"
    result.freespinMermaid = newMermaid()
    result.freespinMermaid.rootNode.name = "freespin_mermaid"

    result.foregroundNode = parent.findNode("foreground")

    result.rootNode.addChild(result.standartMermaid.rootNode)
    result.rootNode.addChild(result.freespinMermaid.rootNode)

    result.prevMpos = @[]
    result.currMpos = @[]


    let colorbal = result.freespinMermaid.rootNode.component(ColorBalanceHLS)
    colorbal.hue = 0.25
    # colorbal.lightness = -0.05
    colorbal.hlsMin = 0.58
    colorbal.hlsMax = 0.77


proc isWildIntersect(mpos: seq[MermaidPosition]): bool =
    if mpos.len > 1:
        if mpos[0].horizontal == posMiss or mpos[1].horizontal == posMiss:
            return false
        if mpos[0].horizontal == posStand or mpos[1].horizontal == posStand:
            return false
        if abs(mpos[0].horizontal.int - mpos[1].horizontal.int) == 1:
            return true
    return false

# proc playFrame(wf: WildFrame, callback: proc(wf: WildFrame) = nil, onReattach: proc(parent, child: var Node)) =
proc playFrame(wf: WildFrame, onReattach: proc(parent, child: var Node)) =
    # if wf.frameType == SmallFrame:

    #     wf.play do():
    #         # if not callback.isNil:
    #             # wf.callback()
    #         discard
    #     var anim = newAnimation()
    #     anim.numberOfLoops = -1
    #     wf.rootNode.addAnimation(anim)
    #     var wasReattach: bool = false
    #     var checkForReattach: bool = false
    #     var parent: Node
    #     var child: Node
    #     anim.chainOnAnimate do(p: float):
    #         if wf.levelsNode.getGlobalAlpha() > 0.01 and not wasReattach:
    #             wasReattach = true
    #             checkForReattach = true
    #             onReattach(parent, child)
    #         if checkForReattach and wf.levelsNode.getGlobalAlpha() < 1.0:
    #             anim.cancel()
    #             if not child.isNil and not parent.isNil:
    #                 child.reparentTo(parent)
    # else:
    #     wf.play do():
    #         discard
    #     var parent: Node
    #     var child: Node
    #     onReattach(parent, child)
        wf.play()
        var parent: Node
        var child: Node
        onReattach(parent, child)

# proc playMultyFrame(wf: WildFrame, callback: proc(wf: WildFrame) = nil, onReattach: proc(parent0, parent1, child0, child1: var Node)) =
proc playMultyFrame(wf: WildFrame, onReattach: proc(parent0, parent1, child0, child1: var Node)) =
    wf.play()
    var parent0, parent1, child0, child1: Node
    onReattach(parent0, parent1, child0, child1)
    # var anim = newAnimation()
    # anim.numberOfLoops = -1
    # wf.rootNode.addAnimation(anim)
    # var wasReattach: bool = false
    # var checkForReattach: bool = false
    # var parent0, parent1, child0, child1: Node
    # anim.chainOnAnimate do(p: float):
    #     if wf.levelsNode.getGlobalAlpha() > 0.01 and not wasReattach:
    #         wasReattach = true
    #         checkForReattach = true
    #         onReattach(parent0, parent1, child0, child1)
    #     if checkForReattach and wf.levelsNode.getGlobalAlpha() < 1.0:
    #         anim.cancel()
    #         if not child0.isNil and not parent0.isNil:
    #             child0.reparentTo(parent0)
    #         if not child1.isNil and not parent1.isNil:
    #             child1.reparentTo(parent1)


proc playNotStand*(mc: MermaidController, antype: AnimType): float32 {.discardable.} =
    if mc.currMpos.len == 1:
        if not mc.currMpos[0].hasWon():
            mc.standartMermaid.play(antype) do():
                mc.standartMermaid.play(SimpleIdle)
            result = mc.standartMermaid.anims[antype].anim.loopDuration*0.5
        else:
            result = 0.0
    elif mc.currMpos.len == 2:
        if not mc.currMpos[0].hasWon():
            mc.standartMermaid.play(antype) do():
                mc.standartMermaid.play(SimpleIdle)
            result = mc.standartMermaid.anims[antype].anim.loopDuration*0.5
        else:
            result = 0.0
        if not mc.currMpos[1].hasWon():
            mc.freespinMermaid.play(antype) do():
                mc.freespinMermaid.play(SimpleIdle)
            result = mc.freespinMermaid.anims[antype].anim.loopDuration*0.5
        else:
            result = 0.0
    else:
        result = 0.0

proc playWF(mc: MermaidController, m: Mermaid, ps: MermaidPosition, onWildFrameCreated: proc(wf: WildFrame)) =
    let wf = newWildFrame(ps)
    onWildFrameCreated(wf)
    mc.frameNode.addChild(wf.rootNode)
    wf.playFrame do(parent, child: var Node):
        if parent.isNil: parent = m.rootNode
        if child.isNil: child = m.rootNode.children[0]
        # if not wf.levelsNode.isNil:
        #     child.reparentTo(wf.levelsNode)

        mc.rootNode.sceneView.wait(0.25) do():
            let msk0 = m.rootNode.addComponent(Mask)
            msk0.maskNode = wf.rootNode.findNode("ltp_bottom_1.png$11")
            if msk0.maskNode.isNil:
                msk0.maskNode = wf.rootNode.findNode("ltp_bottom.png$13")
            msk0.maskType = tmAlphaInverted

            let msk1 = m.rootNode.addComponent(Mask)
            msk1.maskNode = wf.rootNode.findNode("ltp_bottom_1.png")
            if msk1.maskNode.isNil:
                msk1.maskNode = wf.rootNode.findNode("ltp_bottom.png")
            msk1.maskType = tmAlphaInverted

            let msk2 = m.rootNode.addComponent(Mask)
            msk2.maskNode = wf.rootNode.findNode("Alpha_for_little_frame.png")
            msk2.maskType = tmAlpha
            if msk2.maskNode.isNil:
                msk2.maskNode = wf.rootNode.findNode("ltp_middl.png")
                msk2.maskType = tmAlphaInverted

proc play*(mc: MermaidController, mpos: seq[MermaidPosition], onWildFrameCreated: proc(wf: WildFrame)): float32 {.discardable.} =
    let v = mc.rootNode.sceneView
    mc.bCanPlayMermaidAnticipation = false

    proc playMultyWF(m0, m1: Mermaid, ps: seq[MermaidPosition]) =
        let wf = newMultiWildFrame(ps)
        wf.onWildFrameCreated()
        mc.frameNode.addChild(wf.rootNode)
        wf.playMultyFrame do(parent0, parent1, child0, child1: var Node):
            if parent0.isNil: parent0 = m0.rootNode
            if parent1.isNil: parent1 = m1.rootNode
            if child0.isNil: child0 = m0.rootNode.children[0]
            if child1.isNil: child1 = m1.rootNode.children[0]
            # child0.reparentTo(wf.levelsNode)
            # child1.reparentTo(wf.levelsNode)


            v.wait(0.25) do():
                let leftFrame = wf.rootNode.findNode("wild_frame$6")
                let leftBottomMsk = leftFrame.findNode("ltp_bottom.png$13")

                let rightFrame = wf.rootNode.findNode("wild_frame")
                let rightBottomMsk = rightFrame.findNode("ltp_bottom.png")

                let mask0 = m0.rootNode.addComponent(Mask)
                mask0.maskNode = leftBottomMsk
                mask0.maskType = tmAlphaInverted

                let mask1 = m0.rootNode.addComponent(Mask)
                mask1.maskNode = rightBottomMsk
                mask1.maskType = tmAlphaInverted

                let mask2 = m1.rootNode.addComponent(Mask)
                mask2.maskNode = leftBottomMsk
                mask2.maskType = tmAlphaInverted

                let mask3 = m1.rootNode.addComponent(Mask)
                mask3.maskNode = rightBottomMsk
                mask3.maskType = tmAlphaInverted


    proc playMermaidInFrame() =
        proc getWaitFor(m: Mermaid): float32 =
            result = 0.0
            if m.currAnimType == SwimIdle or m.currAnimType == Kiss:
                result += m.anims[SwimOut].anim.loopDuration + m.anims[SwimIn].anim.loopDuration

        let standartMermaidWait = getWaitFor(mc.standartMermaid)
        let freespinMermaidWait = getWaitFor(mc.freespinMermaid)

        if not isWildIntersect(mpos):
            var parentNode: Node
            var childNode: Node
            if mc.currMpos[0].horizontal == posMiss and mc.currMpos[1].horizontal == posMiss:
                childNode = rand([mc.standartMermaid.rootNode, mc.freespinMermaid.rootNode])
                parentNode = mc.rootNode
                childNode.reparentTo(mc.foregroundNode)


            template playStandart() =
                mc.standartMermaid.play(mc.currMpos[0]) do():
                    if getFrameType(mc.currMpos[0]) != NoneFrame:
                        mc.playWF(mc.standartMermaid, mc.currMpos[0], onWildFrameCreated)
                    else:
                        onWildFrameCreated(nil)

            # if mc.currMpos[1].hasWon():
            #     v.wait(freespinMermaidWait) do():
            #         playStandart()
            # else:
            #     playStandart()
            playStandart()


            template playFreespin() =
                mc.freespinMermaid.play(mc.currMpos[1]) do():
                    if getFrameType(mc.currMpos[1]) != NoneFrame:
                        mc.playWF(mc.freespinMermaid, mc.currMpos[1], onWildFrameCreated)
                    else:
                        onWildFrameCreated(nil)

            # if mc.currMpos[0].hasWon():
            #     v.wait(standartMermaidWait) do():
            #         playFreespin()
            # else:
            #     playFreespin()
            playFreespin()


            if not childNode.isNil:
                # v.wait(mc.standartMermaid.anims[SwimMiss].anim.loopDuration + max(freespinMermaidWait, standartMermaidWait)) do():
                v.wait(mc.standartMermaid.anims[SwimMiss].anim.loopDuration) do():
                    mc.frameNode.reparentTo(mc.rootNode)

                    mc.standartMermaid.rootNode.reparentTo(parentNode)
                    mc.freespinMermaid.rootNode.reparentTo(parentNode)

                    childNode.reparentTo(parentNode)

        else:

            # set shift in multi wild frame

            proc getFuturePos(mc: Mermaid, mpos: MermaidPosition, isStandart: bool): Vector3 =
                if mc.currAnimType == SwimIdle or mc.currAnimType == Kiss:
                    let oldInv = mc.inversed
                    mc.inversed = not mc.inversed
                    result = mc.getPos(mpos)
                    if isStandart: result.x = result.x + ( if not mc.inversed: -100.0 else: 100.0 )
                    else: result.x = result.x + ( if not mc.inversed: 100.0 else: -100.0 )
                    mc.inversed = oldInv
                else:
                    result = mc.getPos(mpos)
                    if isStandart: result.x = result.x + ( if not mc.inversed: -100.0 else: 100.0 )
                    else: result.x = result.x + ( if not mc.inversed: 100.0 else: -100.0 )

            var destPosStandart = mc.standartMermaid.getFuturePos(mc.currMpos[0], true)
            var destPosFreespin = mc.freespinMermaid.getFuturePos(mc.currMpos[1], false)

            # destPosStandart.x = destPosStandart.x + ( if not mc.standartMermaid.inversed: -100.0 else: 100.0 )
            # destPosFreespin.x = destPosFreespin.x + ( if not mc.freespinMermaid.inversed: 100.0 else: -100.0 )

            v.wait(freespinMermaidWait) do():
                mc.standartMermaid.play(mc.currMpos[0], destPosStandart)

            v.wait(standartMermaidWait) do():
                mc.freespinMermaid.play(mc.currMpos[1], destPosFreespin) do():
                    playMultyWF(mc.standartMermaid, mc.freespinMermaid, mc.currMpos)

    template getNotStandAnimType(mp: MermaidPosition): AnimType =
        if mp.horizontal == posStand:
            rand([Look, SwimSwirl, NotInit])
        else:
            NotInit

    proc playNotStand(m: Mermaid, at: AnimType) =
        m.play(at) do():
            mc.bCanPlayMermaidAnticipation = true
            m.play(SimpleIdle)

    if mc.currMpos.len == 1:
        result += getMermaidAnimDuration(mc.standartMermaid, mc.currMpos[0])

        let notStandAnim = getNotStandAnimType(mc.currMpos[0])
        if notStandAnim != NotInit:
            result += mc.standartMermaid.anims[notStandAnim].anim.loopDuration

        mc.standartMermaid.play(mc.currMpos[0]) do():
            if getFrameType(mc.currMpos[0]) != NoneFrame:
                mc.playWF(mc.standartMermaid, mc.currMpos[0], onWildFrameCreated)
            else:
                onWildFrameCreated(nil)

                # TODO hacky hack
                let waitDuration = if (mc.currMpos[0].horizontal != posStand): 1.25 else: 0.5
                v.wait(waitDuration) do():
                    if notStandAnim == NotInit:
                        mc.bCanPlayMermaidAnticipation = true

            if notStandAnim != NotInit:
                mc.standartMermaid.playNotStand(notStandAnim)


        if mc.prevMpos.len == 2:
            if mc.prevMpos[1].horizontal != posMiss and mc.prevMpos[1].horizontal != posStand:
                mc.freespinMermaid.play(SwimOut) do():
                    mc.freespinMermaid.rootNode.hide(0.5)
            else:
                mc.freespinMermaid.rootNode.hide(0.5)

    elif mc.currMpos.len == 2:
        let standartMermaidDuration = getMermaidAnimDuration(mc.standartMermaid, mc.currMpos[0])
        let freespinMermaidDuration = getMermaidAnimDuration(mc.freespinMermaid, mc.currMpos[1])

        result += max(standartMermaidDuration, freespinMermaidDuration)

        # var standartNotStandDuration = 0.0
        # let standartMermaidNotStandAnim = getNotStandAnimType(mc.currMpos[0])
        # if standartMermaidNotStandAnim != NotInit:
        #     mc.standartMermaid.playNotStand(standartMermaidNotStandAnim)
        #     standartNotStandDuration = mc.standartMermaid.anims[standartMermaidNotStandAnim].anim.loopDuration

        # var freespinNotStandDuration = 0.0
        # let freespinMermaidNotStandAnim = getNotStandAnimType(mc.currMpos[0])
        # if freespinMermaidNotStandAnim != NotInit:
        #     mc.freespinMermaid.playNotStand(freespinMermaidNotStandAnim)
        #     freespinNotStandDuration = mc.freespinMermaid.anims[freespinMermaidNotStandAnim].anim.loopDuration

        # result += max(standartNotStandDuration, freespinNotStandDuration)

        if mc.prevMpos.len <= 1:
            result += mc.standartMermaid.anims[SwimIn].anim.loopDuration
            mc.freespinMermaid.inversed = not mc.standartMermaid.inversed
            mc.freespinMermaid.rootNode.show(0)

            mc.freespinMermaid.play(SwimIn) do():
                playMermaidInFrame()

            proc checkMermaid(mc: Mermaid) =
                if mc.currAnimType == SwimIdle or mc.currAnimType == Kiss:
                    mc.play(SwimOut) do():
                        mc.play(SwimIn) do():
                            #SOUND
                            v.BaseMachineView.playWildAppear()
                            mc.play(SimpleIdle)

            mc.standartMermaid.checkMermaid()
        else:
            playMermaidInFrame()
    else:
        # raiseAssert("mermaid position err: " & $mpos)
        discard
