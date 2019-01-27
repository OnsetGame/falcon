import nimx.animation
import rod.node
import rod.component.ae_composition

import core.slot.event_message
import core.components.bitmap_text
import utils.helpers
export event_message

import node_proxy.proxy

const PREFIX = "slots/groovy_slot/event_msg/precomps/"

template getConfig(n: Node, compName: string, cb: proc()): EventMessageConfig =
    var conf: EventMessageConfig
    conf.compPath = PREFIX & compName
    conf.parent = n
    conf.cb = cb
    conf.particleConf = @[]
    conf.particleConf.add((pattern:"particles_win", path: PREFIX & "win_particles_fast_big"))
    conf.particleConf.add((pattern:"particles_small", path: PREFIX & "text_particles"))
    conf.particleConf.add((pattern:"particles_long", path: PREFIX & "text_particles_long"))
    conf.particleConf.add((pattern:"particles_big", path: PREFIX & "text_particles_big"))
    conf.particleConf.add((pattern:"particles_win_huge", path: PREFIX & "win_particles_fast_huge"))
    conf.particleConf.add((pattern:"particles_win_mega", path: PREFIX & "win_particles_fast_mega"))
    conf

proc play777Intro*(n: Node, cb: proc()): EventWinPopup =
    var conf = getConfig(n, "777_Free_spins", cb)
    result = playEventMessage(conf)

proc playBarIntro*(n: Node, cb: proc()): EventWinPopup =
    var conf = getConfig(n, "Bar_Free_spins", cb)
    result = playEventMessage(conf)

proc play5IARow*(n: Node, cb: proc()): EventWinPopup=
    var conf = getConfig(n, "5_of_a_kind", cb)
    result = playEventMessage(conf)

proc play777Result*(n: Node, amount: int64, cb: proc()): EventWinPopup=
    var conf = getConfig(n, "777_result", cb)
    conf.amount = amount
    result = playEventMessage(conf)

proc playBARResult*(n: Node, amount: int64, cb: proc()): EventWinPopup=
    var conf = getConfig(n, "bar_game_result", cb)
    conf.amount = amount
    result = playEventMessage(conf)

proc playBigWin*(n: Node, amount: int64, cb: proc()): EventWinPopup=
    var conf = getConfig(n, "big_win", cb)
    conf.amount = amount
    result = playEventMessage(conf)

proc playHugeWin*(n: Node, amount: int64, cb: proc()): EventWinPopup=
    var conf = getConfig(n, "huge_win", cb)
    conf.amount = amount
    result = playEventMessage(conf)

proc playMegaWin*(n: Node, amount: int64, cb: proc()): EventWinPopup=
    var conf = getConfig(n, "mega_win", cb)
    conf.amount = amount
    result = playEventMessage(conf)

nodeProxy WinLineNumbers:
    aeComp AEComposition {onNode: node}
    playAnim Animation {withValue: np.aeComp.compositionNamed("aeAllCompositionAnimation")}
    counterNode Node {withName:"counter"}
    numbers BmFont {onNodeAdd: counterNode}

proc showWinLinePayout*(n: Node, amount: int64, cb: proc()): Node {.discardable.}=
    var p = new(WinLineNumbers, newLocalizedNodeWithResource(PREFIX & "Numbers_win"))
    let xoff = abs(p.counterNode.children[0].positionX - p.counterNode.children[1].positionX)
    p.numbers.setup(xoff, "9876543210", p.counterNode.children[0].children)
    p.numbers.text = $amount
    p.numbers.halignment = haCenter
    p.counterNode.removeAllChildren()

    n.addChild(p.node)
    n.addAnimation(p.playAnim)
    p.playAnim.onComplete do():
        p.node.removeFromParent()
        if not cb.isNil:
            cb()

    result = p.node
