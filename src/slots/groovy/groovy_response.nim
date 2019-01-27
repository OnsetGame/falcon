import json, logging
import falconserver.slot.machine_base_types

type
    StageType* = enum
        SpinStage
        RespinStage
        FreeSpinStage
        BonusStage

    WinLineData* = tuple
        index: int
        symbols: int
        payout: int64

    Stage* = tuple
        stage: StageType
        field: seq[int]
        symbols: seq[seq[int]]
        hidden: seq[int]
        lines: seq[WinLineData]
        payout: int64

        totalSevensFreespinWin: int64
        totalBarsFreespinWin: int64

    Response* = ref object
        balance*: int64

        respins*: int

        sevensFreespins*: int
        barsFreespins*: int
        sevensProgress*: int
        barsProgress*: int

        stages*: seq[Stage]

        winFreespins*: bool
        linesMultiplier*: int

proc parseStage(jn: JsonNode): Stage =
    if jn.isNil:
        return
    # stage
    if jn.hasKey("stage"):
        let  stage = jn["stage"].str
        if stage == "Spin": result.stage = SpinStage
        elif stage == "FreeSpin": result.stage = FreespinStage
        elif stage == "Respin": result.stage = RespinStage
    # symbols
    if jn.hasKey("field"):
        var symbols: seq[int] = @[]
        for j in jn["field"].items: symbols.add(j.getInt())
        result.field = symbols
        result.symbols = @[
            @[symbols[10],symbols[5],symbols[0]],
            @[symbols[11],symbols[6],symbols[1]],
            @[symbols[12],symbols[7],symbols[2]],
            @[symbols[13],symbols[8],symbols[3]],
            @[symbols[14],symbols[9],symbols[4]]
        ]
    # hidden
    if jn.hasKey("hdn"):
        var hidden: seq[int] = @[]
        for j in jn["hdn"].items:
            hidden.add(j.getInt())
        result.hidden = hidden

    # lines
    var payoutTotal: int64 = 0
    if jn.hasKey("lines"):
        result.lines = @[]
        for ln in jn["lines"]:
            if ln.hasKey("index") and ln.hasKey("symbols") and ln.hasKey("payout"):
                result.lines.add((ln["index"].getInt(), ln["symbols"].getInt(), ln["payout"].getBiggestInt()))
                payoutTotal += ln["payout"].getBiggestInt()
    # totalFreespinWin
    if jn.hasKey("sftw"):
        result.totalSevensFreespinWin = jn["sftw"].getBiggestInt()
    if jn.hasKey("bftw"):
        result.totalBarsFreespinWin = jn["bftw"].getBiggestInt()

    # payout
    if jn.hasKey("payout"):
        result.payout = jn["payout"].getBiggestInt() + payoutTotal
    else:
        result.payout = payoutTotal

proc newResponse*(response: JsonNode): Response =
    result.new()

    if response.hasKey("chips"):
        result.balance = response["chips"].getBiggestInt()

    if response.hasKey("rc"):
        result.respins = response["rc"].getInt()

    if response.hasKey("sfc"):
        result.sevensFreespins = response["sfc"].getInt()

    if response.hasKey("bfc"):
        result.barsFreespins = response["bfc"].getInt()

    if response.hasKey("sfp"):
        result.sevensProgress = response["sfp"].getInt()

    if response.hasKey("bfp"):
        result.barsProgress = response["bfp"].getInt()

    if response.hasKey("stages"):
        result.stages = @[]
        for stg in response["stages"]:
            result.stages.add(parseStage(stg))

    if response.hasKey("wfr"):
        result.winFreespins = response["wfr"].getBool()

    if response.hasKey("lmt"):
        result.linesMultiplier = response["lmt"].num.int

proc debug*(response: Response, lines: seq[Line] = @[]) {.gcsafe.} =
    info "--------------------------RESPONSE--------------------------"
    info "BALANCE:          ", response.balance
    info "FREESPINS SEVENS: ", response.sevensFreespins
    info "FREESPINS BAR:    ", response.barsFreespins
    info "SEVENS PROGRESS:  ", response.sevensProgress
    info "BARS PROGRESS:    ", response.barsProgress
    info "-----------STAGES-----------"
    for i, st in response.stages:
        info "STAGE:       ", st.stage

        template digitize(v: int): string =
            if v < 10: $v & " "
            else: $v

        if st.symbols.len >= 5:
            info "FIELD:       ", digitize(st.symbols[0][2])," ", digitize(st.symbols[1][2])," ", digitize(st.symbols[2][2])," ", digitize(st.symbols[3][2]), " ", digitize(st.symbols[4][2])
            info "             ", digitize(st.symbols[0][1]), " ", digitize(st.symbols[1][1]), " ", digitize(st.symbols[2][1]), " ", digitize(st.symbols[3][1]),  " ", digitize(st.symbols[4][1])
            info "             ", digitize(st.symbols[0][0]), " ", digitize(st.symbols[1][0]), " ", digitize(st.symbols[2][0]), " ", digitize(st.symbols[3][0])," ", digitize(st.symbols[4][0])
        if st.lines.len > 0:
            info "LINES:"
        if lines.len != 0:
            for ln in st.lines: info "             ", ln, " ", lines[ln.index.int]
        else:
            for ln in st.lines: info "             ", ln
        info "PAYOUT:        ", st.payout
        info "SEVENS_FR_WIN: ", st.totalSevensFreespinWin
        info "BARS_FR_WIN:   ", st.totalBarsFreespinWin
        if i < response.stages.len - 1 :
            info "----------------------------"
