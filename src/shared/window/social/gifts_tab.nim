import nimx / [ types, animation, matrixes ]
import rod / [ node, viewport, component ]
import rod / component / [ text_component ]
import utils / [ node_scroll, helpers, falcon_analytics ]
import shared / [ localization_manager, user ]
import shared.window.button_component
import core / helpers / reward_helper
import social_window
import strutils
import core.net.server

const GIFT_ANCHOR_POINT = newVector3(640, 86)
const START_GIFT_POINT = newVector3(1054, 371)
const GIFT_OFFSET = 194.Coord
const MAX_GIFTS_ON_PAGE = 3
const MAX_FIRST_NAME_LEN = 7
const MAX_LAST_NAME_LEN = 7

proc animateGiftButtons(sw: SocialWindow): Animation =
    result = newAnimation()

    sw.btnUp.component(ButtonComponent).enabled = false
    sw.btnDown.component(ButtonComponent).enabled = false
    result.loopDuration = 0.3
    result.numberOfLoops = 1
    result.onComplete do():
        sw.btnUp.component(ButtonComponent).enabled = true
        sw.btnDown.component(ButtonComponent).enabled = true
    sw.giftsScrollContent.addAnimation(result)

proc onButtonDown(sw: SocialWindow) =
    let limit = -(GIFT_OFFSET * (sw.gifts.len.Coord - MAX_GIFTS_ON_PAGE))
    let startPosY = sw.giftsScrollContent.positionY
    var endPosY = startPosY - GIFT_OFFSET

    if limit > endPosY:
        endPosY = limit
    let anim = sw.animateGiftButtons()

    anim.onAnimate = proc(p: float) =
        sw.giftsScrollContent.positionY = interpolate(sw.giftsScrollContent.positionY, endPosY, p)

proc onButtonUp(sw: SocialWindow) =
    let startPosY = sw.giftsScrollContent.positionY
    var endPosY = startPosY + GIFT_OFFSET
    let anim = sw.animateGiftButtons()

    if endPosY > 0:
        endPosY = 0
    anim.onAnimate = proc(p: float) =
        sw.giftsScrollContent.positionY = interpolate(sw.giftsScrollContent.positionY, endPosY, p)

proc initGiftsButtons*(sw: SocialWindow) =
    let btnInvite = sw.anchorNode.findNode("button_green_collect_left_block")
    let buttonInvite = btnInvite.createButtonComponent(btnInvite.animationNamed("press"), newRect(0,0,300,85))

    buttonInvite.onAction do():
        sw.activateFriends()
        sharedAnalytics().wnd_community_tab_changed(sw.source, $sw.activeTab.tabType, 1)

    sw.btnUp = sw.anchorNode.findNode("button_up")
    sw.btnDown = sw.anchorNode.findNode("button_down")

    let buttonUp = sw.btnUp.createButtonComponent(sw.btnUp.animationNamed("press"), newRect(0,0,120,120))
    let buttonDown = sw.btnDown.createButtonComponent(sw.btnDown.animationNamed("press"), newRect(0,0,120,120))

    buttonUp.visibleDisable = false
    buttonDown.visibleDisable = false
    buttonUp.onAction do():
        sw.onButtonUp()
    buttonDown.onAction do():
        sw.onButtonDown()

    sw.btnUp.alpha = 0
    sw.btnDown.alpha = 0

proc checkGiftsScrollLocking*(sw: SocialWindow) =
    if sw.gifts.len > MAX_GIFTS_ON_PAGE:
        sw.giftBarParent.scrollDirection = NodeScrollDirection.vertical
        sw.btnUp.alpha = 1.0
        sw.btnDown.alpha = 1.0
    else:
        let anim = newAnimation()
        let startPosY = sw.giftsScrollContent.positionY

        anim.numberOfLoops = 1
        anim.loopDuration = 0.5
        anim.onAnimate = proc(p: float) =
            sw.giftsScrollContent.positionY = interpolate(startPosY, 0, p)
        sw.anchorNode.addAnimation(anim)
        sw.giftBarParent.scrollDirection = NodeScrollDirection.none
        sw.btnUp.alpha = 0.0
        sw.btnDown.alpha = 0.0

proc setCollectGiftsText*(sw: SocialWindow) =
    let t = sw.anchorNode.findNode("collect_gifts").getComponent(Text)
    if sw.gifts.len == 0:
        t.text = ""
    else:
        t.text = localizedString("COLLECT_GIFTS").format(sw.gifts.len)

proc removeGift(sw: SocialWindow, gift: Gift) =
    gift.node.removeFromParent()

    if sw.gifts.len > MAX_GIFTS_ON_PAGE and gift.index > sw.gifts.len - MAX_GIFTS_ON_PAGE:
        let anim = newAnimation()
        let startPosY = sw.giftsScrollContent.positionY
        let endPosY = sw.giftsScrollContent.positionY + GIFT_OFFSET

        anim.loopDuration = 0.5
        anim.numberOfLoops = 1

        anim.onAnimate = proc(p: float) =
            sw.giftsScrollContent.positionY = interpolate(startPosY, endPosY, p)
        sw.giftsScrollContent.addAnimation(anim)

    for child in sw.giftsScrollContent.children:
        closureScope:
            let cur = child

            if (cur.name.substr(9, cur.name.len)).parseInt() > gift.index:
                let anim = newAnimation()
                let startPosY = cur.positionY
                let endPosY = startPosY - GIFT_OFFSET

                anim.loopDuration = 0.5
                anim.numberOfLoops = 1

                anim.onAnimate = proc(p: float) =
                    cur.positionY = interpolate(cur.positionY, endPosY, p)
                cur.addAnimation(anim)

    let i = sw.gifts.find(gift)
    sw.gifts.del(i)
    sw.checkGiftsScrollLocking()
    sw.setCollectGiftsText()

