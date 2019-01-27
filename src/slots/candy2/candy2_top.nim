import node_proxy.proxy
import nimx.animation
import utils.helpers
import rod.node
import rod.component.ae_composition
import sequtils

nodeProxy Top:
    aeComp AEComposition {onNode: node }
    move* Animation {withValue: np.aeComp.compositionNamed("move") }
    moveFrom* Animation {withValue: np.aeComp.compositionNamed("move", @["boxes_up"]) }
    airplaneIdle Animation {withKey: "play", forNode: "airplane"}
    airplaneShake Animation {withKey: "shake", forNode: "airplane_top"}
    airplaneMove Animation {withKey: "move", forNode: "airplane_top"}
    boxesUpParent* Node {withName: "boxes_up_parent"}
    boxesUpNode* Node {withName: "boxes_up"}
    levelsBox* Node {withName: "levels_box"}
    boy* Node {withName: "boy"}
    boxesUp* seq[Node] {withValue: toSeq(1..4).map(proc(i: int): Node = np.node.findNode("box" & $i))}

proc createTop*(): Top =
    result = new(Top, newNodeWithResource("slots/candy2_slot/top/precomps/top"))

proc startAirplane*(top: Top)  =
    top.airplaneIdle.numberOfLoops = -1
    top.node.addAnimation(top.airplaneIdle)
