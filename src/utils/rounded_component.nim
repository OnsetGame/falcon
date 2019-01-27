import json
import nimx / [ types, composition ]
import nimx / [ property_visitor ]
import rod / [ component ]
import rod / tools / [ serializer ]


let roundedComponentEffect = newPostEffect("""
void rounded_component(vec4 rect, vec2 point) {
    float a = gl_FragColor.a;
    gl_FragColor.a = 0.0;
    drawShape(sdEllipseInRect(rect), vec4(gl_FragColor.rgb, a));
}
""", "rounded_component", ["vec4", "vec2"])


type RoundedComponent* = ref object of Component
    rect*: Rect
    disabled*: bool


method beforeDraw*(c: RoundedComponent, index: int): bool =
    if not c.disabled:
        pushPostEffect(roundedComponentEffect, c.rect, zeroPoint)


method afterDraw(c: RoundedComponent, index: int) = 
    if not c.disabled:
        popPostEffect()


method isPosteffectComponent*(c: Component): bool = true


method visitProperties*(c: RoundedComponent, p: var PropertyVisitor) =
    p.visitProperty("rect", c.rect)
    p.visitProperty("disabled", c.disabled)


registerComponent(RoundedComponent)