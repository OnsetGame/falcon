import nimx / [ http_request, timer, notification_center, pathutils, timer ]

import json, times, tables, strutils, logging, queues, hashes
import shared.user
import preferences
import shared.message_box

import falconserver / common / [ checks, response, currency ]
import falconserver.map.building.builditem
import shafa.game.message_types

import utils / [ timesync, game_state, httpcore_ex ]
import response_parser

import core / zone

export json

const productionServerUrl = "https://game-api.onsetgame.com"
const stageServerUrl* {.used.} = "https://stage-api.onsetgame.com/stage-master"
const localServerUrl {.used.} = "http://localhost:5001"

const clientVersion {.intdefine.}: int = 0


when defined(js) or defined(emscripten):
    import utils.js_helpers

    proc getServerUrl(): string =
        result = getCurrentHref()
        let branch = uriParam(result, "branch")
        if result.find(".onsetgame.com") == -1:
            result = productionServerUrl
        else:
            let firstSlash = result.find('/', 8)
            if firstSlash != -1:
                result.delete(firstSlash, result.len - 1)
            let firstDot = result.find('.', 8)
            if firstDot == -1:
                result = productionServerUrl
            else:
                result.insert("-api", firstDot)

        if branch.len > 0:
            result &= '/'
            result &= branch
else:
    import os

var gServerUrl*: string
proc serverUrl(): string =
    if gServerUrl.len == 0:
        when defined(stage):
            gServerUrl = stageServerUrl
        elif defined(local):
            gServerUrl = localServerUrl
        elif defined(js) or defined(emscripten):
            gServerUrl = getServerUrl()
        else:
            gServerUrl = sharedPreferences(){"apiUrl"}.getStr()
            if gServerUrl.len == 0:
                gServerUrl = productionServerUrl
        info "[Server] serverUrl: ", gServerUrl
    result = gServerUrl


type
    Server* = ref object {.inheritable.}
        timeDiff*: float
        requestQueue: Queue[proc()]
        requestInProgress: bool
        retryCounts: int
        timeoutTimer: Timer
        isBadConnection: bool
        isLostConnection: bool
        showProtocolLogs*: bool

    RealServer* = ref object of Server

var gServer : Server
const MAX_RETRY_COUNT = 20
const RESPONSE_TIMEOUT = 5.0

method init*(s:Server){.base.} =
    s.requestQueue = initQueue[proc()]()
    s.requestInProgress = false
    s.retryCounts = 0
    s.isLostConnection = false

proc setSharedServer*(s: Server = nil) =
    gServer = s

proc sharedServer*(): Server =
    if gServer.isNil:
        gServer = RealServer.new()
        gServer.init()
    result = gServer

proc hasActiveRequests*(s: Server): bool =
    result = s.requestQueue.len > 0

proc notifyConnectionLost(s: Server) =
    sharedNotificationCenter().postNotification("HIDE_BAD_CONNECTION")
    sharedNotificationCenter().postNotification("SHOW_LOST_CONNECTION_ALERT")

proc lostConnection(s: Server, r: Response) =
    s.isBadConnection = false
    info "[Server] RESP status code ", r.statusCode
    info "[Server] RESP status ", r.status
    info "[Server] RESP body ", r.body
    s.init()
    s.isLostConnection = true
    s.notifyConnectionLost()

proc parseResponse(r: Response): JsonNode =
    if r.body.len > 0:
        try: return parseJson(r.body)
        except: discard

proc hasConnectionError(r: Response): bool =
    if r.statusCode <= 0:
        info "[Server] Request with bad statusCode - ", r.statusCode, "  status ", r.status
        return true

    return false

proc hasHttpError(r: Response): bool =
    if r.statusCode > 400:
        info "[Server] Responce with httpError - ", r.statusCode, "  status ", r.status
        return true

    return false

proc hasLostConnection*(s: Server): bool =
    s.isLostConnection

proc checkResponse(jBody: JsonNode): bool =
    if not jBody.isNil:
        let status = jBody{"status"}.getInt()
        if status == StatusCode.OK.int:
            return true

        error "[Server] checkResponse invalid ", jBody
    else:
        error "[Server] checkResponse body isNil "

