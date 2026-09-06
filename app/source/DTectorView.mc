import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Skeleton view (SPEC.md steps 1-5). Not the game -- there is no logic layer
// and no animation runner yet (steps 4 and 7 of the order of work). What this
// DOES prove, against the real production asset pipeline rather than a
// throwaway prototype:
//
//   - the canvas draws at the right size and colour (#819376 field, 320x320
//     centred in the 454x454 round display)
//   - a real Digimon sprite, addressed by digimonDB.json index and cycled
//     through its sprite actions, blits correctly through the row-buffer
//     cache at 10x scale
//   - the display list draws: nesting, container masks, inversion, flips,
//     rectangles and their flick
//   - bitmap text draws in all three faces with the packed metrics
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
    const LCD = 0x819376;   // Preferences.BackgroundColor
    const INK = 0x000000;   // Preferences.ActiveColor
    const TICK_MS = 50;     // the 50 ms floor -> 20 fps

    var _data as GameData?;
    var _atlas as AtlasCache?;
    var _save as SaveFormat?;
    var _queue as InputQueue?;
    var _timer as Timer.Timer?;
    var _renderer as Renderer?;
    var _root as ContainerBuilder?;

    var _demoIndex as Number = 0;      // digimonDB.json index being shown
    var _demoSprite as SpriteBuilder?;
    var _demoAction as Number = 0;
    var _frame as Number = 0;
    var _lastEvent as String = "(none)";
    var _saveStatus as String = "";

    // Verification probes. Each builds a fixed scene that a tool can diff a
    // captured frame against; -1 / false give the animated demo instead.
    //   _probeIndex   >= 0  tools/verify_render.py, one sprite at (4,4)
    //   _probeInvert        the same sprite drawn inverted
    //   _probeText          tools/verify_text.py, the fixed string set
    var _probeIndex as Number = -1;
    var _probeInvert as Boolean = false;
    var _probeText as Boolean = false;

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

        var origin = (dc.getWidth() - CANVAS) / 2;
        _renderer = new Renderer(_atlas, new TextRenderer(_atlas),
                                 origin, origin, SCALE, INK, LCD);

        _demoIndex = findDigimon("agumon");
        buildScene();
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

    function buildScene() as Void {
        var root = new ContainerBuilder();
        root.setName("Root");
        root.setSize(Kaisa.Constants.SCREEN_WIDTH, Kaisa.Constants.SCREEN_HEIGHT).setTransparent(true);
        _root = root;

        if (_probeText) {
            TextProbe.build(root);
        } else if (_probeIndex >= 0) {
            buildSpriteProbe(root);
        } else {
            buildDemo(root);
        }
    }

    // tools/verify_render.py knows this position and size.
    function buildSpriteProbe(root as ContainerBuilder) as Void {
        var sprite = new SpriteBuilder();
        sprite.setName("Probe");
        sprite.setSize(24, 24)
              .setPosition(4, 4)
              .setTransparent(!_probeInvert)
              .invertColors(_probeInvert)
              .setSprite(_data.spriteRef(_probeIndex, _data.ACTION_BASE));
        root.addChild(sprite);
    }

    // (The text probe scene is generated from tools/text_probe.json by
    // tools/gen_text_probe.py, and tools/verify_text.py computes what it must
    // look like from that same spec.)
    //
    // Exercises the parts of the display list that the two probes do not:
    // a masked container that a text box overflows, a flicking rectangle,
    // and a flipped sprite.
    function buildDemo(root as ContainerBuilder) as Void {
        var sprite = new SpriteBuilder();
        sprite.setName("Demo");
        sprite.setSize(24, 24).setPosition(4, 2).setTransparent(true);
        root.addChild(sprite);
        _demoSprite = sprite;

        var flipped = new SpriteBuilder();
        flipped.setName("Flipped");
        flipped.setSize(14, 16)
               .setPosition(1, 1)
               .setTransparent(true)
               .flipHorizontal(true)
               .setSprite(_data.energySpriteRef(0));
        root.addChild(flipped);

        var window = new ContainerBuilder();
        window.setName("Window");
        window.setSize(30, 5).setPosition(1, 26).setTransparent(true).setMaskActive(true);
        root.addChild(window);

        var label = new TextBoxBuilder();
        label.setName("Scroll");
        label.setSize(60, 5)
             .setPosition(-6, 0)
             .setFont(Kaisa.Font.SMALL)
             .setTransparent(true)
             .setText("DISPLAY LIST OK");
        window.addChild(label);

        var cursor = new RectangleBuilder();
        cursor.setName("Cursor");
        cursor.setSize(2, 5).setPosition(29, 26).setFlickPeriodMs(500, true);
        root.addChild(cursor);
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
        _timer.start(method(:tick), TICK_MS, true);
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
        if (_demoSprite != null) {
            if (_frame % 24 == 0) {
                _demoAction = (_demoAction + 1) % 3;   // cycle base -> at -> cr
            }
            var ref = _data.spriteRef(_demoIndex, _demoAction);
            if (ref == null) { ref = _data.spriteRef(_demoIndex, _data.ACTION_BASE); }
            _demoSprite.setSprite(ref);
        }
        advanceFlicks(_root, TICK_MS);
        WatchUi.requestUpdate();
    }

    // RectangleBuilder.Update, which Unity ran per object; the display list
    // has no update pass of its own, so the frame walks it.
    function advanceFlicks(el as ScreenElement?, elapsedMs as Number) as Void {
        if (el == null) { return; }
        if (el instanceof RectangleBuilder) {
            (el as RectangleBuilder).advanceFlick(elapsedMs);
        }
        for (var i = 0; i < el.children.size(); i += 1) {
            advanceFlicks(el.children[i], elapsedMs);
        }
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        _renderer.draw(dc, _root);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, dc.getHeight() - 60, Graphics.FONT_XTINY,
            "input: " + _lastEvent, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(dc.getWidth() / 2, dc.getHeight() - 30, Graphics.FONT_XTINY,
            _saveStatus, Graphics.TEXT_JUSTIFY_CENTER);
    }
}
