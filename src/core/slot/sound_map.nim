import tables
import nimx.animation
import utils / [ sound_manager, sound ]
import async

type SoundMap* = ref object
    soundManager: SoundManager
    soundMap: Table[string, string]
    activeSounds*: Table[string, FadingSound]
    loopStopMap: Table[string, seq[string]]

proc newSoundMap*(sm: SoundManager): SoundMap =
    result.new()
    result.soundManager = sm
    result.soundMap = initTable[string, string]()
    result.activeSounds = initTable[string, FadingSound]()
    result.loopStopMap = initTable[string, seq[string]]()

proc invalidate*(sm: SoundMap)=
    sm.soundMap.clear()
    sm.activeSounds.clear()
    sm.loopStopMap.clear()

proc remap*(sm: SoundMap, key: string, event: string)=
    sm.soundMap[key] = event

proc cancelLoopAt*(sm: SoundMap, key: string, sounds:seq[string])=
    sm.loopStopMap[key] = sounds

proc playAsync*(sm: SoundMap, key: string): Future[FadingSound] {.async.} =
    let cl = sm.loopStopMap.getOrDefault(key)
    # echo "cancelLoop ", key, " stops ", cl
    for v in cl:
        let s = sm.activeSounds.getOrDefault(v)
        if not s.isNil:
            # echo "STOP ", v
            sm.activeSounds[v] = nil
            s.sound.stop()

    var event = sm.soundMap.getOrDefault(key)
    if event.len == 0:
        event = key

    result = await sm.soundManager.sendEventAsync(event)
    if not result.isNil:
        sm.activeSounds[key] = result

        if not result.looped and not result.sound.isNil:
            result.sound.onComplete do():
                sm.activeSounds[key] = nil

proc playAux(sm: SoundMap, key: string) {.async.} =
    let sound = await sm.playAsync(key)

proc play*(sm: SoundMap, key: string) =
    asyncCheck sm.playAux(key)

proc isActive*(sm: SoundMap, key: string): bool =
    result = not sm.activeSounds.getOrDefault(key).isNil

proc stop*(sm: SoundMap, key: string) =
    let s = sm.activeSounds.getOrDefault(key)
    if not s.isNil:
        sm.soundManager.fadeOut(s, 1.0) do():
            s.sound.stop()
        sm.activeSounds[key] = nil
