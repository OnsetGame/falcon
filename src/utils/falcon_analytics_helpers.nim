import times, tables, json, strutils, logging
import analytics

import nimx.animation
import nimx.notification_center
import nimx.timer

import rod.viewport

import shared.gui.gui_module_types
import shared.user

import utils.game_state
import utils.falcon_analytics
import falconserver.map.building.builditem

type ATypes* = enum
    FIRST_RUN_LOADSCREEN_BEGIN = 0
    FIRST_RUN_LOADSCREEN_50_COMPLETE
    FIRST_RUN_TUTORIAL_BEGIN
    FIRST_RUN_FIRST_SPIN_BEGIN
    FIRST_RUN_RETURN_TO_CITY
    FIRST_RUN_PRESS_EXCHANGE_CHIPS
    FIRST_RUN_EXIT_EXCHANGE
    FIRST_QUEST1_COMPLETE
    FIRST_RUN_QUEST1_BACK_TO_THE_CITY
    FIRST_RUN_FIRST_TASK_SPIN_10_ITERATOR
    FIRST_RUN_PRELOADER_BEGIN

type TutorialStep {.pure.} = enum #be careful when editing this enum - numeric values are important!
    FirstRunLoadscreenBegin = 1
    FirstRunLoadscreen50Complete
    FirstRunTutorialBegin
    FirstRun1SlotGameStart
    FirstRunFirstSpinBegin
    FirstRunFirstTaskSpin1
    FirstRunFirstTaskSpin2
    FirstRunFirstTaskSpin3
    FirstRunFirstTaskSpin4
    FirstRunFirstTaskSpin5
    FirstRunFirstTaskSpin6
    FirstRunFirstTaskSpin7
    FirstRunFirstTaskSpin8
    FirstRunFirstTaskSpin9
    FirstRunFirstTaskSpin10
    FirstRunReturnToCity
    FirstRunPressCollectChips
    FirstRunPreloaderBegin

proc sendEvent*(name: string, args: JsonNode, step: TutorialStep, useBuffer: bool = true) =
    sendEvent(name, args, useBuffer)
    tutorialStepCompleted(step.int)

proc updateAnalyticStates*() =
    for t in ATypes:
        let stateStr = $t
        if stateStr.endsWith("ITERATOR"):
            var splitSeq = stateStr.split('_')
            splitSeq.delete(splitSeq.len-1)
            let iterBorder = parseInt(splitSeq[^1])
            splitSeq.delete(splitSeq.len-1)
            let baseStrIterState = join(splitSeq, "_")
            for i in 0..iterBorder: # zero stage for start trigger
                let state = baseStrIterState & '_' & $i
                if not hasGameState(state, ANALYTICS_TAG):
                    setGameState(state, false, ANALYTICS_TAG)
        else:
            if not hasGameState(stateStr, ANALYTICS_TAG):
                setGameState(stateStr, false, ANALYTICS_TAG)

proc resetAnalytics*() =
    for t in ATypes:
        let stateStr = $t
        if stateStr.endsWith("ITERATOR"):
            var splitSeq = stateStr.split('_')
            splitSeq.delete(splitSeq.len-1)
            let iterBorder = parseInt(splitSeq[^1])
            splitSeq.delete(splitSeq.len-1)
            let baseStrIterState = join(splitSeq, "_")
            for i in 0..iterBorder: # zero stage for start trigger
                let state = baseStrIterState & '_' & $i
                setGameState(state, false, ANALYTICS_TAG)
        else:
            setGameState(stateStr, false, ANALYTICS_TAG)

proc isAnalyticEventDone*(key: string): bool =
    return hasGameState(key, ANALYTICS_TAG) and getBoolGameState(key, ANALYTICS_TAG)

proc isAnalyticEventDone*(key: ATypes): bool =
    return hasGameState($key, ANALYTICS_TAG) and getBoolGameState($key, ANALYTICS_TAG)

type ATimer = ref object
    name: ATypes
    startTime*: float64
    finishTime*: float64

type AnalyticsTimers* = ref object of RootObj
    timers: Table[ATypes, ATimer]

#------------------------------------------------------------------------

proc getTimeSec*(): float64 = epochTime().float64

