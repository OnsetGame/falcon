import nimx.animation
import rod.rod_types
import rod.node
import nimx.matrixes
import nimx.types
import rod.quaternion
import rod.component
import rod.component.solid
import rod.viewport
import nimx.property_visitor
import random
import helpers
import math
import perlin

type NAPropertyType* {.pure.} = enum
    position2d
    position3d
    scale2d
    scale3d
    rotation2d
    rotation3d
    alpha
    color

type BaseNodeAnimation* = ref object of Component
    animation*: Animation
    animName*: string
    propType: NAPropertyType

method init*(c: BaseNodeAnimation)=
    c.animName = "BaseNodeAnimation"
    c.animation = newAnimation()
    c.animation.numberOfLoops = -1
    c.animation.loopDuration = 1.0

method visitProperties*(c: BaseNodeAnimation, p: var PropertyVisitor) =
    p.visitProperty("animName", c.animName)
    # p.visitProperty("propType", c.propType)

proc stopAnimation*(c: BaseNodeAnimation)=
    if not c.animation.isNil:
        c.animation.cancel()

method componentNodeWillBeRemovedFromSceneView*(c: BaseNodeAnimation) =
    c.stopAnimation()

type WiggleAnimationProperty* = ref object
    propType*: NAPropertyType
    startVal*: float
    rndNoise: float
    curNoiseVal: float
    noiseValTo: float
    noiseValFrom: float
    curLoop: int
    noise: Noise
    noiseType: NoiseType
    animSpeed: float

proc setNoise*(prop: WiggleAnimationProperty, oct: int, per: float)=
    prop.noise = newNoise(oct, per)

