import nimx.animation
import nimx.types
import rod.node
import rod.viewport
import rod.component
import rod.component.color_balance_hls
import rod.component.tint
import witch_slot_view
import witch_character
import core.slot.base_slot_machine_view
import shared.gui / [ spin_button_module, win_panel_module ]
import utils.pause
import utils.sound_manager
import random

proc startPotLights(v: WitchSlotView, index, activeLights: int) =
    let potTop = v.pots.findNode("top_pot_" & $(index + 1))
    let lightOn = potTop.findNode("light_on_" & $(index + 1))
    let lightOff = potTop.findNode("light_off_" & $(index + 1))

    for i in 1..NUMBER_OF_REELS - 1:
        let isActiveOn = i <= activeLights
        let idleOn = lightOn.findNode("light_idle_" & $i)
        let barrelOn = lightOn.findNode("barrel3_" & $i)
        let barrelOff = lightOff.findNode("barrel3_" & $i)

        idleOn.enabled = isActiveOn
        barrelOn.enabled = isActiveOn
        barrelOff.enabled = not isActiveOn

proc startIdleForPot*(v: WitchSlotView, index: int) =
    let pot = v.pots.findNode("bottom_pot_" & $(index + 1))
    let potAnim = pot.animationNamed("idle")

    v.addAnimation(potAnim)
    v.potIdleAnimsBottom[index] = potAnim
    potAnim.numberOfLoops = -1

proc startIdleForPotTop*(v: WitchSlotView, index: int) =
    let potTop = v.pots.findNode("top_pot_" & $(index + 1))
    let lightOn = potTop.findNode("light_on_" & $(index + 1))
    let lightOnAnim = lightOn.animationNamed("play")
    let potIdleAnim = potTop.animationNamed("idle")

    v.addAnimation(lightOnAnim)
    v.addAnimation(potIdleAnim)
    v.potIdleAnimsTop[index] = potIdleAnim
    lightOnAnim.numberOfLoops = -1
    potIdleAnim.numberOfLoops= -1

proc stopIdleForPot*(v: WitchSlotView, index: int) =
    if not v.potIdleAnimsBottom[index].isNil:
        v.potIdleAnimsBottom[index].cancel()
        v.potIdleAnimsBottom[index] = nil
        v.potIdleAnimsTop[index].cancel()
        v.potIdleAnimsTop[index] = nil

proc fallElementsInPot*(v: WitchSlotView, index: int) =
    let potBottom = v.pots.findNode("bottom_pot_" & $(index + 1))
    let potTop = v.pots.findNode("top_pot_" & $(index + 1))
    let potBottomAnim = potBottom.animationNamed("elements_in_pot")
    let potTopAnim = potTop.animationNamed("elements_in_pot")

    v.addAnimation(potBottomAnim)
    v.addAnimation(potTopAnim)

proc potFreeSpinsIn*(v: WitchSlotView, index: int): Animation {.discardable} =
    let bottom = v.pots.findNode("bottom_pot_" & $(index + 1))
    let top = v.pots.findNode("top_pot_" & $(index + 1))
    let explosionAnim = bottom.findNode("explosion_small").animationNamed("play")
    let topAnim = top.animationNamed("free_spins_in")

    v.stopIdleForPot(index)
    result = bottom.animationNamed("free_spins_in")
    v.addAnimation(result)
    v.addAnimation(topAnim)
    result.addLoopProgressHandler 0.3, true, proc() =
        v.addAnimation(explosionAnim)

proc potFreeSpinsIdle*(v: WitchSlotView, index: int) =
    let bottom = v.pots.findNode("bottom_pot_" & $(index + 1))
    let top = v.pots.findNode("top_pot_" & $(index + 1))
    let bottomAnim = bottom.animationNamed("free_spins_idle")
    let topAnim = top.animationNamed("free_spins_idle")
    let bubblesAnim = bottom.findNode("bubbles_splashes_freespins").animationNamed("play")

    v.addAnimation(bottomAnim)
    v.addAnimation(topAnim)
    v.addAnimation(bubblesAnim)
    v.freeSpinBottomIdleAnims[index] = bottomAnim
    v.freeSpinTopIdleAnims[index] = topAnim
    v.freeSpinIdleBubblesAnims[index] = bubblesAnim
    bottomAnim.numberOfLoops = -1
    topAnim.numberOfLoops = -1
    bubblesAnim.numberOfLoops = -1

proc potsToFreespins*(v: WitchSlotView) =
    proc start(index: int): Animation {.discardable.} =
        result = v.potFreeSpinsIn(index)
        result.onComplete do():
            v.potFreeSpinsIdle(index)
            if index == 2:
                v.slotGUI.spinButtonModule.startFreespins(v.freeSpinsCount)

    let fs = v.pots.findNode("freespins_layer")
    let fsInAnim = fs.animationNamed("in")
    let anim = start(0)

    v.fsRedIdle = fs.animationNamed("idle")
    v.addAnimation(fsInAnim)
    fsInAnim.onComplete do():
        v.addAnimation(v.fsRedIdle)
        v.fsRedIdle.numberOfLoops = -1

    start(4)
    anim.addLoopProgressHandler 0.1, true, proc() =
        start(1)
        start(3)
    anim.addLoopProgressHandler 0.2, true, proc() =
        start(2)