#------------------------------------------------------------------------

proc analyticsLog*[T](msg: string, v: T) =
    info "--------ANALYTICS LOG: ", msg, " ", v
proc analyticsLog*(msg: string) =
    info "--------ANALYTICS MSG: ", msg

#------------------------------------------------------------------------

var gAnalyticsTimers: AnalyticsTimers
proc sharedAnalyticsTimers*(): AnalyticsTimers=
    if gAnalyticsTimers.isNil():
        gAnalyticsTimers.new()
        gAnalyticsTimers.timers = initTable[ATypes, ATimer]()
    result = gAnalyticsTimers

proc sharedAnalyticsTimers*(msg: string): AnalyticsTimers=
    analyticsLog(msg)
    sharedAnalyticsTimers()

proc `[]`*(at: AnalyticsTimers, name: ATypes): ATimer =
    var t: ATimer
    t = at.timers.getOrDefault(name)
    if t.isNil:
        t.new()
        t.name = name
        at.timers[name] = t
    return t

#------------------------------------------------------------------------

proc start*(t: ATimer) =
    t.startTime = epochTime().float64

proc stop*(t: ATimer) =
    t.finishTime = epochTime().float64

proc hasStarted*(t: ATimer): bool =
    return t.startTime > 0

proc diff*(t: ATimer): float64 {.discardable.} =
    if t.finishTime == 0:
        t.stop()
    result = t.finishTime - t.startTime
    setGameState($t.name, true, ANALYTICS_TAG)

    # analyticsLog($t.name)
    # analyticsLog($result)

    sharedAnalyticsTimers().timers.del(t.name)

#------------------------------------------------------------------------

var mIsBeforeTutorialAnalytics: bool

var mClosedByButtonAnalytics: bool

var mPrevWindowAnalytics = "None"
var mCurrWindowAnalytics = "None"
var bStartCountWindows*: bool

var mPrevPopupAnalytics: GUIModuleType = mtNone
var mCurrPopupAnalytics: GUIModuleType = mtNone
var popupCounter: int

var mPrevGUIModuleButtonAnalytics: string = ""
var mCurrGUIModuleButtonAnalytics: string = ""
var guiButtonsCounter: int
var guiPaytableButtonsCounter: int
var bStartCountGUIButtons*: bool

# var mCurrSpotAnalytics: BuildingId = noBuilding

# var mCurrBuildedSlotAnalytics: BuildingId = noBuilding

# var mPrevSlotMenuEntered: BuildingId = noBuilding
# var mCurrSlotMenuEntered: BuildingId = noBuilding
var fromQuestSlotMenuEntered*: BuildingId = noBuilding

var mCurrSlotEntered: BuildingId = noBuilding

var mPrevSoundGainAnalytics: float32
var mCurrSoundGainAnalytics: float32
var mPrevMusicGainAnalytics: float32
var mCurrMusicGainAnalytics: float32
var isAudioSettingsClickedInSlot: bool = false

var currBetAnalytic*: int = 0
var prevBetAnalytic*: int = 0

var lastSpinRTP: float64
var totalSpinRTP*: float64

var spinsAnalytics: int
var bonusAnalitycs: int
var freespinsAnalytics: int

type AControllerTypes* = enum
    aMouse = 0
    aSpace
    aAutospin
    aNone

var mController: AControllerTypes = aNone

var mControllerCount = newSeq[int]()
for i in AControllerTypes: mControllerCount.add(0)

var isInSlotAnalytics*: bool = false

var isProfileVisitedInSlot: bool = false
var isBetClickedInSlot: bool = false

type AStoreTabTypes* = enum
    tSlots = 0
    tResources
    tNone

var mCurrStoreTab: AStoreTabTypes = tNone

var mTryBuildObject: BuildingId = noBuilding

var wasExchangeAnalytics*: bool
var wasLackOfBucksAnalytics*: bool

var startCountQuestWindowsAnalytics*: bool
var questWindowCounterAnalytics*: int
var backToCityInFirstQuest*: bool
var startCountSpinsInFirstQuestAnalytics*: bool
var spinsInFirstQuestAnalytics*: int
var getFirstQuestRewardBeforeExitFromSlotAnalytics*: bool

