import nimx / [ types, animation, matrixes ]
import rod / [ node, viewport, component ]
import rod / component / [ text_component ]
import utils / [ helpers, icon_component, node_scroll, timesync, falcon_analytics ]
import shared / [ localization_manager, game_scene ]
import shared.window.button_component
import shafa / game / reward_types
import social_window
import core.net.server
import strutils
import sequtils
import times
import algorithm

import facebook_sdk.facebook_sdk
import facebook_sdk.facebook_ui
import platformspecific.social_helper

const FRIENDS_ANCHOR_POINT = newVector3(180, 270)
const START_FRIENDS_POINT = newVector3(389, 539)
const FRIEND_DEFAULT_OFFSET = 288.Coord
const MAX_FRIENDS_ON_PAGE = 5
const MAX_FIRST_NAME_LEN = 11
const MAX_LAST_NAME_LEN = 11

const GIFT_SEND_COOLDOWN* = 60*60*24

proc setFriendTimeVal(sw: SocialWindow, friend: Friend)

proc animateFriendButtons(sw: SocialWindow): Animation =
    result = newAnimation()

    sw.btnRight.component(ButtonComponent).enabled = false
    sw.btnLeft.component(ButtonComponent).enabled = false
    result.loopDuration = 0.3
    result.numberOfLoops = 1
    result.onComplete do():
        sw.btnRight.component(ButtonComponent).enabled = true
        sw.btnLeft.component(ButtonComponent).enabled = true
    sw.friendsScrollContent.addAnimation(result)

proc hideInvisible(sw: SocialWindow) =
    let firstFriendWpos = sw.btnLeft.worldPos().x - abs(sw.friendOffset)/2.0
    let lastFriendWpos = sw.btnRight.worldPos().x + abs(sw.friendOffset)/2.0
    for friend in sw.friends:
        let wpx = friend.node.worldPos().x
        if wpx > firstFriendWpos and wpx < lastFriendWpos:
            friend.node.alpha = 1.0
        else:
            friend.node.alpha = 0

proc onButtonRight(sw: SocialWindow) =
    let startPosX = sw.friendsScrollContent.positionX
    let limit = -(FRIEND_DEFAULT_OFFSET * (sw.friends.len.Coord - MAX_FRIENDS_ON_PAGE))
    var endPosX = startPosX - FRIEND_DEFAULT_OFFSET
    let anim = sw.animateFriendButtons()

    if endPosX <= limit:
        endPosX = limit
        sw.btnRight.enabled = false
        sw.btnLeft.enabled = true
    else:
        sw.btnRight.enabled = true
        sw.btnLeft.enabled = true

    anim.onAnimate = proc(p: float) =
        sw.friendsScrollContent.positionX = interpolate(sw.friendsScrollContent.positionX, endPosX, p)
    anim.onComplete do():
        sw.hideInvisible()

    sw.hideInvisible()

proc onButtonLeft(sw: SocialWindow) =
    let startPosX = sw.friendsScrollContent.positionX
    var endPosX = startPosX + FRIEND_DEFAULT_OFFSET
    let anim = sw.animateFriendButtons()

    if endPosX >= 0:
        endPosX = 0
        sw.btnRight.enabled = true
        sw.btnLeft.enabled = false
    else:
        sw.btnRight.enabled = true
        sw.btnLeft.enabled = true

    anim.onAnimate = proc(p: float) =
        sw.friendsScrollContent.positionX = interpolate(sw.friendsScrollContent.positionX, endPosX, p)
    anim.onComplete do():
        sw.hideInvisible()
    sw.hideInvisible()

proc initFriendsButtons*(sw: SocialWindow) =
    sw.btnRight = sw.anchorNode.findNode("button_right")
    sw.btnLeft = sw.anchorNode.findNode("button_left")

    let buttonRight = sw.btnRight.createButtonComponent(sw.btnRight.animationNamed("press"), newRect(0,0,100,100))
    let buttonLeft = sw.btnLeft.createButtonComponent(sw.btnLeft.animationNamed("press"), newRect(0,0,100,100))

    buttonRight.onAction do():
        sw.onButtonRight()
    buttonLeft.onAction do():
        sw.onButtonLeft()

    sw.btnRight.alpha = 0
    sw.btnRight.getComponent(ButtonComponent).enabled = false
    sw.btnLeft.alpha = 0
    sw.btnLeft.getComponent(ButtonComponent).enabled = false

