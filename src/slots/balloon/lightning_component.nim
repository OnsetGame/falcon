import streams, tables, math

import nimx / [ types, context, portable_gl, matrixes, view, image ]
import rod / [ node, viewport, component, postprocess_context, property_visitor ]
import rod / component / [ camera, mesh_component, material ]

import rtd

type Attrib = enum
    aPosition
    aTexCoord

type LightningComponent* = ref object of Component
    depthMap: SelfContainedImage
    postMap: SelfContainedImage

    depthShader: ProgramRef
    postShader: ProgramRef

    resolution: Vector4
    fixedSize*: bool

    vbo, ibo: BufferRef

    postProc: proc(c: Component)

    camDistance: float32

    ocluderNode: Node
    lookAtNode: Node

let vertexShaderDepth = """
attribute vec4 aPosition;
attribute vec2 aTexCoord;

uniform mat4 modelViewProjectionMatrix;
uniform float uCamDistance;

varying float zDepth;

varying vec2 vTexCoord;

void main() {
    gl_Position = modelViewProjectionMatrix * vec4(aPosition.xyz, 1.0);
    zDepth = gl_Position.z / uCamDistance;
    vTexCoord = aTexCoord;
}
"""
let fragmentShaderDepth = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif
varying float zDepth;
void main() {
    gl_FragColor = vec4(gl_FragCoord.z, gl_FragCoord.z, gl_FragCoord.z, 1.0);
}
"""

let fragmentShaderAlphaDepth = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif

uniform float mipBias;

uniform float uMaterialTransparency;

uniform sampler2D maskMapUnit;
uniform vec4 uMaskUnitCoords;
uniform float uMaskPercent;

uniform sampler2D texUnit;
uniform vec4 uTexUnitCoords;
uniform float uTexUnitPercent;

varying vec2 vTexCoord;

varying float zDepth;
void main() {

    float mask = texture2D(maskMapUnit, uMaskUnitCoords.xy + (uMaskUnitCoords.zw - uMaskUnitCoords.xy) * vTexCoord, mipBias).a * uMaskPercent;

    if ( mask < 0.001) {
        discard;
    }

    float diffTextureTexel = texture2D(texUnit, uTexUnitCoords.xy + (uTexUnitCoords.zw - uTexUnitCoords.xy) * vTexCoord, mipBias).a * uTexUnitPercent;

    float invDepth = gl_FragCoord.z;

    gl_FragColor = vec4(invDepth, invDepth, invDepth, diffTextureTexel * uMaterialTransparency);
}
"""

let vertexShaderPost = """
attribute vec4 aPosition;
attribute vec2 aTexCoord;

varying vec2 vTexCoord;

void main() {
    gl_Position = vec4(aPosition.xyz, 1.0);
    vTexCoord = aTexCoord;
}
"""
# let fragmentShaderPost = """
# #ifdef GL_ES
# #extension GL_OES_standard_derivatives : enable
# precision mediump float;
# #endif
# uniform sampler2D depthUnit;
# uniform vec4 uDepthUnitCoords;
# uniform sampler2D texUnit;
# uniform vec4 uTexUnitCoords;
# uniform vec4 uResolution;
# vec4 blur9(sampler2D image, vec2 uv, vec2 resolution, vec2 direction) {
#   vec4 color = vec4(0.0);
#   vec2 off1 = vec2(1.3846153846) * direction;
#   vec2 off2 = vec2(3.2307692308) * direction;
#   color += texture2D(image, uv) * 0.2270270270;
#   color += texture2D(image, uv + (off1 / resolution)) * 0.3162162162;
#   color += texture2D(image, uv - (off1 / resolution)) * 0.3162162162;
#   color += texture2D(image, uv + (off2 / resolution)) * 0.0702702703;
#   color += texture2D(image, uv - (off2 / resolution)) * 0.0702702703;
#   return color;
# }
# // gl_FragColor = blur9(texUnit, uTexUnitCoords.xy + (uTexUnitCoords.zw - uTexUnitCoords.xy) * screenTexCoords, uResolution.xy, vec2(1.0,1.0));
# vec4 bloom(sampler2D image, vec2 uv, vec2 texelSize) {
#     // Larger constant = bigger glow
#     float glow = 4.0 * ((texelSize.x + texelSize.y) / 2.0);
#     vec4 bloom = vec4(0.0,0.0,0.0,0.0);
#     int count = 0;
#     for(float x = uv.x - glow; x < uv.x + glow; x += texelSize.x) {
#         for(float y = uv.y - glow; y < uv.y + glow; y += texelSize.y) {
#             bloom += (texture2D(image, vec2(x, y)) - 0.4) * 30.0;
#             count++;
#         }
#     }
#     return texture2D(image, uv) + clamp(bloom / (count * 30), 0.0, 1.0);
# }
# // gl_FragColor = bloom(texUnit, uTexUnitCoords.xy + (uTexUnitCoords.zw - uTexUnitCoords.xy) * screenTexCoords, texelSize);

