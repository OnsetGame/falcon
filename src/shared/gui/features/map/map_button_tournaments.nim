import rod / node
import shared / gui / [gui_module, gui_module_types]
import shared / gui / features / button_tournaments


type GTournamentsButton* = ref object of GUIModule
    bttn*: ButtonTournaments


proc createTournamentsButton*(parent: Node): GTournamentsButton =
    result = GTournamentsButton.new()
    result.rootNode = newNode("map_touraments_button")
    result.moduleType = mtTournamentsButton
    parent.addChild(result.rootNode)
    result.bttn = newButtonTournaments(result.rootNode)
    result.bttn.source = "bottomMapMenu"
