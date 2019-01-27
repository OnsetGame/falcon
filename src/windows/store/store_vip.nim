import sequtils

import nimx / [types, matrixes]
import rod / node
import rod / component / [text_component]
import node_proxy / proxy
import shared / [localization_manager, user]
import utils / node_scroll
import core / components / layout_component
import core / features / [vip_system, booster_feature]
import core / helpers / reward_helper
import utils / icon_component

import store_tab

const CARD_SIZE = newSize(384, 688)

nodeProxy VipTabHead:
    benefitsTitle Text {onNode: "benefits_title"}:
        text = localizedString("VIP_HEAD_BENEFITS")
    vipLevelTitle Text {onNode: "vip_level_title"}:
        text = localizedString("VIP_HEAD_LEVEL")
        lineSpacing = -6.0
    vipAccessTitle Text {onNode: "vip_access_title"}:
        text = localizedString("VIP_HEAD_ACCESS")
    vipPointsTitle Text {onNode: "vip_points_title"}:
        text = localizedString("VIP_HEAD_POINTS")
    purchaseBonusTitle Text {onNode: "purchase_bonus_title"}:
        text = localizedString("VIP_HEAD_BONUS")
        lineSpacing = -10.0
        bounds = newRect(-125.0, -32.0, 250.0, 70.0)
    layout LayoutComponent {onNodeAdd: node}:
        rel = lrLeft
        withScale = false
        withMinMax = true


nodeProxy VipTab of StoreTab:
    head VipTabHead {withValue: VipTabHead.new(np.node.findNode("vip_store_head"))}
    leftShadowLayout LayoutComponent {onNodeAdd: "grad_l"}:
        rel = lrLeft
        withScale = false
        withMinMax = true
    rightShadowLayout LayoutComponent {onNodeAdd: "grad_r"}:
        rel = lrRight
        withScale = false
        withMinMax = true

    cards NodeScroll
    cardsWrapper Node {withName: "vip_cards_parent"}
    cardsWrapperWidth float {withValue: 1633.0}
    cardsWrapperLayout LayoutComponent {onNodeAdd: cardsWrapper}:
        rel = lrLeft
        withScale = false
        withMinMax = true

        flex = lfrLeftRight
        size = newSize(1633.0, CARD_SIZE.height)
        onResize = proc(newSize: Size) =
            np.cardsWrapperWidth = newSize.width
            if not np.cards.isNil:
                np.cards.resize(newSize)


nodeProxy CurBonus:
    icon IconComponent {onNode: "icon"}
    percents Text {onNode: "percents"}


proc new(T: typedesc[CurBonus], n: Node, icon: string): T =
    let np = CurBonus.new(n)
    np.icon.name = icon
    result = np


proc setValue(np: CurBonus, value: float) =
    np.percents.text = $(value * 100).int & "%"


const BENEFIT_ITEM_SIZE = newSize(100, 110)


nodeProxy BenefitItem:
    icon IconComponent {onNode: "icon"}
    slotIcon IconComponent {onNode: "slot_icon"}:
        node.scale = newVector3(1.5, 1.5, 1)
    title Text {onNode: "title"}

    blueStar Node {withName: "blue_star"}:
        alpha = 0.0
    ratio Text {onNode: "ratio"}


proc new(T: typedesc[BenefitItem], reward: Reward): T =
    let np = BenefitItem.new(newNodeWithResource("common/gui/popups/precomps/vip_card_benefit"))

    var isSlot = false
    np.title.text = reward.localizedCount(minimized = true)
    
    case reward.kind:
        of RewardKind.boosterExp, RewardKind.boosterIncome, RewardKind.boosterTourPoints:
            np.blueStar.alpha = 1.0
            if reward.kind == RewardKind.boosterExp:
                np.ratio.text = btExperience.boostMultiplierText()
            elif reward.kind == RewardKind.boosterIncome:
                np.ratio.text = btIncome.boostMultiplierText()
            else:
                np.ratio.text = btTournamentPoints.boostMultiplierText()
        of RewardKind.exchange:
            np.title.text = "+" & np.title.text
        of RewardKind.wheel:
            np.blueStar.alpha = 1.0
            np.ratio.text = localizedString("TR_FREE")
        of RewardKind.vipaccess:
            isSlot = true
        else:
            discard

    if isSlot:
        np.slotIcon.node.alpha = 1.0
        np.slotIcon.name = reward.ZoneReward.zone
        np.icon.node.alpha = 0.0
        # np.title.node.alpha = 0.0
        np.title.text = localizedString("VIP_REWARD_SLOT")
    else:
        np.slotIcon.node.alpha = 0.0
        np.icon.node.alpha = 1.0
        np.icon.name = reward.icon

    result = np


nodeProxy BenefitLine:
    len int


