import nimx / [types, property_visitor, animation]

import rod / [node, component]
import rod / component / ae_composition
import rod / tools / serializer

import utils / helpers

import tables, json, strutils, random

const enableEditor = not defined(release)

type AnimationType* = enum
    OnShow
    OnHide
    OnAnticipate
    OnStart
    OnStop
    OnIdle
    OnWin
    OnTopShow
    OnTopHide
    OnBottomShow
    OnBottomHide
    AnimNone
    OnTurnStart
    OnTurnIdle
    OnTurnEnd


type AnimationMarker* = ref object of Component
    animType*: AnimationType
    animName*: string

method serialize*(am: AnimationMarker, s: Serializer): JsonNode =
    result = newJObject()
    result.add("animType", s.getValue(am.animType))
    result.add("animName", s.getValue(am.animName))

method deserialize*(am: AnimationMarker, j: JsonNode, s: Serializer) =
    s.deserializeValue(j, "animType", am.animType)
    s.deserializeValue(j, "animName", am.animName)

method visitProperties*(am: AnimationMarker, p: var PropertyVisitor) =
    p.visitProperty("anim type", am.animType)
    p.visitProperty("anim name", am.animName)

registerComponent(AnimationMarker, "ReelsetComponents")

type MarkerAnimations = array[AnimationType.low .. AnimationType.high, seq[Animation]]

type CellElement = ref object
    node: Node
    anims: MarkerAnimations

proc newCellElement(node: Node, anims: MarkerAnimations): CellElement =
    result.new()
    result.node = node
    result.anims = anims

type CellComponent* = ref object of Component
    elements: Table[int, CellElement]
    idToNodeRelation*: Table[int, string]
    currId*: int
    currentAnims*: seq[Animation]

    cache: Table[string, tuple[parent: Node, child: Node]]
    isVisible*: bool

    when enableEditor:
        pathToRootComp: string

proc hide(n: Node, cc: CellComponent) =
    if not n.parent.isNil:
        let obj = (n.parent, n)
        cc.cache[n.name] = obj
        n.removeFromParent()
    cc.isVisible = false
    n.alpha = 0.0
    n.enabled = false

proc show(n: Node, cc: CellComponent) =
    let obj = cc.cache.getOrDefault(n.name)
    if not obj.parent.isNil and not obj.child.isNil:
        obj.parent.addChild(obj.child)
    cc.isVisible = true
    n.alpha = 1.0
    n.enabled = true

method init*(cc: CellComponent) =
    procCall cc.Component.init()
    cc.elements = initTable[int, CellElement]()
    cc.idToNodeRelation = initTable[int, string]()
    cc.cache = initTable[string, tuple[parent: Node, child: Node]]()
    cc.currId = -1
    cc.currentAnims = @[]

proc findComponents(n: Node): seq[AnimationMarker] =
    var compSeq = newSeq[AnimationMarker]()
    discard n.findNode do(nd: Node) -> bool:
        for v in nd.components:
            if v of AnimationMarker:
                if not v.isNil:
                    compSeq.add(v.AnimationMarker)
    return compSeq

proc composeAnimMarkers(n: Node): MarkerAnimations =
    let animMarkers = n.findComponents()
    for am in animMarkers:
        let id = am.animType
        let name = am.animName
        let aeComp = am.node.component(AEComposition)
        if not aeComp.isNil:
            let anim = aeComp.compositionNamed(name)
            if not anim.isNil:
                result[id].add(anim)
        else:
            let anim = am.node.animationNamed(name)
            if not anim.isNil:
                result[id].add(anim)

proc getAnims*(cc: CellComponent, animType: AnimationType): seq[Animation]

