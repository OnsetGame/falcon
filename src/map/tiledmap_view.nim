import
    nimx / [ button, progress_indicator, text_field, window, view_event_handling, image,
            context, view, animation, gesture_detector, event, font, text_field, timer, matrixes, panel_view, popup_button],
    rod / [node, viewport, ray, asset_bundle],
    rod / component / [camera, solid, ui_component, text_component, ae_composition],

    falconserver.map.building.builditem, falconserver.common.response, falconserver.quest.quest_types,

    json, algorithm, times, tables, sequtils, random, strutils, logging, math,

    shared / [cheats_view, director, user, shared_gui, game_scene, loading_info, localization_manager,
                message_box, chips_animation, alerts],
    shared / gui / [gui_pack, gui_module_types, gui_module, money_panel_module],


    utils / [game_state, timesync, angle_cut, sound_manager, pause, helpers, falcon_analytics, falcon_analytics_helpers,
            falcon_analytics_utils, color_segments],

    map_gui,
    quest / [ quests, quest_icon_component, quests_actions ],
    slots / [ all_slot_machines, slot_machine_registry ],

    shared / window / [button_component, tasks_window, task_complete_event, window_manager, welcome_window, special_offer_window, exchange_window, window_component],
    shared / window / [new_feature_window, new_slot_window, upgrade_window],
    shared / window / social / [social_window, friends_tab],
    shared.gui.side_timer_panel,
    shared.gui.new_quest_message_module,
    shared.tutorial,

    tiledmap_debug, tilemap.tile_map_pcg, tilemap.tile_map, tiledmap_menu, tiledmap_menu_flow, tiledmap_state, tiledmap_actions,
    preferences,
    platformspecific.social_helper,
    platformspecific.purchase_helper,
    facebook_sdk.facebook_sdk

import windows / store / store_window
import windows / quests / quest_window

import core / zone
import core / features / [ gifts_feature, booster_feature, slot_feature ]
import core / flow / flow_state_types
import core / flow / flow_states_implementation
import core / zone_helper
import core / net / server
import core / map / income_zone_feature_button
import core / notification_center

import nimx.formatted_text
import tournaments.tournaments_view

import wheel.wheel
import falconserver.purchases.product_bundles_shared

import platformspecific / android / rate_manager
import platformspecific / reports
import map / collect_resources



var mapSize : Size
const minCamScale = 2.8
const maxCamScale = 4.0
const midCamScale = minCamScale + (maxCamScale - minCamScale) * 0.5
const cameraIdleDelay = 3.0

type
    TiledMapView* = ref object of GameSceneWithCheats
        index : int
        gui*: MapGUI
        menuLayer: TiledMapMenu
        mapState: TiledMapState
        updateResAnim: Animation
        disableManualScroll*: bool
        mapNode*: Node
        tiledMap: TileMap
        tileDebugViewNode: Node
        idleCameraAnimation*: Animation
        allowGameEvents: bool
        questMsgController: QuestMessageController

    MapScrollListener = ref object of OnScrollListener
        mapView : TiledMapView
        accelAnim: Animation
        translationLocal*: Vector3
        translationLocalPrev*: Vector3

    MapZoomListener = ref object of OnZoomListener
        buf : float32
        mapView* : TiledMapView

proc updateResourcesOnBuildings*(v: TiledMapView)
proc zoomMap*(v: TiledMapView, factor : float, skipMinScale: bool = false, ratioW = 0.5, ratioH = 0.5)
method onZoomProgress*(ls: MapZoomListener, scale : float32) =
    if ls.mapView.disableManualScroll:
        return

    let d = 1.0 - (scale - ls.buf) * 2.0
    ls.mapView.zoomMap(d)
    ls.buf = scale

method onZoomStart*(ls: MapZoomListener) =
    ls.buf = 1.0'f32

proc getViewSize(v: TiledMapView): Size=
    result =  v.viewportSize * (v.frame.width / v.frame.height / (v.viewportSize.width / v.viewportSize.height))

proc calcCameraPosition*(v: TiledMapView, futPos: Vector3): Vector3=
    let cam = v.camera.node

    let viewportSize = v.getViewSize()
    var camMove = newVector3()
    var width = (viewportSize.width/2) * cam.scale.x
    var height = (viewportSize.height/2) * cam.scale.y

    if futPos.x > width and futPos.x < (mapSize.width - width):
        camMove.x = futPos.x
    elif futPos.x > width:
        camMove.x = mapSize.width - width
    else:
        camMove.x = width

    if futPos.y > height and futPos.y < (mapSize.height - height):
        camMove.y = futPos.y
    elif futPos.y > height:
        camMove.y = mapSize.height - height
    else:
        camMove.y = height

    result = camMove
    result.z = cam.position.z

proc zoomMap*(v: TiledMapView, scale: Vector3, skipMinScale: bool = false, ratioW, ratioH: float)=
    let cam = v.camera.node

    let viewportSize = v.getViewSize()
    var clampScale = clamp(scale.x, minCamScale, maxCamScale)
    var scale = newVector3(clampScale, clampScale, 1.0)

    let allowZoomByMin = skipMinScale or (scale.x >= minCamScale or cam.scale.x < scale.x)
    let allowZoomByBounds = scale.x * viewportSize.width < mapSize.width and scale.y * viewportSize.height < mapSize.height

    if allowZoomByMin and allowZoomByBounds:
        let camDif = cam.scale - scale
        var futCam = cam.position
        futCam.x = futCam.x + (ratioW - 0.5) * (viewportSize.width * camDif.x)
        futCam.y = futCam.y + (ratioH - 0.5) * (viewportSize.height * camDif.y)

        cam.scale = scale
        cam.position = v.calcCameraPosition(futCam)

        v.setNeedsDisplay()

    v.menuLayer.mapScaleChanged(cam.scale)

proc zoomMap*(v: TiledMapView, factor : float, skipMinScale: bool = false, ratioW = 0.5, ratioH = 0.5)=
    let cam = v.camera.node
    var sc = cam.scale
    sc = sc * newVector3(factor,factor,1)
    v.zoomMap(sc, skipMinScale, ratioW, ratioH)

