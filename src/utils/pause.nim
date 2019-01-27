import rod / [ node, viewport ]
import nimx / [ animation, timer, window, animation_runner ]

const ACTIVE_SOFT_PAUSE* = "ActiveSoftPause"

type ControlledTimer* = ref object of RootObj
    timer*:Timer
    activeInSoftPause: bool

type PauseManager* = ref object of RootObj
    sceneView: SceneView
    timers*: seq[ControlledTimer]
    paused*: bool

proc newTimer*(pm: PauseManager, interval: float, repeat: bool, callback: proc()): ControlledTimer =
    result.new()
    result.timer = newTimer(interval, repeat, callback)
    pm.timers.add(result)

proc deleteTimer*(pm: PauseManager, ct: ControlledTimer) =
    let i = pm.timers.find(ct)
    if i != -1: pm.timers.del(i)

proc clear*(pm: PauseManager, t: ControlledTimer) =
    t.timer.clear()
    pm.deleteTimer(t)

proc setTimeout*(pm: PauseManager, interval: float, callback: proc(), activeInSoftPause: bool = false): ControlledTimer {.discardable.} =
    var t: Timer

    result.new()
    result.activeInSoftPause = activeInSoftPause

    let res = result
    proc newCallback() =
        pm.deleteTimer(res)
        callback()
    t = newTimer(interval, false, newCallback)
    result.timer = t
    # assert(not pm.isNil, "PauseManager damaged!")
    # assert(not pm.timers.isNil, "PauseManagers timers damaged!")
    pm.timers.add(result)

proc setInterval*(pm: PauseManager, interval: float, callback: proc(), activeInSoftPause: bool = false): ControlledTimer {.discardable.} =
    result.new()
    var t = setInterval(interval, callback)
    result.timer = t
    result.activeInSoftPause = activeInSoftPause
    pm.timers.add(result)

proc newPauseManager*(v: SceneView): PauseManager =
    result.new()
    result.sceneView = v
    result.timers = @[]
    echo "newPauseManager"

proc pause*(pm: PauseManager, soft: bool = false) =
    if pm.paused: return

    pm.sceneView.animationRunner.pauseAnimations(not soft)

    if soft:
        for a in pm.sceneView.animationRunner.animations:
            if a.tag == ACTIVE_SOFT_PAUSE:
                a.resume()

    for t in pm.timers:
        if not (soft and t.activeInSoftPause):
            t.timer.pause()

    pm.paused = true

proc resume*(pm: PauseManager) =
    if not pm.paused: return

    pm.sceneView.animationRunner.resumeAnimations()

    for t in pm.timers:
        t.timer.resume()

    pm.paused = false

proc recreateAnimationRunner(v: SceneView) {.inline.} =
    if not v.window.isNil:
        v.window.removeAnimationRunner(v.animationRunner)
    v.animationRunner = newAnimationRunner()
    if not v.window.isNil:
        v.window.addAnimationRunner(v.animationRunner)

proc invalidate*(pm: PauseManager) =
    for t in pm.timers: t.timer.clear()
    pm.timers.setLen(0)
    pm.sceneView.recreateAnimationRunner()
