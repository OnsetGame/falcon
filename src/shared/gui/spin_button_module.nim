import rod.rod_types
import rod.node
import rod.viewport
import rod.component
import rod.component.text_component
import rod.component.ui_component
import rod.component.tint

import nimx.property_visitor
import nimx.button
import nimx.matrixes
import nimx.animation
import nimx.composition
import nimx.context
import nimx.portable_gl
import nimx.types

import gui_module
import gui_module_types

import shared.localization_manager
import shared.window.button_component
import utils / helpers

type SplitTintComponent* = ref object of Component
    black*: Color
    white*: Color
    amount*: float32
    splitX*: float

var splitTint = newPostEffect("""
void split_effect(vec4 black, vec4 white, float amount, float split_x)
{
    float b = (0.2126*gl_FragColor.r + 0.7152*gl_FragColor.g + 0.0722*gl_FragColor.b); // Maybe the koeffs should be adjusted
    float a = gl_FragColor.a;
    vec4 res = mix(black, white, b);
    res.a *= a;

    gl_FragColor = mix(gl_FragColor, res, min(amount, step(split_x, gl_FragCoord.x)));
}
""", "split_effect", ["vec4", "vec4", "float", "float"])

method beforeDraw*(c: SplitTintComponent, index: int): bool =
    let fromInWorld = c.node.sceneView.worldToScreenPoint c.node.localToWorld(newVector3(c.splitX))
    var winFromPos = c.node.sceneView.convertPointToWindow(newPoint(fromInWorld.x, fromInWorld.y))
    let w = c.node.sceneView.window
    let pr = if w.isNil: 1.0 else: w.pixelRatio
    pushPostEffect(splitTint, c.black, c.white, c.amount, winFromPos.x * pr)

method afterDraw*(c: SplitTintComponent, index: int) =
    popPostEffect()

method visitProperties*(c: SplitTintComponent, p: var PropertyVisitor) =
    p.visitProperty("black", c.black)
    p.visitProperty("white", c.white)
    p.visitProperty("amount", c.amount)
    p.visitProperty("splitX", c.splitX)

registerComponent(SplitTintComponent, "Falcon")

type
    SpinButtonModule* = ref object of GUIModule
        button*: ButtonComponent
        freespinsCounter: Text
        spinText: Text
        arrowParent*: Node
        arrowsTint: array[2, Tint]
        pressAnim*: Animation
        isAutospin: bool
        isFreespin: bool
        isRespins: bool

    ArrowTint = enum
        SpinTint
        FreespinTint
        RespinTint
        AutospinTint

    ArrowColorData = tuple
        black: Vector3
        white: Vector3

const colors = [
    ( black: newColor(0.94, 0.41, 0.06, 1.0), white: newColor(1.00, 0.60, 0.00, 1.0) ), #SPIN
    ( black: newColor(0.53, 0.71, 0.22, 1.0), white: newColor(0.87, 0.93, 0.24, 1.0) ), #FREESPINS
    ( black: newColor(0.43, 0.05, 0.78, 1.0), white: newColor(0.67, 0.00, 1.00, 1.0) ), #RESPIN
    ( black: newColor(0.95, 0.60, 0.16, 1.0), white: newColor(1.00, 0.92, 0.23, 1.0) )  #AUTOSPIN
]

const holdDuration = 1.0

proc setColor(t: Tint, idx: int) =
    t.black = colors[idx].black
    t.white = colors[idx].white

proc setColor(tnt: openarray[Tint], idx: int) =
    for t in tnt: t.setColor(idx)

proc createSpinButton*(parent: Node): SpinButtonModule =
    result.new()
    result.rootNode = newLocalizedNodeWithResource("common/gui/ui2_0/spin_button.json")
    parent.addChild(result.rootNode)
    result.moduleType = mtSpinButton
    result.freespinsCounter = result.rootNode.findNode("count_@noloc").component(Text)
    result.freespinsCounter.text = ""
    result.spinText = result.rootNode.findNode("gui_spin_@noloc").component(Text)
    result.spinText.text = localizedString("GUI_SPIN")
    result.arrowParent = result.rootNode.findNode("arrows_anchor")
    for i in 1..2:
        result.arrowsTint[i-1] = result.rootNode.findNode("ltp_spin_arrow_" & $i & ".png").componentIfAvailable(Tint)
        result.arrowsTint[i-1].setColor(SpinTint.int)
    result.pressAnim = result.rootNode.animationNamed("press")
    result.button = result.rootNode.createHoldButtonComponent(result.pressAnim, newRect(0.0, 0.0, 270.0, 270.0), holdDuration)

proc playTextAnim(sbm: SpinButtonModule) =
    sbm.freespinsCounter.text = ""

    if not sbm.rootNode.sceneView().isNil:
        sbm.rootNode.sceneView().addAnimation(sbm.rootNode.animationNamed("text"))

proc restoreText(sbm: SpinButtonModule) =
    if sbm.isAutospin:
        sbm.spinText.text = localizedString("GUI_AUTOSPIN")
        sbm.arrowsTint.setColor(AutospinTint.int)
    else:
        sbm.spinText.text = localizedString("GUI_SPIN")
        sbm.arrowsTint.setColor(SpinTint.int)
    sbm.playTextAnim()

proc setFreespinsCount*(sbm: SpinButtonModule, count: int) =
    sbm.freespinsCounter.text = $count
    sbm.spinText.text = $count
    sbm.arrowsTint.setColor(FreespinTint.int)

proc startFreespins*(sbm: SpinButtonModule, count: int) =
    if sbm.isFreespin: return
    sbm.isFreespin = true
    sbm.setFreespinsCount(count)
    sbm.rootNode.addAnimation(sbm.rootNode.animationNamed("numbers"))
    sbm.arrowsTint.setColor(FreespinTint.int)

proc stopFreespins*(sbm: SpinButtonModule) =
    if not sbm.isFreespin: return
    sbm.isFreespin = false
    sbm.restoreText()

proc stopRespins*(sbm: SpinButtonModule)

proc startRespins*(sbm: SpinButtonModule) =
    if sbm.isRespins:
        sbm.stopRespins()

    sbm.isRespins = true
    sbm.spinText.text = localizedString("GUI_RESPIN")
    sbm.arrowsTint.setColor(RespinTint.int)
    sbm.playTextAnim()

proc stopRespins*(sbm: SpinButtonModule) =
    if sbm.isRespins:
        sbm.isRespins = false
        sbm.restoreText()

proc startAutospins*(sbm: SpinButtonModule) =
    sbm.isAutospin = true
    if not sbm.isFreespin and not sbm.isRespins:
        sbm.spinText.text = localizedString("GUI_AUTOSPIN")
        sbm.arrowsTint.setColor(AutospinTint.int)
        sbm.playTextAnim()

proc stopAutospins*(sbm: SpinButtonModule) =
    sbm.isAutospin = false
    if not sbm.isFreespin and not sbm.isRespins:
        sbm.spinText.text = localizedString("GUI_SPIN")
        sbm.arrowsTint.setColor(SpinTint.int)
        sbm.playTextAnim()
