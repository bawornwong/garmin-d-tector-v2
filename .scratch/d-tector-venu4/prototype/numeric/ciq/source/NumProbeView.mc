import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Monkey C side of the numeric parity test (ticket 14).
//
// The port rule says: compute in Float, and convert to Number only after
// Math.floor. These are the four formulas whose results a floor boundary can
// change, ported literally, swept over their whole plausible input range.
// Work is split across timer ticks so no single frame trips the watchdog.
class NumProbeView extends WatchUi.View {
    var _timer as Timer.Timer?;
    var _phase as Number = 0;
    var _row as Number = 1;

    function initialize() { View.initialize(); }

    function onShow() as Void {
        _timer = new Timer.Timer();
        _timer.start(method(:tick), 50, true);
    }
    function onHide() as Void { if (_timer != null) { _timer.stop(); } }

    // port of LogicManager.cs:453
    function getPlayerLevel(playerXP as Number) as Number {
        if (playerXP == 0) { return 1; }
        var level = Math.pow(playerXP, 1.0 / 3.0);
        return Math.floor(level).toNumber();
    }

    // port of LogicManager.cs:846
    function getExperienceGained(friendlyLevel as Number, enemyLevel as Number) as Number {
        var a = (30 * enemyLevel).toFloat();
        var b = Math.pow((2 * enemyLevel) + 10, 2.5);
        var c = Math.pow(enemyLevel + friendlyLevel + 10, 2.5);
        var d = 0.025 + (0.025 * friendlyLevel);
        if (d > 0.5) { d = 0.5; }
        var expGained = ((a * (b / c)) + 1) * d;
        return Math.ceil(expGained).toNumber();
    }

    // port of Digimon.cs:73
    function getSpiritCost(baseCost as Number, decay as Float, playerLevel as Number) as Number {
        var currentCost = baseCost * Math.pow(0.5, playerLevel / decay);
        return Math.floor(currentCost).toNumber();
    }

    // port of Digimon.cs:117
    function getCallCost(baseLevel as Number, playerLevel as Number) as Number {
        var percLevelDiff = baseLevel.toFloat() / playerLevel.toFloat();
        var levelDiff = playerLevel - baseLevel;
        if (percLevelDiff < 0.55 && levelDiff >= 10) { return 0; }
        if (percLevelDiff < 0.75 && levelDiff >= 5) { return 1; }
        if (percLevelDiff < 0.90 && levelDiff >= 2) { return 2; }
        if (percLevelDiff < 1.0 && levelDiff >= 1) { return 3; }
        if (percLevelDiff == 1.0) { return 4; }
        if (percLevelDiff < 1.30) { return 5; }
        if (percLevelDiff < 1.60) { return 6; }
        if (percLevelDiff < 2.0) { return 7; }
        if (percLevelDiff < 3.0) { return 8; }
        return 9;
    }

    function tick() as Void {
        if (_phase == 0) {
            System.println("LEVELTRANS");
            _phase = 1; _row = 2;
            return;
        }
        if (_phase == 1) {
            // find where the level changes, by scanning a window around each
            // cube; pow is monotonic so a window this wide cannot miss a shift
            for (var l = _row; l < _row + 8 && l <= 66; l += 1) {
                var centre = l * l * l;
                var lo = centre - 8;
                if (lo < 1) { lo = 1; }
                var prev = getPlayerLevel(lo - 1);
                for (var xp = lo; xp <= centre + 8; xp += 1) {
                    var v = getPlayerLevel(xp);
                    if (v != prev) { System.println(xp + " " + v); prev = v; }
                }
            }
            _row += 8;
            if (_row > 66) { System.println("EXPGRID"); _phase = 2; _row = 1; }
            return;
        }
        if (_phase == 2) {
            var s = _row + ":";
            for (var e = 1; e <= 51; e += 1) {
                if (e > 1) { s += ","; }
                s += getExperienceGained(_row, e);
            }
            System.println(s);
            _row += 1;
            if (_row > 51) { System.println("SPIRITCOST"); _phase = 3; _row = 0; }
            return;
        }
        if (_phase == 3) {
            var bases = [20, 95, 10, 20, 30, 35, 40, 55];
            var decays = [20.0, 50.0, 20.0, 30.0, 30.0, 40.0, 50.0, 60.0];
            var s = bases[_row] + "/" + decays[_row].format("%d") + ":";
            for (var lv = 1; lv <= 99; lv += 1) {
                if (lv > 1) { s += ","; }
                s += getSpiritCost(bases[_row], decays[_row], lv);
            }
            System.println(s);
            _row += 1;
            if (_row >= 8) { System.println("CALLCOST"); _phase = 4; _row = 1; }
            return;
        }
        if (_phase == 4) {
            var s = _row + ":";
            for (var p = 1; p <= 51; p += 1) {
                if (p > 1) { s += ","; }
                s += getCallCost(_row, p);
            }
            System.println(s);
            _row += 1;
            if (_row > 51) { System.println("END"); _phase = 5; _timer.stop(); }
            return;
        }
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
    }
}
