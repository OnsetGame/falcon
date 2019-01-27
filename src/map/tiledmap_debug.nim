import nimx.types
import nimx.matrixes
import nimx.text_field
import nimx.font
import nimx.panel_view

import rod.node
import rod.rod_types
import rod.component
import rod.component.ui_component

proc resetDebugView*(n: Node)=
    n.enabled = false

proc updateDebugView*(n: Node, debugInfo: seq[tuple[layerName: string, x: int, y: int, tileid: int, index: int]], position: Vector3)=
    let dl = debugInfo.len
    const textH = 20.0
    const layerH = textH * 3.5

    var dioffset = 0.0
    var debugView = newView(newRect(0.0, 0.0, 300.0, dl.float * layerH + textH))
    debugView.backgroundColor = newColor(1.0, 1.0, 1.0, 1.0)
    let dfont = systemFontOfSize(20.0)

    var wpf = newLabel(newRect(0.0, 5.0, 300.0, textH))
    wpf.font = dfont
    wpf.text = "pos x: " & $(position.x.int) & " y: " & $(position.y.int)
    debugView.addSubview(wpf)

    dioffset += textH + 10.0

    for di in debugInfo:
        var yOff = 0.0

        var nf = newLabel(newRect(0.0, yOff, 300.0, textH))
        nf.font = dfont
        nf.text = di.layerName
        yOff += textH

        var xyf = newLabel(newRect(0.0, yOff, 200.0, textH))
        xyf.font = dfont
        xyf.text = "X: " & $di.x & " Y: " & $di.y

        var tf = newLabel(newRect(130.0, yOff, 95.0, textH))
        tf.text = "tile: " & $di.tileid
        tf.font = dfont

        var ti = newLabel(newRect(210.0, yOff, 95.0, textH))
        ti.text = "i: " & $di.index
        ti.font = dfont
        yOff += textH

        var debView = newView(newRect(0.0, dioffset, 300.0, layerH))
        debugView.addSubview(debView)

        debView.addSubview(nf)
        debView.addSubview(xyf)
        debView.addSubview(ti)
        debView.addSubview(tf)

        dioffset += layerH
    n.position = position + newVector3(20.0, 20.0)
    n.component(UIComponent).view = debugView
    n.enabled = true
