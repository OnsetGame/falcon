import shared.user
import json, tables, logging, times
import variant
import nimx.notification_center
import boolseq
import shafa / game / [ reward_types, message_types ]
import utils / [ timesync ]
import slots.bet_config
import map.collect_resources
import core / zone
import core / features / slot_feature
import core / flow / flow_state_types
import core / flow / flow
import quest / quests

type ResponceEvents = enum
    REState = "state"
    REExperience = "lvlData"
    RELevelData = "lvlData"
    REVip = "vip"
    REQuests = "quests"
    REMessages = "messages"
    REExchangeRates = "exchangeNum"
    REServerTime = "serverTime"
    RETutorial = "tutorial"
    RENextExchangeDiscountTime = "cronTime"
    REBetConfig = "betsConf"
    RECollectConfig = "collectConfig"
    REMaintenance = "maintenanceTime"
    REFreeRounds = "freeRounds"
    REFreeRoundsFinished = "freeRoundsFinished"

proc toBoolSeq(jn: JsonNode): BoolSeq=
    var questate = ""
    for ji in jn:
        questate.add(ji.getInt().char)

    result = newBoolSeq(questate)

proc parseEvents*(jn: JsonNode) =
    let user = currentUser()
    jn.updateFeaturesState()
    # echo "parseEvents"
    for t in low(ResponceEvents)..high(ResponceEvents):
        if $t in jn:
            case t
            of REMaintenance:
                if not findActiveState(MaintenanceFlowState).isNil and jn{"maintenanceTime"}.getFloat(0.0) == 0.0:
                    sharedNotificationCenter().postNotification("HAVE_TO_RESTART_APP")
                    return

                elif findActiveState(MaintenanceFlowState).isNil and jn{"maintenanceTime"}.getFloat(0.0) > 0.0:
                    let timeout = jn["maintenanceTime"].getFloat() - jn["serverTime"].getFloat() + epochTime()
                    let state = newFlowState(MaintenanceFlowState, newVariant(timeout))
                    pushBack(state)

            of RELevelData:
                let lvl = jn[$t]["level"].getInt()
                if lvl > user.level or (lvl < user.level and user.cheatsEnabled):
                    user.level = lvl
                    pushFront(LevelUpWindowFlowState)

            of REVip:
                let lvl = max(jn[$t]{"level"}.getInt(), 0)
                user.vipPoints = jn[$t]{"points"}.getInt()
                if user.vipLevel == -1:
                    user.vipLevel = lvl
                else:
                    if lvl > user.vipLevel or (lvl < user.vipLevel and user.cheatsEnabled):
                        let oldVipLevel = user.vipLevel
                        user.vipLevel = lvl
                        for l in oldVipLevel + 1 .. lvl:
                            pushBack(VipLevelUpWindowFlowState(level: l))

            of REQuests:
                if "questate" in jn[$t]:
                    user.questsState = jn[$t]["questate"].toBoolSeq()

                sharedQuestManager().proceedQuests(jn[$t])

            of REBetConfig:
                var bc = parseBetConfig(jn)
                let state = newFlowState(BetConfigFlowState, newVariant(bc))
                pushBack(state)

            of REExperience:
                let toLevelExp = jn[$t]["xpTot"].getInt()
                let currentExp = jn[$t]["xpCur"].getInt()
                let data = (toLevelExp: toLevelExp, currentExp: currentExp)
                let state = newFlowState(ExpirienceFlowState, newVariant(data))
                pushBack(state)

            of REMessages:
                for jmsg in jn["messages"]:
                    let state = newFlowState(ServerMessageFlowState)
                    state.msg = loadMessage(jmsg)
                    pushBack(state)

            of REState, RETutorial:
                let jState = jn[$t]
                if user.clientState.isNil:
                    user.clientState = jState
                else:
                    for k, v in jState:
                        user.clientState[k] = v


            of REExchangeRates:
                user.exchangeNumParts = jn[$t]["cp"].getInt()
                user.exchangeNumChips = jn[$t]["cc"].getInt()

            of REServerTime:
                syncTime(jn[$t].getFloat())
                #info timeSyncInfo()

            of RENextExchangeDiscountTime:
                currentUser().nextExchangeDiscountTime = jn[$t].getFloat()

            of RECollectConfig:
                applyCollectConfig(jn[$t])
                pushBack(CollectConfigFlowState)

            of REFreeRounds:
                jn[$t].updateFeatureForMultipleZones()

            of REFreeRoundsFinished:
                let zone = findZone($jn[$t].getStr())
                let feature = zone.feature.SlotFeature
                if feature.totalRounds == feature.passedRounds:
                    let state = OpenFreeRoundsResultWindowFlowState.newFlowState()
                    state.zone = newVariant(zone)
                    state.pushBack()

            else:
                discard
