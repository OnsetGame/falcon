import tables, sequtils
import button_feature
import quest / quests

import nimx / [types, animation, matrixes, notification_center]
import rod / node
import shared / [localization_manager, game_scene]
import shared / window / window_component
import windows / quests / quest_window


type ButtonQuests* = ref object of ButtonFeature

method onInit*(bf: ButtonQuests) =
    bf.composition = "common/gui/ui2_0/quest_button_big.json"
    bf.rect = newRect(0, 0, 225.0, 250.0)
    bf.title = localizedString("QM_QUESTS")

proc checkHint(bf: ButtonQuests) =
    let actiVeQuests = sharedQuestManager().activeStories()
    if actiVeQuests.len == 0:
        bf.hideHint()
    else:
        bf.hint($actiVeQuests.len)

method onCreate*(bf: ButtonQuests) =

    bf.rootNode.sceneView.GameScene.notificationCenter.addObserver(QUESTS_UPDATED_EVENT, bf) do(v: Variant):
        bf.checkHint()

    bf.rootNode.sceneView.GameScene.notificationCenter.addObserver("WINDOW_COMPONENT_TO_SHOW", bf) do(v: Variant):
        if v.get(WindowComponent) of QuestWindow:
            bf.checkHint()

    bf.rootNode.sceneView.GameScene.notificationCenter.addObserver("QUEST_COMPLETED", bf) do(v: Variant):
        bf.checkHint()

    bf.checkHint()


template newButtonQuests*(parent: Node): ButtonQuests =
    ButtonQuests.new(parent)