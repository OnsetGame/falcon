import
    nimx.view, nimx.context, nimx.button, nimx.animation, nimx.window,
    nimx.view_event_handling, nimx.timer,
    core / notification_center,

    rod.rod_types, rod.node, rod.viewport, rod.component, rod.component.ui_component,
    rod.asset_bundle,
    #
    tables, random, json, strutils, sequtils, algorithm,
    #
    core.net.server, shared.user, core.slot.base_slot_machine_view, shared.chips_animation, shared.gui.slot_gui, shared.win_popup, shared.director,
    #
    utils.sound, utils.sound_manager, utils.helpers, utils.pause, utils.falcon_analytics_helpers,
    utils.fade_animation, utils.falcon_analytics_utils, utils.falcon_analytics,
    #
    shafa.slot.slot_data_types,
    shared.gui.gui_pack,
    #
    shared.gui.gui_module, shared.gui.win_panel_module, shared.gui.total_bet_panel_module, shared.gui.paytable_open_button_module,
    shared.gui.spin_button_module, shared.gui.money_panel_module, shared.window.window_manager, shared.window.button_component

import core / flow / [ flow, flow_state_types ]

const GENERAL_PREFIX = "slots/witch_slot/"
const SOUND_PATH_PREFIX = GENERAL_PREFIX & "sound/"
const TRESHOLDS* = [9, 11, 14]
const SHIFT* = newVector3(-960, -588)
const GAME_FLOW = ["GF_SPIN", "GF_RESPINS", "GF_SPIDER","GF_SHOW_WIN", "GF_SPECIAL", "GF_RUNES", "GF_BONUS", "GF_FREESPINS_INTRO", "GF_FREESPINS", "GF_LEVELUP"]
const WITCH_POS* = [newVector3(825.0, 588.0) + SHIFT, newVector3(1163.0, 588.0) + SHIFT]

type Symbols* {.pure.} = enum
    Wild,
    Scatter,
    Red,
    Yellow,
    Green,
    Blue,
    Plant,
    Mandragora,
    Mushroom,
    Feather,
    Web

type RuneColor* {.pure.} = enum
    Red = 1,
    Yellow,
    Green,
    Blue

type ElementType* {.pure.} = enum
    Wild,
    Scatter,
    Red,
    Yellow,
    Green,
    Blue,
    Predator,
    Mandragora,
    Mushroom,
    Feather,
    Hive #ex-Web

type ElementAnimation* {.pure.} = enum
    Enter,
    Idle,
    IdleOut,
    Win

type WitchElement* = ref object of RootObj
    eType*: ElementType
    anims*: seq[ElementAnimation]
    node*: Node
    glareNode*: Node
    index*: int

type FreespinStatus* {.pure.} = enum
    No,
    Before,
    Yes,
    After

type WitchAnimation* {.pure.} = enum
    Spin,
    PotReady,
    MagicSpin,
    RuneEffect,
    Win,
    FreeSpinsIn,
    FreeSpinsWin,
    BonusEnter,
    InOut,
    Idle,
    FreeSpinsIdle,
    FreeSpinsSpin

type WitchReturn* {.pure.} = enum
    Idle,
    FreespinIdle,
    NoReturn

type WitchPaytableServerData* = tuple
    paytableSeq: seq[seq[int]]
    magicSpinChance: int
    bonusElementsStartAmount: int
    bonusElementsPaytable: seq[seq[int]]
    freespinsAllCount: int

