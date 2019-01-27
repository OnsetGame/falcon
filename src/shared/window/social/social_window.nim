import nimx / [ types, matrixes, animation, image ]
import rod / [ node, viewport, component ]
import rod / component / [ text_component, clipping_rect_component, sprite ]
import shared / window / [ window_component, button_component, window_manager ]
import shared / [ localization_manager, login, deep_links ]
import utils / [ helpers, node_scroll, rounded_sprite, timesync, falcon_analytics, game_state ]
import quest.quests
import strutils
import times, tables, unicode, hashes, sets
import core.net.server
import core / helpers / reward_helper

import jsbind
when defined(emscripten):
    import jsbind.emscripten

import platformspecific / [ social_helper, webview_manager ]
import facebook_sdk.facebook_sdk
import facebook_sdk.facebook_login
import facebook_sdk.facebook_graph_request
import facebook_sdk.facebook_ui

import logging

const ACTIVE_TAB_COLOR = newColor(1.0, 0.87, 0.56, 1.0)
const INACTIVE_TAB_COLOR = newColor(0.6, 0.45, 0.29, 1.0)
const MAX_LEN_NAME = 20
const PERMISSIONS = {fbUserFriends}

const barWidth : Coord = 1430
const barHeight: Coord = 220
const offsetH  : Coord = 30

type SocialTabType* {.pure.} = enum
    Ranking,
    Gifts,
    Friends,
    Permissions,
    Loading

type FriendStatus* {.pure.} = enum
    TickTime,
    SendGift,
    Invite,
    Requested

type Friend* = ref object of RootObj
    node*: Node
    fbUserID*: string
    firstName*: string
    lastName*: string
    status*: FriendStatus
    time*: float
    index*: int
    timeAnim*: Animation
    bottomPanel*: Node
    avatarUrl*: string
    inviteToken*: string

type Gift* = ref object of RootObj
    node*: Node
    id*: string
    friendProfileID*: string
    friendFbID*: string
    friendName*: string
    reward*: Reward
    giftBack*: bool
    index*: int

type SocialTab* = ref object of RootObj
    rootNode: Node
    tabType*: SocialTabType
    glowIdleAnim: Animation

type SocialTabSpinner = ref object of SocialTab
    showHideAnimation: Animation
    spinAnimation: Animation

type SocialWindow* = ref object of WindowComponent
    currentTabType*: SocialTabType
    buttonFriends: ButtonComponent
    buttonGifts: ButtonComponent
    buttonRanking: ButtonComponent
    getPermissionsButton: ButtonComponent
    win: Node
    bkg: Node
    activeTab*: SocialTab
    friendsTab*: SocialTab
    rankingTab*: SocialTab
    giftsTab*: SocialTab
    friends*: seq[Friend]
    gifts*: seq[Gift]
    giftScrollNode: Node
    friendsScrollNode: Node
    giftBarParent*: NodeScroll
    friendsFrameParent*: NodeScroll
    btnUp*: Node
    btnDown*: Node
    btnRight*: Node
    btnLeft*: Node
    giftsScrollContent*: Node
    friendsScrollContent*: Node
    reward*: Reward
    defaultGift*: Reward
    firstFriendIndex*: int
    firstFriendX*: Coord
    friendOffset*: Coord
    nextGiftTimes: ref Table[string, float]
    isCheat*: bool
    giftsAlert*: Node
    giftsAlertShowed: bool
    bottomButtons: Node
    source*: string
    activeFriends*: int
    invitedFriends*: int
    collectedGifts*: int
    giftedBack*: int
    permissionsTab*: SocialTab
    loadingTab*: SocialTabSpinner
    invitedFriendsHash*: HashSet[Hash]

proc newSocialTabSpinner(parentNode: Node): SocialTabSpinner =
    let rootNode = newNodeWithResource("common/gui/popups/precomps/loading_social.json")
    parentNode.addChild(rootNode)
    let spinner = newNodeWithResource("common/lib/precomps/loading.json")
    rootNode.findNode("loading_placeholder").addChild(spinner)

    SocialTabSpinner(
        rootNode: rootNode,
        tabType: SocialTabType.Loading
    )

