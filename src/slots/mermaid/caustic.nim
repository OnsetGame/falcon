import streams
import tables
import math
import times
import opengl

import nimx.types
import nimx.context
import nimx.portable_gl
import nimx.view
import nimx.image
import nimx.render_to_image

import rod.node
import rod.viewport
import rod.component
import rod.component.camera
import nimx.property_visitor

type Attrib = enum
    aPosition
    aTexCoord

type Caustic* = ref object of Component
    postMap: SelfContainedImage
    shader: ProgramRef
    vbo, ibo: BufferRef

    resolution: Vector4
    fixedSize*: bool

    time: float64
    accumTime: float64

let vertexShaderPost = """
attribute vec4 aPosition;
attribute vec2 aTexCoord;

varying vec2 vTexCoord;

void main() {
    gl_Position = vec4(aPosition.xyz, 1.0);
    vTexCoord = aTexCoord;
}
"""

let fragmentShader = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif

uniform sampler2D texUnit;
uniform vec4 uTexUnitCoords;

uniform vec4 uResolution;
uniform float uTime;

varying vec2 vTexCoord;

vec2 uvs() {
    vec2 texelSize = vec2(1.0/uResolution.x, 1.0/uResolution.y);
    vec2 screenTexCoords = gl_FragCoord.xy * texelSize;
    return uTexUnitCoords.xy + (uTexUnitCoords.zw - uTexUnitCoords.xy) * screenTexCoords;
}

float sinn(float x) {
    return sin(x)/2.0+0.5;
}

float causticPatternFn(vec2 pos) {
    return (sin(pos.x*40.0+uTime)
        +pow(sin(-pos.x*130.0+uTime),1.0)
        +pow(sin(pos.x*30.0+uTime),2.0)
        +pow(sin(pos.x*50.0+uTime),2.0)
        +pow(sin(pos.x*80.0+uTime),2.0)
        +pow(sin(pos.x*90.0+uTime),2.0)
        +pow(sin(pos.x*12.0+uTime),2.0)
        +pow(sin(pos.x*6.0+uTime),2.0)
        +pow(sin(-pos.x*13.0+uTime),5.0))/2.0;
}

vec2 causticDistortDomainFn(vec2 pos) {
    pos.x*=(pos.y*0.20+0.5);
    pos.x*=1.0+cos(uTime/1.0)/10.0;
    return pos;
}

