import json, tables, math, logging

import nimx.types
import nimx.context
import nimx.image
import nimx.portable_gl
import nimx.view
import nimx.composition
import nimx.property_visitor

import rod.rod_types
import rod.node
import rod.tools.serializer
import rod.component
import rod.component.sprite
import rod.component.solid
import rod.component.camera
import rod.component.rti
import rod.viewport

const postEffectScr = """

float rect_alpha_uv(vec2 uvs, vec4 texCoord) {
    if (uvs.x < texCoord.x || uvs.x > texCoord.z || uvs.y < texCoord.y || uvs.y > texCoord.w) { return 0.0; }
    else { return 1.0; }
}

vec2 get_uv(vec4 img_coords, vec4 img_bounds, mat4 mvp_inv) {
    vec2 displVpos = vec4(mvp_inv * vec4(gl_FragCoord.x, gl_FragCoord.y, 0.0, 1.0)).xy;
    vec2 destuv = ( displVpos - img_bounds.xy ) / img_bounds.zw;
    return img_coords.xy + (img_coords.zw - img_coords.xy) * destuv;
}

void displacement_effect(sampler2D img, vec4 img_coords, vec4 img_bounds, vec2 displ_size, mat4 mvp_inv, float dislpAlpha) {
    vec2 uv = get_uv(img_coords, img_bounds, mvp_inv);
    vec4 tc = texture2D(img, uv, 0.0);


    tc.rg = tc.rg * displ_size * rect_alpha_uv(uv, img_coords) * tc.a * dislpAlpha;


    vec2 destuv = (vPos - bounds.xy) / bounds.zw;
    vec2 duv = uImage_texCoords.zw - uImage_texCoords.xy;
    vec2 srcxy = uImage_texCoords.xy + duv * uFromRect.xy;
    vec2 srczw = uImage_texCoords.xy + duv * uFromRect.zw;
    vec2 img_uv = srcxy + (srczw - srcxy) * destuv;

    vec2 displ_uv = img_uv + tc.rg;

    gl_FragColor = texture2D(uImage_tex, displ_uv);



    gl_FragColor.a *= uAlpha;
}
"""

type Displacement* = ref object of Component
    mDisplacementNode: Node
    mDisplacementSprite: Sprite
    mRTInode: Node
    mRti: RTI
    displSize*: Size

template inv(m: Matrix4): Matrix4 =
    var res: Matrix4
    if not m.tryInverse(res):
        res.loadIdentity()
    res

proc findComponents*(n: Node, T: typedesc[Component]): auto =
    type TT = T
    var compSeq = newSeq[TT]()
    discard n.findNode do(nd: Node) -> bool:
        let comp = nd.componentIfAvailable(TT)
        if not comp.isNil: compSeq.add(comp)
    return compSeq

proc setupDisplacementComponent(d: Displacement)
proc trySetupDisplacement(d: Displacement)

template displacementNode*(d: Displacement): Node = d.mDisplacementNode
template `displacementNode=`*(d: Displacement, val: Node) =
    d.mDisplacementNode = val
    trySetupDisplacement(d)

template displacementSprite*(d: Displacement): Sprite = d.mDisplacementSprite
template `displacementSprite=`*(d: Displacement, val: Sprite) = d.mDisplacementSprite = val

proc trySetupRTI(d: Displacement)
template rtiNode*(d: Displacement): Node = d.mRTInode
template `rtiNode=`*(d: Displacement, val: Node) =
    d.mRTInode = val
    trySetupRTI(d)

template rti*(d: Displacement): RTI = d.mRti
template `rti=`*(d: Displacement, val: RTI) = d.mRti = val

proc setupDisplacementComponent(d: Displacement) =
    if not d.displacementNode.isNil:
        let spriteCmps = d.displacementNode.findComponents(Sprite)
        let solidCmps = d.displacementNode.findComponents(Solid)
        if spriteCmps.len > 1 or solidCmps.len > 0:
            # if solidCmps.len == 1 and spriteCmps.len == 0: # do solid RTI
            # else: # do all branch RTI
            raise newException(Exception, "use RTI")
        elif spriteCmps.len == 1:
            d.displacementSprite = spriteCmps[0]
        else:
            d.displacementSprite = nil

