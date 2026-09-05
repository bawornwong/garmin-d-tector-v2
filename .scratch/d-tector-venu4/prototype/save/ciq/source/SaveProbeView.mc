import Toybox.Application.Storage;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Ticket 10 probe. Ticket 03 established that Storage.setValue is synchronous
// and expensive but never measured it, and that a name-keyed dictionary save
// would cost ~27 KB against ~1.1 KB packed. Both claims are tested here.
class SaveProbeView extends WatchUi.View {
    const SLOT_BYTES = 1024;    // the packed save's measured size, rounded up
    const DIGIMON = 593;

    var _timer as Timer.Timer?;
    var _phase as Number = 0;
    var _fill as Number = 0;

    function initialize() { View.initialize(); }
    function onShow() as Void {
        _timer = new Timer.Timer();
        _timer.start(method(:tick), 50, true);
    }
    function onHide() as Void { if (_timer != null) { _timer.stop(); } }

    function makeSlot(seed as Number) as ByteArray {
        var b = []b;
        for (var i = 0; i < SLOT_BYTES; i += 1) {
            b.add((i + seed) % 256);
        }
        return b;
    }

    function tick() as Void {
        if (_phase == 0) {
            // a packed slot, written and read back
            var slot = makeSlot(7);
            var t0 = System.getTimer();
            Storage.setValue("slot0", slot);
            var t1 = System.getTimer();
            var back = Storage.getValue("slot0") as ByteArray;
            var t2 = System.getTimer();
            var same = (back != null && back.size() == slot.size());
            if (same) {
                for (var i = 0; i < slot.size(); i += 1) {
                    if (back[i] != slot[i]) { same = false; break; }
                }
            }
            System.println("BYTEARRAY " + SLOT_BYTES + "B  write=" + (t1 - t0) +
                "ms read=" + (t2 - t1) + "ms identical=" + same);
            _phase = 1;
            return;
        }
        if (_phase == 1) {
            // four slots, the count ticket 03 recommended
            var t0 = System.getTimer();
            for (var s = 0; s < 4; s += 1) {
                Storage.setValue("slot" + s, makeSlot(s));
            }
            var t1 = System.getTimer();
            System.println("4 SLOTS write=" + (t1 - t0) + "ms");
            var st = System.getSystemStats();
            System.println("mem " + st.usedMemory + "/" + st.totalMemory);
            _phase = 2;
            return;
        }
        if (_phase == 2) {
            // the rejected shape: a dictionary keyed by digimon name
            var d = {};
            var t0 = System.getTimer();
            for (var i = 0; i < DIGIMON; i += 1) {
                d["digimon" + i] = i % 52;
            }
            var t1 = System.getTimer();
            var st = System.getSystemStats();
            System.println("DICT built " + DIGIMON + " keys in " + (t1 - t0) +
                "ms  mem " + st.usedMemory + "/" + st.totalMemory);
            var t2 = System.getTimer();
            try {
                Storage.setValue("dictslot", d);
                var t3 = System.getTimer();
                var back = Storage.getValue("dictslot") as Dictionary;
                var t4 = System.getTimer();
                System.println("DICT write=" + (t3 - t2) + "ms read=" + (t4 - t3) +
                    "ms keys=" + (back == null ? -1 : back.size()));
            } catch (e) {
                System.println("DICT failed: " + e.getErrorMessage());
            }
            _phase = 3;
            return;
        }
        if (_phase == 3) {
            // how much fits: write 1 KB values, a few per tick, until Storage
            // refuses -- this is the quota ticket 03 could only infer
            var wrote = 0;
            try {
                for (var i = 0; i < 8; i += 1) {
                    Storage.setValue("fill" + _fill, makeSlot(_fill % 200));
                    _fill += 1;
                    wrote += 1;
                }
            } catch (e) {
                System.println("FILL stopped after " + _fill + " KB written: " +
                    e.getErrorMessage());
                Storage.clearValues();
                System.println("DONE");
                _timer.stop();
                _phase = 4;
                return;
            }
            if (_fill % 64 == 0) {
                var st = System.getSystemStats();
                System.println("FILL " + _fill + " KB written, mem " +
                    st.usedMemory + "/" + st.totalMemory);
            }
            if (_fill >= 12288) {
                System.println("FILL reached " + _fill + " KB with no refusal");
                Storage.clearValues();
                System.println("DONE");
                _timer.stop();
                _phase = 4;
            }
            return;
        }
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
    }
}