type AExchangeTypes* = enum
    exChips = 0
    exBeams
    exNone

var currExchangeTypeAnalytics*: AExchangeTypes = exNone

var bFirstDailyDoneAnalytics* = false

#------------------------------------------------------------------------
proc first_run_loadscreen_begin*(a: FalconAnalytics, load_time: int) =
    var j = newJObject()
    j[$aLoadingTime] = %($load_time)
    sendEvent("first_run_loadscreen_begin", j, TutorialStep.FirstRunLoadscreenBegin, false)

proc first_run_loadscreen_50_complete*(a: FalconAnalytics, load_time: int) =
    var j = newJObject()
    j[$aLoadingTime] = %($load_time)
    sendEvent("first_run_loadscreen_50_complete", j, TutorialStep.FirstRunLoadscreen50Complete, false)

proc first_run_first_spin_begin*(a: FalconAnalytics, controller, profile, bet, paytable, audio: int) =
    var j = newJObject()
    j[$aController] = %($controller)
    j[$aProfile] = %($profile)
    j[$aBet] = %($bet)
    j[$aPaytable] = %($paytable)
    j[$aAudio] = %($audio)
    sendEvent("first_run_first_spin_begin", j, TutorialStep.FirstRunFirstSpinBegin, false)

proc first_run_return_to_city*(a: FalconAnalytics, load_time: int) =
    var j = newJObject()
    j[$aLoadingTime] = %($load_time)
    sendEvent("first_run_return_to_city", j, TutorialStep.FirstRunReturnToCity)

proc first_run_press_exchange_chips*(a: FalconAnalytics, bucks_left, chips_left, beams_left, delay_time: int) =
    var j = newJObject()
    j[$aBucksLeft] = %($bucks_left)
    j[$aChipsLeft] = %($chips_left)
    j[$aBeamsLeft] = %($beams_left)
    j[$aDelayTime] = %($delay_time)
    sendEvent("first_run_press_exchange_chips", j)

# proc first_run_exit_exchange*(a: FalconAnalytics, delay_time: int, was_exchange, was_lack_bucks: bool) =
#     var j = newJObject()
#     j[$aDelayTime] = %($delay_time)
#     j[$aWasExchange] = %($was_exchange)
#     j[$aWasLackBucks] = %($was_lack_bucks)
#     sendEvent("first_run_exit_exchange", j)

proc first_run_first_task_spin*(a: FalconAnalytics, currSpin: int, rtp: float32, chips_left: int64, bet: int, slot_id: string, activeTaskProgress: float) =
    var j = newJObject()
    j[$aRTP] = %(formatFloat(rtp, precision = 3))
    j[$aChipsLeft] = %($chips_left)
    j[$aBet] = %($bet)
    j[$aSlotID] = %(slot_id)
    j[$aActiveTaskProgress] = %((activeTaskProgress * 100).int)
    sendEvent("first_run_first_task_spin_" & $currSpin, j, (TutorialStep.FirstRunFirstSpinBegin.int + currSpin).TutorialStep, false)

proc first_run_preloader_begin*(a: FalconAnalytics) =
    var j = newJObject()
    sendEvent("first_run_preloader_begin", j, TutorialStep.FirstRunPreloaderBegin, false)
#------------------------------------------------------------------------

proc checkForFirstSpinInPopup() =
    if isInSlotAnalytics:
        if mCurrWindowAnalytics == "ProfileWindow":
            isProfileVisitedInSlot = true
    else:
        isProfileVisitedInSlot = false

proc checkForBetChange() =
    if isInSlotAnalytics:
        if mCurrGUIModuleButtonAnalytics.contains("bet_panel"):
            isBetClickedInSlot = true
    else:
        isBetClickedInSlot = false

proc checkPaytableScreensCount() =
    if isInSlotAnalytics:
        if mCurrGUIModuleButtonAnalytics.contains("arrow"):
            inc guiPaytableButtonsCounter
    else:
        guiPaytableButtonsCounter = 0

