import os
import rod / [node, asset_bundle]
import nimx / image
import libsha / sha1


type RemoteImageStatus* {.pure.} = enum
    Ready
    InProgress
    Complete
    Error

const CACHEABLE = not defined(js) and not defined(emscripten) and not defined(windows) and not defined(rodplugin)

type RemoteImage* = ref object
    url*: string

    ignoreCache*: bool
    locked: bool
    status: RemoteImageStatus

    onStart*: proc()
    onProgress*: proc(total, progress, speed: BiggestInt)
    onComplete*: proc(image: Image)
    onError*: proc(err: string)
    onAbort*: proc()

    clearPreviousCallbacks: proc()


proc abort*(c: RemoteImage) =
    if not c.clearPreviousCallbacks.isNil:
        if not c.onAbort.isNil:
            c.onAbort()
        c.clearPreviousCallbacks()
        c.status = RemoteImageStatus.Ready


proc download*(c: RemoteImage, complete: proc(err: string, image: Image) = nil) =
    c.abort()

    if c.url.len == 0:
        return

    if not complete.isNil:
        c.onComplete = proc(image: Image) =
            c.onComplete = nil
            c.onError = nil
            c.onAbort = nil
            complete("", image)
        c.onError = proc(err: string) =
            c.onError = nil
            c.onComplete = nil
            c.onAbort = nil
            complete(err, nil)
        c.onAbort = proc() =
            c.onError = nil
            c.onComplete = nil
            c.onAbort = nil

    var onStart = proc() =
        if not c.onStart.isNil:
            c.onStart()
        c.status = RemoteImageStatus.InProgress
    var onComplete = proc(image: Image) =
        if not c.onComplete.isNil:
            c.onComplete(image)
        c.status = RemoteImageStatus.Complete
    var onError = proc(err: string) =
        if not c.onError.isNil:
            c.onError(err)
        c.status = RemoteImageStatus.Error
    var onProgress = proc(total, progress, speed: BiggestInt) =
        if not c.onProgress.isNil:
            c.onProgress(total, progress, speed)
    var aborted: bool

    c.clearPreviousCallbacks = proc() =
        onStart = nil
        onComplete = nil
        onError = nil
        onProgress = nil
        aborted = true
        c.clearPreviousCallbacks = nil

    if not onStart.isNil:
        onStart()

    when CACHEABLE:
        let sha = sha1hexdigest(c.url)
        let path = cacheDir() / "remoteimage"
        createDir(path)

        if c.ignoreCache:
            discard tryRemoveFile(path / (sha & ".validated"))
            discard tryRemoveFile(path / sha)
        else:
            if fileExists(path / sha):
                if fileExists(path / (sha & ".validated")):
                    if not onComplete.isNil:
                        try:
                            onComplete(imageWithContentsOfFile(path / sha))
                        except:
                            discard tryRemoveFile(path / (sha & ".validated"))
                            discard tryRemoveFile(path / sha)
                            onError("Couldn't open file")
                    return
                else:
                    discard tryRemoveFile(path / sha)

        downloadFile(c.url, path / sha,
            proc(err: string) =
                if err.len != 0:
                    if not onError.isNil:
                        onError(err)
                        return
                
                writeFile(path / (sha & ".validated"), "OK")

                if not onComplete.isNil:
                    try:
                        onComplete(imageWithContentsOfFile(path / sha))
                    except:
                        discard tryRemoveFile(path / (sha & ".validated"))
                        discard tryRemoveFile(path / sha)
                        onError("Couldn't open file")
                    
                if not aborted:
                    c.clearPreviousCallbacks(),
            proc(total, progress, speed: BiggestInt) =
                if not onProgress.isNil:
                    onProgress(total, progress, speed)
        )
    else:
        loadImageFromURL(c.url) do(image: Image):
            if image.isNil:
                if not onError.isNil:
                    onError("Download error: " & c.url)
            else:
                if not onComplete.isNil:
                    onComplete(image)
            if not aborted:
                c.clearPreviousCallbacks()


proc status*(c: RemoteImage): RemoteImageStatus = c.status
proc cacheable*(c: RemoteImage): bool = CACHEABLE

proc newRemoteImage*(url: string = ""): RemoteImage =
    result.new()
    result.url = url
