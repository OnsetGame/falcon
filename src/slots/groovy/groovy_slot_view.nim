import random, json, strformat

import nimx / [types, view, image, button, animation, matrixes, view_event_handling, notification_center]

import rod / [ rod_types, node, component, viewport, quaternion, asset_bundle]
import rod.component / [ sprite, ui_component, visual_modifier ]
import falconserver / slot / [machine_base_types, slot_data_types]
import utils / [ sound, sound_manager, animation_controller, pause, win_line]

import shared.localization_manager
import core / slot / [ base_slot_machine_view, state_slot_machine, states / slot_states ]

import core.progress_bar_solid
import core.flow.flow

import
    groovy_response, projection_to_ortho, cell_component,
    reel_component, reelset_component, anticipator_component,
    groovy_event_message, background, character

const GENERAL_PREFIX = "slots/groovy_slot/"

type
    PaytableServerData* = tuple
        itemset: seq[string]
        paytableSeq: seq[seq[int]]

        sevensInReelTrigger: int
        sevensFreespinTrigger: int
        totalSevensFreespinCount: int

        barsFreespinTrigger: int
        totalBarsFreespinCount: int
        barsPayout: seq[int]

type
    GroovySlotView* = ref object of StateSlotMachine
        pd*: PaytableServerData
        bg: Background  # current background
        green: Background
        orange: Background
        violet: Background

        anticipator: AnticipatorComponent
        wilds: AnticipatorComponent
        arrowsAnticipators: AnticipatorComponent
        undoWilds: seq[proc(cb: proc(a: Animation))]

        progress: int
        progressType: int

        reelset: ReelsetComponent
        response: Response
        sceneAnchor: Node

import groovy_paytable

proc set(rc: ReelsetComponent, cb: proc()) =
    proc addButton(n: Node, r: Rect, callback: proc()) =
        let button = newButton(r)
        n.component(UIComponent).view = button
        button.hasBezel = false
        button.onAction do():
            cb()
            callback()

    let x = rc.stepX
    let y = rc.stepY
    for c in rc.cells:
        closureScope:
            let cc = c
            cc.node.addButton(newRect(newPoint(-x/2, -y/2), newSize(x, y))) do():
                if cc.isVisible:
                    cc.playAnim(OnStop)

proc clear(rc: ReelsetComponent) =
    for c in rc.cells:
        c.node.removeComponent(UIComponent)

proc setColor(anticipator: AnticipatorComponent, colorId: int) =
    for cell in anticipator.cells:
        # 0 == violet
        # 1 == green
        # 2 == orange
        cell.play(colorId, OnShow, lpStartToEnd) do(anim: Animation):
            discard

proc changeScene*(v: GroovySlotView, color: string) =
    v.bg.rootNode.alpha = 0.0
    v.bg.topLights.node.alpha = 0.0
    v.bg.rootNode.enabled = false
    v.bg.topLights.node.enabled = false

    case color
    of "green":
        v.bg = v.green
        v.anticipator.setColor(1)
    of "orange":
        v.bg = v.orange
        v.anticipator.setColor(2)
    of "violet":
        v.bg = v.violet
        v.anticipator.setColor(0)
    else: discard
    v.bg.rootNode.alpha = 1.0
    v.bg.topLights.node.alpha = 1.0
    v.bg.rootNode.enabled = true
    v.bg.topLights.node.enabled = true

proc playProgressIdle(v: GroovySlotView) =
    if v.progressType == 0:
        case v.progress
        of 0:
            v.bg.left.playSevenZeroIdle()
        of 1:
            v.bg.left.playSevenOneIdle()
        of 2:
            v.bg.left.playSevenTwoIdle()
        of 3:
            v.bg.left.playSevenThreeIdle()
        else:
            discard
        v.bg.right.playBarZeroIdle()
    else:
        case v.progress
        of 0:
            v.bg.right.playBarZeroIdle()
        of 1:
            v.bg.right.playBarOneIdle()
        of 2:
            v.bg.right.playBarTwoIdle()
        else:
            discard
        v.bg.left.playSevenZeroIdle()

