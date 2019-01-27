import
    tables, random, json, strutils, sequtils, times, hashes, math, algorithm,

    nimx.view, nimx.image, nimx.context,
    nimx.button, nimx.animation, nimx.window,
    nimx.timer, nimx.text_field, nimx.view_event_handling,
    nimx.notification_center,

    rod.rod_types, rod.node, rod.viewport,
    rod.component, rod.component.sprite, rod.component.particle_emitter, rod.component.ui_component,
    rod.component.camera, rod.component.overlay, rod.component.solid, rod.component.channel_levels, rod.component.particle_system,
    rod.component.text_component, rod.component.clipping_rect_component, rod.ray, rod.component.trail, rod.component.visual_modifier, rod.component.rti, rod.component.mask,
    rod.component.clipping_rect_component, rod.asset_bundle,

    core.net.server, shared.user, shared.chips_animation, core.slot.base_slot_machine_view, shared.director,
    shared.gui.gui_pack, shared.gui.gui_module, shared.gui.win_panel_module, shared.gui.total_bet_panel_module, shared.gui.paytable_open_button_module,
    shared.gui.mermaid_rules_module, shared.gui.gui_module_types, shared.gui.spin_button_module, shared.gui.money_panel_module, quest.quests, shared.gui.slot_gui,
    shared.gui.autospins_switcher_module, shared.window.window_manager, shared.window.button_component,

    falconserver.slot.machine_base_types, falconserver.slot.slot_data_types,

    utils.sound, utils.sound_manager, utils.animation_controller, utils.game_state, utils.pause,

    caustic, mermaid_response, mermaid_bg, win_line_helpers_mermaid, utils.displacement

import slots.balloon.bonus_game_panel
import shared.window.button_component

import reeel_spin
import mermaid_controller
import anim_helpers
import reel_loop_component
import reelset

import sprite_digits_component
import mermaid_msg
import mermaid_sound
import paytable_post
import skip_listener
import core / flow / flow_state_types

const PARENT_PATH = "slots/mermaid_slot/"
const SPIN_SPEED_DURATION_MIN = 0.375
const MIN_STOP_TIMEOUT = 2.0 # Stop button will be enabled as soon as server replies but not sooner than this value.
const REEL_COUNT = 5
const ROWS_COUNT = 3

const GAME_FLOW = ["GF_SPIN", "GF_SHOW_WIN", "GF_BONUS", "GF_FREESPIN", "GF_SPECIAL_WIN", "GF_LEVELUP", "GF_FINAL"]


type
    PaytableServerData* = tuple
        itemset: seq[string]
        paytableSeq: seq[seq[int]]
        freespTriggerId: string
        freespRelation: seq[tuple[triggerCount: int, freespinCount: int]]
        bonusTriggerId: string
        bonusCount: int

type
    MermaidMachineView* = ref object of BaseMachineView
        bg: MermaidBG
        reels: Reelset
        mermaid: MermaidController
        wildFrames: seq[WildFrame]

        reelsParticles: seq[ParticleSystem]

        msg: MermaidMSG
        msgComplete: proc()

        winLines: seq[WinLineData]
        linesSeqProc: seq[proc(delta: float32, clbck: proc()): int]

        bIsFreespin: bool

        roundWin: int64
        freespinWin: int64
        totalBonusWin: int64

        bonusResults: seq[int64]

        prevResponse: Response
        currResponse: Response

        bMermaidOnSwim: bool
        bForceStop: bool
        mOnSpin: bool
        onSpinCheck: seq[proc()]

        bWas5InARow: bool

        bHasAnticipation: bool

        bonusPanel: BonusGamePanel
        bonusRulesPanel: MermaidRulesModule
        bonusCounterPanel: MermaidCounterModule

        doLinesSkip: bool

        doBigwinMsgSkip: bool

        pd*: PaytableServerData
        bonusConfigRelation: seq[int]

template bOnSpin*(v: MermaidMachineView): bool = v.mOnSpin
template `bOnSpin=`*(v: MermaidMachineView, val: bool) =
    v.mOnSpin = val
    for p in v.onSpinCheck:
        p()
    v.onSpinCheck = @[]

method spinSound*(v: MermaidMachineView): string =
    "SPIN_BUTTON_MERMAID_SFX"

proc fillReelStack(v: MermaidMachineView) =
    v.winLines = @[]
    v.bonusResults = @[]
    v.freespinWin = 0
    v.roundWin = 0
    v.totalBonusWin = 0
    if v.currResponse.stages.len > 0:
        var currStage: mermaid_response.Stage
        for st in v.currResponse.stages:
            if st.stage == SpinStage or st.stage == FreeSpinStage:
                currStage = st
                if v.currResponse.freespins > 0:
                    v.freespinWin = currStage.totalFreespinWin
                v.roundWin = currStage.payout
                v.winLines = st.lines
            if st.stage == BonusStage:
                v.bonusResults = st.bonusResults
                v.totalBonusWin = st.payout
        v.reels.reelsStack = @[]
        for col in 0..<REEL_COUNT:
            var reel = newSeq[int]()
            for rl in 0..<ROWS_COUNT:
                var elIndex = currStage.symbols[col + rl * REEL_COUNT].int
                reel.add(elIndex)
            v.reels.reelsStack.add(reel)
        v.freeSpinsLeft = v.currResponse.freespins

template isBonusgame(v: MermaidMachineView): bool = v.bonusResults.len != 0

template isFreespins(v: MermaidMachineView): bool = v.freeSpinsLeft >= 1

template check5InARow(v: MermaidMachineView, ln: WinLineData) = v.bWas5InARow = ((ln.symbols == 5) or v.bWas5InARow)

