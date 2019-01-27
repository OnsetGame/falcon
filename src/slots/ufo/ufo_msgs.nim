import
    random, strutils,nimx.matrixes,nimx.view,nimx.window,nimx.animation,nimx.image,nimx.timer,nimx.font,nimx.types,rod.rod_types,rod.node,
    rod.viewport,rod.component.text_component,rod.component.particle_emitter,rod.component.sprite,rod.component.solid,rod.component, rod.component.particle_system,
    rod.component.visual_modifier,rod.component.rti,tables,core.slot.base_slot_machine_view,shared.win_popup,utils.sound,utils.sound_manager,utils.displacement,
    slots.mermaid.anim_helpers, rod.component.ae_composition, utils.helpers

import utils / [sound, sound_manager]

export win_popup

type UfoWinDialogWindow* = ref object of WinDialogWindow
    bonusNode: Node
    msgNode: Node
    onOutAnim: proc()
    destroyer: proc()

var sm: SoundManager
var UFOWDWCache = TableRef[string, Node]()
const UfoMessagesCompositionsPrefix = "slots/ufo_slot/msgs/Precomps/"
const UfoSoundPrefix = "slots/ufo_slot/ufo_sound/"

proc setupDisplacement(parent, rtiNode, displNode: Node, displName: string, displParam: Size) =
    let msRTI = rtiNode.component(RTI)
    msRTI.bBlendOne = true
    parent.sceneView.wait(0.25) do():
        msRTI.bFreezeBounds = true
        msRTI.bDraw = false

    let d = displNode.component(Displacement)
    d.displacementNode = parent.findNode(displName)
    d.rtiNode = rtiNode
    d.displSize = displParam

proc removeDisplacement(rtiNode, displNode: Node) =
    displNode.removeComponent(Displacement)
    rtiNode.removeComponent(RTI)

proc setupMsg(parent, rtiNode, displNode: Node, onDestroy: proc() = nil): UfoWinDialogWindow =
    let branding = UFOWDWCache["all_branding"]
    branding.show(0.0)
    parent.addChild(branding)
    result = new(UfoWinDialogWindow)
    result.node = branding
    result.onDestroy = onDestroy
    result.bonusNode = branding.findNode("branding_bonus")
    result.msgNode = branding.findNode("branding_not_bonus")
    result.bonusNode.hide(0)
    result.msgNode.hide(0)

proc cleanupMsg(wd: UfoWinDialogWindow, rtiNode, displNode: Node) =
    wd.node.hide(0)
    removeDisplacement(rtiNode, displNode)
    wd.node.removeFromParent()
    wd.node.show(0.0)
    wd.readyForClose = true

proc onOutAnimStart(wd: UfoWinDialogWindow) =
    if not wd.onOutAnim.isNil:
        wd.onOutAnim()

proc setupAnims(wd: UfoWinDialogWindow, targetNode: Node, cleanup: proc() = nil): Animation {.discardable.} =
    var idleStarted = false

    let peNode = targetNode.findNode("particle_anchor").findNode("triangle")
    let pe = peNode.getComponent(ParticleSystem)
    pe.start()

    let inAnim = targetNode.component(AEComposition).compositionNamed("in")
    let idleAnim = targetNode.component(AEComposition).compositionNamed("idle")
    let outAnim = targetNode.component(AEComposition).compositionNamed("out")

    inAnim.onComplete do():
        pe.stop()
        if not idleStarted:
            idleStarted = true
            targetNode.addAnimation(idleAnim)
        else:
            targetNode.addAnimation(outAnim)

    idleAnim.onComplete do():
        targetNode.addAnimation(outAnim)

    outAnim.addLoopProgressHandler(0.0, false) do():
        wd.onOutAnimStart()

    outAnim.onComplete do():
        if not cleanup.isNil:
            cleanup()
        if not wd.onDestroy.isNil:
            wd.onDestroy()

    result = outAnim

    wd.destroyer = proc() =
        if idleStarted:
            idleAnim.cancel()
        else:
            idleStarted = true

    targetNode.addAnimation(inAnim)

