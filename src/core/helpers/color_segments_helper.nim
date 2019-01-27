import utils / [ color_segments, helpers ]
import rod / [ rod_types, node ]
import rod / component / [tint]
import nimx / [matrixes, types]


type CardStyle* {.pure.} = enum
    Coffee
    Orange
    Aqua
    Purple
    Grey
    

type ColorSegmentsConf* = tuple
    angle1, angle2: float
    colors: array[4, Color] # left, top, right, bottom

const CoffeeSegmentsConf* = (
    angle1: 15.0,
    angle2: -15.0,
    colors: [
        newColor(0.898, 0.765, 0.494, 1.0),
        newColor(0.863, 0.725, 0.471, 1.0),
        newColor(0.792, 0.651, 0.42, 1.0),
        newColor(0.722, 0.576, 0.373, 1.0)
    ]
)

const Coffee2SegmentsConf* = (
    angle1: 0.0,
    angle2: 15.0,
    colors: CoffeeSegmentsConf.colors
)

const GraySegmentsConf* = (
    angle1: 0.0,
    angle2: 15.0,
    colors: [
        newColor(0.68, 0.68, 0.68, 1.0),
        newColor(0.71, 0.71, 0.71, 1.0),
        newColor(0.62, 0.62, 0.62, 1.0),
        newColor(0.55, 0.55, 0.55, 1.0)
    ]
)

const OrangeSegmentsConf* = (
    angle1: 0.0,
    angle2: 15.0,
    colors: [
        newColor(0.94, 0.698, 0.247, 1.0),
        newColor(0.929, 0.647, 0.235, 1.0),
        newColor(0.874, 0.541, 0.25, 1.0),
        newColor(0.815, 0.431, 0.294, 1.0)
    ]
)

const OrangeSegmentsConf0* = (
    angle1: 0.0,
    angle2: 0.0,
    colors: OrangeSegmentsConf.colors
)

const AquaCardSegmentsConf* = (
    angle1: 0.0,
    angle2: 15.0,
    colors: [
        newColor(70/255, 183/255, 212/255, 1.0),
        newColor(68/255, 170/255, 206/255, 1.0),
        newColor(68/255, 141/255, 187/255, 1.0),
        newColor(71/255, 112/255, 165/255, 1.0)
    ]
)

const AquaCardSegmentsConf0* = (
    angle1: 0.0,
    angle2: 0.0,
    colors: AquaCardSegmentsConf.colors
)

const GreenSegmentsConf* = (
    angle1: 0.0,
    angle2: 0.0,
    colors: [
        newColor(159/255, 199/255, 72/255, 1.0),
        newColor(118/255, 178/255, 75/255, 1.0),
        newColor(138/255, 189/255, 74/255, 1.0),
        newColor(179/255, 210/255, 72/255, 1.0)
    ]
)

const DeepGreenSegmentConf* = (
    angle1: 0.0,
    angle2: 15.0,
    colors: [
        newColor(142/255, 197/255, 74/255, 1.0),
        newColor(126/255, 186/255, 72/255, 1.0),
        newColor(93/255, 162/255, 64/255, 1.0),
        newColor(61/255, 137/255, 55/255, 1.0)
    ]
)

const DeepGreenSegmentConf0* = (
    angle1: 0.0,
    angle2: 0.0,
    colors: DeepGreenSegmentConf.colors
)

const RedSegmentConf* = (
    angle1: 0.0,
    angle2: 15.0,
    colors: [
        newColor(217/255, 62/255, 30/255, 1.0),
        newColor(204/255, 49/255, 36/255, 1.0),
        newColor(204/255, 49/255, 36/255, 1.0),
        newColor(177/255, 24/255, 47/255, 1.0)
    ]
)

const VioletSegmentsConf* = (
    angle1: 0.0,
    angle2: 15.0,
    colors: [
        newColor(154/255, 14/255, 237/255, 1.0),
        newColor(137/255, 29/255, 219/255, 1.0),
        newColor(137/255, 29/255, 219/255, 1.0),
        newColor(103/255, 58/255, 183/255, 1.0)
    ]
)

proc colorSegmentsForNode*(n:Node, conf = CoffeeSegmentsConf) =
    var cs = n.componentIfAvailable(ColorSegments)
    if cs.isNil:
        cs = n.addComponent(ColorSegments, 0)
    cs.angle1 = conf.angle1
    cs.angle2 = conf.angle2
    cs.color1 = conf.colors[0]
    cs.color2 = conf.colors[1]
    cs.color3 = conf.colors[2]
    cs.color4 = conf.colors[3]


proc grayColorSlotNameRect*(node: Node) =
    let tint = node.component(Tint)
    tint.white = newColor(0.55, 0.55, 0.55)
    tint.black = newColor(0.71, 0.71, 0.71)

proc coffeeColorSlotNameRect*(node: Node) =
    let tint = node.component(Tint)
    tint.white = newColor(0.76, 0.59, 0.39)
    tint.black = newColor(0.93, 0.79, 0.53)

proc aquaColorSlotNameRect*(node: Node) =
    let tint = node.component(Tint)
    tint.white = newColor(0.28, 0.44, 0.64)
    tint.black = newColor(0.27, 0.72, 0.83)

proc violetColorSlotNameRect*(node: Node) =
    let tint = node.component(Tint)
    tint.white = newColor(103/255, 59/255, 183/255)
    tint.black = newColor(151/255, 8/255, 243/255)

proc orangeColorSlotNameRect*(node: Node) =
    let tint = node.component(Tint)
    tint.white = newColor(0.95, 0.39, 0.27)
    tint.black = newColor(1.0, 0.68, 0.18)
