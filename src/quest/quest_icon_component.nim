import json
import nimx / [ types, composition, image ]
import nimx / [ property_visitor ]
import rod / [ component, node ]
import rod / component / [ sprite ]
import rod / tools / [ serializer ]

import utils / rounded_component

import quests


var getTileImage*: proc(id: int16): Image = nil
var getLayerImage*: proc(name: string): Image = nil
var getPropertyImage*: proc(propName, propVal: string): Image = nil


type QuestIconImageType* = enum
    qiitSingle
    qiitDouble
    qiitSingleMain

type QuestIconType* = enum
    qitTileId
    qitLayerName
    qitProperty


type QuestIconShowType = enum
    qistMain
    qistSecondary

type QuestIconComponent* = ref object of Component
    cConfigure: bool
    cQuest: Quest
    cIconImageType: QuestIconImageType

    cMainIconType: QuestIconType
    cMainIconTileId: int16
    cMainIconLayerName: string
    cMainIconPropertyValue: string
    cMainRect: Rect

    cSpriteMainNode: Node
    spriteMainComponent: Sprite
    roundedMainComponent: RoundedComponent
    spriteMainBack*: Node

    cSecondaryIconType: QuestIconType
    cSecondaryIconTileId: int16
    cSecondaryIconLayerName: string
    cSecondaryIconPropertyValue: string
    cSecondaryRect: Rect

    cSpriteSecondaryNode: Node
    spriteSecondaryComponent: Sprite
    roundedSecondaryComponent: RoundedComponent
    spriteSecondaryBack*: Node

    mainImage: Image
    secondaryImage: Image


method init*(c: QuestIconComponent) =
    c.cIconImageType = qiitSingle

    c.cMainRect = zeroRect
    c.cSpriteMainNode = newNode("main_image")
    c.roundedMainComponent = c.cSpriteMainNode.component(RoundedComponent)
    c.roundedMainComponent.disabled = true
    c.spriteMainComponent = c.roundedMainComponent.node.component(Sprite)

    c.cSecondaryRect = zeroRect
    c.cSpriteSecondaryNode = newNode("secondary_image")
    c.roundedSecondaryComponent = c.cSpriteSecondaryNode.component(RoundedComponent)
    c.roundedSecondaryComponent.disabled = true
    c.spriteSecondaryComponent = c.roundedSecondaryComponent.node.component(Sprite)


proc drawImage(c: QuestIconComponent, kind: QuestIconShowType, image: Image) =
    var spriteComponent: Sprite
    var roundedComponent: RoundedComponent
    var node: Node
    var rect: Rect

    case kind:
        of qistMain:
            spriteComponent = c.spriteMainComponent
            roundedComponent = c.roundedMainComponent
            node = c.cSpriteMainNode
            rect = c.cMainRect
        of qistSecondary:
            spriteComponent = c.spriteSecondaryComponent
            roundedComponent = c.roundedSecondaryComponent
            node = c.cSpriteSecondaryNode
            rect = c.cSecondaryRect

    if image.isNil:
        node.alpha = 0.0
        spriteComponent.image = image
        return
    node.alpha = 1.0

    let roundedRectSize = rect.size
    let imageSize = image.size()
    let widthToHeight = imageSize.width / imageSize.height

    var spriteRectSize: Size
    if imageSize.width > imageSize.height:
        spriteRectSize = newSize(roundedRectSize.width, roundedRectSize.width / widthToHeight)
    else:
        spriteRectSize = newSize(roundedRectSize.height * widthToHeight, roundedRectSize.height)

    spriteComponent.size = spriteRectSize
    spriteComponent.image = image
    spriteComponent.offset = newPoint(-spriteRectSize.width / 2, -spriteRectSize.height / 2) + rect.origin

    roundedComponent.rect = newRect(newPoint(-roundedRectSize.width / 2, -roundedRectSize.height / 2) + rect.origin, roundedRectSize)


