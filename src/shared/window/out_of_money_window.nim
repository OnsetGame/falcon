import rod.rod_types
import rod.node
import rod.viewport
import rod.component
import rod.component.text_component
import rod.component.ui_component

import nimx.button
import nimx.matrixes
import nimx.animation
import nimx.animation
import nimx.notification_center

import shared.user
import shared.localization_manager
import quest.quest_helpers

import times
import strutils

import falconserver.map.building.builditem

import utils.helpers
import shared.window.window_component
import shared.window.button_component

type OutOfMoneyWindow* = ref object of WindowComponent
    buttonClose*: ButtonComponent
    buttonExchange*: ButtonComponent
    buttonCancel*: ButtonComponent

const icons = ["chips", "parts", "bucks"]

proc makeOneButton(g: OutOfMoneyWindow)=
    let win = g.anchorNode
    win.findNode("button_green").removeFromParent()
    win.findNode("button_black").findNode("title").component(Text).text = localizedString("OOM_OK")
    g.buttonExchange = nil
    win.findNode("button_black").positionX = 820.0

proc setIcon(g: OutOfMoneyWindow, target: string, iar: openarray[string])=
    for ic in iar:
        let i = g.anchorNode.findNode(ic)
        if not i.isNil and ic != target:
            i.removeFromParent()

proc setUpDescription*(g: OutOfMoneyWindow, outOf: string)=
    let win = g.anchorNode
    var key: string

    case outOf
    of "bucks":
        key = "OOM_BUCKS"
    of "chips":
        key = "OOM_CHIPS"
    of "parts":
        key = "OOM_PARTS"

    g.setIcon(outOf, icons)
    win.findNode("oom_alert_title").component(Text).text = localizedFormat("OOM_NOT_ENOUGH", localizedString(key))
    win.findNode("oom_description_0").component(Text).text = localizedFormat("OOM_RUN_OUT", localizedString(key))

    if outOf == "bucks":
        g.makeOneButton()
        win.findNode("oom_description_1").component(Text).text = localizedString("OOM_BUILD_MORE")
        win.findNode("button_black").findNode("title").component(Text).text = localizedString("OOM_STORE")

method onInit*(oom: OutOfMoneyWindow) =
    let win = newLocalizedNodeWithResource("common/gui/popups/precomps/out_of_currency.json")
    oom.anchorNode.addChild(win)

    let btnClose = win.findNode("button_close")
    let clAnim = btnClose.animationNamed("press")
    oom.buttonClose = btnClose.createButtonComponent(clAnim, newRect(10,10,100,100))
    oom.buttonClose.onAction do():
        oom.closeButtonClick()

    let r = oom
    let btnCancel = win.findNode("button_black")
    btnCancel.findNode("title").component(Text).text = localizedString("ALERT_BTTN_NO")
    oom.buttonCancel = btnCancel.createButtonComponent(newRect(10,10,280,80))

    let btnOk = win.findNode("button_green")
    btnOk.findNode("title").component(Text).text = localizedString("ALERT_BTTN_YES")
    oom.buttonExchange = btnOk.createButtonComponent(newRect(10,10,280,80))
    oom.setPopupTitle(localizedString("ALERT_HEAD_TITLE"))

registerComponent(OutOfMoneyWindow, "windows")
