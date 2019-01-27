import rod / [node, component]
import rod / component / text_component
import utils / [ timesync ]
import shared / localization_manager
import times, strutils, sequtils
import nimx.timer
import math

type TimerCompState = enum
    notInitialized
    initialized
    completed

type TextTimerComponentParts* = tuple[days: int, hours: (int, string), minutes: (int, string), seconds: (int, string), milliseconds: int]

type TextTimerComponent* = ref object of Component
    mTimeToEnd: float
    mOnComplete: proc()
    mOnUpdate: proc()
    mTextComp: Text
    state*: TimerCompState
    withDays*: bool
    prepareText*: proc(parts: TextTimerComponentParts): string

proc `timeToEnd=`*(c: TextTimerComponent, val: float) =
    c.mTimeToEnd = val
    c.state = initialized

proc timeToEnd*(c: TextTimerComponent): float =
    c.mTimeToEnd

proc onComplete*(c: TextTimerComponent, cb: proc())=
    c.mOnComplete = cb

proc onUpdate*(c: TextTimerComponent, cb: proc())=
    c.mOnUpdate = cb

method init*(c: TextTimerComponent) =
    procCall c.Component.init()
    c.withDays = true
    c.prepareText = proc(parts: TextTimerComponentParts): string =
        if parts.days > 0:
            result = localizedFormat("TIMER_DAYS_ONLY", $parts.days)
        else:
            result = $parts.hours[1] & ":" & parts.minutes[1] & ":" & parts.seconds[1]
        # if parts.days > 0:
        #     result = localizedFormat("TIMER_DAYS", $parts.days, parts.hours[1])
        # elif parts.hours[0] > 0:
        #     result = localizedFormat("TIMER_HOURS", $parts.hours[0], parts.minutes[1])
        # else:
        #     result = localizedFormat("TIMER_MINUTES", $parts.minutes[0], parts.seconds[1])

const SECONDS_IN_MINUTE = 60
const SECONDS_IN_HOUR = SECONDS_IN_MINUTE * 60
const SECONDS_IN_DAY = SECONDS_IN_HOUR * 24

method draw*(c: TextTimerComponent) =
    if not c.mTextComp.isNil and c.state != notInitialized:
        var t = timeLeft(c.mTimeToEnd)

        if t >= 0.0:
            var t_s = t.int
            let milliseconds = ((t - t_s.float) * 1_000).int

            var days = 0
            if c.withDays:
                days = t_s div SECONDS_IN_DAY
                t_s = t_s - days * SECONDS_IN_DAY

            let hours = t_s div SECONDS_IN_HOUR
            #let hhours = if hours < 10: "0" & $hours else: $hours
            let hhours = $hours
            t_s = t_s - hours * SECONDS_IN_HOUR

            let minutes = t_s div SECONDS_IN_MINUTE
            let mminutes = if minutes < 10: "0" & $minutes else: $minutes
            t_s = t_s - minutes * SECONDS_IN_MINUTE

            let seconds = t_s
            let sseconds = if seconds < 10: "0" & $seconds else: $seconds

            let res = (days, (hours, hhours), (minutes, mminutes), (seconds, sseconds), milliseconds)
            c.mTextComp.text = c.prepareText(res)
            if not c.mOnUpdate.isNil:
                c.mOnUpdate()

        elif c.state != completed:
            c.state = completed
            if not c.mOnComplete.isNil:
                c.mOnComplete()

method componentNodeWasAddedToSceneView*(c: TextTimerComponent)=
    c.mTextComp = c.node.componentIfAvailable(Text)

registerComponent(TextTimerComponent, "Falcon")