proc showImages(c: QuestIconComponent) =
    if c.cConfigure:
        return

    if c.mainImage.isNil and c.secondaryImage.isNil:
        c.spriteMainComponent.image = nil
        c.spriteSecondaryComponent.image = nil
        return

    case c.cIconImageType:
        of qiitSingle:
            c.drawImage(qistSecondary, nil)
            var image = c.secondaryImage
            if image.isNil:
                image = c.mainImage
            c.drawImage(qistMain, image)
        of qiitDouble:
            if not c.mainImage.isNil:
                c.drawImage(qistMain, c.mainImage)
                c.drawImage(qistSecondary, c.secondaryImage)
            elif not c.secondaryImage.isNil:
                c.drawImage(qistMain, c.secondaryImage)
                c.drawImage(qistSecondary, nil)
        of qiitSingleMain:
            c.drawImage(qistSecondary, nil)
            var image = c.mainImage
            if image.isNil:
                image = c.secondaryImage
            c.drawImage(qistMain, image)

proc setImages(c: QuestIconComponent) =
    if c.cConfigure:
        return

    var icon: Image

    icon = nil
    case c.cMainIconType:
        of qitTileId:
            if c.cMainIconTileId > 0 and not getTileImage.isNil:
                icon = getTileImage(c.cMainIconTileId)
        of qitLayerName:
            if c.cMainIconLayerName.len > 0 and not getLayerImage.isNil:
                icon = getLayerImage(c.cMainIconLayerName)
        of qitProperty:
            if c.cMainIconPropertyValue.len > 0 and not getPropertyImage.isNil:
                icon = getPropertyImage("ImageAnchorName", c.cMainIconPropertyValue)
    c.mainImage = icon

    icon = nil
    case c.cSecondaryIconType:
        of qitTileId:
            if c.cSecondaryIconTileId > 0 and not getTileImage.isNil:
                icon = getTileImage(c.cSecondaryIconTileId)
        of qitLayerName:
            if c.cSecondaryIconLayerName.len > 0 and not getLayerImage.isNil:
                icon = getLayerImage(c.cSecondaryIconLayerName)
        of qitProperty:
            if c.cSecondaryIconPropertyValue.len > 0 and not getPropertyImage.isNil:
                icon = getPropertyImage("ImageAnchorName", c.cSecondaryIconPropertyValue)
    c.secondaryImage = icon

    c.showImages()


method componentNodeWasAddedToSceneView*(c: QuestIconComponent) =
    c.node.addChild(c.cSpriteMainNode)
    c.node.addChild(c.cSpriteSecondaryNode)
    c.showImages()


method componentNodeWillBeRemovedFromSceneView*(c: QuestIconComponent) =
    if not c.cSpriteMainNode.isNil:
        c.cSpriteMainNode.removeFromParent()

    if not c.cSpriteSecondaryNode.isNil:
        c.cSpriteSecondaryNode.removeFromParent()

proc `questConfig=`*(c: QuestIconComponent, qc: QuestConfig)=
    if not qc.isNil:
        if qc.zoneImageTiledProp != "":
            c.cMainIconType = qitProperty
            c.cMainIconPropertyValue = qc.zoneImageTiledProp
        if qc.decoreImageTiledProp != "":
            c.cSecondaryIconType = qitProperty
            c.cSecondaryIconPropertyValue = qc.decoreImageTiledProp

    c.setImages()


proc quest*(c: QuestIconComponent): Quest = c.cQuest
proc `quest=`*(c: QuestIconComponent, q: Quest) =
    c.cQuest = q
    c.questConfig = q.config

proc iconImageType*(c: QuestIconComponent): QuestIconImageType = c.cIconImageType
proc `iconImageType=`*(c: QuestIconComponent, t: QuestIconImageType) =
    c.cIconImageType = t
    c.setImages()


proc mainIconType*(c: QuestIconComponent): QuestIconType = c.cMainIconType
proc `mainIconType=`*(c: QuestIconComponent, t: QuestIconType) =
    c.cMainIconType = t
    c.setImages()


proc mainIconTileId*(c: QuestIconComponent): int = c.cMainIconTileId
proc `mainIconTileId=`*(c: QuestIconComponent, v: int) =
    c.cMainIconTileId = v.int16
    case c.cMainIconType:
        of qitTileId:
            c.setImages()
        else:
            discard


