import rod.node
import rod.viewport
import rod.component
import rod.component.text_component

import nimx.animation
import nimx.matrixes

import gui_module
import gui_module_types

import strutils

type WinPanelModule* = ref object of GUIModule
    winTextNode*: Node
    countText*: Text
    winAnim: Animation

proc createWinPanel*(parent: Node): WinPanelModule =
    result.new()
    result.rootNode = newLocalizedNodeWithResource("common/gui/ui2_0/total_win_panel.json")
    parent.addChild(result.rootNode)
    result.moduleType = mtWinPanel
    result.countText = result.rootNode.findNode("count_text").component(Text)
    result.winTextNode = result.rootNode.findNode("gui_win")

proc currentWinValue(t: Text): int64 =
    try: result = t.text.replace(",", "").parseBiggestInt()  # this is dirty hack and should be redone
    except ValueError: discard

proc formatedWinValue(win: int64): string =
    result = if win > 0: formatThousands(win) else: " "

proc animateWin(wp: WinPanelModule, to: int64, t: Text)=
    let start: int64 = t.currentWinValue()
    wp.winAnim = newAnimation()
    wp.winAnim.cancelBehavior = cbJumpToEnd
    wp.winAnim.numberOfLoops = 1
    wp.winAnim.loopDuration = 0.3
    wp.winAnim.onAnimate = proc(p: float)=
        t.text = formatedWinValue(interpolate(start, to, p))
    wp.winAnim.onComplete do():
        t.text = formatedWinValue(to)
    wp.rootNode.addAnimation(wp.winAnim)

proc setNewWin*(wp: WinPanelModule, to: int64, withAnim: bool = false) =
    if withAnim:
        if not wp.winAnim.isNil and not wp.winAnim.finished:
            wp.winAnim.onComplete do():
                wp.animateWin(to, wp.countText)
            wp.winAnim.cancel()
        else:
            wp.animateWin(to, wp.countText)
    else:
        if not wp.winAnim.isNil and not wp.winAnim.finished:
            wp.winAnim.removeHandlers()
            wp.winAnim.onComplete do():
                wp.countText.text = formatedWinValue(to)

            wp.winAnim.cancel()
        else:
            wp.countText.text = formatedWinValue(to)

proc setWinText*(wp: WinPanelModule, text: string) =
    wp.winTextNode.component(Text).text = text

proc addToWin*(wp: WinPanelModule, newWinAmount: int64, withAnim: bool = false) =
    let cwv = wp.countText.currentWinValue()
    wp.setNewWin(cwv+newWinAmount, withAnim)



