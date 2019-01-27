import nimx / [property_visitor, types, matrixes]
import rod / [rod_types, node, component]
import rod / component / text_component
import shared / game_scene
import core / zone
import core / features / booster_feature
import strutils

type BoostMultiplier* = ref object of Component
    feature: Feature
    gs: GameScene
    cb: proc()
    keepSubscribe*: bool
    starNode*:Node
    mText: string

method componentNodeWasAddedToSceneView*(c: BoostMultiplier) =
    if c.starNode.isNil:
        c.starNode = newNodeWithResource("common/gui/popups/precomps/boost_shape")
        c.node.addChild(c.starNode)

        c.node.findNode("boost_txt").getComponent(Text).text = c.mText

proc `text=`*(c: BoostMultiplier, txt: string) =
    c.mText = txt
    let txtNode = c.node.findNode("boost_txt")
    if not txtNode.isNil:
        txtNode.getComponent(Text).text = txt

proc text*(c: BoostMultiplier): string =
    result = c.mText

method visitProperties*(c: BoostMultiplier, p: var PropertyVisitor) =
    p.visitProperty("text", c.text)

proc addBoostMultiplier*(parent: Node, pos: Vector3 = newVector3(0.0), scale: float32 = 1.0): BoostMultiplier =
    let newNode = parent.newChild("BoostMultiplierNode")
    result = newNode.addComponent(BoostMultiplier)
    newNode.position = pos
    newNode.scale = newVector3(scale, scale, 1.0)

proc onRemoved*(c: BoostMultiplier) =
    if not c.feature.isNil and not c.keepSubscribe:
        c.feature.unsubscribe(c.gs, c.cb)

proc addBoostMultiplierForFeature*(parent: Node, pos: Vector3 = newVector3(0.0), scale: float32 = 1.0, kind: BoosterTypes): BoostMultiplier =
    result = parent.addBoostMultiplier(pos, scale)
    let r = result
    r.node.alpha = 0.0
    let feature = findFeature(BoosterFeature)
    let featureUpdate = proc() =
        for booster in feature.boosters:
            if booster.kind == kind:
                if booster.isActive:
                    r.node.alpha = 1.0
                else:
                    r.node.alpha = 0.0

    result.feature = feature
    result.gs = parent.sceneView.GameScene
    result.cb = featureUpdate
    feature.subscribe(result.gs, featureUpdate)
    featureUpdate()

proc addExpBoostMultiplier*(parent: Node, pos: Vector3 = newVector3(0.0), scale: float32 = 1.0): BoostMultiplier =
    result = parent.addBoostMultiplierForFeature(pos, scale, BoosterTypes.btExperience)
    result.text = boostMultiplierText(BoosterTypes.btExperience)

proc addIncomeBoostMultiplier*(parent: Node, pos: Vector3 = newVector3(0.0), scale: float32 = 1.0): BoostMultiplier =
    result = parent.addBoostMultiplierForFeature(pos, scale, BoosterTypes.btIncome)
    result.text = boostMultiplierText(BoosterTypes.btIncome)

proc addTpBoostMultiplier*(parent: Node, pos: Vector3 = newVector3(0.0), scale: float32 = 1.0): BoostMultiplier =
    result = parent.addBoostMultiplierForFeature(pos, scale, BoosterTypes.btTournamentPoints)
    result.text = boostMultiplierText(BoosterTypes.btTournamentPoints)

registerComponent(BoostMultiplier, "Falcon")