type WitchSlotView* = ref object of BaseMachineView
    totalFreeSpinsWinning*: int64
    freeSpinsCount*: int
    potsState*: seq[int]
    potsRunes*: seq[seq[RuneColor]]
    mainParent*: Node
    mainScene*: Node
    pots*: Node
    backgroundIdleTimers*: seq[ControlledTimer]
    backgroundIdleAnims*: seq[Animation]
    potIdleAnimsBottom*: array[0..NUMBER_OF_REELS - 1, Animation]
    potIdleAnimsTop*: array[0..NUMBER_OF_REELS - 1, Animation]
    freeSpinBottomIdleAnims*: array[0..NUMBER_OF_REELS - 1, Animation]
    freeSpinTopIdleAnims*: array[0..NUMBER_OF_REELS - 1, Animation]
    freeSpinIdleBubblesAnims*: array[0..NUMBER_OF_REELS - 1, Animation]
    elementIdles*: seq[Animation]
    initialFade*: FadeSolidAnimation
    elementsParent*: Node
    currentActiveRunes: seq[WitchElement]
    currentElements*: seq[WitchElement]
    currentMagicSpinReel*: int
    wildChildIndex*: int
    fsStatus*: FreespinStatus
    witch*: Node
    currWitchAnimType*: WitchAnimation #del
    currWitchAnim*: Animation #del
    currWinningWitchAnim*: Animation
    witchPos*: int
    isSpider*: bool
    bonusPayout*: int64
    bonusTotalBet*: int64
    linesWin*: int64
    bonusField*: seq[int8]
    winNumbersParent*: Node
    freespinsPlus*: Node
    magicSpinMessage*: Node
    bonusParent*: Node
    specialWinParent*: Node
    currentWin*: int64
    repeatWinAnim*: Animation
    cauldronSound*: Sound
    interruptLinesAnim*: bool
    cheatMagicSpin*: bool
    strPots: string
    curPotsStates: seq[string]
    canSpinBonus*: bool
    fsRedIdle*: Animation
    pd*: WitchPaytableServerData

proc isSecondaryElement*(v: WitchSlotView, index: int): bool =
    let reelIndexes = reelToIndexes(v.currentMagicSpinReel)
    if v.currentMagicSpinReel != -1 and reelIndexes.contains(index):
        return true

import witch_character

proc playWitchWin*(v: WitchSlotView): Animation {.discardable.} =
    if v.fsStatus == FreespinStatus.Yes or v.fsStatus == FreespinStatus.After:
        result = v.playAnim(WitchAnimation.FreeSpinsWin, WitchReturn.FreespinIdle)
        v.soundManager.sendEvent("WITCH_WIN_LAUGH")
    else:
        result = v.playAnim(WitchAnimation.Win)

proc getBigWinType*(v: WitchSlotView): BigWinType =
    result = BigWinType.Big

    if v.linesWin >= v.totalBet * TRESHOLDS[2]:
        result = BigWinType.Mega
    elif v.linesWin >= v.totalBet * TRESHOLDS[1]:
        result = BigWinType.Huge

proc pushNextState*(v: WitchSlotView) =
    let cp = proc() = v.gameFlow.nextEvent()
    let spinFlow = findActiveState(SpinFlowState)
    if not spinFlow.isNil:
        spinFlow.pop()
    let state = newFlowState(SlotNextEventFlowState, newVariant(cp))
    pushBack(state)

import witch_background_anim
import witch_pot_anim
import witch_elements
import witch_spider
import witch_winning_lines
import witch_bonus
import witch_line_numbers
import witch_freespins_intro
import witch_result_screen
import witch_bigwins
import witch_sound
import witch_five_in_a_row
import witch_bonus_intro

proc updatePotsStates(v: WitchSlotView) =
    v.potsRunes = @[]
    for potStates in v.curPotsStates:
        let ps = $potStates
        var p: seq[RuneColor] = @[]

        for i in 0..<ps.len:
            p.add(parseInt($(ps[i])).RuneColor)
        v.potsRunes.add(p)

proc setActiveRunes(v: WitchSlotView) =
    v.currentActiveRunes = @[]
    for i in 0..<v.strPots.len:
        let newRune = parseInt($(v.strPots[i]))

        if v.potsState[i] != newRune:
            if newRune != 0:
                v.potsState[i] = newRune
                let reelIndexes = reelToIndexes(i)
                for ri in reelIndexes:
                    if v.lastField[ri] - 1 == v.potsRunes[i][newRune - 1].int:
                        v.currentActiveRunes.add(v.currentElements[ri])

