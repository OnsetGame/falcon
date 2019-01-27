import times, sequtils, json

import falconserver / map / building / builditem
import core / zone
import tournaments / tournament
import utils / [timesync, helpers]
import nimx / timer

type TournamentsFeature* = ref object of Feature
    lastTournaments: seq[Tournament]

proc newTournamentsFeature*(): Feature =
    TournamentsFeature()

proc nearestTournamentStartTime*(feature:TournamentsFeature, onlyFree:bool = false): float =
    result = -1.0
    for t in feature.lastTournaments:
        if findZone(t.slotName).isActive:
            let isTutorialTournament = t.endDate < 0
            let endDateChecked = isTutorialTournament or serverTime() < t.endDate
            if t.startDate > 0 and serverTime() < t.startDate and endDateChecked:
                if result < 0.0 or result > t.startDate:
                    if onlyFree:
                        if t.entryFee == 0:
                            result = t.startDate
                    else:
                        result = t.startDate

proc lastActiveTournamentEndTime*(feature:TournamentsFeature, onlyFree:bool = false): float =
    result = -1.0
    for t in feature.lastTournaments:
        if findZone(t.slotName).isActive:
            let isTutorialTournament = t.endDate < 0
            let endDateChecked = isTutorialTournament or serverTime() < t.endDate
            if t.endDate > 0 and serverTime() > t.startDate and endDateChecked:
                if result < 0.0 or result < t.endDate:
                    if onlyFree:
                        if t.entryFee == 0:
                            result = t.endDate
                    else:
                        result = t.endDate

proc activeTournaments(feature:TournamentsFeature, onlyFree:bool = false): seq[Tournament] =
    result = newSeq[Tournament]()
    for t in feature.lastTournaments:
        let isTutorialTournament = t.endDate < 0
        let endDateChecked = isTutorialTournament or serverTime() < t.endDate
        if serverTime() > t.startDate and endDateChecked:
            if findZone(t.slotName).isActive:
                if onlyFree:
                    if t.entryFee == 0:
                        #showDebugInfo(t)
                        result.add(t)
                else:
                    #showDebugInfo(t)
                    result.add(t)

proc hasActiveTournament*(feature:TournamentsFeature): bool =
    result = feature.activeTournaments().len > 0

proc hasFreeTournament*(feature:TournamentsFeature): bool =
    result = feature.activeTournaments(true).len > 0

method updateState*(feature: TournamentsFeature, jn: JsonNode) =
    if "tournaments" in jn:
        #echo jn["tournaments"].pretty()
        feature.lastTournaments = parseTournamentsFromResponse(jn["tournaments"])
        feature.dispatchActions()

addFeature(Tournaments, newTournamentsFeature)
