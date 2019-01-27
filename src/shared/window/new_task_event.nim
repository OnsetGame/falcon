import random
import strutils

import rod.rod_types
import rod.node
import rod.viewport
import rod.component
import rod.component.text_component
import rod.component.ui_component
import rod.component.ae_composition
import rod.component.solid

import nimx.matrixes
import nimx.button
import nimx.property_visitor
import nimx.animation

import core / flow / flow
import utils.helpers
import utils.icon_component
import shared.localization_manager
import shared / window / [ window_component, button_component, window_manager ]
import shared.game_scene
import quest.quests
import quest.quest_helpers
import falconserver.map.building.builditem
import narrative.narrative_character


type NewTaskEvent* = ref object of WindowComponent
    window: Node
    textSlotName: Text
    textValue: Text
    textDesc: Text
    character: NarrativeCharacter


proc setUpQuestData*(tw: NewTaskEvent, q: Quest)
method onInit*(tw: NewTaskEvent) =

    tw.isTapAnywhere = true
    let win = newLocalizedNodeWithResource("common/gui/popups/precomps/new_task_event.json")
    tw.window = win
    tw.anchorNode.addChild(win)

    tw.textSlotName = win.findNode("text_slot").getComponent(Text)
    tw.textValue = win.findNode("text_value").getComponent(Text)
    tw.textDesc = win.findNode("text_desc").getComponent(Text)

    let light = win.findNode("ltp_glow_copy.png")
    light.addRotateAnimation(45)

    let showWinAnimCompos = win.getComponent(AEComposition)
    showWinAnimCompos.play("show")
    win.sceneView.GameScene.setTimeout(3.0) do():
        tw.closeButtonClick()

    tw.character = tw.window.addComponent(NarrativeCharacter)
    tw.character.kind = NarrativeCharacterType.WillFerris
    tw.character.bodyNumber = 5
    tw.character.headNumber = 2
    tw.character.shiftPos(-100)


proc setUpQuestData*(tw: NewTaskEvent, q: Quest) =
    let task = q.tasks[0]
    tw.textSlotName.text = localizedString(getSlotName(task.target.BuildingId))
    tw.textValue.text = genTaskShortDescription(task.taskType, task.target.BuildingId, task.progresses[0].total.int64)

    tw.textValue.boundingSize = newSize(400.0,0.0)
    tw.textValue.node.anchor = newVector3(200.0)
    tw.textValue.verticalAlignment = vaCenter

    tw.textSlotName.boundingSize = newSize(200.0,0.0)
    tw.textSlotName.node.anchor = newVector3(100.0)
    tw.textSlotName.verticalAlignment = vaCenter

    tw.textDesc.text = getFullDescription(q.description)
    tw.textDesc.bounds = newRect(-350.0, -50.0, 900.0, 150.0)

    discard tw.window.findNode("icons_anchor").addTaskIconComponent(getTaskIcon(task.taskType, task.target.BuildingId))

    let icoPlaceholder = tw.window.findNode("slot_select_icons").findNode("placeholder")
    # let icoSolid = icoPlaceholder.getComponent(Solid)
    let icoComp = icoPlaceholder.component(IconComponent)
    icoComp.prefix = "common/lib/icons/precomps"
    icoComp.composition = "slot_logos_icons"
    icoComp.name = $task.target.BuildingId
    icoComp.rect = newRect(newPoint(-43, 20), newSize(320.0, 320.0))
    icoPlaceholder.removeComponent(Solid)
    # showSlotIcon(tw.window.findNode("slot_select_icons"), toUpperAscii($task.target.BuildingId))

method hideStrategy*(tw: NewTaskEvent): float =
    tw.character.hide(0.3)
    let showWinAnimCompos = tw.window.getComponent(AEComposition)
    let anim = showWinAnimCompos.play("show")
    anim.loopPattern = lpEndToStart

    return 0.9


method showStrategy*(tw: NewTaskEvent) =
    tw.node.alpha = 1.0
    tw.character.show(0.0)


registerComponent(NewTaskEvent, "windows")


type NewTaskFlowState* = ref object of BaseFlowState
    quest*: Quest

method appearsOn*(state: NewTaskFlowState, current: BaseFlowState): bool = current.name == "SlotFlowState"

method wakeUp*(state: NewTaskFlowState) =
    let tw = sharedWindowManager().show(NewTaskEvent)
    tw.setUpQuestData(state.quest)
    tw.onClose = proc() = state.pop()