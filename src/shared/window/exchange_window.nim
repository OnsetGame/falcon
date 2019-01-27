import json, random, strutils, times, tables, logging, math

import rod / [ rod_types, node, viewport, component ]
import rod / component / [ text_component, ae_composition, clipping_rect_component, particle_system, ui_component ]

import nimx / [ button, matrixes, animation, timer ]
import core / notification_center

import falconserver / common / [ currency, game_balance ]

import shared / [ user, localization_manager, director, game_scene, tutorial ]
import shared / window / [ window_component, button_component, window_manager, special_offer_window ]
import windows / store / store_window
import core.net.server
import utils / [ falcon_analytics, falcon_analytics_helpers, game_state, helpers, timesync, sound_manager, icon_component ]

import platformspecific.purchase_helper
import platformspecific.android.rate_manager
import core / flow / flow_state_types

import core / features / vip_system
import utils.timesync

type ExchangeWindow* = ref object of WindowComponent
    buttonClose*: ButtonComponent
    buttonExchange*: ButtonComponent
    win: Node
    oldChips*: int64
    oldBucks*: int64
    oldParts*: int64
    chips, bucks, parts: int64
    numbers:seq[Node]
    source*: string
    timeAnim: Animation
    timerNode: Node
    exchangeRatesNode: Node
    #onCloseSpecialOfferBundleId: string
    wasExchange: bool
    touchBlocked: bool

proc `amount=`*(p: ExchangeWindow, amount: int64) =
    ## Set amount of exchanged money according to critical received
    ## with exchange operation.
    p.anchorNode.findNode("text_got_amount").component(Text).text = formatThousands(amount)

proc discountAvailiable(p: ExchangeWindow): bool =
    timeLeft(currentUser().nextExchangeDiscountTime) <= 0.0 or currentUser().exchangeNumChips == 0

proc startDiscountTimer(ew: ExchangeWindow)

proc showDealText(p: ExchangeWindow, num: int) =
    p.anchorNode.findNode("discount_exchange").enabled = p.discountAvailiable()
    p.anchorNode.findNode("next_discount_exchange").enabled = not p.discountAvailiable()
    p.timerNode.enabled = not p.discountAvailiable()
    if p.timeAnim.isNil and p.timerNode.enabled:
        p.startDiscountTimer()

proc `exchangeNum=`*(ew: ExchangeWindow, num: int) =
    var bucksPriceIndex = num
    if ew.discountAvailiable():
        bucksPriceIndex = 0

    let (bucks, change) = exchangeRates(bucksPriceIndex, Currency.Chips)
    let deal_price = ew.exchangeRatesNode.findNode("deal_price")
    let regular_price = ew.exchangeRatesNode.findNode("regular_price")
    let chips_rate = ew.exchangeRatesNode.findNode("chips_rate")
    let got_chips_rate = ew.win.findNode("vip_bonus_panel").findNode("chips_rate")

    chips_rate.component(Text).text = formatThousands(change)
    got_chips_rate.component(Text).text = formatThousands(change)

    if ew.discountAvailiable():
        deal_price.component(Text).text = formatThousands(bucks)
        regular_price.component(Text).text = formatThousands(bucks*2)
        deal_price.alpha = 1.0
        deal_price.enabled = true
        ew.exchangeRatesNode.findNode("deal_line").alpha = 1.0
    else:
        deal_price.alpha = 0.0
        deal_price.enabled = false
        ew.exchangeRatesNode.findNode("deal_line").alpha = 0.0

        regular_price.component(Text).text = formatThousands(bucks)
        regular_price.alpha = 1.0
    ew.showDealText(num)

proc setTimeVal(p: ExchangeWindow) =
    let t = timeLeft(currentUser().nextExchangeDiscountTime)

    if t > 0:
        let formattedTime = formatDiffTime(t)
        var strTime = buildTimerString(formattedTime)

        p.timerNode.component(Text).text = strTime
    else:
        if not p.timeAnim.isNil:
            p.timeAnim.cancel()
            p.timeAnim = nil
            p.exchangeNum = currentUser().exchangeNumChips

proc startDiscountTimer(ew: ExchangeWindow) =
    if not ew.timeAnim.isNil:
        ew.timeAnim.cancel()
        ew.timeAnim = nil
    ew.timeAnim = newAnimation()
    ew.timeAnim.loopDuration = 1.0
    ew.timeAnim.numberOfLoops = -1
    ew.timeAnim.addLoopProgressHandler 1.0, false, proc() =
        ew.setTimeVal()
    ew.win.addAnimation(ew.timeAnim)

