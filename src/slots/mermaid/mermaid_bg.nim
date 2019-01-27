import random
import strutils
import tables

import nimx.matrixes
import nimx.animation
import nimx.timer
import nimx.button
import nimx.view

import rod.viewport
import rod.quaternion
import rod.rod_types
import rod.node
import rod.component
import rod.component.sprite
import rod.component.ui_component
import rod.component.ae_composition
import rod.component.mask
import rod.component.color_balance_hls

import anim_helpers
import sprite_digits_component
import mermaid_sound
import core.slot.base_slot_machine_view

const PARENT_PATH = "slots/mermaid_slot/"

const playfieldElements* = [
    ["Wild"    , "wild"     ], # 0
    ["King"    , "scatter"  ], # 1
    ["Prince"  , "bonus"    ], # 2
    ["Star"    , "starfish" ], # 3
    ["Fish"    , "fish"     ], # 4
    ["Turtle"  , "turtle"   ], # 5
    ["Dolphin" , "dolphin"  ], # 6
    ["Seahorse", "seahorse" ], # 7
    ["Ship"    , "ship"     ], # 8
    ["Necklace", "necklace" ], # 9
    ["Chest1"  , "chest1"   ], # 10
    ["Chest2"  , "chest2"   ], # 11
    ["Pearl"   , "shell"    ], # 12
    ["Wildx2"  , "wildx2"   ]  # 13
]

const chestBttnPosAndSize = [
    [ # chest 1
        [905.float32, 725], # pos XY
        [325.float32, 240], # size XY
        [-13.float32, 0] # rotationZ euler
    ],
    [ # chest 2
        [1355.float32, 650], # pos XY
        [345.float32, 230], # size XY
        [0.float32, 0] # rotationZ euler
    ],
    [ # chest 3
        [650.float32, 610], # pos XY
        [300.float32, 210], # size XY
        [0.float32, 0] # rotationZ euler
    ],
    [ # chest 4
        [420.float32, 480], # pos XY
        [260.float32, 200], # size XY
        [-8.float32, 0] # rotationZ euler
    ],
    [ # chest 5
        [1089.float32, 487], # pos XY
        [270.float32, 210], # size XY
        [-1.5.float32, 0] # rotationZ euler
    ],
    [ # chest 6
        [1455.float32, 472], # pos XY
        [270.float32, 190], # size XY
        [7.float32, 0] # rotationZ euler
    ],
    [ # chest 7
        [895.float32, 350], # pos XY
        [270.float32, 190], # size XY
        [10.float32, 0] # rotationZ euler
    ],
    [ # chest 8
        [380.float32, 345], # pos XY
        [270.float32, 200], # size XY
        [-30.float32, 0] # rotationZ euler
    ],
    [ # chest 9
        [1040.float32, 160], # pos XY
        [260.float32, 180], # size XY
        [28.float32, 0] # rotationZ euler
    ],
    [ # fullscreen bttn
        [-980.float32, -588], # pos XY
        [3920.float32, 2352], # size XY
        [0.float32, 0] # rotationZ euler
    ]
]

type MermaidBG* = ref object
    rootNode*: Node
    idleAnimation*: seq[Animation]
    randomAnimation*: seq[Animation]
    completion: Completion
    chestsAnims*: Table[string, Animation]

proc hideChests*(mbg: MermaidBG, duration: float32 = 0.25) =
    for ch in mbg.rootNode.children:
        if ch.name.contains("Chest"):
            ch.hide(duration)

    mbg.rootNode.sceneView.wait(duration) do():
        if not mbg.completion.isNil:
            mbg.completion.finalize()

const POSSIBLE_BONUS_WIN_OBJECT_COUNT = 3

proc addButton(n: Node, i: int, touchAvailable: proc(): bool, callback: proc()): proc() =
    var job = callback
    var buttonParent = n.newChild(n.name & "_button")
    buttonParent.position = newVector3(chestBttnPosAndSize[i][0][0], chestBttnPosAndSize[i][0][1], 0)
    buttonParent.rotation = newQuaternionFromEulerYXZ(0, 0, chestBttnPosAndSize[i][2][0])
    let button = newButton(newRect(0, 0, chestBttnPosAndSize[i][1][0], chestBttnPosAndSize[i][1][1]))
    buttonParent.component(UIComponent).view = button
    button.hasBezel = false

    proc remove() =
        buttonParent.removeFromParent()
        buttonParent = nil

    button.onAction do():
        # avoid clickers
        if touchAvailable() and not job.isNil:
            job()
            job = nil

    result = remove

