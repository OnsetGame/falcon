import times, sequtils, json, strutils, math
import core / zone
import shared / user
import shafa / game / booster_types
import nimx / timer
import utils / [ timesync, helpers ]
import wheel_feature

export booster_types


type BoosterData* = ref object
    expirationTime*: float
    durationTime*: float
    kind*: BoosterTypes
    isFree*: bool
    expirationTimer: Timer

type BoosterFeature* = ref object of Feature
    boosters*: seq[BoosterData]

proc newBoosterFeature*(): Feature =
    BoosterFeature()

proc find*(feature: BoosterFeature, kind: BoosterTypes): BoosterData =
    for v in feature.boosters:
        if v.kind == kind:
            return v

proc boostMultiplierText*(bt: BoosterTypes): string =
    case bt
    of btExperience: "x"&formatFloat(currentUser().boostRates.xp, precision = -1)
    of btIncome: "x"&formatFloat(currentUser().boostRates.inc, precision = -1)
    of btTournamentPoints: "x"&formatFloat(currentUser().boostRates.tp, precision = -1)

proc isActive*(bd: BoosterData): bool =
    result = not bd.isNil and bd.expirationTime >= serverTime()

proc `$`*(bd: BoosterData):string =
    let isFree = bd.isFree
    let isActive = bd.isActive()
    var details = ""
    if isActive:
        details = "will expire in "& $bd.expirationTime & " ($#)".format(buildTimerString(bd.expirationTime-serverTime()))
    else:
        if bd.durationTime > 0:
            details = "charged time "& $bd.durationTime & " ($#)".format(buildTimerString(bd.durationTime))
        else:
            details = "expired in "& $bd.expirationTime & " ($#) ago".format(buildTimerString(serverTime() - bd.expirationTime))

    "[BOOSTER $#] isActive:$# $# isFree:$#".format($bd.kind,isActive,details,isFree)

proc printBoosters*(bf: BoosterFeature) =
    for b in bf.boosters:
        echo $b

proc boosterToActivate*(bf: BoosterFeature): tuple[kind:string,isFree:bool] =
    var tag = ""
    var isFree = false
    for b in bf.boosters:
        if b.durationTime > 0.0:
            tag = $b.kind
            if not isFree:
                isFree = b.isFree

    result = (tag, isFree)

proc onBoosterExpired(bf: BoosterFeature, bd: BoosterData) =
    bf.dispatchActions()


proc addExpirationTimer(bf: BoosterFeature, bd: BoosterData) =
    if bd.expirationTimer.isNil:
        let interval = bd.expirationTime - serverTime()
        if interval > 0.0:
            bd.expirationTimer = setTimeout(interval, proc() = bf.onBoosterExpired(bd))

proc updateFromJson(bf: BoosterFeature, jn: JsonNode) =
    for b in bf.boosters:
        if not b.expirationTimer.isNil:
            b.expirationTimer.clear()
            b.expirationTimer = nil

    bf.boosters = newSeq[BoosterData]()
    for k,v in jn:
        let b = new(BoosterData)
        b.kind = parseEnum[BoosterTypes](k)
        b.durationTime = -1.0
        b.expirationTime = -1.0
        if $bfActiveUntil in v:
            b.expirationTime = v[$bfActiveUntil].getFloat()
            bf.addExpirationTimer(b)
        if $bfCharged in v:
            b.durationTime = v[$bfCharged].getFloat()
        if $bfFree in v:
            b.isFree = v[$bfFree].getBool()
        bf.boosters.add(b)

proc isBoosterActive*(feature: BoosterFeature, kind: BoosterTypes): bool =
    for bd in feature.boosters:
        if bd.kind == kind and bd.isActive:
            return true
    return false

proc freeBoosters*(feature: BoosterFeature): int =
    var counter = 0
    for bd in feature.boosters:
        if bd.isFree and bd.durationTime > 0.0:
            counter.inc

    result = counter

method updateState*(feature: BoosterFeature, jn: JsonNode) =
    if "boosters" in jn:
        feature.updateFromJson(jn["boosters"])
        feature.dispatchActions()

addFeature(Boosters, newBoosterFeature)
