import node_proxy.proxy
import nimx / [ animation, types, matrixes ]
import utils / [ helpers, sound_manager, sound ]
import core.slot.sound_map
import rod / [ node, component ]
import rod.component.particle_system
import shared.game_scene
import shared.window.button_component
import core.slot / [ slot_types, base_slot_machine_view ]
import candy2_slot_view, candy2_top, candy2_types, candy2_win_numbers, candy2_boy
import random, json, sequtils, tables, strformat
import shared / gui / [ win_panel_module, gui_module ]

const BOX_COUNT = 12
const WIN_PANEL_OFFSET_X = 100.0

type Candy2Bonus* = ref object
    view: Candy2SlotView
    moveTo: Animation
    closedBoxes: seq[Box]
    idleAnim: Animation
    elements: seq[Node]
    currBox: int
    onBonusComplete: proc()
    field: seq[float]
    currWin: int64
    remainingBoxOpening: bool

proc moveToBonusAnim(v: Candy2SlotView): Animation =
    result = newCompositAnimation(true, @[v.interior.move, v.background.move, v.top.move, v.bonus.move ])
    result.numberOfLoops = 1

proc moveFromBonusAnim*(v: Candy2SlotView): Animation =
    result = newCompositAnimation(true, @[v.interior.move, v.background.move, v.top.moveFrom, v.bonus.moveFrom])
    result.loopPattern = lpEndToStart
    result.numberOfLoops = 1

proc setStartWin(b: Candy2Bonus): int64 =
    let BONUS = 2
    let bc = b.view.countSymbols(BONUS)

    for rel in b.view.pd.bonusRelation:
        if rel.triggerCount == bc:
            return rel.bonusCount * b.view.totalBet

proc createElement(b: Candy2Bonus, value: float): Node =
    const ELEMENTS = @[6, 5, 4, 3]

    for i in 0..b.view.pd.bonusPossibleMultipliers.high:
        if value == b.view.pd.bonusPossibleMultipliers[i]:
            return newNodeWithResource("slots/candy2_slot/elements/precomps/elem_" & $ELEMENTS[i])

proc startBoxIdle(b: Candy2Bonus): Animation =
    result = newAnimation()

    result.loopDuration = 1
    result.numberOfLoops = -1
    result.addLoopProgressHandler(1.0, false) do():
        let r = rand(b.closedBoxes)
        b.view.bonus.node.addAnimation(r.node.animationNamed("idle"))
    b.view.bonus.node.addAnimation(result)

proc setBoxesViews(v: Candy2SlotView, b: Candy2Bonus) =
    for box in v.boxes:
        box.currView = rand(box.views)

        for view in box.views:
            view.alpha = 0
        box.currView.alpha = 1.0

proc putBoxesBack*(v: Candy2SlotView) =
    const OFFSET = 1877.0

    v.bonus.levelsBox.reattach(v.bonus.boxesDown)
    v.top.levelsBox.reattach(v.top.boxesUpNode)
    v.bonus.levelsBox.positionX = OFFSET
    v.top.levelsBox.positionX = OFFSET
    for box in v.boxes:
        box.elementParent.removeAllChildren()

proc finishGame(v: Candy2SlotView, b: Candy2Bonus) =
    let sg = v.slotGUI
    let anim = v.boyFromBonus()

    sg.winPanelModule.setNewWin(0)
    sg.winPanelModule.setVisible(false)
    sg.winPanelModule.rootNode.positionX = sg.winPanelModule.rootNode.positionX - WIN_PANEL_OFFSET_X
    b.onBonusComplete()
    v.bonusReady = false
    anim.onComplete do():
        v.boyController.node.positionX = v.startBoyPosX
        v.boyController.node.alpha = 0

        v.bonus.levelsBox.reattach(v.bonus.transitionNode)
        v.top.levelsBox.reattach(v.bonus.transitionNode)

proc disableBoxes(v: Candy2SlotView, b: Candy2Bonus) =
    for box in v.boxes:
        box.node.removeComponent("ButtonComponent")

proc openRemainingBoxes(b: Candy2Bonus) =
    if b.remainingBoxOpening:
        return
    b.remainingBoxOpening = true
    var multipliers = {
        3.0: 2,
        2.0: 3,
        1.5: 3,
        1.2: 3
    }.toTable()
    let symbols = {
        3.0: &"{GENERAL_PREFIX}elements/precomps/elem_3",
        2.0: &"{GENERAL_PREFIX}elements/precomps/elem_4",
        1.5: &"{GENERAL_PREFIX}elements/precomps/elem_5",
        1.2: &"{GENERAL_PREFIX}elements/precomps/elem_6"
    }.toTable()
    var multKeys = @[3.0, 2.0, 1.5, 1.2]

    for v in b.field:
        multipliers[v].dec()
        if multipliers[v] == 0:
            multKeys.keepIf(proc(x: float): bool = x != v)

    # 4 closed boxes must be empty
    for i in 0..3:
        closureScope:
            let bx = rand(b.closedBoxes)
            b.closedBoxes.keepIf(proc(x: Box): bool = x != bx)
            bx.elementParent.addAnimation(bx.play)
            bx.play.addLoopProgressHandler(0.5, true) do():
                bx.currView.alpha = 0
                bx.elementParent.playPotentialOops()

    for i, box in b.closedBoxes:
        closureScope:
            let key = rand(multKeys)
            let bx = box

            multipliers[key].dec()
            if multipliers[key] == 0:
                multKeys.keepIf(proc(x: float): bool = x != key)

            bx.elementParent.addAnimation(bx.play)
            bx.play.addLoopProgressHandler(0.5, true) do():
                let elem = newNodeWithResource(symbols[key])
                bx.elementParent.addChild(elem)
                elem.alpha = 0.7
                bx.currView.alpha = 0
                elem.playBonusPotentialWinNumber(key)