proc getGoldSeq(winSrc: seq[int64]): seq[string] =
    result = newSeq[string](winSrc.len)
    for i in 0..<winSrc.len: result[i] = "1"
    var markers = newSeq[bool](winSrc.len)
    for str in ["3", "2", "1"]:
        var currMax = 0.int64
        for i in 0..<winSrc.len:
            if not markers[i] and winSrc[i] >= currMax :
                currMax = winSrc[i]
        for i in 0..<winSrc.len:
            if not markers[i] and (winSrc[i] - currMax) == 0:
                result[i] = str
                markers[i] = true

proc resetAnim(v: SceneView, a: Animation) =
    a.cancel()
    v.wait(0.05) do():
        a.onProgress(0.0)

proc showChests*(mbg: MermaidBG, winSrc: seq[int64], duration: float32 = 0.25, onClick: proc(payout: int64), callback: proc()) =
    # mbg.completion = newCompletion()

    let v = mbg.rootNode.sceneView

    # touch blocker for clickers
    var touchAvailable = true
    var touchChecker = proc(): bool = return touchAvailable

    # counters
    var goldIndexCounter = 1
    var openedChests = 0

    # chests root Node
    let coinsAndChestsNode = mbg.rootNode.findNode("coins_from_chests")

    # over all node for win chest numbers
    let overtopNode = mbg.rootNode.newChild("over_top")

    # completion for win numbers animations
    let winNumCompletionOut = newCompletion()
    let chestButtonsCompletion = newCompletion()

    # cache and cleanup seq's
    var buttonsDestroyers = newSeq[proc()]()
    var goldSeq = getGoldSeq(winSrc)
    var goldInShell = newSeq[Node]()
    var chestsNodes = initTable[string, Node]()
    for i in 1..3: goldInShell.add(coinsAndChestsNode.findNode("gold_" & $i & "_idle"))

    # mermaid in idle win out anims and nodes
    let mermaidNode = mbg.rootNode.findNode("mermaid_bonus")
    let mermaidInAnim = mermaidNode.animationNamed("in")
    let mermaidIdleAnim = mermaidNode.animationNamed("idle")
    let mermaidWinAnim = mermaidNode.animationNamed("win")
    let mermaidOutAnim = mermaidNode.animationNamed("out")

    mermaidInAnim.cancelBehavior =  cbJumpToStart
    mermaidIdleAnim.cancelBehavior =  cbJumpToStart
    mermaidWinAnim.cancelBehavior =  cbJumpToStart
    mermaidOutAnim.cancelBehavior =  cbJumpToStart

    mermaidNode.show(0)

    # clenup mermaid anims
    mbg.completion.to do():
        mermaidNode.hide(0)
        mermaidInAnim.cancel()
        mermaidIdleAnim.cancel()
        mermaidWinAnim.cancel()
        mermaidOutAnim.cancel()

    proc playMermaidIn() =
        touchAvailable = false
        v.addAnimation(mermaidInAnim)
        mermaidInAnim.onComplete do():
            v.addAnimation(mermaidIdleAnim)
        mermaidInAnim.addLoopProgressHandler 0.3, false, proc() =
            touchAvailable = true

    proc playMermaidWin() =
        mermaidIdleAnim.cancel()
        v.addAnimation(mermaidWinAnim)
        mermaidWinAnim.onComplete do():
            v.addAnimation(mermaidIdleAnim)

    proc playMermaidOut() =
        mermaidIdleAnim.cancel()
        v.addAnimation(mermaidOutAnim)
        touchAvailable = false
        mermaidOutAnim.onComplete(callback)
        mermaidOutAnim.addLoopProgressHandler 0.5, false, proc() =
            touchAvailable = true

    proc playNumber(chestNode: Node, strValue: string, chestOpenAnim: Animation = nil, bSilver: bool = false) =
        # play numbers over chest
        let numbersAnchorNode = newNodeWithResource(PARENT_PATH & "comps/number_animation.json")

        if bSilver:
            let hlsComp = numbersAnchorNode.addComponent(ColorBalanceHLS)
            hlsComp.hue = 0.417
            hlsComp.saturation = -0.65
            hlsComp.lightness = 0

        let attachAnchorNode = numbersAnchorNode.findNode("anchor")
        chestNode.findNode("number").addChild(numbersAnchorNode)

        # reparent to top layer cause of shiness
        numbersAnchorNode.reparentTo(overtopNode)
        winNumCompletionOut.to do():
            let outAnim = numbersAnchorNode.animationNamed("out")
            outAnim.onComplete do():
                numbersAnchorNode.removeFromParent()
                overtopNode.removeFromParent()
            v.addAnimation(outAnim)

        if not chestOpenAnim.isNil:
            chestOpenAnim.addLoopProgressHandler 0.15, false, proc() =
                v.addAnimation(numbersAnchorNode.animationNamed("in"))
        else:
            v.addAnimation(numbersAnchorNode.animationNamed("in"))

        let numNode = newNodeWithResource(PARENT_PATH & "comps/sprite_digits.json")
        attachAnchorNode.addChild(numNode)
        numNode.componentIfAvailable(SpriteDigits).value = strValue


    proc doOut() =
        var winCounter = POSSIBLE_BONUS_WIN_OBJECT_COUNT
        for name, nd in chestsNodes:
            playNumber(nd, $winSrc[winCounter], nil, bSilver = true)
            inc winCounter

        let scViewRootNode = mbg.rootNode.sceneView.rootNode
        # let onBttnDestroy = scViewRootNode.addButton(chestBttnPosAndSize.len-1, touchChecker) do():
        let onBttnDestroy = proc() =
            # do magic with gold reparent, cause of bad ae animation
            let goldOutNode = newNodeWithResource(PARENT_PATH & "comps/gold_out.json")
            coinsAndChestsNode.addChild(goldOutNode)
            let idleGoldNode = goldInShell[POSSIBLE_BONUS_WIN_OBJECT_COUNT-1]
            let idleGoldPos = idleGoldNode.position
            let idleGoldParentNode = idleGoldNode.parent
            idleGoldNode.reparentTo( goldOutNode.findNode("gold_out_anchor") )

            # play and sync gold in shell with mermaid
            let goldOutAnim = goldOutNode.playComposition do():
                goldOutNode.removeFromParent()
                idleGoldNode.reparentTo(idleGoldParentNode)
                idleGoldNode.position = idleGoldPos
                idleGoldNode.hide(0)

            goldOutAnim.cancelBehavior = cbJumpToStart

            # do mermaid out
            goldOutAnim.addLoopProgressHandler 0.0028, false, proc() =
                playMermaidOut()

            mbg.completion.to do():
                goldOutAnim.cancel()

            winNumCompletionOut.finalize()

        # mbg.completion.to do():
        #     onBttnDestroy()

        v.wait(1.0) do():
            onBttnDestroy()

    # start bonus preparation and interaction

    playMermaidIn()

    # iterate throught all chests and setup visibility to random chest
    for index in 0..<chestBttnPosAndSize.len-1:
        closureScope:
            let i = index

            # show curent chest cluster (3 chest per cluster)
            let chestNode = mbg.rootNode.findNode("Chest" & $(i+1))
            chestNode.show(duration)

            # chestNode.show(0)

            mbg.completion.to do():
                chestNode.hide(0)
            chestsNodes[chestNode.name] = chestNode

            # get randomly selected chest for cluster
            let availableChestNode = rand(chestNode.getChildrenWithSubname("Chest"))

            # show curr selected chest
            availableChestNode.show(duration)
            mbg.completion.to do():
                availableChestNode.hide(0)

            # prepare gold in chest node parent
            var goldParentNode = availableChestNode.getFirstChildrenWithSubname("Gold")

            # prepare button over chest
            let onBttnDestroy = chestNode.addButton(i, touchChecker) do():

                # SOUNDS
                v.BaseMachineView.playBonusOpenGoldChest()

                # remove nodes from chached chests nodes tbl after click on it
                chestsNodes.del(chestNode.name)

                # prepare current gold in chest according to server response
                var availableGoldNode = goldParentNode.findNode(goldSeq[goldIndexCounter-1])
                availableGoldNode.show(0)
                mbg.completion.to do():
                    availableGoldNode.hide(0)

                # do open chest
                let chestOpenAnim = mbg.chestsAnims[availableChestNode.name]
                chestOpenAnim.cancelBehavior = cbJumpToStart
                v.addAnimation(chestOpenAnim)
                # touchAvailable = false
                mbg.completion.to do():
                    v.resetAnim(chestOpenAnim)

                # play win number over chest
                playNumber(chestNode, $winSrc[goldIndexCounter-1], chestOpenAnim)

                onClick(winSrc[goldIndexCounter-1])

                if goldIndexCounter <= POSSIBLE_BONUS_WIN_OBJECT_COUNT:

                    playMermaidWin()

                    # do fly coins from chest to mermaid shell
                    let flyCoinsNode = coinsAndChestsNode.findNode("controller_" & $(i+1))
                    flyCoinsNode.show(0)
                    let flyCoinsAnim = mbg.chestsAnims[flyCoinsNode.name]

                    chestOpenAnim.addLoopProgressHandler 0.15, false, proc() =
                        v.addAnimation(flyCoinsAnim)
                    flyCoinsAnim.onComplete do():
                        flyCoinsNode.hide(0)

                    mbg.completion.to do():
                        flyCoinsAnim.cancel()

                    # do anim with gold in mermaid shell
                    let goldNode = newNodeWithResource(PARENT_PATH & "comps/gold_" & $goldIndexCounter & ".json")
                    coinsAndChestsNode.addChild(goldNode)
                    let goldAnim = goldNode.playComposition do():
                        # hide previous idle pack of gold in mermaid shell
                        for gld in goldInShell: gld.hide(0)

                        # show curent idle gold pack in mermaid shell
                        goldInShell[openedChests].show(0)
                        goldNode.removeFromParent()

                        # check for last available to open chest
                        if openedChests == POSSIBLE_BONUS_WIN_OBJECT_COUNT-1:
                            doOut()

                        inc openedChests

                    goldAnim.cancelBehavior = cbJumpToStart

                    mbg.completion.to do():
                        goldAnim.cancel()

                    if goldIndexCounter == POSSIBLE_BONUS_WIN_OBJECT_COUNT:
                        # remove bttn's over chest to avoid clicks after 3 times
                        chestButtonsCompletion.finalize()

                else:
                    touchAvailable = false

                inc goldIndexCounter

            chestButtonsCompletion.to do():
                onBttnDestroy()