proc cameraToPoint*(v: TiledMapView, target: Vector3, targetScale: float, callback: proc() = nil) =
    let
        final = newVector3(target.x, target.y)
        initial = v.camera.node.position
        initialScale = v.camera.node.scale.x
        camAnim = newAnimation()

    v.allowGameEvents = false
    camAnim.loopDuration = 0.75
    camAnim.numberOfLoops = 1
    camAnim.onAnimate = proc(p: float) =
        let easeP = expoEaseOut(p)

        let tp = interpolate(initial, final, easeP)
        v.camera.node.position = v.calcCameraPosition(tp)
        v.menuLayer.mapScaleChanged(v.camera.node.scale)

    camAnim.onComplete do():
        v.allowGameEvents = true
        if not callback.isNil:
            callback()

    v.addAnimation(camAnim)

proc cameraToPoint(v: TiledMapView, point: Vector3, scale: float, withAnim: bool, cb: proc() = nil) =
    if withAnim:
        v.cameraToPoint(point, scale, cb)
    else:
        v.zoomMap(scale)
        v.camera.node.position = v.calcCameraPosition point
        v.menuLayer.mapScaleChanged(v.camera.node.scale)

var firstMapLoad: bool

method sceneID*(v: TiledMapView): string  = "Map"

method initAfterResourcesLoaded*(v: TiledMapView) =
    v.pauseManager = newPauseManager(v)
    v.soundManager = newSoundManager(v)

    v.allowGameEvents = true

    var rn = newNodeWithResource("tiledmap/map/map.json")
    rn.name = "MAP"
    rn.position = newVector3(-64.0)
    v.tiledMap = rn.component(TileMap)

    let mapParent = newNode("map_parent")
    mapParent.addChild(rn)

    v.rootNode.addChild(mapParent)

    let menuLayerNode = v.rootNode.newChild("menuLayer")

    v.mapNode = rn
    v.mapState = createTiledMapState(v, v.tiledMap)

    # Used harcoded map size due to incorrect tiled map
    mapSize = newSize(18000.0, 8400.0)

    let rocksLayerTop = itemsForPropertyName[BaseTileMapLayer](v.tiledMap, "RocksPlaceholderTop")[0]
    let idxTop = v.tiledMap.layerIndex(rocksLayerTop.obj)
    let rocksLayerBottom = itemsForPropertyName[BaseTileMapLayer](v.tiledMap, "RocksPlaceholderBottom")[0]
    let idxBottom = v.tiledMap.layerIndex(rocksLayerBottom.obj)
    for rocksPart in [("up_right", idxTop), ("up_middle", idxTop), ("up_left", idxTop), ("right_up", idxBottom), ("right_middle", idxBottom),
    ("middle_down", idxBottom), ("right_down", idxBottom), ("left_down2", idxBottom), ("left_down1", idxBottom)]:
        let part = newNodeWithResource("tiledmap/rocks/precomps/" & rocksPart[0])
        part.position = newVector3(0.0, -544.0)
        v.tiledMap.insertLayer(part, rocksPart[1])

    let cameraNode = v.camera.node
    cameraNode.reparentTo(v.rootNode)
    cameraNode.component(Camera).zNear = -1
    cameraNode.positionZ = 5000


    v.gui = createMapGUI(cameraNode)

    v.menuLayer = createTiledMapMenu(menuLayerNode, v.tiledMap, v.gui)
    v.tileDebugViewNode = menuLayerNode.newChild("tileDebugViewNode")

    v.updateResAnim = newAnimation()
    v.updateResAnim.loopDuration = 0.25
    v.updateResAnim.addLoopProgressHandler(0.9, false) do():
        v.updateResourcesOnBuildings()
    v.gui.layout()

    v.gui.avatar = currentUser().avatar
    v.gui.level = currentUser().level
    v.gui.experience = currentUser().currentExp

    var cameraPoint = newVector3(mapSize.width * 0.5, mapSize.height * 0.5)
    for item in itemsForPropertyName[BaseTileMapLayer](v.tiledMap, "DefaultCameraXY"):
        var splxy = item.property.str.split(",")
        cameraPoint = v.tiledMap.positionAtTileXY(parseInt(splxy[0]), parseInt(splxy[1]))
        break

    if "tiledCameraPosition" in sharedPreferences():
        let jpos = sharedPreferences()["tiledCameraPosition"]
        cameraPoint = newVector3(jpos["x"].getFloat(), jpos["y"].getFloat(), jpos["z"].getFloat())

    v.cameraToPoint(cameraPoint, maxCamScale, false)

    quest_icon_component.getTileImage = proc(id: int16): Image = v.tiledMap.imageForTile(id)
    quest_icon_component.getLayerImage = proc(name: string): Image =
        # echo "get layerImage ", name
        let layer = layerByName[ImageMapLayer](v.tiledMap, name)
        if not layer.isNil:
            # echo "GOT image ", name
            result = layer.image

    quest_icon_component.getPropertyImage = proc(propName, propVal: string): Image =
        # echo "try icon for ", propName, " v ", propVal
        for item in itemsForPropertyValue[ImageMapLayer, string](v.tiledMap,propName, propVal):
            # echo "return layer icon for ", propName, " v ", propVal
            return item.obj.image
        for item in itemsForPropertyValue[Tile, string](v.tiledMap,propName, propVal):
            # echo "return tile icon for ", propName, " v ", propVal
            return item.obj.image

    v.setTimeout(1.5) do():
        if not firstMapLoad:
            mapLoadingTimer.clear()
            mapLoadingTimer = nil
            firstMapLoad = true
            sharedAnalytics().session_start(mapLoadingTime.int)

            let chipsIncomeFullPercent = (resourceCapacityProgress(Currency.Chips) * 100).int
            let bucksIncomeFullPercent = (resourceCapacityProgress(Currency.Bucks) * 100).int
            findFeature(BoosterFeature).sessionStartAnalitics(chipsIncomeFullPercent, bucksIncomeFullPercent)

    v.questMsgController = newQuestMessageController(v.notificationCenter)

    showOffersTimers(v.gui.gui_pack)

