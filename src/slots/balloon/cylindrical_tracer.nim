import nimx.context
import nimx.portable_gl
import nimx.types
import nimx.image
import nimx.matrixes

import rod.component
import rod.quaternion
import rod.component.mesh_component
import rod.component.material
import rod.component.light
import rod.component.camera
import rod.component.sprite
import rod.node
import rod.property_visitor
import rod.viewport

import math

const vertexShader = """
attribute vec4 aPosition;
uniform mat4 mvpMatrix;
void main() { gl_Position = mvpMatrix * vec4(aPosition.xyz, 1.0); }
"""
const fragmentShader = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif
uniform vec4 uColor;
void main() { gl_FragColor = uColor; }
"""
var CylindricalTracerShader: ProgramRef

const initialIndicesCount = 10000
const initialVerticesCount = 10000

type
    Attrib = enum
        aPosition
    CylindricalTracer* = ref object of Component
        color*: Vector4
        indexBuffer: BufferRef
        vertexBuffer: BufferRef
        numberOfIndexes: GLsizei
        vertexOffset: int32
        indexOffset: int32
        prevTransform: Vector3
        traceStep*: int32
        traceStepCounter: int32
        index: int32

        currIndex: GLushort

var globalIndexer: int32 = 0

method componentNodeWillBeRemovedFromSceneView*(t: CylindricalTracer) =
    let c = currentContext()
    let gl = c.gl
    gl.bindBuffer(gl.ARRAY_BUFFER, t.indexBuffer)
    gl.deleteBuffer(t.indexBuffer)
    gl.bindBuffer(gl.ARRAY_BUFFER, t.vertexBuffer)
    gl.deleteBuffer(t.vertexBuffer)

method init*(t: CylindricalTracer) =
    procCall t.Component.init()

    t.color = newVector4(1, 0, 0, 1.0)
    t.numberOfIndexes = 0.GLsizei
    t.traceStep = 15
    t.vertexOffset = 0
    t.traceStepCounter = 0
    t.indexOffset = 0

    t.index = globalIndexer
    inc globalIndexer

proc makeCyliynder(radius: float32, numSteps: int32, startP, destP: Vector3, vertices: var seq[Vector3], indices: var seq[GLushort], currIndx: var GLushort) =
    vertices = newSeq[Vector3](numSteps * 2)
    indices = newSeq[GLushort](6 * numSteps)

    var a = 0.0'f32
    var step = (2.0*PI / numSteps.float64).float32

    for i in 0..<numSteps:
        let x = cos(a) * radius
        let y = sin(a) * radius

        vertices[i] = startP + newVector3(x, y, 0.0)
        vertices[i + numSteps] = destP + newVector3(x, y, 0.0)
        a += step
    # caps
    # vertices[numSteps * 2 + 0].Set(0.0f, 0.0f, z)
    # vertices[numSteps * 2 + 1].Set(0.0f, 0.0f, -z)

    for i in 0..<numSteps:
        let i1 = currIndx.int32+i
        let i2 = currIndx.int32+(i1 + 1) mod numSteps
        let i3 = i1 + numSteps
        let i4 = i2 + numSteps
        indices[i * 6 + 0] = i1.GLushort
        indices[i * 6 + 1] = i3.GLushort
        indices[i * 6 + 2] = i2.GLushort
        indices[i * 6 + 3] = i4.GLushort
        indices[i * 6 + 4] = i2.GLushort
        indices[i * 6 + 5] = i3.GLushort

        # caps
        # indices[numSteps * 6 + i * 6 + 0] = numSteps * 2 + 0;
        # indices[numSteps * 6 + i * 6 + 1] = i1;
        # indices[numSteps * 6 + i * 6 + 2] = i2;
        # indices[numSteps * 6 + i * 6 + 3] = numSteps * 2 + 1;
        # indices[numSteps * 6 + i * 6 + 4] = i4;
        # indices[numSteps * 6 + i * 6 + 5] = i3;

    currIndx += 4.GLushort*numSteps.GLushort

proc addTraceLine(t: CylindricalTracer, point: Vector3) =
    let c = currentContext()
    let gl = c.gl

    # var bVertexBufferNeedUpdate, bIndexBufferNeedUpdate: bool

    # if (t.vertexOffset + 3*sizeof(GLfloat)) > initialVerticesCount*sizeof(GLfloat):
    #     bVertexBufferNeedUpdate = true

    # if (t.indexOffset + 2*sizeof(GLushort)) > initialIndicesCount*sizeof(GLushort):
    #     bIndexBufferNeedUpdate = true

    # if bIndexBufferNeedUpdate or bVertexBufferNeedUpdate:
    #     # recreate index_buffer
    #     gl.bindBuffer(gl.ARRAY_BUFFER, t.indexBuffer)
    #     gl.deleteBuffer(t.indexBuffer)
    #     t.indexBuffer = 0
    #     t.indexOffset = 0
    #     t.numberOfIndexes = 0.GLsizei

    #     t.indexBuffer = gl.createBuffer()
    #     gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, t.indexBuffer)
    #     gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, (initialIndicesCount * sizeof(GLushort)), gl.STREAM_DRAW)

    #     # recreate array_buffer
    #     gl.bindBuffer(gl.ARRAY_BUFFER, t.vertexBuffer)
    #     gl.deleteBuffer(t.vertexBuffer)
    #     t.vertexBuffer = 0
    #     t.vertexOffset = 0

    #     t.vertexBuffer = gl.createBuffer()
    #     gl.bindBuffer(gl.ARRAY_BUFFER, t.vertexBuffer)
    #     gl.bufferData(gl.ARRAY_BUFFER, (initialVerticesCount * sizeof(GLfloat)), gl.STREAM_DRAW)

    #     # fill buffers with initial data
    #     var vertexData = @[t.prevTransform[0].GLfloat, t.prevTransform[1], t.prevTransform[2]]
    #     gl.bufferSubData(gl.ARRAY_BUFFER, t.vertexOffset, vertexData)
    #     t.vertexOffset += sizeof(GLfloat) * 3

    #     var indexData = @[(t.numberOfIndexes).GLushort, (t.numberOfIndexes+1).GLushort]
    #     gl.bufferSubData(gl.ELEMENT_ARRAY_BUFFER, t.indexOffset, indexData)
    #     t.indexOffset += sizeof(GLushort) * 2
    #     t.numberOfIndexes += 1

    #     bIndexBufferNeedUpdate = false
    #     bVertexBufferNeedUpdate = false

    # if not bIndexBufferNeedUpdate and not bVertexBufferNeedUpdate:
        # var vertexData = @[point[0].GLfloat, point[1], point[2]]

    var vertexData: seq[Vector3]
    var indexData: seq[GLushort]
    makeCyliynder(1.0, 8, t.prevTransform, point, vertexData, indexData, t.currIndex)

    var vert = newSeq[GLfloat]()
    var counter = 0
    for i in vertexData:
        vert.add(i[0])
        vert.add(i[1])
        vert.add(i[2])
        counter += 3

    gl.bindBuffer(gl.ARRAY_BUFFER, t.vertexBuffer)
    gl.bufferSubData(gl.ARRAY_BUFFER, t.vertexOffset, vert)
    t.vertexOffset += (sizeof(GLfloat) * vert.len()).int32

    # var indexData = @[(t.numberOfIndexes).GLushort, (t.numberOfIndexes+1).GLushort]
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, t.indexBuffer)
    gl.bufferSubData(gl.ELEMENT_ARRAY_BUFFER, t.indexOffset, indexData)
    t.indexOffset += (sizeof(GLushort) * indexData.len()).int32
    # t.numberOfIndexes += 1

    t.numberOfIndexes += indexData.len().GLsizei

    t.prevTransform = point

proc startTrace(t: CylindricalTracer) =
    if t.traceStepCounter == t.traceStep:
        var transform = t.node.worldPos()
        if t.prevTransform != transform:
            t.addTraceLine(transform)
        # t.prevTransform = transform
        t.traceStepCounter = 0
    inc t.traceStepCounter

method draw*(t: CylindricalTracer) =
    let c = currentContext()
    let gl = c.gl

    if t.indexBuffer == invalidBuffer:
        t.indexBuffer = gl.createBuffer()
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, t.indexBuffer)
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, (initialIndicesCount * sizeof(GLushort)).int32, gl.STREAM_DRAW)
        if t.indexBuffer == invalidBuffer:
            return

    if t.vertexBuffer == invalidBuffer:
        t.vertexBuffer = gl.createBuffer()
        gl.bindBuffer(gl.ARRAY_BUFFER, t.vertexBuffer)
        gl.bufferData(gl.ARRAY_BUFFER, (initialVerticesCount * sizeof(GLfloat)).int32, gl.STREAM_DRAW)
        if t.vertexBuffer == invalidBuffer:
            return
        else:
            var pos = t.node.worldPos()
            # t.addTraceLine(pos)
            t.prevTransform = pos

    if CylindricalTracerShader == invalidProgram:
        CylindricalTracerShader = gl.newShaderProgram(vertexShader, fragmentShader, [(aPosition.GLuint, $aPosition)])
        if CylindricalTracerShader == invalidProgram:
            return

    t.startTrace()

    if t.numberOfIndexes > 0:
        gl.enable(gl.DEPTH_TEST)

        gl.enable(gl.DEPTH_TEST)

        gl.bindBuffer(gl.ARRAY_BUFFER, t.vertexBuffer)
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, t.indexBuffer)
        gl.enableVertexAttribArray(aPosition.GLuint)
        gl.vertexAttribPointer(aPosition.GLuint, 3.GLint, gl.FLOAT, false, (3 * sizeof(GLfloat)).GLsizei , 0)
        gl.useProgram(CylindricalTracerShader)

        if t.color[3] < 1.0:
            gl.enable(gl.BLEND)
            gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

        gl.uniform4fv(gl.getUniformLocation(CylindricalTracerShader, "uColor"), t.color)

        let vp = t.node.sceneView
        let mvpMatrix = vp.getViewProjectionMatrix()
        gl.uniformMatrix4fv(gl.getUniformLocation(CylindricalTracerShader, "mvpMatrix"), false, mvpMatrix)

        # gl.drawElements(gl.LINES, t.numberOfIndexes * 2 - 1, gl.UNSIGNED_SHORT)

        gl.drawElements(gl.TRIANGLES, t.numberOfIndexes, gl.UNSIGNED_SHORT)

        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, invalidBuffer)
        gl.bindBuffer(gl.ARRAY_BUFFER, invalidBuffer)

        #TODO to default settings
        gl.disable(gl.DEPTH_TEST)

method visitProperties*(t: CylindricalTracer, p: var PropertyVisitor) =
    p.visitProperty("color", t.color)
    p.visitProperty("trace_step", t.traceStep)

registerComponent(CylindricalTracer)
