import falconserver.map.building.builditem
import falconserver.quest.quest_types
import shared / [ localization_manager, user ]
import strutils, json
import utils.helpers

import nimx / [ types, matrixes ]
import rod / node
import rod / component
import rod / component / [ solid, text_component ]
import utils / icon_component

type QuestDesc* = tuple[strPart: string, isKey: bool]

const questsIcons* = ["candySlot", "dreamTowerSlot", "balloonSlot", "gasStation_build", "candySlot_build", "balloonSlot_build",
                      "dreamTowerSlot_build", "cityHall_build", "restaurant_build", "storeBuildings", "bank_build", "store_build"]

proc getDescriptionByMainPart(desc: openarray[QuestDesc], main: string): string =
    var args: seq[string] = @[]

    for i in 1..desc.len - 1:
        let d = desc[i]
        if d.isKey:
            args.add("<span style=\"color:FFDF90FF\">" & localizedString(d.strPart) & "</span>")
        else:
            args.add("<span style=\"color:FFDF90FF\">" & d.strPart & "</span>")

    try:
        result = main % args
    except:
        result = main

proc getDescriptionWithoutTarget*(desc: openarray[QuestDesc]): string =
    var s = desc[0].strPart
    s.removeSuffix("_TARGETED")
    result = getDescriptionByMainPart(desc, localizedString(s))

proc getFullDescription*(desc: openarray[QuestDesc]): string =
    result = getDescriptionByMainPart(desc, localizedString(desc[0].strPart))

proc showTaskIcon*(icoNode: Node, icoName: string) =
    for ico in icoNode.children:
        if ico.name == icoName:
            ico.alpha = 1.0
        else:
            ico.alpha = 0.0

proc showSlotIcon*(icoNode: Node, icoName: string) =
    for ico in icoNode.children:
        if ico.name == icoName:
            ico.alpha = 1.0
        else:
            ico.alpha = 0.0

proc iconForQuest*(target: BuildingId, qt: QuestTaskType): string=
    var buildTask = false
    if qt == qttBuild or  qt == qttUpgrade:
        buildTask = true
    result = $target
    if buildTask:
        result &= "_build"

    if result notin questsIcons:
        result = ""

proc getSlotName*(t: BuildingId): string =
    result = "BUILD_NAME_" & ($t).toUpperAscii()

proc getLocalizedSlotName*(t: BuildingId): string =
    result = localizedString(getSlotName(t))

proc isTargetInLocaKey(t: QuestTaskType, target: BuildingId): tuple[isTargeted:bool, isSlotTargetInLoca:bool]=
    result.isTargeted = false
    result.isSlotTargetInLoca = false
    case t:
    of qttSpinNTimes, qttSpinNTimesMaxBet, qttWinChipOnSpins, qttMakeWinSpins, qttWinBigWins,
        qttWinNChips, qttWinChipOnFreespins, qttWinChipsOnBonus, qttWinFreespinsCount, qttWinNLines:
        if target == anySlot or target == noBuilding: discard
        else: result.isTargeted = true
    of qttCollectWild, qttCollectBonus, qttCollectScatters, qttCollectHi0, qttCollectHi1, qttCollectHi2, qttCollectHi3, qttPolymorphNSymbolsIntoWild, qttCollectHidden, qttCollectMultipliers, qttShuffle:
        result.isSlotTargetInLoca = true
    else: discard

proc getTaskLocaKey*(t: QuestTaskType):string=
    case t:
    of qttSpinNTimes:
        result = "QTTSPINNTIMES"
    of qttSpinNTimesMaxBet:
        result = "QTTSPINNTIMESMAXBET"
    of qttMakeWinSpins:
        result = "QTTMAKEWINSPINS"
    of qttWinChipOnSpins:
        result = "QTTWINCHIPONSPINS"
    of qttWinBonusTimes:
        result = "QTTWINBONUSTIMES"
    of qttWinFreespinsCount:
        result = "QTTWINFREESPINSCOUNT"
    of qttWinBigWins:
        result = "QTTWINBIGWINS"
    of qttWinChipsOnBonus:
        result = "QTTWINCHIPSONBONUS"
    of qttWinChipOnFreespins:
        result = "QTTWINCHIPONFREESPINS"
    of qttWinNChips:
        result = "QTTWINNCHIPS"
    of qttWinN5InRow:
        result = "QTTWINN5INROW"
    of qttWinN4InRow:
        result = "QTTWINN4INROW"
    of qttWinN3InRow:
        result = "QTTWINN3INROW"
    of qttCollectScatters:
        result = "QTTCOLLECTSCATTERS"
    of qttCollectBonus:
        result = "QTTCOLLECTBONUS"
    of qttCollectWild:
        result = "QTTCOLLECTWILD"
    of qttBlowNBalloon:
        result = "QTTBLOWNBALLOON"
    of qttMakeNRespins:
        result = "QTTMAKENRESPINS"
    of qttPolymorphNSymbolsIntoWild:
        result = "QTTPOLYMORPHNSYMBOLSINTOWILD"
    of qttGroovySevens:
        result = "qttGroovySevens".toUpperAscii()
    of qttGroovyLemons:
        result = "qttGroovyLemons".toUpperAscii()
    of qttGroovyBars:
        result = "qttGroovyBars".toUpperAscii()
    of qttGroovyCherries:
        result = "qttGroovyCherries".toUpperAscii()
    of qttCollectHi0:
        result = "QTTCOLLECTHI0"
    of qttCollectHi1:
        result = "QTTCOLLECTHI1"
    of qttCollectHi2:
        result = "QTTCOLLECTHI2"
    of qttCollectHi3:
        result = "QTTCOLLECTHI3"
    of qttFreeRounds:
        result = "QTTFREEROUNDS"
    of qttShuffle:
        result = "QTTSHUFFLE"
    of qttCollectHidden:
        result = "QTTHIDDEN"
    of qttCollectMultipliers:
        result = "QTTCOLLECTMULTIPLIERS"
    of qttWinNLines:
        result = "QTTWINNLINES"
    else:
        result = ""


