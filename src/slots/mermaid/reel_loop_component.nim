import nimx / [types, property_visitor, animation, matrixes]
import rod / [node, component]
import utils.helpers
import algorithm

type MoveType* = enum
    MoveUp
    MoveDown
    MoveRight
    MoveLeft
    Stand

type ReelLoop* = ref object of Component
    worldPosElems*: seq[Vector3]
    horizontal: MoveType
    vertical: MoveType
    anim*: Animation

    elems*: seq[Node]
    rootNode*: Node

    onShift*: proc(n: Node)
    onJump*: proc(n: Node)
    onSync*: proc()
    onUpdate*: proc(p: float)

method init*(rl: ReelLoop) =
    procCall rl.Component.init()

proc getSortedChildren(parent: Node): seq[Node] =
    var cells = newSeq[Node]()
    for ch in parent.children: cells.add(ch)
    cells.sort do (n1, n2: Node) -> int:
        let wpos1 = n1.worldPos()
        let wpos2 = n2.worldPos()
        result = cmp(wpos1.x, wpos2.x) or cmp(wpos1.y, wpos2.y) or cmp(wpos1.z, wpos2.z)
    result = cells

proc initWithParentNode(rl: ReelLoop, parent: Node) =
    if parent.isNil or parent.children.len == 0:
        raiseAssert("wrong parent node")
    else:
        rl.rootNode = parent

    if rl.elems.len == 0:
        rl.elems = parent.getSortedChildren()

    if rl.worldPosElems.len == 0:
        var currWpos, prevWpos: Vector3
        for ch in rl.elems:
            let chWpos = ch.worldPos()
            rl.worldPosElems.add(chWpos)
            prevWpos = currWpos
            currWpos = chWpos
        rl.worldPosElems.add(currWpos*2.0-prevWpos) # additional shift cell

    rl.horizontal = Stand
    rl.vertical = Stand

proc handleReel*(rl: ReelLoop) =
    if rl.rootNode.isNil:
        rl.initWithParentNode(rl.node)

    let firstWpos = rl.worldPosElems[0]
    let lastWpos = rl.worldPosElems[rl.worldPosElems.len-1]
    var prevPos = rl.rootNode.worldPos()

    var doAlign = false

    rl.anim = newAnimation()
    rl.anim.loopDuration = 0.1
    rl.anim.numberOfLoops = -1
    rl.anim.onAnimate = proc(p: float) =
        if not rl.anim.isCancelled():

            let firstElemWpos = rl.rootNode.worldPos()
            if prevPos.x < firstElemWpos.x:
                rl.horizontal = MoveRight
            elif prevPos.x > firstElemWpos.x:
                rl.horizontal = MoveLeft
            else:
                rl.horizontal = Stand

            if prevPos.y < firstElemWpos.y:
                rl.vertical = MoveDown
            elif prevPos.y > firstElemWpos.y:
                rl.vertical = MoveUp
            else:
                rl.vertical = Stand

            prevPos = firstElemWpos

            if rl.horizontal != Stand or rl.vertical != Stand:

                for it, el in rl.elems:
                    let elWpos = el.worldPos
                    var diff: Vector3
                    var lastPosUpd = false
                    var firstPosUpd = false

                    case rl.vertical:
                    of MoveUp:
                        if elWpos.y <= firstWpos.y:
                            diff.y = elWpos.y - firstWpos.y
                            lastPosUpd = true
                    of MoveDown:
                        if elWpos.y >= lastWpos.y:
                            diff.y = elWpos.y - lastWpos.y
                            firstPosUpd = true
                    else: discard

                    case rl.horizontal:
                    of MoveLeft:
                        if elWpos.x <= firstWpos.x:
                            diff.x = elWpos.x - firstWpos.x
                            lastPosUpd = true
                    of MoveRight:
                        if elWpos.x >= lastWpos.x:
                            diff.x = elWpos.x - lastWpos.x
                            firstPosUpd = true
                    else: discard

                    if firstPosUpd or lastPosUpd:

                        if not rl.onJump.isNil:
                            rl.onJump(el)

                        if not rl.anim.isCancelled():

                            if firstPosUpd:
                                el.worldPos = firstWpos + diff

                            if lastPosUpd:
                                el.worldPos = lastWpos + diff

                        # if not rl.onJump.isNil:
                        #     rl.onJump(el)
                    else:
                        if not rl.onShift.isNil:
                            rl.onShift(el)

                    # sync with pos
                    if it == 0 and lastPosUpd:
                        doAlign = true

                    if it == 0 and firstPosUpd:
                        doAlign = true

                if doAlign:
                    if not rl.onSync.isNil:
                        rl.onSync()
                    doAlign = false

            if not rl.anim.isCancelled():
                if not rl.onUpdate.isNil:
                    rl.onUpdate(p)

    rl.node.addAnimation(rl.anim)

method componentNodeWasAddedToSceneView*(rl: ReelLoop) =
    rl.handleReel()

method componentNodeWillBeRemovedFromSceneView*(rl: ReelLoop) =
    rl.anim.cancel()

registerComponent(ReelLoop, "Falcon")