proc removeWildFrames(v: MermaidMachineView) =
    proc doUp(wf: WildFrame) =
        v.wait(0.5) do():
            var anim = wf.rootNode.doUpAnim(wf.rootNode.positionY, -1000.0, SPIN_SPEED_DURATION_MIN)
            anim.onComplete do():
                wf.rootNode.removeFromParent()
                anim = nil
    if v.wildFrames.len > 0:
        var framesSeq = newSeq[WildFrame]()
        for fr in v.wildFrames: framesSeq.add(fr)

        var lastAnim: Animation
        for i, wf in framesSeq:
            wf.stop do():
                let mermaids = [v.mermaid.standartMermaid.rootNode.findNode("standart_mermaid"), v.mermaid.freespinMermaid.rootNode.findNode("freespin_mermaid")]
                for mr in mermaids:
                    var msk = mr.componentIfAvailable(Mask)
                    while not msk.isNil:
                        mr.removeComponent(Mask)
                        msk = mr.componentIfAvailable(Mask)
            wf.doUp()
    v.wildFrames = @[]

proc playMermaid(v: MermaidMachineView, callback: proc() = nil) =
    v.mermaid.prevMpos = v.mermaid.currMpos
    v.mermaid.currMpos = v.currResponse.mermaidPosition
    var job = callback

    let onWildFrameCreated = proc(wf: WildFrame) =
        if not wf.isNil:
            v.wildFrames.add(wf)
        if not job.isNil:
            job()
            job = nil

    let mermaidWait = v.mermaid.play(v.currResponse.mermaidPosition, onWildFrameCreated)

    v.bMermaidOnSwim = true

    var mermaidModDuration = mermaidWait
    if not v.isFreespins() and not v.isBonusgame():
        mermaidModDuration = mermaidModDuration * 0.85

    v.wait(mermaidModDuration) do():
        v.bMermaidOnSwim = false

proc hideMermaid(v: MermaidMachineView) =
    v.mermaid.prevMpos = v.mermaid.currMpos
    v.mermaid.currMpos = @[(posMiss, posCenter)]
    let mWait = v.mermaid.play(v.mermaid.currMpos) do(wf: WildFrame):
        if not wf.isNil:
            v.wildFrames.add(wf)
    v.wait(mWait) do():
        v.removeWildFrames()

proc prepareResponse(v: MermaidMachineView, res: JsonNode) =
    v.prevResponse = v.currResponse
    var currResponse = newResponse(res)

    # debug currResponse

    if not v.prevResponse.isNil and not currResponse.isNil:
        checkMermaidPosition(v.prevResponse, currResponse)
    v.currResponse = currResponse

    debug v.currResponse, v.lines

    v.fillReelStack()

    var winForSpin: int64 = 0
    if v.currResponse.balance > currentUser().chips:
        winForSpin = v.currResponse.balance - currentUser().chips
    v.spinAnalyticsUpdate(winForSpin, v.isFreespins)

    currentUser().chips = v.currResponse.balance


proc sendSpinRequest(v: MermaidMachineView, callback: proc() = nil) =
    const serverSpinResponseTimeout = 8.0 # If the server does not reply within this value, the game is likely to exit.

    var stopTimeoutElapsed = false
    var autoStopTimeoutElapsed = false

    v.lastField = @[]
    v.paidLines = @[]
    v.reels.reelsStack = @[]

    v.sendSpinRequest(v.totalBet) do(res: JsonNode):
        v.prepareResponse(res)
        if not callback.isNil:
            callback()

proc stopSpin(v: MermaidMachineView) =
    proc canStop(): bool = v.reels.reelsStack.len > 0 and v.reels.canStopSpin and not v.bMermaidOnSwim
    v.waitUntil(canStop) do():
        v.reels.stopFirstReel()

proc playAppearanceSounds(v: MermaidMachineView, reelIndex: int = 0, scatterCount: var int) =
    var scatterType: int
    if not v.reels.tryGetElementIndex("scatter", scatterType):
        return

    var bonusType: int
    if not v.reels.tryGetElementIndex("bonus", bonusType):
        return

    for st in v.currResponse.stages:
        if st.stage == SpinStage or st.stage == FreeSpinStage:
            for i in 0..<ROWS_COUNT:
                if st.symbols[reelIndex + i * REEL_COUNT] == scatterType:
                    v.playScatterAppear()
                    inc scatterCount
                if st.symbols[reelIndex + i * REEL_COUNT] == bonusType:
                    v.playBonusAppear()

proc checkElemInReel(v: MermaidMachineView, reelIndex: int, onScatter, onBonus: proc(indx: int)) =
    var scatterType: int
    var bonusType: int
    discard v.reels.tryGetElementIndex("scatter", scatterType)
    discard v.reels.tryGetElementIndex("bonus", bonusType)
    for st in v.currResponse.stages:
        if st.stage == SpinStage or st.stage == FreeSpinStage:
            for i in 0..<ROWS_COUNT:
                if st.symbols[reelIndex + i * REEL_COUNT] == scatterType:
                    onScatter(i)
                if st.symbols[reelIndex + i * REEL_COUNT] == bonusType:
                    onBonus(i)

proc reelStopper(v: MermaidMachineView) =
    var bonusCount: int = 0
    var scatterCount: int = 0
    let onScatter = proc(indx: int) = inc scatterCount
    let onBonus = proc(indx: int) = inc bonusCount

    var deltaWait = 0.25
    var startTime = 0.0

    const winLineExp = 1.0
    const bonusExp = 1.5
    const scatterExp = 1.5

    v.bHasAnticipation = false
    var prevWait: float32
    var wasBonus: bool
    var bOnce = false

    proc playMermaidAnticipation() =
        if v.bHasAnticipation and v.mermaid.bCanPlayMermaidAnticipation and not bOnce:
            bOnce = true
            # v.bMermaidOnSwim = true
            if not v.isFreespins():
                v.mermaid.standartMermaid.play(Jump) do():
                    # v.bMermaidOnSwim = false
                    v.mermaid.standartMermaid.play(SimpleIdle)
                # SOUNDS
                v.playMermaidAnticipation()

    for i in 0..<v.reels.reelsStopper.len:
        closureScope:
            let index = i

            v.checkElemInReel(index, onScatter, onBonus)

            if index >= 2 and v.winLines.len > 0:
                deltaWait = winLineExp

                if index >= 3:
                    v.bHasAnticipation = true

            if wasBonus:
                v.bHasAnticipation = true

            if bonusCount > 0 and index == v.reels.reelsStopper.len-2:
                deltaWait = bonusExp
                wasBonus = true

            if index >= 1 and scatterCount > 1:
                deltaWait = scatterExp

                if index != v.reels.reelsStopper.len-1:
                    v.bHasAnticipation = true

            if v.bHasAnticipation:
                let antisipDuration = deltaWait

                v.wait(startTime) do():
                    v.reels.reelsStopper[index] = true
                    playMermaidAnticipation()

                v.wait(startTime-prevWait) do():
                    v.playAnticipationSound(antisipDuration)

                    v.reelsParticles[index].start()
            else:
                v.wait(startTime) do():
                    v.reels.reelsStopper[index] = true
                    playMermaidAnticipation()

            prevWait = deltaWait

            startTime += deltaWait


