import json
import strutils

import falconserver.common.currency

import nimx.view
import nimx.view_event_handling
import nimx.matrixes
import nimx.button
import nimx.notification_center
import nimx.animation
import nimx.window
import nimx.app
import nimx.timer

import rod.component.camera
import rod.viewport
import rod.rod_types
import rod.node

import rod.component
import rod.component.text_component

import shared.gui.gui_module_types
import shared.gui.gui_pack
import shared.gui.money_panel_module
import shared.gui.player_info_module
import shared.gui.map_buttons_module
import shared.gui.menu_button_module
import shared.gui.boosters_side_panel

import windows / store / store_window
import shared.window.window_manager
import shared.window.out_of_money_window
import shared.window.profile_window
import shared.window.tasks_window
import shared.window.button_component
import shared.window.beams_alert_window
import shared.tutorial
import shared.localization_manager

import shared / gui / features / map / [map_button_quests, map_button_collect, map_button_tournaments, map_bottom_menu]

import quest.quests

import shared.message_box
import core.net.server
import shared.user
import shared.shared_gui
import shared.game_scene

import utils.sound_manager
import utils.game_state
import utils.helpers
import rod.ray

import falconserver.auth.profile_types
import strutils
import nimx.image
import utils.falcon_analytics
import facebook_sdk.facebook_sdk
import platformspecific.webview_manager
import core / zone
import core / flow / flow_state_types
import windows / out_of_currency / out_of_currency

type EnterBuildingStore* {.pure.} = enum
    Button,
    BuildingStore,
    MapSpot

type MapGUI* = ref object of RootObj
    gui_pack*: GUIPack
    rootNode*: Node

proc `chips=`*(mg: MapGUI, chips: int64)
proc `bucks=`*(mg: MapGUI, bucks: int64)
proc `parts=`*(mg: MapGUI, parts: int64)
proc `avatar=`*(mg: MapGUI, val: int)
proc `name=`*(mg: MapGUI, val: string)

proc `allowActions`*(mg: MapGUI): bool =
    result = mg.gui_pack.allowActions

proc `allowActions=`*(mg: MapGUI, state: bool) =
    mg.gui_pack.allowActions = state

proc createMapGUI*(parent: Node): MapGUI=
    let rootNode = parent.newChild("GUI")
    rootNode.positionZ = -3000
    rootNode.positionX = -VIEWPORT_SIZE.width * 0.5
    rootNode.positionY = -VIEWPORT_SIZE.height * 0.5

    let gui_pack = createGUIPack(rootNode)

    let fade = newNodeWithResource("common/gui/ui2_0/lower_black_bg")
    fade.position = newVector3(-960.0, 816.0, 0.0)
    rootNode.addChild(fade)

    let pi = gui_pack.addModule(mtPlayerInfo).GPlayerInfo
    let mp = gui_pack.addModule(mtMoneyPanel).GMoneyPanel
    # if mainApplication().keyWindow().fullscreenAvailable:
    #     let fb = gui_pack.addModule(mtFullscreenButton, newVector3(1600,0,0))
    let pb = gui_pack.addModule(mtPlayButton).GPlayButton
    let stp = gui_pack.addModule(mtSidePanel)
    let bp = gui_pack.addModule(mtBoostersPanel).BoostersSidePanel
    let mb = gui_pack.addModule(mtMenuButton).GMenuButton
    when not defined(android) and not defined(ios):
        mb.setButtons(mbSettings, mbSupport, mbFullscreen)
    else:
        mb.setButtons(mbSettings, mbSupport)

    # discard gui_pack.addModule(mtCollectButton)
    discard gui_pack.addModule(mtTournamentsButton)
    discard gui_pack.addModule(mtMapBottomMenu)

    result = new(MapGUI)
    result.gui_pack = gui_pack
    result.rootNode = rootNode

    let g = result

    pi.infoButton.onAction do():
        discard sharedWindowManager().show(ProfileWindow)
        gui_pack.playClickSound()

    # Money exchange
    mp.chips = currentUser().chips
    mp.bucks = currentUser().bucks
    mp.parts = currentUser().parts

    var notif = rootNode.sceneView.GameScene.notificationCenter

    bp.onClickAnywhere = proc() =
        gui_pack.playClickSound()
        showStoreWindow(StoreTabKind.Boosters, "left_panel")

    mp.buttonChips.onAction do():
        gui_pack.playClickSound()
        showStoreWindow(StoreTabKind.Chips, "user_from_map")

    mp.buttonBucks.onAction do():
        gui_pack.playClickSound()
        showStoreWindow(StoreTabKind.Bucks, "user_from_map")

    mp.buttonEnergy.onAction do():
        gui_pack.playClickSound()
        let enWin = sharedWindowManager().show(BeamsAlertWindow)
        enWin.setTitle(localizedString("WIN_ENERGY_TITLE"))
        sharedAnalytics().wnd_not_enough_beams_show(currentUser().parts, currentUser().bucks, 0, "uppermenu")

    proc onPlayClick() =
        if sharedQuestManager().uncompletedQuests.len > 0:
            let q = sharedQuestManager().uncompletedQuests[0]
            let id = q.id
            let taskID = q.getIDForTask()
        gui_pack.playClickSound()
        let tw = sharedWindowManager().show(TasksWindow)
        tw.setTargetSlot(true)
        notif.postNotification("TASK_WINDOW_ANALYTICS_SOURCE", newVariant("map_button_play"))

    notif.addObserver("MENU_CLICK_BUTTON", g) do(args: Variant):
        gui_pack.playClickSound()
        let bttn = args.get(MenuButton)

        case bttn:
            of mbSettings:
                showSettings(gui_pack)
            of mbPlay:
                onPlayClick()
            of mbSupport:
                openSupportWindow()
            of mbFullscreen:
                rootNode.sceneView.GameScene.setTimeout(0.5) do():
                    mainApplication().keyWindow().fullscreen = not mainApplication().keyWindow().fullscreen
            else:
                discard

    pb.GPlayButton.button.onAction(onPlayClick)

    let qb = gui_pack.addModule(mtQuestsButton).GQuestsButton
    qb.onAction do():
        gui_pack.playClickSound()
        showQuests(gui_pack, 0)

        let mp = gui_pack.getModule(mtMoneyPanel).GMoneyPanel
        let chipsAddNode = mp.rootNode.findNode("chips_add")
        chipsAddNode.alpha = 1.0
        chipsAddNode.uiComponentsState(true)

    notif.addObserver("USER_NAME_UPDATED", g.rootNode.sceneView) do(args: Variant):
        let name = args.get(string)
        g.name = name

    notif.addObserver("USER_AVATAR_UPDATED", g.rootNode.sceneView) do(args: Variant):
        let ava = args.get(int)
        g.avatar = ava