proc fallRunes(v: WitchSlotView) =
    v.setActiveRunes()
    v.updatePotsStates()
    if v.currentActiveRunes.len > 0:
        for i in 0..<v.currentActiveRunes.len:
            closureScope:
                let index = i
                let el = v.currentActiveRunes[index]
                let reelIndex = el.index mod NUMBER_OF_REELS

                proc callback() =
                    var next = v.potsState[reelIndex]

                    if next < 4:
                        let start = (el.eType.int - 1).RuneColor
                        let to = v.potsRunes[reelIndex][v.potsState[reelIndex]].RuneColor

                        v.potRuneEffects(reelIndex, start, to)
                        v.playAnim(WitchAnimation.RuneEffect)
                        v.playWitchRuneEffect(start, to)
                        v.fallElementsInPot(reelIndex)
                    else:
                        v.playAnim(WitchAnimation.Spin)
                        v.potReady(reelIndex)
                    v.initPotLights()
                v.fallRune(el, callback)
        v.setTimeout 3.0, proc() =
            v.gameFlow.nextEvent()
    else:
        v.gameFlow.nextEvent()

proc startSpin(v: WitchSlotView) =
    v.sendSpinRequest(v.totalBet) do(res: JsonNode):
        let firstStage = res[$srtStages][0]

        v.bonusField = @[]
        v.curPotsStates = @[]
        for idle in v.elementIdles:
            idle.cancel()
        v.elementIdles = @[]
        for j in firstStage[$srtField].items:
            v.lastField.add(j.getInt().int8)

        if res.hasKey($srtFreespinCount):
            let newFSCount = v.freeSpinsCount - 1

            v.freeSpinsCount = res[$srtFreespinCount].getInt()
            if v.freeSpinsCount > 0:
                if v.fsStatus == FreespinStatus.No:
                    v.fsStatus = FreespinStatus.Before
                    v.onFreeSpinsStart()
                else:
                    v.fsStatus = FreespinStatus.Yes
            else:
                if v.fsStatus == FreespinStatus.Yes:
                    v.fsStatus = FreespinStatus.After
                    v.onFreeSpinsEnd()
                else:
                    v.fsStatus = FreespinStatus.No

            if newFSCount >= 0:
                v.slotGUI.spinButtonModule.setFreespinsCount(newFSCount)

        if res[$srtStages].len > 1:
            let bonusStage = res[$srtStages][1]

            v.bonusPayout = bonusStage[$srtPayout].getBiggestInt().int64
            v.bonusTotalBet = bonusStage[$srtWitchBonusTotalbet].getBiggestInt().int64
            for j in bonusStage[$srtField].items:
                v.bonusField.add(j.getInt().int8)

        for item in firstStage[$srtLines].items:
            let line = PaidLine.new()
            line.winningLine.numberOfWinningSymbols = item["symbols"].getInt()
            line.winningLine.payout = item["payout"].getBiggestInt().int64
            line.index = item["index"].getInt()
            v.paidLines.add(line)
            v.linesWin += line.winningLine.payout

        let oldChips = currentUser().chips
        currentUser().chips = res[$srtChips].getBiggestInt()

        var spent = v.totalBet
        var win: int64 = 0
        if v.fsStatus == FreespinStatus.Yes or v.freeRounds:
            spent = 0
        if currentUser().chips > oldChips:
            win = currentUser().chips - oldChips

        v.spinAnalyticsUpdate(win, v.fsStatus == FreespinStatus.Yes)

        for states in res[$sdtPotsStates]:
            v.curPotsStates.add($states)

        v.clearMagicParents()

        let fill = v.fillField(v.lastField)

        v.isSpider = res[$srtIsSpider].getBool()
        v.strPots = res[$srtPots].getStr()
        v.currWinningWitchAnim = nil
        v.checkLights(v.strPots)
        v.totalFreeSpinsWinning = res[$srtFreespinTotalWin].getBiggestInt()
        fill.onComplete do():
            v.ifWinFreespinsSound()
            v.gameFlow.nextEvent()

