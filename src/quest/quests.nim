import json, logging, tables, times, strutils, algorithm, sequtils, hashes, preferences
import boolseq

import falconserver / quest / quest_types
import falconserver / auth / profile_types
import falconserver / map / building / builditem
import falconserver / common / [game_balance, currency]

import shafa / game / [ feature_types, narrative_types, reward_types ]
import shared / [user, localization_manager]

import utils / [game_state, timesync, falcon_analytics, falcon_analytics_helpers]

import core / notification_center
import core / flow / flow_state_types

import quest_helpers
export quest_types
export currency


const perUpdatesMinimumDelay = 10.0
const QUESTS_UPDATED_EVENT* = "OnQuestsUpdated"
const QUESTS_ON_NEW_QUEST* = "OnNewQuestAdded"
const QUESTS_ON_QUEST_COMPLETED* = "QUESTS_ON_QUEST_COMPLETED"
const QUESTS_KEY* = "QuestManager"
const DAILY_KEY* = "Daily"
const STORY_KEY* = "Story"
const COMPLETED_KEY* = "CompletedQuests"

type TaskProgress* = ref object
    current*: uint64
    total*: uint64
    index*: uint

type Task* = ref object of RootObj
    progresses*:      seq[TaskProgress]
    target*:          int
    taskType*:        QuestTaskType
    icon*:            string
    difficulty*:      DailyDifficultyType

type QuestConfig* = ref object of RootObj
    name*: string
    time*: float
    price*: int
    currency*: Currency
    endTime*: float
    id*: int
    zoneImageTiledProp*: string
    decoreImageTiledProp*: string
    targetName*: string
    isMain*: bool
    deps: seq[int]
    lockedByLevel*: int
    enabled*: bool
    unlockFeature*: FeatureType
    narrative*: NarrativeData
    bubbleHead*: string
    rewards*: seq[Reward]
    vipOnly*: bool

type Quest* = ref object of RootObj
    id*:      int
    name*:    string
    description*: seq[QuestDesc]
    tasks*:   seq[Task]
    status*:  QuestProgress
    icon*:    string
    kind*:    QuestKind
    showCompleted*: bool
    config*: QuestConfig
    skipPrice*: int

type DailyQuest* = ref object of Quest
    rewards: seq[Reward]

type QuestsPreferences* = ref object
    story*: seq[int]
    daily*: seq[int]
    newDaily*: seq[int]
    newStory*: seq[int]
    completed*: seq[int]

type SlotQuest* = ref object
    stage*: int
    questId*: int

type QuestManager* = ref object of RootObj
    daily*: TableRef[int, Quest]
    quests*: TableRef[int, Quest]
    lastUpdateTime*: float
    genTime*: float
    preferences*: QuestsPreferences
    questRevision*: Hash
    slotQuests*: seq[SlotQuest]
    questConfigs*: seq[QuestConfig]

var questManager: QuestManager

template timeToEnd*(qc: QuestConfig): float = timeLeft(qc.endTime)

template timeToEndStr*(qc: QuestConfig): string = buildTimerString(formatDiffTime(qc.timeToEnd))

template timeStr*(qc: QuestConfig): string = buildTimerString(formatDiffTime(qc.time))


proc rewards*(q: Quest): seq[Reward] =
    case q.kind:
        of QuestKind.Story:
            let qc = q.config
            if not qc.isNil:
                return qc.rewards

        of QuestKind.Daily:
            return q.DailyQuest.rewards

        else:
            discard


proc createQuest(kind: QuestKind, name: string, description: seq[QuestDesc], tasks: seq[Task], id: int, p: QuestProgress): Quest =
    if kind == QuestKind.Daily:
        result = DailyQuest.new()
    else:
        result = Quest.new()

    result.kind = kind
    result.id = id
    result.name = name
    result.description = description
    result.tasks = tasks
    result.status = p