proc changeProgress(v: GroovySlotView, value: int, barId: int) =
    let left = v.bg.left
    let right = v.bg.right

    v.progress = value
    v.progressType = barId

    if barId == 0:
        # sevens
        case value
        of 1:
            left.playSevenOneAnimation()
        of 2:
            left.playSevenTwoAnimation()
        of 3:
            left.playSevenThreeAnimation()
        else:
            v.playProgressIdle()
    else:
        # bars
        case value
        of 1:
            right.playBarOneAnimation()
        of 2:
            right.playBarTwoAnimation()
        else:
            v.playProgressIdle()

const INFO_PANEL_MSG = [
    "GR_INFO_WIN_MULT",
    "GR_INFO_BAR_ACT",
    "GR_INFO_BAR_BET",
    "GR_INFO_777_ACT"
]

proc infoPanelRandomMessage(v: GroovySlotView): string =
    localizedString(
        INFO_PANEL_MSG[
            rand(INFO_PANEL_MSG.len - 1)
        ]
    )

method viewOnEnter*(v: GroovySlotView)=
    procCall v.StateSlotMachine.viewOnEnter()

    v.pauseManager = newPauseManager(v)
    v.sound.cancelLoopAt("REEL_STOP_SFX_4", @[
            "SPIN_SOUND_0", "SPIN_SOUND_1", "SPIN_SOUND_2",
            "ANTICIPATION_SOUND_SFX_1", "ANTICIPATION_SOUND_SFX_2",
            "ANTICIPATION_SOUND_SFX_3", "ANTICIPATION_SOUND_SFX_4"
         ])
    v.sound.cancelLoopAt("ANTICIPATION_SOUND_SFX_2", @["ANTICIPATION_SOUND_SFX_1"])
    v.sound.cancelLoopAt("ANTICIPATION_SOUND_SFX_3", @["ANTICIPATION_SOUND_SFX_2"])
    v.sound.cancelLoopAt("ANTICIPATION_SOUND_SFX_4", @["ANTICIPATION_SOUND_SFX_3"])

    v.bg.playIntroAnimation()
    v.playProgressIdle()

method viewOnExit*(v: GroovySlotView)=
    sharedNotificationCenter().removeObserver(v)
    procCall v.StateSlotMachine.viewOnExit()

proc initBackgroundByColor(v: GroovySlotView, color: string, background: Node, foreground: Node, shaker: CameraShaker = nil): Background =
    result = newBackground(
        &"{GENERAL_PREFIX}background/comps/{color}_scene.json",
        background
    )
    if not shaker.isNil:
        result.addCameraShaker(shaker)
    else:
        result.addCameraShaker(&"{GENERAL_PREFIX}background/comps/slot_shake.json", v.rootNode)
    result.addTopLights(&"{GENERAL_PREFIX}background/comps/bg_lights_{color}.json", foreground)
    result.addCharacters(@[
        &"{GENERAL_PREFIX}background/comps/Board_left_{color}.json",
        &"{GENERAL_PREFIX}background/comps/Board_right_{color}.json",
    ])
    var left = result.characters[0].rootNode
    var right = result.characters[1].rootNode

    # comp has arrows that goes both ways - we must remove one
    while (var ar = left.findNode("arrow_win_right"); not ar.isNil):
        ar.removeFromParent()
    while (var ar = right.findNode("arrow_win_left"); not ar.isNil):
        ar.removeFromParent()

    right.scaleX = -1.0
    right.positionX = 1917.0

    for i in 0..1:
        var c = result.characters[i].rootNode
        discard c.addComponent("ProjectionToOrtho")
        var tablo = c.findNode("tablo")
        tablo.rotation = newQuaternionFromEulerXYZ(0.0, 77.0, 0.0)

        if i == 0:
            tablo.findNode("right_arrow").removeFromParent()
        else:
            tablo.findNode("left_arrow").removeFromParent()

proc initBackgrounds(v: GroovySlotView, background: Node, foreground: Node) =
    v.green = v.initBackgroundByColor("green", background, foreground)
    v.orange = v.initBackgroundByColor("orange", background, foreground, v.green.cameraShaker)
    v.violet = v.initBackgroundByColor("violet", background, foreground, v.green.cameraShaker)
    v.green.useWaveOnly(1)
    v.violet.useWaveOnly(2)
    v.orange.useWaveOnly(3)

    v.orange.rootNode.alpha = 0.0
    v.green.rootNode.alpha = 0.0
    v.orange.rootNode.enabled = false
    v.green.rootNode.enabled = false

