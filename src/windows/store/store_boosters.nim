import logging, times, json, tables
import rod / node
import rod / component / [text_component]
import nimx / [types, animation, matrixes, font]
import node_proxy / proxy
import utils / [helpers, icon_component, falcon_analytics]
import shared / [localization_manager, game_scene, tutorial]
import shared / window / button_component
import core / helpers / color_segments_helper
import core / components / timer_component
import core / features / [booster_feature, vip_system]
import core / zone
import core / net / server

import map / collect_resources

import store_tab

type BoosterCardKind {.pure.} = enum
    Experience = "BOOSTER_EXPERIANCE"
    Income = "BOOSTER_INCOME"
    Tournaments = "BOOSTER_TOURNAMENTS"
    Premium = "BOOSTER_PREMIUM"


proc activateBooster(kind: BoosterCardKind, cb: proc()) =
    case kind:
        of BoosterCardKind.Experience:
            sharedServer().activateBooster($btExperience) do(r: JsonNode):
                cb()
        of BoosterCardKind.Tournaments:
            sharedServer().activateBooster($btTournamentPoints) do(r: JsonNode):
                cb()
        of BoosterCardKind.Income:
            sharedServer().activateBooster($btIncome) do(r: JsonNode):
                cb()
        else:
            discard


proc buyBooster(bundleId:string, cb: proc()) =
    cb()


type BoosterCardPayableKind {.pure.} = enum
    Payable
    Renew
    Expired


nodeProxy BoosterCard:
    title Text {onNode: "card_title"}:
        bounds = newRect(-175, -np.title.fontSize, 350, 120)
        verticalAlignment = vaTop
        lineSpacing = -6.0
    vipIcon IconComponent {onNode: "vip_icon"}:
        node.alpha = 0.0
    vipPoints Text {onNode: "vip_points"}:
        node.alpha = 0.0
    durationNum Text {onNode: "duration_num"}
    durationTxt Text {onNode: "duration_txt"}

    boostPremium Node {withName: "boost_premium"}
    boostExperience Node {withName: "boost_experience"}
    boosterTournaments Node {withName: "boost_tournament"}

    payBttnNode Node {withName: "booster_pay_bttn"}:
        alpha = 0.0
    payBttnTitle Text {onNode: np.payBttnNode.findNode("title")}
    freeBttnNode Node {withName: "booster_free_bttn"}:
        alpha = 0.0
    freeBttnTitle Text {onNode: np.freeBttnNode.findNode("title")}:
        text = localizedString("BOOSTER_FREE")

    background Node {withName: "background_segments"}

    onAction proc()
    mainButton ButtonComponent {withValue: np.node.createButtonComponent(newRect(0, 570, 435, 140))}:
        onAction do():
            if not np.onAction.isNil:
                np.onAction()

method deactivate(card: BoosterCard) {.base.} =
    card.onAction = nil
    card.mainButton.node.removeComponent(ButtonComponent)


proc moneyParts(price: int): (string, string) =
    let p1 = price div 100
    let p2 = price - (p1 * 100)
    return ($p1, if p2 < 10: "0" & $p2 else: $p2)


method setPrice(card: BoosterCard, price: int) {.base.} =
    if price > 0:
        card.payBttnNode.alpha = 1.0
        card.freeBttnNode.alpha = 0.0
        let (p1, p2) = price.moneyParts()
        card.payBttnTitle.text = localizedFormat("BOOSTER_MONEY_FORMAT", $p1, $p2)
        card.mainButton.animation = card.payBttnNode.animationNamed("press")
    else:
        card.payBttnNode.alpha = 0.0
        card.freeBttnNode.alpha = 1.0
        card.mainButton.animation = card.freeBttnNode.animationNamed("press")

method setTimeout(card: BoosterCard, timeout: float) {.base.} =
    discard

method setVipPoints(card: BoosterCard, points: int) {.base.} =
    if points > 0:
        card.vipIcon.node.alpha = 1.0
        card.vipPoints.node.alpha = 1.0
        card.vipPoints.text = "+" & $points
    else:
        card.vipIcon.node.alpha = 0.0
        card.vipPoints.node.alpha = 0.0