proc removeQuestWindow*(mg: MapGUI)=
    mg.gui_pack.removeModule(mtQuestWindow)

proc outOfCurrency*(outOf: string)=
    showOutOfCurrency(outOf)

proc `chips=`*(mg: MapGUI, chips: int64) =
    mg.gui_pack.getModule(mtMoneyPanel).GMoneyPanel.chips = chips

proc `bucks=`*(mg: MapGUI, bucks: int64) =
    mg.gui_pack.getModule(mtMoneyPanel).GMoneyPanel.bucks = bucks

proc `parts=`*(mg: MapGUI, parts: int64) =
    mg.gui_pack.getModule(mtMoneyPanel).GMoneyPanel.parts = parts

proc `level=`*(mg: MapGUI, val: int) =
    let pi = mg.gui_pack.getModule(mtPlayerInfo).GPlayerInfo
    pi.level = val

proc `experience=`*(mg: MapGUI, val: int) =
    let pi = mg.gui_pack.getModule(mtPlayerInfo).GPlayerInfo
    pi.experience = val

proc `name=`*(mg: MapGUI, val: string) =
    let pi = mg.gui_pack.getModule(mtPlayerInfo).GPlayerInfo
    pi.name = val

proc `vipLevel=`*(mg: MapGUI, val: int) =
    let pi = mg.gui_pack.getModule(mtPlayerInfo).GPlayerInfo
    pi.vipLevel = val

proc `avatar=`*(mg: MapGUI, val: int) =
    let pi = mg.gui_pack.getModule(mtPlayerInfo).GPlayerInfo
    pi.avatar = val

proc safeLayoutModule(gui: MapGUI, moduleType: GUIModuleType, x,y:float, rel:Relation)=
    let gp = gui.gui_pack
    let guiModule = gp.getModule(moduleType)
    if not guiModule.isNil:
        gp.layoutModule(guiModule, x, y, rel)

proc layout*(gui: MapGUI) =
    if gui.isNil or gui.rootNode.isNil:
        return

    let viewportSize = gui.rootNode.sceneView.GameScene.viewportSize

    gui.safeLayoutModule(mtPlayerInfo, 24.0, 0.0, Relation.TopLeft)
    gui.safeLayoutModule(mtMoneyPanel, 560.0, 12.0, Relation.TopLeft)
    gui.safeLayoutModule(mtMenuButton, -160.0, 7.0, Relation.TopRight)
    gui.safeLayoutModule(mtQuestsButton, 212, 862 - viewportSize.height, Relation.BottomLeft)
    gui.safeLayoutModule(mtMapBottomMenu, 8, 871 - viewportSize.height, Relation.BottomLeft)
    # gui.safeLayoutModule(mtCollectButton, 248, 756 - viewportSize.height, Relation.BottomLeft)
    gui.safeLayoutModule(mtTournamentsButton, 1464 - viewportSize.width, 846 - viewportSize.height, Relation.BottomRight)
    gui.safeLayoutModule(mtPlayButton, 1688 - viewportSize.width, 856 - viewportSize.height, Relation.BottomRight)
    gui.safeLayoutModule(mtSidePanel, -333, -300, Relation.MiddleRight)
    gui.safeLayoutModule(mtBoostersPanel, 0, -300, Relation.MiddleLeft)