proc playHighlightOnSpin(v: MermaidMachineView, reelIndex: int, elemsTable: var Table[tuple[col: int, row: int], bool]) =
    if not v.bForceStop:
        let backNode = v.bg.rootNode.findNode("lines_back")
        backNode.show(0.0)
        for ln in v.winLines:
            if reelIndex < ln.symbols.int:
                if not elemsTable.getOrDefault((reelIndex, v.lines[ln.index.int][reelIndex].int)):
                    elemsTable[(reelIndex, v.lines[ln.index.int][reelIndex].int)] = true

                    let reelIndex = reelIndex
                    let lnIndex = ln.index.int
                    let currIndx = v.lines[lnIndex][reelIndex]
                    let sortedNds = v.reels.getSortedNodes(reelIndex)
                    let currNd = sortedNds[currIndx+v.reels.stopCellFromTop]

                    let highlightNode = createHighlightNd(backNode, currNd)
                    if not highlightNode.isNil:
                        let hgAnim = highlightNode.animationNamed("play")
                        hgAnim.loopDuration = hgAnim.loopDuration * 0.5
                        v.addAnimation(hgAnim)

        let onScatter = proc(indx: int) =
            let currNd = v.reels.getSortedNodes(reelIndex)[indx+v.reels.stopCellFromTop]
            let highlightNode = createHighlightNd(backNode, currNd)
            if not highlightNode.isNil:
                let hgAnim = highlightNode.animationNamed("play")
                hgAnim.loopDuration = hgAnim.loopDuration * 0.5
                v.addAnimation(hgAnim)

        v.checkElemInReel(reelIndex, onScatter, onScatter)

proc tryPlayFreespins(v: MermaidMachineView) =
    if (v.prevResponse.isNil or v.prevResponse.freespins == 0) and v.currResponse.freespins > 0: # freespins starts
        discard
    elif (not v.prevResponse.isNil and v.prevResponse.freespins > 1) and v.currResponse.freespins == 1: # freespins just stop
        # v.slotGUI.spinButtonModule.stopFreespins()
        discard
    elif (not v.prevResponse.isNil and v.prevResponse.freespins > 1) and v.currResponse.freespins > 1: # freespins continue
        v.slotGUI.spinButtonModule.setFreespinsCount(v.currResponse.freespins.int - 1)
    else: # no freespins
        discard

proc startSpin(v: MermaidMachineView, callback: proc() = nil) =
    v.bForceStop = false
    v.bOnSpin = true

    # shift up mermaid win frames or do nothing if frames does not exist in curr spin
    v.removeWildFrames()

    v.sendSpinRequest do():
        # ANALYTICS
        v.BaseMachineView.onSpinClickAnalytics()

        v.playMermaid()

    v.tryPlayFreespins()

    let onCanStop = proc() =
        proc canStop(): bool = v.reels.reelsStack.len > 0 and not v.bMermaidOnSwim and v.reels.canStopSpin
        v.waitUntil(canStop) do():
            if v.bForceStop:
                v.reels.stop()
            else:
                v.reelStopper()

    var reelCounter = 0
    var scatterCount = 0
    var elemsTable = initTable[tuple[col: int, row: int], bool]()
    let onStop = proc() =
        # SOUND
        v.playReelStop()

        # SOUND
        v.playAppearanceSounds(reelCounter, scatterCount)

        # handle highlight under win elems
        v.playHighlightOnSpin(reelCounter, elemsTable)

        v.reelsParticles[reelCounter].stop()

        inc reelCounter

    v.reels.startSpin(onCanStop, onStop) do():
        # this call when all rees fully stopped
        if scatterCount >= 3:
            v.playFreeSpinsWin()

        if not callback.isNil:
            callback()

        # SOUND
        if v.bHasAnticipation:
            v.playOnAnticipationEnd()

    #SOUND
    v.playSpin()

    # slowdown and stop spin
    v.wait(MIN_STOP_TIMEOUT) do():
        if not v.bForceStop:
            v.stopSpin()

proc setBallanceOnSpin(v: MermaidMachineView, oldChips: int64) =
    if v.freeRounds:
        return
    v.slotGUI.winPanelModule.setNewWin(0)
    v.slotGUI.moneyPanelModule.setBalance(oldChips, oldChips - v.totalBet(), false)

proc playSoundsAfterSpin(v: MermaidMachineView) =
    # PLAY MAIN SOUNDS
    var musicType: MusicType
    if v.isBonusgame():
        musicType = MusicType.Bonus
    elif v.isFreespins():
        musicType = MusicType.Freespins
    else:
        musicType = MusicType.Main

    if musicType != prevMusicTupe:

        v.playBackgroundMusic(musicType)

        prevMusicTupe = musicType

proc onBlockedClick*(v: MermaidMachineView) =
    if not v.bForceStop:
        v.bForceStop = true
        v.stopSpin()

    if not v.reels.isSpin:
        if not v.doLinesSkip:
            v.doLinesSkip = true

            if not v.doBigwinMsgSkip:
                v.doBigwinMsgSkip = true

    let bttn = v.rootNode.findNode("bigwin_button")
    if not bttn.isNil:
        bttn.getComponent(ButtonComponent).sendAction()

