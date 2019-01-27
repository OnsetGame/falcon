import nimx.animation

import rod / [ node ]
import rod.component / [ ae_composition ]

import utils.helpers
import node_proxy.proxy

nodeProxy BackgroundChest:
    aeComp AEComposition {onNode: node}
    bgParticlesAnchor* Node {withName: "bg_particles"}:
        positionX = -960
        positionY = 0
    chestParticlesAnchor* Node {withName: "inside_glow"}
    fgParticlesAnchor* Node {withName: "fg_particles"}:
        positionX = -960
        positionY = 0
    sceneIdleAnim* Animation {withValue: np.aeComp.compositionNamed("scene_idle")}:
        numberOfLoops = -1
        cancelBehavior = cbJumpToEnd
    beginBGBonusAnim* Animation {withValue: np.aeComp.compositionNamed("begin_bg_bonus")}
    cardIdleBeginAnim* Animation {withValue: np.aeComp.compositionNamed("card_idle_begin")}:
        numberOfLoops = -1
    cardIdleEndAnim* Animation {withValue: np.aeComp.compositionNamed("card_idle_end")}
    beginElIdleAnim* Animation {withValue: np.aeComp.compositionNamed("begin_el_idle")}:
        numberOfLoops = -1    
    endBGBonusAnim* Animation {withValue: np.aeComp.compositionNamed("end_bg_bonus")}

nodeProxy BackgroundPortals:
    aeComp AEComposition {onNode: node}
    beginBGBonusAnim* Animation {withValue: np.aeComp.compositionNamed("begin_bg_bonus")}
    cardIdleBeginAnim* Animation {withValue: np.aeComp.compositionNamed("card_idle_begin")}:
        numberOfLoops = -1
    cardIdleEndAnim* Animation {withValue: np.aeComp.compositionNamed("card_idle_end")}
    beginElIdleAnim* Animation {withValue: np.aeComp.compositionNamed("begin_el_idle")}:
        numberOfLoops = -1
    endBGBonusAnim* Animation {withValue: np.aeComp.compositionNamed("end_bg_bonus")}

proc startBackgroundParticles*(bg: BackgroundChest) =
    let blueRight = newNodeWithResource("slots/card_slot/particles/bg_blue_prtcl1")
    bg.bgParticlesAnchor.addChild(blueRight)

    let blueLeft = newNodeWithResource("slots/card_slot/particles/bg_blue_prtcl2")
    bg.bgParticlesAnchor.addChild(blueLeft)

    let white = newNodeWithResource("slots/card_slot/particles/bg_white_prtcl")
    bg.bgParticlesAnchor.addChild(white)

    let yellow = newNodeWithResource("slots/card_slot/particles/bg_yellow_prtcl")
    bg.chestParticlesAnchor.addChild(yellow)

    let blueFG = newNodeWithResource("slots/card_slot/particles/fg_blue_prtcl")
    bg.fgParticlesAnchor.addChild(blueFG)

proc newBackgroundChest*(path: string, parent: Node): BackgroundChest =
    result = new(BackgroundChest, newLocalizedNodeWithResource(path))
    parent.addChild(result.node)

proc newBackgroundPortals*(path: string, parent: Node, index: int): BackgroundPortals =
    echo "newBackgroundPortals: ", path
    result = new(BackgroundPortals, newLocalizedNodeWithResource(path))
    parent.insertChild(result.node, index)

proc turnParticlesOff*(bg: BackgroundChest) =
    for i in bg.bgParticlesAnchor.children:
        i.enabled = false
    bg.chestParticlesAnchor.children[0].enabled = false
    bg.fgParticlesAnchor.children[0].enabled = false

proc turnParticlesOn*(bg: BackgroundChest) =
    for i in bg.bgParticlesAnchor.children:
        i.enabled = true
    bg.chestParticlesAnchor.children[0].enabled = true
    bg.fgParticlesAnchor.children[0].enabled = true