method wakeUp*(state: ZoomMapFlowState) =
    let cb = proc() =
        state.pop()
        if not state.onComplete.isNil:
            state.onComplete()

    let tview = currentDirector().gameScene().TiledMapView
    var zone: Zone
    var cameraPoint: Vector3
    if not state.data.isEmpty():
        zone = state.data.get(Zone)
        if zone.isNil:
            cb()
            return
        cameraPoint = zone.getQuestAnchorPos(tview.tiledMap)
    else:
        cameraPoint = state.targetPos

    tview.cameraToPoint(cameraPoint, maxCamScale, true, cb)

proc checkUpdates*(v: TiledMapView) =
    v.setTimeout(0.5) do():
        sharedQuestManager().updateQuests()

proc updateResourcesOnBuildings*(v: TiledMapView) =
    v.questMsgController.update()

const btnSize = newSize(60, 25)

proc createDebugButton(v: TiledMapView, title: string, buttonYBottom: var Coord, action: proc()) =
    let buttonOffset = btnSize.height / 2 - 5
    var buttonXPos = v.bounds.width - (20 + btnSize.width)

    let button = newButton(newRect(buttonXPos, buttonYBottom, btnSize.width, btnSize.height))
    button.title = title
    button.autoresizingMask = { afFlexibleMinX, afFlexibleMinY }
    button.onAction(action)
    v.cheatsView.addSubview(button)
    buttonYBottom -= btnSize.height + buttonOffset

proc createSlotButton(v: TiledMapView, title: string, slotId: BuildingId, buttonYBottom: var Coord) =
    v.createDebugButton(title, buttonYBottom) do():
        discard startSlotMachineGame(slotId, smkDefault)

import shared.window.window_manager
import shared.window.profile_window
import tournaments.tournament_result_window
import utils.console

when not defined(release):
    import rod.edit_view

var tiledebugEnabled = false

import shared.window.beams_alert_window
import shared.window.welcome_window
import narrative / [ narrative_bubble, narrative, narrative_character, quest_narrative ]
import platformspecific / webview_manager

import core / helpers / [ boost_multiplier, reward_helper ]


