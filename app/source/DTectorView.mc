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
    // Which app to open at startup instead of beginning on the character
    // screen, and which of its screens: the apps page with left/right as
    // usual, this only saves pressing them to capture a given screen.
    // 0 = none (the game's own start), 1 = Database, 2 = Status, 3 = Camp,
    // 4 = a random Battle (which has no menu entry of its own).
    var _sliceApp as Number = 0;
    var _probeStatusScreen as Number = 0;
    // A scripted input sequence, one event per frame from frame 5, so a
    // capture can reach a screen several presses deep. It goes through
    // dispatch() like a real press, so the probe exercises the input path
    // rather than reaching around it.
    var _probeInputs as Array<Number> = [];
    var _probeInputAt as Number = 0;
    // Which converted animation to play, traced, for tools/verify_anim.py:
    // -1 plays none. The arguments match the ones the C# harness synthesises
    // (every int is 1), so the two traces are of the same run.
    var _probeAnim as Number = 1;
    var _probeAnimDone as Boolean = false;
    // The roll the animation probe pins Kaisa.Rand to, so an animation whose
    // length depends on one can be diffed; -1 leaves the RNG alone.
    var _probeRand as Number = 17;
    const PROBE_STEPS_PER_FRAME = 10;

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
            startGame(root);
        }
    }

    // The game proper: GameManager, the screen manager and LogicManager's
    // screen state machine, with input routed at the state machine rather than
    // at one app. What the original does in GameManager.Awake.
    function startGame(root as ContainerBuilder) as Void {
        var db = new Database(_data);
        db.load();
        var record = _save.readSlot(0);
        var isNewGame = (record == null);
        if (record == null) { record = _save.createDefault("PLAYER"); }
        seedSkeletonStats(record);
        var saved = new SavedGame(_save, 0, record);
        _gm = new GameManager(_data, db, saved);

        var screenMgr = new ScreenManager(_gm, root);
        _gm.attachScreenManager(screenMgr);

        // A save that did not exist is a new game, which is what
        // GameManager.CreateNewGame is for: it seeds the save, sets the worlds
        // up and plays the opening animation. The character-selection screen
        // that would choose the character is not converted yet, so the default
        // record's character stands in.
        //
        // The animation probe wants an empty display, so it skips all of it
        // and only makes sure the worlds are set up.
        if (isNewGame && _probeAnim < 0) {
            _gm.createNewGame(record.gameChar);
            saved.commit();
        } else if (_gm.worldMgr.getBossOfCurrentArea() < 0) {
            _gm.worldMgr.setupWorlds(
                Kaisa.WellKnown.PLAYER_SPIRIT[record.gameChar]);
            saved.commit();
        }
        // The three blinking overlays run forever and would interleave their
        // events into an animation trace, so the animation probe leaves them
        // off; nothing else in the port depends on them running.
        if (_probeAnim < 0) { screenMgr.startFlashRoutines(); }

        if (_probeAnim >= 0) {
            startAnimProbe();
            return;
        }

        // The character screen is where the original starts, and _sliceApp
        // still lets a capture open one app directly.
        if (_sliceApp == 4) {
            // Battle has no menu entry: the game starts it from an event or a
            // minigame, so the probe calls the same entry point they do.
            _gm.logicMgr.callRandomBattle(false);
        } else if (_sliceApp == 1) {
            _gm.logicMgr.openApp(Kaisa.APP_DATABASE);
        } else if (_sliceApp == 2) {
            _gm.logicMgr.openApp(Kaisa.APP_STATUS);
        } else if (_sliceApp == 3) {
            _gm.logicMgr.openApp(Kaisa.APP_CAMP);
        }
    }

    // Plays one converted animation through the real queue -- so it draws
    // into the same animParent the game gives it -- with the trace on.
    function startAnimProbe() as Void {
        var name = "?";
        var routine = null;
        if (_probeAnim == 0) {
            name = "ChangeDistance";
            routine = new ChangeDistance(_gm, 1, 1);
        } else if (_probeAnim == 1) {
            name = "RewardEmpty";
            routine = new RewardEmpty(_gm);
        } else if (_probeAnim == 2) {
            name = "PaySpiritPower";
            routine = new PaySpiritPower(_gm, 1, 1);
        } else if (_probeAnim == 3) {
            name = "AWardSpiritPower";
            routine = new AWardSpiritPower(_gm, 1);
        } else if (_probeAnim == 4) {
            name = "CharHappyShort";
            routine = new CharHappyShort(_gm);
        } else if (_probeAnim == 5) {
            name = "CharHappy";
            routine = new CharHappy(_gm);
        } else if (_probeAnim == 6) {
            name = "OpenCamp";
            routine = new OpenCamp(_gm, _gm.characterSprites(Kaisa.CHAR_TAKUYA));
        } else if (_probeAnim == 7) {
            name = "CloseCamp";
            routine = new CloseCamp(_gm, _gm.characterSprites(Kaisa.CHAR_TAKUYA));
        } else if (_probeAnim == 9) {
            name = "LaunchAttack";
            // The harness synthesises attack 1, isEnemy false, disobeyed
            // false, and a battle sprite set at energy rank 1.
            routine = new LaunchAttack(_gm,
                _gm.getAllDigimonBattleSprites(_demoIndex, 1), 1, false, false);
        } else if (_probeAnim == 10) {
            name = "AttackCollision";
            // The harness synthesises crush against crush with the enemy
            // winning, and a battle sprite set at energy rank 1 for both.
            routine = new AttackCollision(_gm, 1,
                _gm.getAllDigimonBattleSprites(_demoIndex, 1), 1,
                _gm.getAllDigimonBattleSprites(_demoIndex, 1), 1);
        } else if (_probeAnim == 11) {
            name = "DestroyLoser";
            var loserSprites = _gm.getAllDigimonBattleSprites(_demoIndex, 1);
            routine = new DestroyLoser(_gm, loserSprites, 1,
                                       _gm.digimonSprite(_demoIndex, _gm.data.ACTION_BASE),
                                       false, 1, 1);
        } else if (_probeAnim == 12) {
            name = "DisplayTurn";
            routine = new DisplayTurn(_gm, _demoIndex, 1, 1, _demoIndex, 1, 1,
                                      1, false, 1, 1);
        } else if (_probeAnim == 13) {
            name = "SummonDigimon";
            routine = new SummonDigimon(_gm, _demoIndex);
        } else if (_probeAnim == 14) {
            name = "UnlockDigimon";
            routine = new UnlockDigimon(_gm, _demoIndex, false);
        } else if (_probeAnim == 15) {
            name = "RegularEvolution";
            routine = new RegularEvolution(_gm, _demoIndex, _demoIndex);
        } else if (_probeAnim == 16) {
            name = "SpiritEvolution";
            routine = new SpiritEvolution(_gm, Kaisa.CHAR_TAKUYA, _demoIndex);
        } else if (_probeAnim == 17) {
            name = "FusionSpiritEvolution";
            routine = new FusionSpiritEvolution(_gm, Kaisa.CHAR_TAKUYA, _demoIndex);
        } else if (_probeAnim == 18) {
            name = "AncientEvolution";
            routine = new AncientEvolution(_gm, Kaisa.CHAR_TAKUYA, _demoIndex);
        } else if (_probeAnim == 19) {
            name = "CharSadShort";
            routine = new CharSadShort(_gm);
        } else if (_probeAnim == 20) {
            name = "CharSad";
            routine = new CharSad(_gm);
        } else if (_probeAnim == 21) {
            name = "LevelUp";
            routine = new LevelUp(_gm, 1, 1);
        } else if (_probeAnim == 22) {
            name = "LevelDown";
            routine = new LevelDown(_gm, 1, 1);
        } else if (_probeAnim == 23) {
            name = "RewardDistance";
            routine = new RewardDistance(_gm, false, 1, 1);
        } else if (_probeAnim == 24) {
            name = "RewardSpiritPower";
            routine = new RewardSpiritPower(_gm, false, 1, 1);
        } else if (_probeAnim == 25) {
            name = "LevelUpDigimon";
            routine = new LevelUpDigimon(_gm, _demoIndex);
        } else if (_probeAnim == 26) {
            name = "EraseDigimon";
            routine = new EraseDigimon(_gm, _demoIndex);
        } else if (_probeAnim == 27) {
            name = "LevelDownDigimon";
            routine = new LevelDownDigimon(_gm, _demoIndex);
        } else if (_probeAnim == 28) {
            name = "RewardCode";
            // The harness synthesises the code the same way: a `code`
            // parameter is the literal "vsjk1".
            routine = new RewardCode(_gm, _demoIndex, "vsjk1");
        } else if (_probeAnim == 29) {
            name = "DisplayNewArea";
            routine = new DisplayNewArea(_gm, 0, 1, 1);
        } else if (_probeAnim == 30) {
            name = "DataStorm";
            routine = new DataStorm(_gm, _gm.characterSprites(Kaisa.CHAR_TAKUYA), false);
        } else if (_probeAnim == 31) {
            name = "StartGameAnimation";
            routine = new StartGameAnimation(_gm, Kaisa.CHAR_TAKUYA, _demoIndex, 1,
                                             _demoIndex, 1);
        } else if (_probeAnim == 32) {
            name = "EncounterEnemy";
            routine = new EncounterEnemy(_gm, _demoIndex, 1.0);
        } else if (_probeAnim == 33) {
            name = "EncounterBoss";
            routine = new EncounterBoss(_gm, _demoIndex);
        } else if (_probeAnim == 34) {
            name = "SpendCallPoints";
            routine = new SpendCallPoints(_gm, 1, 1);
        } else if (_probeAnim == 35) {
            name = "DeportSprite";
            routine = new DeportSprite(_gm,
                _gm.digimonSprite(_demoIndex, _gm.data.ACTION_BASE), 24);
        } else if (_probeAnim == 36) {
            name = "DeportDigimon";
            routine = new DeportDigimon(_gm, _demoIndex);
        } else if (_probeAnim == 37) {
            name = "DeportSpirit";
            routine = new DeportSpirit(_gm, _demoIndex, Kaisa.CHAR_TAKUYA);
        } else if (_probeAnim == 38) {
            name = "ReceiveSpirit";
            routine = new ReceiveSpirit(_gm, _demoIndex);
        } else if (_probeAnim == 39) {
            name = "LoseSpirit";
            routine = new LoseSpirit(_gm, _demoIndex, _demoIndex);
        } else if (_probeAnim == 40) {
            name = "AwardDistance";
            routine = new AwardDistance(_gm, 1, 1, 1);
        } else if (_probeAnim == 41) {
            name = "TravelMap";
            routine = new TravelMap(_gm, 0, 1, 1, 1.0);
        } else if (_probeAnim == 42) {
            name = "ForcedTravelMap";
            routine = new ForcedTravelMap(_gm, 0, 1, 1, 1);
        } else if (_probeAnim == 43) {
            name = "DestroyBox";
            routine = new DestroyBox(_gm);
        } else if (_probeAnim == 44) {
            name = "BoxResists";
            routine = new BoxResists(_gm, _demoIndex);
        } else if (_probeAnim == 45) {
            name = "BoostFailed";
            routine = new BoostFailed(_gm, _demoIndex);
        } else if (_probeAnim == 46) {
            name = "BoostSucceed";
            routine = new BoostSucceed(_gm, _demoIndex, _demoIndex);
        } else if (_probeAnim == 47) {
            name = "EnemyEscapes";
            routine = new EnemyEscapes(_gm, _demoIndex, _demoIndex);
        } else if (_probeAnim == 48) {
            name = "TransitionToMap1";
            // The animation reads the player's position out of WorldManager,
            // so the probe puts it where the reference's stub keeps it:
            // world 0, area 0, 100 km to go.
            _gm.saved.record.currentMap = 0;
            _gm.saved.record.currentArea = 0;
            _gm.saved.record.currentDistance = 100;
            routine = new TransitionToMap1(_gm, Kaisa.CHAR_TAKUYA);
        } else if (_probeAnim == 49) {
            name = "LoadCharacterSelection";
            routine = new LoadCharacterSelection(_gm);
        } else if (_probeAnim == 50) {
            name = "StartAppDigiHunter";
            routine = new StartAppDigiHunter(_gm, null);
        } else if (_probeAnim == 8) {
            name = "SwapDDock";
            // The animation reads the dock it is about to overwrite, so the
            // dock has to hold something -- as it does in the reference, whose
            // stub dock is never empty.
            _gm.logicMgr.setDDockDigimon(1, _demoIndex);
            routine = new SwapDDock(_gm, 1, _demoIndex);
        }
        if (_probeRand >= 0) { Kaisa.Rand.forced = _probeRand; }
        System.println("=== " + name + " ===");
        // Enqueueing builds the Anim Parent container the animation draws
        // into; the trace goes on after that, so what it records is the
        // animation and nothing of the host around it.
        _gm.enqueueAnimation(routine);
        Kaisa.Trace.enabled = true;
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
        record.ddockDigimon[1] = _demoIndex;
        // A locked database is an empty database: unlock a spread of Digimon
        // so the gallery, the pages and the spirit menu all have something in
        // them. Level 1 is "owned at base level" (LogicManager's off-by-one).
        for (var i = 0; i < record.digimonLevel.size(); i += 4) {
            record.digimonLevel[i] = 1;
        }
        record.digimonLevel[_demoIndex] = 3;
        record.digicodeUnlocked[_demoIndex] = true;
    }

    // port of InputManager.cs: the adapter's twelve abstract events go to
    // LogicManager, which either handles them itself or passes them to the
    // loaded app. Input is dropped entirely while an animation is playing,
    // which is what gm.LockInput does in the original.
    function dispatch(event as Number) as Void {
        if (_gm == null || _gm.isInputLocked) { return; }
        var lm = _gm.logicMgr;
        if (event == Kaisa.Input.EVT_A) { lm.inputA(); }
        else if (event == Kaisa.Input.EVT_A_DOWN) { lm.inputADown(); }
        else if (event == Kaisa.Input.EVT_A_UP) { lm.inputAUp(); }
        else if (event == Kaisa.Input.EVT_B) { lm.inputB(); }
        else if (event == Kaisa.Input.EVT_B_DOWN) { lm.inputBDown(); }
        else if (event == Kaisa.Input.EVT_B_UP) { lm.inputBUp(); }
        else if (event == Kaisa.Input.EVT_LEFT) { lm.inputLeft(); }
        else if (event == Kaisa.Input.EVT_LEFT_DOWN) { lm.inputLeftDown(); }
        else if (event == Kaisa.Input.EVT_LEFT_UP) { lm.inputLeftUp(); }
        else if (event == Kaisa.Input.EVT_RIGHT) { lm.inputRight(); }
        else if (event == Kaisa.Input.EVT_RIGHT_DOWN) { lm.inputRightDown(); }
        else if (event == Kaisa.Input.EVT_RIGHT_UP) { lm.inputRightUp(); }
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
        // What this proves is the round trip -- the record comes back with the
        // right name and the right positional array sizes. It deliberately
        // does not assert particular values: the game now writes to the same
        // slot at its own checkpoints.
        var ok = (existing != null) && existing.name.equals("PLAYER")
            && existing.digimonLevel.size() == _data.digimonCount();
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
        if (_probeInputAt < _probeInputs.size() && _frame > 4) {
            dispatch(_probeInputs[_probeInputAt]);
            _probeInputAt += 1;
        }
        if (_gm != null && _probeAnim >= 0) {
            // The probe steps the runner several times per frame. Every event
            // is timestamped with its SCHEDULED time and the step size is
            // unchanged, so the trace is identical -- but a 52-second
            // animation no longer takes 52 seconds of the verifier's time.
            for (var n = 0; n < PROBE_STEPS_PER_FRAME; n += 1) {
                _gm.runner.advance(TICK_MS.toDouble());
                _gm.screenMgr.updateQueue();
            }
            if (!_probeAnimDone && !_gm.screenMgr.playingAnimations) {
                _probeAnimDone = true;
                System.println("ANIMEND");
                // The probe is done; leaving the app running costs the
                // verifier its whole two-minute monkeydo timeout per
                // animation, which is most of what a run takes.
                System.exit();
            }
            return;
        }
        if (_gm != null) {
            _gm.runner.advance(TICK_MS.toDouble());
            _gm.screenMgr.updateQueue();
            // PlayerCharacter.UpdateSprite runs on a 0.5 s InvokeRepeating,
            // which is ten frames.
            if (_frame % 10 == 0) { _gm.playerChar.updateSprite(); }
            _gm.screenMgr.updateDisplay();
            var app = _gm.logicMgr.loadedApp;
            if (app != null) { app.tick(TICK_MS); }
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