method onSpinClick*(v: MermaidMachineView) =
    proc canSpin(): bool = not v.reels.isSpin() and not v.bMermaidOnSwim
    procCall v.BaseMachineView.onSpinClick()
    if v.actionButtonState == SpinButtonState.Stop:
        v.setSpinButtonState(SpinButtonState.Blocked)

    elif v.actionButtonState == SpinButtonState.Spin:
        if canSpin():
            if not v.freeRounds:
                let oldChips = currentUser().chips
                if not currentUser().withdraw(v.totalBet()):
                    v.slotGUI.outOfCurrency("chips")
                    echo "Not enouth chips..."
                    return
                v.setTimeout 0.5, proc() =
                    v.setBallanceOnSpin(oldChips)
            v.setSpinButtonState(SpinButtonState.Blocked)
            v.startSpin do():
                v.gameFlow.start()
                # SOUNDS
                v.playSoundsAfterSpin()

    elif v.actionButtonState == SpinButtonState.Blocked:
        v.onBlockedClick()

method clickScreen(v: MermaidMachineView) =
    if not v.msgComplete.isNil:
        v.msgComplete()
        v.msgComplete = nil
        if v.slotGUI.autospinsSwitcherModule.isOn:
            v.onSpinClick()
    else:
        discard v.makeFirstResponder()


proc createBonusIntroScreen(v: MermaidMachineView, parent: Node, callback: proc()) =
    let n = newLocalizedNodeWithResource(PARENT_PATH & "comps/bonus_game_intro.json")
    # v.rootNode.findNode("bg_prt_anchor").addChild(n) # bg_prt_anchor - node before mermaid msgs

    parent.addChild(n) # bg_prt_anchor - node before mermaid msgs

    # TODO  font hotfix
    n.findNode("mermaid_start_text").removeComponent(ChannelLevels)

    var bRtiCreated = false
    let bgAnchor = v.rootNode.findNode("bg_anchor")
    var bgRTI = bgAnchor.componentIfAvailable(RTI)
    if bgRTI.isNil:
        bRtiCreated = true
        bgRTI = bgAnchor.component(RTI)
        v.wait(0.1) do():
            bgRTI.bFreezeBounds = true
        bgRTI.bBlendOne = true
    else:
        bRtiCreated = false

    let bgBlur = n.findNode("blur_bg")
    let payPost = bgBlur.component(PayBgPost)
    payPost.backNode = bgAnchor

    let fullScrBttn = newButton(newRect(0, 0, 1920, 1080))
    n.component(UIComponent).view = fullScrBttn
    fullScrBttn.hasBezel = false
    let outAnim = n.animationNamed("out")
    let bttnParentNd = n.findNode("start_bonus_button")
    let bttnAnim = bttnParentNd.animationNamed("play")
    let bttnNd = n.findNode("start_button")
    let button = newButton(newRect(0, 0, 308, 120))
    bttnNd.component(UIComponent).view = button
    button.hasBezel = false

    button.onAction do():

        v.addAnimation(bttnAnim)
        v.addAnimation(outAnim)

        outAnim.onComplete do():
            n.removeFromParent()

            if bRtiCreated:
                bgAnchor.removeComponent(RTI)
            bgBlur.removeComponent(PayBgPost)

            callback()

template hideGUIBeforeBonus(v: MermaidMachineView) =
    v.prepareGUItoBonus(true)

    if v.bonusPanel.isNil:
        v.bonusPanel = createBonusGamePanel(v.slotGUI.rootNode, newVector3(1242, 952))
    else:
        v.bonusPanel.show()
    v.bonusPanel.setBonusGameWin(0.int64, false)

    if v.bonusRulesPanel.isNil:
        v.bonusRulesPanel = createMermaidRulesModule(v.slotGUI.rootNode, newVector3(100, 952))
    else:
        v.bonusRulesPanel.show()
    if v.bonusCounterPanel.isNil:
        v.bonusCounterPanel = createMermaidCounterModule(v.slotGUI.rootNode, newVector3(968, 952))
    else:
        v.bonusCounterPanel.show()

template showGUIAfterBonus(v: MermaidMachineView) =
    v.prepareGUItoBonus(false)
    v.bonusPanel.hide()
    v.bonusRulesPanel.hide()
    v.bonusCounterPanel.hide()

proc showBonusGame(v: MermaidMachineView, callback: proc()) =

    let displParent = v.rootNode.newChild("bonus_rules")
    let oldParent = v.msg.rootNode.parent
    v.msg.rootNode.reattach(v.rootNode)
    v.msgComplete = v.msg["bonusgame"] do():
        v.msg.rootNode.reattach(oldParent)

    v.wait(1.0) do():
        v.createBonusIntroScreen(displParent) do():
            displParent.removeFromParent()

    v.hideGUIBeforeBonus()

    var counter = 3
    v.bonusCounterPanel.text($counter)
    v.totalBonusWin = 0.int64
    v.bonusPanel.setBonusGameWin(v.totalBonusWin, true)
    let onCLick = proc(payout: int64) =
        dec counter
        v.bonusCounterPanel.text($counter)
        v.totalBonusWin += payout
        v.bonusPanel.setBonusGameWin(v.totalBonusWin, true)

    v.bMermaidOnSwim = true
    v.reels.rootNode.hide(0.75)
    v.mermaid.rootNode.hide(0.75)
    v.bg.showChests(v.bonusResults, 0.75, onCLick) do():
        v.bMermaidOnSwim = false
        v.bg.hideChests()
        v.reels.rootNode.show(0.25)
        v.mermaid.rootNode.show()

        v.msgComplete = v.msg["bonusgame_result"](callback, v.totalBonusWin)

        v.showGUIAfterBonus()

        v.slotGUI.winPanelModule.setNewWin(v.totalBonusWin, true)

