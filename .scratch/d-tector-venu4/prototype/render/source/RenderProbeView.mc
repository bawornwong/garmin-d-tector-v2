import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Ticket 16, third probe: the real ceiling of the graphics pool, and what
// happens when it is overcommitted -- allocation failure, or a silent purge?
// The answer sets how many row buffers the LRU may hold.
class RenderProbeView extends WatchUi.View {
    const W = 288;
    const H = 24;               // one atlas row at the chosen width
    const ROW_BYTES = 288 * 24 * 2;

    var _atlas as BitmapResource?;
    var _timer as Timer.Timer?;
    var _held as Array<Graphics.BufferedBitmap> = [];
    var _done as Boolean = false;

    function initialize() { View.initialize(); }
    function onLayout(dc as Dc) as Void {
        _atlas = WatchUi.loadResource(Rez.Drawables.Atlas24) as BitmapResource;
    }
    function onShow() as Void {
        _timer = new Timer.Timer();
        _timer.start(method(:tick), 50, true);
    }
    function onHide() as Void { if (_timer != null) { _timer.stop(); } }

    function tick() as Void {
        if (_done) { return; }
        for (var i = 0; i < 4; i += 1) {
            try {
                var r = Graphics.createBufferedBitmap({ :width => W, :height => H });
                var b = r.get();
                if (b == null) {
                    report("get() returned null");
                    return;
                }
                var bdc = b.getDc();
                bdc.drawBitmap(0, 0, _atlas);
                _held.add(b);          // strong reference kept
            } catch (e) {
                report("threw: " + e.getErrorMessage());
                return;
            }
        }
        if (_held.size() % 40 == 0) {
            var st = System.getSystemStats();
            System.println("held " + _held.size() + " rows (" +
                (_held.size() * ROW_BYTES / 1024) + " KB of pool)  appMem " +
                st.usedMemory + "/" + st.totalMemory);
        }
        if (_held.size() >= 600) { report("reached 400 rows with no failure"); }
    }

    function report(why as String) as Void {
        System.println("STOPPED at " + _held.size() + " rows = " +
            (_held.size() * ROW_BYTES / 1024) + " KB of pool -- " + why);
        var st = System.getSystemStats();
        System.println("appMem " + st.usedMemory + "/" + st.totalMemory);
        System.println("DONE");
        _done = true;
        _timer.stop();
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
    }
}