proc show*(cc: CellComponent, id: int)=
    if cc.currId == id: return

    var elem = cc.elements.getOrDefault(cc.currId)
    if not elem.isNil:
        elem.node.hide(cc)

    cc.currId = id
    elem = cc.elements.getOrDefault(cc.currId)

    if elem.isNil:
        let ndName = cc.idToNodeRelation.getOrDefault(cc.currId)
        if ndName.len > 0:
            let elemNode = cc.node.findNode(ndName)
            if not elemNode.isNil:
                let animMarkers = elemNode.composeAnimMarkers()
                cc.elements[cc.currId] = newCellElement(elemNode, animMarkers)
                elem = cc.elements[cc.currId]

    if not elem.isNil:
        elem.node.show(cc)
        let anims = cc.getAnims(OnIdle)
        if anims.len > 0:
            anims[0].onProgress(0.0)

proc hide(elements: Table[int, CellElement], cc: CellComponent) =
    for key, elem in elements:
        if not elem.node.isNil:
            elem.node.hide(cc)

proc resetAnimsOnNode*(cc: CellComponent, elemId: int, parent: Node, animType: AnimationType) =
    let idn = cc.elements.getOrDefault(elemId)
    let node = idn.node
    node.nodeWasAddedToSceneView(parent.mSceneView)
    let anims = idn.anims[animType]

    #animations sequences
    for anms in idn.anims:
        #animations sequence of animType type
        for anim in anms:
            #animation of animType type
            if not anim.isNil:
                anim.cancel()

    if anims.len > 0:
        for a in anims:
            a.loopPattern = lpStartToEnd
            a.cancelBehavior = cbJumpToStart
            a.numberOfLoops = 1
            node.addAnimation(a)
            a.cancel()

proc play(idn: CellElement, cc: CellComponent, animType: AnimationType, loopPattern: LoopPattern = lpStartToEnd,
            cb: proc(anim: Animation), playForever: bool = false, isCancelled: bool = false) =
    let node = idn.node
    let anims = idn.anims[animType]

    #animations sequences
    for anims in idn.anims:
        #animations sequence of animType type
        for anim in anims:
            #animation of animType type
            if not anim.isNil:
                anim.cancel()

    if not node.isNil:
        node.show(cc)
        cc.currentAnims = @[]
        if anims.len > 0:
            var longestAnim = anims[0]
            for a in anims:
                a.loopPattern = loopPattern
                a.cancelBehavior = cbJumpToStart
                if a.loopDuration > longestAnim.loopDuration:
                    longestAnim = a
                if playForever == true:
                    a.numberOfLoops = -1
                node.addAnimation(a)
                cc.currentAnims.add(a)
                if isCancelled == true:
                    a.cancel()
            longestAnim.onComplete do():
                longestAnim.removeHandlers()
                if not cb.isNil: cb(longestAnim)
        else:
            if not cb.isNil: cb(nil)
    else:
        if not cb.isNil: cb(nil)

proc play*(cc: CellComponent, elemId: int, animType: AnimationType, loopPattern: LoopPattern = lpStartToEnd,
            cb: proc(anim: Animation) = nil, playForever: bool = false, isCancelled: bool = false) =
    cc.currId = elemId
    let elem = cc.elements.getOrDefault(elemId)
    if not elem.isNil:
        cc.elements.hide(cc)
        elem.play(cc, animType, loopPattern, cb, playForever, isCancelled)
    else:
        let ndName = cc.idToNodeRelation.getOrDefault(elemId)
        if ndName.len > 0:
            let elemNode = cc.node.findNode(ndName)
            if not elemNode.isNil:
                let animMarkers = elemNode.composeAnimMarkers()
                cc.elements[elemId] = newCellElement(elemNode, animMarkers)
                cc.play(elemId, animType, loopPattern, cb, playForever, isCancelled)
            else:
                if not cb.isNil: cb(nil)
        else:
            echo "FAILED TO SETUP NODE WITH ID ", elemId
            if not cb.isNil: cb(nil)