proc createBG*(): MermaidBG =
    result.new()
    result.idleAnimation = @[]
    result.randomAnimation = @[]
    result.rootNode = newNodeWithResource(PARENT_PATH & "comps/bg.json")

    result.idleAnimation.add( result.rootNode.findNode("surface").animationNamed("play")        )
    result.idleAnimation.add( result.rootNode.findNode("surface").animationNamed("play")        )
    result.idleAnimation.add( result.rootNode.findNode("caustic_far").animationNamed("play")    )
    result.idleAnimation.add( result.rootNode.findNode("bottom").animationNamed("play")         )
    result.idleAnimation.add( result.rootNode.findNode("caustic_near").animationNamed("play")   )
    result.idleAnimation.add( result.rootNode.findNode("crab").animationNamed("play")           )
    result.idleAnimation.add( result.rootNode.findNode("smallshine").animationNamed("play")     )
    result.idleAnimation.add( result.rootNode.findNode("middleshine").animationNamed("play")    )
    result.idleAnimation.add( result.rootNode.findNode("foreground").animationNamed("play")     )
    result.idleAnimation.add( result.rootNode.findNode("watergrass").animationNamed("play")     )

    result.randomAnimation.add( result.rootNode.findNode("backfish_3").animationNamed("play")   )
    result.randomAnimation.add( result.rootNode.findNode("backfish_2").animationNamed("play")   )
    result.randomAnimation.add( result.rootNode.findNode("backfish_1").animationNamed("play")   )

    result.randomAnimation.add( result.rootNode.findNode("nearfish_far").animationNamed("play") )
    result.randomAnimation.add( result.rootNode.findNode("nearfish_middle").animationNamed("play"))
    result.randomAnimation.add( result.rootNode.findNode("nearfish_near").animationNamed("play"))
    result.randomAnimation.add( result.rootNode.findNode("nearfish_blur").animationNamed("play"))

    result.randomAnimation.add( result.rootNode.findNode("shark").animationNamed("play")        )


    let sharkMask = result.rootNode.findNode("ltp_shark.png").component(Mask)
    sharkMask.maskNode = result.rootNode.findNode("ltp_ship_over.png")
    sharkMask.maskType = tmAlphaInverted

    let mermaidNode = result.rootNode.findNode("mermaid_bonus")
    mermaidNode.hide(0)

    let coinsAndChestsNode = result.rootNode.findNode("coins_from_chests")

    let rootNd = result.rootNode
    var chestsAnims = initTable[string, Animation]()
    for i in 0..<chestBttnPosAndSize.len-1:
        closureScope:
            let index = i
            let chestNode = rootNd.findNode("Chest" & $(index+1))
            let availableChests = chestNode.getChildrenWithSubname("Chest")
            for ch in availableChests:

                let aeComp = ch.component(AEComposition)
                let anim = aeComp.compositionNamed("aeAllCompositionAnimation")
                anim.cancelBehavior = cbJumpToStart
                chestsAnims[ch.name] = anim

            let flyCoinsNode = newNodeWithResource(PARENT_PATH & "comps/controller_" & $(index+1) & ".json")
            coinsAndChestsNode.addChild(flyCoinsNode)
            flyCoinsNode.hide(0)

            let aeComp = flyCoinsNode.component(AEComposition)
            let anim = aeComp.compositionNamed("aeAllCompositionAnimation")
            anim.cancelBehavior = cbJumpToStart
            chestsAnims[flyCoinsNode.name] = anim

    result.chestsAnims = chestsAnims

    result.completion = newCompletion()


