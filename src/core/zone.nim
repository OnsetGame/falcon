import tables, json, strutils, sequtils
import shafa / game / feature_types
export feature_types
import shared / [user, game_scene, localization_manager]
import quest / quests

import falconserver / common / game_balance
import core / notification_center
import core / flow / flow_manager

type FeatureAction = tuple[scene: GameScene, cb: proc()]
type Feature* = ref object of RootObj
  unlockLevel*: int
  kind*: FeatureType
  unlockQuestConf*: QuestConfig
  actions: seq[FeatureAction]
  hasBonus*: bool

type Zone* = ref object of RootObj
    name*: string
    feature*: Feature
    questConfigs*: seq[QuestConfig]
    flowManager*: FlowManager

method onInit*(feature: Feature, zone: Zone) {.base.} = discard
method updateState*(feature: Feature, updates: JsonNode) {.base.} = discard

proc localizedName*(feature: Feature): string = localizedString("FEATURE_" & $feature.kind & "_NAME")

var gZones = newSeq[Zone]()
var gFeaturesFabric = initTable[FeatureType, proc(): Feature]()

proc findZone*(name: string): Zone =
    for z in gZones:
        if z.name == name:
            return z

proc addFeature*(kind: FeatureType, constructor: proc(): Feature) =
    gFeaturesFabric[kind] = constructor

proc getZones*(): seq[Zone]
proc isActive*(z: Zone): bool

proc initZones*() =
    gZones.setLen(0)

    let configs = sharedQuestManager().questConfigs
    let gb = sharedGameBalance()
    for conf in configs:
        if conf.enabled:
            var confName = conf.targetName
            var zone = findZone(confName)
            if zone.isNil:
                zone = new(Zone)
                zone.questConfigs = newSeq[QuestConfig]()
                zone.questConfigs.add(conf)
                zone.name = confName
                zone.flowManager = newFlowManager(confName)
                let kind = gb.zoneFeatures.getOrDefault(zone.name)
                if gFeaturesFabric.hasKey(kind):
                    zone.feature = gFeaturesFabric[kind]()
                else:
                    zone.feature = new(Feature)
                zone.feature.kind = kind

                gZones.add(zone)
                #echo ">> add zone ", zone.name, "  feature ", zone.feature.kind
            else:
                zone.questConfigs.add(conf)
            
            # copy separeted city hall's zone to cityHall
            if confName == "mainRoad_alley":
                findZone("cityHall").questConfigs.add(conf)

            if zone.feature.kind == conf.unlockFeature:
                if zone.feature.unlockQuestConf.isNil:
                    zone.feature.unlockQuestConf = conf

    for zone in gZones:
        zone.feature.onInit(zone)

    if gZones.len > 0:
        sharedNotificationCenter().addObserver("DIRECTOR_ON_SCENE_REMOVE", gZones[0]) do(args: Variant):
            let curScene = args.get(GameScene)
            for zone in gZones:
                if not zone.feature.isNil and zone.feature.actions.len != 0:
                    zone.feature.actions.keepItIf(it.scene != curScene)
                zone.flowManager.removeAllFlowStates()

proc getZones*(): seq[Zone] =
    if gZones.len() < 1:
        initZones()

    return gZones

proc getQuestZones*(): seq[Zone] =
    getZones().filter(proc(zone: Zone): bool = zone.name != "mainRoad_alley")

proc updateFeaturesState*(jn: JsonNode) =
    for zone in getZones():
        zone.feature.updateState(jn)

proc updateFeatureForMultipleZones*(jn: JsonNode) =
    for zone in getZones():
        if zone.name in jn:
            echo "update zone feature ", zone.name, " with ", jn[zone.name]
            zone.feature.updateState(jn[zone.name])

proc isFeatureUnlockAvailable*(f: Feature): bool =
    for q in sharedQuestManager().activeStories:
        if not f.unlockQuestConf.isNil:
            if f.unlockQuestConf.id == q.config.id:
                return true

proc findFeature*(T: typedesc): T =
    for z in gZones:
        type TT = T
        if z.feature of TT:
            return z.feature.TT

proc getUnlockLevel*(z: Zone): int =
    if z.feature.unlockQuestConf.isNil or not z.feature.unlockQuestConf.enabled:
        return -1
    return sharedQuestManager().questUnlockLevel(z.feature.unlockQuestConf)

proc isActive*(z: Zone): bool =
    return sharedQuestManager().isQuestCompleted(z.feature.unlockQuestConf)

proc isSlot*(z: Zone): bool =
    result = z.feature.kind == FeatureType.Slot

proc isResource*(z: Zone): bool =
    result = z.feature.kind == FeatureType.IncomeChips or z.feature.kind == FeatureType.IncomeBucks

proc getUnlockPrice*(z: Zone): int =
    if z.feature.unlockQuestConf.isNil:
        return 0
    return z.feature.unlockQuestConf.price

proc isFeatureEnabled*(f: FeatureType): bool =
    for zone in getZones():
        if zone.feature.kind == f:
            if zone.isActive(): return true

proc dispatchActions*(feature: Feature) =
    for action in feature.actions:
        action.cb()

proc subscribe*(feature: Feature, scene: GameScene, cb: proc()) =
    feature.actions.add((scene, cb))

proc unsubscribe*(feature: Feature, scene: GameScene, cb: proc) =
    for i, action in feature.actions:
        if action.scene == scene and action.cb == cb:
            feature.actions.delete(i)

proc zoneCompletedQuests*(zone: Zone): int =
    for qc in zone.questConfigs:
        if sharedQuestManager().isQuestCompleted(qc):
            result.inc()

proc activeQuest*(zone: Zone): Quest =
    for qc in zone.questConfigs:
        result = sharedQuestManager().questById(qc.id)
        if not result.isNil:
            return

proc localizedName*(zone: Zone): string = localizedString(zone.name & "_ZONE_NAME")

proc lockedByZone*(z: Zone): Zone=
    let cq = z.zoneCompletedQuests
    if cq >= z.questConfigs.len: return

    let qc = z.questConfigs[cq]
    let lqc = qc.uncompletedDeps()
    if lqc.len > 0 and qc.name != lqc[^1].name:
        result = findZone(lqc[^1].targetName)