proc findSpriteComponent(n: Node): Sprite=
    result = n.componentIfAvailable(Sprite)
    if result.isNil:
        for ch in n.children:
            result = ch.findSpriteComponent()

proc setAvatarWithUrl*(sw: SocialWindow, node: Node, fbImageURL: string) =
    let ava_sprite = node.findNode("customer_teplate").children[0].findSpriteComponent()
    let p = ava_sprite.node

    loadImageFromURL(fbImageURL) do(image: Image):
        echo "FINISHED loadImageFromURL ", fbImageURL
        if not image.isNil:
            let nParent = p.parent
            let n = newNode("fb_avatar")

            #parent.removeComponent(Sprite)
            let profileAvaSprite = n.component(RoundedSprite)

            profileAvaSprite.needUpdateCondition = proc(): bool =
                return (profileAvaSprite.node.getGlobalAlpha() < 0.99)

            profileAvaSprite.image = image
            profileAvaSprite.borderSize = -0.01
            profileAvaSprite.discRadius = 0.31
            profileAvaSprite.discColor = newColor(1.0, 1.0, 1.0, 0.0)
            profileAvaSprite.discCenter = newPoint(0.5, 0.5)
            nParent.addChild(n)

proc setAvatar*(sw: SocialWindow, node: Node, fbUserID: string) =
    let fbImageURL = "https://graph.facebook.com/$#/picture?type=large&height=160&width=160".format(fbUserID)
    sw.setAvatarWithUrl(node, fbImageURL)


proc setUserName*(fNameText, lNameText: Text, firstName, lastName: string, firstNameLen, lastNameLen: int) =
    var normFirstName = firstName
    var normLastName = lastName

    if normFirstName.runeLen() > firstNameLen:
        normFirstName = runeSubStr(firstName, 0, firstNameLen - 1)
        normFirstName &= "..."

    if normLastName.runeLen() > lastNameLen:
        normLastName = runeSubStr(lastName, 0, lastNameLen - 1)
        normLastName &= "..."

    fNameText.text = normFirstName
    lNameText.text = normLastName


proc setRewardPerFriend*(sw: SocialWindow, reward: Reward) =
    let parent = sw.anchorNode.findNode("left_block_anchor")

    sw.anchorNode.findNode("gift_amount").getComponent(Text).text = $reward.amount
    sw.anchorNode.findNode("gift_currency").getComponent(Text).text = localizedString("GIFT_" & strutils.toUpperAscii(reward.icon))
    sw.reward = reward

    for c in parent.children:
        if c.name.contains("placeholder"):
            c.alpha = 0
    parent.childNamed("placeholder_" & reward.icon).alpha = 1.0

proc setDefaultGift*(sw: SocialWindow, gift: Reward) =
    sw.defaultGift = gift

proc setActiveTab*(sw: SocialWindow, tabType: SocialTabType) =
    sw.currentTabType = tabType

    let textRanking = sw.bkg.findNode("ranking_tab_window").getComponent(Text)
    let textGifts = sw.bkg.findNode("gifts_tab_window").getComponent(Text)
    let textFriends = sw.bkg.findNode("friends_tab_window").getComponent(Text)
    let tabsParent = sw.bkg.findNode("parent_tabs")

    textGifts.color = INACTIVE_TAB_COLOR
    textFriends.color = INACTIVE_TAB_COLOR
    textRanking.color = INACTIVE_TAB_COLOR

    if tabType == SocialTabType.Ranking:
        textRanking.color = ACTIVE_TAB_COLOR
        sw.bkg.findNode("ranking_tab").reattach(tabsParent)
    elif tabType == SocialTabType.Gifts:
        textGifts.color = ACTIVE_TAB_COLOR
        sw.bkg.findNode("parent_gift").reattach(tabsParent)
    else:
        textFriends.color = ACTIVE_TAB_COLOR
        sw.bkg.findNode("friend_tab").reattach(tabsParent)

