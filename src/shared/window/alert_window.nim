import rod / [node, component, asset_bundle]
import rod / component / text_component

import nimx / [types, matrixes]
import nimx / assets / asset_manager

import shared / localization_manager
import shared / window / [ window_component, button_component ]

import utils.helpers

type AlertWindow* = ref object of AsyncWindowComponent
    path: string
    buttonClose*: ButtonComponent
    buttonOk*: ButtonComponent
    buttonCancel*: ButtonComponent

proc makeOneButton*(g: AlertWindow)=
    let win = g.anchorNode
    win.findNode("button_black").removeFromParent()
    win.findNode("button_green").findNode("title").component(Text).text = localizedString("OOM_OK")
    g.buttonCancel = nil
    win.findNode("button_green").positionX = 800.0

proc setUpLocalizedHeader*(g: AlertWindow, header: string)=
    let win = g.anchorNode
    let n = win.findNode("ALERT_HEAD_TITLE")
    n.component(Text).text = header

proc setUpLocalizedTitle*(g: AlertWindow, title: string)=
    let win = g.anchorNode
    win.findNode("alert_title").component(Text).text = title

proc setUpLocalizedDescription*(g: AlertWindow, desc: string)=
    let win = g.anchorNode
    win.findNode("alert_description").component(Text).text = desc

proc setUpLocalizedBttnOkTitle*(g: AlertWindow, bttn_title: string)=
     g.buttonOk.node.findNode("title").component(Text).text = bttn_title

proc setUpLocalizedBttnCancelTitle*(g: AlertWindow, bttn_title: string)=
     g.buttonCancel.node.findNode("title").component(Text).text = bttn_title

proc setUpHeader*(g: AlertWindow, header_key: string) =
    g.setUpLocalizedHeader localizedString(header_key)

proc setUpTitle*(g: AlertWindow, title_key: string) =
    g.setUpLocalizedTitle localizedString(title_key)

proc setUpDescription*(g: AlertWindow, desc_key: string) =
    g.setUpLocalizedDescription localizedString(desc_key)

proc setUpBttnOkTitle*(g: AlertWindow, bttn_title_key: string) =
    g.setUpLocalizedBttnOkTitle localizedString(bttn_title_key)

proc setUpBttnCancelTitle*(g: AlertWindow, bttn_title_key: string) =
    g.setUpLocalizedBttnCancelTitle localizedString(bttn_title_key)

proc setUpServerMessage*(g: AlertWindow, text: string)=
    g.setUpLocalizedTitle("Message")
    g.setUpLocalizedBttnOkTitle("OK")
    g.setUpLocalizedDescription(text)
    g.makeOneButton()

proc removeCloseButton*(g: AlertWindow) =
    if not g.buttonClose.isNil:
        g.buttonClose.node.removeFromParent()
        g.buttonClose = nil

proc setCancelButtonText*(oom: AlertWindow, text: string) =
    oom.anchorNode.findNode("button_black").findNode("title").component(Text).text = text

proc setOkButtonText*(oom: AlertWindow, text: string) =
    oom.anchorNode.findNode("button_green").findNode("title").component(Text).text = text

method onInit*(oom: AlertWindow) =
    oom.canMissClick = false
    let win = newLocalizedNodeWithResource(oom.path)
    oom.anchorNode.addChild(win)

    win.findNode("alert_description").component(Text).verticalAlignment = vaCenter
    block:
        #TODO: Workaround for broken load of nodes saved to json from editor.
        let n = win.findNode("ALERT_HEAD_TITLE")
        n.position = newVector3(n.position.x, n.position.y - 13.Coord, n.position.z)

    let btnClose = win.findNode("button_close")
    let clAnim = btnClose.animationNamed("press")
    oom.buttonClose = btnClose.createButtonComponent(clAnim, newRect(10,10,100,100))
    oom.buttonClose.onAction do():
        oom.closeButtonClick()

    let btnCancel = win.findNode("button_black")
    btnCancel.findNode("title").component(Text).text = localizedString("ALERT_BTTN_NO")
    oom.buttonCancel = btnCancel.createButtonComponent(newRect(10,10,280,80))

    let btnOk = win.findNode("button_green")
    btnOk.findNode("title").component(Text).text = localizedString("ALERT_BTTN_YES")
    oom.buttonOk = btnOk.createButtonComponent(newRect(10,10,280,80))

method assetBundles*(w: AlertWindow): seq[AssetBundleDescriptor] =
    const BUNDLES = [
        assetBundleDescriptor("alert_window")
    ]

    try:
        w.path = "common/gui/popups/precomps/alert_window"
        discard newLocalizedNodeWithResource(w.path)
    except:
        w.path = "alert_window/precomps/alert_window"
        result = @BUNDLES

registerComponent(AlertWindow, "windows")