proc exchangeResult(ew: ExchangeWindow, crit: int, val: int64, cb: proc())=
    let totalWin = val * crit

    let coef = ew.win.findNode("multipl")
    coef.component(Text).text = "x" & $crit
    let winAmount = ew.win.findNode("you_got")
    winAmount.component(Text).text = formatThousands(totalWin)

    let winWithVipBonusNode = ew.win.findNode("you_got_2")
    let winBonusNode = ew.win.findNode("amount_chips")

    let currentVipLevel = sharedVipConfig().getLevel(max(currentUser().vipLevel,0))
    if currentVipLevel.level > 0:
        let bonusWin = ceil(currentVipLevel.exchangeBonus * (totalWin).float).int
        winBonusNode.component(Text).text = formatThousands(bonusWin)
        winWithVipBonusNode.component(Text).text = formatThousands(totalWin + bonusWin)
    else:
        winBonusNode.component(Text).text = ""
        winWithVipBonusNode.component(Text).text = ""

    let anim = ew.win.component(AEComposition).compositionNamed("exchange", @["exchange_rates", "text_above_rates", "vip_bonus_panel"])
    let s = ew.win.sceneView

    if not s.isNil: s.addAnimation(ew.exchangeRatesNode.component(AEComposition).compositionNamed("exchange", @["vip_bonus_panel"]))
    s.addAnimation(anim)
    anim.onComplete do():
        let exchangeAnim = ew.win.findNode("vip_bonus_panel").component(AEComposition).compositionNamed("exchange")
        if currentVipLevel.level > 0:
            exchangeAnim.onComplete do():
                s.addAnimation(ew.win.findNode("vip_bonus_panel").component(AEComposition).compositionNamed("exchange_vip"))
        s.addAnimation(exchangeAnim)
        cb()
    anim.addLoopProgressHandler(0.4, false) do():
        s.GameScene.soundManager.sendEvent("COMMON_EXCHANGE_NUMBERS")
    anim.addLoopProgressHandler(0.6, false) do():
        s.GameScene.soundManager.sendEvent("COMMON_EXCHANGE_NUMBERS")
    anim.addLoopProgressHandler(0.8, false) do():
        s.GameScene.soundManager.sendEvent("COMMON_EXCHANGE_NUMBERS_LONG")
        addTutorialFlowState(tsBankWinClose, true)

proc numberVal(n: Node): int=
    result = 1
    for ch in n.children:
        if ch.enabled:
            result = try: parseInt(ch.name.substr(1)) except: 1

proc `numberVal=`(n: Node, val: int)=
    for ch in n.children:
        ch.enabled = ch.name == "x" & $val

proc randomizeNumbers(p: ExchangeWindow)=
    const availableMultiplayers = @[1,2,3,5,10]
    for n in p.numbers:
        n.numberVal = rand(availableMultiplayers)

proc spinAnimation(p: ExchangeWindow, crit: int, chips: int64, callback:proc())=
    let spinAnim = p.win.component(AEComposition).compositionNamed("spin", @["exchange_rates", "text_above_rates"])
    p.win.addAnimation(spinAnim)

    if p.anchorNode.findNode("discount_exchange").enabled == true:
        p.win.addAnimation(p.anchorNode.findNode("text_above_rates").animationNamed("change_in"))

    spinAnim.addLoopProgressHandler(0.5, false) do():
        p.randomizeNumbers()
        p.numbers[p.numbers.len - 2].numberVal = crit

        for i in 0 .. 4:
            p.numbers[i].numberVal = p.numbers[p.numbers.len - 1 - i].numberVal

    let spinAnimOnAnimate = spinAnim.onAnimate
    let particlesParent = p.anchorNode.findNode("particles_parent")

    particlesParent.removeAllChildren()
    spinAnim.onAnimate = proc(prog: float)=
        spinAnimOnAnimate(prog)
        for n in p.numbers:
            n.alpha = 0.5

    spinAnim.onComplete do():
        p.numbers[p.numbers.len - 2].alpha = 1.0
        p.numbers[1].alpha = 1.0

        let particles = newNodeWithResource("common/gui/popups/precomps/particles_reward.json")
        let ps = particles.getComponent(ParticleSystem)
        ps.hasDepthTest = false
        ps.isBlendAdd = true
        particlesParent.addChild(particles)

        p.exchangeResult(crit, chips) do():
            p.isBusy = false
            p.exchangeNum = currentUser().exchangeNumChips
            p.buttonExchange.nxButton.enabled = true
            p.buttonClose.enabled = true
            if not callback.isNil:
                callback()

proc showStore(ew: ExchangeWindow, tabType: StoreTabKind) =
    showStoreWindow(tabType, "not_enough_bucks_exchange")

