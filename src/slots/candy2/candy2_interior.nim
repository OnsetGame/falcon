import node_proxy.proxy
import nimx / [ animation, types, matrixes ]
import utils / [ helpers, sound_manager, animation_controller ]
import rod / [ node, component ]
import rod / component / [ clipping_rect_component, ae_composition ]
import shared.game_scene
import core.slot.slot_types
import core.slot.sound_map
import sequtils, strutils, random, tables
import candy2_types, candy2_spin, candy2_anticipation

const FIRST_ELEM = 3'i8
const LAST_ELEM = 10'i8

nodeProxy ElemBackLight:
    aeComp AEComposition {onNode: node}
    rotNode Node {withName: "ltp_c_00_4.png"}
    inAnim* Animation {withValue: np.aeComp.compositionNamed("in")}
    outAnim* Animation {withValue: np.aeComp.compositionNamed("out")}
    playAnim Animation {withValue: newCompositAnimation(false, @[np.inAnim, np.outAnim])}:
        numberOfLoops = 1

nodeProxy Interior:
    lightsIdle* Animation {withKey: "play", forNode: "lights"}
    lightsShake* Animation {withKey: "shake", forNode: "lights"}
    rouletteMove* Animation {withKey: "play", forNode: "roulette"}
    roulette Node {withName: "roulette"}
    curtainParent Node {withName: "curtain_parent"}
    tableField* Node {withName: "table_field"}
    lollipop Node {withName: "lollipop"}
    sweetParent Node {withName: "sweet_parent"}
    lollipopPlay Animation {withKey: "play", forNode: "lollipop"}
    tables* seq[Node] {withValue: toSeq(0..ELEMENTS_COUNT - 1).map(proc(i: int): Node = np.node.findNode("table_" & $i))}
    placeholders* seq[Placeholder]
    antAnims* seq[Animation]
    cachedElems TableRef[string, seq[Element]]
    transition* Node {withName: "transition"}
    antBack* Node {addTo: "transition", withName: "anticipation_back"}
    antFront* Node {withName: "anticipation_parent"}
    winlineParent* Node {withName: "winline_parent"}
    eaComp* AEComposition {onNode: node}
    move* Animation {withValue: np.eaComp.compositionNamed("move", @["table_field"])}
    anticipationStopped* bool
    backLights seq[ElemBackLight]
    sound* SoundMap

proc createInterior*(): Interior =
    result = new(Interior, newLocalizedNodeWithResource("slots/candy2_slot/interior/precomps/interior"))
    result.cachedElems = newTable[string, seq[Element]]()
    result.placeholders = @[]

    result.transition.insertChild(result.antBack, result.transition.children.len - 2)
    result.antBack.worldPos = newVector3()

    for t in result.tables:
        let plac = createPlaceholder(t)
        result.placeholders.add(plac)

proc setRouletteScissor*(interior: Interior) =
    interior.curtainParent.component(ClippingRectComponent).clippingRect = newRect(0, 00, 2000, 0)

proc moveRoulette*(interior: Interior,  down: bool, instant: bool): Animation {.discardable.} =
    var anim = interior.rouletteMove

    interior.sound.play("CANDY_CURTAIN_SHUTS")

    proc moveCurtain(p: float) =
        let scissorY = (interpolate(0, 870, p)).Coord
        interior.curtainParent.component(ClippingRectComponent).clippingRect = newRect(0, 0, 2000, scissorY)
    result = addOnAnimate(anim, moveCurtain)
    if down:
        result.loopPattern = LoopPattern.lpStartToEnd
    else:
        result.loopPattern = LoopPattern.lpEndToStart
    interior.node.addAnimation(result)

proc startLollipop*(interior: Interior)  =
    interior.lollipopPlay.numberOfLoops = -1
    interior.node.addAnimation(interior.lollipopPlay)
    interior.sweetParent.component(ClippingRectComponent).clippingRect = newRect(0, 0, 300, 400)

proc getElem*(t: Interior, key: string): Element=
    var elems = t.cachedElems.getOrDefault(key)
    if elems.len == 0:
        return createElement(key)
    result = elems[0]
    elems.del(0)
    t.cachedElems[key] = elems

