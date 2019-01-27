import node_proxy / proxy
import nimx / [ types, animation, matrixes ]
import rod / [ rod_types, node ]
import rod / component / [ text_component, vector_shape ]

import falconserver / map / building / builditem

import shared / [ game_scene, localization_manager ]
import core / zone
import core / features / slot_feature
import core / flow / flow
import utils / [ icon_component, progress_bar, helpers ]

import slot_progress_module


nodeProxy FreeRoundsProgressPanelModuleProxy:
    title Text {onNode: "free_rounds_title"}
    icon IconComponent {onNodeAdd: "free_round_placeholder"}:
        hasOutline = true
        composition = "reward_icons"
        name = "freeRounds"
    progressText Text {onNode: "progress_text"}

    progressBar ProgressBar {onNodeAdd: "progress_parent"}
    progressBarShape VectorShape {onNode: "progress_shape_04"}

    progressParticle Node {withName: "progress_particle"}
    
    lastProgress int {withValue: -1}


proc setProgress*(np: FreeRoundsProgressPanelModuleProxy, zone: Zone) =
    let feature = zone.feature.SlotFeature

    if np.lastProgress == feature.passedRounds:
        return
    np.lastProgress = feature.passedRounds

    np.progressText.text = $feature.passedRounds & "/" & $feature.totalRounds
    np.progressBar.progress = feature.passedRounds.float / feature.totalRounds.float
    np.title.text = localizedFormat("FREE_ROUNDS_TITLE", $feature.totalRounds)

    let x = np.progressBarShape.size.width - 30.0
    np.progressParticle.positionX = x
    np.progressParticle.playAnimation("start")


type FreeRoundsProgressPanelModuleFlowState* = ref object of BaseFlowState
    action*: proc()

method appearsOn*(state: FreeRoundsProgressPanelModuleFlowState, current: BaseFlowState): bool = current.name == "SlotFlowState"

method wakeUp*(state: FreeRoundsProgressPanelModuleFlowState) =
    if not state.action.isNil:
        state.action()
    state.pop()


type FreeRoundsProgressPanelModule* = ref object of SlotProgressPanelModule
    proxy*: FreeRoundsProgressPanelModuleProxy


proc createFreeRoundsProgressPanel*(parent: Node): FreeRoundsProgressPanelModule =
    result.new()
    let proxy = FreeRoundsProgressPanelModuleProxy.new(newNodeWithResource("common/gui/ui2_0/free_round_progress_panel"))
    result.proxy = proxy
    result.rootNode = proxy.node

    parent.addChild(result.rootNode)
