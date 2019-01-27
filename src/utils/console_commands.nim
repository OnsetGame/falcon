import tables, json, logging, strutils, times, sequtils
import preferences

import nimx / [ types, matrixes, class_registry, image, view_render_to_image, mini_profiler ]
import core / notification_center
import quest.quests

import utils / [ console, helpers, game_state ]
import shared / [ director, game_init, game_scene, user,
                  localization_manager, window/button_component, deep_links,
                  cheats_view]
import core.net.server
import falconserver.map.building.builditem
import slots.slot_machine_registry
import rod / [ viewport, node ]
import map.tiledmap_view

import facebook_sdk.facebook_sdk
import platformspecific / image_sharing

import tilemap.tile_map
import shared / window / [window_manager, window_component, new_feature_window, new_slot_window]
import core.zone

import core / slot / [base_slot_machine_view]

import map / tiledmap_view
import core / flow / flow_state_types


proc toSlotMachineName(s: string): BuildingId =
    case s:
        of "eiffel": result = dreamTowerSlot
        of "balloon": result = balloonSlot
        of "candy": result = candySlot
        of "ufo": result = ufoSlot
        of "witch": result = witchSlot
        of "mermaid": result = mermaidSlot
        of "groovy": result = groovySlot
        of "test": result = testSlot
        of "candy2": result = candySlot2
        of "card": result = cardSlot
        else: result = parseEnum[BuildingId](s, noBuilding)


proc start(args: seq[string]): string =
    if args[0] == "map":
        directorMoveToMap()
        return "load map "

    var slotMachineName = toSlotMachineName(args[0])
    if slotMachineName.buidingKind != slot:
        return "slot doesnt exist: " & args[0]

    let scene = startSlotMachineGame(slotMachineName, smkDefault)
    return "load slot " & scene.className

registerConsoleComand(start, "start (slotName: string)", "slots: eiffel, balloon, candy, ufo, witch, mermaid, test \nother: map")

when editorEnabled:
    import rod.edit_view

    proc editor(args: seq[string]): string =
        result = "start editing rootNode"
        var node: Node
        let gs = currentDirector().gameScene()
        let editor = startEditor(gs)

        if args.len() > 0:
            node = gs.rootNode.findNode(args[0])
            if node.isNil:
                result = "node for editing not found "
            else:
                editor.selectNode(node)
                result = "start editing node " & node.name

    registerConsoleComand(editor, "editor (nodeName: string)")

proc keyShouldBeKeptOnProfileReset(k: string): bool =
    k.startsWith("SAVED_PROFILE_") or k in ["consoleHistory", "profPw", "profId", "creds"]

proc save_profile(args: seq[string]): string =
    if args.len() == 0:
        return "please write save name"

    sharedServer().profileStorageCommand("save", %*{"save_name": args[0]}) do(j: JsonNode):
        if j{"status"}.getStr() == "OK":
            info "save profile for name ", args[0]

    let key = "SAVED_PROFILE_" & args[0]
    let currPref = newJObject()
    let prefs = sharedPreferences()

    for k, v in prefs:
        if not keyShouldBeKeptOnProfileReset(k):
            currPref[k] = v

    prefs[key] = %currPref
    syncPreferences()

registerConsoleComand(save_profile, "save_profile(newName: string)")


proc restore_profile(args: seq[string]): string =
    if args.len == 0:
        return "please write name for restoring profile "

    sharedServer().profileStorageCommand("restore", %*{"save_name": args[0]}) do(j: JsonNode):
        if j{"status"}.getStr() == "OK":
            info "restore profile for name ", args[0]
            initGame()

    let key = "SAVED_PROFILE_" & args[0]
    let prefs = sharedPreferences()
    let savedPref = prefs{key}
    let keysToDelete = toSeq(prefs.fields.keys)
    for k in keysToDelete:
        if not keyShouldBeKeptOnProfileReset(k):
            prefs.delete(k)

    if not savedPref.isNil:
        for k, v in savedPref:
            if not keyShouldBeKeptOnProfileReset(k):
                prefs[k] = v

    syncPreferences()
    cheatDeleteQuestManager()
    cheatDeleteCurrentUser()
    result = "try to restore profile"

registerConsoleComand(restore_profile, "restore_profile(name: string)")

proc saved_profiles_list(args: seq[string]): string =
    sharedServer().profileStorageCommand("getSaved", newJObject()) do(j: JsonNode):
        if j{"status"}.getStr() == "OK":
            let profiles = j{"saved_profiles"}
            info "get saved profiles"
            for p in profiles:
                info p.getStr()

    result = "try to get saved profiles"

