import math, boolseq
import rod / [ rod_types, node, component, viewport ]
import rod / component / [ text_component, ui_component ]
import nimx / [ matrixes, types, animation, notification_center ]

import map.collect_resources
import utils / [ progress_bar, helpers, sound_manager, falcon_analytics, outline ]
import shared.window.button_component
import shared / [ user, chips_animation, game_scene, director ]
import quest / quests
import core.zone
import core.net.server

type CollectButton* = ref object of RootObj
    rootNode*: Node
    button*: ButtonComponent
    updAnimation: Animation
    avaChips: int
    avaBucks: int
    source*: string

    hinted: bool
    onHint*: proc(text: string)
    chipsProg: float
    bucksProg: float

proc hideHint*(cb: CollectButton) =
    if not cb.hinted:
        return
    cb.hinted = false
    if not cb.onHint.isNil:
        cb.onHint("")


proc hint*(cb: CollectButton, txt: string) =
    if cb.hinted:
        return
    cb.hinted = true
    if not cb.onHint.isNil:
        cb.onHint(txt)


proc enabled*(cb: CollectButton): bool =
    result = isFeatureEnabled(FeatureType.IncomeChips)

proc hinted*(cb: CollectButton): bool =
    cb.hinted


proc updateUi(cb: CollectButton) =
    cb.avaChips = availableResources(Currency.Chips)
    cb.avaBucks = availableResources(Currency.Bucks)

    cb.chipsProg = if cb.avaChips == 0: 0.0  else: resourceCapacityProgress(Currency.Chips)
    cb.bucksProg = if cb.avaBucks == 0: 0.0  else: resourceCapacityProgress(Currency.Bucks)

    if (cb.avaChips > 0 and cb.chipsProg >= 1.0) or (cb.avaBucks > 0 and cb.bucksProg >= 1.0):
        cb.hint("!")
    else:
        cb.hideHint()

    let curChips = cb.avaChips #if cb.avaChips > 0: floor(floor(cb.avaChips / capChips * 100) / 100 * capChips.float).int else: 0
    let curBucks = cb.avaBucks #if cb.avaBucks > 0: floor(floor(cb.avaBucks / capBucks * 100) / 100 * capBucks.float).int else: 0

    let chipsIncome = cb.rootNode.findNode("income_chips").component(Text)
    chipsIncome.text = $curChips

    let bucksIncome = cb.rootNode.findNode("income_bucks").component(Text)
    bucksIncome.text = $curBucks

    # echo "update resources ", [cb.chipsProg, cb.bucksProg]

    let chipsProgComp = cb.rootNode.findNode("chips_prog").component(ProgressBar)
    let bucksProgComp = cb.rootNode.findNode("bucks_prog").component(ProgressBar)
    chipsProgComp.progress = cb.chipsProg
    bucksProgComp.progress = cb.bucksProg

    let chipsIco = cb.rootNode.findNode("chips_placeholder")
    let bucksIco = cb.rootNode.findNode("bucks_placeholder")
    chipsIco.scale = newVector3(1.5, 1.5, 1.0)
    bucksIco.scale = newVector3(1.5, 1.5, 1.0)

    for ch in chipsIco.children:
        discard ch.component(Outline)

    for ch in bucksIco.children:
        discard ch.component(Outline)

proc update*(cb: CollectButton) =
    if not cb.updAnimation.isNil:
        cb.updAnimation.cancel()

    cb.updAnimation = newAnimation()
    cb.updAnimation.onAnimate = proc(p: float) =
        if resourceCollectInitialized():
            cb.updateUi()

    if not cb.rootNode.sceneView.isNil:
        cb.rootNode.addAnimation(cb.updAnimation)

proc newCollectButton*(parent: Node): CollectButton =
    result.new()
    result.rootNode = newNodeWithResource("common/gui/ui2_0/collect_button")
    result.button = result.rootNode.createButtonComponent(result.rootNode.animationNamed("press"), newRect(4.5, 130.0, 475, 176))

    parent.addChild(result.rootNode)

    let r = result
    let chips_parent = r.rootNode.findNode("chips_placeholder")
    let bucks_parent = r.rootNode.findNode("bucks_placeholder")

    result.rootNode.findNode("income_chips").component(Text).text = "0"
    result.rootNode.findNode("chips_prog").component(ProgressBar).progress = 0
    result.rootNode.findNode("income_bucks").component(Text).text = "0"
    result.rootNode.findNode("bucks_prog").component(ProgressBar).progress = 0
    result.rootNode.findNode("collect_shape").alpha = 1.0


    result.button.onAction do():
        if not r.enabled():
            return

        let u = currentUser()
        let pc = u.chips
        let pb = u.bucks

        let scene = r.rootNode.sceneView.GameScene
        scene.soundManager.sendEvent("COMMON_GUI_CLICK")
        if not scene.isNil:
            var gui_parent = scene.rootNode.findNode("GUI")
            if gui_parent.isNil:
                gui_parent = scene.rootNode.findNode("gui_parent")

            if r.avaChips > 0:
                scene.chipsAnim(chips_parent, scene.rootNode.findNode("money_panel").findNode("chips_placeholder"), gui_parent, 5, u.chips, u.chips + r.avaChips)

            if r.avaBucks > 0:
                scene.bucksAnim(bucks_parent, scene.rootNode.findNode("money_panel").findNode("bucks_placeholder"), gui_parent, min(r.avaBucks, 5), u.bucks, u.bucks + r.avaBucks)

        sharedServer().collectResources("all") do(jn: JsonNode):
            if "wallet" in jn:
                u.updateWallet(jn["wallet"])

                var cp = (r.chipsProg * 100.0).int
                var cb = (r.bucksProg * 100.0).int

                sharedAnalytics().resources_collected(u.chips - pc, u.chips, u.bucks - pb, u.bucks, r.chipsProg, r.bucksProg)

    result.update()

    result.rootNode.sceneView.GameScene.notificationCenter.addObserver("CollectConfigEv", r) do(args: Variant):
        r.update()
