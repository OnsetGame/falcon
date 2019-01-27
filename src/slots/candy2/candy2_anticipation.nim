import nimx / [ animation, matrixes ]
import rod.node
import utils.helpers

proc playAnticipation*(parent, particlesNode: Node, index: int, cb: proc() = nil) =
    const START_X = -240.0
    const OFFSET = 240.0
    const PART_START_X = 715.0
    const PART_OFFSET = 245.0

    let anticipator = newNodeWithResource("slots/candy2_slot/winlines/precomps/anticipator")
    let anim = anticipator.animationNamed("play")
    let indexOffset = index - 2

    parent.removeAllChildren()
    parent.addChild(anticipator)
    anticipator.position = newVector3(START_X + indexOffset.float * OFFSET, 90)
    particlesNode.position = newVector3(PART_START_X + indexOffset.float * PART_OFFSET, 450.0)
    parent.addAnimation(anim)

    let particles = newNodeWithResource("slots/candy2_slot/particles/anticipator_particles")
    particlesNode.addChild(particles)
    particles.rotationZ = 180.0
    particles.position = newVector3(522.95, 74.71)

    anim.onComplete do():
        if not cb.isNil:
            cb()
        anticipator.removeFromParent()
        let delay = newAnimation()
        delay.numberOfLoops = 1
        delay.loopDuration = 2.0
        delay.onComplete do():
            particles.removeFromParent()
        particlesNode.addAnimation(delay)
