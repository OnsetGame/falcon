import nimx.animation

import rod.node
import rod.component.ae_composition

import utils.helpers
import card_types

proc setupDefault(e: Node) =
    e.findNode("sun_spin_start").alpha = 1.0
    e.findNode("sun_spin").alpha = 1.0
    e.findNode("sun_spin_end").alpha = 1.0
    e.findNode("sun_win").alpha = 1.0
    e.findNode("multiplyer_spin_X").alpha = 1.0

proc setupX2(e: Node) =
    e.findNode("multiplyer_win_0").alpha = 1.0
    e.findNode("multiplyer_stop_0").alpha = 1.0
    e.findNode("multiplyer_0_idle").alpha = 1.0

proc setupX5(e: Node) =
    e.findNode("multiplyer_win_1").alpha = 1.0
    e.findNode("multiplyer_stop_1").alpha = 1.0
    e.findNode("multiplyer_1_idle").alpha = 1.0

proc setupX10(e: Node) =
    e.findNode("multiplyer_win_2").alpha = 1.0
    e.findNode("multiplyer_stop_2").alpha = 1.0
    e.findNode("multiplyer_2_idle").alpha = 1.0

proc setupBonus(e: Node) =
    e.findNode("multiplyer_win_3").alpha = 1.0
    e.findNode("multiplyer_stop_3").alpha = 1.0
    e.findNode("multiplyer_3_idle").alpha = 1.0

proc hideAll*(e: Node) =
    e.findNode("sun_spin_start").alpha = 0.0
    e.findNode("sun_spin").alpha = 0.0
    e.findNode("sun_spin_end").alpha = 0.0
    e.findNode("sun_win").alpha = 0.0
    e.findNode("multiplyer_spin_X").alpha = 0.0
    e.findNode("multiplyer_win_0").alpha = 0.0
    e.findNode("multiplyer_stop_0").alpha = 0.0
    e.findNode("multiplyer_0_idle").alpha = 0.0
    e.findNode("multiplyer_win_1").alpha = 0.0
    e.findNode("multiplyer_stop_1").alpha = 0.0
    e.findNode("multiplyer_1_idle").alpha = 0.0
    e.findNode("multiplyer_win_2").alpha = 0.0
    e.findNode("multiplyer_stop_2").alpha = 0.0
    e.findNode("multiplyer_2_idle").alpha = 0.0
    e.findNode("multiplyer_win_3").alpha = 0.0
    e.findNode("multiplyer_stop_3").alpha = 0.0
    e.findNode("multiplyer_3_idle").alpha = 0.0

proc setupWinAnimation(e: Node, winType: Sun): Animation =
    let aeComp = e.component(AEComposition)
    let win = aeComp.compositionNamed("win")
    let idle = aeComp.compositionNamed("idle")
    idle.numberOfLoops = -1
    var animations = newSeq[Animation]()

    case winType:
    of Sun.X2:
        e.setupX2()
    of Sun.X5:
        e.setupX5()
    of Sun.X10:
        e.setupX10()
    of Sun.Bonus:
        e.setupBonus()
    else:
        discard    
    
    if winType != Sun.Bonus:
        for k in ["spin_start", "spin", "spin_end"]:
            animations.add(aeComp.compositionNamed(k))

    animations.add(win)
        
    var anim = newCompositAnimation(false, animations)
    anim.numberOfLoops = 1
    anim.onComplete do():
        e.addAnimation(idle)
    e.addAnimation(anim)
    result = anim

proc playSunMultAnimation*(e: Node, winType: Sun): Animation =
    e.setupDefault()
    result = e.setupWinAnimation(winType)
