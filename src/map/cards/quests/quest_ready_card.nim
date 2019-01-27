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


nodeProxy QuestReadyCard of MapZoneCard


proc newQuestReadyCard*(parent: Node, q: Quest): QuestReadyCard =
    let qc = q.config

    result = QuestReadyCard.new(MapZoneCardBgStyle.BottomLeft, parent)
    result.bg.bgColor.backgroundForQuest(q)

    result.cornerPlaceholder.cornerForQuest(q)

    result.titleText.text = localizedString("REWARD_TEXT")
    result.titleBg.tintForQuest(q)

    result.bigIconBgNode.backgroundForQuest(q)
    result.questIcon.questConfig = q.config

    result.descriptionNode.alpha = 1.0
    result.descriptionText.text = localizedString(qc.name & "_TITLE")

    let c = result
    c.activateButton c.buttonBuild:
        c.buttonBuild.title = qc.price.int64.formatThousands()
        case qc.currency
            of Currency.Parts:
                c.buttonBuild.icon = ("reward_icons", "parts")
            of Currency.TournamentPoint:
                c.buttonBuild.icon = ("reward_icons", "tourPoints")
            else:
                c.buttonBuild.icon = ("reward_icons", "undefined")
    
    result.rewardsPlaceholder.alpha = 1.0
    result.rewardsPlaceholder.rewardsForQuest(q)