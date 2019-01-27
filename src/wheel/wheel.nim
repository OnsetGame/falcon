import random, strutils, tables, math, json, logging

import nimx / [ matrixes, animation, timer, button, view, property_visitor ]
import core / notification_center
import core / flow / flow_state_types
import core / features / vip_system

import rod / [ viewport, quaternion, rod_types, viewport, node, asset_bundle, component ]
import rod / component / [ sprite, solid, ui_component, text_component, ae_composition, channel_levels]

import utils / [ helpers, sound, sound_manager, falcon_analytics, icon_component ]

import core / net / [ server ]

import shared / [ user, director, chips_animation, game_scene, tutorial, tutorial_highlight, alerts ]
import shared / localization_manager
import windows / store / store_window
import shared / window / [ window_manager, window_component, button_component ]

import slots.mermaid.anim_helpers

import fix_transform_component

const SECTORS_COUNT = 10

type
    WheelSectorColor* = enum
        purple = 0
        red
        white
        violet

    WheelSectorWin* = enum
        spins = 0
        chips
        bucks
        energy

    WheelSector* = tuple
        color: WheelSectorColor
        winType: WheelSectorWin
        winValue: int

    WheelHistory* = tuple
        winType: WheelSectorWin
        winValue: int

    WheelResponse* = tuple
        nextSpinCost: int
        currSector: int
        freeSpinTimeout: float32
        wallet: tuple[chips: int64, bucks: int64, parts: int64, tournamentPoints: int64]
        timeDiff: float32
        freeSpinsLeft: int

    WheelLayout* = tuple
        sectors: array[SECTORS_COUNT, WheelSector]
        initResponse: WheelResponse

    WheelWindow* = ref object of AsyncWindowComponent
        history: array[3, WheelHistory]
        prevResponse: WheelResponse
        currResponse: WheelResponse
        layout: WheelLayout
        time: float32
        timerStarted: bool
        wasWin: bool
        canSpin: bool
        canStop: bool
        idleAnim: Animation
        completion: Completion
        source*: string
        lastResult: string
        lastActionSpins: int
        spentBucks: int
        vipNode: Node

proc sendEvent(w: WheelWindow, str: string) =
    if not w.node.sceneView.isNil:
        w.node.sceneView.GameScene.soundManager.sendEvent(str)

proc sendEvent(v: SceneView, str: string) =
    if not v.isNil:
        v.GameScene.soundManager.sendEvent(str)

proc playSpinLoop(w: WheelWindow): Sound =
    if not w.node.sceneView.isNil:
        result = w.node.sceneView.GameScene.soundManager.sendSfxEvent("WHEEL_SPIN_LOOP_SFX")

proc playAnticipation(w: WheelWindow): Sound =
    if not w.node.sceneView.isNil:
        result = w.node.sceneView.GameScene.soundManager.sendSfxEvent("WHEEL_ANTICIPATION")

proc getLayoutAndHistory(j: JsonNode): tuple[layout: WheelLayout, history: array[3, WheelHistory]] =

    result.layout.initResponse.freeSpinTimeout = j{"freeSpinTimeout"}.getFloat(24 * 60 * 60)

    if j.hasKey("prevFreeSpin") and j.hasKey("serverTime"):
        let prevFreespTime = j["prevFreeSpin"].getFloat()
        let currServerTime = j["serverTime"].getFloat()
        result.layout.initResponse.timeDiff = currServerTime - prevFreespTime
    if j.hasKey("nextCost"):
        result.layout.initResponse.nextSpinCost = j["nextCost"].getInt()
    if j.hasKey("freeSpinsLeft"):
        result.layout.initResponse.freeSpinsLeft = j["freeSpinsLeft"].getInt()
    if j.hasKey("list"):
        var i: int = 0
        for s in j["list"]:
            if s.hasKey("item") and s.hasKey("count"):
                case s["item"].str:
                of "chips":
                    result.layout.sectors[i].winType = chips
                    result.layout.sectors[i].color = red
                of "bucks":
                    result.layout.sectors[i].winType = bucks
                    result.layout.sectors[i].color = white
                of "beams", "parts", "energy":
                    result.layout.sectors[i].winType = energy
                    result.layout.sectors[i].color = violet
                else: doAssert(false, "wrong protocol")
                if i == SECTORS_COUNT-1:
                    result.layout.sectors[i].color = purple
                result.layout.sectors[i].winValue = s["count"].getInt()

                inc i

    if j.hasKey("history"):
        var i: int = j["history"].len-1
        for s in j["history"]:
            if s.hasKey("item") and s.hasKey("count"):
                case s["item"].str:
                of "chips": result.history[i].winType = chips
                of "bucks": result.history[i].winType = bucks
                of "beams", "parts", "energy": result.history[i].winType = energy
                else: doAssert(false, "wrong protocol")
                result.history[i].winValue = s["count"].getInt()

                dec i