# void main() {
#     vec2 texelSize = vec2(1.0/uResolution.x, 1.0/uResolution.y);
#     vec2 screenTexCoords = gl_FragCoord.xy * texelSize;
#     vec4 depthTexel = texture2D(depthUnit, uDepthUnitCoords.xy + (uDepthUnitCoords.zw - uDepthUnitCoords.xy) * screenTexCoords);
#     // vec4 colorTexel = texture2D(texUnit, uTexUnitCoords.xy + (uTexUnitCoords.zw - uTexUnitCoords.xy) * screenTexCoords);
#     gl_FragColor = depthTexel;
# }
# """

# let fragmentShaderPost = """
# #ifdef GL_ES
# #extension GL_OES_standard_derivatives : enable
# precision mediump float;
# #endif
# uniform sampler2D depthUnit;
# uniform vec4 uDepthUnitCoords;
# uniform sampler2D texUnit;
# uniform vec4 uTexUnitCoords;
# uniform vec4 uResolution;
# uniform float uFocus;
# varying vec2 vTexCoord;
# float radius = 10.0;
# float amount = 100.0;
# float aperture = 0.1;
# #define ITERATIONS 15.0
# #define ONEOVER_ITR  1.0 / ITERATIONS
# #define PI 3.141596
# #define GOLDEN_ANGLE 2.39996323
# vec2 Sample(in float theta, inout float r) {
#     r += 1.0 / r;
#     return (r-1.0) * vec2(cos(theta), sin(theta)) * .06;
# }
# vec3 Bokeh(sampler2D tex, vec2 uv, float radius, float amount) {
#     vec3 acc = vec3(0.0);
#     vec3 div = vec3(0.0);
#     vec2 pixel = vec2(uResolution.y/uResolution.x, 1.0) * radius * .025;
#     float r = 1.0;
#     for (float j = 0.0; j < GOLDEN_ANGLE * ITERATIONS; j += GOLDEN_ANGLE) {
#         vec3 col = texture2D(tex, uv + pixel * Sample(j, r)).xyz;
#         vec3 bokeh = vec3(.5) + pow(col, vec3(10.0)) * amount;
#         acc += col * bokeh;
#         div += bokeh;
#     }
#     return acc / div;
# }
# float sampleBias( vec2 uv ) {
#     float d = abs( 1.0 - texture2D( depthUnit, uv ).r - uFocus );
#     return d * aperture; //min( d * aperture, .005 );
# }
# void main() {
#     vec2 texelSize = vec2(1.0/uResolution.x, 1.0/uResolution.y);
#     vec2 screenTexCoords = gl_FragCoord.xy * texelSize;
#     vec2 uv = uTexUnitCoords.xy + (uTexUnitCoords.zw - uTexUnitCoords.xy) * screenTexCoords;
#     float bias = sampleBias( uTexUnitCoords.xy + (uTexUnitCoords.zw - uTexUnitCoords.xy) * vTexCoord );
#     gl_FragColor = vec4(Bokeh(texUnit, uv, radius * bias, amount ), 1.0);
# }
# """