proc createDebugButtons(v: TiledMapView) =
    var buttonYBottom = v.bounds.height - 250

    when defined(android) or defined(emscripten):
        v.createDebugButton("PP", buttonYBottom) do():
            openPrivacyPolicy()


    v.createDebugButton("rews", buttonYBottom) do():
        # discard sharedWindowManager().show(WelcomeWindow)
        var rewards = newSeq[Reward]()
        # rewards.add(createReward(RewardKind.chips, 1))
        rewards.add(createReward(RewardKind.chips, 2))
        rewards.add(createReward(RewardKind.maxBet, 3))
        rewards.add(createReward(RewardKind.boosterExp, 420000))
        rewards.add(createReward(RewardKind.boosterIncome, 200000))
        rewards.add(createReward(RewardKind.boosterTourPoints, 5))
        rewards.add(createReward(RewardKind.boosterAll, 6))
        rewards.add(createReward(RewardKind.chips, 550000))
        rewards.add(createReward(RewardKind.chips, 770000))
        rewards.add(createReward(RewardKind.incomeChips, 88))
        rewards.add(createReward(RewardKind.incomeBucks, 88))


        # let rewWindow = sharedWindowManager().show(RewardWindow)
        # rewWindow.boxKind = RewardWindowBoxKind.gold
        # rewWindow.rewards = rewards
        let rewState = newFlowState(GiveRewardWindowFlowState)
        rewState.boxKind = RewardWindowBoxKind.gold
        rewState.rewards = rewards
        rewState.isForVip = true
        pushFront(rewState)


    v.createDebugButton("tilesDebug", buttonYBottom) do():
        tiledebugEnabled = not tiledebugEnabled

    when defined(emscripten):
        v.createDebugButton("Fullscreen", buttonYBottom) do():
            v.window.toggleFullscreen()

    v.createDebugButton("Candy2", buttonYBottom) do():
        currentDirector().moveToScene("Candy2SlotView")

    v.createDebugButton("Groovy", buttonYBottom) do():
        currentDirector().moveToScene("GroovySlotView")

    v.createDebugButton("Card", buttonYBottom) do():
        currentDirector().moveToScene("CardSlotView")

    when defined(debugLeaks):
        v.createDebugButton("Timers", buttonYBottom) do():
            for t in activeTimers():
                echo t.instantiationStackTrace

        v.createDebugButton("Crash", buttonYBottom) do():
            var i: ptr int
            i[] = 5

    when editorEnabled:
        v.createDebugButton("editor", buttonYBottom) do():
            discard startEditor(v)

    const NEW_FEATURE_TAG = "NewFeaturesShown"
    const FEATURES = @[FeatureType.IncomeChips,FeatureType.IncomeBucks,FeatureType.Exchange,FeatureType.Tournaments,FeatureType.Wheel,FeatureType.Gift,FeatureType.Friends]
    const NEW_SLOTS = @[candySlot,balloonSlot,witchSlot,mermaidSlot,ufoSlot]

    proc featureWindowWasShown(featureForZone:string): bool =
        result = hasGameState(featureForZone,NEW_FEATURE_TAG)
    proc saveFeatureWasShown(featureForZone:string) =
        setGameState(featureForZone,"",NEW_FEATURE_TAG)

    v.createDebugButton("clearNF", buttonYBottom) do():
        removeStatesByTag(NEW_FEATURE_TAG)

    v.createDebugButton("NFP", buttonYBottom) do():
        var nextFeature = noFeature
        for feature in FEATURES:
            if not featureWindowWasShown($feature):
                saveFeatureWasShown($feature)
                nextFeature = feature
                break

        if nextFeature == noFeature:
            let nfw = sharedWindowManager().show(UpgradeWindow)
        else:
            let nfw = sharedWindowManager().show(NewFeatureWindow)
            nfw.onReady = proc() =
                            let z = new(Zone)
                            let f = new(Feature)
                            f.kind = nextFeature
                            z.name = "Cheat"
                            z.feature = f
                            nfw.setupFeature(z)

    v.createDebugButton("NSP", buttonYBottom) do():
        var nextFeaturedZone:Zone = nil
        for bid in NEW_SLOTS:
            let z = new(Zone)
            z.name = $bid
            if not featureWindowWasShown($bid) and hasWindowForSlot(z):
                saveFeatureWasShown($bid)
                nextFeaturedZone = z
                break

        if nextFeaturedZone.isNil():
            let uw = sharedWindowManager().show(UpgradeWindow)
        else:
            let nsw = sharedWindowManager().show(NewSlotWindow)
            nsw.onReady = proc() =
                            nsw.setupSlot(nextFeaturedZone)

    v.createDebugButton("TF", buttonYBottom) do():
        var friends = newSeq[Friend]()
        var curFriend = Friend.new()

        let posX = 10.0
        let posY = v.frame.height / 7
        let cheat_width = 200.0
        let cheat_height = v.frame.height / 20
        let btn_size = v.frame.width / 21

        var panel = new(PanelView)
        panel.init( newRect(btn_size * 2.0 + posX, posY, cheat_width * 2.0, cheat_height * 7.0) )

        var btnAddFriend = newButton(newRect(0, cheat_height * 5 + 20, cheat_width, cheat_height - 5))
        btnAddFriend.title = "Add friend"

        var btnSubmit = newButton(newRect(cheat_width, cheat_height * 5 + 20, cheat_width, cheat_height - 5))
        btnSubmit.title = "Submit!"

        var textFields = newSeq[TextField]()
        var labels = newSeq[TextField]()

        for i in 0..4:
            let label = newLabel(newRect(5, 5 + i.Coord * cheat_height, cheat_width - 10, cheat_height))
            label.textColor = whiteColor()
            labels.add(label)
            panel.addSubview(label)

            if i < 4:
                var tf = newTextField(newRect(cheat_width, 5 + i.Coord * cheat_height, cheat_width - 10, cheat_height))

                tf.continuous = true
                panel.addSubview(tf)
                textFields.add(tf)

        labels[0].text = "facebook ID"
        labels[1].text = "first name"
        labels[2].text = "last name"
        labels[3].text = "time"
        labels[4].text = "status"

        textFields[0].text = "0"
        textFields[3].text = "0"

        let pb = PopupButton.new(newRect(cheat_width, 5 + 4.Coord * cheat_height, cheat_width - 10, cheat_height))
        var items = newSeq[string]()

        for st in FriendStatus.low..FriendStatus.high:
            items.add($st)
        pb.items = items

        panel.addSubview(pb)
        panel.addSubview(btnAddFriend)
        panel.addSubview(btnSubmit)

        btnAddFriend.onAction do():
            curFriend.fbUserID = textFields[0].text
            curFriend.firstName = textFields[1].text
            curFriend.lastName = textFields[2].text

            try:
                curFriend.time = textFields[3].text.parseFloat()
            except:
                echo "Invalid time format!"

            curFriend.status = parseEnum[FriendStatus](pb.selectedItem)
            friends.add(curFriend)
            curFriend = Friend.new()
        btnSubmit.onAction do():
            setGameState(LAST_SOURCE_SOCIAL, "cheats", ANALYTICS_TAG)

            let em = sharedWindowManager().show(SocialWindow)
            em.isCheat = true
            for f in friends:
                em.addFriend(f.fbUserID, f.firstName, f.lastName, f.status, f.time + epochTime())
                # echo "Add friend ", f.firstName, " ", f.lastName, " ", f.status
            em.addFriendsToView()
            em.activateFriends()

            panel.removeFromSuperview()
        v.addSubview(panel)

    var i = 0
    v.createDebugButton("CustomError", buttonYBottom) do():
        i.inc
        if i > 4:
            i = 0
        reportCustomException("MyEvent1", %*{"KEY" & $i & "1": "VALUE", "KEY" & $i & "2": 10, "KEY" & $i & "3": 40.0, "KEY" & $i & "4": true})

    # v.createDebugButton("NewOffers", buttonYBottom) do():
    #     let sod = (bid:"b16",expires: serverTime() + 60*60)
    #     let pb = getPurchaseHelper().productBundles()["b16"]
    #     pb.products = @[ProductItem(currencyType: VirtualCurrency.Bucks,amount: 2600), ProductItem(currencyType: VirtualCurrency.Energy,amount: 500)]
    #     pb.promoText = "60%\nOFF"
    #     pb.description = "Turbo Offer"
    #     let offerWindow = sharedWindowManager().createWindow(SpecialOfferWindow)
    #     offerWindow.prepareForBundle(sod)
    #     offerWindow.source = "map"
    #     sharedWindowManager().show(offerWindow)
    v.createDebugButton("Boosters", buttonYBottom) do():
        var f: Feature = nil
        for z in getZones():
            if z.feature.kind == FeatureType.Boosters:
                f = z.feature
                break
        if f.isNil:
            echo "No zone with feature.kind Boosters"
        else:
            f.BoosterFeature.printBoosters()
            echo "epochTime() - ", epochTime()

method init*(v: TiledMapView, r: Rect) =
    procCall v.GameScene.init(r)

    v.addDefaultOrthoCamera("Camera")
    discard sharedWindowManager()

    var sl : MapScrollListener
    new(sl)
    sl.mapView = v
    v.addGestureDetector(newScrollGestureDetector(sl))
    var zoomListener = MapZoomListener.new()
    zoomListener.buf = 1.0
    zoomListener.mapView = v
    v.addGestureDetector(newZoomGestureDetector(zoomListener))

    if startCountQuestWindowsAnalytics:
        backToCityInFirstQuest = true

method resizeSubviews*(v: TiledMapView, oldSize: Size) =
    procCall v.SceneView.resizeSubviews(oldSize) ## don't call resizeSubviews from GameScene
    # sharedNotificationCenter().postNotification("GAME_SCENE_RESIZE")
    v.gui.layout()
    sharedNotificationCenter().postNotification("GAME_SCENE_RESIZE", newVariant(v.bounds))