proc getResponse(j: JsonNode): WheelResponse =
    result.freeSpinTimeout = j{"freeSpinTimeout"}.getFloat(24 * 60 * 60)
    if j.hasKey("prevFreeSpin") and j.hasKey("serverTime"):
        let prevFreespTime = j["prevFreeSpin"].getFloat()
        let currServerTime = j["serverTime"].getFloat()
        result.timeDiff = currServerTime - prevFreespTime
    if j.hasKey("nextCost"):
        result.nextSpinCost = j["nextCost"].getInt()
    if j.hasKey("choice"):
        result.currSector = j["choice"].getInt()
    if j.hasKey("wallet"):
        let w = j["wallet"]
        if w.hasKey("chips"):
            result.wallet.chips = w["chips"].getBiggestInt()
        if w.hasKey("bucks"):
            result.wallet.bucks = w["bucks"].getBiggestInt()
        if w.hasKey("parts"):
            result.wallet.parts = w["parts"].getBiggestInt()
        if w.hasKey("tourPoints"):
            result.wallet.tournamentPoints = w["tourPoints"].getBiggestInt()
    if j.hasKey("freeSpinsLeft"):
        result.freeSpinsLeft = j["freeSpinsLeft"].getInt()

proc amountNormalize(v: int): string =
    if v == 0:
        result = $v
    else:
        if (v mod 1000000) == 0: result = $(v / 1000000).int & "M"
        elif (v mod 1000) == 0: result = $(v / 1000).int & "K"
        else: result = $v

proc setupLayout(w: WheelWindow, lt: WheelLayout) =
    let sectors = w.anchorNode.findNode("sectors_anchor")
    let dots = w.anchorNode.findNode("sector_dots_anchor")

    proc showElem(n: Node, elemName: string): Node =
        for ch in n.children: ch.hide(0)
        result = n.findNode(elemName)
        result.show(0)

        if elemName == $purple:
            let chLev = result.component(ChannelLevels)
            chLev.inBlackV = newVector3(0.2, 1.0, 0.0)

    proc getTextComponent(n: Node): Text =
        var comp: Text
        discard n.findNode do(nd: Node) -> bool:
            let c = nd.componentIfAvailable(Text)
            if not c.isNil: comp = c
        result = comp

    for i, s in lt.sectors:
        let sectorDot = dots.findNode("sector_dot_" & $(i+1)).findNode("dot")
        let sector = sectors.findNode("win_part_" & $(i+1))

        let sectorBg = sector.findNode("sector_bg")
        let sectorWininngs = sector.findNode("winnings")

        discard sectorBg.showElem($s.color)
        discard sectorDot.showElem($s.color)

        sectorWininngs.showElem($s.winType).getTextComponent().text = amountNormalize(s.winValue)

type WheelRotationStage* = enum
    speedup = 0
    constant
    slowdown
    finish

type FortuneWheel* = ref object of Component
    startSpeed: float32
    constSpeed: float32
    slowdownSpeed: float32
    stopSpeed: float32
    acceleration: float32
    beforeStopSteps: float32

method visitProperties*(w: FortuneWheel, p: var PropertyVisitor) =
    p.visitProperty("startSpeed", w.startSpeed)
    p.visitProperty("constSpeed", w.constSpeed)
    p.visitProperty("slowdownSpeed", w.slowdownSpeed)
    p.visitProperty("stopSpeed", w.stopSpeed)
    p.visitProperty("acceleration", w.acceleration)
    p.visitProperty("beforeStopSteps", w.beforeStopSteps)

registerComponent(FortuneWheel, "Falcon")

proc playArrow(anchor: Node, loopDuration: float32 = 0.5): Animation =
    result = newAnimation()
    result.numberOfLoops = 1
    result.loopPattern = lpStartToEndToStart
    result.loopDuration = loopDuration
    result.animate val in 0.0 .. -30.0:
        anchor.rotation = aroundZ(val)

    let v = anchor.sceneView
    if not v.isNil:
        v.sendEvent("WHEEL_TIC_SFX")
        v.addAnimation(result)

