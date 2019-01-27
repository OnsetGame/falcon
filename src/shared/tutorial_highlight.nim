import nimx / [ context, composition, view, matrixes, property_visitor ]
import rod / [ component, viewport, node ]

type
    TutorialHightlightShape* = enum
        thsEllipse
        thsRoundedRect

    TutorialHighlight* = ref object of Component
        rect*: Rect
        kind*: TutorialHightlightShape
        roundedRectRadius*: Coord

var roundedRectComposition = newComposition """
uniform vec4 uRect;
uniform float uRadius;
uniform float uAlpha;

void compose() {
    drawShape(sdRect(bounds), vec4(0.0, 0, 0, 0.8 * uAlpha));
    drawShape(sdRoundedRect(uRect, uRadius), vec4(0.0));
}
"""

var ellipseComposition = newComposition """
uniform vec4 uRect;
uniform float uAlpha;
void compose() {
    drawShape(sdRect(bounds), vec4(0.0, 0, 0, 0.8 * uAlpha));
    drawShape(sdEllipseInRect(uRect), vec4(0.0));
}
"""

method init*(c: TutorialHighlight) =
    c.roundedRectRadius = 10

method beforeDraw*(c: TutorialHighlight, index: int): bool =
    let sv = c.node.sceneView
    var bnds = sv.bounds
    var winBounds = bnds
    var rect = c.rect
    let wnd = sv.window
    if not wnd.isNil:
        winBounds = wnd.bounds
        bnds = sv.convertRectToWindow(bnds)
        rect = sv.convertRectToWindow(rect)

    let cc = currentContext()
    currentContext().withTransform ortho(winBounds.x, winBounds.width, winBounds.height, winBounds.y, -1, 1):
        case c.kind
        of thsEllipse:
          ellipseComposition.draw(bnds):
              setUniform("uRect", rect)
              setUniform("uAlpha", cc.alpha)
        of thsRoundedRect:
          roundedRectComposition.draw(bnds):
              setUniform("uRect", rect)
              setUniform("uRadius", c.roundedRectRadius)
              setUniform("uAlpha", cc.alpha)

method visitProperties*(t: TutorialHighlight, p: var PropertyVisitor) =
    p.visitProperty("kind", t.kind)
    p.visitProperty("rect", t.rect)
    p.visitProperty("radius", t.roundedRectRadius)

registerComponent(TutorialHighlight, "Falcon")