proc showGiftsIn(sw: SocialWindow) =
    for child in sw.giftsScrollContent.children:
        if not child.isNil and child.alpha == 1.0:
            child.addAnimation(child.animationNamed("in"))

proc tabIn(sw: SocialWindow, st: SocialTab) =
    st.rootNode.enabled = true
    let showAnim = st.rootNode.animationNamed("in")
    st.rootNode.addAnimation(showAnim)

    if st.tabType == SocialTabType.Gifts:
        if  sharedQuestManager().isQuestCompleted("zep_building"):
            st.rootNode.findNode("build_zeppelin").enabled = false
        else:
            for child in st.rootNode.findNode("gifts_gui").children:
                child.enabled = false
                st.rootNode.findNode("build_zeppelin").enabled = true

        let leftBlockInAnim = st.rootNode.findNode("gift_left_block").animationNamed("in")

        st.rootNode.addAnimation(leftBlockInAnim)
        leftBlockInAnim.addLoopProgressHandler 0.5, false, proc() =
            let glow = st.rootNode.findNode("rewards_glow")
            let inAnim = glow.animationNamed("in")

            st.glowIdleAnim = glow.animationNamed("idle")
            st.rootNode.addAnimation(inAnim)
            inAnim.onComplete do():
                st.rootNode.addAnimation(st.glowIdleAnim)
                st.glowIdleAnim.numberOfLoops = -1
        sw.showGiftsIn()
    elif st.tabType == SocialTabType.Friends:
        let buttonsShowAnim = sw.bottomButtons.animationNamed("in")
        st.rootNode.addAnimation(buttonsShowAnim)
    elif st of SocialTabSpinner:
        st.rootNode.enabled = true

        let st = st.SocialTabSpinner

        if not st.showHideAnimation.isNil:
            st.showHideAnimation.cancel()

        let spinAnim = st.rootNode.findNode("loading").animationNamed("spin")
        spinAnim.numberOfLoops = -1
        st.showHideAnimation = showAnim
        st.spinAnimation = spinAnim
        showAnim.onComplete() do():
            st.showHideAnimation = nil
        st.rootNode.addAnimation(showAnim)
        st.rootNode.addAnimation(spinAnim)

proc activateFriends*(sw: SocialWindow) =
    sw.setActiveTab(SocialTabType.Friends)
    sw.giftScrollNode.enabled = false
    sw.friendsScrollNode.enabled = true
    sw.activeTab = sw.friendsTab
    sw.rankingTab.rootNode.enabled = false
    sw.friendsTab.rootNode.enabled = true
    sw.giftsTab.rootNode.enabled = false
    sw.bottomButtons.enabled = true
    sw.tabIn(sw.friendsTab)

proc saveInvitation*(sw: SocialWindow, invitedFriends:seq[Friend]) =
    var newHashes = newSeq[Hash]()
    for f in invitedFriends:
        let fh = (f.firstName&f.lastName).hash
        if not sw.invitedFriendsHash.containsOrIncl(fh):
            newHashes.add(fh)

    if newHashes.len > 0:
        sharedServer().addInvites(newHashes)

import friends_tab

proc afterCollectGiftFromFriend*(sw: SocialWindow, friendFbid: string) =
    for f in sw.friends:
        if f.fbUserID == friendFbid and f.status != TickTime:
            sw.afterGiftSending(f, GIFT_SEND_COOLDOWN)

import gifts_tab

proc tabOut(sw: SocialWindow, st: SocialTab, cb: proc() = nil) =
    let outAnim = st.rootNode.animationNamed("out")
    st.rootNode.addAnimation(outAnim)

    if st of SocialTabSpinner:
        let st = st.SocialTabSpinner

        if not st.showHideAnimation.isNil:
            st.showHideAnimation.cancel()

        outAnim.onComplete() do():
            st.rootNode.enabled = false
            st.showHideAnimation = nil
            if not st.spinAnimation.isNil:
                st.spinAnimation.cancel()
                st.spinAnimation = nil
            if not cb.isNil:
                cb()
        st.showHideAnimation = outAnim
    elif st.tabType == SocialTabType.Friends:
        let buttonsShowAnim = sw.bottomButtons.animationNamed("out")
        st.rootNode.addAnimation(buttonsShowAnim)
    else:
        outAnim.onComplete() do():
            st.rootNode.enabled = false
            if not cb.isNil:
                cb()

