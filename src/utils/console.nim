import tables, strutils, typetraits, macros, preferences, json, logging

import nimx.types
import nimx.context
import nimx.matrixes
import nimx.view
import nimx.button
import nimx.text_field
import nimx.formatted_text
import nimx.scroll_view
import nimx.view_event_handling
import nimx.stack_view
import nimx.animation
import nimx.window

type
    ConsoleView* = ref object of View
        textField: TextField
        goBttn: Button
        hintsView: StackView
        logField: TextField
        logScroll: ScrollView
        log: seq[string]
        history: seq[string]
        showAnim: Animation


    GameConsoleLogger = ref object of Logger

var historyIndex = 0
const historyLen = 100

var gConsoleView: ConsoleView
var gConsoleLogger: GameConsoleLogger
var consoleCommands = initTable[string, proc(args: seq[string]):string]()
var consoleHints = newSeq[string]()
var consoleHelp = initTable[string, string]()

method init*(v: ConsoleView, r: Rect) =
    procCall v.View.init(r)

proc doCommand(v: ConsoleView)
proc showHints(v: ConsoleView)

proc removeConsole*() =
    if not gConsoleView.isNil:
        var hideCb = proc() =
            if gConsoleView.isNil: return

            if not gConsoleView.superview.isNil:
                if gConsoleView.superview.subviews.len > 0:
                    discard gConsoleView.superview.subviews[0].makeFirstResponder()
                gConsoleView.removeFromSuperView()
                if not gConsoleView.hintsView.isNil:
                    gConsoleView.hintsView.removeFromSuperView()
            gConsoleView = nil

        if not gConsoleView.showAnim.isNil:
            gConsoleView.showAnim.loopPattern = lpEndToStart
            gConsoleView.window.addAnimation(gConsoleView.showAnim)
            gConsoleView.showAnim.onComplete do():
                hideCb()
        else:
            hideCb()

proc sharedConsole*(): ConsoleView {.inline.} = gConsoleView

proc showConsole*(v: View) =
    removeConsole()

    historyIndex = 0
    var textHeight = 20.0
    var consoleheight = v.frame.height / 3.0
    when defined(android):
        textHeight = 40.0
        consoleheight = 100.0

    let rect = newRect(0,0, v.frame.width, consoleheight)
    gConsoleView = ConsoleView.new(rect)
    let c = gConsoleView
    c.showAnim = newAnimation()
    c.showAnim.numberOfLoops = 1
    c.showAnim.loopDuration = 0.25
    c.showAnim.onAnimate = proc(p: float)=
        # let ep = elasticEaseOut(p, 0.84)
        let ep = p
        if gConsoleView.isNil:
            if not c.showAnim.isNil:
                c.showAnim.cancel()
            return
        c.setFrameOrigin(interpolate(newPoint(0, -consoleheight), newPoint(0, 0), ep))

    # result.autoresizingMask = { afFlexibleMinX, afFlexibleMinY }
    v.window.addAnimation(c.showAnim)
    v.addSubview(c)

    c.log = @[]
    c.textField = newTextField(newRect(10, rect.height - textHeight - 5, rect.width - 80, textHeight))
    c.textField.continuous = true
    c.addSubview(c.textField)
    c.textField.onAction do():
        c.showHints()

    c.goBttn = newButton(c, newPoint(rect.width - 60, rect.height - textHeight - 5), newSize(50, textHeight), "Do")
    c.goBttn.onAction  do():
        c.doCommand()

    c.logField = newLabel(newRect(10, 10, rect.width - 35, rect.height - 40))
    c.logField.formattedText.setTextColorInRange(0, -1, newColor(1.0, 1.0, 1.0, 1.0))

    let logScroll = newScrollView(c.logField)
    logScroll.horizontalScrollBar = nil
    c.addSubview(logScroll)
    c.logScroll = logScroll

    let closeBttn = newButton(c, newPoint(rect.width - 25, 10), newSize(30, 30), "x")
    closeBttn.onAction  do():
        removeConsole()

    if gConsoleLogger.isNil:
        gConsoleLogger.new()
        addHandler(gConsoleLogger)

    discard c.makeFirstResponder()

    c.history = @[]
    if "consoleHistory" in sharedPreferences():
        for l in sharedPreferences()["consoleHistory"]:
            c.history.add(l.str)

