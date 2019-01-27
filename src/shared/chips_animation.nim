import rod.rod_types
import rod.node
import rod.component
import rod.component.particle_emitter
import rod.component.sprite
import rod.viewport
import nimx.matrixes
import nimx.view
import nimx.animation
import nimx.image
import nimx.types
import nimx.notification_center
import game_scene
# import base_slot_machine_view
import tables
import utils.sound_manager
import utils.pause
import utils.sound
# import shared.gui.money_panel_module
import utils.console
import shared.director
import math
import strutils

const CHIPS_MAXIMUM_COUNT = 50.int64
const CHIPS_MINIMUM_COUNT = 5.int64
const CHIPS_MOD = 5.int64
const PARTICLES_BIRTHRATE = 0.1

type ParticleVacuumAttractor* = ref object of ParticleAttractor
    onCollide: proc()
    screenBorderBounce: bool

registerComponent(ParticleVacuumAttractor, "ParticleSystem")

method particleUpdate*(pa: ParticleVacuumAttractor, p: ParticleEmitter, part: var ParticleData, timeDiff: float, origin: Vector3)=
    var destination = origin - part.coord

    const rad = 1.0.float
    let rad_m_resetRadius = 1.01
    var dest_len = destination.length
    var dist = if dest_len > 0: dest_len / pa.radius
                          else: 0.0

    # if pa.screenBorderBounce:
    #     let viewportSize = pa.node.sceneView.camera.viewportSize

    #     if (part.coord.x < 0.0 and part.velocity.x < 0.0) or (part.coord.x > viewportSize.width - 100.0 and part.velocity.y > 0.0):
    #         part.velocity = newVector3(-part.velocity.x, part.velocity.y)

    #     if (part.coord.y < 0.0 and part.velocity.y < 0.0) or (part.coord.y > viewportSize.height and part.velocity.y > 0.0):
    #         part.velocity = newVector3(part.velocity.x, -part.velocity.y)

    if dist <= rad:
        if dist < pa.resetRadius:
            part.remainingLifetime = -1
            if not pa.onCollide.isNil:
                pa.onCollide()
            return
        else:
            var force = (rad_m_resetRadius - dist) * pa.gravity
            destination.normalize()
            var upd_velocity = destination * force
            part.velocity *= 0.9
            part.velocity += upd_velocity
    else:
        part.velocity += p.gravity

proc chipsCountForWin*(totalWin, totalBet: int64): int64 =
    var coof = totalWin div totalBet.int64
    result = CHIPS_MINIMUM_COUNT + coof div CHIPS_MOD
    result = if result > CHIPS_MAXIMUM_COUNT: CHIPS_MAXIMUM_COUNT
                                        else: result

proc createParticleNode(particle: string): Node=
    result = newLocalizedNodeWithResource("common/particles/" & particle &  "_particle.json").findNode(particle)

proc createParticle(ptype: string): Node =
    const show_duration = 0.2
    const destV = newVector3(1.0,1.0,1)
    const zeroV = newVector3(0,0,0)
    var particle = createParticleNode(ptype)
    particle.position = newVector3(0,0,0)

    let sprite = particle.component(Sprite)
    let numFrames = sprite.images.len

    let anchor = newNode()
    anchor.addChild(particle)
    anchor.alpha = 1.0

    type PartSet = tuple[alpha: float, scale: Vector3, dur: float]
    var part_settings = newTable[float, PartSet]()

    let c = newComponentWithUpdateProc do():
        let pc = anchor.component(particle_emitter.Particle)
        let pid = pc.pid
        let elapsedLifetime = pc.initialLifetime - pc.remainingLifetime
        sprite.currentFrame = int(elapsedLifetime * 24.0) mod numFrames

        var settings:PartSet
        if part_settings.hasKey(pid):
            settings = part_settings[pid]
        else:
            settings = (alpha: 0.0, scale: zeroV, dur: 0.0)
            part_settings[pid] = settings

        settings.dur = elapsedLifetime

        if settings.dur <= show_duration:
            let step = settings.dur/show_duration
            settings.scale = interpolate(zeroV, destV, step)
            settings.alpha = interpolate(0.0, 1.0, step)

        particle.scale = settings.scale
        particle.alpha = settings.alpha

        part_settings[pid] = settings

    anchor.setComponent "_updateParticle", c

    result = anchor