proc parseQuestConfig(jn: JsonNode): QuestConfig =
    result.new()
    if "name" in jn:
        result.name = jn["name"].getStr()

    if "price" in jn:
        result.price = jn["price"].getInt()

    if "currency" in jn:
        result.currency = try: parseEnum[Currency](jn["currency"].getStr()) except: Currency.Parts

    if "time" in jn:
        result.time = jn["time"].getFloat().float

    if "endTime" in jn:
        result.endTime = jn["endTime"].getFloat().float

    if "id" in jn:
        result.id = jn["id"].getInt()

    if "image_zone" in jn:
        result.zoneImageTiledProp = jn["image_zone"].getStr()

    if "image_decore" in jn:
        result.decoreImageTiledProp = jn["image_decore"].getStr()

    if "target" in jn:
        result.targetName = jn["target"].getStr()

    if "ismain" in jn:
        result.isMain = jn["ismain"].getBool()

    if "d" in jn: #dependencies
        result.deps = @[]
        for jd in jn["d"]:
            result.deps.add(jd.getInt())

    if "lvl" in jn:
        result.lockedByLevel = jn["lvl"].getInt()

    if "enabled" in jn:
        result.enabled = jn["enabled"].getBool()

    if "unlock_feature" in jn:
        result.unlockFeature = parseEnum(jn["unlock_feature"].getStr(), noFeature)
        assert($result.unlockFeature == jn["unlock_feature"].getStr())  # to avoid invalid feature spelling

        # if result.lockedByLevel > 0:
        #     echo "got lockedByLevel ", result.name, " level ", result.lockedByLevel

    if "rews" in jn:
        result.rewards = jn["rews"].getRewards()

    if "narrative" in jn:
        result.narrative = jn["narrative"].toNarrativeData()
        result.narrative.bubbleText = localizedString(result.narrative.bubbleText % [result.name])

    if "vip_only" in jn:
        result.vipOnly = jn["vip_only"].getBool()

    result.bubbleHead = jn{"bubble_head"}.getStr()

proc initQuestConfigs*(qman: QuestManager, jn: JsonNode)=
    qman.questConfigs = newSeq[QuestConfig](jn.len)
    for jc in jn:
        var qc = parseQuestConfig(jc)
        qman.questConfigs[qc.id - 1] = qc

proc getProgress*(q: Quest): float=
    for t in q.tasks:
        for tp in t.progresses:
            result += tp.current.float / tp.total.float
        result /= t.progresses.len.float
    result /= q.tasks.len.float

proc hasProgress*(q: Quest): bool=
    for t in q.tasks:
        for tp in t.progresses:
            if tp.current.int64 > 0:
                result = true

proc completed*(q: Quest): bool=
    result = q.status == QuestProgress.Completed

proc inProgress*(q: Quest): bool=
    result = q.status >= QuestProgress.InProgress and not q.completed()

proc serialize*(qp: QuestsPreferences)=
    setGameState(DAILY_KEY, qp.daily, QUESTS_KEY)
    setGameState(STORY_KEY, qp.story, QUESTS_KEY)
    setGameState(COMPLETED_KEY, qp.completed, QUESTS_KEY)
    # let sp = sharedPreferences()
    # sp[QUESTS_KEY][DAILY_KEY] = %qp.daily
    # sp[QUESTS_KEY][STORY_KEY] = %qp.story
    # sp[QUESTS_KEY][COMPLETED_KEY] = %qp.completed

    # syncPreferences()

proc deserialize*(): QuestsPreferences=
    let sp = sharedPreferences()

    result.new()
    result.daily = @[]
    result.story = @[]
    result.newStory = @[]
    result.newDaily = @[]
    result.completed = @[]

    if hasGameState(DAILY_KEY, QUESTS_KEY):
        for id in getGameState(DAILY_KEY, QUESTS_KEY):
            result.daily.add(id.getInt())

    if hasGameState(STORY_KEY, QUESTS_KEY):
        for id in getGameState(STORY_KEY, QUESTS_KEY):
            result.story.add(id.getInt())

proc addQuest*(qp: QuestsPreferences, q: Quest)=
    if q.kind == QuestKind.Story:
        if q.id notin qp.story:
            qp.story.add(q.id)
            qp.newStory.add(q.id)
    elif q.kind == QuestKind.Daily:
        if q.id notin qp.daily:
            qp.daily.add(q.id)
            qp.newDaily.add(q.id)
            # ANALYTICS
            if q.id == QUEST_GEN_START_ID:
                startCountQuestWindowsAnalytics = true

    # echo "QuestsPreferences addQuest ", q.kind, " newDaily ", qp.newDaily, " newStory ", qp.newStory, " lenDaily ", qp.daily.len, " lenStory ", qp.story.len

