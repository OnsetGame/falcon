import node_proxy.proxy
import rod / [ node, component]
import rod / component / [ text_component, color_balance_hls, ae_composition, vector_shape ]
import nimx / [ types, matrixes, formatted_text, animation, font ]
import utils / [ helpers, icon_component, color_segments ]
import utils / node_proxies / quest_corner
import core / [zone, zone_helper]
import core / components / [ timer_component, animator ]
import core / helpers / [ color_segments_helper, quest_card_helper ]
import quest / [ quests, quest_icon_component, quest_helpers ]
import falconserver.quest.quest_types
import shared / [ localization_manager, user, game_scene ]
import shared / window / button_component
import falconserver / common / [currency]
import falconserver / map / building / builditem

export zone

import strutils, random

const questBarReadyPath      = "tiledmap/gui/ui2_0/questbar_ready"
const questBarInProgressPath = "tiledmap/gui/ui2_0/questbar_inprogress"
const questBarCompletePath   = "tiledmap/gui/ui2_0/questbar_complete"
const questBarGetRewardPath  = "tiledmap/gui/ui2_0/questbar_getreward"

nodeProxy QuestBarBase:
    smallIconNode* Node {withName:"small_icon"}:
        affectsChildren = false
    smallSegments Node {withName: "small_circle"}

    bigIconNode* Node {withName:"big_circle"}:
        affectsChildren = false

    bigIcon QuestIconComponent {onNodeAdd: "building_placeholder"}

    rewards Node {withName: "rewards"}
    rewardsTint Node {withName:"threedot_holder.png"}
    colorsBack Node {withName: "4colors_back"}
    corner Node {withName: "corner"}:
        enabled = false

    cornerHLS ColorBalanceHLS {onNodeAdd: corner}

    cornerHLSAnimator Animator {onNodeAdd: node}:
        inAnimation = newAnimation()
        inAnimation.numberOfLoops = 1
        inAnimation.loopDuration = random(2.0)
        idleAnimation = newAnimation()
        idleAnimation.numberOfLoops = -1
        idleAnimation.loopDuration = 5.0
        autostart = true

    isCompleted bool

nodeProxy QuestBarReady:
    title* Text {onNode:"quest_title"}:
        node.anchor = newVector3(0, 0)
        boundingSize = newSize(400, 200)
        boundingOffset = newPoint(-200, -100)
        lineSpacing = -11.0
        verticalAlignment = vaCenter

    zoneProgress* Text {onNode:"zone_progress"}:
        lineSpacing = -9.0

    buttonNode* Node {withName: "button"}
    buttonTitle* Text {onNode:"title"}
    buttonIconPlaceholder Node {withName:"currency_placeholder"}
    lockedNode Node {withName:"locket_holder"}:
        enabled = false

    button ButtonComponent

nodeProxy QuestBarInProgress:
    timer TextTimerComponent {onNodeAdd:"timer"}
    buttonNode* Node {withName:"button"}
    buttonTitle* Text {onNode:"title"}
    buttonIconPlaceholder Node {withName:"currency_bucks_placeholder"}
    button ButtonComponent
    signPlaceholder Node {withName:"icons_signs_placeholder"}

nodeProxy QuestBarComplete:
    zoneProgress* Text {onNode:"zone_progress"}:
        lineSpacing = -9.0
    buttonNode* Node {withName:"button"}
    buttonTitle* Text {onNode:"title"}:
        text = localizedString("SPOT_BUILDING_COMPLETE")
    buttonIconPlaceholder Node {withName:"icons_signs_placeholder"}
    colorsHolder Node {withName: "4color_comp"}
    button ButtonComponent

nodeProxy QuestBarGetReward:
    buttonNode* Node {withName:"button"}
    buttonTitle* Text {onNode:"title"}:
        text = localizedString("CQ_GET_REWARD")

    colorsHolder Node {withName: "4color_comp"}
    boxIconPlaceholder Node {withName: "icons_signs_placeholder 2"}

    zoneProgress* Text {onNode:"zone_progress"}:
        lineSpacing = -9.0

    rewardsGlowAnim AEComposition {onNode:"rewards_glow"}
    animator Animator {onNodeAdd: node}:
        inAnimation = np.rewardsGlowAnim.compositionNamed("in")
        idleAnimation = np.rewardsGlowAnim.compositionNamed("idle")
        idleAnimation.numberOfLoops = -1
        autostart = true

    button ButtonComponent