proc getAnims*(cc: CellComponent, animType: AnimationType): seq[Animation] =
    let elem = cc.elements.getOrDefault(cc.currId)
    if not elem.isNil:
        result = @[]
        let anims = elem.anims[animType]
        for a in anims:
            result.add(a)
    else:
        let ndName = cc.idToNodeRelation.getOrDefault(cc.currId)
        if ndName.len > 0:
            let elemNode = cc.node.findNode(ndName)
            if not elemNode.isNil:
                let animMarkers = elemNode.composeAnimMarkers()
                cc.elements[cc.currId] = newCellElement(elemNode, animMarkers)
                result = cc.getAnims(animType)
        else:
            echo "FAILED TO SETUP NODE WITH ID ", cc.currId

template getRandomAnimType*(cc: CellComponent): AnimationType =
    random(AnimationType.high.int+1).AnimationType

#TODO fill available elems by user
proc getAvailableRandomElem*(cc: CellComponent, withExceptions: seq[int] = @[]): int =
    result = -1
    var s = newSeq[int]()
    var rv: int = 0
    for k, v in cc.idToNodeRelation: s.add(k)
    if s.len > 0:
        for i in 0 .. < 10: #re-random 10 times maximum if all values failed to differ from exceptions, and set result to -1
            rv = random(s.len)
            for j in withExceptions:
                if rv == j:
                    rv = -1
                    break
            if rv != -1:
                result = rv
                return

proc play*(cc: CellComponent, animType: AnimationType, loopPattern: LoopPattern = lpStartToEnd,
            cb: proc(anim: Animation) = nil, playForever: bool = false, withExceptions: seq[int] = @[]) =
    let elemId = if cc.currId != -1: cc.currId else: cc.getAvailableRandomElem(withExceptions)
    cc.play(elemId, animType, loopPattern, cb, playForever)

proc hide*(cc: CellComponent) =
    cc.currId = -1
    cc.elements.hide(cc)

proc debugPlay*(cc: CellComponent, at: AnimationType = AnimNone, eid: int = -1, withExceptions: seq[int] = @[],
                cb: proc(anim: Animation) = nil, playForever: bool = false, isCancelled: bool = false): string =
    let randElem = cc.getAvailableRandomElem(withExceptions)
    if randElem != -1:
        let elemId = if eid == -1: randElem else: eid
        let animType = if at == AnimNone: cc.getRandomAnimType() else: at
        result = cc.idToNodeRelation[elemId] & "\n" & $animType
        cc.play(elemId, animType, lpStartToEnd, cb, playForever, isCancelled)
    else:
        echo  "ZERO ELEMENTS"

proc showAny(cc: CellComponent) =
    var wasVisible = false
    for key, elem in cc.elements:
        if not elem.node.isNil and elem.node.alpha > 0.1:
            wasVisible = true
    if not wasVisible:
        discard cc.debugPlay(OnShow)

proc showRandomElemWithAnim*(cc: CellComponent, animType: AnimationType, withExceptions: seq[int] = @[]) =
    cc.play(cc.getAvailableRandomElem(withExceptions), animType, lpStartToEnd) do(anim: Animation):
        if anim.isNil: cc.showAny()

proc hideElemWithAnim*(cc: CellComponent, animType: AnimationType) =
    if animType == AnimNone or cc.currId == -1:
        cc.hide()
    else:
        cc.play(cc.currId, animType, lpStartToEnd) do(anim: Animation):
            if anim.isNil: cc.hide()

proc playAnim*(cc: CellComponent, animType: AnimationType, loopPattern: LoopPattern = lpStartToEnd, cb: proc() = nil, playForever: bool = false) =
    proc decorCB(anim: Animation) =
        if not cb.isNil:
            cb()

    if animType != AnimNone and cc.currId != -1:
        cc.play(cc.currId, animType, loopPattern, decorCB, playForever)


