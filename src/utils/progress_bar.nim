import tables, typetraits, logging
import nimx / [ types, context, property_visitor, matrixes ]

import rod.rod_types
import rod.node
import rod.component
import rod.component / [ clipping_rect_component, sprite, vector_shape, solid ]
import rod.utils.serialization_codegen

import utils.helpers

type ProgressBar* = ref object of Component
    mProgress: float32
    mSize: Size
    sccisor*: bool
    sizes: TableRef[string, float32]

proc setSizeForProgress(c: ProgressBar, n: Node)

proc progress*(c: ProgressBar): float32 = c.mProgress
proc `progress=`*(c: ProgressBar, p: float32) =
    c.mProgress = clamp(p, 0.0, 1.0)

    if c.sccisor:
        let clipRect = c.node.getComponent(ClippingRectComponent)
        clipRect.clippingRect = newRect(zeroPoint, newSize(c.mSize.width * c.mProgress, c.mSize.height))
    else:
        c.setSizeForProgress(c.node)

proc size*(c: ProgressBar): Size = c.mSize
proc `size=`*(c: ProgressBar, s: Size) =
    c.mSize = s
    if c.sccisor:
        let clipRect = c.node.addComponent(ClippingRectComponent)
        if not clipRect.isNil:
            clipRect.clippingRect = newRect(zeroPoint, c.size)
            c.progress = c.mProgress

method init(c: ProgressBar) =
    c.sccisor = false
    c.sizes = newTable[string, float32]()
    c.mSize = newSize(0, 0)
    c.mProgress = 1.0

proc parentWithCamera(n: Node): Node =
    if n.parent.isNil: return nil
    if not n.parent.getComponent(Camera).isNil:
        return n.parent
    else:
        return n.parent.parentWithCamera()


method getProgressComponetSize(component: Component): float32 {.base.} =
    warn "[progress_bar] getProgressComponetSize doesn't have implementation for node ", component.node.name
    result = 0.0

method getProgressComponetSize(component: VectorShape): float32 =
    result = component.size.width - component.radius * 2.0
method getProgressComponetSize(component: Solid): float32 =
    result = component.size.width
method getProgressComponetSize(component: Sprite): float32 =
    result = component.size.width

proc cashSizes(c:ProgressBar, n: Node) =
    for component in n.components:
        if component of Sprite or component of Solid or component of VectorShape:
            c.sizes[n.name] = component.getProgressComponetSize()

    for child in n.children:
        c.cashSizes(child)

method setProgressComponetSize(component: Component, size, progress: float32) {.base.} =
    warn "[progress_bar] getComponnetSize doesn't have implementation for node ", component.node.name

method setProgressComponetSize(component: VectorShape, size, progress: float32) =
    let newSize = size * progress
    component.size.width = newSize + component.radius * 2.0
    let anchorX = -component.radius - size / 2.0 + (size - newSize) / 2.0
    component.node.anchor = newVector3(anchorX, component.node.anchor.y, component.node.anchor.z)

method setProgressComponetSize(component: Solid, size, progress: float32) =
    component.size.width = size * progress

method setProgressComponetSize(component: Sprite, size, progress: float32) =
    component.size.width = size * progress

proc setSizeForProgress(c:ProgressBar, n: Node) =
    for component in n.components:
        if component of Sprite or component of Solid or component of VectorShape:
            component.setProgressComponetSize(c.sizes[n.name], c.mProgress)

    for child in n.children:
        c.setSizeForProgress(child)

method componentNodeWasAddedToSceneView*(c: ProgressBar) =
    # if size not setuped already
    if c.mSize.width == 0 or c.mSize.height == 0:
        let cameraNode = c.node.parentWithCamera()
        let bb = c.node.nodeBounds()
        let dimensions = absVector(bb.maxPoint - bb.minPoint)
        c.mSize = newSize(dimensions.x, dimensions.y)

        if not cameraNode.isNil:
            c.mSize = newSize(c.mSize.width / cameraNode.scale.x, c.mSize.height / cameraNode.scale.y + 1)

        if c.sccisor:
            let clipRect = c.node.addComponent(ClippingRectComponent)
            clipRect.clippingRect = newRect(zeroPoint, c.size)
        else:
            c.cashSizes(c.node)

    c.progress = c.mProgress


method visitProperties*(c: ProgressBar, p: var PropertyVisitor) =
    p.visitProperty("progress", c.progress)
    p.visitProperty("size", c.size)

genSerializationCodeForComponent(ProgressBar)
registerComponent(ProgressBar, "Falcon")