proc resetStoryCounter*(qp: QuestsPreferences)=
    qp.newStory.setLen(0)

proc resetDailyCounter*(qp: QuestsPreferences)=
    qp.newDaily.setLen(0)

proc deleteQuest*(qp: QuestsPreferences, q: Quest)=
    for i, qu in qp.completed:
        if qu == q.id:
            qp.completed.del(i)
            break
    if q.kind == QuestKind.Story:
        for i, qu in qp.story:
            if qu == q.id:
                qp.story.del(i)
                break
    elif q.kind == QuestKind.Daily:
        for i, qu in qp.daily:
            if qu == q.id:
                qp.daily.del(i)
                break

proc questById*(man: QuestManager, id: int): Quest=
    result = man.quests.getOrDefault(id)
    if result.isNil:
        result = man.daily.getOrDefault(id)

proc questByName*(man: QuestManager, name: string): Quest =
    for k, v in man.quests:
        if v.config.name == name:
            result = v
            break

proc getAllDeps*(qm: QuestManager, qc: QuestConfig):seq[QuestConfig]=
    result = @[]
    var deps = qc.deps
    while deps.len > 0:
        var tdpes = deps
        deps.setLen(0)
        for d in tdpes:
            var qc: QuestConfig
            qc = qm.questConfigs[d - 1]
            assert(qc.id == d, "Not sorted config")
            deps.add(qc.deps)
            result.add(qc)

proc questUnlockLevel*(qm: QuestManager, questConfig: QuestConfig): int =
    result = questConfig.lockedByLevel

    var alldeps = qm.getAllDeps(questConfig)
    for dep in alldeps:
        result = max(result, dep.lockedByLevel)

proc questUnlockLevel*(qm: QuestManager, quest: Quest): int =
    result = -1

    if not quest.config.isNil:
        result = qm.questUnlockLevel(quest.config)

proc clearPreferences*(man: QuestManager)= # used in resetProgress cheat
    man.preferences.story.setLen(0)
    man.preferences.daily.setLen(0)
    man.preferences.completed.setLen(0)
    sharedPreferences()["quest_module_active_tab"] = %""
    man.preferences.serialize()

proc sharedQuestManager*(): QuestManager=
    if questManager.isNil():
        questManager.new()
        questManager.quests = newTable[int, Quest]()
        questManager.daily = newTable[int, Quest]()
        questManager.preferences = deserialize()

    return questManager

proc cheatDeleteQuestManager*() =
    questManager = nil



proc sortedDailyQueseq*(man: QuestManager): seq[Quest]=
    var queseq = newSeq[Quest]()
    for k, v in man.daily:
        queseq.add(v)

    const sortingPrecision = 100000.0
    queseq.sort(proc(x,y: Quest):int =
        result = ((y.getProgress() - x.getProgress()) * sortingPrecision).int
    )

    result = queseq


proc sortedQueseq*(man: QuestManager): seq[Quest] =
    var queseq = newSeq[Quest]()
    for k, v in man.quests:
        queseq.add(v)

    queseq.sort(proc(x,y: Quest):int =
        result = cmp(y.status, x.status)
        if result == 0:
            result = cmp(y.config.isMain, x.config.isMain)
            if result == 0:
                if x.status == QuestProgress.InProgress:
                    result = cmp(x.config.endTime, y.config.endTime)
                else:
                    result = cmp(x.config.price, y.config.price)
    )

    result = queseq

proc proceedQuests*(man: QuestManager, jn: JsonNode, reload: bool = false)

proc questConfigByName*(man: QuestManager, name: string): QuestConfig =
    for q in man.questConfigs:
        if q.name == name:
            result = q
            break

proc allQuests*(man: QuestManager): seq[Quest]=
    result = newSeq[Quest]()
    for k, v in man.daily:
        result.add(v)

    for k, v in man.quests:
        result.add(v)

