import
    sound, nimx.animation, nimx.window, nimx.timer, rod.viewport, preferences, json, random, times,
    tables, logging, nimx.assets.asset_loading

import nimx.assets.json_loading
import async

export sound

const
    DEFAULT_AMBIENT_FADE_TIME = 2.0
    DEFAULT_MUSIC_FADE_TIME = 4.0
    SOUND_SETTINGS_PREF_KEY = "soundSettings"
    SOUND_GAIN_KEY = "soundGain"
    MUSIC_GAIN_KEY = "musicGain"
    AMBIENT_GAIN_KEY = "ambientGain"

type
    SoundSettingsType* = enum
        ssSoundGain
        ssMusicGain
        ssAmbientGain

    SoundSettings* = ref object of RootObj
        soundGain*: float
        musicGain*: float
        ambientGain*: float
        jsonData: JsonNode

    FadingSound* = ref object of RootObj
        sound*: Sound
        fade*: Animation
        looped*: bool
        name*: string

    SoundInfo = tuple[sound: Sound, gain: float]

    EventInfo = object
        path: string
        delay, fadeTime: float
        trackType: string
        looped: bool
        stopedBy: seq[string]

    EventsData = ref object
        data: Table[string, EventInfo]

    SoundManager* = ref object of RootObj
        currentMusicIndex: int
        currentMusic*: FadingSound
        currentAmbient*: FadingSound
        sceneView: SceneView
        sfxList: seq[Sound]
        settings*: SoundSettings
        isActive: bool
        tempSoundStorage: seq[SoundInfo]
        soundGain*, musicGain*: float
        when not defined(js) or not defined(emscripten):
            playListAnim: Animation

        eventsData: EventsData

var soundSettingsInstance: SoundSettings

proc newEventsData(): EventsData =
    result.new()
    result.data = initTable[string, EventInfo]()

proc serialize(ss: SoundSettings)=
    doAssert(not ss.jsonData.isNil, "We need call deserialize first")

    ss.jsonData[SOUND_GAIN_KEY] = %ss.soundGain
    ss.jsonData[MUSIC_GAIN_KEY] = %ss.musicGain
    ss.jsonData[AMBIENT_GAIN_KEY] = %ss.ambientGain
    sharedPreferences()[SOUND_SETTINGS_PREF_KEY] = ss.jsonData
    syncPreferences()

proc deserialize(ss: SoundSettings)=
    ss.jsonData = try: sharedPreferences()[SOUND_SETTINGS_PREF_KEY]
                  except KeyError: nil
    if ss.jsonData.isNil:
        ss.jsonData = newJObject()
        ss.jsonData[SOUND_GAIN_KEY] = %1.0
        ss.jsonData[MUSIC_GAIN_KEY] = %1.0
        ss.jsonData[AMBIENT_GAIN_KEY] = %1.0
        sharedPreferences()[SOUND_SETTINGS_PREF_KEY] = ss.jsonData
        syncPreferences()

    ss.soundGain = ss.jsonData[SOUND_GAIN_KEY].getFloat()
    ss.musicGain = ss.jsonData[MUSIC_GAIN_KEY].getFloat()
    ss.ambientGain = ss.jsonData[AMBIENT_GAIN_KEY].getFloat()

proc soundSettings*(): SoundSettings =
    if soundSettingsInstance.isNil:
        soundSettingsInstance = new SoundSettings
    soundSettingsInstance.deserialize()
    result = soundSettingsInstance

proc setOption*(ss: SoundSettings, sst: SoundSettingsType, val: float)=
    case sst
    of ssSoundGain:
        ss.soundGain = val
    of ssMusicGain:
        ss.musicGain = val
    of ssAmbientGain:
        ss.ambientGain = val
    else:
        info "setAudioSettings: ", sst, " not_implemented"
    ss.serialize()

proc `gain=`*(fs: FadingSound, gain: float) =
    fs.sound.gain = gain

proc gain*(fs: FadingSound) : float =
    result = fs.sound.gain

proc duration*(fs: FadingSound) : float =
    result = fs.sound.duration

proc setLooping*(fs: FadingSound, loop: bool) =
    if not fs.sound.isNil:
        fs.sound.setLooping(loop)
        fs.looped = loop

proc trySetLooping*(fs: FadingSound, loop: bool) =
    if not fs.isNil:
        fs.sound.setLooping(loop)

proc trySetLooping*(s: Sound, loop: bool) =
    if not s.isNil:
        s.setLooping(loop)

