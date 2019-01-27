when defined(js):
    import dom
elif defined(emscripten):
    import jsbind.emscripten
else:
    import sdl2 except Point, Rect, Event

type MessageBoxType* = enum
    Error,
    Warning,
    Information


proc showMessageBox*(title: string, description: string, box_type: MessageBoxType = MessageBoxType.Information, callback: proc() = nil) =
    when defined(js):
        dom.window.alert(title & "\n" & description)
    elif defined(emscripten):
        let titleAndDesc : cstring = title & "\n" & description
        discard EM_ASM_INT("""
            alert(UTF8ToString($0));
        """, titleAndDesc)
    else:
        var sdl_type: uint32 = SDL_MESSAGEBOX_INFORMATION
        case box_type:
        of MessageBoxType.Error:
            sdl_type = SDL_MESSAGEBOX_ERROR
        of MessageBoxType.Warning:
            sdl_type = SDL_MESSAGEBOX_WARNING
        else:
            discard
        discard showSimpleMessageBox(sdl_type, title, description, glGetCurrentWindow())
    if not callback.isNil:
        callback()
