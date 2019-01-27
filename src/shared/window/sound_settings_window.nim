import rod.rod_types
import rod.node
import rod.component
import rod.component.text_component
import rod.component.ui_component
import rod.component.solid

import nimx.control
import nimx.slider
import nimx.types
import nimx.button
import nimx.matrixes
import nimx.animation
import nimx.font

import utils.sound_manager
import utils.falcon_analytics
import utils.falcon_analytics_helpers
import utils.helpers
import shared.game_scene
import shared.localization_manager
import shared / window / [window_component, button_component, window_manager, alert_window]
import shared.login
import shared.user

import facebook_sdk.facebook_sdk
import facebook_sdk.facebook_login

import platformspecific.android.rate_manager
import platformspecific.webview_manager

type NodeSlider* = ref object of Slider
    dragNode: Node
    debugDraw*: bool
    slideRect: Rect
    callback: proc(v: Coord)

proc valChanged(ns: NodeSlider)=
    if not ns.callback.isNil():
            ns.callback(ns.value)
    let dragX = ns.slideRect.x + ns.value * ns.slideRect.width
    ns.dragNode.positionX = dragX

proc `value=`(ns:NodeSlider, val: Coord)=
    procCall ns.Slider.`value=` val
    ns.sendAction()

proc createNodeSlider*(pn, dn: Node, sr, r: Rect, callback:proc(v: Coord) = nil): NodeSlider {.discardable.} =
    result = new(NodeSlider, r)
    result.dragNode = dn
    result.debugDraw = false
    result.slideRect = sr
    result.callback = callback

    let r = result
    pn.component(UIComponent).view = r
    r.onAction do():
        r.valChanged()

method draw*(s: NodeSlider, r: Rect) =
    if s.debugDraw:
        procCall s.Slider.draw(r)

type SoundSettingsWindow* = ref object of WindowComponent
    enabled*: bool
    buttonClose*: ButtonComponent
    soundGain*: float
    musicGain*: float
    soundGainOnEnter: float
    musicGainOnEnter: float