nodeProxy QuestBarNotAvailable:
    title* Text {onNode:"quest_title"}:
        node.positionY = 350.0
        boundingSize = newSize(400, 200)
        boundingOffset = newPoint(-200, -100)
        verticalAlignment = vaCenter
        lineSpacing = -11.0

    zoneProgress Text {onNode:"zone_progress"}:
        lineSpacing = -9.0

    buttonNode Node {withName: "button"}:
        enabled = false

    buttonShadow Node {withName:"button_shadow"}:
        enabled = false

    lockedNode Node {withName:"locket_holder"}
    lockedText Text {onNode: "locked_text"}

type QuestZonePanel* = ref object of RootObj
    base: QuestBarBase
    node*: Node
    zone*: Zone
    questConfig: QuestConfig
    mPriority: int # sorting
    mOnClick: proc(q: Quest)
    mOnQuestStateChanged: proc(p: QuestZonePanel, z: Zone)
    mOnPlayClick: proc()
    mLeadToZone: proc(z: Zone)

type QuestZoneReady* = ref object of QuestZonePanel
    proxy: QuestBarReady

type QuestZoneInProgress* = ref object of QuestZonePanel
    proxy: QuestBarInProgress

type QuestZoneComplete* = ref object of QuestZonePanel
    proxy: QuestBarComplete

type QuestZoneGetReward* = ref object of QuestZonePanel
    proxy: QuestBarGetReward

type QuestZoneNotAvailable* = ref object of QuestZonePanel
    proxy: QuestBarNotAvailable

proc `onClick=`*(qp: QuestZonePanel, cb:proc(q: Quest))=
    qp.mOnClick = cb

proc `onPlayClick=`*(qp: QuestZonePanel, cb:proc())=
    qp.mOnPlayClick = cb

proc `onQuestStateChanged=`*(qp: QuestZonePanel, cb:proc(p: QuestZonePanel, z: Zone))=
    qp.mOnQuestStateChanged = cb

proc `onLeadToZone=`*(qp: QuestZonePanel, cb:proc(z: Zone))=
    qp.mLeadToZone = cb

proc zoneProgressStr(t: Text, zone: Zone)=
    let zoneName = localizedString(zone.name & "_NAME") & "\n"
    t.text = zoneName & $zone.zoneCompletedQuests() & "/" & $zone.questConfigs.len
    t.mText.setTextColorInRange(0, zoneName.len, newColor(255/255, 223/255, 144/255, 1.0))
    t.mText.setTextColorInRange(zoneName.len, -1, whiteColor())

proc priority*(qp: QuestZonePanel): int = qp.mPriority

proc apply4Colors(base: QuestBarBase, conf: ColorSegmentsConf)=
    if base.colorsBack.componentIfAvailable(ColorSegments).isNil:
        base.colorsBack.colorSegmentsForNode(conf)
        base.bigIconNode.colorSegmentsForNode(conf)
        base.smallSegments.colorSegmentsForNode(conf)

        let parent = base.node.parent
        var vs: VectorShape
        if not parent.isNil:
            let seg = parent.findNode("building_name_bg")
            if not seg.isNil:
                vs = seg.component(VectorShape)

        if conf == GraySegmentsConf:
            base.rewardsTint.grayColorSlotNameRect()
            if not vs.isNil:
                vs.color = newColor(94/255, 94/255, 94/255, 1.0)
        elif conf == OrangeSegmentsConf:
            if not vs.isNil:
                vs.color = newColor(145/255, 77/255, 52/255, 1.0)
        elif conf == AquaCardSegmentsConf:
            base.rewardsTint.aquaColorSlotNameRect()
            if not vs.isNil:
                vs.color = newColor(50/255, 78/255, 115/255, 1.0)
        elif conf in [Coffee2SegmentsConf, CoffeeSegmentsConf]:
            base.rewardsTint.coffeeColorSlotNameRect()
            if not vs.isNil:
                vs.color = newColor(153/255, 114/255, 74/255, 1.0)
        else:
            base.rewardsTint.violetColorSlotNameRect()
            if not vs.isNil:
                vs.color = newColor(72/255, 45/255, 120/255, 1.0)


