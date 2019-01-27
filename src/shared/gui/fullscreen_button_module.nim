import gui_module, gui_module_types
import nimx / [matrixes, animation, control, window, app, notification_center]
import rod / node
import rod / component / ui_component
import shared / game_scene
import utils / falcon_analytics


type FullscreenButtonModule* = ref object of GUIModule
    button*: MultiAnimatedButton


proc createFullscreenButton*(parent: Node): FullscreenButtonModule =
    result.new()
    result.moduleType = mtFullscreenButton
    result.rootNode = newLocalizedNodeWithResource("common/gui/precomps/full_screen_button.json")
    parent.addChild(result.rootNode)

    let toFullScreen = result.rootNode.animationNamed("to_full_screen")
    let toWindowScreen = result.rootNode.animationNamed("to_window_screen")

    let button = result.createMultiAnimatedButton([toFullScreen, toWindowScreen], 110, 110, "fullscreen_button", 10, 10)
    button.onAction do():    
        case button.index:
            of 0:
                mainApplication().keyWindow().fullscreen = true

                button.rootNode.sceneView.GameScene.setTimeout(toFullScreen.loopDuration + 0.1)  do():
                    if mainApplication().keyWindow().fullscreen:
                        sharedAnalytics().fullscreenbutton_inout("enter", parent.sceneView.name)
                    else:
                        sharedAnalytics().fullscreenbutton_inout("enter_error", parent.sceneView.name)
                        button.playIndex(1)
            of 1:
                mainApplication().keyWindow().fullscreen = false

                button.rootNode.sceneView.GameScene.setTimeout(toWindowScreen.loopDuration + 0.1)  do():
                    if not mainApplication().keyWindow().fullscreen:
                        sharedAnalytics().fullscreenbutton_inout("exit", parent.sceneView.name)
                    else:
                        sharedAnalytics().fullscreenbutton_inout("exit_error", parent.sceneView.name)
                        button.playIndex(0)
            else:
                discard

    if mainApplication().keyWindow().fullscreen:
        button.playIndex(0)

    let scene = result.rootNode.sceneView.GameScene
    sharedNotificationCenter().addObserver("WINDOW_FULLSCREEN_HAS_BEEN_CHANGED", scene) do(args: Variant):
        let vals = args.get(tuple[window: Window, fullscreen: bool])
        if not vals.fullscreen and button.index == 1:
            mainApplication().keyWindow().fullscreen = false
            button.playIndex(1)

    result.button = button
