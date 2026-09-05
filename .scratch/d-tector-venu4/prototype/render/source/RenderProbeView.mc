import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Probe for ticket 06, second pass.
//
// The first pass crashed: drawBitmap2 with :transform rejects a palette
// source ("Source must not use a color palette"). So the question becomes
// which of these paths actually works, and what each costs:
//
//   A. palette atlas -> screen, source rect, no transform      (1:1, no scale)
//   B. palette atlas -> 32x32 BufferedBitmap, source rect      (compose stage)
//   C. BufferedBitmap -> screen with :transform scale 10       (present stage)
//   D. BufferedBitmap -> screen with drawScaledBitmap
//   E. tintColor on the non-transform path
//
// B + C together are the interesting pipeline: the whole game screen is only
// 32x32 virtual pixels, so compose at 1:1 and scale ONCE per frame rather
// than once per sprite.
class RenderProbeView extends WatchUi.View {
    const CELL = 24;
    const COLS = 41;
    const SCALE = 10;
    const VIRT = 32;           // the game's virtual screen, in pixels
    const CANVAS = 320;        // VIRT * SCALE
    const LCD = 0x819376;

    var _atlas as BitmapResource?;
    var _buf as Graphics.BufferedBitmapReference?;
    var _bigBuf as Graphics.BufferedBitmapReference?;
    var _row as Graphics.BufferedBitmapReference?;
    var _cache as Graphics.BufferedBitmapReference?;
    var _scale10 as AffineTransform?;
    var _timer as Timer.Timer?;

    var _frame as Number = 0;
    var _results as Array<String> = [];
    var _done as Boolean = false;
    var _composeMs as Number = 0;
    var _presentMs as Number = 0;
    var _sprites as Number = 2;

    function initialize() { View.initialize(); }

    function onLayout(dc as Dc) as Void {
        _atlas = WatchUi.loadResource(Rez.Drawables.Atlas24) as BitmapResource;
        _scale10 = new AffineTransform();
        _scale10.setToScale(SCALE.toFloat(), SCALE.toFloat());
        try {
            _buf = Graphics.createBufferedBitmap({ :width => VIRT, :height => VIRT });
            _results.add("createBufferedBitmap 32x32: OK");
        } catch (e) {
            _results.add("createBufferedBitmap: " + e.getErrorMessage());
        }
    }

    function onShow() as Void {
        _timer = new Timer.Timer();
        _timer.start(method(:tick), 50, true);
    }
    function onHide() as Void { if (_timer != null) { _timer.stop(); } }
    function tick() as Void { _frame += 1; WatchUi.requestUpdate(); }

    function srcOpts(cell as Number) as Dictionary {
        return {
            :bitmapX => (cell % COLS) * CELL,
            :bitmapY => (cell / COLS) * CELL,
            :bitmapWidth => CELL,
            :bitmapHeight => CELL
        };
    }

