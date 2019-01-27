import node_proxy / proxy
import shared / window / button_component
import nimx / [types, matrixes, animation]
import rod / [rod_types, node]

import core / helpers / hint_helper
import utils / helpers


nodeProxy QuestBalloon:
    showHideAnimation Animation
    hint* Hint

    showAnim Animation {withKey: "show"}:
        cancelBehavior = cbJumpToEnd
    hideAnim Animation {withKey: "hide"}:
        cancelBehavior = cbJumpToEnd

    onAction* proc()
    bttn* ButtonComponent {withValue: np.node.createButtonComponent(nil, newRect(0.0, 0.0, 192.0, 192.0))}:
        enabled = false
        onAction do():
            if np.enabled and not np.onAction.isNil:
                np.onAction()

    isHidden* bool
    enabled bool


method show*(b: QuestBalloon, cb: proc() = nil) {.base.} = 
    if not b.isHidden:
        if not cb.isNil:
            if not b.showHideAnimation.isNil:
                b.showHideAnimation.onComplete(cb)
            else:
                cb()
        return
    b.isHidden = false

    if not b.showHideAnimation.isNil:
        b.showHideAnimation.cancel()
        b.showHideAnimation = nil

    b.enabled = false
    b.node.alpha = 1.0

    b.showAnim.removeHandlers()
    b.showAnim.onComplete() do():
        if not b.showHideAnimation.isNil and not b.showAnim.isCancelled:
            b.showHideAnimation = nil
            b.enabled = true
            if not b.hint.isNil:
                b.hint.show()
        if not cb.isNil:
            cb()

    b.showHideAnimation = b.showAnim
    b.node.addAnimation(b.showAnim)

method hide*(b: QuestBalloon, cb: proc() = nil) {.base.} = 
    if b.isHidden:
        if not cb.isNil:
            cb()
        return
    b.isHidden = true

    if not b.showHideAnimation.isNil:
        b.showHideAnimation.cancel()
        b.showHideAnimation = nil

    b.enabled = false

    b.hideAnim.removeHandlers()
    b.hideAnim.onComplete() do():
        if not b.showHideAnimation.isNil and not b.hideAnim.isCancelled:
            b.showHideAnimation = nil
            if not b.hint.isNil:
                b.hint.setVisible(false)
        if not cb.isNil:
            cb()

    b.showHideAnimation = b.hideAnim
    b.node.addAnimation(b.hideAnim)

proc setVisible*(b: QuestBalloon, visible: bool) =
    b.hide()

    if not b.showHideAnimation.isNil:
        b.showHideAnimation.cancel()
        b.showHideAnimation = nil

proc destroy*(b: QuestBalloon, cb: proc() = nil) =
    b.hide() do():
        b.node.removeFromParent()
        if not cb.isNil:
            cb()