template startIdleAnims*(mbg: MermaidBG) =
    let v = mbg.rootNode.sceneView
    for a in mbg.idleAnimation:
        closureScope:
            v.addAnimation(a)

template startRandomAnims*(mbg: MermaidBG) =
    let v = mbg.rootNode.sceneView

    proc addRandAnim(fromVal: int, toRand: int) =
        let waitRandom = rand(0 .. toRand).float32
        v.wait(waitRandom) do():
            if not v.isNil and not mbg.isNil and mbg.randomAnimation.len != 0 and not mbg.randomAnimation[fromVal].isNil:
                mbg.randomAnimation[fromVal].numberOfLoops = 1
                v.addAnimation(mbg.randomAnimation[fromVal])
                mbg.randomAnimation[fromVal].onComplete do():
                    let waitRandom = rand(0 .. toRand).float32
                    v.wait(waitRandom) do():
                        addRandAnim(fromVal, toRand)
                    mbg.randomAnimation[fromVal].removeHandlers()

    addRandAnim(0, 10)
    addRandAnim(1, 10)
    addRandAnim(2, 10)

    addRandAnim(3, 30)
    addRandAnim(4, 30)
    addRandAnim(5, 30)
    addRandAnim(6, 30)

    addRandAnim(7, 50)


proc nameSimplify*(n: Node, nodeModifier: proc(n: Node) = nil) =
    if n.name.contains("idle"):
        n.name = "idle"
        if not nodeModifier.isNil:
            n.nodeModifier()
    elif n.name.contains("win"):
        n.name = "win"
        if not nodeModifier.isNil:
            n.nodeModifier()
    else:
        for ch in n.children:
            ch.nameSimplify(nodeModifier)

