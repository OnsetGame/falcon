import json, logging, strutils
import nimx / [ types, composition ]
import nimx / property_visitor
import nimx / image
import nimx / assets / asset_manager
import rod / node
import rod / component
import rod / component / [ sprite, solid ]
import rod / asset_bundle
import rod / tools / [ serializer ]
import rod / utils / [ property_desc, serialization_codegen ]
import utils / [helpers, outline]

type
    IconComponentKind* {.pure.} = enum
        anchorBased, sizeBased

    IconComponent* = ref object of Component
        kind*: IconComponentKind
        cComposition: string
        cName: string
        cRect: Rect
        stubNode*: Node
        cNode: Node
        prefix*: string
        resolutions*: seq[int]
        cHasOutline: bool
        setupMode*: bool

IconComponent.properties:
    prefix:
        serializationKey: "iconCompositionPrefix"
    cComposition:
        serializationKey: "iconComposition"
    cName:
        serializationKey: "iconName"
    cHasOutline:
        serializationKey: "iconHasOutline"
    # cRect:
    #     serializationKey: "iconRect"

method init*(c: IconComponent) =
    if c.prefix.len == 0:
        c.prefix = "common/lib/icons/precomps"

    if c.cComposition in ["slot_card_icons", "slot_logos_icons"]:
        c.resolutions = @[2, 1]
    else:
        c.resolutions = @[1]

    c.kind = IconComponentKind.anchorBased

proc addNode(c: IconComponent, node: Node) =
    if not c.cNode.isNil:
        c.cNode.removeFromParent()
    c.cNode = if node.isNil: c.stubNode else: node

    if not c.cNode.isNil:
        c.cNode.position = newVector3(c.cRect.size.width / 2 + c.cRect.origin.x, c.cRect.size.height / 2 + c.cRect.origin.y, 0.0)
        c.node.addChild(c.cNode)

        if c.cHasOutline:
            discard c.cNode.addComponent(Outline, 0)

proc outlineRadius*(c: IconComponent, newRadius:float32) =
    if c.cHasOutline and not c.cNode.isNil:
        let outline = c.cNode.getComponent(Outline)
        if not outline.isNil:
            outline.radius = newRadius

proc showIcon*(c: IconComponent) =
    if c.setupMode:
        return

    if c.cComposition == "" or c.cName == "" or c.cRect == zeroRect:
        c.addNode(nil)
        return

    let width = c.cRect.size.width
    let height = c.cRect.size.height

    var origWidth = width
    var origHeight = height

    if c.cComposition.len == 0:
        return

    let prefix = c.prefix & "/" & c.cComposition
    var node: Node

    for resolution in c.resolutions:
        let path = prefix & (if resolution == 1: "" else: "@" & $resolution & "x")

        var compose: Node
        try: compose = newNodeWithResource(path)
        except: continue

        let tmpNode = compose.findNode(c.cName)
        if tmpNode.isNil:
            continue

        var size: Vector3
        case c.kind:
            of IconComponentKind.anchorBased:
                size = tmpNode.position * 2
            of IconComponentKind.sizeBased:
                let bounds = tmpNode.nodeBounds()
                size = bounds.maxPoint - bounds.minPoint

        if size.x == width and size.y == height:
            origWidth = width
            origHeight = height
            node = tmpNode
            break

        elif size.x < width or size.y < height:
            if node.isNil:
                origWidth = size.x
                origHeight = size.y
                node = tmpNode
            break

        origWidth = size.x
        origHeight = size.y
        node = tmpNode

    if not node.isNil:
        case c.kind:
            of IconComponentKind.anchorBased:
                discard
            of IconComponentKind.sizeBased:
                node.anchor = newVector3(origWidth / 2, origHeight / 2)
                node.position = newVector3(0.0, 0.0)

        if origHeight != height or origWidth != width:
            let heightRatio = height / origHeight
            let widthRatio = width / origWidth

            if widthRatio < heightRatio:
                node.scale = newVector3(widthRatio, widthRatio, 1.0) * node.scale
            else:
                node.scale = newVector3(heightRatio, heightRatio, 1.0) * node.scale

    c.addNode(node)

template iconNode*(c: IconComponent): Node = c.cNode

template composition*(c: IconComponent): string = c.cComposition
proc `composition=`*(c: IconComponent, composition: string) =
    if composition in ["slot_card_icons", "slot_logos_icons"]:
        c.resolutions = @[2, 1]

    c.cComposition = composition
    c.showIcon()


template name*(c: IconComponent): string = c.cName
proc `name=`*(c: IconComponent, name: string) =
    c.cName = name
    c.showIcon()

template hasOutline*(c: IconComponent): bool = c.cHasOutline
proc `hasOutline=`*(c: IconComponent, state: bool) =
    c.cHasOutline = state
    if c.cHasOutline and not c.cNode.isNil and c.cNode.getComponent(Outline).isNil:
        discard c.cNode.addComponent(Outline, 0)

    elif not c.cHasOutline and not c.cNode.isNil:
        let outline = c.cNode.getComponent(Outline)
        c.cNode.removeComponent(outline)