proc newSoundManager*(sceneView: SceneView): SoundManager =
    result.new()
    result.currentMusicIndex = -1
    result.sfxList = @[]
    result.settings = soundSettings()
    result.soundGain = soundSettings().soundGain
    result.musicGain = soundSettings().musicGain
    result.sceneView = sceneView
    result.isActive = true
    result.tempSoundStorage = @[]

proc playSound(sm: SoundManager, name: string): Sound =
    result = soundWithResource(name)
    result.play()

proc addFade*(sm: SoundManager, fsound: FadingSound, start: float, to: float, duration: float) =
    fsound.fade = newAnimation()
    fsound.fade.numberOfLoops = 1
    fsound.fade.loopDuration = duration
    fsound.fade.continueUntilEndOfLoopOnCancel = false
    fsound.fade.onAnimate = proc(p: float) =
        fsound.gain = interpolate(start, to, p)
    sm.sceneView.addAnimation(fsound.fade)

proc fadeOut*(sm: SoundManager, fsound: FadingSound, duration: float, cb: proc() = nil) =
    fsound.fade = newAnimation()
    fsound.fade.numberOfLoops = 1
    fsound.fade.loopDuration = duration
    fsound.fade.continueUntilEndOfLoopOnCancel = false

    let sg = fsound.sound.gain

    fsound.fade.onAnimate = proc(p: float) =
        fsound.sound.gain = interpolate(sg, 0.0, p)

    if not cb.isNil:
        fsound.fade.onComplete do():
            cb()

    sm.sceneView.addAnimation(fsound.fade)

proc playSFX*(sm: SoundManager, name: string, gain: float = 1.0): Sound {.discardable.} =
    if sm.isActive:
        result = sm.playSound(name)
        result.gain = gain * sm.settings.soundGain
        if not sm.sfxList.contains(result):
            sm.sfxList.add(result)

proc saveSoundInStorage(sm: SoundManager, sound: Sound) =
    var s: SoundInfo = (sound, sound.gain)
    sm.tempSoundStorage.add(s)
    sound.gain = 0

proc stopAmbient*(sm: SoundManager, fadeTime: float = DEFAULT_MUSIC_FADE_TIME) =
    if not sm.currentAmbient.isNil:
        let ambient = sm.currentAmbient
        sm.addFade(ambient, ambient.gain * sm.settings.soundGain, 0, fadeTime)
        if not sm.currentMusic.isNil:
            sm.addFade(sm.currentMusic, sm.currentMusic.gain, sm.settings.musicGain, fadeTime)
        setTimeout fadeTime, proc() =
            ambient.sound.stop()

        # ambient.fade.onComplete do():
        #     ambient.sound.stop()

        sm.currentAmbient = nil

proc playAmbient*(sm: SoundManager, name: string, musicGain: float = 1.0): FadingSound {.discardable.} =
    if sm.isActive:
        if not sm.currentAmbient.isNil and sm.currentAmbient.name != name:
            sm.stopAmbient()
        if sm.currentAmbient.isNil or sm.currentAmbient.name != name:
            result.new()
            result.sound = sm.playSound(name)
            result.setLooping(true)
            result.name = name
            sm.sfxList.add(result.sound)
            sm.currentAmbient = result
            sm.addFade(sm.currentAmbient, 0,  sm.settings.soundGain, DEFAULT_AMBIENT_FADE_TIME)
            if musicGain < 1.0 and not sm.currentMusic.isNil:
                if not sm.currentMusic.fade.isNil:
                    sm.currentMusic.fade.cancel()
                let newMusicGain = musicGain * sm.settings.musicGain
                sm.addFade(sm.currentMusic, sm.currentMusic.gain, newMusicGain, DEFAULT_MUSIC_FADE_TIME)
        else:
            result = sm.currentAmbient

proc stopMusic*(sm: SoundManager, fadeTime: float = DEFAULT_MUSIC_FADE_TIME) =
    if not sm.currentMusic.isNil:
        let music = sm.currentMusic
        music.sound.onComplete(nil)

        if fadeTime > 0.0:
            sm.addFade(music, music.gain, 0, fadeTime)
            setTimeout fadeTime, proc() =
                music.sound.stop()

            # music.fade.onComplete do():
            #     music.sound.stop()
        else:
            music.sound.stop()

proc stopSFX*(sm: SoundManager, fadeTime: float = DEFAULT_MUSIC_FADE_TIME) =
    for sound in sm.sfxList:
        sound.onComplete(nil)

        if fadeTime > 0.0:
            let fade = FadingSound(sound: sound)
            sm.addFade(fade, sound.gain, 0, fadeTime)
            setTimeout fadeTime, proc() =
                sound.stop()
        else:
            sound.stop()
    sm.sfxList = @[]