proc onSceneAdded(v: TiledMapView) =
    sharedServer().checkMessage("map")
    v.addAnimation(v.updateResAnim)
    addTutorialFlowState(tsCurrencyEnergy)

    for task in sharedQuestManager().activeTasks():
        sharedQuestManager().pauseQuest(task.id)

    pushFront(MapFlowState)
    dumpPending()

    if isFrameClosed($tsMapQuestReward2):
        addTutorialFlowState(tsMapPlaySlot)
        echo " \n addTutorialFlowState(tsMapPlaySlot) "

    # zoom to freeRound
    let zoomState = findFlowState(ZoomMapFlowState)
    if zoomState.isNil:
        for zone in getZones():
            if (zone.feature of SlotFeature) and zone.feature.SlotFeature.hasFreeRounds():
                let zoom = newFlowState(ZoomMapFlowState, newVariant(zone))
                pushFront(zoom)
                break

# proc cameraToQuest(v: TiledMapView, quest: Quest, cb:proc() = nil)=
#     let m = v.menuLayer.menuByQuestStatus(quest, quest.status)

#     if not m.isNil:
#         v.cameraToPoint(m.zonePosition, midCamScale, true, cb)

proc initNotificationsHandlers*(v: TiledMapView)=
    let notif = v.notificationCenter
    let user = currentUser()

    if user.cheatsEnabled:
        var sharedNotif = sharedNotificationCenter()
        sharedNotif.addObserver("chips", v) do(args: Variant):
            let jn = args.get(JsonNode)
            if jn.hasKey("chips"):
                currentUser().chips = jn["chips"].getBiggestInt()
                v.gui.chips = currentUser().chips

        sharedNotif.addObserver("bucks", v) do(args: Variant):
            let jn = args.get(JsonNode)
            if jn.hasKey("bucks"):
                currentUser().bucks = jn["bucks"].getBiggestInt()
                v.gui.bucks = currentUser().bucks

        sharedNotif.addObserver("parts", v) do(args: Variant):
            let jn = args.get(JsonNode)
            if jn.hasKey("parts"):
                currentUser().parts = jn["parts"].getBiggestInt()
                v.gui.parts = currentUser().parts

        sharedNotif.addObserver("tourPoints", v) do(args: Variant):
            let jn = args.get(JsonNode)
            if jn.hasKey("tourpoints"):
                currentUser().tournPoints = jn["tourpoints"].getBiggestInt()

        sharedNotif.addObserver("newQuestPack", v) do(args: Variant):
            let jn = args.get(JsonNode)
            if jn.hasKey("quests"):
                sharedQuestManager().clearAllQuests()
                sharedQuestManager().proceedQuests(jn["quests"], reload = true)

        notif.addObserver("UpdateMapState", v) do(args: Variant):
            sharedQuestManager().updateQuests() do():
                v.mapState.restoreMapState(currentUser().questsState)


    notif.addObserver("EVENT_MENU_BUTTON_CLICKED", v) do(args: Variant):
        let btnevent = args.get(string)
        v.soundManager.sendEvent(btnevent)

    sharedNotificationCenter().addObserver("DIRECTOR_ON_SCENE_ADD", v) do(args: Variant):
        if args.get(GameScene) == v:
            v.onSceneAdded()

    notif.addObserver("CameraAnimation_cameraToMenu", v) do(args: Variant):
        let targetPos = args.get(Vector3) - newVector3(0.0, 100.0 * midCamScale)
        v.cameraToPoint(targetPos, midCamScale)

    notif.addObserver(ANALYTICS_EVENT_OUT_OF_CURRENCY, v) do (args: Variant):
        let (price, source, kind) = args.get(tuple[price: int64, source: string, kind: string])

        if kind == "bucks":
            sharedAnalytics().wnd_not_enough_bucks_show(currentUser().bucks, source)

    notif.addObserver("SHOW_TOURNAMENTS_WINDOW", v) do(args:Variant):
        toggleTournamentsView(v, sharedServer())

    notif.addObserver("MapMenu_Facebook_pressed", v) do(args: Variant):
        showSocialWindow(SocialTabType.Friends, "buildingInfo")

    notif.addObserver("MapMenu_Zeppelin_pressed", v) do(args: Variant):
        showSocialWindow(SocialTabType.Gifts, "buildingInfo")

    notif.addObserver("MapMenu_Wheel_Spin_pressed", v) do(args: Variant):
        let w = sharedWindowManager().show(WheelWindow)
        if not w.isNil:
            w.source = "buildingInfo"

    notif.addObserver("ButtonBuildQuestAwailableAlert_OnClick", v) do(args: Variant):
        v.gui.gui_pack.showQuests(fromSource = 1)


    notif.addObserver("MapPlaySlotClicked", v) do(args: Variant):
        let bi = args.get(BuildingId)
        let tw = sharedWindowManager().show(TasksWindow)
        if not tw.isNil:
            notif.postNotification("TASK_WINDOW_ANALYTICS_SOURCE", newVariant("press_slot_building"))
            tw.setToSlot(bi)

    notif.addObserver("MapPlayFreeSlotClicked", v) do(args: Variant):
        let bi = args.get(BuildingId)
        let tw = sharedWindowManager().show(TasksWindow)

        if not tw.isNil:
            notif.postNotification("TASK_WINDOW_ANALYTICS_SOURCE", newVariant("press_slot_building"))
            tw.setToSlot(bi, true)

    notif.addObserver("UPDATE_QUEST", v) do(args: Variant):
        let quest = args.get(Quest)
        if not quest.config.isNil:
            case quest.status:
                of QuestProgress.InProgress, QuestProgress.GoalAchieved:
                    v.mapState.setPrepareMapState(quest.config)
                of QuestProgress.Completed:
                    v.mapState.setIdleMapState(quest.config)
                else:
                    discard
            v.dispatchAction(OpenQuestBalloonAction, newVariant(quest))
        else:
            warn "UPDATE QUEST ", quest.id , " CONFIG IS NIL!"

    notif.addObserver("ADD_NEW_QUEST", v) do(args: Variant):
        let quest = args.get(Quest)
        let qm = newNewQuestMessage(v.gui.gui_pack.rootNode, quest)
        v.questMsgController.add(qm)

        if not quest.config.isNil:
            v.dispatchAction(OpenQuestBalloonAction, newVariant(quest))
        else:
            warn "ADD_NEW_QUEST ", quest.id , " CONFIG IS NIL!"

    notif.addObserver("BuildingMenuClick_stadium", v) do(args:Variant):
        toggleTournamentsView(v, sharedServer())

    notif.addObserver("BuildingMenuClick_bank", v) do(args:Variant):
        showExchangeChipsWindow("bank_on_map")

    notif.addObserver("NewQuestMessage_click", v) do(args:Variant):
        v.gui.gui_pack.showQuests(fromSource = 6)

    notif.addObserver("BuildingMenuClick_cityHall", v) do(args:Variant):
        showStoreWindow(StoreTabKind.Boosters, "cityhall_building_menu")

    notif.addObserver("BuildingMenuClick_barberShop", v) do(args: Variant):
        discard sharedWindowManager().show(ProfileWindow)

    notif.addObserver(QUESTS_UPDATED_EVENT, v) do(args: Variant):
        for quest in sharedQuestManager().activeStories():
            v.dispatchAction(OpenQuestBalloonAction, newVariant(quest))

    notif.addObserver("UnlockQuest", v) do(args: Variant):
        let config = args.get(QuestConfig)
        sharedQuestManager().updateQuests() do():
            v.mapState.setPrepareMapState(config, false)
            v.mapState.setIdleMapState(config)

    notif.addObserver("ShowSpecialOfferWindow", v) do(args: Variant):
        let sod = args.get(SpecialOfferData)
        let offerWindow = sharedWindowManager().createWindow(SpecialOfferWindow)
        offerWindow.prepareForBundle(sod)
        offerWindow.source = "map"
        sharedWindowManager().show(offerWindow)


    notif.addObserver("ShowSpecialOfferTimer", v) do(args: Variant):
        let sod = args.get(SpecialOfferData)
        v.gui.gui_pack.getModule(mtSidePanel).SideTimerPanel.addTimer(sod)

    notif.addObserver("CameraAnimation_cameraToQuest", v) do(args: Variant):
        v.dispatchAction(OpenQuestCardAction, args)

    notif.addObserver("CameraAnimation_cameraToQuestReady", v) do(args: Variant):
        v.dispatchAction(OpenQuestCardAction, args)

    notif.addObserver("CameraAnimation_cameraToQuestInprogress", v) do(args: Variant):
        v.dispatchAction(OpenQuestCardAction, args)

    notif.addObserver("QUEST_ACCEPT_START_SLOT", v) do(args: Variant):
        v.dispatchAction(OpenQuestCardAction, args)

    var giftNode: Node
    let feature = findZone("zeppelin").feature.GiftsFeature
    feature.subscribe(v) do():
        if giftNode.isNil:
            let n = v.rootNode.findNode("zepp_Animation_IdleAnimation")
            if n.isNil:
                return
            giftNode = n.findNode("gift_placeholder")
        if not giftNode.isNil:
            giftNode.alpha = float(feature.hasGifts)

