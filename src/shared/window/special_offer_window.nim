import times, tables, strutils, logging, json
import nimx / [ types, animation, matrixes, app, window, image ]

import core / notification_center
import core / helpers / color_segments_helper
import core / components / timer_component
import node_proxy / proxy

import rod / [ node, viewport, quaternion, component ]
import rod / component / [text_component, ae_composition, gradient_fill, sprite ]

import utils / [ helpers, falcon_analytics, timesync, icon_component ]

import shared / [ localization_manager, director ]
import shared / window / [ window_component, button_component, window_manager ]

import falconserver / purchases / product_bundles_shared
import platformspecific / purchase_helper
import narrative / narrative_character
import core / components / remote_image_component
import core / net / remote_image
import core / features / vip_system

const SHOW_EXCEPTIONS_NODES = @["background/button_buy","background/button_close"]
const MIN_TIME_TO_SHOW_OFFERS_TIMER = 10.0

const TitleBackColorConf = (
    angle1: 90.0,
    angle2: 90.0,
    colors: [
        newColorB(255,152,0),
        newColorB(255,194,30),
        newColorB(255,173,15),
        newColorB(255,215,45),
    ]
)

nodeProxy OfferWindowProxy:
    comps* AEComposition {onNode: node}
    buttonClose* ButtonComponent {withValue: np.node.findNode("button_close").createButtonComponent(newRect(0.0, 0.0, 120.0, 120.0))}
    buttonBuy* ButtonComponent {withValue: np.node.findNode("button_buy").createButtonComponent(newRect(0.0, 0.0, 435.0, 120.0))}
    bgGradient* GradientFill {onNode: "bg"}

    promoNode* Node {withName: "offer"}
    promoTextNode Node {withName: "x_number_controller"}:
        position = newVector3(1572.5,554.0)
    promoText1* Text {onNode: "line_1"}:
        shadowOffset = newSize(8,50)
        shadowRadius = 1
        shadowSpread = 0
        shadowColor = newColor(0.0,0.0,0.0,0.4)
    promoText2* Text {onNode: "line_2"}:
        shadowOffset = newSize(8,50)
        shadowRadius = 1
        shadowSpread = 0
        shadowColor = newColor(0.0,0.0,0.0,0.4)

    vipPointsNode* Node {withName: "vip_points"}
    vipIcon IconComponent {withValue: np.vipPointsNode.findNode("reward_icons_placeholder").addRewardIcon("vipPoints")}:
        hasOutline = true

    timerNode* Node {withName: "timer"}
    timerTextNode* Node {withName: "days"}
    timer* TextTimerComponent {onNodeAdd: timerTextNode}:
        withDays = false
        prepareText = proc(parts: TextTimerComponentParts): string =
            result = parts.hours[1] & ":" & parts.minutes[1] & ":" & parts.seconds[1]

    oldPriceNode* Node {withName: "old_price"}
    oldPrice* Text {onNode:"old_price_value"}

    titleText* Text {onNode:"only_for_you"}:
        text = "Special Offer"
    descriptionText* Text {onNode:"name_of_pack"}:
        text = ""

    oneProductAmount* Node {withName: "currency_offer_1"}
    oneProductImage* Node {withName: "currency_image_big"}
    twoProductsAmount* Node {withName: "currency_offer_2"}
    twoProductsImage* Node {withName: "currency_image_small"}
    defaultImage* Node {withName: "currncy_default"}
    plusNode* Node {withName: "plus"}
    centerNode* Node {withName: "center"}

type SpecialOfferWindow* = ref object of AsyncWindowComponent
    owp: OfferWindowProxy
    rotateIdleAnims: seq[Animation]
    source*: string
    character: NarrativeCharacter
    inAnim: Animation
    offerCustomUrl*:string
    offerCustomImage:Image
    bundle: ProductBundle
    sod: SpecialOfferData

