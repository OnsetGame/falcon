import json, algorithm
import falconserver / quest / [ quest_types ]
import falconserver.auth.profile_types
import strutils
import shared / localization_manager
import utils / helpers
import shafa / game / reward_types
export reward_types


type RewardWindowBoxKind* {.pure.} = enum
    blue
    gold
    grey
    red


proc isPercentCount*(r: Reward): bool = 
    r.kind in [RewardKind.bucksPurchaseBonus, RewardKind.chipsPurchaseBonus, RewardKind.exchange]


proc isBonus*(r: Reward): bool =
    r.kind in @[RewardKind.incomeChips, RewardKind.incomeBucks, RewardKind.maxBet, RewardKind.boosterExp, RewardKind.boosterIncome, RewardKind.boosterTourPoints]
    

proc prioritizedRewards*(rewards: seq[Reward]): seq[Reward] =
    let priority = [RewardKind.exp, RewardKind.tourPoints, RewardKind.chips, RewardKind.parts, RewardKind.bucks]
    result = rewards.sorted do(a, b: Reward) -> int:
        cmp(priority.find(a.kind), priority.find(b.kind))


proc icon*(r: Reward): string =
    case r.kind:
        of RewardKind.bucks:
            result = "bucks"
        of RewardKind.chips:
            result = "chips"
        of RewardKind.parts:
            result = "parts"
        of RewardKind.tourPoints:
            result = "tourPoints"
        of RewardKind.exp:
            result = "citypoints"
        of RewardKind.maxBet:
            result = "maxBet"
        of RewardKind.incomeChips:
            result = "incomeChips"
        of RewardKind.incomeBucks:
            result = "incomeBucks"

        of RewardKind.boosterExp:
            result = "boosterExp"
        of RewardKind.boosterIncome:
            result = "boosterIncome"
        of RewardKind.boosterTourPoints:
            result = "boosterTourPoints"

        of RewardKind.bucksPurchaseBonus:
            result = "bucksPurchaseBonus"
        of RewardKind.chipsPurchaseBonus:
            result = "chipsPurchaseBonus"
        of RewardKind.exchange:
            result = "exchangeDiscount"
        of RewardKind.wheel:
            result = "fortuneWheelSpin"

        of RewardKind.freeRounds:
            result = "freeRounds"

        else:
            result = $r.kind


proc localizedName*(r: Reward): string =
    case r.kind:
        of RewardKind.bucks:
            localizedString("OOM_BUCKS")
        of RewardKind.chips:
            localizedString("OOM_CHIPS")
        of RewardKind.parts:
            localizedString("OOM_PARTS")
        of RewardKind.tourPoints:
            localizedString("OOM_TOURNAMENT_POINTS")
        of RewardKind.exp:
            localizedString("PI_CITY_POINTS")
        of RewardKind.maxBet:
            localizedString("OOM_MAX_BET")
        of RewardKind.incomeChips:
            localizedString("OOM_INCOME")
        of RewardKind.incomeBucks:
            localizedString("OOM_INCOME")

        of RewardKind.boosterExp:
            localizedString("OOM_BOOSTER_EXP")
        of RewardKind.boosterIncome:
            localizedString("OOM_BOOSTER_INCOME")
        of RewardKind.boosterTourPoints:
            localizedString("OOM_BOOSTER_TP")

        of RewardKind.bucksPurchaseBonus:
            localizedString("REWARD_PURCHASE_BONUS")
        of RewardKind.chipsPurchaseBonus:
            localizedString("REWARD_PURCHASE_BONUS")
        of RewardKind.exchange:
            localizedString("REWARD_EXCHANGE_BOUS")
        of RewardKind.wheel:
            localizedString("REWARD_FREE_SPINS")

        of RewardKind.freeRounds:
            localizedString("REWARD_FREE_ROUNDS")
        
        of RewardKind.vipaccess:
            localizedString("VIP_ACCESS")

        else:
            "Other item"

proc localizedCount*(reward: Reward, minimized: bool = false): string =
    if reward.isBooster():
        if reward.amount >= 3600 * 24:
            let days = reward.amount div (3600 * 24)
            if days == 1:
                result = localizedFormat("TIMER_DAY_ONLY", $days)
            else:
                result = localizedFormat("TIMER_DAYS_ONLY", $days)
        else:
            let hours = reward.amount div 3600
            if hours == 1:
                result = localizedFormat("TIMER_HOUR_ONLY", $hours)
            else:
                result = localizedFormat("TIMER_HOURS_ONLY", $hours)

    elif reward.isIncome():
        result = formatThousands(reward.amount) & " " & localizedString("OOM_PER_HOUR")
    elif reward.isPercentCount():
        result = $reward.amount & "%"
    elif reward.kind == RewardKind.wheel:
        if reward.amount == 1:
            result = localizedFormat("WHEEL_1_SPIN", $reward.amount)
        else:
            result = localizedFormat("WHEEL_N_SPINS", $reward.amount)
    elif reward.kind == RewardKind.freeRounds:
        result = formatThousands(reward.amount)
    elif reward.kind == RewardKind.vipaccess:
        result = ""
    else:
        if minimized:
            if reward.amount >= 1_000_000_000:
                result = $(reward.amount div 1_000_000_000) & "B"
            elif reward.amount >= 1_000_000:
                result = $(reward.amount div 1_000_000) & "M"
            elif reward.amount >= 1_000:
                result = $(reward.amount div 1_000) & "K"
            else:
                result = formatThousands(reward.amount)
        else:
            result = formatThousands(reward.amount)
