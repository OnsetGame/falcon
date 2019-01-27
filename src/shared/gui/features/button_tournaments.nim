import tables, sequtils, variant
import button_feature
import quest / quests

import nimx / [types, animation, matrixes, timer]
import core / [notification_center, zone]
import rod / node
import rod / component / text_component
import shared / [localization_manager, game_scene, director, tutorial ]
import shared / gui / [gui_module, gui_module_types]
import core / features / tournaments_feature
import utils / [ timesync, helpers, pause ]


type ButtonTournaments* = ref object of ButtonFeature
    nearestTournament : ControlledTimer
    lastActiveTournament : ControlledTimer
    onUpdate: proc()

method onInit*(bf: ButtonTournaments) =
    bf.composition = "common/gui/ui2_0/tournament_button.json"
    bf.rect = newRect(0, 0, 202.0, 220.0)
    bf.title = localizedString("GUI_TOURNAMENTS_BUTTON")
    bf.zone = "stadium"
    bf.onAction = proc(active: bool) =
        if active:
            bf.playClick()
            currentNotificationCenter().postNotification("SHOW_TOURNAMENTS_WINDOW", newVariant(bf.source))

proc setupFutureEvents(bf: ButtonTournaments) =
    let zone = findZone(bf.zone)
    let feature = zone.feature.TournamentsFeature
    let scene = bf.rootNode.sceneView.GameScene

    if not feature.hasActiveTournament:
        if feature.nearestTournamentStartTime > 0.0:
            if not bf.nearestTournament.isNil:
                bf.nearestTournament.timer.clear()
            bf.nearestTournament = scene.setTimeout(timeLeft(feature.nearestTournamentStartTime), bf.onUpdate)
            echo "set nearestTournamentStartTime ", buildTimerString(timeLeft(feature.nearestTournamentStartTime))

    if feature.lastActiveTournamentEndTime > 0.0:
        if not bf.lastActiveTournament.isNil:
            bf.lastActiveTournament.timer.clear()
        bf.lastActiveTournament = scene.setTimeout(timeLeft(feature.lastActiveTournamentEndTime), bf.onUpdate)
        echo "set lastActiveTournamentEndTime ", buildTimerString(timeLeft(feature.lastActiveTournamentEndTime))

method onCreate*(bf: ButtonTournaments) =
    let zone = findZone(bf.zone)
    let feature = zone.feature.TournamentsFeature
    let scene = bf.rootNode.sceneView.GameScene

    proc update() =
        if not zone.isActive():
            bf.hideHint()
            bf.disable()
            return

        bf.enable()

        if feature.hasActiveTournament:
            bf.hint("!")
        else:
            bf.hideHint()

        bf.setupFutureEvents()

    bf.onUpdate = update
    feature.subscribe(scene, update)
    update()

    # bf.rootNode.addObserver("QUEST_COMPLETED", bf) do(arg: Variant):
    #     update()

method enable*(bf: ButtonTournaments) =
    procCall bf.ButtonFeature.enable()
    #tsTournamentButton.addTutorialFlowState()


template newButtonTournaments*(parent: Node): ButtonTournaments =
    ButtonTournaments.new(parent)