proc mainIconLayerName*(c: QuestIconComponent): string = c.cMainIconLayerName
proc `mainIconLayerName=`*(c: QuestIconComponent, v: string) =
    c.cMainIconLayerName = v
    case c.cMainIconType:
        of qitLayerName:
            c.setImages()
        else:
            discard


proc mainIconPropertyValue*(c: QuestIconComponent): string = c.cMainIconPropertyValue
proc `mainIconPropertyValue=`*(c: QuestIconComponent, v: string) =
    c.cMainIconPropertyValue = v
    case c.cMainIconType:
        of qitProperty:
            c.setImages()
        else:
            discard


proc secondaryIconType*(c: QuestIconComponent): QuestIconType = c.cSecondaryIconType
proc `secondaryIconType=`*(c: QuestIconComponent, t: QuestIconType) =
    c.cSecondaryIconType = t
    c.setImages()


proc secondaryIconTileId*(c: QuestIconComponent): int = c.cSecondaryIconTileId.int
proc `secondaryIconTileId=`*(c: QuestIconComponent, v: int) =
    c.cSecondaryIconTileId = v.int16
    case c.cSecondaryIconType:
        of qitTileId:
            c.setImages()
        else:
            discard


proc secondaryIconLayerName*(c: QuestIconComponent): string = c.cSecondaryIconLayerName
proc `secondaryIconLayerName=`*(c: QuestIconComponent, v: string) =
    c.cSecondaryIconLayerName = v
    case c.cSecondaryIconType:
        of qitLayerName:
            c.setImages()
        else:
            discard


proc secondaryIconPropertyValue*(c: QuestIconComponent): string = c.cSecondaryIconPropertyValue
proc `secondaryIconPropertyValue=`*(c: QuestIconComponent, v: string) =
    c.cSecondaryIconPropertyValue = v
    case c.cSecondaryIconType:
        of qitProperty:
            c.setImages()
        else:
            discard


proc mainRect*(c: QuestIconComponent): Rect = c.cMainRect
proc `mainRect=`*(c: QuestIconComponent, v: Rect) =
    c.cMainRect = v
    c.showImages()


proc secondaryRect*(c: QuestIconComponent): Rect = c.cSecondaryRect
proc `secondaryRect=`*(c: QuestIconComponent, v: Rect) =
    c.cSecondaryRect = v
    c.showImages()


proc configure*(c: QuestIconComponent, cb: proc()) =
    c.cConfigure = true
    cb()
    c.cConfigure = false
    c.setImages()


proc questId*(c: QuestIconComponent): int = (if not c.quest.isNil: c.quest.id else: 0)
proc `questId=`*(c: QuestIconComponent, v: int) =
    c.quest = sharedQuestManager().questById(v)


proc `mainNode=`*(c: QuestIconComponent, n: Node) =
    n.addChild(c.cSpriteMainNode)
    c.cSpriteMainNode = n


proc `secondaryNode=`*(c: QuestIconComponent, n: Node) =
    n.addChild(c.cSpriteSecondaryNode)
    c.cSpriteSecondaryNode = n


proc rounded*(c: QuestIconComponent): bool = not c.roundedMainComponent.disabled
proc `rounded=`*(c: QuestIconComponent, v: bool) =
    c.roundedMainComponent.disabled = not v
    c.roundedSecondaryComponent.disabled = not v


method visitProperties*(c: QuestIconComponent, p: var PropertyVisitor) =
    p.visitProperty("questId", c.questId)
    p.visitProperty("ImageType", c.iconImageType)

    p.visitProperty("mIconType", c.mainIconType)
    p.visitProperty("mTileId", c.mainIconTileId)
    p.visitProperty("mLayerName", c.mainIconLayerName)
    p.visitProperty("mainRect", c.mainRect)

    p.visitProperty("sIconType", c.secondaryIconType)
    p.visitProperty("sTileId", c.secondaryIconTileId)
    p.visitProperty("sLayerName", c.secondaryIconLayerName)
    p.visitProperty("secondaryRect", c.secondaryRect)

    p.visitProperty("rounded", c.rounded)


registerComponent(QuestIconComponent, "Falcon")