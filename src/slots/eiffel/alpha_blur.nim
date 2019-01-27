import rod.node
import rod.component
import rod.component.sprite
import nimx.types
import nimx.property_visitor
import nimx.matrixes
import nimx.class_registry
import utils.helpers

type AlphaBlur* = ref object of Component
    shifts*: int
    prevPosition*: Vector3
    offset*:Vector3
    spriteComps: seq[Sprite]

method init*(c: AlphaBlur)=
    c.shifts = 5
    c.offset = newVector3(0.0, -5.0, 0.0)

method draw*(c: AlphaBlur)=
    if c.spriteComps.len > 0:
        let st = c.node.position
        for s in 0 ..< c.shifts:
            c.node.position = c.node.position + c.offset
            c.node.alpha = 1.0 - s/c.shifts
            for s in c.spriteComps:
                s.draw()
            c.node.position = st
        c.prevPosition = st

method componentNodeWasAddedToSceneView*(c: AlphaBlur)=
    c.prevPosition = c.node.position
    c.spriteComps = @[]
    c.node.componentsInNode(c.spriteComps)

method visitProperties*(c: AlphaBlur, p: var PropertyVisitor)=
    p.visitProperty("Shifts", c.shifts)

registerComponent(AlphaBlur)