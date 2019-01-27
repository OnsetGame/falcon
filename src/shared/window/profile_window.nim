import rod / [ rod_types, node, viewport, component ]
import rod / component / [ text_component, ui_component, solid, sprite ]
import nimx / [ formatted_text, button, matrixes, animation, font, text_field, image ]

import utils / [ falcon_analytics, rounded_sprite, game_state, helpers, icon_component ]
import shared / [ login, user, localization_manager ]
import shared / window / [ window_component, button_component, window_manager, select_avatar_window ]
import core.net.server

import falconserver.auth.profile_types
import falconserver.common.game_balance

import facebook_sdk.facebook_sdk
import facebook_sdk.facebook_login

import json, strutils

type ProfileWindow* = ref object of WindowComponent
    buttonEdit*:   ButtonComponent
    buttonCartel*: ButtonComponent
    buttonClose*:  ButtonComponent
    buttonFB*:     ButtonComponent

proc setUpCurrency(n: Node, currency: string, val: int64, rank: int)=
    let amount = n.findNode("text_amount").component(Text)
    amount.text = formatThousands(val)
    let rankText = n.findNode("text_rank").component(Text)
    rankText.text = if rank > 0: $rank
                           else: localizedString("PI_NA")

    let iconNode = n.findNode("reward_icons_placeholder")
    n.findNode("pvp_icon").alpha = 0.0
    iconNode.component(IconComponent).name = currency

proc setUpProgress(n: Node, title: string, des:string, pFrom, pTo: int)=

    let ti = n.findNode("level_num").component(Text)
    ti.text = title & "  " & localizedString("GUI_PROFILE_LEVEL")

    let length = ti.text.len
    let font = newFontWithFace("Exo2-Regular", 30)

    ti.mText.setTextColorInRange(length - 6, length, newColor(1.0, 0.87, 0.56))
    ti.mText.setFontInRange(length - 6, length, font)


    n.findNode("description").component(Text).text = localizedString(des)
    n.findNode("text_progress").component(Text).text = formatThousands(pFrom) & "/" & formatThousands(pTo)
    n.findNode("text_progress").component(Text).mText.setTextColorInRange(0, -1, newColor(1,1,1))
    n.findNode("text_progress").component(Text).mText.setTextColorInRange(len(formatThousands(pFrom)), -1, newColor(1.0, 0.87, 0.56))

    let coof = pFrom / pTo
    let pe = n.findNode("percents").component(Text)
    pe.text = $((coof) * 100.0).int & "%"

    var prog = n.findNode("progress")
    if prog.isNil:
        prog = n.findNode("ltp_progress_bar_main.png").newChild("progress")
        prog.positionX = 13
        prog.positionY = 13

    let solid = prog.component(Solid)
    solid.size = newSize(coof * 180, 4)
    solid.color = newColor(1.0, 1.0, 1.0)

