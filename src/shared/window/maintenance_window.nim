import times, strutils, json
import rod / [node, component]
import rod / component / text_component
import shared / window / [window_component, window_manager, alert_window, button_component]
import shared / [user, localization_manager]
import rod / utils / [json_serializer, json_deserializer]
import rod / tools / serializer
import nimx / [matrixes, animation]
import utils / [ helpers, timesync ]


type MaintenanceWindow* = ref object of AlertWindow
    timeout: float
    countDownNode: Node
    countDownAnimation: Animation


method onInit(w: MaintenanceWindow) =
    procCall w.AlertWindow.onInit()

    w.removeCloseButton()
    w.makeOneButton()
    w.buttonOk.onAction do():
        w.closeButtonClick()

    w.countDownNode = newNode("timer")
    w.anchorNode.findNode("alert_description").parent.addChild(w.countDownNode)

    let title = w.anchorNode.findNode("alert_title")
    w.countDownNode.anchor = title.anchor
    w.countDownNode.position = title.position + newVector3(0.0, 300.0)

    let serializer = Serializer.new()
    let node = title.component(Text).serialize(serializer)
    w.countDownNode.component(Text).deserialize(node, serializer)
    w.countDownNode.component(Text).text = ""


proc checkTimeout*(w: MaintenanceWindow) =
    if w.timeout == 0.0:
        return

    if w.timeout <= epochTime():
        w.setUpTitle("ALERT_MAINTENANCE_IN_PROGRESS_TITLE")
        w.setUpDescription("ALERT_MAINTENANCE_IN_PROGRESS_DESC")

        if not w.buttonOk.isNil:
            w.buttonOk.node.removeFromParent()
            w.buttonOk = nil
        if not w.countDownNode.isNil:
            w.countDownNode.removeFromParent()
            w.countDownNode = nil
        if not w.countDownAnimation.isNil:
            w.countDownAnimation.cancel()
            w.countDownAnimation = nil
    else:
        let time = w.timeout.fromSeconds().local()
        echo localizedString("ALERT_MAINTENANCE_IN_PROGRESS_TITLE2")
        echo time.format("d'/'M")
        echo time.format("hh':'mm")
        w.setUpLocalizedTitle(
            localizedString("ALERT_MAINTENANCE_IN_PROGRESS_TITLE2") % [time.format("M'/'d"), time.format("hh':'mm")]
        )
        w.setUpLocalizedDescription(
            localizedString("ALERT_MAINTENANCE_IN_PROGRESS_DESC2")
        )
        if not w.countDownAnimation.isNil:
            w.countDownAnimation.cancel()
        w.countDownAnimation = newAnimation()
        w.countDownAnimation.onAnimate = proc(p: float) =
            if w.countDownAnimation.isNil:
                return
            if w.timeout <= epochTime():
                w.countDownAnimation.cancel()
                w.countDownAnimation = nil
                w.checkTimeout()
                return

            let interval = (w.timeout - epochTime()).int + 1
            let hours = interval div 3600
            let minutes = (interval - hours * 3600) div 60
            let seconds = interval - hours * 3600 - minutes * 60

            w.countDownNode.component(Text).text =
                (if hours < 10: "0" & $hours else: $hours) & ":" &
                (if minutes < 10: "0" & $minutes else: $minutes) & ":" &
                (if seconds < 10: "0" & $seconds else: $seconds)

        w.countDownNode.addAnimation(w.countDownAnimation)


proc updateTimeout*(w: MaintenanceWindow, timeout: float) =
    w.timeout = timeout
    w.onReady = proc() =
        w.checkTimeout()


method hideStrategy(w: MaintenanceWindow): float =
    if not w.countDownAnimation.isNil:
        w.countDownAnimation.cancel()
    result = procCall w.AlertWindow.hideStrategy()


registerComponent(MaintenanceWindow, "windows")


const openWindowAt = [60'i64 * 60'i64, 30 * 60, 15 * 60, 10 * 60, 5 * 60, 1 * 60, 0]
var windowOpened: array[openWindowAt.len, bool]

proc needMaintenanceShow(seconds: int64): bool =
    if seconds < 0:
        return true

    for i, v in openWindowAt:
        if seconds <= v and not windowOpened[i]:
            windowOpened[i] = true
            result = true

proc openMaintenanceWindowIfNeed*(timeout: float, onClose: proc()) =
    if timeout == 0: #Maintenance completed?
        for i in 0 .. windowOpened.high:
            windowOpened[i] = false
        if not onClose.isNil:
            onClose()
        return

    #haacky shit
    if sharedWindowManager().currentWindow() of MaintenanceWindow:
        if not onClose.isNil:
            onClose()
        return

    if needMaintenanceShow(timeLeft(timeout).int64):
        let win = sharedWindowManager().show(MaintenanceWindow)
        win.onClose = onClose
        win.updateTimeout(timeout)

    elif not onClose.isNil:
        onClose()