proc addLog(v: ConsoleView, log: string) {.inline.} =
    v.log.add(log)
    v.logField.text = v.logField.text & "\n [" & $v.log.len & "]   " & v.log[v.log.len - 1]
    let logSize = newSize(v.logField.frame.width, v.logField.formattedText.totalHeight)
    v.logField.setFrameSize(logSize)
    v.logScroll.scrollToBottom()

method log(logger: GameConsoleLogger, level: Level, args: varargs[string, `$`]) =
    if not gConsoleView.isNil:
        gConsoleView.addLog(args.join())

proc showHints(v: ConsoleView) =
    if not v.hintsView.isNil:
        v.hintsView.removeFromSuperView()

    if v.textField.text.len() == 0:
        return

    v.hintsView = newStackView(newRect(0, v.frame.height + 10, 300, 0))
    v.superview.addSubview(v.hintsView)

    var hints = newSeq[string]()
    for h in consoleHints:
        closureScope:
            let hint = h
            let index = hint.find(v.textField.text)
            if index > -1:
                hints.add(hint)
                let hintBttn = newButton(v.hintsView, newPoint(0, 0), newSize(300, 30), hint)
                hintBttn.onAction  do():
                    var command = hint.strip().split("(", 1)
                    v.textField.text = command[0] & " "
                    v.textField.cursorPosition = v.textField.text.len()

proc doCommand(v: ConsoleView) =
    let text = v.textField.text
    var args = text.splitWhitespace()
    if args.len == 0:
        return
    let command_name = args[0]

    if v.history.len > historyLen:
        v.history.delete(0)

    let idx = v.history.find(text)
    if idx < 0:
        v.history.add(text)
    else:
        v.history.del(idx)
        v.history.insert(text, 0)

    var jHistory = newJArray()
    for hs in v.history:
        jHistory.add(%hs)

    sharedPreferences()["consoleHistory"] = jHistory
    syncPreferences()

    historyIndex = v.history.len - 1

    if args.len() > 1 and args[1] == "?":
        let help = consoleHelp.getOrDefault(command_name)
        if help.len > 0:
            info "help for ", command_name, "\n", help
        else:
            info "Sorry, help for this command doesn't exist"

        v.textField.text = ""
        return

    echo "Do console ", command_name
    let command = consoleCommands.getOrDefault(command_name)
    if not command.isNil:
        args.delete(0)
        info command_name, " -> ", command(args)
        v.textField.text = ""
    else:
        warn "Command not found"

when defined(emscripten):
    import jsbind.emscripten

    proc executeConsoleCommand(name, args: string) {.EMSCRIPTEN_KEEPALIVE.} =
        let command = consoleCommands.getOrDefault(name)
        if not command.isNil:
            echo command(args.splitWhitespace())
        else:
            echo "Command not found"

    proc registerBrowserConsoleCommand(name, hint: string) =
        discard EM_ASM_INT("""
        var n = UTF8ToString($0);
        window[n] = function() {
            _executeConsoleCommand(_nimem_s(n), _nimem_s(Array.prototype.slice.apply(arguments).join(" ")));
        };
        window[n].desc = UTF8ToString($1);
        """, cstring(name), cstring(hint))

template registerConsoleComand*(command: proc(value: seq[string]): string, hint: string, help: string = "") =
    let comandWrapped = proc(args: seq[string]): string =
        result = command(args)
        if result.len == 0:
            result = "done"

    when defined(emscripten):
        mixin registerBrowserConsoleCommand
        registerBrowserConsoleCommand(command.astToStr, hint)

    consoleCommands[command.astToStr] = comandWrapped
    consoleHints.add(hint)
    if help.len > 0:
        consoleHelp[command.astToStr] = help

