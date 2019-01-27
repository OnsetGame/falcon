import nimx / [ types, matrixes ]
import rod / [ node, viewport ]

import core.slot.base_slot_machine_view
import slots.eiffel.eiffel_slot_view
import slots.eiffel.eiffel_bonus_game_view

import test_utils

proc bonusView(): EiffelBonusGameView =
    return bonusGameView()

proc checkBonusLoaded*(): bool =
    not bonusView().isNil and bonusView().isWelcomeScreenActive

proc getClocheButton*(indx: int): Point =
    let dishName = "Cloche" & $indx & "$AUX"
    if not bonusView().rootNode.findNode(dishName).isNil():
        let wp = bonusView().rootNode.findNode(dishName).localToWorld(newVector3(10, 10))
        let sp = slotView.worldToScreenPoint(wp)
        newPoint(sp.x, sp.y)
    else:
        newPoint(0.0, 0.0)

proc findEiffelButton(name: string):Point =
    if bonusView().isNil:
        let wp = slotView.rootNode.findNode(name).localToWorld(newVector3(10, 10, 0))
        let sp = slotView.worldToScreenPoint(wp)
        newPoint(sp.x, sp.y)
    else:
        let wp = bonusView().rootNode.findNode(name).localToWorld(newVector3(10, 10, 0))
        let sp = slotView.worldToScreenPoint(wp)
        newPoint(sp.x, sp.y)

proc getStartButton*(): Point =
    findEiffelButton("start")

proc waitEiffelPaytableClosed(): bool = not nodeExists("Spot_right")
proc waitResultScreen():bool = nodeExists("Results_free_and_bonus")
proc waitPaytable(): bool = nodeExists("Spot_right") and slotView.rootNode.findNode("Spot_right").scale == newVector3(1.0, 1.0, 1.0)
proc waitSpecialWin(): bool = nodeExists("specialWin")

proc removeResultScreen() =
    slotView.removeWinAnimationWindow(true)

proc clickPaytableCloseBtn(): Point =
    findEiffelButton("Rope_flash.png$2")

uiTest eiffelTest:
    waitUntil(mapLoaded(), waitUntilSceneLoaded)
    startSlot(dreamTowerSlot)

    waitUntil(slotLoaded(), waitUntilSceneLoaded)
    waitUntil(nodeExists("TOWER") and (not slotView.soundManager.isNil))
    ## regular spin
    pressButton(getSpinButton())
    waitUntil(slotView.actionButtonState == SpinButtonState.Spin, waitUntilSpinState)

    ## bonus spin
    pressButton(getSpinButton())
    waitUntil(checkBonusLoaded())
    pressButton(getStartButton())
    pressButton(getClocheButton(0))
    pressButton(getClocheButton(1))
    pressButton(getClocheButton(2))
    pressButton(getClocheButton(3))
    pressButton(getClocheButton(4))
    pressButton(getClocheButton(5))
    pressButton(getClocheButton(6))
    pressButton(getClocheButton(7))
    pressButton(getClocheButton(8))
    waitUntil(slotLoaded(), waitUntilSceneLoaded)
    # skip bonus outro
    waitUntil(waitResultScreen())

    discard
    removeResultScreen()
    waitUntil(slotView.actionButtonState == SpinButtonState.Spin, waitUntilSpinState)

    ## spin freespin
    pressButton(getSpinButton())

    waitUntil(waitResultScreen())
    discard
    discard
    removeResultScreen()
    # sceneView.removeWinAnimationWindow(true)
    waitUntil(slotView.actionButtonState == SpinButtonState.Spin, waitUntilSpinState)

    pressButton(getDropDownMenu())
    waitUntil(findPaytableButton().enabled == true, 15)
    pressButton(getPaytableBtn())
    discard
    clickPaytableBtn(true)
    discard
    clickPaytableBtn(true)
    discard
    clickPaytableBtn(true)
    discard
    clickPaytableBtn(true)
    discard
    clickPaytableBtn(false)
    discard
    clickPaytableBtn(false)
    discard
    clickPaytableBtn(false)
    discard
    pressButton(findButton("new_close.png"))
    waitUntil(paytableNotClosed())
    discard
    # pressButton(getMapButton())
    loadMap()

registerTest(eiffelTest)
