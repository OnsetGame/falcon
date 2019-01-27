# import json
# import math

import nimx.types
import nimx.view
import nimx.matrixes
import nimx.property_visitor


import rod.rod_types
import rod.node
import rod.tools.serializer
import rod.component
import rod.viewport
import rod.quaternion

type FixTransform* = ref object of Component
    prevRotationMatrix: Matrix4

method componentNodeWasAddedToSceneView*(ft: FixTransform) =
    ft.prevRotationMatrix = ft.node.rotation.toMatrix4()

method beforeDraw*(ft: FixTransform, index: int): bool =
    var sc: Vector3
    var rot: Vector4
    var wt = ft.node.worldTransform() * ft.prevRotationMatrix.inversed()
    if wt.tryGetScaleRotationFromModel(sc, rot):
        rot.w = -rot.w
        ft.node.rotation = rot.Quaternion
        ft.prevRotationMatrix = ft.node.rotation.toMatrix4()

registerComponent(FixTransform, "Falcon")
