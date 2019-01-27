import strutils, sequtils, json, tables, logging

import nimx.types
import nimx.timer
import nimx.property_visitor

import rod.node
import rod.rod_types
import rod.viewport
import rod.component
import rod.component.text_component
import rod.tools.serializer

const enableEditor = not defined(release)

when enableEditor:
    import nimx.property_editors.propedit_registry
    import nimx.property_editors.standard_editors
    import nimx.numeric_text_field
    import nimx.view
    import nimx.text_field
    import nimx.linear_layout

type SetterPair* = tuple
    key: string
    val: string

type TextSetter* = ref object of Component
    setters: seq[SetterPair]
    prefix: string

method init*(t: TextSetter) =
    t.prefix = "@noloc"

proc initWithData*(n: Node, data: openarray[SetterPair]) =
    var names = @data

    proc find(a: openarray[SetterPair], k: string): int {.inline.}=
        for i in items(a):
            if i.key == k: return
            inc(result)
        result = -1

    proc trySetup(nd: Node, v: string): bool =
        if not nd.isNil:
            let txt = nd.getComponent(Text)
            if not txt.isNil:
                txt.text = v
                result = true
            else: info "---------- text component isNil for element: ", nd.name, " with val: ", v
        else: info "++++++++++ node isNil for element: ", nd.name, " with val: ", v

    proc forall(node: Node): bool =
        let id = names.find(node.name)
        if id != -1:
            if node.trySetup(names[id].val):
                names.delete(id)

    discard n.findNode(forall)

proc initWithJson*(n: Node, j: JsonNode) =
    var v = j{"strings"}
    if not v.isNil:
        var data: seq[SetterPair] = @[]
        for i in 0 ..< v.len:
            data.add( ( v[i][0].getStr(), v[i][1].getStr() ) )
        n.initWithData(data)

proc getSetterPairs*(path: string): seq[SetterPair] =
    let n = newNodeWithResource(path)
    proc isComp(node: Node): bool =
        not node.getComponent(TextSetter).isNil
    result = n.findNode(isComp).getComponent(TextSetter).setters

method deserialize*(t: TextSetter, j: JsonNode, s: Serializer) =
    var v = j{"strings"}
    t.setters = @[]
    if not v.isNil:
        for i in 0 ..< v.len:
            t.setters.add( (v[i][0].getStr(), v[i][1].getStr()) )

method serialize*(t: TextSetter, s: Serializer): JsonNode =
    var elements: seq[SetterPair] = @[]
    proc collect(node: Node): bool =
        let txt = node.getComponent(Text)
        if not txt.isNil and node.name.endsWith(t.prefix):
            elements.add( (node.name, txt.text) )
    discard t.node.findNode(collect)

    var chNodes = newSeq[Node]()
    while t.node.children.len > 0:
        chNodes.add(t.node.children[0])
        t.node.children[0].removeFromParent()

    result = newJObject()
    var elNames = newJArray()
    result{"strings"} = elNames
    for value in elements:
        var cell = newJArray()
        cell.add(%value.key)
        cell.add(%value.val)
        elNames.add(cell)

    discard setTimeout(0.5) do():
        for ch in chNodes:
            t.node.addChild(ch)

method visitProperties*(t: TextSetter, p: var PropertyVisitor) =
    discard

registerComponent(TextSetter, "Falcon")
