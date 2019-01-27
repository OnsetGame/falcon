import shared.window / [ window_manager, window_component, alert_window, button_component, old_client_window, maintenance_window ]
import shared / [ director, message_box, localization_manager, deep_links ]
import utils.falcon_analytics

import nimx.notification_center

proc showErrorAlert(title, desc: string) =
    if currentDirector().currentScene.isNil:
        # TODO We should not call this code, will remove
        showMessageBox(localizedString(title), localizedString(desc), MessageBoxType.Error) do():
            sharedNotificationCenter().postNotification("HAVE_TO_RESTART_APP")
    else:
        let alert = sharedWindowManager().showAlert(AlertWindow)
        alert.setup do():
            alert.setUpBttnOkTitle("ALERT_BTTN_RETRY")
            alert.setUpTitle(title)
            alert.setUpDescription(desc)
            alert.makeOneButton()
            alert.removeCloseButton()
            alert.buttonOk.onAction do():
                sharedNotificationCenter().postNotification("HAVE_TO_RESTART_APP")

proc showLostConnectionAlert*() =
    sharedAnalytics().wnd_connect_lost_show()
    showErrorAlert("ALERT_LOST_CONECTION", "ALERT_LOST_CONECTION_DESC")

proc showResourceLoadingAlert*() =
    sharedAnalytics().wnd_resource_problem()
    showErrorAlert("ALERT_RESOURCE_LOAD_PROBLEM", "ALERT_RESOURCE_LOAD_PROBLEM_DESC")


proc showUpgradeClientAlert*() =
    sharedAnalytics().wnd_upgrade_client()
    discard sharedWindowManager().showAlert(OldClientWindow)

proc showMaintenanceAlert*(timeout: float) =
    var w = sharedWindowManager().currentWindow
    if w.isNil or not (w of MaintenanceWindow):
        # sharedAnalytics().wnd_upgrade_client()
        w = sharedWindowManager().showAlert(MaintenanceWindow)
    w.MaintenanceWindow.updateTimeout(timeout)

proc setupAlertHandlers*() =
    sharedNotificationCenter().addObserver("CLIENT_VERSION_TOO_LOW", 1) do(args: Variant):
        showUpgradeClientAlert()

    sharedNotificationCenter().addObserver("MAINTENANCE_IN_PROGRESS", 1) do(args: Variant):
        showMaintenanceAlert(args.get(float))

    sharedNotificationCenter().removeObserver("SHOW_LOST_CONNECTION_ALERT")
    sharedNotificationCenter().addObserver("SHOW_LOST_CONNECTION_ALERT", 1) do(args: Variant):
        showLostConnectionAlert()

    sharedNotificationCenter().removeObserver("SHOW_RESOURCE_LOADING_ALERT")
    sharedNotificationCenter().addObserver("SHOW_RESOURCE_LOADING_ALERT", 1) do(args: Variant):
        showResourceLoadingAlert()