import rod.node

import nimx.matrixes

import gui_module
import gui_pack
import gui_module_types

import rod.component
import rod.component.text_component

type MermaidRulesModule* = ref object of GUIModule

proc createMermaidRulesModule*(parent: Node, pos: Vector3): MermaidRulesModule =
    result.new()
    result.rootNode = newLocalizedNodeWithResource("common/gui/precomps/bonus_game_tips.json")
    parent.addChild(result.rootNode)
    result.rootNode.position = pos
    result.moduleType = mtMermaidRulesModule

template show*(wp: MermaidRulesModule) =
    wp.rootNode.alpha = 1.0

template hide*(wp: MermaidRulesModule) =
    wp.rootNode.alpha = 0.0



type MermaidCounterModule* = ref object of GUIModule

proc createMermaidCounterModule*(parent: Node, pos: Vector3): MermaidCounterModule =
    result.new()
    result.rootNode = newLocalizedNodeWithResource("common/gui/precomps/bonus_game_counter.json")
    parent.addChild(result.rootNode)
    result.rootNode.position = pos
    result.moduleType = mtMermaidCounterModule

template show*(wp: MermaidCounterModule) =
    wp.rootNode.alpha = 1.0

template hide*(wp: MermaidCounterModule) =
    wp.rootNode.alpha = 0.0

proc text*(wp: MermaidCounterModule, text: string) =
    wp.rootNode.findNode("count_text_@noloc").component(Text).text = text
