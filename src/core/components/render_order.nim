import nimx / [ property_visitor ]
import rod / [node, component]

type RenderOrder* = ref object of Component
    topNode*: Node


method isPosteffectComponent*(c: RenderOrder): bool = not c.topNode.isNil

method beforeDraw*(c: RenderOrder, index: int): bool =
    result = true

    for ch in c.node.children:
        if ch != c.topNode:
            ch.recursiveUpdate()
            ch.recursiveDraw()

    if not c.topNode.isNil:
        c.topNode.recursiveUpdate()
        c.topNode.recursiveDraw()

method visitProperties*(c: RenderOrder, p: var PropertyVisitor) =
    if not c.topNode.isNil:

        var name = c.topNode.name
        p.visitProperty("topNode", name)

        var index = c.node.children.find(c.topNode)
        p.visitProperty("child index", index)

registerComponent(RenderOrder, "RenderOrder")
