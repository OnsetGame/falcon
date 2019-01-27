import sound.sound
import nimx.timer
import nimx.assets.asset_loading
import nimx.assets.asset_manager
import nimx.assets.asset_cache
import tables, strutils, streams, logging

export sound.Sound, sound.play, sound.stop, sound.gain, sound.`gain=`, sound.setLooping, sound.duration

when defined(android):
    import sdl2, jnim
    initSoundEngineWithActivity(cast[jobject](androidGetActivity()))

when defined(js) or defined(emscripten):
    import jsbind
    const soundType = "mp3"

    import nimx.assets.web_url_handler
else:
    var soundTimers = newTable[int, Timer]()
    const soundType = "ogg"

const soundExtension = "." & soundType

when defined(js) or defined(emscripten):
    # Sound already has onComplete in js/emsctipten
    export sound.onComplete
else:
    proc onComplete*(s: Sound, callback: proc()) =
        let k = cast[int](s)
        if not callback.isNil:
            var t: Timer
            t = setTimeout(s.duration) do():
                soundTimers.del(k)
                callback()
            soundTimers[k] = t
        else:
            var t = soundTimers.getOrDefault(k)
            if not t.isNil:
                t.clear()
                soundTimers.del(k)

proc filePathFromUrl(url: string): string =
    when defined(android):
        const urlPrefix = "android_asset://"
    else:
        const urlPrefix = "file://"
    assert(url.startsWith(urlPrefix))
    result = url.substr(urlPrefix.len)


proc soundWithResource*(name: string): Sound =
    var nameWithExt = name
    if not name.endsWith(soundExtension):
        nameWithExt &= "." & soundType

    let am = sharedAssetManager()

    when defined(emscripten) or defined(js):
        result = am.cachedAsset(Sound, nameWithExt)
    else:
        result = am.cachedAsset(nameWithExt, Sound(nil))
        if result.isNil:
            let url = am.urlForResource(nameWithExt)
            when defined(android):
                result = newSoundWithURL(url)
            else:
                let fullPath = filePathFromUrl(url)
                result = newSoundWithFile(fullPath)
            am.cacheAsset(name, result)

when defined(js) or defined(emscripten):
    registerAssetLoader(["mp3", "ogg"]) do(url: string, callback: proc(j: Sound)):
        proc handler(r: JSObj) =
            newSoundWithArrayBufferAsync(cast[ArrayBuffer](r), callback)

        loadJSURL(url, "arraybuffer", nil, nil, handler)
else:
    registerAssetLoader(["mp3", "ogg"]) do(url: string, handler: proc(s: Sound)):
        when defined(android):
            handler(newSoundWithURL(url))
        else:
            let fullPath = filePathFromUrl(url)
            handler(newSoundWithFile(fullPath))
