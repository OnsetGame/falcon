import nimx.types
import nimx.context
import nimx.portable_gl
import nimx.types
import nimx.image
import nimx.matrixes
import nimx.view
import nimx.render_to_image
import nimx.property_visitor

import rod.component
import rod.quaternion
import rod.component.mesh_component
import rod.component.material
import rod.component.light
import rod.component.camera
import rod.component.sprite
import rod.node
import rod.viewport

import times

const vertexShader = """
attribute vec4 aPosition;
uniform mat4 modelViewProjectionMatrix;
void main() {
    gl_Position = modelViewProjectionMatrix * vec4(aPosition.xyz, 1.0);
}"""
const fragmentShader = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif

uniform float coverage;
uniform float sharpness;
uniform float alpha;
uniform vec4  resolutionAndDirection;

float hash( float n ) { return fract(sin(n)*43758.5453); }

float noise( vec2 x ) {
    vec2 p;
    p.x = floor(x.x);
    p.y = floor(x.y);
    vec2 f;
    f.x = fract(x.x);
    f.y = fract(x.y);
    f = f*f*(3.0-2.0*f);
    float n = p.x + p.y*57.0;
    return mix(mix(hash(n + 0.0), hash(n + 1.0),f.x), mix(hash(n + 57.0), hash(n + 58.0), f.x), f.y);
}

float fbm( vec2 p ) {
    float f = 0.0;
    f += 0.50000*noise(p);
    p = p*2.02;
    f += 0.25000*noise(p);
    p = p*2.03;
    f += 0.12500*noise(p);
    p = p*2.01;
    f += 0.06250*noise(p);
    p = p*2.04;
    f += 0.03125*noise(p);
    return f/0.984375;
}

void main() {
    vec2 q = gl_FragCoord.xy / resolutionAndDirection.xy;
    vec2 p = -1.0 + 3.0 * q + resolutionAndDirection.zw;
    p.x *= resolutionAndDirection.x / resolutionAndDirection.y;
    float f = fbm(4.0*p);
    float c = f - (1.0 - coverage);
    c = max(c, 0.0);
    f = 1.0 - (pow(sharpness, c));
    gl_FragColor = vec4(f, f, f, f*alpha);
}
"""

# const fragmentShader ="""
# uniform float time;
# uniform vec4  resolutionAndDirection;
# uniform sampler2D noizeUnit;
# float noise( vec2 x ) {
#     vec2 p = floor(x);
#     vec2 f = fract(x);
#     vec2 uv = p.xy + f.xy*f.xy*(3.0-2.0*f.xy);
#     return texture2D( noizeUnit, (uv+118.4)/256.0, -100.0 ).x;
# }
# float fbm( vec2 x) {
#     float h = 0.0;
#     for (float i=1.0;i<10.0;i++) {
#         h+=noise(x*pow(1.6, i))*0.9*pow(0.6, i);
#     }
#     return h;
# }
# float warp(vec2 p, float mm) {
#     float m = 4.0;
#     vec2 q = vec2(fbm(vec2(p)), fbm(p+vec2(5.12*time*0.01, 1.08)));

#     vec2 r = vec2(fbm((p+q*m)+vec2(0.1, 4.741)), fbm((p+q*m)+vec2(1.952, 7.845)));
#     m /= mm;
#     return fbm(p+r*m);
# }
# vec4 mainImage( vec2 fragCoord ) {
#     float speed = 80.0;
#     fragCoord -= vec2(time*speed, 0.0);
#     float col = warp(fragCoord*0.004, 50.0+fbm(fragCoord*0.005)*16.0);
#     float y = pow(1.0-fragCoord.y/resolutionAndDirection.y, 2.0);
#     // return mix(vec4(0.2+0.3*y, 0.4+0.2*y, 1.0, 1.0), vec4(1.0), smoothstep(0.8, 1.0, col));

#     return mix(vec4(y, y, y, y), vec4(1.0), smoothstep(0.82, 1.0, col));
# }
# void main() {
#     gl_FragColor = mainImage(gl_FragCoord.xy);
# }
# """

type ShaderAttribute = enum
    aPosition

type CloudComponent* = ref object of Component
    time: float64
    cloudCoverage*: float32
    cloudSharpness*: float32
    cloudSpeed*: float32
    resolutionAndDirection*: Vector4
    # noizeUnit: SelfContainedImage

    resImage*: SelfContainedImage

var imgWidth = 256.0
var imgHeight = 128.0

let vertexData = [0.0.GLfloat,0.0,0.0,  0.0,imgWidth,0.0,  imgHeight,imgWidth,0.0,  imgHeight,0.0,0.0]
let indexData = [0.GLushort, 1, 2, 2, 3, 0]

