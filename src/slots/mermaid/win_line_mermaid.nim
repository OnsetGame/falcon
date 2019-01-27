import nimx.context
import nimx.portable_gl
import nimx.types
import nimx.image
import nimx.matrixes
import nimx.property_visitor
import nimx.view

import rod.component
import rod.quaternion

import rod.component.camera
import rod.component.sprite
import rod.component.solid
import rod.node
import rod.viewport
import rod.tools.serializer

import math
import random
import opengl
import json

const vertexShader = """
attribute vec2 aPosition;
attribute vec2 aTexCoord;

varying vec2 vTexCoord;

uniform mat4 mvpMatrix;

void main() {
    gl_Position = mvpMatrix * vec4(aPosition.xy, 0.0, 1.0);
    vTexCoord = aTexCoord.xy;
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
uniform vec2 uTiles;

void main() {
    vec2 uv = vTexCoord;
    uv.x = fract(uv.x * uTiles.x);
    uv.y = fract(uv.y * uTiles.y);
    uv = uTexUnitCoords.xy + (uTexUnitCoords.zw - uTexUnitCoords.xy) * uv;
    gl_FragColor = texture2D(texUnit, uv, 0.0);
    gl_FragColor.a *= uAlpha;
}
"""

const POS_UV_ELEMENTS = 8
const IND_ELEMENTS = 2

var WinLineMermaidShader: ProgramRef

type
    Attrib = enum
        aPosition
        aTexCoord

    WinLineMermaid* = ref object of Component
        mWidth: float32
        mRoundSteps: float32
        density*: float32
        # image*: Image

        sprite*: Sprite
        tiles*: Point
        positions*: seq[Vector3]

        indexBuffer: BufferRef
        vertexBuffer: BufferRef
        numberOfIndexes: GLsizei
        uniformLocationCache: seq[UniformLocation]
        iUniform: int

proc cleanup*(wl: WinLineMermaid) =
    let c = currentContext()
    let gl = c.gl
    if wl.indexBuffer != invalidBuffer:
        gl.deleteBuffer(wl.indexBuffer)
        wl.indexBuffer = invalidBuffer
    if wl.vertexBuffer != invalidBuffer:
        gl.deleteBuffer(wl.vertexBuffer)
        wl.vertexBuffer = invalidBuffer

proc emitQuads(wl: WinLineMermaid, dbg: bool = false): tuple[vert: seq[GLfloat], ind: seq[GLushort]]
proc recreateBuffers(wl: WinLineMermaid) =
    let c = currentContext()
    let gl = c.gl
    if wl.indexBuffer == invalidBuffer:
        wl.indexBuffer = gl.createBuffer()
    if wl.vertexBuffer == invalidBuffer:
        wl.vertexBuffer = gl.createBuffer()

    let data = wl.emitQuads()
    wl.numberOfIndexes = data.ind.len.GLsizei

    if wl.positions.len > 1:
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, wl.indexBuffer)
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, data.ind, gl.STATIC_DRAW)
        if wl.indexBuffer == invalidBuffer:
            return
        gl.bindBuffer(gl.ARRAY_BUFFER, wl.vertexBuffer)
        gl.bufferData(gl.ARRAY_BUFFER, data.vert, gl.STATIC_DRAW)
        if wl.vertexBuffer == invalidBuffer:
            return

template width*(wl: WinLineMermaid): float32 = wl.mWidth
template `width=`*(wl: WinLineMermaid, v: float32) =
    wl.mWidth = v
    recreateBuffers(wl)

template roundSteps*(wl: WinLineMermaid): float32 = wl.mRoundSteps
template `roundSteps=`*(wl: WinLineMermaid, v: float32) =
    if v >= 0.0:
        wl.mRoundSteps = v
        recreateBuffers(wl)

method init*(wl: WinLineMermaid) =
    procCall wl.Component.init()
    wl.width = 100.0
    wl.roundSteps = 30.0
    wl.density = 1.0
    wl.tiles = newPoint(1.0, 1.0)
    wl.uniformLocationCache = @[]
    wl.positions = @[]

