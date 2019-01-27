import nimx.view
import nimx.animation
import nimx.matrixes
import nimx.timer

import rod.node
import rod.viewport
import rod.component
import rod.component.particle_system

import core.slot.base_slot_machine_view

import utils.helpers

type Point = tuple[x: float, y: float]

proc initLines(): seq[seq[Point]] =
    result = @[]
    result.add(@[(350.0, 440.0), (1575.0, 440.0)]) #0
    result.add(@[(350.0, 240.0), (1575.0, 240.0)]) #1
    result.add(@[(350.0, 660.0), (1575.0, 660.0)]) #2
    result.add(@[(400.0, 160.0), (970.0, 690.0), (1530.0, 160.0)]) #3
    result.add(@[(400.0, 730.0), (970.0, 220.0), (1530.0, 730.0)]) #4
    result.add(@[(460.0, 440.0), (730.0, 240.0), (1220.0, 660.0), (1575.0, 400.0)]) #5
    result.add(@[(460.0, 440.0), (730.0, 660.0), (1220.0, 240.0), (1575.0, 500.0)]) #6
    result.add(@[(400.0, 240.0), (730.0, 240.0), (1220.0, 660.0), (1540.0, 660.0)]) #7
    result.add(@[(400.0, 660.0), (730.0, 660.0), (1220.0, 240.0), (1540.0, 220.0)]) #8
    result.add(@[(460.0, 240.0), (730.0, 440.0), (970.0, 240.0), (1220.0, 440.0), (1500.0, 160.0)]) #9
    result.add(@[(400.0, 730.0), (730.0, 440.0), (970.0, 660.0), (1220.0, 440.0), (1530.0, 750.0)]) #10
    result.add(@[(460.0, 500.0), (710.0, 240.0), (1230.0, 240.0), (1520.0, 500.0)]) #11
    result.add(@[(460.0, 440.0), (710.0, 660.0), (1230.0, 660.0), (1500.0, 440.0)]) #12
    result.add(@[(460.0, 200.0), (730.0, 460.0), (1260.0, 460.0), (1470.0, 200.0)]) #13
    result.add(@[(460.0, 750.0), (730.0, 460.0), (1230.0, 460.0), (1470.0, 750.0)]) #14
    result.add(@[(370.0, 440.0), (730.0, 440.0), (970.0, 240.0), (1220.0, 440.0), (1585.0, 440.0)]) #15
    result.add(@[(370.0, 440.0), (730.0, 440.0), (970.0, 690.0), (1220.0, 440.0), (1585.0, 440.0)]) #16
    result.add(@[(460.0, 240.0), (730.0, 690.0), (970.0, 240.0), (1220.0, 690.0), (1530.0, 160.0)]) #17
    result.add(@[(460.0, 690.0), (730.0, 240.0), (970.0, 690.0), (1220.0, 240.0), (1500.0, 750.0)]) #18
    result.add(@[(460.0, 730.0), (730.0, 240.0), (970.0, 460.0), (1220.0, 240.0), (1500.0, 750.0)]) #19


proc moveEmitter(node: Node, duration: float, start, to: Point): Animation {.discardable.} =
    let s = newVector3(start.x, start.y)
    let t = newVector3(to.x, to.y)

    result = newAnimation()
    result.loopDuration = duration
    result.numberOfLoops = 1
    result.onAnimate = proc(p: float) =
        node.position = interpolate(s, t, p)
    if not node.sceneView().isNil and not result.isNil:
        node.sceneView().addAnimation(result)

proc startWinningLine(v: BaseMachineView, node: Node, duration: float, lineNumber: int, lines: seq[seq[Point]]) =
    let d = duration / (lines[lineNumber].len - 1).float
    let curLine = lines[lineNumber]

    for c in node.children:
        let emitter = c.component(ParticleSystem)
        emitter.start()

    for i in 0..<curLine.len - 1:
        closureScope:
            let index = i
            v.setTimeout index.float * d, proc() =
                moveEmitter(node, d, curLine[index], curLine[index + 1])
    v.setTimeout duration, proc() =
        for c in node.children:
            let emitter = c.component(ParticleSystem)
            emitter.stop()
    setTimeout duration + 2.5, proc() =
        node.removeFromParent()


proc createCandyWinningLine*(v: BaseMachineView, rootNode: Node, duration: float, lineNumber: int) =
    let node = newLocalizedNodeWithResource("slots/candy_slot/particles/win_line.json")
    let lines = initLines()

    rootNode.addChild(node)
    startWinningLine(v, node, duration, lineNumber, lines)
