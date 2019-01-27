import tables

import nimx.context
import nimx.types
import nimx.view
import nimx.matrixes
import nimx.image
import nimx.animation
import nimx.portable_gl

import rod.node
import rod.property_visitor
import rod.viewport
import rod.quaternion
import rod.component
import rod.component.camera

const vertexShader = """
attribute vec4 aPosition;
uniform mat4 mvpMatrix;
uniform float size;

varying vec2 center;
varying float radius;

void main() {
    gl_Position = mvpMatrix * vec4(aPosition.xyz, 1.0);
    gl_PointSize = size;

    center = (gl_Position.xy / gl_Position.w * 0.5 + 0.5);
    radius = size;
}
"""
const fragmentShader = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif

varying vec2 center;
varying float radius;

uniform sampler2D texUnit;
uniform vec4 uTexUnitCoords;
uniform float angle;
uniform vec4 resolution;
uniform float uAlpha;
const float mipBias = -1000.0;

void main() {
    float cos = cos(angle);
    float sin = sin(angle);
    mat3 rotMatrix = mat3(cos, sin, 0.0, -sin, cos, 0.0, (sin-cos+1.0)*0.5, (-sin-cos+1.0)*0.5, 1.0);

    vec2 uv = (gl_FragCoord.xy / resolution.xy - center) / (radius / resolution.xy) + 0.5;
    vec2 texCoord = (rotMatrix * vec3(uv, 0.0)).xy;
    gl_FragColor = texture2D(texUnit, uTexUnitCoords.xy + (uTexUnitCoords.zw - uTexUnitCoords.xy) * texCoord, mipBias);
    gl_FragColor.a *= uAlpha;
}
"""

var vertexData = newSeq[GLfloat]()
var indexData = newSeq[GLushort]()
# var cntr = 0
# for i in -100..100:
#     for j in -100..100:
#         vertexData.add(i.GLfloat*20.0)
#         vertexData.add(j.GLfloat*20.0)
#         vertexData.add(0.GLfloat)
#         indexData.add(cntr.GLushort)
#         inc cntr
vertexData.add(0.GLfloat)
vertexData.add(0.GLfloat)
vertexData.add(0.GLfloat)
indexData.add(0.GLushort)

var pointSpriteSharedIndexBuffer: BufferRef
var pointSpriteSharedVertexBuffer: BufferRef
var pointSpriteSharedNumberOfIndexes: GLsizei
var pointSpriteSharedShader: ProgramRef

type Attrib = enum
    aPosition

type PointSprite* = ref object of Component
    image*: Image
    size*: float32
    angle*: float32

proc createVBO() =
    let c = currentContext()
    let gl = c.gl

    pointSpriteSharedIndexBuffer = gl.createBuffer()
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, pointSpriteSharedIndexBuffer)
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indexData, gl.STATIC_DRAW)

    pointSpriteSharedVertexBuffer = gl.createBuffer()
    gl.bindBuffer(gl.ARRAY_BUFFER, pointSpriteSharedVertexBuffer)
    gl.bufferData(gl.ARRAY_BUFFER, vertexData, gl.STATIC_DRAW)
    pointSpriteSharedNumberOfIndexes = indexData.len.GLsizei

method init*(b: PointSprite) =
    procCall b.Component.init()
    b.size = 16.0

method draw*(b: PointSprite) =
    let vp = b.node.sceneView
    let c = currentContext()
    let gl = c.gl

    if pointSpriteSharedIndexBuffer == invalidBuffer:
        createVBO()
        if pointSpriteSharedIndexBuffer == invalidBuffer:
            return
    if pointSpriteSharedShader == invalidProgram:
        pointSpriteSharedShader = gl.newShaderProgram(vertexShader, fragmentShader, [(aPosition.GLuint, $aPosition)])
        if pointSpriteSharedShader == invalidProgram:
            return

    gl.enable(gl.BLEND)
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

    gl.enable(gl.DEPTH_TEST)

    gl.bindBuffer(gl.ARRAY_BUFFER, pointSpriteSharedVertexBuffer)
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, pointSpriteSharedIndexBuffer)

    gl.enableVertexAttribArray(aPosition.GLuint)
    gl.vertexAttribPointer(aPosition.GLuint, 3.GLint, gl.FLOAT, false, (3 * sizeof(GLfloat)).GLsizei , 0)

    gl.useProgram(pointSpriteSharedShader)

    var resolution: Vector4
    resolution[0] = b.node.sceneView.bounds.size.width
    resolution[1] = b.node.sceneView.bounds.size.height
    gl.uniform4fv(gl.getUniformLocation(pointSpriteSharedShader, "resolution"), resolution)

    gl.uniform1f(gl.getUniformLocation(pointSpriteSharedShader, "size"), b.size)

    gl.uniform1f(gl.getUniformLocation(pointSpriteSharedShader, "angle"), b.angle/180.0*3.14)

    gl.uniform1f(gl.getUniformLocation(pointSpriteSharedShader, "uAlpha"), c.alpha)

    let mvpMatrix = vp.getViewProjectionMatrix() * b.node.transform()
    gl.uniformMatrix4fv(gl.getUniformLocation(pointSpriteSharedShader, "mvpMatrix"), false, mvpMatrix)

    if b.image.isLoaded:
        var theQuad {.noinit.}: array[4, GLfloat]
        var textureIndex : GLint = 0
        gl.activeTexture(gl.TEXTURE0 + textureIndex.GLenum)
        gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(b.image, gl, theQuad))
        gl.uniform4fv(gl.getUniformLocation(pointSpriteSharedShader, "uTexUnitCoords"), theQuad)
        gl.uniform1i(gl.getUniformLocation(pointSpriteSharedShader, "texUnit"), textureIndex)

    gl.drawElements(gl.POINTS, pointSpriteSharedNumberOfIndexes, gl.UNSIGNED_SHORT)

    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, invalidBuffer)
    gl.bindBuffer(gl.ARRAY_BUFFER, invalidBuffer)

    #TODO to default settings
    gl.disable(gl.DEPTH_TEST)

method visitProperties*(b: PointSprite, p: var PropertyVisitor) =
    p.visitProperty("rotation", b.angle)
    p.visitProperty("size", b.size)

registerComponent(PointSprite)
