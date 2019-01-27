import node_proxy.proxy
import nimx / [ animation, types ]
import utils / [ helpers, sound_manager ]
import rod / [ node, component ]
import rod / component / [ ae_composition ]
import shared.game_scene

nodeProxy StageIntro:
    bonusHolder Node {withName:"bonus_game_intro"}
    
    fiveInArow Node {withName:"five_in_a_row"}
    
    freeSpin Node {withName:"free_spin_intro"}

    aeComp AEComposition {onNode: node}
    playAnim* Animation 

proc createFreespinIntro*(): StageIntro=
    result = new(StageIntro, newLocalizedNodeWithResource("slots/candy2_slot/win_present/precomps/simple_presentation"))
    result.fiveInArow.enabled = false
    result.bonusHolder.enabled = false
    result.playAnim = result.aeComp.compositionNamed("aeAllCompositionAnimation",
             @["bonus_game_intro", "five_in_a_row"])

proc createBonusIntro*(): StageIntro=
    result = new(StageIntro, newLocalizedNodeWithResource("slots/candy2_slot/win_present/precomps/simple_presentation"))
    result.fiveInArow.enabled = false
    result.freeSpin.enabled = false
    result.playAnim = result.aeComp.compositionNamed("aeAllCompositionAnimation",
             @["free_spin_intro", "five_in_a_row"])

proc createFiveInARow*(): StageIntro=
    result = new(StageIntro, newLocalizedNodeWithResource("slots/candy2_slot/win_present/precomps/simple_presentation"))
    result.freeSpin.enabled = false
    result.bonusHolder.enabled = false
    result.playAnim = result.aeComp.compositionNamed("aeAllCompositionAnimation",
             @["bonus_game_intro", "free_spin_intro"])


