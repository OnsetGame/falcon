import times, sequtils, json
import core / zone
import shared / game_scene
import nimx / notification_center
import quest / quests
import utils / timesync

type ExchangeFeature* = ref object of Feature
    hasDiscountedExchange: bool
    nextDiscountedExchange: float

proc newExchangeFeature*(): Feature =
    ExchangeFeature()

proc hasDiscountedExchange*(f: ExchangeFeature): bool = f.hasDiscountedExchange
proc nextDiscountedExchange*(f: ExchangeFeature): float = f.nextDiscountedExchange

method updateState*(feature: ExchangeFeature, jn: JsonNode) =
    if "exchangeChips" in jn and "nextDiscountedExchange" in jn:
        let nextDiscountedExchange = jn["nextDiscountedExchange"].getFloat() + epochTime() - jn["serverTime"].getFloat()

        feature.hasDiscountedExchange = jn["exchangeChips"].getInt() == 0 or timeLeft(nextDiscountedExchange) < 0.0
        feature.hasBonus = feature.hasDiscountedExchange
        feature.nextDiscountedExchange = nextDiscountedExchange
        feature.dispatchActions()

addFeature(Exchange, newExchangeFeature)
