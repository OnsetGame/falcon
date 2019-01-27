import strformat

import nimx / [ animation, matrixes ]

import rod.node
import rod.component.ae_composition

import core.slot.sound_map
import node_proxy.proxy
import utils.helpers

const PREFIX = "slots/card_slot/anticipation/comps"
const LIGHT_START_X = 523.09
const PART_START_X = 461.21
const PART_DOWN_OFFSET = 127.61
const Y = 455.88
const STEP = 222.93
let ANCHOR = newVector3(177.0, 720.0)

nodeProxy AnticipationParticles:
    stream* Animation {withKey: "stream"}:
        cancelBehavior = cbJumpToEnd

nodeProxy AnticipationLight:
    beginning* Animation {withKey: "begin"}:
        cancelBehavior = cbJumpToEnd
    idle* Animation {withKey: "idle"}:
        numberOfLoops = -1
        cancelBehavior = cbContinueUntilEndOfLoop
    ending* Animation {withKey: "end"}:
        cancelBehavior = cbJumpToEnd

type Anticipation* = ref object of RootObj
    particles: array[2, AnticipationParticles]
    light: AnticipationLight
    fade: Animation
    stopped: bool
    sound*: SoundMap


proc prepareLightChain(a: Anticipation) =
    a.light.beginning.onComplete do():
        a.light.node.addAnimation(a.light.idle)
    a.light.idle.onComplete do():
        a.light.node.addAnimation(a.light.ending)
    a.light.ending.onComplete do():
        a.light.node.enabled = false
        for p in a.particles:
            p.node.enabled = false

proc setupPosition(n: Node) =
    n.anchor = ANCHOR
    n.positionY = Y

proc newAnticipation*(backNode: Node, frontNode: Node): Anticipation =
    let particlesUp = new(
        AnticipationParticles,
        newNodeWithResource(&"{PREFIX}/particles_for_anticipation")
    )
    frontNode.addChild(particlesUp.node)
    particlesUp.node.enabled = false
    let particlesDown = new(
        AnticipationParticles,
        newNodeWithResource(&"{PREFIX}/particles_for_anticipation")
    )
    frontNode.addChild(particlesDown.node)
    particlesDown.node.rotationZ = 180.0
    particlesDown.node.enabled = false

    let light = new(
        AnticipationLight,
        newNodeWithResource(&"{PREFIX}/anticipation")
    )
    backNode.addChild(light.node)
    light.node.enabled = false

    result = new(Anticipation)
    result.particles = [particlesUp, particlesDown]
    result.light = light

    result.prepareLightChain()
    setupPosition(particlesUp.node)
    setupPosition(particlesDown.node)
    setupPosition(light.node)

proc start*(a: Anticipation) =
    for p in a.particles:
        p.node.enabled = true
        p.node.alpha = 1.0
        p.node.addAnimation(p.stream)
    a.light.node.enabled = true
    a.light.node.alpha = 1.0
    a.light.node.addAnimation(a.light.beginning)
    a.stopped = false

proc stop*(a: Anticipation) =
    if a.stopped:
        return
    a.stopped = true
    if a.fade.isNil:
        a.fade = newAnimation()
        a.fade.numberOfLoops = 1
        a.fade.loopDuration = 0.2
        a.fade.onAnimate = proc(p: float) =
            let v = 1.0 - p
            a.light.node.alpha = v
            for p in a.particles:
                p.node.alpha = v
        a.fade.onComplete do():
            a.fade = nil
        a.light.idle.cancelBehavior = cbContinueUntilEndOfLoop
        a.light.idle.cancel()
        a.light.node.addAnimation(a.fade)

proc quickStop*(a: Anticipation) =
    if not a.stopped:
        a.sound.stop("ANTICIPATION_SOUND")
        a.sound.play("ANTICIPATION_STOP_SOUND")
    a.stopped = true
    if not a.fade.isNil:
        a.fade.cancel()
    a.light.node.alpha = 0.0
    for p in a.particles:
        p.node.alpha = 0.0

    for p in a.particles:
        p.stream.cancel()
    a.light.beginning.cancel()
    a.light.idle.cancelBehavior = cbJumpToEnd
    a.light.idle.cancel()
    a.light.ending.cancel()

proc `position=`*(a: Anticipation, column: uint8) =
    let offset = column.float * STEP
    a.particles[0].node.positionX = PART_START_X + offset
    a.particles[1].node.positionX = PART_START_X + offset + PART_DOWN_OFFSET
    a.light.node.positionX = LIGHT_START_X + offset

proc startOn*(a: Anticipation, column: uint8) =
    a.position = column
    a.start()
