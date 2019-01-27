import tables, queues, random, json, strutils, sequtils, math, times, logging

import nimx / [ view, image, button, animation, timer, slider, font, matrixes,
                notification_center ]

import rod / [ node, viewport, component, asset_bundle, animated_image, quaternion,
                scene_composition ]
import rod / component / [ sprite, particle_emitter, text_component, visual_modifier,
           blur_component, ui_component, solid, mesh_component, particle_system,
           material, fxaa_post, light, clipping_rect_component, trail ]

import shared / [ user, chips_animation, localization_manager,
                win_popup ]
import core / slot / [base_slot_machine_view]

import utils / [ sound, sound_manager, falcon_analytics, falcon_analytics_helpers,
                falcon_analytics_utils, pause, helpers ]
import quest.quests
import core.net.server
import falconserver.slot.slot_data_types

import balloon_composition
import line_composition
import cell_rails
import rocket_controller

import clouds_component
import balloon_response
import win_numbers
import glitch_component
import animedit
import mesh_instance
import text_component_mask
import hard_billboard
import bonus_game_panel

import shared / gui / [ gui_module, gui_pack, gui_module_types, win_panel_module,
           total_bet_panel_module, paytable_open_button_module, spin_button_module,
           money_panel_module, autospins_switcher_module, balloon_free_spins_module, slot_gui ]

import shared / window / [window_manager, window_component, button_component]
import core / flow / flow_state_types

const resPath = "slots/balloon_slot/"
const SOUND_PATH_PREFIX = resPath & "balloon_sound/"
const NUMBER_OF_REELS = 5
const BETWEEN_CELL_STEP = 15
const STANDART_Y_SHIFT = -78.5
const CAMERA_Z_IN_STANDART = 130.0
var   WILD_INDEX = 1
var   BONUS_INDEX = 1
var   KITE_INDEX = 4
var   BALLOON_SLOT_SPEED = 0.72
var   BALLOON_SLOT_SPEED_FLY = 0.62

const CAMERA_POS_Y = 0.0
const SKY_SCALE = 2.5
const SKY_DEST_SCALE = 3.0
const SUN_SCALE = 1.5
const CAMERA_IN_STANDART = newVector3(0.0, 0.0, 0.0)
const CAMERA_IN_PAYTABLE = newVector3(0.0, -17.0, -150.0)

type Materials = enum
    WILD_MAT
    BONUS_MAT
    SNAKE_MAT
    GLIDER_MAT
    KITE_MAT
    FLAG_MAT
    GREEN_MAT
    RED_MAT
    BLUE_MAT
    YELLOW_MAT
    ROCKET_MAT

type MatCaps = enum
    BLACK
    BLUE
    PINK
    RED
    GREEN
    YELLOW
    WHITE_BLUE
    WHITE_GREEN
    WHITE_RED
    WHITE_YELLOW
    FOIL_BLUE
    FOIL_GOLD
    FOIL_GREEN
    RED_FIREWORKS

type Bigwins = enum
    SIMPLE
    BIGWIN
    HUGEWIN
    MEGAWIN
    JACKPOT

type MusicType {.pure.} = enum
    Main,
    Bonus,
    Freespins

type
    PaytableServerData* = tuple
        itemset: seq[string]
        paytableSeq: seq[seq[int]]
        freespTriggerId: string
        freespRelation: seq[tuple[triggerCount: int, freespinCount: int]]
        bonusTriggerId: string
        bonusCount: int
        minRockets: int
        maxRockets: int

type
    BalloonSlotView* = ref object of BaseMachineView
        destructionsCounter: int
        isInFreeSpins: bool
        isInBonusGame: bool

        bonusQueue: Queue[BonusResponse]
        bonusPayouts: OrderedTable[int, int64]
        currResponse: Response
        prevResponse: Response

        balloonsLib: seq[MeshComponent]
        balloonPlayfield: seq[CellRail]
        linesLib: seq[LineComposition]

        rootCameraNode: Node
        cameraNode: Node
        textWinNode: Node
        # airplaneNode: Node

        playBonusInAnimation: proc(callback: proc())
        playBonusOutAnimation: proc(callback: proc())
        playFreespinAnimation: proc(callback: proc())
        play5InRowAnimation: proc(callback: proc())
        playWinAnimation: seq[tuple [inAnim: proc(callback: proc()), outAnim: proc(callback: proc())]]
        fullscreenButtonsActions: seq[proc()]

        farNode: Node
        nearNode: Node

        freespinController: GUIModule
        freespinControllerAnimation: seq[tuple[anim: Animation, visible: bool]]
        freespinDestructions: int

        rocketTrailFire: AnimatedImage
        bonusDestroyImages: seq[Image]

        idleAnimations: seq[Animation]

        matcaps: seq[Image]

        touchBlocked: bool

        gPrevBalance: int64
        gTotalRoundWin: int64
        gTarget: int

        shakeWorldAnim: Animation
        shakeCameraAnim: Animation
        textWinAnimIn: Animation

        bonusPanel: BonusGamePanel
        totalBonusWin: int64

        music: Table[string, bool]
        wildsSound: seq[Sound]

        introAnimsNodes: seq[Node]
        introAnims: seq[Animation]

        winWindowDestroyProc: proc()
        winWindowReadyForDestroy*: bool

        pd*: PaytableServerData
        bonusConfigRelation: seq[int]

template blockTouch(v: BalloonSlotView) = v.touchBlocked = true
template releaseTouch(v: BalloonSlotView) = v.touchBlocked = false
template fadeHide(n: Node) = n.hide(0.2)
template fadeHide(n: Node, callback: proc()) = n.hide(0.2, callback)
template fadeShow(n: Node) = n.show(0.25)

const DEFAULT_MUSIC_FADE_TIME = 4.0
proc playMusic(v: BalloonSlotView, name: string, fadeTime: float = DEFAULT_MUSIC_FADE_TIME, needFade: bool = true): FadingSound {.discardable.} =
    if v.music.hasKey(name):
        if not v.music[name]:
            for v in mvalues v.music: v = false
            v.music[name] = true
            result = v.soundManager.playMusic(name, fadeTime, needFade)
    else:
        for v in mvalues v.music: v = false
        v.music[name] = true
        result = v.soundManager.playMusic(name, fadeTime, needFade)

proc playBackgroundMusic(v: BalloonSlotView, m: MusicType) =
    var music: FadingSound
    case m
    of MusicType.Main:
        music = v.playMusic(SOUND_PATH_PREFIX & "balloon_main_game_music", 0.8)
    of MusicType.Freespins:
        music = v.playMusic(SOUND_PATH_PREFIX & "balloon_free_spins_music", 0.8)
    of MusicType.Bonus:
        music = v.playMusic(SOUND_PATH_PREFIX & "balloon_bonus_game_music", 0.8)
    if not music.isNil: music.setLooping(true)

proc generatePlayfield(v: BalloonSlotView, splashSeq, backSeq, frontSeq, backDestrSeq, frontDestrSeq: seq[Image], parent: Node): seq[CellRail] =
    var playfield = newSeq[CellRail]()
    let rotAnimPath = resPath & "anim/rotation.dae"
    let bounceAnimPath = resPath & "anim/bounce.dae"
    let offsetX = 0.0
    let offsetY = 0.0
    let rows = @[4,3,2,1,0]
    let cols = @[0,1,2,3,4]
    var cellId = 0

    var isNear = false
    var offsetZ = 0.0

    for i in rows:
        for j in cols:

            let rail = newCellRailWithResource(resPath & "anim/rails.dae", cellId.int8)
            rail.translation = newVector3((BETWEEN_CELL_STEP*j).Coord + offsetX, (BETWEEN_CELL_STEP*i).Coord + offsetY, if isNear: offsetZ else: -offsetZ)
            rail.balloon = newBalloonCompositionWithResource(rotAnimPath, bounceAnimPath, splashSeq, backSeq, frontSeq, backDestrSeq, frontDestrSeq, cellId.int8)
            rail.balloon.meshIndex = -1
            rail.balloon.anchor.scale = newVector3(1.1,1.1,1.1)
            parent.addChild(rail.anchor)
            playfield.add(rail)
            inc cellId

    result = playfield

proc playBounce(n: Node, startY, destY, time, timeout: float32, callback: proc() = proc() = discard) =
    n.sceneView.wait timeout, proc() =
        let anim = newAnimation()
        anim.loopDuration = time
        anim.numberOfLoops = 1
        anim.animate val in startY .. destY:
            n.positionY = val
        n.sceneView().addAnimation(anim)
        anim.onComplete do():
            let anim = n.animationNamed("bounce")
            if not anim.isNil:
                n.addAnimation(anim)
            callback()

