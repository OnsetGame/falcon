import strutils, logging

import nimx / [ autotest, app, window, view, button, mini_profiler, matrixes, abstract_window ]

import map.tiledmap_view
import slots.slot_machine_registry
import rod / [ node, viewport ]
import core.slot.base_slot_machine_view
import shared.director
import shared / window / [button_component, window_manager]
export button_component

export autotest

const waitUntilSpinState* = 150
const waitUntilSceneLoaded* = 250

proc mainWindow*(): Window = mainApplication().keyWindow()

proc getCurrentSlotView(): BaseMachineView =
    for s in mainWindow().subviews:
        if s of BaseMachineView:
            result = BaseMachineView(s)
            break

template slotView*: BaseMachineView = getCurrentSlotView()

proc nodeExists*(name: string): bool =
    not slotView.rootNode.findNode(name).isNil

proc getSpinButton*(): Point =
    let spn = slotView.slotGUI.spinButtonModule.rootNode.localToWorld(newVector3(10, 10))
    let sp = slotView.worldToScreenPoint(spn)
    result = newPoint(sp.x, sp.y)
    info "getSpinButton: ", result

proc getSlotButton*(btn_title: string):Point =
    let mv = TiledMapView(mainWindow().subviews[0])
    let btn = mv.findButtonWithTitle(btn_title)
    let ori = btn.frame.origin
    let siz = btn.bounds.size
    result = newPoint(ori.x + siz.width * 0.5, ori.y + siz.height * 0.5)
    info "getSlotButton: ", btn_title, " pos: ", result

proc startSlot*(slotMachineName: BuildingId) =
    discard startSlotMachineGame(slotMachineName, smkDefault)

proc loadMap*() =
    directorMoveToMap()

proc slotLoaded*(): bool = not slotView.isNil and not slotView.hidden

var numberOfImages = 0
proc checkResourceLeaks*() =
    let p = sharedProfiler()
    if p.enabled:
        let imagesStr = p.valueForKey("Images")
        let ram = getOccupiedMem() div (1024 * 1024)
        let images = if imagesStr.len == 0: 0 else: imagesStr.parseInt()
        info "Ram consumed: ", ram, ", Images allocated: ", images
        if numberOfImages > 0:
            let msg = "Looks like a leak " & $images & " != " & $numberOfImages
            if images != numberOfImages:
                info msg
            doAssert(images == numberOfImages, msg)

        # The following value is kinda hand-picked. Note that some resources
        # (like fonts) may never be deallocated. If you change this value,
        # verify that the test passes by running it at least 10 times in native,
        # and 10 times in emscripten mode since its not very deterministic.
        const maxRamOnTheMap = 300
        doAssert(ram < maxRamOnTheMap, "Looks like a leak")
        numberOfImages = images

proc mapLoaded*(): bool =
    let mw = mainWindow()
    if mw.subviews.len() > 0:
        if mw.subviews[0] of TiledMapView:
            let mv = GameScene(mw.subviews[0])
            result = not mv.rootNode.findNode("MAP").isNil and not mv.hidden
            if result:
                if gcRequested:
                    warn "GC NOT DONE YET"
                    return false

                checkResourceLeaks()
        else:
            result = false
    else:
        result = false

proc paytableNotClosed*(): bool =
    not sharedWindowManager().currentWindow.isNil

proc findButton*(name: string): Point =
    let wp = slotView.rootNode.findNode(name).localToWorld(newVector3(10, 10, 0))
    let sp = slotView.worldToScreenPoint(wp)
    newPoint(sp.x, sp.y)

proc pressButton*(buttonPoint: Point) =
    sendMouseDownEvent(mainWindow(), buttonPoint)
    sendMouseUpEvent(mainWindow(), buttonPoint)

proc clickScreen*() =
    pressButton(newPoint(300, 300))

proc clickPaytableBtn*(isNext: bool) =
    var arrow = findButton("ltp_left_2.png")

    if isNext:
        arrow = findButton("ltp_right_2.png")

    pressButton(arrow)

proc getDropDownMenu*(): Point =
    let wp = slotView.slotGUI.menuButton.rootNode.localToWorld(newVector3(10, 10))
    let sp = slotView.worldToScreenPoint(wp)
    newPoint(sp.x, sp.y)

proc findPaytableButton*(): ButtonComponent =
    slotView.slotGUI.menuButton.rootNode.findNode("paytable_button_in_dropmenu").parent.parent.parent.parent.getComponent(ButtonComponent)

proc getPaytableBtn*(): Point =
    let wp = slotView.slotGUI.menuButton.rootNode.findNode("paytable_button_in_dropmenu").localToWorld(newVector3(10, 10))
    let sp = slotView.worldToScreenPoint(wp)
    newPoint(sp.x, sp.y)
