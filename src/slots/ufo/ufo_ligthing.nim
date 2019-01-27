import
    nimx.context, nimx.portable_gl, nimx.types, rod.node, nimx.matrixes,
    nimx.composition, nimx.font, nimx.animation, random, math, algorithm,
    nimx.timer, rod.rod_types,
    rod.component, rod.component.text_component, rod.component.sprite, rod.viewport, nimx.image


const vertexShader = """
attribute vec4 aPosition;
attribute vec2 aTexCoord;
varying vec2 vUV;
uniform mat4 modelViewProjectionMatrix;
void main() {
    gl_Position = modelViewProjectionMatrix * vec4(aPosition.xyz, 1.0);
    vUV = aTexCoord;
}
"""
const fragmentShader = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif
uniform vec4 uColor;
uniform sampler2D uTexture;
uniform float uAlpha;
varying vec2 vUV;
void main() {
   gl_FragColor = vec4(uColor.rgb, texture2D(uTexture, vUV).a * uAlpha);
   //gl_FragColor = vec4(1.0,1.0,1.0,1.0);
}
"""
when defined(windows):
    import opengl
    var DEBUGLIDRAW = false

var SIMPLETRIANGULATION = false

proc togleLiDebug*()=
    when defined(windows):
        DEBUGLIDRAW = not DEBUGLIDRAW
    discard

proc togleLiTriangleMode*()=
    SIMPLETRIANGULATION = not SIMPLETRIANGULATION

var TEXTURE_GRADIENT : Image = nil

var lineShader: ProgramRef

type
    Attrib = enum
        aPosition
        aTexCoord
        # aAlpha

    LiSegment = ref object
        fromPoint, toPoint: Vector3
        topVertexes, bottomVertexes: seq[Vector3]
        allVertexes: seq[Vector3]

    Ligthing* = ref object of Component
        points: seq[Vector3]
        genPoints: seq[Vector3]

        segments: seq[LiSegment]

        color: Vector4
        target_color: Vector4
        start_color: Vector4
        generations: int
        width*: float
        drawsToFade: int
        drawCalls: int
        offset*: float

        vertexBufferRef: BufferRef
        indexBufferRef: BufferRef

        fromOffset: int32
        toOffset: int32

        vertexBuffer: seq[GLfloat]
        indexBuffer: seq[GLushort]
        textureUnit: Image

        curAlpha: float
        needReload: bool

proc initLigthingShader*(li:Ligthing, context:GraphicsContext)=
    let gl = context.gl

    if lineShader == invalidProgram:
        lineShader = gl.newShaderProgram(vertexShader, fragmentShader, [(Attrib.aPosition.GLuint, $aPosition)])
        if lineShader == invalidProgram:
            return

proc initBuffer*(li:Ligthing, context:GraphicsContext, bufferRef:var BufferRef, bufferType: GLenum, size: int) =
    let gl = context.gl

    if bufferRef == invalidBuffer:
        bufferRef = gl.createBuffer()
        gl.bindBuffer(bufferType, bufferRef)
        gl.bufferData(bufferType, (size * sizeof(GLfloat)).int32, gl.STREAM_DRAW)

proc reloadBuffer*(li:Ligthing, data:openarray[GLfloat]) =
    let c = currentContext()
    let gl = c.gl
    gl.bindBuffer(gl.ARRAY_BUFFER, li.vertexBufferRef)
    gl.bufferSubData(gl.ARRAY_BUFFER, 0, data)

proc randomFromMinus1To1(): float =
    result = rand(2.0) - 1.0

proc add*(s:var seq[GLfloat], v:Vector3)=
    s.add(v.x.GLfloat)
    s.add(v.y.GLfloat)
    s.add(0.GLfloat)

proc triangulate*(li: Ligthing)=
    var idx = 0
    var dir = newVector3(0,0,0)
    var p_index = 0

    proc incIndex(index:var int)=
        if li.points.len - 1> index:
            inc index

    var start_p = li.points[p_index]
    incIndex(p_index)
    var end_p = li.points[p_index]

    if not SIMPLETRIANGULATION:
        for i in 0..<li.genPoints.len:
            var
                bottom: Vector3
                top: Vector3

            dir = end_p - start_p
            dir.normalize()

            if li.genPoints[i] == end_p:
                start_p = li.points[p_index]
                incIndex(p_index)
                end_p = li.points[p_index]

            bottom = newVector3(-dir.y, dir.x, 0) * (li.width/2) + li.genPoints[i]
            top = newVector3(-dir.y, dir.x, 0) * (-li.width/2) + li.genPoints[i]

            var
                uu = i.float / (li.genPoints.len.float + 2)
                vv = 0.0

            li.vertexBuffer.add(top)
            li.vertexBuffer.add(uu.GLfloat)
            li.vertexBuffer.add(vv.GLfloat)

            vv = 1.0
            li.vertexBuffer.add(bottom)
            li.vertexBuffer.add(uu.GLfloat)
            li.vertexBuffer.add(vv.GLfloat)

            li.indexBuffer.add(idx.GLushort)
            inc idx

            li.indexBuffer.add(idx.GLushort)
            inc idx

    else:
        # for seg in li.segments:
        #     let tv = seg.topVertexes
        #     let bv = seg.bottomVertexes
        #     var ti = 0
        #     var bi = 0
        #     while true:
        #         if ti < tv.len:
        #             li.vertexBuffer.add(tv[ti])
        #             li.vertexBuffer.add((ti / tv.len).GLfloat)
        #             li.vertexBuffer.add(0.0.GLfloat)
        #             inc ti
        #             li.indexBuffer.add(idx.GLushort)
        #             inc idx
        #         if bi < bv.len:
        #             li.vertexBuffer.add(bv[bi])
        #             li.vertexBuffer.add((bi / bv.len).GLfloat)
        #             li.vertexBuffer.add(1.0.GLfloat)
        #             inc bi
        #             li.indexBuffer.add(idx.GLushort)
        #             inc idx
        #         if bi >= bv.len and ti >= tv.len:
        #             break

        var isTop = true
        p_index = 0
        start_p = li.genPoints[idx]
        end_p = li.genPoints[idx + 1]

        var topVertexes = newSeq[Vector3]()
        var bottomVertexes = newSeq[Vector3]()

        for i in 0..<li.genPoints.len:
            dir = end_p - start_p
            dir.normalize()

            if idx < li.genPoints.len - 2:
                start_p = li.genPoints[idx]
                end_p = li.genPoints[idx + 1]

            let vv = if isTop: 0.0 else: 1.0
            let uu = i.float / (li.genPoints.len.float + 2)
            let vertex = newVector3(-dir.y, dir.x, 0) * (if isTop: li.width/2 else: -li.width/2) + li.genPoints[i]

            if isTop:
                topVertexes.add(vertex)
            else:
                bottomVertexes.add(vertex)

            li.vertexBuffer.add(vertex)
            li.vertexBuffer.add(uu.GLfloat)
            li.vertexBuffer.add(vv.GLfloat)

            li.indexBuffer.add(idx.GLushort)
            inc idx

            isTop = not isTop

        # # let sortProc = proc(x, y: Vector3)=

        # # topVertexes.sort()

proc generateSegment(li:Ligthing, fromP, toP: Vector3, generations:int): LiSegment=
    result.new()
    result.fromPoint = fromP
    result.toPoint = toP
    result.topVertexes = @[]
    result.bottomVertexes = @[]
    result.allVertexes = @[]

    var tmpArr = newSeq[Vector3]()
    var vertexes = newSeq[Vector3]()
    vertexes.add(fromP)
    vertexes.add(toP)

    var offset = li.offset
    # var isTop = true
    let liWidth = li.width/2.0
    for generation in 0..<generations:
        tmpArr.setLen(0)
        tmpArr.add(vertexes[0])

        for i in 0..<vertexes.len - 1:
            let rnd_offset = randomFromMinus1To1() * offset
            var mid_point = (vertexes[i + 1] + vertexes[i]) * 0.5
            var direction = vertexes[i + 1] - vertexes[i]
            direction.normalize()
            let perp = newVector3(-direction.y, direction.x, 0)
            let perp_offset = perp * rnd_offset
            mid_point += perp_offset

            tmpArr.add(mid_point)
            tmpArr.add(vertexes[i + 1])

            # if not SIMPLETRIANGULATION:
            #     result.topVertexes.add(perp * liWidth + mid_point)
            #     result.bottomVertexes.add(perp * -liWidth + mid_point)
            # else:
            #     if isTop:
            #         result.topVertexes.add(perp * liWidth + mid_point)
            #     else:
            #         result.bottomVertexes.add(perp * -liWidth + mid_point)
            #     isTop = not isTop

        offset /= 2
        vertexes = tmpArr

    result.allVertexes = vertexes

proc generate*(li: Ligthing)=
    li.vertexBuffer.setLen(0)
    li.indexBuffer.setLen(0)
    li.genPoints.setLen(0)
    li.segments.setLen(0)

    for i in 0..<li.points.len - 1:
        let seg = li.generateSegment(li.points[i], li.points[i + 1], li.generations)
        li.segments.add(seg)

        li.genPoints.add(seg.allVertexes)

    # li.genPoints.add(li.points)

    # var offset = li.offset

    # for generation in 0..<li.generations:
    #     var tmp_arr = newSeq[Vector3]()
    #     tmp_arr.add(li.genPoints[0])

    #     for i in 0..<li.genPoints.len - 1:
    #         var start_p = li.genPoints[i]
    #         var end_p = li.genPoints[i + 1]
    #         var rnd_offset = randomFromMinus1To1() * offset
    #         var mid_point = (end_p + start_p) * 0.5
    #         var mid_normalized = end_p - start_p
    #         mid_normalized.normalize()
    #         var perp = newVector3(-mid_normalized.y, mid_normalized.x, 0)
    #         var mid_offset = perp * rnd_offset
    #         mid_point += mid_offset

    #         tmp_arr.add(mid_point)
    #         tmp_arr.add(end_p)
    #     offset /= 2
    #     li.genPoints = tmp_arr

proc shoot*(li:Ligthing) =
    li.generate()
    li.triangulate()
    li.needReload = true

proc initIndexBuffer(li:Ligthing) =
    if li.indexBufferRef == invalidBuffer:
        var context = currentContext()
        var gl = context.gl

        li.initBuffer(context, li.indexBufferRef, gl.ELEMENT_ARRAY_BUFFER, li.indexBuffer.len)
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, li.indexBufferRef)
        gl.bufferSubData(gl.ELEMENT_ARRAY_BUFFER, 0, li.indexBuffer)

method draw*(li: Ligthing) =
    if li.curAlpha <= 0.0: return
    let c = currentContext()
    let gl = c.gl

    li.initLigthingShader(c)
    li.initIndexBuffer()
    li.initBuffer(c, li.vertexBufferRef, gl.ARRAY_BUFFER, li.vertexBuffer.len)

    if li.needReload:
        li.reloadBuffer(li.vertexBuffer)
        li.needReload = false
    else:
        gl.bindBuffer(gl.ARRAY_BUFFER, li.vertexBufferRef)

    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, li.indexBufferRef)

    gl.enableVertexAttribArray(aPosition.GLuint)
    gl.vertexAttribPointer(aPosition.GLuint, 3.GLint, gl.FLOAT, false, (5 * sizeof(GLfloat)).GLsizei , 0)

    gl.enableVertexAttribArray(aTexCoord.GLuint)
    gl.vertexAttribPointer(aTexCoord.GLuint, 2.GLint, gl.FLOAT, false, (5 * sizeof(GLfloat)).GLsizei , 3 * sizeof(GLfloat))

    gl.useProgram(lineShader)

    gl.enable(gl.BLEND)
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE)

    gl.uniform4fv(gl.getUniformLocation(lineShader, "uColor"), li.color)
    c.setTransformUniform(lineShader)

    var theQuad {.noinit.}: array[4, GLfloat]
    gl.activeTexture(gl.TEXTURE0)
    gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(li.textureUnit, gl, theQuad))
    gl.uniform1i(gl.getUniformLocation(lineShader, "uTexture"), 0.GLint)

    gl.uniform1f(gl.getUniformLocation(lineShader, "uAlpha"), (li.node.alpha * li.curAlpha).GLfloat )

    when defined(windows):
        if DEBUGLIDRAW:
            glPolygonMode(GL_FRONT_AND_BACK, GL_LINE)
        else:
            glPolygonMode(GL_FRONT_AND_BACK, GL_FILL)

    gl.drawElements(gl.TRIANGLE_STRIP , li.toOffset.GLsizei, gl.UNSIGNED_SHORT)

    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, invalidBuffer)
    gl.bindBuffer(gl.ARRAY_BUFFER, invalidBuffer)

    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

method init*(li: Ligthing) =
    procCall li.Component.init()
    li.color = newVector4(0.2, 1.0, 1.0, 1)
    li.generations = 0
    li.vertexBuffer = @[]
    li.indexBuffer = @[]
    li.genPoints = @[]
    li.segments = @[]
    li.width = 50
    li.offset = 50

proc initLigthing*(li: Ligthing, points: seq[Vector3], color, target_color: Vector4, generations: int = 5) =
    doAssert( points.len > 2)
    li.points = points
    li.start_color = color
    li.color = color
    li.target_color = target_color
    li.generations = generations
    li.shoot()
    if TEXTURE_GRADIENT.isNil:
        TEXTURE_GRADIENT =  imageWithResource("slots/ufo_slot/slot/scene/resources/gradient128.png")
    li.textureUnit = TEXTURE_GRADIENT

proc animation*(li: Ligthing): Animation =
    li.shoot()

    result = newAnimation()
    result.tag = "ligthning"
    result.loopDuration = 1.0
    result.numberOfLoops = 1
    result.onAnimate = proc(p: float)=
        li.shoot()
        # li.curAlpha = 1.0
        li.curAlpha = if p < 0.5: interpolate(0.0, 2.0, elasticEaseOut(p * 2, 0.74))
                            else: interpolate(2.0, 0.0, quadEaseOut((p - 0.5) * 2))
        li.fromOffset = interpolate(0.int32, li.indexBuffer.len.int32, p)
        if li.toOffset < li.indexBuffer.len:
            li.toOffset = min(interpolate(0, li.indexBuffer.len, p*2).int32, li.indexBuffer.len.int32)
        else:
            li.toOffset = li.indexBuffer.len.int32
            li.fromOffset = interpolate(li.indexBuffer.len, 0, p*2).int32
        # interpolate(0, li.indexBuffer.len, p)
        li.color = interpolate(li.start_color, li.target_color, p)

registerComponent(Ligthing)