proc playAllIn(v: BalloonSlotView, balloons: seq[int8], animDuration: float32 = FLY_IN_TIME, callback: proc() = proc() = discard) =
    v.soundManager.sendEvent("REEL_SPIN_" & $rand(1 .. 2))
    var offset = if not v.isInBonusGame: NUMBER_OF_REELS else: 0
    for indx, val in balloons:
        closureScope:
            if (indx+offset) >= NUMBER_OF_REELS*NUMBER_OF_REELS:
                return

            if v.balloonPlayfield[indx+offset].balloon.meshIndex == -1 or v.balloonPlayfield[indx+offset].balloon.destroyed:
                if val == WILD_INDEX:
                    v.balloonPlayfield[indx+offset].balloon.playBackFrontIdle(BALLOON_SLOT_SPEED)
                else:
                    v.balloonPlayfield[indx+offset].balloon.hideBackFrontIdle()
                v.balloonPlayfield[indx+offset].animIn.loopDuration = (animDuration+rand(1.Coord)) * BALLOON_SLOT_SPEED_FLY
                v.balloonPlayfield[indx+offset].playIn()

                if val == BONUS_INDEX:
                    v.balloonPlayfield[indx+offset].playSlowIdle()
                elif val == WILD_INDEX:
                    v.balloonPlayfield[indx+offset].playFastIdle()
                else:
                    v.balloonPlayfield[indx+offset].playIdle()

                # 0"Wild",
                # 1"Bonus",
                # 2"Snake"->Dog,
                # 3"Glider"->Star,
                # 4"Kite"->Fish,
                # 5"Flag"->Heart,
                # 6"Red",
                # 7"Yellow",
                # 8"Green",
                # 9"Blue"
                # var items = ["Wild", "Bonus", "Snake", "Glider", "Kite", "Flag", "Red", "Yellow", "Green", "Blue"]

                for c in v.balloonPlayfield[indx+offset].balloon.balloonNode.children:
                    c.hide()

                v.balloonPlayfield[indx+offset].anchor.positionZ = 0.0
                v.balloonPlayfield[indx+offset].balloon.balloonNode.scale = newVector3(1.0,1.0,1.0)

                if val == WILD_INDEX:
                    v.wildsSound[indx+offset] = v.soundManager.playSFX(SOUND_PATH_PREFIX & "balloon_wild_win")
                    v.wildsSound[indx+offset].trySetLooping(true)
                if val == BONUS_INDEX:
                    let stripeNode = v.balloonPlayfield[indx+offset].balloon.balloonNode.findNode("stripe")
                    if stripeNode.isNil:
                        let nd = newNodeWithResource(resPath & "models/balloons/stripe.json")
                        nd.position = newVector3(-2.0,-4.2,-0.0)
                        let stripe = nd.componentIfAvailable(Trail)
                        let anim = newAnimation()
                        anim.loopDuration = 60.0
                        anim.numberOfLoops = -1

                        let randSign = rand([-1, 1])
                        let amplitude = rand([-5.0'f32, -5.5, -6.0, -6.6])

                        if randSign == 1:
                            anim.animate val in 0.0 .. 360.0:
                                stripe.gravity[1] = amplitude+cos(val)*amplitude
                        else:
                            anim.animate val in 0.0 .. 360.0:
                                stripe.gravity[1] = amplitude+sin(val)*amplitude

                        v.balloonPlayfield[indx+offset].balloon.balloonNode.addChild(nd)
                        v.addAnimation(anim)

                        stripe.trailMatcap = v.matcaps[FOIL_GOLD.int]
                    else:
                        stripeNode.show()
                        stripeNode.position = newVector3(-2.0,-4.2,-0.0)
                        let stripe = stripeNode.componentIfAvailable(Trail)
                        stripe.trailMatcap = v.matcaps[FOIL_GOLD.int]

                    var rocketPlaceholder = v.balloonPlayfield[indx+offset].balloon.balloonNode.findNode("place")
                    if rocketPlaceholder.isNil:
                        rocketPlaceholder = newNodeWithResource(resPath & "models/balloons/rocket_placeholder.json")
                        v.balloonPlayfield[indx+offset].balloon.balloonNode.addChild(rocketPlaceholder)
                        rocketPlaceholder.findNode("place_1").addChild(newNodeWithResource(resPath & "models/balloons/rocket.json"))
                        rocketPlaceholder.findNode("place_2").addChild(newNodeWithResource(resPath & "models/balloons/rocket.json"))
                    else:
                        rocketPlaceholder.show()

                elif val == 4:
                    v.balloonPlayfield[indx+offset].anchor.positionZ = 8.0
                elif val == 3 or val == 5 or val == 6 or val == 7 or val == 8 or val == 9: # simple balloon
                    let stripeNode = v.balloonPlayfield[indx+offset].balloon.balloonNode.findNode("stripe")
                    if stripeNode.isNil:
                        let nd = newNodeWithResource(resPath & "models/balloons/stripe.json")
                        nd.position = newVector3(0.0,-4.8,-0.25)
                        let stripe = nd.componentIfAvailable(Trail)
                        let anim = newAnimation()
                        anim.loopDuration = 60.0
                        anim.numberOfLoops = -1

                        let randSign = rand([-1, 1])
                        let amplitude = rand([-5.0'f32, -5.5, -6.0, -6.6])

                        if randSign == 1:
                            anim.animate val in 0.0 .. 360.0:
                                stripe.gravity[1] = amplitude+cos(val)*amplitude
                        else:
                            anim.animate val in 0.0 .. 360.0:
                                stripe.gravity[1] = amplitude+sin(val)*amplitude

                        v.balloonPlayfield[indx+offset].balloon.balloonNode.addChild(nd)
                        v.addAnimation(anim)

                        if val == 3 :
                            stripe.trailMatcap = v.matcaps[WHITE_BLUE.int]
                            nd.position = newVector3(0.0,-5.3,-0.25)
                        elif val == 5 :
                            stripe.trailMatcap = v.matcaps[WHITE_GREEN.int]
                            nd.position = newVector3(0.0,-5.6,-0.25)
                        elif val == 8 :
                            stripe.trailMatcap = v.matcaps[WHITE_GREEN.int]
                        elif val == 6:
                            stripe.trailMatcap = v.matcaps[WHITE_RED.int]
                        elif val == 9:
                            stripe.trailMatcap = v.matcaps[WHITE_BLUE.int]
                        elif val == 7:
                            stripe.trailMatcap = v.matcaps[WHITE_YELLOW.int]
                    else:
                        stripeNode.show()
                        stripeNode.position = newVector3(0.0,-4.8,-0.25)
                        let stripe = stripeNode.componentIfAvailable(Trail)
                        if val == 3 :
                            stripe.trailMatcap = v.matcaps[WHITE_BLUE.int]
                            stripeNode.position = newVector3(0.0,-5.3,-0.25)
                        elif val == 5 :
                            stripe.trailMatcap = v.matcaps[WHITE_GREEN.int]
                            stripeNode.position = newVector3(0.0,-5.6,-0.25)
                        elif val == 8 :
                            stripe.trailMatcap = v.matcaps[WHITE_GREEN.int]
                        elif val == 6:
                            stripe.trailMatcap = v.matcaps[WHITE_RED.int]
                        elif val == 9:
                            stripe.trailMatcap = v.matcaps[WHITE_BLUE.int]
                        elif val == 7:
                            stripe.trailMatcap = v.matcaps[WHITE_YELLOW.int]

                v.balloonPlayfield[indx+offset].balloon.setupMesh(v.balloonsLib[val])
                v.balloonPlayfield[indx+offset].balloon.meshIndex = val
            v.balloonPlayfield[indx+offset].balloon.destroyed = false
    let loopDuration = (animDuration+0.15) * BALLOON_SLOT_SPEED_FLY
    v.wait loopDuration, proc() =
        callback()

proc playAllIn(v: BalloonSlotView, callback: proc()) =
    v.playAllIn(v.currResponse.symbols, FLY_IN_TIME, callback)

proc playAllInBeforeBonus(v: BalloonSlotView, callback: proc()) =
    var balloons: seq[int8]
    balloons = @[]
    for i in 5..19:
        balloons.add(v.currResponse.symbols[i])
    v.playAllIn(balloons, FLY_IN_TIME, callback)

proc playAllOut(v: BalloonSlotView, animDuration: float32 = FLY_OUT_TIME, callback: proc() = proc() = discard, bAfterBonus: bool = false) =
    v.soundManager.sendEvent("REEL_SPIN_" & $rand(1 .. 2))

    let startIndx = if (v.isInBonusGame or bAfterBonus): 0 else: NUMBER_OF_REELS
    let finishIndx = if (v.isInBonusGame or bAfterBonus): NUMBER_OF_REELS*5 else: NUMBER_OF_REELS*4
    for i in startIndx..<finishIndx:
        closureScope:
            v.balloonPlayfield[i].animOut.loopDuration = (animDuration+rand(1.Coord)) * BALLOON_SLOT_SPEED_FLY*1.3
            v.balloonPlayfield[i].playOut()
            v.balloonPlayfield[i].stopIdle()
            v.balloonPlayfield[i].balloon.meshIndex = -1
            v.balloonPlayfield[i].balloon.destroyed = true

    let loopDuration = (animDuration+0.15) * BALLOON_SLOT_SPEED_FLY*1.3
    v.wait loopDuration, proc() =
        for w in v.wildsSound:
            if not w.isNil:
                w.stop()
        v.wildsSound = newSeq[Sound](25)
        callback()

proc playAllOut(v: BalloonSlotView, callback: proc() = proc() = discard) =
    v.playAllOut(FLY_OUT_TIME, callback)

proc playOutAfterBonus(v: BalloonSlotView, callback: proc() = proc() = discard) =
    v.soundManager.sendEvent("REEL_SPIN_" & $rand(1 .. 2))
    let animDuration: float32 = FLY_OUT_TIME
    for i in 0..<5:
        closureScope:
            v.balloonPlayfield[i].animOut.loopDuration = (animDuration+rand(2000.Coord)/2000.0) * BALLOON_SLOT_SPEED_FLY*1.3
            v.balloonPlayfield[i].playOut()
            v.balloonPlayfield[i].stopIdle()
            v.balloonPlayfield[i].balloon.meshIndex = -1
            v.balloonPlayfield[i].balloon.destroyed = true
    for i in 20..<25:
        closureScope:
            v.balloonPlayfield[i].animOut.loopDuration = (animDuration+rand(2000.Coord)/2000.0) * BALLOON_SLOT_SPEED_FLY*1.3
            v.balloonPlayfield[i].playOut()
            v.balloonPlayfield[i].stopIdle()
            v.balloonPlayfield[i].balloon.meshIndex = -1
            v.balloonPlayfield[i].balloon.destroyed = true
    let loopDuration = (animDuration+0.15) * BALLOON_SLOT_SPEED_FLY*1.3
    v.wait loopDuration, proc() =
        for w in v.wildsSound:
            if not w.isNil:
                w.stop()
        v.wildsSound = newSeq[Sound](25)
        callback()

proc playLines(v: BalloonSlotView, callback: proc() = proc() = discard) =
    if v.currResponse.lines.len == 0:
        callback()
        return

    type Interpolation = enum
        Sinus
        Cosinus
        None

    proc playLineSound(delay: float32) =
        v.wait(delay) do(): v.soundManager.sendEvent("WIN_LINE")

    proc moveThroughPoints(n: Node, targets: seq[Vector3], duration: float32, interpolateType: Interpolation = None) =
        if targets.len <= 1:
            return
        let singleStepDuration = duration/targets.len.float32
        var prevPosition = targets[0]
        var z = prevPosition[2]
        var curveAmplitude = 3.0

        proc doAnim(n: Node, fr, to: Vector3, callback: proc()) =
            var a = newAnimation()
            a.loopDuration = singleStepDuration
            a.numberOfLoops = 1

            var amplitude: proc(p: float): float32
            case interpolateType:
            of Sinus:
                amplitude = proc(p: float): float32 = return sin(p/curveAmplitude)
            of Cosinus:
                amplitude = proc(p: float): float32 = return cos(p/curveAmplitude)
            else:
                amplitude = proc(p: float): float32 = return 0.0

            a.onAnimate = proc(p: float) =
                let mu2 = (1-cos(p*PI))/2
                let x = interpolate(fr[0], to[0], p)
                let y =(fr[1]*(1-mu2)+to[1]*mu2) + amplitude(x)

                n.position = newVector3(x,y,z)

                var modelMatrix: Matrix4
                modelMatrix.lookAt(eye = prevPosition, center = n.position, up = newVector3(0,1,0))
                var scaleNd: Vector3
                var rotation: Vector4
                discard modelMatrix.tryGetScaleRotationFromModel(scaleNd, rotation)
                n.rotation = Quaternion(rotation)

                prevPosition = n.position

            a.onComplete do():
                a = nil
                callback()
            n.addAnimation(a)

        let threshold = targets.len-1
        var currIndex = 0
        proc doMove() =
            if currIndex < threshold:
                let strt = targets[currIndex]
                let dst = targets[currIndex+1]
                inc currIndex
                n.doAnim(strt, dst) do():
                    doMove()
            else:
                let tr = n.findNode("line_trail").componentIfAvailable(Trail)
                tr.bCollapsible = true
                tr.cutSpeed = 100.0 / BALLOON_SLOT_SPEED_FLY

                var prtcl = n.findNode("Confetti1").componentIfAvailable(ParticleSystem)
                prtcl.stop()
                prtcl = n.findNode("Confetti2").componentIfAvailable(ParticleSystem)
                prtcl.stop()

                let hideDuration = 0.25 * BALLOON_SLOT_SPEED
                let waitBeforeHide = duration - hideDuration
                n.sceneView.wait(waitBeforeHide * BALLOON_SLOT_SPEED_FLY) do():
                    n.fadeHide()
                    n.sceneView.wait(hideDuration) do():
                        n.removeFromParent()
        doMove()

    proc isOnDiagonal(i, lnIndex: int): bool =
        let ln = v.lines[lnIndex]
        if i == 0 or i == ln.len-1: return false
        if ln[i-1] < ln[i] and ln[i] < ln[i+1]: return true
        if ln[i-1] > ln[i] and ln[i] > ln[i+1]: return true
        if ln[i-1] == ln[i] and ln[i] == ln[i+1]: return true
        return false

    proc modifyPoints(points: var seq[Vector3]): seq[Vector3] =
        if points.len <= 1:
            return
        result = @[]
        result.add(points[0])
        for i in 1..points.len-2:
            result.add(interpolate(points[i-1], points[i], 0.92))
            result.add(interpolate(points[i], points[i+1], 0.08))
        result.add(points[points.len-1])

    let balloonsRoot = v.rootNode.findNode("root_anim")
    var delay = 0.0
    const FIELD_SHIFT = 5
    var lineAnimDuration = 1.0 * BALLOON_SLOT_SPEED
    var soundDelay: float32 = 0.0

    for j in 0..<v.currResponse.lines.len:
        closureScope:
            let ln = v.currResponse.lines[j]
            let index = j

            v.wait(delay) do():

                playLineSound(soundDelay)
                soundDelay += lineAnimDuration

                var positionForWinNumber: Vector3

                for j in 0..2:
                    let lineNode = v.nearNode.newChild("line")
                    let trailNode = newNodeWithResource(resPath & "particles/line_particle/line_trail.json")
                    lineNode.addChild(trailNode)
                    let tr = trailNode.componentIfAvailable(Trail)
                    let prtclNode = newNodeWithResource(resPath & "particles/line_particle/wind_balloons.json")
                    lineNode.addChild(prtclNode)

                    let orthoHeight = 17.0
                    if j == 0:
                        tr.trailHeight = 2.5*orthoHeight
                        lineNode.alpha = 0.9
                    else:
                        discard lineNode.component(VisualModifier)
                        lineNode.alpha = 1.0
                        tr.trailHeight = 1.1*orthoHeight

                    tr.angleThreshold = 0.0

                    var points = newSeq[Vector3]()
                    for i, cell in v.lines[ln.index.int]:
                        if not isOnDiagonal(i, ln.index.int):
                            let posNodeParent = v.rootNode.findNode( "cell_" & $(cell * NUMBER_OF_REELS + i + FIELD_SHIFT) )
                            let posNode = posNodeParent.findNode("balloon")
                            let worldPosNode = posNode.worldPos()
                            let reparentNd = v.rootNode.newChild()
                            reparentNd.position = worldPosNode
                            reparentNd.reparentTo(v.nearNode)
                            reparentNd.removeFromParent()
                            points.add(reparentNd.position)
                        if i == 2:
                            let posNodeParent = v.rootNode.findNode( "cell_" & $(cell * NUMBER_OF_REELS + i + FIELD_SHIFT) )
                            let posNode = posNodeParent.findNode("balloon")
                            let worldPosNode = posNode.worldPos()
                            positionForWinNumber = worldPosNode
                    # points = modifyPoints(points)
                    lineNode.position = points[0]
                    if j == 0:
                        lineNode.moveThroughPoints(points, lineAnimDuration, None)
                    elif j == 1:
                        # tr.color = newColor(0.5,0.95,1.0,1.0)
                        lineNode.moveThroughPoints(points, lineAnimDuration, Cosinus)
                    else:
                        lineNode.moveThroughPoints(points, lineAnimDuration, Sinus)

                v.rootNode.playNumber(v.nearNode, positionForWinNumber, ln.payout, lineAnimDuration)

            delay += lineAnimDuration + 0.25

    v.wait delay, proc() =
        callback()

proc getDestroy(v: BalloonSlotView) =
    let offset = if not v.isInBonusGame: NUMBER_OF_REELS else: 0
    for ln in v.currResponse.lines:
        for i in 0 ..< ln.symbols.int:
            let k = v.lines[ln.index.int][i]
            v.balloonPlayfield[k * NUMBER_OF_REELS + i + offset].balloon.destroyed = true

proc processDestroy(v: BalloonSlotView, callback: proc() = proc() = discard) =
    if not v.currResponse.hasDestruction():
        callback()
        return
    var timeout = 0.0
    var currDestroyTime = 0.9 * BALLOON_SLOT_SPEED_FLY
    let startIndx = if not v.isInBonusGame: NUMBER_OF_REELS else: 0
    let lines = if not v.isInBonusGame: 3 else: 5
    for i in startIndx..<startIndx+NUMBER_OF_REELS:
        for j in 0..<lines:
            closureScope:
                let indx = i + j * NUMBER_OF_REELS
                if v.balloonPlayfield[indx].balloon.destroyed:
                    let currTimeout = timeout
                    v.balloonPlayfield[indx].stopIdle()
                    v.balloonPlayfield[indx].balloon.playDestroy(currTimeout, BALLOON_SLOT_SPEED_FLY)

                    let splashWait = timeout + 0.275 * BALLOON_SLOT_SPEED_FLY
                    v.wait splashWait, proc()=
                        v.soundManager.sendEvent("POW_BALLON_" & $rand(1 .. 2))
                    timeout += 0.35 * BALLOON_SLOT_SPEED_FLY
    let loopDuration = currDestroyTime + timeout
    v.wait loopDuration, proc() =
        callback()

proc setupShifts(v: BalloonSlotView) =
    let startIndx = if not v.isInBonusGame: NUMBER_OF_REELS else: 0
    let finishIndx = if not v.isInBonusGame: NUMBER_OF_REELS*4 else: NUMBER_OF_REELS*5
    for i in startIndx ..< finishIndx:
        if v.balloonPlayfield[i].balloon.destroyed:
            var j = i
            while j < finishIndx:
                closureScope:
                    v.balloonPlayfield[j].balloon.shiftCells += 1
                    j += NUMBER_OF_REELS

proc resetShifts(v: BalloonSlotView) =
    for i in v.balloonPlayfield: i.balloon.shiftCells = 0

proc processShifts(v: BalloonSlotView, callback: proc() = proc() = discard) =
    let startIndx = if not v.isInBonusGame: NUMBER_OF_REELS*2 else: NUMBER_OF_REELS
    let finishIndx = if not v.isInBonusGame: NUMBER_OF_REELS*4 else: NUMBER_OF_REELS*NUMBER_OF_REELS
    let shiftTime = 0.3 * BALLOON_SLOT_SPEED_FLY.float32
    var timeout = 0.0
    let lines = if not v.isInBonusGame: 2 else: 4
    for i in startIndx..<startIndx+NUMBER_OF_REELS:
        for j in 0..<lines:
            closureScope:
                let indx = i + j * NUMBER_OF_REELS
                if v.balloonPlayfield[indx].balloon.shiftCells != 0:
                    if not v.balloonPlayfield[indx].balloon.destroyed:
                        let newParentAnchorIndex = indx - v.balloonPlayfield[indx].balloon.shiftCells * NUMBER_OF_REELS
                        let moveNode = v.balloonPlayfield[indx].balloon.balloonParent
                        let delatPos = BETWEEN_CELL_STEP * v.balloonPlayfield[indx].balloon.shiftCells.Coord
                        moveNode.translateY = -delatPos
                        swap(v.balloonPlayfield[indx], v.balloonPlayfield[newParentAnchorIndex])

                        let currTimeout = timeout
                        moveNode.playBounce(moveNode.positionY, moveNode.positionY + delatPos, shiftTime, currTimeout)
                        timeout += 0.05

                    v.balloonPlayfield[indx].balloon.shiftCells = 0
    let loopDuration = shiftTime+timeout*BALLOON_SLOT_SPEED_FLY
    v.wait loopDuration, proc() =
        callback()

proc shakeWrap(v: BalloonSlotView, nd: Node) =
    let pathLocation = resPath & "anim/camshake.dae"
    var shakeNode: Node
    loadSceneAsync pathLocation, proc(n: Node) =
        shakeNode = n.findNode("shake")
        nd.parent.addChild(shakeNode)
        nd.reparentTo(shakeNode)

proc playShake(v: BalloonSlotView) =
    if v.shakeWorldAnim.isNil:
        let nd = v.rootNode.findNode("world").parent
        v.shakeWorldAnim = nd.animationNamed("shake-anim")
        v.shakeWorldAnim.numberOfLoops = 1
        v.shakeWorldAnim.cancelBehavior = cbJumpToStart
        v.addAnimation(v.shakeWorldAnim)
        v.shakeWorldAnim.onComplete do():
            v.shakeWorldAnim.cancel()
            nd.position = newVector3()
    else:
        v.addAnimation(v.shakeWorldAnim)

    if v.shakeCameraAnim.isNil:
        let nd = v.rootNode.findNode("camera_anchor").parent
        v.shakeCameraAnim = nd.animationNamed("shake-anim")
        v.shakeCameraAnim.numberOfLoops = 1
        v.shakeCameraAnim.cancelBehavior = cbJumpToStart
        v.addAnimation(v.shakeCameraAnim)
        v.shakeCameraAnim.onComplete do():
            v.shakeCameraAnim.cancel()
            nd.position = newVector3()
    else:
        v.addAnimation(v.shakeCameraAnim)

proc afterBonusInteractives(v: BalloonSlotView)

proc emitRocket(v: BalloonSlotView, emiter, receiver: BalloonComposition, trgt: Target, awaitTime: float32 = 0.0, isLastBonus: bool = false) =
    let cellPayout = trgt.payout
    let cellMultiplier = trgt.val.int
    let cellIndex = trgt.key.int

    v.wait awaitTime, proc() =
        var rocket = v.rootNode.newChild("rocket")
        var mc = rocket.component(MeshComponent)
        mc.fromMeshComponent(v.balloonsLib[ROCKET_MAT.int])

        var bigestLifetime = 2.float32
        var smokeNode = rocket.createAndPrepareSmoke(v.rocketTrailFire, bigestLifetime)

        var start = emiter.anchor.worldPos()
        start[1] += 5.0
        let randY = rand(20'f32)
        start.x += rand(5'f32)
        let dest = emiter.anchor.worldPos() + newVector3(100, 100+randY, 50)

        let animOut = rocket.makeLinearAnimFromPoints(start, dest)

        v.addAnimation(animOut)

        v.soundManager.sendEvent("ROCKET_ANIMATION")

        animOut.onComplete do():
            smokeNode.hideSmoke()
            v.rootCameraNode.addChild(smokeNode)

            rocket.removeFromParent()
            v.rootNode.addChild(rocket)
            rocket.position = newVector3(0,0,0)

            var circleAnim = v.rootCameraNode.initCircleRocketAnim(v.balloonsLib[ROCKET_MAT.int], v.rocketTrailFire, proc() =
                let start = emiter.anchor.worldPos() - newVector3(120, 0, -10)
                let dest = receiver.anchor.worldPos() - newVector3(0, 0, -5)
                let animBack = rocket.makeLinearAnimFromPoints(start, dest)

                rocket.addChild(smokeNode)
                smokeNode.positionZ = 0.0
                smokeNode.showSmoke()

                animBack.onComplete do():
                    # cellPayout
                    if not v.bonusPayouts.hasKey(cellIndex):
                        v.bonusPayouts[cellIndex] = cellPayout
                    v.totalBonusWin += cellPayout

                    v.bonusPanel.setBonusGameWin(v.totalBonusWin, false)

                    v.playShake()

                    rocket.removeComponent(MeshComponent)
                    rocket.removeFromParent()
                    rocket = nil

                    receiver.playBonusDestroy(v.bonusDestroyImages)
                    receiver.balloonParent.playWave()

                    smokeNode.hideSmoke()
                    v.rootCameraNode.addChild(smokeNode)

                    v.wait bigestLifetime, proc() =
                        smokeNode.removeFromParent()

                    var onMultiplierPlayed = proc() =
                        if isLastBonus:
                            dec v.gTarget

                        if isLastBonus and v.gTarget == 0:
                            v.afterBonusInteractives()

                    var multiplierNode = receiver.balloonNode.findNode("mult_num")
                    if multiplierNode.isNil:
                        multiplierNode = receiver.balloonNode.newChild("mult_num")
                        discard multiplierNode.component(HardBillboard)
                        let numNode = newLocalizedNodeWithResource(resPath & "2d/compositions/numbers_bonus.json")
                        multiplierNode.addChild(numNode)
                        let textComp = numNode.findNode("text").componentIfAvailable(Text)
                        textComp.text = "x" & $cellMultiplier
                        let anim = numNode.animationNamed("play")
                        v.addAnimation(anim)
                        anim.onComplete do():
                            anim.removeHandlers()
                            onMultiplierPlayed()
                    else:
                        multiplierNode.removeAllChildren()
                        discard multiplierNode.component(HardBillboard)
                        let numNode = newLocalizedNodeWithResource(resPath & "2d/compositions/numbers_bonus.json")
                        multiplierNode.addChild(numNode)
                        let textComp = numNode.findNode("text").componentIfAvailable(Text)
                        textComp.text = "x" & $cellMultiplier
                        let anim = numNode.animationNamed("play")
                        v.addAnimation(anim)
                        anim.onComplete do():
                            anim.removeHandlers()
                            onMultiplierPlayed()

                v.addAnimation(animBack)
            )
            let animDuration = circleAnim.loopDuration
            circleAnim.loopDuration = animDuration * 1.25 * BALLOON_SLOT_SPEED_FLY
            v.addAnimation(circleAnim)

proc generateRockets(v: BalloonSlotView, emiter: BalloonComposition, bonus: BonusResponse, isLast: bool = false) =
    var targets = bonus.targets
    var timeing = 0.0
    var targetLast = targets.len - 1

    for indx, j in targets:
        closureScope:
            if isLast:
                inc v.gTarget
            let timeout = 0.0
            emiter.balloonNode.hide()
            if j.key != -1:
                let k = j.key.int
                let receiver = v.balloonPlayfield[j.key].balloon
                v.emitRocket(emiter, receiver, j, timeing, isLast)
                timeing += 0.2 * BALLOON_SLOT_SPEED_FLY.float32
            else:
                # MULTIPLIER
                var multiplierNode = v.rootNode.newChild("mult_num")
                multiplierNode.position = emiter.anchor.worldPos()
                discard multiplierNode.component(HardBillboard)

                let numNode = newNodeWithResource(resPath & "2d/compositions/numbers_bonus.json")
                multiplierNode.addChild(numNode)

                let textComp = numNode.findNode("text").componentIfAvailable(Text)
                textComp.text = "x2"

                let anim = numNode.animationNamed("play")
                v.addAnimation(anim)
                anim.onComplete do():
                    v.wait 0.5, proc() =
                        multiplierNode.removeFromParent()
                        multiplierNode = nil
                        if isLast and v.gTarget == 0:
                            v.afterBonusInteractives()

proc createBonusInteractive(v: BalloonSlotView, bonus: BonusResponse, currBucket: int) =
    var parent = v.balloonPlayfield[bonus.index].carriage
    v.bonusQueue.enqueue(bonus)

    let blinkParentNode = v.balloonPlayfield[bonus.index].carriage
    var blinkNode = newNodeWithResource(resPath & "2d/compositions/tap.json")
    var blinkAnim = blinkNode.animationNamed("play")
    blinkAnim.numberOfLoops = -1
    blinkNode.position = newVector3(-4.0, 5.0, 0.0)
    blinkNode.scale = newVector3(0.075, -0.07, -0.07)
    blinkParentNode.addChild(blinkNode)
    v.addAnimation(blinkAnim)

    var buttonAction = proc() =
        let emiter = v.balloonPlayfield[bonus.index].balloon
        let boxSmokeNode = newNodeWithResource(resPath & "particles/rocket/smoke_out.json")
        let smokeComp = boxSmokeNode.componentIfAvailable(PSHolder)
        emiter.balloonNode.addChild(boxSmokeNode)
        boxSmokeNode.reparentTo(v.rootCameraNode)
        smokeComp.played = true
        let smokeCompLifeTime = 2.0
        v.wait smokeCompLifeTime, proc() =
            boxSmokeNode.removeFromParent()

        blinkAnim.cancel()
        blinkNode.removeFromParent()
        blinkNode = nil

        v.soundManager.sendEvent("ROCKET_START")

        let bonus = v.bonusQueue.dequeue()
        let isLast = if v.bonusQueue.len == 0: true else: false
        v.generateRockets(emiter, bonus, isLast)

    parent.createButton(BETWEEN_CELL_STEP, BETWEEN_CELL_STEP, buttonAction)

proc cameraFlyOutAnim(v: BalloonSlotView) =
    let startZ = v.rootCameraNode.positionZ
    let destZ = -CAMERA_Z_IN_STANDART-50.0
    let moveTime = 4.0 * BALLOON_SLOT_SPEED.float32
    let anim = newAnimation()
    anim.loopDuration = moveTime
    anim.numberOfLoops = 1
    anim.onAnimate = proc(p: float) = v.rootCameraNode.positionZ = interpolate(startZ, destZ, elasticEaseOut(p, moveTime))
    v.addAnimation(anim)

proc cameraFlyInAnim(v: BalloonSlotView) =
    let startZ = v.rootCameraNode.positionZ
    let destZ = -CAMERA_Z_IN_STANDART
    let moveTime = 4.0 * BALLOON_SLOT_SPEED.float32
    let anim = newAnimation()
    anim.loopDuration = moveTime
    anim.numberOfLoops = 1
    anim.onAnimate = proc(p: float) = v.rootCameraNode.positionZ = interpolate(startZ, destZ, elasticEaseOut(p, moveTime))
    v.addAnimation(anim)

proc cameraFlyUpAnim(v: BalloonSlotView, callback: proc() = proc() = discard) =
    let skyNode = v.rootNode.findNode("sky")
    let sunNode = v.rootNode.findNode("sun_anchor")
    let startY = 0.0
    let destY = 180.0
    let startScale = SKY_SCALE
    let destScale = SKY_DEST_SCALE
    let sunStartScale = SUN_SCALE
    let sunDestScale = SUN_SCALE - (SKY_DEST_SCALE/SKY_SCALE-1.0)
    var start = [startY, startScale, sunStartScale]
    var dest = [destY, destScale, sunDestScale]
    let moveTime = 7.0 * BALLOON_SLOT_SPEED.float32
    let anim = newAnimation()
    anim.loopDuration = moveTime
    anim.numberOfLoops = 1
    anim.onAnimate = proc(p: float) =
        var posYScale = interpolate(start, dest, elasticEaseOut(p, moveTime))
        v.cameraNode.positionY = CAMERA_POS_Y + posYScale[0]
        skyNode.scaleY = posYScale[1]
        sunNode.scaleY = posYScale[2]

    v.wait 2.0 * BALLOON_SLOT_SPEED.float32, proc() =
        var starsNode = skyNode.findNode("stars")
        if starsNode.isNil:
            skyNode.addChild(newNodeWithResource(resPath & "intro/stars.json"))
        else:
            starsNode.fadeShow()
        callback()
    v.addAnimation(anim)

proc cameraFlyDownAnim(v: BalloonSlotView) =
    let skyNode = v.rootNode.findNode("sky")
    let sunNode = v.rootNode.findNode("sun_anchor")

    let startY = 180.0
    let destY = 0.0
    let startScale = SKY_DEST_SCALE
    let destScale = SKY_SCALE
    let sunStartScale = SUN_SCALE - (SKY_DEST_SCALE/SKY_SCALE-1.0)
    let sunDestScale = SUN_SCALE
    var start = [startY, startScale, sunStartScale]
    var dest = [destY, destScale, sunDestScale]

    let moveTime = 7.0 * BALLOON_SLOT_SPEED.float32
    let anim = newAnimation()
    anim.loopDuration = moveTime
    anim.numberOfLoops = 1
    anim.onAnimate = proc(p: float) =
        var posYScale = interpolate(start, dest, elasticEaseOut(p, moveTime))
        v.cameraNode.positionY = CAMERA_POS_Y + posYScale[0]
        skyNode.scaleY = posYScale[1]
        sunNode.scaleY = posYScale[2]

    v.wait 2.0 * BALLOON_SLOT_SPEED.float32, proc() =
        var starsNode = skyNode.findNode("stars")
        if starsNode.isNil:
            starsNode = newNodeWithResource(resPath & "intro/stars.json")
            skyNode.addChild(starsNode)
        starsNode.fadeHide()
    v.addAnimation(anim)

proc onClickScreen(v: BalloonSlotView, callback: proc()) =
    var bttnNode = v.rootCameraNode.newChild("win_bttn")
    bttnNode.positionX = -v.bounds.size.width*2.0
    bttnNode.positionY = -v.bounds.size.height*2.0
    bttnNode.positionZ = -3000.0
    bttnNode.scale = newVector3(10,10,10)
    var button = newButton(newRect(0, 0, v.bounds.size.width, v.bounds.size.height))
    bttnNode.component(UIComponent).view = button
    button.hasBezel = false
    var action = proc() =
        if not bttnNode.isNil:
            bttnNode.removeComponent(UIComponent)
            bttnNode.removeFromParent()
            bttnNode = nil
            button = nil
            while v.fullscreenButtonsActions.len > 0:
                let job = v.fullscreenButtonsActions.pop()
                job()
            callback()
    button.onAction(action)
    v.fullscreenButtonsActions.add(action)

proc unlockSpinIfLevelUp(v: BalloonSlotView)

method removeWinAnimationWindow*(v: BalloonSlotView, fast: bool = true): bool  =
    if not v.winWindowDestroyProc.isNil:
        v.winWindowReadyForDestroy = false;
        v.winWindowDestroyProc()
        v.winWindowDestroyProc = nil
        v.onWinDialogClose()
        v.setSpinButtonState(SpinButtonState.Spin)
        v.releaseTouch()
        v.unlockSpinIfLevelUp()
        result = true

proc showRoundBalance(v: BalloonSlotView) =
    currentUser().chips = v.currResponse.balance

    template playBalance() =
        v.soundManager.sendEvent("REGULAR_WIN_SOUND_" & $rand(1 .. 2))

        let roundWin = v.gTotalRoundWin

        var isBigNumber = false
        let strDigitsLen = ($roundWin).len

        # NEAR WIN NUMBERS
        let centerFront = 950.0
        let stepFront = SMALL_FONT_STEP
        let digitsFrontLen = (strDigitsLen div 2).float32 * stepFront
        let modFrontShift = if ((strDigitsLen mod 2) == 0) : (stepFront/2.0) else: 0
        let posFront = newVector3(centerFront - digitsFrontLen + modFrontShift, -420.0, 0.0)

        let numNodeSmall = newWinNumbersNode(roundWin, FontSize.MediumFont)
        numNodeSmall.position = posFront
        v.nearNode.addChild(numNodeSmall)

        let smallAnims = numNodeSmall.winNumbersAnimation(0.35)

        # FAR WIN NUMBERS
        let centerBack = 940.0
        let stepBack = BIG_FONT_STEP
        let digitsBackLen = (strDigitsLen div 2).float32 * stepBack
        let modBackShift = if ((strDigitsLen mod 2) == 0) : (stepBack/2.0) else: 0
        let posBack = newVector3(centerBack - digitsBackLen + modBackShift, 150.0, 0.0)

        let numNodeBig = newWinNumbersNode(roundWin, FontSize.BigFont)
        numNodeBig.position = posBack
        v.farNode.addChild(numNodeBig)

        let bigAnims = numNodeBig.winNumbersAnimation(0.35)

        # PLAY IN ANIM
        v.addAnimation(smallAnims.inAnim)
        v.addAnimation(bigAnims.inAnim)

        template playNumOut() =
            v.onClickScreen do():
                # PLAY OUT ANIM
                v.addAnimation(smallAnims.outAnim)
                v.addAnimation(bigAnims.outAnim)
                smallAnims.outAnim.onComplete do():
                    smallAnims.outAnim.removeHandlers()
                    numNodeSmall.removeFromParent()
                bigAnims.outAnim.onComplete do():
                    bigAnims.outAnim.removeHandlers()
                    numNodeBig.removeFromParent()

        playNumOut()

    if v.gTotalRoundWin > 0'i64:
        let oldChips = currentUser().chips-v.gTotalRoundWin
        if v.prevResponse.stage == FreeSpinStage:
            v.soundManager.sendEvent("FREE_SPINS_WIN")

        v.slotGUI.winPanelModule.setNewWin(v.gTotalRoundWin.int64, true)

        v.chipsAnim(v.rootNode.findNode("total_bet_panel"), oldChips.int64, currentUser().chips, "")

        v.wait BALLOON_SLOT_SPEED_FLY.float32, proc() =
            # v.chipsAnim(v.slotGUI.rootNode, oldChips.int64, currentUser().chips, "")
            v.gTotalRoundWin = 0

        proc hideTextWinAnim() =
            v.textWinAnimIn.loopPattern = lpEndToStart
            v.addAnimation(v.textWinAnimIn)
            v.textWinAnimIn.onComplete do():
                v.textWinAnimIn.removeHandlers()
                v.textWinNode.hide()
                v.textWinAnimIn.loopPattern = lpStartToEnd

        if v.gTotalRoundWin >= v.totalBet()*v.multMega:
            var duration = 2.0 * 3.0 * BALLOON_SLOT_SPEED_FLY
            let nd = bigwinNumbersNode(v.gTotalRoundWin, duration)

            v.nearNode.addChild(nd)
            v.addAnimation(nd.animationNamed("play"))
            v.onBigWinHappend(BigWinType.Mega, oldChips)
            v.blockTouch()

            v.soundManager.pauseMusic()
            v.playWinAnimation[BIGWIN.int].inAnim do():
                v.wait 1.0, proc() =
                    v.playWinAnimation[BIGWIN.int].outAnim do(): discard
                    v.playWinAnimation[HUGEWIN.int].inAnim do():
                        v.wait 1.0, proc() =
                            v.playWinAnimation[HUGEWIN.int].outAnim do(): discard
                            v.playWinAnimation[MEGAWIN.int].inAnim do():
                                v.wait(8.0) do():
                                    v.soundManager.resumeMusic()

                                proc onDestroy() =
                                    hideTextWinAnim()
                                    v.playWinAnimation[MEGAWIN.int].outAnim do():
                                        nd.removeFromParent()
                                v.winWindowDestroyProc = onDestroy
                                v.onWinDialogShowAnimationComplete()
                                v.winWindowReadyForDestroy = true
                                v.onClickScreen do():
                                    discard v.removeWinAnimationWindow()

        elif v.gTotalRoundWin >= v.totalBet()*v.multHuge:
            var duration = 2.0 * 2.0 * BALLOON_SLOT_SPEED_FLY
            let nd = bigwinNumbersNode(v.gTotalRoundWin, duration)

            v.nearNode.addChild(nd)
            v.addAnimation(nd.animationNamed("play"))
            v.onBigWinHappend(BigWinType.Huge, oldChips)
            v.blockTouch()

            v.soundManager.pauseMusic()

            v.playWinAnimation[BIGWIN.int].inAnim do():
                v.wait 1.0, proc() =
                    v.playWinAnimation[BIGWIN.int].outAnim do(): discard
                    v.playWinAnimation[HUGEWIN.int].inAnim do():
                        v.wait(6.0) do():
                            v.soundManager.resumeMusic()

                        proc onDestroy() =
                            hideTextWinAnim()
                            v.playWinAnimation[HUGEWIN.int].outAnim do():
                                nd.removeFromParent()
                        v.winWindowDestroyProc = onDestroy
                        v.onWinDialogShowAnimationComplete()
                        v.winWindowReadyForDestroy = true
                        v.onClickScreen do():
                            discard v.removeWinAnimationWindow()

        elif v.gTotalRoundWin >= v.totalBet()*v.multBig:
            var duration = 2.0 * 1.0 * BALLOON_SLOT_SPEED_FLY
            let nd = bigwinNumbersNode(v.gTotalRoundWin, duration)

            nd.positionX = 1037.0
            v.onBigWinHappend(BigWinType.Big, oldChips)
            v.nearNode.addChild(nd)
            v.addAnimation(nd.animationNamed("play"))

            v.blockTouch()
            v.soundManager.pauseMusic()
            v.playWinAnimation[BIGWIN.int].inAnim do():
                v.wait(4.0) do():
                    v.soundManager.resumeMusic()

                proc onDestroy() =
                    hideTextWinAnim()
                    v.playWinAnimation[BIGWIN.int].outAnim do():
                        nd.removeFromParent()
                v.winWindowDestroyProc = onDestroy
                v.onWinDialogShowAnimationComplete()
                v.winWindowReadyForDestroy = true
                v.onClickScreen do():
                    discard v.removeWinAnimationWindow()
        else:
            playBalance()
            v.unlockSpinIfLevelUp()
    else:
        v.slotGUI.moneyPanelModule.setBalance(v.gPrevBalance, currentUser().chips, false)
        v.unlockSpinIfLevelUp()
        discard

    v.gPrevBalance = v.currResponse.balance

template hideGUIBeforeBonus(v: BalloonSlotView) =
    v.freespinController.rootNode.hide()
    v.prepareGUItoBonus(true)

    if v.bonusPanel.isNil: v.bonusPanel = createBonusGamePanel(v.slotGUI.rootNode, newVector3(650, 960))
    v.bonusPanel.show()
    v.bonusPanel.setBonusGameWin(0.int64, false)

proc showControllerDestructions(v: BalloonSlotView)
template showGUIAfterBonus(v: BalloonSlotView) =
    v.freespinController.rootNode.show()
    v.prepareGUItoBonus(false)

    if v.bonusPanel.isNil: v.bonusPanel = createBonusGamePanel(v.slotGUI.rootNode, newVector3(650, 960))
    v.bonusPanel.setBonusGameWin(0.int64, false)
    v.bonusPanel.hide()

    v.destructionsCounter = 1
    v.showControllerDestructions()

proc resetControllerDestructions(v: BalloonSlotView) =
    for i in 0..v.prevResponse.destructions-1:
        closureScope:
            let index = i
            if index < 9:
                if v.freespinControllerAnimation[index].visible:
                    v.freespinControllerAnimation[index].anim.loopPattern = lpEndToStart
                    v.addAnimation(v.freespinControllerAnimation[index].anim)
                    v.freespinControllerAnimation[index].anim.onComplete do():
                        v.freespinControllerAnimation[index].visible = false
                        v.freespinControllerAnimation[index].anim.removeHandlers()

proc showControllerDestructions(v: BalloonSlotView) =
    if v.destructionsCounter > 0:
        let index = v.destructionsCounter - 1

        # check previous
        if index < v.freespinControllerAnimation.len:
            if index >= 1 and not v.freespinControllerAnimation[index-1].visible:
                var ind = index-1
                while ind >= 0:
                    if not v.freespinControllerAnimation[ind].visible:
                        v.freespinControllerAnimation[ind].anim.loopPattern = lpStartToEnd
                        v.freespinControllerAnimation[ind].visible = true
                        v.addAnimation(v.freespinControllerAnimation[ind].anim)
                    dec ind

            v.freespinControllerAnimation[index].anim.loopPattern = lpStartToEnd
            v.freespinControllerAnimation[index].visible = true
            v.addAnimation(v.freespinControllerAnimation[index].anim)

    else:
        if v.prevResponse.destructions > 0:
            v.resetControllerDestructions()

proc hideLinesAfterBonusGame(v: BalloonSlotView) =
    for v in v.balloonPlayfield:
        closureScope:
            let currCell = v
            currCell.balloon.balloonNode.hide()
            currCell.balloon.frontSpriteWrapperNode.hide()
            currCell.balloon.backSpriteWrapperNode.hide()

proc checkFor5InRow(v: BalloonSlotView, callback: proc()) =
    var bWas5InRow: bool = false
    for ln in v.currResponse.lines:
        if ln.symbols == 5:
            bWas5InRow = true
            break
    if bWas5InRow:
        v.play5InRowAnimation(callback)
    else:
        callback()

proc processReels(v: BalloonSlotView, callback: proc() = proc() = discard) =
    v.playLines do():
        v.checkFor5InRow do():
            v.getDestroy()
            v.processDestroy do():
                v.setupShifts()
                v.processShifts()
                v.resetShifts()
                callback()

proc unlockSpinIfLevelUp(v: BalloonSlotView) =
    # let event = sharedGameEventsQueue().getEvent(GameEventType.LevelUpEv)
    # if not event.isNil and v.slotGUI.gameEventsProcessing == false:
    #     let lvl = event.data.get(int)
    #     let cb = proc () =
    #         sharedGameEventsQueue().delete(event)
    #         v.setSpinButtonState(SpinButtonState.Spin)
    #         v.slotGUI.processGameEvents()

    #     # v.slotGUI.showLevelUpPopup(lvl, cb)
    # else:
        # v.setSpinButtonState(SpinButtonState.Spin)
        # v.slotGUI.processGameEvents()

    let cb = proc () =
        v.setSpinButtonState(SpinButtonState.Spin)
    let spinFlow = findActiveState(SpinFlowState)
    if not spinFlow.isNil:
        spinFlow.pop()
    let state = newFlowState(SlotNextEventFlowState, newVariant(cb))
    pushBack(state)

proc spin(v: BalloonSlotView)

proc respin(v: BalloonSlotView) =
    v.gTotalRoundWin += v.currResponse.payout
    v.setTimeout 0.15, proc() =
        v.playAllIn do():
            if v.currResponse.hasDestruction() or v.isInFreeSpins:
                v.processReels do():
                    v.showControllerDestructions()
                    v.slotGUI.winPanelModule.setNewWin(v.gTotalRoundWin, true)
                    v.spin()
            else:
                v.showControllerDestructions()
                if v.currResponse.stage != BonusStage and v.currResponse.stage != FreeSpinStage:
                    v.showRoundBalance()

template resetFirstDestrController(v: BalloonSlotView) =
    if not v.currResponse.hasDestruction():
        let index = 0
        if v.freespinControllerAnimation[index].visible:
            v.freespinControllerAnimation[index].anim.loopPattern = lpEndToStart
            v.addAnimation(v.freespinControllerAnimation[index].anim)
            v.freespinControllerAnimation[index].anim.onComplete do():
                v.freespinControllerAnimation[index].visible = false
                v.freespinControllerAnimation[index].anim.removeHandlers()

template restoreAfterBonusGame(v: BalloonSlotView) =
    v.playAllOut do():
        v.hideLinesAfterBonusGame()
        if v.prevResponse.stage == BonusStage and v.currResponse.stage == BonusStage:
            info "BONUS AFTER BONUS DETECTED"
        else:
            v.respin()

proc handleFreespinsCount(v: BalloonSlotView) =
    if v.prevResponse.stage == SpinStage or abs(v.currResponse.freespins.int-v.freeSpinsLeft) > 1:
        v.freeSpinsLeft = v.currResponse.freespins.int
    else:
        if not v.prevResponse.hasDestruction():
            dec v.freeSpinsLeft

proc preBonusInteractives(v: BalloonSlotView, callback: proc()) =
    var bttnNode = v.rootCameraNode.newChild("scr_button")
    bttnNode.positionX = -v.bounds.size.width/2.0
    bttnNode.positionY = -v.bounds.size.height/2.0
    var button = newButton(newRect(0, 0, v.bounds.size.width, v.bounds.size.height))
    bttnNode.component(UIComponent).view = button
    button.hasBezel = false
    var buttonAction = proc() =
        bttnNode.removeComponent(UIComponent)
        bttnNode.removeFromParent()
        bttnNode = nil
        button = nil
        v.playBonusOutAnimation(callback)
    button.onAction do():
        buttonAction()
    v.hideGUIBeforeBonus()

proc afterBonusInteractives(v: BalloonSlotView) =
    v.onBonusGameEnd()
    v.wait(1.25 * BALLOON_SLOT_SPEED) do():
        v.bonusPayouts.sort do(x, y: (int, int64)) -> int:
            result = cmp(x[1], y[1])
            if result == 0:
                result = cmp(x[0], y[0])

        var processedPayouts = 0
        var timeout = 0.0

        for key, val in mpairs v.bonusPayouts:

            let valToCached = val
            let balloonIndexCached = key.int

            closureScope:
                inc processedPayouts

                let receiver = v.balloonPlayfield[balloonIndexCached.int].balloon

                let multiplierOverBalloon = receiver.balloonNode.findNode("mult_num")

                # # SETUP DESTROY
                if balloonIndexCached.int >= 5 and balloonIndexCached.int < 20:
                    v.balloonPlayfield[balloonIndexCached.int].balloon.destroyed = true

                var winNumNode = v.rootNode.newChild("win_num")
                winNumNode.position = receiver.anchor.worldPos()
                discard winNumNode.component(HardBillboard)

                proc playBonusBalloonDestroy(indx: int) =
                    if v.balloonPlayfield[indx].balloon.destroyed:
                        v.balloonPlayfield[indx].stopIdle()
                        v.balloonPlayfield[indx].balloon.playDestroy(0.0, BALLOON_SLOT_SPEED_FLY)
                        v.wait(0.275 * BALLOON_SLOT_SPEED_FLY) do():
                            v.soundManager.sendEvent("POW_BALLON_" & $rand(1 .. 2))

                let valTo = valToCached
                let balloonIndex = balloonIndexCached.int
                if processedPayouts < v.bonusPayouts.len:
                    v.wait(timeout.float32) do():
                        v.soundManager.sendEvent("ON_BONUS_NUMBER_FLY_UP")
                        playBonusBalloonDestroy(balloonIndex)
                        v.wait(0.5*BALLOON_SLOT_SPEED_FLY) do():
                            multiplierOverBalloon.fadeHide do():
                                multiplierOverBalloon.removeFromParent()
                                winNumNode.playUpBonusNumber(valTo, 0.float32, BALLOON_SLOT_SPEED.float32, proc() = discard)
                else:
                    v.wait(timeout.float32) do():
                        v.soundManager.sendEvent("ON_BONUS_NUMBER_FLY_UP")
                        playBonusBalloonDestroy(balloonIndex)
                        v.wait(0.5*BALLOON_SLOT_SPEED_FLY) do():
                            multiplierOverBalloon.fadeHide do():
                                multiplierOverBalloon.removeFromParent()
                                winNumNode.playUpBonusNumber(valTo, 0.float32, BALLOON_SLOT_SPEED.float32) do():
                                    v.bonusPayouts = initOrderedTable[int, int64]()
                                    v.cameraFlyInAnim()
                                    v.playOutAfterBonus do():
                                        v.showGUIAfterBonus()

                                        # PROCCESS DESTROY
                                        v.isInBonusGame = false
                                        v.currResponse.stage = SpinStage

                                        for i, val in v.currResponse.symbols:
                                            if val == BONUS_INDEX:
                                                v.balloonPlayfield[i].balloon.destroyed = true

                                        v.setupShifts()
                                        v.processShifts()
                                        v.resetShifts()

                                        if v.prevResponse.stage == FreeSpinStage:
                                            v.currResponse.stage = FreeSpinStage
                                        v.isInBonusGame = true

                                        v.spin()

                timeout += 0.35 * BALLOON_SLOT_SPEED

proc onSpinResponse(v: BalloonSlotView) =
    case v.currResponse.stage:
        of SpinStage:
            v.playBackgroundMusic(MusicType.Main)

            let isPrevBonus = v.isInBonusGame
            v.isInBonusGame = false
            v.isInFreeSpins = false

            if v.prevResponse.stage == FreeSpinStage:
                v.onFreeSpinsEnd()
                v.wait FLY_IN_TIME*BALLOON_SLOT_SPEED_FLY, proc() =
                    v.cameraFlyDownAnim()
                    v.slotGUI.spinButtonModule.stopFreespins()

            if isPrevBonus:
                v.wait(FLY_IN_TIME*BALLOON_SLOT_SPEED_FLY) do():
                    v.resetFirstDestrController()

            if not v.prevResponse.hasDestruction():
                v.playAllOut do():
                    v.respin()
            else:
                v.respin()

        of FreeSpinStage:
            v.playBackgroundMusic(MusicType.Freespins)

            let isPrevBonus = v.isInBonusGame
            v.isInBonusGame = false
            v.isInFreeSpins = true

            if v.prevResponse.stage == SpinStage:
                v.stage = GameStage.FreeSpin
                if v.prevResponse.hasDestruction():
                    v.gTotalRoundWin += v.currResponse.payout
                    v.playAllIn do():
                        v.handleFreespinsCount()
                        v.resetControllerDestructions()
                        v.slotGUI.spinButtonModule.startFreespins(v.currResponse.freespins.int)
                        v.playFreespinAnimation do():
                            v.cameraFlyUpAnim do():
                                v.playAllOut do():
                                    if v.currResponse.freespins == 5 or
                                       v.currResponse.freespins == 10 or
                                       v.currResponse.freespins == 15 or
                                       v.currResponse.freespins == 25 or
                                       v.currResponse.freespins == 50 :
                                        v.freespinsTriggered.inc()
                                        v.lastActionSpins = 0

                                        let spinsFromLast = saveNewFreespinLastSpins(v.name)
                                        sharedAnalytics().freespins_start(v.name, v.slotSpins, v.totalBet, currentUser().chips, spinsFromLast)
                                    v.respin()
                else:
                    v.wait FLY_IN_TIME*BALLOON_SLOT_SPEED_FLY, proc() =
                        v.handleFreespinsCount()
                        v.resetControllerDestructions()
                        v.slotGUI.spinButtonModule.startFreespins(v.currResponse.freespins.int)
                        v.playFreespinAnimation do():
                            v.cameraFlyUpAnim do():
                                v.playAllOut do():
                                    v.respin()

            elif v.prevResponse.stage == FreeSpinStage:
                v.handleFreespinsCount()

                v.slotGUI.spinButtonModule.setFreespinsCount(v.freeSpinsLeft.int)
                if not v.prevResponse.hasDestruction():
                    v.playAllOut do():
                        v.respin()
                else:
                    v.respin()
            elif isPrevBonus:
                v.slotGUI.spinButtonModule.startFreespins(v.currResponse.freespins.int)
                v.wait(FLY_IN_TIME*BALLOON_SLOT_SPEED_FLY) do():
                    v.resetFirstDestrController()
            else:
                info "\n\n\nFIX ME OF FREESPINSTAGE\n\n\n"

        of BonusStage:
            v.slotBonuses.inc()
            v.lastActionSpins = 0

            let spinsFromLast = saveNewBonusgameLastSpins(v.name)
            sharedAnalytics().bonusgame_start(v.name, v.slotSpins, v.totalBet, currentUser().chips, spinsFromLast)
            v.resetControllerDestructions()

            if v.prevResponse.stage == FreeSpinStage:
                v.handleFreespinsCount()

            v.playBackgroundMusic(MusicType.Bonus)

            let isPrevBonus = v.isInBonusGame
            v.isInBonusGame = false
            v.isInFreeSpins = false

            if v.prevResponse.stage == FreeSpinStage and v.prevResponse.freespins == 1:
                v.wait FLY_IN_TIME*BALLOON_SLOT_SPEED_FLY, proc() =
                    v.cameraFlyDownAnim()
                    v.slotGUI.spinButtonModule.stopFreespins()
                    v.applyBetChanges()
            if isPrevBonus:
                v.wait(FLY_IN_TIME*BALLOON_SLOT_SPEED_FLY) do():
                    v.resetFirstDestrController()

            template playBonus() =
                v.isInBonusGame = true

                v.totalBonusWin = 0

                v.gTotalRoundWin += v.currResponse.payout

                var bonusInteractives = proc() =
                    # reset all targets to check callback
                    v.gTarget = 0
                    for i, b in v.currResponse.bonuses:
                        closureScope:
                            v.createBonusInteractive(b, i)

                v.preBonusInteractives do():
                    v.cameraFlyOutAnim()
                    v.playAllIn do():
                        bonusInteractives()

            template playPrebonus() =
                v.playAllInBeforeBonus do():
                    v.playBonusInAnimation do():
                        playBonus()


            if v.prevResponse.destructions > 0 and v.prevResponse.stage != BonusStage:
                playPrebonus()
            else:
                v.playAllOut do():
                    v.setTimeout 0.15, proc() =
                        playPrebonus()
        else:
            info "CORRUPT STAGE"

proc spin(v: BalloonSlotView) =
    v.sendSpinRequest(v.totalBet()) do(r: JsonNode):
        var resp = newResponse(r, v.destructionsCounter)

        v.prevResponse = v.currResponse
        v.currResponse = resp

        var spent = v.totalBet()
        if v.currResponse.stage == FreeSpinStage or v.prevResponse.payout > 0:
            spent = 0
        else:
            v.slotGUI.winPanelModule.setNewWin(0)
        if v.freeRounds:
            spent = 0

        v.sessionTotalSpend += spent
        v.sessionTotalWin += v.currResponse.payout

        saveTotalWin(v.name,v.currResponse.payout)
        saveTotalSpent(v.name,spent)
        saveLastBet(v.name, v.totalBet())

        if not v.prevResponse.hasDestruction():
            v.slotSpins.inc()
            saveTotalSpins(v.name)

        v.incLastActionSpins()

        # ANALYTICS
        setLastRTPAnalytics(if v.currResponse.payout > 0: v.currResponse.payout.float64/spent.float64 else: 0, v.BaseMachineView.getRTP())
        setStagesCountAnalytics(v.BaseMachineView.slotSpins, v.BaseMachineView.slotBonuses, v.BaseMachineView.freespinsTriggered)

        # ANALYTICS
        if not v.isInFreeSpins:
            runFirstTask10TimesSpinAnalytics(v.getRTP().float32, currentUser().chips.int64, v.totalBet().int, v.name, v.getActiveTaskProgress())

        if v.prevResponse.isNil:
            v.prevResponse = v.currResponse

        v.onSpinResponse()

method restoreState*(v: BalloonSlotView, res: JsonNode) =
    procCall v.BaseMachineView.restoreState(res)

    v.prevResponse = nil
    v.currResponse = nil

    v.gLines = v.lines.len

    if res.hasKey("chips"):
        currentUser().updateWallet(res["chips"].getBiggestInt())
        v.slotGUI.moneyPanelModule.setBalance(0.int64, currentUser().chips, false)


    if res.hasKey("freeSpinsCount"):
        let fc = res["freeSpinsCount"].getBiggestInt()
        if fc > 0:
            v.stage = GameStage.FreeSpin

    v.gTotalRoundWin = 0
    v.currResponse = newZeroWinResponse(res)
    v.prevResponse = v.currResponse

    if res.hasKey("paytable"):
        var pd: PaytableServerData
        let paytable = res["paytable"]
        if paytable.hasKey("items"):
            pd.itemset = @[]
            for itm in paytable["items"]:
                pd.itemset.add(itm.getStr())
        pd.paytableSeq = res.getPaytableData()
        if paytable.hasKey("freespin_trigger"):
            pd.freespTriggerId = paytable["freespin_trigger"].getStr()
        if paytable.hasKey("freespin_count"):
            pd.freespRelation = @[]
            let fr = paytable["freespin_count"]
            for i in countdown(fr.len-1, 0):
                let rel = fr[i]
                if rel.hasKey("trigger_destruction") and rel.hasKey("freespin_count"):
                    pd.freespRelation.add((rel["trigger_destruction"].getInt(), rel["freespin_count"].getInt()))
        if paytable.hasKey("bonus_trigger"):
            pd.bonusTriggerId = paytable["bonus_trigger"].getStr()
        if paytable.hasKey("bonus_count"):
            pd.bonusCount = paytable["bonus_count"].getInt()
        if paytable.hasKey("bonus_rockets_count"):
            v.bonusConfigRelation = @[]
            pd.maxRockets = -100
            pd.minRockets = 100
            for itm in paytable["bonus_rockets_count"]:
                let rockets = itm.getInt()
                v.bonusConfigRelation.add(rockets)
                if rockets > pd.maxRockets: pd.maxRockets = rockets
                if rockets < pd.minRockets: pd.minRockets = rockets

        v.pd = pd
    v.slotGUI.totalBetPanelModule.plusEnabled = false
    v.slotGUI.totalBetPanelModule.minusEnabled = false

method setupCameraForGui*(v: BalloonSlotView) = discard

method viewOnEnter(v: BalloonSlotView)=
    procCall v.BaseMachineView.viewOnEnter()

    v.soundManager = newSoundManager(v)

    v.soundManager.loadEvents(SOUND_PATH_PREFIX & "baloon", "common/sounds/common")

    v.music = initTable[string, bool]()
    v.wildsSound = newSeq[Sound](25)

    v.playBackgroundMusic(MusicType.Main)
    v.soundManager.playAmbient(SOUND_PATH_PREFIX & "balloon_ambience", 0.8)

    let guiAnchor = v.rootCameraNode.newChild("gui_anchor")
    guiAnchor.scale.y = -1.0
    guiAnchor.position = newVector3(-955, 550, -2050)
    guiAnchor.addChild(v.slotGUI.rootNode)
    v.slotGUI.addModule(mtBalloonFreeSpins)

    v.slotGUI.rootNode.parent.findNode("gui_parent").insertChild(v.slotGUI.rootNode.findNode("balloon_free_spins"), 0)

    v.freespinController = v.slotGUI.getModule(mtBalloonFreeSpins)
    v.freespinControllerAnimation = @[]
    v.freespinDestructions = 0
    for i in 1..9:
        closureScope:
            let index = i
            let anim = v.freespinController.rootNode.findNode("fsc_balloon_" & $ index).animationNamed("play")
            anim.numberOfLoops = 1
            anim.loopPattern = lpEndToStart
            v.freespinControllerAnimation.add((anim, false))

method onSpinClick(v: BalloonSlotView) =
    if v.actionButtonState == SpinButtonState.Stop:
        discard
    elif v.touchBlocked:
        discard v.removeWinAnimationWindow()
    elif v.actionButtonState == SpinButtonState.Spin and not v.touchBlocked:
        # ANALYTICS
        v.BaseMachineView.onSpinClickAnalytics()

        block rotateAnimBlock:
            let rotate = newAnimation()
            let sbm = v.slotGUI.spinButtonModule
            rotate.loopDuration = 1.0
            rotate.numberOfLoops = 1
            rotate.onAnimate = proc(p:float)=
                sbm.arrowParent.rotation = newQuaternionFromEulerXYZ(0.0, 0.0, interpolate(0.0, 360.0, p))
            v.addAnimation(rotate)

        v.soundManager.sendEvent("ON_SPIN_CLICK")

        while v.fullscreenButtonsActions.len > 0:
            let job = v.fullscreenButtonsActions.pop()
            job()

        if v.currResponse.freespins == 0:
            v.slotGUI.winPanelModule.setNewWin(0)
            if not v.freeRounds:
                if not currentUser().withdraw(v.totalBet()):
                    v.actionButtonState = SpinButtonState.Spin
                    if not v.slotGUI.isNil:
                        v.slotGUI.outOfCurrency("chips")
                    return

                let oldBalance = currentUser().chips
                currentUser().chips -= v.totalBet()
                v.slotGUI.moneyPanelModule.setBalance(oldBalance, currentUser().chips, false)
            v.setSpinButtonState(SpinButtonState.Blocked)
            v.spin()
    elif v.actionButtonState == SpinButtonState.StopAnim:
        discard

proc initCloudsAnim(n: Node,
                    bounds: tuple[AA: Vector3, BB: Vector3],
                    speed: float32,
                    wait: float32,
                    meshLib: seq[MeshComponent] = @[],
                    randomY: float32 = 100.0,
                    randomZ: float32 = 20.0,
                    startX: float32 = -100000.0): Animation =

    let v = n.sceneView.BalloonSlotView

    var startY = bounds.AA.y
    var destY = bounds.BB.y
    var startZ = bounds.AA.z
    var destZ = bounds.BB.z
    var randY = rand(1000'f32)/randomY
    var randZ = rand(1000'f32)/randomZ
    let randSign = rand([-1, 1]).float32
    let start = [bounds.AA.x.float32, bounds.AA.y, bounds.AA.z,0,0,0,0,0,0,0]
    let dest = [bounds.BB.x.float32, bounds.BB.y, bounds.BB.z,0,0,0,0,0,0,0]

    var anim = newEditableAnimation(start, dest)
    anim.Animation.numberOfLoops = 1
    anim.Animation.loopPattern = lpStartToEnd

    if startX != -100000.0:
        anim.startProps[0] = startX
        anim.Animation.loopDuration = (abs(bounds.AA.x) + abs(startX))/(abs(bounds.AA.x) + abs(bounds.BB.x)) * speed
    else:
        anim.startProps[0] = bounds.AA.x
        anim.Animation.loopDuration = speed

    anim.destProps[0] = bounds.BB.x

    anim.startProps[1] = startY + randSign * randY
    anim.destProps[1] = destY + randSign * randY

    anim.startProps[2] = startZ + randSign * randZ
    anim.destProps[2] = destZ + randSign * randZ

    # set in start position
    n.position = newVector3(anim.startProps[0], anim.startProps[1], anim.startProps[2])

    anim.Animation.onAnimate = proc(p: float) =
        var val = interpolate(anim.startProps, anim.destProps, linear(p))
        n.position = newVector3(val[0], val[1], val[2])

    anim.Animation.onComplete do():
        if meshLib.len != 0:
            n.component(MeshComponent).fromMeshComponent(rand(meshLib))

        randY = rand(1000'f32)/randomY
        randZ = rand(1000'f32)/randomZ

        anim.Animation.loopDuration = speed

        anim.startProps[0] = bounds.AA.x
        anim.destProps[0] = bounds.BB.x

        anim.startProps[1] = startY + randSign * randY
        anim.destProps[1] = destY + randSign * randY

        anim.startProps[2] = startZ + randSign * randZ
        anim.destProps[2] = destZ + randSign * randZ

        v.addAnimation(anim)

    if meshLib.len != 0:
        n.component(MeshComponent).fromMeshComponent(rand(meshLib))

    if startX != -100000.0:
        v.addAnimation(anim)
    else:
        v.wait wait, proc() =
            v.addAnimation(anim)

    result = anim

proc initTreeAnim(n: Node, bounds: tuple[AA: Vector3, BB: Vector3], speed: float32, randFrequency: float32 = 4.0, bUseRotation: bool = true, bUseScale: bool = true): Animation =
    let v = n.sceneView.BalloonSlotView
    var waitBefore = randFrequency + rand(1'f32)
    var randRotationY = rand(360'f32)
    var startScale = n.scaleX
    var randSign = rand([-1'f32, 1])
    var randScale = startScale - rand(100'f32)/1000.0
    var startZ = bounds.AA.z
    var destZ = bounds.BB.z
    var randZ = rand(1'f32)

    # set in start position
    n.position = bounds.AA
    if bUseRotation:
        n.rotation = aroundY(randRotationY * randSign)
    if bUseScale:
        n.scale = newVector3(randScale, randScale, randScale)

    let start = [bounds.AA.x.float32, bounds.AA.y, bounds.AA.z,0,0,0,0,0,0,0]
    let dest = [bounds.BB.x.float32, bounds.BB.y, bounds.BB.z,0,0,0,0,0,0,0]

    var anim = newEditableAnimation(start, dest)
    anim.Animation.numberOfLoops = 1
    anim.Animation.loopPattern = lpStartToEnd
    anim.Animation.loopDuration = speed
    anim.Animation.numberOfLoops = 1

    anim.startProps[2] = startZ + randZ
    anim.destProps[2] = destZ + randZ

    anim.Animation.onAnimate = proc(p: float) =
        var val = interpolate(anim.startProps, anim.destProps, linear(p))
        n.position = newVector3(val[0], val[1], val[2])

    anim.Animation.onComplete do():
        waitBefore = randFrequency + rand(1'f32)
        randRotationY = rand(360'f32)
        randSign = rand([-1'f32, 1])
        randScale = startScale - rand(100'f32)/1000.0
        randZ = rand(1'f32)

        n.hide()
        v.wait waitBefore, proc() =
            n.show()

            if bUseRotation:
                n.rotation = aroundY(randRotationY * randSign)
            if bUseScale:
                n.scale = newVector3(randScale, randScale, randScale)

            anim.startProps[2] = startZ + randZ
            anim.destProps[2] = destZ + randZ

            v.addAnimation(anim)

    v.wait waitBefore, proc() =
        v.addAnimation(anim)

    result = anim

proc initWindAnim(n: Node, bounds: tuple[AA: Vector3, BB: Vector3], speed: float32, randFrequency: float32 = 3.0): Animation =
    let v = n.sceneView.BalloonSlotView
    var waitBefore = randFrequency + rand(randFrequency.int).float32
    var startZ = bounds.AA.z
    var destZ = bounds.BB.z
    var randZ = rand(20'f32)
    var randSign = rand([-1'f32, 1])
    let ampVars = [180'f32, 160.0, 140.0, 120.0]
    var amplitude = rand(ampVars)

    # set in start position
    n.position = bounds.AA

    let start = [bounds.AA.x.float32, bounds.AA.y, bounds.AA.z,0,0,0,0,0,0,0]
    let dest = [bounds.BB.x.float32, bounds.BB.y, bounds.BB.z,0,0,0,0,0,0,0]

    var anim = newEditableAnimation(start, dest)
    anim.Animation.numberOfLoops = 1
    anim.Animation.loopPattern = lpStartToEnd
    anim.Animation.loopDuration = speed
    anim.Animation.numberOfLoops = 1

    anim.startProps[2] = startZ + randZ
    anim.destProps[2] = destZ + randZ

    anim.Animation.onAnimate = proc(p: float) =
        var val = interpolate(anim.startProps, anim.destProps, linear(p))
        if randSign == 1:
            n.position = newVector3(val[0], val[1] + val[1] * sin(val[0]/amplitude)/1.75, val[2])
        else:
            n.position = newVector3(val[0], val[1] + val[1] * cos(val[0]/amplitude)/1.75, val[2])

    anim.Animation.onComplete do():
        waitBefore = randFrequency + rand(randFrequency.int).float32
        randZ = rand(20'f32)
        randSign = rand([-1'f32, 1])
        amplitude = rand(ampVars)

        v.wait waitBefore, proc() =
            anim.startProps[2] = startZ + randZ
            anim.destProps[2] = destZ + randZ

            v.addAnimation(anim)

    v.wait waitBefore, proc() =
        v.addAnimation(anim)

    result = anim

proc initCameraAnim(n: Node, bounds: tuple[AA: float32, BB: float32], speed: float32): Animation =
    let v = n.sceneView
    var amplitude = 1.3
    var rotAmplitude = 0.6

    var anim = newAnimation()
    anim.loopDuration = speed
    anim.numberOfLoops = -1

    anim.loopPattern = lpStartToEndToStart

    anim.animate val in bounds.AA .. bounds.BB:
        n.positionY = sin(val) * amplitude
        n.rotation = aroundZ(sin(val) * rotAmplitude)

    v.addAnimation(anim)

    result = anim

proc onIntroSkip(v: BalloonSlotView) =
    var gc = v.rootNode.component(GlitchComponent)

    var drtns = newSeq[float]()
    for anim in v.introAnims:
        var duration = epochTime() - anim.startTime
        var loopProgress = (duration mod anim.loopDuration) / anim.loopDuration
        var newSt = anim.startTime + (anim.loopDuration/4) * loopProgress
        anim.prepare(newSt)
        drtns.add(anim.loopDuration)

    var skipAnim = newAnimation()
    skipAnim.loopDuration = 1.0
    skipAnim.numberOfLoops = 1
    skipAnim.onAnimate = proc(p:float)=
        for i, anim in v.introAnims:
            anim.loopDuration = interpolate(drtns[i], drtns[i]/4, p )

    skipAnim.onComplete do():
        BALLOON_SLOT_SPEED = 1.0
        BALLOON_SLOT_SPEED_FLY = 1.0

    v.addAnimation(skipAnim)

method initAfterResourcesLoaded(v: BalloonSlotView) =
    procCall v.BaseMachineView.initAfterResourcesLoaded()
    v.cameraNode = v.rootNode.findNode("Camera")
    v.bonusQueue = initQueue[BonusResponse]()
    v.bonusPayouts = initOrderedTable[int, int64]()
    v.idleAnimations = newSeq[Animation]()
    v.prevResponse = nil
    v.currResponse = nil

    # CREATE 2D ANCHORS
    v.farNode = v.cameraNode.newChild("far")
    v.nearNode = v.cameraNode.newChild("near")

    # camera create
    v.rootCameraNode = v.cameraNode.newChild("camera_anchor")
    v.rootCameraNode.positionX = -2.5

    # destr mask
    let maskNode = newNodeWithResource(resPath & "2d/compositions/destr_mask_2d_resource.json")
    let maskSprite = maskNode.componentIfAvailable(Sprite)
    let splashImages = maskSprite.images

    # wild
    let wildIdleFrontNode = newNodeWithResource(resPath & "2d/compositions/wild_idle_front_2d_resource.json")
    let wildIdleFrontSprite = wildIdleFrontNode.componentIfAvailable(Sprite)
    let wildImagesFront = wildIdleFrontSprite.images

    let wildIdleBackNode = newNodeWithResource(resPath & "2d/compositions/wild_idle_back_2d_resource.json")
    let wildIdleBackSprite = wildIdleBackNode.componentIfAvailable(Sprite)
    let wildImagesBack = wildIdleBackSprite.images

    let wildDestroyBackNode = newNodeWithResource(resPath & "2d/compositions/wild_destr_back_2d_resource.json")
    let wildDestroyBackSprite = wildDestroyBackNode.componentIfAvailable(Sprite)
    let wildImagesDestroyBack = wildDestroyBackSprite.images

    let wildDestroyFrontNode = newNodeWithResource(resPath & "2d/compositions/wild_destroy_front_2d_resource.json")
    let wildDestroyFrontSprite = wildDestroyFrontNode.componentIfAvailable(Sprite)
    let wildImagesDestroyFront = wildDestroyFrontSprite.images

    # load rocket trail images
    let cartoonFireNode = newNodeWithResource(resPath & "particles/rocket/cartoonfire_2d_resource.json")
    let cartoonfireSprite = cartoonFireNode.componentIfAvailable(Sprite)
    v.rocketTrailFire = newAnimatedImageWithImageSeq(cartoonfireSprite.images)

    # load bonus destruction image
    let saluteBonusNode = newNodeWithResource(resPath & "particles/rocket/salute_2d_resource.json")
    let saluteBonusSprite = saluteBonusNode.componentIfAvailable(Sprite)
    v.bonusDestroyImages = saluteBonusSprite.images

    # load material lib
    let matcapsNode = newNodeWithResource(resPath & "models/materials_2d_resource.json")
    let matcapSprite = matcapsNode.componentIfAvailable(Sprite)
    v.matcaps = matcapSprite.images

    # library of balloons for fast selection
    var resource3dNode = v.rootCameraNode.newChild("balloons")
    resource3dNode.positionZ = -15000.0

    v.balloonsLib = setupBalloonsMaterilals(resource3dNode, splashImages) # Why do we later overwrite balloonsLib with s???

    let items = ["Wild", "Bonus", "Snake", "Glider", "Kite", "Flag", "Red", "Yellow", "Green", "Blue"]
    var s = newSeq[MeshComponent]()
    for k, v in items:
        let n = resource3dNode.findNode(v)
        if v == "Wild":
            WILD_INDEX = k.int
        if v == "Bonus":
            BONUS_INDEX = k.int
        if not n.isNil:
            let mc = n.componentIfAvailable(MeshComponent)
            if not mc.isNil:
                s.add(mc)
    v.balloonsLib = s
    # load rocket model
    var rocket = newNodeWithResource(resPath & "models/balloons/rocket.json")
    rocket.scale = newVector3(0.5, 0.5, 0.5)
    rocket.positionZ = -15000.0
    v.rootNode.addChild(rocket)
    let rocketMesh = rocket.componentIfAvailable(MeshComponent)
    v.balloonsLib.add(rocketMesh)

    # create grid playfield
    let sceneShiftTranslation = newVector3(-128.0, STANDART_Y_SHIFT, 0.0)
    let rootCellsNode = v.rootCameraNode.newChild("root_anim")
    rootCellsNode.position = sceneShiftTranslation
    v.balloonPlayfield = v.generatePlayfield(splashImages, wildImagesBack, wildImagesFront,
                                             wildImagesDestroyBack, wildImagesDestroyFront, rootCellsNode)
    # create lines
    let rootLinesNode = v.rootCameraNode.newChild("root_lines")
    rootLinesNode.scale = newVector3(0.2, 0.2, 0.2)
    rootLinesNode.position = newVector3(-50.0, 0.0, 0.0)

    let vmLinesModifier = rootLinesNode.component(VisualModifier)
    vmLinesModifier.blendMode = COLOR_ADD

    let numbersRootNode = v.nearNode.newChild("root_numbers")

    # BONUS
    let bonusNodeBack = newLocalizedNodeWithResource(resPath & "bonus/BonusGame_back.json")

    let bonusBackAnim = bonusNodeBack.animationNamed("play")
    bonusBackAnim.numberOfLoops = 1
    v.farNode.addChild(bonusNodeBack)
    bonusNodeBack.hide()

    let bonusNodeFront = newLocalizedNodeWithResource(resPath & "bonus/BonusGame_front.json")
    let bonusFrontAnim = bonusNodeFront.animationNamed("play")
    v.nearNode.addChild(bonusNodeFront)
    bonusNodeFront.hide()

    let bonusNodeBlue = newLocalizedNodeWithResource(resPath & "bonus/BonusGame_blue.json")
    let bonusNodeBlueMask = bonusNodeBlue.component(TextMask)

    let bonusBlueInAnim = bonusNodeBlue.animationNamed("in")
    let bonusBlueOutAnim = bonusNodeBlue.animationNamed("out")
    v.nearNode.addChild(bonusNodeBlue)
    bonusNodeBlue.hide()

    let bonusNodeText = newLocalizedNodeWithResource(resPath & "bonus/BonusGame_text.json")
    let bonusTextInAnim = bonusNodeText.animationNamed("in")
    let bonusTextIdleAnim = bonusNodeText.animationNamed("idle")
    bonusTextIdleAnim.numberOfLoops = -1
    bonusTextIdleAnim.loopPattern = lpStartToEndToStart
    bonusTextIdleAnim.loopDuration = bonusTextIdleAnim.loopDuration * 2.0
    let bonusTextOutAnim = bonusNodeText.animationNamed("out")
    v.nearNode.addChild(bonusNodeText)
    bonusNodeText.hide()


    v.playBonusInAnimation = proc(callback: proc()) =
        bonusNodeBack.show()
        bonusNodeFront.show()

        v.addAnimation(bonusBackAnim)
        v.addAnimation(bonusFrontAnim)

        v.soundManager.sendEvent("BONUS_GAME_WORDS_ANIMATION")

        bonusFrontAnim.onComplete do():
            bonusNodeFront.hide()
            bonusFrontAnim.removeHandlers()
            callback()

        bonusBackAnim.onComplete do():
            bonusNodeBack.hide()
            bonusBackAnim.removeHandlers()

        let bonusBackAnimDuration = bonusBackAnim.loopDuration - 0.75
        v.wait bonusBackAnimDuration, proc() =
            bonusNodeBlue.show()
            bonusNodeText.show()
            v.addAnimation(bonusBlueInAnim)
            v.addAnimation(bonusTextInAnim)

            v.soundManager.sendEvent("BONUS_GAME_ANNOUNCE")

            bonusTextInAnim.onComplete do():
                v.addAnimation(bonusTextIdleAnim)
                bonusTextInAnim.removeHandlers()

    v.playBonusOutAnimation = proc(callback: proc()) =
        v.addAnimation(bonusBlueOutAnim)
        v.addAnimation(bonusTextOutAnim)

        bonusTextIdleAnim.cancel()

        bonusTextOutAnim.onComplete do():
            bonusTextOutAnim.removeHandlers()
            bonusNodeBlue.hide()
            bonusNodeText.hide()

        callback()

    #FREESPIN
    let freespNodeBack = newLocalizedNodeWithResource(resPath & "freespin/FreeSpins_back.json")
    let freespBackAnim = freespNodeBack.animationNamed("play")
    v.farNode.addChild(freespNodeBack)
    freespNodeBack.hide()

    let freespNodeFront = newLocalizedNodeWithResource(resPath & "freespin/FreeSpins_Front.json")
    let freespFrontAnim = freespNodeFront.animationNamed("play")
    v.nearNode.addChild(freespNodeFront)
    freespNodeFront.hide()

    v.playFreespinAnimation = proc(callback: proc()) =
        v.soundManager.sendEvent("FREE_SPINS_WORDS_ANIMATION")

        freespNodeBack.show()
        freespNodeFront.show()
        v.addAnimation(freespBackAnim)
        v.addAnimation(freespFrontAnim)
        freespBackAnim.onComplete do():
            freespBackAnim.removeHandlers()
            freespNodeBack.hide()
            callback()
        freespFrontAnim.onComplete do():
            freespFrontAnim.removeHandlers()
            freespNodeFront.hide()

    # SIMPLE
    # BIGWIN
    # HUGEWIN
    # MEGAWIN
    # JACKPOT

    v.fullscreenButtonsActions = @[]

    v.playWinAnimation = @[]

    v.winWindowReadyForDestroy = false

    var jobIn: proc(callback: proc()) = proc(callback: proc() = proc() = discard) =
        callback()
    var jobOut: proc(callback: proc()) = proc(callback: proc() = proc() = discard) =
        callback()
    v.playWinAnimation.add( (jobIn, jobOut) )

    let bigwinResLocations = @[
        ["bigwin/BigWin_back.json" , "BALLOON_BIG"    , "BALLOON_WIN"],
        ["bigwin/HugeWin_back.json", "BALLOON_HUGE"   , "BALLOON_WIN"],
        ["bigwin/MegaWin_back.json", "BALLOON_MEGA"   , "BALLOON_WIN"],
        ["bigwin/JackPot_back.json", "BALLOON_JACKPOT", "BALLOON_WIN"]
    ]

    proc replaceSolidWithScissor(n: Node) =
        let solid = n.componentIfAvailable(Solid)
        if not solid.isNil:
            let clip = n.component(ClippingRectComponent)
            clip.clippingRect = newRect(0, 0, solid.size[0], solid.size[1])
            n.removeComponent(Solid)
        for c in n.children:
            c.replaceSolidWithScissor()

    v.textWinNode = newLocalizedNodeWithResource(resPath & "bigwin/TextWin_front.json")
    v.textWinNode.replaceSolidWithScissor()

    let textWinComponent1 = v.textWinNode.findNode("WIN").componentIfAvailable(Text)
    let textWinComponent2 = v.textWinNode.findNode("BIG").componentIfAvailable(Text)
    v.textWinAnimIn = v.textWinNode.animationNamed("in")
    v.nearNode.addChild(v.textWinNode)
    v.textWinNode.hide()

    for res in bigwinResLocations:
        closureScope:
            let resLocation = res[0]
            let bigwinNode = newLocalizedNodeWithResource(resPath & resLocation)
            let bigwinNodeMask = bigwinNode.component(TextMask)
            let bigwinInAnim = bigwinNode.animationNamed("in")
            bigwinInAnim.loopDuration = bigwinInAnim.loopDuration * 2.0
            let bigwinIdleAnim = bigwinNode.animationNamed("idle")
            bigwinIdleAnim.numberOfLoops = -1
            bigwinIdleAnim.loopPattern = lpStartToEndToStart
            bigwinIdleAnim.loopDuration = bigwinIdleAnim.loopDuration * 4.0
            let bigwinOutAnim = bigwinNode.animationNamed("out")
            bigwinOutAnim.loopDuration = bigwinOutAnim.loopDuration * 2.0
            v.farNode.addChild(bigwinNode)
            bigwinNode.hide()

            let playOutWinAnimation = proc(callback: proc()) =
                v.addAnimation(bigwinOutAnim)
                bigwinOutAnim.onComplete do():
                    bigwinOutAnim.removeHandlers()
                    bigwinIdleAnim.cancel()
                    bigwinNode.hide()
                    callback()

            let text1 = localizedString(res[2])
            let text2 = localizedString(res[1])

            let playInWinAnimation = proc(callback: proc()) =
                v.textWinNode.show()
                textWinComponent1.text = text1
                textWinComponent2.text = text2
                v.textWinAnimIn.loopPattern = lpStartToEnd
                v.addAnimation(v.textWinAnimIn)
                v.soundManager.sendEvent(text2 & "_" & text1)
                bigwinNode.show()
                v.addAnimation(bigwinInAnim)
                bigwinInAnim.onComplete do():
                    bigwinInAnim.removeHandlers()
                    v.addAnimation(bigwinIdleAnim)
                    callback()

            v.playWinAnimation.add((playInWinAnimation, playOutWinAnimation))

    # 5 IN A ROW
    let fiveFarNode = newLocalizedNodeWithResource(resPath & "bigwin/5in_a_row_back.json")
    # let fiveFarNodeMask = fiveFarNode.component(TextMask)
    let fiveFarAnim = fiveFarNode.animationNamed("play")
    v.farNode.addChild(fiveFarNode)
    fiveFarNode.hide()

    let fiveNearNode = newLocalizedNodeWithResource(resPath & "bigwin/5in_a_row_front.json")
    let fiveNearAnim = fiveNearNode.animationNamed("play")
    v.nearNode.addChild(fiveNearNode)
    fiveNearNode.hide()

    v.play5InRowAnimation = proc(callback: proc()) =
        v.soundManager.sendEvent("5_IN_ROW")
        fiveFarNode.fadeShow()
        v.addAnimation(fiveFarAnim)
        fiveFarAnim.onComplete do():
            fiveFarNode.fadeHide()
            fiveFarAnim.removeHandlers()

        fiveNearNode.fadeShow()
        v.addAnimation(fiveNearAnim)
        fiveNearAnim.onComplete do():
            fiveNearNode.fadeHide()
            fiveNearAnim.removeHandlers()

            callback()

    # LOAD INTRO
    v.introAnimsNodes = @[]
    v.introAnims = @[]

    proc registerAnimation(n: Node, animSeq: var seq[Node]) =
        if not isNil(n.animations):
            for anim in n.animations.values():
                animSeq.add(n)
                n.registerAnimation("play", anim)
                v.introAnims.add(anim)

        for child in n.children:
            registerAnimation(child, animSeq)

    # block spin button
    v.setSpinButtonState(SpinButtonState.Blocked)

    # intro
    let introPathLocation = resPath & "intro/camera_anim.dae"
    loadSceneAsync introPathLocation, proc(n: Node) =
        let introSceneNode = newNodeWithResource(resPath & "intro/intro.json")
        let camParent = n.findNode("camera_anim_anchor")

        # skybox==skyplane
        var skyNode = newNodeWithResource(resPath & "intro/sky_sprite.json")
        skyNode.positionZ = -5000.0
        skyNode.scale = newVector3(2.5, 2.5, 2.5)

        var treeRailsNode: Node
        var farTreeAnch: Node
        var nearTreeAnch: Node
        var midTreeAnch: Node

        var cloudAnchorNode: Node
        var cloudRangeNode1: Node
        var cloudRangeNode2: Node
        var cloudRangeNode3: Node
        var cloudRangeNode4: Node
        var cloudRangeNode5: Node

        var windAnchorNode: Node

        treeRailsNode = newNode("tree_anchor")
        cloudAnchorNode = newNodeWithResource(resPath & "intro/clouds_anchor.json")

        # make hierarchy
        v.rootNode.addChild(introSceneNode)
        v.rootNode.addChild(n)

        let worldNode = camParent.newChild("world")
        worldNode.addChild(skyNode)
        worldNode.addChild(cloudAnchorNode)
        worldNode.addChild(treeRailsNode)

        v.shakeWrap(worldNode)

        camParent.addChild(v.cameraNode)

        # intro anim + timeings
        n.registerAnimation(v.introAnimsNodes)
        let cameraAnimation = v.introAnimsNodes[0].animationNamed("play")

        # TODO REMOVE DEBUG ONLY
        let INTRO_SPEED_MULTIPLIER = 1.0
        cameraAnimation.loopDuration = cameraAnimation.loopDuration * INTRO_SPEED_MULTIPLIER

        # intro start
        let restoreAnim = newAnimation()
        restoreAnim.numberOfLoops = 1
        restoreAnim.loopDuration = 0.55 * cameraAnimation.loopDuration * INTRO_SPEED_MULTIPLIER
        restoreAnim.onComplete do():
            if not v.currResponse.isNil:
                v.playBackgroundMusic(MusicType.Main)
                v.isInBonusGame = false
                v.isInFreeSpins = false

                if v.currResponse.stage == FreeSpinStage:
                    v.gTotalRoundWin += v.currResponse.payout
                    v.playAllIn do():
                        v.showControllerDestructions()
                        v.wait 0.5, proc() =
                            v.onSpinResponse()
                else:
                    if v.prevResponse.stage == BonusStage:
                        v.restoreAfterBonusGame()
                    else:
                        # v.respin()
                        v.gTotalRoundWin += v.currResponse.payout
                        v.playAllIn do():
                            v.showControllerDestructions()
                            if v.currResponse.stage != BonusStage:
                                v.unlockSpinIfLevelUp()

            # fly out anim
            let flyOutTime = 1.0 * INTRO_SPEED_MULTIPLIER
            var animCameraOut = newAnimation()
            animCameraOut.numberOfLoops = 1
            animCameraOut.loopDuration = flyOutTime
            var startTranslation = 0.0
            var destTranslation = -CAMERA_Z_IN_STANDART
            animCameraOut.animate val in startTranslation .. destTranslation:
                v.rootCameraNode.positionZ = val
            v.addAnimation(animCameraOut)
            v.updateTotalBetPanel()


        v.addAnimation(restoreAnim)
        v.introAnims.add(restoreAnim)

        proc createCloudsAnim() =
            # clouds anim
            var cloudMeshLib: seq[MeshComponent] = @[]
            var nearPlaneLib: seq[MeshComponent] = @[]
            var midPlaneLib: seq[MeshComponent] = @[]
            var farPlaneLib: seq[MeshComponent] = @[]

            var cloudNodeRes = newNodeWithResource(resPath & "intro/cloud_2d_resource.json")
            var cloudSprites = cloudNodeRes.componentIfAvailable(Sprite)

            for i in 0..2:
                closureScope:
                    var cloudNode = newNodeWithResource(resPath & "intro/cloud.json")
                    let meshCloud = cloudNode.componentIfAvailable(MeshComponent)
                    var img = cloudSprites.images[i]
                    meshCloud.material.albedoTexture = img
                    meshCloud.material.depthEnable = false
                    cloudMeshLib.add(meshCloud)
                    # init mesh on render path
                    v.rootNode.addChild(cloudNode)
                    cloudNode.positionZ = 1000.0
                    v.wait 0.5, proc() =
                        cloudNode.removeFromParent()

            farPlaneLib.add(cloudMeshLib[2])
            farPlaneLib.add(cloudMeshLib[1])

            midPlaneLib.add(cloudMeshLib[2])
            midPlaneLib.add(cloudMeshLib[1])
            midPlaneLib.add(cloudMeshLib[0])

            nearPlaneLib.add(cloudMeshLib[1])
            nearPlaneLib.add(cloudMeshLib[0])

            cloudRangeNode1 = cloudAnchorNode.findNode("cloud_1")
            cloudRangeNode1.scale = newVector3(0.6,0.6,0.6)
            cloudRangeNode1.position = newVector3(0,96,-400)
            var cloudInstComponent = cloudRangeNode1.component(InstanceCloud)
            cloudInstComponent.MeshComponent.material.depthEnable = false
            cloudInstComponent.MeshComponent.fromMeshComponent(newNodeWithResource(resPath & "intro/cloud.json").componentIfAvailable(MeshComponent))
            var start = newVector3(800, 0, 0)
            var dest = newVector3(-800, 0, 0)
            var duration = 35.0 * 0.8
            var cloudCount = 3
            var stepX = (abs(start.x) + abs(dest.x))/cloudCount.float32
            for j in 0..<cloudCount:
                closureScope:
                    var waitBefore = j.float * 11.5 * 0.8
                    v.idleAnimations.add(cloudRangeNode1.newChild($j).initCloudsAnim((start, dest), duration, waitBefore, nearPlaneLib, 200.0, 150.0, j.float32*stepX))

            cloudRangeNode2 = cloudAnchorNode.findNode("cloud_2")
            cloudRangeNode2.position = newVector3(0,35,-600)
            cloudInstComponent = cloudRangeNode2.component(InstanceCloud)
            cloudInstComponent.MeshComponent.material.depthEnable = false
            cloudInstComponent.MeshComponent.fromMeshComponent(newNodeWithResource(resPath & "intro/cloud.json").componentIfAvailable(MeshComponent))
            start = newVector3(1150, 0, 0)
            dest = newVector3(-1150, 0, 0)
            duration = 50.0/1.8
            cloudCount = 4
            stepX = (abs(start.x) + abs(dest.x))/cloudCount.float32
            for j in 0..<cloudCount:
                closureScope:
                    var waitBefore = j.float * 12.5/1.8
                    v.idleAnimations.add(cloudRangeNode2.newChild($j).initCloudsAnim((start, dest), duration, waitBefore, nearPlaneLib, 100.0, 100.0, j.float32*stepX))

            cloudRangeNode3 = cloudAnchorNode.findNode("cloud_3")
            cloudRangeNode3.position = newVector3(-150,-25,-600)
            cloudInstComponent = cloudRangeNode3.component(InstanceCloud)
            cloudInstComponent.MeshComponent.material.depthEnable = false
            cloudInstComponent.MeshComponent.fromMeshComponent(newNodeWithResource(resPath & "intro/cloud.json").componentIfAvailable(MeshComponent))
            cloudInstComponent.material.ambient = newColor(0.636, 0.964, 0.82, 0.82)
            cloudInstComponent.material.diffuse = newColor(1.0, 1.0, 1.0, 1.0)
            start = newVector3(1500, -21, -750)
            dest = newVector3(-1500, -21, -750)
            duration = 64.0/2.2*1.2
            cloudCount = 5
            stepX = (abs(start.x) + abs(dest.x))/cloudCount.float32
            for j in 0..<cloudCount:
                closureScope:
                    var waitBefore = j.float * 12.75/2.2*1.2
                    v.idleAnimations.add(cloudRangeNode3.newChild($j).initCloudsAnim((start, dest), duration, waitBefore, midPlaneLib, 60.0, 80.0, j.float32*stepX))
            cloudRangeNode3.moveTo(newVector3(-150,-25,-600), newVector3(0,-25,-600), 12.75/2.2*1.2 * 8.0)

            cloudRangeNode4 = cloudAnchorNode.findNode("cloud_4")
            cloudInstComponent = cloudRangeNode4.component(InstanceCloud)
            cloudInstComponent.MeshComponent.material.depthEnable = false
            cloudRangeNode4.position = newVector3(-300,-60,-800)
            cloudRangeNode4.scale = newVector3(0.35,0.35,0.35)
            cloudInstComponent.MeshComponent.fromMeshComponent(newNodeWithResource(resPath & "intro/cloud.json").componentIfAvailable(MeshComponent))
            cloudInstComponent.material.ambient = newColor(0.636, 0.964, 0.82, 0.9)
            cloudInstComponent.material.diffuse = newColor(1.0, 1.0, 1.0, 0.8)
            start = newVector3(2500, -123, -1100)
            dest = newVector3(-2500, -123, -1100)
            duration = 74.0 / 1.5
            cloudCount = 8
            stepX = (abs(start.x) + abs(dest.x))/cloudCount.float32
            for j in 0..<cloudCount:
                closureScope:
                    var waitBefore = j.float * 9.2 / 1.5
                    v.idleAnimations.add(cloudRangeNode4.newChild($j).initCloudsAnim((start, dest), duration, waitBefore, farPlaneLib, 40.0, 60.0, j.float32*stepX))
            cloudRangeNode4.moveTo(newVector3(-300,-60,-800), newVector3(0,-60,-800), 9.2 / 1.5 * 8.0)

            cloudRangeNode5 = cloudAnchorNode.findNode("cloud_5")
            cloudRangeNode5.scale = newVector3(0.3,0.3,0.3)
            cloudRangeNode5.position = newVector3(-600,-110,-1000)
            cloudInstComponent = cloudRangeNode5.component(InstanceCloud)
            cloudInstComponent.MeshComponent.material.depthEnable = false
            cloudInstComponent.MeshComponent.fromMeshComponent(newNodeWithResource(resPath & "intro/cloud.json").componentIfAvailable(MeshComponent))
            cloudInstComponent.material.ambient = newColor(0.636, 0.964, 0.82, 1.0)
            cloudInstComponent.material.diffuse = newColor(1.0, 1.0, 1.0, 0.3)
            start = newVector3(3000, -320, -2000)
            dest = newVector3(-3000, -320, -2000)
            duration = 84.0 * 0.8
            cloudCount = 11
            stepX = (abs(start.x) + abs(dest.x))/cloudCount.float32
            for j in 0..<cloudCount:
                closureScope:
                    var waitBefore = j.float * 7.75 * 0.8
                    v.idleAnimations.add(cloudRangeNode5.newChild($j).initCloudsAnim((start, dest), duration, waitBefore, farPlaneLib, 20.0, 50.0, j.float32*stepX))
            cloudRangeNode5.moveTo(newVector3(-600,-110,-1000), newVector3(0,-110,-1000), 7.75 * 0.8 * 8.0)

            cloudAnchorNode.moveTo(newVector3(0,50,0), newVector3(0,0,0), cameraAnimation.loopDuration)

        proc createWindAnim() =
            # wind trails
            windAnchorNode = v.cameraNode.newChild("wind_anchor")
            var startTrailTime = 0.0
            var stepTrailTime = 2.0
            var posWind = @[-50.0,-100.0,-150.0,-200.0,-250.0,-300.0]
            for i in 0..5:
                closureScope:
                    let windNode = newNodeWithResource(resPath & "models/wind_trail.json")
                    windNode.name = "wind_" & $i
                    var parentNode = windAnchorNode.newChild("parent_wind_"& $i)
                    parentNode.addChild(windNode)
                    parentNode.positionY = posWind[i]
                    v.wait startTrailTime, proc() =
                        v.idleAnimations.add( initWindAnim(windNode, (newVector3(-900, 100, -500), newVector3(900, 100, -500)), 8.0, stepTrailTime.float32) )
                    startTrailTime += stepTrailTime
            # reatach
            v.cameraNode.addChild(windAnchorNode)
            windAnchorNode.position = newVector3(250.0, 50.0, -450.0)
            windAnchorNode.alpha = 1.1

        # flying tree anim
        proc createTreeAnim() =
            # far_plane trees
            farTreeAnch = treeRailsNode.newChild("far")
            farTreeAnch.position = newVector3(0,-235,-1000)
            farTreeAnch.scale = newVector3(0.4,0.4,0.4)
            let farInstancedTree = farTreeAnch.component(InstanceMesh)
            farInstancedTree.MeshComponent.fromMeshComponent(newNodeWithResource(resPath & "intro/board_tree.json").componentIfAvailable(MeshComponent))
            farInstancedTree.material.ambient = newColor(0.38, 0.67, 0.74, 1.0)
            farInstancedTree.material.emission = newColor(0.05, 0.05, 0.05, 1.0)
            for i in 0 ..< 7:
                closureScope:
                    var waitBefore = i.float * 3.2
                    var tree = farTreeAnch.newChild($i)
                    var start = newVector3(1350, 0, 0)
                    var dest = newVector3(-1350, 0, 0)
                    var duration = 22.0
                    v.idleAnimations.add(tree.initCloudsAnim((start, dest), duration, waitBefore))

            # near_plane trees
            v.wait 0.18 * cameraAnimation.loopDuration, proc() =
                nearTreeAnch = treeRailsNode.newChild("near")
                nearTreeAnch.position = newVector3(0,-100,-300)
                nearTreeAnch.scale = newVector3(10,10,10)
                let nearInstancedTree = nearTreeAnch.component(InstanceMesh)
                nearInstancedTree.MeshComponent.fromMeshComponent(newNodeWithResource(resPath & "intro/tree.json").componentIfAvailable(MeshComponent))
                for i in 1 ..< 10:
                    var waitBefore = i.float * 1.2
                    let tree = nearTreeAnch.newChild($i)
                    v.idleAnimations.add( tree.initTreeAnim((newVector3(20, 0, 0), newVector3(-20, 0, 0)), 7.0, waitBefore, true, true) )

            # mid_plane trees
            midTreeAnch = treeRailsNode.newChild("mid")
            midTreeAnch.position = newVector3(0,-150,-500)
            midTreeAnch.scale = newVector3(10,10,10)
            let midInstancedTree = midTreeAnch.component(InstanceMesh)
            midInstancedTree.MeshComponent.fromMeshComponent(newNodeWithResource(resPath & "intro/tree.json").componentIfAvailable(MeshComponent))
            midInstancedTree.material.ambient = newColor(0.34, 0.46, 0.49, 1.0)
            midInstancedTree.material.emission = newColor(0.05, 0.05, 0.05, 1.0)
            for i in 1 ..< 20:
                var waitBefore = i.float * 1.4
                let tree = midTreeAnch.newChild($i)
                v.idleAnimations.add( tree.initTreeAnim((newVector3(30, 0, 0), newVector3(-30, 0, 0)), 7.0*2.0, waitBefore, true, true) )

        createCloudsAnim()

        createWindAnim()

        createTreeAnim()

        let leavesNode = newNodeWithResource(resPath & "particles/leaves/root_leaves.json")
        v.cameraNode.addChild( leavesNode )

        let skyAnim = newAnimation()
        skyAnim.numberOfLoops = 1
        skyAnim.loopDuration = 0.2 * cameraAnimation.loopDuration
        # * INTRO_SPEED_MULTIPLIER
        skyAnim.onComplete do():
            # createWindAnim()
            windAnchorNode.reparentTo(v.cameraNode)

            # createTreeAnim()

            v.wait 5.0, proc() =
                farTreeAnch.componentIfAvailable(InstanceMesh).MeshComponent.material.depthEnable = false
                cloudRangeNode1.componentIfAvailable(InstanceCloud).MeshComponent.material.depthEnable = false
                cloudRangeNode2.componentIfAvailable(InstanceCloud).MeshComponent.material.depthEnable = false
                cloudRangeNode3.componentIfAvailable(InstanceCloud).MeshComponent.material.depthEnable = false
                cloudRangeNode4.componentIfAvailable(InstanceCloud).MeshComponent.material.depthEnable = false
                cloudRangeNode5.componentIfAvailable(InstanceCloud).MeshComponent.material.depthEnable = false

            # GLOBAL REATACH
            v.cameraNode.addChild(v.farNode)
            v.farNode.position = newVector3(-120.0, 67.0, -250.0)
            v.farNode.scale = newVector3(0.125, -0.125, -0.125)

            v.rootCameraNode.reparentTo(v.cameraNode)

            v.shakeWrap(v.rootCameraNode)

            v.cameraNode.addChild(v.nearNode)
            v.nearNode.position = newVector3(-57.6, 32.6, -120.0)
            v.nearNode.scale = newVector3(0.06, -0.06, -0.06)

            leavesNode.reparentTo(v.cameraNode)

            v.rootCameraNode.findNode("gui_anchor").reparentTo(v.cameraNode)

        v.addAnimation(skyAnim)
        v.introAnims.add(skyAnim)

        # intro anim
        cameraAnimation.numberOfLoops = 1
        cameraAnimation.onComplete do():
            var gc = v.rootNode.componentIfAvailable(GlitchComponent)
            if not gc.isNil: v.rootNode.removeComponent(GlitchComponent)

            # cleanup
            introSceneNode.removeFromParent()
            n.removeFromParent(false)
            v.rootNode.addChild(camParent)
            camParent.name = "root_camera"

            # camera idle anim
            v.idleAnimations.add( initCameraAnim(v.rootCameraNode, (0.float32, radToDeg(2*3.14.float32)), 512.0.float32) )

        v.addAnimation(cameraAnimation)

method init*(v: BalloonSlotView, r: Rect) =
    procCall v.BaseMachineView.init(r)
    v.gLines = 25
    v.multBig = 8
    v.multHuge = 11
    v.multMega = 13

    v.addDefaultPerspectiveCamera("Camera")

method draw*(v: BalloonSlotView, r: Rect) =
    procCall v.SceneView.draw(r)

method viewOnExit*(v: BalloonSlotView) =

    for a in v.idleAnimations:
        a.cancel()
    procCall v.BaseMachineView.viewOnExit()

method assetBundles*(v: BalloonSlotView): seq[AssetBundleDescriptor] =
    const ASSET_BUNDLES = [
        assetBundleDescriptor("slots/balloon_slot")
    ]
    result = @ASSET_BUNDLES

method clickScreen(v: BalloonSlotView) = discard
