import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Abstract input events (ADR 9). The source binds two independent Unity
// event streams per button: OnInputA (a completed tap, fires on release
// regardless of how long the button was held) and OnInputADown/OnInputAUp
// (the raw press/release pair). Both streams are used at real call sites
// (InputA: 14, InputADown/Up: 5 each; InputLeft: 11, Down/Up: 7 each), so
// both are reproduced. Order isn't specified anywhere in the source itself;
// Unity's EventSystem raises PointerUp before Click for the same release,
// so the adapter fires Up before the base event on every release. This is
// a decision made during the build, not one of the sixteen wayfinder
// tickets -- flagged here for the same reason ADRs exist.
module Kaisa {
    module Input {
        const EVT_A = 0;
        const EVT_A_DOWN = 1;
        const EVT_A_UP = 2;
        const EVT_B = 3;
        const EVT_B_DOWN = 4;
        const EVT_B_UP = 5;
        const EVT_LEFT = 6;
        const EVT_LEFT_DOWN = 7;
        const EVT_LEFT_UP = 8;
        const EVT_RIGHT = 9;
        const EVT_RIGHT_DOWN = 10;
        const EVT_RIGHT_UP = 11;

        function eventName(e as Number) as String {
            if (e == EVT_A) { return "A"; }
            if (e == EVT_A_DOWN) { return "A_DOWN"; }
            if (e == EVT_A_UP) { return "A_UP"; }
            if (e == EVT_B) { return "B"; }
            if (e == EVT_B_DOWN) { return "B_DOWN"; }
            if (e == EVT_B_UP) { return "B_UP"; }
            if (e == EVT_LEFT) { return "LEFT"; }
            if (e == EVT_LEFT_DOWN) { return "LEFT_DOWN"; }
            if (e == EVT_LEFT_UP) { return "LEFT_UP"; }
            if (e == EVT_RIGHT) { return "RIGHT"; }
            if (e == EVT_RIGHT_DOWN) { return "RIGHT_DOWN"; }
            if (e == EVT_RIGHT_UP) { return "RIGHT_UP"; }
            return "?";
        }
    }
}

// Feeds an event queue the 20 fps loop drains once per tick (ADR 9): this
// gives the logic layer a deterministic per-frame ordering, since Connect IQ
// delivers input on a path independent of the render timer.
class InputQueue {
    var _q as Array<Number> = [];

    function push(e as Number) as Void {
        _q.add(e);
    }

    function drain() as Array<Number> {
        var out = _q;
        _q = [];
        return out;
    }
}

// ADR 9 + ticket 13: KEY_ENTER -> A, KEY_ESC -> B (native press/release).
// The left/right screen halves, held, carry Left/Right via onDrag -- and
// per ticket 13's spike, touch-down is `onDrag START` OR `onHold`,
// whichever arrives first (a perfectly still touch produces no drag event
// at all, only a late onHold), and touch-up is `onDrag STOP` OR
// `onRelease`. onSwipe is consumed and discarded. Exit is timed from a long
// press of KEY_ESC, since onBack fires on release rather than during the
// hold.
class InputDelegate extends WatchUi.BehaviorDelegate {
    const HALF_X = 227;             // canvas is 320 wide, centred in 454
    const EXIT_HOLD_MS = 1500;

    var _queue as InputQueue;
    var _escDownAt as Number = 0;
    var _touchDownHalf as Number = -1;   // -1 = up, 0 = left, 1 = right

    function initialize(queue as InputQueue) {
        BehaviorDelegate.initialize();
        _queue = queue;
    }

    function halfOf(x as Number) as Number {
        return (x < HALF_X) ? 0 : 1;
    }

    function touchDown(half as Number) as Void {
        if (_touchDownHalf == half) { return; }
        touchUp();
        _touchDownHalf = half;
        _queue.push((half == 0) ? Kaisa.Input.EVT_LEFT_DOWN : Kaisa.Input.EVT_RIGHT_DOWN);
    }

    function touchUp() as Void {
        if (_touchDownHalf == -1) { return; }
        _queue.push((_touchDownHalf == 0) ? Kaisa.Input.EVT_LEFT_UP : Kaisa.Input.EVT_RIGHT_UP);
        _queue.push((_touchDownHalf == 0) ? Kaisa.Input.EVT_LEFT : Kaisa.Input.EVT_RIGHT);
        _touchDownHalf = -1;
    }

    function onKeyPressed(e as WatchUi.KeyEvent) as Boolean {
        var k = e.getKey();
        if (k == WatchUi.KEY_ENTER) {
            _queue.push(Kaisa.Input.EVT_A_DOWN);
            return true;
        }
        if (k == WatchUi.KEY_ESC) {
            _escDownAt = System.getTimer();
            _queue.push(Kaisa.Input.EVT_B_DOWN);
            return true;
        }
        return false;
    }

    function onKeyReleased(e as WatchUi.KeyEvent) as Boolean {
        var k = e.getKey();
        if (k == WatchUi.KEY_ENTER) {
            _queue.push(Kaisa.Input.EVT_A_UP);
            _queue.push(Kaisa.Input.EVT_A);
            return true;
        }
        if (k == WatchUi.KEY_ESC) {
            var held = System.getTimer() - _escDownAt;
            _queue.push(Kaisa.Input.EVT_B_UP);
            _queue.push(Kaisa.Input.EVT_B);
            if (held >= EXIT_HOLD_MS) {
                System.exit();
            }
            return true;
        }
        return false;
    }

    function onDrag(e as WatchUi.DragEvent) as Boolean {
        var c = e.getCoordinates();
        var t = e.getType();
        var half = halfOf(c[0]);
        if (t == WatchUi.DRAG_TYPE_START) {
            touchDown(half);
        } else if (t == WatchUi.DRAG_TYPE_CONTINUE) {
            if (_touchDownHalf == -1) {
                touchDown(half);       // START was missed (still touch + jitter)
            } else if (half != _touchDownHalf) {
                touchDown(half);       // crossed the midpoint
            }
        } else if (t == WatchUi.DRAG_TYPE_STOP) {
            touchUp();
        }
        return true;
    }

    function onHold(e as WatchUi.ClickEvent) as Boolean {
        // fallback for a perfectly still touch: no onDrag ever fires for it
        var c = e.getCoordinates();
        touchDown(halfOf(c[0]));
        return true;
    }

    function onRelease(e as WatchUi.ClickEvent) as Boolean {
        touchUp();
        return true;
    }

    function onSwipe(e as WatchUi.SwipeEvent) as Boolean {
        return true;   // consumed: the drag stream already saw this gesture
    }

    function onBack() as Boolean {
        return true;    // consumed: prevents exit: (ticket 13, confirmed on device)
    }

    function onSelect() as Boolean {
        return true;
    }
}