method deserialize*(cc: CellComponent, j: JsonNode, s: Serializer) =
    var v = j{"idToNodeRelation"}
    if not v.isNil:
        cc.idToNodeRelation = initTable[int, string]()
        for i in 0 ..< v.len:
            cc.idToNodeRelation[($v[i][0]).parseInt()] = v[i][1].getStr()

    v = j{"pathToRootComp"}
    if not v.isNil:
        let pathToRootComp = v.getStr()
        if pathToRootComp.len > 0:

            when enableEditor:
                cc.pathToRootComp = pathToRootComp

            let nd = newNodeWithResource(pathToRootComp)
            while nd.children.len > 0:
                nd.children[0].reattach(cc.node)
            v = j{"animMarkers"}
            if not v.isNil:
                for i in 0 ..< v.len:
                    let jMarker = v[i]
                    let fullpath = jMarker{"path"}
                    var n: Node = cc.node
                    for i in 0..<fullpath.len:
                        n = n.findNode(fullpath[i].getStr())
                    if not n.isNil:
                        let animMarker = n.addComponent(AnimationMarker)
                        animMarker.animType = ($jMarker{"type"}).parseInt().AnimationType
                        animMarker.animName = jMarker{"name"}.getStr()

            for k, v in cc.idToNodeRelation:
                cc.play(k, AnimNone)
            cc.hide()
        else:
            echo "SETUP PATH TO ROOT COMP"

proc checkAndModifyNodeName(n: Node, name: string, nameseq: var seq[string], cache: var Table[seq[string], int]) =
    nameseq.insert(n.name, 0)
    if not cache.hasKey(nameseq):
        cache[nameseq] = 1
    else:
        if not n.parent.isNil and n.parent.name != name:
            checkAndModifyNodeName(n.parent, name, nameseq, cache)

method serialize*(cc: CellComponent, s: Serializer): JsonNode =
    var animMarkersJArray = newJArray()
    var nodeNameCache = initTable[seq[string], int]()
    for key, name in cc.idToNodeRelation:
        let elemNode = cc.node.findNode(name)
        if not elemNode.isNil:
            let animMarkers = elemNode.findComponents()
            for am in animMarkers:
                var nodeNameSeq: seq[string] = @[]
                am.node.checkAndModifyNodeName(cc.node.name, nodeNameSeq, nodeNameCache)

                var animMarker = newJObject()
                var toNodePath = newJArray()
                for name in nodeNameSeq:
                    toNodePath.add(%name)
                animMarker.add("path", toNodePath)
                animMarker.add("type", %(am.animType.int))
                animMarker.add("name", %am.animName)

                animMarkersJArray.add(animMarker)


    var chNodes = newSeq[Node]()
    while cc.node.children.len > 0:
        chNodes.add(cc.node.children[0])
        cc.node.children[0].removeFromParent()

    result = newJObject()
    var elNames = newJArray()
    for key, value in cc.idToNodeRelation:
        var cell = newJArray()
        cell.add(%key)
        cell.add(%value)
        elNames.add(cell)
    result.add("idToNodeRelation", elNames)
    result.add("animMarkers", animMarkersJArray)

    when enableEditor:
        result.add("pathToRootComp", %cc.pathToRootComp)

    cc.node.sceneView.wait(0.5) do():
        for ch in chNodes:
            cc.node.addChild(ch)