proc createTab(rootNode: Node, tabType: SocialTabType): SocialTab =
    result.new()
    rootNode.enabled = false
    result.rootNode = rootNode
    result.tabType = tabType

proc initButtons(sw: SocialWindow) =
    let btnShare = sw.anchorNode.findNode("facebook_share_button")
    let btnLike = sw.anchorNode.findNode("facebook_like_button")
    let btnClose = sw.anchorNode.findNode("button_close")
    let btnRate = sw.anchorNode.findNode("blue_button_rate")
    let btnInvite = sw.anchorNode.findNode("green_button_friends")
    let buttonClose = btnClose.createButtonComponent(btnClose.animationNamed("press"), newRect(0,0,125,125))
    let buttonInvite = btnInvite.createButtonComponent(btnInvite.animationNamed("press"), newRect(0,0,400,85))

    let bttnTextNode = btnInvite.findNode("facebook_invite_more_friends")

    if not bttnTextNode.isNil:
        bttnTextNode.getComponent(Text).text = "VISIT FAN PAGE!"
        bttnTextNode.findNode("tiny_plus.png").removeFromParent()

    when defined(android) and false:
        let buttonShare = btnShare.createButtonComponent(btnShare.animationNamed("press"), newRect(0,0,230,85))
        let buttonLike = btnLike.createButtonComponent(btnLike.animationNamed("press"), newRect(0,0,230,85))
        let buttonRate = btnRate.createButtonComponent(btnRate.animationNamed("press"), newRect(0,0,275,85))
        buttonShare.onAction do():
            echo "SHARE FACEBOOK!"
        buttonLike.onAction do():
            echo "LIKE FACEBOOK!"
        buttonRate.onAction do():
            echo "RATE FACEBOOK!"
    else:
        btnShare.removeFromParent()
        btnLike.removeFromParent()
        btnRate.removeFromParent()


    buttonClose.onAction do():
        sw.closeButtonClick()

    buttonInvite.onAction do():
        openFunPageWindow()
        # var allInviteTokens = newSeq[string]()
        # for friend in sw.friends:
        #     if not friend.inviteToken.isNil:
        #         allInviteTokens.add(friend.inviteToken)

        # sendInviteToFriend(allInviteTokens) do(fd: FacebookGameResponse):
        #     if not fd.isNil:
        #         sw.invitedFriends += allInviteTokens.len()
        #         sharedAnalytics().invite_more_friends_accept(sw.source, sw.activeFriends, sw.invitedFriends)
        #         for f in sw.friends:
        #             if not f.inviteToken.isNil and f.inviteToken in allInviteTokens:
        #                 sw.setFriendStatus(f, FriendStatus.Requested)

        # sharedAnalytics().invite_more_friends_click(sw.source, $sw.currentTabType, sw.activeFriends)

    sw.initFriendsButtons()
    sw.initGiftsButtons()

proc activateGifts*(sw: SocialWindow) =
    sw.setActiveTab(SocialTabType.Gifts)
    sw.giftScrollNode.enabled = true
    sw.friendsScrollNode.enabled = false
    sw.activeTab = sw.giftsTab
    sw.rankingTab.rootNode.enabled = false
    sw.giftsTab.rootNode.enabled = true
    sw.friendsTab.rootNode.enabled = false
    sw.bottomButtons.enabled = false
    sw.tabIn(sw.giftsTab)
    sw.checkGiftsScrollLocking()