proc dequeueNextRequest(s: Server) =
    if s.requestQueue.len > 0:
        s.requestInProgress = true
        let p = s.requestQueue.dequeue()
        p()

when not defined(emscripten):
    let recFileName = getEnv("FALCON_REC")
    if recFileName.len != 0:
        info "[Server] recFileName = ", recFileName

    proc logRequest(meth, url, request, response: string, headers: openarray[(string, string)]) =
        var firstRequestTime {.global.}: float
        var requestID {.global.}: int

        if recFileName.len > 0:
            if firstRequestTime == 0:
                firstRequestTime = epochTime()
            let requestTime = epochTime() - firstRequestTime
            let f = open(recFileName, fmAppend)
            requestID += 1
            let headersJS = newJObject()
            for pair in headers:
                    headersJS[pair[0]] = %pair[1]
            f.write((json.`%*`({"id": requestID, "time": requestTime, "meth": meth, "url": url, "headers": headersJS, "request": request, "response": response})).pretty())
            f.write("\n\n")
            f.close()

proc retryRequestSend(s: Server, meth, url, body: string, headers: openarray[(string, string)], handler: proc(r: Response, jr: JsonNode), badResp: Response, onRequestSucceeded: proc(r: Response)) =
    if s.retryCounts < MAX_RETRY_COUNT:
        s.retryCounts.inc
        warn "[Server] Send request retry № ", s.retryCounts
        let headers = @headers
        sendRequest(meth, url, body, headers) do(r: Response):
            if hasConnectionError(r):
                discard newTimer(3.0, false) do():
                    s.retryRequestSend(meth, url, body, headers, handler, r, onRequestSucceeded)
            else:
                onRequestSucceeded(r)
    else:
        s.lostConnection(badResp)

proc sendRequestSerial*(s: Server, meth, url, body: string, headers: openarray[(string, string)], handler: proc(r: Response, jr: JsonNode)) =
    let headers = @headers
    s.requestQueue.enqueue() do():
        s.timeoutTimer = newTimer(RESPONSE_TIMEOUT, false) do():
            warn "[Server] Response timeout: " & url
            s.timeoutTimer.clear()
            s.timeoutTimer = nil
            s.isBadConnection = true
            sharedNotificationCenter().postNotification("SHOW_BAD_CONNECTION")

        info "> req ", url
        sendRequest(meth, url, body, headers) do(r: Response):
            # setTimeout(6.0) do():
            when not defined(emscripten):
                logRequest(meth, url, body, r.body, headers)

            # if s.showProtocolLogs:
            #     info url, ":\n\t", r.body

            var onRequestSucceeded = proc(r: Response) =
                info "> resp ", url
                s.timeoutTimer.clear()
                s.timeoutTimer = nil
                s.retryCounts = 0
                if s.isBadConnection:
                    s.isBadConnection = false
                    sharedNotificationCenter().postNotification("HIDE_BAD_CONNECTION")

                s.isLostConnection = false

                let jr = r.parseResponse()

                if checkResponse(jr):
                    handler(r, jr)
                else:
                    if jr.isNil:
                        s.lostConnection(r)
                    elif jr["status"].getInt() == StatusCode.IncorrectMinClientVersion.int:
                        sharedNotificationCenter().postNotification("CLIENT_VERSION_TOO_LOW")
                    elif jr["status"].getInt() == StatusCode.MaintenanceInProgress.int:
                        let maintenanceTime = if "maintenanceTime" in jr: jr["maintenanceTime"].getFloat() - jr["serverTime"].getFloat() + epochTime() else: epochTime() - 3600
                        sharedNotificationCenter().postNotification("MAINTENANCE_IN_PROGRESS", newVariant(maintenanceTime))
                    else:
                        s.lostConnection(r)

                    s.requestInProgress = false
                    return

                s.requestInProgress = false
                s.dequeueNextRequest()

            if "cheats" notin url:
                if hasConnectionError(r):
                    discard newTimer(1.0, false) do():
                        s.retryRequestSend(meth, url, body, headers, handler, r, onRequestSucceeded)
                    return

                if hasHttpError(r):
                    s.retryCounts = MAX_RETRY_COUNT - 2
                    discard newTimer(3.0, false) do():
                        s.retryRequestSend(meth, url, body, headers, handler, r, onRequestSucceeded)
                    return

            onRequestSucceeded(r)

    if not s.requestInProgress:
        s.dequeueNextRequest()

