import nimx / [ types, matrixes, font, formatted_text, animation, view ]
import rod / [ node, viewport, quaternion ]
import rod.component
import rod.component / [ text_component, tint, vector_shape, gradient_fill, ae_composition ]
import rod.utils.text_helpers
import shared / window / [ window_component, button_component, window_manager ]
import windows / store / store_window
import shared / [ localization_manager, user, game_scene, tutorial ]
import core / [ zone, zone_actions, zone_helper, notification_center, notification_center ]
import utils / [ helpers, icon_component, node_scroll, progress_bar, falcon_analytics, game_state ]
import quest / [ quests, quest_helpers, quests_actions ]
import slots / [ slot_machine_registry ]
import falconserver.map.building.builditem
import falconserver.common.currency
import tables
import strutils
import json
import map / tiledmap_actions
import shared / deep_links
import core / features / slot_feature
import core / net / server
import shared / director
import falconserver.common.game_balance

const MAX_SLOTS_ON_PAGE = 3
const SLOTS_DEFAULT_OFFSET = 432.Coord

var slotColors =
    {
    dreamTowerSlot: "54221DFF",
    candySlot:      "465E1DFF",
    balloonSlot:    "6C1D34FF",
    witchSlot :     "1C5A46FF",
    mermaidSlot:    "661853FF",
    ufoSlot:        "1E366EFF",
    groovySlot:     "1C313DFF",
    candySlot2:     "290E64FF",
    cardSlot:       "4F1F4CFF"
    }.toTable

let slots = @[dreamTowerSlot, candySlot, balloonSlot, witchSlot, mermaidSlot, groovySlot, candySlot2, ufoSlot, cardSlot]
var prevActiveSlots = newSeq[bool](slots.len())

type SkipButtonStyle = enum
    Orange = "button_orange_circle"
    Red = "button_red_circle"
    Blue = "button_blue_circle"

type CardType = enum
    Normal
    Locked
    VipLocked
    Skip
    Soon
    FreeRounds

type SoonSlots = enum
    Goldmine

type TasksCard = ref object of RootObj
    node: Node
    cardType: CardType
    slot: BuildingId
    playButton: ButtonComponent
    unlockButton: ButtonComponent
    completeButton: ButtonComponent
    progbar: ProgressBar
    desc: Node

type TasksWindow* = ref object of WindowComponent
    rootNode*: Node
    parent*: Node
    buttonLeft: ButtonComponent
    buttonRight: ButtonComponent
    slotsScrollNode: Node
    slotsFrameParent: NodeScroll
    slotsScrollContent*: Node
    cards: seq[TasksCard]
    source: string

proc applyTintToThreedot(card: TasksCard) =
    let threedot = card.node.findNode("threedot_placeholder.png")
    let tintEffect = Tint.new()

    case card.slot
    of candySlot:
        tintEffect.black = newColor(0.56470590829849, 0.76470589637756, 0.25098040699959, 1.0)
        tintEffect.white = newColor(0.35294118523598, 0.5137255191803, 0.09803921729326, 1.0)
    of dreamTowerSlot:
        tintEffect.black = newColor(0.76078432798386, 0.24705882370472, 0.1843137294054, 1.0)
        tintEffect.white = newColor(0.44313725829124, 0.1803921610117, 0.14901961386204, 1.0)
    of ufoSlot:
        tintEffect.black = newColor(0.2392156869173, 0.71372550725937, 0.82352942228317, 1.0)
        tintEffect.white = newColor(0.16470588743687, 0.24705882370472, 0.63137257099152, 1.0)
    of witchSlot:
        tintEffect.black = newColor(0.32941177487373, 0.92549020051956, 0.55294120311737, 1.0)
        tintEffect.white = newColor(0.15294118225574, 0.48627451062202, 0.41176471114159, 1.0)
    of mermaidSlot:
        tintEffect.black = newColor(0.94117647409439, 0.24313725531101, 0.49411764740944, 1.0)
        tintEffect.white = newColor(0.52549022436142, 0.0588235296309, 0.45882353186607, 1.0)
    of balloonSlot:
        tintEffect.black = newColor(0.84705883264542, 0.25098040699959, 0.29411765933037, 1.0)
        tintEffect.white = newColor(0.60784316062927, 0.09803921729326, 0.28627452254295, 1.0)
    of groovySlot:
        tintEffect.black = newColor(0.2078, 0.6392, 0.3568, 1.0)
        tintEffect.white = newColor(0.1843, 0.2117, 0.4156, 1.0)
    of candySlot2:
        tintEffect.black = newColor(0.5843, 0.2431, 1.0, 1.0)
        tintEffect.white = newColor(0.2313, 0.0627, 0.5647, 1.0)
    of cardSlot:
        tintEffect.black = newColor(0.7647, 0.0901, 0.4745, 1.0)
        tintEffect.white = newColor(0.4392, 0.0941, 0.3137, 1.0)
    else:
        discard

    tintEffect.amount = 1.0
    threedot.setComponent("Tint", tintEffect)