proc setOldPrice(sow: SpecialOfferWindow, oldPrice: string) =
    if oldPrice.len > 0:
        sow.owp.oldPriceNode.enabled = true
        sow.owp.oldPrice.text = "$" & oldPrice
    else:
        sow.owp.oldPriceNode.removeFromParent()

proc `priceOnBuyBttn=`*(sow: SpecialOfferWindow, price:string) =
    sow.owp.buttonBuy.textColor = whiteColor()
    sow.owp.buttonBuy.title = localizedFormat("SOW_BUY_BTTN_TEMPLATE","$" & price)

proc prepareForBundle*(sow: SpecialOfferWindow, sod: SpecialOfferData) =
    let bundles = getPurchaseHelper().productBundles()
    sow.bundle = bundles[sod.bid]
    sow.sod = sod
    sow.offerCustomUrl = sow.bundle.customImageUrl

proc showCustomImage(sow: SpecialOfferWindow) =
    if sow.offerCustomImage.isNil:
        info "Image from $# not found.".format(sow.offerCustomUrl)
    else:
        sow.owp.defaultImage.removeFromParent()
        let comp = sow.owp.centerNode.component(Sprite)
        comp.image = sow.offerCustomImage
        comp.offset = newPoint(-sow.offerCustomImage.size.width / 2, -sow.offerCustomImage.size.height / 2)
        sow.owp.centerNode.alpha = 1.0

proc setupOneProductView(sow: SpecialOfferWindow, product:ProductItem, iType: ImageType) =
    sow.owp.twoProductsAmount.removeFromParent()
    sow.owp.twoProductsImage.removeFromParent()
    sow.owp.plusNode.removeFromParent()
    sow.owp.oneProductAmount.findNode("icon_placeholder").addCurrencyIcon($product.currencyType)
    sow.owp.oneProductAmount.findNode("amount").getComponent(Text).text = (product.amount).formatThousands

    if sow.offerCustomUrl.len > 0:
        sow.owp.oneProductImage.removeFromParent()
        sow.showCustomImage()
    else:
        sow.owp.defaultImage.removeFromParent()
        let imgName = $product.currencyType & "_" & $iType
        sow.owp.oneProductImage.removeChildrensExcept(@[imgName.toLowerAscii])

proc setupTwoProductsView(sow: SpecialOfferWindow, products:seq[ProductItem], iType: ImageType) =
    sow.owp.oneProductAmount.removeFromParent()
    sow.owp.oneProductImage.removeFromParent()

    var p1 = products[0]
    var p2 = products[1]

    var haveProperImage:bool = false
    if sow.offerCustomUrl.len > 0:
        ## Implement loading of custom url image here.
        sow.owp.twoProductsImage.removeFromParent()
        sow.owp.plusNode.removeFromParent()
        sow.showCustomImage()
    else:
        if p1.currencyType == VirtualCurrency.Energy or (p1.currencyType == VirtualCurrency.Bucks and p2.currencyType == VirtualCurrency.Chips):
            let t = p1
            p1 = p2
            p2 = t

        if p1.currencyType == VirtualCurrency.Bucks or p1.currencyType == VirtualCurrency.Chips and
             p2.currencyType == VirtualCurrency.Energy or p2.currencyType == VirtualCurrency.Bucks:
            haveProperImage = true

        if haveProperImage:
            sow.owp.defaultImage.removeFromParent()
            let imgName = $p1.currencyType & "_" & $p2.currencyType
            sow.owp.twoProductsImage.removeChildrensExcept(@[imgName.toLowerAscii])
        else:
            sow.owp.twoProductsImage.removeFromParent()

    sow.owp.twoProductsAmount.findNode("icon_placeholder1").addCurrencyIcon($p1.currencyType)
    sow.owp.twoProductsAmount.findNode("amount1").getComponent(Text).text = (p1.amount).formatThousands
    sow.owp.twoProductsAmount.findNode("icon_placeholder2").addCurrencyIcon($p2.currencyType)
    sow.owp.twoProductsAmount.findNode("amount2").getComponent(Text).text = (p2.amount).formatThousands