proc handleRedirectUrl(s: Server, r: JsonNode): bool =
    when not defined(js) and not defined(emscripten):
        if "apiUrl" in r:
            gServerUrl = r["apiUrl"].str
            warn "[Server] Got redirect URL: ", gServerUrl
            sharedPreferences()["apiUrl"] = %gServerUrl
            syncPreferences()
            result = true

proc onResponseReceived(s: Server, r: JsonNode) =
    if s.handleRedirectUrl(r):
        showMessageBox("Restart required", "New server url: " & serverUrl(), MessageBoxType.Error) do():
            info "[Server] Quitting"
            system.quit()

    parseEvents(r)

proc facebookToken(): string =
    result = currentUser().fbToken

method login*(s: Server, handler: proc(r: JsonNode) = nil) {.base.} = discard
method linkFacebookProfile*(s: Server, linkType: string, handler: proc(r: JsonNode)) {.base.} = discard
method spin*(s: Server, bet: int64, lines: int, slotMachineId: string, mode: JsonNode, data: JsonNode, handler: proc(r: JsonNode)) {.base.} = discard
method getMode*(s: Server, slotMachineId: string, mode: JsonNode, hhandler: proc(r:JsonNode)) {.base.} = discard

# method getMap*(s: Server, handler: proc(r: JsonNode) = nil) {.base.} = discard
method getStore*(s: Server, handler: proc(r: JsonNode) = nil) {.base.} = discard

method getCheatsConfig*(s: Server, handler: proc (r: JsonNode) = nil) {.base.} = discard
method sendCheatRequest*(s: Server, req: string, data: JsonNode, handler: proc (r: JsonNode) = nil) {.base.} = discard
method checkUpdates*(s: Server, handler: proc(r: JsonNode) = nil) {.base.} = discard

method sendQuestCommand*(s: Server, command: string, indx: int, customData: JsonNode = nil, handler: proc(r: JsonNode) = nil){.base.} = discard

method collectResources*(s: Server, fromBuild:string, handler: proc(r: JsonNode)) {.base.} = discard
method exchangeBucks*(s: Server, cTo: Currency, handler: proc(r: JsonNode)) {.base.} = discard
method updateProfile*(s: Server, name: string, avatar: int, handler: proc(r: JsonNode) = nil) {.base.} = discard

method completeTutorialStep*(s: Server, step: string, handler: proc(r: JsonNode) = nil) {.base.} = discard

method verifyAndCompletePurchase*(s: Server, info: JsonNode, handler: proc(r: JsonNode) = nil) {.base.} = discard
method profileStorageCommand*(s: Server, command: string, data: JsonNode, handler: proc(r: JsonNode) = nil) {.base.} = discard
method purchaseLogic*(s: Server, targetLogic: string, info: JsonNode = nil, handler: proc(r: JsonNode) = nil) {.base.} = discard

method getFortuneWheelState*(s: Server, handler: proc(r: JsonNode) = nil) {.base.} = discard
method spinFortuneWheel*(s: Server, handler: proc(r: JsonNode) = nil) {.base.} = discard

method getTournamentsList*(s: Server, sinceTimeSet: ref Table[string, float], handler: proc(r: JsonNode) = nil) {.base.} = discard
method getTutorialTournament*(s: Server, handler: proc(r: JsonNode) = nil) {.base.} = discard
method getTournamentInfo*(s: Server, partId: string, sinceTime: float, handler: proc(r: JsonNode) = nil) {.base.} = discard
method joinTournament*(s: Server, tournId: string, handler: proc(r: JsonNode) = nil) {.base.} = discard
method leaveTournament*(s: Server, partId: string, handler: proc(r: JsonNode) = nil) {.base.} = discard
method claimTournamentReward*(s: Server, partId: string, handler: proc(r: JsonNode) = nil) {.base.} = discard
method tournamentCreateFast*(s: Server, handler: proc(r: JsonNode) = nil) {.base.} = discard
method finishTournament*(s: Server, tournId: string, handler: proc(r: JsonNode) = nil) {.base.} = discard
method inviteTournamentBots*(s: Server, tournId: string, handler: proc(r: JsonNode) = nil) {.base.} = discard
method gainTournamentScore*(s: Server, partId: string, sinceTime: float, handler: proc(r: JsonNode) = nil) {.base.} = discard

