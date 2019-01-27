import nimx.matrixes
import rod.node
import rod.component
import rod.component.text_component
import rod.component.vector_shape
import shared.game_scene
import utils.helpers
import utils.icon_component
import utils.timesync
import utils.progress_bar
import tournaments.tournament
import falconserver.common.currency
import times


import .. / gui_module
import .. / gui_module_types
import slot_progress_module


type TournamentsProgressPanelModule* = ref object of SlotProgressPanelModule
    progbar: ProgressBar
    tournament: Tournament

proc setCurrency*(tppl: TournamentsProgressPanelModule) =
    let comp = tppl.rootNode.findNode("currency_placeholder").addComponent(IconComponent)
    var curr = Currency.Bucks

    if tppl.tournament.prizeFundBucks <= 0:
        curr = Currency.Chips

    comp.composition = "currency_" & $curr
    comp.name = $curr

proc setPrizePool*(tppl: TournamentsProgressPanelModule,) =
    let pp = tppl.rootNode.findNode("tournament_prize_pool_@noloc").getComponent(Text)
    if tppl.tournament.prizeFundBucks > 0:
        pp.text = $(tppl.tournament.prizeFundBucks)
    else:
        pp.text = $(tppl.tournament.prizeFundChips div 1000) & "K"

proc setTime*(tppl: TournamentsProgressPanelModule) =
    const MINUTE = 60
    const OFFSET = 95

    let timer = tppl.rootNode.findNode("tournament_timer_@noloc").getComponent(Text)
    let left = timeLeft(tppl.tournament.endDate)

    if left > 0:
        let t = left.fromSeconds().getGMTime()
        timer.text = t.format("h:mm:ss")
    else:
        timer.text = ""

    if left > 0 and left < MINUTE:
        tppl.rootNode.addAnimation(tppl.rootNode.findNode("tournament_progress_bar").animationNamed("highlight"))
        let progPart = tppl.rootNode.findNode("progress_particle")
        let shapeWidth = tppl.rootNode.findNode("progress_shape_04").getComponent(VectorShape).size.width

        progPart.positionX = shapeWidth - OFFSET
        progPart.enabled = true
        tppl.rootNode.addAnimation(progPart.animationNamed("start"))

proc setProgress*(tppl: TournamentsProgressPanelModule) =
    let runTimeLeft = if tppl.tournament.endDate < 0: tppl.tournament.duration  else: timeLeft(tppl.tournament.endDate)
    if tppl.tournament.endDate < 0:
        tppl.progbar.progress = 0.0
    else:
        tppl.progbar.progress = 1.0 - runTimeLeft / (tppl.tournament.endDate - tppl.tournament.startDate)

proc createTournamentsProgressPanel*(parent: Node): TournamentsProgressPanelModule =
    result.new()
    let win = newLocalizedNodeWithResource("common/gui/ui2_0/tournament_progress_panel.json")
    parent.addChild(win)
    result.rootNode = win

    discard win.findNode("slot_logos_icons_placeholder").addSlotLogos(win.sceneView.GameScene.sceneID())

    let pp = win.findNode("progress_parent")
    pp.positionX = pp.positionX + 80
    result.progbar = win.findNode("progress_parent").addComponent(ProgressBar)
    result.progbar.progress = 0.0

proc init*(tppl: TournamentsProgressPanelModule, t: Tournament) =
    tppl.tournament = t
    tppl.setCurrency()
    tppl.setPrizePool()
    tppl.setTime()
    tppl.setProgress()

proc createTournamentsProgressPanel*(parent: Node, t: Tournament): TournamentsProgressPanelModule =
    result = createTournamentsProgressPanel(parent)
    result.init(t)

proc update*(tppl: TournamentsProgressPanelModule) =
    if not tppl.tournament.isNil:
        tppl.setPrizePool()
        tppl.setTime()
        tppl.setProgress()

proc disablePanel*(tppl: TournamentsProgressPanelModule) =
    tppl.rootNode.enabled = false
    tppl.rootNode.removeFromParent()