proc initInfo*(v: TiledMapView, callback: proc())=
    let server = sharedServer()
    let user = currentUser()

    v.gui.vipLevel = currentUser().vipLevel
    v.gui.name = currentUser().name
    if currentUser().avatar >= 0:
        v.gui.avatar = currentUser().avatar

    if not callback.isNil:
        callback()

    if user.cheatsEnabled:
        server.getCheatsConfig do(j: JsonNode):
            if not j.isNil and j.kind != JNull:
                v.cheatsView = createCheatsView(j, v.frame)
                v.addSubview(v.cheatsView)
                v.cheatsView.showCheats()
                v.createDebugButtons()

    v.initNotificationsHandlers()

    v.soundManager.loadEvents("tiledmap/sounds/map")
    v.soundManager.loadEvents("common/sounds/common")
    v.soundManager.sendEvent("BACKGROUND_MUSIC")
    v.soundManager.sendEvent("MAP_AMBIENT")

proc getTiledMap*(v: TiledMapView): TileMap =
    result = v.tiledMap

method preloadSceneResources*(v:TiledMapView, onComplete: proc() = nil, onProgress: proc(p:float) = nil) =
    proc afterResourcesLoaded() =
        v.initInfo(onComplete)

    procCall v.GameScene.preloadSceneResources(afterResourcesLoaded, onProgress)

method viewOnEnter*(v: TiledMapView)=
    procCall v.GameScene.viewOnEnter()

    currentUser().updateWallet()
    v.checkUpdates()

    v.setTimeout(0.5) do():
        isInSlotAnalytics = false

    v.mapState.restoreMapState(currentUser().questsState)

    v.setTimeout(1.5) do():
        for quest in sharedQuestManager().activeStories():
            v.dispatchAction(OpenQuestBalloonAction, newVariant(quest))

    setGameState("SHOW_BACK_TO_CITY", true)
    setGameState("MAP_SHOWED", true)

    if isFeatureEnabled(Tournaments):
        # Check free tournaments
        if currentUser().tournPoints == 0:
            sharedServer().getTutorialTournament()
        else:
            sharedServer().getTournamentsList(nil)

method viewOnExit*(v: TiledMapView)=
    procCall v.GameScene.viewOnExit()

    quest_icon_component.getTileImage = nil
    quest_icon_component.getLayerImage = nil
    quest_icon_component.getPropertyImage = nil

    let camPos = v.camera.node.position

    sharedPreferences()["tiledCameraPosition"] = json.`%*`({"x": camPos.x, "y": camPos.y, "z": camPos.z})
    syncPreferences()
    sharedLocalizationManager().removeStrings(v.name)
    # v.menuLayer.removeNotifiers()

