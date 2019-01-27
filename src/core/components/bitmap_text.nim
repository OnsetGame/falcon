import nimx / [ property_visitor, matrixes ]
import rod / [ node, component, viewport ]
import rod / component / [ sprite, text_component ]
import tables
export HorizontalTextAlignment

# simple bitmap font for numbers
# in event messages and winlines
type BmFont* = ref object of Component
    charset*: Table[char, Node]
    # xoffset*: float
    offset*: Vector3
    halignment*: HorizontalTextAlignment
    mText: string

proc setup*(bm: BmFont, offset: Vector3, chars: string, nodes: seq[Node])=
    assert(chars.len == nodes.len)
    bm.charset = initTable[char, Node]()
    bm.offset = offset
    
    for i in 0 ..< chars.len:
        bm.charset[chars[i]] = nodes[i]

proc setup*(bm: BmFont, offsetX: float, chars: string, nodes: seq[Node])=
    bm.setup(newVector3(offsetX), chars, nodes)

proc text*(bm: BmFont): string =
    result = bm.mText

proc `text=`*(bm: BmFont, t: string)=
    bm.mText = t

proc recursiveSetViewToPrototype(n: Node, v: SceneView) =
    n.mSceneView = v
    for child in n.children:
        child.recursiveSetViewToPrototype(v)

method beforeDraw*(bm: BmFont, index: int): bool =
    result = true

    let allWidth = (bm.text.len - 1).float * bm.offset.x
    var globalOff = 0.0

    if bm.halignment == haRight:
        globalOff = -allWidth
    elif bm.halignment == haCenter:
        globalOff = -allWidth * 0.5

    for i, ch in bm.text:
        let bc = bm.charset.getOrDefault(ch)
        if not bc.isNil:
            var pos = bm.offset * i.float 
            pos.x = pos.x + globalOff
            bc.position = pos

            bc.recursiveUpdate()
            bc.recursiveDraw()

method afterDraw*(c: BmFont, index: int) =
    discard

method isPosteffectComponent*(c: BmFont): bool = true

method componentNodeWasAddedToSceneView*(bm: BmFont)=
    for k, v in bm.charset:
        bm.node.addChild(v)
        # v.enabled = false

method visitProperties*(bm: BmFont, p: var PropertyVisitor) =
    p.visitProperty("text", bm.text)
    p.visitProperty("offset", bm.offset)
    p.visitProperty("halignment", bm.halignment)

registerComponent(BmFont, "Falcon")
