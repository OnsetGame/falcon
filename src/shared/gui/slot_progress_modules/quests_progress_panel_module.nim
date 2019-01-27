import rod.node
import rod.component
import rod.component.text_component
import rod.component.ui_component
import rod.component.solid
import rod.component.vector_shape
import rod.component.gradient_fill
import rod.viewport

import nimx.matrixes
import nimx.notification_center
import nimx.button
import nimx.types
import nimx.animation
import nimx.formatted_text
import nimx.font

import utils.sound_manager
import quest.quests
import quest.quest_helpers
import shared.game_scene
import falconserver.quest.quest_types
import falconserver.map.building.builditem
import falconserver.tutorial.tutorial_types

import shared.localization_manager
import shared.window.button_component
import shared.window.window_manager
import shared.window.tasks_window
import shared.tutorial
import math
import strutils
import utils.icon_component
import utils.helpers
import utils.progress_bar
import utils.outline
import core / flow / flow_state_types


import .. / gui_module
import .. / gui_module_types
import .. / map_buttons_module
import slot_progress_module


type QPState {.pure.}  = enum
    Complete,
    NewTask,
    TaskInfo

type QuestsProgressPanelModule* = ref object of SlotProgressPanelModule
    mProg: float
    oldProg: float
    quest: Quest
    state: QPState
    hideButton: bool
    newTaskIdle: Animation
    progbar: ProgressBar
    progText: Text

proc `prog=`*(qppl: QuestsProgressPanelModule, prog: float) =
    qppl.oldProg = qppl.mProg
    qppl.mProg = prog

proc prog*(qppl: QuestsProgressPanelModule) : float =
    result = qppl.mProg

proc setTaskIcon(qppl: QuestsProgressPanelModule)=
    let questname = qppl.rootNode.findNode("task_description")
    let t = questname.component(Text)

    t.lineSpacing = -8
    if qppl.quest.isNil:
        t.text = ""
    else:
        t.text = getTaskPanelTitle(qppl.quest.tasks[0].taskType, qppl.quest.tasks[0].target.BuildingId)
        let icoAnchor = qppl.rootNode.findNode("icons_anchor")
        let tico = getTaskIcon(qppl.quest.tasks[0].taskType, qppl.quest.tasks[0].target.BuildingId)
        discard icoAnchor.addTaskIconComponent(tico)

proc updateQuestProgress*(qppl: QuestsProgressPanelModule)=
    if not qppl.quest.isNil:
        let task = qppl.quest.tasks[0]
        let anim = newAnimation()
        let oldProgress = qppl.progbar.progress
        let newProgress = task.progresses[0].current.float / task.progresses[0].total.float
        let currstr = formatThousands(task.progresses[0].current.int64)
        let progText = qppl.progText

        anim.loopDuration = 0.15
        anim.numberOfLoops = 1
        anim.onAnimate = proc(p: float)=
            qppl.progbar.progress = interpolate(oldProgress, newProgress, p)
        qppl.rootNode.addAnimation(anim)
        if oldProgress < newProgress:
            anim.onComplete do():
                qppl.rootNode.addAnimation(qppl.rootNode.findNode("progress_bar").animationNamed("highlight"))
                let progPart = qppl.rootNode.findNode("progress_particle")
                let shapeWidth = qppl.rootNode.findNode("progress_shape_02").getComponent(VectorShape).size.width

                progPart.positionX = shapeWidth - 80
                progPart.enabled = true
                qppl.rootNode.addAnimation(progPart.animationNamed("start"))

        progText.text = currstr & " / " & formatThousands(task.progresses[0].total.int64)
        progText.mText.setTextColorInRange(currstr.len, progText.text.len, newColor(0.8, 0.8, 0.8, 1.0))
        progText.mText.setTextColorInRange(0, currstr.len, newColor(1.0, 1.0, 1.0, 1.0))

        var f = newFontWithFace(progText.font.face, progText.font.size * 0.8)
        progText.mText.setFontInRange(currstr.len, progText.text.len, f)
        progText.mText.setFontInRange(0, currstr.len, progText.font)

proc switchPanel(qppl: QuestsProgressPanelModule, state: QPState) =
    var anim: Animation
    qppl.setTaskIcon()

    if qppl.state != state:
        if state == QPState.Complete:
            qppl.updateQuestProgress()
            anim = qppl.rootNode.animationNamed("complete")
            qppl.progbar.progress = 1.0
        elif state == QPState.NewTask:
            qppl.progbar.progress = 0
            anim = qppl.rootNode.animationNamed("get_new_task")
            anim.onComplete do():
                qppl.rootNode.addAnimation(qppl.newTaskIdle)
        else:
            qppl.newTaskIdle.cancel()
            anim = qppl.rootNode.animationNamed("change_to_icon")
        qppl.rootNode.addAnimation(anim)

    qppl.state = state
    #qppl.rootNode.findNode("alert_text_@noloc").component(Text).text = $(sharedQuestManager().stageLevel() + 1)

