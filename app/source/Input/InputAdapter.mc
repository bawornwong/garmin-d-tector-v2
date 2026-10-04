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
        // Not one of the original's twelve: a debug-only shortcut that walks
        // the journey along without a walk, for testing on the simulator.
        const EVT_WALK = 12;

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
            if (e == EVT_WALK) { return "WALK"; }
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

// ADR 9 + ticket 13, with the mapping the user chose:
//
//   left / right / bottom / top touch sectors       Left / Right / A / B
//   the upper button                                         A
//   the lower button                                         B
//
// The original's buttons deliver two streams per press -- a completed tap and
// the raw down/up pair -- and both are used, so every gesture here delivers
// both. The zone is chosen at touch-down and stays fixed until release,
// including when a finger drifts into another zone. Holding the side zones
// supports auto-repeat (CodeInput, Database); holding the bottom supports A
// actions such as Finder's search. Swipes have no directional mapping.
//
// Per ticket 13's spike, touch-down is `onDrag START` OR `onHold`, whichever
// arrives first (a perfectly still touch produces no drag event at all, only a
// late onHold), and touch-up is `onDrag STOP` OR `onRelease`. A short, still
// touch arrives as `onTap` on release. Exit timing uses the lower key's raw
// press/release pair.
class InputDelegate extends WatchUi.InputDelegate {
    // Four sectors meet at the display centre. Diagonal boundaries put the
    // cardinal directions in the middle of their sectors, as in the diagram.
    const TOUCH_CENTRE = 227;       // 454 / 2
    const EXIT_HOLD_MS = 1500;

    const REGION_NONE = -1;
    const REGION_LEFT = 0;
    const REGION_RIGHT = 1;
    const REGION_BOTTOM = 2;
    const REGION_TOP = 3;

    var _queue as InputQueue;
    var _escDownAt as Number = 0;
    var _region as Number = REGION_NONE;    // the region the finger went down in

    function initialize(queue as InputQueue) {
        WatchUi.InputDelegate.initialize();
        _queue = queue;
    }

    function regionOf(x as Number, y as Number) as Number {
        var dx = x - TOUCH_CENTRE;
        var dy = y - TOUCH_CENTRE;
        if (dx.abs() > dy.abs()) {
            return dx < 0 ? REGION_LEFT : REGION_RIGHT;
        }
        return dy < 0 ? REGION_TOP : REGION_BOTTOM;
    }

    function downEvent(region as Number) as Number {
        if (region == REGION_LEFT) { return Kaisa.Input.EVT_LEFT_DOWN; }
        if (region == REGION_RIGHT) { return Kaisa.Input.EVT_RIGHT_DOWN; }
        if (region == REGION_TOP) { return Kaisa.Input.EVT_B_DOWN; }
        return Kaisa.Input.EVT_A_DOWN;
    }

    function upEvent(region as Number) as Number {
        if (region == REGION_LEFT) { return Kaisa.Input.EVT_LEFT_UP; }
        if (region == REGION_RIGHT) { return Kaisa.Input.EVT_RIGHT_UP; }
        if (region == REGION_TOP) { return Kaisa.Input.EVT_B_UP; }
        return Kaisa.Input.EVT_A_UP;
    }

    function tapEvent(region as Number) as Number {
        if (region == REGION_LEFT) { return Kaisa.Input.EVT_LEFT; }
        if (region == REGION_RIGHT) { return Kaisa.Input.EVT_RIGHT; }
        if (region == REGION_TOP) { return Kaisa.Input.EVT_B; }
        return Kaisa.Input.EVT_A;
    }

    function touchDown(x as Number, y as Number) as Void {
        if (_region != REGION_NONE) { return; }
        _region = regionOf(x, y);
        _queue.push(downEvent(_region));
    }

    // Release the original zone exactly once, even if both STOP and RELEASE
    // are delivered for the same touch.
    function touchUp() as Void {
        if (_region == REGION_NONE) { return; }
        var region = _region;
        _region = REGION_NONE;
        _queue.push(upEvent(region));
        _queue.push(tapEvent(region));
    }

