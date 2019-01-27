import tables, sequtils, algorithm, times, json, logging, strutils

import nimx.view
import nimx.button
import nimx.matrixes
import nimx.text_field
import nimx.panel_view

import rod.rod_types
import rod.viewport
import rod.node
import rod.component

import rod.component.ui_component
import nimx.table_view
import nimx.scroll_view
import nimx.notification_center
import nimx.formatted_text

import utils / [timesync, helpers]

import core.net.server

import falconserver.map.building.builditem

import falconserver.tournament.rewards


type Participation* = ref object of RootObj
    id*: string
    profileId*: string
    name*: string
    score*: int
    scoreTime*: float


proc newParticipation(id: string): Participation =
    result.new
    result.id = id


proc parse*(p: Participation, val: JsonNode) =
    let profileId = val{"profileId"}
    if not profileId.isNil:
        p.profileId = profileId.str

    let playerName = val{"playerName"}
    if not playerName.isNil:
        p.name = playerName.str

    p.score = val["score"].getInt()
    p.scoreTime = val["scoreTime"].getFloat()


proc compareRating*(p1, p2: Participation): int {.procvar.} =
    result = cmp(p2.score, p1.score)
    if result == 0:
        result = cmp(p1.scoreTime, p2.scoreTime)


type Tournament* = ref object
    id*: string
    title*: string
    level*: int
    slotName*: string
    bet*: int
    place*: int
    playersCount*: int
    startDate*: float
    endDate*: float
    duration*: float
    isClosed*: bool
    entryFee*: int
    prizeFundChips*: int64
    prizeFundBucks*: int64
    participationId*: string
    boosted*: bool

    sinceTime*: float
    participants*: TableRef[string, Participation]
    sortedParticipants*: seq[Participation]
    rewardPoints*: int
    rewardChips*: int64
    rewardBucks*: int64
    rewardUfoFreeRounds*: int
    rewardIsClaimed*: bool

    finalScore*: int
    actualScoreTime*: float
    scoreGain*: Table[string, int]


proc myScore*(t: Tournament): int =
    if t.participationId.len > 0 and not t.participants.isNil:
        result = t.participants[t.participationId].score
    else:
        result = t.finalScore


proc isPrizePlace*(t: Tournament): bool =
    result = calcRewardCurrency(t.prizeFundChips, t.playersCount, t.place) > 0  or  calcRewardCurrency(t.prizeFundBucks, t.playersCount, t.place) > 0


template findIt*[T](arr: openarray[T], predicate: untyped): int =
    var myresult {.gensym.} = -1
    for i in 0 ..< arr.len:
        template it: T {.inject.} = arr[i]
        if predicate:
            myresult = i
            break
    myresult


proc parseParticipants*(t: Tournament, list: JsonNode) =
    if list.isNil:
        return

    if t.participants.isNil:
        t.participants = newTable[string, Participation]()

    for key, val in list:
        if not t.participants.hasKey(key):
            t.participants[key] = newParticipation(key)
        t.participants[key].parse(val)
        t.sinceTime = max(t.sinceTime, t.participants[key].scoreTime)

    t.playersCount = t.participants.len


proc sortParticipants*(t: Tournament) =
    t.sortedParticipants = toSeq(values(t.participants))
    t.sortedParticipants.sort compareRating
    let pos = t.sortedParticipants.findIt( t.participationId == it.id )
    assert(0 <= pos  and  pos < t.sortedParticipants.len)
    t.place = pos + 1


proc updateFromParticipantsResponse*(t: Tournament, response: JsonNode, preserveScore: bool) =
    var currentScore: int
    var currentScoreTime: float
    if preserveScore:
        let p = t.participants[t.participationId]
        currentScore = p.score
        currentScoreTime = p.scoreTime

    var newEndDate = response{"ends"}
    if not newEndDate.isNil:
        t.endDate = newEndDate.getFloat()
    t.prizeFundChips = response["prize"].getBiggestInt()
    t.prizeFundBucks = response{"prizeBk"}.getBiggestInt()

    t.parseParticipants(response["participants"])
    if not t.boosted:
        t.boosted = response{"boosted"}.getBool(default = false)

    if preserveScore:
        let p = t.participants[t.participationId]
        t.actualScoreTime = p.scoreTime
        p.score = currentScore
        p.scoreTime = currentScoreTime

    t.sortParticipants()


