import nimx.scroll_view
import nimx.text_field
import nimx.keyboard
import nimx.view_event_handling
import nimx.window_event_handling
import nimx.popup_button
import nimx.view
import nimx.animation
import nimx.window
import nimx.font
import nimx.button

import nimx.panel_view
import nimx.outline_view
import nimx.property_visitor
import rod.rod_types
import rod.node
import rod.viewport

import algorithm
import strutils
import sequtils
import tables
import math

import utils.helpers

type EditableAnimation* = ref object of Animation
    startProps*: array[10, float32]
    destProps*: array[10, float32]

proc newEditableAnimation*(): EditableAnimation =
    result.new()

proc newEditableAnimation*(startProps, destProps: array[10, float32]): EditableAnimation =
    result = newEditableAnimation()
    result.startProps = startProps
    result.destProps = destProps

type NumericTextField = ref object of TextField

proc newNumericTextField(r: Rect): NumericTextField =
    result.new()
    result.init(r)

method onScroll(v: NumericTextField, e: var Event): bool =
    result = true
    var action = false
    try:
        var val = parseFloat(v.text).int
        if VirtualKey.LeftControl in e.modifiers:
            val += e.offset.y.int * 10.int
        elif VirtualKey.LeftShift in e.modifiers:
            val += e.offset.y.int * 100.int
        else:
            val += e.offset.y.int
        v.text = $val
        action = true
        v.setNeedsDisplay()
    except:
        discard
    if action:
        v.sendAction()

