import json, tables, math

import nimx.types
import nimx.context
import nimx.view
import nimx.matrixes
import nimx.property_visitor
import nimx.portable_gl

import rod.rod_types
import rod.node
import rod.tools.serializer
import rod / utils / [ property_desc, serialization_codegen ]
import rod.component
import rod.component.camera
import rod.viewport

type ProjectionToOrtho* = ref object of Component

proc getProjMat(c: Camera): Transform3D =
    let absBounds = c.node.sceneView.convertRectToWindow(c.node.sceneView.bounds)
    var winSize = absBounds.size
    if not c.node.sceneView.window.isNil:
        winSize = c.node.sceneView.window.bounds.size
    let cy = absBounds.y + absBounds.height / 2
    let cx = absBounds.x + absBounds.width / 2
    let top = -cy
    let bottom = winSize.height - cy
    let left = -cx
    let right = winSize.width - cx
    let angle = degToRad(c.fov) / 2.0
    let Z = absBounds.height / 2.0 / tan(angle)
    let nLeft = c.zNear * left / Z
    let nRight = c.zNear * right / Z
    let nTop = c.zNear * top / Z - 0.055
    let nBottom = c.zNear * bottom / Z - 0.055
    result.frustum(nLeft, nRight, -nBottom, -nTop, c.zNear, c.zFar)

method beforeDraw*(pto: ProjectionToOrtho, index: int): bool =
    result = true

    let v = pto.node.sceneView
    if v.isNil:
        return
    let camera = v.camera
    let oldPosition = camera.node.position
    let oldScale = camera.node.scale
    let oldZNear = camera.zNear
    let oldZFar = camera.zFar
    let oldFov = camera.fov
    let oldVPMat = v.viewProjMatrix

    camera.node.position = oldPosition + newVector3(0.0,80.0,2666.7)
    camera.node.scale = oldScale * newVector3(1.0,-1.0,1.779)
    camera.zNear = 1.0
    camera.zFar = 10000.0
    camera.fov = 39.6
    v.viewMatrixCached = camera.node.worldTransform.inversed()
    v.viewProjMatrix = camera.getProjMat() * v.viewMatrixCached

    currentContext().withTransform v.viewProjMatrix:
        for ch in pto.node.children:
            ch.recursiveDraw()

    camera.node.position = oldPosition
    camera.node.scale = oldScale
    camera.zNear = oldZNear
    camera.zFar = oldZFar
    camera.fov = oldFov
    v.viewProjMatrix = oldVPMat

registerComponent(ProjectionToOrtho, "Effects")