proc setColorBackground(card: TasksCard, parent: Node) = #TODO replace this precompose after CCToner implementation!
    let colorCards = parent.findNode("color_cards")
    for c in colorCards.children:
        if c.name != $card.slot:
            c.enabled = false

proc setLockPicture(card: TasksCard) =
    let colorCards = card.node.findNode("lock_cards")

    for c in colorCards.children:
        if c.name != $card.slot:
            c.enabled = false

proc isSlotAvailable(bid: BuildingId): bool =
    let clientState = currentUser().clientState
    if "initial_slot" in clientState:
        let initialSlot = clientState["initial_slot"].num.BuildingId
        if initialSlot == bid:
            return true

    for slotID in activeSlots():
        if bid == slotID:
            return true

    let zone = findZone($bid)
    return zone.isActive()

proc taskForSlot(target: BuildingId): Quest =
    for v in sharedQuestManager().slotQuests:
        result = sharedQuestManager().questById(v.questId)
        if not result.isNil and result.tasks[0].target == target.int:
            break

    assert(not result.isNil, "Quest for slot `" & $target & "` not found")


proc acceptTaskAndStartSlot(tw: TasksWindow, card: TasksCard) =
    let quest = taskForSlot(card.slot)
    assert(not quest.isNil)

    let gameName = $(quest.tasks[0].target.BuildingId)
    let task = quest.tasks[0]

    if quest.status > QuestProgress.Ready:
        tw.closeButtonClick()
        return

    sharedAnalytics().task_open(quest.getProgress(), sharedQuestManager().totalStageLevel(), quest.tasks[0].target.BuildingId, sharedQuestManager().slotStageLevel(quest), task.progresses[0].total.int64, $task.difficulty, $task.taskType & "_" & $card.slot)
    currentNotificationCenter().postNotification("TasksWindow_closedApplyTaskBet")

    let wonclose = tw.onClose
    tw.onClose = proc()=
        discard startSlotMachineGame(task.target.BuildingId, smkDefault)
        if not wonclose.isNil:
            wonclose()

    sharedQuestManager().acceptTask(quest.id, gameName) do():
        echo "Accept task ", gameName
        tw.closeButtonClick()

proc startSlotInFreeRoundsMode(tw: TasksWindow, card: TasksCard) =
    let wonclose = tw.onClose
    tw.onClose = proc() =
        let quest = taskForSlot(currentDirector().currentScene.name.buildingIdFromClassName())
        if not quest.isNil and quest.status == QuestProgress.InProgress:
            sharedServer().sendQuestCommand("pause", quest.id)
        sharedDeepLinkRouter().handle("/free-rounds/" & buildingIdToClassName[card.slot])
        if not wonclose.isNil:
            wonclose()
    tw.closeButtonClick()

proc recreateNormalCard(tw: TasksWindow, card: TasksCard)