proc animView*(v: SceneView) =

    let animView = PanelView.new(newRect(0, 0, 300, 500))
    animView.collapsible = true

    v.addSubview(animView)

    let title = newLabel(newRect(22, 6, 108, 15))
    title.textColor = whiteColor()
    title.text = "Anim"
    animView.addSubview(title)

    var labelOffsetX = 5.0
    var textFieldY = 6.0+40.0
    var textFieldOffsetX = 60.0
    var textFieldOffsetY = 0.0

    let lbNode = newLabel(newRect(labelOffsetX, textFieldY+textFieldOffsetY, 40.0, 20.0))
    lbNode.text = "node"
    lbNode.textColor = whiteColor()
    animView.addSubview(lbNode)

    var prevNode: Node
    var inspectedNode: Node

    var currAnims = initTable[string, seq[View]]()

    template addView(v: seq[View], trgt: View) =
        v.add(trgt)
        animView.addSubview(trgt)
        trgt.setNeedsDisplay()

    let nodeTf = newTextField(newRect(textFieldOffsetX, textFieldY+textFieldOffsetY, 120.0, 20.0))
    nodeTf.autoresizingMask = { afFlexibleWidth, afFlexibleMaxY }
    nodeTf.text = "root"
    nodeTf.onAction do():
        inspectedNode = v.rootNode.findNode(nodeTf.text)

        if not inspectedNode.isNil and not inspectedNode.animations.isNil:
            for name, a in inspectedNode.animations:
                if not currAnims.hasKey(name):
                    var views: seq[View]

                    textFieldY += 20.0
                    textFieldOffsetY += 5.0

                    #------------------------------------------

                    let lbAnim = newLabel(newRect(labelOffsetX, textFieldY+textFieldOffsetY, 40.0, 20.0))
                    lbAnim.text = if name.len > 0: name else: "noname"
                    lbAnim.textColor = whiteColor()
                    views.addView(lbAnim)

                    let playButton = Button.new(newRect(textFieldOffsetX, textFieldY+textFieldOffsetY, 120.0, 20.0))
                    playButton.title = "play"
                    playButton.onAction do():
                        v.addAnimation(a)
                    views.addView(playButton)

                    textFieldY += 20.0
                    textFieldOffsetY += 5.0

                    #------------------------------------------

                    let lbAnimDuration = newLabel(newRect(labelOffsetX, textFieldY+textFieldOffsetY, 40.0, 20.0))
                    lbAnimDuration.text = "duration:"
                    lbAnimDuration.textColor = whiteColor()
                    views.addView(lbAnimDuration)

                    var propTextViewDuration = newNumericTextField(newRect(textFieldOffsetX, textFieldY+textFieldOffsetY, 120.0, 20.0))
                    propTextViewDuration.text = formatFloat(a.loopDuration, precision = 6)
                    propTextViewDuration.textColor = blackColor()
                    propTextViewDuration.onAction do():
                        try: a.loopDuration = parseFloat(propTextViewDuration.text).float32
                        except: discard
                    views.addView(propTextViewDuration)

                    textFieldY += 20.0
                    textFieldOffsetY += 5.0

                    #------------------------------------------

                    let lbAnimLoops = newLabel(newRect(labelOffsetX, textFieldY+textFieldOffsetY, 40.0, 20.0))
                    lbAnimLoops.text = "loops:"
                    lbAnimLoops.textColor = whiteColor()
                    views.addView(lbAnimLoops)

                    var propTextViewLoops = newNumericTextField(newRect(textFieldOffsetX, textFieldY+textFieldOffsetY, 120.0, 20.0))
                    propTextViewLoops.text = $a.numberOfLoops
                    propTextViewLoops.textColor = blackColor()
                    propTextViewLoops.onAction do():
                        try: a.numberOfLoops = parseInt(propTextViewLoops.text)
                        except: discard
                    views.addView(propTextViewLoops)

                    textFieldY += 20.0
                    textFieldOffsetY += 5.0

                    #------------------------------------------

                    var val: EnumValue
                    val.possibleValues = initTable[string, int]()
                    for i in low(type(LoopPattern)) .. high(type(LoopPattern)):
                        val.possibleValues[$i] = ord(i)

                    val.curValue = a.loopPattern.int
                    var items = newSeq[string]()
                    for k, v in val.possibleValues:
                        items.add(k)

                    sort(items, system.cmp)
                    var enumChooser = newPopupButton(v, newPoint(textFieldOffsetX, textFieldY+textFieldOffsetY), newSize(208, 20.0), items, val.curValue)
                    enumChooser.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
                    enumChooser.onAction do():
                        a.loopPattern = val.possibleValues[enumChooser.selectedItem()].LoopPattern
                    views.addView(enumChooser)

                    textFieldY += 20.0
                    textFieldOffsetY += 5.0

                    #------------------------------------------

                    for i in 0..<a.EditableAnimation.startProps.len:
                        closureScope:
                            let index = i

                            var propTextViewStart = newNumericTextField(newRect(textFieldOffsetX, textFieldY+textFieldOffsetY, 100.0, 20.0))
                            propTextViewStart.text = formatFloat(a.EditableAnimation.startProps[index], precision = 6)
                            propTextViewStart.textColor = blackColor()
                            propTextViewStart.onAction do():
                                try: a.EditableAnimation.startProps[index] = parseFloat(propTextViewStart.text).float32
                                except: discard
                            views.addView(propTextViewStart)

                            var propTextViewDest = newNumericTextField(newRect(textFieldOffsetX+105.0, textFieldY+textFieldOffsetY, 100.0, 20.0))
                            propTextViewDest.text = formatFloat(a.EditableAnimation.destProps[index], precision = 6)
                            propTextViewDest.textColor = blackColor()
                            propTextViewDest.onAction do():
                                try: a.EditableAnimation.destProps[index] = parseFloat(propTextViewDest.text).float32
                                except: discard
                            views.addView(propTextViewDest)

                            textFieldY += 20.0
                            textFieldOffsetY += 5.0

                    #------------------------------------------

                    currAnims[name] = views

        if inspectedNode != prevNode:
            echo "selection changed"
            for k, v in currAnims:
                for view in v:
                    view.removeFromSuperview()
                currAnims.del(k)
            labelOffsetX = 5.0
            textFieldY = 6.0+40.0
            textFieldOffsetX = 60.0
            textFieldOffsetY = 0.0

        prevNode = inspectedNode

        v.setNeedsDisplay()

    animView.addSubview(nodeTf)
    textFieldY += 20.0
    textFieldOffsetY+= 5.0

    nodeTf.sendAction()
