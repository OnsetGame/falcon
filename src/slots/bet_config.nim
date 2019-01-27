import json

type BetConfig* = tuple
    bets: seq[int]
    serverBet: int
    hardBets: int

proc parseBetConfig*(res: JsonNode): BetConfig=
    result.bets = @[]
    var betsconf = res{"betsConf"}
    if not betsconf.isNil:
        for b in betsconf["allBets"]:
            result.bets.add(b.getInt())
        result.serverBet = betsconf["servBet"].getInt()
        result.hardBets = betsconf["hardBet"].getInt()
