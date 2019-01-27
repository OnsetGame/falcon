import strformat, strutils, json, tables
import math, random, variant

import nimx / [ types, animation, button, matrixes, animation, button ]

import rod / [ node, asset_bundle, quaternion ]
import rod.component / [ ae_composition, ui_component, gradient_fill, text_component ]

import rod.component.camera
import core.slot.states.slot_states
import core.slot / [ state_slot_machine, base_slot_machine_view, slot_types, state_slot_types ]
import core.flow.flow
import falconserver.slot.machine_card_types
import shared.game_scene
import shared.window.button_component
import card_background
import card_anticipation
import card_sun_anticipation
import card_types
import card_sun_multiplier
import card_event_message
import card_highlights

import node_proxy.proxy
import sequtils

import slots.groovy.reelset_component
import slots.groovy.reel_component
import slots.groovy.groovy_response
import slots.groovy.cell_component

import shafa.slot.slot_data_types

const GENERAL_PREFIX* = "slots/card_slot/"
const HIDDEN_ID = 9
const SUN_MULTI* = 10
const SUN_SCATTER = 11

const BONUSCOORDS: seq[Point] = @[newPoint(340, 200), newPoint(785, 200), newPoint(1230, 200)]
const BUTTON_SIZE: Size = newSize(345, 470)
const LAYERSNAMES: array[3, string] = ["CARD_FREESPINS_INTRO_CHOOSE", "CARD_FREESPINS_INTRO_YOUR", "CARD_FREESPINS_INTRO_GAME"]
const PORTALSNAMES: array[1..3, string] = ["To_blue", "To_green", "To_red"]
const SOUNDPORTALNAMES: array[1..3, string] = ["MOON_SPIN", "SUN_SPIN", "CROW_SPIN"]
const RESULTSNAMES: array[1..3, string] = ["win_bonus_game_H", "win_bonus_game_M", "win_bonus_game_S"]
const FREESPINSNAMES*: array[1..3, string] = ["hidden", "multiplier", "shuffle"]
const FREESPINSNAMESRESTORE: array[1..3, string] = ["hidden_choose_continue", "multi_choose_continue", "shuffle_choose_continue"]
const FREESPINSEVENT: array[1..2, string] = ["choose_free_spins_game", "continue_free_spins_game"]

var startExceptions: seq[seq[int]] = @[ @[9, 10, 11 ], @[9, 10, 11], @[9, 10, 11], @[9, 10, 11], @[9, 10, 11] ]
var mainExceptions: seq[seq[int]] = @[ @[10], @[10, 11], @[10], @[10, 11], @[10] ]
var frHiddenExceptions: seq[seq[int]] = @[ @[9, 10, 11], @[0,1,2,3,4,5,6,7,8,10,11], @[9, 10, 11], @[0,1,2,3,4,5,6,7,8,10,11], @[9, 10, 11] ]
var frMultiExceptions: seq[seq[int]] = @[ @[9, 10, 11], @[9, 10, 11], @[9, 11], @[9, 10, 11], @[9, 10, 11] ]
var frShuffleExceptions: seq[seq[int]] = @[ @[9, 10, 11], @[9, 10, 11], @[9, 10, 11], @[9, 10, 11], @[9, 10, 11] ]

when defined(debug):
    var DBG_BTTN_I = 0

type
    CardForceStop* = ref object of ForceStopState

    CardSlotView* = ref object of StateSlotMachine
        background: BackgroundChest
        portals: BackgroundPortals
        reelsetRoot: Node
        reelset*: ReelsetComponent
        response*: Response
        anticipation: array[5, Anticipation]
        winlinesArray*: WinLinesArray #[ 0..19 ][ {Vector3(50, 30, 0), 1}, {...}, {...}, {...}, {...} ]#
        repeatWinLineAnims*: proc()
        winLinesAnim*:Animation
        fireLinesGroup*: Node
        freespins*: array[3, int]  # fs count for each fs mode
        winlineParent*: Node
        eventMessageParent*: Node
        freeSpinsEventMessage: Node
        pd*: CardPaytableServerData
        sunAnticipation: SunAnticipation
        hightlights*: Highlights
        freeSpinsIndex: int
        particlesNode: Node
        sunMultNodes: seq[Node]
        layers: Node
        reelsShuffled: bool
        indices: array[15, bool]

import card_winlines
import card_paytable

method appearsOn*(s: CardForceStop, o: BaseFlowState): bool =
    result = procCall s.ForceStopState.appearsOn(o)
    if not result:
        result = o.name in ["SunMultiplierState", "SunBonusState"]

method createForceStopState*(ss: CardSlotView): ForceStopState =
    result = ss.newSlotState(CardForceStop)

method init*(v: CardSlotView, r: Rect) =
    procCall v.StateSlotMachine.init(r)
    v.addDefaultOrthoCamera("Camera")
    v.gLines = 20
    v.soundEventsPath = "slots/card_slot/card_sound/card"
    v.timingConfig.spinIdleDuration = 1.0
    v.lines = @[]
    v.paidLines = @[]
    v.repeatWinLineAnims = nil
    v.winLinesAnim = nil
    v.winlinesArray = WinLinesArray()
    v.fireLinesGroup = nil
    v.sunAnticipation = nil
    v.hightlights = nil
    v.freeSpinsIndex = 0
    v.reelsetRoot = nil
    v.particlesNode = nil

proc pickFreespinsState(v: CardSlotView)=
    case v.freespinsStage
    of FREESPINSNAMES[1]: v.freeSpinsIndex = 1
    of FREESPINSNAMES[2]: v.freeSpinsIndex = 2
    of FREESPINSNAMES[3]: v.freeSpinsIndex = 3
    else: discard