proc setupReelLandingAnim(v: GroovySlotView) =
    # var lastReel = v.reelset.reels[^2]
    # lastReel.onReelLanding = proc() =
    #     v.bg.playLandAnimation()

    proc onStopAnim(r: ReelComponent, it: int) =
        r.onStopProgress(0.4) do():
            if it == 2:
                v.bg.playLandAnimation()

            for i in 0 .. 2:
                r[i].component(CellComponent).play(OnStop, lpStartToEnd, nil)

    for i, r in v.reelset.reels:
        r.onStopAnim(i)

method initAfterResourcesLoaded(v: GroovySlotView) =
    procCall v.StateSlotMachine.initAfterResourcesLoaded()
    randomize()

    let bgAnchor = newNode("background_scene_anchor")
    let fgAnchor = newNode("foreground_scene_anchor")
    v.initBackgrounds(bgAnchor, fgAnchor)
    v.bg = v.violet
    v.progressType = 0
    v.progress = 0

    let sceneAnchor = v.bg.cameraShaker.slot.newChild("scene_anchor")
    sceneAnchor.positionY = -48.0
    sceneAnchor.addChild(bgAnchor)

    var infoParticles = newNodeWithResource(GENERAL_PREFIX & "event_msg/precomps/info_particles")
    bgAnchor.addChild(infoParticles)

    let n = newNodeWithResource(GENERAL_PREFIX & "comps/editor_reels_anchor")
    sceneAnchor.addChild(n)

    v.anticipator = n.findNode("anticipators").getComponent(AnticipatorComponent)
    v.wilds = n.findNode("wilds_anticipators").getComponent(AnticipatorComponent)
    v.arrowsAnticipators = n.findNode("anticipation_arrows").getComponent(AnticipatorComponent)
    for el in v.arrowsAnticipators.elems:
        el.hideElemWithAnim(AnimNone)
    v.reelset = n.findNode("reelset").getComponent(ReelsetComponent)
    v.reelset.update()
    v.reelset.set() do():
        v.sound.play("GAME_CLICK_ELEM")

    v.setupReelLandingAnim()

    sceneAnchor.addChild(fgAnchor)
    v.sceneAnchor = sceneAnchor
    v.changeScene("violet")

proc playWild(v: GroovySlotView, cb: proc()) =
    var clbck = cb
    var wasWild = false
    var st = v.response.stages[0]
    for i, stg in v.response.stages:
        st = stg
    # show 777wilds
    if st.stage != FreeSpinStage:
        for i, reel in v.reelset.reels:
            closureScope:
                let it = i

                if v.reelset.reels[it].node.enabled and v.response.sevensProgress > 0:
                    if  (st.symbols[it][0] == 5 or st.symbols[it][0] == 6 or st.symbols[it][0] == 7) and
                        (st.symbols[it][1] == 5 or st.symbols[it][1] == 6 or st.symbols[it][1] == 7) and
                        (st.symbols[it][2] == 5 or st.symbols[it][2] == 6 or st.symbols[it][2] == 7):

                        v.sound.play("7WILD_APPEAR")
                        if not v.sound.isActive("RESPIN_SFX"):
                            v.sound.play("RESPIN_SFX")

                        v.wilds[it].play(OnShow, lpStartToEnd) do(a: Animation):
                            if not clbck.isNil:
                                clbck()
                                clbck = nil

                        wasWild = true

                        v.reelset.reels[it].node.enabled = false
                        let undoJob = proc(cb: proc(a: Animation)) =
                            v.reelset.reels[it].node.enabled = true
                            v.wilds[it].play(OnShow, lpEndToStart, cb)
                        v.undoWilds.add(undoJob)
    if wasWild:
        v.bg.playInfoPanelTextAnimation(
            localizedString("GR_INFO_777_RESPIN")
        )

        # left progress board
        if v.response.sevensProgress > 0:
            v.changeProgress(v.response.sevensProgress, 0)
        # right progress board
        elif v.response.barsProgress > 0:
            v.changeProgress(v.response.barsProgress, 1)
    else:
        if not clbck.isNil:
            clbck()
            clbck = nil

proc removeWild(v: GroovySlotView, cb: proc(removed: bool)) =
    if v.undoWilds.len == 0:
        cb(false)
        return
    var counter = v.undoWilds.len
    for it in 0..<v.undoWilds.len:
        v.sound.play("7WILD_DISAPPEAR")
        v.undoWilds[it] do(a: Animation):
            dec counter
            if counter == 0:
                v.sound.stop("RESPIN_SFX")
                cb(true)
    v.undoWilds = @[]