method init*(qp: QuestZonePanel) {.base.} =
    qp.base = new(QuestBarBase, qp.node.findNode("questbar_base"))

    let complQ = qp.zone.zoneCompletedQuests()
    qp.base.isCompleted = complQ >= qp.zone.questConfigs.len

    if qp.base.isCompleted:
        qp.questConfig = qp.zone.questConfigs[^1]
    else:
        qp.questConfig = qp.zone.questConfigs[complQ]

    let q = qp.zone.activeQuest()
    qp.base.bigIcon.configure do():
        qp.base.bigIcon.questConfig = qp.questConfig
        qp.base.bigIcon.iconImageType = if not qp.base.isCompleted: qiitDouble else: qiitSingleMain
        qp.base.bigIcon.mainNode = qp.base.bigIconNode
        qp.base.bigIcon.mainRect = newRect(0.0, 0.0, 280.0, 280.0)
        qp.base.bigIcon.secondaryNode = qp.base.smallIconNode
        qp.base.bigIcon.secondaryRect = newRect(55.0, 15.0, 90.0, 90.0)

    if not q.isNil:
        let n = rewardsIcons(q.rewards)
        n.positionY = -26
        qp.base.rewards.addChild(n)

    if not q.isNil and q.isIncomeQuest():
        qp.base.corner.enabled = true

        qp.mPriority += 200
        var cp = new(CornerRed, qp.base.corner)
        cp.cornerText.text = qp.zone.feature.localizedName()
        qp.base.apply4Colors(VioletSegmentsConf)

        qp.mPriority -= sharedQuestManager().questUnlockLevel(qp.questConfig)
    elif not qp.base.isCompleted and qp.zone.feature.kind != noFeature:
        let unlockQc = qp.zone.feature.unlockQuestConf
        if unlockQc.name == qp.questConfig.name:
            qp.base.corner.enabled = true

            case qp.zone.feature.kind:
                of FeatureType.Slot:
                    qp.mPriority += 300
                    var cp = new(CornerYellow, qp.base.corner)
                    cp.cornerText.text = qp.zone.feature.localizedName()
                    if not q.isNil:
                        qp.base.apply4Colors(AquaCardSegmentsConf)
                    if currentUser().getABOrDefault("quest_corner_hls").len > 0:
                        qp.base.cornerHLSAnimator.idleAnimation.onAnimate = proc(p: float)=
                            qp.base.cornerHLS.hue = p
                else:
                    var cp = new(CornerGreen, qp.base.corner)
                    cp.cornerText.text = qp.zone.feature.localizedName()
                    qp.mPriority += 100
                    if not q.isNil:
                        qp.base.apply4Colors(OrangeSegmentsConf)

            qp.mPriority -= sharedQuestManager().questUnlockLevel(qp.questConfig)

method init(qp: QuestZoneReady) =
    qp.proxy = new(QuestBarReady, newLocalizedNodeWithResource(questBarReadyPath))
    qp.node = qp.proxy.node
    qp.mPriority = 1000

    procCall qp.QuestZonePanel.init()

    qp.proxy.zoneProgress.zoneProgressStr(qp.zone)

    qp.proxy.title.text = localizedString(qp.questConfig.name & "_TITLE")
    qp.proxy.title.color = whiteColor()
    qp.base.apply4Colors(Coffee2SegmentsConf)

    qp.proxy.buttonTitle.text = $qp.questConfig.price
    if qp.questConfig.currency == Currency.Parts:
        discard qp.proxy.buttonIconPlaceholder.addEnergyIcons()
    else:
        let ico = qp.proxy.buttonIconPlaceholder.addTournamentPointIcon()
        ico.hasOutline = true
        #addRewardIcon("tourPoints")
        # qp.proxy.buttonIconPlaceholder.scale = newVector3(0.5, 0.5, 0.5)

    qp.proxy.button = createButtonComponent(qp.proxy.buttonNode, newRect(0,0,350,100))
    qp.proxy.button.onAction do():
        if not qp.mOnClick.isNil():
            qp.mOnClick(qp.zone.activeQuest())

method init(qp: QuestZoneInProgress) =
    qp.proxy =  new(QuestBarInProgress, newLocalizedNodeWithResource(questBarInProgressPath))
    qp.node = qp.proxy.node
    qp.mPriority = 2000
    procCall qp.QuestZonePanel.init()

    let q = qp.zone.activeQuest()
    assert(not q.isNil)

    qp.proxy.timer.timeToEnd = q.config.endTime
    qp.base.apply4Colors(Coffee2SegmentsConf)

    qp.proxy.timer.onUpdate do():
        qp.proxy.buttonTitle.text = $q.speedUpPrice

    qp.proxy.timer.onComplete do():
        q.status = QuestProgress.GoalAchieved
        if not qp.proxy.node.sceneView.isNil:
            qp.proxy.node.sceneView.GameScene.setTimeout(0.1) do():
                if not qp.mOnQuestStateChanged.isNil():
                    qp.mOnQuestStateChanged(qp, qp.zone)

    discard qp.proxy.buttonIconPlaceholder.addBucksIcons()
    discard qp.proxy.signPlaceholder.addSignIcons("lightning")

    qp.proxy.button = createButtonComponent(qp.proxy.buttonNode, newRect(0,0,350,100))
    qp.proxy.button.onAction do():
        if not qp.mOnClick.isNil():
            qp.mOnClick(q)

