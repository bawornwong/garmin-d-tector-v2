import Toybox.Application;
import Toybox.Lang;
import Toybox.Notifications;
import Toybox.WatchUi;

class DTectorApp extends Application.AppBase {
    var _view as DTectorView?;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
    }

    function getServiceDelegate() as [Toybox.System.ServiceDelegate] {
        return [new StepBackground()];
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var view = new DTectorView();
        _view = view;
        if (!view.isProbeMode()) {
            StepBackgroundSchedule.apply();
        }
        Notifications.registerForNotificationMessages(method(:onNotification));
        var queue = new InputQueue();
        var delegate = new InputDelegate(queue);
        view.setQueue(queue);
        return [view, delegate];
    }

    function onNotification(message as Notifications.NotificationMessage) as Void {
        if (_view != null) { _view.requestStepRefresh(); }
    }

    function onStorageChanged() as Void {
        if (_view != null) { _view.requestStepRefresh(); }
    }

    function onStop(state as Dictionary?) as Void {
        if (_view != null) { _view.flushAndReleaseSteps(); }
    }
}