proc setupUnsupportedProductsView(sow: SpecialOfferWindow, iType: ImageType) =
    sow.owp.oneProductAmount.removeFromParent()
    sow.owp.oneProductImage.removeFromParent()
    sow.owp.twoProductsAmount.removeFromParent()
    sow.owp.twoProductsImage.removeFromParent()
    sow.owp.plusNode.removeFromParent()

    if sow.offerCustomUrl.len > 0:
        sow.showCustomImage()

proc setupBundleItems(sow: SpecialOfferWindow, pb:ProductBundle) =
    #pb.products = @[ProductItem(currencyType: Energy,amount: 2600), ProductItem(currencyType: Energy,amount: 150), ProductItem(currencyType: Bucks,amount: 2600)]
    case pb.products.len:
        of 1:
            sow.setupOneProductView(pb.products[0],pb.imageType)
        of 2:
            sow.setupTwoProductsView(pb.products,pb.imageType)
        else:
            warn "Unsupported amount of product items $# in Bundle".format(pb.products.len)
            sow.setupUnsupportedProductsView(pb.imageType)

proc setOfferDetails(sow: SpecialOfferWindow) =
    let pb = sow.bundle
    let sod = sow.sod

    if timeleft(sod.expires) < MIN_TIME_TO_SHOW_OFFERS_TIMER:
        sow.owp.timerNode.removeFromParent()
    else:
        sow.owp.timer.timeToEnd = sod.expires

    sow.priceOnBuyBttn = pb.usdPrice
    sow.setOldPrice(pb.oldUsdPrice)
    sow.owp.titleText.text = pb.name
    sow.owp.descriptionText.text = pb.description
    if pb.promoText.len > 0:
        let res = pb.promoText.split({'|'})
        sow.owp.promoText1.text = res[0]
        sow.owp.promoText2.text = ""
        if res.len > 1: sow.owp.promoText2.text = res[1]
    else:
        sow.owp.promoNode.removeFromParent()

    sow.setupBundleItems(pb)

    # sow.owp.timer.onComplete do():
    #     sow.closeButtonClick()

proc setupVipPoints(sow: SpecialOfferWindow) =
    let vipConfig = sharedVipConfig()

    let textNode = sow.owp.vipPointsNode.findNode("vip_points_text")
    let points = vipConfig.vipPointsForPrice(sow.bundle.priceUsdCents.float / 100)
    textNode.getComponent(Text).text = "+" & $points


method onInit*(sow: SpecialOfferWindow) =
    sow.owp = OfferWindowProxy.new(newLocalizedNodeWithResource("common/gui/popups/precomps/offers_window/new_offers"))
    sow.anchorNode.addChild(sow.owp.node)

    # Fix wrong export gradient.
    sow.owp.bgGradient.startPoint = zeroPoint
    sow.owp.plusNode.findNode("plus_button_shape").getComponent(GradientFill).startPoint.x = 100.0

    sow.setupVipPoints()

    sow.owp.buttonBuy.onAction do():
        sharedAnalytics().special_offer_try(sow.bundle.id, sow.source)
        mainApplication().keyWindow().fullscreen = false
        if getPurchaseHelper().isPurchasesAvailiable():
            getPurchaseHelper().purchaseProduct(sow.bundle.id)
        else:
            warn "Can't purchase bundle ", sow.bundle.id ,". Purchases are not availiable!!!"

    sow.character = sow.owp.node.addComponent(NarrativeCharacter)
    sow.character.kind = NarrativeCharacterType.WillFerris
    sow.character.bodyNumber = 9
    sow.character.headNumber = 6

    sow.setOfferDetails()

    let timeLeft = ((sow.sod.expires - serverTime()) / 3600).int
    sharedAnalytics().special_offer_open(sow.sod.bid, sow.source, timeLeft)

