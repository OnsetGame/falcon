import json, logging

import nimx / [ types, timer, animation, button, matrixes, event, autotest ]
import core / notification_center

import rod / [ rod_types, node, viewport, quaternion ]
import rod / component / [ ui_component, solid, text_component, camera, ae_composition ]

import shared / [ director, game_scene, user, localization_manager ]
import core.net.server
import utils / [game_state, falcon_analytics]

import falconserver.tutorial.tutorial_types
export tutorial_types

import core / flow / flow_state_types
import narrative / narrative
export narrative

import core / features / [ exchange_feature, tournaments_feature]
import core / zone

import quest / quests

type TutButton* = ref object of Button

method onScroll*(b: TutButton, e: var Event): bool =
    result = true

proc isFrameClosed*(name: string): bool =
    if haveTestsToRun():
        return true
    else:
        return name in currentUser().clientState and currentUser().clientState[name].getBool(false)

proc addTutorialFlowState*(state: TutorialState, imidiatly: bool = false, front: bool = false) =
    let st = findFlowState(TutorialFlowState)
    if not st.isNil and st.name == $state:
        return

    if not isFrameClosed($state):
        let tut_state = newFlowState(TutorialFlowState)
        tut_state.name = $state
        if imidiatly:
            execute(tut_state)
        else:
            if front:
                pushFront(tut_state)
            else:
                pushBack(tut_state)

method getType*(state: TutorialFlowState): FlowStateType = TutorialFS
method getFilters*(state: TutorialFlowState): seq[FlowStateType] = return @[NarrativeFS]

proc openTutorialStep*(quest: Quest) =
    let targetName = quest.config.targetName

    case quest.status:
        of QuestProgress.Ready:
            if targetName == "restaurant":
                tsMapQuestAvailble.addTutorialFlowState()
            if targetName == "dreamTowerSlot":
                tsMapQuestAvailble2.addTutorialFlowState()
            if targetName == "wheeloffortune" and currentUser().isEnoughtParts(quest.config.price):
                tsWheelQuestAvailble.addTutorialFlowState()
            if targetName == "stadium":
                tsTournamentQuestAvailble.addTutorialFlowState()
            if targetName == "ufoSlot" and isFrameClosed($tsTournamentJoin):
                tsUfoQuestAvailble.addTutorialFlowState()
            if targetName == "bank":
                tsBankQuestAvailble.addTutorialFlowState()
            if targetName == "candySlot":
                tsCandyQuestAvailble.addTutorialFlowState()
            if targetName == "cityHall" and isFrameClosed($tsUfoQuestAvailble):
                tsBoosterQuestAvailble.addTutorialFlowState()

        of QuestProgress.GoalAchieved:
            if targetName == "restaurant":
                tsMapQuestComplete.addTutorialFlowState()
            if targetName == "dreamTowerSlot":
                tsMapQuestComplete2.addTutorialFlowState()
            if targetName == "wheeloffortune":
                addTutorialFlowState(tsWheelQuestComplete)

        of QuestProgress.Completed:
            if targetName == "restaurant":
                tsMapQuestReward.addTutorialFlowState()
            if targetName == "dreamTowerSlot":
                tsMapQuestReward2.addTutorialFlowState()
            if targetName == "wheeloffortune":
                addTutorialFlowState(tsWheelQuestReward)
            if targetName == "candySlot":
                tsMapCandyQuestReward.addTutorialFlowState()
            if targetName == "bank":
                tsBankQuestReward.addTutorialFlowState()
            if targetName == "stadium":
                tsStadiumQuestReward.addTutorialFlowState()

        else:
            discard

method wakeUp*(state: TutorialFlowState) =
    echo "TutorialFlowState ", state.name
    if isFrameClosed(state.name):
        state.pop()
        return

    let nState = newFlowState(NarrativeState)
    nState.composName = state.name
    nState.execute()
    # sharedAnalytics().tutorial_show(state.name, -1, isUseTutorBufferForAnalytics(state))

    nState.onCLose = proc() =
        sharedServer().completeTutorialStep(state.name) do(jn: JsonNode):
            info "complete tutorial step ", state.name
            sharedAnalytics().tutorial_step(state.name, -1, isUseTutorBufferForAnalytics(state.name))
            state.pop()

            let exchangeFeature = findFeature(ExchangeFeature)
            let tournamentFeature = findFeature(TournamentsFeature)

            if state.name == $tsMapQuestReward2:
                addTutorialFlowState(tsMapPlaySlot)
            if state.name == $tsWheelQuestReward:
                addTutorialFlowState(tsWheelGuiButton)
            if state.name == $tsBankQuestReward and exchangeFeature.hasDiscountedExchange:
                addTutorialFlowState(tsBankFeatureBttn)
            if state.name == $tsMapCandyQuestReward:
                addTutorialFlowState(tsMapPlayCandy)
            if state.name == $tsWheelClose:
                addTutorialFlowState(tsGasStationQuestAvailble)
            if state.name == $tsStadiumQuestReward:
                tournamentFeature.dispatchActions()
                addTutorialFlowState(tsTournamentButton)
            if state.name == $tsShowTpPanel:
                for quest in sharedQuestManager().activeStories():
                    quest.openTutorialStep()