# let fragmentShaderPost = """
# #ifdef GL_ES
# #extension GL_OES_standard_derivatives : enable
# precision mediump float;
# #endif

# uniform sampler2D depthUnit;
# uniform vec4 uDepthUnitCoords;

# uniform sampler2D texUnit;
# uniform vec4 uTexUnitCoords;

# uniform vec4 uResolution;

# uniform float uFocus;

# varying vec2 vTexCoord;

# uniform float decay;
# uniform float exposure;
# uniform float density;
# uniform float weight;

# vec2 uv() {
#     vec2 texelSize = vec2(1.0/uResolution.x, 1.0/uResolution.y);
#     vec2 screenTexCoords = gl_FragCoord.xy * texelSize;
#     return uTexUnitCoords.xy + (uTexUnitCoords.zw - uTexUnitCoords.xy) * screenTexCoords;
# }

# vec4 pixelMain(vec2 texCoord) {
#     const int NUM_SAMPLES = 16;

#     vec2 lightPositionOnScreen = uResolution.zw;
#     vec2 tc = texCoord;
#     vec2 deltaTexCoord = (tc - lightPositionOnScreen.xy);
#     deltaTexCoord *= 1.0 / float(NUM_SAMPLES) * density;

#     float illuminationDecay = 1.0;
#     vec4 color = texture2D(depthUnit, tc)*0.4;

#     for(int i=0; i < NUM_SAMPLES ; i++) {
#         tc -= deltaTexCoord;
#         vec4 sample = texture2D(depthUnit, tc)*0.4;
#         sample *= illuminationDecay * weight;
#         color += sample;
#         illuminationDecay *= decay;
#     }
#     vec4 realColor = texture2D(texUnit, texCoord);
#     return ((vec4((vec3(color.r,color.g,color.b) * exposure),1.0))+(realColor*(1.1)));
# }

# void main() {
#     gl_FragColor = pixelMain(uv());
# }
# """

let fragmentShaderPost = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif

uniform sampler2D depthUnit;
uniform vec4 uDepthUnitCoords;

uniform sampler2D texUnit;
uniform vec4 uTexUnitCoords;

uniform vec4 uResolution;

varying vec2 vTexCoord;

vec2 uv() {
    vec2 texelSize = vec2(1.0/uResolution.x, 1.0/uResolution.y);
    vec2 screenTexCoords = gl_FragCoord.xy * texelSize;
    return uTexUnitCoords.xy + (uTexUnitCoords.zw - uTexUnitCoords.xy) * screenTexCoords;
}