method getFriendsInfo*(s: Server, handler: proc(r: JsonNode) = nil) {.base.} = discard
method sendGift*(s: Server, friendFBId: string, handler: proc(r: JsonNode)) {.base.} = discard

method getGiftsList*(s: Server, friendsWithInvite:seq[tuple[fbid:string,hash:Hash]], handler: proc(r: JsonNode) = nil) {.base.} = discard
method claimGift*(s: Server, id: string, sendBack: bool, handler: proc(r: JsonNode) = nil) {.base.} = discard

method addInvites*(s: Server, invitedFriendsHashes:seq[Hash], handler: proc(r: JsonNode) = nil) {.base.} = discard
method checkMessage*(s: Server, target: string, handler: proc(r: JsonNode) = nil) {.base.} = discard
method removeMessage*(s: Server, message: string, handler: proc(r: JsonNode) = nil) {.base.} = discard
method setGdprStatus*(s: Server, status: bool, handler: proc(r: JsonNode) = nil) {.base.} = discard
method activateBooster*(s: Server, boosterTag: string, handler: proc(r: JsonNode) = nil) {.base.} = discard
method ping*(s: Server, handler: proc(r: JsonNode) = nil) {.base.} = discard

method completeFreeRounds*(s: Server, slot: string, handler: proc(r: JsonNode) = nil) {.base.} = discard

const PING_TIMEOUT = 120.0
var pingTimer: Timer
proc setupPing(s: RealServer) =
    if not pingTimer.isNil:
        pingTimer.clear()
    pingTimer = setTimeout(PING_TIMEOUT) do():
        if s.hasActiveRequests():
            s.setupPing()
            return

        if currentUser().profileId.len != 0 and currentUser().sessionId.len != 0:
            pingTimer = nil
            if not s.hasLostConnection():
                s.ping()
            s.setupPing()
        else:
            pingTimer = nil
            s.login() do(jn: JsonNode):
                if not pingTimer.isNil:
                    pingTimer.clear()
                    pingTimer = nil
                sharedNotificationCenter().postNotification("HAVE_TO_RESTART_APP")
            s.setupPing()

# replacement for getTimeZone(), which don't takes DST into account
# we just calculete time difference with and without reset 'timezone' and 'DST' flags
# returned result format is similar to getTimeZone()
proc getWorkingTimezoneWithHack(): int =
    let t = getTime()
    var tInfoG = utc(t)
    info "[Server] GM timezone = ", tInfoG.timezone, ",  isDST = ", tInfoG.isDST, ",  HH = ", tInfoG.hour
    var tInfo = local(t)
    info "[Server] Local timezone = ", tInfo.timezone, ",  isDST = ", tInfo.isDST, ",  HH = ", tInfo.hour
    info "[Server] getTimeZone() = ", now().utcOffset #getTimeZone()
    when defined(emscripten):
        result = -now().utcOffset
    else:
        when tInfo.timeZone is int:
            tInfo.timezone = 0
        else:
            tInfo.timezone = utc()
        tInfo.isDST = false
        result = (t.toUnix - tInfo.toTime().toUnix).int
    info "[Server] Local hour = ", tInfo.hour, ",  diff with tz0 = ", result, " seconds"

proc credentialStorage(): JsonNode =
    ## Returns a JsonNode object that should store `profId` and `profPw` fields.
    ## Depending on api server url those should be different.
    let url = serverUrl()
    let prefs = sharedPreferences()
    if url == productionServerUrl:
        return prefs

    var creds = prefs{"creds"}
    if creds.isNil:
        creds = newJObject()
        prefs{"creds"} = creds

    result = creds{url}
    if result.isNil:
        result = newJObject()
        creds{url} = result

