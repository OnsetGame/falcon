import nimx / matrixes
import rod / node
import shared / gui / [gui_module, gui_module_types]
import shared / gui / features / collect_button
import core / helpers / boost_multiplier


type GCollectButton* = ref object of GUIModule
    bttn*: CollectButton
    boostMultiplier*: BoostMultiplier

proc createCollectButton*(parent: Node): GCollectButton =
    result = GCollectButton.new()
    result.rootNode = newNode("map_collect_button")
    result.moduleType = mtCollectButton
    parent.addChild(result.rootNode)
    result.bttn = newCollectButton(result.rootNode)
    result.bttn.source = "bottomMapMenu"

    result.boostMultiplier = result.rootNode.addIncomeBoostMultiplier(newVector3(405.0, 135, 0), 0.8)

method onRemoved*(gcb: GCollectButton)=
    if not gcb.boostMultiplier.isNil:
        gcb.boostMultiplier.onRemoved()
        gcb.boostMultiplier = nil
