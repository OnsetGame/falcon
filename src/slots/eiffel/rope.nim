# Drawing of ropes for tower slots

import nimx.context
import nimx.composition
import nimx.image
import nimx.types

var ropeComposition = newComposition """
uniform Image uImage;
uniform float uAnimationOffset;

void compose() {
    float ropeImageHeight = 28.0;

    vec2 uv = vPos - bounds.xy;

    uv.x /= bounds.z;
    float xEdge = 0.5; // X texCoord that devides right and left rope
    float ySign = sign(step(xEdge, uv.x) - 0.5);

    uv.y += ropeImageHeight * uAnimationOffset * ySign;
    uv.y = mod(uv.y, ropeImageHeight);

    uv.y /= ropeImageHeight;

    gl_FragColor = texture2D(uImage.tex, uImage.texCoords.xy + (uImage.texCoords.zw - uImage.texCoords.xy) * uv);
}
"""

proc drawRope*(i: Image, x, fromY, height: Coord, animationOffset: Coord) =
    let c = currentContext()
    let r = newRect(x - 10, fromY, i.size.width, height)

    if i.isLoaded:
        ropeComposition.draw r:
            setUniform("uAnimationOffset", animationOffset)
            setUniform("uImage", i)
