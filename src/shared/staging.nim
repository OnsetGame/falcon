when defined(js) or defined(emscripten):
    import nimx.pathutils
    import strutils
    when defined(stage) or defined(local):
        let isStage* = true
    else:
        let isStage* = getCurrentHref().find("game.onsetgame.com") == -1
else:
    when defined(stage):
        var isStage* = true
    else:
        var isStage* = false
