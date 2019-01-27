import times, logging, strutils, sequtils, tables
import falconserver / quest / quest_types
import falconserver / map / building / builditem
import falconserver / common / [game_balance, currency]
import shared / [user]
import core / notification_center
import utils / console
import quests, quest_helpers
import core.net.server

proc updateQuests*(man: QuestManager, callback: proc() = nil)=
    sharedServer().checkUpdates( proc(j: JsonNode)=
        if not callback.isNil:
            callback()
        if "wallet" in j:
            currentUser().updateWallet(j["wallet"])
    )

proc nextGenTime*(man: QuestManager): float =
    result = (man.genTime + 3600.0 * 8.0) - epochTime()
    if result < 0.0:
        result = 0.0
        man.updateQuests()

proc getQuestRewardsAUX(man: QuestManager, id: int, data: JsonNode, cb: proc())=
    sharedServer().sendQuestCommand("getReward", id, data) do(r: JsonNode):
        for v in man.slotQuests:
            if v.questId == id:
                v.questId = 0
        man.deleteQuest(id)

        man.proceedQuests(r["quests"], reload = true)

        if not cb.isNil:
            cb()


proc getQuestRewards*(man: QuestManager, id: int, cb: proc() = nil) =
    getQuestRewardsAUX(man, id, nil, cb)

proc getLevelUpRewards*(man: QuestManager, fromScene: string, cb: proc() = nil)=
    getQuestRewardsAUX(man, -1, %*{"sceneId": fromScene}, cb)


proc acceptQuestAUX(man: QuestManager, id:int, data: JsonNode, cb: proc())=
    var q = man.questById(id)
    if not q.isNil and q.status == QuestProgress.InProgress:
        return

    sharedServer().sendQuestCommand("accept", id, data) do(r: JsonNode):
        man.proceedQuests(r["quests"], reload = true)

        if "wallet" in r:
            currentUser().updateWallet(r["wallet"])

        if not cb.isNil:
            cb()

proc acceptQuest*(man: QuestManager, id:int, cb: proc()=nil)=
    man.acceptQuestAUX(id, nil, cb)

proc acceptTask*(man: QuestManager, id: int, slot: string, cb: proc()=nil)=
    man.acceptQuestAUX(id, %*{"sceneId": slot}, cb)

proc pauseQuest*(man: QuestManager, id:int)=
    sharedServer().sendQuestCommand("pause", id, handler = proc(r: JsonNode)=
        man.proceedQuests(r["quests"], reload = true)
        )


proc speedUpQuest*(man: QuestManager, id: int, cb: proc() = nil)=
    let q = man.questById(id)
    let speedUpPrice = q.speedUpPrice()
    if currentUser().withdraw(bucks = speedUpPrice.int64):
        sharedServer().sendQuestCommand(
            "speedUp", id,
            handler = proc(r: JsonNode)=
                man.proceedQuests(r["quests"], reload = true)

                if "wallet" in r:
                    currentUser().updateWallet(r["wallet"])

                if not cb.isNil:
                    cb()
        )

proc completeQuest*(man: QuestManager, id: int)=
    sharedServer().sendQuestCommand("complete", id, handler = proc(r: JsonNode)=
        man.proceedQuests(r["quests"], reload = true)

        if "wallet" in r:
            currentUser().updateWallet(r["wallet"])
        )

proc generateTask*(man: QuestManager, callBack: proc())=
    sharedServer().sendQuestCommand("generateTask", 0, handler = proc(r: JsonNode)=
        echo "generateTask :", r
        man.proceedQuests(r["quests"], reload = true)

        if "wallet" in r:
            currentUser().updateWallet(r["wallet"])
        if not callBack.isNil:
            callBack()
        )

proc completeQuestWithDeps*(man: QuestManager, id: int, callBack: proc())=
    assert(id - 1 <= man.questConfigs.len, "Incorrect quest id")

    sharedServer().sendQuestCommand("completeQuestWithDeps", id, handler = proc(r: JsonNode)=
        echo "complete quests to ", r
        let targetConfig = man.questConfigs[id - 1
        ]
        let allDeps = man.getAllDeps(targetConfig)
        for dq in allDeps:
            man.deleteQuest(dq.id)
            echo "delete quest by id ", dq.id

        man.deleteQuest(targetConfig.id)

        man.proceedQuests(r["quests"], reload = true)

        if "wallet" in r:
            currentUser().updateWallet(r["wallet"])

        if not callBack.isNil:
            callBack()
    )

