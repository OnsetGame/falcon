import rod.node
import rod.component
import rod.component.ui_component
import rod.component.text_component

import nimx.types
import nimx.matrixes
import nimx.animation

import gui_module
import gui_module_types
import shared.window.button_component
import strutils

type AutospinsSwitcherModule* = ref object of GUIModule
    button*: ButtonComponent
    anim*: Animation
    #animOff*: Animation
    mIsOn: bool
    onStateChanged*: proc(state: bool)

proc createAutospinsSwitcher*(parent: Node): AutospinsSwitcherModule =
    result.new()
    result.rootNode = newLocalizedNodeWithResource("common/gui/ui2_0/autospin_switcher")
    parent.addChild(result.rootNode)
    result.moduleType = mtAutospinsSwitcher

    result.anim = result.rootNode.animationNamed("switch")
    result.button = result.rootNode.createButtonComponent(result.anim, newRect(-20.0, 0.0, 270.0, 125.0))
    result.button.enabled = false

    for c in result.rootNode.children:
        if c.name.contains("gui_autospins"):
            c.getComponent(Text).lineSpacing = -5

proc `isOn=`*(bc: AutospinsSwitcherModule, state: bool) =
    bc.mIsOn = state
    if not bc.onStateChanged.isNil:
        bc.onStateChanged(bc.mIsOn)

template isOn*(bc: AutospinsSwitcherModule): bool = bc.mIsOn

proc switchOn*(bc: AutospinsSwitcherModule) =
    bc.anim.loopPattern = lpStartToEnd
    bc.rootNode.addAnimation(bc.anim)
    bc.isOn = true

proc switchOff*(bc: AutospinsSwitcherModule) =
    bc.anim.loopPattern =  lpEndToStart
    bc.rootNode.addAnimation(bc.anim)
    bc.isOn = false