proc showFreespins(v: MermaidMachineView, callback: proc()) =
    v.msgComplete = v.msg["freespin"] do():
        if not callback.isNil: callback()

proc createWinSeq(v: MermaidMachineView, ln: WinLineData): seq[tuple[nd: Node, pr: proc(callback: proc())]] =
    var winElems: seq[tuple[nd: Node, pr: proc(callback: proc())]] = @[]
    var winDuration: float32

    var uniqueElemIndexes = newSeq[int](v.reels.elementsName.len)

    for i in 0..<ln.symbols.int:
        closureScope:
            let reelIndex = i
            let lnIndex = ln.index.int

            let currIndx = v.lines[lnIndex][reelIndex]
            let sortedNds = v.reels.getSortedNodes(reelIndex)

            let currNd = sortedNds[currIndx+v.reels.stopCellFromTop]
            let elementIndex = v.reels.reelsStack[reelIndex][currIndx]

            uniqueElemIndexes[elementIndex] = uniqueElemIndexes[elementIndex] + 1

            var playproc = proc(callback: proc()) =
                let elIdx = elementIndex
                if canPlayLines:
                    winDuration = v.reels.playWin(currNd, elIdx) do():
                        if not v.bOnSpin and not v.isBonusgame() and not v.reels.isSpin():
                            v.reels.playIdle(currNd, elIdx)
                        callback()

            winElems.add((currNd, playproc))

    # SOUNDS
    for i, el in uniqueElemIndexes:
        if el > 0:
            case v.reels.elementName(i):
            of "seahorse": v.playWinHighSymbolSeahorse()
            of "fish": v.playWinHighSymbolFish()
            of "turtle": v.playWinHighSymbolTurtle()
            of "dolphin": v.playWinHighSymbolDolphin()
            of "starfish": v.playWinHighSymbolStar()
            else: discard

    result = winElems

proc removeHightlights(v: MermaidMachineView, backNode: Node) =
    for ch in backNode.children:
        let hgAnim = ch.animationNamed("play")
        hgAnim.loopDuration = hgAnim.loopDuration * 0.5
        hgAnim.loopPattern = lpEndToStart
        v.addAnimation(hgAnim)
        hgAnim.onComplete do():
            ch.removeFromParent()

proc prepareWinLines(v: MermaidMachineView) =
    v.bOnSpin = false

    let backNode = v.bg.rootNode.findNode("lines_back")
    backNode.show(0.0)
    v.removeHightlights(backNode)

    v.linesSeqProc = @[]

    if v.winLines.len > 0:

        let linesNone = v.bg.rootNode.findNode("lines_front")
        linesNone.show(0.0)

        let numbersNone = v.bg.rootNode.findNode("numbers_front")
        numbersNone.show(0.0)

        for ln in v.winLines:
            closureScope:
                let winElems = v.createWinSeq(ln)
                let index = ln.index.int
                let payout = ln.payout.int
                let playProc: proc(delta: float32, clbck: proc()): int = proc(delta: float32, clbck: proc()): int =
                    result = payout
                    # if canPlayLines:
                    linesNone.playLineComp(backNode, winElems, index, delta, clbck)
                    numbersNone.playLineNumber(payout, winElems[2], delta)
                v.linesSeqProc.add(playProc)
                v.check5InARow(ln)

proc hideLines(v: MermaidMachineView) =
    let linesNone = v.bg.rootNode.findNode("lines_front")
    let backNode = v.bg.rootNode.findNode("lines_back")
    let numbersNone = v.bg.rootNode.findNode("numbers_front")

    linesNone.removeAllChildren()
    backNode.removeAllChildren()
    numbersNone.removeAllChildren()
    canPlayLines = false

proc cleanupLines(v: MermaidMachineView) =
    let linesNone = v.bg.rootNode.findNode("lines_front")
    let backNode = v.bg.rootNode.findNode("lines_back")
    let numbersNone = v.bg.rootNode.findNode("numbers_front")

    linesNone.hide(0)
    backNode.hide(0)
    v.linesSeqProc = @[]
    linesNone.removeAllChildren()
    backNode.removeAllChildren()
    numbersNone.removeAllChildren()
    canPlayLines = false

proc playWinLines(v: MermaidMachineView, callback: proc()) =
    if v.linesSeqProc.len > 0:

        v.doLinesSkip = false

        canPlayLines = true

        proc playMermaidWin() =
            if not v.isFreespins() and v.wildFrames.len == 0 and v.mermaid.bCanPlayMermaidAnticipation:
                # v.bMermaidOnSwim = true
                v.mermaid.standartMermaid.play(SwimCircle) do():
                    # v.bMermaidOnSwim = false
                    v.mermaid.standartMermaid.play(SimpleIdle)
                # SOUNDS
                v.playMermaidHappy()

        playMermaidWin()

        var perRoundWin: int64 = 0
        var index = 0
        proc play() =
            template check() =
                if v.doLinesSkip or v.linesSeqProc.len == 0:
                    v.hideLines()
                    v.slotGUI.winPanelModule.setNewWin(v.roundWin, false)
                    callback()
                    return
            check()
            if index < v.linesSeqProc.len:
                check()
                let p = v.linesSeqProc[index]
                let payout = p(0) do():
                    inc index
                    play()
                perRoundWin += payout
                v.slotGUI.winPanelModule.setNewWin(perRoundWin, true)
            else:
                index = 0
                callback()

        play()
    else:
        callback()

proc repeatWinLines(v: MermaidMachineView) =
    canPlayLines = true

    proc canPalay(): bool =
        return v.linesSeqProc.len > 0 and (not v.isBonusgame() and not v.isFreespins() and not v.slotGUI.autospinsSwitcherModule.isOn)

    var index = 0
    proc playLooped() =
        if canPalay():
            let p = v.linesSeqProc[index]
            discard p(1.0) do():
                if canPalay():
                    if index != v.linesSeqProc.len-1:
                        inc index
                    else:
                        index = 0
                    playLooped()
        else:
            v.cleanupLines()
    proc checker() =
        if v.bOnSpin:
            v.cleanupLines()
    v.onSpinCheck.add(checker)

    playLooped()

