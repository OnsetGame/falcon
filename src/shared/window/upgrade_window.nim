import rod.rod_types
import rod.node
import rod.viewport
import rod.component
import rod.component.text_component
import rod.component.ui_component
import rod.component.ae_composition

import nimx.matrixes
import nimx.property_visitor
import core / notification_center

import utils / [ helpers, game_state, falcon_analytics ]
import shared.localization_manager
import shared.window.window_component
import shared.window.button_component
import shared.game_scene
import shared.director
import quest.quests
import core / flow / [flow, flow_state_types]
import narrative.narrative_character


type UpgradeWindow* = ref object of WindowComponent
    window: Node
    onContinue*: proc()
    onUpgrade*: proc()
    character: NarrativeCharacter


method onInit*(w: UpgradeWindow) =
    let win = newLocalizedNodeWithResource("common/gui/popups/precomps/upgrade_window.json")
    w.window = win
    w.canMissClick = false
    w.anchorNode.addChild(win)

    let txtDesc = win.findNode("text_desc").getComponent(Text)
    txtDesc.text = localizedString("WUC_DESC")

    let title = win.findNode("upgrade_city_tab").findNode("title").getComponent(Text)
    title.text = localizedString("WUC_TITLE")

    let bttnContinue = win.findNode("bttn_upgrade").getComponent(ButtonComponent) # now it's continue button %)
    bttnContinue.title = localizedString("WUC_CONTINUE")
    bttnContinue.onAction do():
        if not w.onContinue.isNil:
            w.onContinue()
        currentNotificationCenter().postNotification("TASK_WINDOW_ANALYTICS_SOURCE", newVariant("wnd_upgrade_city"))
        w.closeButtonClick()

    let bttnUpgrade = win.findNode("bttn_continue").getComponent(ButtonComponent)  # now it's upgrade button %)
    bttnUpgrade.title = localizedString("WUC_UPGRADE")
    bttnUpgrade.onAction do():
        if not w.onUpgrade.isNil:
            w.onUpgrade()
        bttnUpgrade.enabled = false
        currentNotificationCenter().postNotification("SET_EXIT_FROM_SLOT_REASON", newVariant("wnd_upgrade_city"))
        directorMoveToMap()
    let slotState = findActiveState(SlotFlowState).SlotFlowState
    if not slotState.isNil:
        sharedAnalytics().wnd_upgrade_city(sharedQuestManager().totalStageLevel(), slotState.target, sharedQuestManager().slotStageLevel(slotState.target))

    w.character = w.window.addComponent(NarrativeCharacter)
    w.character.kind = NarrativeCharacterType.WillFerris
    w.character.bodyNumber = 1
    w.character.headNumber = 2
    w.character.shiftPos(-130)

    setGameState("SHOW_BACK_TO_CITY", true)


method onMissClick*(w: UpgradeWindow) =
    if not w.onContinue.isNil:
        w.onContinue()
    currentNotificationCenter().postNotification("TASK_WINDOW_ANALYTICS_SOURCE", newVariant("wnd_upgrade_city"))

method hideStrategy*(tw: UpgradeWindow): float =
    tw.character.hide(0.3)
    tw.node.hide(0.5)
    let showWinAnimCompos = tw.window.getComponent(AEComposition)
    showWinAnimCompos.play("hide")

    return 1.0

method showStrategy*(w: UpgradeWindow) =
    w.node.alpha = 1.0
    let showWinAnimCompos = w.window.getComponent(AEComposition)
    showWinAnimCompos.play("show")
    w.character.show(0.0)

registerComponent(UpgradeWindow, "windows")