proc setFriendAvatar(sw: SocialWindow, gift: Gift) =
    sw.setAvatar(gift.node, gift.friendFbID)

proc collectGift(sw: SocialWindow, gift: Gift) =
    sharedServer().claimGift(gift.id, gift.giftBack, proc(res: JsonNode) =
        echo "claimGift res = ", res

        if "wallet" in res:
            let scale = newVector3(0.4, 0.4, 1.0)
            var placeholder = gift.node.findNode("chips_placeholder")
            var icon = sw.anchorNode.sceneView.rootNode.findNode("money_panel").findNode("chips_placeholder")

            if gift.reward.kind == RewardKind.bucks:
                placeholder = gift.node.findNode("bucks_placeholder")
                icon = sw.anchorNode.sceneView.rootNode.findNode("money_panel").findNode("bucks_placeholder")
            elif gift.reward.kind == RewardKind.parts:
                placeholder = gift.node.findNode("energy_placeholder")
                icon = sw.anchorNode.sceneView.rootNode.findNode("money_panel").findNode("energy_placeholder")

            let anim = addRewardFlyAnim(placeholder, icon, scale)

            anim.onComplete do():
                currentUser().updateWallet(res["wallet"])
            sw.removeGift(gift)
            if sw.gifts.len > 0:
                sw.giftsAlert.findNode("gifts_count").getComponent(Text).text = $sw.gifts.len
                sw.anchorNode.addAnimation(sw.giftsAlert.animationNamed("remainder_alert"))
            else:
                let completeAnim = sw.giftsAlert.animationNamed("complete")

                completeAnim.loopPattern = lpEndToStart
                sw.anchorNode.addAnimation(completeAnim)

            sw.afterCollectGiftFromFriend(gift.friendFbID)
            sw.collectedGifts.inc()
            if gift.giftBack:
                sw.giftedBack.inc()

            let giftCollected = $gift.reward.kind & " " & $gift.reward.amount
            sharedAnalytics().collect_gift(sw.source, giftCollected, gift.friendFbID, gift.giftBack.int)
    )

proc toogleGiftBack(sw: SocialWindow, gift: Gift, flag: bool = true) =
    gift.node.findNode("checkbox_parent").alpha = if flag: 1.0 else: 0.0
    gift.node.findNode("checkbox_ramka.png").getComponent(ButtonComponent).enabled = flag
    gift.giftBack = flag


proc addGift*(sw: SocialWindow, id: string, friendProfileID: string, friendFbID: string, reward: Reward) =
    let gift = Gift.new()

    gift.id = id
    gift.friendProfileID = friendProfileID
    gift.friendFbID = friendFbID
    gift.reward = reward
    gift.node = newLocalizedNodeWithResource("common/gui/popups/precomps/gift_bar.json")
    gift.giftBack = true
    gift.index = sw.gifts.len

    let btnCollect = gift.node.findNode("button_orange_collect")
    let buttonCollect = btnCollect.createButtonComponent(btnCollect.animationNamed("press"), newRect(0,0,250,80))

    sw.giftBarParent.addChild(gift.node)
    gift.node.name = "gift_bar_" & $gift.index
    gift.node.anchor = GIFT_ANCHOR_POINT
    gift.node.position = START_GIFT_POINT + newVector3(0, GIFT_OFFSET * sw.gifts.len.Coord)
    gift.node.alpha = 0

    buttonCollect.onAction do():
        sw.collectGift(gift)

    let firstNameText = gift.node.findNode("gift_first_name").getComponent(Text)
    let lastNameText = gift.node.findNode("gift_last_name").getComponent(Text)
    let frame = gift.node.findNode("checkbox_ramka.png")
    let checkboxButton = frame.createButtonComponent(newRect(-20,-20,180,100))
    let checkbox = gift.node.findNode("chek_mark.png")
    let chips = gift.node.findNode("chips_placeholder")
    let bucks = gift.node.findNode("bucks_placeholder")
    let energy = gift.node.findNode("energy_placeholder")

    chips.alpha = 0
    bucks.alpha = 0
    energy.alpha = 0
    if reward.kind == RewardKind.chips:
        chips.alpha = 1.0
    elif reward.kind == RewardKind.bucks:
        bucks.alpha = 1.0
    else:
        energy.alpha = 1.0

    gift.node.findNode("gift_amount").getComponent(Text).text = formatThousands(reward.amount)
    gift.node.findNode("gift_currency").getComponent(Text).text = localizedString("GIFT_" & reward.icon.toUpperAscii())
    var friendFound = false
    for friend in sw.friends:
        if friend.fbUserID == friendFbID:
            friendFound = true
            setUserName(firstNameText, lastNameText, friend.firstName, friend.lastName, MAX_FIRST_NAME_LEN, MAX_LAST_NAME_LEN)
            if friend.status == FriendStatus.TickTime:
                sw.toogleGiftBack(gift, false)
            break

    if not friendFound:
        setUserName(firstNameText, lastNameText, "Reel", "Valley", MAX_FIRST_NAME_LEN, MAX_LAST_NAME_LEN)
        sw.toogleGiftBack(gift, false)
    gift.node.alpha = 1.0

    sw.setFriendAvatar(gift)
    checkboxButton.onAction do():
        if checkbox.alpha == 0:
            gift.giftBack = true
            checkbox.alpha = 1
        else:
            gift.giftBack = false
            checkbox.alpha = 0
    sw.gifts.add(gift)
    sw.setCollectGiftsText()
    sw.checkGiftsScrollLocking()

