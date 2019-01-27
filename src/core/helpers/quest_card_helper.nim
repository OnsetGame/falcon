import tables, sequtils, logging, algorithm
import rod / node
import rod / component / text_component
import quest / quests
import core / zone
import node_proxy / proxy
import utils / node_proxies / quest_corner
import utils / [color_segments, icon_component]
import nimx / [types, matrixes, font]
import core / helpers / [ boost_multiplier, reward_helper ]
import core / features / booster_feature


import color_segments_helper
export CardStyle


var configs: array[CardStyle.low .. CardStyle.high, ColorSegmentsConf]
configs[Coffee] = Coffee2SegmentsConf
configs[Orange] = OrangeSegmentsConf
configs[Aqua] = AquaCardSegmentsConf
configs[Purple] = VioletSegmentsConf
configs[Grey] = GraySegmentsConf

var tints: array[CardStyle.low .. CardStyle.high, proc(node: Node)]
tints[Coffee] = coffeeColorSlotNameRect
tints[Orange] = orangeColorSlotNameRect
tints[Aqua] = aquaColorSlotNameRect
tints[Purple] = violetColorSlotNameRect
tints[Grey] = grayColorSlotNameRect


proc getCardStyle*(q: Quest): CardStyle =
    if q.config.unlockFeature == FeatureType.Slot:
        return CardStyle.Aqua

    for reward in q.rewards:
        if reward.kind in [RewardKind.incomeChips, RewardKind.incomeBucks]:
            return CardStyle.Purple

    if q.config.unlockFeature != noFeature:
        return CardStyle.Orange

    return CardStyle.Coffee


proc backgroundForQuest*(n: Node, q: Quest) =
    # if not n.componentIfAvailable(ColorSegments).isNil:
    #     return
    n.colorSegmentsForNode(configs[getCardStyle(q)])


proc tintForQuest*(n: Node, q: Quest) =
    tints[getCardStyle(q)](n)


proc cornerForQuest*(n: Node, q: Quest) =
    n.alpha = 1.0

    case getCardStyle(q):
        of Orange:
            let proxy = CornerGreen.new(newNodeWithResource("tiledmap/gui/ui2_0/corner_placeholder"))
            n.addChild(proxy.node)
            let zone = findZone(q.config.targetName)
            proxy.cornerText.text = zone.feature.localizedName()
        of Aqua:
            let proxy = CornerYellow.new(newNodeWithResource("tiledmap/gui/ui2_0/corner_placeholder"))
            n.addChild(proxy.node)
            let zone = findZone(q.config.targetName)
            proxy.cornerText.text = zone.feature.localizedName()
        of Purple:
            let proxy = CornerRed.new(newNodeWithResource("tiledmap/gui/ui2_0/corner_placeholder"))
            n.addChild(proxy.node)
            let zone = findZone(q.config.targetName)
            proxy.cornerText.text = zone.feature.localizedName()
        else:
            if not q.config.isMain:
                n.alpha = 0.0

proc rewardToBoosterType(rk: RewardKind): BoosterTypes =
    case rk
    of RewardKind.boosterExp:
        result = BoosterTypes.btExperience
    of RewardKind.boosterIncome:
        result = BoosterTypes.btIncome
    of RewardKind.boosterTourPoints:
        result = BoosterTypes.btTournamentPoints
    else:
        error "No booster type for ", $rk

proc rewardsIcons*(rewards: seq[Reward]): Node =
    result = newNode()

    var rewards = rewards.prioritizedRewards()
    if rewards.len > 4:
        rewards.setLen(4)

    let s: Size = newSize(120, 120)
    let offset: float = 85

    var width = 0.0
    for reward in rewards:
        var iconName = reward.icon

        let parentNode = result.newChild(iconName)
        var ico: IconComponent
        if reward.isBooster():
            let icoAnchor = parentNode.newChild("icoAnchor")
            ico = icoAnchor.addRewardIcon(iconName)
            let bm = parentNode.addBoostMultiplier(pos = newVector3(55.0, 65.0), scale = 0.3)
            bm.text = boostMultiplierText(rewardToBoosterType(reward.kind))
            parentNode.positionX = width
        else:
            ico = parentNode.addRewardIcon(iconName)
            ico.node.positionX = width

        ico.rect = newRect(newPoint(0,0), s)
        width += offset

    result.anchor = newVector3(width * 0.5)
    result.positionX = -15.0


proc rewardsForQuest*(n: Node, q: Quest) =
    let rewardsNode = rewardsIcons(q.rewards)
    n.addChild(rewardsNode)

    proc tryAddOutlineToIcon(n: Node) =
        let ic = n.getComponent(IconComponent)
        if not ic.isNil:
            ic.outlineRadius(20.0)

    for child in rewardsNode.children:
        child.tryAddOutlineToIcon()
        for grandChild in child.children:
            grandChild.tryAddOutlineToIcon()