method viewOnEnter*(v: CardSlotView)=
    when defined(debug):
        DBG_BTTN_I = 0

    procCall v.StateSlotMachine.viewOnEnter()
    v.camera.node.component(Camera).zNear = -50
    for a in v.anticipation:
        a.sound = v.sound

    v.sound.play("MAIN_BACKGROUND_MUSIC")
    v.sound.play("MAIN_AMBIENCE")

    v.background.startBackgroundParticles()
    v.background.node.addAnimation(v.background.sceneIdleAnim)
    v.reelset.rebuildTextureCache()

proc getAnticipationPosition(v: CardSlotView, hidsmb: seq[seq[int]]): AnticipationPosition =
    var antPos = AnticipationPosition.None
    let reel = 4

    var isAnticipated: bool = true
    var curElemIndex: int = -1 #-1: all elements in winning line are hidden or wild; -2: scatter is on the way, skip line
    var reelStartIndex: int = 0
    var highlightsPerLine: int = -1

    for line in v.lines:
        isAnticipated = true

        #Determine first symbol in winning line. [1..8] counts as starting, [0,9..10] are skipped, 11 break the rule
        while reelStartIndex != reel:

            let cellId = hidsmb[reelStartIndex][2-line[reelStartIndex]]

            if cellId in 1..8:
                curElemIndex = cellId
                break
            elif cellId == SUN_SCATTER:
                curElemIndex = -2
                break

            inc reelStartIndex

        case curElemIndex
        of -1:
            antPos = AnticipationPosition.Both
            break
        of -2:
            isAnticipated = false
            continue
        else:
            discard

        #When appropriate symbol exists, continue building line with the same rule from above
        highlightsPerLine = -1

        for reelIndex in reelStartIndex + 1 .. reel - 1: #1..3
            let cellId = hidsmb[reelIndex][2-line[reelIndex]]
            if not (cellId in @[0, curElemIndex, HIDDEN_ID, SUN_MULTI]):
                isAnticipated = false
                break

            case reelIndex
            of 2:
                if antPos == AnticipationPosition.None:
                    antPos = AnticipationPosition.Forth
                highlightsPerLine = 2
            of 3:
                antPos = AnticipationPosition.Both
                highlightsPerLine = 3
                break
            else:
                discard

        for hl in 0..highlightsPerLine:
            if hidsmb[hl][2-line[hl]] != HIDDEN_ID:
                let fieldIndex = hl + line[hl] * slot_types.NUMBER_OF_REELS
                v.indices[fieldIndex] = true

    if (SUN_SCATTER in hidsmb[0]) and (SUN_SCATTER in hidsmb[2]) and (SUN_SCATTER in hidsmb[4]):
        if antPos == AnticipationPosition.None:
            antPos = AnticipationPosition.Fifth
        elif antPos == AnticipationPosition.Forth:
            antPos = AnticipationPosition.Both

    result = antPos

proc getHidField(v: CardSlotView): seq[seq[int]] =
    v.response = newResponse(v.lastResponce)
    var st = v.response.stages[0]
    var hidSmbs: seq[seq[int]] = st.symbols

    for i in st.hidden:
        let reelIndex = i mod slot_types.NUMBER_OF_REELS
        let rawIndex = i div slot_types.NUMBER_OF_REELS
        hidSmbs[reelIndex][NUMBER_OF_ROWS - 1 - rawIndex] = 9

    result = hidSmbs

method getStateForStopAnim*(v: CardSlotView): WinConditionState =

    result = WinConditionState.NoWin

    if v.getAnticipationPosition(v.getHidField()) >= AnticipationPosition.Forth:
        result = WinConditionState.Line

proc playIdleAnimation*(v: CardSlotView, spElems: seq[seq[int]], cb: proc() = nil) =
    let rc: ReelsetComponent = v.reelset
    for i in 0 .. < spElems.len:
        for j in 0 .. < spElems[i].len:
            let cc = rc.reels[i].elems[spElems[i].len-j-1].getComponent(CellComponent)
            cc.playAnim(OnIdle, lpStartToEnd, nil, true)
    if not cb.isNil:
        cb()

proc playHiddenTurnAnimation*(v: CardSlotView, rs: seq[seq[int]], spElems: seq[int], cb: proc() = nil) =
    let rc: ReelsetComponent = v.reelset
    var reelStopperCounter = spElems.len

    var cbSingle: bool = true
    for i in 0..spElems.len - 1:
        closureScope:
            let reelIndex = spElems[i] mod slot_types.NUMBER_OF_REELS
            let rowIndex = spElems[i] div slot_types.NUMBER_OF_REELS
            let hidNode = rc.reels[reelIndex].elems[rowIndex]
            let cc = hidNode.getComponent(CellComponent)
            if cbSingle == true:
                v.sound.play("HIDDEN_TURN_AND_SHOW")
                cbSingle = false

            let idn = rs[reelIndex][NUMBER_OF_ROWS - 1 - rowIndex]
            cc.resetAnimsOnNode(idn, hidNode, OnTurnEnd)

            proc onTrigger() =
                cc.play(HIDDEN_ID, OnTurnStart, lpStartToEnd, nil, false, true)
                cc.play(idn, OnTurnEnd, lpStartToEnd) do(anim: Animation):
                    dec reelStopperCounter
                    cc.play(idn, OnIdle, lpStartToEnd, nil, true)
                    if reelStopperCounter == 0:
                        cb()

            var anim = newAnimation()
            anim.loopDuration = 0.1
            anim.numberOfLoops = 1
            anim.onComplete do():
                onTrigger()
            rc.node.addAnimation(anim)

    if cbSingle == true:
        cb()

proc createAnticipation(v: CardSlotView) =
    let reelset = v.rootNode.findNode("reelset")
    let parent = reelset.parent
    let index = parent.children.find(reelset)

    let frontNode = newNode("anticipation_front")
    let backNode = newNode("anticipation_back")
    parent.insertChild(
        frontNode,
        index + 1
    )
    parent.insertChild(
        backNode,
        index
    )

    v.anticipation = [
        newAnticipation(backNode, frontNode),
        newAnticipation(backNode, frontNode),
        newAnticipation(backNode, frontNode),
        newAnticipation(backNode, frontNode),
        newAnticipation(backNode, frontNode)
    ]

    v.anticipation[0].position = 0
    v.anticipation[1].position = 1
    v.anticipation[2].position = 2
    v.anticipation[3].position = 3
    v.anticipation[4].position = 4