template getUniformLocation(gl: GL, name: cstring): UniformLocation =
    inc wl.iUniform
    if wl.uniformLocationCache.len - 1 < wl.iUniform:
        wl.uniformLocationCache.add(gl.getUniformLocation(WinLineMermaidShader, name))
    wl.uniformLocationCache[wl.iUniform]

template setColorUniform(c: GraphicsContext, name: cstring, col: Color) =
    c.setColorUniform(c.gl.getUniformLocation(name), col)

proc distance(first, second: Vector2): float =
    result = sqrt(pow(first.x-second.x, 2)+pow(first.y-second.y, 2))

proc distance(first, second: Vector3): float =
    result = sqrt(pow(first.x-second.x, 2)+pow(first.y-second.y, 2)+pow(first.z-second.z, 2))

proc normalize*(v: var Vector2) =
    let leng = v.length()
    if leng != 0:
        v[0] /= leng
        v[1] /= leng

proc addVertexData(pMin, pMax: Vector2, totalLen: var GLfloat, data: var seq[GLfloat]) =

    if data.len >= POS_UV_ELEMENTS:
        let prevInnerX = data[data.len - 8]
        let prevInnerY = data[data.len - 7]
        let prevOuterX = data[data.len - 4]
        let prevOuterY = data[data.len - 3]
        let prevMidP = (newVector2(prevInnerX, prevInnerY) + newVector2(prevOuterX, prevOuterY)) / 2.0
        let currMidP = (pMin + pMax) / 2.0
        var dist = distance(prevMidP, currMidP)

        totalLen += dist

    data.add(pMin[0].GLfloat)
    data.add(pMin[1].GLfloat)
    data.add(totalLen.GLfloat)
    data.add(0.95.GLfloat)
    data.add(pMax[0].GLfloat)
    data.add(pMax[1].GLfloat)
    data.add(totalLen.GLfloat)
    data.add(0.05.GLfloat)

proc addIndexData(currIndex: var GLushort, data: var seq[GLushort]) =
    data.add(currIndex)
    data.add(currIndex+1)
    currIndex += IND_ELEMENTS.GLushort

template angleBetweenVecRad(u, v: Vector2): float32 =
    arctan2(u.y - v.y, u.x - v.x)

template angleBetweenVecRad(u, v: Vector3): float32 =
    arctan2(u.y - v.y, u.x - v.x)

template angleBetweenVecDeg(u, v: Vector2): float32 =
    angleBetweenVecRad(u, v) * 180.0 / PI

template angleBetweenVecDeg(u, v: Vector3): float32 =
    angleBetweenVecRad(u, v) * 180.0 / PI

proc bHasInetersectPoint(p1, p2: Vector2, p3, p4: Vector2, res: var Vector2): bool =
    result = false
    let d = (p1.x - p2.x) * (p3.y - p4.y) - (p1.y - p2.y) * (p3.x - p4.x)
    if (d >= -1.0 and d <= 1.0):
        return
    let pre = (p1.x * p2.y - p1.y * p2.x)
    let post = (p3.x * p4.y - p3.y * p4.x)
    res.x = ( pre * (p3.x - p4.x) - (p1.x - p2.x) * post ) / d
    res.y = ( pre * (p3.y - p4.y) - (p1.y - p2.y) * post ) / d
    result = true

proc perpendicularPoint(A, B: Vector2, C: Vector2): Vector2 =
    var x = B.y - A.y
    var y = A.x - B.x
    var L = (A.x*B.y - B.x*A.y + A.y*C.x - B.y*C.x + B.x*C.y - A.x*C.y)/(x*(B.y - A.y) + y*(A.x - B.x))
    var H: Vector2
    H.x = C.x + x * L
    H.y = C.y + y * L
    return H


var solids: seq[Node] = @[]
var dbgCounter = 0