proc forElementsOfKind(v: MermaidMachineView, kind: int, onFind: proc(n: Node, indx: int)) =
    for st in v.currResponse.stages:
        if st.stage == SpinStage or st.stage == FreeSpinStage:
            for i in 0..<ROWS_COUNT:
                for j in 0..<REEL_COUNT:
                    if st.symbols[j + i * REEL_COUNT] == kind:
                        onFind(v.reels.getSortedNodes(j)[i + v.reels.stopCellFromTop], v.reels.reelsStack[j][i])

proc tryPlayKing(v: MermaidMachineView, callback: proc()) =
    if v.isFreespins():

        var scatterType: int
        var scatterCount: int
        discard v.reels.tryGetElementIndex("scatter", scatterType)
        var winDuration: float32

        v.forElementsOfKind(scatterType) do(n: Node, indx: int):
            inc scatterCount

        if scatterCount > 2:
            v.forElementsOfKind(scatterType) do(n: Node, indx: int):
                winDuration = v.reels.playWin(n, indx) do():
                    discard

            # SOUND
            v.playFreeSpinWin()

            v.wait(winDuration) do():
                callback()
        else:
            callback()
    else:
        callback()

proc tryPlayPrince(v: MermaidMachineView, callback: proc()) =
    if v.isBonusgame():
        var bonusType: int
        discard v.reels.tryGetElementIndex("bonus", bonusType)
        var winDuration: float32

        v.forElementsOfKind(bonusType) do(n: Node, indx: int):
            winDuration = v.reels.playWin(n, indx) do():
                discard

        # SOUND
        v.playBonusWin()

        v.wait(winDuration) do():
            callback()
    else:
        callback()

proc show5InARow(v: MermaidMachineView, callback: proc()) =
    if v.bWas5InARow:
        v.bWas5InARow = false
        v.msgComplete = v.msg["5_in_a_row"](callback)
    else:
        if not callback.isNil: callback()

proc showBigwin(v: MermaidMachineView, callback: proc()) =
    if not v.isBonusgame():
        let bigWin = v.multBig * v.totalBet
        if v.roundWin >= bigWin:
            let hugeWin = v.multHuge * v.totalBet
            let megaWin = v.multMega * v.totalBet

            var bwt = BigWinType.Big
            if v.roundWin >= hugeWin:
                bwt = BigWinType.Huge
            if v.roundWin >= megaWin:
                bwt = BigWinType.Mega
            v.onBigWinHappend(bwt,currentUser().chips - v.roundWin)

            v.msg.setupBigwins(bigWin, hugeWin, megaWin)
            v.msgComplete = v.msg["bigwin"](callback, v.roundWin)
        else:
            if not callback.isNil: callback()
    else:
        if not callback.isNil: callback()

proc showSpecialWin(v: MermaidMachineView, callback: proc()) =
    if v.bIsFreespin and v.freeSpinsLeft == 1:
        # if curresp has win: play win result
        v.msgComplete = v.msg["freespin_result"](callback, v.freespinWin)
        v.slotGUI.winPanelModule.setNewWin(v.freespinWin, false)
        v.hideMermaid()
        v.bIsFreespin = false

        v.slotGUI.spinButtonModule.stopFreespins()
    else:
        if not callback.isNil:
            callback()

proc startChipsAnim(v: MermaidMachineView) =
    let oldBalance = v.slotGUI.moneyPanelModule.getBalance()
    if not v.prevResponse.isNil and not v.currResponse.isNil:
        v.chipsAnim(v.rootNode.findNode("total_bet_panel"), oldBalance, oldBalance + v.roundWin, "")

proc initGameFlow(v: MermaidMachineView)=
    let notif = v.notificationCenter

    notif.addObserver("GF_SPIN", v) do(args: Variant):
        v.gameFlow.nextEvent()
        # v.setSpinButtonState(SpinButtonState.Spin)

    notif.addObserver("GF_SHOW_WIN", v) do(args: Variant):
        v.doLinesSkip = false

        v.prepareWinLines()

        let skip = proc(): bool =
            if v.doLinesSkip:
                v.hideLines()
            return v.doLinesSkip
        let job = proc(clb: proc()) =
            v.playWinLines(clb)

        skipListener(skip, job) do():
            v.doBigwinMsgSkip = false
            v.show5InARow do():
                v.showBigwin do():



                    v.repeatWinLines()
                    v.startChipsAnim()
                    v.gameFlow.nextEvent()

    notif.addObserver("GF_BONUS", v) do(args: Variant):
        if v.isBonusgame():
            v.tryPlayPrince do():
                v.onBonusGameStart()
                v.showBonusGame do():
                    let oldBalance = v.slotGUI.moneyPanelModule.getBalance()
                    if not v.prevResponse.isNil and not v.currResponse.isNil:
                        v.chipsAnim(v.rootNode.findNode("total_bet_panel"), oldBalance, oldBalance + v.totalBonusWin, "")
                    v.onBonusGameEnd()
                    v.gameFlow.nextEvent()
        else:
            v.gameFlow.nextEvent()

    notif.addObserver("GF_FREESPIN", v) do(args: Variant):
        if v.isFreespins():
            v.tryPlayKing do():
                if not v.bIsFreespin:
                    v.slotGUI.spinButtonModule.startFreespins(v.freeSpinsLeft.int)
                    v.bIsFreespin = true
                    v.onFreeSpinsStart()
                    v.showFreespins do():
                        v.startSpin do():
                            v.gameFlow.start()
                else:
                    if v.freeSpinsLeft > 1:
                        v.startSpin do():
                            if not v.prevResponse.isNil and v.prevResponse.freespins < v.currResponse.freespins: # freespins continue
                                v.slotGUI.spinButtonModule.setFreespinsCount(v.currResponse.freespins.int)
                            v.gameFlow.start()
                    else:
                        v.onFreeSpinsEnd()
                        v.gameFlow.nextEvent()
        else:
            v.gameFlow.nextEvent()

    notif.addObserver("GF_SPECIAL_WIN", v) do(args: Variant):
        v.showSpecialWin do():
            v.gameFlow.nextEvent()

    notif.addObserver("GF_LEVELUP", v) do(args: Variant):
        let cp = proc() = v.gameFlow.nextEvent()
        let spinFlow = findActiveState(SpinFlowState)
        if not spinFlow.isNil:
            spinFlow.pop()
        let state = newFlowState(SlotNextEventFlowState, newVariant(cp))
        pushBack(state)

    notif.addObserver("GF_FINAL", v) do(args: Variant):
        v.setSpinButtonState(SpinButtonState.Spin)