const arcAnimStem = 0.1
var fromInc = false
var fromAngle = 0.0
var toAngle = 0.01

method draw*(v: ConsoleView, r: Rect) =
    procCall v.View.draw(r)

    let c = currentContext()
    c.strokeWidth = 0
    c.fillColor = newColor(0.0, 0.0, 0.0, 0.7)
    c.drawRect(r)

    c.fillColor = newColor(0.0, 0.0, 0.0, 0.0)
    c.strokeWidth = 2

    let coof = fromAngle / toAngle
    c.strokeColor = newColor((toAngle / 6.28) * 0.25, toAngle / 6.28, coof, 0.3)
    if fromInc:
        fromAngle += arcAnimStem
        if fromAngle >= 6.28:
            fromAngle = 0.0
            fromInc = false
    else:
        toAngle += arcAnimStem
        if toAngle >= 6.28:
            toAngle = 0.01
            fromInc = true

    let radius = v.frame.height * 0.1
    c.drawArc(newPoint(v.frame.width - radius * 2.5, v.frame.height - radius * 2.5), radius, fromAngle, toAngle)

method onTouchEv*(v: ConsoleView, e: var Event): bool =
    result = procCall v.View.onTouchEv(e)

    return true

method onKeyDown*(v: ConsoleView, e: var Event): bool =
    case e.keyCode
    of VirtualKey.Return:
        v.doCommand()
        result = true
    of VirtualKey.E:
        result = false
    of VirtualKey.NonUSBackSlash:
        removeConsole()
        result = true
    else: discard

proc scrollHistory(v: ConsoleView, scroll: int) =
    if v.history.len > 0 and historyIndex < v.history.len:
        v.textField.text = v.history[historyIndex]
        v.textField.cursorPosition = v.textField.text.len()

        historyIndex = historyIndex - scroll
        if historyIndex < 0:
            historyIndex = v.history.len - 1
        elif historyIndex >= v.history.len:
            historyIndex = 0

method onKeyUp*(v: ConsoleView, e: var Event): bool =
    case e.keyCode
    of VirtualKey.NonUSBackSlash, VirtualKey.Backtick:
        discard v.textField.makeFirstResponder()
        result = false
    of VirtualKey.Escape:
        removeConsole()
        result = false
    of VirtualKey.Up:
        v.scrollHistory(1)
    of VirtualKey.Down:
        v.scrollHistory(-1)
    of VirtualKey.PageUp:
        v.logScroll.scrollPageUp()
    of VirtualKey.PageDown:
        v.logScroll.scrollPageDown()
    else: discard

proc add(args: seq[string]): string =
    var v1, v2: int
    if args.len() > 0: v1 = args[0].parseInt()
    if args.len() > 1: v2 = args[1].parseInt()
    let sum = v1 + v2
    result = $sum

proc subtract(args: seq[string]): string =
    var v1, v2: int
    if args.len() > 0: v1 = args[0].parseInt()
    if args.len() > 1: v2 = args[1].parseInt()
    let sum = v1 - v2
    result = $sum

proc print(args: seq[string]): string =
    var res = ""
    for arg in args:
        res = res & " " & arg
    result = res

proc help(args: seq[string]): string=
    let newLine = "\n    "
    result = "All registered commands:" & newLine
    for hint in consoleHints:
        result &= hint & newLine

    result &= "Controls: " & newLine
    result &= "PageUp, PageDown - scroll log pages" & newLine
    result &= "Arrow Up/Down  - scroll log to Top/Bottom" & newLine
    result &= "Return - execute command" & newLine
    result &= "command ? - get command description" & newLine

registerConsoleComand(add, "add (value1, value2: int)")
registerConsoleComand(subtract, "subtract (value1, value2: int)")
registerConsoleComand(print, "print (value1: string)")
registerConsoleComand(help, "help()")
