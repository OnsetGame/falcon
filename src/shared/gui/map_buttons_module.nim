import rod / [ rod_types, node, viewport, component ]
import rod / component / [ text_component, ui_component ]
import nimx / [ button, matrixes, animation, notification_center, formatted_text, timer ]
import utils / [ sound_manager, game_state, pause ]

import quest.quests

import shared / [ game_scene, user ]
import shared / window / [ window_component, button_component ]
import windows / quests / quest_window

import gui_module
import gui_module_types

type GBuildStore* = ref object of GUIModule
    button*: ButtonComponent

type GPlayButton* = ref object of GUIModule
    button*: ButtonComponent
    numTasks: int

proc createPlayButton*(parent: Node): GPlayButton =
    result.new()
    result.rootNode = newLocalizedNodeWithResource("common/gui/ui2_0/play_button.json")
    result.rootNode.name = "map_play_button"
    parent.addChild(result.rootNode)
    result.moduleType = mtPlayButton

    let pressAnim = result.rootNode.animationNamed("press")
    result.button = result.rootNode.createButtonComponent(pressAnim, newRect(10.0, 10.0, 250.0, 250.0))