template rect*(c: IconComponent): Rect = c.cRect
proc `rect=`*(c: IconComponent, rect: Rect) =
    c.cRect = rect
    c.showIcon()

template setup*(c: IconComponent, x: untyped): untyped =
    c.setupMode = true

    x

    c.setupMode = false
    c.showIcon()

method componentNodeWasAddedToSceneView*(c: IconComponent) =
    if not c.node.isNil and c.cRect == zeroRect:
        let solid = c.node.getComponent(Solid)
        if not solid.isNil:
            c.cRect = newRect(newPoint(0.0, 0.0), solid.size)
            solid.color = newColor(0.0, 0.0, 0.0, 0.0)

    c.showIcon()

method componentNodeWillBeRemovedFromSceneView*(c: IconComponent) =
    if not c.cNode.isNil:
        c.cNode.removeFromParent()

method deserialize*(c: IconComponent, j: JsonNode, s: Serializer) =
    s.deserializeValue(j, "iconCompositionPrefix", c.prefix)
    s.deserializeValue(j, "iconComposition", c.cComposition)
    s.deserializeValue(j, "iconName", c.cName)
    s.deserializeValue(j, "iconHasOutline", c.cHasOutline)

method serialize*(c: IconComponent, s: Serializer): JsonNode =
    result = newJObject()
    result.add("iconCompositionPrefix", s.getValue(c.prefix))
    result.add("iconComposition", s.getValue(c.cComposition))
    result.add("iconName", s.getValue(c.cName))
    result.add("iconHasOutline", s.getValue(c.cHasOutline))

method visitProperties*(c: IconComponent, p: var PropertyVisitor) =
    p.visitProperty("kind", c.kind)
    p.visitProperty("prefix", c.prefix)
    p.visitProperty("composition", c.composition)
    p.visitProperty("name", c.name)
    p.visitProperty("rect", c.rect)
    p.visitProperty("hasOutline", c.hasOutline)


proc addRewardIcon*(n: Node, name: string = ""): IconComponent =
    result = n.component(IconComponent)
    result.prefix = "common/lib/icons/precomps"
    result.composition = "reward_icons"
    result.hasOutline = true
    if name.len != 0: result.name = name

proc addSlotIcons*(n: Node, name: string = ""): IconComponent =
    result = n.component(IconComponent)
    result.prefix = "common/lib/icons/precomps"
    result.composition = "slot_logos_icons"
    if name.len != 0: result.name = name

proc addBuildingIcons*(n: Node, name: string = ""): IconComponent =
    result = n.component(IconComponent)
    result.prefix = "common/lib/icons/precomps"
    result.composition = "buildings_icons"
    if name.len != 0: result.name = name

proc addChipsIcons*(n: Node, name: string = "chips"): IconComponent =
    result = n.component(IconComponent)
    result.prefix = "common/lib/icons/precomps"
    result.composition = "currency_chips"
    result.hasOutline = true
    if name.len != 0: result.name = name

proc addBucksIcons*(n: Node, name: string = "bucks"): IconComponent =
    result = n.component(IconComponent)
    result.prefix = "common/lib/icons/precomps"
    result.composition = "currency_bucks"
    result.hasOutline = true
    if name.len != 0: result.name = name

proc addEnergyIcons*(n: Node, name: string = "energy"): IconComponent =
    result = n.component(IconComponent)
    result.prefix = "common/lib/icons/precomps"
    result.composition = "currency"
    result.hasOutline = true
    if name.len != 0: result.name = name

proc addCurrencyIcon*(n: Node, currency:string) =
    var c = currency.toLowerAscii
    if c == "energy":
        c = "parts"
    discard n.addRewardIcon(c)

proc addFeatureIcons*(n: Node, name: string = ""): IconComponent =
    result = n.component(IconComponent)
    result.prefix = "common/lib/icons/precomps"
    result.composition = "feature_button_icon"
    if name.len != 0: result.name = name

proc addSignIcons*(n: Node, name: string = ""): IconComponent =
    result = n.component(IconComponent)
    result.prefix = "common/lib/icons/precomps"
    result.composition = "icons_signs"
    result.hasOutline = true
    if name.len != 0: result.name = name

proc addSlotLogos*(n: Node, name: string = ""): IconComponent =
    result = n.component(IconComponent)
    result.prefix = "common/lib/icons/precomps"
    result.composition = "slot_logos_icons"
    if name.len != 0: result.name = name

proc addSlotLogos2x*(n: Node, name: string = ""): IconComponent =
    result = n.component(IconComponent)
    result.prefix = "common/lib/icons/precomps"
    result.composition = "slot_logos_icons@2x"
    if name.len != 0: result.name = name

proc addPaylinesIcon*(n: Node, name: string = ""): IconComponent =
    result = n.component(IconComponent)
    result.prefix = "common/lib/icons/precomps"
    result.composition = "paylines"
    if name.len != 0: result.name = name

proc addTournamentPointIcon*(n: Node): IconComponent =
    result = n.component(IconComponent)
    result.prefix = "common/lib/icons/precomps"
    result.composition = "tournament_point"
    result.name = "tournament_point_icon_b.png"

genSerializationCodeForComponent(IconComponent)
registerComponent(IconComponent, "Falcon")
