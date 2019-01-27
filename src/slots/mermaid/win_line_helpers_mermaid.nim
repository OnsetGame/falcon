import json
import tables
import math

import nimx.types
import nimx.context
import nimx.view
import nimx.animation
import nimx.formatted_text
import nimx.font

import rod.rod_types
import rod.node
import rod.component.sprite
import rod.component.solid
import rod.component.particle_system
import rod.component.text_component
import rod.viewport

import win_line_mermaid
import anim_helpers
import reelset
import sprite_digits_component

import mermaid_sound
import core.slot.base_slot_machine_view

var linepos = [
    (@[[0, 560], [1920, 560]], 2.0, 120.0),
    (@[[0, 300], [1920, 300]], 2.0, 120.0),
    (@[[0, 800], [1920, 800]], 2.0, 120.0),
    (@[[0, 300], [450, 260], [958, 900], [1466, 260], [1920, 300]], 2.4, 130.0),
    (@[[0, 800], [450, 860], [960, 200], [1466, 860], [1920, 800]], 2.1, 130.0),
    (@[[0, 560], [450, 632], [704, 111], [1212, 1000], [1466, 560], [1920, 560]], 1.9, 130.0),
    (@[[0, 560], [450, 560], [704, 900], [1212, 200], [1466, 560], [1920, 560]], 2.2, 130.0),
    (@[[0, 280], [704, 280], [1212, 840], [1920, 800]], 4.5, 125.0),
    (@[[0, 800], [780, 800], [1212, 300], [1920, 300]], 5.0, 150.0),
    (@[[0, 300], [450, 200], [704, 800], [958, 0], [1212, 800], [1466, 200], [1920, 300]], 1.6, 130.0),
    (@[[0, 800], [450, 900], [704, 200], [958, 1200], [1212, 200], [1466, 900], [1920, 800]], 1.5, 130.0),
    (@[[0, 530], [450, 600], [704, 280], [1212, 280], [1466, 600], [1920, 530]], 3.0, 130.0),
    (@[[0, 530], [450, 480], [704, 800], [1212, 800], [1466, 480], [1920, 530]], 3.0, 130.0),
    (@[[0, 300], [450, 300], [704, 560], [1212, 560], [1466, 300], [1920, 300]], 7.0, 130.0),
    (@[[0, 800], [450, 800], [704, 560], [1212, 560], [1466, 800], [1920, 800]], 7.0, 130.0),
    (@[[0, 560], [704, 560], [958, 200], [1212, 560], [1920, 560]], 2.2, 130.0),
    (@[[0, 560], [704, 560], [958, 900], [1212, 560], [1920, 560]], 2.2, 130.0),
    (@[[0, 300], [450, 150], [704, 1600], [958, -800], [1212, 1600], [1466, 150], [1920, 300]], 1.5, 130.0),
    (@[[0, 800], [450, 900], [704, -800], [958, 2340], [1212, -800], [1466, 900], [1920, 800]], 1.5, 130.0),
    (@[[0, 800], [450, 900], [704, 0], [958, 850], [1212, 0], [1466, 900], [1920, 800]], 1.6, 115.0),
    (@[[0, 300], [450, 100], [704, 1400], [958, -160], [1212, 1400], [1466, 100], [1920, 300]], 1.51, 130.0),
    (@[[0, 280], [450, 230], [704, 820], [1212, 820], [1466, 230], [1920, 280]], 3.0, 130.0),
    (@[[0, 800], [450, 800], [704, 300], [1212, 300], [1466, 800], [1920, 800]], 5.2, 130.0),
    (@[[0, 530], [520, 650], [704, -1100], [958, 2610], [1153, -250], [1466, 650], [1920, 530]], 1.5, 130.0),
    (@[[0, 530], [450, 470], [760, 1080], [975, -280], [1200, 1080], [1466, 470], [1920, 530]], 1.5, 110.0)
]

