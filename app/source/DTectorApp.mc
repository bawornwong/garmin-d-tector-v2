import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class DTectorApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var view = new DTectorView();
        var queue = new InputQueue();
        var delegate = new InputDelegate(queue);
        view.setQueue(queue);
        return [view, delegate];
    }
}