proc activateNoPermissionsScreen*(sw: SocialWindow) =
    sw.giftScrollNode.enabled = false
    sw.friendsScrollNode.enabled = false
    sw.rankingTab.rootNode.enabled = false
    sw.giftsTab.rootNode.enabled = false
    sw.friendsTab.rootNode.enabled = false
    sw.buttonFriends.enabled = false
    sw.buttonGifts.enabled = false
    sw.buttonRanking.enabled = false
    sw.bottomButtons.enabled = false
    sw.activeTab = sw.permissionsTab
    sw.tabIn(sw.permissionsTab)

proc activateLoadingScreen*(sw: SocialWindow) =
    sw.giftScrollNode.enabled = false
    sw.friendsScrollNode.enabled = false
    sw.rankingTab.rootNode.enabled = false
    sw.giftsTab.rootNode.enabled = false
    sw.friendsTab.rootNode.enabled = false
    sw.buttonFriends.enabled = false
    sw.buttonGifts.enabled = false
    sw.buttonRanking.enabled = false
    sw.bottomButtons.enabled = false
    sw.activeTab = sw.loadingTab
    sw.tabIn(sw.loadingTab)

proc activateRanking*(sw: SocialWindow) =
    sw.setActiveTab(SocialTabType.Ranking)
    sw.giftScrollNode.enabled = false
    sw.friendsScrollNode.enabled = false
    sw.activeTab = sw.rankingTab
    sw.rankingTab.rootNode.enabled = true
    sw.giftsTab.rootNode.enabled = false
    sw.friendsTab.rootNode.enabled = false
    sw.bottomButtons.enabled = false
    sw.tabIn(sw.rankingTab)

proc addFriendsFromFacebook(sw: SocialWindow, fd:JsonNode) =
    #echo "addFriendsFromFacebook with ", fd{"data"}
    #let dataStr = $fd{"data"}
    #let dataJson = parseJson(dataStr)
    for jFriend in fd{"data"}:
        let firstName = jFriend{"first_name"}.getStr
        let lastName = jFriend{"last_name"}.getStr
        #echo "Friend $# $#".format(firstName, lastName)
        let fbid = jFriend{"id"}.getStr
        var status = FriendStatus.SendGift
        var remainingTime:float = 0.float
        if sw.nextGiftTimes.hasKey(fbid):
            let nextGiftTime = sw.nextGiftTimes[fbid]
            remainingTime = timeLeft(nextGiftTime)
            echo "nextGiftTime - ", remainingTime
            if remainingTime > 0.float:
                status = FriendStatus.TickTime
        let newFriend = sw.newFriend(firstName, lastName, fbid, remainingTime)
        sw.addFriend(newFriend, status)

proc addInvitableFriendsFromFacebook(sw: SocialWindow, fd:JsonNode) =
    #echo "addInvitableFriendsFromFacebook with ", fd{"data"}
    #let dataStr = $fd{"data"}
    #let dataJson = parseJson(dataStr)
    for jFriend in fd{"data"}:
        echo "jFriend -", jFriend
        let invToken = jFriend{"id"}.getStr
        let firstName = jFriend{"first_name"}.getStr
        let lastName = jFriend{"last_name"}.getStr
        let data = jFriend{"picture"}{"data"}
        let imgUrl = data{"url"}.getStr

        let fh = (firstName&lastName).hash
        if sw.invitedFriendsHash.contains(fh):
            echo "Already invited ", fh, " ", firstName, " ", lastName
        else:
            let newFriend = sw.newInvitableFriend(firstName, lastName, invToken, imgUrl)
            sw.addFriend(newFriend, FriendStatus.Invite)

proc showGiftsAlert(sw: SocialWindow) =
    if not sw.giftsAlertShowed and sw.gifts.len > 0:
        sw.giftsAlert.findNode("gifts_count").getComponent(Text).text = $sw.gifts.len
        sw.anchorNode.addAnimation(sw.giftsAlert.animationNamed("complete"))
        sw.giftsAlertShowed = true

