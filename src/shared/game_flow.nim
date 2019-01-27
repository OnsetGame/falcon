import logging
import core / notification_center
import shared.director

const GF_NEXT_EVENT* = "GF_NEXT_EVENT"

type GameFlow* = ref object of RootObj
    events: seq[string]
    current: int

proc currentEvent*(gf: GameFlow): string =
    if gf.current <= gf.events.len() and gf.current > 0:
        result = gf.events[gf.current - 1]
    else:
        result = "GF_NOT_STARTED"

proc isStarted*(gf: GameFlow):bool = gf.current > 0

proc postEvent*(gf: GameFlow)=
    let ev_len = gf.events.len
    if gf.current >= ev_len:
        #info "GF: rewind"
        gf.current = 0
    else:
        let ev = gf.events[gf.current]
        #info "GF: nextEvent ", ev
        inc gf.current
        currentNotificationCenter().postNotification(ev)

proc start*(gf: GameFlow)=
    gf.current = 0
    gf.postEvent()

proc nextEvent*(gf: GameFlow)=
    gf.postEvent()

proc newGameFlow*(ev: varargs[string]): GameFlow=
    doAssert(ev.len > 0)
    result.new()
    result.events = @ev
    result.current = 0