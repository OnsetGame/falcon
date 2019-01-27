import rod / node
import nimx / animation
import sequtils
import utils / helpers

type Highlights* = ref object of RootObj
    root*: Node
    subRoot*: Node

const GENERAL_PREFIX = "slots/card_slot/"

proc cleanUp*(hl: Highlights) =
    while hl.root.children.len != 0:
        closureScope:
            let ii = hl.root.children[0]            
            ii.reattach(hl.subRoot)
            ii.animationNamed("start").cancel()
            ii.animationNamed("idle").cancel()
            let animEnd = ii.animationNamed("end")
            animEnd.loopPattern = lpStartToEnd
            animEnd.onComplete do():
                ii.removeFromParent(true)
            ii.addAnimation(animEnd)

proc attachToNode*(hl: Highlights, parent: Node) =
    parent.addChild(hl.root)
    parent.addChild(hl.subRoot)

proc onHighlightAnim*(hl: Highlights, parent: Node, reelID: int, playForever: bool, name: string) =
    let highlightNode = newNodeWithResource(GENERAL_PREFIX & "specials/precomps/highlight")
    highlightNode.name = name

    hl.root.addChild(highlightNode)
    highlightNode.worldPos = parent.worldPos()
    highlightNode.positionX = highlightNode.positionX - 15
    highlightNode.positionY = highlightNode.positionY + 25

    let animStart = highlightNode.animationNamed("start")
    animStart.loopPattern = lpStartToEnd
    animStart.onComplete do():
        let animIdle = highlightNode.animationNamed("idle")
        animIdle.numberOfLoops = (if playForever == true: -1 else: 1)
        animIdle.loopPattern = lpStartToEnd
        animIdle.onComplete do():
            highlightNode.alpha = 0
        highlightNode.addAnimation(animIdle)
    
    highlightNode.addAnimation(animStart)