proc showBonus*(parent, rtiNode, displNode: Node, onDestroy: proc() = nil): UfoWinDialogWindow {.discardable.} =
    var res = setupMsg(parent, rtiNode, displNode, onDestroy)
    setupDisplacement(res.bonusNode, rtiNode, displNode, "displace_up", newSize(0.0, -0.2))
    res.bonusNode.show(0.25)
    let outAnim = res.setupAnims(res.bonusNode)

    outAnim.addLoopProgressHandler(0.0, false) do():
        res.onOutAnimStart()

    outAnim.addLoopProgressHandler(0.8, false) do():
        if not res.onDestroy.isNil:
            res.onDestroy()
            res.onDestroy = nil
        removeDisplacement(rtiNode, displNode)

    outAnim.onComplete do():
        cleanupMsg(res, rtiNode, displNode)
        res.bonusNode.hide(0)

    result = res
    result.onOutAnim = proc() = sm.sendEvent("BONUS_OUT")

proc showNotBonus(parent, rtiNode, displNode: Node, onDestroy: proc() = nil): UfoWinDialogWindow =
    var res = setupMsg(parent, rtiNode, displNode, onDestroy)
    setupDisplacement(res.msgNode, rtiNode, displNode, "displace_right", newSize(-0.2, 0.0))
    res.msgNode.show(0.25)
    result = res

proc showFreespins*(parent, rtiNode, displNode: Node, onDestroy: proc() = nil): UfoWinDialogWindow {.discardable.} =
    let res = showNotBonus(parent, rtiNode, displNode, onDestroy)
    let freespNode = res.msgNode.findNode("free_title")
    freespNode.show(0)
    res.setupAnims(res.msgNode) do():
        cleanupMsg(res, rtiNode, displNode)
        freespNode.hide(0)
    result = res
    result.onOutAnim = proc() = sm.sendEvent("FREESPINS_OUT")

proc showRespins*(parent, rtiNode, displNode: Node, onDestroy: proc() = nil): UfoWinDialogWindow {.discardable.} =
    let res = showNotBonus(parent, rtiNode, displNode, onDestroy)
    let respinsNode = res.msgNode.findNode("respins")
    respinsNode.show(0)
    res.setupAnims(res.msgNode) do():
        cleanupMsg(res, rtiNode, displNode)
        respinsNode.hide(0)
    result = res
    result.onOutAnim = proc() = sm.sendEvent("RESPINS_OUT")

proc showCountedFreespins*(parent, rtiNode, displNode: Node, count: int = 2, onDestroy: proc() = nil): UfoWinDialogWindow {.discardable.} =
    let res = showNotBonus(parent, rtiNode, displNode, onDestroy)
    let freespNode = res.msgNode.findNode("2FreeSpins_title")
    let counterPreNames = ["white", "blue1", "blue2", "blue3"]
    for n in counterPreNames:
        freespNode.findNode("fs_" & n & "_@noloc").getComponent(Text).text = "+" & $count
    freespNode.show(0)
    res.setupAnims(res.msgNode) do():
        cleanupMsg(res, rtiNode, displNode)
        freespNode.hide(0)
    result = res
    result.onOutAnim = proc() = sm.sendEvent("COUNTED_FREESPINS_OUT")

proc show5InARow*(parent, rtiNode, displNode: Node, onDestroy: proc() = nil): UfoWinDialogWindow {.discardable.} =
    let res = showNotBonus(parent, rtiNode, displNode, onDestroy)
    let fiveNode = res.msgNode.findNode("five_of_a_kind")
    fiveNode.show(0)
    res.setupAnims(res.msgNode) do():
        cleanupMsg(res, rtiNode, displNode)
        fiveNode.hide(0)
    result = res
    result.onOutAnim = proc() = sm.sendEvent("5_IN_A_ROW_OUT")

method destroy*(winAnim: UfoWinDialogWindow) =
    if not winAnim.destroyer.isNil:
        winAnim.destroyer()

