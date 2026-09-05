import Toybox.Application;
import Toybox.WatchUi;

class InputProbeApp extends Application.AppBase {
    function initialize() { AppBase.initialize(); }
    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var v = new InputProbeView();
        return [v, new InputProbeDelegate(v)];
    }
}