    function onKeyPressed(e as WatchUi.KeyEvent) as Boolean {
        var k = e.getKey();
        logKey("pressed", k);
        // The simulator's keyboard, which the watch itself has no equivalent
        // of: the arrow keys stand in for the side zones, and any other key walks
        // (the fifty steps a tester does not want to take).
        if (k == WatchUi.KEY_LEFT) {
            _queue.push(Kaisa.Input.EVT_LEFT_DOWN);
            return true;
        }
        if (k == WatchUi.KEY_RIGHT) {
            _queue.push(Kaisa.Input.EVT_RIGHT_DOWN);
            return true;
        }
        if (keyWalks(k)) {
            _queue.push(Kaisa.Input.EVT_WALK);
            return true;
        }
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

    // Whichever key the simulator sends for the space bar -- it is not one of
    // the named constants, so the walk answers to any key that is not already
    // spoken for, and prints what it was.
    (:debug)
    function logKey(what as String, k as Number) as Void {
        System.println("KEYEVENT " + what + "=" + k
            + " [enter=" + WatchUi.KEY_ENTER + " esc=" + WatchUi.KEY_ESC
            + " left=" + WatchUi.KEY_LEFT + " right=" + WatchUi.KEY_RIGHT
            + " up=" + WatchUi.KEY_UP + " down=" + WatchUi.KEY_DOWN
            + " menu=" + WatchUi.KEY_MENU + "]");
    }

    (:release)
    function logKey(what as String, k as Number) as Void {
    }

    (:debug)
    function logGesture(what as String) as Void {
        System.println("INPUTEVENT " + what);
    }

    (:release)
    function logGesture(what as String) as Void {
    }

    (:debug)
    function keyWalks(k as Number) as Boolean {
        if (k == WatchUi.KEY_ENTER || k == WatchUi.KEY_ESC
                || k == WatchUi.KEY_LEFT || k == WatchUi.KEY_RIGHT) {
            return false;
        }
        System.println("KEY " + k + " -> walk");
        return true;
    }

    (:release)
    function keyWalks(k as Number) as Boolean {
        return false;
    }

    function onKeyReleased(e as WatchUi.KeyEvent) as Boolean {
        var k = e.getKey();
        logKey("released", k);
        if (k == WatchUi.KEY_LEFT) {
            _queue.push(Kaisa.Input.EVT_LEFT_UP);
            _queue.push(Kaisa.Input.EVT_LEFT);
            return true;
        }
        if (k == WatchUi.KEY_RIGHT) {
            _queue.push(Kaisa.Input.EVT_RIGHT_UP);
            _queue.push(Kaisa.Input.EVT_RIGHT);
            return true;
        }
        if (keyWalks(k)) { return true; }
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

    // InputDelegate also receives the completed key event after the raw
    // press/release pair. Consume Back here: leaving it unhandled makes the
    // system pop the view after a single press, before the view can apply its
    // two-press exit rule. The game event is queued by onKeyReleased only.
    function onKey(e as WatchUi.KeyEvent) as Boolean {
        var k = e.getKey();
        logKey("complete", k);
        return k == WatchUi.KEY_ESC || k == WatchUi.KEY_ENTER
            || k == WatchUi.KEY_LEFT || k == WatchUi.KEY_RIGHT;
    }

    function onBack() as Boolean {
        logGesture("back");
        return true;
    }

    function onDrag(e as WatchUi.DragEvent) as Boolean {
        var c = e.getCoordinates();
        var t = e.getType();
        logGesture("drag type=" + t + " at " + c[0] + "," + c[1]);
        if (t == WatchUi.DRAG_TYPE_START) {
            touchDown(c[0], c[1]);
        } else if (t == WatchUi.DRAG_TYPE_CONTINUE) {
            if (_region == REGION_NONE) {
                touchDown(c[0], c[1]);      // START was missed (still touch + jitter)
            }
        } else if (t == WatchUi.DRAG_TYPE_STOP) {
            touchUp();
        }
        return true;
    }

    function onHold(e as WatchUi.ClickEvent) as Boolean {
        logGesture("hold at " + e.getCoordinates()[0]);
        // fallback for a perfectly still touch: no onDrag ever fires for it
        var c = e.getCoordinates();
        touchDown(c[0], c[1]);
        return true;
    }

    function onRelease(e as WatchUi.ClickEvent) as Boolean {
        logGesture("release at " + e.getCoordinates()[0]);
        touchUp();
        return true;
    }

    function onTap(e as WatchUi.ClickEvent) as Boolean {
        logGesture("tap at " + e.getCoordinates()[0] + "," + e.getCoordinates()[1]);
        // A tap the drag stream never saw -- some taps arrive as nothing else.
        if (_region != REGION_NONE) { return true; }
        var c = e.getCoordinates();
        touchDown(c[0], c[1]);
        touchUp();
        return true;
    }

    function onSwipe(e as WatchUi.SwipeEvent) as Boolean {
        // A swipe-only callback has no touch coordinates. Consume it without
        // inventing a Left/Right press; the touch stream owns zone input.
        logGesture("swipe ignored");
        return true;
    }

}