proc createTestButton(v: CardSlotView, action: proc()) =
    when defined(debug):
        let button = newButton(newRect(50, 150 + 50 * DBG_BTTN_I.float, 100, 50))
        button.title = "Test " & $DBG_BTTN_I
        button.onAction do():
            action()
        v.addSubview(button)
        inc DBG_BTTN_I

proc unshuffle(v: CardSlotView, cb: proc())=
    let callback = proc()=
        if not cb.isNil:
            cb()

    v.reelset.sortReels(callback) do(r1, r2:Node, cb: proc()):
        var a = newAnimation()
        a.numberOfLoops = 1
        a.loopDuration = 0.25
        let ff = r1.position
        let fd = r2.position

        let ss = newVector3(1.0, 1.0, 1.0)
        let bs = newVector3(1.15, 1.15, 1.15)
        let ls = newVector3(0.85, 0.85, 0.85)

        a.addLoopProgressHandler(0.0, false) do():
            v.sound.play("SHUFFLE_" & $rand(1 .. 3))
        a.onAnimate = proc(p: float)=
            var pong = p * 2
            if pong > 1.0: pong = 2 - pong

            r1.position = interpolate(ff, fd, p)
            r1.scale = interpolate(ss, ls, pong)

            r2.position = interpolate(fd, ff, p)
            r2.scale = interpolate(ss, bs, pong)

        a.onComplete do():
            a.removeHandlers()
            cb()

        v.addAnimation(a)

proc getSoundCB(v: CardSlotView): proc(p: float) =
    result = proc (p: float) =
        if p >= 0.999999999999:
            v.sound.stop("POINTS_COUNT_SOUND")

proc onStopEvent(v: CardSlotView): proc(uid: int, reelID: int, deathType: int) =
    result = proc (uid: int, reelID: int, deathType: int) =
        if v.sunAnticipation.idToNode[reelID].hasKey(uid):
            var deathTypeVar: SunDeathType
            case deathType:
                of 0: deathTypeVar = FlyAway
                of 1: deathTypeVar = Fade
                of 2: deathTypeVar = InstaKill
                else:
                    discard
            v.sunAnticipation.removeSunTail(uid, reelID, deathTypeVar)

proc onUpdate(v: CardSlotView): proc(uid: int, reelID: int, positionY: float) =
    result = proc(uid: int, reelID: int, positionY: float) =
        if v.sunAnticipation.idToNode[reelID].hasKey(uid):
            v.sunAnticipation.updateSunTail(uid, reelID, positionY)

proc onSunTailSpawn(v: CardSlotView): proc(uid: int, reelID: int, pos: Vector3, shiftSpeed: float32) =
    result = proc(uid: int, reelID: int, pos: Vector3, shiftSpeed: float32) =
        v.sunAnticipation.createSunTail(uid, reelID, pos, shiftSpeed)
        v.sound.play("SUN_TAIL_FLY")

proc animOnReelStop(v: CardSlotView, reelID: int, cb: proc()) =
    let reelset = v.reelset
    let rl = reelset[reelID].node.getComponent(ReelComponent)

    v.response = newResponse(v.lastResponce)
    var st = v.response.stages[0]

    var ifHiddenDetected: bool = false
    var isFirstHidden: bool = false
    for i, ch in rl.elems:
        closureScope:
            let ii = i
            let cch = ch
            let cell = cch.component(CellComponent)
            var ihd = ifHiddenDetected
            var ifh = isFirstHidden
            if ii < 3:
                let currId = st.symbols[reelID][2 - ii]
                for k in st.hidden:
                    if reelID + ii * slot_types.NUMBER_OF_REELS == k:
                        if ihd == false:
                            ihd = true
                            ifHiddenDetected = ihd
                        cell.play(HIDDEN_ID, OnTurnStart, lpStartToEnd) do(anim: Animation):
                            cell.play(HIDDEN_ID, OnTurnIdle, lpStartToEnd, nil, true, false)
                            if ifh == false:
                                ifh = true
                                if not cb.isNil:
                                    cb()
                        break
                    else:
                        if not currId in SUN_MULTI .. SUN_SCATTER:
                            cell.play(currId, OnIdle, lpStartToEnd, nil, true)
                        else:
                            cell.play(currId, OnIdle, lpStartToEnd, nil, false, true)
                if ihd == false:
                    if not currId in SUN_MULTI .. SUN_SCATTER:
                        cell.play(currId, OnIdle, lpStartToEnd, nil, true)
                    else:
                        cell.play(currId, OnIdle, lpStartToEnd, nil, false, true)
    if not ifHiddenDetected and not cb.isNil:
        cb()

proc setReelsetReactions(v: CardSlotView, isTurnedON: bool = true) =
    var onSpawnProc: proc(uid: int, reelID: int, pos: Vector3, shiftSpeed: float32) = if isTurnedON: v.onSunTailSpawn() else: nil
    var onUpdateProc: proc(uid: int, reelID: int, positionY: float) = if isTurnedON: v.onUpdate() else: nil
    var onElementsStopProc: proc(uid: int, reelID: int, deathType: int) = if isTurnedON: v.onStopEvent() else: nil

    for i in v.reelset.reels:
        i.node.getComponent(ReelComponent).setOnSpawnProc(@[10, 11], onSpawnProc)
        i.node.getComponent(ReelComponent).setOnUpdateProc(@[10, 11], onUpdateProc)
        i.node.getComponent(ReelComponent).setOnElementStopProc(@[10, 11], onElementsStopProc)

