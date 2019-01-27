import strutils

import nimx.matrixes
import nimx.view
import nimx.window
import nimx.animation
import nimx.image
import nimx.timer
import nimx.notification_center

import rod.rod_types
import rod.node
import rod.viewport

import rod.component.particle_emitter
import rod.component.sprite
import rod.component

import utils.helpers
import random

import shared.game_scene

proc createFeatherEmitter(singleImagesNode: Node): Node =
    result = newNode("FeatherEmitter")
    result.position = newVector3(0, -100)
    let pe = result.component(ParticleEmitter)
    pe.lifetime = 3
    pe.gravity = newVector3(0.0, 0.1, 0)
    pe.numberOfParticles = 15
    pe.birthRate = 0.03
    pe.direction = -180.Coord
    pe.directionRandom = 480.0
    pe.velocity = 8.0
    pe.velocityRandom = 0.1

    let pt = newNode()
    let sprite = pt.component(Sprite)
    sprite.images = newSeq[Image](15)

    let numFrames = sprite.images.len

    let c = newComponentWithUpdateProc do():
        let pc = pt.component(particle_emitter.Particle)
        let elapsedLifetime = pc.initialLifetime - pc.remainingLifetime
        sprite.currentFrame = int(elapsedLifetime * 30.0) mod numFrames

    pt.setComponent "_updateParticle", c

    for i in 0 ..< 15:
        sprite.images[i] = singleImagesNode.findNode("Feathers").component(Sprite).images[i]

    pe.particlePrototype = pt

proc createPigeonAnim*(reelNodes: seq[Node], singleImagesNode: Node, v:GameScene, i: int, j:int) =
    let field = reelNodes[i].findNode("Field")
    let cage = field.childNamed($(j + 1)).findNode("symbol")
    let openAnim = cage.animationNamed("open_door")
    let flyAnim = cage.animationNamed("fly")
    let pe = createFeatherEmitter(singleImagesNode)
    let pigeon_back = cage.findNode("pigeon_back")
    let pigeon_front = cage.findNode("pigeon_front")
    let moveAnim = newAnimation()

    moveAnim.numberOfLoops = 1
    moveAnim.loopDuration = 2

    flyAnim.numberOfLoops = - 1
    v.setTimeout 0.2 * i.float(), proc() =
        let pigeonAnchor = cage.newChild()
        pigeonAnchor.reparentTo(v.rootNode)

        v.addAnimation(openAnim)
        openAnim.onComplete do():
            pigeon_front.reparentTo(pigeonAnchor)
            v.addAnimation(moveAnim)
            v.addAnimation(flyAnim)
            pigeon_back.removeFromParent()
            v.addAnimation(pe.component(ParticleEmitter).animation)
            cage.addChild(pe)
        var rnd = rand(300)
        if i > 2:
            rnd *= -1

        let oldTranslation = pigeonAnchor.position
        let newTanslation = oldTranslation + newVector3(Coord(rnd), Coord(- 2000.0))
        let oldFeathersTranslation = pe.position
        let newFeathersTanslation = oldTranslation + newVector3(Coord(rnd), Coord(- 200.0))

        moveAnim.onAnimate = proc(p: float) =
            pigeonAnchor.position = interpolate(oldTranslation, newTanslation, p)
            pe.position = interpolate(oldFeathersTranslation, newFeathersTanslation, p)
            let scaleFactor = 1.0 + (1.5 * p)
            pigeonAnchor.scale = newVector3(scaleFactor, scaleFactor, 1.0)

        moveAnim.onComplete do():
            pe.component(ParticleEmitter).stop()
            pigeonAnchor.removeFromParent()
            v.notificationCenter.postNotification("mime_play_win_anim")
