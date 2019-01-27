import random

import nimx / [types, animation, matrixes]
import core/ notification_center
import core / helpers / hint_helper

import rod / [ rod_types, node ]
import rod / component / [ text_component ]
import utils / [ icon_component, helpers, sound_manager ]

import shared / [director, game_scene]
import shared / window / [ button_component ]
import core / zone
import quest / quests


type ButtonFeature* = ref object of RootObj
    rootNode*: Node

    lockInstance*: Hint
    hintInstance*: HintWithTitle

    bttn*: ButtonComponent
    enabled: bool
    hinted: bool

    composition*: string
    icon*: string
    title*: string
    zone*: string
    rect: Rect

    source*: string
    onAction*: proc(enabled: bool)
    onHint*: proc(text: string)
    onEnable*: proc()
    onDisable*: proc()


method enable*(bf: ButtonFeature) {.base.}
proc disable*(bf: ButtonFeature)


proc playClick*(bf: ButtonFeature) =
    bf.rootNode.sceneView.GameScene.soundManager.sendEvent("COMMON_GUI_CLICK")


method onInit*(bf: ButtonFeature) {.base.} = discard
method onCreate*(bf: ButtonFeature) {.base.} =
    let zone = findZone(bf.zone)

    if zone.isNil:
        return

    if not zone.isActive():
        bf.disable()

        bf.rootNode.addObserver("QUEST_COMPLETED", bf) do(arg: Variant):
            if zone.isActive():
                bf.rootNode.removeObserver("QUEST_COMPLETED", bf)
                bf.enable()
    else:
        bf.enable()

proc addButton(bf: ButtonFeature) =
    if not bf.bttn.isNil:
        bf.rootNode.removeComponent(bf.bttn)

    let animation = if bf.enabled: bf.rootNode.animationNamed("press") else: nil
    bf.bttn = bf.rootNode.createButtonComponent(animation, bf.rect)
    bf.bttn.onAction do():
        if not bf.onAction.isNil:
            bf.onAction(bf.enabled)

proc setNodes(bf: ButtonFeature) =
    let iconNode = bf.rootNode.findNode("icon_placeholder")
    if not iconNode.isNil:
        let comp = iconNode.component(IconComponent)
        comp.name = bf.icon

    let titleNode = bf.rootNode.findNode("title")
    if not titleNode.isNil:
        let comp = titleNode.component(Text)
        comp.text = bf.title

    let lockNode = bf.rootNode.findNode("lock_comp")
    if not lockNode.isNil:
        bf.lockInstance = newHint(lockNode)
    bf.enabled = true
    bf.addButton()

    let hintNode = bf.rootNode.findNode("alert_comp")
    if not hintNode.isNil:
        bf.hintInstance = newHintWithTitle(hintNode)


proc new*(T: typedesc[ButtonFeature], parent: Node): T  =
    result = T.new()

    result.composition = "common/gui/ui2_0/button_map"
    result.rect = newRect(0, 26, 173, 196)

    result.onInit()

    let rootNode = newNodeWithResource(result.composition)
    parent.addChild(rootNode)
    result.rootNode = rootNode
    result.setNodes()

    result.onCreate()


method enable*(bf: ButtonFeature) {.base.} =
    if bf.enabled:
        return
    bf.enabled = true

    if not bf.lockInstance.isNil:
        bf.lockInstance.hide() do():
            bf.addButton()
            if not bf.onEnable.isNil:
                bf.onEnable()
    else:
        bf.addButton()
        if not bf.onEnable.isNil:
            bf.onEnable()


proc disable*(bf: ButtonFeature) =
    if not bf.enabled:
        return
    bf.enabled = false

    bf.addButton()

    if not bf.lockInstance.isNil:
        bf.lockInstance.show() do():
            if not bf.onDisable.isNil:
                bf.onDisable()
    else:
        if not bf.onDisable.isNil:
            bf.onDisable()


proc setEnabledState*(bf: ButtonFeature, enabled: bool) =
    if enabled:
        bf.enable()
    else:
        bf.disable()


proc hideHintInternal*(bf: ButtonFeature, cb: proc() = nil) =
    if not bf.hinted:
        if not cb.isNil:
            cb()
        return
    bf.hinted = false

    bf.hintInstance.hide(cb)

proc hideHint*(bf: ButtonFeature, cb: proc() = nil) =
    bf.hideHintInternal() do():
        if not cb.isNil:
            cb()
        if not bf.onHint.isNil:
            bf.onHint("")

proc hint*(bf: ButtonFeature, txt: string) =
    if txt.len == 0:
        bf.hideHint()
        return

    if bf.hinted and bf.hintInstance.title.text == txt:
        return

    bf.hideHintInternal() do():
        bf.hinted = true
        bf.hintInstance.titleText = txt

        bf.hintInstance.show()

        if not bf.onHint.isNil:
            bf.onHint(txt)

proc rect*(bf: ButtonFeature): Rect =
    bf.rect

proc `rect=`*(bf: ButtonFeature, rect: Rect) =
    bf.rect = rect
    if not bf.bttn.isNil:
        bf.addButton()

proc enabled*(bf: ButtonFeature): bool =
    bf.enabled

proc hinted*(bf: ButtonFeature): bool =
    bf.hinted