method setDuration(card: BoosterCard, dur: int) {.base.} =
    var days = dur div (3600 * 24)
    if days > 1:
        card.durationNum.text = $days
        card.durationTxt.text = localizedString("BOOSTER_DAYS")
    elif days == 1:
        card.durationNum.text = $days
        card.durationTxt.text = localizedString("BOOSTER_DAY")
    else:
        let hours = dur div 3600
        if hours > 1:
            card.durationNum.text = $hours
            card.durationTxt.text = localizedString("BOOSTER_HOURS")
        else:
            card.durationNum.text = "1"
            card.durationTxt.text = localizedString("BOOSTER_HOUR")

method setOldPrice(card: BoosterCard, price: int) {.base.} =
    discard


nodeProxy PayableBoosterCard of BoosterCard:
    desc Text {onNode: "card_desc"}:
        bounds = newRect(-175, -np.desc.fontSize, 350, 120)
        verticalAlignment = vaTop
        shadowOffset = newSize(0, 2)
        shadowRadius = 4.0
        shadowColor = newColor(0, 0, 0, 0)
        lineSpacing = -6.0

    boosterIncome Node {withName: "boost_city_table"}

    activateBttnNode Node {withName: "booster_activate_bttn"}:
        alpha = 0.0


nodeProxy PayableIncomeBoosterCard of PayableBoosterCard:
    incomeCurrentText Text {onNode: "current_txt"}:
        text = localizedString("BOOSTER_CURRENT")
    incomeBoostedText Text {onNode: "boosted_txt"}:
        text = localizedString("BOOSTER_BOOSTED")
    incomeBoostedText2 Text {onNode: "boosted_txt2"}:
        text = localizedString("BOOSTER_BOOSTED")

    incomeChips Text {onNode: "income_chips"}
    incomeBucks Text {onNode: "income_bucks"}
    incomeChipsBoosted Text {onNode: "boosted_income_chips"}
    incomeBucksBoosted Text {onNode: "boosted_income_bucks"}


nodeProxy PayablePremiumBoosterCard of PayableBoosterCard:
    oldPriceNode Node {withName: "boost_old_price_comp"}
        #alpha = 1.0
    oldPriceTxt Text {onNode: "booster_old_price"}


method setOldPrice(card: PayablePremiumBoosterCard, price: int) =
    let (p1, p2) = price.moneyParts()
    card.oldPriceTxt.text = "$" & p1 & "." & p2


proc new(T: typedesc[PayableBoosterCard], n: Node, kind: BoosterCardKind): PayableBoosterCard =
    case kind:
        of BoosterCardKind.Premium:
            result = PayablePremiumBoosterCard.new(n)

            result.desc.color = newColor(1.0, 1.0, 1.0)
            result.desc.shadowColor = newColor(0, 0, 0, 0.4)
            result.desc.node.alpha = 1.0

            result.background.colorSegmentsForNode(AquaCardSegmentsConf)
            result.boostPremium.alpha = 1.0
            result.boostExperience.alpha = 0.0
            result.boosterTournaments.alpha = 0.0
            result.boosterIncome.alpha = 0.0
        of BoosterCardKind.Experience:
            result = PayableBoosterCard.new(n)

            result.background.colorSegmentsForNode(Coffee2SegmentsConf)
            result.boostPremium.alpha = 0.0
            result.boostExperience.alpha = 1.0
            result.boosterTournaments.alpha = 0.0
            result.boosterIncome.alpha = 0.0
        of BoosterCardKind.Tournaments:
            result = PayableBoosterCard.new(n)

            result.background.colorSegmentsForNode(Coffee2SegmentsConf)
            result.boostPremium.alpha = 0.0
            result.boostExperience.alpha = 0.0
            result.boosterTournaments.alpha = 1.0
            result.boosterIncome.alpha = 0.0
        of BoosterCardKind.Income:
            let card = PayableIncomeBoosterCard.new(n)

            card.background.colorSegmentsForNode(Coffee2SegmentsConf)
            card.desc.node.alpha = 0.0
            card.boostPremium.alpha = 0.0
            card.boostExperience.alpha = 0.0
            card.boosterTournaments.alpha = 0.0
            card.boosterIncome.alpha = 1.0

            let incomeChips = resourcePerHour(Currency.Chips)
            let incomeBucks = resourcePerHour(Currency.Bucks)
            let boostedIncomeChips = (2.0 * incomeChips.float).int
            let boostedIncomeBucks = (2.0 * incomeBucks.float).int

            card.incomeChips.text = formatThousands(incomeChips)
            card.incomeBucks.text = formatThousands(incomeBucks)
            card.incomeChipsBoosted.text = formatThousands(boostedIncomeChips)
            card.incomeBucksBoosted.text = formatThousands(boostedIncomeBucks)

            result = card
        else:
            discard

    result.title.text = localizedString($kind & "_DEFAULT_TITLE")
    result.desc.text = localizedString($kind & "_DESC")