proc onBoxesClick(v: Candy2SlotView, b: Candy2Bonus) =
    for box in v.boxes:
        closureScope:
            let bx = box

            bx.button.onAction do():
                if not v.bonusBusy:
                    v.bonusBusy = true
                    if b.currBox < b.elements.len:
                        v.bonus.node.addAnimation(bx.play)
                        bx.button.enabled = false
                        v.sound.play("BONUS_UNWRAP_" & $rand(1 .. 3))

                        bx.play.addLoopProgressHandler(0.5, true) do():
                            let element = b.elements[b.currBox]
                            let anim = element.animationNamed("win")
                            let particle = newLocalizedNodeWithResource("slots/candy2_slot/particles/root_new_confetti.json")

                            b.currWin = (b.currWin.float * b.field[b.currBox]).int64
                            bx.currView.alpha = 0
                            bx.elementParent.addChild(b.elements[b.currBox])
                            element.playBonusWinNumber(b.field[b.currBox])
                            element.reattach(v.rootNode)
                            element.addChild(particle)
                            particle.position = newVector3(300, 380)

                            for child in particle.children:
                                child.component(ParticleSystem).start()

                            v.boyWin()
                            v.bonus.node.addAnimation(anim)
                            anim.onComplete do():
                                v.sound.play("BONUS_JAR_" & $rand(1 .. 3))
                                v.slotGUI.winPanelModule.setNewWin(b.currWin)
                                element.reattach(bx.elementParent)
                            b.currBox.inc()
                            v.bonusBusy = false
                        for cb in b.closedBoxes:
                            if cb == bx:
                                keepIf(b.closedBoxes, proc(x: Box): bool = x != bx)
                                break
                    else:
                        v.disableBoxes(b)
                        v.bonus.node.addAnimation(bx.play)
                        bx.play.addLoopProgressHandler(0.5, true) do():
                            let boyAnim = v.boyNowin()
                            bx.currView.alpha = 0
                            bx.elementParent.playOops()
                            b.idleAnim.cancel()
                            b.openRemainingBoxes()
                            boyAnim.onComplete do():
                                let delay = newAnimation()
                                delay.numberOfLoops = 1
                                delay.loopDuration = 3
                                v.bonus.node.addAnimation(delay)
                                delay.onComplete do():
                                    v.finishGame(b)

proc createBonus*(): BonusProxy =
    result =  new(BonusProxy, newNodeWithResource("slots/candy2_slot/bonus/precomps/bonus"))

proc startBonusGame*(v: Candy2SlotView, data: JsonNode,  cb: proc()): Candy2Bonus =
    let sg = v.slotGUI

    result.new()
    result.view = v
    result.elements = @[]
    result.field = @[]
    v.boxes = @[]

    result.moveTo = v.moveToBonusAnim()
    result.moveTo.loopPattern = lpStartToEnd

    v.bonus.node.addAnimation(result.moveTo)

    v.bonusBusy = false
    for item in data["field"].items:
        let fe = item.getFloat() / 10.0
        let elem = result.createElement(fe)

        result.field.add(fe)
        result.elements.add(elem)

    for bu in v.top.boxesUp:
        let box = new(Box, bu)
        v.boxes.add(box)

    for i in 5..BOX_COUNT:
        let box = new(Box, v.bonus.node.findNode("box" & $i))
        v.boxes.add(box)

    result.closedBoxes = v.boxes
    v.setBoxesViews(result)

    let res = result
    result.moveTo.onComplete do():
        v.playBackgroundMusic(MusicType.Bonus)
        res.currWin = res.setStartWin().int64

        for box in v.boxes:
            box.button = box.node.createButtonComponent(nil, newRect(182.0, 162.0, 240.0, 240.0))

        sg.winPanelModule.setVisible(true)
        sg.winPanelModule.setNewWin(res.currWin)
        sg.winPanelModule.rootNode.positionX = sg.winPanelModule.rootNode.positionX + WIN_PANEL_OFFSET_X
        v.onBoxesClick(res)
        res.idleAnim = res.startBoxIdle()
        res.onBonusComplete = cb
        res.moveTo.removeHandlers()
        v.bonusReady = true