proc angle(a: Vector3): float =
    result = arctan2(-a.y, a.x)

proc runParticlesAnimation(v: GameScene, particle: string, parent, f, t: Node, particlesCount: int, onCollide:proc() = nil): ParticleEmitter =
    var par_emitter = newNode("chips_ParticleEmitter")
    var par_attractor = newNode("chips_ParticleAttractor")
    var particle = createParticle(particle)
    let pa = par_attractor.component(ParticleVacuumAttractor)
    let pe = par_emitter.component(ParticleEmitter)

    var tl = parent.worldToLocal(t.worldPos())
    var fl = parent.worldToLocal(f.worldPos())
    tl.z = fl.z

    var pa_gravity = (tl - fl)
    pa_gravity.normalize()
    par_emitter.position = fl
    par_attractor.position = tl
    if v.camera.projectionMode == cpPerspective:
        pa_gravity.y *= -1
    var chips_direction = radToDeg(pa_gravity.angle())
    pa_gravity *= 0.1
    pa.radius = 1000 * v.camera.node.scale.x
    pa.resetRadius = 0.1 # 0.2 is a hole radius, based on calculations - radius * hole (800 * 0.2 = 160)
    pa.gravity = 5.5.float
    pa.onCollide = onCollide

    pe.oneShot = true
    pe.setAttractor(pa)
    pe.lifetime = 5
    pe.gravity = pa_gravity
    pe.numberOfParticles = particlesCount
    pe.birthRate = PARTICLES_BIRTHRATE
    pe.direction = chips_direction.Coord
    pe.directionRandom = 45
    pe.velocity = 5.0
    pe.velocityRandom = 0.5
    pe.particlePrototype = particle

    t.addChild(par_attractor)
    v.addAnimation(pe.animation)

    var chips_node = newNode("Chips_WinParticlesNode")

    chips_node.position = newVector3(0,0,0)
    chips_node.addChild(par_emitter)
    chips_node.addChild(par_attractor)

    parent.addChild(chips_node)

    # v.setTimeout delay_to_remove, proc()=
    pe.animation.onComplete do():
        chips_node.removeFromParent()

    result = pe

proc onCollideAnimation(n: Node, dur: float): Animation =
    result = n.animationNamed("onChipsCollideAnim")
    if result.isNil:
        let toNodeScale = n.scale
        result = newAnimation()
        result.loopDuration = dur
        result.numberOfLoops = 1
        result.cancelBehavior = cbJumpToEnd
        result.loopPattern = lpStartToEndToStart
        result.onAnimate = proc(p:float)=
            n.scale = interpolate(toNodeScale, toNodeScale * 1.1, p)

        n.registerAnimation("onChipsCollideAnim", result)

proc particlesAnim(v: GameScene, particle: string, fromNode, toNode, parent: Node, particlesCount:int = 5, oldBalance, newBalance: int64, onCollide: proc() = nil): ParticleEmitter =
    let diff = newBalance - oldBalance
    const balance_anim_dur = 0.15
    let per_particle = diff div particlesCount.int64

    var on_collide_anim = toNode.onCollideAnimation(balance_anim_dur)

    var curBalance = oldBalance
    var curParticle = 0
    if v.notificationCenter.isNil:
        return

    v.notificationCenter.postNotification(particle.toUpperAscii() & "_PARTICLE_ANIMATION_STARTED", newVariant((oldBalance, newBalance)))
    result = v.runParticlesAnimation(particle, parent, fromNode, toNode, particlesCount, proc()=
        inc curParticle
        on_collide_anim.cancel()
        v.addAnimation(on_collide_anim)
        var nb = if curBalance + per_particle > newBalance: newBalance
                                                            else: curBalance + per_particle

        if particlesCount == curParticle:
            nb = newBalance
            v.sound_manager.sendEvent("COMMON_" & particle.toUpperAscii() & "_COUNTUP_END")

        curBalance = nb
        if not onCollide.isNil:
            onCollide()
        )

    v.sound_manager.sendEvent("COMMON_" & particle.toUpperAscii() & "_COUNTUP")
    for i in 1 ..< particlesCount:
        closureScope:
            let index = i
            v.setTimeout 0.25 * index.float, proc()=
                v.sound_manager.sendEvent("COMMON_" & particle.toUpperAscii() & "_COUNTUP")


