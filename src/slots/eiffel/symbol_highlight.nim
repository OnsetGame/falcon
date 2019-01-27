import rod.component
import rod.viewport
import rod.rod_types
import rod.node
import nimx.animation
import nimx.types
import logging

import utils / [lights_cluster, helpers]

type SymbolHighlightComponent* = ref object of Component
    anim: Animation
    lc: LightsCluster

const symbolWidth = 190
const symbolHeight = 190

method init(s: SymbolHighlightComponent) =
    s.lc = LightsCluster.new()
    const cnt = 42
    s.lc.coords = radialLightsCoords(newPoint(symbolWidth / 2, symbolHeight / 2 + 15), symbolHeight * 0.55, cnt)
    s.lc.intensity = radialDependantIntensityFunction()
    s.lc.count = cnt
    s.anim = s.lc.waveAnimation()
    s.anim.numberOfLoops = -1

method draw(s: SymbolHighlightComponent) =
    let lc = s.lc
    if not lc.isNil: lc.draw()

method componentNodeWasAddedToSceneView*(s: SymbolHighlightComponent) = s.node.addAnimation(s.anim)
method componentNodeWillBeRemovedFromSceneView*(s: SymbolHighlightComponent) = s.anim.cancel()

registerComponent(SymbolHighlightComponent)


type SymbolHighlightController* = ref object
    reelNodes*: seq[Node]

proc setSymbolHighlighted*(v: SymbolHighlightController, n: Node, flag: bool, altMode: bool = false) =
    if n.isNil:
        warn "node not found in setSymbolHighlighted: ", n.name
        return
    if flag:
        let s =  n.component(SymbolHighlightComponent)
        if altMode:
            s.lc.intensity = radialDependantIntensityFunction2()
    else:
        n.removeComponent(SymbolHighlightComponent)

proc clearSymbolHighlights*(v: SymbolHighlightController) =
    for i in 0 ..< v.reelNodes.len:
        var j = 1
        while true:
            let n = v.reelNodes[i].findNode("Field").findNode($j)
            if n.isNil:
                break
            else:
                n.removeComponent(SymbolHighlightComponent)
            inc j
