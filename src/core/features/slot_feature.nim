import times, sequtils, json

import falconserver / map / building / builditem
import core / zone


type SlotFeature* = ref object of Feature
    totalRounds*: int
    passedRounds*: int
    totalRoundsWin*: int64

proc newSlotFeature*(): Feature =
    SlotFeature()

proc hasFreeRounds*(feature: SlotFeature): bool =
    feature.totalRounds > 0

method updateState*(feature: SlotFeature, jn: JsonNode) =
    if "rounds" in jn:
        feature.totalRounds = jn["rounds"].getInt()
        feature.passedRounds = jn["passed"].getInt()
        feature.totalRoundsWin = jn["reward"].getBiggestInt()
        feature.dispatchActions()

addFeature(Slot, newSlotFeature)


import quest / quests
proc generateFreeRoundsQuestFor*(buildingId: BuildingId): Quest =
    let feature = findZone($buildingId).feature.SlotFeature

    let task = Task.new()
    task.target = buildingId.int
    task.progresses = @[TaskProgress(current: feature.passedRounds.uint64, total: feature.totalRounds.uint64)]
    task.taskType = qttFreeRounds
    
    result.new()
    result.tasks = @[task]
    result.description = @[("QTTFREEROUNDS_DESC", true)]