    function probe(dc as Dc) as Void {
        // F: the classic drawBitmap with a palette source
        try { dc.drawBitmap(10, 10, _atlas); _results.add("F drawBitmap(palette)->screen: OK"); }
        catch (e) { _results.add("F: " + e.getErrorMessage()); }

        // G: drawScaledBitmap with a palette source
        try { dc.drawScaledBitmap(10, 10, 100, 100, _atlas); _results.add("G drawScaledBitmap(palette): OK"); }
        catch (e) { _results.add("G: " + e.getErrorMessage()); }

        // H: palette atlas into a buffer via the classic drawBitmap, then
        //    drawBitmap2 with a source rect on the buffer. If this works the
        //    atlas survives: one load-time blit, then cells all the way down.
        try {
            var big = Graphics.createBufferedBitmap({ :width => 984, :height => 960 });
            var bdc = big.get().getDc();
            bdc.drawBitmap(0, 0, _atlas);
            _results.add("H1 palette->big buffer via drawBitmap: OK");
            _bigBuf = big;
            var st = System.getSystemStats();
            _results.add("H1 mem after 984x960 buffer: " + st.usedMemory + "/" + st.totalMemory);
            dc.drawBitmap2(10, 120, big.get(), {
                :bitmapX => 12 * 24, :bitmapY => 0,
                :bitmapWidth => 24, :bitmapHeight => 24,
                :transform => _scale10, :filterMode => Graphics.FILTER_MODE_POINT });
            _results.add("H2 bigBuffer cell + transform x10: OK");
        } catch (e) { _results.add("H: " + e.getErrorMessage()); }

        // I: can a BufferedBitmap itself be palettised?
        try {
            var pal = Graphics.createBufferedBitmap({ :width => 32, :height => 32,
                :palette => [Graphics.COLOR_BLACK, 0x819376] as Array<ColorType> });
            _results.add("I createBufferedBitmap with :palette: OK");
            dc.drawBitmap2(200, 120, pal.get(), { :transform => _scale10 });
            _results.add("I2 palettised buffer + transform: OK");
        } catch (e) { _results.add("I: " + e.getErrorMessage()); }

        for (var i = 0; i < _results.size(); i += 1) { System.println("PROBE " + _results[i]); }
        var s2 = System.getSystemStats();
        System.println("PROBE stats " + s2.usedMemory + " / " + s2.totalMemory);
    }

    // Source size dominates, so the atlas cannot live as one big buffer.
    // Two ways to keep the blit source small:
    //   ROW   one buffer per atlas row (984x24), 40 of them
    //   CACHE one 24x24 buffer per sprite, filled once from the palette
    //         resource by drawing the whole atlas at a negative offset
    function frameCost(dc as Dc) as Void {
        var off = (dc.getWidth() - CANVAS) / 2;

        if (_row == null) {
            var t = System.getTimer();
            _row = Graphics.createBufferedBitmap({ :width => 984, :height => 24 });
            _row.get().getDc().drawBitmap(0, 0, _atlas);
            System.println("SETUP row buffer 984x24 fill=" + (System.getTimer() - t) + "ms");

            t = System.getTimer();
            _cache = Graphics.createBufferedBitmap({ :width => 24, :height => 24 });
            var cdc = _cache.get().getDc();
            cdc.drawBitmap(-12 * 24, 0, _atlas);   // extract cell 12 by offset
            System.println("SETUP cell cache 24x24 fill=" + (System.getTimer() - t) + "ms");
            var st = System.getSystemStats();
            System.println("SETUP mem " + st.usedMemory + "/" + st.totalMemory);
        }

        // ROW: blit a cell out of a 984x24 row buffer
        var t0 = System.getTimer();
        for (var i = 0; i < _sprites; i += 1) {
            var o = srcOpts(i % COLS);
            o[:bitmapY] = 0;
            o[:transform] = _scale10;
            o[:filterMode] = Graphics.FILTER_MODE_POINT;
            dc.drawBitmap2(off, off, _row.get(), o);
        }
        var t1 = System.getTimer();

        // CACHE: blit a whole 24x24 buffer, scaled
        for (var i = 0; i < _sprites; i += 1) {
            dc.drawBitmap2(off, off, _cache.get(),
                { :transform => _scale10, :filterMode => Graphics.FILTER_MODE_POINT });
        }
        var t2 = System.getTimer();

        // CACHE fill cost: what a cache miss costs
        var t3 = System.getTimer();
        _cache.get().getDc().drawBitmap(-((_frame % 40) * 24), 0, _atlas);
        var t4 = System.getTimer();

        System.println("COST sprites=" + _sprites +
            " row=" + (t1 - t0) + " cache=" + (t2 - t1) + " miss=" + (t4 - t3));
        if (_frame % 12 == 0 && _sprites < 32) { _sprites *= 2; }
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        if (!_done) {
            probe(dc);
            _done = true;
            return;
        }
        frameCost(dc);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, 6, Graphics.FONT_XTINY,
            _sprites + " spr",
            Graphics.TEXT_JUSTIFY_CENTER);
    }
}