proc setupSkipFeature(tw: TasksWindow, card: TasksCard) =
    let quest = taskForSlot(card.slot)
    let task = quest.tasks[0]

    var skipStyle = parseEnum(currentUser().getABOrDefault("skip_task_button", "button_orange_circle"), Blue)

    let buttons1 = card.node.findNode("task_play")
    card.setColorBackground(buttons1)
    let buttons2 = card.node.findNode("task_frame_skip")
    card.setColorBackground(buttons2)
    var skipBttnNode: Node

    let flipAnimation = card.node.animationNamed("flip")
    flipAnimation.loopPattern = lpStartToEnd
    flipAnimation.onProgress(1.0)
    buttons1.rotation = newQuaternion()

    if task.progresses[0].current.float == task.progresses[0].total.float:
        buttons1.findNode("card_buttons").alpha = 0.0
        return

    for i in SkipButtonStyle.low .. SkipButtonStyle.high:
        if i == skipStyle:
            let bttnNode1 = buttons1.findNode($i)
            let bttn1 = bttnNode1.createButtonComponent(bttnNode1.animationNamed("press"), newRect(170, 10, 106, 106))
            bttn1.onAction do():
                sharedAnalytics().task_rotate(quest.getProgress(), $task.difficulty, $task.taskType & "_" & $card.slot, card.slot, sharedQuestManager().slotStageLevel(quest))
                let anim = card.node.animationNamed("flip")
                anim.loopPattern = lpEndToStart
                anim.onComplete do():
                    if not skipBttnNode.sceneView.isNil:
                        buttons2.rotation = newQuaternion()
                bttnNode1.addAnimation(anim)

                let skipPriceText = formatThousands(sharedQuestManager().slotStageSkipCost(quest))

                buttons2.findNode("SKIP_TASK_DESC").getComponent(Text).text = localizedFormat("SKIP_TASK_DESC", skipPriceText)
                if skipBttnNode.isNil:
                    skipBttnNode = buttons2.findNode("big_white_stroke_green_btn_bucks")
                skipBttnNode.findNode("title").getComponent(Text).text = skipPriceText
                let skipBttn = skipBttnNode.createButtonComponent(skipBttnNode.animationNamed("press"), newRect(0, 0, 337, 112))
                skipBttnNode.affectsChildrenRec(true)
                skipBttn.enabled = true
                skipBttn.onAction do():
                    skipBttn.enabled = false
                    let price = quest.speedUpPrice()
                    if price <= currentUser().bucks:
                        sharedAnalytics().task_skip(quest.getProgress(), $task.difficulty, $task.taskType & "_" & $card.slot, card.slot, sharedQuestManager().slotStageLevel(quest), price)
                        sharedQuestManager().speedUpQuest(quest.id) do():
                            let anim = card.node.animationNamed("flip")
                            anim.loopPattern = lpStartToEnd
                            anim.onComplete do():
                                if not skipBttnNode.sceneView.isNil:
                                    tw.recreateNormalCard(card)
                                    buttons1.rotation = newQuaternion()
                            skipBttnNode.addAnimation(anim)
                    else:
                        showStoreWindow(StoreTabKind.Bucks, "skip_task")

            let bttnNode2 = buttons2.findNode($i)
            let bttn2 = bttnNode2.createButtonComponent(bttnNode2.animationNamed("press"), newRect(170, 10, 106, 106))
            bttn2.onAction do():
                let anim = card.node.animationNamed("flip")
                anim.loopPattern = lpStartToEnd
                anim.onComplete do():
                    if not skipBttnNode.sceneView.isNil:
                        buttons1.rotation = newQuaternion()
                bttnNode2.addAnimation(anim)

                skipBttnNode.removeComponent(ButtonComponent)
        else:
            buttons1.findNode($i).removeFromParent()
            buttons2.findNode($i).removeFromParent()

proc setTaskDetails(card: TasksCard) =
    let quest = taskForSlot(card.slot)

    card.completeButton.node.removeFromParent()
    let taskIco = card.node.findNode("task_illustration")
    let desc = card.desc.getComponent(Text)

    let task = quest.tasks[0]
    let ico = taskIco.addTaskIconComponent(getTaskIcon(task.taskType, card.slot))
    let stageLevel = card.node.findNode("stage_number")
    let currstr = formatThousands(task.progresses[0].current.int64)
    let progText = card.node.findNode("cur_progress").getComponent(Text)
    var f = newFontWithFace(progText.font.face, progText.font.size * 0.8)

    ico.hasOutline = false
    stageLevel.getComponent(Text).text = $sharedQuestManager().slotStageLevel(quest)
    desc.text = getDescriptionWithoutTarget(quest.description)
    card.node.findNode("reward_amount").getComponent(Text).text = formatThousands(quest.rewards[0].amount)
    card.progbar.progress = task.progresses[0].current.float / task.progresses[0].total.float
    progText.text = currstr & " / " & formatThousands(task.progresses[0].total.int64)
    progText.mText.setFontInRange(currstr.len, progText.text.len, f)
    progText.mText.setFontInRange(0, currstr.len, progText.font)


proc positionCard(tw: TasksWindow, card: TasksCard) =
    tw.slotsFrameParent.addChild(card.node)
    card.node.position = newVector3(tw.cards.len.float * (SLOTS_DEFAULT_OFFSET + 23), 197)
    tw.cards.add(card)