proc parseTournament*(key: string, val: JsonNode): Tournament =
    result.new
    result.id = key
    result.title = val["title"].str
    result.level = val["level"].getInt()
    result.slotName = val["slot"].str
    result.bet = val["bet"].getInt()
    result.playersCount = val["players"].getInt()
    result.startDate = val["starts"].getFloat()
    result.endDate = val{"ends"}.getFloat(default = -1)
    result.duration = val{"duration"}.getFloat(default = result.endDate - result.startDate)
    result.isClosed = val{"closed"}.getBool(default = false)
    result.entryFee = val["fee"].getInt()
    result.prizeFundChips = val["prize"].getBiggestInt()
    result.prizeFundBucks = val{"prizeBk"}.getBiggestInt()
    result.participationId = val{"partId"}.getStr()

    result.finalScore = val{"score"}.getInt()
    result.scoreGain = { "Spin": 0, "Bonus": 0 }.toTable()

    result.parseParticipants(val{"participants"})

    result.rewardPoints = val{"rewpt"}.getInt()
    result.rewardChips = val{"rewch"}.getBiggestInt()
    result.rewardBucks = val{"rewch"}.getBiggestInt()
    result.rewardUfoFreeRounds = val{"rewFR"}.getInt()
    result.boosted = val{"boosted"}.getBool(default = false)
    result.rewardIsClaimed = result.isClosed and result.participationId.len == 0
    let finalPlace = val{"place"}
    if not finalPlace.isNil:
        result.place = finalPlace.getInt()

proc scorePoolName(stage: string): string =
    if stage == "Bonus":
        result = "Bonus"
    else:
        result = "Spin"

proc addPendingScoreGain*(t: Tournament, stage: string, gain: int, scoreTime: float) =
    t.scoreGain[scorePoolName(stage)] += gain
    t.actualScoreTime = scoreTime


proc applyOneScoreGain*(t: Tournament, stage: string) =
    if t.scoreGain[scorePoolName(stage)] > 0:
        let p = t.participants[t.participationId]
        p.scoreTime = t.actualScoreTime
        p.score += 1
        t.scoreGain[scorePoolName(stage)] -= 1
        t.sortParticipants()
    else:
        warn "no tournament score gain to apply"


proc applyWholeScoreGain*(t: Tournament, stage: string) =
    let p = t.participants[t.participationId]
    p.scoreTime = t.actualScoreTime
    p.score += t.scoreGain[scorePoolName(stage)]
    t.scoreGain[scorePoolName(stage)] = 0
    t.sortParticipants()

proc shouldShowInWindow*(t: Tournament): bool =
    if t.endDate < 0:  # tutorial tournament
        return true
    let runTimeLeft = timeLeft(t.endDate)
    let expiredNotClosed = runTimeLeft < 0 and not t.isClosed
    result = not expiredNotClosed


proc parseTournamentsFromResponse*(response: JsonNode): seq[Tournament] =
    result = @[]
    for key, val in response:
        let t = parseTournament(key, val)
        if t.shouldShowInWindow():
            result.add(t)
    result.sort do(t1, t2: Tournament) -> int:
        result = cmp(t1, t2)

proc showDebugInfo*(t: Tournament) =
    echo "t ", t.title
    echo "   timeToStart: ", buildTimerString(timeLeft(t.startDate), "h:m")
    echo "   timeToEnd: ", buildTimerString(timeLeft(t.endDate), "h:m")
    echo "   isFree ", t.entryFee == 0

