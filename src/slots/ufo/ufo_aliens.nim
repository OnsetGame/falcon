import nimx     / [animation,types,matrixes]
import rod      / [node, viewport, component.color_balance_hls]
import utils    / [sound_manager,and_gate, helpers]
import rod.component.ae_composition
import logging, strutils

import ufo_types

const ALIEN_NODE_NAME = "alien_core"

type AnimationInfo* = ref object of RootObj
    pStart: float
    pEnd: float
    node: Node
    animName: string
    hideOnComplete:bool

proc newAnimationInfo(node:Node, animName: string, hideOnComplete: bool = true, pStart:float = 0.0, pEnd:float = 1.0): AnimationInfo =
    result.new()
    result.node = node
    result.animName = animName
    result.hideOnComplete = hideOnComplete
    result.pStart = pStart
    result.pEnd = pEnd

proc composeCompositAnimation(aInfos : seq[AnimationInfo]): CompositAnimation =
    ## Creates one animation with target duration from sequence of animations.
    doAssert(aInfos.len > 0)

    var cmList = newSeq[ComposeMarker]()
    var duration = 0.0
    for ai in aInfos:
        closureScope:
            let closeAi = ai
            let anim = closeAi.node.animationNamed(closeAi.animName)
            duration = anim.loopDuration
            if anim.isNil:
                info "Couldn't find animation $1 for node $2".format(closeAi.animName, closeAi.node.name)
            else:
                if closeAi.node.alpha < 0.1:
                    anim.addLoopProgressHandler 0.0, false, proc() =
                        closeAi.node.alpha = 1.0
                if closeAi.hideOnComplete:
                    anim.onComplete do():
                        closeAi.node.alpha = 0.0
                let cm = newComposeMarker(closeAi.pStart,closeAi.pEnd,anim)
                cmList.add(cm)

    result = newCompositAnimation(duration, cmList)
    result.numberOfLoops = 1

proc isChangeAnimStateImmediate(stateFrom:AlienAnimStates, stateTo:AlienAnimStates):bool =
    result = false
    case stateFrom:
    of AlienAnimStates.None,
        AlienAnimStates.SpecialIdle,
        AlienAnimStates.InPortal,
        AlienAnimStates.Intro,
        AlienAnimStates.WildWin,
        AlienAnimStates.Anticipation,
        AlienAnimStates.Spin,
        AlienAnimStates.WildToPortal:
        result = true
    else:
        discard

proc addWildTextAnim(aNode,wtNode:Node, animName:string, isRed: bool): Animation =
    let wildTextParent = aNode.findNode("wild_text_p")
    wildTextParent.affectsChildren = true

    if isRed:
        wildTextParent.component(ColorBalanceHLS).hue = 130.0 / 360.0

    assert(not wtNode.isNil)
    wildTextParent.addChild(wtNode)

    let aeComp = wtNode.component(AEComposition)
    result = aeComp.compositionNamed(animName)

    assert(not result.isNil)


proc addPortalPartsAnim(aNode:Node): Animation =
    let portalParent = aNode.findNode("Portal_p")
    let partsNode = newLocalizedNodeWithResource(GENERAL_PREFIX&"slot/aliens/portal_small")

    assert(not partsNode.isNil)
    portalParent.addChild(partsNode)
    var nodeIndex = 0
    for i,n in aNode.parent.children:
        if n.name == aNode.name:
            nodeIndex = i
    partsNode.reattach(aNode.parent, nodeIndex-1)

    let aeComp = partsNode.component(AEComposition)
    result = aeComp.compositionNamed("play")

    assert(not result.isNil)
    result.onComplete do():
        partsNode.removeFromParent()


proc addShineAnim(aNode:Node): Animation =
    let portalParent = aNode.findNode("Portal_p")
    let shineNode = newLocalizedNodeWithResource(GENERAL_PREFIX&"slot/aliens/Shine")
    assert(not shineNode.isNil)
    portalParent.addChild(shineNode)
    var nodeIndex = 0
    for i,n in aNode.parent.children:
        if n.name == aNode.name:
            nodeIndex = i
    shineNode.reattach(aNode.parent, nodeIndex+1)

    let aeComp = shineNode.component(AEComposition)
    result = aeComp.compositionNamed("play")

    assert(not result.isNil)
    result.onComplete do():
        shineNode.removeFromParent()


