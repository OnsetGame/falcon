import tables

import nimx.context
import nimx.types
import nimx.view
import nimx.matrixes
# import nimx.image
import nimx.animation
import nimx.portable_gl
import nimx.property_visitor

import rod.node
import rod.viewport
import rod.quaternion
import rod.component
import rod.component.camera
import rod.animated_image

const vertexShader = """
attribute vec4 aPosition;
attribute vec2 aTexCoord;

varying vec2 vTexCoord;

uniform mat4 mvpMatrix;

void main() {
    vTexCoord = aTexCoord;
    gl_Position = mvpMatrix * vec4(aPosition.xyz, 1.0);
}
"""
const fragmentShader = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif

varying vec2 vTexCoord;

uniform sampler2D texUnit;
uniform vec4 uTexUnitCoords;
uniform float uAlpha;

const float mipBias = -1000.0;

void main() {
    gl_FragColor = texture2D(texUnit, uTexUnitCoords.xy + (uTexUnitCoords.zw - uTexUnitCoords.xy) * vTexCoord, mipBias);
    gl_FragColor.a *= uAlpha;
}
"""

let width = 0.5.GLfloat
let height = 0.5.GLfloat
let indexData = [0.GLushort, 1, 2, 2, 3, 0]
let vertexData = [
        -width,  height, 0.0, 0.0, 1.0,
        -width, -height, 0.0, 0.0, 0.0,
         width, -height, 0.0, 1.0, 0.0,
         width,  height, 0.0, 1.0, 1.0
        ]

var softBillboardSharedIndexBuffer: BufferRef
var softBillboardSharedVertexBuffer: BufferRef
var softBillboardSharedNumberOfIndexes: GLsizei
var softBillboardSharedShader: ProgramRef

type Attrib = enum
    aPosition
    aTexCoord

type SoftBillboard* = ref object of Component
    image*: AnimatedImage
    bFixedSize*: bool
    initialDistanceToCamera: float32
    initialScale: Vector3

proc createVBO() =
    let c = currentContext()
    let gl = c.gl

    softBillboardSharedIndexBuffer = gl.createBuffer()
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, softBillboardSharedIndexBuffer)
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indexData, gl.STATIC_DRAW)

    softBillboardSharedVertexBuffer = gl.createBuffer()
    gl.bindBuffer(gl.ARRAY_BUFFER, softBillboardSharedVertexBuffer)
    gl.bufferData(gl.ARRAY_BUFFER, vertexData, gl.STATIC_DRAW)
    softBillboardSharedNumberOfIndexes = indexData.len.GLsizei

proc getTransformBillboard(n: Node, mat: var Matrix4) =
    mat.translate(n.position)
    mat.scale(n.scale)

proc transformBillboard(n: Node): Matrix4 =
    result.loadIdentity()
    n.getTransformBillboard(result)

proc worldTransformBillboard(n: Node): Matrix4 =
    if n.parent.isNil:
        result = n.transformBillboard
    else:
        let w = n.parent.worldTransformBillboard
        w.multiply(n.transformBillboard, result)

method init*(b: SoftBillboard) =
    procCall b.Component.init()

method draw*(b: SoftBillboard) =
    let vp = b.node.sceneView
    let c = currentContext()
    let gl = c.gl

    if softBillboardSharedIndexBuffer == invalidBuffer:
        createVBO()
        if softBillboardSharedIndexBuffer == invalidBuffer:
            return
    if softBillboardSharedShader == invalidProgram:
        softBillboardSharedShader = gl.newShaderProgram(vertexShader, fragmentShader, [(Attrib.aPosition.GLuint, $aPosition), (aTexCoord.GLuint, $aTexCoord)])
        if softBillboardSharedShader == invalidProgram:
            return

    gl.bindBuffer(gl.ARRAY_BUFFER, softBillboardSharedVertexBuffer)
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, softBillboardSharedIndexBuffer)

    gl.enableVertexAttribArray(aPosition.GLuint)
    gl.vertexAttribPointer(aPosition.GLuint, 3.GLint, gl.FLOAT, false, (5 * sizeof(GLfloat)).GLsizei, 0)

    gl.enableVertexAttribArray(aTexCoord.GLuint)
    gl.vertexAttribPointer(aTexCoord.GLuint, 2.GLint, gl.FLOAT, false, (5 * sizeof(GLfloat)).GLsizei, 3*sizeof(GLfloat))

    gl.useProgram(softBillboardSharedShader)

    if b.bFixedSize:
        let currDist = vp.mCamera.node.worldPos - b.node.worldPos
        if b.initialDistanceToCamera == 0:
            b.initialDistanceToCamera = currDist.length()
            b.initialScale = b.node.scale
        let deltaScale = b.initialDistanceToCamera / currDist.length()
        b.node.scale = b.initialScale / deltaScale

    var projTransform : Transform3D
    vp.camera.getProjectionMatrix(vp.bounds, projTransform)

    var viewTransform = vp.viewMatrixCached

    viewTransform[0] = 1.0
    viewTransform[4] = 0.0
    viewTransform[8] = 0.0

    viewTransform[1] = 0.0
    viewTransform[5] = 1.0
    viewTransform[9] = 0.0

    viewTransform[2] = 0.0
    viewTransform[6] = 0.0
    viewTransform[10] = 1.0

    var tr = b.node.worldTransformBillboard()
    if b.image.isLoaded:
        let scaleVec = newVector3(b.image.size.width, b.image.size.height, 1.0)
        tr.scale(scaleVec)

    let mvpMatrix = projTransform * viewTransform * tr

    gl.uniformMatrix4fv(gl.getUniformLocation(softBillboardSharedShader, "mvpMatrix"), false, mvpMatrix)

    gl.uniform1f(gl.getUniformLocation(softBillboardSharedShader, "uAlpha"), c.alpha)

    if b.image.isLoaded:
        var theQuad {.noinit.}: array[4, GLfloat]
        gl.activeTexture(gl.TEXTURE0)
        gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(b.image, gl, theQuad))
        gl.uniform4fv(gl.getUniformLocation(softBillboardSharedShader, "uTexUnitCoords"), theQuad)
        gl.uniform1i(gl.getUniformLocation(softBillboardSharedShader, "texUnit"), 0)

    gl.drawElements(gl.TRIANGLES, softBillboardSharedNumberOfIndexes, gl.UNSIGNED_SHORT)

    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, invalidBuffer)
    gl.bindBuffer(gl.ARRAY_BUFFER, invalidBuffer)

import nimx.image
method visitProperties*(b: SoftBillboard, p: var PropertyVisitor) =
    p.visitProperty("image", Image(b.image))
    p.visitProperty("fixed_size", b.bFixedSize)

registerComponent(SoftBillboard)
