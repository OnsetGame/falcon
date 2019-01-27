import nimx.view, nimx.timer, nimx.class_registry, nimx.context, nimx.animation
import rod.viewport, rod.node, rod.component

import shared.director, shared.game_scene
import utils.helpers

import screens.splash_screen


type LogoScreen* = ref object of SplashScreen

method name*(ss: LogoScreen): string = "LogoScreen"

method initAfterResourcesLoaded*(ss:LogoScreen) =
    ss.rootNode.addChild(newNodeWithResource("splash_screen/precomps/logo_screen.json"))

registerClass(LogoScreen)