proc setAnimState*(alien:BaseAlien, nextState:AlienAnimStates, onCompleteHandler: proc() = nil, onAnimateHandler: proc(p:float) = nil) =
    #echo "Trying to set animstate ", nextState, " for ", alien.node.name , " currently in ", alien.curAnimationState
    if alien.curAnimationState == nextState:
        if alien.curAnimation != nil and not alien.curAnimation.finished:
            info "alien already in $1 animation state".format($nextState)
            return

    if alien.curAnimationState in {AlienAnimStates.WildToPortal,AlienAnimStates.InPortal} and not alien.curAnimation.finished:
        echo "Canceled wild setAnimState $1 couse it in WildToPortal anim".format($nextState)
        return

    var nextAnimation : Animation = nil
    var onCompleteAnimState = AlienAnimStates.None
    var nextAnimSound:string

    let isRed = alien.index == "A1"

    let sm = alien.sceneView.sound_manager
    case nextState
        of AlienAnimStates.None:
            discard
        of AlienAnimStates.Idle:
            let aiAlienAnim = newAnimationInfo(alien.node,$CharAnim.Idle_1,false)
            nextAnimation = composeCompositAnimation(@[aiAlienAnim])
            nextAnimation.numberOfLoops = -1

        of AlienAnimStates.Intro:
            let aiAlienIntro = newAnimationInfo(alien.node,$CharAnim.Intro,false)
            nextAnimation = composeCompositAnimation(@[aiAlienIntro])

            nextAnimation.addLoopProgressHandler 0.0, false, proc() =
                 alien.sceneView.addAnimation(addShineAnim(alien.node))
                 alien.sceneView.addAnimation(addPortalPartsAnim(alien.node))

            onCompleteAnimState = AlienAnimStates.Idle

            nextAnimSound = "_INTRO"
        of AlienAnimStates.SpecialIdle:
            let aiAlienAnim = newAnimationInfo(alien.node,$CharAnim.Idle_2,false)
            nextAnimation = composeCompositAnimation(@[aiAlienAnim])

            onCompleteAnimState = AlienAnimStates.Idle
            nextAnimSound = "_SPECIAL_IDLE"
        of AlienAnimStates.Spin:
            let aiAlienAnim = newAnimationInfo(alien.node,$CharAnim.Spin,false)
            nextAnimation = composeCompositAnimation(@[aiAlienAnim])

            onCompleteAnimState = AlienAnimStates.Idle
            nextAnimSound = "_SPIN"
        of AlienAnimStates.Anticipation:
            var anticipation_start_anim = alien.node.animationNamed($CharAnim.AnticipationStart)
            anticipation_start_anim.addLoopProgressHandler 0.0, false, proc() =
                sm.sendEvent(alien.index&"_ANTICIPATION_START")
            var anticipation_loop_anim = alien.node.animationNamed($CharAnim.AnticipationLoop)
            anticipation_loop_anim.numberOfLoops = 3

            var anticipation_end_anim = alien.node.animationNamed($CharAnim.AnticipationEnd)
            anticipation_end_anim.addLoopProgressHandler 0.0, false, proc() =
                sm.sendEvent(alien.index&"_ANTICIPATION_END")

            nextAnimation = newCompositAnimation(false, @[anticipation_start_anim,anticipation_loop_anim,anticipation_end_anim])
            nextAnimation.numberOfLoops = 1

            onCompleteAnimState = AlienAnimStates.Idle

        of AlienAnimStates.Win:
            let aiAlienAnim = newAnimationInfo(alien.node,$CharAnim.Win,false)
            nextAnimation = composeCompositAnimation(@[aiAlienAnim])

            onCompleteAnimState = AlienAnimStates.Idle

            nextAnimSound = "_WIN"

        of AlienAnimStates.BigWin:
            let aiAlienAnim = newAnimationInfo(alien.node,$CharAnim.BigWin,false)
            nextAnimation = composeCompositAnimation(@[aiAlienAnim])

            onCompleteAnimState = AlienAnimStates.Idle

            nextAnimSound = "_BIGWIN"
        of AlienAnimStates.InPortal:

            let aiAlienAnim = newAnimationInfo(alien.node,$CharAnim.InPortal)
            nextAnimation = composeCompositAnimation(@[aiAlienAnim])

            nextAnimation.addLoopProgressHandler 0.3, false, proc() =
                alien.sceneView.addAnimation(addShineAnim(alien.node))

            nextAnimSound ="_INPORTAL"
        of AlienAnimStates.WildAppear:
            let aiAlien = newAnimationInfo(alien.node,$CharAnim.WildAppear,false)

            var wtNode:Node = nil
            if isRed:
                wtNode = newLocalizedNodeWithResource(GENERAL_PREFIX&"slot/aliens/wild_intro_red")
            else:
                wtNode = newLocalizedNodeWithResource(GENERAL_PREFIX&"slot/aliens/wild_intro")

            let wildTextIntroAnim = addWildTextAnim(alien.node, wtNode, "play", isRed)
            wildTextIntroAnim.onComplete do():
                wtNode.removeFromParent()

            nextAnimation = composeCompositAnimation(@[aiAlien])
            nextAnimation.addLoopProgressHandler 0.0, false, proc() =
                alien.sceneView.addAnimation(addPortalPartsAnim(alien.node))
                alien.sceneView.addAnimation(wildTextIntroAnim)

            onCompleteAnimState = AlienAnimStates.WildIdle

            nextAnimSound ="_WILDAPPEAR"
        of AlienAnimStates.WildIdle:
            let aiAlien = newAnimationInfo(alien.node,$CharAnim.WildIdle,false)
            var wtNode:Node = nil
            if isRed:
                wtNode = newLocalizedNodeWithResource(GENERAL_PREFIX&"slot/aliens/wild_idle_static_red")
            else:
                wtNode = newLocalizedNodeWithResource(GENERAL_PREFIX&"slot/aliens/wild_idle_static")

            let wildTextIdleAnim = addWildTextAnim(alien.node, wtNode, "wild_idle", isRed)
            wildTextIdleAnim.numberOfLoops = -1
            let char_ca = composeCompositAnimation(@[aiAlien])

            let cm1 = newComposeMarker(0.0,0.95,char_ca)
            let cm2 = newComposeMarker(0.0,1.0,wildTextIdleAnim)
            var markers = @[cm1,cm2]

            nextAnimation = newCompositAnimation(wildTextIdleAnim.loopDuration, markers)
            nextAnimation.onComplete do():
                wtNode.hide(0.1, proc() = wtNode.removeFromParent())

        of AlienAnimStates.WildMoveRight:
            # not used anymore...
            discard
        of AlienAnimStates.WildWin:
            let aiAlien = newAnimationInfo(alien.node,$CharAnim.WildWin,false)

            let wtNode = newLocalizedNodeWithResource(GENERAL_PREFIX&"slot/aliens/wild_win")
            let wildTextWinAnim = addWildTextAnim(alien.node, wtNode, "play", isRed)
            wildTextWinAnim.onComplete do():
                wtNode.removeFromParent()

            nextAnimation = composeCompositAnimation(@[aiAlien])

            nextAnimation.addLoopProgressHandler 0.0, true, proc() =
                alien.sceneView.addAnimation(wildTextWinAnim)

            onCompleteAnimState = AlienAnimStates.WildIdle
            nextAnimSound = "_WILDWIN"
        of AlienAnimStates.WildToPortal:
            let aiAlien = newAnimationInfo(alien.node,$CharAnim.WildToPortal)
            nextAnimation = composeCompositAnimation(@[aiAlien])

            let wtNode = newLocalizedNodeWithResource(GENERAL_PREFIX&"slot/aliens/wild_outro")
            let wildTextOutroAnim = addWildTextAnim(alien.node, wtNode, "play", isRed)
            wildTextOutroAnim.onComplete do():
                wtNode.removeFromParent()

            nextAnimation.addLoopProgressHandler 0.0, false, proc() =
                alien.sceneView.addAnimation(addShineAnim(alien.node))
                alien.sceneView.addAnimation(wildTextOutroAnim)

            nextAnimSound = "_WILDTOPORTAL"
        of AlienAnimStates.GoWild:
            discard

    proc startNextAnimation(alien:BaseAlien) =
        alien.node.alpha = 1.0
        alien.curAnimation = nextAnimation
        alien.curAnimationState = nextState
        if not onCompleteHandler.isNil:
            #echo "onCompleteHandler not Nil"
            alien.curAnimation.onComplete do():
                #echo "Call onCompleteHandler for " & alien.node.name
                onCompleteHandler()
        if not onAnimateHandler.isNil:
            alien.curAnimation.onAnimate = onAnimateHandler

        alien.sceneView.addAnimation(nextAnimation)

        if nextAnimSound.len != 0:
            sm.sendEvent(alien.index&nextAnimSound)

    let changeStateImmediate = isChangeAnimStateImmediate(alien.curAnimationState, nextState)

    if not nextAnimation.isNil:
        #nextAnimation.continueUntilEndOfLoopOnCancel = true
        if onCompleteAnimState != AlienAnimStates.None:
            nextAnimation.onComplete do():
                alien.setAnimState(onCompleteAnimState)
        if not alien.curAnimation.isNil and not alien.curAnimation.finished:
            if changeStateImmediate:
                #alien.curAnimation.continueUntilEndOfLoopOnCancel = false
                alien.curAnimation.removeHandlers()
            if alien.curAnimation.numberOfLoops < 0 or changeStateImmediate:
                alien.curAnimation.cancel()
            alien.curAnimation.onComplete do():
                startNextAnimation(alien)
        else:
            startNextAnimation(alien)