proc spinReady(v: WitchSlotView) =
    var anim: Animation
    let beforeSpinChips = currentUser().chips
    let r = rand(1..3)

    v.lastField = @[]
    v.paidLines = @[]
    v.currentMagicSpinReel = -1
    if v.fsStatus == FreespinStatus.Yes or v.fsStatus == FreespinStatus.Before:
        anim = v.playAnim(WitchAnimation.FreeSpinsSpin, WitchReturn.FreespinIdle)
    else:
        anim = v.playAnim(WitchAnimation.Spin)
        if not v.freeRounds:
            anim.addLoopProgressHandler 0.8, false, proc() =
                v.slotGUI.moneyPanelModule.setBalance(beforeSpinChips, beforeSpinChips - v.totalBet, false)
        v.potSpinEnter()

    if v.fsStatus == FreespinStatus.Yes or v.fsStatus == FreespinStatus.Before:
        v.soundManager.sendEvent("REEL_SPIN_FREESPINS_" & $r)
    else:
        v.soundManager.sendEvent("REEL_SPIN_" & $r)

    v.slotGUI.winPanelModule.setNewWin(0)
    v.currentWin = 0
    v.linesWin = 0
    v.bonusPayout = 0
    v.bonusTotalBet = 0
    v.interruptLinesAnim = false

    if not v.repeatWinAnim.isNil:
        v.repeatWinAnim.cancel()
        v.repeatWinAnim = nil
    if v.fsStatus == FreespinStatus.Yes or v.fsStatus == FreespinStatus.After:
        v.soundManager.sendEvent("FALL_INGREDIENTS_FREESPINS")
    else:
        let r = rand(1..3)
        v.soundManager.sendEvent("FALL_INGREDIENTS_" & $r)
    anim.addLoopProgressHandler 0.4, false, proc() =
        if v.fsStatus == FreespinStatus.Before:
            v.stopAllGlares(true)
            v.startSpin()
        else:
            let eOut = v.elementsOut()

            v.stopAllGlares(true)
            eOut.onComplete do():
                v.startSpin()

method onSpinClick*(v: WitchSlotView) =
    procCall v.BaseMachineView.onSpinClick()
    if v.actionButtonState == SpinButtonState.Spin:
        if not v.freeRounds:
            if currentUser().withdraw(v.totalBet()):
                v.gameFlow.start()
            else:
                echo "Not enough chips..."
                v.slotGUI.outOfCurrency("chips")
        else:
            v.gameFlow.start()

    elif v.actionButtonState == SpinButtonState.StopAnim:
        v.interruptLinesAnim = true
        v.slotGUI.winPanelModule.setNewWin(v.linesWin)
        v.actionButtonState = SpinButtonState.Blocked

proc setInitialData(v: WitchSlotView) =
    v.slotGUI.moneyPanelModule.setBalance(v.currentBalance, v.currentBalance, false)

proc startFreeSpins(v: WitchSlotView) =
    if v.fsStatus == FreespinStatus.Yes or v.fsStatus == FreespinStatus.Before:
        v.setSpinButtonState(SpinButtonState.Blocked)
        v.gameFlow.start()
    else:
        v.showRepeatingSymbols()
        v.gameFlow.nextEvent()
        v.setSpinButtonState(SpinButtonState.Spin)

proc prepareToFreespins(v: WitchSlotView) =
    let anim = v.playAnim(WitchAnimation.FreeSpinsIn, WitchReturn.FreespinIdle)

    v.soundManager.sendEvent("WITCH_FREESPINS_IN")
    v.potsToFreespins()
    anim.addLoopProgressHandler 0.8, true, proc() =
        v.startFreespinsIntro()

