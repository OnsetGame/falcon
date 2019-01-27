import json
import rod.rod_types
import rod.node
import rod.viewport
import rod.component

import rod / component / [ text_component, ui_component, vector_shape]

import nimx.types
import nimx.button
import nimx.matrixes
import nimx.animation

import gui_module
import gui_pack
import gui_module_types

import nimx.notification_center

import utils / [ helpers, icon_component ]
import shared / [ user, localization_manager ]
import shared.director
import shared.window.button_component

type GMoneyPanel* = ref object of GUIModule
    buttonChips*: ButtonComponent
    buttonBucks*: ButtonComponent
    buttonEnergy*: ButtonComponent
    chipsVal*: Node
    chipsText: Text
    mChips: int64
    mParts: int64
    mBucks: int64

proc `chips=`*(mp: GMoneyPanel, val: int64)
proc `bucks=`*(mp: GMoneyPanel, val: int64)
proc `parts=`*(mp: GMoneyPanel, val: int64)

proc chips*(mp: GMoneyPanel): int64 = mp.mChips
proc parts*(mp: GMoneyPanel): int64 = mp.mParts
proc bucks*(mp: GMoneyPanel): int64 = mp.mBucks

proc createMoneyPanel*(parent: Node): GMoneyPanel =
    result.new()

    var abTest = currentUser().getABOrDefault("top_panel_variant", "01")
    if abTest notin @["01", "02", "03"]:
        abTest = "01"

    result.rootNode = newNodeWithResource("common/gui/ui2_0/money_panel_" & abTest)
    result.rootNode.name = "money_panel" # for AB testing
    parent.addChild(result.rootNode)
    result.moduleType = mtMoneyPanel
    result.chipsVal = result.rootNode.findNode("chips_val")
    result.chipsText = result.chipsVal.component(Text)

    let btnFrame = newRect(10,10,80,80)
    var chipsPressAnim: Animation = result.rootNode.animationNamed("chips_press")

    var bucksPressAnim: Animation = result.rootNode.animationNamed("bucks_press")
    let bucks_back = result.rootNode.findNode("bucks_back").getComponent(VectorShape)
    let bucksSize = newSize(bucks_back.size.width, bucks_back.size.height)
    result.buttonChips = result.rootNode.findNode("chips_add").createButtonComponent(newRect(newPoint(-280, -8), bucksSize))
    result.buttonBucks = result.rootNode.findNode("bucks_add").createButtonComponent(newRect(newPoint(-280, -8), bucksSize))

    let energy = result.rootNode.findNode("energy_back")
    let energyComp = energy.getComponent(VectorShape)
    let energySize = newSize(energyComp.size.width, energyComp.size.height)
    result.buttonEnergy = energy.createButtonComponent(newRect(newPoint(-energySize.width/2.0, -energySize.height/2.0), energySize))

    discard result.rootNode.findNode("chips_placeholder").addChipsIcons()
    discard result.rootNode.findNode("bucks_placeholder").addBucksIcons()
    discard result.rootNode.findNode("energy_placeholder").addEnergyIcons()
    let bucksHolde = result.rootNode.findNode("bucks_placeholder")

    # for AB testing
    let chipsBttnNode = result.rootNode.findNode("chips_add")
    let bucksBttnNode = result.rootNode.findNode("bucks_add")
    let chipsBuyText = result.rootNode.findNode("chips_add").findNode("buy")
    let bucksBuyText = result.rootNode.findNode("bucks_add").findNode("buy")
    if not chipsBuyText.isNil: chipsBuyText.getComponent(Text).text = localizedString("SE_BUY")
    if not bucksBuyText.isNil: bucksBuyText.getComponent(Text).text = localizedString("SE_BUY")

    let r = result
    sharedNotificationCenter().addObserver(EVENT_CURRENCY_UPDATED, r.rootNode.sceneView, proc(v: Variant)=
        let user = v.get(User)
        r.chips = user.chips
        r.parts = user.parts
        r.bucks = user.bucks
        )
    result.chipsText.text = "0"

proc onRemoved*(mp: GMoneyPanel)=
    sharedNotificationCenter().removeObserver(EVENT_CURRENCY_UPDATED, mp.rootNode.sceneView)

proc setBalance*(mp: GMoneyPanel, start, to: int64, withAnim: bool = true, duration: float = 1.0) =
    if mp.rootNode.sceneView().isNil: return
    mp.chips = to
    if withAnim:
        mp.rootNode.sceneView().startNumbersAnim(max(start, mp.chips), to, duration, mp.chipsText)
    else:
        mp.chipsText.text = formatThousands(to)

proc getBalance*(mp: GMoneyPanel): int64 =
    result = parseThousands(mp.chipsText.text)

proc `chips=`*(mp: GMoneyPanel, val: int64) =
    mp.chipsText.text = formatThousands(val)
    mp.mChips = val

proc `bucks=`*(mp: GMoneyPanel, val: int64) =
    let node = mp.rootNode.findNode("bucks_val")
    node.component(Text).text = formatThousands(val)
    mp.mBucks = val

proc `parts=`*(mp: GMoneyPanel, val: int64) =
    let node = mp.rootNode.findNode("energy_val")
    node.component(Text).text = formatThousands(val)
    mp.mParts = val


