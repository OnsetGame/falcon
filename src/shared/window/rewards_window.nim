import math, tables, strutils, times, logging, algorithm
import rod / [rod_types, node, viewport]
import rod / component
import rod / component / [ae_composition, text_component, gradient_fill, color_balance_hls]
import nimx / [animation, button, matrixes, notification_center]
import shared / window / [window_manager, window_component, button_component]
import shared / [localization_manager, game_scene]
import shared / user
import utils / [helpers, icon_component, sound_manager]
import core / helpers / [ boost_multiplier, reward_helper ]
import core / features / booster_feature
import core / zone


type RewardWindow* = ref object of WindowComponent
    wBoxKind: RewardWindowBoxKind
    wRewards: seq[Reward]
    wRewardNodes: seq[Node]
    forQuestID*: int
    winBody: Node
    boxAnimation: Animation
    glowAnimation: Animation
    phase: uint8
    isRewardsShowed: bool
    isForVip: bool

const REWARDS_OUT_DURATION = 0.5
const REWARDS_BONUS_COLOR = newColor(0.61, 0.92, 0.94, 1.0)
const REWARDS_SLOT_COLOR = newColor(1.0, 0.58, 0.95, 1.0)

const ELEMENT_DISTANCE_X = 280.0
const ELEMENT_DISTANCE_Y = 200.0

proc sendSoundEvent(rw: RewardWindow, event: string) =
    if not rw.winBody.sceneView.isNil and not rw.winBody.sceneView.GameScene.soundManager.isNil:
        let sm = rw.winBody.sceneView.GameScene.soundManager
        sm.stopSFX()
        sm.sendEvent(event)


template boxKind*(rw: RewardWindow) = rw.wBoxKind
proc `boxKind=`*(rw: RewardWindow, v: RewardWindowBoxKind) =
    rw.wBoxKind = v
    var nodesForRemove: seq[Node] = @[]

    discard rw.winBody.findNode(
        proc(n: Node): bool =
            if n.name.startsWith("rewards_box_"):
                try:
                    if parseEnum[RewardWindowBoxKind](n.name[11..n.name.len]) != v:
                        nodesForRemove.add(n)
                except:
                    discard
    )

    for node in nodesForRemove:
        node.removeFromParent()

proc createReward(reward: Reward): Node =
    let n = newNodeWithResource("common/gui/popups/precomps/rewards_items_even")

    var icon = reward.icon
    var composition = "reward_icons"
    let gradient = n.findNode("bg_1").getComponent(GradientFill)
    gradient.startPoint = newPoint(0, 120)
    gradient.endPoint = newPoint(0, -120)

    if reward.isBooster():
        let mult = n.findNode("booster_multiplier").addBoostMultiplier(newVector3(-138, -78, 0))
        case reward.kind:
            of RewardKind.boosterExp:
                mult.text = boostMultiplierText(btExperience)
            of RewardKind.boosterIncome:
                mult.text = boostMultiplierText(btIncome)
            of RewardKind.boosterTourPoints:
                mult.text = boostMultiplierText(btTournamentPoints)
            else:
                discard

    if reward.kind == RewardKind.freeRounds:
        let freeRoundNode = n.findNode("booster_multiplier").newChild("freeRoundNode")
        freeRoundNode.position = newVector3(-100, -40, 0)
        let freeRoundIcon = freeRoundNode.addRewardIcon("freeRounds")
        freeRoundIcon.rect = newRect(0, 0, 150, 150)
        composition = "slot_logos_icons"
        icon = reward.ZoneReward.zone
    elif reward.kind == RewardKind.vipaccess:
        composition = "slot_logos_icons"
        icon = reward.ZoneReward.zone

    let rewTitle = n.findNode("rewardTitle").component(Text)
    rewTitle.lineSpacing = -8
    rewTitle.verticalAlignment = VerticalAlignment.vaCenter
    rewTitle.bounds = newRect(-118, -28, 235, 55)
    rewTitle.text = reward.localizedName().toUpperAscii()
    let iconComp = n.findNode("reward_icon_placeholder").component(IconComponent)
    iconComp.composition = composition
    iconComp.name = icon

    let feature = findFeature(BoosterFeature)
    if reward.kind == RewardKind.exp and feature.isBoosterActive(btExperience):
        reward.amount = round(reward.amount.float * currentUser().boostRates.xp).int

    let title2 = n.findNode("rewardTitle_2").component(Text)
    title2.lineSpacing = -15
    title2.bounds = newRect(-132, -65, 252, 100)
    title2.text = reward.localizedCount()

    if title2.text.len > 8:
        title2.fontSize = 46.0

    if reward.isBonus():
        rewTitle.color = REWARDS_BONUS_COLOR
    # elif reward.isSlot():
    #     rewTitle.color = REWARDS_SLOT_COLOR

    result = n


