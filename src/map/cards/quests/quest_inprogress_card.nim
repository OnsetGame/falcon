import .. / map_zone_card
import node_proxy / proxy
import rod / node
import quest / [quests, quest_icon_component]
import nimx / matrixes
import shared / window / button_component
import shared / [localization_manager]
import rod / component / text_component
import utils / [helpers, color_segments]
import core / helpers / quest_card_helper
import core / components / timer_component


import .. / .. / tiledmap_actions


nodeProxy QuestInProgressCard of MapZoneCard:
    quest* Quest

    timer* TextTimerComponent {onNodeAdd: timerTextNode}:
        withDays = false
        prepareText = proc(parts: TextTimerComponentParts): string =
            result = parts.hours[1] & ":" & parts.minutes[1] & "<span style=\"fontSize:40;color:FFDF90FF\">:" & parts.seconds[1] & "</span>"
        onUpdate do():
            np.buttonSpeedup.title = np.quest.speedUpPrice.formatThousands()
        onComplete do():
            np.onAction = nil
            np.node.dispatchAction(UpdateQuestsAction)


proc newQuestInProgressCard*(parent: Node, q: Quest): QuestInProgressCard =
    result = QuestInProgressCard.new(MapZoneCardBgStyle.BottomLeft, parent)
    result.bg.bgColor.backgroundForQuest(q)
    result.quest = q

    result.cornerPlaceholder.alpha = 1.0
    result.cornerPlaceholder.cornerForQuest(q)

    result.titleText.text = localizedString("QB_BUILDING_TIME")
    result.titleBg.tintForQuest(q)

    result.bigIconBgNode.backgroundForQuest(q)
    result.questIcon.questConfig = q.config

    result.descriptionNode.alpha = 1.0
    result.descriptionText.text = localizedString("SUW_TITLE2")

    let c = result
    c.activateButton c.buttonSpeedup:
        c.buttonSpeedup.icon = ("currency_bucks", "bucks")

    result.timerNode.alpha = 1.0
    result.timer.timeToEnd = q.config.endTime