proc chipsAnim*(v: GameScene, fromNode, toNode, parent: Node, particlesCount:int = 5, oldBalance, newBalance: int64, onCollide: proc() = nil): ParticleEmitter {.discardable.} =
    result = v.particlesAnim("chips", fromNode, toNode, parent, particlesCount, oldBalance, newBalance, onCollide)

proc partsAnim*(v: GameScene, fromNode, toNode, parent: Node, particlesCount:int = 5, oldBalance, newBalance: int64, onCollide: proc() = nil): ParticleEmitter {.discardable.} =
    result = v.particlesAnim("parts", fromNode, toNode, parent, particlesCount, oldBalance, newBalance, onCollide)

proc bucksAnim*(v: GameScene, fromNode, toNode, parent: Node, particlesCount:int = 5, oldBalance, newBalance: int64, onCollide: proc() = nil): ParticleEmitter {.discardable.} =
    result = v.particlesAnim("bucks", fromNode, toNode, parent, particlesCount, oldBalance, newBalance, onCollide)

proc cityPointsAnim*(v: GameScene, fromNode, toNode, parent: Node, particlesCount:int = 5, oldBalance, newBalance: int64, onCollide: proc() = nil): ParticleEmitter {.discardable.} =
    result = v.particlesAnim("citypoints", fromNode, toNode, parent, particlesCount, oldBalance, newBalance, onCollide)

proc tournamentPointsAnim*(v: GameScene, fromNode, toNode, parent: Node, particlesCount:int, oldBalance, newBalance: int64, onCollide: proc() = nil): ParticleEmitter {.discardable.} =
    result = v.particlesAnim("tournament_points", fromNode, toNode, parent, particlesCount, oldBalance, newBalance, onCollide)

## CONSOLE COMMANDS FOR TESTING
proc parseParticleAnim(particle: string, args: seq[string]): string =
    result = ""
    if args.len != 4:
        result = "Invalid args"
    else:
        let scene = currentDirector().currentScene
        let fromNode = scene.rootNode.findNode(args[0])
        if fromNode.isNil:
            result = "from node not found"

        let toNode = scene.rootNode.findNode(args[1])
        if toNode.isNil:
            result = "to node not found"


        let parentNode = scene.rootNode.findNode(args[2])
        if parentNode.isNil:
            result = "parent node not found"

        var particles = 0
        try:
            particles = parseInt(args[3])
        except:
            result = "incorect amount val"

        if result.len > 0:
            return
        result = $args
        discard scene.particlesAnim(particle, fromNode, toNode, parentNode, particles, oldBalance = 0, newBalance = 100)

proc chipsAnimation(args: seq[string]): string=
    result = parseParticleAnim("chips", args)

registerConsoleComand(chipsAnimation, "chipsAnimation(fronNode, toNode, parentNode: string, amount: int)")

proc partsAnimation(args: seq[string]): string=
    result = parseParticleAnim("parts", args)

registerConsoleComand(partsAnimation, "partsAnimation(fronNode, toNode, parentNode: string, amount: int)")

proc bucksAnimation(args: seq[string]): string=
    result = parseParticleAnim("bucks", args)

registerConsoleComand(bucksAnimation, "bucksAnimation(fronNode, toNode, parentNode: string, amount: int)")

proc citypointsAnimation(args: seq[string]): string=
    result = parseParticleAnim("citypoints", args)

registerConsoleComand(citypointsAnimation, "citypointsAnimation(fronNode, toNode, parentNode: string, amount: int)")