proc cheatCompleteTasks*(man: QuestManager, id: int)=
    sharedServer().sendCheatRequest("/cheats/common/quests/complete", %*{"questIndex": id}, proc(r: JsonNode)=
        man.proceedQuests(r["quests"])
        )


proc complete_task*(args: seq[string]): string =
    let quests = sharedQuestManager().readyTasks()
    var id = -1
    if args.len() > 0:
        echo "args ", args
        id = parseInt(args[0])
    else:
        let aq = sharedQuestManager().activeTasks()
        if aq.len() > 0:
            id = aq[0].id
        else:
            return "active quests don't found"

    var body = %*{"machine": "null", "questIndex": id}
    echo "body ", body
    sharedServer().sendCheatRequest("/cheats/quests_complete", body) do(jn: JsonNode):
        echo "complete_task ", jn.pretty()
        info "complete_task ", id
        sharedQuestManager().proceedQuests(jn, true)

registerConsoleComand(complete_task, "complete_task (id: int)")


proc resetCron(args: seq[string]): string=
    var body = %*{"resetCron": true}
    sharedServer().sendCheatRequest("/cheats/reset_cron", body) do(jn: JsonNode):
        sharedQuestManager().updateQuests()
        discard

    result = "resetCron"

registerConsoleComand(resetCron, "resetCron")

proc allTaskTypes(): string=
    result = ""
    for qtt in low(QuestTaskType)..high(QuestTaskType):
        result &= "\n\t - " & $qtt & " (" & getTaskLocaKey(qtt) & ")"

proc generateTask(args: seq[string]): string =
    if args.len != 2:
        return "Incorrect number of arguments " & $args.len

    var target = try: parseEnum[BuildingId](args[0]) except: noBuilding
    var qtt = try: parseQuestTaskType(args[1], 100_500) except: qttLevelUp

    if target == noBuilding:
        return "Bad task target " & args[0] & " try enter one of this:\n\t - " & $dreamTowerSlot & "\n\t - " & $balloonSlot & "\n\t - " & $candySlot
    if qtt == qttLevelUp:
        return "Bad quest task type " & args[1] & " try one of this " & allTaskTypes()

    var body = %*{"target": $target, "qtt": $qtt}
    sharedServer().sendCheatRequest("/cheats/generate_task_for_slot", body) do(jn: JsonNode):
        sharedQuestManager().updateQuests()
        discard

registerConsoleComand(generateTask, "generateTask(target: BuildingId, qtt: QuestTaskType)")

proc reach_quest(args: seq[string]): string =
    if args.len() > 0:
        echo "args ", args
        var body = %*{"quest": args[0]}
        sharedServer().sendCheatRequest("/cheats/reachQuest", body) do(jn: JsonNode):
            currentNotificationCenter().postNotification("UpdateMapState")
    else:
        return "no arguments passed."

registerConsoleComand(reach_quest, "reach_quest (quest: string)")



proc tasks_list(args: seq[string]): string =
    let ready = sharedQuestManager().readyTasks()
    let active = sharedQuestManager().activeTasks()
    template taskInfo(q: Quest) =
        info " id(" & $q.id & "); target (" & getSlotName(q.tasks[0].target.BuildingId) & "); qtt (" & $q.tasks[0].taskType & "); ismaxbet (" & $sharedGameBalance().taskBets[q.tasks[0].difficulty] & "); difficulty (" & $q.tasks[0].difficulty & ");"

    info " - READY - "
    for q in ready:
        taskInfo(q)

    info " - ACTIVE - "
    for q in active:
        taskInfo(q)

    info " --- "

registerConsoleComand(tasks_list, "tasks_list ()")


proc accept_quest(args: seq[string]): string =
    if args.len() > 0:
        echo "args ", args
        var id: int
        try:
            id = parseInt(args[0])
        except:
            return "Error:first argument is not int"
        proc predicate(q: Quest): bool = q.id == id
        let isPendingTask = sequtils.any(sharedQuestManager().readyTasks(), predicate)
        let isActiveTask = sequtils.any(sharedQuestManager().activeTasks(), predicate)
        if isActiveTask:
            return "Task $# already active.".format(id)
        if not isPendingTask:
            return "Task $# isn't ready to be active.\n Ready tasks : $#".format(id, $sharedQuestManager().readyTasks().map(proc(q:Quest):string = $q.id))
        sharedQuestManager().acceptQuest(id)
        return "Task $# accepted!".format(id)
    else:
        return "no arguments passed."

registerConsoleComand(accept_quest, "accept_quest (id: int)")

proc showTasksTypes(args: seq[string]): string =
    result = allTaskTypes()

registerConsoleComand(showTasksTypes, "showTasksTypes()")