method setPrice(card: PayableBoosterCard, price: int) =
    if price < 0:
        card.activateBttnNode.alpha = 1.0
        card.activateBttnNode.findNode("title").component(Text).text = localizedString("BOOSTER_ACTIVATE")
        card.mainButton.animation = card.activateBttnNode.animationNamed("press")

        card.durationNum.node.alpha = 0.0
        card.durationTxt.node.alpha = 0.0
    else:
        card.activateBttnNode.alpha = 0.0
        card.durationNum.node.alpha = 1.0
        card.durationTxt.node.alpha = 1.0
        procCall card.BoosterCard.setPrice(price)


nodeProxy RenewBoosterCard of BoosterCard:
    boosterIncome Node {withName: "boost_city"}

    activeBackground Node {withName: "active_background"}:
        colorSegmentsForNode((
            angle1: 0.0,
            angle2: 0.0,
            colors: [
                newColor(19.0/255.0, 234.0/255.0, 253.0/255.0, 1.0),
                newColor(14.0/255.0, 212.0/255.0, 250.0/255.0, 1.0),
                newColor(8.0/255.0, 190.0/255.0, 247.0/255.0, 1.0),
                newColor(3.0/255.0, 169.0/255.0, 244.0/255.0, 1.0)
            ]
        ))
    activeText Text {onNode: "active_txt"}:
        text = localizedString("BOOSTER_ACTIVE")
    prolongText Text {onNode: "prolong_txt"}:
        text = localizedString("BOOSTER_PROLONG")

    timer TextTimerComponent {onNodeAdd: "timer"}
    timerActive Node {withName: "timer_green"}:
        alpha = 0.0
    timerExpires Node {withName: "timer_red"}:
        alpha = 0.0


proc new(T: typedesc[RenewBoosterCard], n: Node, kind: BoosterCardKind): T =
    let card = T.new(n)

    card.title.text = localizedString($kind & "_ACTIVE_TITLE")
    card.background.colorSegmentsForNode(DeepGreenSegmentConf)

    case kind:
        of BoosterCardKind.Premium:
            card.boostPremium.alpha = 1.0
            card.boostExperience.alpha = 0.0
            card.boosterTournaments.alpha = 0.0
            card.boosterIncome.alpha = 0.0
        of BoosterCardKind.Experience:
            card.boostPremium.alpha = 0.0
            card.boostExperience.alpha = 1.0
            card.boosterTournaments.alpha = 0.0
            card.boosterIncome.alpha = 0.0
        of BoosterCardKind.Tournaments:
            card.boostPremium.alpha = 0.0
            card.boostExperience.alpha = 0.0
            card.boosterTournaments.alpha = 1.0
            card.boosterIncome.alpha = 0.0
        of BoosterCardKind.Income:
            card.boostPremium.alpha = 0.0
            card.boostExperience.alpha = 0.0
            card.boosterTournaments.alpha = 0.0
            card.boosterIncome.alpha = 1.0
        else:
            discard

    result = card


method deactivate(card: RenewBoosterCard) =
    procCall card.BoosterCard.deactivate()
    card.timer.node.removeComponent(TextTimerComponent)


method setTimeout(card: RenewBoosterCard, timeout: float) =
    card.timer.timeToEnd = timeout
    card.timer.onUpdate() do():
        if timeout - epochTime() > (5 * 60):
            card.timerActive.alpha = 1.0
            card.timerExpires.alpha = 0.0
        else:
            card.timerActive.alpha = 0.0
            card.timerExpires.alpha = 1.0


nodeProxy ExpiredBoosterCard of BoosterCard:
    boosterIncome Node {withName: "boost_city"}

    tryAgainText Text {onNode: "try_again_txt"}:
        text = localizedString("BOOSTER_TRY_AGAIN")

    expiredBackground Node {withName: "expired_background"}:
        colorSegmentsForNode((
            angle1: 0.0,
            angle2: 0.0,
            colors: [
                newColor(255.0/255.0, 215.0/255.0, 45.0/255.0, 1.0),
                newColor(255.0/255.0, 194.0/255.0, 30.0/255.0, 1.0),
                newColor(255.0/255.0, 173.0/255.0, 15.0/255.0, 1.0),
                newColor(255.0/255.0, 152.0/255.0, 0.0/255.0, 1.0)
            ]
        ))
    expiredText Text {onNode: "expired_txt"}:
        text = localizedString("BOOSTER_EXPIRED")


