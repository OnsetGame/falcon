import
    nimx.animation, nimx.window, nimx.text_field, nimx.types,
    nimx.matrixes, rod.rod_types, rod.node, rod.viewport, nimx.font,
    rod.component, rod.component.text_component, rod.component.clipping_rect_component,
    tower_lights, utils.lights_cluster, utils.helpers, random,
    rod.component.solid, strutils

import nimx.view
import nimx.button
import rod.component
import rod.component.ui_component
import shared.localization_manager

const SPEED_MULTIPLIER = 15

# when defined(js):
const STATUS_SCALE = newVector3(0.9,0.9,0.9)
# else:
    # const STATUS_SCALE = newVector3(1.0,1.0,1.0)

const ZERO_SCALE = newVector3(0.0,0.0,0.0)

type IPMessageType* {.pure.} = enum
    Wild,
    FreeSpins,
    ScatterInFreeSpins,
    LineBets,
    Idle,
    Bonus,
    Scatter,
    WinBonus,
    Win,
    FreeSpinsLeft,
    IPMessageType_len

type InfoPanel* = ref object of RootObj
    node*: Node
    ipType*: IPMessageType
    idle_anim*: LightsCluster
    win_anim*: LightsCluster
    idle_slow_anim*: LightsCluster
    lightAnimProc*: proc(cluster: LightsCluster, timeout: float, animDur: float)
    timeOutProc*: proc(timeout: float, callback: proc())
    scatter_anim: Node
    bonus_anim: Node
    status_node: Node
    animation: Animation
    texts: array[IPMessageType.IPMessageType_len.int, string]

proc lightClusterInfoPanel(op:Point, arr:auto, dir: bool = true):LightsCluster=
    result.new()
    result.count = arr.len
    result.coords = proc(i:int):Point=
        result = if dir : arr[i]
                   else : arr[arr.len - 1 - i]
        result.x += op.x
        result.y += op.y

proc newInfoPanel*(n: Node, p: Node): InfoPanel =
    result.new()
    result.node = n
    result.node.animationNamed("run").loopDuration *= SPEED_MULTIPLIER

    var clusterNode = newNode("LightClusterInfoPanel")
    const lightP = newPoint(29, 29)
    var win_anim = lightClusterInfoPanel(lightP, infoPanel_idle_coords)
    var idle_anim = lightClusterInfoPanel(lightP, infoPanel_win_coords)
    var idle_slow_anim = lightClusterInfoPanel(lightP, infoPanel_idle_coords, false)

    clusterNode.setComponent "lightClusters", newComponentWithDrawProc(proc() =
        var lc = idle_anim
        if not lc.isNil: lc.draw()
        var lw = win_anim
        if not lw.isNil: lw.draw()
        var ls = idle_slow_anim
        if not ls.isNil: ls.draw()
    )

    result.idle_anim = idle_anim
    result.win_anim = win_anim
    result.idle_slow_anim = idle_slow_anim
    result.lightAnimProc = nil

    result.scatter_anim = newLocalizedNodeWithResource("slots/eiffel_slot/eiffel_slot/precomps/panelInfo_scatter.json")
    result.bonus_anim = newLocalizedNodeWithResource("slots/eiffel_slot/eiffel_slot/precomps/panelInfo_bonus.json")
    result.node.addChild(result.scatter_anim)
    result.node.addChild(result.bonus_anim)
    result.status_node = result.node.findNode("status_text")

    var status_holder = newNode("status_holder")
    result.node.addChild(status_holder)
    result.status_node.reparentTo(status_holder)

    result.texts[IPMessageType.Wild.int] = localizedString("EIFFEL_INFO_WILD")
    result.texts[IPMessageType.FreeSpins.int] = localizedString("EIFFEL_INFO_FS")
    result.texts[IPMessageType.LineBets.int] = localizedString("EIFFEL_INFO_LB")
    result.texts[IPMessageType.Idle.int] = localizedString("EIFFEL_INFO_IDLE")
    result.texts[IPMessageType.Bonus.int] = localizedString("EIFFEL_INFO_BONUS")
    result.texts[IPMessageType.Scatter.int] = localizedString("EIFFEL_INFO_SCATTER")
    result.texts[IPMessageType.WinBonus.int] = localizedString("EIFFEL_INFO_WB")
    result.texts[IPMessageType.Win.int] = localizedString("EIFFEL_INFO_TW")
    result.texts[IPMessageType.FreeSpinsLeft.int] = localizedString("EIFFEL_INFO_FSL")
    result.texts[IPMessageType.ScatterInFreeSpins.int] = localizedString("EIFFEL_INFO_SIFS")

    result.ipType = IPMessageType.IPMessageType_len

    p.addChild(clusterNode)

