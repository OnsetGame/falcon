import random, logging, strutils

import rod.rod_types
import rod.node
import rod.viewport
import rod.component
import rod.component.text_component
import rod.component.ae_composition

import nimx.matrixes
import nimx.button
import nimx.property_visitor
import nimx.animation

import utils / [ helpers, node_scroll, falcon_analytics_helpers, falcon_analytics ]
import shared.localization_manager
import shared.window.window_component
import shared.window.button_component
import shared.game_scene
import shared.user

import narrative / narrative_character
import platformspecific / webview_manager


type WelcomeWindow* = ref object of WindowComponent
    title: Text
    desc: Text
    window: Node
    idleAnim: Animation
    onRemove*: proc()
    topShadow: Node
    bottomShadow: Node
    character: NarrativeCharacter
    privacyBttn: ButtonComponent
    faqBttn: ButtonComponent
    textScroll: NodeScroll

proc applyFrameData*(tw: WelcomeWindow)

proc createScroll(tw: WelcomeWindow) =
    let txt = tw.window.findNode("description_txt")
    txt.position = newVector3(0, 0, 0)
    let scrlNode = newNode("scrlNode")
    scrlNode.position = newVector3(0, -560, 0)
    tw.window.findNode("anchor_bubble").insertChild(scrlNode, 1)

    tw.textScroll = createNodeScroll(newRect(0, 0, 980, 560), scrlNode)
    tw.textScroll.nodeSize = txt.getComponent(Text).getSize()
    tw.textScroll.scrollDirection = NodeScrollDirection.vertical
    tw.textScroll.addChild(txt)
    tw.textScroll.onActionProgress = proc() =
        let scrollY = tw.textScroll.scrollY
        if scrollY == 0.0:
            tw.topShadow.alpha = 0.0
            tw.bottomShadow.alpha = 1.0
        elif scrollY == 1.0:
            tw.topShadow.alpha = 1.0
            tw.bottomShadow.alpha = 0.0
        else:
            tw.topShadow.alpha = 1.0
            tw.bottomShadow.alpha = 1.0

method onInit*(tw: WelcomeWindow) =
    tw.isTapAnywhere = false
    tw.canMissClick = false
    let win = newLocalizedNodeWithResource("common/gui/popups/precomps/Welcome.json")
    tw.anchorNode.addChild(win)
    tw.window = win
    tw.title = win.findNode("title_txt").getComponent(Text)
    tw.desc = win.findNode("description_txt").getComponent(Text)
    tw.title.shadowRadius = 4.0
    tw.desc.shadowRadius = 4.0
    tw.desc.bounds = newRect(0, 0, 980, 0)
    tw.desc.horizontalAlignment = haCenter

    tw.privacyBttn = tw.window.findNode("privacy_bttn").getComponent(ButtonComponent)
    tw.faqBttn = tw.window.findNode("faq_bttn").getComponent(ButtonComponent)
    tw.topShadow = tw.window.findNode("top_text_shadow")
    tw.bottomShadow = tw.window.findNode("top_text_shadow_2")

    tw.topShadow.alpha = 0.0
    tw.privacyBttn.node.scaleX = 0.0
    tw.faqBttn.node.scaleX = 0.0
    tw.privacyBttn.node.getComponent(Text).text = localizedString("GDPR_PRIVACY")
    tw.faqBttn.node.getComponent(Text).text = localizedString("GDPR_FAQ")

    tw.privacyBttn.onAction do():
        openPrivacyPolicy()

    tw.faqBttn.onAction do():
        openFaq()

    tw.character = win.findNode("chcracterAnchor").addComponent(NarrativeCharacter)
    tw.character.kind = NarrativeCharacterType.WillFerris
    tw.character.bodyNumber = 4
    tw.character.headNumber = 2

    let showWinAnimCompos = win.getComponent(AEComposition)
    showWinAnimCompos.play("show", @["accept_bttn"]).onComplete do():
        tw.character.show(0.0)

    let user = currentUser()
    sharedAnalytics().first_run_welcome_screen_show(user.chips)

    let btnGoNode = win.findNode("accept_bttn")
    let btnPlay = btnGoNode.getComponent(ButtonComponent)
    btnPlay.title = localizedString("OOM_OK")
    btnPlay.onAction do():
        sharedAnalytics().first_run_welcome_screen_press(user.chips)
        tw.closeButtonClick()

    tw.applyFrameData()
    tw.createScroll()

proc applyFrameData*(tw: WelcomeWindow) =
    var username = if currentUser().name.len() <= 0: "Player" else: currentUser().name
    tw.title.text = localizedString("WELCOME_TITLE") % [username]
    tw.desc.text = ""

proc `title=`*(tw: WelcomeWindow, txt: string) =
    tw.title.text = txt

proc `description=`*(tw: WelcomeWindow, txt: string) =
    tw.desc.text = txt
    let size = tw.desc.getSize()
    tw.textScroll.nodeSize = size
    if size.height < 560:
        tw.textScroll.scrollDirection = NodeScrollDirection.none
    else:
        tw.textScroll.scrollDirection = NodeScrollDirection.vertical

proc `character=`*(tw: WelcomeWindow, character: NarrativeCharacterType) =
    tw.character.kind = character

proc `bodyNumber=`*(tw: WelcomeWindow, num: int) =
    tw.character.bodyNumber = num

proc `headNumber=`*(tw: WelcomeWindow, num: int) =
    tw.character.headNumber = num

proc showPrivacy*(tw: WelcomeWindow) =
    tw.privacyBttn.node.scaleX = 1.0

proc showFaq*(tw: WelcomeWindow) =
    tw.faqBttn.node.scaleX = 1.0

method hideStrategy*(w: WelcomeWindow):float =
    if not w.character.isNil:
        w.character.hide(0.3)
    let showWinAnimCompos = w.window.getComponent(AEComposition)
    let anim = showWinAnimCompos.play("show", @["accept_bttn"])
    anim.loopPattern = lpEndToStart
    return anim.loopDuration

method showStrategy*(w: WelcomeWindow) =
    w.node.alpha = 1.0
    discard

method visitProperties*(tw: WelcomeWindow, p: var PropertyVisitor) =
    p.visitProperty("title", tw.title)
    p.visitProperty("desc", tw.desc)

registerComponent(WelcomeWindow, "windows")