method onTapDown*(lis: MapScrollListener, e : var Event) =
    let v = lis.mapView
    lis.translationLocal = v.camera.node.position
    if not lis.accelAnim.isNil:
        lis.accelAnim.cancel()

    v.tileDebugViewNode.resetDebugView()
    if not v.idleCameraAnimation.isNil:
        v.idleCameraAnimation.cancel()

method onTapUp*(lis: MapScrollListener, dx, dy : float32, e : var Event) =
    let v = lis.mapView

    var pos = newVector3(e.localPosition.x, e.localPosition.y)
    let ray = v.rayWithScreenCoords((e.localPosition.x, e.localPosition.y))
    var res: Vector3
    if ray.intersectWithPlane(newVector3(0, 0, 1), newVector3(0, 0, 0), res):
        if abs(dx) < 15 and abs(dy) < 15:
            let maplp = v.tiledMap.node.worldToLocal(res)
            if tiledebugEnabled:
                var debugInfo = v.tiledMap.visibleTilesAtPositionDebugInfo(maplp)
                v.tileDebugViewNode.updateDebugView(debugInfo, res)
            let il = v.tiledMap.layerIntersectsAtPositionWithPropertyName(maplp, "target")

            v.menuLayer.closeAllMenuCards()

            for layer in il:
                let target = layer.properties.getOrDefault("target").getStr()
                let zone = findZone(target)
                if not zone.isNil:
                    v.dispatchAction(OpenZoneInfoCardAction, newVariant((zone, maplp)))
                    break

        else:
            let cam = v.camera.node
            var diff = (lis.translationLocalPrev - cam.position)
            if diff.length() < 5.0: return

            let cp = cam.position
            var acc = diff.length()
            diff.normalize()
            diff = diff * -(acc)
            let futP = cam.position + diff * sqrt(diff.length() * 0.5)

            let dur = sqrt(acc) / 10.0

            let a = newAnimation()
            a.loopDuration = dur
            a.numberOfLoops = 1
            a.onAnimate = proc(p: float)=
                let ip = expoEaseOut(p)
                cam.position = v.calcCameraPosition(interpolate(cp, futP, ip))

            lis.accelAnim = a
            v.addAnimation(a)

method onScrollProgress*(lis: MapScrollListener, dx, dy : float32, e : var Event) =
    let v = lis.mapView
    let cam = v.camera.node

    if not v.gui.allowActions or v.disableManualScroll or sharedWindowManager().hasVisibleWindows():
        return

    let viewportSize = v.viewportSize
    let ratioW = v.viewportSize.width / v.bounds.width
    let ratioH = v.viewportSize.height / v.bounds.height
    let futPos = lis.translationLocal + newVector(-dx * ratioW, -dy * ratioH, 0) * cam.scale # map downscaled
    lis.translationLocalPrev = cam.position
    cam.position = v.calcCameraPosition(futPos)

    v.setNeedsDisplay()
    # v.updateMenuLayer()
    v.menuLayer.mapScaleChanged(v.camera.node.scale)

method onScroll*(v: TiledMapView, e: var Event): bool =
    result = procCall v.SceneView.onScroll(e)
    if not result:
        if not v.idleCameraAnimation.isNil:
            v.idleCameraAnimation.cancel()

        if not v.gui.allowActions or v.disableManualScroll or sharedWindowManager().hasVisibleWindows(): return true

        let ratioW: float = e.localPosition.x / v.bounds.width
        let ratioH: float = e.localPosition.y / v.bounds.height
        v.zoomMap(if e.offset.y > 0: 1.04 else: 0.96, skipMinScale = false, ratioW, ratioH)
        result = true

method onKeyDown*(v: TiledMapView, e: var Event): bool =
    result = procCall v.GameSceneWithCheats.onKeyDown(e)
    if currentUser().isCheater():
        if not result and e.modifiers.anyOsModifier():
            result = true
            case e.keyCode:
            of VirtualKey.C:
                let mln = v.rootNode.findNode("menuLayer")
                mln.enabled = not mln.enabled
            else:
                discard

method name*(v: TiledMapView): string =
    result = "TiledMapView"

method assetBundles*(v: TiledMapView): seq[AssetBundleDescriptor] =
    const MAP_RESOURCES = [
        assetBundleDescriptor("tiledmap/anim"),
        assetBundleDescriptor("tiledmap/map"),
        assetBundleDescriptor("tiledmap/tiles"),
        assetBundleDescriptor("tiledmap/gui"),
        assetBundleDescriptor("tiledmap/rocks"),
        assetBundleDescriptor("tiledmap/sounds")
    ]
    return @MAP_RESOURCES

method loadingInfo*(v:TiledMapView): LoadingInfo =
    result = newLoadingInfo("map", "map")

registerClass(TiledMapView)


