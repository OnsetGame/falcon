import rod.node
import rod.component
import rod.component.text_component
import rod.component.ui_component
import rod.component.comp_ref
import rod.component.sprite

import nimx.matrixes
import nimx.types

import utils.helpers


type NinepartTextComponent* = ref object of RootObj
    rootNode*: Node
    ninePartNode: Node
    textNode: Node
    inited: bool


proc setSize(n: Node, sz: Size) =
    for c in n.components:
        if c of Sprite:
            let s = Sprite(c)
            s.size = sz
    for c in n.children:
        c.setSize(sz)


proc setSize(ntc: NinepartTextComponent, size: Size) =
    let nnc = ntc.ninePartNode.component(CompRef)
    for n in nnc.node.children:
        n.setSize(nnc.size)


proc setText*(ntc: NinepartTextComponent, text: string) =
    let nnc = ntc.ninePartNode.component(CompRef)
    let nnt = ntc.textNode.component(Text)

    var oldBBox = nnt.getBBox()
    nnt.text = text
    var newBBox = nnt.getBBox()

    if not ntc.inited:
        newBBox.maxPoint = newBBox.maxPoint + newVector3(0.0, nnt.mText.lineBaseline(0) / 2)
        ntc.inited = true

    let oldTextSize = oldBBox.maxPoint - oldBBox.minPoint
    let offset = (newVector3(nnc.size.width, nnc.size.height) - oldTextSize) / 2

    ntc.ninePartNode.anchor = ntc.textNode.anchor
    ntc.ninePartNode.position = ntc.textNode.position - offset
    
    let delta = (newBBox.maxPoint - newBBox.minPoint) - oldTextSize
    nnc.size = nnc.size + newSize(delta.x, delta.y)
    ntc.ninePartNode.position = ntc.ninePartNode.position + newBBox.minPoint

    ntc.setSize(nnc.size)


proc newNinepartTextComponent*(composition, ninePartNodeName, textNodeName: string): NinepartTextComponent = 
    let rootNode = newLocalizedNodeWithResource("tiledmap/gui/precomps/build_locker_text.json")
    let ninePartNode = rootNode.findNode(ninePartNodeName)
    let textNode = rootNode.findNode(textNodeName)

    result = NinepartTextComponent(
        rootNode: rootNode,
        ninePartNode: ninePartNode,
        textNode: textNode
    )

    result.setText(textNode.component(Text).text)


proc newNinepartTextComponent*(rootNode, ninePartNode, textNode: Node): NinepartTextComponent = 
    result = NinepartTextComponent(
        rootNode: rootNode,
        ninePartNode: ninePartNode,
        textNode: textNode
    )

    result.setText(textNode.component(Text).text)