proc playMusic*(sm: SoundManager, name: string, fadeTime: float = DEFAULT_MUSIC_FADE_TIME, needFade: bool = true): FadingSound {.discardable.} =
    if sm.isActive:
        let musicGain = sm.settings.musicGain

        if not sm.currentMusic.isNil and sm.currentMusic.name != name:
            sm.stopMusic(fadeTime)

        result.new()
        result.sound = sm.playSound(name)
        result.name = name
        sm.currentMusic = result

        if needFade:
            sm.addFade(result, 0, musicGain, fadeTime)
            sm.currentMusic.gain = 0
        else:
            sm.currentMusic.gain = musicGain

        result = sm.currentMusic

proc playMusicRandomShuffled*(sm: SoundManager, list: seq[string], needFade: bool = true)=
    let playList = list

    sm.currentMusicIndex = rand(list.high)
    var music = sm.playMusic(list[sm.currentMusicIndex], needFade = needFade)
    if not music.isNil and music.duration >= 0.001:
        music.sound.onComplete do():
            if not sm.isNil():
                sm.playMusicRandomShuffled(playList, false)


proc playMusicList*(sm: SoundManager, list: seq[string], fadeTime: float = DEFAULT_MUSIC_FADE_TIME) =
    sm.playMusic(list[sm.currentMusicIndex], fadeTime).gain = sm.musicGain
    sm.currentMusicIndex.inc()
    if sm.currentMusicIndex == list.len:
        sm.currentMusicIndex = 0
    setTimeout(sm.currentMusic.duration - fadeTime, proc() =
        sm.stopMusic(fadeTime)
        sm.playMusic(list[sm.currentMusicIndex])
        )

proc stop*(sm: SoundManager, immediate: bool = true) =
    if immediate:
        sm.stopMusic(0.0)
        sm.stopAmbient(0.0)
    else:
        sm.stopMusic()
        sm.stopAmbient()
    for sound in sm.sfxList:
        sound.stop()
    sm.sfxList = @[]
    sm.isActive = false

proc pauseMusic*(sm: SoundManager) =
    if not sm.currentMusic.isNil:
        proc pause() =
            sm.currentMusic.gain = 0

        if not sm.currentMusic.fade.isNil:
            sm.currentMusic.fade.addTotalProgressHandler(1.0, false, pause)
            sm.currentMusic.fade.cancel()

        sm.currentMusic.gain = 0
        sm.musicGain = 0

proc resumeMusic*(sm: SoundManager) =
    if not sm.currentMusic.isNil:
        proc resume() =
            sm.musicGain = sm.settings.musicGain
            sm.currentMusic.gain = sm.settings.musicGain

        if sm.currentMusic.fade.isNil or sm.currentMusic.fade.finished:
            resume()
        else:
            sm.currentMusic.fade.addTotalProgressHandler(1.0, false, resume)
            sm.currentMusic.fade.cancel()

proc pauseSounds*(sm: SoundManager) =
    for sfx in sm.sfxList:
        sm.saveSoundInStorage(sfx)
    if not sm.currentAmbient.isNil:
        proc pause() =
            sm.saveSoundInStorage(sm.currentAmbient.sound)
        sm.currentAmbient.fade.addTotalProgressHandler(1.0, false, pause)
        sm.currentAmbient.fade.cancel()
    sm.soundGain = 0

proc resumeSounds*(sm: SoundManager) =
    for i, si in sm.tempSoundStorage:
        si.sound.gain = si.gain
    sm.tempSoundStorage = @[]
    sm.soundGain = sm.settings.soundGain

proc pause*(sm: SoundManager) =
    sm.isActive = false
    sm.pauseMusic()
    sm.pauseSounds()

proc resume*(sm: SoundManager) =
    sm.isActive = true
    sm.resumeMusic()
    sm.resumeSounds()

proc start*(sm: SoundManager) =
    sm.isActive = true

proc setMusicGain*(sm: SoundManager, gain: float)=
    sm.soundGain = gain
    if not sm.currentMusic.isNil:
        sm.currentMusic.gain = gain


proc setSoundGain*(sm: SoundManager, gain: float)=
    sm.musicGain = gain
    for s in sm.sfxList:
        s.gain = gain

proc setMuteSound*(sm: SoundManager, disable: bool)=
    if not disable:
        sm.settings.setOption ssSoundGain, 1.0
        sm.resumeSounds()
    else:
        sm.settings.setOption ssSoundGain, 0.0
        sm.pauseSounds()