proc checkForSoundSettingsVisit() =
    if isInSlotAnalytics:
        isAudioSettingsClickedInSlot = true
    else:
        mCurrMusicGainAnalytics = 0
        mPrevMusicGainAnalytics = 0
        mCurrSoundGainAnalytics = 0
        mPrevSoundGainAnalytics = 0
        isAudioSettingsClickedInSlot = false
        for i in 0..<mControllerCount.len: mControllerCount[i] = 0

proc firstSpinEventAnalytics*() =
    if not isAnalyticEventDone(FIRST_RUN_FIRST_SPIN_BEGIN):
        var bet = if not isBetClickedInSlot: 0 else: ( if currBetAnalytic < prevBetAnalytic: 1 else: 2 )

        proc getAudio(): int =
            if not isAudioSettingsClickedInSlot: return 0
            if  (mCurrSoundGainAnalytics == mPrevSoundGainAnalytics or mPrevSoundGainAnalytics == 0) and
                (mCurrMusicGainAnalytics == mPrevMusicGainAnalytics or mPrevMusicGainAnalytics == 0):
                    return 1
            if  mCurrSoundGainAnalytics   < mPrevSoundGainAnalytics and
                (mCurrMusicGainAnalytics == mPrevMusicGainAnalytics or mPrevMusicGainAnalytics == 0):
                    return 2
            if  (mCurrSoundGainAnalytics == mPrevSoundGainAnalytics or mPrevSoundGainAnalytics == 0) and
                mCurrMusicGainAnalytics   < mPrevMusicGainAnalytics:
                    return 3
            if  mCurrSoundGainAnalytics   < mPrevSoundGainAnalytics and
                mCurrMusicGainAnalytics   < mPrevMusicGainAnalytics:
                    return 4
            return 5
        sharedAnalytics().first_run_first_spin_begin(mController.int, if isProfileVisitedInSlot: 1 else: 0, bet, guiPaytableButtonsCounter, getAudio())
        setGameState($FIRST_RUN_FIRST_SPIN_BEGIN, true, ANALYTICS_TAG)

proc setLastRTPAnalytics*(lastSpin, totalRTP: float64) =
    lastSpinRTP = lastSpin
    totalSpinRTP = totalRTP

proc setStagesCountAnalytics*(spis, bonus, freespins: int) =
    spinsAnalytics = spis
    bonusAnalitycs = bonus
    freespinsAnalytics = freespins

proc checkToCity() =
    proc mechanics(bHasBonusGameAnalytics, bHasFreespinsAnalytics: bool): int =
        if not bHasBonusGameAnalytics and not bHasFreespinsAnalytics: return 0
        if     bHasBonusGameAnalytics and not bHasFreespinsAnalytics: return 1
        if not bHasBonusGameAnalytics and     bHasFreespinsAnalytics: return 2
        if     bHasBonusGameAnalytics and     bHasFreespinsAnalytics: return 3

    var mech = mechanics( if bonusAnalitycs > 0: true else: false, if freespinsAnalytics > 0: true else: false )

    proc controller(): int =
        if mControllerCount[aMouse.int]    >= mControllerCount[aSpace.int] and mControllerCount[aMouse.int]    >= mControllerCount[aAutospin.int]: return 0
        if mControllerCount[aSpace.int]    >= mControllerCount[aMouse.int] and mControllerCount[aSpace.int]    >= mControllerCount[aAutospin.int]: return 1
        if mControllerCount[aAutospin.int] >= mControllerCount[aMouse.int] and mControllerCount[aAutospin.int] >= mControllerCount[aSpace.int]:    return 2

    if startCountSpinsInFirstQuestAnalytics and not isAnalyticEventDone(FIRST_RUN_QUEST1_BACK_TO_THE_CITY):
        getFirstQuestRewardBeforeExitFromSlotAnalytics = false
        startCountSpinsInFirstQuestAnalytics = false
        spinsInFirstQuestAnalytics = 0

proc checkBackToCityFromQuest*() =
    if isInSlotAnalytics:
        checkToCity()

proc checkBackToCity() =
    if isInSlotAnalytics:
        if mCurrGUIModuleButtonAnalytics.contains("back_city") or (bFirstDailyDoneAnalytics and mCurrGUIModuleButtonAnalytics.contains("card_parent")):
            checkToCity()
    else:
        discard

