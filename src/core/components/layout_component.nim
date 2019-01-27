import nimx / [types, matrixes, view, property_visitor]
import rod / [component, node, ray, viewport, rod_types]
import shared / game_scene
import core / notification_center


const RESOLUTION = VIEWPORT_SIZE.width / VIEWPORT_SIZE.height


type LayoutRelation* = enum
    lrTopLeft
    lrTop
    lrTopRight
    lrRight
    lrBottomRight
    lrBottom
    lrBottomLeft
    lrLeft


type LayoutFlexRelation* = enum
    lfrNoFlex
    lfrLeftRight
    lftrTopBottom
    lfrBox


type LayoutComponent* = ref object of Component
    cRel: LayoutRelation
    cWithScale: bool
    cWithMinMax: bool

    cFlexRel: LayoutFlexRelation
    cSize: Size
    onResize*: proc(size: Size)

    cOriginalScale: Vector3
    cOriginalPosition: Vector3
    setup: bool
    cCurrentPosition: Vector3


method init*(c: LayoutComponent) =
    c.setup = true


proc guiScale*(r: Rect): Vector3 =
    const targetRatio = RESOLUTION
    let currentRatio = r.width / r.height
    let scaleRatio = currentRatio / targetRatio
    result = newVector3(scaleRatio, scaleRatio, 1.0)
    if result.x > 1.0:
        result = newVector3(1.0,1.0,1.0)


proc onResizeAux(c: LayoutComponent) =
    if c.setup:
        return

    let maxCorner = c.node.sceneView().bounds.maxCorner
    let curResolution = maxCorner.x / maxCorner.y
    let delta = (curResolution - RESOLUTION) * 1080

    if curResolution != RESOLUTION:
        case c.cRel:
            of lrTopLeft, lrBottomLeft, lrLeft:
                c.node.positionX = c.cOriginalPosition.x - delta / 2.0
            of lrTopRight, lrRight, lrBottomRight:
                c.node.positionX = c.cOriginalPosition.x + delta / 2.0
            else:
                discard
    
    if c.cWithScale:
        if curResolution >= RESOLUTION:
            c.node.scale = c.cOriginalScale
            c.node.positionY = c.cOriginalPosition.y
        else:
            let scale = curResolution / RESOLUTION
            c.node.scale = newVector3(c.cOriginalScale.x * scale, c.cOriginalScale.y * scale, 1)
            
            case c.cRel:
                of lrTopLeft, lrBottomLeft, lrLeft:
                    c.node.positionX = c.node.positionX - c.node.anchor.x * (1 - scale)
                of lrTopRight, lrRight, lrBottomRight:
                    c.node.positionX = c.node.positionX + c.node.anchor.x * (1 - scale)
                else:
                    discard
            
            case c.cRel:
                of lrTopLeft, lrTop, lrTopRight:
                    c.node.positionY = c.cOriginalPosition.y - c.node.anchor.y * (1 - scale)
                of lrBottomLeft, lrBottom, lrBottomRight:
                    c.node.positionY = c.cOriginalPosition.y + c.node.anchor.y * (1 - scale)
                else:
                    discard

    if c.cWithMinMax:
        case c.cRel:
            of lrTopLeft, lrBottomLeft, lrLeft:
                c.node.positionX = min(c.node.positionX, c.cOriginalPosition.x)
            of lrTopRight, lrRight, lrBottomRight:
                c.node.positionX = max(c.node.positionX, c.cOriginalPosition.x)
            else:
                discard
    
    if not c.onResize.isNil and c.cFlexRel != lfrNoFlex:
        case c.cFlexRel:
            of lfrLeftRight:
                case c.cRel:
                    of lrTopRight, lrRight, lrBottomRight:
                        c.node.positionX = c.node.positionX - delta * c.node.scale.x
                    else:
                        discard
                if c.cWithMinMax:
                    c.onResize(newSize(max(c.cSize.width + delta, c.cSize.width), c.cSize.height))
                else:
                    c.onResize(newSize(c.cSize.width + delta, c.cSize.height))
            of lftrTopBottom:
                if c.cWithScale:
                    if c.cWithMinMax:
                        c.onResize(newSize(c.cSize.width, max(c.cSize.height /  c.node.scale.y, c.cSize.height)))
                    else:
                        c.onResize(newSize(c.cSize.width, c.cSize.height /  c.node.scale.y))
            of lfrBox:
                case c.cRel:
                    of lrTopRight, lrRight, lrBottomRight:
                        c.node.positionX = c.node.positionX - delta * c.node.scale.x
                    else:
                        discard
                let width = c.cSize.width + delta
                let height = c.cSize.height / c.node.scale.y
                if c.cWithMinMax:
                    c.onResize(newSize(max(width, c.cSize.width), max(height, c.cSize.height)))
                else:
                    c.onResize(newSize(width, height))
            else:
                discard


method componentNodeWasAddedToSceneView(c: LayoutComponent) =
    c.cOriginalScale = c.node.scale
    c.cOriginalPosition = c.node.position
    c.setup = false

    sharedNotificationCenter().addObserver("GAME_SCENE_RESIZE", c) do(args: Variant):
        c.onResizeAux()
    c.onResizeAux()


method componentNodeWillBeRemovedFromSceneView(c: LayoutComponent) =
    c.node.scale = c.cOriginalScale
    c.node.position = c.cOriginalPosition

    sharedNotificationCenter().removeObserver("GAME_SCENE_RESIZE", c)


proc rel*(c: LayoutComponent): LayoutRelation = c.cRel
proc `rel=`*(c: LayoutComponent, rel: LayoutRelation) =
    c.cRel = rel
    c.onResizeAux()

proc withScale*(c: LayoutComponent): bool = c.cWithScale
proc `withScale=`*(c: LayoutComponent, withScale: bool) =
    c.cWithScale = withScale
    c.onResizeAux()

proc withMinMax*(c: LayoutComponent): bool = c.cWithMinMax
proc `withMinMax=`*(c: LayoutComponent, withMinMax: bool) =
    c.cWithMinMax = withMinMax
    c.onResizeAux()

proc flex*(c: LayoutComponent): LayoutFlexRelation = c.cFlexRel
proc `flex=`*(c: LayoutComponent, flex: LayoutFlexRelation) =
    c.cFlexRel = flex
    c.onResizeAux()

proc size*(c: LayoutComponent): Size = c.cSize
proc `size=`*(c: LayoutComponent, size: Size) =
    c.cSize = size
    c.onResizeAux()


template setup*(c: LayoutComponent, x: untyped): untyped =
    let setup = c.setup
    c.setup = true

    x

    x.setup = setup
    if not setup:
        c.onResizeAux()


method visitProperties*(c: LayoutComponent, p: var PropertyVisitor) =
    p.visitProperty("rel", c.rel)
    p.visitProperty("withScale", c.withScale)
    p.visitProperty("size", c.size)
    p.visitProperty("flex", c.flex)
    p.visitProperty("withMinMax", c.withMinMax)


registerComponent(LayoutComponent, "Falcon")