proc potFreeSpinsIdleOut*(v: WitchSlotView, index: int): Animation {.discardable.} =
    let bottom = v.pots.findNode("bottom_pot_" & $(index + 1))
    let top = v.pots.findNode("top_pot_" & $(index + 1))
    let bottomAnim = bottom.animationNamed("free_spins_out")
    let topAnim = top.animationNamed("free_spins_out")

    if not v.freeSpinBottomIdleAnims[index].isNil:
        v.freeSpinBottomIdleAnims[index].cancel()
        v.freeSpinTopIdleAnims[index].cancel()
        v.addAnimation(bottomAnim)
        v.addAnimation(topAnim)
        bottomAnim.onComplete do():
            v.startIdleForPot(index)
            v.startIdleForPotTop(index)
        v.freeSpinBottomIdleAnims[index] = nil
        v.freeSpinTopIdleAnims[index] = nil

    if not v.freeSpinIdleBubblesAnims[index].isNil:
        v.freeSpinIdleBubblesAnims[index].cancelBehavior = cbContinueUntilEndOfLoop
        v.freeSpinIdleBubblesAnims[index].cancel()
        v.freeSpinIdleBubblesAnims[index] = nil
    result = bottomAnim

proc potsFromFreespins*(v: WitchSlotView): Animation {.discardable.} =
    v.slotGUI.winPanelModule.setNewWin(v.totalFreeSpinsWinning, false)
    v.slotGUI.spinButtonModule.stopFreespins()
    v.fsRedIdle.cancel()
    v.addAnimation(v.pots.findNode("freespins_layer").animationNamed("out"))
    for i in 0..<5:
        result = v.potFreeSpinsIdleOut(i)
    v.startIdle()

proc potMagicSpin*(v: WitchSlotView, index: int) =
    let top = v.pots.findNode("top_pot_" & $(index + 1))
    let ms = top.findNode("magic_spin")
    let topAnim = top.animationNamed("magic_spin")
    let msAnim = ms.animationNamed("play")

    v.soundManager.sendEvent("MAGIC_SPIN")
    v.addAnimation(topAnim)
    v.addAnimation(msAnim)

proc turnLightsOnPot*(v: WitchSlotView, index: int, isOn: bool) =
    let lightOn = v.rootNode.findNode("light_on_" & $(index + 1))
    let lightOff = v.rootNode.findNode("light_off_" & $(index + 1))

    lightOn.enabled = isOn
    lightOff.enabled = isOn

proc potReady*(v: WitchSlotView, index: int) =
    let ind = index + 1
    let bottom = v.pots.findNode("bottom_pot_" & $ind)
    let top = v.pots.findNode("top_pot_" & $ind)
    let bottomAnim = bottom.animationNamed("pot_ready")
    let topAnim = top.animationNamed("pot_ready")
    let middleAnim = top.findNode("pot_ready_middle_part").animationNamed("play")
    let flaresAnim = top.findNode("flares").animationNamed("play")
    let purple = top.findNode("purple_" & $ind & "_idle")
    let purpleAnim = purple.animationNamed("play")
    let readyBlue = v.pots.findNode("pot_ready_blue")

    for i in 1..5:
        readyBlue.childNamed("ready_blue_" & $i).enabled = false
    readyBlue.childNamed("ready_blue_" & $(index + 1)).enabled = true

    v.addAnimation(topAnim)
    v.addAnimation(bottomAnim)
    v.addAnimation(middleAnim)
    v.addAnimation(flaresAnim)
    v.addAnimation(purpleAnim)
    v.addAnimation(readyBlue.animationNamed("play"))

    purple.enabled = true
    flaresAnim.addLoopProgressHandler 0.5, false, proc() =
        v.turnLightsOnPot(index, false)
    purpleAnim.numberOfLoops = -1
    v.stopIdleForPot(index)
    v.soundManager.sendEvent("POT_READY")
    topAnim.onComplete do():
        v.startIdleForPot(index)
        v.startIdleForPotTop(index)


proc potBonusEffect*(v: WitchSlotView): Animation =
    let top = v.pots.findNode("top_pot_3")
    let bottom = v.pots.findNode("bottom_pot_3")
    let topAnim = top.animationNamed("bonus")
    let bottomAnim = bottom.animationNamed("bonus")
    let mainAnim = v.pots.animationNamed("bonus")
    let anim = top.findNode("bonus_effect").animationNamed("play")
    result = v.playAnim(WitchAnimation.BonusEnter)

    v.soundManager.sendEvent("BONUS_WIN")
    v.playAnim(WitchAnimation.BonusEnter)
    v.addAnimation(bottomAnim)
    v.addAnimation(mainAnim)
    result.addLoopProgressHandler 0.2, false, proc() =
        v.addAnimation(topAnim)
        v.addAnimation(anim)