proc setMuteMusic*(sm: SoundManager, disable: bool)=
    if not disable:
        sm.settings.setOption ssMusicGain, 1.0
        sm.resumeMusic()
    else:
        sm.settings.setOption ssMusicGain, 0.0
        sm.pauseMusic()

proc loadEventsFromAsset(sm: SoundManager, url: string)=
    loadAsset(url) do(d: EventsData, err: string):
        if not d.isNil:
            for k, v in d.data:
                sm.eventsData.data[k] = v

proc loadEvents*(sm: SoundManager, paths: varargs[string]) =
    if sm.eventsData.isNil:
        sm.eventsData = newEventsData()

    for path in paths:
        sm.loadEventsFromAsset("res://" & path & ".sounds")

proc sendEventAsync*(sm: SoundManager, event: string): Future[FadingSound] =
    let rf = newFuture[FadingSound]()
    result = rf

    if sm.isNil:
        warn "SoundManager isNil"
        rf.complete(nil)
        return
    if sm.eventsData.isNil:
        error "SoundManager :: Events data does't exist"
        rf.complete(nil)
        return

    let ei = sm.eventsData.data.getOrDefault(event)
    if ei.path.len > 0:
        let playEvent = proc() =
            var sound: FadingSound
            case ei.trackType
            of "sound":
                sound = FadingSound(sound: sm.playSound(ei.path))

            of "music":
                var fadeTime = ei.fadeTime
                if fadeTime == 0.0:
                    fadeTime = 0.1
                sound = sm.playMusic(ei.path, fadeTime)

            of "ambient":
                sound = sm.playAmbient(ei.path)

            of "sfx":
                let sfx = sm.playSFX(ei.path)
                if not sfx.isNil:
                    sfx.setLooping(ei.looped)
                sound = FadingSound(sound: sfx)

            else: warn "SoundManager :: track type doesn't exist ", ei.trackType

            if not sound.isNil:
                sound.setLooping(ei.looped)

            # echo "sm:play ", event, " suc ", not sound.isNil

            rf.complete(sound)

        if ei.delay > 0.0:
            setTimeout ei.delay, proc() =
                if not sm.isNil:
                    playEvent()
                else:
                    rf.complete(nil)
        else:
            playEvent()
    else:
        warn "SoundManager :: event: ", event, " not found"
        rf.complete(nil)

proc sendEventAux(sm: SoundManager, event: string) {.async.} =
    discard await sm.sendEventAsync(event)

proc sendEvent*(sm: SoundManager, event: string) =
    asyncCheck sm.sendEventAux(event)

proc sendSfxEvent*(sm: SoundManager, event: string): Sound {.discardable.} =
    if sm.eventsData.isNil:
        error "SoundManager :: Events data does't exist"
        return
    let ei = sm.eventsData.data.getOrDefault(event)
    if ei.path.len > 0:
        result = soundWithResource(ei.path)
        result.setLooping(ei.looped)
        result.gain = sm.settings.soundGain
        if not sm.sfxList.contains(result):
            sm.sfxList.add(result)
        result.play()
    else:
        warn "SoundManager :: event: ", event, " not found"

registerAssetLoader(["sounds"]) do(url: string, callback: proc(j: EventsData)):
    loadJsonFromURL(url) do(j: JsonNode):
        let data = newEventsData()
        if not j.isNil:
            for event, val in j:
                var ei: EventInfo
                var jN: JsonNode

                jN = val{"path"}
                if not jN.isNil:
                    ei.path = jN.getStr()
                jN = val{"delay"}
                if not jN.isNil:
                    ei.delay = jN.getFloat()
                else:
                    ei.delay = 0.0
                jN = val{"fadeTime"}
                if not jN.isNil:
                    ei.fadeTime = jN.getFloat()
                else:
                    ei.fadeTime = 0.0
                jN = val{"trackType"}
                if not jN.isNil:
                    ei.trackType = jN.getStr("music")
                jN = val{"looped"}
                if not jN.isNil:
                    ei.looped = jN.getBool()
                else:
                    ei.looped = false

                data.data[event] = ei
        callback(data)

#[
How to use events
First loading list of events. The file should have ".sounds" extension:
v.soundManager.loadEvents("common/sounds/test")

And call events:
v.soundManager.sendEvent("EVENT_1")

Example Json:
{
  "EVENT_1": {
    "path": "common/sounds/common_level_up",
    "delay": 0.5,
    "trackType": "sound",
  },
  "EVENT_2": {
    "path": "common/sounds/common_spin_button",
    "delay": 2.5,
    "trackType": "music",
    "fadeTime": 1.0
  }
}
]#
