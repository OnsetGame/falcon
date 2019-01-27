import json
import tables
import math

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
vec2 get_mask_uv(vec4 mask_img_coords, vec4 mask_bounds, mat4 mvp_inv) {
    vec2 ppostVpos = vec4(mvp_inv * vec4(gl_FragCoord.x, gl_FragCoord.y, 0.0, 1.0)).xy;
    vec2 destuv = ( ppostVpos - mask_bounds.xy ) / mask_bounds.zw;
    return mask_img_coords.xy + (mask_img_coords.zw - mask_img_coords.xy) * destuv;
}
void pay_post_effect(sampler2D mask_img, vec4 mask_img_coords, vec4 mask_bounds, mat4 mvp_inv) {
    vec2 uv = get_mask_uv(mask_img_coords, mask_bounds, mvp_inv);
    vec3 tc = texture2D(mask_img, uv, 5.0).rgb * 0.2270270270;
    tc += texture2D(mask_img, uv + vec2(2.7692307692, 2.7692307692) / mask_bounds.z, 5.0).rgb * 0.3162162162;
    tc += texture2D(mask_img, uv - vec2(2.7692307692, 2.7692307692) / mask_bounds.z, 5.0).rgb * 0.3162162162;
    tc += texture2D(mask_img, uv + vec2(6.4615384616, 6.4615384616) / mask_bounds.z, 5.0).rgb * 0.0702702703;
    tc += texture2D(mask_img, uv - vec2(6.4615384616, 6.4615384616) / mask_bounds.z, 5.0).rgb * 0.0702702703;
    gl_FragColor.rgb = mix(tc, vec3(0.0, 0.05078125, 0.16015625), 0.5);
}
"""

type PayBgPost* = ref object of Component
    rti: RTI
    mBackNode: Node

template inv(m: Matrix4): Matrix4 =
    var res: Matrix4
    if not m.tryInverse(res):
        res.loadIdentity()
    res

template backNode*(ppost: PayBgPost): Node = ppost.mBackNode
template `backNode=`*(ppost: PayBgPost, val: Node) =
    ppost.mBackNode = val
    if not ppost.mBackNode.isNil:
        ppost.rti = ppost.mBackNode.componentIfAvailable(RTI)

method componentNodeWillBeRemovedFromSceneView*(ppost: PayBgPost) =
    # ppost.rti = nil
    # ppost.mBackNode = nil
    discard

const clipMat: Matrix4 = [0.5.Coord,0,0,0,0,0.5,0,0,0,0,1.0,0,0.5,0.5,0,1.0]

method beforeDraw*(ppost: PayBgPost, index: int): bool =
    if not ppost.rti.isNil and not ppost.rti.image.isNil:

        let gl = currentContext().gl
        gl.bindTexture(gl.TEXTURE_2D, ppost.rti.image.SelfContainedImage.texture)
        gl.generateMipmap(gl.TEXTURE_2D)
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_NEAREST)

        var theQuad {.noinit.}: array[4, GLfloat]
        discard getTextureQuad(ppost.rti.image, currentContext().gl, theQuad)
        let maskImgCoords = newRect(theQuad[0], theQuad[1], theQuad[2], theQuad[3])
        var maskBounds = ppost.rti.getImageScreenBounds()

        let vp = ppost.node.sceneView
        var trInv = (clipMat * vp.viewProjMatrix * ppost.mBackNode.worldTransform()).inv()
        let glvp = currentContext().gl.getViewport()
        trInv.scale(newVector3(1.0/(glvp[2] - glvp[0]).float, 1.0/(glvp[3] - glvp[1]).float, 1.0))

        pushPostEffect(newPostEffect(postEffectScr, "pay_post_effect", ["sampler2D", "vec4", "vec4", "mat4"]), ppost.rti.image, maskImgCoords, maskBounds, trInv)

method afterDraw*(ppost: PayBgPost, index: int) =
    if not ppost.rti.isNil and not ppost.rti.image.isNil:
        popPostEffect()

method serialize*(ppost: PayBgPost, serealizer: Serializer): JsonNode =
    result = newJObject()
    result.add("nodeName", serealizer.getValue(ppost.backNode))

method deserialize*(ppost: PayBgPost, j: JsonNode, serealizer: Serializer) =
    var nodeName: string
    serealizer.deserializeValue(j, "nodeName", nodeName)
    addNodeRef(ppost.backNode, nodeName)

method visitProperties*(ppost: PayBgPost, p: var PropertyVisitor) =
    p.visitProperty("node", ppost.backNode)

registerComponent(PayBgPost, "Effects")
