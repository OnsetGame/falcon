import json, logging
import falconserver.slot.machine_base_types

type
    MermaidHorizontalPosition* = enum
        posLeft = 0
        posCenterLeft
        posCenterRight
        posRight
        posMiss
        posStand
        horisontalError

    MermaidVerticalPosition* = enum
        posCenter = 0
        posUp
        posDown
        verticalError

    MermaidPosition* = tuple
        horizontal: MermaidHorizontalPosition
        vertical: MermaidVerticalPosition

    StageType* = enum
        SpinStage
        FreeSpinStage
        BonusStage

    WinLineData* = tuple
        index: int64
        symbols: int64
        payout: int64

    Stage* = tuple
        stage: StageType
        symbols: seq[int8]
        lines: seq[WinLineData]
        payout: int64
        bonusResults: seq[int64]
        totalFreespinWin: int64
        jackpot: bool

    Response* = ref object
        mermaidPosition*: seq[MermaidPosition]
        balance*: int64
        freespins*: int
        stages*: seq[Stage]

proc parseMermaidHorizontalPosition(v: JsonNode): MermaidHorizontalPosition =
    case v.getInt():
    of 0: return posLeft
    of 1: return posCenterLeft
    of 2: return posCenterRight
    of 3: return posRight
    of 4: return posMiss
    of 5: return posStand
    else: return horisontalError

proc parseMermaidVerticalPosition(v: JsonNode): MermaidVerticalPosition =
    case v.getInt():
    of 0: return posCenter
    of 1: return posUp
    of 2: return posDown
    else: return verticalError

proc parseStage(jn: JsonNode): Stage =
    if jn.isNil:
        return
    # stage
    if jn.hasKey("stage"):
        let  stage = jn["stage"].str
        if stage == "Spin": result.stage = SpinStage
        elif stage == "Bonus": result.stage = BonusStage
        elif stage == "FreeSpin": result.stage = FreespinStage
    # symbols
    if jn.hasKey("field"):
        if result.stage == BonusStage:
            result.bonusResults = @[]
            for j in jn["field"].items: result.bonusResults.add(j.num)
        else:
            result.symbols = @[]
            for j in jn["field"].items: result.symbols.add(j.getInt().int8)

    # lines
    var payoutTotal: int64 = 0
    if jn.hasKey("lines"):
        result.lines = @[]
        for ln in jn["lines"]:
            if ln.hasKey("index") and ln.hasKey("symbols") and ln.hasKey("payout"):
                result.lines.add((ln["index"].getBiggestInt(), ln["symbols"].getBiggestInt(), ln["payout"].getBiggestInt()))
                payoutTotal += ln["payout"].getBiggestInt()
    # totalFreespinWin
    if jn.hasKey("ftw"):
        result.totalFreespinWin = jn["ftw"].getBiggestInt()
    # payout
    if jn.hasKey("payout"):
        # if result.stage != FreespinStage:
        #     result.payout = jn["payout"].getBiggestInt()
        # else:
        #     result.payout = jn["payout"].getBiggestInt() + payoutTotal
        result.payout = jn["payout"].getBiggestInt() + payoutTotal
    else:
        result.payout = payoutTotal

    # jackpot
    if jn.hasKey("jackpot"):
        result.jackpot = jn["jackpot"].getBool()


proc hasWon*(mp: MermaidPosition): bool =
    if mp.horizontal != posStand and mp.horizontal != posMiss:
        return true
    return false

# var bluePosition = true
# var redPosition = false

proc checkMermaidPosition*(prev: Response, curr: var Response) =

    const REEL_COUNT = 5
    var rowsCounter = 0
    var rowPos = -1
    var scatters = 0
    var bonuses = 0
    for st in curr.stages:
        if st.stage == SpinStage or st.stage == FreeSpinStage:
            for i, el in st.symbols:
                if el == 0: # WILD INDEX
                    if rowPos == -1:
                        rowPos = i
                    inc rowsCounter
                if el == 1: # SCATTER INDEX
                    inc scatters
                if el == 2: # BONUS INDEX
                    inc bonuses

    if (rowsCounter > 0  or scatters >= 3 or bonuses >= 2) and curr.mermaidPosition.len == 0:
        var mp: MermaidPosition
        if (rowPos div REEL_COUNT) == 0:
            mp.vertical = posUp
            if rowsCounter >= REEL_COUNT:
                mp.vertical = posCenter
        else:
            mp.vertical = posDown

        let pos = if rowPos >= REEL_COUNT: rowPos - REEL_COUNT else: rowPos
        case pos:
        of 0: mp.horizontal = posLeft
        of 1: mp.horizontal = posCenterLeft
        of 2: mp.horizontal = posCenterRight
        of 3: mp.horizontal = posRight
        else: mp.horizontal = posMiss

        curr.mermaidPosition = @[mp]

    if prev.mermaidPosition.len <= 1 or curr.mermaidPosition.len <= 1:
        return
    else:
        var currFirstMp = curr.mermaidPosition[0]
        var currSecondMp = curr.mermaidPosition[1]

        var prevFirstMp = prev.mermaidPosition[0]
        var prevSecondMp = prev.mermaidPosition[1]


        # if prevFirstMp.hasWon() and not currFirstMp.hasWon():
        #     currFirstMp.horizontal = posStand


        # if prevSecondMp.hasWon() and not currSecondMp.hasWon():
        #     currSecondMp.horizontal = posStand


        # echo "\n BLUE POS: ", bluePosition, "\n RED POS ", redPosition, "\n"

        curr.mermaidPosition = @[currFirstMp, currSecondMp]

