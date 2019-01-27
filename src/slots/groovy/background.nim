import strutils

import nimx.animation

import rod / [ node, component ]
import rod.component / [ ae_composition, text_component ]

import node_proxy.proxy
import utils.helpers

import character

nodeProxy BackgroundProxy:
    characters* Node {addTo: node}

    infoPanel* Node {withName: "info_panel"}
    infoText* Text {onNode: np.infoPanel.findNode("info_text")}
    infoPanelComp AEComposition {onNode: infoPanel}
    textSlide* Animation {withValue: np.infoPanelComp.compositionNamed("text_slide")}

    lightBulbs* Node {withName: "light_bulbs"}:
        alpha = 0.0
    lightBulbsComp AEComposition {onNode: lightBulbs}
    wave* Animation {withValue: np.lightBulbsComp.compositionNamed("wave")}
    waveIdle* Animation {withValue: np.lightBulbsComp.compositionNamed("idle")}:
        numberOfLoops = -1
        cancelBehavior = cbJumpToEnd

nodeProxy TopLights:
    intro* Animation {withKey: "intro"}
    spin* Animation {withKey: "spin"}:
        numberOfLoops = -1
        cancelBehavior = cbJumpToEnd
    win* Animation {withKey: "win"}
    idle* Animation {withKey: "idle"}:
        numberOfLoops = -1
        cancelBehavior = cbJumpToEnd

nodeProxy CameraShaker:
    slot* Node {withName: "slot"}
    shakeComp AEComposition {onNode: node}
    shake* Animation {withValue: np.shakeComp.compositionNamed("shake")}

type Background* = ref object of RootObj
    scene: BackgroundProxy
    characters*: seq[Character]
    topLights*: TopLights
    cameraShaker*: CameraShaker


proc rootNode*(b: Background): Node =
    b.scene.node

proc left*(b: Background): Character =
    b.characters[0]

proc right*(b: Background): Character =
    b.characters[1]

proc infoPanel*(b: Background): Node =
    b.scene.infoPanel

proc infoPanelAnim*(b: Background): Animation =
    b.scene.textSlide

proc newBackground*(path: string, parent: Node): Background =
    result = Background.new()
    result.scene = new(
        BackgroundProxy,
        newLocalizedNodeWithResource(path)
    )
    result.characters = @[]
    parent.addChild(result.scene.node)

proc addCharacter*(b: Background, path: string): Character {.discardable.} =
    result = newCharacter(path, b.scene.characters)
    b.characters.add(result)

proc addCharacters*(b: Background, pathSeq: seq[string]) =
    for path in pathSeq:
        b.addCharacter(path)

proc addTopLights*(b: Background, path: string, parent: Node) =
    b.topLights = new(TopLights, newLocalizedNodeWithResource(path))
    b.topLights.node.translateY = 47.0
    parent.addChild(b.topLights.node)

proc addCameraShaker*(b: Background, path: string, parent: Node) =
    b.cameraShaker = new(CameraShaker, newLocalizedNodeWithResource(path))
    parent.addChild(b.cameraShaker.node)

proc addCameraShaker*(b: Background, shaker: CameraShaker) =
    b.cameraShaker = shaker

proc playWaveAnimation*(bg: Background, waveId: int = 0) =
    bg.scene.lightBulbs.alpha = 1.0
    bg.scene.lightBulbs.addAnimation(bg.scene.wave)

proc playWaveIdleAnimation*(bg: Background) =
    if bg.scene.waveIdle.pauseTime == 0:
        bg.scene.lightBulbs.addAnimation(bg.scene.waveIdle)
    else:
        bg.scene.waveIdle.resume()

proc playInfoPanelTextAnimation*(bg: Background, text: string = "") =
    if text.len > 0:
        bg.scene.infoText.text = text
        bg.scene.infoPanel.addAnimation(bg.scene.textSlide)

proc playIdleAnimation*(bg: Background)
proc cancelIdleAnimation*(bg: Background)

proc playIntroAnimation*(bg: Background) =
    bg.scene.node.addAnimation(bg.topLights.intro)
    bg.playWaveAnimation()
    for c in bg.characters:
        c.playIntroAnimation()

proc playSpinAnimation*(bg: Background) =
    # bg.scene.node.addAnimation(bg.topLights.spin)
    for c in bg.characters:
        c.playSpinAnimation()

proc playLandAnimation*(bg: Background) =
    bg.topLights.spin.cancel()
    for c in bg.characters:
        c.playLandAnimation()

proc playWinAnimation*(bg: Background, text: string = "") =
    bg.scene.node.addAnimation(bg.topLights.win)
    bg.playWaveAnimation()
    bg.playInfoPanelTextAnimation(text)

    for c in bg.characters:
        c.playWinAnimation()

proc playIdleAnimation*(bg: Background) =
    bg.scene.node.addAnimation(bg.topLights.idle)
    bg.playWaveIdleAnimation()

proc cancelIdleAnimation*(bg: Background) =
    bg.topLights.idle.cancel()
    bg.scene.waveIdle.pause()

proc shakeCamera*(bg: Background) =
    bg.cameraShaker.node.addAnimation(bg.cameraShaker.shake)

proc useWaveOnly*(bg: Background, waveId: int) =
    let waveToKeep = "flare_wave " & $waveId
    let idleWave = "flare_wave_bg"
    var lb = bg.scene.lightBulbs
    var i = 0
    var l = lb.children.len

    while i < l:
        let c = lb.children[i]

        if startsWith(c.name, waveToKeep) or startsWith(c.name, idleWave):
            i.inc()
        else:
            c.removeFromParent()
            l = lb.children.len
