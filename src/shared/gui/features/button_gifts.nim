import button_feature
import core / [zone, notification_center]
import rod / node

import shared / [game_scene, localization_manager]
import shared / window / social / social_window

import core / features / gifts_feature


type ButtonGifts* = ref object of ButtonFeature


method onInit*(bf: ButtonGifts) =
    bf.icon = "Gift"
    bf.title = localizedString("GUI_GIFTS_BUTTON")
    bf.zone = "zeppelin"
    

method onCreate*(bf: ButtonGifts) =
    let zone = findZone(bf.zone)
    let feature = zone.feature.GiftsFeature
    let scene = bf.rootNode.sceneView.GameScene

    proc update() =
        if not zone.isActive():
            bf.hideHint()
            bf.disable()
            return

        bf.enable()

        if feature.hasGifts:
            bf.hint($feature.giftsCount)
        else:
            bf.hideHint()

    feature.subscribe(scene, update)
    update()

    bf.onAction = proc(enabled: bool) =
        if enabled:
            bf.playClick()
            showSocialWindow(SocialTabType.Gifts, bf.source)
    
    bf.rootNode.addObserver("QUEST_COMPLETED", bf) do(arg: Variant):
        update()


template newButtonGifts*(parent: Node): ButtonGifts =
    ButtonGifts.new(parent)