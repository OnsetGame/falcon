import
    nimx.view, nimx.context, nimx.button, nimx.animation, nimx.window,
    nimx.timer, nimx.notification_center, nimx.image,

    rod.rod_types, rod.node, rod.viewport, rod.component, rod.component.ui_component, rod.component.sprite,
    rod.component.clipping_rect_component, rod.asset_bundle,
    #
    tables, random, json, strutils, sequtils, algorithm, os,
    #
    core.net.server, shared.user, core.slot.base_slot_machine_view, shared.chips_animation, shared.cheats_view,
    #
    utils.sound, utils.sound_manager, utils.helpers, utils.pause,
    #
    shafa.slot.slot_data_types,
    shared.gui.gui_pack,
    #
    shared.gui.gui_module, shared.gui.win_panel_module, shared.gui.total_bet_panel_module, shared.gui.paytable_open_button_module,
    shared.gui.spin_button_module, shared.gui.money_panel_module

type TestSlotView* = ref object of BaseMachineView
    wheel: Node

const GENERAL_PREFIX = "slots/test_slot/"

proc getElementsForWheel(v: TestSlotView): int =
    var i = 1
    while true:
        try:
            discard imageWithResource(GENERAL_PREFIX & "element_" & $i & ".png")
            i.inc()
        except:
            break
    result = i - 1

proc fillRandomField(v: TestSlotView) =
    let maxElement = v.getElementsForWheel()

    for i in 1..15:
        let rand = rand(1..maxElement)
        let image = imageWithResource(GENERAL_PREFIX & "element_" & $rand & ".png")
        v.wheel.findNode("element_" & $i).component(Sprite).image = image
    for i in 1..5:
        for j in 1..3:
            let rand = rand(1..maxElement)
            let image = imageWithResource(GENERAL_PREFIX & "element_" & $rand & ".png")
            v.wheel.findNode("parent_" & $i).findNode("top_" & $j).component(Sprite).image = image

proc fillUniqueField(v: TestSlotView) =
    let maxElement = v.getElementsForWheel()
    var unique: seq[int] = @[]

    for i in 0..<15:
        unique.add(i)

    unique.shuffle()
    v.fillRandomField()

    for i in 0..<maxElement:
        let num = unique[i]
        let place = indexToPlace(num)
        let image = imageWithResource(GENERAL_PREFIX & "element_" & $(i + 1) & ".png")
        v.wheel.findNode("parent_" & $(place.x + 1)).findNode("element_" & $(place.x + 1 + 5 * place.y)).component(Sprite).image = image

method initAfterResourcesLoaded(v: TestSlotView) =
    procCall v.BaseMachineView.initAfterResourcesLoaded()
    v.wheel = newLocalizedNodeWithResource(GENERAL_PREFIX & "wheel.json")
    v.rootNode.addChild(v.wheel)
    v.wheel.findNode("background").component(Sprite).image = imageWithResource(GENERAL_PREFIX & "background.png")
    v.wheel.findNode("background").component(ClippingRectComponent).clippingRect = newRect(300, 120, 1500, 740)
    v.fillRandomField()

    let unique = newButton(newRect(10, 200, 100, 50))
    unique.title = "Unique field"
    unique.onAction do():
        v.fillUniqueField()
    v.addSubview(unique)

method onSpinClick*(v: TestSlotView) =
    let anim = newAnimation()
    anim.loopDuration = 0.15
    anim.numberOfLoops = 5

    anim.onAnimate = proc(p: float) =
        for i in 1..5:
            v.wheel.findNode("parent_" & $i).positionY = interpolate(0.Coord, 500.Coord, p)

method viewOnEnter*(v: TestSlotView) =
    procCall v.BaseMachineView.viewOnEnter()

method viewOnExit*(v: TestSlotView) =
    procCall v.BaseMachineView.viewOnExit()

method init*(v: TestSlotView, r: Rect) =
    procCall v.BaseMachineView.init(r)
    v.addDefaultOrthoCamera("Camera")

method clickScreen(v: TestSlotView) =
    discard v.makeFirstResponder()

method assetBundles*(v: TestSlotView): seq[AssetBundleDescriptor] =
    const ASSET_BUNDLES = [
        assetBundleDescriptor("slots/test_slot")
    ]
    result = @ASSET_BUNDLES