proc setupVipPanel(ew: ExchangeWindow) =
    #Hack for broken position when rotating shapes...
    ew.win.findNode("triangle_2").position = newVector3(653.0,-128.0)
    ew.win.findNode("triangle_3").position = newVector3(658.0,-128.0)

    let vipConfig = sharedVipConfig()
    let currentVipLevel = vipConfig.getLevel(max(currentUser().vipLevel,0))

    let bonusPercents = ew.win.findNode("amount_percent").component(Text)

    if currentVipLevel.level > 0:
        ew.win.findNode("VIP_BONUS_YET").removeFromParent
        ew.win.findNode("YOU_DONT_HAVE").removeFromParent
        bonusPercents.text = ("+$#%").format(ceil(currentVipLevel.exchangeBonus * 100.0).int)
    else:
        bonusPercents.text = ""

    discard ew.win.findNode("reward_icons_placeholder").addRewardIcon("vipPoints")

method onInit*(ew: ExchangeWindow) =
    let win = newLocalizedNodeWithResource("common/gui/popups/precomps/exchange_window.json")
    ew.anchorNode.addChild(win)
    ew.win = win

    ew.setupVipPanel()

    if isFrameClosed($tsBankWinExchangeBttn):
        ew.moneyPanelOnTop = true

    let btnClose = ew.anchorNode.findNode("button_close")
    let clAnim = btnClose.animationNamed("press")
    let yellowButton = ew.anchorNode.findNode("button_yellow_long")

    ew.buttonClose = btnClose.createButtonComponent(clAnim, newRect(10,10,100,100))
    ew.buttonClose.onAction do():
        ew.closeButtonClick()

        #let offerBundleID = ew.onCloseSpecialOfferBundleId

        if not ew.wasExchange and ew.source == "slot_out_of_chips":
            showStoreWindow(StoreTabKind.Chips, "not_enough_bucks_exchange")
        # if not getPurchaseHelper().profileOffers.hasKey(offerBundleID):
        #     let cb = proc() =
        #         let accepted_offers = getPurchaseHelper().profileOffers
        #         if accepted_offers.hasKey(offerBundleID):
        #             currentNotificationCenter().postNotification("ShowSpecialOfferWindow", newVariant(getPurchaseHelper().profileOffers[offerBundleID]))

        #     getPurchaseHelper().tryToStartOffer(offerBundleID,cb)


    ew.buttonExchange = yellowButton.createButtonComponent(newRect(10.0, 10.0,364.0, 124.0))

    let ybt = yellowButton.findNode("title")
    ybt.component(Text).text = localizedString("EXCHANGE_BUTTON")

    ew.oldChips = currentUser().chips
    ew.oldBucks = currentUser().bucks
    ew.oldParts = currentUser().parts

    ew.chips = currentUser().chips
    ew.bucks = currentUser().bucks
    ew.parts = currentUser().parts

    let winMan = sharedWindowManager()

    ew.timerNode = ew.win.findNode("time_@noloc")
    ew.exchangeRatesNode = ew.win.findNode("exchange_rates")

    let sceneName = ew.node.sceneView.name
    ew.win.findNode("Baraban").component(ClippingRectComponent).clippingRect = newRect(0.0, 50.0, 302.0, 370.0)
    ew.numbers = @[]
    let spController = ew.win.findNode("spin_controller")
    for i in -1..13:
        let numb = newLocalizedNodeWithResource("common/gui/popups/precomps/exchange_baraban_numbers.json")
        numb.positionY = (i * -201).float
        spController.addChild(numb)
        numb.alpha = 0.5
        ew.numbers.add(numb)

    ew.numbers[1].alpha = 1.0
    ew.randomizeNumbers()

    ew.buttonExchange.onAction do():
        if ew.touchBlocked:
            return
        ew.buttonClose.enabled = false
        ew.isBusy = true
        winMan.playSound("COMMON_EXCHANGEPOPUP_EXCHANGE_CLICK")
        winMan.playSound("COMMON_EXCHANGEPOPUP_CURRENCY_PULSE")
        winMan.playSound("COMMON_EXCHANGE_REEL")
        let user = currentUser()

        var localExchangeNum = user.exchangeNumChips
        if user.withdraw(0, exchangeRates(localExchangeNum, Currency.Chips).bucks, 0, "exchange"):
            ew.buttonExchange.nxButton.enabled = false
            sharedServer().exchangeBucks(Currency.Chips, proc(r: JsonNode) =
                if r["status"].getInt() == 0:

                    let oldChips = user.chips
                    let oldBucks = user.bucks
                    let oldParts = user.parts

                    let critical = r["critical"].getInt()

                    let oldRates = exchangeRates(localExchangeNum, Currency.Chips)

                    ew.bucks = r["bucks"].getBiggestInt()
                    ew.chips = r["chips"].getBiggestInt()
                    ew.parts = r["parts"].getBiggestInt()

                    user.updateWallet(bucks = ew.bucks)

                    ew.spinAnimation(critical, oldRates.change) do():
                        user.updateWallet(chips = ew.chips, parts = ew.parts)

                    winMan.playSound("COMMON_EXCHANGEPOPUP_CHIPS")
                    sharedAnalytics().get_chips(sceneName, oldChips,  oldBucks, abs(ew.bucks - oldBucks), ew.chips - oldChips)

                    if critical > 1:
                        winMan.playSound("COMMON_EXCHANGEPOPUP_CRITICAL")

                    winMan.playSound("COMMON_EXCHANGEPOPUP_ARROW")
                    winMan.playSound("COMMON_EXCHANGEPOPUP_YOUTGOT")
                    ew.wasExchange = true

                    if "cronTime" in r:
                        currentUser().nextExchangeDiscountTime = r["cronTime"].getFloat()

                    if RATEUS_USER_LEVEL <= currentUser().level and critical > 1:
                        pushBack(RateUsFlowState)
                else:
                    info "Exchange fail, status: ", r["status"].getInt()
                )
        else:
            ew.touchBlocked = true
            setTimeout(1.0) do():
                ew.touchBlocked = false
                showStoreWindow(StoreTabKind.Bucks, "not_enough_bucks_exchange")
                ew.close()
            wasLackOfBucksAnalytics = true

    #currentUser().cronTime = (epochTime() + 20).float # FOR DEBUG
    ew.exchangeNum = currentUser().exchangeNumChips

    # currentNotificationCenter().addObserver("CHIPS_EXCHANGE_WINDOW_SOURCE", ew) do(args: Variant):
    #     ew.source = args.get(string)
    #     sharedAnalytics().wnd_get_chips_open(sceneName, ew.source, ew.oldChips,  ew.oldBucks)
    #     currentNotificationCenter().removeObserver("CHIPS_EXCHANGE_WINDOW_SOURCE", ew)

    # let scj = getPurchaseHelper().getStoreConfigJson()
    # if scj.hasKey("chips_offer"):
    #     ew.onCloseSpecialOfferBundleId = scj["chips_offer"].getStr()

