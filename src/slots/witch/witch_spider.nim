import rod.node
import rod.viewport
import rod.quaternion
import nimx.animation
import nimx.matrixes
import utils.helpers
import witch_slot_view
import witch_elements
import core.slot.base_slot_machine_view
import utils.sound_manager


type SpitSettings = tuple [
    angle: float,
    delta: Vector3
]

const spitCollection: array[3, array[14, SpitSettings]] = [
    [
        (182.37, newVector3(-480.0, 20.0)), (184.28, newVector3(-190.0, 20.0)), (0.0, newVector3(100.0, 20.0)), (0.0, newVector3(400.0, 20.0)),
        (162.35, newVector3(-480.0, 175.0)), (149.13, newVector3(-210.0, 160.0)), (96.02, newVector3(-40.0, 80.0)), (34.27, newVector3(120.0, 150.0)), (18.98, newVector3(370.0, 170.0)),
        (145.72, newVector3(-510.0, 340.0)), (128.4, newVector3(-250.0, 340.0)), (92.9, newVector3(-40.0, 320.0)), (55.37, newVector3(150.0, 320.0)), (36.48, newVector3(370.0, 340.0))
    ],
    [
        (203.0, newVector3(-480.0, -150.0)), (217.0, newVector3(-210.0, -120.0)), (265.3, newVector3(-40.0, -80.0)), (319.4, newVector3(120.0, -120.0)), (335.1, newVector3(370.0, -150.0)),
        (183.7, newVector3(-480.0, 20.0)), (184.8, newVector3(-210.0, 20.0)), (0.0, newVector3(100.0, 25.0)), (0.0, newVector3(370.0, 25.0)),
        (163.3, newVector3(-510.0, 175.0)), (149.5, newVector3(-210.0, 160.0)), (95.6, newVector3(-35.0, 70.0)), (34.0, newVector3(110.0, 145.0)), (18.0, newVector3(370.0, 160.0))

    ],
    [
        (218.75, newVector3(-510.0, -340.0)), (234.73, newVector3(-250.0, -320.0)), (267.18, newVector3(-40.0, -320.0)), (301.40, newVector3(170.0, -280.0)), (318.75, newVector3(380.0, -320.0)),
        (203.89, newVector3(-480.0, -150.0)), (217.03, newVector3(-250.0, -120.0)), (264.72, newVector3(-40.0, -75.0)), (318.96, newVector3(120.0, -120.0)), (334.06, newVector3(380.0, -140.0)),
        (184.59, newVector3(-480.0, 20.0)), (184.91, newVector3(-190.0, 20.0)), (5.0, newVector3(80.0, 40.0)), (-10.0, newVector3(380.0, 0.0))
    ]
]

proc getSpitSettings(spiderIndex, elementIndex: int): SpitSettings =
    var si = 0

    if spiderIndex == 7:
        si = 1
    elif spiderIndex == 12:
        si = 2

    var ei = elementIndex
    if elementIndex > spiderIndex:
        ei.dec()

    result = spitCollection[si][ei]

proc sendShot(v: WitchSlotView, s: SpitSettings) =
    let shot = newLocalizedNodeWithResource("slots/witch_slot/elements/precomps/spider/shot.json")
    let start = shot.animationNamed("start")
    let spider = v.rootNode.findNode("spider")
    let localRoot = v.rootNode.findNode("root_elements")
    let staticParent = shot.findNode("static_parent")
    let shotParts: seq[Node] = @[shot.findNode("vystrel2.png"), shot.findNode("part_1"), shot.findNode("part_2")]

    spider.findNode("parent_shot").addChild(shot)
    shot.reattach(localRoot)
    staticParent.reattach(localRoot)
    for part in shotParts:
        part.reattach(localRoot)
    start.addLoopProgressHandler 0.4, false, proc() =
        let move = newAnimation()
        let pos = shotParts[1].position

        for part in shotParts:
            part.rotation = newQuaternionFromEulerXYZ(0.0, 0.0, s.angle)

        move.numberOfLoops = 1
        move.loopDuration = 0.25
        move.onAnimate = proc(p: float) =
            for part in shotParts:
                part.position = newVector3(interpolate(pos.x, pos.x + s.delta.x, p), interpolate(pos.y, pos.y + s.delta.y, p))
        v.addAnimation(move)

    v.addAnimation(start)
    start.onComplete do():
        shot.removeFromParent()
        for part in shotParts:
            part.removeFromParent()
        staticParent.removeFromParent()

proc getWild(v: WitchSlotView): WitchElement =
    for elem in v.currentElements:
        if elem.eType == ElementType.Wild:
            return elem

proc spiderSpit*(v: WitchSlotView) =
    let spider = v.getWild()

    if v.isSpider and not spider.isNil and not spider.node.isNil:
        let inside = spider.node.findNode("spider_inside")
        let idle = inside.animationNamed("idle")
        let win = inside.animationNamed("win")

        v.setTimeout 0.2, proc() =
            inside.findNode("glow_wild").enabled = false
            idle.cancel()
            idle.onComplete do():
                v.addAnimation(win)
                v.soundManager.sendEvent("WEB_TRANSFORM")
                win.onComplete do():
                    v.addAnimation(idle)
                    idle.numberOfLoops = -1
                    idle.removeHandlers()
                    v.setTimeout 2.0, proc() =
                        v.gameFlow.nextEvent()

            for elem in v.currentElements:
                closureScope:
                    let e = elem
                    case e.eType
                    of ElementType.Predator..ElementType.Feather:
                        win.addLoopProgressHandler 0.72, false, proc() =
                            v.sendShot(getSpitSettings(spider.index, e.index))
                        win.addLoopProgressHandler 0.85, false, proc() =
                            v.elementToWeb(e.index)
                    else:
                        discard
    else:
        v.gameFlow.nextEvent()

