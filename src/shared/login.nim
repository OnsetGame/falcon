import json, times, strutils, logging, tables

import facebook_sdk.facebook_sdk
import facebook_sdk.facebook_login
import facebook_sdk.facebook_graph_request

import shared.user
import core.net.server
import shared.director
import shared.window.alert_window
import shared.window.window_manager
import shared.window.window_component
import shared.window.button_component
import shared.localization_manager
import utils / [ falcon_analytics, falcon_analytics_helpers, game_state, analytics, crashlytics_logger, timesync ]

import platformspecific.purchase_helper
import quest.quests

import falconserver.map.building.builditem
import falconserver.common.game_balance
import falconserver.auth.profile_types

import nimx / [ http_request ]
import core / notification_center

import screens.splash_screen

import slots.slot_machine_registry
import preferences
import core.zone
import shafa / game / booster_types
import core / features / [booster_feature, vip_system]

when defined(emscripten):
    import jsbind.emscripten

when defined(debug):
    import os

proc initialServerRequest*(callback: proc()) =
    let server = sharedServer()
    let user = currentUser()

    server.login do(j: JsonNode):
        info "[game_init] Got profile."

        if "serverTime" in j:
            syncTime(j["serverTime"].getFloat())

        user.gdpr = j{"gdpr"}.getBool()
        user.gdprReward = j{"gdprReward"}.getInt()

        if "migrated" in j:
            removeStatesByTag("QuestManager")

        if j.hasKey("isBro"):
            let cheats = j["isBro"].getBool()
            user.cheatsEnabled = cheats
            server.showProtocolLogs = true

        user.updateWallet(j["chips"].getBiggestInt(), j["bucks"].getBiggestInt(), j["parts"].getBiggestInt(), j["tourPoints"].getBiggestInt())

        let lvl  = j["lvl"].getInt()
        let cexp = j["xp"].getInt()
        let texp = j["txp"].getInt()
        var ava  = j["avatar"].getInt()
        if ava == ppFacebook.int and user.fbUserId.len == 0:
            ava = ppNotSet.int
        let vip  = j["vip"].getInt()
        var bets = newSeq[int]()

        if "allBets" in j:
            for b in j["allBets"]:
                bets.add(b.getInt)

        if "gb" in j:
            echo "receive game balance ", j["gb"]
            if "ab" in j:
                var abTestVariant = j{"ab"}.getStr()
                if abTestVariant.len != 0:
                    setUserProperty("ab", abTestVariant)
                else:
                    abTestVariant = "none"

                sendEvent("split_choose", %*{"control_group": abTestVariant}, false)


            sharedGameBalance().updateGameBalance(j["gb"])

        if "questConfig" in j:
            sharedQuestManager().initQuestConfigs(j["questConfig"])
            initZones()

        if "sceneToLoad" in j:
            let slotstr = j["sceneToLoad"].getStr()
            let b_id = parseEnum[BuildingId](slotstr)
            directorFirstSceneName(buildingIdToClassName[b_id])

        server.purchaseLogic("getStoreData", nil) do(jn: JsonNode):
            if "product_bundles" in jn:
                getPurchaseHelper().onRecieveProductBundlesFromServer(jn["product_bundles"])
            if "store_config" in jn:
                getPurchaseHelper().onRecieveStoreSettingsFromServer(jn["store_config"])
            if "offers" in jn:
                getPurchaseHelper().onRecieveProfileOffersDataFromServer(jn["offers"])
            if "vip_config" in jn:
                sharedVipConfig().fromJson(jn["vip_config"])

        if j["name"].getStr().len > 0:
            user.name = j["name"].getStr()

        if "boosterRates" in j:
            let rates = j["boosterRates"]
            user.boostRates.xp = rates[$btExperience].getFloat()
            user.boostRates.inc = rates[$btIncome].getFloat()
            user.boostRates.tp = rates[$btTournamentPoints].getFloat()


        findFeature(BoosterFeature).updateState(j)

        user.avatar = ava
        user.level = lvl
        user.toLevelExp = texp
        user.currentExp = cexp
        user.betLevels = bets

        user.vipLevel = max(j{"vip"}{"level"}.getInt(), 0)
        user.vipPoints = j{"vip"}{"points"}.getInt()

        setUserId(user.profileId)
        setCrashlyticsUserID(user.profileId)

        if user.level < 2 or not hasGameState("NEW_PLAYER_SENT"):
            newPlayer(user.profileId)
            setGameState("NEW_PLAYER_SENT", true)

        when defined(emscripten):
            discard EM_ASM_INT("""
            if (window.Raven !== undefined) {
                Raven.setUserContext({
                    profID: UTF8ToString($0)
                });
            }
            """, cstring(user.profileId))

        # Do not delete! Dumps login response to the stub_server
        # when defined(debug):
        #     writeFile("tests" / "login.json", j.pretty(4))

        sharedQuestManager().proceedQuests(j["quests"], reload = true)
        setGameState("SHOW_BACK_TO_CITY", sharedQuestManager().totalStageLevel() > 1)

        callback()