proc createProperty*(st: float, oct: int, per: float): WiggleAnimationProperty=
    result.new()
    result.rndNoise = rand(1'f32)
    result.startVal = st
    result.curNoiseVal = 0.5
    result.curLoop = -1
    result.setNoise(oct, per)
    result.animSpeed = 0.0
    result.noiseValTo = 0.5
    # result.noise.get(result.noiseType, 0.0, result.rndNoise)

proc nextDestination*(prop: WiggleAnimationProperty, loop: int)=
    prop.curLoop = loop
    prop.rndNoise = rand(1'f32)
    prop.noiseValFrom = prop.noiseValTo
    # prop.curNoiseVal = prop.noiseValFrom
    prop.noiseValTo = prop.noise.get(prop.noiseType, loop.float, prop.rndNoise)

proc interpolate*(prop: WiggleAnimationProperty, amount: float, loopProg: float, loop: int): float=
    if prop.curLoop < 0: # started
        prop.curLoop = 0
        prop.nextDestination(loop)

    var np: float

    if prop.curLoop != loop:
        prop.nextDestination(loop)

    np = interpolate(prop.noiseValFrom, prop.noiseValTo, loopProg)

    case prop.propType:
    of NAPropertyType.alpha:
        result = interpolate(1.0 - amount, 1.0, np)
    of NAPropertyType.color:
        result = interpolate(0.0, prop.startVal, np)
    of NAPropertyType.scale2d, NAPropertyType.scale3d:
        result = max(0.0, interpolate(prop.startVal - amount, prop.startVal + amount, np))
    else:
        result = interpolate(prop.startVal - amount, prop.startVal + amount, np)

type WiggleAnimation* = ref object of BaseNodeAnimation
    octaves*: int
    persistance*: float
    animProps*: seq[WiggleAnimationProperty]
    amount*: float
    mEnabled: bool

proc cosineInterpolate*(a,b,p: float): float=
    let pi_mod = p * PI
    let p2 = (1.0 - cos(pi_mod)) * 0.5
    result = a * (1.0 - p2) + b * p

proc noiseType*(c: WiggleAnimation): NoiseType=
    if c.animProps.len > 0:
        result = c.animProps[0].noiseType

proc `noiseType=`*(c: WiggleAnimation, t: NoiseType)=
    for prop in c.animProps:
        prop.noiseType = t

proc propertyType*(c: WiggleAnimation): NAPropertyType=
    result = c.propType

proc `propertyType=`*(c: WiggleAnimation, val: NAPropertyType)=
    c.propType = val
    c.animProps = @[]
    var propsLen = 0

    case val:
    of NAPropertyType.position2d, NAPropertyType.scale2d:
        propsLen = 2
    of NAPropertyType.position3d, NAPropertyType.scale3d:
        propsLen = 2
    of NAPropertyType.alpha:
        propsLen = 1
    of NAPropertyType.color:
        propsLen = 3
    else:
        discard

    case val:
    of NAPropertyType.position2d, NAPropertyType.position3d:
        for i in 0..<propsLen:
            let prop = createProperty(c.node.position[i], c.octaves, c.persistance)
            prop.propType = val
            c.animProps.add(prop)

    of NAPropertyType.alpha:
        let prop = createProperty(c.node.alpha, c.octaves, c.persistance)
        prop.propType = val
        c.animProps.add(prop)

    of NAPropertyType.scale2d, NAPropertyType.scale3d:
        for i in 0..<propsLen:
            let prop = createProperty(c.node.scale[i], c.octaves, c.persistance)
            prop.propType = val
            c.animProps.add(prop)

    of NAPropertyType.color:
        if not c.node.componentIfAvailable(Solid).isNil:
            let sol = c.node.component(Solid)
            var prop = createProperty(sol.color.r, c.octaves, c.persistance)
            prop.propType = val
            c.animProps.add(prop)

            prop = createProperty(sol.color.g, c.octaves, c.persistance)
            prop.propType = val
            c.animProps.add(prop)

            prop = createProperty(sol.color.b, c.octaves, c.persistance)
            prop.propType = val
            c.animProps.add(prop)
    of NAPropertyType.rotation2d:
        let prop = createProperty(-(c.node.rotation.eulerAngles[2]), c.octaves, c.persistance)
        prop.propType = val
        c.animProps.add(prop)
    else:
        discard

proc updateState(c: WiggleAnimation) =
    if c.mEnabled:
        c.propertyType = c.propertyType

        c.node.registerAnimation(c.animName, c.animation)
        c.node.addAnimation(c.animation)

        c.animation.onAnimate = proc(p:float)=
            let cl = c.animation.curLoop
            case c.propType:
            of NAPropertyType.position2d, NAPropertyType.position3d:
                var pos = c.node.position
                for i, prop in c.animProps:
                    pos[i] = prop.interpolate(c.amount, p, cl)
                c.node.position = pos

            of NAPropertyType.scale2d, NAPropertyType.scale3d:
                var scl = c.node.scale
                for i, prop in c.animProps:
                    scl[i] = prop.interpolate(c.amount, p, cl)
                c.node.scale = scl
            of NAPropertyType.alpha:
                c.node.alpha = c.animProps[0].interpolate(c.amount, p, cl)
            of NAPropertyType.color:
                if not c.node.componentIfAvailable(Solid).isNil:
                    let sol = c.node.component(Solid)
                    sol.color.r = c.animProps[0].interpolate(c.amount, p, cl)
                    sol.color.g = c.animProps[1].interpolate(c.amount, p, cl)
                    sol.color.b = c.animProps[2].interpolate(c.amount, p, cl)
            of NAPropertyType.rotation2d:
                c.node.rotation = newQuaternionFromEulerYXZ(0.0, 0.0, c.animProps[0].interpolate(c.amount, p, cl))
                let rot = c.node.rotation
            else:
                discard
    else:
        c.animation.cancel()
        discard

method componentNodeWasAddedToSceneView*(c: WiggleAnimation) =
    c.updateState()

proc enabled*(c: WiggleAnimation): bool=
    result = c.animProps.len > 0 and c.animProps[0].curLoop >= 0

proc `enabled=`*(c: WiggleAnimation, val: bool)=
    c.mEnabled = val

    if not c.node.sceneView.isNil:
        c.updateState()

proc animationSpeed*(c: WiggleAnimation): float =
    if c.animProps.len > 0:
        result = c.animProps[0].animSpeed * 10000.0

proc `animationSpeed=`*(c: WiggleAnimation, val: float)=
    for prop in c.animProps:
        prop.animSpeed = val / 10000.0

method visitProperties*(c: WiggleAnimation, p: var PropertyVisitor) =
    procCall c.BaseNodeAnimation.visitProperties(p)
    p.visitProperty("octaves", c.octaves)
    p.visitProperty("persistance", c.persistance)
    p.visitProperty("noiseType", c.noiseType)
    p.visitProperty("amount", c.amount)
    p.visitProperty("loopDuration", c.animation.loopDuration)
    p.visitProperty("curLoop", c.animation.curLoop)
    p.visitProperty("enabled", c.enabled)
    p.visitProperty("animationSpeed", c.animationSpeed)
    p.visitProperty("propertyType", c.propertyType)

method init*(c: WiggleAnimation)=
    procCall c.BaseNodeAnimation.init()
    c.animName = "WiggleAnimation"
    c.octaves = 2

registerComponent(WiggleAnimation, "Falcon")