method initWindowComponent*(sow: SpecialOfferWindow) =
    proc onEnd() = procCall sow.AsyncWindowComponent.initWindowComponent

    sow.moneyPanelOnTop = true
    sow.isTapAnywhere = false
    sow.canMissClick = false

    if sow.offerCustomUrl.len > 0:
        let ri = RemoteImage.new()
        ri.url = sow.offerCustomUrl
        ri.onComplete = proc(i:Image) =
                            sow.offerCustomImage = i
                            onEnd()
        ri.onError = proc(err:string) =
                            info "Error: ", err
                            onEnd()

        ri.download()
    else:
        onEnd()


proc setVisualEffects(sow: SpecialOfferWindow, state: bool) =
    let backRaysNode = sow.owp.node.findNode("back_rays")
    let backRays2Node = sow.owp.node.findNode("back_rays2")
    if state:
        sow.rotateIdleAnims = newSeq[Animation]()
        sow.rotateIdleAnims.add(backRaysNode.addRotateAnimation(20))
        sow.rotateIdleAnims.add(backRays2Node.addRotateAnimation(20))
    else:
        backRaysNode.removeFromParent()
        backRays2Node.removeFromParent()
        sow.owp.node.findNode("golden_star").removeFromParent()
        sow.owp.node.findNode("white_star").removeFromParent()
        sow.owp.node.findNode("special_offer_circle").removeFromParent()

method showStrategy*(sow: SpecialOfferWindow) =
    sow.node.enabled = true
    sow.node.alpha = 1.0
    sow.inAnim = sow.owp.comps.play("in", SHOW_EXCEPTIONS_NODES)

    sow.setVisualEffects(not sow.bundle.disableEffects)

    sow.inAnim.onComplete do():
        if sow.rotateIdleAnims.len != 0:
            sow.rotateIdleAnims.add(sow.owp.node.findNode("golden_star").addRotateAnimation(10))
            sow.rotateIdleAnims.add(sow.owp.node.findNode("white_star").addRotateAnimation(-10))
            sow.rotateIdleAnims.add(sow.owp.node.findNode("special_offer_circle").addRotateAnimation(-10))

        sow.owp.buttonClose.onAction do():
            sow.closeButtonClick()

        sow.character.show(0.0)

        if not sow.bundle.disableEffects:
            let particlesNode = newNodeWithResource("common/particles/offer_window_particles")
            sow.owp.node.insertChild(particlesNode,0)



method hideStrategy*(sow: SpecialOfferWindow): float =
    let hideAnim = sow.owp.comps.play("out", SHOW_EXCEPTIONS_NODES)

    if not sow.character.isNil:
        sow.character.hide(0.3)

    if not sow.inAnim.isNil:
        sow.inAnim.cancel()

    for a in sow.rotateIdleAnims:
        a.cancel()
    sow.rotateIdleAnims.setLen(0)

    sow.owp.buttonBuy.nxButton.enabled = false


    var tte = 0
    if timeleft(sow.sod.expires) > MIN_TIME_TO_SHOW_OFFERS_TIMER:
        tte = sow.owp.timer.timeToEnd.int

    sharedAnalytics().special_offer_closed(sow.bundle.id, sow.source, tte)

    return hideAnim.loopDuration

method beforeRemove*(sow: SpecialOfferWindow)=
    procCall sow.AsyncWindowComponent.beforeRemove
    let accepted_offers = getPurchaseHelper().profileOffers
    if accepted_offers.hasKey(sow.bundle.id):
        let sod = accepted_offers[sow.bundle.id]
        let timeRemaining = sod.expires - serverTime()
        if  timeRemaining > MIN_TIME_TO_SHOW_OFFERS_TIMER:
            currentNotificationCenter().postNotification("ShowSpecialOfferTimer", newVariant(sod))

registerComponent(SpecialOfferWindow, "windows")