proc createEmptyNodeCell(name: string): Node =
    result = newNode(name)
    let cellWinNode = result.newChild("win")
    let cellIdleNode = result.newChild("idle")
    cellWinNode.registerAnimation("play", newAnimation())
    cellIdleNode.registerAnimation("play", newAnimation())

proc createElementsGrid*(mbg: MermaidBG): seq[seq[Node]] =
    let cellsAnchor = newNode("cells")
    let chlen = mbg.rootNode.children.len
    mbg.rootNode.insertChild(cellsAnchor, chlen-3)

    let startVector = newVector3(166,0,0)
    let stepX = 254.0
    let stepY = 250.0
    var nameCounter = 0

    result = newSeq[seq[Node]]()
    for i in 0..4:
        result.add(newSeq[Node](7))

    var pos = newVector3()
    for row in 0..6:
        pos[1] = startVector[1] + stepY * row.float32 - 2 * stepY
        for col in 0..4:
            pos[0] = startVector[0] + stepX * col.float32

            let elementsNode = newNodeWithResource(PARENT_PATH & "comps/elements.json")
            elementsNode.nameSimplify do(n: Node): n.hide(0)

            # TODO insert mermaid here
            elementsNode.findNode("wild").removeFromParent()
            elementsNode.findNode("wildx2").removeFromParent()
            elementsNode.insertChild(createEmptyNodeCell("wild"), 0)
            elementsNode.insertChild(createEmptyNodeCell("wildx2"), elementsNode.children.len-1)

            var indCounter = 0
            var sortedNode = newNode($nameCounter)
            sortedNode.positionY = pos[1]
            while indCounter < playfieldElements.len:
                let ch = elementsNode.findNode(playfieldElements[indCounter][1])
                let idleAnim = ch.findNode("idle").animationNamed("play")
                idleAnim.numberOfLoops = -1
                sortedNode.addChild(ch)
                inc indCounter

            var reelNode = cellsAnchor.findNode("reel_" & $col)
            if reelNode.isNil:
                reelNode = newNodeWithResource(PARENT_PATH & "comps/bounce.json")
                reelNode.name = "reel_" & $col
                reelNode.positionX = pos[0]
                cellsAnchor.addChild(reelNode)

            reelNode.findNode("anchor").addChild(sortedNode)

            result[col][row] = sortedNode
            inc nameCounter
