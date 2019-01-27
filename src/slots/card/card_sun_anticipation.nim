import rod / [ node, component ]
import nimx / [ animation, matrixes ]
import utils.helpers
import math
import tables

const VANISHING_POINT* = -1000

type SunDeathType* = enum
    FlyAway,
    Fade,
    InstaKill

type SunTailComponent* = ref object of Component
    shiftSpeed*: float32
    prevYPos*: float
    behaviour*: int #1 = moveIn, 2 = moveIdle, 3 = moveOut
    anim*: Animation

type SunAnticipation* = ref object of RootObj
    sun_tails_field*: Node #parent node for X reels with N suns anticipation running on
    idToNode*: Table[int, Table[int, Node]]

const SUN_TAIL_MAX_SCALE_SPEED* = 1000
const SUN_TAIL_MAX_ALPHA_SPEED = 200

method init*(sa: SunAnticipation) =
    sa.sun_tails_field = nil
    sa.idToNode = initTable[int, Table[int, Node]]()

method init*(st: SunTailComponent) =
    st.shiftSpeed = 0.0
    st.anim = nil
    st.behaviour = 1
    st.prevYPos = 0.0

proc setup*(sa: SunAnticipation, parent: Node, reelsQ: int) =
    if sa.sun_tails_field == nil:
        sa.sun_tails_field = newNode("sun_tails_field")
        parent.addChild(sa.sun_tails_field)
        for i in 0 .. < reelsQ:
            sa.idToNode[i] = initTable[int, Node]()

#DeathType: 0 - fly, 1 - stand still, 2 - insta die
proc removeSunTail*(sa: SunAnticipation, uid: int, reelID: int, deathType: SunDeathType) =
    if not sa.sun_tails_field.isNil:
        let sun_tail = sa.idToNode[reelID][uid]

        let stComponent = sun_tail.getComponent(SunTailComponent)

        case deathType
            of FlyAway:
                
                let a = newAnimation()  #W8 3 seconds before killing object
                a.numberOfLoops = 1
                a.loopDuration = 1.0
                a.onAnimate = proc(p:float) =
                    let dt = getDeltaTime()
                    sun_tail.positionY = sun_tail.positionY + dt * stComponent.shiftSpeed
                a.onComplete do():
                    sun_tail.removeFromParent(true)

                sa.sun_tails_field.addAnimation(a)
                sa.idToNode[reelID].del(uid)
            of Fade:
                let a = newAnimation()  #W8 1 second before starting fade animation
                a.numberOfLoops = 1
                a.loopDuration = 1.0

                proc fade() =
                    let fadeAnim = newAnimation()  #W8 3 seconds before killing object
                    fadeAnim.numberOfLoops = 1
                    fadeAnim.loopDuration = 0.5
                    fadeAnim.onAnimate = proc(p: float) =
                        sun_tail.findNode("sun_tail_fire").alpha = interpolate(1.0, 0.0, p)
                    sa.sun_tails_field.addAnimation(fadeAnim)
                a.addLoopProgressHandler(0.25, false, fade)
                a.timingFunction = bezierTimingFunction(0.2, 1.06, 0.79, 0.98)
                a.onAnimate = proc(p: float) =
                    sun_tail.findNode("sun_tail_fire").mScale.y = interpolate(3.0, 0.5, p)
                    sun_tail.findNode("sun_tail_fire").mScale.x = interpolate(1.3, 1.0, p)
                    sun_tail.findNode("sun_tail_fire").mAnchorPoint.x = interpolate(0.0, -60.0, p)
                a.onComplete do():
                    var anim = newAnimation()
                    anim.loopDuration = 0.15
                    anim.numberOfLoops = 1
                    anim.onAnimate = proc(p: float) =
                        sun_tail.findNode("shining").alpha = interpolate(1.0, 0.0, p)
                    anim.onComplete do():
                        sun_tail.removeFromParent(true)
                        sa.idToNode[reelID].del(uid)
                    sa.sun_tails_field.addAnimation(anim)

                sa.sun_tails_field.addAnimation(a)
            of InstaKill:
                sun_tail.removeFromParent(true)
                sa.idToNode[reelID].del(uid)
            else:
                discard

proc updateSunTail*(sa: SunAnticipation, uid: int, reelID: int, positionY: float) =
    let sun_tail = sa.idToNode[reelID][uid]
    let stComponent = sun_tail.getComponent(SunTailComponent)
    let dt = getDeltaTime()
    sun_tail.positionY = positionY - 270.0
    stComponent.prevYPos = positionY

proc createSunTail*(sa: SunAnticipation, uid: int, reelID: int, pos: Vector3, shiftSpeed: float32) =
    const tail_offsetX = 257.0
    const tail_offsetY = 160.0
    let sun_tail = newNode("sun_tail_" & $uid)
    let sun = newNodeWithResource("slots/card_slot/elements/precomps/sun_idle")
    sun.scale = newVector3(0.9, 0.9, 1.0)
    sun.positionY = 255
    sun.positionX = 122
    let sun_tail_fire = newNodeWithResource("slots/card_slot/specials/precomps/sun_tail_fire")
    sun_tail_fire.positionY = sun_tail_fire.positionY + 350
    sun_tail_fire.positionX = sun_tail_fire.positionX - 60
    sun_tail_fire.mAnchorPoint.y = 150
    sun_tail_fire.mScale.x = 1.3
    sun_tail_fire.mScale.y = 3.0
    sun_tail.addChild(sun_tail_fire)
    sun_tail.addChild(sun)

    var stComponent = sun_tail.addComponent(SunTailComponent)
    stComponent.shiftSpeed = shiftSpeed

    sun_tail.position = pos
    sun_tail.positionX = sun_tail.positionX - tail_offsetX
    sun_tail.positionY = sun_tail.positionY - tail_offsetY

    sa.sun_tails_field.addChild(sun_tail)
    sa.idToNode[reelID][uid] = sun_tail

    let anim = sun_tail_fire.animationNamed("suntail_anticipate")
    anim.cancelBehavior = cbJumpToStart
    anim.numberOfLoops = -1

    stComponent.anim = anim
    sun_tail.addAnimation(anim)

registerComponent(SunTailComponent, "SunAnticipationComponents")