method getStateForStopAnim*(v: GroovySlotView): WinConditionState =
    result = WinConditionState.NoWin

proc seqHasElem(v: GroovySlotView, elem: string, s: seq[int]): bool =
    let eli = v.pd.itemset.find(elem)
    result = eli in s

proc reelHasElem(v: GroovySlotView, ri: int, elem:string): bool =
    if v.lastField.len == 0: return
    var reel = newSeq[int](3)
    for i in 0 ..< 3:
        reel[i] = v.lastField[i * 5 + ri]
    result = v.seqHasElem(elem, reel)

proc reelHasOneOfElems(v: GroovySlotView, ri: int, elems: varargs[string]): bool =
    for el in elems:
        if v.reelHasElem(ri, el):
            return true

proc winLineHasElem(v: GroovySlotView, li: int, ll: int, elem: string): bool =
    if v.lines.len == 0 or v.lastField.len == 0: return
    let coords = v.lines[li]
    var elems = newSeq[int](ll)
    for i in 0 ..< ll:
        elems[i] = coords[i] * 5 + i

    result = v.seqHasElem(elem, elems)

proc winLineHasOneOfElems(v: GroovySlotView, li, ll: int, elems: varargs[string]): bool =
    for el in elems:
        if v.winLineHasElem(li, ll, el):
            return true