method init(qp: QuestZoneComplete) =
    qp.proxy = new(QuestBarComplete, newLocalizedNodeWithResource(questBarCompletePath))
    qp.node = qp.proxy.node
    qp.mPriority = 3000
    procCall qp.QuestZonePanel.init()
    qp.proxy.zoneProgress.zoneProgressStr(qp.zone)
    qp.base.apply4Colors(Coffee2SegmentsConf)

    qp.proxy.button = createButtonComponent(qp.proxy.buttonNode, newRect(0,0,350,100))
    qp.proxy.button.onAction do():
        if not qp.mOnClick.isNil():
            qp.mOnClick(qp.zone.activeQuest())

    qp.proxy.colorsHolder.colorSegmentsForNode(GreenSegmentsConf)
    discard qp.proxy.buttonIconPlaceholder.addSignIcons("blue_sign")

method init(qp: QuestZoneGetReward) =
    qp.proxy = new(QuestBarGetReward, newLocalizedNodeWithResource(questBarGetRewardPath))
    qp.node = qp.proxy.node
    qp.mPriority = 4000
    procCall qp.QuestZonePanel.init()
    qp.base.apply4Colors(Coffee2SegmentsConf)

    qp.proxy.button = createButtonComponent(qp.proxy.buttonNode, newRect(0,0,350,100))
    qp.proxy.button.onAction do():
        if not qp.mOnClick.isNil():
            qp.mOnClick(qp.zone.activeQuest())

    qp.proxy.colorsHolder.colorSegmentsForNode(GreenSegmentsConf)
    qp.proxy.zoneProgress.zoneProgressStr(qp.zone)
    discard qp.proxy.boxIconPlaceholder.addSignIcons("box")

method init(qp: QuestZoneNotAvailable) =
    qp.proxy = new(QuestBarNotAvailable, newLocalizedNodeWithResource(questBarReadyPath))
    qp.node = qp.proxy.node
    procCall qp.QuestZonePanel.init()

    qp.base.rewards.enabled = false
    qp.proxy.zoneProgress.zoneProgressStr(qp.zone)
    if not qp.base.isCompleted:
        qp.proxy.title.text = localizedString(qp.questConfig.name & "_TITLE")
    else:
        qp.proxy.title.text = localizedString(qp.zone.name & "_NAME")
    qp.proxy.title.color = whiteColor()
    let lockLvl = sharedQuestManager().questUnlockLevel(qp.questConfig)

    let lc = qp.zone.lockedByZone()

    if qp.base.isCompleted:
        qp.proxy.lockedText.text = localizedString("SPOT_COMING_SOON")
    else:
        var setupLeadBtn = true
        let btn = qp.proxy.lockedText.node.parent.createButtonComponent(newRect(-170,-50,340,100))

        if not lc.isNil:
            qp.proxy.lockedText.text = localizedString("BUILD_TO_UNLOCK") % [lc.localizedName()]
        elif qp.zone.isSlot() and getVipZoneLevel(parseEnum[BuildingId](qp.zone.name)) > currentUser().vipLevel:
            let lvl = getVipZoneLevel(parseEnum[BuildingId](qp.zone.name))

            qp.proxy.lockedText.text = localizedString("OPEN_SLOT_ON_VIP") % [$lvl]
        elif lockLvl > currentUser().level:
            qp.proxy.lockedText.text = localizedString("TW_NOT_AVAILABLE_DESC") % [$lockLvl]
            btn.onAction do():
                if not qp.mOnPlayClick.isNil:
                    qp.mOnPlayClick()
            setupLeadBtn = false
        else:
            qp.proxy.lockedText.text = localizedString("MAP_COMPLETE_TO_UNLOCK")

        if setupLeadBtn:
            btn.onAction do():
                if not qp.mLeadToZone.isNil:
                    qp.mLeadToZone(lc)

    qp.proxy.lockedText.color = whiteColor()
    qp.base.apply4Colors(GraySegmentsConf)

proc createQuestBarForZone*(zone: Zone): QuestZonePanel=
    var panel: QuestZonePanel

    let q = zone.activeQuest()
    if not q.isNil:
        case q.status:
        of QuestProgress.Ready:
            panel = new(QuestZoneReady)
        of QuestProgress.InProgress:
            panel = new(QuestZoneInProgress)
        of QuestProgress.GoalAchieved:
            panel = new(QuestZoneComplete)
        of QuestProgress.Completed:
            panel = new(QuestZoneGetReward)
        else:
            discard
    else:
        panel = new(QuestZoneNotAvailable)
    panel.zone = zone
    panel.init()

    result = panel