proc setNextPosIndex*(wildAlien:WildSymbolAlien) =
    const NUMBER_OF_REELS = 5
    const ELEMENTS_COUNT = 15
    # checks current position row and bounds,
    # if on next position we out of bounds or row is changed - no next position for wild.
    var nextPos = wildAlien.curPlaceIndex + wildAlien.moveDirection.int
    let currentPosRow = wildAlien.curPlaceIndex div NUMBER_OF_REELS
    let nextPosRow = nextPos div NUMBER_OF_REELS

    echo "\n\n"
    echo "setNextPosIndex for alien " , wildAlien.index," cur pos " , wildAlien.curPlaceIndex
    echo "target nextPos ", nextPos
    echo "currentPosRow ", currentPosRow
    echo "nextPosRow ", nextPosRow

    if nextPos < 0 or nextPos >= ELEMENTS_COUNT or nextPosRow != currentPosRow:
        nextPos = -1
        echo "[FIXED]nextPos ", nextPos

    wildAlien.nextPlaceIndex = nextPos


proc addWildOnField*(alien:MainAlien, phIndex:int, callback:proc() = nil) =
    let freeAlienWildSymbol = alien.wildsPool.pop()
    let v = alien.sceneView
    let target_ph = v.placeholders[phIndex]
    freeAlienWildSymbol.node.worldPos = v.placeholdersPositions[phIndex]
    freeAlienWildSymbol.curPlaceIndex = phIndex
    freeAlienWildSymbol.suspended = false
    freeAlienWildSymbol.setNextPosIndex()
    freeAlienWildSymbol.setAnimState(AlienAnimStates.WildAppear, callback)
    alien.activeWilds.add(freeAlienWildSymbol)
    echo "Move $# at placeholder's position $#".format(freeAlienWildSymbol.node.name, target_ph.name)

