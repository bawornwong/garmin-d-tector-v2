import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Ticket 13. Logs every input event with a timestamp so the five open
// questions from the input research can be answered from the trace rather
// than from documentation:
//   1. does DRAG_TYPE_STOP always fire when the finger lifts?
//   2. does Venu 4 reserve a long press of KEY_ESC for the system?
//   3. does holding a host key give one down/up pair, or OS-rate repeats?
//   4. does swipeLeft reach the app raw, being unbound by the system?
//   5. does consuming onBack actually stop the app exiting?
class InputProbeDelegate extends WatchUi.BehaviorDelegate {
    var _view as InputProbeView;
    var _keyDownAt as Dictionary<Number, Number> = {};

    function initialize(v as InputProbeView) {
        BehaviorDelegate.initialize();
        _view = v;
    }

    function log(s as String) as Void {
        System.println(System.getTimer() + " " + s);
        _view.note(s);
    }

    function keyName(k as Number) as String {
        if (k == WatchUi.KEY_ENTER) { return "KEY_ENTER"; }
        if (k == WatchUi.KEY_ESC) { return "KEY_ESC"; }
        if (k == WatchUi.KEY_MENU) { return "KEY_MENU"; }
        if (k == WatchUi.KEY_UP) { return "KEY_UP"; }
        if (k == WatchUi.KEY_DOWN) { return "KEY_DOWN"; }
        return "KEY_" + k;
    }

    function onKeyPressed(e as KeyEvent) as Boolean {
        var k = e.getKey();
        _keyDownAt[k] = System.getTimer();
        log("onKeyPressed " + keyName(k));
        return true;
    }

    function onKeyReleased(e as KeyEvent) as Boolean {
        var k = e.getKey();
        var held = _keyDownAt.hasKey(k) ? (System.getTimer() - _keyDownAt[k]) : -1;
        log("onKeyReleased " + keyName(k) + " heldMs=" + held);
        return true;
    }

    function onKey(e as KeyEvent) as Boolean {
        log("onKey " + keyName(e.getKey()));
        return true;
    }

    function onTap(e as ClickEvent) as Boolean {
        var c = e.getCoordinates();
        log("onTap (" + c[0] + "," + c[1] + ")");
        return true;
    }

    function onHold(e as ClickEvent) as Boolean {
        var c = e.getCoordinates();
        log("onHold (" + c[0] + "," + c[1] + ")");
        return true;
    }

    function onRelease(e as ClickEvent) as Boolean {
        var c = e.getCoordinates();
        log("onRelease (" + c[0] + "," + c[1] + ")");
        return true;
    }

    function onDrag(e as DragEvent) as Boolean {
        var c = e.getCoordinates();
        var t = e.getType();
        var n = (t == WatchUi.DRAG_TYPE_START) ? "START"
              : (t == WatchUi.DRAG_TYPE_CONTINUE) ? "CONTINUE"
              : (t == WatchUi.DRAG_TYPE_STOP) ? "STOP" : ("" + t);
        log("onDrag " + n + " (" + c[0] + "," + c[1] + ") half=" +
            (c[0] < 227 ? "LEFT" : "RIGHT"));
        return true;
    }

    function onSwipe(e as SwipeEvent) as Boolean {
        var d = e.getDirection();
        var n = (d == WatchUi.SWIPE_LEFT) ? "LEFT"
              : (d == WatchUi.SWIPE_RIGHT) ? "RIGHT"
              : (d == WatchUi.SWIPE_UP) ? "UP"
              : (d == WatchUi.SWIPE_DOWN) ? "DOWN" : ("" + d);
        log("onSwipe " + n);
        return true;
    }

    // consuming these is what keeps the app from exiting
    function onBack() as Boolean { log("onBack (consumed)"); return true; }
    function onSelect() as Boolean { log("onSelect"); return true; }
    function onMenu() as Boolean { log("onMenu <- unreachable on Venu 4?"); return true; }
    function onNextPage() as Boolean { log("onNextPage"); return true; }
    function onPreviousPage() as Boolean { log("onPreviousPage"); return true; }
}
