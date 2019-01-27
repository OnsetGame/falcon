import tables
import json
import strutils
import sequtils
import algorithm
import random

import falconserver.slot.machine_base_types

const BONUS_INDEX = 1

# const SINGLE_DESTRUCTION* = 1
# const DOUBLE_DESTRUCTION* = 2
# const TRIPLE_DESTRUCTION* = 9
# const FOURTH_DESTRUCTION* = 15
# const FIFTH_DESTRUCTION*  = 30
# const SIXTH_DESTRUCTION*  = 50

const FREESPIN_MIN_START_DESTRUCTION*  = 5
const FREESPIN_MAX_START_DESTRUCTION*  = 9

type
    StageType* = enum
        SpinStage,
        FreeSpinStage,
        BonusStage

    Target* = tuple [
       key: int8,
       val: int8,
       payout: int64
    ]

    BonusResponse* = ref object
        index*  : int8
        targets*: seq[Target]

    Response* = ref object
        stage*  : StageType
        symbols*: seq[int8]
        balance*: int64
        bonuses*: seq[BonusResponse]

        lines*: seq[tuple[index: int64, symbols: int64, payout: int64]]
        payout*: int64
        freespins*: int64
        destructions*: int8
        totalFreespinWin*: int64

proc newBonusResponse*(): BonusResponse =
    result.new()
    result.targets = @[]

proc `==`*(r0, r1: Response): bool =
    if r0.symbols.len != r1.symbols.len: return false
    var i = 0
    while i < r0.symbols.len:
        if r0.symbols[i] == r1.symbols[i]: inc i
        else: return false
    return true

proc `!=`*(r0, r1: Response): bool =
    return not (r0 == r1)

proc hasDestruction*(r: Response): bool =
    result = if r.payout > 0: true else: false

proc canStartBonus*(r: Response): bool =
    var bonusCount = 0.int
    for i in r.symbols:
        if i == BONUS_INDEX:
            inc bonusCount
    if bonusCount >= 3: return true
    else: return false

proc newResponse*(response: JsonNode, destructionsCounter: var int): Response =
    var stage: string
    var stageType: StageType
    var freespinsCount: int64
    var res: JsonNode
    if response.hasKey("stages"):
        res = response["stages"][0]

    if res.hasKey("stage"):
        stage = res["stage"].str

    if response.hasKey("freeSpinsCount"):
        freespinsCount = response["freeSpinsCount"].num

    if stage == "Spin" or stage == "Respin":
        stageType = SpinStage
    elif stage == "Bonus":
        stageType = BonusStage
    elif stage == "FreeSpin" or freespinsCount > 0:
        stageType = FreespinStage

    result.new()
    result.stage = stageType
    result.symbols = newSeq[int8]()
    result.freespins = freespinsCount

    if res.hasKey("ftw"):
        result.totalFreespinWin = res["ftw"].getBiggestInt()

    if res.hasKey("field"):
        var fld = newSeq[int8](res["field"].len)
        var iter = 0
        for j in res["field"].items:
            fld[iter] = j.getInt().int8
            inc iter

        if fld.len > 15 and stageType == SpinStage: # fix for cheats
            fld.delete(0,4)                         # fix for cheats
            fld.delete(fld.len-5,fld.len-1)         # fix for cheats

        result.symbols = fld


    if response.hasKey("chips"):
        result.balance = response["chips"].num

    if stageType == BonusStage:
        result.bonuses = newSeq[BonusResponse]()
        var totalResponsePayout: int64 = 0

        # inc destructionsCounter

        result.destructions = destructionsCounter.int8

        if res.hasKey("rockets"):
            for box in res["rockets"]:
                let bonus = newBonusResponse()

                for cell, targets in box:
                    bonus.index = parseInt($cell).int8

                    for dest, res in pairs targets:
                        let k = res[0].getInt().int8 # target index
                        let v = res[1].getInt().int8 # symbol count in line
                        let p = res[2].getBiggestInt() # payout

                        totalResponsePayout += p

                        bonus.targets.add((k, v, p))

                bonus.targets.sort do(t1, t2: Target) -> int:
                    result = cmp(t1.val, t2.val)
                    if result == 0:
                        result = cmp(t1.payout, t2.payout)

                result.bonuses.add(bonus)

            if res.hasKey("payout"):
                totalResponsePayout = res["payout"].getBiggestInt()
                result.payout = totalResponsePayout
    else:
        if res.hasKey("field"):
            if res.hasKey("lines"):
                for ln in res["lines"]:
                    if ln.hasKey("index") and ln.hasKey("symbols") and ln.hasKey("payout"):
                        let index = ln["index"].num
                        let symbols = ln["symbols"].num
                        let payout = ln["payout"].num
                        result.lines.add((index.int64, symbols.int64, payout.int64))
                        result.payout += payout.int64

            if result.lines.len != 0:
                # case destructionsCounter
                # of 0:
                #     result.destructions = SINGLE_DESTRUCTION
                # of 1:
                #     result.destructions = DOUBLE_DESTRUCTION
                # else: discard

                inc destructionsCounter

                # case destructionsCounter
                # of 3: result.destructions = TRIPLE_DESTRUCTION
                # of 4: result.destructions = FOURTH_DESTRUCTION
                # of 5: result.destructions = FIFTH_DESTRUCTION
                # of 6: result.destructions = SIXTH_DESTRUCTION
                # else: discard

                if destructionsCounter >= FREESPIN_MAX_START_DESTRUCTION:
                    result.destructions = 50
                else:
                    result.destructions = destructionsCounter.int8
            else:
                destructionsCounter = 0





proc newZeroWinResponse*(response: JsonNode): Response =
    result.new()
    result.stage = SpinStage
    result.freespins = 0
    result.totalFreespinWin = 0

    let availableSymbols = @[
        2.int8, #2"Snake"->Dog,
        3,      #3"Glider"->Star,
        4,      #4"Kite"->Fish,
        5,      #5"Flag"->Heart,
        6,      #6"Red",
        7,      #7"Yellow",
        8,      #8"Green",
        9       #9"Blue"
    ]
    var secondColAvailableSymbols = availableSymbols

    result.symbols = newSeq[int8](15)

    for col in 0..<5:
        for row in 0..<3:
            if col <= 1:
                let pid = rand(secondColAvailableSymbols.len - 1)
                result.symbols[col + row * 5] = secondColAvailableSymbols[pid]
                secondColAvailableSymbols.delete(pid)
            else:
                result.symbols[col + row * 5] = rand(availableSymbols)

    if response.hasKey("chips"):
        result.balance = response["chips"].num

    result.destructions = 0
    result.lines = @[]
    result.payout = 0