proc disablePanel*(qppl: QuestsProgressPanelModule) =
    qppl.rootNode.enabled = false
    qppl.rootNode.removeFromParent()

method checkPanel*(r: QuestsProgressPanelModule, force: bool = false) =
    let man = sharedQuestManager()
    let tasks = man.activeTasks()

    if tasks.len > 0:
        r.quest = tasks[0]
        if r.hideButton or force:
            r.switchPanel(QPState.TaskInfo)
            r.hideButton = false

    if not r.quest.isNil and tasks.len > 0:
        r.prog = min(1.0, r.quest.getProgress())
        r.updateQuestProgress()
    else:
        r.hideButton = true

proc createQuestsProgressPanel*(parent: Node): QuestsProgressPanelModule =
    result.new()
    let win = newLocalizedNodeWithResource("common/gui/ui2_0/task_progress_bar.json")
    parent.addChild(win)

    result.rootNode = win
    result.state = QPState.TaskInfo
    result.newTaskIdle = result.rootNode.animationNamed("quest_idle")
    result.progText = result.rootNode.findNode("progress_text").component(Text)
    result.newTaskIdle.numberOfLoops = -1

    #win.findNode("energy").getComponent(IconComponent).hasOutline = true

    let r = result
    let scene = GameScene(win.sceneView)
    let notif = scene.notificationCenter
    let play_bttn_node = result.rootNode.findNode("icon_play.png")
    let anim = result.rootNode.animationNamed("press")
    let play_bttn = play_bttn_node.createButtonComponent(anim, newRect(0.0, 0.0, 140.0, 140.0))

    play_bttn.onAction do():
        let tw = sharedWindowManager().show(TasksWindow)
        notif.postNotification("TASK_WINDOW_ANALYTICS_SOURCE", newVariant("slot_panel_play"))
        scene.addAnimation(r.rootNode.animationNamed("press"))


    notif.addObserver("TASKS_WINDOW_CLOSED", r, proc(v: Variant) =
        if sharedQuestManager().activeQuests().len == 0:
            r.switchPanel(QPState.NewTask)
            echo "TASKS_WINDOW_CLOSED"
    )

    notif.addObserver("TASKS_COMPLETE_EVENT", r, proc(v: Variant) =
        r.switchPanel(QPState.Complete)
    )

    notif.addObserver(QUESTS_UPDATED_EVENT, r, proc(v: Variant)=
        r.checkPanel()
    )

    r.setTaskIcon()

    let pp = r.rootNode.findNode("progress_parent")
    pp.positionX = pp.positionX + 80
    r.progbar = r.rootNode.findNode("progress_parent").addComponent(ProgressBar)
    pp.findNode("progress_shape_02").getComponent(GradientFill).endPoint.y = 15

    let queseq = sharedQuestManager().activeQuests()
    if queseq.len > 0:
        for q in queseq:
            r.quest = q
            r.prog = min(q.getProgress(), 1.0)
        r.setTaskIcon()
    else:
        r.prog = 0
        r.setTaskIcon()
        r.rootNode.enabled = false

    r.updateQuestProgress()

    discard result.rootNode.findNode("icons_size_placeholder").addSignIcons("blue_sign")

    let flash = result.rootNode.findNode("task_energy_particle_00001.png")
    let flashOutline = flash.addComponent(Outline)
    flashOutline.radius = 4.0

    let blueSign = result.rootNode.findNode("blue_sign")
    let outline = blueSign.addComponent(Outline)
    outline.radius = 9.0

    result.rootNode.findNode("task_completed_2").getComponent(Text).lineSpacing = -10
    result.rootNode.findNode("get_new_task").getComponent(Text).lineSpacing = -10

    let aq = sharedQuestManager().activeTasks()
    if aq.len() == 0:
        r.rootNode.enabled = true
        r.switchPanel(QPState.NewTask)

proc onRemoved*(qppl: QuestsProgressPanelModule)=
    let scene = GameScene(qppl.rootNode.sceneView)
    scene.notificationCenter.removeObserver(QUESTS_UPDATED_EVENT, qppl.rootNode.sceneView)