proc regSlotRestoreState(v: CardSlotView)=
    v.registerReaction("SlotRestoreState") do(state: AbstractSlotState):
        echo "Entering SlotRestoreState"
        let res = state.SlotRestoreState.restoreData
        v.winlineParent = newNode("winline_parent")
        v.reelset.node.addChild(v.winlineParent)
        v.eventMessageParent = newNode("event_message_parent")
        v.rootNode.addChild(v.eventMessageParent)
        v.freeSpinsEventMessage = newNode("free_spins_event_message")
        v.rootNode.addChild(v.freeSpinsEventMessage)
        v.initWinLinesCoords()
        var fs = newSeq[int]()

        if res.hasKey("paytable"):
            var pd: CardPaytableServerData
            var paytable = res["paytable"]

            pd.paytableSeq = res.getPaytableData()
            v.pd = pd

        if v.freespinsCount == 0:
            v.freespinsStage = "NoFreespin"
            echo "\n\nv.freespinsStage = NoFreespin\n\n"
        v.pickFreespinsState()
        state.finish()

proc regSpinInAnimationState(v: CardSlotView)=
    v.registerReaction("SpinInAnimationState") do(state: AbstractSlotState):
        proc onStateStop() =
            state.finish()

        v.hightlights.cleanUp()

        v.sound.play("SPIN_" & $rand(1 .. 3))
        v.reelset.play(onStateStop)

proc regSpinOutAnimationState(v: CardSlotView)=
    v.registerReaction("SpinOutAnimationState") do(state: AbstractSlotState):
        echo "SpinOutAnimationState"
        v.response = newResponse(v.lastResponce)

        for sun in v.sunMultNodes:
            sun.hideAll()
        v.sunMultNodes.setlen(0)

        var isForceStop = false
        var isHiddenForceStop = false
        var st = v.response.stages[0]

        let oldTimings = v.reelset.stopTimings

        for i, value in v.indices:
            v.indices[i] = false

        var hidSmbs = v.getHidField()

        let anticipationPos = v.getAnticipationPosition(v.getHidField())

        v.reelsShuffled = false

        #Every time spin enters spinout state, update paid lines
        v.paidLines = @[]
        for item in st.lines:
            let line = PaidLine.new()
            line.winningLine.numberOfWinningSymbols = item.symbols
            line.winningLine.payout = cast[int32](item.payout)
            line.index = item.index
            v.paidLines.add(line)

        proc onStateStop() =
            v.reelset.stopTimings = oldTimings
            if v.reelsShuffled:
                let anticipationAnim = newAnimation()
                anticipationAnim.loopDuration = 2.0
                anticipationAnim.numberOfLoops = 1
                anticipationAnim.addLoopProgressHandler(0.0, false) do():
                    for anticipation in v.anticipation:
                        anticipation.start()
                    v.anticipation[0].sound.play("ANTICIPATION_SOUND")
                anticipationAnim.onComplete do():
                    anticipationAnim.removeHandlers()
                    for anticipation in v.anticipation:
                        anticipation.stop()
                    v.anticipation[0].sound.stop("ANTICIPATION_SOUND")
                    v.anticipation[0].sound.play("ANTICIPATION_STOP_SOUND")
                    v.unshuffle() do():
                        state.finish()
                v.reelset.node.addAnimation(anticipationAnim)
            else:
                state.finish()

        proc onReelLand(reelIndex: int) =
            case reelIndex:
            of 1:
                if not isForceStop and v.freespinsStage == FREESPINSNAMES[1]:
                    v.anticipation[1].stop()
            of 2:
                if not isForceStop and v.freespinsStage != FREESPINSNAMES[1] and v.freespinsStage != FREESPINSNAMES[3]:
                    if anticipationPos in @[AnticipationPosition.Forth, AnticipationPosition.Both]:
                        v.anticipation[3].start()
                        v.anticipation[3].sound.play("ANTICIPATION_SOUND")
            of 3:
                if not isForceStop and v.freespinsStage != FREESPINSNAMES[3]:
                    v.anticipation[3].stop()
                    if anticipationPos in @[AnticipationPosition.Fifth, AnticipationPosition.Both]:
                        v.anticipation[4].start()
                        if anticipationPos == AnticipationPosition.Fifth or v.freespinsStage == FREESPINSNAMES[1]:
                            v.anticipation[4].sound.play("ANTICIPATION_SOUND")
                    elif anticipationPos == AnticipationPosition.Forth:
                        v.anticipation[3].sound.stop("ANTICIPATION_SOUND")
            of 4:
                if v.freespinsStage != FREESPINSNAMES[3]:
                    v.anticipation[4].stop()
                    v.anticipation[3].sound.stop("ANTICIPATION_SOUND")
                    v.anticipation[4].sound.stop("ANTICIPATION_SOUND")
            else:
                discard

        proc onReelStop(reelIndex: int) =

            if reelIndex != 4:
                v.animOnReelStop(reelIndex, nil)

            case reelIndex:
            of 2:
                v.playHighLight(@[0, 1, 2], v.indices)

                #In some cases, highlights appear when 2 scatters appear in line 0 and 2 accordingly
                if SUN_SCATTER in st.symbols[0] and SUN_SCATTER in st.symbols[2]:
                    let scatterReels: seq[int] = @[0, 2]
                    for reelIndex in scatterReels: #0 2 4
                        for j in 0 .. < st.symbols[reelIndex].len:
                            if st.symbols[reelIndex][j] == SUN_SCATTER:
                                let reelNode = v.reelset.reels[reelIndex].node
                                let cellElementNode = reelNode.children[2-j]
                                v.hightlights.onHighlightAnim(cellElementNode, reelIndex, true, "SUN_SCATTER")
            of 3:
                v.playHighLight(@[3], v.indices)
            of 4:
                v.animOnReelStop(reelIndex) do():
                    v.playHiddenTurnAnimation(st.symbols, st.hidden, onStateStop)
                    isHiddenForceStop = true
                v.playHighLight(@[4], v.indices)
                for i in 1..3:
                    v.sound.stop("SPIN_" & $i)
            else:
                discard

        if anticipationPos >= AnticipationPosition.Forth and v.freespinsStage != FREESPINSNAMES[3]:
            v.setRotationAnimSettings(
                ReelsAnimMode.Short,
                v.getStateForStopAnim(),
                (bonusReels: @[], scatterReels: @[])
            )

            v.reelset.stopTimings[3] += v.animSettings[3].time
            v.reelset.stopTimings[4] += v.animSettings[4].time

            if anticipationPos >= AnticipationPosition.Fifth:
                v.reelset.stopTimings[4] += v.animSettings[3].time

        if v.freespinsStage == FREESPINSNAMES[3]:
            v.reelsShuffled = true
            v.reelset.setOnReelsLandProc(0.2, nil)
            v.reelset.shuffledStop(hidSmbs, onReelStop)
        else:
            if v.freespinsStage == FREESPINSNAMES[1]:
                v.anticipation[1].start()
                v.anticipation[3].start()
                v.anticipation[3].sound.play("ANTICIPATION_SOUND")
            v.reelset.stop(hidSmbs, onReelStop)

        v.reelset.setOnReelsLandProc(0.2, onReelLand)

        let oldCancel = state.cancel
        state.SpinOutAnimationState.cancel = proc() =
            isForceStop = true
            if isHiddenForceStop:
                for reel in v.reelset.reels:
                    for elem in reel.elems:
                        let currentAnims = elem.getComponent(CellComponent).getAnims(OnTurnEnd)
                        for i in currentAnims:
                            i.cancel()
                        let currentAnimsB = elem.getComponent(CellComponent).getAnims(OnTurnEnd)
                        for i in currentAnimsB:
                            i.cancel()

            v.reelset.forceStop()
            for a in v.anticipation:
                a.quickStop()

            if not oldCancel.isNil:
                oldCancel()