proc spin(w: WheelWindow, canStop: proc(): bool, callback: proc()) =
    const SECTOR_STEP = 360.0 / SECTORS_COUNT.float32

    var spinAnticipationSfx: Sound

    let rotAnchor = w.anchorNode.findNode("rotation_anchor")
    let yellowAnchor = w.anchorNode.findNode("yellow_anchor")

    var wheelCmp = rotAnchor.getComponent(FortuneWheel)
    if wheelCmp.isNil:
        wheelCmp = rotAnchor.component(FortuneWheel)

        wheelCmp.startSpeed = 0.0
        wheelCmp.constSpeed = 550.0
        wheelCmp.slowdownSpeed = 175.0
        wheelCmp.stopSpeed = 30.0
        wheelCmp.acceleration = 4.5
        wheelCmp.beforeStopSteps = rand(2..3).float32

    let anim = newAnimation()
    anim.loopDuration = 1.0
    anim.numberOfLoops = -1
    var startRotation = -rotAnchor.rotation.eulerAngles().z
    var destRotation = startRotation + (SECTORS_COUNT - w.currResponse.currSector + w.prevResponse.currSector).float32 * SECTOR_STEP
    var currSpeed = wheelCmp.startSpeed
    var currAnimStage = speedup
    var finished = false


    template norm() =
        if startRotation > 360.0:
            startRotation -= 360.0
        if destRotation > 360.0 and destRotation - 360.0 >= startRotation:
            destRotation -= 360.0
    norm()

    let arrowAnchor = w.anchorNode.findNode("arrow_frame").findNode("rotation_arrow_anchor")
    var arrowAnim = arrowAnchor.playArrow((wheelCmp.constSpeed-wheelCmp.startSpeed)/1000.0)
    var currIndex: int
    var prevIndex: int

    template playArrow(speed: float32) =
        currIndex = startRotation.int div SECTOR_STEP.int
        if currIndex != prevIndex:
            prevIndex = currIndex
            arrowAnim.cancel()
            var duration = (wheelCmp.constSpeed-speed)/900.0
            if duration < 0.05: duration = 0.05
            arrowAnim = arrowAnchor.playArrow(duration)

    anim.onAnimate = proc(p: float) =
        if not finished:
            var delta = getDeltaTime()
            if delta > 0.1: delta = 0.1

            template incr() =
                playArrow(currSpeed)
                startRotation += currSpeed * delta
                norm()
                rotAnchor.rotation = aroundZ(startRotation)
                yellowAnchor.rotation = aroundZ(startRotation)

            case currAnimStage:
            of speedup:
                if currSpeed <= wheelCmp.constSpeed:
                    currSpeed += wheelCmp.acceleration
                else:
                    currAnimStage = constant
                    return
            of constant:
                if canStop():
                    currAnimStage = slowdown
                    destRotation = (SECTORS_COUNT - w.currResponse.currSector).float32 * SECTOR_STEP
                    return
            of slowdown:
                if spinAnticipationSfx.isNil:
                    spinAnticipationSfx = w.playAnticipation()

                if currSpeed >= wheelCmp.slowdownSpeed:
                    currSpeed -= wheelCmp.acceleration
                else:
                    if startRotation >= destRotation - wheelCmp.beforeStopSteps * SECTOR_STEP - currSpeed * delta and startRotation <= destRotation :
                        currAnimStage = finish
                        return
            of finish:
                if startRotation >= destRotation - SECTOR_STEP - currSpeed * delta and startRotation <= destRotation:
                    if not spinAnticipationSfx.isNil:
                        spinAnticipationSfx.stop()
                        w.sendEvent("WHEEL_ANTICIPATION_END")
                        spinAnticipationSfx = nil

                if currSpeed >= wheelCmp.stopSpeed:
                    currSpeed -= wheelCmp.acceleration

                if startRotation >= destRotation - currSpeed * delta:
                    finished = true
                    rotAnchor.rotation = aroundZ(destRotation)
                    yellowAnchor.rotation = aroundZ(startRotation)
                    anim.cancel()
                    anim.removeHandlers()
                    callback()
                    return
            incr()

    w.isBusy = true
    w.anchorNode.addAnimation(anim)
    pushBack(RateUsFlowState)


const SERVER_RESPONSE_TIMEOUT = 8.0
proc handleResponseTimeout(v: WheelWindow) =
    sharedAnalytics().wnd_connect_lost_show()
    showLostConnectionAlert()
    info "Response timeout"

proc sendSpinRequest(w: WheelWindow, handler: proc(j: JsonNode)) =
    var gotResponse = false
    sharedServer().spinFortuneWheel proc(res: JsonNode) =
        echo "sendSpinRequest: ", res
        handler(res)
        gotResponse = true
    w.anchorNode.sceneView.wait(SERVER_RESPONSE_TIMEOUT) do():
        if not gotResponse:
            w.handleResponseTimeout()

proc restoreState(w: WheelWindow, handler: proc(j: JsonNode)) =
    var gotResponse = false
    sharedServer().getFortuneWheelState proc(res: JsonNode) =
        echo "restoreState: ", res
        handler(res)
        gotResponse = true
    w.anchorNode.sceneView.wait(SERVER_RESPONSE_TIMEOUT) do():
        if not gotResponse:
            w.handleResponseTimeout()

proc setupSpinCost(spinbutton: Node, cost: int) =
    let money = spinbutton.findNode("WHEEL_SPIN_BUTTON_SPIN_COST_@noloc")
    let txt = money.componentIfAvailable(Text)
    txt.text = $cost

proc playScaleAnim(w: WheelWindow, compName, animName: string) =
    let anNd = w.anchorNode.findNode(compName)
    let an = anNd.animationNamed(animName)
    if not w.anchorNode.sceneView.isNil:
        w.anchorNode.addAnimation(an)

proc playButtonScaleAnim(w: WheelWindow, name: string) =
    w.playScaleAnim("spin_wheel_clicker", name)

proc playArrowsScaleAnim(w: WheelWindow, name: string) =
    w.playScaleAnim("arrows", name)

proc showButton(w: WheelWindow, cost: int): Node =
    if cost == 0:
        w.anchorNode.findNode("pay_spin").hide(0)
        result = w.anchorNode.findNode("free_spin")
    else:
        w.anchorNode.findNode("free_spin").hide(0)
        result = w.anchorNode.findNode("pay_spin")
        result.setupSpinCost(cost)
    result.show(0)
    w.playButtonScaleAnim("in")

