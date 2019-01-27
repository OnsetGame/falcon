import json
import strutils
import tables
import times
import logging

import falconserver / common / [ currency, game_balance ]
import falconserver.quest.quest_types
import falconserver.map.building.builditem

import nimx.view
import nimx.view_event_handling
import nimx.matrixes
import nimx.system_logger
import nimx.button
import nimx.image
import core / notification_center
import nimx.animation
import nimx.timer

import rod.viewport
import rod.rod_types
import rod.node

import rod.component
# import rod.component.ui_component
import rod.component.text_component
import rod.component.sprite

import gui.gui_module_types
import gui.gui_pack
import gui.money_panel_module
import gui.player_info_module
import gui.map_buttons_module
import gui.side_timer_panel

import message_box
import core.net.server
import user
import utils.sound_manager
import utils.falcon_analytics
import utils.falcon_analytics_helpers
import utils.timesync
import facebook_sdk.facebook_sdk
import quest / [quests, quests_actions]
import utils.helpers
import utils.game_state
import game_scene
import shared.localization_manager
import quest.quest_helpers
import shared.chips_animation

import shared.tutorial

import shared.director
import shared / window / [ button_component, window_manager, profile_window, select_avatar_window,
        out_of_money_window, exchange_window, sound_settings_window, welcome_window, rewards_window,
        levelup_window, new_quest_window, complete_quest_msg_window, new_task_event, task_complete_event,
        compensation_window, beams_alert_window, upgrade_window, tasks_window, alert_window, window_component, special_offer_window, rate_window]

import windows / store / store_window
import windows / quests / quest_window
import shared / window / [new_feature_window, new_slot_window, maintenance_window]

import tournaments.tournament_info_view
import tournaments.tournament

import shared.gui.new_quest_message_module

import platformspecific.purchase_helper
import platformspecific.android.rate_manager
import core.zone
import core / zone_helper
import core / flow / flow_state_types
import core / helpers / reward_helper

const NEW_FEATURE_TAG = "NewFeaturesShown"

proc showProfile*(gui_pack: GUIPack, callback: proc(ava: int, name: string)){.deprecated.}=
    let prof_win = sharedWindowManager().show(ProfileWindow)


proc showSettings*(gui_pack: GUIPack) {.deprecated.} =
    let ss = sharedWindowManager().show(SoundSettingsWindow)

    ss.onClose = proc() =
        gui_pack.playClickSound()
        gui_pack.allowActions = true

        soundSettings().setOption ssMusicGain, ss.musicGain
        soundSettings().setOption ssSoundGain, ss.soundGain

proc giveRewards*(gui_pack: GUIPack, forQuestID: int, rewards: seq[Reward], kind: RewardWindowBoxKind, onComplete: proc() = nil) =
    let rewWindow = sharedWindowManager().show(RewardWindow)
    rewWindow.boxKind = kind
    rewWindow.rewards = rewards
    rewWindow.forQuestID = forQuestID

    rewWindow.onClose = proc() =
        if not onComplete.isNil:
            onComplete()

proc giveRewardsById*(gui_pack: GUIPack, qid: int, onComplete: proc() = nil) =
    let q = sharedQuestManager().questById(qid)
    let cb = proc() =
        if not q.isNil:
            gui_pack.giveRewards(qid, q.rewards, RewardWindowBoxKind.grey, onComplete)

    sharedQuestManager().getQuestRewards(qid, cb)


proc showQuests*(gui_pack: GUIPack, fromSource:int, z: Zone = nil) {.deprecated.} =
    let qw = sharedWindowManager().show(QuestWindow)
    if qw.isNil:
        return
    qw.fromSource = fromSource


proc showEndQuestMessage*(gui_pack: GUIPack, onCompleteProc: proc()= nil) =
    let message = newNodeWithResource("common/gui/popups/precomps/Alert_comp.json")
    gui_pack.rootNode.addChild(message)

    let anim = message.animationNamed("complete")
    gui_pack.rootNode.addAnimation(anim)

proc featureWindowWasShown(featureForZone:string): bool =
    result = hasGameState(featureForZone,NEW_FEATURE_TAG)

