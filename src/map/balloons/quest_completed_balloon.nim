import node_proxy / proxy

import quest_balloon

import rod / [node]
import nimx / [types, matrixes, animation]

import quest / quests

import core / helpers / hint_helper
import shared / window / button_component
import utils / helpers


nodeProxy QuestCompletedBalloon of QuestBalloon:
    anchor Vector3 {withValue: newVector3(0.0, 168.0, 0.0)}
    hintNode Node {withName: "alert_comp_placeholder"}

    hintShadow Node {withName: "alert_comp_shadow"}:
        alpha = 0.0


proc newQuestCompletedBalloon*(parent: Node, q: Quest): QuestCompletedBalloon =
    let node = newNodeWithResource("tiledmap/gui/ui2_0/quest_getreward_balloon")
    result = QuestCompletedBalloon.new(node)
    node.anchor = result.anchor
    node.alpha = 0.0

    let hint = newHintWithTitle(newNodeWithResource("common/gui/ui2_0/alert_comp"))
    hint.titleText = $q.rewards.len
    result.hintNode.addChild(hint.node)
    result.hint = hint

    parent.addChild(node)

    result.setVisible(false)
    hint.setVisible(false)


method show*(b: QuestCompletedBalloon, cb: proc() = nil) =
    proc mycb() =
        let anim = newAnimation()
        anim.loopDuration = 0.3
        anim.numberOfLoops = 1
        anim.onAnimate = proc(p: float) =
            b.hintShadow.alpha = p
        b.node.addAnimation(anim)
        if not cb.isNil:
            cb()
    procCall b.QuestBalloon.show(mycb)