method didBecomeCurrentScene*(v: WitchSlotView)=
    # don't procCall BaseSlotMachineView!!!!111oneOnE!
    if v.freeSpinsCount > 0:
        v.fsStatus = FreespinStatus.Yes
        v.prepareToFreespins()

method restoreState*(v: WitchSlotView, res: JsonNode) =
    procCall v.BaseMachineView.restoreState(res)

    var s: string
    v.setSpinButtonState(SpinButtonState.Blocked)
    v.curPotsStates = @[]

    if res.hasKey($srtFreespinCount):
        v.freeSpinsCount = res[$srtFreespinCount].getInt()
        if v.freeSpinsCount > 0:
            v.stage = GameStage.FreeSpin
        else:
            v.setSpinButtonState(SpinButtonState.Spin)
            v.firstFill()
    else:
        v.setSpinButtonState(SpinButtonState.Spin)
        v.firstFill()

    if res.hasKey($srtFreespinTotalWin):
        v.totalFreeSpinsWinning = res[$srtFreespinTotalWin].getBiggestInt()
    if res.hasKey($srtPots):
        v.potsState = @[]
        s = res[$srtPots].getStr()
        for i in 0..<s.len:
            v.potsState.add(parseInt($(s[i])))
    else:
        v.potsState = @[0, 0, 0, 0 ,0]

    if res.hasKey("paytable"):
        var pd: WitchPaytableServerData
        var paytable = res["paytable"]
        var bep = paytable["bonus_elements_paytable"]

        pd.paytableSeq = res.getPaytableData()
        pd.bonusElementsPaytable = @[]

        for r in bep:
            var row: seq[int] = @[]
            for elem in r:
                row.add(elem.getInt())
            pd.bonusElementsPaytable.add(row)

        pd.magicSpinChance = paytable["magic_spin_chance"].getInt()
        pd.bonusElementsStartAmount = paytable["bonus_start_elements"].getInt()
        if paytable.hasKey("freespin_count"):
            pd.freespinsAllCount = paytable["freespin_count"].getInt()
        v.pd = pd

    currentUser().updateWallet(res[$srtChips].getBiggestInt())
    v.setInitialData()
    v.startIdleForAllPots()
    for states in res[$sdtPotsStates]:
        v.curPotsStates.add($states)
    v.setTimeout 1.0, proc() =
        v.initialFade.changeFadeAnimMode(0, 0.3)
        v.updatePotsStates()
        if s == "44444" or s.len == 0:
            s = "00000"

        v.initPotLights(s == "00000")
        v.checkLights(s)
        v.turnPurples(s)

proc startFreespinIntro(v: WitchSlotView) =
    if v.fsStatus == FreespinStatus.Before:
        let scattersAnim = v.playScattersWin()

        scattersAnim.addLoopProgressHandler 1.0, true, proc() =
            let anim = v.elementsOut()

            anim.onComplete do():
                v.prepareToFreespins()
    elif v.fsStatus == FreespinStatus.After:
        v.fsStatus = FreespinStatus.No

        let anim = v.potsFromFreespins()

        anim.addLoopProgressHandler 0.5, true, proc() =
            v.playAnim(WitchAnimation.InOut)
        proc onDestroy() =
            v.changeWitchPos()
            v.specialWinParent.removeAllChildren()
            v.initialFade.changeFadeAnimMode(0, 0.5)
            v.gameFlow.nextEvent()
        v.winDialogWindow = v.startResultScreen(v.totalFreeSpinsWinning, false, onDestroy)
    else:
        v.gameFlow.nextEvent()

proc prepareToIntro(v: WitchSlotView) =
    if v.linesWin >= TRESHOLDS[0] * v.totalBet:
        proc onDestroy() =
            v.specialWinParent.removeAllChildren()
            v.initialFade.changeFadeAnimMode(0, 0.5)
            v.slotGUI.enableWindowButtons(true)

            if v.fsStatus == FreespinStatus.Before:
                let eOut = v.elementsOut()
                eOut.onComplete do():
                    v.gameFlow.nextEvent()
            else:
                v.gameFlow.nextEvent()
        v.onBigWinHappend(v.getBigWinType, v.currentBalance - v.linesWin)
        v.winDialogWindow = v.startBigwinScreen(v.linesWin, onDestroy)
    elif v.check5InARow():
        v.startFiveInARow()
    else:
        v.gameFlow.nextEvent()