proc emitDebugSolid(wl: WinLineMermaid, name: string, pos: Vector2) =
    let ndName = name & $dbgCounter
    let currColor = newColor(rand(50).float32/50.float32, rand(50).float32/50.float32, rand(50).float32/50.float32, 1.0)
    inc dbgCounter
    var ch = wl.node.sceneView.rootNode.findNode(ndName)
    if ch.isNil:
        let size = newSize(20, 20)
        ch = wl.node.sceneView.rootNode.newChild(ndName)
        let sld = ch.component(Solid)
        ch.anchor = newVector3(size.width/2.0,size.height/2.0,0)
        sld.size = size
        sld.color = currColor
    ch.worldPos = newVector3(pos.x, pos.y)

    solids.add(ch)

proc emitQuads(wl: WinLineMermaid, dbg: bool = false): tuple[vert: seq[GLfloat], ind: seq[GLushort]] =


    if dbg:
        for ch in solids:
            ch.removeFromParent()
        solids = @[]
        dbgCounter = 0


    var lines: seq[ tuple[aMin: Vector3, aMax: Vector3, bMin: Vector3, bMax: Vector3] ] = @[]
    var currP: Vector3
    var nextP: Vector3
    var currDir: Vector2
    var prevDir: Vector2

    for i in 0 ..< wl.positions.len-1:
        currP = wl.positions[i]
        nextP = wl.positions[i+1]
        currDir = newVector2(currP.x - nextP.x, currP.y - nextP.y)
        currDir.normalize()
        let topDir = newVector3(-currDir.y, currDir.x)
        let botDir = newVector3(currDir.y, -currDir.x)
        let pMaxNext = nextP + topDir * wl.width
        let pMinNext = nextP + botDir * wl.width
        # if lines.len > 0:
        #     if (currDir.x == prevDir.x and currDir.y == prevDir.y) or lines[^1][2] == pMinNext or lines[^1][3] == pMaxNext:
        #         lines[^1][2]= pMinNext
        #         lines[^1][3] = pMaxNext
        #     else:
        #         let pMaxCurr = currP + topDir * wl.width
        #         let pMinCurr = currP + botDir * wl.width
        #         lines.add( (pMinCurr, pMaxCurr, pMinNext, pMaxNext) )
        # else:
        let pMaxCurr = currP + topDir * wl.width
        let pMinCurr = currP + botDir * wl.width
        lines.add( (pMinCurr, pMaxCurr, pMinNext, pMaxNext) )

        prevDir = currDir

    result.vert = @[]
    result.ind = @[]

    var innerTotalLen = 0.GLfloat
    var totalLen = 0.GLfloat
    var currIndex = 0.GLushort

    var currLine: tuple[aMin: Vector3, aMax: Vector3, bMin: Vector3, bMax: Vector3]
    var nextLine: tuple[aMin: Vector3, aMax: Vector3, bMin: Vector3, bMax: Vector3]

    var pPointLeftMax: Vector2
    var pPointLeftMin: Vector2

    var pPointRightMax: Vector2
    var pPointRightMin: Vector2

    var aa1 : Vector2
    var bb1 : Vector2
    var aa2 : Vector2
    var bb2 : Vector2
    var k = 0

    if lines.len == 1:
        currLine = lines[0]

        addVertexData(newVector2(currLine.aMin.x, currLine.aMin.y), newVector2(currLine.aMax.x, currLine.aMax.y), totalLen, result.vert)
        addIndexData(currIndex, result.ind)

        addVertexData(newVector2(currLine.bMin.x, currLine.bMin.y), newVector2(currLine.bMax.x, currLine.bMax.y), totalLen, result.vert)
        addIndexData(currIndex, result.ind)

    var segments: seq[ tuple[leftMin: Vector2, leftMax: Vector2, rightMin: Vector2, rightMax: Vector2] ] = @[]

    while k < lines.len-1:
        var segment: tuple[leftMin: Vector2, leftMax: Vector2, rightMin: Vector2, rightMax: Vector2]

        currLine = lines[k]
        nextLine = lines[k+1]
        aa1 = newVector2(currLine.aMin.x, currLine.aMin.y)
        bb1 = newVector2(currLine.bMin.x, currLine.bMin.y)
        aa2 = newVector2(nextLine.bMin.x, nextLine.bMin.y)
        bb2 = newVector2(nextLine.aMin.x, nextLine.aMin.y)

        if k == 0:
            pPointLeftMin = newVector2(currLine.aMin.x, currLine.aMin.y)
            pPointLeftMax = newVector2(currLine.aMax.x, currLine.aMax.y)

            segment.leftMin = pPointLeftMin
            segment.leftMax = pPointLeftMax

        var intersectP: Vector2
        if not bHasInetersectPoint(aa1, bb1, aa2, bb2, intersectP):
            # inc k
            # continue
            discard

        aa2 = newVector2(nextLine.aMax.x, nextLine.aMax.y)
        bb2 = newVector2(nextLine.bMax.x, nextLine.bMax.y)

        var intersectP2: Vector2
        if not bHasInetersectPoint(aa1, bb1, aa2, bb2, intersectP2):
            # inc k
            # continue
            discard

        var projLen = distance(intersectP, intersectP2) / wl.density
        var lineLen = distance(aa1, bb1)

        aa2 = newVector2(currLine.aMin.x, currLine.aMin.y)
        bb2 = newVector2(currLine.bMin.x, currLine.bMin.y)

        pPointLeftMin.x = bb2.x - projLen * 1.5 * (bb2.x - aa2.x) / lineLen
        pPointLeftMin.y = bb2.y - projLen * 1.5 * (bb2.y - aa2.y) / lineLen

        aa2 = newVector2(currLine.aMax.x, currLine.aMax.y)
        bb2 = newVector2(currLine.bMax.x, currLine.bMax.y)

        pPointLeftMax = perpendicularPoint(aa2, bb2, pPointLeftMin)

        aa2 = newVector2(nextLine.aMin.x, nextLine.aMin.y)
        bb2 = newVector2(nextLine.bMin.x, nextLine.bMin.y)

        lineLen = distance(aa2, bb2)

        pPointRightMin.x = aa2.x - projLen * 1.5 * (aa2.x - bb2.x) / lineLen
        pPointRightMin.y = aa2.y - projLen * 1.5 * (aa2.y - bb2.y) / lineLen

        aa2 = newVector2(nextLine.aMax.x, nextLine.aMax.y)
        bb2 = newVector2(nextLine.bMax.x, nextLine.bMax.y)
        pPointRightMax = perpendicularPoint(aa2, bb2, pPointRightMin)


        if k != 0:
            segment.leftMin = pPointLeftMin
            segment.leftMax = pPointLeftMax
            segment.rightMin = pPointRightMin
            segment.rightMax = pPointRightMax

            segments.add(segment)
        else:
            segment.rightMin = pPointLeftMin
            segment.rightMax = pPointLeftMax

            segments.add(segment)

            var segm: tuple[leftMin: Vector2, leftMax: Vector2, rightMin: Vector2, rightMax: Vector2]

            segm.leftMin = pPointLeftMin
            segm.leftMax = pPointLeftMax
            segm.rightMin = pPointRightMin
            segm.rightMax = pPointRightMax

            segments.add(segm)

        if k == lines.len-2:
            var segm: tuple[leftMin: Vector2, leftMax: Vector2, rightMin: Vector2, rightMax: Vector2]

            segm.leftMin = pPointRightMin
            segm.leftMax = pPointRightMax
            segm.rightMin = newVector2(nextLine.bMin.x, nextLine.bMin.y)
            segm.rightMax = newVector2(nextLine.bMax.x, nextLine.bMax.y)

            segments.add(segm)

        inc k

    var iterr = 0
    while iterr < segments.len:

        var pPointLeftMin = segments[iterr].leftMin
        var pPointLeftMax = segments[iterr].leftMax
        var pPointRightMin = segments[iterr].rightMin
        var pPointRightMax = segments[iterr].rightMax

        # if iterr == 0:
        #     addVertexData(pPointLeftMin, pPointLeftMax, totalLen, result.vert)
        #     addIndexData(currIndex, result.ind)

        addVertexData(pPointLeftMin, pPointLeftMax, totalLen, result.vert)
        addIndexData(currIndex, result.ind)

        var intersectP3: Vector2
        if bHasInetersectPoint(pPointLeftMax, pPointLeftMin, pPointRightMax, pPointRightMin, intersectP3):

            let smallRadius = distance(intersectP3, pPointRightMax)
            let bigRadius =  wl.width*2.0 + smallRadius

            var innerLen = totalLen.GLfloat
            var outerLen = totalLen.GLfloat

            if intersectP3.y < pPointLeftMax.y:
                # UP
                var startRot = arccos((pPointLeftMax.x - intersectP3.x) / smallRadius)
                var endRot = arccos((pPointRightMax.x - intersectP3.x) / smallRadius)
                var step = (endRot - startRot) / wl.roundSteps

                while startRot >= endRot:

                    var smallX = intersectP3.x + smallRadius * cos(startRot)
                    var smallY = intersectP3.y + smallRadius * sin(startRot)
                    var bigX = intersectP3.x + bigRadius * cos(startRot)
                    var bigY = intersectP3.y + bigRadius * sin(startRot)
                    startRot += step

                    addVertexData(newVector2(bigX, bigY), newVector2(smallX, smallY), totalLen, result.vert)
                    addIndexData(currIndex, result.ind)
            else:
                # DOWN
                var startRot = arccos((intersectP3.x - pPointLeftMax.x) / smallRadius)
                var endRot = arccos((intersectP3.x - pPointRightMax.x) / smallRadius)
                var step = (endRot - startRot) / wl.roundSteps
                while startRot <= endRot:
                    let smallX = intersectP3.x - (smallRadius - wl.width*2.0) * cos(startRot)
                    let smallY = intersectP3.y - (smallRadius - wl.width*2.0) * sin(startRot)
                    let bigX = intersectP3.x - (bigRadius - wl.width*2.0) * cos(startRot)
                    let bigY = intersectP3.y - (bigRadius - wl.width*2.0) * sin(startRot)
                    startRot += step
                    addVertexData(newVector2(smallX, smallY), newVector2(bigX, bigY), totalLen, result.vert)
                    addIndexData(currIndex, result.ind)

        addVertexData(pPointRightMin, pPointRightMax, totalLen, result.vert)
        addIndexData(currIndex, result.ind)

        if dbg:
            emitDebugSolid(wl, "left_min_", pPointLeftMin)
            emitDebugSolid(wl, "left_max_", pPointLeftMax)
            emitDebugSolid(wl, "right_min_", pPointRightMin)
            emitDebugSolid(wl, "right_max_", pPointRightMax)

        iterr += 1

    var iter = 0
    while iter < result.vert.len:
        result.vert[iter+2] /= totalLen
        result.vert[iter+6] /= totalLen
        iter += POS_UV_ELEMENTS

