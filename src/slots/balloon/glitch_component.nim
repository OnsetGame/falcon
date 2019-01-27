import streams, tables, math, times
import opengl

import nimx / [ types, context, portable_gl, view, image, render_to_image ]
import nimx.assets.url_stream

import rod.node
import rod.viewport
import rod.component
import rod.component.camera
import nimx.property_visitor

var noizeUnit: SelfContainedImage

type Attrib = enum
    aPosition
    aTexCoord

type
    ShaderType* = enum
        GreenStripe
        RewindGreenStripe
        Grayscale
        VHS1
        VHS2
        Debug

type GlitchComponent* = ref object of Component
    postMap: SelfContainedImage
    shaders: seq[ProgramRef]
    currShader: ShaderType
    vbo, ibo: BufferRef

    resolution: Vector4
    fixedSize*: bool

    time: float64
    accumTime: float64

    currVertexShaderPath: string
    currFragmentShaderPath: string

let vertexShaderPost = """
attribute vec4 aPosition;
attribute vec2 aTexCoord;

varying vec2 vTexCoord;

void main() {
    gl_Position = vec4(aPosition.xyz, 1.0);
    vTexCoord = aTexCoord;
}
"""

let fragmentShaderPost0 = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif

uniform sampler2D texUnit;
uniform vec4 uTexUnitCoords;

uniform vec4 uResolution;
uniform float uTime;

varying vec2 vTexCoord;

vec2 uv() {
    vec2 texelSize = vec2(1.0/uResolution.x, 1.0/uResolution.y);
    vec2 screenTexCoords = gl_FragCoord.xy * texelSize;
    return uTexUnitCoords.xy + (uTexUnitCoords.zw - uTexUnitCoords.xy) * screenTexCoords;
}

vec4 greenStripeGlitch() {
    vec2 q = uv();
    q = vec2(q.x, 1.0-q.y);
    vec2 samplePosition = q;

    vec3 oricol = texture2D( texUnit, q ).xyz;
    vec3 col;

    col.r = texture2D(texUnit,vec2(samplePosition.x+0.003,-samplePosition.y)).x;
    col.g = texture2D(texUnit,vec2(samplePosition.x+0.000,-samplePosition.y)).y;
    col.b = texture2D(texUnit,vec2(samplePosition.x-0.003,-samplePosition.y)).z;

    col = clamp(col*0.5+0.5*col*col*1.2,0.0,1.0);
    col *= 0.5 + 0.5*16.0*samplePosition.x*samplePosition.y*(1.0-samplePosition.x)*(1.0-samplePosition.y);
    col *= vec3(0.95,1.05,0.95);
    col *= 0.9+0.1*sin(10.0*uTime+samplePosition.y*1000.0);
    col *= 0.99+0.01*sin(110.0*uTime);

    float comp = smoothstep( 0.2, 0.7, sin(uTime) );
    col = mix( col, oricol, clamp(-2.0+2.0*q.x+3.0*comp,0.0,1.0) );

    return vec4(col,1.0);
}

void main() {
    gl_FragColor = greenStripeGlitch();
}
"""

let fragmentShaderPost1 = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif

uniform sampler2D texUnit;
uniform vec4 uTexUnitCoords;

uniform vec4 uResolution;
uniform float uTime;

varying vec2 vTexCoord;

vec2 uv() {
    vec2 texelSize = vec2(1.0/uResolution.x, 1.0/uResolution.y);
    vec2 screenTexCoords = gl_FragCoord.xy * texelSize;
    return uTexUnitCoords.xy + (uTexUnitCoords.zw - uTexUnitCoords.xy) * screenTexCoords;
}

float rand(vec2 co) { return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453); }

vec4 greenStripeGlitch() {
    vec2 uvs = uv();
    vec2 samplePosition = vec2(uvs.x+(rand(vec2(uTime,gl_FragCoord.y))-0.5)/512.0, 1.0-uvs.y+(rand(vec2(uTime))-0.5)/256.0);

    vec3 texel = texture2D(texUnit, samplePosition).xyz;
    vec3 glitch_texel = vec3(0.0,0.0,0.0);

    glitch_texel.r = texture2D(texUnit,vec2(samplePosition.x+0.003,-samplePosition.y)).x;
    glitch_texel.g = texture2D(texUnit,vec2(samplePosition.x+0.000,-samplePosition.y)).y;
    glitch_texel.b = texture2D(texUnit,vec2(samplePosition.x-0.003,-samplePosition.y)).z;

    glitch_texel = clamp(glitch_texel*0.5+0.5*glitch_texel*glitch_texel*1.2,0.0,1.0);
    glitch_texel *= 0.5 + 0.5*16.0*samplePosition.x*samplePosition.y*(1.0-samplePosition.x)*(1.0-samplePosition.y);
    vec3 add_green_vec = vec3(0.95,1.05,0.95);
    glitch_texel *= add_green_vec;
    float stripe_height = 1000.0;
    glitch_texel *= 0.9+0.1*sin(10.0*uTime+samplePosition.y*stripe_height);
    glitch_texel *= 0.99+0.01*sin(128.0*uTime);

    float shift = smoothstep(0.2, 0.7, sin(uTime));
    glitch_texel = mix( glitch_texel, texel, clamp(-2.0+2.0*uvs.x+3.0*shift,0.0,1.0) );

    return vec4(glitch_texel,1.0);
}

void main() {
    gl_FragColor = greenStripeGlitch();
}
"""