proc addButton(n: Node, r: Rect, callback: proc()) =
    let button = newButton(r)
    n.component(UIComponent).view = button
    button.hasBezel = false
    button.onAction do():
        callback()

proc showUiWin(w: WheelWindow)
proc showUiHistory(w: WheelWindow)
proc setupUi(w: WheelWindow, callback: proc() = nil)

proc openWheelAnalytics(w: WheelWindow) =
    let diffTime = w.currResponse.freeSpinTimeout - w.time
    var fullHours: int

    if diffTime > 0:
        fullHours = (diffTime / 3600).int
    sharedAnalytics().wnd_wheel_open(fullHours, w.source)

proc spinWheelAnalytics(w: WheelWindow, r: WheelResponse) =
    let s = w.layout.sectors[r.currSector]

    let result = $s.winType & " " & $s.winValue
    sharedAnalytics().wheel_spin(w.prevResponse.nextSpinCost, result, w.lastResult, w.source, currentUser().bucks)
    w.lastResult = result
    w.lastActionSpins.inc()
    w.spentBucks += w.prevResponse.nextSpinCost

proc addHistory(w: WheelWindow, r: WheelResponse) =
    w.history[2] = w.history[1]
    w.history[1] = w.history[0]
    let s = w.layout.sectors[r.currSector]
    w.history[0] = (s.winType, s.winValue)

proc arrowsRotation(w: WheelWindow) =
    let arr = w.anchorNode.findNode("arrows").findNode("spin_arrows")
    let an = newAnimation()
    an.numberOfLoops = 1
    an.timingFunction = quadEaseInOut
    an.loopDuration = 1.5
    an.animate val in 0.0 .. 360.0:
        arr.rotation = aroundZ(val)
    w.anchorNode.addAnimation(an)

proc winCircleAnim(w: WheelWindow, numLoops: int = 1, cb: proc() = nil): Animation =
    let anchor = w.anchorNode.findNode("arrow_frame")

    var children: array[24, Node]
    for i in 0..<children.len:
        children[i] = anchor.findNode("small_light_" & $(1+i)).findNode("light")

    let an = newAnimation()
    an.numberOfLoops = numLoops
    an.loopDuration = 2.5

    let border = children.len
    let delay = 3.5
    let scaleDiv = 1.75
    let step = an.loopDuration/border.float32/delay
    var progress = 0.0
    let duration = an.loopDuration/border.float32*delay

    for i in 0..<border:
        closureScope:
            let index = i
            an.addLoopProgressHandler(progress, false) do():
                let anim = newAnimation()
                anim.numberOfLoops = 1
                anim.loopDuration = duration
                anim.loopPattern = lpStartToEndToStart
                anim.animate val in 0.0 .. 1.0:
                    children[index].alpha = val
                    children[index].scaleX = 1.0 + val/scaleDiv
                    children[index].scaleY = 1.0 + val/scaleDiv

                if not w.anchorNode.sceneView.isNil:
                    w.anchorNode.addAnimation(anim)

            progress += step
    result = an
    if not w.anchorNode.sceneView.isNil:
        w.anchorNode.addAnimation(an)
    an.onComplete do():
        if not cb.isNil: cb()

proc winScissorsAnim(w: WheelWindow, numLoops: int = 1, cb: proc() = nil) =
    let anchor = w.anchorNode.findNode("arrow_frame")

    var children: array[24, Node]
    for i in 0..<children.len:
        children[i] = anchor.findNode("small_light_" & $(1+i)).findNode("light")

    let an = newAnimation()
    an.numberOfLoops = numLoops
    an.loopDuration = 1.75

    let border = children.len div 2
    let delay = 3.5
    let scaleDiv = 1.25
    let step = an.loopDuration/border.float32/delay
    var progress = 0.0
    let duration = an.loopDuration/border.float32*delay

    for i in 0..<border:
        closureScope:
            let index = i
            an.addLoopProgressHandler(progress, false) do():
                let anim = newAnimation()
                anim.numberOfLoops = 1
                anim.loopDuration = duration
                anim.loopPattern = lpStartToEndToStart
                anim.animate val in 0.0 .. 1.0:
                    children[index].alpha = val
                    children[index].scaleX = 1.0 + val/scaleDiv
                    children[index].scaleY = 1.0 + val/scaleDiv

                    children[children.len-1-index].alpha = val
                    children[children.len-1-index].scaleX = 1.0 + val/scaleDiv
                    children[children.len-1-index].scaleY = 1.0 + val/scaleDiv

                if not w.anchorNode.sceneView.isNil:
                    w.anchorNode.addAnimation(anim)

            progress += step

    if not w.anchorNode.sceneView.isNil:
        w.anchorNode.addAnimation(an)
    an.onComplete do():
        if not cb.isNil: cb()

