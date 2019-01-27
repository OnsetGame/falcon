## Simple progress bar that uses `Solid` component as filling bar. You can set
## thickness, color, direction (0.0 top, 90.0 right, 180.0 bottom and
## 270.0 is left). You need to provide how much sections you want and which
## length one section is, also where to put node with progress bar:
##
## .. code-block:: Nim
##   const sections = 100
##   const oneSectionLength = 1.0
##   var bar = newProgressBarSolid(sections, oneSectionLength, someNode)
##   bar.thickness = 50.0
##   bar.color = newColor(0.5, 0.5, 0.5)
##   bar.position = newVector3(560.0, 240.0, 0.0)
##   bar.progress = 0.2  # 20% filled
##
## You can control bar filling by setting `progress`.

import math

import nimx / [ types, matrixes, animation ]

import rod.node
import rod.component.solid
import rod.quaternion

import utils.helpers

type ProgressBarSolid* = ref object of RootObj
    node: Node
    solid: Solid
    mSections: int
    mSectionLength: float32
    mProgress: float32  ## \
    ## `mProgress` represents percentage in range [0.0 - 1.0]
    animate*: bool
    mAnimation: Animation
    duration*: float



proc animateProgress(bar: ProgressBarSolid, f, t: float32) =
    if not bar.mAnimation.isNil:
        bar.mAnimation.cancel()

    bar.mAnimation = newAnimation()
    bar.mAnimation.numberOfLoops = 1
    bar.mAnimation.loopDuration = bar.duration
    bar.mAnimation.cancelBehavior = cbJumpToEnd
    bar.mAnimation.onAnimate = proc(p: float) =
        bar.node.scaleY = round(interpolate(f, t, p) / bar.mSectionLength) * bar.mSectionLength
    bar.mAnimation.onComplete do():
        bar.mAnimation = nil
    bar.node.addAnimation(bar.mAnimation)

proc calculate(bar: ProgressBarSolid) =
    let to = round(bar.mSections.float32 * bar.mProgress) * bar.mSectionLength

    if bar.animate:
        bar.animateProgress(bar.node.scaleY, to)
    else:
        bar.node.scaleY = to

proc newProgressBarSolid*(s: int, sl: float32, parent: Node): ProgressBarSolid =
    result = ProgressBarSolid.new()
    result.node = newNode("progress_bar")
    result.solid = result.node.addComponent(Solid)
    result.solid.size = newSize(10.0, 1.0)
    result.solid.color = newColor(1.0, 0.0, 0.0)
    result.mSections = s
    result.mSectionLength = sl
    result.mProgress = 0.0
    result.animate = false
    result.duration = 0.5
    result.calculate()
    parent.addChild(result.node)

proc rootNode*(bar: ProgressBarSolid): Node = bar.node

proc thickness*(bar: ProgressBarSolid): float32 = bar.solid.size.width
proc `thickness=`*(bar: ProgressBarSolid, v: float32) =
    bar.solid.size.width = v
    bar.node.anchor = newVector3(v * 0.5, 1.0, 0.0)

proc color*(bar: ProgressBarSolid): Color = bar.solid.color
proc `color=`*(bar: ProgressBarSolid, c: Color) = bar.solid.color = c

proc sections*(bar: ProgressBarSolid): int = bar.mSections
proc `sections=`*(bar: ProgressBarSolid, v: int) =
    bar.mSections = v
    bar.calculate()

proc sectionLength*(bar: ProgressBarSolid): float32 = bar.mSectionLength
proc `sectionLength=`*(bar: ProgressBarSolid, v: float32) =
    bar.mSectionLength = v
    bar.calculate()

proc progress*(bar: ProgressBarSolid): float32 = bar.mProgress
proc `progress=`*(bar: ProgressBarSolid, v: float32) =
    bar.mProgress = clamp(v, 0.0, 1.0)
    bar.calculate()

proc position*(bar: ProgressBarSolid): Vector3 = bar.node.position
proc `position=`*(bar: ProgressBarSolid, v: Vector3) =
    bar.node.position = v

proc rotation*(bar: ProgressBarSolid): float32 = bar.node.rotation.z
proc `rotation=`*(bar: ProgressBarSolid, r: float32) =
    let old = bar.node.rotation
    bar.node.rotation = newQuaternionFromEulerXYZ(
        old.x, old.y, clamp(r, 0.0, 360.0)
    )
