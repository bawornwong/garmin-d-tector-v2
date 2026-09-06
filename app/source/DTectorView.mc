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
    var _gm as GameManager?;
    var _app as DigiviceApp?;

    var _demoIndex as Number = 0;      // digimonDB.json index being shown
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
    // Which Status screen the slice starts on; the app pages with left/right
    // as usual, this only saves pressing them to capture a given screen.
    var _probeStatusScreen as Number = 0;

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
        proveSave();
        buildScene();
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
            startStatusApp(root);
        }
    }

    // The vertical slice (SPEC step 6): the real Status app, on the real
    // display list, over the real save. There is no main menu yet, so the app
    // is started directly and closeLoadedApp only logs -- the host that owns
    // the menu is LogicManager's screen state machine, which arrives with it.
    function startStatusApp(root as ContainerBuilder) as Void {
        var db = new Database(_data);
        db.load();
        var record = _save.readSlot(0);
        if (record == null) { record = _save.createDefault("PLAYER"); }
        seedSkeletonStats(record);
        var saved = new SavedGame(_save, 0, record);
        _gm = new GameManager(_data, db, saved);

        var app = new Status(_gm, self, root);
        app.currentScreen = _probeStatusScreen;
        app.startApp();
        _app = app;
    }

    // SKELETON SCAFFOLDING, in RAM only and never committed: a fresh save is
    // all zeroes, and a Status screen full of zeroes proves less than one with
    // numbers of different widths in it. The real values arrive with the
    // Camp/Map apps that produce them.
    function seedSkeletonStats(record as SaveRecord) as Void {
        if (record.playerExperience != 0) { return; }
        record.currentDistance = 1284;
        record.steps = 37;
        record.playerExperience = 5832;     // level 18 = floor(5832^(1/3))
        record.spiritPower = 42;
        record.totalBattles = 13;
        record.totalWins = 9;
        record.ddockDigimon[0] = _demoIndex;
    }

    // IAppController.CloseLoadedApp
    function closeLoadedApp(newScreen as Number) as Void {
        System.println("closeLoadedApp(" + newScreen + ") -- no menu to return to yet");
    }

    // Routes the adapter's twelve abstract events at the loaded app, which is
    // what InputManager.cs does in the original.
    function dispatch(event as Number) as Void {
        if (_app == null) { return; }
        if (event == Kaisa.Input.EVT_A) { _app.inputA(); }
        else if (event == Kaisa.Input.EVT_A_DOWN) { _app.inputADown(); }
        else if (event == Kaisa.Input.EVT_A_UP) { _app.inputAUp(); }
        else if (event == Kaisa.Input.EVT_B) { _app.inputB(); }
        else if (event == Kaisa.Input.EVT_B_DOWN) { _app.inputBDown(); }
        else if (event == Kaisa.Input.EVT_B_UP) { _app.inputBUp(); }
        else if (event == Kaisa.Input.EVT_LEFT) { _app.inputLeft(); }
        else if (event == Kaisa.Input.EVT_LEFT_DOWN) { _app.inputLeftDown(); }
        else if (event == Kaisa.Input.EVT_LEFT_UP) { _app.inputLeftUp(); }
        else if (event == Kaisa.Input.EVT_RIGHT) { _app.inputRight(); }
        else if (event == Kaisa.Input.EVT_RIGHT_DOWN) { _app.inputRightDown(); }
        else if (event == Kaisa.Input.EVT_RIGHT_UP) { _app.inputRightUp(); }
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
                dispatch(events[i]);
            }
        }
        if (_app != null) { _app.tick(TICK_MS); }
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