void main() {
    gl_FragColor = texture2D(texUnit, uv());;
}
"""


var decay: float32 = 0.99
var exposure: float32 = 0.99
var density: float32 = 0.4
var weight: float32 = 0.1
var lightPosX: float = 0.5
var lightPosY: float = 0.5
var camDistance: float32 = 8000.0

var mipBias: float32 = -1000.0

var depthDebugShader: ProgramRef
var colorDebugShader: ProgramRef

var depthAlphaShader: ProgramRef

var bShowDepthMap: bool
var bShowColorMap: bool

let fragmentShaderPostDepthMap = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif
uniform sampler2D depthUnit;
uniform vec4 uDepthUnitCoords;
uniform vec4 uResolution;
varying vec2 vTexCoord;
void main() {
    gl_FragColor = texture2D(depthUnit, uDepthUnitCoords.xy + (uDepthUnitCoords.zw - uDepthUnitCoords.xy) * gl_FragCoord.xy * vec2(1.0/uResolution.x, 1.0/uResolution.y));
}
"""
let fragmentShaderPostColorMap = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif
uniform sampler2D texUnit;
uniform vec4 uTexUnitCoords;
uniform vec4 uResolution;
varying vec2 vTexCoord;
void main() {
    gl_FragColor = texture2D(texUnit, uTexUnitCoords.xy + (uTexUnitCoords.zw - uTexUnitCoords.xy) * gl_FragCoord.xy * vec2(1.0/uResolution.x, 1.0/uResolution.y));
}
"""

proc checkResolution*(lc: LightningComponent) =
    let vp = lc.node.sceneView
    let currWidth = vp.bounds.width
    let currHeight = vp.bounds.height

    if currWidth != lc.resolution[0] or currHeight != lc.resolution[1]:
        lc.resolution = newVector4(currWidth, currHeight, 0.0)

        if not lc.depthMap.isNil and not lc.fixedSize:
            let c = currentContext()
            let gl = c.gl
            gl.deleteFramebuffer(lc.depthMap.framebuffer)
            gl.deleteTexture(lc.depthMap.texture)
            lc.depthMap.framebuffer = invalidFrameBuffer
            lc.depthMap.texture = invalidTexture
            lc.depthMap = nil

        if lc.depthMap.isNil:
            lc.depthMap = imageWithSize(newSize(lc.resolution[0], lc.resolution[1]))

        if not lc.postMap.isNil and not lc.fixedSize:
            let c = currentContext()
            let gl = c.gl
            gl.deleteFramebuffer(lc.postMap.framebuffer)
            gl.deleteTexture(lc.postMap.texture)
            lc.postMap.framebuffer = invalidFrameBuffer
            lc.postMap.texture = invalidTexture
            lc.postMap = nil

        if lc.postMap.isNil:
            lc.postMap = imageWithSize(newSize(lc.resolution[0], lc.resolution[1]))

        lc.resolution[0] = currWidth
        lc.resolution[1] = currHeight
        lc.resolution[2] = lightPosX
        lc.resolution[3] = lightPosY

proc createAndSetup(bc: LightningComponent) =
    let c = currentContext()
    let gl = c.gl

    if bc.depthShader == invalidProgram:
        bc.depthShader = c.gl.newShaderProgram(vertexShaderDepth, fragmentShaderDepth, [(aPosition.GLuint, $aPosition), (aTexCoord.GLuint, $aTexCoord)])
    if bc.postShader == invalidProgram:
        bc.postShader = c.gl.newShaderProgram(vertexShaderPost, fragmentShaderPost, [(aPosition.GLuint, $aPosition), (aTexCoord.GLuint, $aTexCoord)])

    if depthAlphaShader == invalidProgram:
        depthAlphaShader = c.gl.newShaderProgram(vertexShaderDepth, fragmentShaderAlphaDepth, [(aPosition.GLuint, $aPosition), (aTexCoord.GLuint, $aTexCoord)])

    if depthDebugShader == invalidProgram:
        depthDebugShader = c.gl.newShaderProgram(vertexShaderPost, fragmentShaderPostDepthMap, [(aPosition.GLuint, $aPosition), (aTexCoord.GLuint, $aTexCoord)])
    if colorDebugShader == invalidProgram:
        colorDebugShader = c.gl.newShaderProgram(vertexShaderPost, fragmentShaderPostColorMap, [(aPosition.GLuint, $aPosition), (aTexCoord.GLuint, $aTexCoord)])

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

    if bc.node.sceneView.postprocessContext.isNil:
        bc.node.sceneView.postprocessContext = newPostprocessContext()

    bc.node.sceneView.postprocessContext.drawProc = bc.postProc

    if bc.ocluderNode.isNil:
        bc.ocluderNode = bc.node.sceneView.camera.node

method init*(bc: LightningComponent) =
    procCall bc.Component.init()
    bc.camDistance = camDistance
    bc.resolution[2] = lightPosX
    bc.resolution[3] = lightPosY

    bc.postProc = proc(c: Component) =
        let m = c.node.componentIfAvailable(MeshComponent)
        if not m.isNil:
            let postprocShader = m.node.sceneView.postprocessContext.shader

            if m.material.shader == invalidProgram or m.material.bShaderNeedUpdate:
                m.setupAndDraw()
                m.material.bShaderNeedUpdate = false
            let oldShader = m.material.shader

            if postprocShader != invalidProgram:
                m.material.shader = postprocShader

            currentContext().gl.useProgram(m.material.shader)
            m.setupAndDraw()
            m.material.shader = oldShader

proc recursiveDrawDepth(n: Node) =
    if n.alpha < 0.0000001: return
    let c = currentContext()
    var tr = c.transform
    let oldAlpha = c.alpha
    c.alpha *= n.alpha
    n.getTransform(tr)
    c.withTransform tr:
        var hasPosteffectComponent = false
        if not n.components.isNil:
            let mc = n.component(MeshComponent)
            if not mc.isNil:

                let oldShader = mc.node.sceneView.postprocessContext.shader

                if not mc.material.maskTexture.isNil or mc.material.blendEnable:
                    mc.node.sceneView.postprocessContext.shader = depthAlphaShader

                mc.draw()

                mc.node.sceneView.postprocessContext.shader = oldShader

                hasPosteffectComponent = hasPosteffectComponent or mc.isPosteffectComponent()
        if not hasPosteffectComponent:
            for c in n.children: c.recursiveDrawDepth()
    c.alpha = oldAlpha

var bFreze: bool = false
var viewMatrix: Matrix4
var projMatrix: Matrix4

method draw*(bc: LightningComponent) =
    let vp = bc.node.sceneView
    let c = currentContext()
    let gl = c.gl

    bc.checkResolution()

    bc.createAndSetup()

    # var distance: float32 = 0.0

    if not bFreze:
        if bc.lookAtNode.isNil:
            viewMatrix.loadIdentity()
            viewMatrix = bc.ocluderNode.worldTransform.inversed
            # distance = vp.camera.zFar
        else:
            let ocluderWP = bc.ocluderNode.worldPos
            let lookAtWP = bc.lookAtNode.worldPos
            viewMatrix.loadIdentity()
            viewMatrix.lookAt(eye = ocluderWP, center = lookAtWP, up = newVector3(0,1,0))
            viewMatrix[12] = ocluderWP[0]
            viewMatrix[13] = ocluderWP[1]
            viewMatrix[14] = ocluderWP[2]
            viewMatrix.inverse()
            # distance = sqrt(pow(lookAtWP[0] - ocluderWP[0], 2)+pow(lookAtWP[1] - ocluderWP[1], 2)+pow(lookAtWP[2] - ocluderWP[2], 2)) * 2.0

        projMatrix.loadIdentity()
        projMatrix.ortho(-bc.resolution[0]/20, bc.resolution[0]/20, -bc.resolution[1]/20, bc.resolution[1]/20, vp.camera.zNear, bc.camDistance)
        # projMatrix.perspective(vp.camera.fov, bc.resolution[0] / bc.resolution[1], vp.camera.zNear, bc.camDistance)

    var vpMatrix = projMatrix * viewMatrix

    var depthMatrix: Matrix4
    depthMatrix[0] = 0.5
    depthMatrix[1] = 0.0
    depthMatrix[2] = 0.0
    depthMatrix[3] = 0.0
    depthMatrix[4] = 0.0
    depthMatrix[5] = 0.5
    depthMatrix[6] = 0.0
    depthMatrix[7] = 0.0
    depthMatrix[8] = 0.0
    depthMatrix[9] = 0.0
    depthMatrix[10] = 0.5
    depthMatrix[11] = 0.0
    depthMatrix[12] = 0.5
    depthMatrix[13] = 0.5
    depthMatrix[14] = 0.5
    depthMatrix[15] = 1.0

    var mvpMatrix: Matrix4
    var cameraViewMatrix = vp.camera.node.worldTransform.inversed
    var cameraProjMatrix: Matrix4
    cameraProjMatrix.perspective(vp.camera.fov, vp.bounds.width / vp.bounds.height, vp.camera.zNear, vp.camera.zFar)
    mvpMatrix = cameraProjMatrix * cameraViewMatrix


    depthMatrix = depthMatrix * vpMatrix


    if bc.depthShader != invalidProgram:
        bc.node.sceneView.postprocessContext.shader = bc.depthShader # bind
        gl.useProgram(bc.depthShader)

        gl.uniform1f(gl.getUniformLocation(bc.depthShader, "uCamDistance"), bc.camDistance)
        gl.uniform1f(gl.getUniformLocation(bc.depthShader, "mipBias"), mipBias)

        bc.depthMap.flipVertically()
        bc.depthMap.draw proc() =
            c.withTransform vpMatrix:
                # gl.enable(gl.CULL_FACE)
                # gl.cullFace(gl.FRONT)
                for n in bc.node.children: n.recursiveDrawDepth()

        bc.node.sceneView.postprocessContext.shader = invalidProgram # release
        gl.useProgram(invalidProgram)

        bc.node.sceneView.postprocessContext.depthImage = bc.depthMap
        bc.node.sceneView.postprocessContext.depthMatrix = depthMatrix

        # bc.postMap.flipVertically()
        # bc.postMap.draw proc() =
        #     c.withTransform vpMatrix:
        #         for n in bc.node.children: n.recursiveDraw()

    # if bc.postShader == invalidProgram:
    #     return

    # var bcpShader = bc.postShader

    # if bShowDepthMap:
    #     bc.postShader = depthDebugShader
    # if bShowColorMap:
    #     bc.postShader = colorDebugShader

    # gl.useProgram(bc.postShader)
    # gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, bc.ibo)
    # gl.bindBuffer(gl.ARRAY_BUFFER, bc.vbo)
    # var offset: int = 0
    # gl.enableVertexAttribArray(aPosition.GLuint)
    # gl.vertexAttribPointer(aPosition.GLuint, 3, gl.FLOAT, false, (5 * sizeof(GLfloat)).GLsizei, offset)
    # offset += 3 * sizeof(GLfloat)
    # gl.enableVertexAttribArray(aTexCoord.GLuint)
    # gl.vertexAttribPointer(aTexCoord.GLuint, 2, gl.FLOAT, false, (5 * sizeof(GLfloat)).GLsizei, offset)

    # var theQuad {.noinit.}: array[4, GLfloat]
    # var textureIndex : GLint = 0
    # gl.activeTexture(GLenum(int(gl.TEXTURE0) + textureIndex))
    # gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(bc.depthMap, gl, theQuad))
    # gl.uniform4fv(gl.getUniformLocation(bc.postShader, "uDepthUnitCoords"), theQuad)
    # gl.uniform1i(gl.getUniformLocation(bc.postShader, "depthUnit"), textureIndex)

    # inc textureIndex

    # gl.activeTexture(GLenum(int(gl.TEXTURE0) + textureIndex))
    # gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(bc.postMap, gl, theQuad))
    # gl.uniform4fv(gl.getUniformLocation(bc.postShader, "uTexUnitCoords"), theQuad)
    # gl.uniform1i(gl.getUniformLocation(bc.postShader, "texUnit"), textureIndex)

    # let resolution = newVector4(vp.bounds.width, vp.bounds.height, bc.resolution[2], bc.resolution[3])
    # gl.uniform4fv(gl.getUniformLocation(bc.postShader, "uResolution"), bc.resolution)

    # gl.uniform1f(gl.getUniformLocation(bc.postShader, "decay"), decay)
    # gl.uniform1f(gl.getUniformLocation(bc.postShader, "exposure"), exposure)
    # gl.uniform1f(gl.getUniformLocation(bc.postShader, "density"), density)
    # gl.uniform1f(gl.getUniformLocation(bc.postShader, "weight"), weight)

    # gl.drawElements(gl.TRIANGLES, 6, gl.UNSIGNED_SHORT)
    # gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, invalidBuffer)
    # gl.bindBuffer(gl.ARRAY_BUFFER, invalidBuffer)
    # gl.useProgram(invalidProgram)

    # bc.postShader = bcpShader
    if not bShowDepthMap:
        c.withTransform mvpMatrix:
            # gl.cullFace(gl.BACK)
            for n in bc.node.children: n.recursiveDraw()
    else:
        var bcpShader = bc.postShader
        bc.postShader = depthDebugShader
        gl.useProgram(bc.postShader)
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, bc.ibo)
        gl.bindBuffer(gl.ARRAY_BUFFER, bc.vbo)
        var offset: int = 0
        gl.enableVertexAttribArray(aPosition.GLuint)
        gl.vertexAttribPointer(aPosition.GLuint, 3, gl.FLOAT, false, (5 * sizeof(GLfloat)).GLsizei, offset)
        offset += 3 * sizeof(GLfloat)
        gl.enableVertexAttribArray(aTexCoord.GLuint)
        gl.vertexAttribPointer(aTexCoord.GLuint, 2, gl.FLOAT, false, (5 * sizeof(GLfloat)).GLsizei, offset)
        var theQuad {.noinit.}: array[4, GLfloat]
        var textureIndex : GLint = 0
        gl.activeTexture(GLenum(int(gl.TEXTURE0) + textureIndex))
        gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(bc.depthMap, gl, theQuad))
        gl.uniform4fv(gl.getUniformLocation(bc.postShader, "uDepthUnitCoords"), theQuad)
        gl.uniform1i(gl.getUniformLocation(bc.postShader, "depthUnit"), textureIndex)
        inc textureIndex
        gl.activeTexture(GLenum(int(gl.TEXTURE0) + textureIndex))
        gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(bc.postMap, gl, theQuad))
        gl.uniform4fv(gl.getUniformLocation(bc.postShader, "uTexUnitCoords"), theQuad)
        gl.uniform1i(gl.getUniformLocation(bc.postShader, "texUnit"), textureIndex)
        let resolution = newVector4(vp.bounds.width, vp.bounds.height, bc.resolution[2], bc.resolution[3])
        gl.uniform4fv(gl.getUniformLocation(bc.postShader, "uResolution"), bc.resolution)
        gl.uniform1f(gl.getUniformLocation(bc.postShader, "decay"), decay)
        gl.uniform1f(gl.getUniformLocation(bc.postShader, "exposure"), exposure)
        gl.uniform1f(gl.getUniformLocation(bc.postShader, "density"), density)
        gl.uniform1f(gl.getUniformLocation(bc.postShader, "weight"), weight)
        gl.drawElements(gl.TRIANGLES, 6, gl.UNSIGNED_SHORT)
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, invalidBuffer)
        gl.bindBuffer(gl.ARRAY_BUFFER, invalidBuffer)
        gl.useProgram(invalidProgram)
        bc.postShader = bcpShader

method isPosteffectComponent*(bc: LightningComponent): bool = true

method visitProperties*(bc: LightningComponent, p: var PropertyVisitor) =
    p.visitProperty("dist", bc.camDistance)
    p.visitProperty("fixed_size", bc.fixedSize)

    p.visitProperty("depth", bShowDepthMap)
    p.visitProperty("color", bShowColorMap)

    # p.visitProperty("decay", decay)
    # p.visitProperty("exposure", exposure)
    # p.visitProperty("density", density)
    # p.visitProperty("weight", weight)

    # p.visitProperty("posX", bc.resolution[2])
    # p.visitProperty("posY", bc.resolution[3])

    p.visitProperty("ocluder", bc.ocluderNode)
    p.visitProperty("look at", bc.lookAtNode)

    p.visitProperty("bias", mipBias)

    p.visitProperty("freze", bFreze)


registerComponent(LightningComponent)
