import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// One test per press of the upper button; the lower button repeats the
// current one. Each prints its own result, so the console transcript is the
// deliverable -- copy it into ticket 01's Answer.
class ProbeView extends WatchUi.View {
    // The sweep covers the extracted melodies' real range with headroom at
    // both ends: 95% of the port's notes sit between 910 and 3413 Hz, the
    // whole set between 65 and 5669 Hz (ticket 04). The top three points
    // are past anything the game needs and exist to find the ceiling.
    const SWEEP = [65, 250, 500, 910, 1500, 2643, 3413, 4000, 5669, 8000, 10000];

    var _step as Number = 0;
    var _line1 as String = "ToneProbe";
    var _line2 as String = "UP: next test";
    var _line3 as String = "DOWN: repeat";
    var _timer as Timer.Timer?;
    var _sweepAt as Number = -1;

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Dc) as Void {
        report();
    }

    // --- test 0: what the platform admits to ---------------------------------
    function report() as Void {
        var s = System.getDeviceSettings();
        System.println("=== ToneProbe on " + s.partNumber + " ===");
        System.println("Attention has :playTone    = " + (Attention has :playTone));
        System.println("Attention has :ToneProfile = " + (Attention has :ToneProfile));
        System.println("Attention has :vibrate     = " + (Attention has :vibrate));
        System.println("Attention has :VibeProfile = " + (Attention has :VibeProfile));
        System.println("settings.tonesOn           = " + s.tonesOn);
        System.println("settings.vibrateOn         = " + s.vibrateOn);
        System.println("");
        System.println("Press UP for each test in turn. Say out loud whether you");
        System.println("HEARD or FELT it -- the console cannot tell you that.");
        setLines("0: capabilities", "printed to console", "UP for test 1");
    }

    function setLines(a as String, b as String, c as String) as Void {
        _line1 = a; _line2 = b; _line3 = c;
        WatchUi.requestUpdate();
    }

    function next() as Void {
        _step += 1;
        run();
    }

    function repeatTest() as Void {
        run();
    }

    function run() as Void {
        if (_step == 1) { testSystemTone(); }
        else if (_step == 2) { testSingleProfile(); }
        else if (_step == 3) { startSweep(); }
        else if (_step == 4) { testBlocking(); }
        else if (_step == 5) { testArrayLength(); }
        else if (_step == 6) { testSpam(); }
        else if (_step == 7) { testInterrupt(); }
        else if (_step == 8) { testVibeSingle(); }
        else if (_step == 9) { testVibeDutyCycle(); }
        else if (_step == 10) { testVibePattern(); }
        else if (_step == 11) { testRealMelody(); }
        else { _step = 0; report(); }
    }

    // --- 1: does a stock system tone make any sound at all? ------------------
    function testSystemTone() as Void {
        System.println("--- 1: system tone TONE_LOUD_BEEP ---");
        System.println("If THIS is silent, CIQ tones do not reach the speaker at");
        System.println("all on this watch, and the whole sound half of the map");
        System.println("collapses to haptics. Everything after assumes it rang.");
        if (Attention has :playTone) { Attention.playTone(Attention.TONE_LOUD_BEEP); }
        setLines("1: system tone", "TONE_LOUD_BEEP", "heard it?");
    }

    // --- 2: a single custom ToneProfile --------------------------------------
    function testSingleProfile() as Void {
        System.println("--- 2: one custom ToneProfile, 2643 Hz for 500 ms ---");
        System.println("2643 Hz is the median pitch of the extracted melodies.");
        playProfiles([new Attention.ToneProfile(2643, 500)]);
        setLines("2: custom tone", "2643 Hz, 500ms", "heard it?");
    }

    // --- 3: the frequency sweep ----------------------------------------------
    // One point per second so each is heard separately; a single array would
    // run them together and make the edges impossible to place.
    function startSweep() as Void {
        System.println("--- 3: frequency sweep, one point per second ---");
        System.println("Note the LOWEST and HIGHEST you can actually hear.");
        _sweepAt = 0;
        _timer = new Timer.Timer();
        (_timer as Timer.Timer).start(method(:sweepTick), 1000, true);
        sweepTick();
    }

    function sweepTick() as Void {
        if (_sweepAt >= SWEEP.size()) {
            (_timer as Timer.Timer).stop();
            System.println("sweep done");
            setLines("3: sweep done", "note lowest+highest", "UP for test 4");
            return;
        }
        var f = SWEEP[_sweepAt];
        System.println("  " + f + " Hz");
        playProfiles([new Attention.ToneProfile(f, 400)]);
        setLines("3: sweep", f + " Hz", "audible?");
        _sweepAt += 1;
    }

    // --- 4: does playTone block the caller? ----------------------------------
    // The frame budget is 50 ms (ADR 5). If a 2-second tone takes 2 seconds to
    // return, the playback engine's fiber design is wrong and ticket 05 needs
    // re-cutting.
    function testBlocking() as Void {
        System.println("--- 4: does playTone block? ---");
        var t0 = System.getTimer();
        playProfiles([new Attention.ToneProfile(2643, 2000)]);
        var elapsed = System.getTimer() - t0;
        System.println("  playTone(2000ms tone) returned in " + elapsed + " ms");
        System.println("  <50ms = async, fine. ~2000ms = BLOCKS, ticket 05 is wrong.");
        setLines("4: blocking?", elapsed + " ms to return", "UP for test 5");
    }

    // --- 5: how long an array will it take? ----------------------------------
    // Undocumented (ticket 02). The engine chunks at ~220 ms, which is ~4-10
    // notes, so the practical answer only has to clear that -- but the ceiling
    // is worth knowing before someone raises the chunk size.
    function testArrayLength() as Void {
        System.println("--- 5: array length ceiling ---");
        var sizes = [4, 16, 64, 128];
        for (var s = 0; s < sizes.size(); s += 1) {
            var n = sizes[s];
            var arr = [];
            for (var i = 0; i < n; i += 1) {
                arr.add(new Attention.ToneProfile(2000 + (i % 8) * 200, 40));
            }
            try {
                Attention.playTone({ :toneProfile => arr });
                System.println("  " + n + " profiles: accepted");
            } catch (e) {
                System.println("  " + n + " profiles: REJECTED -- " + e.getErrorMessage());
            }
        }
        System.println("  (listen: did the longer ones play in full or truncate?)");
        setLines("5: array length", "4/16/64/128", "played in full?");
    }

    // --- 6: spam ------------------------------------------------------------
    // The button call sites can fire several times a second. Ticket 05 assumes
    // a new call simply replaces the old.
    function testSpam() as Void {
        System.println("--- 6: ten calls back to back, no waiting ---");
        for (var i = 0; i < 10; i += 1) {
            playProfiles([new Attention.ToneProfile(1500 + i * 200, 100)]);
        }
        System.println("  heard: one tone? ten? a stutter? nothing?");
        setLines("6: spam x10", "no gaps between", "what happened?");
    }

    // --- 7: can a tone in progress be replaced? ------------------------------
    // There is no stop API (ticket 02). The engine's interrupt-on-new-sound
    // rule depends on a NEW playTone cutting the old one off.
    function testInterrupt() as Void {
        System.println("--- 7: long tone, then a second one 300 ms in ---");
        System.println("  expect: the low tone is CUT OFF by the high one.");
        playProfiles([new Attention.ToneProfile(800, 3000)]);
        _timer = new Timer.Timer();
        (_timer as Timer.Timer).start(method(:interruptTick), 300, false);
        setLines("7: interrupt", "800Hz then 4000Hz", "was it cut off?");
    }

    function interruptTick() as Void {
        playProfiles([new Attention.ToneProfile(4000, 500)]);
        System.println("  second tone fired");
    }

    // --- 8-10: vibration -----------------------------------------------------
    function testVibeSingle() as Void {
        System.println("--- 8: single vibration, dutyCycle 50, 500 ms ---");
        vibrate([new Attention.VibeProfile(50, 500)]);
        setLines("8: vibrate", "50% / 500ms", "felt it?");
    }

    // Ticket 02 found Garmin documents Forerunners as ignoring duty cycle
    // entirely. Unconfirmed for Venu 4 -- if these three feel identical, the
    // vibration vocabulary (ticket 06) can only use LENGTH and PATTERN.
    function testVibeDutyCycle() as Void {
        System.println("--- 9: duty cycle 25 / 50 / 100, 400 ms each ---");
        System.println("  do these feel like THREE strengths, or all the same?");
        vibrate([new Attention.VibeProfile(25, 400),
                 new Attention.VibeProfile(0, 250),
                 new Attention.VibeProfile(50, 400),
                 new Attention.VibeProfile(0, 250),
                 new Attention.VibeProfile(100, 400)]);
        setLines("9: duty cycle", "25 / 50 / 100", "three strengths?");
    }

    // The boss-encounter candidate from ticket 06, and the shortest knock, so
    // the two can be told apart by feel.
    function testVibePattern() as Void {
        System.println("--- 10: ticket 06's candidates: regular vs boss encounter ---");
        System.println("  first: one 150ms knock (regular)");
        vibrate([new Attention.VibeProfile(50, 150)]);
        _timer = new Timer.Timer();
        (_timer as Timer.Timer).start(method(:bossTick), 1500, false);
        setLines("10: encounter", "regular, then boss", "tell them apart?");
    }

    function bossTick() as Void {
        System.println("  now: boss, three harder beats");
        vibrate([new Attention.VibeProfile(80, 150),
                 new Attention.VibeProfile(0, 80),
                 new Attention.VibeProfile(80, 150),
                 new Attention.VibeProfile(0, 80),
                 new Attention.VibeProfile(80, 250)]);
    }

    // --- 11: an actual melody from the game ----------------------------------
    // levelUp's real extracted notes: the 4-note motif, one repeat, as
    // tools/pack_sounds.py produced them. The point of the whole effort --
    // does it sound like the D-Tector?
    function testRealMelody() as Void {
        System.println("--- 11: levelUp, as extracted ---");
        playProfiles([
            new Attention.ToneProfile(3068, 110),
            new Attention.ToneProfile(2455, 110),
            new Attention.ToneProfile(2046, 90),
            new Attention.ToneProfile(2643, 110),
            new Attention.ToneProfile(3074, 90),
            new Attention.ToneProfile(2455, 110),
            new Attention.ToneProfile(2046, 90),
            new Attention.ToneProfile(2643, 110),
            new Attention.ToneProfile(3074, 489)
        ]);
        setLines("11: levelUp", "the real melody", "recognisable?");
    }

    // --- helpers -------------------------------------------------------------
    // Deliberately NOT gated on tonesOn/vibrateOn: this probe wants to know
    // whether the system enforces them by itself, which ticket 02 could not
    // settle from the documentation. Toggle the watch's own sound setting off
    // and re-run test 2 to find out.
    function playProfiles(arr as Array) as Void {
        if (!(Attention has :playTone)) {
            System.println("  !! no playTone on this device");
            return;
        }
        try {
            Attention.playTone({ :toneProfile => arr });
        } catch (e) {
            System.println("  !! playTone threw: " + e.getErrorMessage());
        }
    }

    function vibrate(arr as Array) as Void {
        if (!(Attention has :vibrate)) {
            System.println("  !! no vibrate on this device");
            return;
        }
        try {
            Attention.vibrate(arr);
        } catch (e) {
            System.println("  !! vibrate threw: " + e.getErrorMessage());
        }
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        dc.drawText(cx, cy - 60, Graphics.FONT_SMALL, _line1, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, cy - 20, Graphics.FONT_MEDIUM, _line2, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, cy + 30, Graphics.FONT_SMALL, _line3, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, cy + 70, Graphics.FONT_XTINY,
            "step " + _step + " / 11", Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class ProbeDelegate extends WatchUi.BehaviorDelegate {
    var _view as ProbeView;

    function initialize(v as ProbeView) {
        BehaviorDelegate.initialize();
        _view = v;
    }

    function onNextPage() as Boolean { _view.next(); return true; }
    function onPreviousPage() as Boolean { _view.repeatTest(); return true; }
    function onSelect() as Boolean { _view.next(); return true; }

    function onKeyPressed(e as WatchUi.KeyEvent) as Boolean {
        var k = e.getKey();
        if (k == WatchUi.KEY_ENTER) { _view.next(); return true; }
        if (k == WatchUi.KEY_DOWN) { _view.repeatTest(); return true; }
        return false;
    }
}
