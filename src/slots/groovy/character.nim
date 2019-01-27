## The sole purpose of this module is to gather everything related to
## ``Character`` entity in one place. You can have zero or many characters on
## you scene, just keep references so you can call character procs:
##
## .. code-block:: Nim
##   var chars: seq[Character] = @[]
##   var parent: Node = newNode("anchor")
##   chars.add(newCharacter("res/chars/crab.json", parent))
##
## Every `JSON` character composition must have 3 ``Animation`` markers
## (`intro`, `spin`, `win`) as every slot has welcoming, spinning and winning
## animation. This is done for easy slot re-skinning.

import nimx.animation

import rod.node
import rod.component.ae_composition

import node_proxy.proxy

import utils.helpers

nodeProxy CharacterProxy:
    displayComp AEComposition {onNode: node}

    intro* Animation {withValue: np.displayComp.compositionNamed("intro")}
    spin* Animation {withValue: np.displayComp.compositionNamed("spin")}:
        numberOfLoops = -1
    land* Animation {withValue: np.displayComp.compositionNamed("land")}
    win* Animation {withValue: np.displayComp.compositionNamed("win")}

nodeProxy BarSevenProxy:
    displayComp AEComposition {onNode: node}

    barOne* Animation {withValue: np.displayComp.compositionNamed("bar_one")}
    barTwo* Animation {withValue: np.displayComp.compositionNamed("bar_two")}
    sevenOne* Animation {withValue: np.displayComp.compositionNamed("seven_one")}
    sevenTwo* Animation {withValue: np.displayComp.compositionNamed("seven_two")}
    sevenThree* Animation {withValue: np.displayComp.compositionNamed("seven_three")}

type Character* = ref object of RootObj
    ## Entity that encapsulates all character related procs.
    proxy: CharacterProxy
    barSeven: BarSevenProxy


proc rootNode*(c: Character): Node =
    c.proxy.node

proc playBarZeroIdle*(c: Character)
proc playBarOneIdle*(c: Character)
proc playBarTwoIdle*(c: Character)
proc playSevenZeroIdle*(c: Character)
proc playSevenOneIdle*(c: Character)
proc playSevenTwoIdle*(c: Character)
proc playSevenThreeIdle*(c: Character)

proc `barSevenAlpha=`*(c: Character, v: float) =
    c.barSeven.node.alpha = v

proc addBarSeven(c: Character, path: string, parent: Node) =
    c.barSeven = new(
        BarSevenProxy,
        newLocalizedNodeWithResource(path)
    )
    parent.addChild(c.barSeven.node)

    c.barSeven.barOne.onComplete do():
        c.playBarOneIdle()
    c.barSeven.barTwo.onComplete do():
        c.playBarTwoIdle()
    c.barSeven.sevenOne.onComplete do():
        c.playSevenOneIdle()
    c.barSeven.sevenTwo.onComplete do():
        c.playSevenTwoIdle()
    c.barSeven.sevenThree.onComplete do():
        c.playSevenThreeIdle()
    c.proxy.intro.onComplete do():
        c.barSevenAlpha = 1.0
    c.proxy.land.onComplete do():
        c.barSevenAlpha = 1.0
    c.proxy.win.onComplete do():
        c.barSevenAlpha = 1.0

proc newCharacter*(path: string, parent: Node): Character =
    ## Creates ``Character`` instance from ``path`` (must be valid ``*.jcomp``
    ## file) and adds it node as child of ``parent``.
    result = Character.new()
    result.proxy = new(
        CharacterProxy,
        newLocalizedNodeWithResource(path)
    )
    parent.addChild(result.proxy.node)
    result.addBarSeven(
        "slots/groovy_slot/background/comps/bar_777.json",
        result.proxy.node.findNode("tablo")
    )

proc playIntroAnimation*(c: Character) =
    ## Starts animation named ``intro``.
    c.barSevenAlpha = 0.0
    c.rootNode.addAnimation(c.proxy.intro)

proc playSpinAnimation*(c: Character) =
    ## Starts animation named ``spin``
    c.barSevenAlpha = 0.5
    c.rootNode.addAnimation(c.proxy.spin)

proc playLandAnimation*(c: Character) =
    ## Starts animation named ``land``
    c.proxy.spin.cancel()
    c.barSevenAlpha = 0.5
    c.rootNode.addAnimation(c.proxy.land)

proc playWinAnimation*(c: Character) =
    ## Starts animation named ``win``
    c.barSevenAlpha = 0.5
    c.rootNode.addAnimation(c.proxy.win)


proc playBarZeroIdle*(c: Character) =
    c.barSeven.barOne.onProgress(0.0)

proc playBarOneIdle*(c: Character) =
    c.barSeven.barTwo.onProgress(0.0)

proc playBarTwoIdle*(c: Character) =
    c.barSeven.barTwo.onProgress(0.25)

proc playBarOneAnimation*(c: Character) =
    ## Starts animation named ``barOne``
    c.barSeven.node.addAnimation(c.barSeven.barOne)

proc playBarTwoAnimation*(c: Character) =
    ## Starts animation named ``barTwo``
    c.barSeven.node.addAnimation(c.barSeven.barTwo)


proc playSevenZeroIdle*(c: Character) =
    c.barSeven.sevenOne.onProgress(0.1)

proc playSevenOneIdle*(c: Character) =
    c.barSeven.sevenTwo.onProgress(0.0)

proc playSevenTwoIdle*(c: Character) =
    c.barSeven.sevenThree.onProgress(0.0)

proc playSevenThreeIdle*(c: Character) =
    c.barSeven.sevenThree.onProgress(0.2)

proc playSevenOneAnimation*(c: Character) =
    ## Starts animation named ``sevenOne``
    c.barSeven.node.addAnimation(c.barSeven.sevenOne)

proc playSevenTwoAnimation*(c: Character) =
    ## Starts animation named ``sevenTwo``
    c.barSeven.node.addAnimation(c.barSeven.sevenTwo)

proc playSevenThreeAnimation*(c: Character) =
    ## Starts animation named ``sevenThree``
    c.barSeven.node.addAnimation(c.barSeven.sevenThree)
