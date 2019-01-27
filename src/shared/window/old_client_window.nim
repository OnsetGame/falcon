import rod / component
import shared / window / [window_component, window_manager, alert_window, button_component]
import core / notification_center


when defined(android):
    import jnim
    import nimx.utils.android

    jclass com.onsetgame.reelvalley.MainActivity of JVMObject:
        proc goForRatingApp()

    proc upgrade() =
        let act = cast[MainActivity](mainActivity())
        act.goForRatingApp()
        quit(0)
elif defined(emscripten):
    proc upgrade() =
        sharedNotificationCenter().postNotification("HAVE_TO_RESTART_APP")
else:
    proc upgrade() =
        quit(0)


type OldClientWindow* = ref object of AlertWindow


method onInit(w: OldClientWindow) =
    procCall w.AlertWindow.onInit()

    w.removeCloseButton()
    w.makeOneButton()
    w.setUpTitle("ALERT_CLIENT_VERSION_TOO_LOW_TITLE")
    w.setUpDescription("ALERT_CLIENT_VERSION_TOO_LOW_DESC")
    w.setUpBttnOkTitle("ALERT_CLIENT_VERSION_TOO_LOW_BTTN")
    w.buttonOk.onAction do():
        upgrade()


registerComponent(OldClientWindow, "windows")