proc blinkAnim(nodes: openarray[Node], scaleDiv: float32 = 2.0, loopDuration: float32 = 1.5, numLoops: int = -1): Animation =
    let ndArray = @nodes
    result = newAnimation()
    result.numberOfLoops = numLoops
    result.loopDuration = loopDuration
    result.timingFunction = quadEaseInOut
    result.loopPattern = lpStartToEndToStart
    result.animate val in 0.0 .. 1.0:
        for i in 0..<ndArray.len:
            var scaledif: float32
            if i mod 2 == 0:
                ndArray[i].alpha = val
                scaledif = val/scaleDiv
            else:
                ndArray[i].alpha = 1.0 - val
                scaledif = (1.0 - val)/scaleDiv
            ndArray[i].scaleX = 1.0 + scaledif
            ndArray[i].scaleY = 1.0 + scaledif

proc blinkIdleAnim(w: WheelWindow) =
    let anchor = w.anchorNode.findNode("yellow_anchor")
    var children: array[10, Node]
    for i, ch in anchor.children:
        children[i] = ch.findNode("light")
    if not w.anchorNode.sceneView.isNil:
        w.anchorNode.addAnimation(blinkAnim(children, 2.0, 1.5, -1))

proc blinkWinAnim(w: WheelWindow, clbck: proc() = nil) =
    let anchor = w.anchorNode.findNode("arrow_frame")
    var children: array[24, Node]
    var i = 0
    for ch in anchor.children:
        if ch.name.contains("small_"):
            children[i] = ch.findNode("light")
            inc i
    let an = blinkAnim(children, 2.0, 1.5, 1)
    an.onComplete do():
        if not clbck.isNil: clbck()
    if not w.anchorNode.sceneView.isNil:
        w.anchorNode.addAnimation(an)

proc animateWallet(w: WheelWindow, duration: float32 = 1.0) =
    let anim = newAnimation()
    anim.loopDuration = duration
    anim.numberOfLoops = 1

    let el = w.layout.sectors[w.currResponse.currSector]
    case el.winType:
    of spins:
        discard
    of chips:
        anim.loopDuration = duration * 2.0
        anim.onAnimate = proc(p: float) =
            currentUser().updateWallet(chips = interpolate(w.prevResponse.wallet.chips, w.currResponse.wallet.chips, p))
    of bucks:
        anim.onAnimate = proc(p: float) =
            currentUser().updateWallet(bucks = interpolate(w.prevResponse.wallet.bucks, w.currResponse.wallet.bucks, p))
    of energy:
        anim.onAnimate = proc(p: float) =
            currentUser().updateWallet(parts = interpolate(w.prevResponse.wallet.parts, w.currResponse.wallet.parts, p))

    if not w.anchorNode.sceneView.isNil:
        w.anchorNode.addAnimation(anim)
    else:
        let dChips = w.currResponse.wallet.chips
        let dBucks = w.currResponse.wallet.bucks
        let dParts = w.currResponse.wallet.parts
        currentUser().updateWallet(dChips, dBucks, dParts, w.currResponse.wallet.tournamentPoints)

proc isDayPassed(w: WheelWindow): bool =
    let diffTime = w.currResponse.freeSpinTimeout - w.time
    result = diffTime <= 0

proc freeSpins(w: WheelWindow): int =
    result = w.currResponse.freeSpinsLeft
    if w.isDayPassed():
        result += 1

proc spin(w: WheelWindow) =
    if w.canSpin:
        w.canSpin = false
        let cost = w.currResponse.nextSpinCost

        if not currentUser().withdraw(bucks = cost):
            setTimeout(1.0) do():
                showStoreWindow(StoreTabKind.Bucks, "wheel")
            return

        currentUser().updateWallet(bucks = currentUser().bucks - cost)
        w.prevResponse.wallet.bucks = w.prevResponse.wallet.bucks - cost
        w.playButtonScaleAnim("out")
        w.arrowsRotation()
        w.sendEvent("WHEEL_PRESS_SPIN_SFX")
        let spinLoopSfx = w.playSpinLoop()

        let freeSpinsLeft = w.freeSpins() - 1
        w.anchorNode.findNode("ui_1").findNode("WHEEL_UI_1_TEXT_COUNTER").component(Text).text = $freeSpinsLeft

        w.sendSpinRequest do(j: JsonNode):
            w.prevResponse = w.currResponse
            w.currResponse = getResponse(j)
            if cost == 0:
                currentNotificationCenter().postNotification("WHEEL_FREE_SPIN", newVariant(w.currResponse.freeSpinTimeout - w.currResponse.timeDiff))

            if w.wasWin:
                w.addHistory(w.prevResponse)
            w.spinWheelAnalytics(w.currResponse)
            w.time = w.currResponse.timeDiff
            w.canStop = true

            w.completion.to do():
                if not spinLoopSfx.isNil:
                    spinLoopSfx.stop()
                w.sendEvent("WHEEL_WIN_SFX")

                discard w.showButton(w.currResponse.nextSpinCost)

                w.canSpin = true
                w.canStop = false

                if w.wasWin:
                    w.showUiHistory()
                w.wasWin = true
                w.setupUi()
                w.showUiWin()
                w.animateWallet()

                w.idleAnim.cancel()
                w.winScissorsAnim(1) do():
                    w.blinkWinAnim do():
                        w.idleAnim = w.winCircleAnim(-1)


        w.spin(proc(): bool = w.canStop) do():
            w.completion.finalize()