proc showFriendReward*(sw: SocialWindow, friend: Friend, toFriend: bool) =
    let num = friend.node.findNode("num")
    let greySolidComponent = friend.node.findNode("gray_solid").getComponent(IconComponent)
    var reward: Reward

    if toFriend:
        reward = sw.defaultGift
    else:
        reward = sw.reward

    if reward.kind == RewardKind.chips:
        greySolidComponent.name = "chips"
        greySolidComponent.composition = "currency_chips"
    elif reward.kind == RewardKind.bucks:
        greySolidComponent.name = "bucks"
        greySolidComponent.composition = "currency_bucks"

    friend.bottomPanel.enabled = true
    num.enabled = true
    friend.node.findNode("gray_solid").enabled = true
    friend.node.findNode("ltp_black_circle_small_black.png").enabled = true
    if toFriend:
        friend.node.findNode("friend_to_friend").enabled = true
        num.getComponent(Text).text = formatThousands(sw.defaultGift.amount)
    else:
        num.getComponent(Text).text = "<span style=\"color:FFDF90FF\">+</span>" & formatThousands(sw.reward.amount)

proc setFriendWaitForResponse(sw: SocialWindow, friend: Friend) =
    friend.bottomPanel.enabled = true
    friend.node.findNode("parent_wait").enabled = true

proc setFriendStatus*(sw: SocialWindow, friend: Friend, status: FriendStatus) =
    friend.status = status
    for st in FriendStatus.low..FriendStatus.high:
        friend.node.findNode(($st).toLowerAscii()).enabled = false
    friend.node.findNode(($status).toLowerAscii()).enabled = true

    friend.bottomPanel = friend.node.findNode("reward_friends")
    for c in friend.bottomPanel.children:
        c.enabled = false

    if status == FriendStatus.TickTime and friend.time > 0:
        friend.timeAnim = newAnimation()

        friend.timeAnim.loopDuration = 1.0
        friend.timeAnim.numberOfLoops = -1
        friend.timeAnim.addLoopProgressHandler 0.0, false, proc() =
            sw.setFriendTimeVal(friend)
            friend.time -= 1
        friend.node.addAnimation(friend.timeAnim)
    elif status == FriendStatus.Invite:
        sw.showFriendReward(friend, false)
    elif status == FriendStatus.Requested:
        sw.setFriendWaitForResponse(friend)
    elif status == FriendStatus.SendGift:
        sw.showFriendReward(friend, true)

proc setFriendAvatar(sw: SocialWindow, friend: Friend) =
    if not sw.isCheat:
        if friend.fbUserID.len == 0:
            sw.setAvatarWithUrl(friend.node, friend.avatarUrl)
        else:
            sw.setAvatar(friend.node, friend.fbUserID)

proc animateFriendToPosX(sw: SocialWindow, friend: Friend, newPosX: Coord) =
    const ANIM_TIME = 0.3
    let anim = newAnimation()
    let startPosX = friend.node.positionX

    anim.numberOfLoops = 1
    anim.loopDuration = ANIM_TIME
    anim.onAnimate = proc(p: float) =
        friend.node.positionX = interpolate(startPosX, newPosX, p)
    friend.node.addAnimation(anim)

proc setFirstFriendIndex(sw: SocialWindow) =
    const INVITE_OFFSET = 4
    var engagedCount: int

    for friend in sw.friends:
        if friend.status == FriendStatus.TickTime or friend.status == FriendStatus.SendGift:
            engagedCount.inc()

    for friend in sw.friends:
        if friend.status == FriendStatus.Invite:
            sw.firstFriendIndex = friend.index
            break

    if engagedCount > 0:
        sw.firstFriendIndex -= INVITE_OFFSET

    if sw.firstFriendIndex > sw.friends.len - MAX_FRIENDS_ON_PAGE:
        sw.firstFriendIndex = sw.friends.len - MAX_FRIENDS_ON_PAGE
    if sw.firstFriendIndex < 0:
        sw.firstFriendIndex = 0

proc sortFriends(sw: SocialWindow) =
    sw.friends.sort do(x, y: Friend) -> int:
        result = cmp(x.status, y.status)

proc onTickTimeEnd(sw: SocialWindow, friend: Friend) =
    var index = sw.friends.len - 1
    var posX: Coord
    var nextStatus = FriendStatus.Requested

    if sequtils.any(sw.friends, proc(f: Friend): bool = return f.status == FriendStatus.Invite):
        nextStatus = FriendStatus.Invite

    for fr in sw.friends:
        if fr.status == nextStatus:
            index = fr.index - 1
            posX = fr.node.positionX - FRIEND_DEFAULT_OFFSET
            break
    friend.node.alpha = 1.0
    friend.node.positionX = posX
    for fr in sw.friends:
        if fr.index <= index and fr.index > friend.index:
            sw.animateFriendToPosX(fr, fr.node.positionX - FRIEND_DEFAULT_OFFSET)
            fr.index.dec()
    friend.index = index

