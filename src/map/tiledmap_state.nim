import nimx / [ matrixes, animation, notification_center ]
import rod / [ node, component, viewport, rod_types ]
import rod / component / [ ae_composition ]
import tilemap / [ tile_map, tile_map_pcg ]
import shared / [ game_scene, director ]
import utils / [ sound_manager ]
import quest / [ quests, quest_helpers, quests_actions ]
import boolseq, tables, strutils, random, sequtils, json

type TiledMapState* = ref object
    scene*: GameScene
    tiledMap*: TileMap
    showedLayerCompositions: seq[BaseTileMapLayer]

proc createTiledMapState*(v: GameScene, tm: TileMap): TiledMapState=
    result.new()
    result.scene = v
    result.tiledMap = tm
    result.showedLayerCompositions = @[]

proc execAnimations(n: Node, scene: GameScene, animated: bool, d: float = -1.0, cb: proc() = nil) =
    var inAnimation = if animated: n.component(AEComposition).compositionNamed("in") else: nil
    let idleAnimation = n.component(AEComposition).compositionNamed("idle")
    var delay = d

    proc playIdle() =
        if not cb.isNil:
            cb()
        if not idleAnimation.isNil:
            idleAnimation.numberOfLoops = -1
            scene.addAnimation(idleAnimation)

    if delay < 0:
        delay = 0.0
        if not inAnimation.isNil:
            delay = rand(inAnimation.loopDuration)
        elif not idleAnimation.isNil:
            delay = rand(idleAnimation.loopDuration)

    if inAnimation.isNil and animated:
        n.alpha = 0.0
        inAnimation = newAnimation()
        inAnimation.loopDuration = 0.5
        inAnimation.numberOfLoops = 1
        inAnimation.onAnimate = proc(p: float) =
            n.alpha = interpolate(0.0, 1.0, p)

    if delay > 0.0:
        let delayAnimation = newAnimation()
        delayAnimation.numberOfLoops = 1
        delayAnimation.loopDuration = delay
        if not inAnimation.isNil:
            inAnimation = newCompositAnimation(false, delayAnimation, inAnimation)
            inAnimation.numberOfLoops = 1
        else:
            inAnimation = delayAnimation

    if not inAnimation.isNil:
        inAnimation.onComplete do():
            if not inAnimation.isCancelled:
                playIdle()
        scene.addAnimation(inAnimation)
    else:
        playIdle()

proc showLayerComposition*(s: TiledMapState, layer: BaseTileMapLayer = nil, name: string, animated: bool = false, cb: proc() = nil) =
    let anim = layerByName[BaseTileMapLayer](s.tiledMap, layer.name & "_Animation_" & name)
    let hasProp = name in layer.properties

    if anim.isNil and hasProp:
        let composition = layer.properties[name].str

        if name == "InAnimation" and composition == "starfall":
            let n = layer.node

            let stalpha =  n.alpha
            let stpos = n.position
            let endalpha = 0.0
            let endpos = stpos + newVector3(0.0, -1500.0)

            n.position = endpos
            n.alpha = endalpha

            let anim = newAnimation()
            anim.loopDuration = 0.35
            anim.numberOfLoops = 1
            anim.onAnimate = proc(p: float)=
                n.position = interpolate(endpos, stpos, p)
                n.alpha = interpolate(endalpha, stalpha, p)
            anim.onComplete do():
                if not cb.isNil and not anim.isCancelled:
                    cb()

            s.scene.setTimeOut(0.5) do():
                s.scene.addAnimation(anim)

            return

        let parent = newNode(layer.name & "_Animation_" & name)
        let index = s.tiledMap.layerIndex(layer)
        s.tiledMap.insertLayer(parent, index + (if name == "InAnimation": 2 else: 1))

        var compLayer = layerByName[BaseTileMapLayer](s.tiledMap, parent.name)
        s.showedLayerCompositions.add(compLayer)

        var scale = newVector3(1.0, 1.0, 1.0)
        if (name & "Scale") in layer.properties:
            let scaleVal = layer.properties[name & "Scale"].str.split(",")
            scale = newVector3(scaleVal[0].parseFloat(), scaleVal[1].parseFloat(), scaleVal[2].parseFloat())

        var offset = newVector3(0.0, 0.0, 0.0)
        if name & "Offset" in layer.properties:
            let offsetParts = layer.properties[name & "Offset"].str.split(",")
            offset = newVector3(offsetParts[0].parseFloat(), offsetParts[1].parseFloat(), offsetParts[2].parseFloat()) * s.tiledMap.tileSize

        var positions = layer.properties[name & "XY"].str.split(";")
        var completed: int
        for index, pos in positions:
            let n = newNodeWithResource("tiledmap/anim/precomps/" & composition & ".json")

            let posXY = pos.split(",")
            n.position = s.tiledMap.positionAtTileXY(posXY[0].parseInt(), posXY[1].parseInt()) + newVector3(0.0, s.tiledMap.tileSize.y / 2, 0.0) + offset
            n.scale = scale

            let anchorNode = n.findNode("anchor_node")
            if not anchorNode.isNil:
                n.anchor = anchorNode.anchor
            else:
                for child in n.children:
                    child.position = newVector3(0.0, 0.0, 0.0)

            parent.addChild(n)

            execAnimations(n, s.scene, animated, if name == "InAnimation" or index == 0: 0.0 else: -1.0) do():
                completed.inc
                if not cb.isNil and completed == positions.len:
                    cb()
    else:
        if not cb.isNil:
            cb()