proc setupSpinButton(w: WheelWindow) =
    var spinbutton = w.showButton(w.currResponse.nextSpinCost)
    # rename for tutorial
    let bttnNode = spinbutton.findNode("spin_wheel_but")
    bttnNode.name = "spin_wheel_but_tut"
    let bttn = bttnNode.createButtonComponent(newRect(0,0,115,115))
    bttn.onAction do():
        w.spin()

proc setupTimerUi(w: WheelWindow) =
    if w.timerStarted:
        return
    w.timerStarted = true
    let ui2 = w.anchorNode.findNode("ui_2").findNode("timer_wheel")
    let ui2H = ui2.findNode("WHEEL_UI_2_TIMER_HOURS_@noloc").getComponent(Text)
    let ui2M = ui2.findNode("WHEEL_UI_2_TIMER_MINUTES_@noloc").getComponent(Text)
    let ui2S = ui2.findNode("WHEEL_UI_2_TIMER_SECONDS_@noloc").getComponent(Text)

    template setupTime(h, m, s: string) =
        ui2H.text = if parseFloat(h).int < 10: "0" & h else: h
        ui2M.text = if parseFloat(m).int < 10: "0" & m else: m
        ui2S.text = s

    proc updateTime() =
        w.time = w.time + 1.0
        let diffTime = w.currResponse.freeSpinTimeout - w.time
        let timeLeft = if diffTime <= 0: 0.0 else: diffTime
        let time = formatDiffTime(timeLeft)
        if time.len > 3:
            setupTime(time[1], time[2], time[3])
        if timeLeft <= 0:
            w.setupUi()
            discard w.showButton(0)
            w.time = 0
            w.currResponse.nextSpinCost = 0

    updateTime()

    let anim = newAnimation()
    anim.loopDuration = 1.0
    anim.numberOfLoops = -1
    anim.addLoopProgressHandler(1.0, false) do():
        updateTime()
    if not w.anchorNode.sceneView.isNil:
        w.anchorNode.addAnimation(anim)

proc showUiHistory(w: WheelWindow) =
    let ui2 = w.anchorNode.findNode("ui_2").findNode("list")

    for i in countdown(3, 1):
        let el = w.history[i-1]
        if el.winValue != 0:
            let currCell = ui2.findNode("winning_history_" & $i)
            for ch in currCell.children: ch.hide(0)

            currCell.findNode("WHEEL_UI_2_LIST_AMOUNT_@noloc").show(0)
            currCell.findNode("WHEEL_UI_2_LIST_AMOUNT_@noloc").getComponent(Text).text = amountNormalize(el.winValue)

            currCell.findNode("WHEEL_UI_2_LIST_TYPE_@noloc").show(0)
            case el.winType:
            of spins:
                currCell.findNode("WHEEL_UI_2_LIST_TYPE_@noloc").getComponent(Text).text = localizedString("WHEEL_FREESPIN")
            of chips:
                currCell.findNode("chips_placeholder").show(0.0)
                currCell.findNode("WHEEL_UI_2_LIST_TYPE_@noloc").getComponent(Text).text = localizedString("WHEEL_CHIPS")
            of bucks:
                currCell.findNode("bucks_placeholder").show(0.0)
                currCell.findNode("WHEEL_UI_2_LIST_TYPE_@noloc").getComponent(Text).text = localizedString("WHEEL_BUCKS")
            of energy:
                currCell.findNode("energy_placeholder").show(0.0)
                currCell.findNode("WHEEL_UI_2_LIST_TYPE_@noloc").getComponent(Text).text = localizedString("WHEEL_ENERGY")

const REWARDS_OUT_DURATION = 0.65
proc addRewardFlyAnim(w: WheelWindow, sourceNode: Node, destNode: Node, scale: Vector3) =
    var s = sourceNode.worldPos
    let e = if not destNode.isNil: destNode.worldPos else: s
    let p1 = (e - s) / 3 + s + newVector3(rand(-300.0 .. 300.0), rand(-300.0 .. 300.0), 0)
    let p2 = (e - s) * 2 / 3 + s + newVector3(rand(-300.0 .. 300.0), rand(-300.0 .. 300.0), 0)
    let c1 = newVector3(p1.x, p1.y, s.z)
    let c2 = newVector3(p2.x, p2.y, s.z)
    let initialScale = sourceNode.scale
    let flyAnim = newAnimation()
    flyAnim.loopDuration = REWARDS_OUT_DURATION
    flyAnim.numberOfLoops = 1
    flyAnim.onAnimate = proc(p:float) =
        let t = interpolate(0.0, 1.0, p)
        let point = calculateBezierPoint(t, s, e, c1, c2)
        sourceNode.scale = interpolate(newVector3(1.0, 1.0, 1.0), scale, p) * initialScale
        if sourceNode.scaleX != 0 and sourceNode.scaleY != 0 and sourceNode.scaleZ != 0:
            var parentTr: Matrix4
            if sourceNode.parent.worldTransform.tryInverse(parentTr):
                sourceNode.position = parentTr * point

    flyAnim.onComplete do():
        sourceNode.removeFromParent()
    w.anchorNode.addAnimation(flyAnim)

