import variant
import shared / game_scene
export game_scene


type OpenQuestBalloonAction* = ref object of GameSceneAction
type OpenQuestCardAction* = ref object of GameSceneAction
type OpenZoneInfoCardAction* = ref object of GameSceneAction
type TryToStartQuestAction* = ref object of GameSceneAction
type TryToSpeedupQuestAction* = ref object of GameSceneAction
type TryToCompleteQuestAction* = ref object of GameSceneAction
type TryToGetRewardsQuestAction* = ref object of GameSceneAction
type OpenQuestsWindowWithZone* = ref object of GameSceneAction
type OpenFeatureWindowWithZone* = ref object of GameSceneAction
type PlaySlotWithZone* = ref object of GameSceneAction
type CollectResourcesAction* = ref object of GameSceneAction
type UpdateQuestsAction* = ref object of GameSceneAction
type ZoomToZoneAction* = ref object of GameSceneAction
type ZoomToQuestAction* = ref object of GameSceneAction
