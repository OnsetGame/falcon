import sequtils
import shafa / game / [ vip_types, reward_types ]
import json

export vip_types


var vp: VipConfig

proc sharedVipConfig*(): VipConfig =
    if vp.isNil:
        vp = VipConfig.new()
        vp.pointsPerBucks = 0
        vp.levels = @[]
    return vp


proc getLevel*(config: VipConfig, level: Natural): VipLevel =
    if config.levels.len <= level:
        return VipLevel()
    result = config.levels[level]


proc len*(config: VipConfig): Natural =
    config.levels.len


proc filterVipRewards*(rewards: seq[Reward]): seq[Reward] =
    rewards.filter(proc(x: Reward): bool = x.kind != RewardKind.gifts)