proc hideLayerComposition*(s: TiledMapState, layer: BaseTileMapLayer = nil, animated: bool = false, name: string, cb: proc() = nil) =
    layer.enabled = false

    let animationLayer = layerByName[BaseTileMapLayer](s.tiledMap, layer.name & "_Animation_" & name)

    if not animationLayer.isNil:
        if animated:
            var outAnimations = map(animationLayer.node.children, proc(n: Node): Animation =
                result = n.component(AEComposition).compositionNamed("out")
                if result.isNil:
                    let alpha = n.alpha
                    result = newAnimation()
                    result.loopDuration = 0.5
                    result.numberOfLoops = 1
                    result.onAnimate = proc(p: float)=
                        n.alpha = interpolate(alpha, 0.0, p)
            )

            if outAnimations.len > 0:
                var anim = newCompositAnimation(true, outAnimations)
                anim.numberOfLoops = 1
                anim.onComplete do():
                    s.tiledMap.removeLayer(layer.name & "_Animation_" & name)
                    if not cb.isNil and not anim.isCancelled:
                        cb()
                s.scene.addAnimation(anim)
                # playBuildEndSound()
            else:
                s.tiledMap.removeLayer(layer.name & "_Animation_" & name)
                # playBuildEndSound()
                if not cb.isNil:
                    cb()
        else:
            s.tiledMap.removeLayer(layer.name & "_Animation_" & name)
            # playBuildEndSound()
            if not cb.isNil:
                cb()
    else:
        # playBuildEndSound()
        if not cb.isNil:
            cb()

    var idx = s.showedLayerCompositions.find(animationLayer)
    if idx >= 0:
        s.showedLayerCompositions.del(idx)

proc setPrepareMapState*(s: TiledMapState, quest: QuestConfig, animated: bool = true) =
    var itemsForHide = itemsForPropertyValue[BaseTileMapLayer, string](s.tiledMap, "QuestOut", quest.name)

    s.scene.soundManager.sendEvent(if rand(100) > 50: "BUILDING_START_1" else: "BUILDING_START_2")

    for item in itemsForPropertyValue[BaseTileMapLayer, string](s.tiledMap, "QuestIn", quest.name):
        if "PrepareAnimationHideLayers" in item.obj.properties:
            for layerName in item.obj.properties["PrepareAnimationHideLayers"].str.split(","):
                let layer = layerByName[BaseTileMapLayer](s.tiledMap, layerName)
                if not layer.isNil:
                    s.hideLayerComposition(layer, animated, name = "IdleAnimation")

        if "PrepareAnimationKeepLayers" in item.obj.properties:
            for layerName in item.obj.properties["PrepareAnimationKeepLayers"].str.split(","):
                itemsForHide.keepIf(proc(item: tuple[obj: BaseTileMapLayer, property: JsonNode]): bool = item.obj.node.name != layerName)

        s.showLayerComposition(item.obj, "PrepareAnimation", animated)

    for item in itemsForHide:
        s.hideLayerComposition(item.obj, animated, name = "IdleAnimation")

