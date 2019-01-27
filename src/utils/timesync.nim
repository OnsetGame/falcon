## Module that implements client-side responsibility for time syncing
import strutils
import times

type
    TimeSyncError* = ref object of Exception
        ## Error of syncing time with server

    TimeSync = ref object
        ## Client-side time synchronizer
        synchronized: bool   # Equals to true when initial
                             # sync was performed.
        diff: float64        # Difference between server and local
                             # time.

let
    synchronizer: TimeSync = TimeSync(synchronized: false, diff: 0.0)
        ## Zero diff between server and client
        ## Calculated as :
        ## GlobalServerTimeDiff = serverTime - epochTime()

proc raiseTimeSyncError*(msg: string) =
    ## Raise error when something was wrong with time syncing.
    ## For debug use primarily.
    let errTimeSync = new(TimeSyncError)
    errTimeSync.msg = msg
    raise errTimeSync

proc serverTime*(): float64 =
    ## Return current server time
    if synchronizer.synchronized:
        return epochTime() + synchronizer.diff
    else:
        raiseTimeSyncError("You have tried to call serverTime() with uninitialized synchronizer")
        return 0.0

proc localTime*(): float64 = epochTime()
    ## Return client's local time

proc syncTime*(serverTime: float64) =
    synchronizer.synchronized = true
    synchronizer.diff = serverTime - epochTime()
    ## Sync time. Sets difference between local time and server time

proc timeSynchronized*(): bool =
    return synchronizer.synchronized

proc timeLeft*(endTime: float64): float =
    ## @arg `endTime`: End time is a time of an event came from server.
    ## Returns server-aware time left before something happens.
    if synchronizer.synchronized:
        return endTime - (epochTime() + synchronizer.diff)
    else:
        raiseTimeSyncError("You have tried to call timeLeft() with uninitialized synchronizer")

proc timeFrom*(startTime: float64): float =
    if synchronizer.synchronized:
        return serverTime() - startTime
    else:
        raiseTimeSyncError("You have tried to call timeFrom() with uninitialized synchronizer")

proc timeSyncInfo*(): string =
    ## Returns human-readable debug info related to time synchronizer.
    if timeSynchronized():
        let
            sTime = serverTime()
            lTime = localTime()
            diff = sTime - lTime
        return "[TIME-SYNC] Server time: $#, Local time: $#, Difference: $#" % [$sTime, $lTime, $diff]
    else:
        return "[TIME-SYNC] Not synchronized. You will receive exceptions trying to use time functions."