proc activeQuests*(man: QuestManager): seq[Quest] {.deprecated.}=
    result = @[]

    for k, v in man.daily:
        if v.status == QuestProgress.InProgress:
            result.add(v)

proc activeStories*(man: QuestManager): seq[Quest]=
    result = @[]

    for v in man.quests.values():
        result.add(v)

proc activeTasks*(man: QuestManager): seq[Quest] =
    result = @[]

    for k, v in man.daily:
        if v.status == QuestProgress.InProgress:
            result.add(v)


proc readyTasks*(man: QuestManager): seq[Quest] =
    result = @[]

    for k, v in man.daily:
        if v.status == QuestProgress.Ready:
            result.add(v)


proc deleteQuest*(man: QuestManager, id: int) =
    let q = man.questById(id)
    if not q.isNil:
        if q.kind == QuestKind.Story:
            man.quests.del(id)
            # info "delete story id ", id
        elif q.kind == QuestKind.Daily:
            for v in man.slotQuests:
                if v.questId == id:
                    setGameState("LAST_CLOSED_TASK_ID", v.stage + 1, "QUESTS")
            man.daily.del(id)
            # info "delete task id ", id

        man.preferences.deleteQuest(q)


proc speedUpPrice*(q: Quest): int =
    if not q.isNil:
        case q.kind:
            of QuestKind.Story:
                if not q.config.isNil:
                    let gb = sharedGameBalance()
                    let r = max((q.config.timeToEnd / 60.0), 1.0) * gb.questSpeedUpPrice.float
                    result = r.int
            of QuestKind.Daily:
                result = q.skipPrice
            else:
                discard


proc complitedQuests*(man: QuestManager): seq[Quest]=
    result = @[]

    for k, v in man.quests:
        if v.status == QuestProgress.Completed:
            result.add(v)

proc uncompletedQuests*(man: QuestManager): seq[Quest] =
    result = @[]

    for k, v in man.quests:
        if not v.completed:
            result.add(v)

proc completedTasks*(man: QuestManager): seq[Quest]=
    result = @[]

    for k, v in man.daily:
        if v.status == QuestProgress.Completed:
            result.add(v)

proc activeQuestsCount*(man: QuestManager): int =
    result += man.activeQuests().len
    result += man.uncompletedQuests.len


proc clearAllQuests*(man: QuestManager)=
    man.quests = newTable[int, Quest]()
    man.daily = newTable[int, Quest]()

proc slotStageLevel*(man: QuestManager, quest: Quest): int =
    for v in man.slotQuests:
        if v.questId == quest.id:
            return v.stage

proc slotStageLevel*(man: QuestManager, target: BuildingId): int =
    for v in man.slotQuests:
        let q = man.questById(v.questId)
        if not q.isNil and q.tasks[0].target == target.int:
            return v.stage

proc slotStageSkipCost*(man: QuestManager, quest: Quest): int =
    result = quest.skipPrice

# should be removed, probably
proc totalStageLevel*(man: QuestManager): int =
    for v in man.slotQuests:
        result += v.stage

proc getIDForTask*(quest: Quest): string =
    let task = quest.tasks[0]
    var xpReward: int64
    var target = ""

    if task.target.BuildingId != noBuilding:
        target = $task.target.BuildingId & "_"
    result = $task.taskType & "_" & target & $task.progresses[0].total & "_" & $(sharedQuestManager().slotStageLevel(quest)) & "_" & $task.difficulty

import preferences

proc proceedQuestPreferences*(quest: Quest): int = # returns how many quests and dailies were completed since quest started
    let state = $quest.id & SINCE_QUESTS_OPENED
    if hasGameState(state, ANALYTICS_TAG):
        result = getIntGameState(state, ANALYTICS_TAG)
        removeGameState(state, ANALYTICS_TAG)

    for item in sharedPreferences().pairs:
        if item.key.contains(SINCE_QUESTS_OPENED):
            var k = item.key
            k.removeSuffix("_" & ANALYTICS_TAG)
            saveNewCountedEvent(k)