proc createFreeRoundsSlotCard*(tw: TasksWindow, slot: BuildingId, slotFeature: SlotFeature) =
    let frCard = TasksCard.new()

    frCard.slot = slot
    frCard.cardType = CardType.FreeRounds
    frCard.node = newLocalizedNodeWithResource("common/gui/popups/precomps/task_frame")
    frCard.node.findNode("task_frame_skip").removeFromParent()
    frCard.desc = frCard.node.findNode("task_description")

    let frameNode = frCard.node.findNode("task_play")
    frameNode.rotation = newQuaternion()
    frameNode.alpha = 1.0

    frCard.node.findNode("stage_number").removeFromParent()
    frCard.node.findNode("card_buttons").removeFromParent()
    frCard.node.findNode("tw_stage").removeFromParent()
    frCard.node.findNode("reward_bottom").removeFromParent()
    frCard.node.findNode("big_white_stroke_blue_btn").removeFromParent()
    frCard.node.findNode("big_white_stroke_complete_btn").removeFromParent()
    frCard.node.findNode("unlock_parent").removeChildrensExcept(@["reward_amount", "task_window_progress_bar","cur_progress"])

    discard frCard.node.findNode("slot_icons").addSlotLogos($slot)
    frCard.setColorBackground(frCard.node)

    let btnPlay = frCard.node.findNode("button_orange_wide_01")
    btnPlay.findNode("title").getComponent(Text).text = localizedString("TW_PLAY_NEW")

    frCard.playButton = btnPlay.createButtonComponent(btnPlay.animationNamed("press"), newRect(55,0,440,120))
    frCard.playButton.onAction do():
        echo "PLAY FREE ROUNDS ", slot
        if not tw.processClose and not tw.isBusy:
            tw.isBusy = true
            tw.startSlotInFreeRoundsMode(frCard)

    let descTextComp = frCard.desc.getComponent(Text)
    descTextComp.verticalAlignment = vaCenter
    descTextComp.text = $slotFeature.totalRounds
    descTextComp.shadowRadius = 2.5
    descTextComp.fontSize = 72.0
    frCard.desc.positionY = 365.0

    let freeRoundsTextNode = frCard.node.findNode("reward_amount")
    freeRoundsTextNode.getComponent(Text).text = localizedString("FREE_ROUNDS_ON_CARD")
    freeRoundsTextNode.positionY = 74.0

    frCard.progbar = frCard.node.findNode("progress_task_parent").addComponent(ProgressBar)
    frCard.node.findNode("progress_shape_02").getComponent(GradientFill).endPoint.y = 5

    let taskIco = frCard.node.findNode("task_illustration")
    let ico = taskIco.addRewardIcon("freeRounds")
    ico.hasOutline = false

    tw.positionCard(frCard)

    let progText = frCard.node.findNode("cur_progress").getComponent(Text)
    let f = newFontWithFace(progText.font.face, progText.font.size * 0.8)

    frCard.progbar.progress =  slotFeature.passedRounds.float / slotFeature.totalRounds.float
    progText.text = $slotFeature.passedRounds & " / " & $slotFeature.totalRounds
    progText.mText.setFontInRange(($slotFeature.passedRounds).len, progText.text.len, f)
    progText.mText.setFontInRange(0, ($slotFeature.passedRounds).len, progText.font)

proc createNormalSlotCard(tw: TasksWindow, slot: BuildingId): TasksCard =
    result.new()
    let r = result

    r.slot = slot
    r.cardType = CardType.Normal
    r.node = newLocalizedNodeWithResource("common/gui/popups/precomps/task_frame")
    r.desc = r.node.findNode("task_description")

    let rewardBottom = r.node.findNode("reward_bottom")
    let btnPlay = r.node.findNode("button_orange_wide_01")
    let btnUnlock = r.node.findNode("big_white_stroke_blue_btn")
    let btnComplete = r.node.findNode("big_white_stroke_complete_btn")

    discard r.node.findNode("reward_icon").addEnergyIcons()
    discard r.node.findNode("slot_icons").addSlotLogos($slot)

    r.setColorBackground(r.node)
    r.playButton = btnPlay.createButtonComponent(btnPlay.animationNamed("press"), newRect(55,0,440,120))
    r.unlockButton = btnUnlock.createButtonComponent(btnUnlock.animationNamed("press"), newRect(55,0,440,120))
    r.completeButton = btnComplete.createButtonComponent(btnComplete.animationNamed("press"), newRect(55,0,440,120))
    btnPlay.findNode("title").getComponent(Text).text = localizedString("TW_PLAY_NEW")
    btnUnlock.findNode("title").getComponent(Text).text = localizedString("TW_UNLOCK")
    discard btnUnlock.findNode("placeholder").addEnergyIcons()
    btnUnlock.enabled = false

    rewardBottom.getComponent(VectorShape).color = fromHexColor(slotColors[slot])
    r.desc.getComponent(Text).lineSpacing = -9
    r.desc.positionY = r.desc.positionY - 20
    r.desc.getComponent(Text).verticalAlignment = vaCenter
    r.playButton.onAction do():
        echo "PLAY BUTTON ", slot
        if isSlotAvailable(slot) and not tw.processClose and not tw.isBusy:
            tw.isBusy = true
            tw.acceptTaskAndStartSlot(r)

    r.applyTintToThreedot()
    r.progbar = r.node.findNode("progress_task_parent").addComponent(ProgressBar)
    r.node.findNode("progress_shape_02").getComponent(GradientFill).endPoint.y = 5