proc trySetupDisplacement(d: Displacement) =
    try: d.setupDisplacementComponent()
    except Exception:
        let ex = getCurrentException()
        info ex.name, ": ", getCurrentExceptionMsg(), "\n", ex.getStackTrace()

proc setupRTI(d: Displacement) =
    if not d.rtiNode.isNil:
        let rtiCmps = d.rtiNode.findComponents(RTI)
        if rtiCmps.len > 0:
            d.rti = rtiCmps[0]
        else:
            d.rti = nil
            raise newException(Exception, "RTI not found")

proc trySetupRTI(d: Displacement) =
    try: d.setupRTI()
    except Exception:
        let ex = getCurrentException()
        info ex.name, ": ", getCurrentExceptionMsg(), "\n", ex.getStackTrace()

method componentNodeWasAddedToSceneView*(d: Displacement) =
    if d.displacementSprite.isNil:
        d.trySetupDisplacement()

method componentNodeWillBeRemovedFromSceneView*(d: Displacement) =
    d.displacementSprite = nil

const clipMat: Matrix4 = [0.5.Coord,0,0,0,0,0.5,0,0,0,0,1.0,0,0.5,0.5,0,1.0]

method afterDraw*(d: Displacement, index: int) =
    if not d.displacementSprite.isNil and not d.rti.isNil and not d.rti.image.isNil:

        let oldRtiState = d.rti.bDraw
        d.rti.bDraw = false

        let vp = d.node.sceneView
        var theQuad {.noinit.}: array[4, GLfloat]
        discard getTextureQuad(d.displacementSprite.image, currentContext().gl, theQuad)
        let displacementImgCoords = newRect(theQuad[0], theQuad[1], theQuad[2], theQuad[3])
        let displacementBounds = newRect(d.displacementSprite.getOffset(), d.displacementSprite.image.size)

        var trInv = (clipMat * vp.viewProjMatrix * d.displacementSprite.node.worldTransform()).inv()
        let glvp = currentContext().gl.getViewport()
        trInv.scale(newVector3(1.0/(glvp[2] - glvp[0]).float, 1.0/(glvp[3] - glvp[1]).float, 1.0))

        let displacementAlpha = d.displacementSprite.node.alpha

        pushPostEffect(newPostEffect(postEffectScr, "displacement_effect", ["sampler2D", "vec4", "vec4", "vec2", "mat4", "float"]), d.displacementSprite.image, displacementImgCoords, displacementBounds, d.displSize, trInv, displacementAlpha)

        d.rti.drawWithBlend()

        popPostEffect()

        d.rti.bDraw = oldRtiState

method serialize*(d: Displacement, serealizer: Serializer): JsonNode =
    result = newJObject()
    result.add("displNodeName", serealizer.getValue(d.displacementNode))
    result.add("rtiNodeName", serealizer.getValue(d.rtiNode))
    result.add("displSize", serealizer.getValue(d.displSize))

method deserialize*(d: Displacement, j: JsonNode, serealizer: Serializer) =
    var displNodeName: string
    serealizer.deserializeValue(j, "displNodeName", displNodeName)
    addNodeRef(d.displacementNode, displNodeName)
    var rtiNodeName: string
    serealizer.deserializeValue(j, "rtiNodeName", rtiNodeName)
    addNodeRef(d.displacementNode, rtiNodeName)
    serealizer.deserializeValue(j, "displSize", d.displSize)

method visitProperties*(d: Displacement, p: var PropertyVisitor) =
    p.visitProperty("displ name", d.displacementNode)
    p.visitProperty("rti name", d.rtiNode)
    p.visitProperty("displ size", d.displSize)

registerComponent(Displacement, "Effects")