let fragmentShaderPost2 = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif

uniform sampler2D texUnit;
uniform vec4 uTexUnitCoords;

uniform vec4 uResolution;
uniform float uTime;

varying vec2 vTexCoord;

vec2 uv() {
    vec2 texelSize = vec2(1.0/uResolution.x, 1.0/uResolution.y);
    vec2 screenTexCoords = gl_FragCoord.xy * texelSize;
    return uTexUnitCoords.xy + (uTexUnitCoords.zw - uTexUnitCoords.xy) * screenTexCoords;
}

float rand(vec2 co) { return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453); }

vec4 grayscaleGlitch() {
    vec2 samplePosition = uv();

    float screenRatio = uResolution.x / uResolution.y;

    vec3 texture = texture2D(texUnit, samplePosition).rgb;

    float barHeight = 6.;
    float barSpeed = 5.6;
    float barOverflow = 1.2;
    float blurBar = clamp(sin(samplePosition.y * barHeight + uTime * barSpeed) + 1.25, 0., 1.);
    float bar = clamp(floor(sin(samplePosition.y * barHeight + uTime * barSpeed) + 1.95), 0., barOverflow);

    float noiseIntensity = .75;
    float pixelDensity = 250.;
    vec3 color = vec3(clamp(rand( vec2(floor(samplePosition.x * pixelDensity * screenRatio), floor(samplePosition.y * pixelDensity)) * uTime ) + 1. - noiseIntensity, 0., 1.));

    color = mix(color - noiseIntensity * vec3(.25), color, blurBar);
    color = mix(color - noiseIntensity * vec3(.08), color, bar);
    color = mix(vec3(0.), texture, color);
    color.b += .042;

    color *= vec3(1.0 - pow(distance(samplePosition, vec2(0.5, 0.5)), 2.1) * 2.8);

    return vec4(color, 1.);
}

void main() {
    gl_FragColor = grayscaleGlitch();
}
"""

let fragmentShaderPost3 = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif

uniform sampler2D texUnit;
uniform vec4 uTexUnitCoords;

uniform vec4 uResolution;
uniform float uTime;

varying vec2 vTexCoord;

vec2 uv() {
    vec2 texelSize = vec2(1.0/uResolution.x, 1.0/uResolution.y);
    vec2 screenTexCoords = gl_FragCoord.xy * texelSize;
    return uTexUnitCoords.xy + (uTexUnitCoords.zw - uTexUnitCoords.xy) * screenTexCoords;
}

float rand(vec2 co) { return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453); }

vec4 rewindVHS1() {
    vec4 texColor = vec4(0.0, 0.0, 0.0, 0.0);
    vec2 fragCoord = gl_FragCoord.xy;
    vec2 samplePosition = uv();
    samplePosition = vec2(samplePosition.x, 1.0-samplePosition.y);
    float whiteNoise = 9999.0;

    samplePosition.x = samplePosition.x+(rand(vec2(uTime,fragCoord.y))-0.5)/64.0;
    samplePosition.y = samplePosition.y+(rand(vec2(uTime))-0.5)/32.0;
    texColor = texColor + (vec4(-0.5)+vec4(rand(vec2(fragCoord.y,uTime)),rand(vec2(fragCoord.y,uTime+1.0)),rand(vec2(fragCoord.y,uTime+2.0)),0))*0.1;

    whiteNoise = rand(vec2(floor(samplePosition.y*80.0),floor(samplePosition.x*50.0))+vec2(uTime,0));
    if (whiteNoise > 11.5-30.0*samplePosition.y || whiteNoise < 1.5-5.0*samplePosition.y) {
        samplePosition.y = 1.0-samplePosition.y; //Fix for upside-down texture
        texColor = texColor + texture2D(texUnit,samplePosition);
    } else {
        texColor = vec4(1);
    }
    return texColor;
}

void main() {
    gl_FragColor = rewindVHS1();
}
"""

let fragmentShaderPost4 = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif

uniform sampler2D texUnit;
uniform vec4 uTexUnitCoords;

uniform vec4 uResolution;
uniform float uTime;

varying vec2 vTexCoord;

