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
//   swipe left / swipe right   Left / Right
//   a tap anywhere inside the emulated canvas                A
//   the lower button                                         B
//
// The original's buttons deliver two streams per press -- a completed tap and
// the raw down/up pair -- and both are used, so every gesture here delivers
// both. A swipe is instantaneous and delivers DOWN, UP and the tap together,
// which is exactly what a short press of a physical button delivers.
//
// Holding still outside the canvas, on whichever side it fell on, keeps the
// held Left / Right the auto-repeat scrolling needs (CodeInput, Database): a
// swipe is told apart from a hold by how far the finger travelled, so the two
// do not collide. Holding inside the canvas is a held A, which is what the
// Finder's press-and-hold search needs from a touch-only device.
//
// Per ticket 13's spike, touch-down is `onDrag START` OR `onHold`, whichever
// arrives first (a perfectly still touch produces no drag event at all, only a
// late onHold), and touch-up is `onDrag STOP` OR `onRelease`. Exit is timed
// from a long press of the lower button, since onBack fires on release rather
// than during the hold.
class InputDelegate extends WatchUi.BehaviorDelegate {
    const CENTRE_X = 227;           // canvas is 320 wide, centred in 454
    // The canvas itself is the A zone -- the whole 320x320 square the game
    // draws into, not just a box in its middle -- and everything outside it
    // is Left or Right by which half it falls in. Outside the canvas is
    // exactly the touch dead-zone the round bezel already carves out on each
    // side, so no shape beyond this rectangle needs reproducing here.
    const CANVAS_X0 = 67;           // (454 - 320) / 2
    const CANVAS_X1 = 387;          // CANVAS_X0 + 320
    const CANVAS_Y0 = 67;
    const CANVAS_Y1 = 387;
    // How far a finger has to travel horizontally before the gesture is a
    // swipe rather than a press.
    const SWIPE_MIN_DX = 40;
    const EXIT_HOLD_MS = 1500;

    const REGION_NONE = -1;
    const REGION_LEFT = 0;
    const REGION_RIGHT = 1;
    const REGION_CENTRE = 2;

    var _queue as InputQueue;
    var _escDownAt as Number = 0;
    var _region as Number = REGION_NONE;    // the region the finger went down in
    var _downX as Number = 0;
    var _swiped as Boolean = false;

    function initialize(queue as InputQueue) {
        BehaviorDelegate.initialize();
        _queue = queue;
    }

    function regionOf(x as Number, y as Number) as Number {
        if (x >= CANVAS_X0 && x < CANVAS_X1 && y >= CANVAS_Y0 && y < CANVAS_Y1) {
            return REGION_CENTRE;
        }
        return (x < CENTRE_X) ? REGION_LEFT : REGION_RIGHT;
    }

    function downEvent(region as Number) as Number {
        if (region == REGION_LEFT) { return Kaisa.Input.EVT_LEFT_DOWN; }
        if (region == REGION_RIGHT) { return Kaisa.Input.EVT_RIGHT_DOWN; }
        return Kaisa.Input.EVT_A_DOWN;
    }

    function upEvent(region as Number) as Number {
        if (region == REGION_LEFT) { return Kaisa.Input.EVT_LEFT_UP; }
        if (region == REGION_RIGHT) { return Kaisa.Input.EVT_RIGHT_UP; }
        return Kaisa.Input.EVT_A_UP;
    }

    function tapEvent(region as Number) as Number {
        if (region == REGION_LEFT) { return Kaisa.Input.EVT_LEFT; }
        if (region == REGION_RIGHT) { return Kaisa.Input.EVT_RIGHT; }
        return Kaisa.Input.EVT_A;
    }

    function touchDown(x as Number, y as Number) as Void {
        if (_region != REGION_NONE) { return; }
        _region = regionOf(x, y);
        _downX = x;
        _swiped = false;
        _queue.push(downEvent(_region));
    }

    // A press that ended where it started is a press: down, up and the tap.
    // One that travelled is a swipe: the press it began as is released
    // WITHOUT its tap, and the swipe's own three events follow, so a swipe
    // that started on the left but went right is a Right.
    function touchUp() as Void {
        if (_region == REGION_NONE) { return; }
        var region = _region;
        var swiped = _swiped;
        var dx = _lastX - _downX;
        _region = REGION_NONE;
        _swiped = false;

        _queue.push(upEvent(region));
        if (!swiped) {
            _queue.push(tapEvent(region));
            return;
        }
        pushSide((dx < 0) ? Kaisa.Input.EVT_LEFT : Kaisa.Input.EVT_RIGHT);
    }