method init*(v: GroovySlotView, r: Rect) =
    procCall v.StateSlotMachine.init(r)

    v.gLines = 25
    v.soundEventsPath = "slots/groovy_slot/sounds/groovy"
    var fsStarted = false

    # TODO ask about multipliers
    v.multBig = 10
    v.multHuge = 15
    v.multMega = 25

    v.undoWilds = @[]
    v.reelsInfo = (bonusReels: @[], scatterReels: @[])

    v.addDefaultOrthoCamera("Camera")

    proc isFreeSpins(v: GroovySlotView): bool =
        result = false
        if not v.response.isNil:
            result = (v.response.sevensFreespins - 1) > 0 or (v.response.barsFreespins - 1) > 0

    v.registerReaction("SlotRestoreState") do(state: AbstractSlotState):
        let res = state.SlotRestoreState.restoreData
        if res.hasKey("paytable"):
            var pd: PaytableServerData
            let paytable = res["paytable"]
            if paytable.hasKey("items"):
                pd.itemset = @[]
                for itm in paytable["items"]:
                    pd.itemset.add(itm.getStr())
            pd.paytableSeq = res.getPaytableData()

            if paytable.hasKey("barsFreespinTrigger"):
                pd.barsFreespinTrigger = paytable["barsFreespinTrigger"].getInt()
            else:
                pd.barsFreespinTrigger = 2
            if paytable.hasKey("totalBarsFreespinCount"):
                pd.totalBarsFreespinCount = paytable["totalBarsFreespinCount"].getInt()
            else:
                pd.totalBarsFreespinCount = 10
            if paytable.hasKey("barsPayout"):
                var jArr = paytable["barsPayout"]
                pd.barsPayout = @[]
                for el in jArr:
                    pd.barsPayout.add(el.getInt())
            else:
                pd.barsPayout = @[0,0,0,0,1,2,5,10,15,20,30,50,100,200,500,1000]
            if paytable.hasKey("sevensInReelTrigger"):
                pd.sevensInReelTrigger = paytable["sevensInReelTrigger"].getInt()
            else:
                pd.sevensInReelTrigger = 3
            if paytable.hasKey("sevensFreespinTrigger"):
                pd.sevensFreespinTrigger = paytable["sevensFreespinTrigger"].getInt()
            else:
                pd.sevensFreespinTrigger = 3
            if paytable.hasKey("totalSevensFreespinCount"):
                pd.totalSevensFreespinCount = paytable["totalSevensFreespinCount"].getInt()
            else:
                pd.totalSevensFreespinCount = 10
            v.pd = pd

        #restore last field
        if "lsr" in res:
            let jfield = res["lsr"]
            var field = newSeq[int]()
            for j in jfield:
                field.add(j.getInt())
            v.reelset.field = field

        state.finish()

    v.registerReaction("SpinInAnimationState") do(state: AbstractSlotState):
        v.bg.cancelIdleAnimation()

        # Removed due to complaint against text anim during spin
        #[if v.isFreeSpins():
            if v.response.sevensFreespins > 0:
                v.bg.playInfoPanelTextAnimation(
                    localizedString("GR_INFO_777_FS")
                )
            elif v.response.barsFreespins > 0:
                v.bg.playInfoPanelTextAnimation(
                    localizedString("GR_INFO_BAR_FS")
                )
        else:
            v.bg.playInfoPanelTextAnimation(v.infoPanelRandomMessage())]#

        proc play() =
            var r = rand(2)
            v.sound.play("SPIN_SOUND_" & $r)

            v.bg.playSpinAnimation()
            v.anticipator.play(OnHide)
            v.reelset.clear()
            v.reelset.play do():
                state.finish()

        if v.isFreeSpins() and not v.response.isNil and v.undoWilds.len > 0 and (v.response.respins == 0 or v.response.sevensFreespins > 0):
            v.removeWild do(val: bool):
                play()
        else:
            play()

    v.registerReaction("SpinOutAnimationState") do(state: AbstractSlotState):
        v.response = newResponse(v.lastResponce)
        # debug v.response

        var st = v.response.stages[0]
        for i, stg in v.response.stages:
            st = stg

        proc onStop() =
            # if st.lines.len == 0:
            #     # show 777wilds
            #     v.playWild do():
            #         state.finish()
            # else:
            state.finish()

        # cells anticipation
        let mediana = v.reelset.reels.len div 2
        for reelIndex, reel in v.reelset.reels:
            closureScope:
                let it = reelIndex
                reel.onIndexedStop = proc() =
                    v.sound.play("REEL_STOP_SFX_" & $it)
                    v.anticipator[it].play(OnShow)
                    if it == mediana:
                        for i in 0..mediana:
                            let it = i
                            for ln in st.lines:
                                if it < ln.symbols.int:
                                    v.anticipator[it][v.lines[ln.index.int][it].int].play(OnAnticipate)
                    elif it > mediana:
                        for ln in st.lines:
                            if it < ln.symbols.int:
                                v.anticipator[it][v.lines[ln.index.int][it].int].play(OnAnticipate)

        # arrows anticipation and stop timeout duration
        var isForceStop = false
        if st.lines.len > 0:
            var maxWiningSymbols = 0
            var minWiningSymbols = mediana + 1
            for ln in st.lines:
                if ln.symbols > maxWiningSymbols:
                    maxWiningSymbols = ln.symbols
                if ln.symbols < minWiningSymbols and ln.symbols > 0:
                    minWiningSymbols = ln.symbols

            let oldTimings = v.reelset.stopTimings

            var cntr = 1
            let anticipationDuration = 1.5
            for i in minWiningSymbols..<v.reelset.stopTimings.len:
                v.reelset.stopTimings[i] += anticipationDuration * cntr.float32
                if i < maxWiningSymbols:
                    inc cntr

            var reelStopperCounter = 0
            if v.reelset.canStop:
                v.reelset.stop(st.symbols) do(reelIndex: int):
                    if reelIndex >= minWiningSymbols-1 and reelIndex < v.reelset.cols-1 and reelIndex < maxWiningSymbols and not isForceStop:
                        v.sound.play("ANTICIPATION_SOUND_SFX_" & $reelIndex)
                        v.arrowsAnticipators[reelIndex+1][0].play(OnShow, lpStartToEnd) do(a: Animation):
                            if not isForceStop:
                                # a.numberOfLoops = -1
                                v.arrowsAnticipators[reelIndex+1][0].play(OnShow, lpStartToEnd) do(a: Animation):
                                    v.arrowsAnticipators[reelIndex+1][0].hideElemWithAnim(AnimNone)
                            else:
                                v.arrowsAnticipators[reelIndex+1][0].hideElemWithAnim(AnimNone)
                    if v.reelHasOneOfElems(reelIndex, "wild"):
                        v.sound.play("WILD_APPEAR_SFX")
                    if v.reelHasOneOfElems(reelIndex, "7red","7green","7blue","7any"):
                        v.sound.play("777_APPEAR_SFX")
                    if v.reelHasOneOfElems(reelIndex, "3bar","2bar","1bar"):
                        v.sound.play("BAR_APPEAR_SFX")
                    v.arrowsAnticipators[reelIndex][0].hideElemWithAnim(AnimNone)

                    inc reelStopperCounter
                    if reelStopperCounter == v.reelset.cols:
                        v.reelset.stopTimings = oldTimings
                        onStop()
        else:
            v.reelset.stop(st.symbols, onStop)

        let so = state.SpinOutAnimationState
        so.cancel = proc() =
            isForceStop = true
            v.reelset.forceStop()
            for el in v.arrowsAnticipators.elems:
                el.hideElemWithAnim(AnimNone)

    v.timingConfig.spinIdleDuration = 0.1

    v.registerReaction("StartShowAllWinningLines") do(state: AbstractSlotState):
        v.bg.shakeCamera()

        # left progress board
        if v.response.sevensProgress > 0:
            v.changeProgress(v.response.sevensProgress, 0)

            if v.response.sevensProgress == v.pd.sevensFreespinTrigger:
                v.bg.playInfoPanelTextAnimation(
                    localizedString("GR_INFO_777_WON")
                )
            else:
                v.bg.playWinAnimation(localizedFormat("GR_777_PROGRESS", $v.response.sevensProgress))

            v.sound.play("777_PROGRESS_SFX")

        # right progress board
        elif v.response.barsProgress > 0:
            v.changeProgress(v.response.barsProgress, 1)

            if v.response.barsProgress == v.pd.barsFreespinTrigger:
                v.bg.playInfoPanelTextAnimation(
                    localizedString("GR_INFO_BAR_WON")
                )
            else:
                v.bg.playWinAnimation(localizedFormat("GR_BAR_PROGRESS", $v.response.barsProgress))

            v.sound.play("BAR_PROGRESS_SFX")
        else:
            v.changeProgress(0, 0)

            v.bg.playWinAnimation()

        if v.isFreeSpins() and fsStarted:
            if v.response.sevensFreespins > 0:
                v.bg.playInfoPanelTextAnimation(
                    localizedFormat("GR_INFO_FS_LEFT", $v.response.sevensFreespins)
                )
            elif v.response.barsFreespins > 0:
                v.bg.playInfoPanelTextAnimation(
                    localizedFormat("GR_INFO_FS_LEFT", $v.response.barsFreespins)
                )
        else:
            v.bg.playInfoPanelTextAnimation(
                localizedFormat("GR_INFO_TOTAL_WIN", $v.getPayoutForLines())
            )

        v.reelset.fadeNode.show(0.75)
        state.finish()

    v.registerReaction("EndShowAllWinningLines") do(state: AbstractSlotState):
        v.reelset.fadeNode.hide(0.75)

        if not v.isFreeSpins():
            v.bg.playIdleAnimation()

        v.playWild() do():
            state.finish()

    v.registerReaction("ShowWinningLine") do(state:AbstractSlotState):
        if state of ShowWinningLine:
            let r = rand(2)
            v.sound.play("GAME_SHOW_WIN_LINE_" & $r)
            var elemAnims: seq[Animation] = @[]
            let wl = state.ShowWinningLine
            let coords = v.lines[wl.line.index] #[ 0, 1, 2, 1, 0 ]#
            let numberOfElements = wl.line.winningLine.numberOfWinningSymbols
            var parentsElems = newSeq[Node](v.reelset.reels.len)
            var parentsWilds = newSeq[Node](v.reelset.reels.len)

            if v.winLineHasElem(wl.line.index, numberOfElements, "wild"):
                v.sound.play("WILD_WIN_SFX")
            elif v.winLineHasOneOfElems(wl.line.index, numberOfElements, "7red","7green","7blue","7any","3bar","2bar","1bar"):
                let r = rand(4)
                v.sound.play("WIN_HIGH_SYMBOL_" & $r & "_SFX")
            else:
                let r = rand(2)
                v.sound.play("REGULAR_WIN_SOUND_" & $r & "_SFX")

            for i in 0 ..< v.reelset.reels.len:
                parentsElems[i] = v.reelset.reels[i].node
                parentsWilds[i] = v.wilds.node

            # let step = 0.1
            # var stepSum = 0.0
            var winCounter = numberOfElements
            for i in 0 ..< numberOfElements:
                closureScope:
                    let it = i
                    let c = coords[it]
                    let node = if v.reelset.reels[it].node.enabled: v.reelset.reels[it][c] else: v.wilds[it][0].node
                    let parent = if v.reelset.reels[it].node.enabled: parentsElems[it] else: parentsWilds[it]

                    # v.setTimeout(stepSum) do():
                    v.anticipator[it][c].play(OnWin)

                    # because simple reattach does not work
                    var oldId: int
                    for i, c in parent.children:
                        if c == node: oldId = i
                    node.reattach(v.reelset.frontNode)

                    let cc = node.getComponent(CellComponent)
                    let anims = cc.getAnims(OnWin)
                    for a in anims: a.cancelBehavior = cbJumpToStart
                    elemAnims.add(anims)

                    cc.play(OnWin, lpStartToEnd) do(a: Animation):
                        # because reattach does not work
                        if parent.children.len < oldId:
                            oldId = parent.children.len
                        parent.insertChild(node, oldId)
                        if v.reelset.reels[it].node.enabled:
                            node.position = v.reelset.cellsPos[it][c]
                        else:
                            node.position = v.wilds.cellsPos[it][0]

                        dec winCounter
                        if winCounter == 0:
                            state.finish()
                    # stepSum += step

            const sceneShift = newVector3(450.0, 0.0, 0.0)
            let wlNode = v.sceneAnchor.newChild("win_line" & $wl.line.index)
            let wlComp = wlNode.addComponent(WinLine)
            for i in 0 ..< v.reelset.reels.len:
                if i == 0:
                    wlComp.positions.add(v.reelset.cellsWpos[i][coords[i]] - sceneShift)
                wlComp.positions.add(v.reelset.cellsWpos[i][coords[i]])
                if i == v.reelset.reels.len-1:
                    wlComp.positions.add(v.reelset.cellsWpos[i][coords[i]] + sceneShift)

            let lineComp = newNodeWithResource(GENERAL_PREFIX & "comps/line")
            lineComp.enabled = false
            wlNode.addChild(lineComp)
            let lnAnim = lineComp.animationNamed("play")
            v.sceneAnchor.addAnimation(lnAnim)

            wlComp.sprite = lineComp.findNode("line_sprite").getComponent(Sprite)
            wlComp.width = 50.0
            wlComp.density = 1.8
            discard wlNode.addComponent(VisualModifier)

            let winNum = v.sceneAnchor.showWinLinePayout(wl.totalPayout, nil)

            lnAnim.onComplete do():
                wlNode.removeFromParent()

            wl.cancel = proc() =
                v.bg.cameraShaker.shake.cancelBehavior = cbJumpToStart
                v.bg.cameraShaker.shake.cancel()

                winNum.removeFromParent()
                v.setTimeout 0.3, proc() =
                    lnAnim.cancelBehavior = cbJumpToStart
                    lnAnim.cancel()
                for an in elemAnims: an.cancel()
                elemAnims = @[]

    v.registerReaction("NoWinState") do (state: AbstractSlotState):
        v.bg.playInfoPanelTextAnimation(localizedString("GR_NO_WIN"))

        if not v.isFreeSpins():
            v.bg.playIdleAnimation()
            v.changeProgress(0, 0)

        v.sound.play("GAME_NO_WIN")

        # remove 777 wild if any
        # removed == true - we had 777 wild and animation was removed
        # else we don't have 777 wild's on field
        v.removeWild() do(removed: bool):
            if removed:
                state.finish()
            else: # try play 777 wild animation if any on field
                v.playWild() do():
                    state.finish()

    v.registerReaction("FreespinExitState") do(state: AbstractSlotState):
        let fe = state.FreespinExitState
        var w: WinDialogWindow
        var st = v.response.stages[0]
        for i, stg in v.response.stages:
            st = stg
        if st.totalSevensFreespinWin > 0:
            v.sound.play("777_FREE_SPINS_RESULT_SCREEN_SFX")
            w = play777Result(v.sceneAnchor, fe.amount) do():
                state.finish()
                v.sound.play("GAME_BACKGROUND_MUSIC")
                v.sound.play("GAME_BACKGROUND_AMBIENCE")

        elif st.totalBarsFreespinWin > 0:
            v.sound.play("BAR_FREE_SPINS_RESULT_SCREEN_SFX")
            w = playBarResult(v.sceneAnchor, fe.amount) do():
                state.finish()
                v.sound.play("GAME_BACKGROUND_MUSIC")
                v.sound.play("GAME_BACKGROUND_AMBIENCE")

        if not w.isNil:
            v.winDialogWindow = w
            fe.cancel = proc()=
                if w == v.winDialogWindow:
                    v.winDialogWindow = nil
                if not w.isNil:
                    w.destroy()

        fsStarted = false
        v.changeScene("violet")
        v.changeProgress(0, 0)

    v.registerReaction("FreespinEnterState") do(state: AbstractSlotState):
        v.sound.stop("RESPIN_SFX")
        if not v.response.isNil and v.response.sevensFreespins > 0:
            v.changeScene("orange")
            v.bg.playLandAnimation()
            v.sound.play("777_FREE_SPINS_RESULT_SCREEN_SFX")
            discard play777Intro(v.sceneAnchor) do():
                state.finish()
                v.sound.play("777_FREE_SPINS_MUSIC")
                v.sound.play("777_FREE_SPINS_AMBIENCE")

        elif not v.response.isNil and v.response.barsFreespins > 0:
            v.changeScene("green")
            v.bg.playLandAnimation()
            v.sound.play("BAR_FREE_SPINS_START_SCREEN_SFX")
            discard playBarIntro(v.sceneAnchor) do():
                state.finish()
                v.sound.play("BAR_FREE_SPINS_MUSIC")
                v.sound.play("BAR_FREE_SPINS_AMBIENCE")
        else:
            state.finish()

        fsStarted = true

    v.registerReaction("FiveInARowState") do(state: AbstractSlotState):
        v.sound.play("FIVE_IN_A_ROW_SFX")
        discard v.sceneAnchor.play5IARow do():
            state.finish()

    v.registerReaction("MultiWinState") do(state: AbstractSlotState):
        let mw = state.MultiWinState
        var w: WinDialogWindow

        case mw.winKind:
        of WinType.Huge:
            v.sound.play("HUGE_WIN_SFX")
            w = playHugeWin(v.sceneAnchor, mw.amount) do():
                v.sound.stop("HUGE_WIN_SFX")
                state.finish()
        of WinType.Big:
            v.sound.play("BIG_WIN_SFX")
            w = playBigWin(v.sceneAnchor, mw.amount) do():
                v.sound.stop("BIG_WIN_SFX")
                state.finish()
        else:
            v.sound.play("MEGA_WIN_SFX")
            w = playMegaWin(v.sceneAnchor, mw.amount) do():
                v.sound.stop("MEGA_WIN_SFX")
                state.finish()

        v.winDialogWindow = w
        mw.cancel = proc()=
            if v.winDialogWindow == w:
                v.winDialogWindow = nil

            if not w.isNil:
                w.destroy()

    v.registerReaction("SlotRoundComplete") do(state: AbstractSlotState):
        v.reelset.set() do():
            v.sound.play("GAME_CLICK_ELEM")
        state.finish()