method viewOnEnter*(v: MermaidMachineView)=
    procCall v.BaseMachineView.viewOnEnter()
    v.initGameFlow()
    # v.soundManager = newSoundManager(v)
    v.initSounds()
    v.pauseManager = newPauseManager(v)

var displButton: Button
var prtButton: Button
var lowFPSbutton: Button

method viewOnExit*(v: MermaidMachineView)=
    sharedNotificationCenter().removeObserver(v)

    v.bg = nil
    v.reels = nil
    v.mermaid = nil
    v.wildFrames = @[]
    v.reelsParticles = @[]
    v.msg = nil
    v.msgComplete = nil
    v.winLines = @[]
    v.linesSeqProc = @[]
    v.bonusResults = @[]
    v.prevResponse = nil
    v.currResponse = nil

    v.onSpinCheck = @[]
    v.bonusPanel = nil
    v.bonusCounterPanel = nil

    linesCache = initTable[int, Node]()


    displButton = nil
    prtButton = nil
    lowFPSbutton = nil

    procCall v.BaseMachineView.viewOnExit()

method restoreState*(v: MermaidMachineView, res: JsonNode) =
    procCall v.BaseMachineView.restoreState(res)

    v.prepareResponse(res)

    if res.hasKey($srtLines):
        #TODO check in base view class why it does not initialize by default
        v.gLines = v.lines.len

    if res.hasKey($sdtFreespinCount):
        v.freeSpinsLeft = res[$sdtFreespinCount].getInt()
        if v.freeSpinsLeft > 0:
            v.stage = GameStage.FreeSpin
            v.setSpinButtonState(SpinButtonState.Blocked)

    if res.hasKey($sdtFreespinTotalWin):
        v.roundWin = res[$sdtFreespinTotalWin].getBiggestInt()

    if res.hasKey($srtChips):
        currentUser().updateWallet(res[$srtChips].getBiggestInt())
        v.slotGUI.moneyPanelModule.setBalance(0, v.currentBalance, false)

    if res.hasKey("paytable"):
        var pd: PaytableServerData
        let paytable = res["paytable"]
        if paytable.hasKey("items"):
            pd.itemset = @[]
            for itm in paytable["items"]:
                pd.itemset.add(itm.getStr())
        pd.paytableSeq = res.getPaytableData()
        if paytable.hasKey("freespin_trigger"):
            pd.freespTriggerId = paytable["freespin_trigger"].getStr()
        if paytable.hasKey("freespin_count"):
            pd.freespRelation = @[]
            let fr = paytable["freespin_count"]
            for i in countdown(fr.len-1, 0):
                let rel = fr[i]
                if rel.hasKey("trigger_count") and rel.hasKey("freespin_count"):
                    pd.freespRelation.add((rel["trigger_count"].getInt(), rel["freespin_count"].getInt()))
        if paytable.hasKey("bonus_trigger"):
            pd.bonusTriggerId = paytable["bonus_trigger"].getStr()
        if paytable.hasKey("bonus_count"):
            pd.bonusCount = paytable["bonus_count"].getInt()
        if paytable.hasKey("bonus_config"):
            v.bonusConfigRelation = @[]
            for itm in paytable["bonus_config"]:
                v.bonusConfigRelation.add(itm.getInt())

        v.pd = pd

proc initTestButtons(v: MermaidMachineView)

proc addBgParticles(v: MermaidMachineView, bAdd: bool = true) =
    let anchNd = v.rootNode.findNode("bg_prt_anchor")
    if bAdd:
        anchNd.addChild(newNodeWithResource(PARENT_PATH & "comps/bg_particles.json"))
    else:
        anchNd.removeAllChildren()

method initAfterResourcesLoaded(v: MermaidMachineView) =
    # DISPLACEMENT
    let displNode = v.rootNode.newChild("displacement")
    let displAnchorNode = newNode("displ_src")
    v.rootNode.addChild(displAnchorNode)

    v.bg = createBG()
    let bgAnchor = v.rootNode.newChild("bg_anchor")
    bgAnchor.addChild(v.bg.rootNode)
    v.bg.startIdleAnims()
    v.bg.startRandomAnims()
    v.bg.hideChests(0.0)
    v.bg.rootNode.component(ClippingRectComponent).clippingRect = newRect(0.0, 0.0, 1920.0, 1080.0)

    let cellsAnchor = newNodeWithResource(PARENT_PATH & "comps/reelset.json")
    v.reels = cellsAnchor.componentIfAvailable(Reelset)

    discard v.bg.rootNode.findNode("reels").newChild("lines_back")

    let reelsNode = v.bg.rootNode.findNode("reels")
    reelsNode.addChild(cellsAnchor)

    # REELS PARTICLES
    v.reelsParticles = @[]
    var positions = @[newVector3(460,680,0), newVector3(710,680,0), newVector3(970,680,0), newVector3(1230,680,0), newVector3(1480,680,0)]
    for i in 0..<REEL_COUNT:
        let prtclNd = newNodeWithResource(PARENT_PATH & "comps/bubble_spin.json")
        reelsNode.addChild(prtclNd)
        prtclNd.position = positions[i]
        prtclNd.name = prtclNd.name & $i
        v.reelsParticles.add(prtclNd.findNode("PRT_Bubble").componentIfAvailable(ParticleSystem))

    v.mermaid = newMermaidController(v.bg.rootNode)
    v.mermaid.standartMermaid.play(SimpleIdle)

    # lines node
    let linesNone = v.bg.rootNode.newChild("lines_front")
    discard linesNone.component(VisualModifier)
    # numbers node
    let numbersNone = v.bg.rootNode.newChild("numbers_front")

    # PRTCL
    discard v.bg.rootNode.newChild("bg_prt_anchor")

    v.addBgParticles(true)

    v.msg = createMermaidMSG()
    v.bg.rootNode.addChild(v.msg.rootNode)

    v.prevResponse = nil
    v.currResponse = nil

    v.bMermaidOnSwim = false
    v.bIsFreespin = false
    v.bOnSpin = false
    v.onSpinCheck = @[]

    v.initTestButtons()