proc createNodeWithArrow*(wsa: WildSymbolAlien): Node =
    let resSuffix = if wsa.index == "A1": "alien_arrow2" else: "alien_arrow"
    let offsetX = if wsa.index == "A1": 20 else: -20
    result = newLocalizedNodeWithResource(GENERAL_PREFIX&"slot/aliens/"&resSuffix)
    result.scale = newVector3(0.8, 0.8)
    let xPos = 350 + offsetX
    result.anchor = newVector3(xPos.Coord, 420)

proc extendsWildsPool*(alien:MainAlien) =
    for i in 0 .. WILDS_POOL_SIZE:
        let wsa = WildSymbolAlien.new()
        wsa.curPlaceIndex = -1
        wsa.nextPlaceIndex = -1
        wsa.moveDirection = alien.moveDirection
        wsa.index = alien.index
        wsa.sceneView = alien.sceneView
        wsa.node = newLocalizedNodeWithResource(alien.resourcePath)
        wsa.node.name = alien.index & "_wild" & $i
        if wsa.index == "A1":
            wsa.node.anchor = newVector3(350.0, 450.0, 0.0) #alien.node.anchor
            wsa.wildSymbolId = Wild_Red
        else:
            wsa.wildSymbolId = Wild_Green
            wsa.node.anchor = alien.node.anchor
        wsa.node.alpha = 0.0
        wsa.isMoving = false
        alien.wildsParent.addChild(wsa.node)
        alien.wildsPool.add(wsa)
