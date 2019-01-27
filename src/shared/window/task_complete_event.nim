import random
import strutils

import rod.rod_types
import rod.node
import rod.viewport
import rod.component
import rod.component.text_component
import rod.component.ui_component
import rod.component.ae_composition

import core / notification_center
import nimx.matrixes
import nimx.button
import nimx.property_visitor
import nimx.animation
import nimx.formatted_text
import utils.helpers
import utils.falcon_analytics
import utils.sound_manager

import shared.localization_manager
import shared.window.window_component
import shared.window.button_component
import shared.game_scene
import shared.director
import shared.user
import shafa / game / reward_types

import falconserver.auth.profile_types
import falconserver.map.building.builditem
import quest.quests
import quest.quest_helpers

import narrative.narrative_character


type TaskCompleteEvent* = ref object of WindowComponent
    window: Node
    textDesc: Text
    allowClose: bool
    reward: Reward
    idleAnim: Animation
    character: NarrativeCharacter

method onInit*(tw: TaskCompleteEvent) =
    tw.isTapAnywhere = true
    let win = newLocalizedNodeWithResource("common/gui/popups/precomps/task_complete_event.json")
    tw.window = win
    tw.anchorNode.addChild(win)

    tw.window.findNode("tab_task_complete").findNode("title").component(Text).text = localizedString("TASK_COMPLETED")

    let showWinAnimCompos = win.getComponent(AEComposition)
    let glow = tw.window.findNode("ltp_glow_copy.png")
    glow.addRotateAnimation(40)

    showWinAnimCompos.play("show").onComplete do():
        tw.allowClose = true
        tw.idleAnim = showWinAnimCompos.play("idle", @["ltp_glow"])
        tw.idleAnim.numberOfLoops = -1

    currentNotificationCenter().postNotification("STOP_AUTOSPINS", newVariant(AutospinStopReason.CompleteTask))
    tw.character = tw.window.addComponent(NarrativeCharacter)
    tw.character.kind = NarrativeCharacterType.WillFerris
    tw.character.bodyNumber = 4
    tw.character.headNumber = 4


proc setupQuestData*(tw: TaskCompleteEvent, energy: int)=
    let energyAmount = tw.window.findNode("amount_energy").component(Text)

    tw.reward = createReward(RewardKind.parts, energy)

    let energyAmountStr = "+" & $energy & " "
    energyAmount.text = energyAmountStr & localizedString("CURRENCY_PARTS")
    energyAmount.mText.setTextColorInRange(energyAmountStr.len, energyAmount.text.len, newColor(1.0, 0.87, 0.56, 1.0))
    energyAmount.mText.setTextColorInRange(0, energyAmountStr.len, newColor(1.0, 1.0, 1.0, 1.0))

method onShowed*(w: TaskCompleteEvent) =
    procCall w.WindowComponent.onShowed()

    let gs = w.node.sceneView
    if not gs.isNil and not gs.GameScene.sound_manager.isNil:
        echo "COMMON_TASK_COMPLETE "
        gs.GameScene.sound_manager.sendEvent("COMMON_TASK_COMPLETE")

proc addRewardFlyAnim(tw: TaskCompleteEvent) =
    let bttn = tw.window.sceneView.rootNode.findNode("money_panel").findNode("energy_placeholder")
    let rewNode = tw.window.findNode("energy")
    let reward = tw.reward
    if rewNode.positionY > 500.0:
        rewNode.positionY = 500.0

    var s = rewNode.worldPos
    let e = if not bttn.isNil: bttn.worldPos else: s
    let p1 = (e - s) / 3 + s + newVector3(rand(-300.0 .. 300.0), rand(-300.0 .. 300.0), 0)
    let p2 = (e - s) * 2 / 3 + s + newVector3(rand(-300.0 .. 300.0), rand(-300.0 .. 300.0), 0)
    let c1 = newVector3(p1.x, p1.y, s.z)
    let c2 = newVector3(p2.x, p2.y, s.z)

    let flyAnim = newAnimation()
    flyAnim.loopDuration = 0.7
    flyAnim.numberOfLoops = 1
    flyAnim.onAnimate = proc(p:float) =
        let t = interpolate(0.0, 1.0, p)
        let point = calculateBezierPoint(t, s, e, c1, c2)
        rewNode.scale = interpolate(newVector3(1.0, 1.0, 1.0), newVector3(0.36, 0.36, 1.0), p)
        rewNode.worldPos = point

    let targetParts = currentUser().parts + reward.amount

    flyAnim.onComplete proc() =
        currentUser().updateWallet(parts = targetParts)
        tw.closeButtonClick()
        rewNode.removeFromParent()

    rewNode.addAnimation(flyAnim)

method missClick*(tw: TaskCompleteEvent)=
    if tw.allowClose:
        if not tw.idleAnim.isNil:
            tw.idleAnim.cancel()

        tw.allowClose = false
        let showWinAnimCompos = tw.window.getComponent(AEComposition)
        showWinAnimCompos.play("hide").addLoopProgressHandler(0.5, false) do():
            tw.addRewardFlyAnim()
        tw.character.hide(0.3)

method hideStrategy*(tw: TaskCompleteEvent): float =
    #tw.character.hide(0.3)
    discard

method showStrategy*(tw: TaskCompleteEvent) =
    tw.node.alpha = 1.0
    tw.character.show(0.0)

registerComponent(TaskCompleteEvent, "windows")