proc checkForFirstTimeExchangeVisit() =
    if mCurrWindowAnalytics == "ExchangeWindow" and currExchangeTypeAnalytics == exChips:
        if not isAnalyticEventDone(FIRST_RUN_PRESS_EXCHANGE_CHIPS) and sharedAnalyticsTimers()[FIRST_RUN_PRESS_EXCHANGE_CHIPS].hasStarted():
            let bucks_left = currentUser().bucks.int
            let chips_left = currentUser().chips.int
            let beams_left = currentUser().parts.int
            sharedAnalytics().first_run_press_exchange_chips(bucks_left, chips_left, beams_left, sharedAnalyticsTimers()[FIRST_RUN_PRESS_EXCHANGE_CHIPS].diff().int)

            sharedAnalyticsTimers()[FIRST_RUN_EXIT_EXCHANGE].start()

# proc checkForFirstExchangeClose() =
#     if not isAnalyticEventDone(FIRST_RUN_EXIT_EXCHANGE) and sharedAnalyticsTimers()[FIRST_RUN_EXIT_EXCHANGE].hasStarted():
#         # sharedAnalytics().first_run_exit_exchange(sharedAnalyticsTimers()[FIRST_RUN_EXIT_EXCHANGE].diff().int, wasExchangeAnalytics, wasLackOfBucksAnalytics)
#         wasExchangeAnalytics = false
#         wasLackOfBucksAnalytics = false

proc checkForQuestPopup() =
    if startCountQuestWindowsAnalytics and mCurrWindowAnalytics == "QuestWindow":
        inc questWindowCounterAnalytics

proc checkForFirstQuestGetReward() =
    if mCurrWindowAnalytics == "RewardWindow" and startCountSpinsInFirstQuestAnalytics:
        getFirstQuestRewardBeforeExitFromSlotAnalytics = true

proc startFirstTask10TimesSpinAnalytics*() =
    setGameState("FIRST_RUN_FIRST_TASK_SPIN_0", true, ANALYTICS_TAG)

proc runFirstTask10TimesSpinAnalytics*(rtp: float32, chips: int64, bet: int, sceneName: string, taskProgress: float) =
    if not isAnalyticEventDone(FIRST_QUEST1_COMPLETE) and not isAnalyticEventDone("FIRST_RUN_FIRST_TASK_SPIN_10") and isAnalyticEventDone("FIRST_RUN_FIRST_TASK_SPIN_0"):
        var currSpin = 1
        var currState = ""
        while currSpin <= 10:
            currState = "FIRST_RUN_FIRST_TASK_SPIN_" & $currSpin
            if not isAnalyticEventDone(currState):
                break
            inc currSpin
        sharedAnalytics().first_run_first_task_spin(currSpin, rtp, chips, bet, sceneName, taskProgress)
        setGameState(currState, true, ANALYTICS_TAG)

#------------------------------------------------------------------------

proc isBeforeTutorialAnalytics*(): bool =
    return mIsBeforeTutorialAnalytics
proc isBeforeTutorialAnalytics*(msg: string): bool=
    analyticsLog(msg, mIsBeforeTutorialAnalytics)
    return mIsBeforeTutorialAnalytics
proc setIsBeforeTutorialAnalytics*(v: bool) =
    mIsBeforeTutorialAnalytics = v
proc setIsBeforeTutorialAnalytics*(v: bool, msg: string) =
    analyticsLog(msg, v)
    setIsBeforeTutorialAnalytics(v)

proc closedByButtonAnalytics*(): bool =
    return mClosedByButtonAnalytics
proc closedByButtonAnalytics*(msg: string): bool {.discardable.} =
    analyticsLog(msg, mClosedByButtonAnalytics)
    result = mClosedByButtonAnalytics
proc setClosedByButtonAnalytics*(v: bool) =
    mClosedByButtonAnalytics = v
    # analyticsLog("setClosedByButtonAnalytics ", mClosedByButtonAnalytics)
    # analyticsLog("mCurrWindowAnalytics on close ", mCurrWindowAnalytics)
    # checkForFirstExchangeClose()