method init*(v: MermaidMachineView, r: Rect) =
    procCall v.BaseMachineView.init(r)
    v.gameFlow = newGameFlow(GAME_FLOW)

    v.gLines = 35

    # TODO ask about multipliers
    v.multBig = 10
    v.multHuge = 13
    v.multMega = 15

    v.addDefaultOrthoCamera("Camera")

method assetBundles*(v: MermaidMachineView): seq[AssetBundleDescriptor] =
    const ASSET_BUNDLES = [
        assetBundleDescriptor("slots/mermaid_slot")
    ]
    result = @ASSET_BUNDLES

proc addDisplacement(v: MermaidMachineView) =
    let displAnchorNode = v.rootNode.findNode("displ_src")
    var displSrcNode = displAnchorNode.findNode("all_displacement_map")
    if displSrcNode.isNil:
        displSrcNode = newNodeWithResource(PARENT_PATH & "msg_comps/all_displacement_map.json")
        displAnchorNode.addChild(displSrcNode)

    v.addAnimation(displSrcNode.animationNamed("idle"))
    displSrcNode.enabled = false

    let bgAnchor = v.rootNode.findNode("bg_anchor")
    let rtiBg = bgAnchor.component(RTI)
    rtiBg.bDraw = false
    rtiBg.bBlendOne = true
    v.wait(0.5) do():
        rtiBg.bFreezeBounds = true

    let displNode = v.rootNode.findNode("displacement")
    let displComp = displNode.component(Displacement)
    displComp.displacementNode = displSrcNode
    displComp.rtiNode = bgAnchor
    displComp.displSize = newSize(0.0047, 0.0047)

proc removeDisplacement(v: MermaidMachineView) =
    let displSrcNode = v.rootNode.findNode("all_displacement_map")
    if not displSrcNode.isNil:
        displSrcNode.animationNamed("idle").cancel()
        displSrcNode.removeFromParent()

    let displNode = v.rootNode.findNode("displacement")
    if not displNode.isNil:
        displNode.removeComponent(Displacement)

    let bgAnchor = v.rootNode.findNode("bg_anchor")
    if not bgAnchor.isNil:
        bgAnchor.removeComponent(RTI)

proc initTestButtons(v: MermaidMachineView) =
    proc createDisplButton() =
        let bttn = newButton(newRect(10.Coord, 170.Coord, 60.Coord, 20.Coord))
        bttn.title = "displ off"
        bttn.onAction do():
            let displNode = v.rootNode.findNode("displacement")
            let displCom = displNode.componentIfAvailable(Displacement)
            if displCom.isNil:
                bttn.title = "displ on"
                v.addDisplacement()
            else:
                bttn.title = "displ off"
                v.removeDisplacement()
        v.addSubview bttn
        displButton = bttn

    # createDisplButton()

    proc addParticles() =
        var bOn = false
        let bttn = newButton(newRect(10.Coord, 195.Coord, 60.Coord, 20.Coord))
        bttn.title = "prt off"
        bttn.onAction do():
            if not bOn:
                bttn.title = "prt on"
                v.addBgParticles(true)
            else:
                bttn.title = "prt off"
                v.addBgParticles(false)
            bOn = not bOn

        v.addSubview bttn
        prtButton = bttn

    # addParticles()

    proc lowFps() =
        var bOn = false
        let bttn = newButton(newRect(10.Coord, 220.Coord, 60.Coord, 20.Coord))
        bttn.title = "fps off"

        let an = newAnimation()
        an.onAnimate = proc(p: float) =
            for i in 0..4000:
                for j in 0..i:
                    let k = i * j

        bttn.onAction do():
            if not bOn:
                bttn.title = "low fps on"
                v.addAnimation(an)
            else:
                bttn.title = "low fps off"
                an.cancel()
            bOn = not bOn

        v.addSubview bttn
        lowFPSbutton = bttn

    # lowFps()


import nimx.app

method onKeyDown*(v: MermaidMachineView, e: var Event): bool =
    discard procCall v.BaseMachineView.onKeyDown(e)

    case e.keyCode
    of VirtualKey.Space:
        if v.actionButtonState == SpinButtonState.Blocked:
            v.onBlockedClick()

        proc sendMouseEvent(wnd: Window, p: Point, bs: ButtonState) =
            var evt = newMouseButtonEvent(p, VirtualKey.MouseButtonPrimary, bs)
            evt.window = wnd
            discard mainApplication().handleEvent(evt)
        proc pressButton(buttonPoint: Point) =
            sendMouseEvent(v.window, buttonPoint, bsDown)
            sendMouseEvent(v.window, buttonPoint, bsUp)
        pressButton(newPoint(-50.0, -50.0))
    else: discard

    if not result and e.modifiers.anyOsModifier():
        result = true
        case e.keyCode:
        of VirtualKey.Z:
            if not displButton.isNil:
            # and not prtButton.isNil and not lowFPSbutton.isNil:
                displButton.removeFromSuperview()
                displButton = nil
                # prtButton.removeFromSuperview()
                # prtButton = nil
                # lowFPSbutton.removeFromSuperview()
                # lowFPSbutton = nil
            else:
                v.initTestButtons()
        else:
            discard

    result = true