proc showSpecGameResult(parent, rtiNode, displNode: Node, totalWin: int64 = 0, lrs: openarray[Node], cntrs: openarray[Node], onDestroy: proc()): UfoWinDialogWindow =
    let res = showNotBonus(parent, rtiNode, displNode, onDestroy)
    let layers = @lrs
    for n in layers: n.show(0)
    let counters = @cntrs
    var str = ""
    for i in 0..< len($totalWin):
        str &= rand("#$%&@")

    template setupStr(s: string) =
        for ct in counters:
            ct.component(Text).text = s
    setupStr(str)

    proc playCounter(loopDuration: float32, cb: proc()) =
        let counterAnim = newAnimation()
        counterAnim.cancelBehavior = cbJumpToEnd
        counterAnim.loopDuration = loopDuration
        counterAnim.numberOfLoops = 1
        counterAnim.onAnimate = proc(p: float) =
            setupStr($interpolate(0.int64, totalWin, p))

        res.msgNode.addAnimation(counterAnim)
        counterAnim.onComplete(cb)

    let aeComp = res.msgNode.component(AEComposition)
    let idleAnim = aeComp.compositionNamed("idle")
    let inAnim = res.msgNode.playComposition("in") do():
        res.msgNode.addAnimation(idleAnim)
        idleAnim.numberOfLoops = -1
        idleAnim.onComplete do():
            let outAnim = res.msgNode.playComposition("out") do():
                cleanupMsg(res, rtiNode, displNode)
                for n in layers: n.hide(0)

                if not res.onDestroy.isNil:
                    res.onDestroy()

            outAnim.addLoopProgressHandler(0.0, false) do():
                res.onOutAnimStart()

    playCounter(4.0) do():
        res.readyForClose = true

    result = res
    result.destroyer = proc() =
        idleAnim.numberOfLoops = 0

proc getFreespinsAndBonusCounters(): array[5, Node] =
    let freeAndBonus = UFOWDWCache["all_branding"].findNode("free_and_bonus_results")
    result = [
        freeAndBonus.findNode("win_count_white_@noloc"),
        freeAndBonus.findNode("win_count_blue1_@noloc"),
        freeAndBonus.findNode("win_count_blue2_@noloc"),
        freeAndBonus.findNode("win_count_blue3_@noloc"),
        freeAndBonus.findNode("win_count_blue4_@noloc")
    ]

proc showFreespinsResult*(parent, rtiNode, displNode: Node, totalWin: int64 = 0, onDestroy: proc() = nil): UfoWinDialogWindow {.discardable.} =
    let allNd = UFOWDWCache["all_branding"]
    let freeAndBonus = allNd.findNode("free_and_bonus_results")
    let nodes = [
        freeAndBonus.findNode("free_and_bonus_results"),
        freeAndBonus.findNode("freespins_white_@noloc"),
        freeAndBonus.findNode("freespins_blue1_@noloc"),
        freeAndBonus.findNode("freespins_blue2_@noloc"),
        freeAndBonus.findNode("freespins_blue3_@noloc"),
        freeAndBonus.findNode("freespins_blue4_@noloc")
    ]
    let counters = getFreespinsAndBonusCounters()
    result = showSpecGameResult(parent, rtiNode, displNode, totalWin, nodes, counters, onDestroy)
    result.onOutAnim = proc() = sm.sendEvent("FREESPINS_RESULT_OUT")

proc showBonusResult*(parent, rtiNode, displNode: Node, totalWin: int64 = 0, onDestroy: proc() = nil): UfoWinDialogWindow {.discardable.} =
    let allNd = UFOWDWCache["all_branding"]
    let freeAndBonus = allNd.findNode("free_and_bonus_results")
    let nodes = [
        freeAndBonus.findNode("free_and_bonus_results"),
        freeAndBonus.findNode("bonusgame_white_@noloc"),
        freeAndBonus.findNode("bonusgame_blue1_@noloc"),
        freeAndBonus.findNode("bonusgame_blue2_@noloc"),
        freeAndBonus.findNode("bonusgame_blue3_@noloc"),
        freeAndBonus.findNode("bonusgame_blue4_@noloc")
    ]
    let counters = getFreespinsAndBonusCounters()
    result = showSpecGameResult(parent, rtiNode, displNode, totalWin, nodes, counters, onDestroy)
    result.onOutAnim = proc() = sm.sendEvent("BONUS_RESULT_OUT")