method initActions*(tmv: TiledMapView) =
    proc zoomToZoneAction(zone: Zone) =
        cleanPendingStates(ZoomMapFlowState)
        let zoomState = newFlowState(ZoomMapFlowState, newVariant(zone))
        pushBack(zoomState)

    let zoomToZone = ZoomToZoneAction.new() do(g: GameScene, data: Variant, onComplete: proc(success: bool)):
        let zone = data.get(Zone)
        zoomToZoneAction(zone)
        onComplete(true)

    tmv.registerAction(zoomToZone)

    let zoomToQuest = ZoomToQuestAction.new() do(g: GameScene, data: Variant, onComplete: proc(success: bool)):
        let quest = data.get(Quest)
        let zone = findZone(quest.config.targetName)
        zoomToZoneAction(zone)
        onComplete(true)
    tmv.registerAction(zoomToQuest)

    let openQuestBalloonAction = OpenQuestBalloonAction.new() do(g: GameScene, data: Variant, onComplete: proc(success: bool)):
        let quest = data.get(Quest)
        let zone = findZone(quest.config.targetName)

        OpenQuestBubbleFlowState.pushMapZoneMenuFlowState(zone, quest, tmv.menuLayer)
    tmv.registerAction(openQuestBalloonAction)

    let openQuestCardAction = OpenQuestCardAction.new() do(g: GameScene, data: Variant, onComplete: proc(success: bool)):
        let quest = data.get(Quest)
        let zone = findZone(quest.config.targetName)

        zoomToZoneAction(zone)

        tmv.menuLayer.closeAllMenuCards()
        OpenQuestCardFlowState.pushMapZoneMenuFlowState(zone, quest, tmv.menuLayer)
    tmv.registerAction(openQuestCardAction)

    let openZoneInfoCardAction = OpenZoneInfoCardAction.new() do(g: GameScene, data: Variant, onComplete: proc(success: bool)):
        var zone: Zone
        if data.ofType(Zone):
            zone = data.get(Zone)
            g.TiledMapView.menuLayer.showCardForZone(zone)
        else:
            let (z, position) = data.get((Zone, Vector3))
            zone = z
            g.TiledMapView.menuLayer.showCardForZone(zone, position) do():
                onComplete(true)

        g.dispatchAction(ZoomToZoneAction, newVariant(zone))
    tmv.registerAction(openZoneInfoCardAction)

    let tryToStartQuest = TryToStartQuestAction.new() do(g: GameScene, data: Variant, onComplete: proc(success: bool)):
        let quest = data.get(Quest)
        let zone = findZone(quest.config.targetName)

        if currentUser().tryWithdraw(quest.config.currency, quest.config.price):
            CloseQuestCardFlowState.pushMapZoneMenuFlowState(zone, quest, tmv.menuLayer)

            sharedQuestManager().acceptQuest(quest.id)

            let user = currentUser()
            let state = $quest.id & BUTTON_GO_QUEST_CLICKED
            if not hasGameState(state, ANALYTICS_TAG):
                sharedAnalytics().quest_paid(quest.config.name, "map", sharedQuestManager().activeQuestsCount(), user.chips, user.parts, user.bucks)
                setGameState(state, true, ANALYTICS_TAG)

            onComplete(true)
        else:
            OpenQuestBubbleFlowState.pushMapZoneMenuFlowState(zone, quest, tmv.menuLayer)
            sharedAnalytics().wnd_not_enough_beams_show(currentUser().parts, currentUser().bucks, quest.config.price, "map")

            case quest.config.currency:
                of Currency.Parts:
                    let win = sharedWindowManager().show(BeamsAlertWindow)
                    win.source = quest.config.name
                of Currency.TournamentPoint:
                    let win = sharedWindowManager().show(TourPointsAlertWindow)
                    win.source = quest.config.name
                else:
                    return

            onComplete(false)
    tmv.registerAction(tryToStartQuest)

    let trySpeedupQuest = TryToSpeedupQuestAction.new() do(g: GameScene, data: Variant, onComplete: proc(success: bool)):
        let quest = data.get(Quest)
        let zone = findZone(quest.config.targetName)

        if quest.speedUpPrice() <= currentUser().bucks:
            CloseQuestCardFlowState.pushMapZoneMenuFlowState(zone, quest, tmv.menuLayer)
            sharedQuestManager().speedUpQuest(quest.id)
            sharedAnalytics().quest_speedup_complete(quest.config.name)
            onComplete(true)
        else:
            OpenQuestBubbleFlowState.pushMapZoneMenuFlowState(zone, quest, tmv.menuLayer)
            showStoreWindow(StoreTabKind.Bucks, "not_enough_bucks_speedup")
            onComplete(false)
    tmv.registerAction(trySpeedupQuest)

    let tryCompleteQuest = TryToCompleteQuestAction.new() do(g: GameScene, data: Variant, onComplete: proc(success: bool)):
        let quest = data.get(Quest)

        sharedAnalytics().quest_complete(quest.config.name, "map")
        sharedQuestManager().completeQuest(quest.id)

        if RATEUS_USER_LEVEL <= currentUser().level:
            g.setTimeout(0.8) do():
                pushBack(RateUsFlowState)

        onComplete(true)
    tmv.registerAction(tryCompleteQuest)

    let tryGetRewards = TryToGetRewardsQuestAction.new() do(g: GameScene, data: Variant, onComplete: proc(success: bool)):
        let quest = data.get(Quest)
        let zone = findZone(quest.config.targetName)

        g.soundManager.sendEvent("COLLECT_REWARDS_FIRST_TIME")
        sharedAnalytics().quest_get_reward(quest.config.name, "map")

        let state = newFlowState(GiveQuestRewardFlowState, newVariant(quest.id))
        pushFront(state)

        onComplete(true)

        CloseQuestBubbleFlowState.pushMapZoneMenuFlowState(zone, quest, tmv.menuLayer)
    tmv.registerAction(tryGetRewards)

    let openQuestsWindowWithZone = OpenQuestsWindowWithZone.new() do(g: GameScene, data: Variant, onComplete: proc(success: bool)):
        let zone = data.get(Zone)

        let qw = sharedWindowManager().show(QuestWindow)
        qw.fromSource = 2

        onComplete(true)
    tmv.registerAction(openQuestsWindowWithZone)

    let openFeatureWindowWithZone = OpenFeatureWindowWithZone.new() do(g: GameScene, data: Variant, onComplete: proc(success: bool)):
        let zone = data.get(Zone)
        zone.openFeatureWindow()
        onComplete(true)
    tmv.registerAction(openFeatureWindowWithZone)

    let playSlotWithZone = PlaySlotWithZone.new() do(g: GameScene, data: Variant, onComplete: proc(success: bool)):
        let zone = data.get(Zone)
        g.notificationCenter.postNotification("MapPlaySlotClicked", newVariant(parseEnum[BuildingId](zone.name)))
        onComplete(true)
    tmv.registerAction(playSlotWithZone)

    let collectResources = CollectResourcesAction.new() do(g: GameScene, data: Variant, onComplete: proc(success: bool)):
        let currency = data.get(Currency)
        currency.collectResources()
    tmv.registerAction(collectResources)

    let updateQuests = UpdateQuestsAction.new() do(g: GameScene, data: Variant, onComplete: proc(success: bool)):
        g.TiledMapView.checkUpdates()
        onComplete(true)
    tmv.registerAction(updateQuests)