proc regShowWinningLine(v: CardSlotView) =
    v.registerReaction("ShowWinningLine") do(state: AbstractSlotState):
        v.response = newResponse(v.lastResponce)
        let wl = state.ShowWinningLine

        proc stateFinished() =
            state.finish()

        v.playWinLine(wl.line, v.response.stages[0].symbols, stateFinished)

        state.ShowWinningLine.cancel = proc() =
            let r = v.winlinesArray.lines[wl.line.index].animComposite

            r.removeHandlers()
            r.cancel()

            for reel in v.reelset.reels:
                for elem in reel.elems:
                    let currentAnims = elem.getComponent(CellComponent).getAnims(OnWin)
                    for i in currentAnims:
                        i.cancel()

            v.hightlights.cleanUp()

            let small_win = v.winlineParent.findNode("small_win")
            if not small_win.isNil:

                let anim = small_win.animationNamed("play")
                if not anim.isNil:
                    anim.removeHandlers()
                    anim.cancel()
                small_win.removeFromParent(true)

            else:
                stateFinished()

        v.sound.play("WIN_LINE_" & $rand(1 .. 3))

proc regFiveInARowState(v: CardSlotView) =
    v.registerReaction("FiveInARowState") do(state: AbstractSlotState):
        v.sound.play("FIVE_IN_A_ROW")
        discard playFiveOfAKind(v.eventMessageParent) do():
            state.finish()

proc regMultiWinState(v: CardSlotView) =
    v.registerReaction("MultiWinState") do(state: AbstractSlotState):
        v.hightlights.cleanUp()

        let mw = state.MultiWinState
        var w: WinDialogWindow

        v.sound.play("POINTS_COUNT_SOUND")

        case mw.winKind:
        of WinType.Big:
            v.sound.play("BIG_WIN_MUSIC")
            w = playBigWin(v.eventMessageParent, mw.amount, v.getsoundCB()) do():
                v.sound.play("MAIN_BACKGROUND_MUSIC")
                state.finish()
        of WinType.Huge:
            v.sound.play("HUGE_WIN_MUSIC")
            w = playHugeWin(v.eventMessageParent, mw.amount, v.getSoundCB()) do():
                v.sound.play("MAIN_BACKGROUND_MUSIC")
                state.finish()
        else:
            v.sound.play("MEGA_WIN_MUSIC")
            w = playMegaWin(v.eventMessageParent, mw.amount, v.getSoundCB()) do():
                v.sound.play("MAIN_BACKGROUND_MUSIC")
                state.finish()

        v.winDialogWindow = w
        mw.cancel = proc()=
            v.sound.stop("POINTS_COUNT_SOUND")
            if v.winDialogWindow == w:
                v.winDialogWindow = nil

            if not w.isNil:
                v.sound.play("WIN_OUT")
                w.destroy()

proc regNoWinState(v: CardSlotView) =
    v.registerReaction("NoWinState") do (state: AbstractSlotState):

        let field = v.response.stages[^1].field
        if SUN_MULTI in field:
            let s = v.newSlotState(SunMultiplierState)
            pushBack(s)
        else:
            v.hightlights.cleanUp()

        state.finish()

proc regSunBonusState(v: CardSlotView) =
    v.registerReaction("SunBonusState") do(state: AbstractSlotState):
        echo "SunBonusState"

        var suns = newSeq[Node]()
        for reel in v.reelset.reels:
            for r in reel.elems:
                var s = r.findNode("sun_main")
                if not s.isNil:
                    suns.add(s)

        let cb = proc()=
            v.hightlights.cleanUp()
            let newState = v.newSlotState(TransitionState)
            pushBack(newState)
            state.finish()

        var lastAnims: seq[Animation] = @[]
        if suns.len == 0:
            cb()
        else:
            v.sunMultNodes.add(suns)
            v.sound.play("SUN_ANIMATION_FREE_SPINS")
            for i, s in suns:
                lastAnims.add(s.playSunMultAnimation(Sun.Bonus))
                lastAnims[i].cancelBehavior = cbJumpToEnd
            lastAnims[lastAnims.len - 1].onComplete(cb)

        state.SunBonusState.cancel = proc() =
            for lastAnim in lastAnims:
                if not lastAnim.isNil:
                    lastAnim.cancel()

