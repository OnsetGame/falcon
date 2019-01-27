import rod / node
import rod / component
import rod / component / sprite
import nimx / [animation, matrixes]
import utils / helpers


type LoaderComponent* = ref object of Component
    spinner: Node
    spin: Animation


method componentNodeWasAddedToSceneView*(c: LoaderComponent) =
    c.spinner = newNodeWithResource("common/lib/precomps/loading")
    c.spinner.anchor = newVector3(64, 64)
    c.spinner.position = c.node.anchor
    c.node.addChild(c.spinner)
    c.spin = c.spinner.animationNamed("spin")
    c.spin.numberOfLoops = -1
    c.node.addAnimation(c.spin)


method componentNodeWillBeRemovedFromSceneView*(c: LoaderComponent) =
    if not c.spin.isNil:
        c.spin.cancel()
    if not c.spinner.isNil:
        c.spinner.removeFromParent()


registerComponent(LoaderComponent, "Falcon")