proc afterGiftSending*(sw: SocialWindow, friend: Friend, nextGiftTime:float) =
    var oldIndex = friend.index

    echo "Gift to ", friend.firstName, " ", friend.lastName, " was sent."
    friend.time = nextGiftTime
    friend.node.position = START_FRIENDS_POINT
    for f in sw.friends:
        if f.index < oldIndex:
            f.index.inc()
    friend.index = 0
    for fr in sw.friends:
        if fr.index <= oldIndex and fr.index > 0:
            sw.animateFriendToPosX(fr, fr.node.positionX + FRIEND_DEFAULT_OFFSET)
    sw.setFriendStatus(friend, FriendStatus.TickTime)

proc onSendGift(sw: SocialWindow, friend: Friend) =
    if sw.isCheat:
        sw.afterGiftSending(friend, GIFT_SEND_COOLDOWN.float)
    else:
        sharedServer().sendGift(friend.fbUserID) do(resp:JsonNode):
            if "status" in resp:
                echo resp["status"]
            else:
                let nextGiftTime = resp["nextTime"].getFloat()
                let giftDetails = $sw.defaultGift.kind & " " & $sw.defaultGift.amount

                sw.giftedBack.inc()
                sw.afterGiftSending(friend, timeLeft(nextGiftTime))
                sharedAnalytics().send_gift(sw.source, giftDetails, friend.fbUserID)

proc onSendInviteComplete(sw:SocialWindow, friend: Friend) =
    var oldIndex = friend.index
    friend.node.position = START_FRIENDS_POINT + newVector3(FRIEND_DEFAULT_OFFSET * (sw.friends.len.Coord - 1), 0)
    for f in sw.friends:
        if f.index < sw.friends.len and f.index > oldIndex:
            f.index.dec()
    friend.index = sw.friends.len - 1
    for fr in sw.friends:
        if fr.index < sw.friends.len - 1 and fr.index >= oldIndex:
            sw.animateFriendToPosX(fr, fr.node.positionX - FRIEND_DEFAULT_OFFSET)

    sw.setFriendStatus(friend, FriendStatus.Requested)
    sw.saveInvitation(@[friend])

import logging

proc onSendInvite(sw: SocialWindow, friend: Friend) =
    sendInviteToFriend(@[friend.inviteToken]) do(resp: FacebookGameResponse):
        info "resp is nil? ", resp.isNil
        if not resp.isNil:
            echo "Invite was sent to ", friend.firstName, " ", friend.lastName
            sharedAnalytics().invite_friend_accept($sw.activeTab.tabType, friend.fbUserID)
            sw.invitedFriends.inc()
            sw.onSendInviteComplete(friend)

proc setFriendTimeVal(sw: SocialWindow, friend: Friend) =
    let timeLeft = friend.time
    let formattedTime = formatDiffTime(timeLeft)
    let strTime = buildTimerString(formattedTime)

    friend.node.findNode("friends_time").component(Text).text = strTime
    if timeLeft <= 0:
        sw.setFriendStatus(friend, FriendStatus.SendGift)
        friend.timeAnim.cancel()
        sw.onTickTimeEnd(friend)

proc initFriendButtons(sw: SocialWindow, friend: Friend) =
    let btnInvitePersonal = friend.node.findNode("invite")
    let btnSendGift = friend.node.findNode("sendgift")
    let buttonInvitePersonal = btnInvitePersonal.createButtonComponent(btnInvitePersonal.animationNamed("press"), newRect(10,10,205,85))
    let buttonSendGift = btnSendGift.createButtonComponent(btnSendGift.animationNamed("press"), newRect(10,10,255,85))

    buttonInvitePersonal.onAction do():
        sharedAnalytics().invite_friend_click(sw.source, sw.activeFriends)
        sw.onSendInvite(friend)
    buttonSendGift.onAction do():
        sw.onSendGift(friend)

proc newFriend*(sw: SocialWindow, firstName, lastName: string, fbUserID: string, time: float = 0): Friend =
    let friend = Friend.new()
    friend.fbUserID = fbUserID
    friend.node = newLocalizedNodeWithResource("common/gui/popups/precomps/friend_gui.json")
    friend.time = time
    friend.firstName = firstName
    friend.lastName = lastName

    let firstNameText = friend.node.findNode("friend_name").getComponent(Text)
    let lastNameText = friend.node.findNode("friend_last_name").getComponent(Text)
    friend.node.anchor = FRIENDS_ANCHOR_POINT
    setUserName(firstNameText, lastNameText, firstName, lastName, MAX_FIRST_NAME_LEN, MAX_LAST_NAME_LEN)
    result = friend