proc showAnimated(ip: InfoPanel, anim_type: IPMessageType): Animation=
    var anim_node : Node
    case anim_type
    of IPMessageType.Scatter:
        anim_node = ip.scatter_anim
    of IPMessageType.Bonus:
        anim_node = ip.bonus_anim
    else:
        return

    const endR = 415.0
    var status_pos = ip.status_node.position

    var anim_play = anim_node.animationNamed("play_anim")
    anim_play.cancelBehavior = cbContinueUntilEndOfLoop
    var holder = ip.node.findNode("status_holder")

    var clipAnim = newAnimation()
    clipAnim.loopDuration = 0.5
    clipAnim.numberOfLoops = 1
    clipAnim.cancelBehavior = cbContinueUntilEndOfLoop
    clipAnim.onAnimate = proc(p:float)=
        var w : Coord = interpolate(0.0, endR*2, p)
        var h : Coord = 100
        var x : Coord = interpolate(status_pos.x, status_pos.x - endR, p)
        var y : Coord = status_pos.y - h.Coord + 10
        holder.component(ClippingRectComponent).clippingRect = newRect(x, y, w, h)

    var showAnim = newMetaAnimation(anim_play, clipAnim)
    showAnim.parallelMode = true
    showAnim.numberOfLoops = 1

    var delayAnim = newAnimation()
    delayAnim.numberOfLoops = 1
    delayAnim.loopDuration = 1.5

    var hide_anim = anim_node.animationNamed("hide_anim")
    hide_anim.cancelBehavior = cbContinueUntilEndOfLoop

    result = newMetaAnimation([showAnim, delayAnim, hide_anim])
    result.numberOfLoops = 1

proc showWin(ip: InfoPanel, toVal:int64): Animation =

    var text_comp = ip.status_node.component(Text)

    var scaleUpAnim = newAnimation()
    scaleUpAnim.loopDuration = 0.25
    scaleUpAnim.numberOfLoops = 1
    scaleUpAnim.cancelBehavior = cbContinueUntilEndOfLoop
    scaleUpAnim.onAnimate = proc(p:float)=
        ip.status_node.scale = interpolate(ZERO_SCALE, STATUS_SCALE, p)

    var winAnim = newAnimation()
    winAnim.loopDuration = 1.0
    winAnim.numberOfLoops = 1
    winAnim.cancelBehavior = cbJumpToEnd
    winAnim.onAnimate = proc(p:float)=
        var val = interpolate(0.int64, toVal, p)
        text_comp.text = ip.texts[IPMessageType.Win.int] % [$val]

    var delayAnim = newAnimation()
    delayAnim.loopDuration = 5.0
    delayAnim.numberOfLoops = 1

    var delayNotCanceble = newAnimation()
    delayNotCanceble.loopDuration = 1.0
    delayNotCanceble.numberOfLoops = 1
    delayNotCanceble.cancelBehavior = cbContinueUntilEndOfLoop

    var scaleDownAnim = newAnimation()
    scaleDownAnim.loopDuration = 0.25
    scaleDownAnim.numberOfLoops = 1
    scaleDownAnim.cancelBehavior = cbContinueUntilEndOfLoop
    scaleDownAnim.onAnimate = proc(p:float)=
        ip.status_node.scale = interpolate(STATUS_SCALE, ZERO_SCALE, p)

    result = newMetaAnimation(scaleUpAnim, winAnim, delayAnim, scaleDownAnim)
    result.numberOfLoops = 1

proc showFreespinsLeft(ip: InfoPanel, left: int64): Animation =
    var text_comp = ip.status_node.component(Text)

    text_comp.text = ip.texts[IPMessageType.FreeSpinsLeft.int] % [$left]

    var scaleUpAnim = newAnimation()
    scaleUpAnim.loopDuration = 0.25
    scaleUpAnim.numberOfLoops = 1
    scaleUpAnim.cancelBehavior = cbContinueUntilEndOfLoop
    scaleUpAnim.onAnimate = proc(p:float)=
        ip.status_node.scale = interpolate(ZERO_SCALE, STATUS_SCALE, p)

    var delayAnim = newAnimation()
    delayAnim.loopDuration = 3.0
    delayAnim.numberOfLoops = 1

    var scaleDownAnim = newAnimation()
    scaleDownAnim.loopDuration = 0.25
    scaleDownAnim.numberOfLoops = 1
    scaleDownAnim.cancelBehavior = cbContinueUntilEndOfLoop
    scaleDownAnim.onAnimate = proc(p:float)=
        ip.status_node.scale = interpolate(STATUS_SCALE, ZERO_SCALE, p)

    result = newMetaAnimation(scaleUpAnim, delayAnim, scaleDownAnim)
    result.numberOfLoops = 1

var delayAnimCounter = 0