# import json
# var data: seq[string] = @[]
# var index = -1
# data.add(
#     """{"mp":[],"chips":3092480,"fc":5,"stages":[{"stage":"Spin","field":[0,0,5,5,5,0,0,1,1,1,4,5,6,7,8],"lines":[{"index":1,"symbols":5,"payout":3000},{"index":3,"symbols":3,"payout":400},{"index":9,"symbols":3,"payout":600},{"index":11,"symbols":4,"payout":1000},{"index":15,"symbols":3,"payout":600},{"index":16,"symbols":3,"payout":400},{"index":17,"symbols":3,"payout":600},{"index":23,"symbols":3,"payout":400},{"index":24,"symbols":3,"payout":600}],"jackpot":false}],"quests":{"queseq":[],"questate":[],"stage":0,"stageTasks":[100000,100001,100002,100003,100004]},"lvlData":{"level":10,"xpCur":362,"xpTot":43755},"maxBet":6,"serverTime":1500905005.469785}"""
# )
# data.add(
#     """{"mp":[[4,0],[2,1]],"chips":3092480,"fc":5,"stages":[{"stage":"FreeSpin","field":[1,11,0,0,11,6,7,0,0,8,3,12,7,8,7],"lines":[],"jackpot":false,"ftw":0}],"quests":{"queseq":[],"questate":[],"stage":0,"stageTasks":[100000,100001,100002,100003,100004]},"lvlData":{"level":10,"xpCur":362,"xpTot":43755},"maxBet":6,"serverTime":1500905030.006436}"""
# )
# data.add(
#     """{"mp":[[4,0],[4,0]],"chips":3092880,"fc":4,"stages":[{"stage":"FreeSpin","field":[7,7,10,11,6,5,4,7,7,12,12,11,9,10,11],"lines":[{"index":7,"symbols":3,"payout":400}],"jackpot":false,"ftw":400}],"quests":{"queseq":[],"questate":[],"stage":0,"stageTasks":[100000,100001,100002,100003,100004]},"lvlData":{"level":10,"xpCur":362,"xpTot":43755},"maxBet":6,"serverTime":1500905036.195392}"""
# )
# data.add(
#     """{"mp":[[4,0],[4,0]],"chips":3092880,"fc":3,"stages":[{"stage":"FreeSpin","field":[5,11,4,7,9,12,9,1,10,12,1,12,10,9,10],"lines":[],"jackpot":false,"ftw":400}],"quests":{"queseq":[],"questate":[],"stage":0,"stageTasks":[100000,100001,100002,100003,100004]},"lvlData":{"level":10,"xpCur":362,"xpTot":43755},"maxBet":6,"serverTime":1500905041.33823}"""
# )

proc newResponse*(response: JsonNode): Response =
    result.new()

    if response.hasKey("mp"):
        result.mermaidPosition = @[]
        for pos in response["mp"]:
            result.mermaidPosition.add((pos[0].parseMermaidHorizontalPosition, pos[1].parseMermaidVerticalPosition))

    if response.hasKey("chips"):
        result.balance = response["chips"].getBiggestInt()

    if response.hasKey("fc"):
        result.freespins = response["fc"].getInt()

    if response.hasKey("stages"):
        result.stages = @[]
        for stg in response["stages"]:
            result.stages.add(parseStage(stg))

proc debug*(response: Response, lines: seq[Line] = @[]) {.gcsafe.} =
    info "--------------------------RESPONSE--------------------------"
    info "POSITION:    ", response.mermaidPosition
    info "BALANCE:     ", response.balance
    info "FREESPINS:   ", response.freespins
    info "-----------STAGES-----------"
    for i, st in response.stages:
        info "STAGE:       ", st.stage

        template digitize(v: int): string =
            if v < 10: $v & " "
            else: $v

        if st.symbols.len >= 15:
            info "FIELD:       ", digitize(st.symbols[0]), " ", digitize(st.symbols[1]), " ", digitize(st.symbols[2]), " ", digitize(st.symbols[3]), " ", digitize(st.symbols[4])
            info "             ", digitize(st.symbols[5]), " ", digitize(st.symbols[6]), " ", digitize(st.symbols[7]), " ", digitize(st.symbols[8]), " ", digitize(st.symbols[9])
            info "             ", digitize(st.symbols[10]), " ", digitize(st.symbols[11]), " ", digitize(st.symbols[12]), " ", digitize(st.symbols[13]), " ", digitize(st.symbols[14])
        else:
            info "FIELD:       ", st.bonusResults
        if st.lines.len > 0:
            info "LINES:"
        if lines.len != 0:
            for ln in st.lines: info "             ", ln, " ", lines[ln.index.int]
        else:
            for ln in st.lines: info "             ", ln
        info "PAYOUT:      ", st.payout
        info "FR_WIN:      ", st.totalFreespinWin
        info "JACKPOT:     ", st.jackpot
        if i < response.stages.len - 1 :
            info "----------------------------"