proc getTaskIcon*(t: QuestTaskType, target: BuildingId): string=
    var locaKey = t.getTaskLocaKey()
    if locaKey.len > 0:
        if t == qttWinChipOnSpins:
            locaKey = qttWinNChips.getTaskLocaKey()
        var (isTargeted, isSlotTargetInLoca) = t.isTargetInLocaKey(target)
        if isSlotTargetInLoca:
            locaKey &= "_" & $target
        result = locaKey
    else:
        result = getTaskLocaKey(qttSpinNTimes)

proc genTaskName*(t: QuestTaskType, target: BuildingId): string=
    let locaKey = getTaskLocaKey(t)
    if locaKey.len > 0:
        var (isTargeted, isSlotTargetInLoca) = t.isTargetInLocaKey(target)
        result = locaKey & "_QTITLE"
        if isSlotTargetInLoca:
            result.add('_')
            result &= ($target).toUpperAscii()
    else:
        result = "TASK_NOT_LOCALIZED" & $t

proc genTaskDescription*(t: QuestTaskType, target: BuildingId, args: varargs[int64]): seq[QuestDesc] =
    result = @[]

    let locaKey = getTaskLocaKey(t)
    if locaKey.len > 0:
        var (isTargeted, isSlotTargetInLoca) = t.isTargetInLocaKey(target)

        if isSlotTargetInLoca:
            result.add((locaKey & "_QDESC_SHORT_" & ($target).toUpperAscii(), true))
            result.add((formatThousands(args[0]), false))
        elif isTargeted:
            result.add((locaKey & "_QDESC_SHORT_TARGETED", true))
            result.add((formatThousands(args[0]), false))
            result.add((getSlotName(target), true))
        else:
            result.add((locaKey & "_QDESC_SHORT", true))
            result.add((formatThousands(args[0]), false))
    else:
        result.add(("TASK_NOT_LOCALIZED_" & $t, false))

proc genTaskShortDescription*(t: QuestTaskType, target: BuildingId, args: varargs[int64]): string=
    var locaKey = getTaskLocaKey(t)
    if locaKey.len > 0:
        var (isTargeted, isSlotTargetInLoca) = t.isTargetInLocaKey(target)
        locaKey &= "_NEW_TASK"

        if isSlotTargetInLoca:
            locaKey &= "_" & ($target).toUpperAscii()

        result = localizedFormat(locaKey, formatThousands(args[0]))
    else:
        result = "TASK_NOT_LOCALIZED " & $t

proc getTaskPanelTitle*(t: QuestTaskType, target: BuildingId): string=
    var locaKey = getTaskLocaKey(t)
    if locaKey.len > 0:
        var (isTargeted, isSlotTargetInLoca) = t.isTargetInLocaKey(target)
        locaKey &= "_QPROG_PANEL"
        if isSlotTargetInLoca:
            locaKey &= "_" & ($target).toUpperAscii()

        result = localizedString(locaKey)
    else:
        result = "TASK_NOT_LOCALIZED " & $t

proc activeSlots*(): seq[BuildingId]=
    result = @[]
    let u = currentUser()
    if "slots" in u.clientState:
        for jbi in u.clientState["slots"]:
            result.add(parseEnum[BuildingId](jbi.str))

proc activeSlotsStr*(): seq[string]=
    result = @[]
    let u = currentUser()
    if "slots" in u.clientState:
        for jbi in u.clientState["slots"]:
            result.add(jbi.str)

proc storyQuestIcon*(id: int): string {.deprecated.} =
    # let user = currentUser()
    # case id:
    # of 1: result = "build_store"
    # of 2: result = "build_city_hall"
    # of 3: result = "build_restaurant"
    # of 4: result = "build_gasStation"
    # of 5: result = "build_bank"
    # of 6: result = "build_city_hall"
    # of 7:
    #     let ss = user.playerSlotsFlow()[1]
    #     if ss == dreamTowerSlot:
    #         result = "secondSlot"
    #     else:
    #         result = $ss
    # of 8: result = "build_restaurant"
    # of 9: result = "build_gasStation"
    # of 10:
    #     result = $user.playerSlotsFlow()[2]
    # of 11: result = "build_restaurant"
    # of 12: result = "build_gasStation"
    # of 13: result = "build_stadium"
    # else:
    result = ""

proc addTaskIconComponent*(n: Node, name: string): IconComponent =
    result = n.component(IconComponent)
    result.composition = "all_task_icons"
    result.name = name
    result.hasOutline = true