proc recreateNormalCard(tw: TasksWindow, card: TasksCard) =
    let i = tw.cards.find(card)
    let position = card.node.position
    let index = tw.slotsFrameParent.indexOf(card.node)

    let otherCard = tw.createNormalSlotCard(card.slot)
    otherCard.node.position = position
    tw.cards[i] = otherCard
    tw.slotsFrameParent.removeChild(card.node)
    tw.slotsFrameParent.insertChild(otherCard.node, index)

    otherCard.setTaskDetails()
    tw.setupSkipFeature(otherCard)

proc setBaseLockedCard(tw: TasksWindow, card: TasksCard) =
    card.setColorBackground(card.node)
    card.setLockPicture()
    discard card.node.findNode("slot_icons").addSlotLogos($(card.slot))

    let lock = card.node.findNode("lock_comp")
    tw.anchorNode.addAnimation(lock.animationNamed("complete"))

proc createLockedSlotCard(tw: TasksWindow, slot: BuildingId): TasksCard =
    result.new()
    result.slot = slot
    result.cardType = CardType.Locked
    result.node = newLocalizedNodeWithResource("common/gui/popups/precomps/task_frame_lock")
    tw.setBaseLockedCard(result)

proc createVipLockedSlotCard(tw: TasksWindow, slot: BuildingId): TasksCard =
    result.new()
    result.slot = slot
    result.cardType = CardType.VipLocked
    result.node = newLocalizedNodeWithResource("common/gui/popups/precomps/task_vip_lock")

    tw.setBaseLockedCard(result)
    result.node.findNode("title").component(Text).text = localizedString("TW_GO_VIP")

    let btnUnlockVIP = result.node.findNode("big_white_stroke_vip_btn")
    let goVIP = btnUnlockVIP.createButtonComponent(btnUnlockVIP.animationNamed("press"), newRect(55,0,440,120))
    let lvl = getVipZoneLevel(slot)

    result.node.findNode("tw_unlock_vip").getComponent(Text).text = localizedFormat("TW_UNLOCK_VIP", $lvl)
    goVIP.onAction do():
        showStoreWindow(StoreTabKind.Vip, "user_from_go_vip_tasks")

proc addSoonSlotCard(tw: TasksWindow, slot: SoonSlots) =
    let card = TasksCard.new()
    card.node = newLocalizedNodeWithResource("common/gui/popups/precomps/task_frame_soon")

    let desc = card.node.findNode("soon_slot_desc").getComponent(Text)
    let cards = card.node.findNode("soon_cards")

    card.cardType = CardType.Soon
    desc.text = localizedString("CS_" & $slot & "_DESC")
    desc.lineSpacing = -5
    desc.verticalAlignment = vaCenter

    for c in cards.children:
        if c.name != ($slot).toLowerAscii():
            c.enabled = false
    tw.positionCard(card)

proc addSoonSlotCard(tw: TasksWindow, slot: string) =
    case slot
    of "goldMineSlot":
        tw.addSoonSlotCard(Goldmine)
    else:
        echo "No soon card for ", slot

proc getSlotQuest(bid: BuildingId): Quest =
    for quest in sharedQuestManager().activeStories():
        var qtarget = try: parseEnum[BuildingId](quest.config.targetName) except: noBuilding
        if qtarget == bid:
            return quest

