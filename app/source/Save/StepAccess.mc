import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.System;

// Two-intent handoff for the single slot0 source/game checkpoint. Foreground
// publishes its lease before checking the background flag; background sets
// its flag before checking the foreground lease. A crashed service is killed
// by Connect IQ after 30 seconds, so foreground can recover its flag at 35s.
(:background)
class StepAccess {
    const LEASE_MS = 120000l;
    const RENEW_MS = 30000l;
    const STALE_BUSY_MS = 35000l;
    const FG_KEY = "stepFgLease";
    const BG_KEY = "stepBgBusy";

    var _published as Boolean = false;
    var _active as Boolean = false;
    var _leaseAt as Number = 0;
    var _waitFrom as Number = 0;

    function age(now as Number, then as Number) as Long {
        return (now.toLong() - then.toLong()) & 0xffffffffl;
    }

    function tryForeground() as Boolean {
        var now = System.getTimer();
        try {
            if (!_published || age(now, _leaseAt) >= RENEW_MS) {
                Storage.setValue(FG_KEY, now);
                _leaseAt = now;
                _published = true;
                _active = false;
            }
            if (_active) { return true; }
            var busy = Storage.getValue(BG_KEY) as Number?;
            if (busy == null) {
                _waitFrom = 0;
                _active = true;
                return true;
            }
            if (_waitFrom == 0) { _waitFrom = now; }
            if (age(now, _waitFrom) >= STALE_BUSY_MS) {
                Storage.deleteValue(BG_KEY);
                _waitFrom = 0;
                _active = true;
                return true;
            }
        } catch (e) {
            _active = false;
        }
        return false;
    }

    function releaseForeground() as Void {
        _active = false;
        _published = false;
        _waitFrom = 0;
        try { Storage.deleteValue(FG_KEY); } catch (e) { }
    }

    function beginBackground() as Boolean {
        try {
            var now = System.getTimer();
            Storage.setValue(BG_KEY, now);
            var lease = Storage.getValue(FG_KEY) as Number?;
            if (lease != null && age(now, lease as Number) < LEASE_MS) {
                Storage.deleteValue(BG_KEY);
                return false;
            }
            return true;
        } catch (e) {
            endBackground();
            return false;
        }
    }

    function endBackground() as Void {
        try { Storage.deleteValue(BG_KEY); } catch (e) { }
    }
}