proc analytics*(ew: ExchangeWindow, source: string) =
    sharedAnalytics().wnd_get_chips_open(ew.node.sceneView.name, source, ew.oldChips, ew.oldBucks)

method showStrategy*(ew: ExchangeWindow) =
    ew.node.enabled = true
    ew.node.alpha = 1.0

    let a = ew.win.component(AEComposition).compositionNamed("in",@["exchange_rates", "text_above_rates", "vip_bonus_panel"])
    a.addLoopProgressHandler 0.5, false, proc() =
        ew.win.addAnimation(ew.win.findNode("vip_bonus_panel").component(AEComposition).compositionNamed("in"))
    ew.win.addAnimation(a)

    ew.exchangeRatesNode.positionY = -104.5
    addTutorialFlowState(tsBankWinExchangeBttn, true)

method hideStrategy*(p: ExchangeWindow): float =
    let outAnim = p.win.component(AEComposition).compositionNamed("out", @["exchange_rates", "text_above_rates", "vip_bonus_panel"])

    p.win.addAnimation(outAnim)
    p.node.hide(outAnim.loopDuration)
    if not p.timeAnim.isNil:
        p.timeAnim.cancel()
    p.anchorNode.findNode("spin_controller").alpha = 0
    return outAnim.loopDuration

method beforeRemove*(ew: ExchangeWindow) =
    procCall ew.WindowComponent.beforeRemove

    let user = currentUser()
    user.updateWallet(chips = ew.chips, bucks = ew.bucks, parts = ew.parts)
    let spentBucks = abs(user.bucks - ew.oldBucks)
    let gotChips = user.chips - ew.oldChips
    sharedAnalytics().wnd_get_chips_close(ew.anchorNode.sceneView.name, ew.source, ew.oldChips,  ew.oldBucks, spentBucks, gotChips)

    # currentNotificationCenter().removeObserver("CHIPS_EXCHANGE_WINDOW_SOURCE", ew)

registerComponent(ExchangeWindow, "windows")


proc showExchangeChipsWindow*(source: string, onClose: proc() = nil) =
    currExchangeTypeAnalytics = exChips
    let em = sharedWindowManager().show(ExchangeWindow)
    em.analytics(source)
    em.onClose = onClose