proc saveFeatureWasShown(featureForZone:string) =
    setGameState(featureForZone,"",NEW_FEATURE_TAG)

proc showUpgradeOrNewFeatureWindow*(cb: proc())=
    let zones = getZones()

    var zoneWithNewFeature:Zone = nil
    for z in zones:
        let fKind = z.feature.kind
        let featureForZone = $fKind&z.name

        if z.feature.isFeatureUnlockAvailable():
            var shouldContinue = false
            if z.feature.kind == FeatureType.Slot:
                shouldContinue = hasWindowForSlot(z)
            else:
                shouldContinue = hasWindowForFeature(z)
            if shouldContinue:
                if not featureWindowWasShown(featureForZone) and z.getUnlockPrice() <= currentUser().parts:
                    zoneWithNewFeature = z
                    break

    if zoneWithNewFeature.isNil():
        let uw = sharedWindowManager().show(UpgradeWindow)
        uw.onUpgrade = cb
        uw.onContinue = proc() =
            let tw = sharedWindowManager().show(TasksWindow)
            tw.setTargetSlot()
            tw.onClose = cb
    else:
        saveFeatureWasShown($zoneWithNewFeature.feature.kind&zoneWithNewFeature.name)
        let zoomState = newFlowState(ZoomMapFlowState, newVariant(zoneWithNewFeature))
        pushBack(zoomState)

        if zoneWithNewFeature.feature.kind == FeatureType.Slot:
            let nsw = sharedWindowManager().show(NewSlotWindow)
            nsw.onReady = proc() = nsw.setupSlot(zoneWithNewFeature)
            nsw.onClose = proc() =
                let tw = sharedWindowManager().show(TasksWindow)
                tw.setTargetSlot()
                tw.onClose = cb
            nsw.onUnlock = cb
        else:
            let nfw = sharedWindowManager().show(NewFeatureWindow)
            nfw.onReady = proc() = nfw.setupFeature(zoneWithNewFeature)
            nfw.onClose = proc() =
                let tw = sharedWindowManager().show(TasksWindow)
                tw.setTargetSlot()
                tw.onClose = cb
            nfw.onUnlock = cb

proc tryStartSpecialOffer*(offerBundleID: string, callback: proc()) =
    let ph = getPurchaseHelper()
    if not ph.profileOffers.hasKey(offerBundleID):
        let cbTry = proc() =
            let accepted_offers = ph.profileOffers
            if accepted_offers.hasKey(offerBundleID):
                let sod = ph.profileOffers[offerBundleID]
                let offerWindow = sharedWindowManager().createWindow(SpecialOfferWindow)
                offerWindow.prepareForBundle(sod)
                offerWindow.source = currentDirector().currentScene.name
                offerWindow.onClose = callback
                sharedWindowManager().show(offerWindow)

            else:
                callback()

        ph.tryToStartOffer(offerBundleID, cbTry)
    else:
        callback()

proc tryStartSpecialOfferFromAction*(offerJson: JsonNode, callback: proc()) =
    let ph = getPurchaseHelper()
    let cbTry = proc(bid:string) =
        if bid.len > 0:
            let sod = ph.profileOffers[bid]
            let offerWindow = sharedWindowManager().createWindow(SpecialOfferWindow)
            offerWindow.prepareForBundle(sod)
            offerWindow.source = currentDirector().currentScene.name
            offerWindow.onClose = callback
            sharedWindowManager().show(offerWindow)


        else:
            callback()
    ph.tryToStartOfferFromAction(offerJson,cbTry)

proc showOffersTimers*(gui_pack: GUIPack) =
    const MIN_TIME_TO_SHOW_OFFERS_TIMER = 10.0
    let accepted_offers = getPurchaseHelper().profileOffers
    if accepted_offers.len > 0:
        for bid, sod in pairs(accepted_offers):
            let timeRemaining = sod.expires - serverTime()
            if  timeRemaining > MIN_TIME_TO_SHOW_OFFERS_TIMER:
                gui_pack.getModule(mtSidePanel).SideTimerPanel.addTimer(sod)
