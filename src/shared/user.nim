import facebook_sdk.facebook_sdk
import nimx.notification_center
import message_box
import logging
import json
import observarble

import shared.localization_manager

import utils.rounded_sprite
import rod.component.sprite
import rod.node
import nimx.types
import nimx.image
import boolseq

import preferences
import strutils

import node_proxy / plugins / observarble_component
export observarble_component

var prototypeMechanics* = false
var userPlatform* = "UNKNOWN"
when defined(js) or defined(emscripten):
    userPlatform = "FACEBOOK"
elif defined(android):
    userPlatform = "ANDROID"
elif defined(ios):
    userPlatform = "IOS"
elif defined(windows):
    userPlatform = "PC_CLIENT"
elif defined(macosx):
    userPlatform = "MAC_CLIENT"

type BoostRates* = ref object
    xp*: float
    inc*: float
    tp*: float


observarble User:
    {vipLevel, vipPoints}

    ## User model at client side (for server-side model look into
    ## `falconserver.auth.profile`.
    profileId*     string  ## Profile id
    sessionId*     string  ## Active client-server session id

    chips*         int64   ## Chips - currency for betting on slot machines
    bucks*         int64   ## Bucks - more valuable currency than chips
    parts*         int64   ## Parts - currency used for building on map
    tournPoints*   int64   ## Tournament points - tournament winning score

    cheatsEnabled* bool    ## Trusted users can perform cheats for
                            ## development and testings purposes
    trtParams* JsonNode

    exchangeNumParts*  int ## Number of exchange operation for parts
    exchangeNumChips*  int ## Number of exchange operation for chips

    level*         int     ## Current level
    mCurrentExp*   int     ## Current experience
    toLevelExp*    int     ## Experience to next level
    name*          string  ## User name
    title*         string  ## User title
    avatar*        int     ## Current user's avatar
    vipLevel*      int
    vipPoints*     int
    betLevels*     seq[int]
    questsState*    BoolSeq
    clientState*      JsonNode
    nextExchangeDiscountTime*      float

    chipsPerHour*  int
    bucksPerHour*  int

    gdpr* bool
    gdprReward* int
    boostRates* BoostRates
    boosters* JsonNode


var gUser: User
var fbAvatar: Image # user facebook avatar

const EVENT_CURRENCY_UPDATED* = "EVENT_CURRENCY_UPDATED"
const EVENT_OUT_OF_CURRENCY*  = "EVENT_OUT_OF_CURRENCY"
const EVENT_LEVELPROG*        = "EVENT_LEVELPROG"
const ANALYTICS_EVENT_OUT_OF_CURRENCY* = "ANALYTICS_EVENT_OUT_OF_CURRENCY"

proc currentUser*(): User =
    ## Returns current user. If no global user was created before
    ## call to the function - new User object is generated.
    if gUser.isNil:
        gUser = User(
            sessionId: "",
            fbToken:  "",
            chips: 4000,
            bucks: 0,
            parts: 0,
            cheatsEnabled: false,
            fbLoggedIn: false,
            exchangeNumParts: 0,
            exchangeNumChips: 0,
            level: -1,
            mCurrentExp: 0,
            toLevelExp: 0,
            title: "",
            questsState: newBoolSeq(),
            clientState: newJObject(),
            gdpr: false,
            gdprReward: 0,
            boostRates: BoostRates(xp:1.0,inc:1.0,tp:1.0)
        )
        gUser.vipLevel = -1
    result = gUser

proc cheatDeleteCurrentUser*() =
    gUser = nil

proc expProgress*(u: User): float =
    if u.toLevelExp != 0:
        result = clamp(u.mCurrentExp / u.toLevelExp, 0.0, 1.0)

proc `currentExp=`*(u: User, val:int)=
    u.mCurrentExp = val
    sharedNotificationCenter().postNotification(EVENT_LEVELPROG, newVariant(u.expProgress))

proc `currentExp`*(u: User): int =
    result = u.mCurrentExp

proc isEnoughtChips*(u: User, value: int): bool =
    result = u.chips >= value

proc isEnoughtBucks*(u: User, value: int): bool =
    result = u.bucks >= value

proc isEnoughtParts*(u: User, value: int): bool =
    result = u.parts >= value