registerConsoleComand(saved_profiles_list, "saved_profiles_list()")

proc show_gui(args: seq[string]): string =
    if args.len() == 0:
        return
    let gs:GameScene = currentDirector().gameScene()
    var gui = gs.rootNode.findNode("GUI")
    if gui.isNil:
        gui = gs.rootNode.findNode("gui_parent")
    if gui.isNil:
        return

    var isShow = false
    try: isShow = parseBool(args[0])
    except:
        result = "invalid value"
        return

    if gs of GameSceneWithCheats:
        let gsc = gs.GameSceneWithCheats
        if isShow:
            gui.enabled = true
            if not gsc.cheatsView.isNil:
                gsc.cheatsView.hidden = false
            result = "show gui"
        else:
            gui.enabled = false
            if not gsc.cheatsView.isNil:
                gsc.cheatsView.hidden = true
            result = "hide gui"

registerConsoleComand(show_gui, "show_gui (isShow: bool)")

proc add_tutorial_event(args: seq[string]): string =
    if args.len == 0:
        return "please write tutorial name"

    result = "do tutorial " & args[0]

registerConsoleComand(add_tutorial_event, "add_tutorial_event(name: string)")


## Console cheats
proc addChips(args: seq[string]): string=
    if args.len > 0:
        result = args[0]
        var body = %*{"machine": "null", "value": args[0]}
        sharedServer().sendCheatRequest("/cheats/chips", body) do(jn: JsonNode):
            currentNotificationCenter().postNotification("chips", newVariant(jn))
    else:
        result = "wrong arguments!"

proc setChips(args: seq[string]): string=
    discard addChips(@["0"]) #reset chips
    result = addChips(args)

proc addExp(args: seq[string]): string=
    if args.len > 0:
        result = args[0]
        var body = %*{"machine": "null", "value": args[0]}
        sharedServer().sendCheatRequest("/cheats/exp", body) do(jn: JsonNode):
            currentNotificationCenter().postNotification("exp", newVariant(jn))
    else:
        result = "wrong arguments!"

proc addTP(args: seq[string]): string=
    if args.len > 0:
        result = args[0]
        var body = %*{"machine": "null", "value": args[0]}
        sharedServer().sendCheatRequest("/cheats/tourpoints", body) do(jn: JsonNode):
            currentNotificationCenter().postNotification("tourPoints", newVariant(jn))
    else:
        result = "wrong arguments!"

proc setLevel(args: seq[string]):string =
    if args.len == 1:
        result = args[0]
        var body = %*{"machine": "null", "value": args[0]}
        sharedServer().sendCheatRequest("/cheats/level", body) do(jn: JsonNode):
            currentNotificationCenter().postNotification("exp", newVariant(jn))
    else:
        result = "wrong arguments!"

registerConsoleComand(addChips, "addChips (amount:int)")
registerConsoleComand(setChips, "setChips (amount:int)")
registerConsoleComand(addExp, "addExp (amount:int)")
registerConsoleComand(setLevel, "setLevel (amount:int)")
registerConsoleComand(addTP, "addTP (amount:int)")

proc mapDebugInfo(args: seq[string]): string =
    let gs = currentDirector().gameScene()
    if args.len > 0:
        let maxNodes = parseInt(args[0])
        if gs of TiledMapView:
            gs.TiledMapView.getTiledMap().setDebugMaxNodes(maxNodes)
            result = "show info with node count in compos. Maximum =  " & $maxNodes
    else:
        if gs of TiledMapView:
            gs.TiledMapView.getTiledMap().setDebugMaxNodes(0)
        result = "hide info with node count in compos"

registerConsoleComand(mapDebugInfo, "mapDebugInfo (maxNode: int)")

# Various crash simulations
proc crashNullPointer(args: seq[string]): string =
    var a: ptr int
    a[] = 5

proc crashAssert(args: seq[string]): string =
    doAssert(false)

proc crashStackOverflow(args: seq[string]): string =
    result = " 1 " & crashStackOverflow(args) & crashStackOverflow(args)

proc crashOutOfMem(args: seq[string]): string =
    var strs = newSeq[string]()
    for i in 0 .. 50:
        strs.add(newString(1024 * 1024 * 1024)) # Alloc 1Gb
        strs[^1][2 * 1024 * 1024] = 'o'

registerConsoleComand(crashStackOverflow, "crashStackOverflow()")
registerConsoleComand(crashNullPointer, "crashNullPointer()")
registerConsoleComand(crashAssert, "crashAssert()")
registerConsoleComand(crashOutOfMem, "crashOutOfMem()")