proc showUiWin(w: WheelWindow) =
    if w.anchorNode.sceneView.isNil:
        return

    let ui2 = w.anchorNode.findNode("ui_2").findNode("prize")
    let ui2Type = ui2.findNode("WHEEL_UI_2_PRIZE_WIN_TYPE_@noloc").getComponent(Text)
    let ui2Amount = ui2.findNode("WHEEL_UI_2_PRIZE_WIN_AMOUNT_@noloc").getComponent(Text)
    for ch in ui2.findNode("prize_wheel_icon").children: ch.hide(0.0)

    w.anchorNode.addAnimation(ui2.findNode("prize").animationNamed("in"))

    let anNd2 = ui2.findNode("rewards_glow")
    let an2 = anNd2.animationNamed("in")
    w.anchorNode.addAnimation(an2)
    an2.onComplete do():
        an2.removeHandlers()
        if not w.anchorNode.sceneView.isNil:
            w.anchorNode.addAnimation(anNd2.animationNamed("idle"))

        w.isBusy = false
        addTutorialFlowState(tsWheelClose, true)

    ui2Amount.text = amountNormalize(w.layout.sectors[w.currResponse.currSector].winValue)

    ui2Type.node.show(0)
    ui2Amount.node.show(0)

    let u = currentUser()
    let pc = u.chips
    let fromNd = ui2.findNode("prize_wheel_icon")

    var toNdParent = w.anchorNode.sceneView.rootNode.findNode("GUI")
    if toNdParent.isNil:
        toNdParent = w.anchorNode.sceneView.rootNode.findNode("gui_parent")

    case w.layout.sectors[w.currResponse.currSector].winType:
    of spins:
        let str = localizedString("WHEEL_FREESPIN")
        ui2Type.text = str
    of chips:
        let str = localizedString("WHEEL_CHIPS")
        ui2.findNode("chips_placeholder").show(0.0)
        ui2Type.text = str

        ui2.findNode("prize_wheel_icon").findNode("chips_placeholder").show(0)

        let toNd = w.anchorNode.sceneView.rootNode.findNode("money_panel").findNode("chips_placeholder")
        w.anchorNode.sceneView.GameScene.chipsAnim(fromNd, toNd, toNdParent, 5, pc, u.chips)
    of bucks:
        let str = localizedString("WHEEL_BUCKS")
        ui2.findNode("bucks_placeholder").show(0.0)
        ui2Type.text = str

        ui2.findNode("prize_wheel_icon").findNode("bucks_placeholder").show(0)

        let toNd = w.anchorNode.sceneView.rootNode.findNode("money_panel").findNode("bucks_placeholder")
        w.anchorNode.sceneView.GameScene.bucksAnim(fromNd, toNd, toNdParent, 5, pc, u.chips)
    of energy:
        let str = localizedString("WHEEL_ENERGY")
        ui2.findNode("energy_placeholder").show(0.0)
        ui2Type.text = str

        let ui2PrizeAnchor = ui2.findNode("prize_wheel_icon")
        ui2PrizeAnchor.findNode("energy_placeholder").show(0)

        let fromNd = newNodeWithResource("tiledmap/wheel/comps/prize_wheel_icon.json")
        ui2PrizeAnchor.addChild(fromNd)
        fromNd.findNode("energy_placeholder").show(0)

        let toNd = w.anchorNode.sceneView.rootNode.findNode("money_panel").findNode("energy_placeholder")

        var scale = newVector3(0.36, 0.36, 1.0)
        w.addRewardFlyAnim(fromNd, toNd, scale)

proc setupUi(w: WheelWindow, callback: proc() = nil) =
    let ui1 = w.anchorNode.findNode("ui_1")
    let ui2 = w.anchorNode.findNode("ui_2")
    ui2.show()
    ui1.findNode("lets_spin_prize_box").hide()

    let freeSpinsLeft = w.freeSpins()

    if freeSpinsLeft > 0:
        ui1.show()
        w.sendEvent("WHEEL_DAILY_FREESPIN")
        ui1.findNode("WHEEL_UI_1_TEXT_COUNTER").component(Text).text = $freeSpinsLeft
        ui1.playComposition(callback)
        ui2.findNode("timer_wheel").hide(0)
    else:
        ui1.hide(0)
        ui2.findNode("timer_wheel").show(0)
        w.setupTimerUi()

    if w.wasWin:
        ui2.findNode("prize").show(0)
        ui2.findNode("lets_spin_prize_box").hide(0)
    else:
        ui2.findNode("prize").hide(0)
        let prizeBoxNd = ui2.findNode("lets_spin_prize_box")
        prizeBoxNd.show(0)
        setTimeout(1.5) do():
            if not w.processClose:
                prizeBoxNd.playComposition()

    if w.history.len > 0:
        ui2.findNode("WHEEL_UI_1_TEXT_LETS_WIN_PRIZE").hide(0)
        ui2.findNode("list").show(0)
    else:
        ui2.findNode("WHEEL_UI_1_TEXT_LETS_WIN_PRIZE").show(0)
        ui2.findNode("list").hide(0)

