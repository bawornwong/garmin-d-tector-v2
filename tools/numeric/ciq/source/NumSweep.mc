import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Numeric parity sweep, Monkey C side. Drives the PORTED Logic/Digimon.mc --
// the real file, pulled in by monkey.jungle's sourcePath, not a copy -- over
// the same parameter grid as tools/numeric/Sweep.cs, printing one line per
// value in the same format. tools/verify_numeric.py diffs the two outputs.
//
// Float results print as their IEEE-754 bit pattern, because a decimal
// rendering would hide the one-ULP difference that this test exists to catch.
//
// The sweep is cut into slices of LINES_PER_TICK across a timer: a single
// callback that printed all 16,000 lines would trip the watchdog.
class NumSweepApp extends Application.AppBase {
    function initialize() { AppBase.initialize(); }
    function getInitialView() { return [new NumSweepView()]; }
}

class NumSweepView extends WatchUi.View {
    const LINES_PER_TICK = 250;

    // (stage, spiritType, name) triples, in Sweep.cs order
    const SPIRIT_COST_CASES = [
        [Kaisa.STAGE_SPIRIT, Kaisa.SPIRIT_HUMAN, "x"],
        [Kaisa.STAGE_SPIRIT, Kaisa.SPIRIT_ANIMAL, "x"],
        [Kaisa.STAGE_SPIRIT, Kaisa.SPIRIT_HYBRID, "x"],
        [Kaisa.STAGE_SPIRIT, Kaisa.SPIRIT_ANCIENT, "x"],
        [Kaisa.STAGE_SPIRIT, Kaisa.SPIRIT_FUSION, "x"],
        [Kaisa.STAGE_SPIRIT, Kaisa.SPIRIT_CHILD, "x"],
        [Kaisa.STAGE_ARMOR, Kaisa.SPIRIT_NONE, "x"],
        [Kaisa.STAGE_ROOKIE, Kaisa.SPIRIT_NONE, "x"],
        [Kaisa.STAGE_MEGA, Kaisa.SPIRIT_FUSION, "susanoomon"]
    ];
    const BOSS_LEVEL_CASES = [
        [Kaisa.STAGE_SPIRIT, Kaisa.SPIRIT_ANCIENT],
        [Kaisa.STAGE_SPIRIT, Kaisa.SPIRIT_HUMAN],
        [Kaisa.STAGE_ARMOR, Kaisa.SPIRIT_NONE],
        [Kaisa.STAGE_ROOKIE, Kaisa.SPIRIT_NONE]
    ];
    const BOSS_STATS_CASES = [
        [Kaisa.STAGE_SPIRIT, Kaisa.SPIRIT_HUMAN],
        [Kaisa.STAGE_SPIRIT, Kaisa.SPIRIT_ANCIENT],
        [Kaisa.STAGE_SPIRIT, Kaisa.SPIRIT_ANIMAL],
        [Kaisa.STAGE_MEGA, Kaisa.SPIRIT_NONE]
    ];

    var _timer as Timer.Timer?;
    var _phase as Number = 0;
    var _i as Number = 0;
    var _j as Number = 0;
    var _k as Number = 0;
    var _started as Boolean = false;

    function initialize() { View.initialize(); }

    function onShow() as Void {
        _timer = new Timer.Timer();
        _timer.start(method(:tick), 50, true);
    }

    function onHide() as Void {
        if (_timer != null) { _timer.stop(); }
    }

    function stats(hp as Number, en as Number, cr as Number, ab as Number) as CombatStats {
        return new CombatStats(hp, en, cr, ab);
    }

    // Sweep.cs's Make(): only the fields the formulas read matter.
    function make(stage as Number, spirit as Number, baseLevel as Number,
                  st as CombatStats, bossStats as CombatStats?, name as String) as Digimon {
        return new Digimon(0, 1, 1, name, stage, spirit, 0, Kaisa.ELEMENT_FIRE, -1,
                           false, baseLevel, st, bossStats, false, "abcde",
                           Kaisa.RARITY_COMMON, false);
    }

    function f(value as Float) as String {
        var b = [0, 0, 0, 0]b;
        b.encodeNumber(value, Lang.NUMBER_FORMAT_FLOAT,
                       { :offset => 0, :endianness => Lang.ENDIAN_BIG });
        return b.decodeNumber(Lang.NUMBER_FORMAT_UINT32,
                              { :offset => 0, :endianness => Lang.ENDIAN_BIG }).toString();
    }

    function tick() as Void {
        var budget = LINES_PER_TICK;
        while (budget > 0 && _phase <= 8) {
            budget -= step();
        }
        if (_phase > 8) {
            System.println("END");
            if (_timer != null) { _timer.stop(); }
        }
    }

