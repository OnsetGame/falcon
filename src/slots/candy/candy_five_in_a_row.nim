import rod.node
import rod.viewport
import nimx.view
import nimx.animation
import utils.fade_animation
import utils.sound_manager
import shared.game_scene

proc showFiveInARow*(parent: Node): Animation {.discardable.} =
    let v = parent.sceneView()
    let root = parent.newChild("parent_five_in_a_row")
    let n = newLocalizedNodeWithResource("slots/candy_slot/five_in_a_row/five_in_a_row.json")
    let fade = addFadeSolidAnim(v, root, blackColor(), VIEWPORT_SIZE, 0.0, 0.5, 1.0)

    result = n.animationNamed("play")
    root.addChild(n)
    parent.addChild(root)
    v.addAnimation(result)
    v.addAnimation(n.childNamed("shadow").findNode("free_spins_lines").animationNamed("play"))
    v.addAnimation(n.childNamed("free_spins_lines").animationNamed("play"))
    v.GameScene.soundManager.sendEvent("CANDY_FIVE_IN_A_ROW")
    result.addLoopProgressHandler 0.8, false, proc() =
        fade.changeFadeAnimMode(0, 0.5)
    result.onComplete do():
        root.removeFromParent()


