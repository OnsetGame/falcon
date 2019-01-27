import rod.node
import rod.viewport
import rod.component
import rod.component.text_component

import nimx.animation
import nimx.matrixes

import shared.gui.gui_module
import shared.gui.gui_module_types

import strutils

type BonusGamePanel* = ref object of GUIModule
    winTextNode*: Node
    countText*: Text
    winAnim: Animation

proc createBonusGamePanel*(parent: Node, pos: Vector3): BonusGamePanel =
    result.new()
    result.rootNode = newLocalizedNodeWithResource("common/gui/precomps/total_win_panel_big.json")
    parent.addChild(result.rootNode)
    result.rootNode.position = pos
    result.moduleType = mtWinPanel
    result.countText = result.rootNode.findNode("win").component(Text)
    result.winTextNode = result.rootNode.findNode("win")

proc currentWin(t: Text): int64 =
    try: result = t.text.replace(",", "").parseBiggestInt().int64  # this is dirty hack and should be redone
    except ValueError: discard

proc animateWin(wp: BonusGamePanel, to: int64, t: Text)=
    let start: int64 = t.currentWin()
    wp.winAnim = newAnimation()
    wp.winAnim.cancelBehavior = cbJumpToEnd
    wp.winAnim.numberOfLoops = 1
    wp.winAnim.loopDuration = 1.0
    wp.winAnim.onAnimate = proc(p: float)=
        t.text = formatThousands(interpolate(start, to, p))
    wp.rootNode.addAnimation(wp.winAnim)

proc setBonusGameWin*(wp: BonusGamePanel, to: int64, withAnim: bool = false) =
    if withAnim:
        if not wp.winAnim.isNil and not wp.winAnim.finished:
            wp.winAnim.onComplete do():
                wp.animateWin(to, wp.countText)
            wp.winAnim.cancel()
        else:
            wp.animateWin(to, wp.countText)
    else:
        if not wp.winAnim.isNil and not wp.winAnim.finished:
            wp.winAnim.onComplete do():
                wp.countText.text = if to > 0'i64: formatThousands(to)
                                                  else: " "

            wp.winAnim.cancel()
        else:
            wp.countText.text = if to > 0'i64: formatThousands(to)
                                          else: " "

template show*(wp: BonusGamePanel) =
    wp.rootNode.alpha = 1.0

template hide*(wp: BonusGamePanel) =
    wp.rootNode.alpha = 0.0

proc text*(wp: BonusGamePanel, text: string) =
    wp.winTextNode.component(Text).text = text