vec2 uv() {
    vec2 texelSize = vec2(1.0/uResolution.x, 1.0/uResolution.y);
    vec2 screenTexCoords = gl_FragCoord.xy * texelSize;
    return uTexUnitCoords.xy + (uTexUnitCoords.zw - uTexUnitCoords.xy) * screenTexCoords;
}

float rand(vec2 co) { return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453); }

vec4 rewindVHS2() {
    vec2 samplePosition = uv();

    float magnitude = 0.0009;

    vec2 offsetRedUV = samplePosition;
    offsetRedUV.x = samplePosition.x + rand(vec2(uTime*0.03,samplePosition.y*0.42)) * 0.001;
    offsetRedUV.x += sin(rand(vec2(uTime*0.2, samplePosition.y)))*magnitude;

    vec2 offsetGreenUV = samplePosition;
    offsetGreenUV.x = samplePosition.x + rand(vec2(uTime*0.004,samplePosition.y*0.002)) * 0.004;
    offsetGreenUV.x += sin(uTime*9.0)*magnitude;

    vec2 offsetBlueUV = samplePosition;
    offsetBlueUV.x = samplePosition.y;
    offsetBlueUV.x += rand(vec2(cos(uTime*0.01),sin(samplePosition.y)));

    float r = texture2D(texUnit, offsetRedUV).r;
    float g = texture2D(texUnit, offsetGreenUV).g;
    float b = texture2D(texUnit, samplePosition).b;

    return vec4(r,g,b,1.0);
}

void main() {
    gl_FragColor = rewindVHS2();
}
"""

let fragmentShaderDebug = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif

uniform sampler2D texUnit;
uniform vec4 uTexUnitCoords;

uniform vec4 uResolution;
uniform float uTime;

varying vec2 vTexCoord;

vec2 uv() {
    vec2 texelSize = vec2(1.0/uResolution.x, 1.0/uResolution.y);
    vec2 screenTexCoords = gl_FragCoord.xy * texelSize;
    return uTexUnitCoords.xy + (uTexUnitCoords.zw - uTexUnitCoords.xy) * screenTexCoords;
}

void main() {
    gl_FragColor = texture2D(texUnit, uv());
}
"""

var fragShaderLib = newSeq[string]()
fragShaderLib.add(fragmentShaderPost0)
fragShaderLib.add(fragmentShaderPost1)
fragShaderLib.add(fragmentShaderPost2)
fragShaderLib.add(fragmentShaderPost3)
fragShaderLib.add(fragmentShaderPost4)
fragShaderLib.add(fragmentShaderDebug)

proc assignShadersWithResource*(gc: GlitchComponent, currShader: int, vertexShader: string = "", fragmentShader: string = "") =

    gc.currShader = currShader.ShaderType

    if gc.shaders[gc.currShader.int] != invalidProgram:
        currentContext().gl.deleteProgram(gc.shaders[gc.currShader.int])
        gc.shaders[gc.currShader.int] = invalidProgram

    template shaderSourceLoaded() =
        if gc.shaders[gc.currShader.int] == invalidProgram:
            let gl = currentContext().gl
            gc.shaders[gc.currShader.int] = gl.newShaderProgram(gc.currVertexShaderPath, gc.currFragmentShaderPath, [(Attrib.aPosition.GLuint, $aPosition), (aTexCoord.GLuint, $aTexCoord)])
            gc.currVertexShaderPath = ""
            gc.currFragmentShaderPath = ""

    if vertexShader != "":
        openStreamForURL("res://" & vertexShader) do(s: Stream, err: string):
            if not s.isNil:
                gc.currVertexShaderPath = s.readAll()
                s.close()
    else:
        gc.currVertexShaderPath = vertexShaderPost

    if fragmentShader != "":
        openStreamForURL("res://" & fragmentShader) do(s: Stream, err: string):
            if not s.isNil:
                gc.currFragmentShaderPath = s.readAll()
                s.close()
    else:
        gc.currFragmentShaderPath = fragmentShaderPost0

    shaderSourceLoaded()

proc vertexShaderPath*(gc: GlitchComponent): string = result = gc.currVertexShaderPath
proc `vertexShaderPath=`*(gc: GlitchComponent, s: string) =
    gc.currVertexShaderPath = s
    enableAutoGLerrorCheck(false)
    gc.assignShadersWithResource(gc.currShader.int, gc.currVertexShaderPath, gc.currFragmentShaderPath)

proc fragmentShaderPath*(gc: GlitchComponent): string = result = gc.currFragmentShaderPath
proc `fragmentShaderPath=`*(gc: GlitchComponent, s: string) =
    gc.currFragmentShaderPath = s
    enableAutoGLerrorCheck(false)
    gc.assignShadersWithResource(gc.currShader.int, gc.currVertexShaderPath, gc.currFragmentShaderPath)