proc getLoginCredentials(): tuple[profId, passwd: string] {.inline.} =
    let creds = credentialStorage()
    result.profId = creds{"profId"}.getStr()
    result.passwd = creds{"profPw"}.getStr()

proc storeLoginCredentials(profId, passwd: string) {.inline.} =
    let creds = credentialStorage()
    creds["profId"] = %profId
    creds["profPw"] = %passwd
    syncPreferences()

proc handleLoginResponse(jr: JsonNode) =
    let u = currentUser()
    u.sessionId = jr["sessionId"].str
    u.chips = jr["chips"].num
    u.bucks = jr["bucks"].num
    u.parts = jr["parts"].num
    u.trtParams = jr{"trt"}

    if "pid" in jr:
        let newProfileId = jr["pid"].str
        info "[core.net.server] new profileId: ", newProfileId
        let newPassword = jr["pw"].str
        u.profileId = newProfileId
        let prefs = sharedPreferences()
        if "devId" in prefs:
            prefs.delete("devId")
        storeLoginCredentials(newProfileId, newPassword)

method login*(s: RealServer, handler: proc(r: JsonNode) = nil) =
    s.setupPing()

    var trtId = ""
    var requestIds = ""

    when defined(emscripten):
        trtId = uriParam(getCurrentHref(), "trt", "")
        let decodedHref = decodeUrl(getCurrentHref())
        echo "[Server] href - ", getCurrentHref()
        echo "[Server] decodedHref - " , decodedHref
        request_ids = uriParam(getCurrentHref(), "request_ids", "")
        echo "[Server] request_ids ", request_ids
        request_ids = decodeUrl(decodeUrl(request_ids))
        echo "[Server] decoded decoded request_ids ", request_ids

    let body = %*{"timeZone": getWorkingTimezoneWithHack()}
    when not defined(emscripten):
        if recFileName.len > 0:
            body["randomSeed"] = %(119461473)

    let (profileId, password) = getLoginCredentials()

    info "[Server] profileId: ", profileId
    info "[Server] platform ", userPlatform
    s.sendRequestSerial("POST", serverUrl() & "/auth/login", $body, {
            "Falcon-Client-Version": $clientVersion,
            "Falcon-Prof-Id": profileId, "Falcon-Pwd": password,
            "Falcon-FB-Tok": facebookToken(),
            "Falcon-Proto-Version": $protocolVersion,
            "Falcon-TRT": trtId,
            "Falcon-Platform": userPlatform,
            "Falcon-FB-Request-Ids": request_ids }) do(r: Response, jr: JsonNode):
        if s.handleRedirectUrl(jr):
            s.login(handler)
        else:
            handleLoginResponse(jr)
            if not handler.isNil: handler(jr)
            s.onResponseReceived(jr)

method linkFacebookProfile*(s: RealServer, linkType: string, handler: proc(r: JsonNode)) =
    let profileId = currentUser().profileId
    let sessid = currentUser().sessionId
    s.sendRequestSerial("POST", serverUrl() & "/auth/fb/link", "", {
            "Falcon-Client-Version": $clientVersion,
            "Falcon-Prof-Id": profileId, "Falcon-FB-Tok": facebookToken(),
            "Falcon-Proto-Version": $protocolVersion, "Falcon-Link-Type": linkType,
            "Falcon-Session-Id": sessid }) do(r: Response, jr: JsonNode):
        s.onResponseReceived(jr)
        if not handler.isNil: handler(jr)

proc post(s: RealServer, urlPath: string, body: JsonNode, handler: proc(r: JsonNode)) =
    # no sense in any requests if connection has lost
    if s.hasLostConnection():
        s.notifyConnectionLost()
        return

    s.setupPing()
    let b = if body.isNil: "" else: $body
    let profileId = currentUser().profileId
    let sessid = currentUser().sessionId
    s.sendRequestSerial("POST", serverUrl() & urlPath, b, {
            "Falcon-Client-Version": $clientVersion,
            "Falcon-Prof-Id": profileId,
            "Falcon-Session-Id": sessid}) do(r: Response, jr: JsonNode):
        s.onResponseReceived(jr)
        if not handler.isNil: handler(jr)