when enableEditor:
    import nimx.property_editors.propedit_registry
    import nimx.property_editors.standard_editors
    import nimx.numeric_text_field
    import nimx.view
    import nimx.text_field
    import nimx.linear_layout
    import nimx.button

    import rod / component / text_component

    proc newSeqPropertyViewNew(setter: proc(s: seq[tuple[name: string, index: int]]), getter: proc(): seq[tuple[name: string, index: int]]): PropertyEditorView =
        var val = getter()
        var height = val.len() * (editorRowHeight + 2) + (editorRowHeight + 2) * 2
        let pv = PropertyEditorView.new(newRect(0, 0, 208, height.Coord))
        proc onValChange() =
            setter(val)
        proc onSeqChange() =
            onValChange()
            if not pv.changeInspector.isNil:
                pv.changeInspector()
        const XOffset = 0.Coord
        var x = XOffset
        var y = (editorRowHeight + 2).float32
        for i in 0 ..< val.len:
            closureScope:
                let index = i
                x = XOffset
                let tf = newTextField(newRect(x, y, 150, editorRowHeight))
                tf.font = editorFont()
                pv.addSubview(tf)
                tf.text = $val[index].name
                tf.onAction do():
                    if index < val.len:
                        val[index].name = tf.text
                        onValChange()

                x += 150
                let ntf = newNumericTextField(newRect(x, y, 50, editorRowHeight))
                pv.addSubview(ntf)
                ntf.text = $val[index].index
                ntf.onAction do():
                    if index < val.len:
                        val[index].index = ntf.text.parseFloat().int
                        onValChange()

                y += editorRowHeight + 2

        x = if (val.len == 0): 0.0 else: x
        y = if (val.len == 0): 0.0 else: y
        let addButton = Button.new(newRect(x, y, editorRowHeight, editorRowHeight))
        addButton.title = "+"
        pv.addSubview(addButton)
        addButton.onAction do():
            val.add(("", 0.int))
            onSeqChange()

        result = pv

    registerPropertyEditor(newSeqPropertyViewNew)

    type InfoString = ref object
        val: string

    proc newStringInfoPropertyView(setter: proc(msg: InfoString), getter: proc(): InfoString): PropertyEditorView =
        result = PropertyEditorView.new(newRect(0, 0, 208, editorRowHeight*4))
        let cb = Button.new(newRect(0, 0, editorRowHeight*6, editorRowHeight))
        cb.title = "play random"
        let label = newLabel(newRect(0, editorRowHeight*2, 100, editorRowHeight))
        label.text = getter().val
        cb.onAction do():
            setter(getter())
            label.text = getter().val
        result.addSubview(label)
        result.addSubview(cb)

    registerPropertyEditor(newStringInfoPropertyView)

    method visitProperties*(cc: CellComponent, p: var PropertyVisitor) =
        proc relation(cc: CellComponent): seq[tuple[name: string, index: int]] =
            result = @[]
            for k, v in cc.idToNodeRelation:
                result.add((v, k))

        proc `relation=`(cc: CellComponent, rel: seq[tuple[name: string, index: int]]) =
            cc.idToNodeRelation = initTable[int, string]()
            var maxVal = -100000
            for val in rel:
                if maxVal < val.index: maxVal = val.index
            inc maxVal
            for val in rel:
                if cc.idToNodeRelation.hasKey(val.index):
                    cc.idToNodeRelation[maxVal] = val.name
                    echo "KEY ALREADY EXIST. INC MAX KEY"
                else:
                    cc.idToNodeRelation[val.index] = val.name

        var msg: InfoString
        msg.new()
        msg.val = ""
        proc isPlay(cc: CellComponent): InfoString = msg
        proc `isPlay=`(cc: CellComponent, m: InfoString) =
            msg.val = cc.debugPlay()

        p.visitProperty("elements", cc.relation)
        p.visitProperty("play rand", cc.isPlay)

        proc path(cc: CellComponent): string = cc.pathToRootComp
        proc `path=`(cc: CellComponent, v: string) =
            cc.pathToRootComp = v
            cc.node.removeAllChildren(true)
            cc.elements = initTable[int, CellElement]()
            cc.cache = initTable[string, tuple[parent: Node, child: Node]]()
            try:
                let nd = newNodeWithResource(cc.pathToRootComp)
                if not nd.isNil:
                    while nd.children.len > 0:
                        nd.children[0].reattach(cc.node)
            except:
                echo "wrong path"

        p.visitProperty("path to comp", cc.path)


registerComponent(CellComponent, "ReelsetComponents")
