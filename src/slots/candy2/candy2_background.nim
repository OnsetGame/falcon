import node_proxy.proxy
import nimx.animation
import utils.helpers
import rod.node

nodeProxy Background:
    move* Animation {withKey: "move"}

nodeProxy ShakeParent:
    shake* Animation {withKey: "shake"}
    shakeNode* Node {withName: "shake_parent"}

proc createBackground*(): Background =
    result = new(Background, newLocalizedNodeWithResource("slots/candy2_slot/background/precomps/back"))

proc createShakeParent*(): ShakeParent =
    result = new(ShakeParent, newLocalizedNodeWithResource("slots/candy2_slot/background/precomps/camera_shake"))
