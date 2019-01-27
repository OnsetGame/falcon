import node_proxy / proxy

import quest_balloon

import rod / [node]
import nimx / [types, matrixes, animation]

import quest / quests

import shared / window / button_component


nodeProxy QuestGoalAchievedBalloon of QuestBalloon:
    anchor Vector3 {withValue: newVector3(0.0, 144.0, 0.0)}


proc newQuestGoalAchievedBalloon*(parent: Node, q: Quest): QuestGoalAchievedBalloon =
    let node = newNodeWithResource("tiledmap/gui/ui2_0/quest_complete_balloon")
    result = QuestGoalAchievedBalloon.new(node)
    node.anchor = result.anchor
    node.alpha = 0.0

    parent.addChild(node)

    result.setVisible(false)