proc disableUnlock(tw: TasksWindow, card: TasksCard, enable: bool) =
    const NORMAL_POS = 400
    const UNLOCK_POS = 318

    card.node.findNode("task_illustration").enabled = enable
    card.node.findNode("unlock_parent").enabled = enable
    card.node.findNode("tw_stage").enabled = enable
    card.node.findNode("stage_number").enabled = enable
    card.node.findNode("circle_reward").enabled = enable
    card.node.findNode("circle_component_shadow.png").enabled = enable
    card.playButton.node.enabled = enable

    card.unlockButton.node.enabled = not enable

    card.node.findNode("task_play").findNode("card_buttons").alpha = float(enable)
    let flipAnimation = card.node.animationNamed("flip")
    flipAnimation.loopPattern = lpStartToEnd
    flipAnimation.onProgress(1.0)
    card.node.findNode("task_play").rotation = newQuaternion()

    if enable:
        let t = card.desc.getComponent(Text)

        t.color = whiteColor()
        t.text = getDescriptionWithoutTarget(taskForSlot(card.slot).description)
        card.desc.positionY = UNLOCK_POS

        card.setTaskDetails()
        tw.setupSkipFeature(card)
    else:
        card.desc.positionY = NORMAL_POS

proc setUnlock(tw: TasksWindow, card: TasksCard) =
    card.completeButton.node.removeFromParent()
    card.unlockButton.onAction do():
        let quest = getSlotQuest(card.slot)
        if quest.status >= QuestProgress.GoalAchieved:
            tw.close()
            return

        if not quest.isNil and not tw.isBusy:
            var currValue = currentUser().parts
            let zone = findZone($card.slot)

            if quest.config.currency == Currency.TournamentPoint:
                currValue = currentUser().tournPoints

            if zone.getUnlockPrice() > currValue:
                if quest.config.currency == Currency.TournamentPoint:
                    let tpa = sharedWindowManager().show("TourPointsAlertWindow")
                    if card.node.sceneView.GameScene.name != "TiledMapView":
                        tpa.onClose = proc() = discard sharedWindowManager().show("TasksWindow")
                else:
                    discard sharedWindowManager().show("BeamsAlertWindow")
            else:
                card.unlockButton.node.affectsChildrenRec(true)
                card.unlockButton.enabled = false
                zone.unlock do():
                    tw.disableUnlock(card, true)
                    currentNotificationCenter().postNotification("UnlockQuest", newVariant(zone.feature.unlockQuestConf))

proc setComplete(tw: TasksWindow, card: TasksCard) =
    card.unlockButton.node.removeFromParent()
    card.completeButton.title = localizedString("TW_COMPLETE")
    card.completeButton.onAction do():
        if getSlotQuest(card.slot).status >= QuestProgress.Completed:
            tw.close()
            return
        if card.completeButton.node.sceneView.name != "TiledMapView":
            sharedDeepLinkRouter().handle("/scene/TiledMapView/window/QuestWindow")
        else:
            card.completeButton.node.dispatchAction(TryToCompleteQuestAction, newVariant(getSlotQuest(card.slot)))
            card.completeButton.node.dispatchAction(ZoomToZoneAction, newVariant(findZone($card.slot)))
            tw.close()

proc addCard(tw: TasksWindow, bid: BuildingId) =
    var card: TasksCard

    if isSlotAvailable(bid):
        card = createNormalSlotCard(tw, bid)
        tw.positionCard(card)
        card.setTaskDetails()
        tw.setupSkipFeature(card)
    else:
        let quest = getSlotQuest(bid)
        let zone = findZone($bid)

        if not quest.isNil:
            var unlockKey = "TW_UNLOCK_DESC"
            let price = zone.getUnlockPrice()

            card = createNormalSlotCard(tw, bid)
            tw.positionCard(card)
            if bid == ufoSlot:
                unlockKey = "TW_UNLOCK_UFO_DESC"
                discard card.unlockButton.node.findNode("placeholder").addTournamentPointIcon()
            card.unlockButton.title = price.formatThousands()

            let t = card.desc.getComponent(Text)
            t.color = whiteColor()
            t.text = localizedFormat(unlockKey, price.formatThousands())
            tw.disableUnlock(card, false)
            if quest.status == QuestProgress.GoalAchieved:
                tw.setComplete(card)
            else:
                tw.setUnlock(card)
        else:
            var notAvailableKey = "TW_NOT_AVAILABLE_DESC"
            if bid == ufoSlot:
                notAvailableKey = "TW_NOT_AVAILABLE_UFO_DESC"

            let zone = findZone($bid)
            if not zone.isNil and zone.questConfigs.len > 0 and zone.feature.unlockQuestConf.vipOnly:
                card = createVipLockedSlotCard(tw, bid)
            else:
                card = createLockedSlotCard(tw, bid)

                let txtUnlock = card.node.findNode("tw_not_available_desc").getComponent(Text)
                txtUnlock.verticalAlignment = vaCenter
                txtUnlock.text = localizedFormat(notAvailableKey, $zone.getUnlockLevel())
                txtUnlock.node.positionY = txtUnlock.node.positionY - 5
            tw.positionCard(card)