proc new(T: typedesc[ExpiredBoosterCard], n: Node, kind: BoosterCardKind): T =
    let card = T.new(n)

    card.title.text = localizedString($kind & "_EXPIRED_TITLE")
    card.background.colorSegmentsForNode(RedSegmentConf)

    case kind:
        of BoosterCardKind.Premium:
            card.boostPremium.alpha = 1.0
            card.boostExperience.alpha = 0.0
            card.boosterTournaments.alpha = 0.0
            card.boosterIncome.alpha = 0.0
        of BoosterCardKind.Experience:
            card.boostPremium.alpha = 0.0
            card.boostExperience.alpha = 1.0
            card.boosterTournaments.alpha = 0.0
            card.boosterIncome.alpha = 0.0
        of BoosterCardKind.Tournaments:
            card.boostPremium.alpha = 0.0
            card.boostExperience.alpha = 0.0
            card.boosterTournaments.alpha = 1.0
            card.boosterIncome.alpha = 0.0
        of BoosterCardKind.Income:
            card.boostPremium.alpha = 0.0
            card.boostExperience.alpha = 0.0
            card.boosterTournaments.alpha = 0.0
            card.boosterIncome.alpha = 1.0
        else:
            discard

    result = card


nodeProxy BoosterCardsSet:
    expired Node {withName: "boost_expired"}:
        alpha = 0.0
    active Node {withName: "boost_active"}:
        alpha = 0.0
    normal Node {withName: "boost_normal"}:
        alpha = 0.0
    curCard BoosterCard
    kind BoosterCardKind

proc new(T: typedesc[BoosterCardsSet], n: Node, kind: BoosterCardKind): T =
    result = T.new(n)
    result.kind = kind


proc setActive(s: BoosterCardsSet, payableKind: BoosterCardPayableKind) =
    if not s.curCard.isNil:
        s.curCard.deactivate()

    case payableKind:
        of Payable:
            s.expired.alpha = 0.0
            s.active.alpha = 0.0
            s.normal.alpha = 1.0
            let booster = PayableBoosterCard.new(s.normal, s.kind)
            s.curCard = booster
        of Renew:
            s.expired.alpha = 0.0
            s.active.alpha = 1.0
            s.normal.alpha = 0.0
            s.curCard = RenewBoosterCard.new(s.active, s.kind)
        of Expired:
            s.expired.alpha = 1.0
            s.active.alpha = 0.0
            s.normal.alpha = 0.0
            s.curCard = ExpiredBoosterCard.new(s.expired, s.kind)
        else:
            discard


template setPrice(s: BoosterCardsSet, price: int) =
    s.curCard.setPrice(price)


template setOldPrice(s: BoosterCardsSet, price: int) =
    s.curCard.setOldPrice(price)


template setTimeout(s: BoosterCardsSet, timeout: float) =
    s.curCard.setTimeout(timeout)


template setVipPoints(s: BoosterCardsSet, points: int) =
    s.curCard.setVipPoints(points)


template setDuration(s: BoosterCardsSet, points: int) =
    s.curCard.setDuration(points)


template setAction(s: BoosterCardsSet, cb: proc()) =
    s.curCard.onAction = cb


template deactivate(s: BoosterCardsSet) =
    s.curCard.deactivate()


proc setData(s: BoosterCardsSet, data: BoosterData) =
    let vipConfig = sharedVipConfig()

    if data.durationTime > 0:
        if data.isFree:
            s.setActive(BoosterCardPayableKind.Payable)
            s.setPrice(0)
            s.setVipPoints(-1)
            s.setDuration(data.durationTime.int)
        else:
            s.setActive(BoosterCardPayableKind.Payable)
            s.setPrice(-1)
            s.setVipPoints(-1)
            s.setDuration(data.durationTime.int)
        s.setAction() do():
            s.curCard.mainButton.enabled = false
            findFeature(BoosterFeature).activateBoosterAnalytics(data.kind, true)
            activateBooster(s.kind) do():
                s.curCard.mainButton.enabled = true
    elif data.expirationTime >= epochTime():
        s.setActive(BoosterCardPayableKind.Renew)
        s.setTimeout(data.expirationTime)
        s.setAction() do():
            s.curCard.mainButton.enabled = false
    else:
        s.setActive(BoosterCardPayableKind.Payable)

