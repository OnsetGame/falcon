import button_feature
import core / [zone, notification_center]
import core / features / exchange_feature
import rod / node

import shared / [game_scene, localization_manager]
import shared / window / [window_manager, exchange_window]


type ButtonExchange* = ref object of ButtonFeature


method onInit*(bf: ButtonExchange) =
    bf.icon = "Exchange"
    bf.title = localizedString("GUI_EXCHANGE_BUTTON")
    bf.zone = "bank"


method onCreate*(bf: ButtonExchange) =
    let zone = findZone(bf.zone)
    let feature = zone.feature.ExchangeFeature
    let scene = bf.rootNode.sceneView.GameScene

    proc update() =
        if not zone.isActive():
            bf.hideHint()
            bf.disable()
            return

        bf.enable()

        if feature.hasDiscountedExchange:
            bf.hint("50%\nOFF")
        else:
            bf.hideHint()

    feature.subscribe(scene, update)
    update()

    bf.onAction = proc(enabled: bool) =
        if enabled:
            bf.playClick()
            let win = sharedWindowManager().show(ExchangeWindow)
            win.source = bf.source
            win.analytics(win.source)

    bf.rootNode.addObserver("QUEST_COMPLETED", bf) do(arg: Variant):
        update()


template newButtonExchange*(parent: Node): ButtonExchange =
    ButtonExchange.new(parent)