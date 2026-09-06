import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Skeleton view (SPEC.md step 1-2: "draw a static screen from row buffers.
// Proves the whole asset path"). Not the game -- there is no logic layer,
// no animation runner and no font renderer wired up yet (steps 4, 5, 7 of
// the order of work). What this DOES prove, against the real production
// asset pipeline (not a throwaway prototype):
//
//   - the canvas draws at the right size and colour (ADR: #819376 field,
//     320x320 centred in the 454x454 round display)
//   - a real Digimon sprite, addressed by digimonDB.json index and cycled
//     through its sprite actions, blits correctly through the row-buffer
//     cache at 10x scale
//   - the input adapter's twelve abstract events fire correctly for both
//     the two physical buttons and the held-screen-half touch mapping
//   - a save record round-trips through Storage using the real positional
//     packed format
//
// The HUD text (event name, save status) uses the system font, not the
// port's own bitmap-font renderer -- that is a build diagnostic overlay,
// not in-game text.
class DTectorView extends WatchUi.View {
    const CANVAS = 320;
    const SCALE = 10;
    const LCD = 0x819376;

    var _data as GameData?;
    var _atlas as AtlasCache?;
    var _save as SaveFormat?;
    var _queue as InputQueue?;
    var _timer as Timer.Timer?;

    var _demoIndex as Number = 0;      // digimonDB.json index being shown
    var _demoAction as Number = 0;
    var _frame as Number = 0;
    var _lastEvent as String = "(none)";
    var _saveStatus as String = "";

    function initialize() {
        View.initialize();
    }

    function setQueue(q as InputQueue) as Void {
        _queue = q;
    }

    function onLayout(dc as Dc) as Void {
        _data = new GameData();
        _data.load();
        _atlas = new AtlasCache();
        _atlas.load();
        _save = new SaveFormat(_data);

        _demoIndex = findDigimon("agumon");

        proveSave();
    }

    // Not a general lookup used by game logic (that would defeat ADR 7 --
    // nothing addresses a Digimon by name at runtime); this exists only to
    // pick a demo sprite for the skeleton view.
    function findDigimon(wantName as String) as Number {
        var n = _data.digimonCount();
        for (var i = 0; i < n; i += 1) {
            if (_data.name(i).equals(wantName)) { return i; }
        }
        return 0;
    }

    function proveSave() as Void {
        var existing = _save.readSlot(0);
        if (existing == null) {
            var fresh = _save.createDefault("PLAYER");
            fresh.digimonLevel[_demoIndex] = 4;
            _save.writeSlot(0, fresh);
            existing = _save.readSlot(0);
        }
        var ok = (existing != null) && existing.name.equals("PLAYER")
            && existing.digimonLevel[_demoIndex] == 4;
        _saveStatus = ok ? "SAVE OK (" + existing.digimonLevel.size() + " digimon)"
                         : "SAVE MISMATCH";
        System.println("SaveFormat: " + _saveStatus);
    }

    function onShow() as Void {
        _timer = new Timer.Timer();
        _timer.start(method(:tick), 50, true);   // the 50 ms floor -> 20 fps
    }

    function onHide() as Void {
        if (_timer != null) { _timer.stop(); }
    }

    function tick() as Void {
        _frame += 1;
        if (_queue != null) {
            var events = _queue.drain();
            for (var i = 0; i < events.size(); i += 1) {
                _lastEvent = Kaisa.Input.eventName(events[i]);
            }
        }
        if (_frame % 24 == 0) {
            _demoAction = (_demoAction + 1) % 3;   // cycle base -> at -> cr
        }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var off = (dc.getWidth() - CANVAS) / 2;
        dc.setColor(LCD, LCD);
        dc.fillRectangle(off, off, CANVAS, CANVAS);

        drawSprite(dc, _demoIndex, _demoAction, off + 40, off + 40);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, dc.getHeight() - 60, Graphics.FONT_XTINY,
            "input: " + _lastEvent, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(dc.getWidth() / 2, dc.getHeight() - 30, Graphics.FONT_XTINY,
            _saveStatus, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawSprite(dc as Dc, digimonIndex as Number, action as Number,
                         x as Number, y as Number) as Void {
        var ref = _data.spriteRef(digimonIndex, action);
        if (ref == null) { ref = _data.spriteRef(digimonIndex, _data.ACTION_BASE); }
        if (ref == null) { return; }
        var cls = ref[0];
        var sx = ref[1];
        var sy = ref[2];
        var w = ref[3];
        var h = ref[4];

        var located = _atlas.locate(cls, sx, sy);
        if (located == null) { return; }
        var buf = located[0];
        var lx = located[1];
        var ly = located[2];

        var t = new Graphics.AffineTransform();
        t.setToScale(SCALE.toFloat(), SCALE.toFloat());
        dc.drawBitmap2(x, y, buf, {
            :bitmapX => lx, :bitmapY => ly, :bitmapWidth => w, :bitmapHeight => h,
            :transform => t, :filterMode => Graphics.FILTER_MODE_POINT
        });
    }
}
