import random
import strutils
import tables

import nimx.matrixes
import nimx.animation
import nimx.timer
import nimx.button
import nimx.view

import rod.viewport
import rod.rod_types
import rod.node
import rod.component
import rod.component.sprite
import rod.component.ui_component
import rod.component.ae_composition
import rod.component.mask
import rod.component.particle_system

import anim_helpers
import sprite_digits_component
import utils.displacement

import mermaid_sound
import core.slot.base_slot_machine_view
import shared.win_popup
import shared.window.button_component
import utils.sound
import utils.sound_manager

const PARENT_PATH = "slots/mermaid_slot/"

type MermaidMSG* = ref object of WinDialogWindow
    rootNode*: Node
    animations*: Table[string, proc(callback: proc() = nil, val: int64 = 0): proc()]
    completion: Completion

    bigWin: int64
    hugeWin: int64
    megaWin: int64

    winWindowDestroyProc: proc()

proc `[]`*(m: MermaidMSG, name: string): proc(callback: proc() = nil, val: int64 = 0): proc() =
    return m.animations.getOrDefault(name)

proc prepareLightsweep(n: Node, letterName, maskName, letterSpriteName, maskSpriteName, lightsweepName: string): Completion =
    let lettersNode = n.findNode(letterName)
    let letterSpriteNode = lettersNode.findNode(letterSpriteName)
    letterSpriteNode.show(0)

    let lettersMaskNode = n.findNode(maskName)
    let mskSpriteNode = lettersMaskNode.findNode(maskSpriteName)
    mskSpriteNode.show(0)

    let lightsweepNode = n.findNode(lightsweepName)
    lightsweepNode.show(0)
    let mskComponent = lightsweepNode.componentIfAvailable(Mask)
    mskComponent.maskComponent = mskSpriteNode.componentIfAvailable(Sprite)

    result = newCompletion()
    result.to do():
        mskSpriteNode.hide(0)
        lightsweepNode.hide(0)
        letterSpriteNode.hide(0)
        mskComponent.maskComponent = nil

proc addFullscreenButton(n: Node, canProcess: proc(): bool, callback: proc()): proc() =
    var buttonParent = n.newChild(n.name & "_button")
    let button = newButton(newRect(0, 0, 1920, 1080))
    buttonParent.component(UIComponent).view = button
    button.hasBezel = false

    var job = proc() =
        buttonParent.removeFromParent()
        buttonParent = nil
        callback()

    button.onAction do():
        if not job.isNil and canProcess():
            job()
            job = nil

