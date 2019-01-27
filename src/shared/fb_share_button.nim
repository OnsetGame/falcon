import strutils, logging

import facebook_sdk / [facebook_sdk]
import platformspecific / image_sharing
import rod / [node, component]
import rod.component.ae_composition
import nimx / [view_render_to_image, image, animation, class_registry]

import shared.window.button_component
import shared / [ localization_manager, director, game_scene ]

import utils / [ helpers, game_state, falcon_analytics ]

type FBShareButton* = ref object of Component
    autoShare: bool
    checkBoxNode: Node
    shareBttn: ButtonComponent
    isShared: bool
    onShareClick*: proc()

proc shareImage(c: FBShareButton) =
    info "try to share image"
    let gs = currentDirector().gameScene()
    sharedAnalytics().shared_screen_initiate(gs.className())

    c.isShared = true
    c.node.enabled = false
    when facebookSupported and not defined(runAutoTests):
        let image = c.node.sceneView.screenShot()
        fbSDK.shareImage(image, localizedFormat("FACEBOOK_SHARE_IMG_BONUS", "😎"))
    c.node.enabled = true

proc addFBShareButton*(parent: Node = nil): FBShareButton =
    ## Adds share button to `parent`. Old share button will be removed if exists.
    if not parent.isNil:
        let oldShareButton = parent.findNode("fb_share_button")
        if not oldShareButton.isNil:
            oldShareButton.removeFromParent()

    let n = newNode("fb_share_button")
    result = n.addComponent(FBShareButton)
    if not parent.isNil:
        parent.addChild(n)

proc hide*(c: FBShareButton) =
    c.onShareClick = nil
    if not c.isShared and c.autoShare:
        c.shareImage()

    let showWinAnimCompos = c.node.children[0].getComponent(AEComposition)
    let anim = showWinAnimCompos.play("out", @["chek_button"])
    anim.onComplete do():
        c.node.removeFromParent()

proc changeCheckStatus(c: FBShareButton, status: bool) {.inline.} =
    if c.autoShare == status:
        return

    let aeComp = c.checkBoxNode.getComponent(AEComposition)
    if status:
        aeComp.play("press1")
    else:
        aeComp.play("press2")

    c.autoShare = status
    setGameState("FB_BUTTON_CHECK_STATE", c.autoShare, "FALCON")

method componentNodeWasAddedToSceneView*(c: FBShareButton) =
    if not hasGameState("FB_BUTTON_CHECK_STATE", "FALCON"):
        setGameState("FB_BUTTON_CHECK_STATE", true, "FALCON")

    let compos = newLocalizedNodeWithResource("common/gui/precomps/share_button_comp.json")
    c.node.addChild(compos)

    let showWinAnimCompos = compos.getComponent(AEComposition)
    showWinAnimCompos.play("in", @["chek_button"])

    c.checkBoxNode = compos.findNode("chek_button")
    c.shareBttn = compos.findNode("button_facebook").getComponent(ButtonComponent)
    c.shareBttn.title = localizedString("FACEBOOK_SHARE")

    c.shareBttn.onAction do():
        c.shareImage()
        if not c.onShareClick.isNil:
            c.onShareClick()

    if c.checkBoxNode.isNil:
        c.autoShare = false
    else:
        c.checkBoxNode.getComponent(ButtonComponent).onAction do():
            c.changeCheckStatus(not c.autoShare)

        c.autoShare = getBoolGameState("FB_BUTTON_CHECK_STATE", "FALCON")
        if c.autoShare:
            c.checkBoxNode.getComponent(AEComposition).play("press1")

registerComponent(FBShareButton, "falcon")