import nimx.view, nimx.context, nimx.animation, nimx.window, nimx.timer
import rod.rod_types, rod.node, rod.viewport

import core.slot.base_slot_machine_view
import utils.sound_manager
import utils.helpers
import math, random

const SYMBOLS_COUNT = 10

proc showSymbolInPlace(parent: Node, num: int64) =
    for i in 0..9:
        parent.findNode("win" & $i).alpha = 0
    parent.findNode("win" & $num).alpha = 1

proc createCandyLineNumbers*(v: BaseMachineView, parent: Node, number: int64, speedUp: bool = false): Node =
    result = newLocalizedNodeWithResource("slots/candy_slot/slot/line_numbers.json")

    let mainAnim = result.animationNamed("play")
    let drops = result.findNode("drops_line_numbers")
    let dropsAnim = drops.animationNamed("play")
    let symbols = defineCountSymbols(number, SYMBOLS_COUNT)
    var power = (symbols.symbolsCount - 1).float
    var num = number

    if speedUp:
        mainAnim.loopDuration = mainAnim.loopDuration * 2
    var invisible: seq[int] = @[]
    for i in 1..8:
        invisible.add(rand(9..20))

    if not speedUp:
        for i in 1..20:
            let drop = drops.findNode("drop_" & $i)
            let randDrop = rand(1..8)

            if invisible.contains(i):
                drop.removeFromParent()
            if i < 11:
                for j in 1..8:
                    let dropBrown = drop.findNode("drop_brown_" & $j)
                    dropBrown.alpha = 0
                drop.findNode("drop_brown_" & $randDrop).alpha = 1
    for i in 1..SYMBOLS_COUNT:
        let sym = result.findNode("win_number_" & $i)

        if i < symbols.firstSymbol or i >= symbols.firstSymbol + symbols.symbolsCount:
            sym.removeFromParent()
        else:
            showSymbolInPlace(sym, num div pow(10, power).int64)
            num = num mod pow(10, power).int64
            power -= 1
    mainAnim.addLoopProgressHandler 0.2, false, proc() =
        v.soundManager.playSFX("slots/candy_slot/candy_sound/candy_chocolate_points_splash")
    v.addAnimation(mainAnim)
    v.addAnimation(dropsAnim)
    parent.addChild(result)