proc checkInvitedFriends(sw: SocialWindow): seq[tuple[fbid:string,hash:Hash]] =
    result = newSeq[tuple[fbid:string,hash:Hash]]()
    for f in sw.friends:
        if f.fbUserID.len > 0:
            let fHash = (f.firstName&f.lastName).hash
            if sw.invitedFriendsHash.contains(fHash):
                result.add((f.fbUserID,fHash))

proc sendInitRequestsNoCheck(sw: SocialWindow) =
    sw.tabIn(sw.loadingTab)

    let inv_friends_cb = proc(fd: JsonNode) =
        if sw.win.sceneView.isNil:
            return
        #echo "CB: - ", pretty(j)

        sw.addInvitableFriendsFromFacebook(fd)
        sw.addFriendsToView()
        let friendsFromInvite = sw.checkInvitedFriends()
        sharedServer().getGiftsList(friendsFromInvite, proc(res: JsonNode) =
            if sw.win.sceneView.isNil:
                return

            echo "getGiftsList res = ", res
            for key, val in res["response"]:
                let giftType = val["t"].str
                if giftType == "daily" or giftType == "invite":
                    var friendProfile = ""
                    if "fp" in val:
                        friendProfile = val["fp"].str
                    var fromFB = val{"ff"}.getStr
                    let firstGainItem = val["g"][0]
                    var rew: Reward
                    case firstGainItem["currency"].str:
                        of "Bucks":
                            rew = createReward(RewardKind.bucks, firstGainItem["amount"].getBiggestInt())
                        of "Chips":
                            rew = createReward(RewardKind.chips, firstGainItem["amount"].getBiggestInt())
                        of "Energy":
                            rew = createReward(RewardKind.parts, firstGainItem["amount"].getBiggestInt())
                            if isNilOrEmpty(fromFB):
                                fromFB = "100001544267465"
                    sw.addGift(key, friendProfile, fromFB, rew)
                    sw.showGiftsIn()

            var sendGift: int
            for friend in sw.friends:
                if friend.status == FriendStatus.SendGift:
                    sendGift.inc()
                    sw.activeFriends.inc()
                elif friend.status == FriendStatus.TickTime:
                    sw.activeFriends.inc()

            sharedAnalytics().wnd_community_open(sw.source, $sw.currentTabType, sw.activeFriends, sendGift, sw.gifts.len)

            sw.showGiftsAlert()
        )

        sw.tabOut(sw.loadingTab) do():
            case sw.currentTabType:
                of SocialTabType.Friends:
                    sw.activateFriends()
                of SocialTabType.Gifts:
                    sw.activateGifts()
                of SocialTabType.Ranking:
                    sw.activateRanking()
                else:
                    discard

    let friends_cb = proc(fd: JsonNode) =
        if fd.isNil:
            sw.activateNoPermissionsScreen()
        else:
            sw.addFriendsFromFacebook(fd)
            requestFBInvitableFriends(inv_friends_cb)

    sharedServer().getFriendsInfo(proc(res: JsonNode) =
        echo "getFriendsInfo res = ", res
        let r = res["response"]
        if not r.isNil and r.len > 0:
            for key, val in r:
                let lastGiftSendTime = val["nextGiftTime"].getFloat()
                sw.nextGiftTimes[key] = lastGiftSendTime
            echo "nextGiftTimes total ", sw.nextGiftTimes.len

        let invs = res["invites"]
        if not invs.isNil and invs.len > 0:
            for iHash in invs:
                discard sw.invitedFriendsHash.containsOrIncl(iHash.getInt().Hash)#add(iHash.getInt().Hash)
        echo "invitedFriends ", sw.invitedFriendsHash

        requestFBFriends(friends_cb)
    )

proc checkToken(sw: SocialWindow, token: FacebookAccessToken) =
    if not token.isNil and (token.grantedPermissions * PERMISSIONS == PERMISSIONS):
        sw.sendInitRequestsNoCheck()
    else:
        sw.activateNoPermissionsScreen()

proc sendInitRequests*(sw: SocialWindow)

