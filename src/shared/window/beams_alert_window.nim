import random, strutils, json

import rod / [ rod_types, node , viewport, component ]
import rod / component / [ text_component, ui_component, ae_composition ]

import nimx / [ matrixes, button, property_visitor, animation, formatted_text]
import core / notification_center

import utils / [ helpers, falcon_analytics, sound_manager, icon_component ]

import shared / [ localization_manager, game_scene, user, director, deep_links, tutorial ]
import shared / window / [ window_component, button_component, window_manager, tasks_window ]

import falconserver.map.building.builditem
import quest.quests
import narrative.narrative_character


type
    BeamsAlertWindow* = ref object of WindowComponent
        window: Node
        initialQuest: Quest
        source*: string
        character: NarrativeCharacter

    TourPointsAlertWindow* = ref object of BeamsAlertWindow


proc setTitle*(w: BeamsAlertWindow, title: string) =
    let tab_title = w.window.findNode("TABS").findNode("title").getComponent(Text)
    tab_title.text = title

method onInit*(tw: BeamsAlertWindow) =
    let win = newLocalizedNodeWithResource("common/gui/popups/precomps/beams_alert_window.json")
    tw.window = win
    tw.anchorNode.addChild(win)

    let textDesc = win.findNode("text_desc").getComponent(Text)
    textDesc.text = localizedString("NOT_ENOUGHT_BEAMS")

    tw.window.findNode("tour_big_icon").alpha = 0.0

    tw.setTitle(localizedString("NOT_ENOUGHT_BEAMS_TITLE"))

    let btnClose = win.findNode("button_close")
    let closeAnim = btnClose.animationNamed("press")
    let buttonClose = btnClose.createButtonComponent(closeAnim, newRect(10.0, 10.0, 80.0, 80.0))
    buttonClose.onAction do():
        tw.closeButtonClick()

    let btnOkNode = win.findNode("orange_button_play_2colors")
    let btnOk = btnOkNode.createButtonComponent(newRect(5,5,300,90))

    btnOkNode.findNode("title").getComponent(Text).text = localizedString("WELCOME_PLAY")
    btnOkNode.findNode("pvp_icon").alpha = 0.0

    btnOk.onAction do():
        let taskWindow = sharedWindowManager().show(TasksWindow)
        taskWindow.setTargetSlot()

        if sharedQuestManager().uncompletedQuests.len() > 0:
            let q = sharedQuestManager().uncompletedQuests[0]
            let id = q.id
            let user = currentUser()

            if tw.source.len() > 0:
                sharedAnalytics().press_go_to_tasks(q.config.name, getCountedEvent($id & "_" & TRY_QUEST_COMPLETE), user.chips, user.parts, user.bucks, "map")
            else:
                sharedAnalytics().press_go_to_tasks(q.config.name, getCountedEvent($id & "_" & TRY_QUEST_COMPLETE), user.chips, user.parts, user.bucks, "uppermenu")
            currentNotificationCenter().postNotification("TASK_WINDOW_ANALYTICS_SOURCE", newVariant("popup_not_enough_beams"))

    tw.character = tw.window.addComponent(NarrativeCharacter)
    tw.character.kind = NarrativeCharacterType.WillFerris
    tw.character.bodyNumber = 5
    tw.character.headNumber = 2
    tw.character.shiftPos(-70)


method hideStrategy*(tw: BeamsAlertWindow): float =
    tw.character.hide(0.3)
    let hideWinAnimCompos = tw.window.getComponent(AEComposition)
    hideWinAnimCompos.play("hide")
    return 0.4

method showStrategy*(tw: BeamsAlertWindow) =
    tw.node.alpha = 1.0
    let showWinAnimCompos = tw.window.getComponent(AEComposition)

    let gs = tw.node.sceneView
    if not gs.isNil and not gs.GameScene.soundManager.isNil:
        gs.GameScene.soundManager.sendEvent("COMMON_EXCHANGEPOPUP_BEAMS")

    showWinAnimCompos.play("show").onComplete do():
        if not tw.window.sceneView.isNil:
            let light = tw.window.findNode("ltp_glow_copy.png")
            light.addRotateAnimation(45)

    if isFrameClosed("TS_NOT_ENOUGH_TP"):
        tw.character.show(0.0)

method beforeRemove*(w: BeamsAlertWindow) =
    if w.source.len() > 0:
        sharedAnalytics().wnd_not_enough_beams_close("map")
    else:
        sharedAnalytics().wnd_not_enough_beams_close("uppermenu")

registerComponent(BeamsAlertWindow, "windows")

method onInit*(tw: TourPointsAlertWindow) =
    procCall tw.BeamsAlertWindow.onInit()

    for n in ["energy_placeholder","placeholder"]:
        var enIco = tw.window.findNode(n).componentIfAvailable(IconComponent)
        if not enIco.isNil:
            enIco.name = "tourPoints"

    let btnOkNode = tw.window.findNode("orange_button_play_2colors")
    btnOkNode.findNode("pvp_icon").alpha = 1.0
    btnOkNode.findNode("play_icon").alpha = 0.0
    let btnOk = btnOkNode.component(ButtonComponent)

    if currentDirector().gameScene().name == "TiledMapView":
        btnOk.onAction do():
            btnOk.enabled = false
            currentNotificationCenter().postNotification("SHOW_TOURNAMENTS_WINDOW")
    else:
        btnOk.title = localizedString("OOM_OK")
        btnOk.onAction do():
            sharedDeepLinkRouter().handle("/scene/TiledMapView/window/TournamentsWindow")

    let textDesc = tw.window.findNode("text_desc").getComponent(Text)
    textDesc.text = localizedString("NOT_ENOUGHT_TOURPOINTS")
    textDesc.boundingSize= newSize(850,0)
    tw.window.findNode("text_desc").position = newVector3(535, 657)

    tw.setTitle(localizedString("NOT_ENOUGHT_TOURPOINTS_TITLE"))

    tw.window.findNode("tour_big_icon").alpha = 1.0
    tw.window.findNode("cards_beams_alert").alpha = 0.0

    tsNotEnoughTp.addTutorialFlowState(true)


registerComponent(TourPointsAlertWindow, "windows")