method checkUpdates*(s: RealServer, handler: proc(r: JsonNode) = nil) =
    let body = %*{"getQuests":0}
    s.post("/profile/update", body, handler)

method updateProfile*(s: RealServer, name: string, avatar: int, handler: proc(r: JsonNode) = nil)=
    let body = %*{"name": name, "avatar": avatar}
    s.post("/profile/update", body, handler)

method getCheatsConfig*(s: RealServer, handler: proc(r: JsonNode) = nil) =
    s.post("/cheats/update", nil, handler)

method sendCheatRequest*(s: RealServer, req: string, data: JsonNode, handler: proc (r: JsonNode) = nil) =
    info "send cheat ", req, " with data: ", data
    s.post(req, data, handler)

method sendQuestCommand*(s:RealServer, command:string, indx: int, customData: JsonNode = nil, handler: proc(r: JsonNode) = nil)=
    let data = %*{"questIndex": indx}
    if not customData.isNil:
        for k, v in customData:
            data[k] = v

    s.post("/quests/" & command, data, handler)

method spin*(s: RealServer, bet: int64, lines: int, slotMachineId: string, mode: JsonNode, data: JsonNode, handler: proc(r: JsonNode)) =
    let body = %*{ "bet": bet, "lines": lines }
    if not mode.isNil:
        body["mode"] = mode
    if not data.isNil:
        body["data"] = data
    s.post("/slot/spin/" & slotMachineId, body, handler)


method getMode*(s: RealServer, slotMachineId: string, mode: JsonNode, handler: proc(r: JsonNode)) =
    #let body = %*{}
    let body = newJObject()
    if not mode.isNil:
        body["mode"] = mode
    s.post("/slot/getMode/" & slotMachineId, body, handler)

method collectResources*(s: RealServer, fromBuild: string, handler: proc(r: JsonNode)) =
    let body = %*{ "from": fromBuild }
    s.post("/collect/resources", body, handler)

method exchangeBucks*(s: RealServer, cTo: Currency, handler: proc(r: JsonNode)) =
    let body = %*{"Falcon-Exchange-Currency-To": cTo.int}
    s.post("/profile/exchange", body, handler)

method getStore*(s: RealServer, handler: proc(r: JsonNode)) =
    s.post("/store/get", newJObject(), handler)

method completeTutorialStep*(s: RealServer, step: string, handler: proc(r: JsonNode) = nil) =
    s.post("/tutorial/step/" & step, newJObject(), handler)


method getFortuneWheelState*(s: RealServer, handler: proc(r: JsonNode)) =
    s.post("/fortune/state", newJObject(), handler)

method spinFortuneWheel*(s: RealServer, handler: proc(r: JsonNode)) =
    s.post("/fortune/spin", newJObject(), handler)


method getTournamentsList*(s: RealServer, sinceTimeSet: ref Table[string, float], handler: proc(r: JsonNode)) =
    let data = newJObject()
    if not sinceTimeSet.isNil:
        let sinceTime = newJObject()
        for k,v in sinceTimeSet:
            sinceTime[k] = %v
        data["sinceTime"] = sinceTime

    s.post("/tournaments/list", data, handler)

method getTutorialTournament*(s: RealServer, handler: proc(r: JsonNode)) =
    s.post("/tournaments/tutorial", newJObject(), handler)

method getTournamentInfo*(s: RealServer, partId: string, sinceTime: float, handler: proc(r: JsonNode)) =
    let data = %*{"partId": partId, "sinceTime": sinceTime}
    s.post("/tournaments/info", data, handler)

method joinTournament*(s: RealServer, tournId: string, handler: proc(r: JsonNode) = nil) =
    let data = %*{"tournamentId": tournId}
    s.post("/tournaments/join", data, handler)

method leaveTournament*(s: RealServer, partId: string, handler: proc(r: JsonNode) = nil) =
    let data = %*{"partId": partId};
    s.post("/tournaments/leave", data, handler)