proc requestPermissions(sw: SocialWindow) =
    fbSDK.getCurrentAccessToken() do(token: FacebookAccessToken):
        if token.isNil:
            ingameFacebookLogin(PERMISSIONS) do(token: FacebookAccessToken):
                if sw.win.sceneView.isNil:
                    let w = sharedWindowManager().show(SocialWindow)
                    w.setActiveTab(sw.currentTabType)
                    w.sendInitRequests()
                else:
                    sw.checkToken(token)
        else:
            fbSDK.logInWithReadPermissions(PERMISSIONS) do(error: FacebookException, result: FacebookLoginResult):
                if error.isNil and not sw.win.sceneView.isNil:
                    sw.checkToken(result.token)

proc sendInitRequests*(sw: SocialWindow) =
    when not facebookSupported:
        error "FACEBOOK NOT SUPPORTED!"
        sw.activateNoPermissionsScreen()
    else:
        fbSDK.getCurrentAccessToken() do(token: FacebookAccessToken):
            if not token.isNil:
                fbSDK.fetchCurrentPermissions() do(error: FacebookException, grantedPermissions: FacebookPermissionsSet, declinedPermissions: FacebookPermissionsSet):
                    if grantedPermissions * PERMISSIONS == PERMISSIONS:
                        sw.sendInitRequestsNoCheck()
                    else:
                        sw.activateNoPermissionsScreen()
            else:
                sw.activateNoPermissionsScreen()


method onInit*(sw: SocialWindow) =
    let win = newLocalizedNodeWithResource("common/gui/popups/precomps/friends_gifts_gui.json")

    sw.bkg = win.findNode("friend_gift_background")
    sw.moneyPanelOnTop = true

    let btnRanking = sw.bkg.findNode("ranking.png")
    let btnGifts = sw.bkg.findNode("gifts.png")
    let btnFriends = sw.bkg.findNode("friends.png")
    let btnPermissions = win.findNode("fb_button_01")
    let rectGifts = newRect(400, 250, 1400, 720)
    let rectFriends = newRect(250, 255, 1420, 540)

    sw.giftScrollNode = win.findNode("bars_parent")
    sw.giftBarParent = createNodeScroll(rectGifts, sw.giftScrollNode)
    sw.giftBarParent.scrollDirection = NodeScrollDirection.none
    sw.giftBarParent.bounces = true

    sw.giftScrollNode.component(ClippingRectComponent).clippingRect = rectGifts
    sw.giftScrollNode.enabled = false
    sw.giftsScrollContent = sw.giftScrollNode.findNode("NodeScrollContent")

    sw.friendsScrollNode = win.findNode("friends_parent")
    sw.friendsFrameParent = createNodeScroll(rectFriends, sw.friendsScrollNode)
    sw.friendsFrameParent.scrollDirection = NodeScrollDirection.none
    #sw.friendsFrameParent.bounces = true

    sw.friendsScrollNode.component(ClippingRectComponent).clippingRect = rectFriends
    sw.friendsScrollNode.enabled = true
    sw.friendsScrollContent = sw.friendsScrollNode.findNode("NodeScrollContent")

    sw.giftsAlert = win.findNode("alert_comp_small")
    sw.anchorNode.addChild(win)
    sw.bottomButtons = sw.anchorNode.findNode("bottom_buttons")
    sw.win = win
    sw.friends = @[]
    sw.gifts = @[]
    sw.initButtons()
    sw.setCollectGiftsText()

    sw.friendsTab = createTab(sw.win.findNode("friends_gui"), SocialTabType.Friends)
    sw.giftsTab = createTab(sw.win.findNode("gifts_gui"), SocialTabType.Gifts)
    sw.rankingTab = createTab(sw.win.findNode("ranking_gui"), SocialTabType.Ranking)
    sw.permissionsTab = createTab(sw.win.findNode("get_permissions"), SocialTabType.Permissions)
    #sw.friendsTab.rootNode.findNode("facebook_like_button").findNode("facebook_share").getComponent(Text).text = localizedString("FACEBOOK_LIKE")

    sw.buttonRanking = btnRanking.createButtonComponent(newRect(10,10,480,100))
    sw.buttonRanking.onAction do():
        sw.activateRanking()
        sharedAnalytics().wnd_community_tab_changed(sw.source, $sw.activeTab.tabType)

    sw.buttonGifts = btnGifts.createButtonComponent(newRect(10,10,400,100))
    sw.buttonGifts.onAction do():
        sw.activateGifts()
        sharedAnalytics().wnd_community_tab_changed(sw.source, $sw.activeTab.tabType)

    sw.buttonFriends = btnFriends.createButtonComponent(newRect(10,10,470,100))
    sw.buttonFriends.onAction do():
        sw.activateFriends()
        sharedAnalytics().wnd_community_tab_changed(sw.source, $sw.activeTab.tabType)

    sw.getPermissionsButton = btnPermissions.createButtonComponent(btnPermissions.animationNamed("press"), newRect(0,0,480,80))
    sw.getPermissionsButton.onAction do():
        sw.requestPermissions()

    sw.setRewardPerFriend(createReward(RewardKind.bucks, 100))
    sw.setDefaultGift(createReward(RewardKind.chips, 10000))

    sw.nextGiftTimes = newTable[string, float]()
    sw.invitedFriendsHash = initSet[Hash]()
    sw.loadingTab = newSocialTabSpinner(win)

    #sw.addFriend("1818629941484498", "ВАСИСУАЛИЙ-ВИТАЛИЙ", "ЛоханкинКукурузникович", FriendStatus.Invite) #TEST
    #sw.addFriendsToView()
    #sw.addGift("id", "1818629941484498", "1818629941484498", createReward("bucks", 500)) #TEST

    sw.mapFreeze(true)

