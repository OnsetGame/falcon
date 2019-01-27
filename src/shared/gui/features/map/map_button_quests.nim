import rod / node
import shared / gui / [gui_module, gui_module_types]
import shared / gui / features / button_quests


type GQuestsButton* = ref object of GUIModule
    bttn*: ButtonQuests


proc onAction*(b: GQuestsButton, cb: proc() = nil) =
    b.bttn.onAction = proc(enabled: bool) =
        if enabled and not cb.isNil:
            cb()


proc createQuestsButton*(parent: Node): GQuestsButton =
    result = GQuestsButton.new()
    result.rootNode = newNode("map_quests_button")
    result.moduleType = mtQuestsButton
    parent.addChild(result.rootNode)
    result.bttn = newButtonQuests(result.rootNode)
    result.bttn.source = "bottomMapMenu"