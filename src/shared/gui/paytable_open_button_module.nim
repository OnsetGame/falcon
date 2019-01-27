import rod.rod_types
import rod.node
import rod.viewport
import rod.component.ui_component

import nimx.types
import nimx.animation
import nimx.matrixes

import gui_module
import gui_module_types
import shared.window.button_component

type PaytableOpenButtonModule* = ref object of GUIModule
    button*: ButtonComponent

proc createPaytableOpenButton*(parent: Node): PaytableOpenButtonModule =
    result.new()
    result.rootNode = newLocalizedNodeWithResource("common/gui/precomps/pay_table_open_button.json")
    parent.addChild(result.rootNode)
    result.moduleType = mtPayTableOpenButton

    let anim = result.rootNode.animationNamed("press")
    result.button = result.rootNode.createButtonComponent(anim, newRect(0.0, 0.0, 175.0, 175.0))
