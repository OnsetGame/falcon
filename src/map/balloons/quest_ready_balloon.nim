import node_proxy / proxy

import quest_balloon

import rod / [node]
import rod / component / [text_component]
import nimx / [types, matrixes, animation]

import core / zone
import core / helpers / [hint_helper, quest_card_helper]
import quest / [quests, quest_icon_component]

import utils / helpers
import shared / window / button_component
import shafa / game / narrative_types


nodeProxy QuestReadyBalloon of QuestBalloon:
    icons Node {withName: "character_icons"}

    anchor Vector3 {withValue: newVector3(0, 168.0, 0.0)}


proc newQuestReadyBalloon*(parent: Node, q: Quest): QuestReadyBalloon =
    let node = newNodeWithResource("tiledmap/gui/ui2_0/quest_ready_balloon")
    result = QuestReadyBalloon.new(node)
    node.anchor = result.anchor
    node.alpha = 0.0

    let size = result.bttn.bounds.size
    result.bttn.bounds = newRect(result.anchor.x, result.anchor.y - size.height, size.width, size.height)

    if q.config.bubbleHead.len == 0:
        for child in result.icons.children:
            child.alpha = float(child.name == $WillFerris & "_01")
    else:
        for child in result.icons.children:
            child.alpha = float(child.name == $q.config.bubbleHead)

    parent.addChild(node)

    result.setVisible(false)