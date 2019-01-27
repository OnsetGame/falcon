import rod.node
import rod.viewport
import rod.component.color_balance_hls
import nimx.animation
import nimx.matrixes
import witch_slot_view
import random
import utils.sound_manager

proc playWitchRuneEffect*(v: WitchSlotView, cFrom, cTo: RuneColor) =
    for c in v.witch.findNode("magic_rune").children:
        c.removeComponent(ColorBalanceHLS)

    proc colorize(color: RuneColor, isAfter: bool) =
        var right = v.witch.findNode("magic_rune_smoke_right_before")
        var left = v.witch.findNode("magic_rune_smoke_left_before")
        var light = v.witch.findNode("magic_rune_light_before")

        if isAfter:
            right = v.witch.findNode("magic_rune_smoke_right_after")
            left = v.witch.findNode("magic_rune_smoke_left_after")
            light = v.witch.findNode("magic_rune_light_after")

        let effectSmoke = ColorBalanceHLS.new()
        let effectLight = ColorBalanceHLS.new()

        case color
        of RuneColor.Red:
            effectLight.hue = 0.536
            effectLight.saturation = 1.0
            effectLight.lightness = -0.18

            effectSmoke.hue = 0.0
            effectSmoke.saturation = 0.0
            effectSmoke.lightness = 0.0
        of RuneColor.Blue:
            effectLight.hue = 0.0
            effectLight.saturation = 0.0
            effectLight.lightness = 0.0

            effectSmoke.hue = 0.494
            effectSmoke.saturation = 0.42
            effectSmoke.lightness = 0.0
        of RuneColor.Green:
            effectLight.hue = -0.086
            effectLight.saturation = 1.0
            effectLight.lightness = -0.09

            effectSmoke.hue = -0.23
            effectSmoke.saturation = 0.0
            effectSmoke.lightness = 0.0
        of RuneColor.Yellow:
            effectLight.hue = -0.313
            effectLight.saturation = 1.0
            effectLight.lightness = -0.22

            effectSmoke.hue = -0.336
            effectSmoke.saturation = 0.0
            effectSmoke.lightness = 0.0

        right.setComponent("ColorBalanceHLS", effectSmoke)
        left.setComponent("ColorBalanceHLS", effectSmoke)
        light.setComponent("ColorBalanceHLS", effectLight)

    colorize(cFrom, false)
    colorize(cTo, true)


proc playAnim*(v: WitchSlotView, a: WitchAnimation, returnToIdle: WitchReturn = WitchReturn.Idle): Animation {.discardable.} =
    var name: string

    case a
    of WitchAnimation.Spin..WitchAnimation.PotReady:
        name = "witch_spin"
    of WitchAnimation.Idle..WitchAnimation.FreeSpinsIdle:
        name = "free_spins_idle"

        for i in 1..8:
            v.witch.findNode("color_" & $i).enabled = a == WitchAnimation.FreeSpinsIdle
    of WitchAnimation.MagicSpin..WitchAnimation.RuneEffect:
        name = "magic_rune"
    of WitchAnimation.Win:
        name = "witch_win"
        v.soundManager.sendEvent("WITCH_CLAPPING")
    of WitchAnimation.FreeSpinsIn..WitchAnimation.FreeSpinsWin:
        name = "free_spin_in"
    of WitchAnimation.FreeSpinsSpin:
        name = "spin_fs"
    of WitchAnimation.BonusEnter:
        name = "witch_bonus"
    of WitchAnimation.InOut:
        name = "witch_in_out"

    let animFirst = v.witch.animationNamed(name)
    result = v.witch.findNode(name).animationNamed("play")

    v.witch.animationNamed("free_spins_idle").cancel()
    v.witch.findNode("free_spins_idle").animationNamed("play").cancel()
    if name == "free_spins_idle":
        animFirst.numberOfLoops = -1
        result.numberOfLoops = -1
    else:
        result.onComplete do():
            if returnToIdle == WitchReturn.Idle:
                v.playAnim(WitchAnimation.Idle)
            elif returnToIdle == WitchReturn.FreespinIdle:
                v.playAnim(WitchAnimation.FreeSpinsIdle)

    v.currWitchAnimType = a
    v.currWitchAnim = result

    v.addAnimation(animFirst)
    v.addAnimation(result)

    if a == WitchAnimation.InOut:
        v.addAnimation(v.witch.findNode("witch_out").animationNamed("play"))
        result.addLoopProgressHandler 0.56, false, proc() =
            v.addAnimation(v.witch.findNode("witch_in").animationNamed("play"))


proc startIdle*(v: WitchSlotView) =
    if v.fsStatus == FreespinStatus.Yes:
        v.playAnim(WitchAnimation.FreeSpinsIn, WitchReturn.FreespinIdle)
    else:
        v.playAnim(WitchAnimation.Idle)

proc changeWitchPos*(v: WitchSlotView) =
    let anim = v.playAnim(WitchAnimation.InOut)

    if v.witchPos == 0:
        v.witchPos = 1
    else:
        v.witchPos = 0
    anim.addLoopProgressHandler 0.5, false, proc() =
        v.witch.position = WITCH_POS[v.witchPos]

    v.soundManager.sendEvent("WITCH_IN_OUT")

proc createWitch*(v: WitchSlotView) =
    var parent = newNode("witch_parent")

    v.rootNode.findNode("parent_pots").addChild(parent)
    v.witch = newNodeWithResource("slots/witch_slot/witch/precomps/witch_anim.json")
    v.witchPos = rand(WITCH_POS.high)
    v.witch.position = WITCH_POS[v.witchPos]
    parent.addChild(v.witch)
    v.startIdle()