var cloudShader: ProgramRef
var cloudsSharedIndexBuffer: BufferRef
var cloudsSharedVertexBuffer: BufferRef
var cloudsSharedNumberOfIndexes: GLsizei

proc createVBO() =
    let c = currentContext()
    let gl = c.gl

    cloudsSharedIndexBuffer = gl.createBuffer()
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, cloudsSharedIndexBuffer)
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indexData, gl.STATIC_DRAW)

    cloudsSharedVertexBuffer = gl.createBuffer()
    gl.bindBuffer(gl.ARRAY_BUFFER, cloudsSharedVertexBuffer)
    gl.bufferData(gl.ARRAY_BUFFER, vertexData, gl.STATIC_DRAW)
    cloudsSharedNumberOfIndexes = indexData.len.GLsizei

method init*(cc: CloudComponent) =
    procCall cc.Component.init()
    cc.time = epochTime()
    cc.cloudCoverage = 0.3
    cc.cloudSharpness = 0.0000001
    cc.cloudSpeed = -1.0

method draw*(cc: CloudComponent) =
    let c = currentContext()
    let gl = c.gl

    if cloudsSharedIndexBuffer == invalidBuffer:
        createVBO()
        if cloudsSharedIndexBuffer == invalidBuffer:
            return

    if cloudShader == invalidProgram:
        cloudShader = gl.newShaderProgram(vertexShader, fragmentShader,  [(ShaderAttribute.aPosition.GLuint, "aPosition")])
        if cloudShader == invalidProgram:
            return

    if cc.resImage.isNil:
        # cc.noizeUnit = imageWithResource("slots/balloon_slot/2d/rgbnoise.png")

        cc.resImage = imageWithSize(newSize(imgWidth, imgHeight))

        cc.resolutionAndDirection[0] = cc.node.sceneView.bounds.size.width
        cc.resolutionAndDirection[1] = cc.node.sceneView.bounds.size.height
        cc.resolutionAndDirection[2] = 0.0
        cc.resolutionAndDirection[3] = 0.0

    cc.resImage.draw( proc() =

        gl.useProgram(cloudShader)

        # var theQuad {.noinit.}: array[4, GLfloat]
        # gl.activeTexture(gl.TEXTURE0)
        # gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(cc.noizeUnit, gl, theQuad))
        # gl.uniform1i(gl.getUniformLocation(cloudShader, "noizeUnit"), 0.GLint)

        var t = epochTime().float64
        var delta = abs(t.float64 - cc.time.float64)*30.0.float64/1000.0.float64
        cc.time = t.float64

        cc.resolutionAndDirection[0] = cc.node.sceneView.bounds.size.width
        cc.resolutionAndDirection[1] = cc.node.sceneView.bounds.size.height/4.0
        cc.resolutionAndDirection[2] -= delta.float * cc.cloudSpeed.float

        gl.uniform4fv(gl.getUniformLocation(cloudShader, "resolutionAndDirection"), cc.resolutionAndDirection)

        # gl.uniform1f(gl.getUniformLocation(cloudShader, "time"), cc.time)
        gl.uniform1f(gl.getUniformLocation(cloudShader, "alpha"), c.alpha)
        gl.uniform1f(gl.getUniformLocation(cloudShader, "coverage"), cc.cloudCoverage)
        gl.uniform1f(gl.getUniformLocation(cloudShader, "sharpness"), cc.cloudSharpness)

        c.setTransformUniform(cloudShader)

        gl.bindBuffer(gl.ARRAY_BUFFER, cloudsSharedVertexBuffer)
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, cloudsSharedIndexBuffer)

        gl.enableVertexAttribArray(aPosition.GLuint)
        gl.vertexAttribPointer(aPosition.GLuint, 3.GLint, gl.FLOAT, false, (3 * sizeof(GLfloat)).GLsizei , 0)

        gl.drawElements(gl.TRIANGLES, cloudsSharedNumberOfIndexes, gl.UNSIGNED_SHORT)

        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, invalidBuffer)
        gl.bindBuffer(gl.ARRAY_BUFFER, invalidBuffer)
    )

    cc.resImage.flipVertically()

    var r: Rect
    r.origin = newPoint(0.0, 0.0)
    r.size = cc.resImage.size

    c.drawImage(cc.resImage, r, zeroRect)

method visitProperties*(cc: CloudComponent, p: var PropertyVisitor) =
    p.visitProperty("coverage", cc.cloudCoverage)
    p.visitProperty("sharpness", cc.cloudSharpness)
    p.visitProperty("speed", cc.cloudSpeed)

registerComponent(CloudComponent)