proc potRuneEffects*(v: WitchSlotView, index: int, start, to: RuneColor) =
    let pot = v.pots.findNode("top_pot_" & $(index + 1))
    let potAnim = pot.animationNamed("rune_effects")
    let runeEffect = pot.findNode("rune_effect")
    let runeAnim = runeEffect.animationNamed("play")
    let runeLightFromAnim = runeEffect.findNode("rune_light_from").animationNamed("play")
    let runeLightToAnim = runeEffect.findNode("rune_light_to").animationNamed("play")
    let runeLightFromAnim2 = runeEffect.findNode("rune_light_from_2").animationNamed("play")
    let runeLightToAnim2 = runeEffect.findNode("rune_light_to_2").animationNamed("play")

    v.addAnimation(potAnim)
    v.addAnimation(runeAnim)
    v.addAnimation(runeLightFromAnim)
    v.addAnimation(runeLightToAnim)
    v.addAnimation(runeLightFromAnim2)
    v.addAnimation(runeLightToAnim2)

proc potSpinEnter*(v: WitchSlotView) =
    for i in 0..<NUMBER_OF_REELS:
        let potTop = v.pots.findNode("top_pot_" & $(i + 1))
        let potBottom = v.pots.findNode("bottom_pot_" & $(i + 1))
        let topAnim = potTop.animationNamed("spin_enter")
        let bottomAnim = potBottom.animationNamed("spin_enter")
        let addedAnim = potTop.findNode("spin").animationNamed("start")

        v.addAnimation(addedAnim)
        v.addAnimation(topAnim)
        v.addAnimation(bottomAnim)

proc setEffectOnLight(on, off: Node, num: int, col: RuneColor) =
    let lightIdle = on.findNode("light_idle_" & $num)
    let barrelOn = on.findNode("barrel3_" & $num)
    let barrelOff = off.findNode("barrel3_" & $num)
    let ltpLight = lightIdle.findNode("ltp_light1.png")
    let effect = ColorBalanceHLS.new()
    effect.init()

    ltpLight.removeComponent(ColorBalanceHLS)
    barrelOn.removeComponent(ColorBalanceHLS)
    barrelOff.removeComponent(ColorBalanceHLS)
    case col
    of RuneColor.Yellow:
        effect.hue = 0.111
    of RuneColor.Green:
        effect.hue = 0.277
    of RuneColor.Blue:
        effect.hue = 0.597
        effect.saturation = 0.2
    else:
        effect.hue = 0
        effect.saturation = 0
    ltpLight.setComponent("ColorBalanceHLS", effect)
    barrelOn.setComponent("ColorBalanceHLS", effect)
    barrelOff.setComponent("ColorBalanceHLS", effect)

proc fallElementInPot*(v: WitchSlotView, potIndex: int) =
    let n = v.rootNode.findNode("fall_element_in_pot_" & $(potIndex + 1))
    v.addAnimation(n.animationNamed("play"))

proc setLightsSequenceForPot*(v: WitchSlotView, index: int, lights: openarray[RuneColor]) =
    let potTop = v.pots.findNode("top_pot_" & $(index + 1))
    let lightOn = potTop.findNode("light_on_" & $(index + 1))
    let lightOff = potTop.findNode("light_off_" & $(index + 1))

    for i in 1..NUMBER_OF_REELS - 1:
        setEffectOnLight(lightOn, lightOff, i, lights[i - 1])

proc startIdleForAllPots*(v: WitchSlotView) =
    for i in 0..<NUMBER_OF_REELS:
        closureScope:
            let index = i

            v.setTimeout rand(1.0), proc() =
                v.startIdleForPot(index)
                v.startIdleForPotTop(index)

proc initPotLights*(v: WitchSlotView, newPots: bool = false) =
    for i in 0..<v.potsState.len:
        v.setLightsSequenceForPot(i, v.potsRunes[i])

        if newPots:
            v.startPotLights(i, 0)
        else:
            v.startPotLights(i, v.potsState[i])

proc checkLights*(v: WitchSlotView, s: string) =
    if s == "00000":
        for i in 0..<s.len:
            v.potsState[i] = 0
            v.setLightsSequenceForPot(i, v.potsRunes[i])

proc turnPurples*(v: WitchSlotView, s: string) =
    for i in 1..s.len:
        let purple = v.rootNode.findNode("purple_" & $i & "_idle")
        let purpleAnim = purple.animationNamed("play")

        if s[i - 1] != '4':
            purple.enabled = false
            purpleAnim.cancel()
        else:
            v.addAnimation(purpleAnim)
            purpleAnim.numberOfLoops = -1
            v.turnLightsOnPot(i - 1, false)

proc restoreAfterBonus*(v: WitchSlotView) =
    for i in 1..5:
        v.rootNode.findNode("light_off_" & $i).enabled = true
        v.rootNode.findNode("light_on_" & $i).enabled = true
        v.potsState[i - 1] = 0
        v.startPotLights(i - 1, 0)
    v.initPotLights(true)
