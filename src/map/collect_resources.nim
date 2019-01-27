import falconserver.common.currency
import utils.timesync
import shared.user
import times, json, strutils, math
import nimx.notification_center

import core.zone
import core.features.booster_feature

export Currency

type ResourceCollect* = ref object of RootObj
    lastCollectTime*: float
    resourcePerHour*: int
    fullIncomeHours*: float
    calculatedGainDuration*: float
    calculatedGain*: float
    currency: Currency

type ResourceCollectConfig* = ref object of RootObj
    resources*: seq[ResourceCollect]

var gResourceCollectConfig: ResourceCollectConfig = nil
proc sharedResCollectConfig*(): ResourceCollectConfig =
    if gResourceCollectConfig.isNil:
        gResourceCollectConfig = new(ResourceCollectConfig)
        gResourceCollectConfig.resources = @[]

    result = gResourceCollectConfig

proc confForCurrency(currency: Currency) : ResourceCollect=
    let rcc = sharedResCollectConfig()
    for rc in rcc.resources:
        if rc.currency == currency:
            return rc
    #assert(not result.isNil, "Collectable resource not found")

# proc resourceCapacity*(currency: Currency): int =
#     let rc = confForCurrency(currency)
#     result = rc.resourcePerHour * rc.fullIncomeHours.int


proc resourceCapacityProgress*(currency: Currency): float =
    let rc = confForCurrency(currency)
    if rc.isNil or rc.resourcePerHour == 0:
        return 0.0
    result = clamp(timeFrom(rc.lastCollectTime) / (rc.fullIncomeHours * 60.0 * 60.0), 0.0, 1.0)


proc availableResources*(currency: Currency): int =
    let rc = confForCurrency(currency)

    let booster = findFeature(BoosterFeature).find(btIncome)
    let boosterExpired = if booster.isNil: 0.0  else: booster.expirationTime
    let fullFillDur = rc.fullIncomeHours * 60.0 * 60.0
    let actualFillDur = clamp(timeFrom(rc.lastCollectTime), 0, fullFillDur)
    let calculatedDur = clamp(rc.calculatedGainDuration, 0, actualFillDur)
    let remainingFillDur = actualFillDur - calculatedDur
    let boosteredDur = clamp(boosterExpired - (rc.lastCollectTime + calculatedDur), 0, remainingFillDur)
    let nonBoosteredDur = remainingFillDur - boosteredDur

    result = round(rc.calculatedGain + rc.resourcePerHour.float / 60.0 / 60.0 * (boosteredDur * currentUser().boostRates.inc + nonBoosteredDur)).int
    # echo "DDD lastCollectTime = ", rc.lastCollectTime
    # echo "DDD boosterExpired = ", boosterExpired
    # echo "DDD fullFillDur = ", fullFillDur
    # echo "DDD actualFillDur = ", actualFillDur
    # echo "DDD calculatedDur = ", calculatedDur
    # echo "DDD calculatedGain = ", rc.calculatedGain
    # echo "DDD remainingFillDur = ", remainingFillDur
    # echo "DDD boosteredDur = ", boosteredDur
    # echo "DDD nonBoosteredDur = ", nonBoosteredDur
    # echo "DDD availableResources = ", result
    # echo "DDD rc.resourcePerHour = ", rc.resourcePerHour
    # echo "DDD currentUser().boostRates.inc = ", currentUser().boostRates.inc
    # echo "DDD formula float = ", rc.calculatedGain.float + (rc.resourcePerHour.float / 60.0 / 60.0 * (boosteredDur * currentUser().boostRates.inc + nonBoosteredDur))
    # echo "DDD result = ", result


proc resourcePerHour*(currency: Currency): int =
    let rc = confForCurrency(currency)
    result = rc.resourcePerHour

proc resourceCollectInitialized*(): bool = sharedResCollectConfig().resources.len > 0


proc applyCollectConfig*(jn: JsonNode)=
    let conf = sharedResCollectConfig()
    conf.resources = @[]
    for jrc in jn:
        var rc = new(ResourceCollect)
        rc.lastCollectTime = jrc["lct"].getFloat()
        rc.resourcePerHour = jrc["rph"].getInt()
        rc.fullIncomeHours = jrc["ful"].getFloat()
        rc.currency = parseEnum[Currency](jrc["kind"].getStr(), Chips)
        if "cgd" in jrc:
            rc.calculatedGainDuration = jrc["cgd"].getFloat()
            rc.calculatedGain = jrc["cg"].getFloat()
        else:
            rc.calculatedGainDuration = 0
            rc.calculatedGain = 0
        conf.resources.add(rc)

    # echo "ApplyCollectConfig ", jn
    # echo "available chips ", availableResources(Chips), " of ", resourceCapacity(Chips)
    # echo "available bucks ", availableResources(Bucks), " of ", resourceCapacity(Bucks)