when facebookSupported:
    proc linkFacebookProfile(linkType: LinkFacebookType, cb: proc()) =
        sharedServer().linkFacebookProfile($linkType) do(resp: JsonNode):
            if resp{"restart"}.getBool():
                var preferences = sharedPreferences()
                for key, _ in preferences:
                    preferences.delete(key)
                syncPreferences()
                cheatDeleteQuestManager()
                cheatDeleteCurrentUser()
                directorFirstSceneName("")

                sharedNotificationCenter().postNotification("HAVE_TO_RESTART_APP")
                return

            let res = parseEnum[LinkFacebookResults](resp["result"].getStr())
            case res:
                of larCantBeLinked:
                    let alert = sharedWindowManager().show(AlertWindow)
                    alert.setup do():
                        alert.setUpBttnOkTitle("ALERT_BTTN_RETRY")
                        alert.setUpTitle("ALERT_LINK_FACEBOOK_TITLE")
                        alert.setUpDescription("ALERT_LINK_FACEBOOK_ERROR")
                        alert.makeOneButton()
                        alert.buttonOk.onAction do():
                            sharedNotificationCenter().postNotification("HAVE_TO_RESTART_APP")
                of larCollision:
                    let alert = sharedWindowManager().show(AlertWindow)
                    alert.setup do():
                        alert.setUpBttnOkTitle("ALERT_BTTN_YES")
                        alert.setUpTitle("ALERT_LINK_FACEBOOK_TITLE")
                        alert.setUpDescription("ALERT_LINK_FACEBOOK_DESC")

                        alert.setCancelButtonText(localizedString("ALERT_LINK_FACEBOOK_DEVICE"))
                        alert.buttonOk.onAction do():
                            alert.close()
                            currentUser().fbLoggedIn = true
                            linkFacebookProfile(lftFacebook, cb)

                        alert.setOkButtonText(localizedString("ALERT_LINK_FACEBOOK_FACEBOOK"))
                        alert.buttonCancel.onAction do():
                            alert.close()
                            currentUser().fbLoggedIn = true
                            linkFacebookProfile(lftDevice, cb)

                        alert.buttonClose.onAction do():
                            alert.close()
                            let user = currentUser()
                            user.fbUserId = ""
                            user.fbToken = ""
                            user.fbLoggedIn = false
                else:
                    cb()

    proc facebookLoginSuccess(cb: proc()) =
        let user = currentUser()
        if user.avatar == ppNotSet.int or user.name.len == 0:
            when defined(emscripten):
                sharedAnalyticsTimers()[FIRST_RUN_LOADSCREEN_BEGIN].start()

            let fields = %*{"fields": "id"}
            fbSDK.startGraphRequest("/me", fields) do(error: FacebookException, result: JsonNode):
                if error.isNil and not result.isNil:
                    sharedAnalytics().fb_first_login(result)

                    if user.avatar == ppNotSet.int:
                        user.avatar = ppFacebook.int
                    user.name = "user"
                    sharedServer().updateProfile(user.name, user.avatar) do(r: JsonNode):
                        cb()
        else:
            cb()


    proc ingameFacebookLoginSuccess(token: FacebookAccessToken, cb: proc()) =
        let user = currentUser()
        user.fbUserId = token.userID
        user.fbToken = token.tokenString

        assert(not cb.isNil)
        linkFacebookProfile(lftNone) do():
            facebookLoginSuccess() do():
                currentNotificationCenter().postNotification("USER_NAME_UPDATED", newVariant(user.name))
                currentNotificationCenter().postNotification("USER_AVATAR_UPDATED", newVariant(user.avatar))
                cb()

    proc loginFacebook(additionalPermissions: FacebookPermissionsSet, haveToLogin: bool = false, cb: proc(token: FacebookAccessToken)) =
        let permissions: FacebookPermissionsSet = {fbPublicProfile} + additionalPermissions
        fbSDK.logIn(permissions) do(error: FacebookException, res: FacebookLoginResult):
            if error.isNil and not res.token.isNil:
                cb(res.token)
            elif haveToLogin:
                loginFacebook(additionalPermissions, haveToLogin, cb)
            else:
                cb(nil)

    proc ingameFacebookLogin*(additionalPermissions: FacebookPermissionsSet, cb: proc(token: FacebookAccessToken)) =
        fbSDK.getCurrentAccessToken() do(token: FacebookAccessToken):
            if token.isNil:
                loginFacebook(additionalPermissions, false) do(token: FacebookAccessToken):
                    if not token.isNil:
                        ingameFacebookLoginSuccess(token) do():
                            cb(token)
            else:
                ingameFacebookLoginSuccess(token) do():
                    cb(token)

    proc ingameFacebookLogin*(cb: proc(token: FacebookAccessToken)) =
        let additionalPermissions: FacebookPermissionsSet = {}
        ingameFacebookLogin(additionalPermissions, cb)

    proc prepareFacebook*(cb: proc()) =
        fbSDK.getCurrentAccessToken() do(token: FacebookAccessToken):
            if not token.isNil:
                let user = currentUser()
                user.fbUserId = token.userID
                user.fbToken = token.tokenString
                user.fbLoggedIn = true

                initialServerRequest() do():
                    facebookLoginSuccess(cb)
            else:
                when defined(emscripten):
                    let additionalPermissions: FacebookPermissionsSet = {}
                    loginFacebook(additionalPermissions, true) do(token: FacebookAccessToken):
                        let user = currentUser()
                        user.fbUserId = token.userID
                        user.fbToken = token.tokenString
                        user.fbLoggedIn = true

                        initialServerRequest() do():
                            facebookLoginSuccess(cb)
                else:
                    initialServerRequest(cb)
else:
    proc prepareFacebook*(cb: proc()) =
        cb()
    proc ingameFacebookLogin*(cb: proc(token: FacebookAccessToken)) =
        cb(nil)
    proc ingameFacebookLogin*(permissions: FacebookPermissionsSet, cb: proc(token: FacebookAccessToken)) =
        cb(nil)