proc nextCrontTime(args: seq[string]):string=
    let nextExchangeDiscountTime = currentUser().nextExchangeDiscountTime
    result = $(fromSeconds(nextExchangeDiscountTime.int).getLocalTime())

registerConsoleComand(nextCrontTime, "nextCrontTime()")


proc showNimxButtons(args: seq[string]):string =
    if args.len > 0:
        let enable = parseBool(args[0])
        var bttns = newSeq[ButtonComponent]()
        componentsInNode(currentDirector().gameScene().rootNode, bttns)
        for bttn in bttns:
            bttn.nxButton.hasBezel = enable

    result = "showNimxButtons"

registerConsoleComand(showNimxButtons, "showNimxButtons()")

proc profiler(args: seq[string]):string =
    let profiler = sharedProfiler()
    profiler.enabled = not profiler.enabled

registerConsoleComand(profiler, "profiler()")

proc resetRate(args: seq[string]):string =
    removeGameState("LAST_SHOWED_DAY", "RATE_US")
    removeGameState("RATE_RATED", "RATE_US")

registerConsoleComand(resetRate, "resetRate()")

proc lostConnection(args: seq[string]):string =
    sharedNotificationCenter().postNotification("SHOW_LOST_CONNECTION_ALERT")

registerConsoleComand(lostConnection, "lostConnection()")

proc handleDeepLink(args: seq[string]): string =
    sharedDeepLinkRouter().handle(args[0])

registerConsoleComand(handleDeepLink, "handleDeepLink(path: string)")

when not defined(js) and not defined(emscripten) and not defined(android):
    import os
    proc screenShot(args: seq[string]):string=
        if args.len > 0:
            let name = args[0]
            let gs = currentDirector().gameScene()
            let image = gs.screenShot()
            let path = getCurrentDir() & "/" & name & ".png"
            image.writeToPNGFile(path)
            result = "save scrennShot to: " & path

    registerConsoleComand(screenShot, "screenShot(name: string)")

when facebookSupported:
    proc shareImage(args: seq[string]): string=
        let gs = currentDirector().gameScene()
        let image = gs.screenShot()
        fbSDK.shareImage(image, localizedFormat("FACEBOOK_SHARE_IMG_BONUS", "😎"))

        result = "shareImage: "

    registerConsoleComand(shareImage, "shareImage()")


proc showFeatureWindow(args: seq[string]):string=
    let supportedSlots = @[candySlot,balloonSlot,witchSlot,mermaidSlot,ufoSlot]
    let supportedFeatures = @[IncomeChips,IncomeBucks,Exchange,Tournaments,Wheel,Gift,Friends]

    proc help(): string =
        result = "\nSupported slots: "& join(map(supportedSlots, proc(b:BuildingId):string = $b)," ")
        result &= "\nSupported features: "& join(map(supportedFeatures, proc(f:FeatureType):string = $f)," ")

    if args.len == 1:
        let fName = args[0]
        var bid = noBuilding
        var fType = noFeature
        try:
            bid = parseEnum[BuildingId](fName)
        except: discard
        if bid == noBuilding:
            try:
                fType = parseEnum[FeatureType](fName)
            except: discard
            if fType == noFeature:
                result = "No window for "&fName
                result &= help()
                return

        if bid != noBuilding:
            let nsw = sharedWindowManager().show(NewSlotWindow)
            nsw.onReady = proc() =
                            let z = new(Zone)
                            z.name = $bid
                            nsw.setupSlot(z)

        if fType != noFeature:
            let nfw = sharedWindowManager().show(NewFeatureWindow)
            nfw.onReady = proc() =
                            let z = new(Zone)
                            let f = new(Feature)
                            f.kind = fType
                            z.feature = f
                            nfw.setupFeature(z)
    else:
        result = help()

registerConsoleComand(showFeatureWindow, "showFeatureWindow()")

proc hideNode(args: seq[string]): string=
    let name = args[0]
    let node = currentDirector().gameScene().rootNode.findNode(name)
    if not node.isNil:
        node.alpha = 0.0
    else:
        result = "node not found " & name

registerConsoleComand(hideNode, "hideNode(name: string)")

proc showNode(args: seq[string]): string=
    let name = args[0]
    let node = currentDirector().gameScene().rootNode.findNode(name)
    if not node.isNil:
        node.alpha = 1.0
    else:
        result = "node not found " & name

registerConsoleComand(showNode, "showNode(name: string)")



