import strutils, strtabs, parseutils
import nimx.pathutils

export uriParamsPairs, uriParam

when defined(emscripten):
    import jsbind.emscripten

proc uriParams*(url: string): StringTableRef =
    result = newStringTable()
    for k, v in url.uriParamsPairs:
        result[k] = v

proc reloadWindow*() =
    when defined(js):
        {.emit: "location.reload(true);".}
    elif defined(emscripten):
        discard EM_ASM_INT("location.reload(true);")