proc regSunMultiplierState(v: CardSlotView) =
    v.registerReaction("SunMultiplierState") do (state: AbstractSlotState):
        echo "SunMultiplierState"
        let reel = v.reelset.reels[2].elems

        var e: Node
        for r in reel:
            e = r.findNode("sun_main")
            if not e.isNil:
                break

        let cb = proc() =
            v.hightlights.cleanUp()
            state.finish()

        var sunMultAnim: Animation

        if e.isNil:
            cb()
        else:
            var sunMult = v.response.linesMultiplier.Sun
            v.sunMultNodes.add(e)

            v.sound.play("SUN_SPIN_AND_WIN")
            sunMultAnim = e.playSunMultAnimation(sunMult)
            sunMultAnim.onComplete(cb)
            sunMultAnim.cancelBehavior = cbJumpToEnd

        state.SunMultiplierState.cancel = proc() =
            if not sunMultAnim.isNil:
                sunMultAnim.cancel()

proc regFreespinEnterState(v: CardSlotView) =
    v.registerReaction("FreespinEnterState") do (state: AbstractSlotState):
        v.sound.play("FREESPIN_BACKGROUND_MUSIC")
        v.sound.play("FREE_SPINS_ANNOUNCE")

        if (not v.response.isNil and v.response.winFreeSpins) or
            v.freespinsCount > 0:
            let s = v.newSlotState(SunBonusState)
            pushBack(s)

        state.finish()

proc regTransitionState(v: CardSlotView) =
    v.registerReaction("TransitionState") do(state: AbstractSlotState):
        echo "TransitionState"

        #----------------GUI----------------#

        let cardsAnim = newAnimation()
        cardsAnim.loopDuration = 0.2
        cardsAnim.numberOfLoops = 1
        cardsAnim.onAnimate = proc(p: float) =
            v.rootNode.findNode("gui_parent").alpha = interpolate(1.0, 0.0, p)
        cardsAnim.onComplete do():
            v.rootNode.findNode("gui_parent").enabled = false
        v.reelset.node.addAnimation(cardsAnim)

        #---------------CHEST---------------#

        v.background.sceneIdleAnim.cancel()
        v.background.beginBGBonusAnim.addLoopProgressHandler(0.0, false) do():
            v.sound.play("CHOOSE_YOUR_GAME")
        v.background.beginBGBonusAnim.addLoopProgressHandler(0.13, false) do():
            if v.freespinsStage == "NoFreespin":
                let freeSpinsNode = newNodeWithResource(PREFIX & FREESPINSEVENT[1])
                v.layers.addChild(freeSpinsNode)

                let chooseYourGameNode = freeSpinsNode.findNode("choose_your_game")
                for i, v in LAYERSNAMES:

                    proc setGradientOptions(gr: GradientFill, j: int) =
                        gr.startPoint.y = -40
                        gr.endPoint.y = 0
                        if j == 1:
                            gr.startColor = newColor(1.0, 0.0, 1.0)
                            gr.endColor = newColor(1.0, 1.0, 1.0)
                        elif j == 2:
                            gr.startColor = newColor(1.0, 0.004, 0.36)
                            gr.endColor = newColor(1.0, 0.513, 0.5)

                    setGradientOptions(chooseYourGameNode.findNode(v).getComponent(GradientFill), 1)
                    setGradientOptions(chooseYourGameNode.findNode(v).children[0].getComponent(GradientFill), 2)

                let introAnim = freeSpinsNode.component(AEComposition).compositionNamed("intro")
                introAnim.cancelBehavior = cbJumpToEnd
                introAnim.onComplete do():
                    let newState = v.newSlotState(FreespinsModeSelection)
                    pushBack(newState)
                    state.finish()

                freeSpinsNode.addAnimation(introAnim)

                v.background.beginBGBonusAnim.onComplete do():
                    v.background.beginBGBonusAnim.removeHandlers()
                    v.background.turnParticlesOff()
                    v.background.node.addAnimation(v.background.cardIdleBeginAnim)
            else:
                v.pickFreespinsState()

                let freeSpinsNode = newNodeWithResource(PREFIX & FREESPINSEVENT[2])
                v.layers.addChild(freeSpinsNode)

                let introAnim = freeSpinsNode.component(AEComposition).compositionNamed("intro")
                introAnim.cancelBehavior = cbJumpToEnd

                introAnim.addLoopProgressHandler(0.8, false) do():
                    let newState = v.newSlotState(FreespinsMode)
                    pushBack(newState)
                    state.finish()

                freeSpinsNode.addAnimation(introAnim)

        v.background.node.addAnimation(v.background.beginBGBonusAnim)

