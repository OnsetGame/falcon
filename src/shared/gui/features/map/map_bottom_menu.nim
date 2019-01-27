import rod / node
import node_proxy / proxy


import shared / gui / features / button_feature
import shared / window / [button_component, window_manager]
import .. / slot / slot_bottom_menu
import utils / falcon_analytics
import shared / [user, localization_manager]
import shared / gui / [gui_module, gui_module_types]


type ButtonMapCollect = ref object of ButtonSlotCollect


method onInit*(bf: ButtonMapCollect) =
    procCall bf.ButtonSlotCollect.onInit()
    bf.composition = "common/gui/ui2_0/collect_in_map_button"
    bf.title = localizedString("GUI_BONUS")


method sendAnalEvents(bf: ButtonMapCollect, isOpen: bool) =
    let hints = bf.hintsCount()

    if isOpen:
        sharedAnalytics().collect_map_open(bf.chipsOnShow, hints.int64)
    else:
        sharedAnalytics().collect_map_open(currentUser().chips, currentUser().chips - bf.chipsOnShow)


type MapBottomMenu* = ref object of GUIModule
    bttn*: ButtonMapCollect

proc createMapBottomMenu*(parent: Node): MapBottomMenu =
    result = MapBottomMenu.new()
    let rootNode = newNode("map_bottom_menu")
    result.rootNode = rootNode
    result.moduleType = mtMapBottomMenu
    parent.addChild(result.rootNode)

    result.bttn = ButtonMapCollect.new(result.rootNode)
    result.bttn.source = "bottomMapMenu"
    for b in result.bttn.buttons:
        b.source = "mapCollect"
    result.bttn.collect.source = "mapCollect"

    let action = result.bttn.onAction
    result.bttn.onAction = proc(enabled: bool) =
        rootNode.removeFromParent()
        sharedWindowManager().insertNodeBeforeWindows(rootNode)
        action(enabled)

method onRemoved*(gsbm: MapBottomMenu)=
    if not gsbm.bttn.isNil:
        gsbm.bttn.onRemoved()