proc setIdleMapState*(s: TiledMapState, quest: QuestConfig, animated: bool = true) =
    proc applyIdleState(i: BaseTileMapLayer)=
        s.hideLayerComposition(i, animated = true, name = "PrepareAnimation")
        if "PrepareAnimationHideLayers" in i.properties:
            for layerName in i.properties["PrepareAnimationHideLayers"].str.split(","):
                let layer = layerByName[BaseTileMapLayer](s.tiledMap, layerName)
                if not layer.isNil:
                    if "IdleAnimation" in layer.properties and not layer.enabled:
                        layer.enabled = false
                        s.showLayerComposition(layer, "IdleAnimation", animated)
                    else:
                        layer.enabled = true

        if "PrepareAnimationKeepLayers" in i.properties:
            let layersNames = i.properties["PrepareAnimationKeepLayers"].str.split(",")
            for item in itemsForPropertyValue[BaseTileMapLayer, string](s.tiledMap, "QuestOut", quest.name):
                if item.obj.node.name in layersNames:
                    s.hideLayerComposition(item.obj, animated, name = "IdleAnimation")

        if "IdleAnimation" in i.properties:
            i.enabled = false
            var animated = true
            if "IdleAnimationAnimated" in i.properties:
                animated = i.properties["IdleAnimationAnimated"].getBool()
            s.showLayerComposition(i, "IdleAnimation", animated = animated)
        else:
            i.enabled = true

    for item in itemsForPropertyValue[BaseTileMapLayer, string](s.tiledMap,"QuestIn", quest.name):
        if "InAnimation" in item.obj.properties:
            s.showLayerComposition(item.obj, "InAnimation", animated) do():
                closureScope:
                    let lan = item.obj.name & "_Animation_InAnimation"
                    s.tiledMap.removeLayer(lan)

        if "IdleAnimationTimeout" in item.obj.properties:
            var idleAnimationTimeout = item.obj.properties["IdleAnimationTimeout"].getFloat()
            closureScope:
                let i = item
                s.scene.setTimeOut(idleAnimationTimeout) do():
                    applyIdleState(i.obj)
        else:
            applyIdleState(item.obj)

    if quest.targetName == "cityHall":
        s.scene.soundManager.sendEvent("BUILDINGMENU_UPGRADE_cityHall")
    elif quest.targetName == "restaurant" or quest.targetName == "restaurant2":
        s.scene.soundManager.sendEvent("BUILDINGMENU_UPGRADE_restaurant")
    elif  quest.targetName == "gasStation" or quest.targetName == "gasStation2":
        s.scene.soundManager.sendEvent("BUILDINGMENU_UPGRADE_gasStation")
    else:
        s.scene.soundManager.sendEvent(if rand(100) > 50: "BUILDING_END_1" else: "BUILDING_END_2")

    s.scene.notificationCenter.postNotification("QuestCompleteState_" & quest.name)

proc restoreMapState*(s: TiledMapState, mapState: BoolSeq) =
    let questConfigs = sharedQuestManager().questConfigs

    for scomp in s.showedLayerCompositions:
        if not scomp.isNil:
            s.tiledMap.removeLayer(scomp.name)

    s.showedLayerCompositions.setLen(0)

    for item in itemsForPropertyName[BaseTileMapLayer](s.tiledMap, "QuestIn"):
        item.obj.enabled = (item.property.str.toLowerAscii() == "zero")

    for i in 0..<mapState.len:
        if mapState[i]:
            for item in itemsForPropertyValue[BaseTileMapLayer, string](s.tiledMap, "QuestOut", questConfigs[i].name):
                item.obj.enabled = false

            for item in itemsForPropertyValue[BaseTileMapLayer, string](s.tiledMap, "QuestIn", questConfigs[i].name):
                item.obj.enabled = true

    for quest in sharedQuestManager().activeStories():
        case quest.status:
            of QuestProgress.InProgress, QuestProgress.GoalAchieved:
                s.setPrepareMapState(quest.config)
            of QuestProgress.Completed:
                for item in itemsForPropertyValue[BaseTileMapLayer, string](s.tiledMap,"QuestOut", quest.config.name):
                    item.obj.enabled = false

                for item in itemsForPropertyValue[BaseTileMapLayer, string](s.tiledMap, "QuestIn", quest.config.name):
                    item.obj.enabled = true

            else:
                discard

    for item in itemsForPropertyName[BaseTileMapLayer](s.tiledMap, "QuestIn"):
        if item.obj.enabled:
            if "IdleAnimation" in item.obj.properties:
                item.obj.enabled = false
                s.showLayerComposition(item.obj, "IdleAnimation", animated = false)
            else:
                item.obj.enabled = true