proc updateWallet*(u: User, chips: int64 = -1, bucks: int64 = -1, parts: int64 = -1, tournPoints: int64 = -1) =
    if chips != -1:
        u.chips = chips
    if bucks != -1:
        u.bucks = bucks
    if parts != -1:
        u.parts = parts
    if tournPoints != -1:
        u.tournPoints = tournPoints
    sharedNotificationCenter().postNotification(EVENT_CURRENCY_UPDATED, newVariant(u) )

proc updateWallet*(u: User, wallet: JsonNode)=
    var chips = wallet["chips"].getBiggestInt()
    var bucks = wallet["bucks"].getBiggestInt()
    var parts = wallet["parts"].getBiggestInt()
    var tourPoints = wallet["tourPoints"].getBiggestInt()

    u.updateWallet(chips, bucks, parts, tourPoints)

proc avatarResource*(u: User): string=
    # Avatars are exported from AE profile_select_avatar composition.
    if u.avatar > 3 and u.avatar < 12:
        result = "ava_" & $u.avatar
    else:
        result = "ava_0"
    debug "avatarResource ", result, " for id ", u.avatar

proc isLoggedIn*(u: User): bool = u.sessionId.len != 0
    ## Checks if user is logged in - either received
    ## session ID by sending its device id to server, or
    ## by performing authentication via Facebook API.

proc isCheater*(u: User): bool = u.cheatsEnabled
    ## Only trusted users can have cheats enabled

proc updateLocalPreferences*(u: User) =
    ## Sync User object info with local preferences storage

proc isExchangeAllowed*(u: User): bool=
    if "exchange" in u.clientState:
        result = u.clientState["exchange"].getBool()

proc withdraw*(u: User, chips: int64 = 0, bucks: int64 = 0, parts: int64 = 0, source: string = ""): bool =
    let notif = sharedNotificationCenter()
    if u.chips < chips:
        # showMessageBox("Out of chips", "There are not enough chips on your balance")
        notif.postNotification(EVENT_OUT_OF_CURRENCY, newVariant("chips"))
        notif.postNotification(ANALYTICS_EVENT_OUT_OF_CURRENCY, newVariant((price: chips, source: source, kind: "chips")))
        return false
    if u.bucks < bucks:
        # showMessageBox("Out of bucks", "There are not enough bucks on your balance")
        notif.postNotification(EVENT_OUT_OF_CURRENCY, newVariant("bucks"))
        notif.postNotification(ANALYTICS_EVENT_OUT_OF_CURRENCY, newVariant((price: bucks, source: source, kind: "bucks")))
        return false
    if u.parts < parts:
        # showMessageBox("Out of parts", "There are not enough parts on your balance")
        notif.postNotification(EVENT_OUT_OF_CURRENCY, newVariant("parts"))
        return false
    result = true

proc setupAvatarSpriteForFacebook(parent: Node, image: Image) =
    let profileAvaSprite = parent.component(RoundedSprite)

    profileAvaSprite.needUpdateCondition = proc(): bool =
        return (profileAvaSprite.node.getGlobalAlpha() < 0.99)

    profileAvaSprite.image = image
    profileAvaSprite.borderSize = -0.01
    profileAvaSprite.discRadius = 0.31
    profileAvaSprite.discColor = newColor(1.0, 1.0, 1.0, 0.0)
    profileAvaSprite.discCenter = newPoint(0.5, 0.5)

proc completedQuests*(u: User): int =
    for i in 0..<u.questsState.len:
        if u.questsState[i] == true:
            result.inc()

proc getABOrDefault*(u: User, k:string, d: string = ""): string=
    if not u.trtParams.isNil and not u.trtParams{k}.isNil:
        return u.trtParams{k}.getStr()

    result = d

when facebookSupported:
    proc loadFbImage*(callback: proc()) =
        if currentUser().fbUserId.len == 0:
            callback()
            return

        if fbAvatar.isNil:
            let fbImageURL = "https://graph.facebook.com/$#/picture?type=large&height=160&width=160".format(currentUser().fbUserId)
            loadImageFromURL(fbImageURL) do(image: Image):
                fbAvatar = image
                callback()
        else:
            callback()

    proc setupFBImage*(parent: Node, callback: proc())=
        if currentUser().fbUserId.len > 0:
            loadFbImage() do():
                if not fbAvatar.isNil:
                    setupAvatarSpriteForFacebook(parent, fbAvatar)
                callback()
        else:
            fbAvatar = nil
            callback()
