import rod.node
import rod.viewport
import rod.component
import nimx.matrixes
import nimx.animation
import witch_slot_view
import utils.helpers
import math

const SYMBOLS_COUNT = 10
const SYMBOL_OFFSET = 90

proc showSymbolInPlace(parent: Node, num: int64) =
    for i in 0..9:
        parent.findNode($i & "_black").alpha = 0
    parent.findNode($num & "_black").alpha = 1

proc createWinLineNumbers*(v: WitchSlotView, parent: Node, number: int64, forBonus: bool = false): Node {.discardable.} =
    result = newNodeWithResource("slots/witch_slot/winning_line/precomps/win_line_numbers.json")

    let res = result
    let anim = res.animationNamed("start")
    let symbols = defineCountSymbols(number, SYMBOLS_COUNT)
    var power = (symbols.symbolsCount - 1).float
    var num = number

    if forBonus:
        anim.loopDuration = anim.loopDuration * 2.5

    parent.addChild(res)
    v.addAnimation(anim)
    anim.onComplete do():
        res.removeFromParent()

    res.findNode("numbers_all").removeComponent("ColorBalanceHLS")
    res.findNode("glint").removeComponent("ColorBalanceHLS")

    if forBonus:
        res.findNode("glow_glint.png").removeFromParent()
        res.findNode("glint").positionY = 0.0
    else:
        res.findNode("glow_glint.png").removeComponent("ColorBalanceHLS")


    for i in 1..SYMBOLS_COUNT:
            let sym = res.findNode("numbers_black_" & $i)

            if i < symbols.firstSymbol or i >= symbols.firstSymbol + symbols.symbolsCount:
                sym.removeFromParent()
            else:
                showSymbolInPlace(sym, num div pow(10, power).int64)
                num = num mod pow(10, power).int64
                power -= 1

    if symbols.symbolsCount mod 2 == 0:
        let numbers = res.findNode("numbers_all")
        numbers.position = numbers.position - newVector3(SYMBOL_OFFSET, 0)