proc parseTasks*(jTasks: JsonNode, id:int): seq[Task]=
    result = @[]

    for t in jTasks:
        var task = new(Task)
        let biTarget = t[$qtfObject].getInt().BuildingId
        task.progresses = @[]

        for tp in t[$qtfProgress]:
            var taskP = new(TaskProgress)
            taskP.current = tp[$qtfCurrentProgress].getBiggestInt().uint64
            taskP.total = tp[$qtfTotalProgress].getBiggestInt().uint64
            taskP.index = tp[$qtfProgressIndex].getInt().uint
            task.progresses.add(taskP)

        task.target          = parseEnum[BuildingId](t[$qtfObject].getStr()).int
        task.taskType        = parseQuestTaskType(t[$qtfType].getStr(), id)
        task.icon            = getTaskIcon(task.taskType, task.target.BuildingId)
        task.difficulty      = t[$qtfDifficulty].getInt().DailyDifficultyType
        result.add(task)

proc questFromJson(jQuest: JsonNode): Quest=
    let qid = jQuest[$qfId].getInt()
    let qkind = jQuest[$qfKind].getInt().QuestKind

    var tasks = parseTasks(jQuest[$qfTasks], qid)
    let name = genTaskName(tasks[0].taskType, tasks[0].target.BuildingId)
    var desc: seq[QuestDesc]

    if qkind == QuestKind.Story:
        var locKey = $qid
        if "config" in jQuest:
            locKey = jQuest["config"]["name"].str
        desc = @[(locKey & "_DESC", true)]
    else:
        let totalP = tasks[0].progresses[0].total.int64
        desc = genTaskDescription(tasks[0].taskType, tasks[0].target.BuildingId, totalP)

    let quest = createQuest(qkind, name, desc, tasks, jQuest[$qfId].getInt(), jQuest[$qfStatus].getInt().QuestProgress)
    quest.icon = iconForQuest(tasks[0].target.BuildingId, tasks[0].taskType)
    if qkind == QuestKind.Daily and "rews" in jQuest:
        quest.DailyQuest.rewards = jQuest["rews"].getRewards()

    if "skipPrice" in jQuest:
        quest.skipPrice = jQuest["skipPrice"].getInt()

    result = quest