void main() {
    vec2 pos = gl_FragCoord.xy/uResolution.xy - vec2(0.5,0.5);
    vec2  causticDistortedDomain = causticDistortDomainFn(pos);
    float causticShape = clamp(7.0-length(causticDistortedDomain.x*20.0),0.0,1.0);
    float causticPattern = causticPatternFn(causticDistortedDomain);
    float caustic = causticShape * causticPattern;
    caustic *= (pos.y+0.5)/4.0;
    float f = length(pos+vec2(-0.5,0.5))*length(pos+vec2(0.5,0.5))*(1.0+caustic)/1.0;

    vec3 texel = texture2D(texUnit, uvs()).xyz;
    vec3 cau = vec3(0.1,0.5,0.6)*f;

    gl_FragColor = vec4( mix(cau+texel, texel, 0.4), 1.0);
}
"""

proc checkResolution*(lc: Caustic) =
    let vp = lc.node.sceneView
    let currWidth = vp.bounds.width
    let currHeight = vp.bounds.height

    if currWidth != lc.resolution[0] or currHeight != lc.resolution[1]:
        lc.resolution = newVector4(currWidth, currHeight, 0.0, 0.0)
        if not lc.postMap.isNil and not lc.fixedSize:
            let gl = currentContext().gl
            gl.deleteFramebuffer(lc.postMap.framebuffer)
            gl.deleteTexture(lc.postMap.texture)
            lc.postMap.framebuffer = invalidFrameBuffer
            lc.postMap.texture = invalidTexture
            lc.postMap = nil

        if lc.postMap.isNil:
            lc.postMap = imageWithSize(newSize(lc.resolution[0], lc.resolution[1]))

        lc.resolution[0] = currWidth
        lc.resolution[1] = currHeight
        lc.resolution[2] = 0.0
        lc.resolution[3] = 0.0

proc createAndSetup(bc: Caustic) =
    let gl = currentContext().gl

    if bc.shader == invalidProgram:
        bc.shader = gl.newShaderProgram(vertexShaderPost, fragmentShader, [(aPosition.GLuint, $aPosition), (aTexCoord.GLuint, $aTexCoord)])

    if bc.vbo == invalidBuffer:
        let width = 1.GLfloat
        let height = 1.GLfloat
        let vertexData = [
            -width,  height, 0.0, 0.0, 1.0,
            -width, -height, 0.0, 0.0, 0.0,
             width, -height, 0.0, 1.0, 0.0,
             width,  height, 0.0, 1.0, 1.0
        ]
        bc.vbo = gl.createBuffer()
        gl.bindBuffer(gl.ARRAY_BUFFER, bc.vbo)
        gl.bufferData(gl.ARRAY_BUFFER, vertexData, gl.STATIC_DRAW)

    if bc.ibo == invalidBuffer:
        let indexData = [0.GLushort, 1, 2, 2, 3, 0]
        bc.ibo = gl.createBuffer()
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, bc.ibo)
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indexData, gl.STATIC_DRAW)

method init*(bc: Caustic) =
    procCall bc.Component.init()
    bc.time = epochTime()
    bc.shader = invalidProgram

method draw*(bc: Caustic) =
    let vp = bc.node.sceneView
    let c = currentContext()
    let gl = c.gl

    bc.checkResolution()

    bc.createAndSetup()

    let mvp = vp.getViewProjectionMatrix() * bc.node.worldTransform()
    bc.postMap.flipVertically()
    bc.postMap.draw proc() =
        c.withTransform mvp:
            for n in bc.node.children: n.recursiveDraw()

    gl.useProgram(bc.shader)
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, bc.ibo)
    gl.bindBuffer(gl.ARRAY_BUFFER, bc.vbo)
    var offset: int = 0
    gl.enableVertexAttribArray(aPosition.GLuint)
    gl.vertexAttribPointer(aPosition.GLuint, 3, gl.FLOAT, false, (5 * sizeof(GLfloat)).GLsizei, offset)
    offset += 3 * sizeof(GLfloat)
    gl.enableVertexAttribArray(aTexCoord.GLuint)
    gl.vertexAttribPointer(aTexCoord.GLuint, 2, gl.FLOAT, false, (5 * sizeof(GLfloat)).GLsizei, offset)

    var theQuad {.noinit.}: array[4, GLfloat]

    gl.activeTexture(GLenum(int(gl.TEXTURE0)))
    gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(bc.postMap, gl, theQuad))
    gl.uniform4fv(gl.getUniformLocation(bc.shader, "uTexUnitCoords"), theQuad)
    gl.uniform1i(gl.getUniformLocation(bc.shader, "texUnit"), 0.GLint)

    gl.uniform4fv(gl.getUniformLocation(bc.shader, "uResolution"), bc.resolution)
    let epTime = epochTime().float64
    bc.time = epTime - bc.time
    bc.accumTime = bc.accumTime + bc.time
    gl.uniform1f(gl.getUniformLocation(bc.shader, "uTime"), bc.accumTime)
    bc.time = epTime

    gl.drawElements(gl.TRIANGLES, 6, gl.UNSIGNED_SHORT)
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, invalidBuffer)
    gl.bindBuffer(gl.ARRAY_BUFFER, invalidBuffer)
    gl.useProgram(invalidProgram)

method isPosteffectComponent*(bc: Caustic): bool = true

registerComponent(Caustic)