proc collectWinNodesWithSubnames(subzero: string): array[11, Node] =
    let wt = UFOWDWCache["all_branding"].findNode("win_title")
    let wt1 = wt.findNode("win_res_1")
    let wt2 = wt.findNode("win_res_2")
    result = [
        wt,
        wt1.findNode(subzero & "_white_@noloc"),
        wt1.findNode(subzero & "_blue1_@noloc"),
        wt1.findNode(subzero & "_blue2_@noloc"),
        wt1.findNode(subzero & "_blue3_@noloc"),
        wt1.findNode(subzero & "_blue4_@noloc"),
        wt2.findNode(subzero & "_white_@noloc"),
        wt2.findNode(subzero & "_blue1_@noloc"),
        wt2.findNode(subzero & "_blue2_@noloc"),
        wt2.findNode(subzero & "_blue3_@noloc"),
        wt2.findNode(subzero & "_blue4_@noloc")
    ]

proc collectCounterNodes(): array[10, Node] =
    let wt = UFOWDWCache["all_branding"].findNode("win_title")
    let wt1 = wt.findNode("win_res_1")
    let wt2 = wt.findNode("win_res_2")
    result = [
        wt1.findNode("win_count_white_@noloc"),
        wt1.findNode("win_count_blue1_@noloc"),
        wt1.findNode("win_count_blue2_@noloc"),
        wt1.findNode("win_count_blue3_@noloc"),
        wt1.findNode("win_count_blue4_@noloc"),
        wt2.findNode("win_count_white_@noloc"),
        wt2.findNode("win_count_blue1_@noloc"),
        wt2.findNode("win_count_blue2_@noloc"),
        wt2.findNode("win_count_blue3_@noloc"),
        wt2.findNode("win_count_blue4_@noloc")
    ]

proc showBigWin*(parent, rtiNode, displNode: Node, totalWin: int64 = 0, onDestroy: proc() = nil): UfoWinDialogWindow {.discardable.} =
    let nodes = collectWinNodesWithSubnames("big")
    let counters = collectCounterNodes()
    result = showSpecGameResult(parent, rtiNode, displNode, totalWin, nodes, counters, onDestroy)
    result.onOutAnim = proc() = sm.sendEvent("BIGWIN_OUT")

proc showHugeWin*(parent, rtiNode, displNode: Node, totalWin: int64 = 0, onDestroy: proc() = nil): UfoWinDialogWindow {.discardable.} =
    let nodes = collectWinNodesWithSubnames("huge")
    let counters = collectCounterNodes()
    result = showSpecGameResult(parent, rtiNode, displNode, totalWin, nodes, counters, onDestroy)
    result.onOutAnim = proc() = sm.sendEvent("HUGEWIN_OUT")

proc showMegaWin*(parent, rtiNode, displNode: Node, totalWin: int64 = 0, onDestroy: proc() = nil): UfoWinDialogWindow {.discardable.} =
    let nodes = collectWinNodesWithSubnames("mega")
    let counters = collectCounterNodes()
    result = showSpecGameResult(parent, rtiNode, displNode, totalWin, nodes, counters, onDestroy)
    result.onOutAnim = proc() = sm.sendEvent("MEGAWIN_OUT")

proc initWinDialogs*(s: SoundManager)=
    sm = s
    UFOWDWCache = newTable[string, Node]()
    # let allCmp = newLocalizedNodeWithResource(UfoMessagesCompositionsPrefix & "all_branding.json")
    let allCmp = newNodeWithResource(UfoMessagesCompositionsPrefix & "all_branding.json")
    UFOWDWCache["all_branding"] = allCmp
    allCmp.findNode("branding_bonus").alpha = 0.0
    allCmp.findNode("branding_not_bonus").alpha = 0.0

    allCmp.findNode("branding_bonus").findNode("particle_anchor").addChild(newNodeWithResource(UfoMessagesCompositionsPrefix & "bonus_triangles.json"))
    allCmp.findNode("branding_not_bonus").findNode("particle_anchor").addChild(newNodeWithResource(UfoMessagesCompositionsPrefix & "no_bonus_triangles.json"))

proc clearWinDialogsCache*() =
    UFOWDWCache = nil
    sm = nil