proc regFreespinsModeSelection(v: CardSlotView) =
    v.registerReaction("FreespinsModeSelection") do(state: AbstractSlotState):
        echo "FreespinsModeSelection"
        let freeSpinsNode = v.layers.findNode(FREESPINSEVENT[1])
        let idleAnim = freeSpinsNode.component(AEComposition).compositionNamed("idle")
        idleAnim.cancelBehavior = cbJumpToEnd
        idleAnim.numberOfLoops = -1
        freeSpinsNode.addAnimation(idleAnim)

        var choosen = false
        proc addButton(n: Node, r: Rect, choice: string, index: int) =
            let buttonComponent = n.component(ButtonComponent)
            buttonComponent.bounds = r
            buttonComponent.onAction do():
                n.removeComponent(ButtonComponent)

                if choosen: return
                choosen = true

                v.freeSpinsIndex = index

                idleAnim.cancel()

                if choice == FREESPINSNAMES[1]:
                    v.freespinsStage = FREESPINSNAMES[1]
                elif choice == FREESPINSNAMES[2]:
                    v.freespinsStage = FREESPINSNAMES[2]
                else:
                    v.freespinsStage = FREESPINSNAMES[3]
                let newState = v.newSlotState(FreespinsMode)
                pushBack(newState)

                v.onFreespinsModeSelect()
                state.finish()

        for i in 1 .. 3:
            closureScope:
                let index = i

                var choice: string = ""
                case index.FreespinsType
                    of Hidden: choice = FREESPINSNAMES[1]
                    of Multiplier: choice = FREESPINSNAMES[2]
                    of Shuffle: choice = FREESPINSNAMES[3]
                    else: discard

                let buttonNode = newNode("buttonNode" & $index)
                freeSpinsNode.insertChild(buttonNode, freeSpinsNode.children.len - 5)
                buttonNode.addButton(newRect(BONUSCOORDS[i-1], BUTTON_SIZE), choice, index)

proc regFreespinsMode(v: CardSlotView) =
    v.registerReaction("FreespinsMode") do(state: AbstractSlotState):
        echo "FreespinsMode"
        if v.freespinsStage == FREESPINSNAMES[1]:
            v.reelset.setExceptions(frHiddenExceptions)
        if v.freespinsStage == FREESPINSNAMES[2]:
            v.reelset.setExceptions(frMultiExceptions)
        elif v.freespinsStage == FREESPINSNAMES[3]:
            v.reelset.setExceptions(frShuffleExceptions)
            v.setReelsetReactions(false)
        var freeSpinsNode: Node = v.layers.findNode(FREESPINSEVENT[1])
        var freeSpinsChoiceNode: Node = nil
        if freeSpinsNode.isNil:
            freeSpinsChoiceNode = newNodeWithResource(PREFIX & FREESPINSNAMESRESTORE[v.freeSpinsIndex])
            freeSpinsNode = v.layers.findNode(FREESPINSEVENT[2])
        else:
            freeSpinsChoiceNode = newNodeWithResource(PREFIX & FREESPINSNAMES[v.freeSpinsIndex] & "_choose")
        #--------------PORTALS--------------#
        v.portals = newBackgroundPortals(
            &"{GENERAL_PREFIX}background/comps/" & PORTALSNAMES[v.freeSpinsIndex],
            v.layers, 1)

        v.portals.cardIdleEndAnim.onComplete do():
            v.portals.node.addAnimation(v.portals.beginElIdleAnim)
        v.portals.node.addAnimation(v.portals.cardIdleEndAnim)

        #---------------CHEST---------------#

        v.background.cardIdleBeginAnim.cancel()
        v.background.cardIdleEndAnim.onComplete do():
            v.background.beginElIdleAnim.addLoopProgressHandler(0.0, true) do():
                v.sound.play(SOUNDPORTALNAMES[v.freeSpinsIndex])
            v.background.node.addAnimation(v.background.beginElIdleAnim)
        v.background.node.addAnimation(v.background.cardIdleEndAnim)

        #---------------EVENT--------------#
        let chooseAnim = freeSpinsNode.component(AEComposition).compositionNamed("choose")
        chooseAnim.cancelBehavior = cbJumpToEnd
        chooseAnim.addLoopProgressHandler(0, false) do():
            v.particlesNode = newNodeWithResource(GENERAL_PREFIX & "particles/prtcl_MM_bg2")
            v.layers.insertChild(v.particlesNode, 2)
        chooseAnim.addLoopProgressHandler(0.0, false) do():
            v.sound.play("CHOOSE_YOUR_GAME_END")
        chooseAnim.onComplete do():
            freeSpinsNode.removeFromParent(true)

            chooseAnim.removeHandlers()

            let prevReelsetPos = v.reelsetRoot.worldPos()
            let prevReelsetScale = v.reelsetRoot.scale()

            v.reelsetRoot.reattach(v.layers, v.layers.children.len)

            v.rootNode.findNode("gui_parent").enabled = true
            v.reelsetRoot.positionX = 0

            let cardsAnim = newAnimation()
            cardsAnim.loopDuration = 0.2
            cardsAnim.numberOfLoops = 1
            cardsAnim.onAnimate = proc(p: float) =
                v.rootNode.findNode("gui_parent").alpha = interpolate(0.0, 1.0, p)
                v.reelsetRoot.positionY = interpolate(prevReelsetPos.y, 0, p)
                v.reelsetRoot.scaleX = interpolate(prevReelsetScale.x, 1.0, p)
                v.reelsetRoot.scaleY = interpolate(prevReelsetScale.y, 1.0, p)
            v.reelsetRoot.addAnimation(cardsAnim)

            v.data = %($v.freeSpinsIndex.FreespinsType)
            v.freeSpinsLeft = v.freespins[v.freeSpinsIndex - 1]

            state.finish()

        freeSpinsNode.addAnimation(chooseAnim)

        freeSpinsNode.addChild(freeSpinsChoiceNode)

        let freeSpinsChooseAnim = freeSpinsChoiceNode.component(AEComposition).compositionNamed("choose")
        freeSpinsChooseAnim.cancelBehavior = cbJumpToEnd
        freeSpinsNode.addAnimation(freeSpinsChooseAnim)

