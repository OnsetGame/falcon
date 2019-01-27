import times, sequtils, json
import core / zone
import shared / game_scene
import nimx / notification_center
import quest / quests


type WheelFeature* = ref object of Feature
    hasFreeSpin: bool
    nextFreeSpin: float

proc newWheelFeature*(): Feature =
    WheelFeature()

proc hasFreeSpin*(f: WheelFeature): bool = f.hasFreeSpin
proc nextFreeSpinAt*(f: WheelFeature): float = f.nextFreeSpin

method updateState*(feature: WheelFeature, jn: JsonNode) =
    var dispatchActionsRequired = false
    if "prevFreeSpin" in jn and "freeSpinTimeout" in jn:
        let prevFreeSpinTime = jn["prevFreeSpin"].getFloat()
        let serverTime = jn["serverTime"].getFloat()
        let freeSpinTimeout = jn["freeSpinTimeout"].getFloat()

        feature.hasFreeSpin = freeSpinTimeout - (serverTime - prevFreeSpinTime) <= 0
        feature.hasBonus = feature.hasFreeSpin
        feature.nextFreeSpin = prevFreeSpinTime + freeSpinTimeout + (epochTime() - serverTime)
        dispatchActionsRequired = true

    if jn.hasKey("freeSpinsLeft"):
        let freeSpinsLeft = jn["freeSpinsLeft"].getInt()
        feature.hasFreeSpin = feature.hasFreeSpin or freeSpinsLeft > 0
        dispatchActionsRequired = true

    if dispatchActionsRequired:
        feature.dispatchActions()

addFeature(Wheel, newWheelFeature)