method onInit*(ssw: SoundSettingsWindow) =
    ssw.enabled = true
    let win = newLocalizedNodeWithResource("common/gui/popups/precomps/settings.json")
    ssw.anchorNode.addChild(win)

    let btnClose = win.findNode("button_close")
    ssw.buttonClose = btnClose.createButtonComponent(newRect(0, 0, 120, 120))
    ssw.buttonClose.onAction do():
        ssw.closeButtonClick()

    let btnConnect = win.findNode("fb_button_04")
    let btnRate = win.findNode("orange_button_07")
    when defined(ios) or defined(android):
        if not currentUser().fbLoggedIn:
            let anim = btnConnect.animationNamed("press")
            let buttonConnect = btnConnect.createButtonComponent(anim, newRect(0,0,300,90))
            buttonConnect.onAction do():
                ingameFacebookLogin() do(token: FacebookAccessToken):
                    ssw.close()
            btnConnect.findNode("facebook_share").component(Text).text = localizedString("SETTINGS_FACEBOOK_CONNECT")
        else:
            btnConnect.removeFromParent()

        if not isRated():
            let buttonRate = btnRate.createButtonComponent(btnRate.animationNamed("press"), newRect(0,0,300,90))
            buttonRate.onAction do():
                sharedAnalytics().wnd_settings_press_rate()
                ssw.close()
                rateApp()
            btnRate.findNode("orange_button_07").findNode("title").component(Text).text = localizedString("SETTINGS_RATE_GAME")
        else:
            btnRate.removeFromParent()
    else:
        btnConnect.removeFromParent()
        btnRate.removeFromParent()

    const sliderRect = newRect(-20, -40, 720, 100)
    const offset = 13.0
    const color = newColor(1.0,0.99,0.64)

    let musicProg = win.findNode("music_progress").newChild("prog")
    musicProg.positionX = offset
    musicProg.positionY = offset
    musicProg.component(Solid).color = color

    let soundProg = win.findNode("sound_progress").newChild("prog")
    soundProg.positionX = offset
    soundProg.positionY = offset
    soundProg.component(Solid).color = color

    let scene = win.sceneView.GameScene
    let r = ssw
    sharedAnalytics().wnd_settings_open(scene.name)
    createNodeSlider(musicProg, win.findNode("music_drag"), newRect(596, 609, 660, 4), sliderRect, proc(v: Coord)=
        # ANALYTYCS
        setCurrMusicGainAnalytics(v.float32)

        r.musicGain = v
        scene.soundManager.setMusicGain v
        musicProg.component(Solid).size = newSize(interpolate(0.0, sliderRect.width - 40.0, v), 4)
        discard
        ).value = soundSettings().musicGain
    ssw.musicGainOnEnter = soundSettings().musicGain

    createNodeSlider(soundProg, win.findNode("sound_drag"), newRect(596, 465, 660, 4), sliderRect, proc(v: Coord)=
        # ANALYTYCS
        setCurrSoundGainAnalytics(v.float32)

        r.soundGain = v
        scene.soundManager.setSoundGain v
        soundProg.component(Solid).size = newSize(interpolate(0.0, sliderRect.width - 40.0, v), 4)
        discard
        ).value = soundSettings().soundGain
    ssw.soundGainOnEnter = soundSettings().soundGain
    ssw.setPopupTitle(localizedString("SA_SETTINGS"))
    
    let privacyLabel = win.newChild("Extract label")
    privacyLabel.position = newVector3(960.0 - 125.0, 792)
    let textComp = privacyLabel.component(Text)
    textComp.text = localizedString("PRIVACY_SETTINGS")
    textComp.boundingSize = newSize(250, 40)
    textComp.font = newFontWithFace("Exo2-Black", 24)
    textComp.color = grayColor()
    textComp.horizontalAlignment = haCenter
    privacyLabel.createButtonComponent(newRect(0, 0, 250, 40)).onAction do():
        openPrivacyPolicy()

    # let extractLabel = win.newChild("Extract label")
    # extractLabel.positionX = 453
    # extractLabel.positionY = 792
    # extractLabel.component(Text).text = localizedString("REQUEST_EXTRACT_PERSONAL_DATA")
    # extractLabel.component(Text).boundingSize = newSize(614, 40)
    # extractLabel.component(Text).font = newFontWithFace("Exo2-Black", 24)
    # extractLabel.component(Text).color = grayColor()
    # extractLabel.createButtonComponent(newRect(0, 0, 614, 40)).onAction do():
    #     let alert = sharedWindowManager().show(AlertWindow)
    #     alert.setup do():
    #         alert.setUpTitle("ALERT_ATTENTION")
    #         alert.setUpDescription("ALERT_DELETING_PERSONAL_DATA")

    #         # we invert buttons here, so default button will be green Cancel
    #         alert.setUpBttnOkTitle("ALERT_BTTN_CANCEL")
    #         alert.buttonOk.onAction do():
    #             alert.closeButtonClick()
    #         alert.setUpBttnCancelTitle("ALERT_BTTN_CONFIRM_DELETION")
    #         alert.buttonCancel.onAction do():
    #             openSupportWindow(localizedString("REQUEST_EXTRACT_PERSONAL_DATA"))
    #             alert.closeButtonClick()

    # let hideAdsLabel = win.newChild("Hide ads label")
    # hideAdsLabel.positionX = 1100
    # hideAdsLabel.positionY = 792
    # hideAdsLabel.component(Text).text = localizedString("REQUEST_HIDE_ADS")
    # hideAdsLabel.component(Text).boundingSize = newSize(366, 40)
    # hideAdsLabel.component(Text).font = newFontWithFace("Exo2-Black", 24)
    # hideAdsLabel.component(Text).color = grayColor()
    # hideAdsLabel.createButtonComponent(newRect(0, 0, 366, 40)).onAction do():
    #     openSupportWindow(localizedString("REQUEST_HIDE_ADS"))


method beforeRemove*(gss: SoundSettingsWindow)=
    if gss.enabled:
        let musicChange = (gss.musicGain - gss.musicGainOnEnter) * 100
        let soundChange = (gss.soundGain - gss.soundGainOnEnter) * 100

        sharedAnalytics().wnd_settings_closed(gss.anchorNode.sceneView.name, musicChange.int, soundChange.int)
        gss.enabled = false

    #procCall gss.WindowComponent.onClosed()

registerComponent(SoundSettingsWindow, "windows")
