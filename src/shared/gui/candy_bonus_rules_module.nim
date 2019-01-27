import rod.node
import rod.component
import rod.component.text_component

import nimx.matrixes

import gui_module
import gui_module_types

type CandyBonusRulesModule* = ref object of GUIModule
    rulesText: Text

proc createCandyBonusRules*(parent: Node): CandyBonusRulesModule =
    result.new()
    result.rootNode = newLocalizedNodeWithResource("common/gui/precomps/candy_bonus_rules.json")
    parent.addChild(result.rootNode)
    result.moduleType = mtCandyBonusRules
    result.rulesText = result.rootNode.findNode("candy_rules_bonus").component(Text)

proc setRulesText*(cbr: CandyBonusRulesModule, text: string) =
    cbr.rulesText.text = text
