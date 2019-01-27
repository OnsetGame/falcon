
import rod / [node, component]
import rod / component / [ae_composition, text_component]
import nimx.animation
import node_proxy.proxy
import utils.helpers
import core.components.bitmap_text

import shared.win_popup
export win_popup

type EventMessageConfig* = tuple
    compPath: string
    parent: Node
    amount: int64
    onInit: proc()
    onCountup: proc(p: float)
    cb: proc()
    particleConf: seq[tuple[pattern: string, path: string]]

nodeProxy EventMessage:
    aeComp AEComposition {onNode: node}
    playAnim* Animation {withValue: np.aeComp.compositionNamed("play")}:
        cancelBehavior = cbJumpToEnd

nodeProxy EventMessageCountup of EventMessage:
    hideAnim* Animation {withValue: np.aeComp.compositionNamed("hide")}
    idleAnim* Animation {withValue: np.aeComp.compositionNamed("idle")}

    counterNode Node {withName: "counter"}
    counter* BmFont {onNodeAdd: counterNode}

type EventWinPopup* = ref object of WinDialogWindow
    proxy*: EventMessage

type EventCountupWinPopup* = ref object of EventWinPopup

proc play(ev: EventWinPopup)=


    if ev.proxy of EventMessageCountup:
        let r = ev.proxy.playAnim
        let i = ev.proxy.EventMessageCountup.idleAnim

        ev.node.addAnimation(r)

        r.onComplete do():
            if not i.isNil:
                i.numberOfLoops = -1
                ev.node.addAnimation(i)

            ev.readyForClose = true
    else:
        let r = ev.proxy.playAnim
        ev.node.addAnimation(r)
        r.onComplete do():
            ev.destroy()

method destroy*(emc: EventWinPopup)=
    if emc.destroyed:
        return
    emc.destroyed = true

    emc.node.removeFromParent()
    if not emc.onDestroy.isNil:
        emc.onDestroy()

method destroy*(emc: EventCountupWinPopup)=
    if not emc.readyForClose:
        emc.proxy.playAnim.cancel()
        return

    if emc.destroyed:
        return
    if not emc.proxy.EventMessageCountup.idleAnim.isNil:
        emc.proxy.EventMessageCountup.idleAnim.cancel()
    emc.destroyed = true
    let hide = emc.proxy.EventMessageCountup.hideAnim
    emc.node.addAnimation(hide)
    hide.onComplete do():
        if not emc.onDestroy.isNil:
            emc.onDestroy()
        emc.node.removeFromParent()

method init(e: EventWinPopup, c: EventMessageConfig) =
    for conf in c.particleConf:
        var nodes = e.node.findNodesContains(conf.pattern, false)
        if nodes.len > 0:
            for n in nodes:
                n.addChild(newNodeWithResource(conf.path))

method init*(e: EventCountupWinPopup, c: EventMessageConfig) =
    procCall e.EventWinPopup.init(c)

    let proxy = e.proxy.EventMessageCountup

    if c.onCountup.isNil:
        let xoff = abs(proxy.counterNode.children[0].positionX - proxy.counterNode.children[1].positionX)
        proxy.counter.setup(xoff, "9876543210", proxy.counterNode.children[0].children)
        proxy.counter.halignment = haCenter
        proxy.counterNode.removeAllChildren()

        proxy.playAnim.chainOnAnimate do(p: float):
            proxy.counter.text = $(interpolate(0'i64, c.amount, expoEaseOut(p)))
    else:
        proxy.playAnim.chainOnAnimate do(p: float):
            c.onCountup(p)

proc playEventMessage*(conf: EventMessageConfig): EventWinPopup=
    if conf.amount > 0:
        result = new(EventCountupWinPopup)
        result.proxy = new(EventMessageCountup, newLocalizedNodeWithResource(conf.compPath))
    else:
        result = new(EventWinPopup)
        result.proxy = new(EventMessage, newLocalizedNodeWithResource(conf.compPath))

    result.node = result.proxy.node
    result.onDestroy = conf.cb

    result.init(conf)

    conf.parent.addChild(result.proxy.node)

    if not conf.onInit.isNil:
        conf.onInit()

    result.play()
