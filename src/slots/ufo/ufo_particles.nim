import nimx.matrixes
import nimx.types
import rod.node
import rod.component
import rod.component.particle_system
import rod.component.clipping_rect_component
import core.slot.base_slot_machine_view
import ufo_types

proc addAnticipationParticle*(v: UfoSlotView) =
    let p = newNodeWithResource("slots/ufo_slot/slot/particles/anticipation_up")

    v.rootNode.findNode("ufo3").addChild(p)
    p.position = newVector3(965, 1028)
    p.component(ClippingRectComponent).clippingRect = newRect(-200, -850, 500, 1000)

proc stopAnticipationParticle*(v: UfoSlotView) =
    let p = v.rootNode.findNode("anticipation_up")

    if not p.isNil:
        for c in p.children:
            let particleComp = c.componentIfAvailable(ParticleSystem)
            if not particleComp.isNil:
                particleComp.stop()

proc addRaysBack*(v: UfoSlotView) =
    var raysBack: seq[Node] = @[]
    var raysFront: seq[Node] = @[]
    var rbl: seq[ParticleSystem] = @[]
    var rfl: seq[ParticleSystem] = @[]
    var rfd: seq[ParticleSystem] = @[]

    for i in 1..5:
        let rb = newNodeWithResource("slots/ufo_slot/slot/particles/ray_back")
        let rf = newNodeWithResource("slots/ufo_slot/slot/particles/ray_up")

        raysBack.add(rb)
        raysFront.add(rf)
        rb.component(ClippingRectComponent).clippingRect = newRect(-200, -1100, 500, 1000)
        rf.component(ClippingRectComponent).clippingRect = newRect(-200, -1100, 500, 1000)
        rbl.add(rb.childNamed("lines2").component(ParticleSystem))
        rfl.add(rf.childNamed("lines").component(ParticleSystem))
        rfd.add(rf.childNamed("dots").component(ParticleSystem))
        v.rootNode.findNode("ufo" & $i).insertChild(rb, 0)
        v.rootNode.findNode("ufo" & $i).addChild(rf)
        rb.position = newVector3(451, 1250)
        rf.position = newVector3(451, 1250)

    raysBack[1].positionX = 685
    raysBack[2].positionX = 985
    raysBack[3].positionX = 1225
    raysBack[4].positionX = 1529
    rbl[0].gravity.x = 5
    rbl[1].gravity.x = 3
    rbl[3].gravity.x = -3
    rbl[4].gravity.x = -5
    rbl[0].startRotation.z = -15
    rbl[1].startRotation.z = -8
    rbl[3].startRotation.z = 8
    rbl[4].startRotation.z = 15

    raysFront[1].positionX = 685
    raysFront[2].positionX = 985
    raysFront[3].positionX = 1225
    raysFront[4].positionX = 1529
    rfl[0].gravity.x = 5
    rfl[1].gravity.x = 3
    rfl[3].gravity.x = -3
    rfl[4].gravity.x = -5
    rfl[0].startRotation.z = -10
    rfl[1].startRotation.z = -5
    rfl[3].startRotation.z = 5
    rfl[4].startRotation.z = 10
    rfd[0].gravity.x = 5
    rfd[1].gravity.x = 3
    rfd[3].gravity.x = -3
    rfd[4].gravity.x = -5