proc showBonus(v: WitchSlotView) =
    if v.bonusField.len > 0:
        let anim = v.potBonusEffect()

        anim.onComplete do():
            v.startBonusIntro()
    else:
        v.gameFlow.nextEvent()

method clickScreen(v: WitchSlotView) =
    discard v.makeFirstResponder()

proc initGameFlow(v: WitchSlotView) =
    let notif = v.notificationCenter

    notif.addObserver("GF_SPIN", v) do(args: Variant):
        v.setSpinButtonState(SpinButtonState.Blocked)
        v.spinReady()

    notif.addObserver("GF_RESPINS", v) do(args: Variant):
        v.magicSpin()
        if v.currentMagicSpinReel != -1:
            v.playAnim(WitchAnimation.MagicSpin)
            v.potMagicSpin(v.currentMagicSpinReel)

    notif.addObserver("GF_SPIDER", v) do(args: Variant):
        v.spiderSpit()

    notif.addObserver("GF_SHOW_WIN", v) do(args: Variant):
        v.showLinesAndGlares()

    notif.addObserver("GF_RUNES", v) do(args: Variant):
        v.fallRunes()

    notif.addObserver("GF_SPECIAL", v) do(args: Variant):
        v.prepareToIntro()

    notif.addObserver("GF_BONUS", v) do(args: Variant):
        v.showBonus()

    notif.addObserver("GF_FREESPINS_INTRO", v) do(args: Variant):
        v.startFreespinIntro()

    notif.addObserver("GF_FREESPINS", v) do(args: Variant):
        v.startFreeSpins()

    notif.addObserver("GF_LEVELUP", v) do(args: Variant):
        v.pushNextState()

method viewOnEnter*(v: WitchSlotView) =
    procCall v.BaseMachineView.viewOnEnter()
    v.soundManager = newSoundManager(v)
    v.soundManager.loadEvents(SOUND_PATH_PREFIX & "witch", "common/sounds/common")
    v.initGameFlow()
    v.startBackgroundIdleAnimations()
    v.playBackgroundMusic(MusicType.Main)
    v.specialWinParent = v.slotGUI.rootNode.newChild("special_win_parent")

method viewOnExit*(v: WitchSlotView) =
    v.clearBackgroundIdleAnimations()
    cleanPendingStates(SlotNextEventFlowState)
    procCall v.BaseMachineView.viewOnExit()

proc createTestButton(v: WitchSlotView, action: proc()) =
    let button = newButton(newRect(50, 550, 100, 50))
    button.title = "Test"
    button.onAction do():
        if not action.isNil:
            action()
    v.addSubview(button)