proc checkResolution*(lc: GlitchComponent) =
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

proc createAndSetup(bc: GlitchComponent) =
    let gl = currentContext().gl

    if bc.shaders[bc.currShader.int] == invalidProgram:
        bc.shaders[bc.currShader.int] = gl.newShaderProgram(vertexShaderPost, fragShaderLib[bc.currShader.int], [(aPosition.GLuint, $aPosition), (aTexCoord.GLuint, $aTexCoord)])

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

method init*(bc: GlitchComponent) =
    procCall bc.Component.init()
    bc.time = epochTime()
    bc.shaders = newSeq[ProgramRef](fragShaderLib.len)
    bc.currShader = RewindGreenStripe
    bc.currVertexShaderPath = ""
    bc.currFragmentShaderPath = ""

    # if noizeUnit.isNil:
    #     noizeUnit = imageWithResource("slots/balloon_slot/noize/noize.png")

# var readMap: SelfContainedImage
# var bOnce = true
# var pixels: seq[uint8]

method draw*(bc: GlitchComponent) =
    let vp = bc.node.sceneView
    let c = currentContext()
    let gl = c.gl

    bc.checkResolution()

    bc.createAndSetup()

    # if bOnce:
    #     readMap = imageWithSize(newSize(bc.resolution[0], bc.resolution[1]))
    #     var texCoords : array[4, GLfloat]
    #     var texture = readMap.getTextureQuad(gl, texCoords)
    #     if texture.isEmpty:
    #         texture = gl.createTexture()
    #         readMap.texture = texture
    #     gl.bindTexture(gl.TEXTURE_2D, texture)
    #     gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    #     gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA.GLint, bc.resolution[0].GLsizei, bc.resolution[1].GLsizei, 0, gl.RGBA, gl.UNSIGNED_BYTE, nil)

    #     let seqSize = (bc.resolution[0] * bc.resolution[1] * 4)
    #     pixels = newSeq[uint8](seqSize.int)
    #     bOnce = false

    # glReadPixels( 0.GLint, 0.GLint, bc.resolution[0].GLsizei, bc.resolution[1].GLsizei, GL_RGBA, GL_UNSIGNED_BYTE, unsafeAddr pixels[0])
    # gl.bindTexture(gl.TEXTURE_2D, readMap.texture)
    # glTexSubImage2D( GL_TEXTURE_2D, 0.GLint, 0.GLint, 0.GLint, bc.resolution[0].GLsizei, bc.resolution[1].GLsizei, GL_RGBA, GL_UNSIGNED_BYTE, cast[pointer](pixels) )

    let mvp = vp.getViewProjectionMatrix() * bc.node.worldTransform()
    bc.postMap.draw proc() =
        c.withTransform mvp:
            for n in bc.node.children: n.recursiveDraw()

    gl.useProgram(bc.shaders[bc.currShader.int])
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
    gl.uniform4fv(gl.getUniformLocation(bc.shaders[bc.currShader.int], "uTexUnitCoords"), theQuad)
    gl.uniform1i(gl.getUniformLocation(bc.shaders[bc.currShader.int], "texUnit"), 0.GLint)

    if not noizeUnit.isNil:
        gl.activeTexture(GLenum(int(gl.TEXTURE0) + 1))
        gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(noizeUnit, gl, theQuad))
        gl.uniform4fv(gl.getUniformLocation(bc.shaders[bc.currShader.int], "uNoizeUnitCoords"), theQuad)
        gl.uniform1i(gl.getUniformLocation(bc.shaders[bc.currShader.int], "noizeUnit"), 1.GLint)

    gl.uniform4fv(gl.getUniformLocation(bc.shaders[bc.currShader.int], "uResolution"), bc.resolution)
    let epTime = epochTime().float64
    bc.time = epTime - bc.time
    gl.uniform1f(gl.getUniformLocation(bc.shaders[bc.currShader.int], "uTime"), bc.time)
    bc.accumTime = bc.accumTime + bc.time
    gl.uniform1f(gl.getUniformLocation(bc.shaders[bc.currShader.int], "uAccumTime"), bc.accumTime)
    bc.time = epTime

    gl.drawElements(gl.TRIANGLES, 6, gl.UNSIGNED_SHORT)
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, invalidBuffer)
    gl.bindBuffer(gl.ARRAY_BUFFER, invalidBuffer)
    gl.useProgram(invalidProgram)

method isPosteffectComponent*(bc: GlitchComponent): bool = true

method visitProperties*(gc: GlitchComponent, p: var PropertyVisitor) =
    p.visitProperty("curent", gc.currShader )
    p.visitProperty("shader", (gc.vertexShaderPath, gc.fragmentShaderPath) )

registerComponent(GlitchComponent)