proc checkFreeRoundsSlot(): BuildingId =
    let sortOrder = sharedGameBalance().slotSortOrder

    result = noBuilding

    for s in sortOrder:
        let bid = parseEnum[BuildingId](s, noBuilding)
        if bid != noBuilding:
            let zone = findZone($bid)
            if not zone.isNil:
                let slotFeature = zone.feature.SlotFeature
                if slotFeature.hasFreeRounds:
                    result = bid
                    break

proc checkNewSlot(): BuildingId =
    result = dreamTowerSlot
    for i in 0 .. slots.len - 1:
        if prevActiveSlots[i] == false and slots[i].isSlotAvailable():
            result = slots[i]
            break

    # update previous Slots
    for i in 0 .. slots.len - 1:
        if slots[i].isSlotAvailable():
            prevActiveSlots[i] = true

proc getFirstSlotBuildingId(): BuildingId =
    let sortOrder = sharedGameBalance().slotSortOrder
    for s in sortOrder:
        let bid = parseEnum[BuildingId](s, noBuilding)
        if bid != noBuilding:
            let zone = findZone($bid)
            if not zone.isNil:
                result = bid
                break

proc enableCenterLight(tw: TasksWindow, enabled: bool) =
    let back = tw.rootNode.findNode("task_lightup_bg")
    let fg = tw.rootNode.findNode("task_lightup_fg")
    let pp = fg.findNode("particle_null")
    let anim = fg.component(AEComposition).compositionNamed("play")

    back.enabled = enabled
    fg.enabled = enabled

    if enabled:
        let particle = newNodeWithResource("common/gui/popups/precomps/lightup_prt")

        pp.addChild(particle)
        anim.numberOfLoops = -1
        tw.rootNode.addAnimation(anim)
    else:
        pp.removeAllChildren()
        anim.cancel()


proc setToSlot*(tw: TasksWindow, targetSlot: BuildingId, freeRounds: bool = false) =
    var index = -1
    for c in tw.cards:
        if c.slot == targetSlot:
            if not freeRounds and c.cardType != FreeRounds:
                index = tw.slotsFrameParent.indexOf(c.node)
                break
            elif freeRounds and c.cardType == FreeRounds:
                index = tw.slotsFrameParent.indexOf(c.node)
                break

    if index >= 0:
        let prevOnActionEnd = tw.slotsFrameParent.onActionEnd
        proc onAutoScrollEnds() =
            tw.enableCenterLight(true)
            tw.slotsFrameParent.onActionEnd = prevOnActionEnd

        tw.slotsFrameParent.scrollToIndex(index)
        tw.slotsFrameParent.onActionEnd = onAutoScrollEnds

    if freeRounds:
        let zone = findZone($targetSlot)
        sharedAnalytics().wnd_tasks_open_fr(tw.source, "fr_" & $targetSlot, zone.feature.SlotFeature.passedRounds)
    else:
        let task = taskForSlot(targetSlot).tasks[0]
        sharedAnalytics().wnd_tasks_open(targetSlot, sharedQuestManager().slotStageLevel(targetSlot), task.progresses[0].total.int64, tw.source, $task.difficulty, $task.taskType & "_" & $task.target.BuildingId)


proc setTargetSlot*(tw: TasksWindow, withFreeRounds: bool = false) =
    var targetSlot = noBuilding
    var isFreeRounds = withFreeRounds
    if withFreeRounds:
        targetSlot = checkFreeRoundsSlot()

    if targetSlot == noBuilding:
        isFreeRounds = false
        targetSlot = checkNewSlot()
        if targetSlot == getFirstSlotBuildingId():
            if hasGameState(LAST_SLOT, ANALYTICS_TAG):
                let lastSlot = buildingIdFromClassName(getStringGameState(LAST_SLOT, ANALYTICS_TAG))

                if lastSlot != noBuilding and lastSlot in activeSlots():
                    targetSlot = lastSlot

    tw.setToSlot(targetSlot, isFreeRounds)