method showStrategy*(sw: SocialWindow) =
    let inAnim = sw.bkg.animationNamed("in")

    sw.node.enabled = true
    sw.node.alpha = 1.0
    sw.anchorNode.addAnimation(inAnim)

    inAnim.onComplete do():
        sw.showGiftsAlert()

method hideStrategy*(sw: SocialWindow): float =
    sw.mapFreeze(false)

    let outAnim = sw.bkg.animationNamed("out")
    sw.win.addAnimation(outAnim)
    sw.node.hide(outAnim.loopDuration)
    if not sw.activeTab.isNil:
        sw.tabOut(sw.activeTab)

    sw.btnRight.alpha = 0.0
    sw.btnLeft.alpha = 0.0

    for friend in sw.friends:
        if not friend.timeAnim.isNil:
            friend.timeAnim.cancel()
    if not sw.giftsTab.glowIdleAnim.isNil:
        sw.giftsTab.glowIdleAnim.cancel()

    for c in sw.friendsScrollContent.children:
        sw.anchorNode.addAnimation(c.animationNamed("out"))

    return outAnim.loopDuration

method beforeRemove*(sw: SocialWindow) =
    procCall sw.WindowComponent.beforeRemove
    sharedAnalytics().wnd_community_closed(sw.source, $sw.currentTabType, sw.invitedFriends, sw.collectedGifts, sw.giftedBack)

proc showSocialWindow*(socialType: SocialTabType, source: string): SocialWindow {.discardable.} =
    result = sharedWindowManager().show(SocialWindow)
    if not result.isNil:
        result.source = source
        result.setActiveTab(socialType)
        result.sendInitRequests()

sharedDeepLinkRouter().registerHandler(
    "social"
    , onHandle = proc(route: string, next: proc()) =
        let socialType = parseEnum[SocialTabType](route, Friends)
        let w = showSocialWindow(socialType, "deepLink")
        if w.isNil:
            sharedWindowManager().onSceneAddedWithDeepLink = proc() =
                sharedWindowManager().onSceneAddedWithDeepLink = nil
                showSocialWindow(socialType, "deepLink")
                next()
        else:
            next()
)

registerComponent(SocialWindow, "windows")
