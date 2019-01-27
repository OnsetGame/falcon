import rod.rod_types, rod.node
import nimx.animation

type UfoWinLine* = ref object of RootObj
    nodes:seq[Node]
    animation*:CompositAnimation
    winLine:seq[int16]

proc new*(wl:UfoWinLine, winLine:seq[int16]) =





