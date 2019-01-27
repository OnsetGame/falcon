import json, logging

import rod / [ rod_types, node, viewport, component ]
import rod / component / [text_component, ui_component, sprite ]
import nimx / [ button, matrixes, text_field, image ]
import core / notification_center

import shared / [ user, localization_manager, director ]
import shared / window / [ window_component, button_component, window_manager ]
import core.net.server
import facebook_sdk.facebook_sdk
import falconserver.auth.profile_types

import utils / [ rounded_sprite, helpers ]

const avatarsCount = 12

type SelectAvatarWindow* = ref object of WindowComponent
    buttonClose: ButtonComponent
    buttonReturn: ButtonComponent
    buttonSelect: ButtonComponent
    selectedAva: int
    userName: string

method onInit*(saw: SelectAvatarWindow) =
    let win = newLocalizedNodeWithResource("common/gui/popups/precomps/profile_select_avatar.json")
    saw.anchorNode.addChild(win)

    saw.setPopupTitle(localizedString("SA_SELECT"))

    let btnClose = win.findNode("button_close")
    saw.buttonClose = btnClose.createButtonComponent(btnClose.animationNamed("press"), newRect(10, 10, 100, 100))
    saw.buttonClose.onAction do():
        saw.closeButtonClick()

    let btnBack = win.findNode("button_back")
    saw.buttonReturn = btnBack.createButtonComponent(newRect(10, 10, 100, 100))
    saw.buttonReturn.onAction do():
        discard sharedWindowManager().show("ProfileWindow")

    let btnSelect = win.findNode("button_black_small")

    btnSelect.findNode("unactive").alpha = 0.0
    btnSelect.findNode("unactive_title").alpha = 0.0
    btnSelect.findNode("title").component(Text).text = localizedString("SA_APPLY")
    saw.buttonSelect = btnSelect.createButtonComponent(newRect(10, 10, 180, 80))
    saw.buttonSelect.onAction do():
        sharedWindowManager().playSound("COMMON_GUI_CLICK")
        if currentUser().avatar != saw.selectedAva or currentUser().name != saw.userName:
            currentUser().avatar = saw.selectedAva
            currentUser().name = saw.userName

            currentNotificationCenter().postNotification("USER_NAME_UPDATED", newVariant(currentUser().name))
            currentNotificationCenter().postNotification("USER_AVATAR_UPDATED", newVariant(currentUser().avatar))

            sharedServer().updateProfile(currentUser().name, currentUser().avatar) do(r: JsonNode):
                discard

    saw.userName = currentUser().name
    let fontRef = win.findNode("Player_Name").component(Text)
    fontRef.node.removeFromParent()

    fontRef.text = currentUser().name
    if fontRef.text.len == 0:
        fontRef.text = localizedString("USER_PLAYER")

    let playerName = win.findNode("playerNameField").newChild("textField")
    let textField = newTextField(newRect(10,10, 800, 60))
    textField.font = fontRef.font
    textField.formattedText = fontRef.mText
    textField.text = fontRef.text
    textField.hasBezel = false
    textField.continuous = true
    textField.backgroundColor.a = 0

    playerName.position = newVector3(0.0, 5.0)

    var userNameTmp = textField.text
    textField.onAction do():
        if textField.text.len < 15:
            saw.userName = textField.text
            userNameTmp = textField.text
        else:
            textField.text = userNameTmp

    playerName.component(UIComponent).view = textField
    saw.selectedAva = currentUser().avatar

    proc findSpriteComponent(n: Node): Sprite=
        result = n.componentIfAvailable(Sprite)
        if result.isNil:
            for ch in n.children:
                result = ch.findSpriteComponent()
                if not result.isNil: break

    let ava_template = win.findNode("ava_template").findNode("customer_teplate").children[0].findSpriteComponent()
    let ava_res = newLocalizedNodeWithResource("common/gui/popups/precomps/" & currentUser().avatarResource & ".json").findSpriteComponent()

    var fbAvatarImage: Image

    template setupDefaultAva() =
        if not ava_template.isNil and not ava_res.isNil:
            ava_template.image = ava_res.image

    template setupFBShifts() =
        when facebookSupported:
            if saw.selectedAva == ppFacebook.int and currentUser().fbLoggedIn:
                ava_template.node.position = newVector3(73, 73, 0)
            else:
                ava_template.node.position = newVector3(80, 80, 0)
        else: discard

    when facebookSupported:
        let fb_res_node = win.findNode("ava_4")
        let fb_res_sprite_node = fb_res_node.findSpriteComponent().node
        fb_res_sprite_node.removeComponent(Sprite)

        fb_res_sprite_node.setupFBImage do():
            var ava_facebook_res = fb_res_sprite_node.component(RoundedSprite)
            fbAvatarImage = ava_facebook_res.cachedImage
            fb_res_node.scale = newVector3(0.95, 0.95, 1.0)

            ava_facebook_res.needUpdateCondition = proc(): bool =
                if ava_facebook_res.node.getGlobalAlpha() >= 0.99:
                    fbAvatarImage = ava_facebook_res.cachedImage
                    if currentUser().avatar == ppFacebook.int:
                        ava_template.image = fbAvatarImage
                    return false
                return true

            if currentUser().avatar == ppFacebook.int:
                ava_template.image = fbAvatarImage
            else:
                setupDefaultAva()
            setupFBShifts()

        # Change name function is disabled for facebook.
        if currentUser().fbLoggedIn:
            win.findNode("gui_enter_name").component(Text).text = "Your name"
    else:
        setupDefaultAva()

    for i in 4..<avatarsCount:
        closureScope:
            var index = i
            let ava_name = "ava_" & $index
            let ava_node = win.findNode(ava_name)
            let btn = newButton(newRect(0, 0, 150, 150))
            btn.hasBezel = false
            ava_node.component(UIComponent).view = btn
            btn.onAction do():
                var img: Image

                if index == 4 and not fbAvatarImage.isNil:
                    saw.selectedAva = ppFacebook.int
                    img = fbAvatarImage
                else:
                    saw.selectedAva = index
                    let sel_sprite = ava_node.findSpriteComponent()
                    img = sel_sprite.image

                if not ava_template.isNil:
                    ava_template.image = img
                    setupFBShifts()
                else:
                    error "ava_template doesn't have component Sprite"

registerComponent(SelectAvatarWindow, "windows")