proc createContent(tw: TasksWindow) =
    if tw.processClose:
        return

    let sortOrder = sharedGameBalance().slotSortOrder

    for s in sortOrder:
        let bid = parseEnum[BuildingId](s, noBuilding)
        if bid != noBuilding:
            let zone = findZone($bid)
            if not zone.isNil:
                let slotFeature = zone.feature.SlotFeature
                if slotFeature.hasFreeRounds:
                    tw.createFreeRoundsSlotCard(bid, slotFeature)


    for s in sortOrder:
        let bid = parseEnum[BuildingId](s, noBuilding)
        if bid notin [noBuilding]:
            tw.addCard(bid)
    tw.addSoonSlotCard(SoonSlots.Goldmine)

    tw.slotsFrameParent.looped = true
    if isFrameClosed($tsMapQuestReward2):
        addTutorialFlowState(tsTaskWinPlaySlot, true)


method showStrategy*(tw: TasksWindow) =
    tw.node.alpha = 1.0
    tw.rootNode.alpha = 1.0

    let animation = tw.rootNode.animationNamed("in")
    tw.rootNode.addAnimation(animation)

method hideStrategy*(tw: TasksWindow): float =
    let animation = tw.rootNode.animationNamed("out")
    tw.rootNode.addAnimation(animation)
    return animation.loopDuration

method onInit*(tw: TasksWindow) =
    tw.rootNode = newLocalizedNodeWithResource("common/gui/popups/precomps/choose_task")
    tw.parent = tw.anchorNode
    tw.parent.addChild(tw.rootNode)
    tw.rootNode.findNode("text_content_active").component(Text).text = localizedString("CHOOSE_TASK")
    tw.rootNode.findNode("text_content_inactive").component(Text).text = localizedString("CHOOSE_TASK")

    let btnClose = tw.rootNode.findNode("button_close")
    let bc = btnClose.createButtonComponent(btnClose.animationNamed("press"), newRect(10,10,100,100))
    let btnRight = tw.rootNode.findNode("button_right")
    let btnLeft = tw.rootNode.findNode("button_left")

    tw.buttonRight = btnRight.createButtonComponent(btnRight.animationNamed("press"), newRect(10,10,100,100))
    tw.buttonLeft = btnLeft.createButtonComponent(btnLeft.animationNamed("press"), newRect(10,10,100,100))

    let bounds = tw.rootNode.sceneView.bounds
    let vp = tw.rootNode.sceneView.camera.viewportSize
    let coof = clamp((bounds.width / bounds.height) / (vp.width / vp.height), 1.0, 4.0)
    let w = 1920 * coof

    tw.slotsScrollNode =  tw.rootNode.findNode("slots_parent")
    tw.slotsScrollNode.positionY = -500.0
    tw.slotsFrameParent = createNodeScroll(newRect((1920 - w) * 0.5, 120, w, 795), tw.slotsScrollNode)
    tw.slotsFrameParent.scrollDirection = NodeScrollDirection.horizontal
    tw.slotsFrameParent.nodeSize = newSize(SLOTS_DEFAULT_OFFSET, 730)
    tw.slotsFrameParent.contentOffset = newVector3(745)

    tw.rootNode.findNode("grad_l").positionX = tw.rootNode.findNode("grad_l").positionX  + ((1920 - w) * 0.5)
    tw.rootNode.findNode("grad_r").positionX = tw.rootNode.findNode("grad_r").positionX  - ((1920 - w) * 0.5)
    btnLeft.positionX = btnLeft.positionX + ((1920 - w) * 0.5)
    btnRight.positionX = btnRight.positionX - ((1920 - w) * 0.5)

    tw.slotsScrollContent = tw.slotsScrollNode.findNode("NodeScrollContent")
    tw.cards = @[]

    currentNotificationCenter().addObserver("TASK_WINDOW_ANALYTICS_SOURCE", tw) do(args: Variant):
        let source = args.get(string)
        tw.source = source
        currentNotificationCenter().removeObserver("TASK_WINDOW_ANALYTICS_SOURCE", tw)

    bc.onAction do():
        currentNotificationCenter().postNotification("TASKS_WINDOW_CLOSED")
        tw.closeButtonClick()
    tw.buttonRight.onAction do():
        tw.slotsFrameParent.moveRight()
    tw.buttonLeft.onAction do():
        tw.slotsFrameParent.moveLeft()
    btnRight.enabled = false

    let quests = sharedQuestManager().readyTasks()
    if quests.len() > 0:
        tw.createContent()
    else:
        let callback = proc() = tw.createContent()
        sharedQuestManager().generateTask(callback)
    tw.enableCenterLight(true)

    proc disableLight() =
        tw.enableCenterLight(false)

    tw.slotsFrameParent.onActionStart = disableLight

registerComponent(TasksWindow, "windows")