proc showInResultAnim(gameResultNode: Node, gametypeName: string, totalWin: int64, callback: proc() = nil) = # gametypeName = "bonus_game_title" # "free_spins_title"
    let v = gameResultNode.sceneView.BaseMachineView
    let inAnim = gameResultNode.animationNamed("in")

    gameResultNode.findNode(gametypeName).show(0)
    gameResultNode.show(0)

    v.addAnimation(inAnim)
    inAnim.onComplete do():
        v.addAnimation(gameResultNode.animationNamed("idle"))
    inAnim.addLoopProgressHandler 0.3, false, proc() =
        gameResultNode.findNode("title_blinks").playComposition()
    inAnim.addLoopProgressHandler 0.6, false, proc() =
        gameResultNode.findNode("LensFlareLeft").playComposition()
        gameResultNode.findNode("LensFlareRight").playComposition()

    v.addAnimation(gameResultNode.findNode(gametypeName).animationNamed("in"))
    v.addAnimation(gameResultNode.findNode("Effect_with_idle").animationNamed("in"))

    gameResultNode.findNode("Effect_with_idle").animationNamed("in").onComplete do():
        v.addAnimation(gameResultNode.findNode("Effect_with_idle").animationNamed("idle"))

    v.addAnimation(gameResultNode.findNode("backwater_idle").animationNamed("in"))
    gameResultNode.findNode("backwater_idle").animationNamed("in").onComplete do():
        v.addAnimation(gameResultNode.findNode("backwater_idle").animationNamed("idle"))

    v.addAnimation(gameResultNode.findNode("Disp_Map_B_idle").animationNamed("idle"))
    v.addAnimation(gameResultNode.findNode("EffectPRT_B_Small").animationNamed("in"))
    v.addAnimation(gameResultNode.findNode("Ribbon").animationNamed("in"))
    # v.addAnimation(gameResultNode.findNode("all_displacement_map").animationNamed("idle"))

    proc addRollinDigitsAnim(dest: int64) =
        var numNode = gameResultNode.findNode("num_scale_anchor")
        if numNode.isNil:
            numNode = newNodeWithResource(PARENT_PATH & "comps/sprite_digits.json")
            numNode.name = "num_scale_anchor"
            gameResultNode.findNode("num_anchor").addChild(numNode)

        let spNumComp = numNode.componentIfAvailable(SpriteDigits)

        let animSpinNumbers = newAnimation()
        animSpinNumbers.loopDuration = inAnim.loopDuration
        animSpinNumbers.numberOfLoops = 1
        animSpinNumbers.onAnimate = proc(p: float)=
            spNumComp.value = $interpolate(0'i64, dest, p)
            numNode.scaleX = interpolate(0.5, 0.95, p)
            numNode.scaleY = interpolate(0.5, 0.95, p)

        let countupSfx = v.playCountupSFX()

        v.addAnimation(animSpinNumbers)
        animSpinNumbers.onComplete do():
            countupSfx.stop()
            if not callback.isNil:
                callback()

    addRollinDigitsAnim(totalWin)

proc showOutResultAnim(gameResultNode: Node, gametypeName: string, callback: proc() = nil) =
    let v = gameResultNode.sceneView
    gameResultNode.animationNamed("idle").cancel()
    gameResultNode.findNode("Effect_with_idle").animationNamed("idle").cancel()
    gameResultNode.findNode("backwater_idle").animationNamed("idle").cancel()
    v.addAnimation(gameResultNode.animationNamed("out"))

    let outEffAnim = gameResultNode.findNode("Effect_with_idle").animationNamed("out")
    let outBackAnim = gameResultNode.findNode("backwater_idle").animationNamed("out")

    let effDuration = outEffAnim.loopDuration
    outEffAnim.loopDuration = effDuration / 2.5
    let backwaterDuration = outBackAnim.loopDuration
    outBackAnim.loopDuration = backwaterDuration / 2.5

    v.addAnimation(outEffAnim)
    v.addAnimation(outBackAnim)

    outBackAnim.onComplete do():
        outEffAnim.loopDuration = effDuration
        outBackAnim.loopDuration = backwaterDuration

        gameResultNode.findNode(gametypeName).hide(0)
        gameResultNode.hide(0)
        gameResultNode.findNode("Disp_Map_B_idle").animationNamed("idle").cancel()
        # gameResultNode.findNode("all_displacement_map").animationNamed("idle").cancel()
        if not callback.isNil:
            callback()

method destroy*(v: MermaidMSG) =
    if not v.winWindowDestroyProc.isNil:
        v.rootNode.sceneView.BaseMachineView.onWinDialogClose()
        v.winWindowDestroyProc()
        v.winWindowDestroyProc = nil
        v.rootNode.sceneView.BaseMachineView.winDialogWindow = nil

proc createMermaidMSG*(): MermaidMSG =
    result.new()
    result.rootNode = newNode("mermaid_msg")
    result.rootNode.positionY = -94.0
    result.animations = initTable[string, proc(callback: proc() = nil, val: int64 = 0): proc()]()
    result.completion = newCompletion()

    let rootNd = result.rootNode
    let winWindow = result

    let freespBonusGameNode = newNodeWithResource(PARENT_PATH & "msg_comps/msg/freespin_bonusgame.json")
    result.rootNode.addChild(freespBonusGameNode)

    freespBonusGameNode.hide(0)

    let titleAnchorNode = freespBonusGameNode.findNode("title_anchor")
    result.animations["freespin"] = proc(callback: proc() = nil, val: int64 = 0): proc() =

        freespBonusGameNode.findNode("effect_new.png").component(Mask).maskNode = freespBonusGameNode.findNode("Disp_Map_B")

        let v = freespBonusGameNode.sceneView.BaseMachineView
        # SOUND
        v.playFreeSpinsStartScreen()
        v.soundManager.pauseMusic()

        freespBonusGameNode.show(0)
        let complF = titleAnchorNode.prepareLightsweep("big_letter", "big_letter_msk", "F.png", "F.png", "ltp_lightsweep_1.png$15")
        let complRee = titleAnchorNode.prepareLightsweep("ree_onus", "ree_onus_msk", "ltp_ree.png", "ltp_ree.png", "ltp_lightsweep_1.png$20")
        let complSpins = titleAnchorNode.prepareLightsweep("spins_game", "spins_game_msk", "spins.png", "spins.png", "ltp_lightsweep_1.png")

        let freeBonusPrtNode = newNodeWithResource(PARENT_PATH & "comps/prt_ev/free_bonus.json")
        freespBonusGameNode.findNode("title_anchor").addChild(freeBonusPrtNode)

        freespBonusGameNode.playComposition do():

            v.soundManager.resumeMusic()

            freespBonusGameNode.hide(0)
            complF.finalize()
            complRee.finalize()
            complSpins.finalize()
            if not callback.isNil: callback()

            # freeBonusPrtNode.removeFromParent()
            freeBonusPrtNode.reattach(rootNd)
            let maxLifetime = 10.0

            freeBonusPrtNode.findNode("PRT_Ruby").componentIfAvailable(ParticleSystem).stop()
            freeBonusPrtNode.findNode("PRT_Bubble").componentIfAvailable(ParticleSystem).stop()

            freespBonusGameNode.sceneView.wait(maxLifetime) do():
                freeBonusPrtNode.removeFromParent()

        result = proc() = discard

    result.animations["bonusgame"] = proc(callback: proc() = nil, val: int64 = 0): proc() =
        let v = freespBonusGameNode.sceneView.BaseMachineView

        freespBonusGameNode.findNode("effect_new.png").component(Mask).maskNode = freespBonusGameNode.findNode("Disp_Map_B")

        # SOUND
        v.playBonusStartScreen()
        v.soundManager.pauseMusic()

        freespBonusGameNode.show(0)
        let complB = titleAnchorNode.prepareLightsweep("big_letter", "big_letter_msk", "ltp_b.png", "ltp_b.png", "ltp_lightsweep_1.png$15")
        let complOnus = titleAnchorNode.prepareLightsweep("ree_onus", "ree_onus_msk", "ltp_onus_2.png", "ltp_onus_2.png", "ltp_lightsweep_1.png$20")
        let complGame = titleAnchorNode.prepareLightsweep("spins_game", "spins_game_msk", "ltp_game_2.png", "ltp_game_2.png", "ltp_lightsweep_1.png")

        let freeBonusPrtNode = newNodeWithResource(PARENT_PATH & "comps/prt_ev/free_bonus.json")
        freespBonusGameNode.findNode("title_anchor").addChild(freeBonusPrtNode)

        freespBonusGameNode.playComposition do():

            v.soundManager.resumeMusic()

            freespBonusGameNode.hide(0)
            complB.finalize()
            complOnus.finalize()
            complGame.finalize()
            if not callback.isNil: callback()

            # freeBonusPrtNode.removeFromParent()
            freeBonusPrtNode.reattach(rootNd)
            let maxLifetime = 10.0

            freeBonusPrtNode.findNode("PRT_Ruby").componentIfAvailable(ParticleSystem).stop()
            freeBonusPrtNode.findNode("PRT_Bubble").componentIfAvailable(ParticleSystem).stop()

            freespBonusGameNode.sceneView.wait(maxLifetime) do():
                freeBonusPrtNode.removeFromParent()

        result = proc() = discard

    let gameResultNode = newNodeWithResource(PARENT_PATH & "msg_comps/msg/game_results.json")
    result.rootNode.addChild(gameResultNode)
    gameResultNode.hide(0)

    gameResultNode.findNode("effect_new.png").getComponent(Mask).maskNode = gameResultNode.findNode("effect_new.png").findNode("Disp_Map_B_idle")



    let freespeenResultPrtNode = newNodeWithResource(PARENT_PATH & "comps/prt_ev/results.json")
    result.animations["freespin_result"] = proc(callback: proc() = nil, val: int64 = 0): proc() =

        gameResultNode.findNode("effect_new.png").component(Mask).maskNode = gameResultNode.findNode("effect_new.png").findNode("Disp_Map_B_idle")

        let v = gameResultNode.sceneView.BaseMachineView
        # SOUND
        v.playFreeSpinsResultScreen()
        v.soundManager.pauseMusic()

        gameResultNode.addChild(freespeenResultPrtNode)
        let prtCoins = freespeenResultPrtNode.findNode("PRT_Coins").componentIfAvailable(ParticleSystem)
        let prtRuby1 = freespeenResultPrtNode.findNode("PRT_Ruby_1").componentIfAvailable(ParticleSystem)
        let prtRuby2 = freespeenResultPrtNode.findNode("PRT_Ruby_2").componentIfAvailable(ParticleSystem)
        let prtBubble = freespeenResultPrtNode.findNode("PRT_Bubble").componentIfAvailable(ParticleSystem)

        var bCanProcess = false
        let canProcess = proc(): bool = return bCanProcess

        let clbk = proc() =
            freespeenResultPrtNode.reattach(rootNd)
            prtCoins.stop()
            prtRuby1.stop()
            prtRuby2.stop()
            prtBubble.stop()

            let maxLifetime = 10.0

            gameResultNode.sceneView.wait(maxLifetime) do():
                freespeenResultPrtNode.removeFromParent()
            if not callback.isNil: callback()

        gameResultNode.showInResultAnim("free_spins_title", val) do():
            bCanProcess = true
            v.soundManager.resumeMusic()
            winWindow.winWindowDestroyProc = clbk
            v.onWinDialogShowAnimationComplete()
            v.winDialogWindow = winWindow

        result = gameResultNode.sceneView.rootNode.addFullscreenButton(canProcess) do():
            gameResultNode.showOutResultAnim("free_spins_title") do():

                gameResultNode.findNode("num_scale_anchor").scaleX = 0

                winWindow.destroy()


        prtCoins.start()
        prtRuby1.start()
        prtRuby2.start()
        prtBubble.start()
        gameResultNode.sceneView.wait(1.0) do():
            prtCoins.stop()

    let bonusResultPrtNode = newNodeWithResource(PARENT_PATH & "comps/prt_ev/results.json")
    result.animations["bonusgame_result"] = proc(callback: proc() = nil, val: int64 = 0): proc() =

        let v = gameResultNode.sceneView.BaseMachineView

        gameResultNode.findNode("effect_new.png").component(Mask).maskNode = gameResultNode.findNode("effect_new.png").findNode("Disp_Map_B_idle")

        # SOUND
        v.playBonusResultScreen()
        v.soundManager.pauseMusic()

        gameResultNode.addChild(bonusResultPrtNode)
        let prtCoins = bonusResultPrtNode.findNode("PRT_Coins").componentIfAvailable(ParticleSystem)
        let prtRuby1 = bonusResultPrtNode.findNode("PRT_Ruby_1").componentIfAvailable(ParticleSystem)
        let prtRuby2 = bonusResultPrtNode.findNode("PRT_Ruby_2").componentIfAvailable(ParticleSystem)
        let prtBubble = bonusResultPrtNode.findNode("PRT_Bubble").componentIfAvailable(ParticleSystem)

        var bCanProcess = false
        let canProcess = proc(): bool = return bCanProcess

        let clbk = proc() =
            bonusResultPrtNode.reattach(rootNd)
            prtCoins.stop()
            prtRuby1.stop()
            prtRuby2.stop()
            prtBubble.stop()

            let maxLifetime = 10.0

            gameResultNode.sceneView.wait(10.0) do():
                bonusResultPrtNode.removeFromParent()
            if not callback.isNil: callback()

        gameResultNode.showInResultAnim("bonus_game_title", val) do():
            bCanProcess = true
            v.soundManager.resumeMusic()
            winWindow.winWindowDestroyProc = clbk
            v.onWinDialogShowAnimationComplete()
            v.winDialogWindow = winWindow

        result = gameResultNode.sceneView.rootNode.addFullscreenButton(canProcess) do():

            gameResultNode.showOutResultAnim("bonus_game_title") do():

                gameResultNode.findNode("num_scale_anchor").scaleX = 0

                winWindow.destroy()

        prtCoins.start()
        prtRuby1.start()
        prtRuby2.start()
        prtBubble.start()
        gameResultNode.sceneView.wait(1.0) do():
            prtCoins.stop()


    let fiveInARowNode = newNodeWithResource(PARENT_PATH & "msg_comps/msg/5_in_arow.json")
    result.rootNode.addChild(fiveInARowNode)
    fiveInARowNode.hide(0)

    result.animations["5_in_a_row"] = proc(callback: proc(), val: int64 = 0): proc() =

        fiveInARowNode.findNode("effect_new.png").component(Mask).maskNode = fiveInARowNode.findNode("Disp_Map_B")

        let freeBonusPrtNode = newNodeWithResource(PARENT_PATH & "comps/prt_ev/five_row.json")
        fiveInARowNode.addChild(freeBonusPrtNode)

        freeBonusPrtNode.findNode("PRT_Rubins").componentIfAvailable(ParticleSystem).start()

        let v = gameResultNode.sceneView.BaseMachineView
        # SOUND
        v.playFiveInARow()
        v.soundManager.pauseMusic()

        fiveInARowNode.show(0)
        fiveInARowNode.playComposition do():

            v.soundManager.resumeMusic()

            fiveInARowNode.hide(0)
            if not callback.isNil: callback()

            freeBonusPrtNode.reattach(rootNd)
            let maxLifetime = 10.0

            freeBonusPrtNode.findNode("PRT_Rubins").componentIfAvailable(ParticleSystem).stop()
            freeBonusPrtNode.findNode("PRT_Bubble").componentIfAvailable(ParticleSystem).stop()

            freespBonusGameNode.sceneView.wait(maxLifetime) do():
                freeBonusPrtNode.removeFromParent()

        result = proc() = discard

    let bigwinAllNode = newNodeWithResource(PARENT_PATH & "msg_comps/msg/big_win_all.json")
    result.rootNode.addChild(bigwinAllNode)
    bigwinAllNode.hide(0)

    let mermaidMsg = result
    result.animations["bigwin"] = proc(callback: proc(), val: int64 = 0): proc() =

        bigwinAllNode.findNode("effect_new.png").component(Mask).maskNode = bigwinAllNode.findNode("Disp_Map_B_idle")

        var clickCounter = 0

        let v = bigwinAllNode.sceneView.BaseMachineView

        var animSeq = newSeq[Animation]()
        proc addAnimation(anim: Animation) =
            anim.cancelBehavior = cbJumpToEnd
            v.addAnimation(anim)


        # SOUND
        v.soundManager.pauseMusic()

        let bigwinSound = v.playBigWin()
        var hugewinSound: Sound
        var megawinSound: Sound
        var countupSfx: Sound

        bigwinAllNode.show(0)

        let reswultTitleNode = bigwinAllNode.findNode("ltp_result_2.png")
        reswultTitleNode.hide(0)

        let effInAnim = bigwinAllNode.findNode("Effect_with_idle").animationNamed("in")
        let effIdleAnim = bigwinAllNode.findNode("Effect_with_idle").animationNamed("idle")
        let effOutAnim = bigwinAllNode.findNode("Effect_with_idle").animationNamed("out")
        addAnimation(effInAnim)
        effInAnim.onComplete do():
            addAnimation(effIdleAnim)
            effInAnim.removeHandlers()

        let effVerticalInAnim = bigwinAllNode.findNode("EffectPRT_B_Small").animationNamed("in")
        addAnimation(effVerticalInAnim)

        let backwaterInAnim = bigwinAllNode.findNode("backwater_idle").animationNamed("in")
        let backwaterIdleAnim = bigwinAllNode.findNode("backwater_idle").animationNamed("idle")
        let backwaterOutAnim = bigwinAllNode.findNode("backwater_idle").animationNamed("out")
        addAnimation(backwaterInAnim)
        backwaterInAnim.onComplete do():
            addAnimation(backwaterIdleAnim)
            backwaterInAnim.removeHandlers()

        let dispMapIdleAnim = bigwinAllNode.findNode("Disp_Map_B_idle").animationNamed("idle")
        addAnimation(dispMapIdleAnim)

        # let displacementAllIdleAnim = bigwinAllNode.findNode("all_displacement_map").animationNamed("idle")
        # addAnimation(displacementAllIdleAnim)

        template playLensFlare() =
            bigwinAllNode.findNode("LensFlareRight").playComposition()
            bigwinAllNode.findNode("LensFlareLeft").playComposition()

        let bigWinTitleInAnim = bigwinAllNode.findNode("Big_win").animationNamed("in")
        let bigWinTitleOutAnim = bigwinAllNode.findNode("Big_win").animationNamed("out")

        proc getLetterParticles(n: Node, namePrefix, name1, name2, name3: string): tuple[n1: ParticleSystem, n2: ParticleSystem, n3: ParticleSystem] =
            let bNode = n.findNode(namePrefix).findNode(name1)
            let igNode = n.findNode(namePrefix).findNode(name2)
            let winNode = n.findNode(namePrefix).findNode(name3)

            var bigLetterPrtNode = bNode.findNode("bubble_prt_child")
            var igUgeReeEgaLetterPrtNode = igNode.findNode("bubble_prt_child")
            var winSpinsLetterPrtNode = winNode.findNode("bubble_prt_child")

            if bigLetterPrtNode.isNil:
                bigLetterPrtNode = newNodeWithResource(PARENT_PATH & "comps/prt_ev/big_letter.json")
                bNode.addChild(bigLetterPrtNode)
            if igUgeReeEgaLetterPrtNode.isNil:
                igUgeReeEgaLetterPrtNode = newNodeWithResource(PARENT_PATH & "comps/prt_ev/ig_uge_ree_ega_letter.json")
                igNode.addChild(igUgeReeEgaLetterPrtNode)
            if winSpinsLetterPrtNode.isNil:
                winSpinsLetterPrtNode = newNodeWithResource(PARENT_PATH & "comps/prt_ev/win_spins_letter.json")
                winNode.addChild(winSpinsLetterPrtNode)

            result.n1 = bigLetterPrtNode.findNode("PRT_Bubble").componentIfAvailable(ParticleSystem)
            result.n2 = igUgeReeEgaLetterPrtNode.findNode("PRT_Bubble").componentIfAvailable(ParticleSystem)
            result.n3 = winSpinsLetterPrtNode.findNode("PRT_Bubble").componentIfAvailable(ParticleSystem)

        proc start(nodes: tuple[n1: ParticleSystem, n2: ParticleSystem, n3: ParticleSystem]) =
            nodes.n1.start()
            nodes.n2.start()
            nodes.n3.start()

        let letterBigPrt = bigwinAllNode.getLetterParticles("bigwin_title_anchor", "ltp_b.png", "ltp_ig_2.png", "ltp_win.png")

        let hugeWinTitleInAnim = bigwinAllNode.findNode("Huge_win").animationNamed("in")
        let hugeWinTitleOutAnim = bigwinAllNode.findNode("Huge_win").animationNamed("out")

        let letterHugePrt = bigwinAllNode.getLetterParticles("hugewin_title_anchor", "ltp_h.png", "uge", "ltp_win.png")

        let megaWinTitleInAnim = bigwinAllNode.findNode("Mega_win").animationNamed("in")
        let megaWinTitleOutAnim = bigwinAllNode.findNode("Mega_win").animationNamed("out")

        let letterMegaPrt = bigwinAllNode.getLetterParticles("megawin_title_anchor", "ltp_m.png", "ltp_ega.png", "ltp_win.png")

        let bigwinPrtNode = newNodeWithResource(PARENT_PATH & "comps/prt_ev/bigwin.json")
        bigwinAllNode.addChild(bigwinPrtNode)

        let prtCoins1 = bigwinPrtNode.findNode("PRT_Coins_1").componentIfAvailable(ParticleSystem)
        let prtCoins2 = bigwinPrtNode.findNode("PRT_Coins_2").componentIfAvailable(ParticleSystem)
        let prtRuby1 = bigwinPrtNode.findNode("PRT_Ruby_1").componentIfAvailable(ParticleSystem)
        let prtRuby2 = bigwinPrtNode.findNode("PRT_Ruby_2").componentIfAvailable(ParticleSystem)
        let prtBubble = bigwinPrtNode.findNode("PRT_Bubble").componentIfAvailable(ParticleSystem)

        bigwinPrtNode.show(0)

        prtCoins1.start()
        prtCoins2.start()
        prtRuby1.start()
        prtRuby2.start()
        prtBubble.start()

        let stpPrtCallback = proc() =
            bigwinPrtNode.reattach(rootNd)
            prtCoins1.stop()
            prtCoins2.stop()
            prtRuby1.stop()
            prtRuby2.stop()
            prtBubble.stop()
            let maxLifetime = 10.0
            bigwinPrtNode.sceneView.wait(10.0) do():
                bigwinPrtNode.hide(0)
                bigwinPrtNode.reattach(bigwinPrtNode)

        effInAnim.addLoopProgressHandler 0.3, false, proc() =
            addAnimation(bigWinTitleInAnim)

            # LETTERS PARTICLES
            letterBigPrt.start()

            bigWinTitleInAnim.addLoopProgressHandler(0.6, false) do():
                bigwinAllNode.findNode("Flame_Big").playComposition()

        effInAnim.addLoopProgressHandler 0.5, false, proc() =
            playLensFlare()


        let ribbonInAnim = bigwinAllNode.findNode("Ribbon").animationNamed("in")
        let ribbonOutAnim = bigwinAllNode.findNode("ribbon_parent_out").animationNamed("out")
        let ribbonNode = bigwinAllNode.findNode("ribbon_parent")
        let ribbonHugeInAnim = ribbonNode.animationNamed("bounce_huge")
        let ribbonMegaInAnim = ribbonNode.animationNamed("bounce_mega")


        effInAnim.addLoopProgressHandler 0.4, false, proc() =
            addAnimation(ribbonInAnim)

            ribbonInAnim.addLoopProgressHandler 0.05, false, proc() =
                ribbonNode.scale = newVector3(1,1,1)
                ribbonNode.findNode("num_win_anchor").scale = newVector3(1,1,1)
                ribbonNode.show(0)

        var outTitleAnim: Animation = bigWinTitleOutAnim
        proc doOut(clbk: proc() = nil) =
            effIdleAnim.cancel()
            let effDuration = effOutAnim.loopDuration
            effOutAnim.loopDuration = effDuration / 2.5
            let backwaterDuration = backwaterOutAnim.loopDuration
            backwaterOutAnim.loopDuration = backwaterDuration / 2.5
            addAnimation(effOutAnim)
            backwaterIdleAnim.cancel()
            addAnimation(backwaterOutAnim)
            # displacementAllIdleAnim.cancel()
            addAnimation(ribbonOutAnim)
            addAnimation(outTitleAnim)
            effOutAnim.onComplete do():
                effOutAnim.loopDuration = effDuration
                backwaterOutAnim.loopDuration = backwaterDuration
                effOutAnim.removeHandlers()
                bigwinAllNode.hide(0)
                reswultTitleNode.show(0)
                if not clbk.isNil: clbk()

        var canDoMega = false
        proc doHuge() =

            # SOUND
            hugewinSound = v.playHugeWin()

            outTitleAnim = hugeWinTitleOutAnim
            addAnimation(bigWinTitleOutAnim)
            bigWinTitleOutAnim.addLoopProgressHandler(0.5, false) do():
                addAnimation(hugeWinTitleInAnim)
                # LETTERS PARTICLES
                letterHugePrt.start()

                hugeWinTitleInAnim.addLoopProgressHandler(0.6, false) do():
                    bigwinAllNode.findNode("Flame_Huge").playComposition()
                hugeWinTitleInAnim.addLoopProgressHandler 0.3, false, proc() =
                    playLensFlare()
                hugeWinTitleInAnim.addLoopProgressHandler 0.1, false, proc() =
                    addAnimation(ribbonHugeInAnim)
                hugeWinTitleInAnim.onComplete do():
                    hugeWinTitleInAnim.removeHandlers()
                    canDoMega = true

        proc doMega() =

            # SOUND
            megawinSound = v.playMegaWin()

            outTitleAnim = megaWinTitleOutAnim
            addAnimation(hugeWinTitleOutAnim)
            hugeWinTitleOutAnim.addLoopProgressHandler(0.5, false) do():
                addAnimation(megaWinTitleInAnim)

                # LETTERS PARTICLES
                letterMegaPrt.start()

                megaWinTitleInAnim.addLoopProgressHandler(0.6, false) do():
                    bigwinAllNode.findNode("Flame_Mega").playComposition()
                megaWinTitleInAnim.addLoopProgressHandler 0.5, false, proc() =
                    playLensFlare()
                megaWinTitleInAnim.addLoopProgressHandler 0.1, false, proc() =
                    addAnimation(ribbonMegaInAnim)
                megaWinTitleInAnim.onComplete do():
                    megaWinTitleInAnim.removeHandlers()

        ribbonInAnim.onComplete do():
            ribbonInAnim.removeHandlers()

        ###########################################

        var buttonParent: Node

        var canDoHuge = false
        ribbonInAnim.addLoopProgressHandler 0.9, false, proc() =
            canDoHuge = true

        var numNode = ribbonNode.findNode("num_scale_anchor")
        if numNode.isNil:
            numNode = newNodeWithResource(PARENT_PATH & "comps/sprite_digits.json")
            numNode.name = "num_scale_anchor"
            ribbonNode.findNode("num_anchor").addChild(numNode)

        let spNumComp = numNode.componentIfAvailable(SpriteDigits)

        var finishedWithoutSkip = false
        var animSpinNumbers: Animation
        proc addRollinDigitsAnim(dest: int64) =
            var bHugeStart, bMegaStart: bool = false

            let bigwinDuration = effInAnim.loopDuration * 0.4 + ribbonInAnim.loopDuration * (1.0-0.3)
            let hugewinDuration = if dest >= mermaidMsg.hugeWin: bigWinTitleOutAnim.loopDuration * 0.5 + hugeWinTitleInAnim.loopDuration else: 0.0
            let megawinDuration = if dest >= mermaidMsg.megaWin: hugeWinTitleOutAnim.loopDuration * 0.5 + megaWinTitleInAnim.loopDuration else: 0.0
            animSpinNumbers = newAnimation()
            animSpinNumbers.cancelBehavior = cbJumpToEnd
            animSpinNumbers.loopDuration = bigwinDuration + hugewinDuration + megawinDuration
            animSpinNumbers.numberOfLoops = 1

            animSpinNumbers.onAnimate = proc(p: float) =
                let val = interpolate(0'i64, dest, p)
                spNumComp.value = $val
                numNode.scaleX = interpolate(0.5, 0.95, p)
                numNode.scaleY = interpolate(0.5, 0.95, p)

            # proc(dest: int64) =
                # var start = [0.float, 0.5]
                # var dest = [dest.float, 0.95]
                # animSpinNumbers.animate val in start .. dest:
                    # spNumComp.value = $(val[0].int)
                    # numNode.scaleX = val[1]
                    # numNode.scaleY = val[1]

                if clickCounter == 0:
                    if not bHugeStart and canDoHuge and val >= mermaidMsg.hugeWin:
                        bHugeStart = true

                        if not bigwinSound.isNil:
                            bigwinSound.stop()
                        doHuge()

                    if not bMegaStart and canDoMega and val >= mermaidMsg.megaWin:
                        bMegaStart = true
                        if not hugewinSound.isNil:
                            hugewinSound.stop()
                        doMega()


            countupSfx = v.playCountupSFX()

            v.addAnimation(animSpinNumbers)
            animSpinNumbers.onComplete do():
                finishedWithoutSkip = true

                countupSfx.stop()
                v.soundManager.resumeMusic()

                v.onWinDialogShowAnimationComplete()
                v.winDialogWindow = winWindow

        var bCanProcess = false
        let canProcess = proc(): bool = return bCanProcess
        ribbonInAnim.addLoopProgressHandler 0.3, false, proc() =
            bCanProcess = true
            addRollinDigitsAnim(val)


        # FINAL BUTTON
        buttonParent = winWindow.rootNode.newChild("bigwin_button")
        buttonParent.position = newVector3(-1000, -1000, 0)
        let button = buttonParent.createButtonComponent(newRect(-2000, -2000, 10000, 10000))

        let clbk = proc() =
            if bCanProcess:
                if clickCounter == 0:
                    for anim in animSeq:
                        anim.cancel()
                    animSeq = @[]
                    animSpinNumbers.cancel()

                if clickCounter == 1 or finishedWithoutSkip:
                    winWindow.destroy()

                inc clickCounter

        winWindow.winWindowDestroyProc = proc() =
            buttonParent.removeFromParent()
            buttonParent = nil

            if not finishedWithoutSkip:
                countupSfx.stop()
                v.soundManager.resumeMusic()

            doOut do():
                numNode.removeFromParent()
                if not callback.isNil: callback()
            stpPrtCallback()

        button.onAction do():
            clbk()

proc setupBigwins*(m: MermaidMSG, bigWin, hugeWin, megaWin: int64) =
    m.bigWin = bigWin
    m.hugeWin = hugeWin
    m.megaWin = megaWin