proc `rewards=`*(rw: RewardWindow, rewards: seq[Reward]) =
    var rewards = rewards.prioritizedRewards()

    rw.wRewardNodes = newSeq[Node]()
    rw.wRewards = rewards
    let anchor = rw.winBody.findNode("rewards_item_anchor")
    let count = rewards.len()

    for i, rew in rewards:
        let rewNode = rew.createReward()
        rw.wRewardNodes.add(rewNode)

        var x = 0.0
        var y = 0.0
        if i < 6:
            x = ELEMENT_DISTANCE_X * (i.float + 0.5 - min(count.float, 6.0) / 2.0)
            if count > 6: y = -ELEMENT_DISTANCE_Y
        else:
            x = ELEMENT_DISTANCE_X * (i.float + 0.5 - 6.0 - (count.float - 6.0) / 2.0)
            y = ELEMENT_DISTANCE_Y
        rewNode.anchor = newVector3(960, 620, 0)
        rewNode.position = newVector3(x, y, 0.0)
        anchor.addChild(rewNode)


proc nextPhase(rw: RewardWindow): void


proc createModalButton(rw: RewardWindow, cb: proc() = nil) =
    let btnReward = newNode("bttnReward_node")
    rw.winBody.addChild(btnReward)
    let buttonReward = btnReward.createButtonComponent(newRect(0, 0, 1920, 1080))
    buttonReward.onAction do():
        btnReward.removeFromParent()
        if not cb.isNil:
            cb()
        else:
            rw.nextPhase()

proc showRewardItems(rw: RewardWindow) =
    if rw.isRewardsShowed:
        return
    rw.isRewardsShowed = true

    for rewNode in rw.wRewardNodes:
        let showAnim = rewNode.component(AEComposition).compositionNamed("show")
        rewNode.addAnimation(showAnim)

    if rw.isForVip:
        rw.anchorNode.findNode("button_collect_all_purple").alpha = 1.0
    else:
        rw.anchorNode.findNode("button_collect_all_orange").alpha = 1.0