proc setClosedByButtonAnalytics*(msg: string, v: bool) =
    analyticsLog(msg, v)
    setClosedByButtonAnalytics(v)

proc currWindowAnalytics*(): string =
    return mCurrWindowAnalytics
proc setCurrWindowAnalytics*(windowName: string) =
    # analyticsLog("setCurrPopupAnalytics =", v)
    mPrevWindowAnalytics = mCurrWindowAnalytics
    mCurrWindowAnalytics = windowName
    checkForFirstSpinInPopup()
    checkForSoundSettingsVisit()
    checkForFirstTimeExchangeVisit()
    checkForQuestPopup()
    checkForFirstQuestGetReward()

proc currPopupAnalytics*(): GUIModuleType =
    return mCurrPopupAnalytics
proc currPopupAnalytics*(msg: string): GUIModuleType {.discardable.} =
    analyticsLog(msg, mCurrPopupAnalytics)
    return mCurrPopupAnalytics
proc setCurrPopupAnalytics*(v: GUIModuleType) =
    # analyticsLog("setCurrPopupAnalytics =", v)
    mPrevPopupAnalytics = mCurrPopupAnalytics
    mCurrPopupAnalytics = v
    checkForFirstSpinInPopup()
    checkForSoundSettingsVisit()
    checkForFirstTimeExchangeVisit()
    checkForQuestPopup()
    checkForFirstQuestGetReward()

proc currGUIModuleAnalytics*(): string =
    return mCurrGUIModuleButtonAnalytics
proc setCurrGUIModuleAnalytics*(v: string) =
    # analyticsLog("setCurrGUIModuleAnalytics =", v)
    mPrevGUIModuleButtonAnalytics = mCurrGUIModuleButtonAnalytics
    mCurrGUIModuleButtonAnalytics = v
    if bStartCountGUIButtons: inc guiButtonsCounter
    checkForBetChange()
    checkPaytableScreensCount()
    checkBackToCity()

# proc currSpotAnalytics*(): BuildingId =
#     return mCurrSpotAnalytics

# proc currSpotAnalytics*(msg: string): BuildingId {.discardable.} =
#     analyticsLog(msg, mCurrSpotAnalytics)
#     return mCurrSpotAnalytics

# proc setCurrSpotAnalytics*(v: BuildingId) =
#     mCurrSpotAnalytics = v

# proc setCurrSpotAnalytics*(msg: string, v: BuildingId) =
#     analyticsLog(msg, v)
#     setCurrSpotAnalytics(v)

# proc currBuildedSlotAnalytics*(): BuildingId =
#     return mCurrBuildedSlotAnalytics
# proc currBuildedSlotAnalytics*(msg: string): BuildingId {.discardable.} =
#     analyticsLog(msg, mCurrBuildedSlotAnalytics)
#     return mCurrBuildedSlotAnalytics
# proc setCurrBuildedSlotAnalytics*(v: BuildingId) =
#     mCurrBuildedSlotAnalytics = v
# proc setCurrBuildedSlotAnalytics*(msg: string, v: BuildingId) =
#     analyticsLog(msg, v)
#     setCurrBuildedSlotAnalytics(v)

# proc currSlotMenuEntered*(): BuildingId =
#     return mCurrSlotMenuEntered
# proc currSlotMenuEntered*(msg: string): BuildingId {.discardable.} =
#     analyticsLog(msg, mCurrSlotMenuEntered)
#     return mCurrSlotMenuEntered
# proc setCurrSlotMenuEntered*(v: BuildingId) =
#     # analyticsLog("setCurrSlotMenuEntered = ", $v)
#     mPrevSlotMenuEntered = mCurrSlotMenuEntered
#     mCurrSlotMenuEntered = v
# proc setCurrSlotMenuEntered*(msg: string, v: BuildingId) =
#     analyticsLog(msg, v)
#     setCurrSlotMenuEntered(v)

proc currSlotEntered*(): BuildingId =
    return mCurrSlotEntered
proc currSlotEntered*(msg: string): BuildingId {.discardable.} =
    analyticsLog(msg, mCurrSlotEntered)
    return mCurrSlotEntered
proc setCurrSlotEntered*(v: BuildingId) =
    mCurrSlotEntered = v
