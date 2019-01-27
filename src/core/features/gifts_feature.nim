import times, sequtils, json
import core / zone
import shared / game_scene
import nimx / notification_center
import quest / quests


type GiftsFeature* = ref object of Feature
    hasGifts: bool
    giftsCount: int

proc newGiftsFeature*(): Feature =
    GiftsFeature()

proc hasGifts*(f: GiftsFeature): bool = f.hasGifts
proc giftsCount*(f: GiftsFeature): int = f.giftsCount

method updateState*(feature: GiftsFeature, jn: JsonNode) =
    if "giftsCount" in jn:
        let giftsCount = jn["giftsCount"].getInt()

        feature.hasGifts = giftsCount > 0
        feature.hasBonus = feature.hasGifts
        feature.giftsCount = giftsCount
        feature.dispatchActions()

addFeature(Gift, newGiftsFeature)