nodeProxy BoostersTab of StoreTab:
    incomeBoosterSet BoosterCardsSet {withValue: BoosterCardsSet.new(np.node.findNode("income_booster_frame"), BoosterCardKind.Income)}
    premiumBoosterSet BoosterCardsSet {withValue: BoosterCardsSet.new(np.node.findNode("premium_booster_frame"), BoosterCardKind.Premium)}
    tournamentsBoosterSet BoosterCardsSet {withValue: BoosterCardsSet.new(np.node.findNode("tournaments_booster_frame"), BoosterCardKind.Tournaments)}
    experienceBoosterSet BoosterCardsSet {withValue: BoosterCardsSet.new(np.node.findNode("experience_booster_frame"), BoosterCardKind.Experience)}

    unsubscribeFeatures proc()

proc setDefaultBooster(t: BoostersTab, bcs: BoosterCardsSet) =
    bcs.setActive(BoosterCardPayableKind.Payable)
    bcs.setAction() do():
        bcs.curCard.mainButton.enabled = false

proc subscribeFeatures*(t: BoostersTab) =
    let feature = findFeature(BoosterFeature)
    proc drawCards() =
        var status = 0
        for f in feature.boosters:
            case f.kind:
                of btExperience:
                    t.experienceBoosterSet.setData(f)
                    status = status or (1 shl BoosterCardKind.Experience.int)
                of btIncome:
                    t.incomeBoosterSet.setData(f)
                    status = status or (1 shl BoosterCardKind.Income.int)
                of btTournamentPoints:
                    t.tournamentsBoosterSet.setData(f)
                    status = status or (1 shl BoosterCardKind.Tournaments.int)

        if (status and (1 shl BoosterCardKind.Premium.int)) == 0:
            t.setDefaultBooster(t.premiumBoosterSet)
        if (status and (1 shl BoosterCardKind.Income.int)) == 0:
            t.setDefaultBooster(t.incomeBoosterSet)
        if (status and (1 shl BoosterCardKind.Tournaments.int)) == 0:
            t.setDefaultBooster(t.tournamentsBoosterSet)
        if (status and (1 shl BoosterCardKind.Experience.int)) == 0:
            t.setDefaultBooster(t.experienceBoosterSet)

    feature.subscribe(t.node.sceneView.GameScene, drawCards)
    drawCards()
    t.unsubscribeFeatures = proc() =
        feature.unsubscribe(t.node.sceneView.GameScene, drawCards)


proc setIconStroke(n: Node) =
    let comp = n.getComponent(IconComponent)
    if comp.isNil:
        for nn in n.children:
            nn.setIconStroke()
    else:
        comp.hasOutline = true


proc createBoostersTab*(n: Node, source: string, currTaskProgress: float): BoostersTab =
    let tab = BoostersTab.new(newNodeWithResource("common/gui/popups/precomps/booster_shop"))
    tab.source = source
    tab.currTaskProgress = currTaskProgress
    n.addChild(tab.node)
    tab.node.setIconStroke()
    tab.subscribeFeatures()
    result = tab

    tsBoosterWindow.addTutorialFlowState(true)
    tsBoosterIndicators.addTutorialFlowState()


method remove*(tab: BoostersTab, removeFromParent: bool = true) =
    tab.unsubscribeFeatures()

    tab.incomeBoosterSet.deactivate()
    tab.premiumBoosterSet.deactivate()
    tab.tournamentsBoosterSet.deactivate()
    tab.experienceBoosterSet.deactivate()

    procCall tab.StoreTab.remove(removeFromParent)


nodeProxy BoostersStubTab of StoreTab:
    text Text {onNodeAdd: node}:
        node.position = newVector3(VIEWPORT_SIZE.width / 2, VIEWPORT_SIZE.height / 2)

        horizontalAlignment = haCenter
        verticalAlignment = vaCenter
        color = newColor(1, 1, 1, 1)
        font = newFontWithFace("Exo2-Black", 72.0)
        text = localizedString("BOOSTER_UNLOCK_TEXT")
        shadowColor = newColor(0, 0, 0, 0.4)
        shadowRadius = 4.0
        shadowOffset = newSize(0, 2.0)


proc createBoostersStubTab*(n: Node, source: string, currTaskProgress: float): BoostersStubTab =
    let tab = BoostersStubTab.new(newNode("boosters_stub_tab"))
    tab.source = source
    tab.currTaskProgress = currTaskProgress
    n.addChild(tab.node)
    result = tab
