import nimx.types
import nimx.animation
import rod.node
import rod.component
import rod.component.tint
import core.slot.base_slot_machine_view

proc colorize(n: Node, mode: GameStage) =
    let newTint = Tint.new()
    let anim = newAnimation()
    var oldTint = n.getComponent(Tint)

    case mode:
    of GameStage.FreeSpin:
        newTint.white = newColor(0.89708429574966, 0.28134179115295, 0.04707960784435, 1.0)
        newTint.black = newColor(0.89708429574966, 0.36482000350952, 0.04707960784435, 1.0)
        newTint.amount = 1.0
    of GameStage.Respin:
        newTint.white = newColor(0.38987603783607, 0.87089508771896, 0.0, 1.0)
        newTint.black = newColor(0.79737943410873, 0.98874682188034, 0.02599562704563, 1.0)
        newTint.amount = 1.0
    of GameStage.Spin:
        newTint.white = newColor(0.0, 0.0, 0.0, 0.0)
        newTint.black = newColor(0.0, 0.0, 0.0, 0.0)
        newTint.amount = 0.0
    else:
        discard

    if oldTint.isNil:
        oldTint = Tint.new()
        n.setComponent("Tint", oldTint)

    anim.numberOfLoops = 1
    anim.loopDuration = 3.0
    anim.onAnimate = proc(p: float)=
        n.getComponent(Tint).white = interpolate(oldTint.white, newTint.white, p)
        n.getComponent(Tint).black = interpolate(oldTint.black, newTint.black, p)
        n.getComponent(Tint).amount = interpolate(oldTint.amount, newTint.amount, p)
    n.addAnimation(anim)

proc colorizePlates*(n: Node, mode: GameStage) =
    for i in 1..NUMBER_OF_REELS:
        let plate = n.findNode("ufo" & $i)

        plate.findNode("add" & $i & ".png").colorize(mode)
        plate.findNode("ray3.png").colorize(mode)
        plate.findNode("luchi" & $i & ".png").colorize(mode)
        plate.findNode("circle" & $i & "_1f.png").colorize(mode)
        plate.findNode("circle" & $i & "_2f.png").colorize(mode)
        plate.findNode("circle" & $i & "_3f.png").colorize(mode)
        plate.findNode("circle" & $i & "_1b.png").colorize(mode)
        plate.findNode("circle" & $i & "_2b.png").colorize(mode)
        plate.findNode("circle" & $i & "_3b.png").colorize(mode)