method claimTournamentReward*(s: RealServer, partId: string, handler: proc(r: JsonNode) = nil) =
    let data = %*{"partId": partId};
    s.post("/tournaments/claim", data, handler)

method tournamentCreateFast*(s: RealServer, handler: proc(r: JsonNode)) =
    s.post("/tournaments/createfast", newJObject(), handler)

method finishTournament*(s: RealServer, tournId: string, handler: proc(r: JsonNode)) =
    let data = %*{"tournamentId": tournId}
    s.post("/tournaments/finish", data, handler)

method inviteTournamentBots*(s: RealServer, tournId: string, handler: proc(r: JsonNode)) =
    let data = %*{"tournamentId": tournId}
    s.post("/tournaments/bots/join", data, handler)

method gainTournamentScore*(s: RealServer, partId: string, sinceTime: float, handler: proc(r: JsonNode)) =
    let data = %*{"partId": partId, "sinceTime": sinceTime}
    s.post("/tournaments/gain", data, handler)


method getFriendsInfo*(s: RealServer, handler: proc(r: JsonNode)) =
    let data = %*{}
    s.post("/friends/info", data, handler)

method sendGift*(s: RealServer, friendFBId: string, handler: proc(r: JsonNode)) =
    let data = %*{"toProfileFB": friendFBId}
    s.post("/friends/gift/send", data, handler)

method getGiftsList*(s: RealServer, friendsWithInvite:seq[tuple[fbid:string,hash:Hash]], handler: proc(r: JsonNode)) =
    let data = %*{}
    if friendsWithInvite.len > 0:
        var fwiJson = newJObject()
        for f in friendsWithInvite:
            fwiJson[f.fbid] = %f.hash
        data["friendsWithInvite"] = fwiJson

    s.post("/gifts/list", data, handler)

method claimGift*(s: RealServer, id: string, sendBack: bool, handler: proc(r: JsonNode)) =
    let data = %*{"id": id, "sendBack": sendBack}
    s.post("/gifts/claim", data, handler)

method addInvites*(s: RealServer, newFriendsHashes:seq[Hash], handler: proc(r: JsonNode) = nil) =
    let newHashes = newJArray()
    for h in newFriendsHashes:
        newHashes.add(%h)
    let data = %*{"hashes": newHashes}
    s.post("/invites/add", data, handler)

method verifyAndCompletePurchase*(s: RealServer, info: JsonNode, handler: proc(r: JsonNode) = nil) =
    ## Send request to server with succeded purchase info.
    s.post("/purchase", info, handler)

method purchaseLogic*(s: RealServer, targetLogic: string, info: JsonNode = nil, handler: proc(r: JsonNode) = nil) =
    ## Send request to one of server purchase logic.
    var info = info
    if info.isNil: info = newJObject()
    s.post("/purchases/" & targetLogic, info, handler)

method profileStorageCommand*(s: RealServer, command: string, data: JsonNode, handler: proc(r: JsonNode) = nil) =
    s.post("/profile/storage/" & command, data, handler)

method checkMessage*(s: RealServer, target: string, handler: proc(r: JsonNode) = nil) =
    let body = %*{"target": target}
    s.post("/message/" & "check", body, handler)

method removeMessage*(s: RealServer, message: string, handler: proc(r: JsonNode) = nil) =
    let body = %*{$mfKind: message}
    s.post("/message/" & "remove", body, handler)

method ping*(s: RealServer, handler: proc(r: JsonNode) = nil) =
    s.post("/ping", newJObject(), handler)

method setGdprStatus*(s: RealServer, status: bool, handler: proc(r: JsonNode) = nil) =
    let body = %*{"status": status}
    s.post("/user/gdpr", body, handler)

method activateBooster*(s: RealServer, boosterTag: string, handler: proc(r: JsonNode) = nil) =
    s.post("/boost/"&boosterTag, newJObject(), handler)

method completeFreeRounds*(s: RealServer, slot: string, handler: proc(r: JsonNode) = nil) =
    s.post("/free-rounds/" & slot & "/get-reward", newJObject(), handler)