    // Emits one line (or a header) and advances the cursor; returns the lines
    // it printed so the caller can keep its budget.
    function step() as Number {
        var st = stats(40, 25, 15, 20);

        if (_phase == 0) {                                  // MAXEXTRA
            if (!_started) { System.println("MAXEXTRA"); _started = true; _i = 0; _j = 1; }
            var stage = _i;
            System.println(stage + " " + _j + " "
                + make(stage, Kaisa.SPIRIT_NONE, _j, st, null, "x").maxExtraLevel());
            _j += 1;
            if (_j > 100) { _j = 1; _i += 1; if (_i > 6) { nextPhase(); } }
            return 1;
        }
        if (_phase == 1) {                                  // SPIRITCOST
            if (!_started) { System.println("SPIRITCOST"); _started = true; _i = 0; _j = 1; }
            var c = SPIRIT_COST_CASES[_i];
            var d = make(c[0], c[1], 10, st, null, c[2]);
            System.println(c[0] + " " + c[1] + " " + c[2] + " " + _j + " " + d.getSpiritCost(_j));
            _j += 1;
            if (_j > 100) { _j = 1; _i += 1; if (_i >= SPIRIT_COST_CASES.size()) { nextPhase(); } }
            return 1;
        }
        if (_phase == 2) {                                  // CALLCOST
            if (!_started) { System.println("CALLCOST"); _started = true; _i = 1; _j = 1; }
            System.println(_i + " " + _j + " "
                + make(Kaisa.STAGE_ROOKIE, Kaisa.SPIRIT_NONE, _i, st, null, "x").getCallCost(_j));
            _j += 3;
            if (_j > 100) { _j = 1; _i += 3; if (_i > 100) { nextPhase(); } }
            return 1;
        }
        if (_phase == 3) {                                  // BOSSLEVEL
            if (!_started) { System.println("BOSSLEVEL"); _started = true; _i = 0; _j = 1; }
            var c = BOSS_LEVEL_CASES[_i];
            System.println(c[0] + " " + c[1] + " " + _j + " "
                + make(c[0], c[1], 10, st, null, "x").getBossLevel(_j));
            _j += 1;
            if (_j > 100) { _j = 1; _i += 1; if (_i >= BOSS_LEVEL_CASES.size()) { nextPhase(); } }
            return 1;
        }
        if (_phase == 4) {                                  // CHANCES
            if (!_started) { System.println("CHANCES"); _started = true; _i = 1; _j = 1; }
            var d = make(Kaisa.STAGE_ROOKIE, Kaisa.SPIRIT_NONE, _i, st, null, "x");
            System.println(_i + " " + _j + " " + f(d.getObeyChance(_j)) + " " + f(d.getIdleChance(_j)));
            _j += 3;
            if (_j > 60) { _j = 1; _i += 1; if (_i > 60) { nextPhase(); } }
            return 1;
        }
        if (_phase == 5) {                                  // EVOLVE
            if (!_started) { System.println("EVOLVE"); _started = true; _i = 1; _j = 1; _k = 1; }
            var d = make(Kaisa.STAGE_ROOKIE, Kaisa.SPIRIT_NONE, _i, st, null, "x");
            System.println(_i + " " + _j + " " + _k + " " + f(d.getEvolveChance(_j, _k)));
            _k += 1;
            if (_k > 10) {
                _k = 1;
                _j += 7;
                if (_j > 100) { _j = 1; _i += 3; if (_i > 100) { nextPhase(); } }
            }
            return 1;
        }
        if (_phase == 6) {                                  // BOSSSTATS
            if (!_started) { System.println("BOSSSTATS"); _started = true; _i = 0; _j = 1; _k = 1; }
            var c = BOSS_STATS_CASES[_i];
            var d = make(c[0], c[1], 10, st, stats(_j, _j + 1, _j + 2, _j + 3), "x");
            var s = d.getBossStats(_k);
            System.println(c[0] + " " + c[1] + " " + _j + " " + _k + " "
                + s.hp + " " + s.en + " " + s.cr + " " + s.ab);
            _k += 9;
            if (_k > 100) {
                _k = 1;
                _j += 7;
                if (_j > 400) { _j = 1; _i += 1; if (_i >= BOSS_STATS_CASES.size()) { nextPhase(); } }
            }
            return 1;
        }
        if (_phase == 7) {                                  // FRIENDLYSTATS
            if (!_started) { System.println("FRIENDLYSTATS"); _started = true; _i = 1; _j = 1; _k = 0; }
            var d = make(Kaisa.STAGE_ROOKIE, Kaisa.SPIRIT_NONE, _i,
                         stats(_j, _j + 5, _j + 9, _j + 13), null, "x");
            var s = d.getFriendlyStats(_k);
            System.println(_i + " " + _j + " " + _k + " "
                + s.hp + " " + s.en + " " + s.cr + " " + s.ab);
            _k += 5;
            if (_k > d.maxExtraLevel()) {
                _k = 0;
                _j += 11;
                if (_j > 300) { _j = 1; _i += 3; if (_i > 60) { nextPhase(); } }
            }
            return 1;
        }
        // phase 8                                          // ENERGYRANK
        if (!_started) { System.println("ENERGYRANK"); _started = true; _i = 0; }
        System.println(_i + " " + new MutableCombatStats(1, _i, 1, 1).getEnergyRank());
        _i += 1;
        if (_i > 320) { nextPhase(); }
        return 1;
    }

    function nextPhase() as Void {
        _phase += 1;
        _started = false;
    }
}