# [1,1,1,1,1], [0, 560], [1920, 560], 2.0, 120.0
# [0,0,0,0,0], [0, 300], [1920, 300], 2.0, 120.0
# [2,2,2,2,2], [0, 800], [1920, 800], 2.0, 120.0
# [0,1,2,1,0], [0, 300], [450, 260], [958, 900], [1466, 260], [1920, 300], 2.4, 130.0
# [2,1,0,1,2], [0, 800], [450, 860], [960, 200], [1466, 860], [1920, 800], 2.1, 130.0
# [1,0,1,2,1], [0, 560], [450, 632], [704, 111], [1212, 1000], [1466, 560], [1920, 560], 1.9, 130.0
# [1,2,1,0,1], [0, 560], [450, 560], [704, 900], [1212, 200], [1466, 560], [1920, 560], 2.2, 130.0
# [0,0,1,2,2], [0, 280], [704, 280], [1212, 840], [1920, 800], 4.5, 125.0
# [2,2,1,0,0], [0, 800], [780, 800], [1212, 300], [1920, 300], 5.0, 150.0
# [0,1,0,1,0], [0, 300], [450, 200], [704, 800], [958, 0], [1212, 800], [1466, 200], [1920, 300], 1.5, 130.0
# [2,1,2,1,2], [0, 800], [450, 900], [704, 200], [958, 1200], [1212, 200], [1466, 900], [1920, 800], 1.5, 130.0
# [1,0,0,0,1], [0, 530], [450, 600], [704, 280], [1212, 280], [1466, 600], [1920, 530], 3.0, 130.0
# [1,2,2,2,1], [0, 530], [450, 480], [704, 800], [1212, 800], [1466, 480], [1920, 530], 3.0, 130.0
# [0,1,1,1,0], [0, 300], [450, 300], [704, 560], [1212, 560], [1466, 300], [1920, 300], 7.0, 130.0
# [2,1,1,1,2], [0, 800], [450, 800], [704, 560], [1212, 560], [1466, 800], [1920, 800], 7.0, 130.0
# [1,1,0,1,1], [0, 560], [704, 560], [958, 200], [1212, 560], [1920, 560], 2.2, 130.0
# [1,1,2,1,1], [0, 560], [704, 560], [958, 900], [1212, 560], [1920, 560], 2.2, 130.0
# [0,2,0,2,0], [0, 300], [450, 150], [704, 1600], [958, -800], [1212, 1600], [1466, 150], [1920, 300], 1.5, 130.0
# [2,0,2,0,2], [0, 800], [450, 900], [704, -800], [958, 2340], [1212, -800], [1466, 900], [1920, 800], 1.5, 130.0
# [2,0,1,0,2], [0, 800], [450, 900], [704, 0], [958, 850], [1212, 0], [1466, 900], [1920, 800], 1.6, 115.0
# [0,2,1,2,0], [0, 300], [450, 100], [704, 1400], [958, -160], [1212, 1400], [1466, 100], [1920, 300], 2.0, 130.0
# [0,2,2,2,0], [0, 280], [450, 230], [704, 820], [1212, 820], [1466, 230], [1920, 280], 3.0, 130.0
# [2,0,0,0,2], [0, 800], [450, 800], [704, 300], [1212, 300], [1466, 800], [1920, 800], 5.2, 130.0
# [1,0,2,0,1], [0, 530], [520, 650], [704, -1100], [958, 2610], [1153, -250], [1466, 650], [1920, 530], 1.5, 130.0
# [1,2,0,2,1], [0, 530], [450, 470], [760, 1080], [975, -280], [1200, 1080], [1466, 470], [1920, 530], 1.5, 110.0

# type
#     WinLineController* = ref object

const PARENT_PATH = "slots/mermaid_slot/"

var linesCache* = initTable[int, Node]()

var canPlayLines*: bool = true

proc playLine(frontNode: Node, lnIndex: int, shift: float32 = 0.0): tuple[nd: Node, anim: Animation] =
    var lnNode = linesCache.getOrDefault(lnIndex)

    if lnNode.isNil:


        let lnCfg = linepos[lnIndex]

        lnNode = frontNode.newChild($lnIndex)
        lnNode.alpha = 0.0
        let winLine = lnNode.component(WinLineMermaid)
        for p in lnCfg[0]:

            # proc addAndGet(pos: Vector3): Node =
            #     var nd = frontNode.findNode($pos.x & $pos.y)
            #     if nd.isNil:
            #         nd = frontNode.newChild($pos.x & $pos.y)
            #         let sld = nd.component(Solid)k
            #         sld.size = newSize(30,30)
            #         nd.anchor = newVector3(15,15)
            #     nd.position = pos
            #     result = nd
            proc addAndGet(pos: Vector3): Vector3 =
                result = pos

            winLine.positions.add(addAndGet(newVector3(p[0].float32, (p[1].float32 + shift), 0.float32)))
        winLine.density = lnCfg[1]
        winLine.width = lnCfg[2]
        winLine.roundSteps = 42.0

        linesCache[lnIndex] = lnNode
    else:
        frontNode.addChild(lnNode)

    var donorNode = newNodeWithResource(PARENT_PATH & "comps/lines_comp/line.json")
    frontNode.addChild(donorNode)
    donorNode.alpha = 0.0
    lnNode.componentIfAvailable(WinLineMermaid).sprite = donorNode.findFirstSpriteComponent()
    let anim = donorNode.animationNamed("play")
    anim.onComplete do():
        donorNode.removeFromParent()
        lnNode.removeFromParent()
        anim.removeHandlers()
        # winLine.cleanup()

    anim.loopDuration = 1.0
    result.anim = anim
    result.nd = lnNode