proc nextPhase(rw: RewardWindow) =
    case rw.phase:
        of 0:
            var canMakeNextStep = false

            rw.boxAnimation = rw.winBody.findNode("rewards_box_in_window").component(AEComposition).compositionNamed("idle")
            rw.boxAnimation.numberOfLoops = -1
            rw.winBody.addAnimation(rw.boxAnimation)
            rw.sendSoundEvent("MAP_REWARD_SAFE_IDLE")

            var inAnimation: CompositAnimation

            let inGlowAnimation = rw.winBody.findNode("rewards_glow").component(AEComposition).compositionNamed("in")
            inGlowAnimation.numberOfLoops = 1
            inGlowAnimation.onComplete do():
                if not inAnimation.isCancelled():
                    rw.glowAnimation = rw.winBody.findNode("rewards_glow").component(AEComposition).compositionNamed("idle")
                    rw.glowAnimation.numberOfLoops = -1
                    rw.winBody.addAnimation(rw.glowAnimation)

            let inBodyAnimation = rw.winBody.component(AEComposition).compositionNamed("in", @["rewards_glow", "rewards_box_in_window"])
            inBodyAnimation.numberOfLoops = 1

            inAnimation = newCompositAnimation(true, inBodyAnimation, inGlowAnimation)
            inAnimation.numberOfLoops = 1
            inAnimation.onComplete do():
                if canMakeNextStep:
                    rw.nextPhase()
                else:
                    canMakeNextStep = true
            rw.winBody.addAnimation(inAnimation)

            rw.createModalButton() do():
                if canMakeNextStep:
                    rw.nextPhase()
                else:
                    canMakeNextStep = true
                    inAnimation.cancel()
        of 1:
            rw.sendSoundEvent("MAP_REWARD_BAG_CLICK")
            var canMakeNextStep = false

            rw.winBody.enabled = true

            let boxExplosionAnimation = rw.winBody.findNode("rewards_box_explosion").component(AEComposition).compositionNamed("idle")
            boxExplosionAnimation.numberOfLoops = -1
            rw.winBody.addAnimation(boxExplosionAnimation)

            let boxExplosionTintAnimation = rw.winBody.findNode("rewards_box_explosion_tint").component(AEComposition).compositionNamed("idle")
            boxExplosionTintAnimation.numberOfLoops = -1
            rw.winBody.addAnimation(boxExplosionTintAnimation)

            rw.boxAnimation.cancel()
            rw.boxAnimation = nil

            let explosionAnimation = rw.winBody.component(AEComposition).compositionNamed("explosion", @["rewards_glow", "rewards_box_explosion", "rewards_box_explosion_tint"])
            explosionAnimation.numberOfLoops = 1

            explosionAnimation.addLoopProgressHandler(0.5, false) do():
                rw.showRewardItems()

            explosionAnimation.onComplete do():
                boxExplosionAnimation.cancel()
                boxExplosionTintAnimation.cancel()

                if not rw.glowAnimation.isNil():
                    rw.glowAnimation.cancel()
                    rw.glowAnimation = nil

                if explosionAnimation.isCancelled():
                    explosionAnimation.onProgress(1.0)
                    rw.createModalButton() do():
                        rw.nextPhase()
                else:
                    if canMakeNextStep:
                        rw.nextPhase()
                    else:
                        canMakeNextStep = true
            rw.winBody.addAnimation(explosionAnimation)

            rw.createModalButton() do():
                if canMakeNextStep:
                    rw.nextPhase()
                else:
                    canMakeNextStep = true
                    explosionAnimation.cancel()
                    rw.showRewardItems()
        of 2:
            rw.sendSoundEvent("MAP_REWARD_BAG_ITEM_OUT")

            let winRoot = sharedWindowManager().windowsRoot()
            var chipsDest: Node
            var bucksDest: Node
            var partsDest: Node
            var incomeDest: Node
            var incomeResourceDest: Node
            var otherDest: Node

            proc execFlyAnim()=
                for i, n in rw.wRewardNodes:
                    let reward = rw.wRewards[i]
                    var parentNode = winRoot.sceneView.rootNode.findNode("rewardsFlyParent")
                    var destNode: Node
                    var scale = newVector3(0.36, 0.36, 1.0)

                    case reward.kind:
                        of RewardKind.chips:
                            if chipsDest.isNil and not winRoot.isNil:
                                chipsDest = winRoot.parent.findNode("money_panel").findNode("chips_placeholder")
                            destNode = chipsDest
                        of RewardKind.bucks:
                            if bucksDest.isNil and not winRoot.isNil:
                                bucksDest = winRoot.parent.findNode("money_panel").findNode("bucks_placeholder")
                            destNode = bucksDest
                        of RewardKind.parts:
                            if partsDest.isNil and not winRoot.isNil:
                                partsDest = winRoot.parent.findNode("money_panel").findNode("energy_placeholder")
                            destNode = partsDest
                        of RewardKind.incomeChips, RewardKind.incomeBucks:
                            if incomeDest.isNil and not winRoot.isNil:
                                var collectButton = winRoot.parent.findNode("map_collect_button")
                                # Map
                                if not collectButton.isNil:
                                    if reward.kind == RewardKind.incomeChips:
                                        incomeDest = collectButton.findNode("ebutton_anim_controller")
                                        incomeResourceDest = collectButton.findNode("chips_placeholder")
                                    else:
                                        incomeDest = collectButton.findNode("button_anim_controller")
                                        incomeResourceDest = collectButton.findNode("bucks_placeholder")
                                # Slot
                                else:
                                    collectButton = winRoot.parent.findNode("slot_bottom_menu")
                                    if not collectButton.isNil:
                                        let dest = collectButton.findNode("collect_in_slot_control")
                                        if not dest.isNil:
                                            incomeDest = collectButton
                                            incomeResourceDest = collectButton

                                # Ugly Scene
                                if incomeDest.isNil:
                                    let otherDest = winRoot.parent.findNode("player_info").findNode("lvl")
                                    incomeDest = otherDest
                                    incomeResourceDest = otherDest
                                    scale.x = 0.2
                                    scale.y = 0.2
                            destNode = incomeDest
                        else:
                            if otherDest.isNil and not winRoot.isNil:
                                otherDest =  winRoot.parent.findNode("player_info").findNode("lvl")
                            destNode = otherDest
                            scale.x = 0.2
                            scale.y = 0.2

                    let sourceNode = n.findNode("rew_icon")
                    if not sourceNode.isNil:
                        addRewardFlyAnim(sourceNode, destNode, scale, parentNode)

            rw.winBody.sceneView.GameScene.setTimeout(REWARDS_OUT_DURATION + 0.1) do():
                let user = currentUser()

                var chips = user.chips
                var bucks = user.bucks
                var parts = user.parts
                var tournPoints = user.tournPoints

                for reward in rw.wRewards:
                    case reward.kind:
                        of RewardKind.chips:
                            chips += reward.amount
                        of RewardKind.bucks:
                            bucks += reward.amount
                        of RewardKind.tourPoints:
                            tournPoints += reward.amount
                        of RewardKind.parts:
                            parts += reward.amount
                        of RewardKind.vipaccess:
                            let zone = findZone(reward.ZoneReward.zone)
                            rw.winBody.sceneView.GameScene.notificationCenter.postNotification("UnlockQuest", newVariant(zone.feature.unlockQuestConf))
                        else:
                            discard

                user.updateWallet(chips, bucks, parts, tournPoints)

            let outAnimation = rw.winBody.component(AEComposition).compositionNamed("out", @["rewards_glow"])
            outAnimation.numberOfLoops = 1
            outAnimation.addLoopProgressHandler(0.2, false) do():
                execFlyAnim()
            outAnimation.onComplete do():
                rw.nextPhase()

            rw.winBody.addAnimation(outAnimation)
        of 3:
            rw.close()
        else:
            discard
    rw.phase.inc

