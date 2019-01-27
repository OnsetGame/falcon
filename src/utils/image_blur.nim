import nimx.types
import nimx.portable_gl
import nimx.context
import nimx.image

const imageVertexShader = """
attribute vec4 saPosition;

uniform mat4 modelViewProjectionMatrix;

varying vec2 vTexCoord;

void main()
{
    vTexCoord = saPosition.zw;
    gl_Position = modelViewProjectionMatrix * vec4(saPosition.xy, 0, 1);
}
"""

const imageFragmentShader = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif

uniform sampler2D textureSampler;
varying vec2 vTexCoord;
uniform vec2 uBlurVector;

vec2 adjustedBlurVector = uBlurVector / 10000.0;

void main() {
    vec4 averageColor = vec4(0.0, 0.0, 0.0, 1.0);
    for (int index = -8; index < 8;index++) {
        vec2 pointCoordinate = vTexCoord + adjustedBlurVector * float(index);
        vec4 color = texture2D(textureSampler, pointCoordinate);

        if (pointCoordinate.x < 0.0 || pointCoordinate.x > 1.0) {
            color = vec4(1.0, 1.0, 1.0, 0.0);
        }

        averageColor = averageColor + color;
    }

    averageColor = averageColor / 16.0;
    averageColor.a = pow(averageColor.a, 4.0);

    gl_FragColor = min(averageColor, 1.0);
}
"""

var shader: GLuint

proc drawImageWithBlur*(c: GraphicsContext, i: Image, toRect: Rect, fromRect: Rect = zeroRect, blurVector: Vector2) =
    if shader == 0:
        shader = c.gl.newShaderProgram(imageVertexShader, imageFragmentShader, [(0.GLuint, "saPosition")])

    var texCoords : array[4, GLfloat]
    let t = i.getTextureQuad(c.gl, texCoords)
    if t != 0:
        c.gl.useProgram(shader)
        c.gl.activeTexture(c.gl.TEXTURE0)
        c.gl.bindTexture(c.gl.TEXTURE_2D, t)
        c.gl.enable(c.gl.BLEND)
        c.gl.blendFunc(c.gl.SRC_ALPHA, c.gl.ONE_MINUS_SRC_ALPHA)

        let sizeInTexels = newSize(texCoords[2] - texCoords[0], texCoords[3] - texCoords[1])
        var s0 : Coord = texCoords[0]
        var t0 : Coord = texCoords[1]
        var s1 : Coord = texCoords[2]
        var t1 : Coord = texCoords[3]
        if fromRect != zeroRect:
            s0 = texCoords[0] + fromRect.x / i.size.width * sizeInTexels.width
            t0 = texCoords[1] + fromRect.y / i.size.height * sizeInTexels.height
            s1 = texCoords[0] + fromRect.maxX / i.size.width * sizeInTexels.width
            t1 = texCoords[1] + fromRect.maxY / i.size.height * sizeInTexels.height

        let points = [toRect.minX, toRect.minY, s0, t0,
                    toRect.maxX, toRect.minY, s1, t0,
                    toRect.maxX, toRect.maxY, s1, t1,
                    toRect.minX, toRect.maxY, s0, t1]
        c.gl.enableVertexAttribArray(0.GLuint)
        c.setTransformUniform(shader)
        c.gl.uniform2fv(c.gl.getUniformLocation(shader, "uBlurVector"), blurVector)
        c.gl.vertexAttribPointer(0.GLuint, 4, false, 0, points)
        c.gl.drawArrays(c.gl.TRIANGLE_FAN, 0, 4)
