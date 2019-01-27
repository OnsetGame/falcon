import rod / [ node, component ]
import rod / component / [ ae_composition, tint ]
import nimx / [ animation, matrixes, types ]
import node_proxy.proxy
import core.components.bitmap_text
import shared.game_scene
import utils.helpers
import strformat
import tables

const PREFIX = "slots/candy2_slot/numbers/precomps/"

let positions = @[
    newVector3(960.0, 282.0),
    newVector3(960.0, 502.0),
    newVector3(960.0, 715.0)
]

nodeProxy SlotWinNumber:
    aeComp AEComposition {onNode: node}
    playAnim* Animation {withValue: np.aeComp.compositionNamed("play")}
    numbersNode Node {withName: "win_numbers"}
    numbers BmFont {onNodeAdd: numbersNode}

nodeProxy BonusWinNumber:
    aeComp AEComposition {onNode: node}
    # playOopsAnim* Animation {withValue: np.aeComp.compositionNamed("play", @["win_numbers"])}
    startAnim* Animation {withValue: np.aeComp.compositionNamed("start")}
    endAnim* Animation {withValue: np.aeComp.compositionNamed("end")}
    numbersNode Node {withName: "win_numbers_Y"}
    oopsNode Node {withName: "win_oops"}
    dropsNode Node {withName: "drops_line_numbers"}
    numbers BmFont {onNodeAdd: numbersNode}

proc playSlotWinNumber*(parent: Node, amount: int64, index: int): Animation =
    let r = new(SlotWinNumber, newNodeWithResource(PREFIX & "slot_win_number"))
    let off = r.numbersNode.children[1].position - r.numbersNode.children[0].position
    r.numbers.setup(off, "0123456789x.", r.numbersNode.children[0].children)
    r.numbers.text = $amount
    r.numbers.halignment = haCenter
    r.numbersNode.removeAllChildren()
    r.node.position = positions[clamp(index, 0, positions.high)]
    parent.addChild(r.node)

    result = r.playAnim

    r.playAnim.onComplete do():
        r.node.removeFromParent()

    r.node.addAnimation(r.playAnim)

proc playBonusPotentialWinNumber*(parent: Node, amount: float) =
    let r = new(BonusWinNumber, newNodeWithResource(&"{PREFIX}bonus_win_number"))
    let off = r.numbersNode.children[1].position - r.numbersNode.children[0].position

    var tintEffect: Tint = Tint.new()
    tintEffect.white = newColor(1.0, 1.0, 1.0, 1.0)
    tintEffect.black = newColor(0.0, 0.0, 0.0, 1.0)
    tintEffect.amount = 1.0

    r.numbers.setup(off, "0123456789x.", r.numbersNode.children[0].children)
    for i, k in r.numbers.charset:
        k.setComponent("Tint", tintEffect)   

    let amount_decimal = toInt(amount)
    let amount_fractured = amount - toFloat(amount_decimal)

    if amount_fractured != 0.0:
        r.numbers.text = "x" & $amount
    else:
        r.numbers.text = "x" & $amount_decimal

    r.numbers.halignment = haCenter
    r.numbersNode.alpha = 1.0
    r.numbersNode.position = newVector3(260.74, 387.73)
    r.numbersNode.anchor = newVector3()
    r.numbersNode.scale = newVector3(0.8, 0.8)

    parent.addChild(r.numbersNode)

proc playBonusWinNumber*(parent: Node, amount: float) =
    let r = new(BonusWinNumber, newNodeWithResource(PREFIX & "bonus_win_number"))
    let off = r.numbersNode.children[1].position - r.numbersNode.children[0].position

    r.node.position = newVector3(270, 375)
    r.numbers.setup(off, "0123456789x.", r.numbersNode.children[0].children)

    let amount_decimal = toInt(amount)
    let amount_fractured = amount - toFloat(amount_decimal)

    if amount_fractured != 0.0:
        r.numbers.text = "x" & $amount
    else:
        r.numbers.text = "x" & $amount_decimal

    r.numbers.halignment = haCenter
    r.numbersNode.removeAllChildren()
    parent.addChild(r.node)
    r.oopsNode.removeFromParent()
    r.startAnim.onComplete do():
        let rootNode = r.node.sceneView.GameScene.rootNode
        r.node.reattach(rootNode)

        let s = r.node.position
        let e = rootNode.findNode("totalwin_shape").worldPos
        let c1 = newVector3(1150.0, 50)
        let c2 = newVector3(1450.0, 50)
        let scale = r.node.scale
        let fly = newAnimation()

        fly.numberOfLoops = 1
        fly.loopDuration = 1.0
        fly.onAnimate = proc(p: float) =
            let t = interpolate(0.0, 1.0, p)
            let point = calculateBezierPoint(t, s, e, c1, c2)
            let scaleX = interpolate(scale.x, 0.5, p)
            let scaleY = scaleX

            r.node.position = point
            r.node.scale = newVector3(scaleX, scaleY, 1.0)
        r.node.addAnimation(fly)
        fly.onComplete do():
            r.numbersNode.removeFromParent()
            r.endAnim.onComplete do():
                r.node.removeFromParent()
            r.node.addAnimation(r.endAnim)

    r.node.addAnimation(r.startAnim)

proc playPotentialOops*(parent: Node) =
    let r = new(BonusWinNumber, newNodeWithResource(PREFIX & "bonus_win_number"))
    r.node.position = newVector3(295, 500)
    parent.addChild(r.node)

    let tintEffect = r.oopsNode.findNode("oops.png").component(Tint)
    tintEffect.white = newColor(1.0, 1.0, 1.0, 1.0)
    tintEffect.black = newColor(0.0, 0.0, 0.0, 1.0)
    tintEffect.amount = 1.0
    r.oopsNode.findNode("oops.png").alpha = 0.7

    r.numbersNode.removeFromParent()
    r.dropsNode.removeFromParent()
    r.startAnim.onComplete do():
        r.node.addAnimation(r.endAnim)

    r.node.addAnimation(r.startAnim)

proc playOops*(parent: Node) =
    let r = new(BonusWinNumber, newNodeWithResource(PREFIX & "bonus_win_number"))
    r.node.position = newVector3(295, 500)
    parent.addChild(r.node)

    r.numbersNode.removeFromParent()
    r.dropsNode.removeFromParent()
    r.startAnim.onComplete do():
        r.node.addAnimation(r.endAnim)

    r.node.addAnimation(r.startAnim)
