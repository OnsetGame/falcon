import nimx.types
import nimx.animation
import nimx.matrixes
import rod.node
import rod.component
import rod.component.text_component
import rod.component.ae_composition
import window_component, button_component
import shared.localization_manager
import utils.helpers
import utils.falcon_analytics
import narrative.narrative_character

import platformspecific.android.rate_manager

type RateWindow* = ref object of WindowComponent
    win: Node
    glowAnim: Animation
    character: NarrativeCharacter

method onInit*(rw: RateWindow) =
    rw.win = newLocalizedNodeWithResource("common/gui/popups/precomps/love_game_window.json")
    rw.anchorNode.addChild(rw.win)

    let btnClose = rw.win.findNode("button_close")
    let btnLater = rw.win.findNode("button_later")
    let btnRate = rw.win.findNode("button_rate")
    let buttonClose = btnClose.createButtonComponent(btnClose.animationNamed("press"), newRect(10,10,100,100))
    let buttonLater = btnLater.createButtonComponent(btnLater.animationNamed("press"), newRect(0,0,400,130))
    let buttonRate = btnRate.createButtonComponent(btnRate.animationNamed("press"), newRect(0,0,400,120))
    let title = rw.win.findNode("TAB_539px")
    let particle = newNodeWithResource("common/particles/light_particle.json")
    let glowRate = rw.win.findNode("ltp_glow_rate")

    glowRate.addChild(particle)
    particle.position = newVector3(300, 300)
    title.findNode("text_content_active").component(Text).text = localizedString("RATE_LOVE")
    title.findNode("text_content_inactive").component(Text).text = localizedString("RATE_LOVE")
    rw.win.findNode("button_rate").findNode("title").component(Text).text = localizedString("RATE_RATE")
    rw.win.findNode("button_later").findNode("title").component(Text).text = localizedString("RATE_LATER")
    rw.glowAnim = glowRate.animationNamed("idle")
    rw.glowAnim.numberOfLoops = -1
    rw.win.addAnimation(rw.glowAnim )

    buttonClose.onAction do():
        rw.closeButtonClick()

    buttonLater.onAction do():
        rw.closeButtonClick()

    buttonRate.onAction do():
        sharedAnalytics().wnd_rate_us_press()
        rw.closeButtonClick()
        rateApp()

    setRateShowDay()

    rw.character = rw.win.addComponent(NarrativeCharacter)
    rw.character.kind = NarrativeCharacterType.WillFerris
    rw.character.bodyNumber = 6
    rw.character.headNumber = 2
    rw.character.shiftPos(66, 49)


method showStrategy*(rw: RateWindow) =
    let inAnim = rw.win.component(AEComposition).compositionNamed("in", @["button_rate", "button_later", "button_close", "ltp_glow_rate"])
    let idleAnim = rw.win.findNode("rate_inner").component(AEComposition).compositionNamed("idle")

    idleAnim.numberOfLoops = -1
    rw.node.enabled = true
    rw.node.alpha = 1.0
    rw.anchorNode.addAnimation(inAnim)
    inAnim.onComplete do():
        rw.anchorNode.addAnimation(idleAnim)
        sharedAnalytics().wnd_rate_us_show()

    rw.character.show(0.0)


method hideStrategy*(rw: RateWindow): float =
    rw.character.hide(0.3)

    let outAnim = rw.win.component(AEComposition).compositionNamed("out", @["button_rate", "button_later", "button_close", "ltp_glow_rate"])

    rw.win.addAnimation(outAnim)
    rw.glowAnim.cancel()
    return outAnim.loopDuration


registerComponent(RateWindow, "windows")