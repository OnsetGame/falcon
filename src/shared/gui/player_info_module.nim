import rod.rod_types
import rod.node
import rod.viewport
import rod.component
import rod.component.text_component
import rod.component.ui_component

import nimx.button
import nimx.matrixes
import nimx.animation
import nimx.context
import nimx.notification_center

import math
import gui_module
import gui_module_types
import shared.user
import shared.localization_manager
import nimx.property_visitor

import facebook_sdk.facebook_sdk
import strutils, strformat
import nimx.image
import utils / [ rounded_sprite, progress_bar ]
import rod.component.sprite
import core.net.server
import json
import falconserver.auth.profile_types
import windows / store / store_window
import shared / window / button_component
import core / helpers / boost_multiplier
import node_proxy / proxy

nodeProxy VipAvatarIconProxy:
    level Text {onNode: "vip_level"}
    bttn ButtonComponent {withValue: np.node.createButtonComponent(newRect(-15, -30, 120, 120))}

type GPlayerInfo* = ref object of GUIModule
    mLevel:      int
    mName:       string
    mVip_level:  int
    mExperience: int
    infoButton*: Button
    currentAva:  Node
    roundProg:   ProgressBar
    boostMultiplier: BoostMultiplier
    vipIco: VipAvatarIconProxy

proc `avatar=`*(gp: GPlayerInfo, val: int)
proc `level=`*(gp: GPlayerInfo, val: int)
proc `name=`*(gp: GPlayerInfo, val: string)
proc `experience=`*(gp: GPlayerInfo, val: int)
proc `vipLevel=`*(gp: GPlayerInfo, val: int)

proc `progress=`(gp: GPlayerInfo, val: float32) =
    gp.roundProg.progress = val
    let progText = gp.rootNode.findNode("player_level_progress").getComponent(Text)
    progText.text = &"{val * 100:0.2f}%"

proc createPlayerInfo*(parent: Node): GPlayerInfo =
    result.new()
    result.rootNode = newNodeWithResource("common/gui/ui2_0/player_info.json")
    parent.addChild(result.rootNode)
    result.moduleType = mtPlayerInfo

    result.rootNode.findNode("player_level_progress").positionX = 340.0

    let ava = result.rootNode.findNode("ava")
    let btn = newButton(newRect(0, 0, 200, 200))
    ava.component(UIComponent).view = btn
    btn.hasBezel = false
    result.infoButton = btn

    let roundPN = result.rootNode.findNode("level_progress_bar")
    result.roundProg = roundPN.component(ProgressBar)

    if currentUser().avatar >= 0:
        result.avatar = currentUser().avatar
    result.name = currentUser().name
    result.level = currentUser().level

    result.progress = currentUser().expProgress()

    let r = result

    var roundProgAnim = newAnimation()
    roundProgAnim.loopDuration = 0.25
    roundProgAnim.numberOfLoops = 1

    result.boostMultiplier = result.rootNode.addExpBoostMultiplier(newVector3(405, -10, 0), 0.8)

    sharedNotificationCenter().addObserver(EVENT_LEVELPROG, r.rootNode.sceneView) do(args: Variant):
        let prog = args.get(float)

        let currProg = r.roundProg.progress
        let sw = 5.0
        if currProg != prog:
            roundProgAnim.onAnimate = proc(p:float)=
                if currProg - prog > 0.01:
                    let pr = interpolate(currProg, 1.0 + prog, p)
                    r.progress = if pr < 1.0: pr else: pr - 1.0
                else:
                    r.progress = interpolate(currProg, prog, p)

            r.rootNode.addAnimation(roundProgAnim)

        r.level = currentUser().level

    result.vipIco = VipAvatarIconProxy.new(newNodeWithResource("common/gui/popups/precomps/vip_avatar"))
    result.vipIco.node.positionX = -32.0
    result.vipIco.level.text = $currentUser().vipLevel
    result.vipIco.bttn.onAction do():
        showStoreWindow(StoreTabKind.Vip, "vip_avatar_bttn")
    result.rootNode.addChild(result.vipIco.node)

    r.rootNode.subscribe(currentUser()) do():
        r.vipLevel = currentUser().vipLevel

method onRemoved*(gp: GPlayerInfo)=
    echo "onRemoved GPlayerInfo"
    if not gp.boostMultiplier.isNil:
        gp.boostMultiplier.onRemoved()
        gp.boostMultiplier = nil
    sharedNotificationCenter().removeObserver(EVENT_LEVELPROG, gp.rootNode.sceneView)

proc `avatar=`*(gp: GPlayerInfo, val: int)=
    if not gp.currentAva.isNil:
        gp.currentAva.removeFromParent()

    if val == ppFacebook.int:
        when facebookSupported:
            let avaNode = gp.rootNode.findNode("ava")
            var avatar = avaNode.findNode("FBavatar")
            if avatar.isNil:
                avatar = avaNode.newChild("FBavatar")
                avatar.position = newVector3(6.0, 4.5, 0)
                avatar.scale = newVector3(0.96, 0.96, 0)
            else:
                avatar.removeFromParent()
                avaNode.addChild(avatar)
            avatar.setupFBImage do():
                discard
        else:
            discard

    else:
        let avaNode = gp.rootNode.findNode("ava")
        var avatar = avaNode.findNode("FBavatar")
        if not avatar.isNil:
            avatar.removeFromParent()

        gp.currentAva = newLocalizedNodeWithResource("common/gui/popups/precomps/" & currentUser().avatarResource & ".json")
        avaNode.addChild(gp.currentAva)
        gp.currentAva.scale = newVector3(1.05,1.05,1.0)
        gp.currentAva.positionY = -2.6

proc `level=`*(gp: GPlayerInfo, val: int)=
    gp.mLevel = val
    let node = gp.rootNode.findNode("lvl")
    let textComp = node.component(Text)
    textComp.text = $gp.mLevel

proc `name=`*(gp: GPlayerInfo, val: string)=
    if val == "":
        gp.mName = localizedString("USER_PLAYER")
    else:
        gp.mName = val
    let node = gp.rootNode.findNode("name")
    let textComp = node.component(Text)
    textComp.text = gp.mName

proc `vipLevel=`*(gp: GPlayerInfo, val: int)=
    gp.mVip_level = val
    gp.vipIco.level.text = $val

proc `experience=`*(gp: GPlayerInfo, val: int)=
    gp.mExperience = val
    # let node = gp.rootNode.findNode("exp")
    # let textComp = node.component(Text)
    # textComp.text = $gp.mExperience