proc putElem(t: Interior, node: Node)=
    var elems = t.cachedElems.getOrDefault(node.name)
    var elem = createElement(node)

    elems.add(elem)
    t.cachedElems[node.name] = elems

proc spinIn*(t: Interior, cb: proc())=
    let startAnim = newAnimation()

    startAnim.loopDuration = 1
    startAnim.numberOfLoops = 1
    for ri in 0..NUMBER_OF_REELS - 1:
        let reelIndexes = reelToIndexes(ri)
        for i in reelIndexes:
            closureScope:
                let index = i
                let reelIndex = ri

                startAnim.addLoopProgressHandler 0.25 * reelIndex.float, false, proc() =
                    let spinElementAnim = spinInAnim(t.placeholders[index])

                    t.node.addAnimation(spinElementAnim)
                    if index == ELEMENTS_COUNT - 1:
                        spinElementAnim.onComplete do():
                            cb()
    t.node.addAnimation(startAnim)

proc setElement*(t: Interior, index: int, value: int8) =
    let plac = t.placeholders[index]

    if plac.node.children.len > 0:
        t.putElem(plac.node.children[0])
        plac.node.removeAllChildren()

    let k = "elem_" & $value
    var elem = t.getElem(k)

    t.placeholders[index].node.addChild(elem.node)
    t.placeholders[index].element = elem

proc setElements*(t: Interior, field: openarray[int8]) =
    for i in 0..t.placeholders.high:
        t.setElement(i, field[i])

proc removeBacklights*(t: Interior, cb: proc())=
    if t.backLights.len == 0:
        cb()
    else:
        var anims = newSeq[Animation]()
        for ri in 0..NUMBER_OF_REELS - 1:
            let reelIndexes = reelToIndexes(ri)
            for i in reelIndexes:
                var bl = t.backLights[i]
                if not bl.isNil:
                    let p = t.placeholders[i]
                    var idle = newAnimation()
                    idle.loopDuration = ri.float * 0.1
                    idle.numberOfLoops = 1

                    p.node.parent.insertChild(bl.node, 0)
                    bl.node.position = newVector3(-162, -325)

                    var a = newCompositAnimation(false, @[idle, bl.outAnim])
                    a.numberOfLoops = 1
                    anims.add(a)

        var a = newCompositAnimation(true, anims)
        a.numberOfLoops = 1
        t.node.addAnimation(a)
        a.onComplete do():
            for b in t.backLights:
                if not b.isNil:
                    b.node.removeFromParent()
            t.backLights = @[]
            cb()

proc prepareBackLights*(t: Interior, animSettings: seq[RotationAnimSettings]) =
    t.backLights = newSeq[ElemBackLight](ELEMENTS_COUNT)

    for sett in animSettings:
        if sett.highlight.len > 0:
            for i in sett.highlight:
                if t.backLights[i].isNil:
                    t.backLights[i] = new(ElemBackLight, newNodeWithResource("slots/candy2_slot/winlines/precomps/candy_win_backlights"))
                    t.placeholders[i].node.parent.insertChild(t.backLights[i].node, 0)
                    t.backLights[i].node.position = newVector3(-162, -325)
                    t.backLights[i].rotNode.addRotateAnimation(505.0)

proc chooseElement(t: Interior, spinData: Candy2SpinData, index: int) =
    const CAKE = 11'i8

    if spinData.wildIndexes.contains(index):
        let firstReelIndexes = reelToIndexes(0)
        var elements: seq[int8] = @[]
        var exceptions: seq[int8] = @[]

        for fri in firstReelIndexes:
            exceptions.add(spinData.field[fri])
        for i in FIRST_ELEM..LAST_ELEM:
            if not exceptions.contains(i):
                elements.add(i)

        let r = rand(elements)
        t.setElement(index, r)
    elif spinData.wildActivator == index and spinData.wildIndexes.len > 0:
        t.setElement(index, CAKE)
    else:
        t.setElement(index, spinData.field[index])