proc setCurrSlotEntered*(msg: string, v: BuildingId) =
    analyticsLog(msg, v)
    setCurrSlotEntered(v)

proc controller*(): AControllerTypes =
    return mController
proc controller*(msg: string): AControllerTypes {.discardable.} =
    analyticsLog(msg, mController)
    return mController
proc setController*(v: AControllerTypes) =
    # analyticsLog("setController = ", $v)
    mController = v
    mControllerCount[mController.int] = mControllerCount[mController.int] + 1
    if startCountSpinsInFirstQuestAnalytics:
        inc spinsInFirstQuestAnalytics
proc setController*(msg: string, v: AControllerTypes) =
    analyticsLog(msg, v)
    setController(v)

proc currSoundGainAnalytics*(): float32 =
    return mCurrSoundGainAnalytics
proc currSoundGainAnalytics*(msg: string): float32 {.discardable.} =
    analyticsLog(msg, mCurrSoundGainAnalytics)
    return mCurrSoundGainAnalytics
proc setCurrSoundGainAnalytics*(v: float32) =
    # analyticsLog("setCurrSoundGainAnalytics = ", $v)
    if v != mCurrSoundGainAnalytics:
        mPrevSoundGainAnalytics = mCurrSoundGainAnalytics
        mCurrSoundGainAnalytics = v
proc setCurrSoundGainAnalytics*(msg: string, v: float32) =
    analyticsLog(msg, v)
    setCurrSoundGainAnalytics(v)

proc currMusicGainAnalytics*(): float32 =
    return mCurrMusicGainAnalytics
proc currMusicGainAnalytics*(msg: string): float32 {.discardable.} =
    analyticsLog(msg, mCurrMusicGainAnalytics)
    return mCurrMusicGainAnalytics
proc setCurrMusicGainAnalytics*(v: float32) =
    # analyticsLog("setCurrMusicGainAnalytics = ", $v)
    if v != mCurrMusicGainAnalytics:
        mPrevMusicGainAnalytics = mCurrMusicGainAnalytics
        mCurrMusicGainAnalytics = v
proc setCurrMusicGainAnalytics*(msg: string, v: float32) =
    analyticsLog(msg, v)
    setCurrMusicGainAnalytics(v)

proc currStoreTab*(): AStoreTabTypes =
    return mCurrStoreTab
proc currStoreTab*(msg: string): AStoreTabTypes {.discardable.} =
    analyticsLog(msg, mCurrStoreTab)
    return mCurrStoreTab
proc setCurrStoreTab*(v: AStoreTabTypes) =
    # analyticsLog("setCurrStoreTab = ", $v)
    mCurrStoreTab = v
proc setCurrStoreTab*(msg: string, v: AStoreTabTypes) =
    analyticsLog(msg, v)
    setCurrStoreTab(v)

proc tryBuildObject*(): BuildingId =
    return mTryBuildObject
proc tryBuildObject*(msg: string): BuildingId {.discardable.} =
    # analyticsLog(msg, mTryBuildObject)
    return mTryBuildObject
proc setTryBuildObject*(v: BuildingId) =
    # analyticsLog("setTryBuildObject = ", $v)
    mTryBuildObject = v
proc setTryBuildObject*(msg: string, v: BuildingId) =
    # analyticsLog(msg, v)
    setTryBuildObject(v)

#------------------------------------------------------------------------

proc noteProgressTime*(v: SceneView, capturatotor: proc(): float64, breakpoints: seq[float64], callback: proc(results: seq[float64]))=
    var res: seq[float64] = @[]
    var valProgBreakpoints = breakpoints
    let startTime = epochTime().float64
    var a = newAnimation()
    a.numberOfLoops = -1
    a.loopDuration = 0.001
    a.onAnimate = proc(p:float) =
        if valProgBreakpoints.len > 0:
            for k, v in valProgBreakpoints:
                closureScope:
                    if v <= capturatotor():
                        res.add(epochTime().float64 - startTime)
                        valProgBreakpoints.del(k)
        else:
            a.cancel()

    a.onComplete do():
        callback(res)
        a = nil

    v.addAnimation(a)
