import times, sequtils, json
import nimx / animation
import core / zone
import shared / game_scene
import core / notification_center
import quest / quests


type IncomeFeature* = ref object of Feature
    currency: Currency

method updateState*(f: IncomeFeature, jn: JsonNode) =
    f.dispatchActions()

method onInit(f: IncomeFeature, zone: Zone) =
    sharedNotificationCenter().addObserver("DIRECTOR_ON_SCENE_ADD", f) do(args: Variant):
        let scene = args.get(GameScene)
        let animation = newAnimation()
        animation.loopDuration = 0.3
        animation.numberOfLoops = -1
        animation.onAnimate = proc(p: float) =
            f.updateState(newJObject())
        scene.addAnimation(animation)

proc newIncomeBucksFeature*(): Feature =
    let res = IncomeFeature()
    res.currency = Currency.Bucks
    result = res

proc newIncomeChipsFeature*(): Feature =
    let res = IncomeFeature()
    res.currency = Currency.Chips
    result = res

addFeature(IncomeBucks, newIncomeBucksFeature)
addFeature(IncomeChips, newIncomeChipsFeature)