    // A side gesture as the original's button delivers it: the raw pair and
    // the completed tap.
    function pushSide(tap as Number) as Void {
        if (tap == Kaisa.Input.EVT_LEFT) {
            _queue.push(Kaisa.Input.EVT_LEFT_DOWN);
            _queue.push(Kaisa.Input.EVT_LEFT_UP);
            _queue.push(Kaisa.Input.EVT_LEFT);
        } else {
            _queue.push(Kaisa.Input.EVT_RIGHT_DOWN);
            _queue.push(Kaisa.Input.EVT_RIGHT_UP);
            _queue.push(Kaisa.Input.EVT_RIGHT);
        }
    }

    var _lastX as Number = 0;

    function onKeyPressed(e as WatchUi.KeyEvent) as Boolean {
        var k = e.getKey();
        logKey("pressed", k);
        // The simulator's keyboard, which the watch itself has no equivalent
        // of: the arrow keys stand in for the swipes, and any other key walks
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
            _escKeyDown = true;
            _queue.push(Kaisa.Input.EVT_B_DOWN);
            return true;
        }
        return false;
    }

    // Whether an ESC keypress is in flight, so onBack() below -- which the
    // simulator calls both as a companion to that key AND on its own for a
    // plain click on the device picture's back-button hotspot -- knows
    // whether B has already gone out for this press.
    var _escKeyDown as Boolean = false;

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
            _escKeyDown = false;
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
        logGesture("drag type=" + t + " at " + c[0] + "," + c[1]);
        _lastX = c[0];
        if (t == WatchUi.DRAG_TYPE_START) {
            touchDown(c[0], c[1]);
        } else if (t == WatchUi.DRAG_TYPE_CONTINUE) {
            if (_region == REGION_NONE) {
                touchDown(c[0], c[1]);      // START was missed (still touch + jitter)
            } else if ((c[0] - _downX).abs() >= SWIPE_MIN_DX) {
                _swiped = true;
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
        _lastX = c[0];
        touchDown(c[0], c[1]);
        return true;
    }

    function onRelease(e as WatchUi.ClickEvent) as Boolean {
        logGesture("release at " + e.getCoordinates()[0]);
        var c = e.getCoordinates();
        _lastX = c[0];
        touchUp();
        return true;
    }

    function onTap(e as WatchUi.ClickEvent) as Boolean {
        logGesture("tap at " + e.getCoordinates()[0] + "," + e.getCoordinates()[1]);
        // A tap the drag stream never saw -- some taps arrive as nothing else.
        if (_region != REGION_NONE) { return true; }
        var c = e.getCoordinates();
        _lastX = c[0];
        touchDown(c[0], c[1]);
        touchUp();
        return true;
    }

    function onSwipe(e as WatchUi.SwipeEvent) as Boolean {
        logGesture("swipe dir=" + e.getDirection()
            + " [left=" + WatchUi.SWIPE_LEFT + " right=" + WatchUi.SWIPE_RIGHT
            + " up=" + WatchUi.SWIPE_UP + " down=" + WatchUi.SWIPE_DOWN + "]");
        // Normally the drag stream has already reported this gesture. It is
        // handled here only when it did not: some swipes arrive as this alone.
        if (_region != REGION_NONE) { return true; }
        var d = e.getDirection();
        if (d == WatchUi.SWIPE_LEFT) {
            pushSide(Kaisa.Input.EVT_LEFT);
        } else if (d == WatchUi.SWIPE_RIGHT) {
            pushSide(Kaisa.Input.EVT_RIGHT);
        }
        return true;
    }

    // REVERTED: onBack/onSelect turned out to be generic companions the
    // simulator fires alongside an ordinary touch gesture ANYWHERE on the
    // screen -- a plain tap that already produced its own correct Left/Right/
    // A also raised one of these with no coordinates of its own, which is
    // what made every tap look like it was also pressing A once this pair
    // dispatched on top of it (confirmed by log: a tap at x=16 correctly
    // dispatched LEFT and ALSO fired a bare "select"). No coordinates means
    // no way to tell a real bezel-button press from that noise, so both stay
    // consumed-and-ignored, as they were originally.
    function onBack() as Boolean {
        logGesture("back");
        return true;    // consumed: prevents exit (ticket 13, confirmed on device)
    }

    function onSelect() as Boolean {
        logGesture("select");
        return true;
    }
}