proc enableFlowStateDebug*(args: seq[string]): string=
    let root = currentDirector().gameScene().rootNode
    var debuger = root.findNode("FlowStateDebug")
    if debuger.isNil:
        debuger = root.newChild("FlowStateDebug")
    let dc = debuger.component(FlowStateRecordComponent)
    dc.speed = 15
    dc.textSize = 20

    if args.len > 0: dc.speed = parseFloat(args[0])
    if currentDirector().gameScene() of TiledMapView: dc.textSize = 64

registerConsoleComand(enableFlowStateDebug, "enableFlowStateDebug(speed: float)")

proc disableFlowStateDebug*(args: seq[string]): string=
    let node = currentDirector().gameScene().rootNode.findNode("FlowStateDebug")
    if not node.isNil:
        node.removeFromParent()

registerConsoleComand(disableFlowStateDebug, "disableFlowStateDebug()")

proc printFlow*(args: seq[string]): string=
    printFlowStates()

registerConsoleComand(printFlow, "printFlow()")

when defined(android):
    import nimx.utils.android, jnim

    jclass com.onsetgame.reelvalley.MainActivity of JVMObject:
        proc showSystemAlert(msg: string)

    proc showSystemAlert*(args: seq[string]): string=
        result = "alert(msg)"
        if args.len == 1:
            let msg = args[0]
            let act = cast[MainActivity](mainActivity())
            act.showSystemAlert(msg)

    proc userStats*(args: seq[string]): string=
        let u = currentUser()
        result = "$# $# $# $# $# $#".format($u.chips, $u.bucks, $u.parts, $u.tournPoints, $u.vipPoints, $u.vipLevel)
        discard showSystemAlert(@[result])

    registerConsoleComand(userStats, "userStats(msg)")


proc setVipPoints(args: seq[string]): string =
    if args.len > 0:
        if not args[0].isDigit():
            result = "Argument must be a number!"
            return

        var body = %*{"points": parseInt(args[0])}
        sharedServer().sendCheatRequest("/cheats/vip", body)
    else:
        result = "wrong arguments!"
registerConsoleComand(setVipPoints, "setVipPoints(points)")

proc setWheelFSTimer(args: seq[string]): string =
    if args.len > 0:
        if not args[0].isDigit():
            result = "Argument must be a number!"
            return

        var body = %*{"value": parseInt(args[0])}
        sharedServer().sendCheatRequest("/cheats/nfs", body)
    else:
        result = "wrong arguments!"
registerConsoleComand(setWheelFSTimer, "setWheelFSTimer(seconds)")

proc setWheelFreespins(args: seq[string]): string =
    if args.len > 0:
        if not args[0].isDigit():
            result = "Argument must be a number!"
            return

        var body = %*{"value": parseInt(args[0])}
        sharedServer().sendCheatRequest("/cheats/setWheelFreespins", body)
    else:
        result = "wrong arguments!"
registerConsoleComand(setWheelFreespins, "setWheelFreespins(amount)")


proc addFreeRounds(args: seq[string]): string =
    if args.len > 0:
        let slotName = toSlotMachineName(args[0])
        if slotName == noBuilding:
            return "slot doesnt exist: " & args[0]

        if not args[1].isDigit():
            result = "argument `rounds` must be a number!"
            return

        var body = %*{"rounds": parseInt(args[1]), "slotId": $slotName}
        sharedServer().sendCheatRequest("/cheats/addFreeRounds", body)
    else:
        result = "wrong arguments!"
registerConsoleComand(addFreeRounds, "addFreeRounds(slotId, rounds)")


proc startFreeRounds(args: seq[string]): string =
    if args.len > 0:
        let slotName = toSlotMachineName(args[0])
        if slotName.buidingKind != slot:
            return "slot doesnt exist: " & args[0]
        
        let scene = startSlotMachineGame(slotName, smkFreeRound)
        scene.BaseMachineView.freeRounds = true
        return "start free rounds for " & $slotName
    else:
        result = "wrong arguments!"
registerConsoleComand(startFreeRounds, "startFreeRounds(slotId)")

proc setExchangeDiscountIn(args: seq[string]): string=
    if args.len() != 1:
        return "Usage: setExchangeDiscountIn(seconds: int)"
    let s = parseInt(args[0])

    var body = %*{"value": s}
    sharedServer().sendCheatRequest("/cheats/setExchangeDiscountIn", body) do(jn: JsonNode):
        if "cronTime" in jn:
            currentUser().nextExchangeDiscountTime = parseFloat($jn["cronTime"])

    result = "setExchangeDiscountIn " & $s & " seconds"

registerConsoleComand(setExchangeDiscountIn, "setExchangeDiscountIn(seconds: int)")