proc spinOut*(t: Interior, settings: seq[RotationAnimSettings], spinData: Candy2SpinData, boy: AnimationController, cb: proc()) =
    proc spinOutEnd(a: Animation, cb: proc())=
        a.onComplete do():
            cb()


    t.antAnims = @[]
    for ri in 0..NUMBER_OF_REELS - 1:
        let reelIndexes = reelToIndexes(ri)
        let time = settings[ri].time
        var boosted = false

        if ri < NUMBER_OF_REELS - 1 and settings[ri + 1].boosted:
            boosted = true

        for i in reelIndexes:
            closureScope:
                let index = i
                let b = boosted
                let rii = ri
                let anim = newAnimation()
                let reelSettings = settings[rii]
                anim.loopDuration = time
                anim.numberOfLoops = 1
                anim.onComplete do():
                    t.sound.play("SPIN_END_" & $rand(1 .. 3))
                    let outAnim = spinOutAnim(t.placeholders[index])

                    t.chooseElement(spinData, index)
                    t.node.addAnimation(outAnim)

                    let finishAnim = t.placeholders[index].element.node.animationNamed("finish")
                    finishAnim.loopDuration = 0.15
                    if index == ELEMENTS_COUNT - 1:
                        finishAnim.spinOutEnd(cb)

                    t.node.addAnimation(finishAnim)
                    finishAnim.onComplete do():
                        if t.backLights.len != 0 and reelSettings.highlight.len > 0:
                            for el in reelSettings.highlight:
                                t.node.addAnimation(t.backLights[el].inAnim)
                                t.sound.play("CANDY_ROTATION_LIGHT")
                        if spinData.field[index] == 2:
                            t.sound.play("BONUS_STOP")
                        elif spinData.field[index] == 1:
                            t.sound.play("SCATTER_APPEAR")
                        elif spinData.field[index] == 0:
                            t.sound.play("CANDY_WILD_APPEAR")

                    if not t.anticipationStopped and b and index > ELEMENTS_COUNT - 4:
                        let anim = boy.setImmediateAnimation("anticipation")

                        anim.addLoopProgressHandler 0.2, false, proc() =
                            t.sound.play("BOY_CLAPS")
                        t.sound.play("ANTICIPATION_SOUND")
                        playAnticipation(t.antBack, t.antFront, rii + 1) do():
                            t.sound.stop("ANTICIPATION_SOUND")
                            t.sound.play("ANTICIPATION_STOP_SOUND")

                t.antAnims.add(anim)
                t.node.addAnimation(anim)

proc showWinLine*(t: Interior, lineIndexes: seq[int]): Animation=
    var anims = newSeq[Animation]()
    for i, li in lineIndexes:
        var items = newSeq[Animation]()

        var a = t.placeholders[li].element.node.component(AEComposition).compositionNamed("win")
        var bl = new(ElemBackLight, newNodeWithResource("slots/candy2_slot/winlines/precomps/candy_win_backlights"))
        t.placeholders[li].node.parent.insertChild(bl.node, 0)
        bl.node.position = newVector3(-162, -325)
        bl.rotNode.addRotateAnimation(505.0)

        closureScope:
            let blnode = bl.node
            bl.playAnim.onComplete do():
                blnode.removeFromParent()

        if i == 0:
            items.add(a)
            items.add(bl.playAnim)
        else:
            var ia = newAnimation()
            ia.numberOfLoops = 1
            ia.loopDuration = i.float * 0.1

            var ca = newCompositAnimation(true, @[a,bl.playAnim])
            ca.numberOfLoops = 1

            ca = newCompositAnimation(false, @[ia,ca])
            ca.numberOfLoops = 1
            items.add(ca)

        var aa = newCompositAnimation(true, items)
        aa.numberOfLoops = 1
        anims.add(aa)

    var r = newCompositAnimation(true, anims)
    r.numberOfLoops = 1
    t.node.addAnimation(r)

    result = r

proc firstFill*(interior: Interior) =
    var randomField: array[0..ELEMENTS_COUNT, int8]

    for reel in 0..NUMBER_OF_REELS - 1:
        var p = @[FIRST_ELEM, 4, 5, 6, 7, 8, 9, 10]
        let indexes = reelToIndexes(reel)

        for i in 0..indexes.high:
            let r = rand(p.high)
            randomField[indexes[i]] = p[r]
            p.delete(r)

    interior.setElements(randomField)