proc newInvitableFriend*(sw: SocialWindow, firstName, lastName, inviteToken, avatarUrl : string ): Friend =
    let friend = Friend.new()
    friend.firstName = firstName
    friend.lastName = lastName
    friend.node = newLocalizedNodeWithResource("common/gui/popups/precomps/friend_gui.json")
    friend.time = 0.float
    friend.inviteToken = inviteToken
    friend.avatarUrl = avatarUrl

    let firstNameText = friend.node.findNode("friend_name").getComponent(Text)
    let lastNameText = friend.node.findNode("friend_last_name").getComponent(Text)

    friend.node.anchor = FRIENDS_ANCHOR_POINT
    echo "newInvitableFriend setUserName ", firstName, " ", lastName
    echo "avatarUrl - ", avatarUrl
    setUserName(firstNameText, lastNameText, firstName, lastName, MAX_FIRST_NAME_LEN, MAX_LAST_NAME_LEN)

    result = friend

proc addFriend*(sw: SocialWindow, f: Friend, status: FriendStatus) =
    f.status = status
    sw.setFriendAvatar(f)
    sw.friends.add(f)
    sw.initFriendButtons(f)

proc addFriend*(sw: SocialWindow, fbUserID: string, firstName, lastName: string, status: FriendStatus, time: float = 0): Friend {.discardable.} = #FOR CHEATS!
    let friend = Friend.new()

    friend.fbUserID = fbUserID
    friend.node = newLocalizedNodeWithResource("common/gui/popups/precomps/friend_gui.json")
    friend.time = time
    friend.status = status

    let firstNameText = friend.node.findNode("friend_name").getComponent(Text)
    let lastNameText = friend.node.findNode("friend_last_name").getComponent(Text)

    friend.node.anchor = FRIENDS_ANCHOR_POINT
    setUserName(firstNameText, lastNameText, firstName, lastName, MAX_FIRST_NAME_LEN, MAX_LAST_NAME_LEN)
    sw.setFriendAvatar(friend)
    friend.node.alpha = 0
    sw.friends.add(friend)
    sw.initFriendButtons(friend)


proc addFriendsToView*(sw: SocialWindow) =
    sw.sortFriends()
    sw.friendsFrameParent.customSize = (newSize(FRIEND_DEFAULT_OFFSET * sw.friends.len.Coord, 540))

    for i in 0..<sw.friends.len:
        let friend = sw.friends[i]
        friend.index = i
        sw.friendsFrameParent.addChild(friend.node)
        sw.setFriendStatus(friend, friend.status)

        friend.node.name = "friend_frame_" & $friend.index
        friend.node.position = START_FRIENDS_POINT + newVector3(FRIEND_DEFAULT_OFFSET * friend.index.Coord, 0)
        friend.node.addAnimation(friend.node.animationNamed("in"))

        if sw.friends.len > MAX_FRIENDS_ON_PAGE:
            sw.friendsFrameParent.scrollDirection = NodeScrollDirection.horizontal
            sw.btnRight.alpha = 1.0
            sw.btnLeft.alpha = 1.0
            sw.btnRight.getComponent(ButtonComponent).enabled = true
            sw.btnLeft.getComponent(ButtonComponent).enabled = true
    sw.setFirstFriendIndex()

    if sw.friends.len > 0:
        sw.firstFriendX = sw.friends[0].node.worldPos().x

    if sw.friends.len > 1:
        sw.friendOffset = sw.friends[1].node.worldPos().x - sw.friends[0].node.worldPos().x

    let newPosX = sw.friendsScrollContent.positionX - FRIEND_DEFAULT_OFFSET * sw.firstFriendIndex.Coord
    sw.friendsScrollContent.position = newVector3(newPosX, sw.friendsScrollContent.positionY)

    var maxIndexOnPage = sw.firstFriendIndex + MAX_FRIENDS_ON_PAGE
    if maxIndexOnPage > sw.friends.len:
        maxIndexOnPage = sw.friends.len

    for i in sw.firstFriendIndex..<maxIndexOnPage:
        sw.friends[i].node.alpha = 1.0

    proc hide() =
        sw.hideInvisible()

    sw.friendsFrameParent.onActionProgress = hide
    sw.friendsFrameParent.onActionEnd = hide