proc addReward(np: BenefitLine, reward: Reward) =
    let benefitItem = BenefitItem.new(reward)
    np.node.addChild(benefitItem.node)
    for c in np.node.children:
        c.positionX = c.positionX - BENEFIT_ITEM_SIZE.width / 2
    benefitItem.node.position = newVector3(BENEFIT_ITEM_SIZE.width * (np.len.float - 1.0) / 2.0, 0)
    np.len.inc


nodeProxy VipCard:
    level int

    vipLvl Text {onNode: "vip_lvl"}
    vipIcon IconComponent {onNode: "reward_icon_diamond"}
    vipPoints Text {onNode: "vip_points_for_lvl"}

    user User
    inactiveBg Node: {withName: "vip_card_bg2", observe: user}:
        alpha = float(np.user.vipLevel != np.level)
    activeBg Node {withName: "vip_card_bg1", observe: user}:
        alpha = float(np.user.vipLevel == np.level)

    bonusChips CurBonus {withValue: CurBonus.new(np.node.findNode("vip_card_pbonus_chips"), "chips")}
    bonusBucks CurBonus {withValue: CurBonus.new(np.node.findNode("vip_card_pbonus_bucks"), "bucks")}

    benefitsLine1 BenefitLine {withValue: BenefitLine.new(np.node.findNode("vip_card_benefit_line1"))}
    benefitsLine2 BenefitLine {withValue: BenefitLine.new(np.node.findNode("vip_card_benefit_line2"))}

    vipAccessLine BenefitLine {withValue: BenefitLine.new(np.node.findNode("vip_card_access_line"))}


proc newVipCard(level: VipLevel): VipCard =
    let node = newNodeWithResource("common/gui/popups/precomps/vip_card")
    let card = VipCard.new(node)

    card.level = level.level
    card.vipLvl.text = $level.level
    card.vipPoints.text = $level.pointsRequired
    card.bonusChips.setValue(level.chipsBonus)
    card.bonusBucks.setValue(level.bucksBonus)

    card.user = currentUser()
    card.inactiveBg.alpha = float(card.user.vipLevel != card.level)
    card.activeBg.alpha = float(card.user.vipLevel == card.level)

    let rewards = level.rewards.filterVipRewards().filter(proc(reward: Reward): bool = reward.kind notin [RewardKind.bucksPurchaseBonus, RewardKind.chipsPurchaseBonus, RewardKind.exchange, RewardKind.vipaccess])

    const itemsPerLine = 3

    for i in 0 ..< min(rewards.len, itemsPerLine):
        card.benefitsLine1.addReward(rewards[i])
    if rewards.len <= itemsPerLine:
        card.benefitsLine1.node.anchor = newVector3(0, -BENEFIT_ITEM_SIZE.height / 2)
    else:
        card.benefitsLine1.node.anchor = newVector3(0, 0)
        for i in min(rewards.len, itemsPerLine) ..< min(rewards.len, 2 * itemsPerLine):
            card.benefitsLine2.addReward(rewards[i])
    
    if level.exchangeBonus > 0:
        card.vipAccessLine.addReward(createReward(RewardKind.exchange, (level.exchangeBonus * 100).int64))

    let accessRewards = level.rewards.filterVipRewards().filter(proc(reward: Reward): bool = reward.kind == RewardKind.vipaccess)
    for reward in accessRewards:
        card.vipAccessLine.addReward(reward)

    result = card


proc createVipTab*(n: Node, source: string, currTaskProgress: float): VipTab =
    let tab = VipTab.new(newNodeWithResource("common/gui/popups/precomps/vip_store"))
    tab.source = source
    tab.currTaskProgress = currTaskProgress
    n.addChild(tab.node)

    tab.cards = createNodeScroll(newRect(0, 0, tab.cardsWrapperWidth, CARD_SIZE.height), tab.cardsWrapper)
    tab.cards.nodeSize = CARD_SIZE
    tab.cards.scrollDirection = NodeScrollDirection.horizontal

    for i, lvl in sharedVipConfig().levels:
        let proxy = lvl.newVipCard()
        proxy.node.position = newVector3(CARD_SIZE.width * i.float, 0)
        tab.cards.addChild(proxy.node)

    tab.cards.scrollToIndex(currentUser().vipLevel)
    tab.cards.onActionProgress = proc() =
        if tab.cards.scrollX == 0.0:
            # tab.leftShadowLayout.node.alpha = 0.0
            tab.rightShadowLayout.node.alpha = 1.0
        elif tab.cards.scrollX == 1.0:
            tab.leftShadowLayout.node.alpha = 1.0
            tab.rightShadowLayout.node.alpha = 0.0
        else:
            tab.leftShadowLayout.node.alpha = 1.0
            tab.rightShadowLayout.node.alpha = 1.0

    result = tab


proc scrollToCurrentLevel*(tab: VipTab) =
    tab.cards.scrollToIndex(currentUser().vipLevel)


method remove*(tab: VipTab, removeFromParent: bool = true) =
    procCall tab.StoreTab.remove(removeFromParent)