proc proceedQuests*(man: QuestManager, jn: JsonNode, reload: bool = false)=
    if "queseq" notin jn: return

    let qRev = hash($jn["queseq"])

    if man.questRevision == qRev:
        if not findActiveState(SlotFlowState).isNil:
            pushBack(UpdateTaskProgresState)
        elif not currentNotificationCenter().isNil:
            currentNotificationCenter().postNotification(QUESTS_UPDATED_EVENT)
        return

    man.questRevision = qRev

    for q in jn["queseq"]:
        let qid = q[$qfId].getInt()
        let qkind = q[$qfKind].getInt().QuestKind
        var oldStatus, updStatus = QuestProgress.None
        var quest: Quest
        if qkind == QuestKind.Story:
            quest = man.quests.getOrDefault(qid)
        else:
            quest = man.daily.getOrDefault(qid)

        if quest.isNil:
            quest = questFromJson(q)

            if quest.kind == QuestKind.Story and quest.id notin man.preferences.story:
                if not hasGameState($quest.id & SINCE_QUESTS_OPENED, ANALYTICS_TAG):
                    var initVal: int
                    setGameState($quest.id & SINCE_QUESTS_OPENED, initVal, ANALYTICS_TAG)
        else:
            updStatus = q[$qfStatus].getInt().QuestProgress
            oldStatus = quest.status

            if quest.status != updStatus:
                quest.status = updStatus

                if quest.status == QuestProgress.GoalAchieved or quest.completed():
                    if not currentNotificationCenter().isNil:
                        currentNotificationCenter().postNotification("QUEST_COMPLETED", newVariant(quest))

            var tasks = parseTasks(q[$qfTasks], quest.id)
            let task = q[$qfTasks][0]
            if quest.kind != QuestKind.Story:
                quest.description = genTaskDescription(tasks[0].taskType, tasks[0].target.BuildingId, tasks[0].progresses[0].total.int64)
                quest.icon = iconForQuest(tasks[0].target.BuildingId, tasks[0].taskType)

            quest.tasks = tasks

        let user = currentUser()

        if "config" in q:
            let jConf = q["config"]
            quest.config = parseQuestConfig(q["config"])

        if qkind == QuestKind.Story:
            man.quests[qid] = quest
            # info "add story ", qid

            if quest.id notin man.preferences.story:
                let state = newFlowState(NewQuestBarFlowState, newVariant(quest))
                pushBack(state)

            if not quest.isNil and quest.completed() and quest.id notin man.preferences.completed:
                quest.showCompleted = true

                man.preferences.completed.add(quest.id)
        else:
            man.daily[qid] = quest
            # info "add daily ", qid
            if not quest.isNil and quest.completed() and quest.id notin man.preferences.completed:
                if findFlowState(CompleteTaskFlowState).isNil:
                    let cte = newFlowState(CompleteTaskFlowState, newVariant(quest))
                    pushBack(cte)

                man.preferences.completed.add(quest.id)

                let id = $(quest.getIDForTask())
                if not hasGameState(id, ANALYTICS_TAG):
                    let stage = sharedQuestManager().slotStageLevel(quest)
                    let spinsNumber = getCountedEvent(SPINS_PER_TASK & "_" & $stage)
                    let task = quest.tasks[0]

                    removeGameState(SPINS_PER_TASK & "_" & $stage, ANALYTICS_TAG)
                    sharedAnalytics().task_complete(spinsNumber, task.progresses[0].total.int64, $task.difficulty, $task.taskType & "_" & $task.target.BuildingId, task.target.BuildingId, stage)
                    setGameState($id, true, ANALYTICS_TAG)

                # ANALYTICS
                if quest.id == QUEST_GEN_START_ID and not isAnalyticEventDone(FIRST_QUEST1_COMPLETE):
                    startCountQuestWindowsAnalytics = false
                    questWindowCounterAnalytics = 0
                    backToCityInFirstQuest = false
                    startCountSpinsInFirstQuestAnalytics = true
                    setGameState($FIRST_QUEST1_COMPLETE, true, ANALYTICS_TAG)

            # ANALYTICS
            if not quest.isNil and quest.id == QUEST_GEN_START_ID and quest.status == QuestProgress.InProgress:
                startFirstTask10TimesSpinAnalytics()

        man.preferences.addQuest(quest)

        if oldStatus != updStatus and quest.kind == QuestKind.Story:
            let state = newFlowState(MapQuestUpdateFlowState, newVariant(quest))
            pushBack(state)

    man.preferences.serialize()
    if not findActiveState(SlotFlowState).isNil:
        pushBack(UpdateTaskProgresState)
    elif not currentNotificationCenter().isNil:
        currentNotificationCenter().postNotification(QUESTS_UPDATED_EVENT)

    man.slotQuests = @[]
    if "slotQuests" in jn:
        for k,v in jn["slotQuests"]:
            let sq = new SlotQuest
            sq.stage = v["s"].getInt()
            sq.questId = v["q"].getInt()
            man.slotQuests.add(sq)


proc isQuestFinished*(qm: QuestManager, config: QuestConfig): bool =
    let ind = config.id - 1
    if ind > -1:
        if ind < currentUser().questsState.len and currentUser().questsState[ind]:
            return true


template isQuestFinished*(config: QuestConfig): bool =
    sharedQuestManager().isQuestFinished(config)


proc isQuestCompleted*(qm: QuestManager, config: QuestConfig): bool =
    if qm.isQuestFinished(config):
        return true

    for q in qm.activeStories():
        if q.config.id == config.id:
            if q.status >= QuestProgress.Completed:
                return true
            return false

template isQuestCompleted*(config: QuestConfig): bool =
    sharedQuestManager().isQuestCompleted(config)

proc isQuestCompleted*(qm: QuestManager, name: string): bool =
    for config in qm.questConfigs:
        if config.name == name:
            return qm.isQuestCompleted(config)

proc uncompletedDeps*(qc: QuestConfig): seq[QuestConfig]=
    result = @[]
    let qm = sharedQuestManager()
    for qi in qc.deps:
        let q = qm.questConfigs[qi - 1]
        if not qm.isQuestCompleted(q):
            result.add(q)
