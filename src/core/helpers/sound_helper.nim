import rod / node
import shared / game_scene
import utils / sound_manager


proc playSound*(node: Node, sound: string) =
    node.sceneView.GameScene.soundManager.sendEvent(sound)