proc showStaticText(ip: InfoPanel): Animation =

    let anim = ip.node.animationNamed("play")
    anim.loopPattern = lpStartToEnd
    anim.cancelBehavior = cbContinueUntilEndOfLoop
    anim.addLoopProgressHandler(1.0, true, proc() =
        anim.loopPattern = lpEndToStart
        )

    let delayAnim = newAnimation()
    delayAnim.tag = "delayAnim_" & $delayAnimCounter
    delayAnim.numberOfLoops = -1
    delayAnim.loopDuration = 1.0



    result = newMetaAnimation(anim, delayAnim, anim)
    result.tag = "problemAnim_" & $delayAnimCounter
    result.numberOfLoops = 1

    inc delayAnimCounter

proc showRunningText(ip: InfoPanel, text_idx: int): Animation =
    let anim = ip.node.animationNamed("run")

    var text = ip.texts[text_idx]
    var str_len = text.len
    let char_dur = 0.2
    anim.loopDuration = max((str_len.float * char_dur), 8.0)
    result = anim

proc prepareLigth(ip: InfoPanel, mtype: IPMessageType)=
    if not ip.lightAnimProc.isNil:
        if mtype == IPMessageType.Bonus or mtype == IPMessageType.Scatter:
            ip.lightAnimProc(ip.idle_slow_anim, timeout = 0.0, animDur = 2.0)
        elif mtype == IPMessageType.Win or mtype == IPMessageType.FreeSpinsLeft:
            ip.lightAnimProc(ip.idle_anim, timeout = 0.0, animDur = 2.0)
            ip.lightAnimProc(ip.win_anim, timeout = 2.0, animDur = 2.5)
        elif (mtype.int >= IPMessageType.Wild.int and mtype.int <= IPMessageType.Idle.int):
            ip.lightAnimProc(ip.idle_slow_anim, timeout = 0.0, animDur= 2.0)
        elif mtype == IPMessageType.WinBonus:
            ip.lightAnimProc(ip.win_anim, timeout = 0.0, animDur = 1.5)
            ip.lightAnimProc(ip.idle_slow_anim, timeout = 1.5, animDur = 2.0)

proc preparePanel(ip: InfoPanel, text_idx: int )=
    var text = ip.texts[text_idx]
    ip.status_node.component(Text).text = text
    ip.status_node.positionX = 962
    ip.status_node.alpha = 1.0
    ip.status_node.scale = STATUS_SCALE

proc resetPanel(ip: InfoPanel)=
    ip.status_node.positionX = 400
    ip.status_node.alpha = 0.0
    ip.status_node.scale = STATUS_SCALE
    ip.ipType = IPMessageType.IPMessageType_len

proc playAnim(ip:InfoPanel, a: Animation)=
    ip.animation = a
    ip.node.addAnimation(ip.animation)

    ip.animation.addLoopProgressHandler 1.0, true, proc()=
        ip.resetPanel()

proc animationForMessage(ip: InfoPanel, mtype: IPMessageType, arg: int64 | int): Animation =
    case mtype
    of IPMessageType.Bonus, IPMessageType.Scatter:
        var holder = ip.node.findNode("status_holder")
        holder.component(ClippingRectComponent).clippingRect = newRect(0,0,0,0)
        result = ip.showAnimated(mtype)
    of IPMessageType.Wild..IPMessageType.Idle:
        ip.status_node.positionX = 0
        result = ip.showRunningText(mtype.int)
    of IPMessageType.Win:
        result = ip.showWin(arg)
        ip.status_node.scale = ZERO_SCALE
    of IPMessageType.FreeSpinsLeft:
        result = ip.showFreespinsLeft(arg)
        ip.status_node.scale = ZERO_SCALE
    of IPMessageType.WinBonus:
        ip.status_node.positionX = 0
        result = ip.showStaticText()
    else:
        discard

proc showText*(ip: InfoPanel, mtype: IPMessageType, arg: int64= 0)=

    proc showMessage(i: InfoPanel, t: IPMessageType, a: int64)=
        i.ipType = t
        i.preparePanel(t.int)
        i.prepareLigth(t)
        i.playAnim(i.animationForMessage(t, a))

    if not ip.animation.isNil and not ip.animation.finished and not ip.animation.isCancelled():
        ip.animation.cancel()
        ip.animation.onComplete do():
            ip.showMessage(mtype, arg)
        return

    elif ip.animation.isNil or ip.animation.finished:
        ip.showMessage(mtype, arg)

proc removeTotalWinAnim*(ip: InfoPanel)=
    if not ip.animation.isNil and not ip.animation.finished and ip.ipType == IPMessageType.Win:
        ip.animation.cancel()

var testing = false

proc showRandomText*(ip: InfoPanel, isRunning:bool = true): bool =
    if testing: return true
    if ip.animation.isNil or ip.animation.finished:
        let rand = rand(IPMessageType.Idle.int)
        ip.showText(rand.IPMessageType)
        return true
    return false