method assetBundles*(v: GroovySlotView): seq[AssetBundleDescriptor] =
    const ASSET_BUNDLES = [
        assetBundleDescriptor("slots/groovy_slot")
    ]
    result = @ASSET_BUNDLES

import nimx.app

method onKeyDown*(v: GroovySlotView, e: var Event): bool =
    discard procCall v.StateSlotMachine.onKeyDown(e)
    case e.keyCode
    of VirtualKey.Space:
        if v.actionButtonState == SpinButtonState.Blocked:
            # v.onBlockedClick()
            discard
        proc sendMouseEvent(wnd: Window, p: Point, bs: ButtonState) =
            var evt = newMouseButtonEvent(p, VirtualKey.MouseButtonPrimary, bs)
            evt.window = wnd
            discard mainApplication().handleEvent(evt)
        proc pressButton(buttonPoint: Point) =
            sendMouseEvent(v.window, buttonPoint, bsDown)
            sendMouseEvent(v.window, buttonPoint, bsUp)
        pressButton(newPoint(-50.0, -50.0))

    of VirtualKey.J:
        var em = play777Intro(v.sceneAnchor) do():
            discard

    of VirtualKey.M:
        var isMusicStoped {.global.} = false
        if not isMusicStoped:
            v.sound.stop("GAME_BACKGROUND_MUSIC")
        else:
            v.sound.play("GAME_BACKGROUND_MUSIC")
        isMusicStoped = not isMusicStoped

    else: discard
    result = true