proc manageFixTransform(w: WheelWindow, job: proc(n: Node)) =
    if w.anchorNode.isNil or w.anchorNode.findNode("cabs_ancor").isNil:
        return
    for ch in w.anchorNode.findNode("cabs_ancor").children: ch.job()
    for ch in w.anchorNode.findNode("yellow_anchor").children: ch.job()
    for ch in w.anchorNode.findNode("sector_dots_anchor").children: ch.job()

method hideStrategy*(w: WheelWindow): float =
    w.mapFreeze(false)
    procCall w.WindowComponent.closeButtonClick()

    if w.anchorNode.isNil or w.anchorNode.findNode("spin_wheel_clicker").isNil:
        return 0.0

    w.manageFixTransform do(n: Node):
        n.removeComponent(FixTransform)
    if w.anchorNode.findNode("spin_wheel_clicker").alpha > 0.5:
        w.playButtonScaleAnim("out")
        w.playArrowsScaleAnim("out")

    let anim = w.anchorNode.findNode("wheel_all").playComposition("out") do():
        w.completion.finalize()

    sharedAnalytics().wnd_wheel_closed(w.lastActionSpins, w.spentBucks, w.lastResult, currentUser().bucks)

    result = anim.loopDuration

proc setupCloseButton(w: WheelWindow) =
    var bOnce = true
    let btnClose = w.anchorNode.findNode("button_close")
    let closeAnim = btnClose.animationNamed("play")
    btnClose.component(ButtonComponent).onAction do():
        if bOnce and not w.isBusy:
            bOnce = false
            w.anchorNode.addAnimation(closeAnim)
            closeAnim.addLoopProgressHandler(0.25, false) do():
                w.closeButtonClick()

method onInit*(w: WheelWindow) =
    w.canSpin = true
    w.canStop = false
    w.anchorNode = newLocalizedNodeWithResource("tiledmap/wheel/comps/wheel_all.json")
    w.node.addChild(w.anchorNode)
    w.completion = newCompletion()
    w.setupCloseButton()
    w.node.hide(0)
    w.lastResult = "NONE"
    let v = w.node.sceneView.GameScene
    v.soundManager.loadEvents("tiledmap/wheel/sounds/wheel")

    if isFrameClosed($tsWheelClose):
        w.moneyPanelOnTop = true
    if w.source.len == 0:
        w.source = "deepLink"

    w.mapFreeze(true)

proc freeSpinsForNextVipLevel(): int =
    let vipConfig = sharedVipConfig()

    let currentVipLevel = max(currentUser().vipLevel,0)
    var nextVipLevel = currentVipLevel + 1
    if nextVipLevel > vipConfig.levels.high:
        nextVipLevel = currentVipLevel
    result = vipConfig.getLevel(nextVipLevel).wheelReward

proc setupVip(w: WheelWindow) =
    w.vipNode = newLocalizedNodeWithResource("common/gui/popups/precomps/vip_wheel")
    w.node.findNode("gui_wheel_all").addChild(w.vipNode)
    discard w.vipNode.findNode("reward_icons_placeholder").addRewardIcon("vipPoints")
    # Fix broken text export
    let vip = w.vipNode.findNode("VIP_CAPS")
    let bonus = w.vipNode.findNode("BONUS_CAPS")
    vip.position = newVector3(203,-27)
    vip.component(Text).fontSize = 42.0
    bonus.position = newVector3(203,11)
    let nfs = freeSpinsForNextVipLevel()
    w.vipNode.findNode("NEXT_VIP_LEVEL_GAIN").component(Text).text = "+" & $nfs & " " & localizedString("NEXT_VIP_LEVEL_GAIN")
    w.vipNode.playComposition("in")


method showStrategy*(w: WheelWindow) =
    w.node.position = newVector3(960.0, 540.0)
    w.node.anchor = newVector3(960.0, 540.0)
    w.restoreState do(j: JsonNode):
        w.node.show(0)
        addTutorialFlowState(tsWheelSpin, true)
        w.anchorNode.findNode("wheel_all").playComposition("in") do():
            w.isBusy = false

        w.playArrowsScaleAnim("in")
        w.manageFixTransform do(n: Node):
            discard n.component(FixTransform)
        w.blinkIdleAnim()

        (w.layout, w.history) = getLayoutAndHistory(j)
        w.currResponse = w.layout.initResponse
        w.currResponse.wallet = (currentUser().chips, currentUser().bucks, currentUser().parts, currentUser().tournPoints)
        w.prevResponse = w.currResponse
        w.time = w.currResponse.timeDiff

        w.setupLayout(w.layout)
        w.setupSpinButton()
        w.setupUi()
        w.showUiHistory()
        w.openWheelAnalytics()
        w.setupVip()

        w.idleAnim = w.winCircleAnim(-1)

method onShowed*(w: WheelWindow) =
    discard
    # procCall w.WindowComponent.onShowed()

method assetBundles*(v: WheelWindow): seq[AssetBundleDescriptor] =
    const BUNDLES = [
        assetBundleDescriptor("tiledmap/wheel")
    ]
    result = @BUNDLES

registerComponent(WheelWindow, "windows")