proc createHighlightNd*(backNode, overNd: Node): Node =
    var highlightNode = newNodeWithResource(PARENT_PATH & "comps/highlight.json")
    backNode.addChild(highlightNode)
    let winNd = overNd.findNode("win")

    if not winNd.isNil:
        highlightNode.worldPos = winNd.worldPos
        result = highlightNode

# proc playPrtNode(parentNd, frontNode: Node) =
#     let prtNd = newNodeWithResource(PARENT_PATH & "comps/bubble_win_line.json")
#     let prt = prtNd.findNode("PRT_Bubble").componentIfAvailable(ParticleSystem)
#     frontNode.addChild(prtNd)
#     let winNd = parentNd.findNode("win")
#     prtNd.worldPos = winNd.worldPos
#     prt.start()
#     parentNd.sceneView.wait(0.25) do():
#         prt.stop()
#         parentNd.sceneView.wait(prt.lifetime) do():
#             prtNd.removeFromParent()

proc playLineComp*(frontNode, backNode: Node, winElems: seq[tuple[nd: Node, pr: proc(callback: proc())]], lnIndex: int, delayTime: float32, callback: proc() = nil) =
    let v = frontNode.sceneView

    template play() =
        if not canPlayLines:
            return

        # SOUND
        v.BaseMachineView.playRegularWinSound()

        let secondNd = playLine(frontNode, lnIndex, 0.0)
        let animStep = secondNd.anim.loopDuration / 9.float32
        for i, el in winElems:
            closureScope:
                let index = i

                let nd = el.nd
                let playproc = el.pr
                let prog = animStep*(index+1).float32

                secondNd.anim.addLoopProgressHandler(prog, false) do():
                    # nd.playPrtNode(frontNode)
                    let highlightNode = createHighlightNd(backNode, nd)
                    if not highlightNode.isNil:
                        let hgAnim = highlightNode.animationNamed("play")
                        hgAnim.loopDuration = hgAnim.loopDuration * 0.6
                        v.addAnimation(hgAnim)
                        hgAnim.onComplete do():
                            hgAnim.removeHandlers()
                            hgAnim.loopPattern = lpEndToStart
                            v.addAnimation(hgAnim)
                            hgAnim.onComplete do():
                                highlightNode.removeFromParent()

                    # let oldParent = nd.parent
                    # nd.reattach(frontNode)
                    if not playproc.isNil:
                        playproc do():
                            # nd.reattach(oldParent)
                            discard

        secondNd.anim.onComplete do():
            if not callback.isNil:
                callback()

        secondNd.nd.alpha = 1.0
        v.addAnimation(secondNd.anim)

        # v.wait(0.1) do():
        #     let lastNd = playLine(frontNode, lnIndex, 50.0)
        #     lastNd.nd.alpha = 1.0
        #     v.addAnimation(lastNd.anim)

    if delayTime > 0:
        v.wait(delayTime) do():
            play()
    else:
        play()


proc playLineNumber*(frontNode: Node, payout: int, winElem: tuple[nd: Node, pr: proc(callback: proc())], delayTime: float32) =
    let v = frontNode.sceneView
    let winNd = winElem.nd.findNode("win")
    if not winNd.isNil:
        let n = newNodeWithResource(PARENT_PATH & "comps/win_line_number.json")
        frontNode.addChild(n)
        n.worldPos = winNd.worldPos
        n.findNode("win_num").componentIfAvailable(SpriteDigits).value = $payout
        let anim = n.animationNamed("play")
        anim.onComplete do():
            n.removeFromParent()

        v.wait(delayTime+0.25) do():
            if not n.isNil and not n.parent.isNil:
                v.addAnimation(anim)