proc forVip*(rw: RewardWindow, state: bool) =
    rw.isForVip = state
    rw.anchorNode.findNode("corner").alpha = rw.isForVip.float32

method onInit*(rw: RewardWindow) =
    rw.winBody = newLocalizedNodeWithResource("common/gui/popups/precomps/rewards_window")
    rw.anchorNode.addChild(rw.winBody)

    let glowParticles = newNodeWithResource("common/particles/prt_glow_scene.json")
    rw.winBody.findNode("glow_particles_anchor").addChild(glowParticles)

    let explosionParticles = newNodeWithResource("common/particles/explosion_particles.json")
    rw.winBody.findNode("explosion_particles_anchor").addChild(explosionParticles)

    rw.anchorNode.findNode("button_collect_all_orange").findNode("text").getComponent(Text).text = localizedString("RW_COLLECT_ALL")
    rw.anchorNode.findNode("button_collect_all_purple").findNode("text").getComponent(Text).text = localizedString("RW_COLLECT_ALL")
    rw.anchorNode.findNode("corner_text").getComponent(Text).text = localizedString("REWARDS_WIN_CORNER_VIP")
    rw.anchorNode.findNode("corner_placeholder.png").getComponent(ColorBalanceHLS).hue = 0.8

    rw.anchorNode.findNode("button_collect_all_purple").alpha = 0.0
    rw.anchorNode.findNode("button_collect_all_orange").alpha = 0.0
    rw.anchorNode.findNode("corner").alpha = 0.0

    rw.anchorNode.findNode("ltp_solidorange.png").alpha = 0.0


method showStrategy*(rw: RewardWindow) =
    procCall rw.WindowComponent.showStrategy()
    rw.nextPhase()

registerComponent(RewardWindow, "windows")