proc regFreespinExitState(v: CardSlotView) =
    let bgNode = v.background.node.findNode("chest_controller").findNode("chest")
    v.registerReaction("FreespinExitState") do (state: AbstractSlotState):
        echo "FreespinExitState"
        #--------------PORTALS--------------#

        v.portals.beginElIdleAnim.cancel()
        v.portals.node.reattach(v.background.node, v.background.node.children.len - 1)

        v.portals.endBGBonusAnim.onComplete do():
            v.portals.node.removeFromParent(true)
            v.freespinsStage = "NoFreespin"
        v.portals.node.addAnimation(v.portals.endBGBonusAnim)
        v.sound.stop("FREESPIN_BACKGROUND_MUSIC")

        #---------------CHEST---------------#

        v.background.beginElIdleAnim.cancel()
        v.background.turnParticlesOn()

        v.background.endBGBonusAnim.addLoopProgressHandler(0.3, false) do():
            v.particlesNode.removeFromParent(true)
        v.background.endBGBonusAnim.onComplete do():
            v.background.beginBGBonusAnim.removeHandlers()
            v.background.endBGBonusAnim.removeHandlers()
            v.reelsetRoot.reattach(bgNode.findNode("reelsetRoot"))
            v.background.node.addAnimation(v.background.sceneIdleAnim)
        v.background.node.addAnimation(v.background.endBGBonusAnim)

        #-----------------------------------#

        var w: WinDialogWindow = nil

        v.sound.play("FREE_SPINS_RESULT")
        v.sound.play("POINTS_COUNT_SOUND")
        w = playResults(v.freeSpinsEventMessage, state.FreespinExitState.amount, RESULTSNAMES[v.freeSpinsIndex], v.getSoundCB()) do():
            v.sound.play("MAIN_BACKGROUND_MUSIC")
            state.finish()

        v.winDialogWindow = w
        state.FreespinExitState.cancel = proc() =
            v.sound.stop("POINTS_COUNT_SOUND")
            if v.winDialogWindow == w:
                v.winDialogWindow = nil

            if not w.isNil:
                v.sound.play("WIN_OUT")
                w.destroy()

        v.reelset.setExceptions(mainExceptions)
        v.setReelsetReactions(true)

proc regStartShowAllWinningLines(v: CardSlotView) =
    v.registerReaction("StartShowAllWinningLines") do(state: AbstractSlotState):
        let field = v.response.stages[^1].field
        if SUN_MULTI in field:
            let s = v.newSlotState(SunMultiplierState)
            pushBack(s)

        state.finish()

proc registerReactions(v: CardSlotView)=
    v.regSlotRestoreState()
    v.regSpinInAnimationState()
    v.regSpinOutAnimationState()
    v.regShowWinningLine()
    v.regFiveInARowState()
    v.regMultiWinState()
    v.regNoWinState()
    v.regSunBonusState()
    v.regSunMultiplierState()
    v.regFreespinEnterState()
    v.regFreespinsModeSelection()
    v.regFreespinsMode()
    v.regFreespinExitState()
    v.regStartShowAllWinningLines()
    v.regTransitionState()

method initAfterResourcesLoaded*(v: CardSlotView) =
    procCall v.StateSlotMachine.initAfterResourcesLoaded()
    randomize()

    v.layers = newNode("layers")
    v.rootNode.addChild(v.layers)

    #---------------CHEST---------------#

    v.background = newBackgroundChest(
        &"{GENERAL_PREFIX}background/comps/backgroundChest",
        v.layers
    )

    let bgNode = v.background.node.findNode("chest_controller").findNode("chest")
    v.reelsetRoot = newNode("reelsetAnchor")
    bgNode.findNode("reelsetRoot").addChild(v.reelsetRoot)

    #------------HIGHLIGHTS-------------#

    v.hightlights = Highlights(root: newNode("highlights"), subRoot: newNode("highlightsEnd"))
    v.hightlights.attachToNode(v.reelsetRoot)

    let reelsetNode = newNodeWithResource(GENERAL_PREFIX & "elements/precomps/elements_cell")
    v.reelsetRoot.addChild(reelsetNode)
    v.reelset = reelsetNode.findNode("reelset").getComponent(ReelsetComponent)
    v.reelset.setExceptions(startExceptions)
    v.reelset.update()
    v.reelset.setExceptions(mainExceptions)

    v.reelset.setOnReelsLandProc(0.1) do(index: int):
        if not v.response.isNil:
            let symbols = v.response.stages[0].symbols[index]
            if (SUN_MULTI in symbols) or (SUN_SCATTER in symbols):
                v.sound.play("SUN_APPEAR")

    v.reelset.setOnReelsLandProc(0.15) do(index: int):
        v.sound.play("SPIN_END_" & $rand(1 .. 3) )

    v.setReelsetReactions()

    #---------SUN ANTICIPATION----------#

    v.sunAnticipation = SunAnticipation(sun_tails_field: nil, idToNode: initTable[int, Table[int, Node]]())
    v.sunAnticipation.setup(v.reelset.node, 5)
    v.createAnticipation()

    when defined(debug):
        var fs = false
        v.createTestButton(proc() =
            discard
            let test = playFiveOfAKind(v.rootNode, nil)
        )

    v.sunMultNodes = @[]
    v.registerReactions()

method restoreState(v: CardSlotView, res: JsonNode) =
    if $srtCardFreespinsType in res:
        v.freespinsStage = res[$srtCardFreespinsType].getStr().toLowerAscii()
    else:
        v.freespinsStage = "NoFreespin"
    v.pickFreespinsState()

    procCall v.StateSlotMachine.restoreState(res)
    if v.freespinsCount > 0:
        v.onFreespinsModeSelect()

method assetBundles*(v: CardSlotView): seq[AssetBundleDescriptor] =
    const ASSET_BUNDLES = [
        assetBundleDescriptor("slots/card_slot/background"),
        assetBundleDescriptor("slots/card_slot/elements"),
        assetBundleDescriptor("slots/card_slot/anticipation"),
        assetBundleDescriptor("slots/card_slot/specials"),
        assetBundleDescriptor("slots/card_slot/particles"),
        assetBundleDescriptor("slots/card_slot/branding"),
        assetBundleDescriptor("slots/card_slot/paytable"),
        assetBundleDescriptor("slots/card_slot/card_sound")
    ]

    return @ASSET_BUNDLES
