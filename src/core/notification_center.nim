import logging
import rod / node
import nimx / notification_center
export notification_center

import shared / game_scene


var lcn: NotificationCenter = nil

proc currentNotificationCenter*(): NotificationCenter {.deprecated.} =
    ## **Deprecated:** Use **node.addObserver/node.postNotification** or **GameEvents** instead.
    lcn

proc setCurrentNotificationCenter*(nc: NotificationCenter) =
    lcn = nc


proc addObserver*(n: Node, name: string, observerId: ref, action: proc(args: Variant)) =
    if GameScene(n.sceneView).notificationCenter.isNil:
        sharedNotificationCenter().addObserver("DIRECTOR_ON_SCENE_ADD", n) do(args: Variant):
            sharedNotificationCenter().removeObserver("DIRECTOR_ON_SCENE_ADD", n)
            if not GameScene(n.sceneView).notificationCenter.isNil:
                GameScene(n.sceneView).notificationCenter.addObserver(name, observerId, action)
            else:
                error "Notification observer `", name, "` has not been setted! Something went wrong."
    else:
        GameScene(n.sceneView).notificationCenter.addObserver(name, observerId, action)

template addObserver*(n: Node, name: string, action: proc(args: Variant)) =
    n.addObserver(name, n, action)

proc removeObserver*(n: Node, name: string, observerId: ref) =
    if not GameScene(n.sceneView).notificationCenter.isNil:
        GameScene(n.sceneView).notificationCenter.removeObserver(name, observerId)

template removeObserver*(n: Node, name: string) =
    n.removeObserver(name, n)


proc postNotification*(n: Node, name: string, args: Variant) =
    if not GameScene(n.sceneView).notificationCenter.isNil:
        GameScene(n.sceneView).notificationCenter.postNotification(name, args)