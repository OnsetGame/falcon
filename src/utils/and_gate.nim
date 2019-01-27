type AndGate* = ref object
    pendingEvents: seq[string]
    handler*: proc()

proc newAndGate*(events: openarray[string], handler: proc() = nil): AndGate =
    result.new()
    result.pendingEvents = @events
    result.handler = handler

proc event*(ag: AndGate, e: string) =
    let i = ag.pendingEvents.find(e)
    if i == -1: return
    # assert(i != -1)
    ag.pendingEvents.del(i)
    if ag.pendingEvents.len == 0 and not ag.handler.isNil: ag.handler()
