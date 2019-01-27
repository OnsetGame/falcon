import nimx.types
import nimx.context
import nimx.image
import nimx.composition
import nimx.portable_gl

import rod.component
import rod.component.sprite

type ShadeSprite* = ref object of Sprite
    imageBG*: Image
    imageMask*: Image
    color*: Color

# s.color = newColor(0.0, 0.5, 0.5, 1.0) # GREEN FROM res\eiffel_slot\BG_Free.png
# s.color = newColor(1.0, 0.0, 0.0, 1.0) # RED FROM res\eiffel_slot\BG_Red.png
# s.color = newColor(0.0, 0.2, 0.6, 1.0) # BLUE

method init*(s: ShadeSprite) =
    s.color = newColor(1.0, 0.0, 0.0, 1.0)
    procCall s.Component.init()

var shadeSpriteComposition = newComposition """
uniform Image uImage;
uniform Image uMaskImage;
uniform vec4 uFromRect;
uniform float uAlpha;
uniform vec4 uColor;

void compose() {
    vec2 destuv = (vPos - bounds.xy) / bounds.zw;

    vec2 duv = uImage.texCoords.zw - uImage.texCoords.xy;
    vec2 srcxy = uImage.texCoords.xy + duv * uFromRect.xy;
    vec2 srczw = uImage.texCoords.xy + duv * uFromRect.zw;
    vec2 uv = srcxy + (srczw - srcxy) * destuv;

    vec4 texColor = texture2D(uImage.tex, uv);
    vec4 maskColor = texture2D(uMaskImage.tex, uv);

    vec4 diff = (maskColor - texColor);
    diff.a = diff.r + diff.g + diff.b;
    vec4 texel = vec4(0.0, 0.0, 0.0, diff.a);

    float maskMainColor = diff.r;

    texel.r = diff.r * uColor.r;
    texel.g = diff.g + (maskMainColor * uColor.g);
    texel.b = diff.b + (maskMainColor * uColor.b);

    gl_FragColor = texColor + texel * uColor.a;
    gl_FragColor.a *= uAlpha;
}
"""

proc drawShadeSprite*(c: GraphicsContext, s: ShadeSprite, toRect: Rect, fromRect: Rect = zeroRect, alpha: ColorComponent = 1.0) =
    if s.imageBG.isLoaded and s.imageMask.isLoaded:
        var fr = newRect(0, 0, 1, 1)
        if fromRect != zeroRect:
            let size = s.imageBG.size
            fr = newRect(fromRect.x / size.width, fromRect.y / size.height, fromRect.maxX / size.width, fromRect.maxY / size.height)
        shadeSpriteComposition.draw toRect:
            setUniform("uImage", s.imageBG)
            setUniform("uMaskImage", s.imageMask)
            setUniform("uAlpha", alpha * c.alpha)
            setUniform("uFromRect", fr)
            setUniform("uColor", s.color)

method draw*(s: ShadeSprite) =
    if not s.imageBG.isNil and not s.imageMask.isNil:
        let c = currentContext()
        let gl = c.gl
        var r: Rect
        r.origin = s.offset
        r.size = s.imageBG.size

        c.drawShadeSprite(s, r, zeroRect)
        gl.activeTexture(gl.TEXTURE0) # set default texture unit usage

registerComponent(ShadeSprite)
