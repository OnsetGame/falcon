import rod.node

import nimx.matrixes

import gui_module
import gui_pack
import gui_module_types

type BalloonFreeSpinsModule* = ref object of GUIModule

proc createBalloonFreeSpins*(parent: Node): BalloonFreeSpinsModule =
    result.new()
    result.rootNode = newLocalizedNodeWithResource("common/gui/precomps/balloon_free_spins.json")
    parent.addChild(result.rootNode)
    result.moduleType = mtBalloonFreeSpins
