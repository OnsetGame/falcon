import rod.rod_types
import rod.node
import rod.viewport
import rod.component
import rod.component.text_component
import rod.component.ui_component
import rod.component.ae_composition

import nimx.button
import nimx.matrixes
import nimx.animation
import nimx.control

import shared.user
import shared.game_scene
import shared.localization_manager
import shared.window.window_component
import shared.window.button_component

import shafa / game / reward_types

import utils.sound_manager
import utils.helpers
import utils.falcon_analytics

import node_proxy / proxy
import strutils, logging

import narrative.narrative_character


nodeProxy VipLevelupProxy:
    title Text {onNode: np.node.findNode("tab_middle").findNode("title")}:
        text = localizedString("VIP_LVLUP_TITLE")
    rewardBttn ButtonComponent {onNode: "button_exhange_new"}:
        title = localizedString("LEVELUP_GETREWARD")
    aeComp AEComposition {onNode: node}
    showAnim Animation {withValue: np.aeComp.compositionNamed("show", @["button_exhange_new"])}
    hideAnim Animation {withValue: np.aeComp.compositionNamed("hide")}
    prevLvl Text {onNode: "text_lvl_prev"}
    currLvl Text {onNode: "text_lvl_cur"}
    glow Node {withName: "ltp_glow_copy.png"}

type VipLevelUPWindow* = ref object of WindowComponent
    buttonReward*: ButtonComponent
    proxy: VipLevelupProxy
    rewards*: seq[Reward]
    character: NarrativeCharacter


method onInit*(w: VipLevelUPWindow) =
    w.proxy = new(VipLevelupProxy, newNodeWithResource("common/gui/popups/precomps/level_up_VIP"))
    w.anchorNode.addChild(w.proxy.node)
    w.proxy.glow.addRotateAnimation(45.0)

    let scene = w.anchorNode.sceneView.GameScene
    scene.soundManager.sendEvent("COMMON_LEVELUP")

    w.proxy.rewardBttn.onAction do():
        w.closeButtonClick()

    w.character = w.anchorNode.addComponent(NarrativeCharacter)
    w.character.kind = NarrativeCharacterType.WillFerris
    w.character.bodyNumber = 4
    w.character.headNumber = 4


proc setUp*(w: VipLevelUPWindow, lvl: int) =
    w.proxy.currLvl.text = $lvl
    w.proxy.prevLvl.text = $(lvl - 1)

method showStrategy*(w: VipLevelUPWindow) =
    w.node.alpha = 1.0
    w.node.addAnimation(w.proxy.showAnim)
    w.character.show(0.0)

method hideStrategy*(w: VipLevelUPWindow): float =
    w.character.hide(0.3)
    result = 0.3


registerComponent(VipLevelUPWindow, "windows")
