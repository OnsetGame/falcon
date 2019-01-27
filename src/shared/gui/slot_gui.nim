import rod.node
import rod.viewport

import nimx.matrixes
import nimx.button
import nimx.window
import nimx.app
import nimx.timer

import quest.quests

import gui_pack
import gui_module_types
import spin_button_module, total_bet_panel_module, win_panel_module, paytable_open_button_module, fullscreen_button_module, menu_button_module, shared.user,
    money_panel_module, autospins_switcher_module, slot_progress_modules.slot_progress_module, player_info_module, map_buttons_module, shared.shared_gui, side_timer_panel

import shared / gui / features / slot / slot_bottom_menu
import core / flow / [ flow, flow_state_types ]

import rod / component / sprite
import nimx.notification_center
import shared.window.window_manager
import shared.window.profile_window
import windows / store / store_window
import shared.window.tasks_window
import shared.tutorial
import shared.tutorial_highlight
import shared.game_scene
import shared.window.button_component
export gui_pack, money_panel_module
import falconserver.tutorial.tutorial_types
import shared.tutorial
import platformspecific.webview_manager
import utils / [ timesync ]
import windows / out_of_currency / out_of_currency

type SlotGUI* = ref object of GUIPack
    spinButtonModule*: SpinButtonModule
    totalBetPanelModule*: TotalBetPanelModule
    winPanelModule*: WinPanelModule
    collectButton*: GSlotBottomMenu
    moneyPanelModule*: GMoneyPanel
    autospinsSwitcherModule*: AutospinsSwitcherModule
    progressPanel*: SlotProgressPanelModule
    playerInfo*: GPlayerInfo
    menuButton*: GMenuButton
    sideTimePanel*: SideTimerPanel


proc createSlotGUI*(rootNode: Node, scene: GameScene): SlotGUI =
    let guiParent = newNode("gui_parent")
    rootNode.addChild(guiParent)

    result.new()
    result.rootNode = guiParent
    result.initGui()

    let fade = newNodeWithResource("common/gui/ui2_0/lower_black_bg")
    fade.position = newVector3(-960.0, 836.0, 0.0)
    guiParent.addChild(fade)

    result.autospinsSwitcherModule = result.addModule(mtAutospinsSwitcher).AutospinsSwitcherModule
    result.spinButtonModule = result.addModule(mtSpinButton).SpinButtonModule
    result.winPanelModule = result.addModule(mtWinPanel).WinPanelModule
    result.totalBetPanelModule = result.addModule(mtTotalBetPanel).TotalBetPanelModule
    result.moneyPanelModule = result.addModule(mtMoneyPanel).GMoneyPanel
    result.playerInfo = result.addModule(mtPlayerInfo).GPlayerInfo
    result.menuButton = result.addModule(mtMenuButton).GMenuButton
    result.sideTimePanel = result.addModule(mtSidePanel).SideTimerPanel
    result.collectButton = result.addModule(mtSlotBottomMenu).GSlotBottomMenu

    if currentUser().avatar >= 0:
        result.playerInfo.avatar = currentUser().avatar

    let notif = scene.notificationCenter
    let r = result
    r.playerInfo.infoButton.onAction do():
        r.playClickSound()
        discard sharedWindowManager().show(ProfileWindow)

    r.moneyPanelModule.buttonChips.onAction do():
        r.playClickSound()
        notif.postNotification("NEED_SHOW_CHIPS_STORE")

    r.moneyPanelModule.buttonBucks.onAction do():
        r.playClickSound()
        notif.postNotification("NEED_SHOW_BUCKS_STORE")

    notif.addObserver("MENU_CLICK_BUTTON", r) do(args: Variant):
        r.playClickSound()
        let bttn = args.get(MenuButton)

        case bttn:
            of mbSettings:
                showSettings(r)
            of mbPlay:
                let tw = sharedWindowManager().show(TasksWindow)
                tw.setTargetSlot()
            of mbSupport:
                openSupportWindow()
            else:
                discard

    notif.addObserver("USER_NAME_UPDATED", scene) do(args: Variant):
        let name = args.get(string)
        r.playerInfo.name = name

    notif.addObserver("USER_AVATAR_UPDATED", scene) do(args: Variant):
        let ava = args.get(int)
        r.playerInfo.avatar = ava

    result.showOffersTimers()

proc outOfCurrency*(sg: SlotGUI, outOf: string, cb: proc() = nil)=
    if outOf == "chips":
        let st = findActiveState(SlotFlowState).SlotFlowState
        if not st.isNil:
            if not st.tournament.isNil:
                if timeLeft(st.tournament.endDate) < 10*60 and not st.tournament.boosted:
                    setTimeout(1.0) do():
                        showOutOfCurrencyState(outOf, cb)
                    return
            else:
                let tasks = sharedQuestManager().activeTasks()
                if tasks.len > 0:  # and  tasks[0].getProgress() >= 0.8:
                    setTimeout(1.0) do():
                        showOutOfCurrencyState(outOf, cb)
                    return
    showOutOfCurrency(outOf, cb)

proc completeQuestById*(sg: SlotGUI, qid: int)=
    sg.giveRewardsById(qid)

proc enableWindowButtons*(sg: SlotGUI, enable: bool) =
    sg.playerInfo.infoButton.enabled = enable
    sg.moneyPanelModule.buttonEnergy.enabled = enable
    sg.menuButton.setVisible(enable)
    sg.collectButton.setVisible(enable)

proc layoutGUI*(sg: SlotGUI) =
    if sg.isNil or sg.rootNode.isNil:
        return

    let viewportSize = sg.rootNode.sceneView.GameScene.viewportSize

    if not sg.spinButtonModule.isNil:
        sg.layoutModule(sg.spinButtonModule, 1650 - viewportSize.width, 812 - viewportSize.height, Relation.BottomRight)

    if not sg.autospinsSwitcherModule.isNil:
        sg.layoutModule(sg.autospinsSwitcherModule, 1545 - viewportSize.width, 990 - viewportSize.height, Relation.BottomRight)

    if not sg.winPanelModule.isNil:
        sg.layoutModule(sg.winPanelModule, 1240 - viewportSize.width, 972 - viewportSize.height, Relation.BottomRight)

    if not sg.totalBetPanelModule.isNil:
        sg.layoutModule(sg.totalBetPanelModule, 701 - viewportSize.width, 967 - viewportSize.height, Relation.BottomRight)

    if not sg.progressPanel.isNil:
        sg.layoutModule(sg.progressPanel, 115, 813 - viewportSize.height, Relation.BottomLeft)

    if not sg.menuButton.isNil:
        sg.layoutModule(sg.menuButton, -160, 7, Relation.TopRight)

    if not sg.moneyPanelModule.isNil:
        sg.layoutModule(sg.moneyPanelModule, 560, 12, Relation.TopLeft)

    if not sg.playerInfo.isNil:
        sg.layoutModule(sg.playerInfo, 24, 0, Relation.TopLeft)

    let ballonFreeSpins = sg.getModule(mtBalloonFreeSpins)
    if not ballonFreeSpins.isNil:
        sg.layoutModule(ballonFreeSpins, -230, -413, Relation.MiddleRight)

    if not sg.collectButton.isNil:
        sg.layoutModule(sg.collectButton, 8, 871 - viewportSize.height, Relation.BottomLeft)

    if not sg.sideTimePanel.isNil:
        sg.layoutModule(sg.sideTimePanel, -333, -300, Relation.MiddleRight)
