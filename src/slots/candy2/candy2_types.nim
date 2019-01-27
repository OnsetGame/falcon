import nimx.animation
import rod.node
import rod.component.ae_composition
import core.slot.state_slot_machine
import node_proxy.proxy
import shared.window.button_component
import sequtils

let GENERAL_PREFIX* = "slots/candy2_slot/"
const BOX_VIEWS_COUNT = 10

type Candy2PaytableServerData* = tuple
    paytableSeq: seq[seq[int]]
    freespinsRelation: seq[tuple[triggerCount: int, freespinCount: int]]
    bonusRelation: seq[tuple[triggerCount: int, bonusCount: int]]
    bonusPossibleMultipliers: seq[float]

type ElementState* = enum
    Prepared,
    In,
    Idle,
    Out,
    Finished

type Element* = ref object
    node*: Node
    state*: ElementState

type Candy2SpinData* = tuple
    field: seq[int8]
    wildIndexes: seq[int]
    wildActivator: int

type Placeholder* = ref object
    node*: Node
    table*: Node
    element*: Element
    caramels*: seq[Node]
    motions*: seq[Node]
    colorSpins*: seq[Node]
    curCaramels*: seq[Node]
    curMotions*: seq[Node]
    curColorSpins*: seq[Node]

nodeProxy BonusProxy:
    aeComp AEComposition {onNode: node }
    move* Animation {withValue: np.aeComp.compositionNamed("move") }
    moveFrom* Animation {withKey: "move"}
    boxesDown* Node {withName: "boxes_down"}
    levelsBox* Node {withName: "levels_box"}
    boxesDownMove* Animation {withKey: "move", forNode: "boxes_down"}
    transitionNode* Node {withName: "transition_scene"}

nodeProxy Box:
    idle* Animation {withKey: "idle"}
    play* Animation {withKey: "play"}
    elementParent* Node {withName: "parent_elements"}
    button* ButtonComponent
    views* seq[Node] {withValue: toSeq(1..BOX_VIEWS_COUNT).map(proc(i: int): Node = np.node.findNode("box_view_" & $i))}
    currView* Node