method initAfterResourcesLoaded(v: WitchSlotView) =
    procCall v.BaseMachineView.initAfterResourcesLoaded()
    v.setSpinButtonState(SpinButtonState.Blocked)
    v.mainParent = v.rootNode.newChild("main_parent")
    v.mainScene = newNodeWithResource(GENERAL_PREFIX & "slot/witch_main_scene.json")
    v.mainParent.addChild(v.mainScene)
    v.backgroundIdleTimers = @[]
    v.backgroundIdleAnims = @[]

    v.createWitch()
    v.pots = newNodeWithResource(GENERAL_PREFIX & "pots/main.json")
    v.mainParent.findNode("parent_pots").addChild(v.pots)
    v.elementsParent = newNodeWithResource(GENERAL_PREFIX & "slot/precomps/spin.json")
    v.pots.findNode("root_elements").addChild(v.elementsParent)
    v.winNumbersParent = v.rootNode.newChild("win_lines_parent")
    v.freespinsPlus = newNodeWithResource("slots/witch_slot/winning_line/precomps/free_spins_plus.json")
    v.rootNode.addChild(v.freespinsPlus)
    v.magicSpinMessage = newNodeWithResource("slots/witch_slot/winning_line/precomps/magic_spin.json")
    v.rootNode.addChild(v.magicSpinMessage)
    v.bonusParent = v.rootNode.newChild("bonus_parent")

    let fadeParent = newNode("fade_parent")
    let bgParticle = newNodeWithResource("slots/witch_slot/particles/bg_particles.json")
    let fgParticle = newNodeWithResource("slots/witch_slot/particles/fg_particles.json")

    v.mainScene.findNode("particles_bg_parent").addChild(bgParticle)
    v.mainParent.addChild(fgParticle)
    v.mainParent.addChild(fadeParent)

    #########################

    proc test() = discard
        # let test = newLocalizedNodeWithResource("tiledmap/anim/precomps/candy2_improvement2_idle")
        # v.rootNode.addChild(test)
        # test.position = newVector3(0, 300)

    #########################
    when defined(debug):
        v.createTestButton(test)
    v.initialFade = addFadeSolidAnim(v, fadeParent, blackColor(), VIEWPORT_SIZE, 0.0, 1.0, 0)

method init*(v: WitchSlotView, r: Rect) =
    procCall v.BaseMachineView.init(r)
    v.gameFlow = newGameFlow(GAME_FLOW)
    v.gLines = 20
    v.potsState = @[]
    v.potsRunes = @[]
    v.elementIdles = @[]
    v.currentMagicSpinReel = -1
    v.wildChildIndex = -1
    v.addDefaultOrthoCamera("Camera")

method resizeSubviews*(v: WitchSlotView, oldSize: Size) =
    const fr = 4/3
    const tr = 16/9
    let camera = v.camera
    var ratio = (tr - v.frame.width / v.frame.height) / (tr - fr)
    ratio = min(1.0, max(0.0, ratio))

    let diffY = 96 * ratio
    let viewportSize = newSize(1920, 1080 + diffY)

    camera.viewportSize = viewportSize
    camera.node.positionX = viewportSize.width / 2
    camera.node.positionY = viewportSize.height / 2

    v.mainParent.positionY = -(96 / 2 - diffY)
    procCall v.BaseMachineView.resizeSubviews(oldSize)

method onKeyDown*(v: WitchSlotView, e: var Event): bool =
    discard procCall v.BaseMachineView.onKeyDown(e)
    case e.keyCode:
    of VirtualKey.Space:
        if v.bonusParent.children.len == 0:
            if not v.slotGUI.gameEventsProcessing:
                v.onSpinClick()
        else:
            currentNotificationCenter().postNotification("WITCH_BONUS_SPACE_CLICK")
    else:
        discard
    if not result and e.modifiers.anyOsModifier():
        when defined(debug):
            case e.keyCode:
            of VirtualKey.C:
                v.cheatMagicSpin = true
                v.onSpinClick()
            else:
                discard
    result = true

method assetBundles*(v: WitchSlotView): seq[AssetBundleDescriptor] =
    const ASSET_BUNDLES = [
        assetBundleDescriptor("slots/witch_slot/bonus"),
        assetBundleDescriptor("slots/witch_slot/elements"),
        assetBundleDescriptor("slots/witch_slot/particles"),
        assetBundleDescriptor("slots/witch_slot/paytable"),
        assetBundleDescriptor("slots/witch_slot/pots"),
        assetBundleDescriptor("slots/witch_slot/slot"),
        assetBundleDescriptor("slots/witch_slot/winning_line"),
        assetBundleDescriptor("slots/witch_slot/witch"),
        assetBundleDescriptor("slots/witch_slot/special_win"),
        assetBundleDescriptor("slots/witch_slot/sound")
    ]
    result = @ASSET_BUNDLES