method onInit*(pw: ProfileWindow) =
    let win = newLocalizedNodeWithResource("common/gui/popups/precomps/profile_window.json")
    pw.anchorNode.addChild(win)
    saveNewCountedEvent(PROFILE_ENTER)
    sharedAnalytics().wnd_profile_open(pw.node.sceneView.name, getIntGameState(PROFILE_ENTER, ANALYTICS_TAG))

    const btnRect = newRect(10, 10, 180, 80)
    let btnCartel = win.findNode("button_cartel")
    btnCartel.findNode("active").alpha = 0.0
    btnCartel.findNode("title").alpha = 0.0
    let unactiveTitle = btnCartel.findNode("unactive_title").component(Text)
    unactiveTitle.text = localizedString("PI_CARTEL")
    pw.buttonCartel = btnCartel.createButtonComponent(btnRect)
    pw.buttonCartel.nxButton.Button.enabled = false

    let btnEdit = win.findNode("button_edit")
    btnEdit.findNode("unactive").alpha = 0.0
    btnEdit.findNode("unactive_title").alpha = 0.0

    pw.buttonEdit = btnEdit.createButtonComponent(btnRect)
    btnEdit.findNode("title").component(Text).text = localizedString("PI_EDIT")
    pw.buttonEdit.onAction do():
        discard sharedWindowManager().show(SelectAvatarWindow)

    let btnClose = win.findNode("button_close")
    pw.buttonClose = btnClose.createButtonComponent(btnClose.animationNamed("press"), newRect(10,10,100,100))
    pw.setPopupTitle(localizedString("PI_PROFILE"))
    pw.buttonClose.onAction do():
        pw.closeButtonClick()

    let user = currentUser()

    let gb = sharedGameBalance()
    var totalExt = 0
    for i in 0 ..< user.level-1:
        totalExt += gb.levelProgress[i].experience
    totalExt += user.currentExp

    let chips_res = win.findNode("chips_resource")
    chips_res.setUpCurrency("chips", user.chips, 0)
    let parts_res = win.findNode("rate_resource")
    parts_res.setUpCurrency("tourPoints", user.tournPoints, 0)
    let vip_res = win.findNode("pvp_resource")
    vip_res.setUpCurrency("vipPoints", user.vipPoints, 0)
    let cp_res = win.findNode("citypoints_resource")
    cp_res.setUpCurrency("citypoints", totalExt, 0)

    let plName = win.findNode("text_playerName").component(Text)
    plName.text = user.name

    let plTitle = win.findNode("text_playerTitle")
    plTitle.component(Text).text = user.title

    let lvlProg = win.findNode("level_prog")
    lvlProg.setUpProgress($user.level, "PI_CITY_POINTS", user.currentExp, user.toLevelExp)

    let vipProg = win.findNode("vip_prog")
    vipProg.removeFromParent()

    proc findSpriteComponent(n: Node): Sprite=
        result = n.componentIfAvailable(Sprite)
        if result.isNil:
            for ch in n.children:
                result = ch.findSpriteComponent()

    let fbbutton = win.findNode("button_facebook")

    when defined(ios) or defined(android):
        if not user.fbLoggedIn:
            fbbutton.createButtonComponent(newRect(10,10,250,80)).onAction do():
                ingameFacebookLogin() do(token: FacebookAccessToken):
                    pw.close()
                    discard sharedWindowManager().show(ProfileWindow)
        else:
            fbbutton.removeFromParent()
    else:
        fbbutton.removeFromParent()

    let ava_sprite = win.findNode("ava_template").findNode("customer_teplate").children[0].findSpriteComponent()
    let ava_res = newLocalizedNodeWithResource("common/gui/popups/precomps/" & user.avatarResource & ".json").findSpriteComponent()

    when facebookSupported:
        if user.avatar == ppFacebook.int and user.fbUserId != "":
            ava_sprite.node.removeComponent(Sprite)
            ava_sprite.node.setupFBImage do():
                discard
        else:
            if not ava_sprite.isNil and not ava_res.isNil:
                ava_sprite.image = ava_res.image
                ava_sprite.node.removeComponent(RoundedSprite)
    else:
        if not ava_sprite.isNil and not ava_res.isNil:
            ava_sprite.image = ava_res.image
            ava_sprite.node.removeComponent(RoundedSprite)

    let profid = win.findNode("player_profile_up.png").newChild("profid")
    let profidText = newFormattedText("ID: " & currentUser().profileId)
    profidText.setFontInRange(0, -1, unactiveTitle.font)
    profidText.setTextColorInRange(0, -1, unactiveTitle.color)
    let tf = newLabel(newRect(0, 0, 800, 40))
    # User cannot select profile id on android device
    when not defined(android):
        tf.selectable = true
    tf.backgroundColor.a = 0
    tf.formattedText = profidText
    profid.component(UIComponent).view = tf
    profid.position = newVector3(580, 65)
    profid.anchor = newVector3(265.0)
    profid.scale.y = -profid.scale.y

proc update*(pi: ProfileWindow)=
    let lvl_node = pi.anchorNode.findNode("level_prog")
    let user = currentUser()
    lvl_node.setUpProgress($user.level, "PI_CITY_POINTS", user.currentExp, user.toLevelExp)

method beforeRemove*(pi: ProfileWindow) =
    sharedAnalytics().wnd_profile_closed(pi.node.sceneView.name)

registerComponent(ProfileWindow, "windows")
