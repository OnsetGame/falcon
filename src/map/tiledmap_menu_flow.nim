import variant, typetraits
import quest / quests
import core / flow / [ flow, flow_state_types, flow_states_implementation ]
import core / zone
import narrative / [ quest_narrative, narrative_character, narrative ]
import shafa / game / narrative_types
import tiledmap_menu, tiledmap_quest_card, tiledmap_quest_balloons


type MapZoneMenuFlowState* = ref object of BaseFlowState
    zone*: Zone
    quest*: Quest
    menu*: TiledMapMenu
method appearsOn*(fs: MapZoneMenuFlowState, cur: BaseFlowState): bool = cur.parent.isNil


proc pushMapZoneMenuFlowState*(T: typedesc, zone: Zone, quest: Quest, menu: TiledMapMenu): T {.discardable.} =
    if zone.isNil or zone.flowManager.isNil:
        return

    let fs = T.newFlowState()
    fs.zone = zone
    fs.quest = quest
    fs.menu = menu

    zone.flowManager.pushBack(fs)

    result = fs


type OpenQuestBubbleFlowStateImpl* = ref object of MapZoneMenuFlowState
method wakeUp*(fs: OpenQuestBubbleFlowStateImpl) =
    fs.menu.showBubbleForQuest(fs.quest, proc() =
        fs.zone.flowManager.pop(fs)
    )


type OpenQuestCardFlowStateImpl* = ref object of MapZoneMenuFlowState
method wakeUp*(fs: OpenQuestCardFlowStateImpl) =
    if findFlowState(NarrativeState).isNil and fs.quest.status == QuestProgress.Ready and not fs.quest.config.narrative.isNil and fs.quest.config.narrative.character != None:
        let state = QuestNarrativeState.newFlowState()
        state.ndata = fs.quest.config.narrative
        state.pushBack()

    fs.menu.showCardForQuest(fs.quest, proc() =
        fs.zone.flowManager.pop(fs)
    )


type CloseQuestBubbleFlowState* = ref object of MapZoneMenuFlowState
method wakeUp*(fs: CloseQuestBubbleFlowState) =
    fs.menu.hideBubbleForQuest(fs.quest, proc() =
        fs.zone.flowManager.pop(fs)
    )


type CloseQuestCardFlowState* = ref object of MapZoneMenuFlowState
method wakeUp*(fs: CloseQuestCardFlowState) =
    let state = findFlowState(QuestNarrativeState)
    if not state.isNil:
        state.pop()

    fs.menu.hideCardForQuest(fs.quest, proc() =
        fs.zone.flowManager.pop(fs)
    )


type OpenQuestBubbleFlowState* = ref object of MapZoneMenuFlowState
method wakeUp*(fs: OpenQuestBubbleFlowState) =
    if fs.menu.questCard.isCardOpenedFor(fs.quest):
        CloseQuestCardFlowState.pushMapZoneMenuFlowState(fs.zone, fs.quest, fs.menu)
    if not fs.menu.questBubbles.isBubbleOpenedFor(fs.quest):
        if not fs.quest.config.isQuestFinished():
            OpenQuestBubbleFlowStateImpl.pushMapZoneMenuFlowState(fs.zone, fs.quest, fs.menu)

    fs.zone.flowManager.pop(fs)


type OpenQuestCardFlowState* = ref object of MapZoneMenuFlowState
method wakeUp*(fs: OpenQuestCardFlowState) =
    fs.menu.clear()

    if fs.menu.questBubbles.isBubbleOpenedFor(fs.quest):
        CloseQuestBubbleFlowState.pushMapZoneMenuFlowState(fs.zone, fs.quest, fs.menu)
    if not fs.menu.questCard.isCardOpenedFor(fs.quest):
        OpenQuestCardFlowStateImpl.pushMapZoneMenuFlowState(fs.zone, fs.quest, fs.menu)

    fs.zone.flowManager.pop(fs)


proc closeAllMenuCards*(menu: TiledMapMenu) =
    menu.clear()

    let quest = menu.lastQuest
    if quest.isNil:
        return

    let zone = findZone(quest.config.targetName)
    OpenQuestBubbleFlowState.pushMapZoneMenuFlowState(zone, quest, menu)