var isWireframe = false
method draw*(wl: WinLineMermaid) =
    let c = currentContext()
    let gl = c.gl

    wl.iUniform = -1

    if wl.indexBuffer == invalidBuffer:
        wl.recreateBuffers()
    #     wl.indexBuffer = gl.createBuffer()
    #     gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, wl.indexBuffer)
    #     gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, (40000 * sizeof(GLushort)), gl.STREAM_DRAW)
    #     wl.vertexBuffer = gl.createBuffer()
    #     gl.bindBuffer(gl.ARRAY_BUFFER, wl.vertexBuffer)
    #     gl.bufferData(gl.ARRAY_BUFFER, (80000 * sizeof(GLfloat)), gl.STREAM_DRAW)
    # else:
    #     let data = wl.emitQuads()
    #     wl.numberOfIndexes = data.ind.len.GLsizei
    #     gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, wl.indexBuffer)
    #     gl.bufferSubData(gl.ELEMENT_ARRAY_BUFFER, 0.int32, data.ind)
    #     gl.bindBuffer(gl.ARRAY_BUFFER, wl.vertexBuffer)
    #     gl.bufferSubData(gl.ARRAY_BUFFER, 0.int32, data.vert)

    if WinLineMermaidShader == invalidProgram:
        WinLineMermaidShader = gl.newShaderProgram(vertexShader, fragmentShader, [(aPosition.GLuint, $aPosition), (aTexCoord.GLuint, $aTexCoord)])
        if WinLineMermaidShader == invalidProgram:
            return

    gl.bindBuffer(gl.ARRAY_BUFFER, wl.vertexBuffer)
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, wl.indexBuffer)

    gl.enableVertexAttribArray(aPosition.GLuint)
    gl.vertexAttribPointer(aPosition.GLuint, 2, gl.FLOAT, false, (4 * sizeof(GLfloat)).GLsizei, 0.int)
    gl.enableVertexAttribArray(aTexCoord.GLuint)
    gl.vertexAttribPointer(aTexCoord.GLuint, 2, gl.FLOAT, false, (4 * sizeof(GLfloat)).GLsizei, 2.int * sizeof(GLfloat))

    gl.useProgram(WinLineMermaidShader)

    let tiles = [wl.tiles.x.GLfloat, wl.tiles.y]
    gl.uniform2fv(gl.getUniformLocation("uTiles"), tiles)
    gl.uniformMatrix4fv(gl.getUniformLocation("mvpMatrix"), false, wl.node.sceneView.viewProjMatrix * wl.node.worldTransform())
    # gl.uniformMatrix4fv(gl.getUniformLocation("mvpMatrix"), false, wl.node.sceneView.viewProjMatrix)
    gl.uniform1f(gl.getUniformLocation("uAlpha"), c.alpha)

    if not wl.sprite.isNil and not wl.sprite.image.isNil and wl.sprite.image.isLoaded:
        var theQuad {.noinit.}: array[4, GLfloat]
        gl.activeTexture(GLenum(int(gl.TEXTURE0)))
        gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(wl.sprite.image, gl, theQuad))
        gl.uniform4fv(gl.getUniformLocation("uTexUnitCoords"), theQuad)
        gl.uniform1i(gl.getUniformLocation("texUnit"), 0.GLint)

    when not defined(ios) and not defined(android) and not defined(js) and not defined(emscripten):
        glPolygonMode(GL_FRONT_AND_BACK, if isWireframe: GL_LINE else: GL_FILL)

    gl.drawElements(gl.TRIANGLE_STRIP, wl.numberOfIndexes, gl.UNSIGNED_SHORT)

    when not defined(ios) and not defined(android) and not defined(js) and not defined(emscripten):
        glPolygonMode(GL_FRONT_AND_BACK, GL_FILL)

    gl.bindBuffer(gl.ARRAY_BUFFER, invalidBuffer)
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, invalidBuffer)


method visitProperties*(wl: WinLineMermaid, p: var PropertyVisitor) =

    template img(wl: WinLineMermaid): Image =
        if not wl.sprite.isNil:
            wl.sprite.image
        else:
            nil
    template `img=`(wl: WinLineMermaid, i: Image) =
        if not wl.sprite.isNil:
            wl.sprite.image = i
            recreateBuffers(wl)

    p.visitProperty("image", wl.img)
    p.visitProperty("width", wl.width)
    p.visitProperty("tiles", wl.tiles)
    p.visitProperty("roundSteps", wl.roundSteps)

    p.visitProperty("isWireframe", isWireframe)


    proc `rebuild=`(wl: WinLineMermaid, v: bool) =
        let data = wl.emitQuads(true)
    proc rebuild(wl: WinLineMermaid): bool =
        return false

    p.visitProperty("rebuild", wl.rebuild)
    p.visitProperty("density", wl.density)

proc newWinLineMermaid(): WinLineMermaid =
    new(result, cleanup)

proc creator(): RootRef =
    result = newWinLineMermaid()

registerComponent(WinLineMermaid, creator)
