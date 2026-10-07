import Toybox.Attention;
import Toybox.Lang;
import Toybox.System;

// Renew the system brightness for 30 seconds after showing the game or input.
// AMOLED firmware can reject long continuous illumination; stop requesting
// for this visible session if it does, and let the device manage its display.
class DisplayAwake {
    const DURATION_MS = 30000l;
    const REFRESH_MS = 1000l;
    var _visible as Boolean = false;
    var _blocked as Boolean = false;
    var _startedAt as Number = 0;
    var _lastRequestAt as Number? = null;

    function initialize() {
    }

    function show(now as Number) as Void {
        _visible = true;
        _blocked = false;
        _lastRequestAt = null;
        input(now);
    }

    function hide() as Void {
        _visible = false;
        _lastRequestAt = null;
    }

    function input(now as Number) as Void {
        if (!_visible) { return; }
        _startedAt = now;
        tick(now);
    }

    function age(now as Number, then as Number) as Long {
        return (now.toLong() - then.toLong()) & 0xffffffffl;
    }

    function tick(now as Number) as Void {
        if (!_visible || _blocked || age(now, _startedAt) > DURATION_MS) { return; }
        var last = _lastRequestAt;
        if (last != null && age(now, last) < REFRESH_MS) { return; }
        try {
            requestBacklight();
            _lastRequestAt = now;
        } catch (e) {
            _blocked = true;
            System.println("DisplayAwake: " + e.getErrorMessage());
        }
    }

    function requestBacklight() as Void {
        if (Attention has :backlight) { Attention.backlight(true); }
    }
}
