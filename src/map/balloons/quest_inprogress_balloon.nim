import node_proxy / proxy

import quest_balloon

import rod / [node]
import rod / component / [text_component]
import nimx / [types, matrixes, animation]

import quest / quests

import shared / window / button_component
import core / components / timer_component

import .. / tiledmap_actions


nodeProxy QuestInProgressBalloon of QuestBalloon:
    anchor Vector3 {withValue: newVector3(0.0, 144.0, 0.0)}

    timer* TextTimerComponent {onNodeAdd: "counter"}:
        withDays = false
        prepareText = proc(parts: TextTimerComponentParts): string =
            result = parts.hours[1] & ":" & parts.minutes[1] & "<span style=\"fontSize:16\">:" & parts.seconds[1] & "</span>"
        onComplete do():
            np.node.dispatchAction(UpdateQuestsAction)


proc newQuestInProgressBalloon*(parent: Node, q: Quest): QuestInProgressBalloon =
    let node = newNodeWithResource("tiledmap/gui/ui2_0/quest_progress_balloon")
    result = QuestInProgressBalloon.new(node)
    node.anchor = result.anchor
    node.alpha = 0.0

    result.timer.timeToEnd = q.config.endTime

    parent.addChild(node)

    result.setVisible(false)