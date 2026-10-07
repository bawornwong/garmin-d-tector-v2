import Toybox.ActivityMonitor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

// Connect IQ host for the game: loads packed assets and the save, builds the
// screen tree, routes input, advances the 20 fps runner, and draws each frame.
// Debug builds also carry fixed-scene probes for verification.
class DTectorView extends WatchUi.View {
    const CANVAS = 320;
    const SCALE = 10;
    const LCD = 0x819376;   // Preferences.BackgroundColor
    const INK = 0x000000;   // Preferences.ActiveColor
    const TICK_MS = 50;     // the 50 ms floor -> 20 fps
    const DOUBLE_BACK_MS = 1500l;

    var _data as GameData?;
    var _atlas as AtlasCache?;
    var _save as SaveFormat?;
    var _queue as InputQueue?;
    var _timer as Timer.Timer?;
    var _displayAwake as DisplayAwake = new DisplayAwake();
    var _renderer as Renderer?;
    var _root as ContainerBuilder?;
    var _gm as GameManager?;

    var _demoIndex as Number = 0;      // Digimon index used by verification probes
    var _frame as Number = 0;
    var _saveStatus as String = "";
    var _firstBackAt as Number? = null;

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
    // A scripted input sequence, one event per second from frame 5, so a
    // capture can reach a screen several presses deep and a smoke test can
    // walk the game unattended. It goes through dispatch() like a real press,
    // so the probe exercises the input path rather than reaching around it,
    // and each press prints where the game was when it landed.
    // A smoke tour: open the menu, walk it, open Status, back out, open the
    // Database, back out, open the Map, back out.
    var _probeInputs as Array<Number> = [];
    const PROBE_INPUT_EVERY = 20;       // one scripted press per second
    var _probeInputAt as Number = 0;
    // Which converted animation to play, traced, for tools/verify_anim.py:
    // -1 plays none. The arguments match the ones the C# harness synthesises
    // (every int is 1), so the two traces are of the same run.
    var _probeAnim as Number = -1;
    var _probeAnimDone as Boolean = false;
    // Draws the Status app's screens for tools/verify_screens.py.
    var _probeScreens as Boolean = false;
    // How many frames to dump the display list for, every tenth frame: what a
    // frame actually draws, in draw order, for when a rendering question needs
    // the frame rather than a guess. 0 is off.
    var _dumpFrames as Number = 0;
    var _stepSync as JourneyStepSync = new JourneyStepSync();
    var _stepReader as GarminStepReader = new GarminStepReader();
    var _shake as ShakeDetector = new ShakeDetector();
    var _shakeRunning as Boolean = false;
    var _pendingShakes as Number = 0;
    var _shown as Boolean = false;
    var _stepRefreshRequested as Boolean = true;
    var _resumeStepSample as Boolean = true;
    var _waitingForSave as Boolean = false;
    var _reloadOnShow as Boolean = false;
    var _historyDay as Number = 0;
    var _historyAt as Number = 0;
    // Clear the walking pose after 150 frames without a shake.
    const WALK_IDLE_FRAMES = 150;
    var _idleFrames as Number = 0;
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

    function isProbeMode() as Boolean {
        return _probeIndex >= 0 || _probeText || _probeScreens || _probeAnim >= 0
            || _probeInputs.size() > 0 || _sliceApp > 0 || _dumpFrames > 0;
    }

    function onLayout(dc as Dc) as Void {
        _data = new GameData();
        _data.load();
        _atlas = new AtlasCache();
        _atlas.load();
        Kaisa.Prefs.load();
        _save = new SaveFormat(_data);

        var origin = (dc.getWidth() - CANVAS) / 2;
        _renderer = new Renderer(_atlas, new TextRenderer(_atlas),
                                 origin, origin, SCALE, INK, LCD);

        _demoIndex = findDigimon("agumon");
        if (!isProbeMode() && !_save.access.tryForeground()) {
            _waitingForSave = true;
            _root = new ContainerBuilder();
            _root.setName("Root");
            _root.setSize(Kaisa.Constants.SCREEN_WIDTH,
                          Kaisa.Constants.SCREEN_HEIGHT).setTransparent(true);
        } else {
            inspectSave();
            buildScene();
        }
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
        _stepSync = new JourneyStepSync();
        var db = new Database(_data);
        db.load();
        var record = _save.readSlot(0);
        // GameManager.cs:88 -- a game is new when no character has been chosen,
        // not when the file is missing: the original writes a save before the
        // player picks, and asks `SavedGame.PlayerChar == GameChar.none`.
        var isNewGame = (record == null || record.gameChar == Kaisa.CHAR_NONE);
        if (record == null) { record = _save.createDefault("PLAYER"); }
        // The skeleton stats are scaffolding for the verification probes only.
        // A player's save is whatever they have played; seeding it made a
        // fresh game start at level 18 with 9 wins, and made a reset look
        // like it had done nothing.
        if (_probeScreens || _probeAnim >= 0) {
            seedSkeletonStats(record);
            // A real new game sets this to 300 (GameManager.createNewGame);
            // a probe record skips that, and seedSkeletonStats itself skips
            // re-seeding once playerExperience is already nonzero from an
            // earlier probe launch persisted in the simulator's own
            // Storage -- so this is unconditional, every launch, rather
            // than folded into seedSkeletonStats's one-time seed. Left at
            // SaveFormat's raw class default of 0, `WorldManager.takeSteps`
            // sees `stepsToNextEvent <= 0` and arms a pending event on the
            // FIRST step any probed animation happens to take; that event
            // commits to Storage and leaks into every later probe in the
            // same simulator session -- which is why an unrelated
            // animation's queue-drain (ScreenManager.cs:101's
            // checkPendingEvents, on ANY animation's completion) started
            // firing a stray "sound triggerEvent" nowhere in the golden
            // reference. Found chasing 0/53 down to a single trailing event
            // that survived even with sound entirely muted.
            record.pendingEvent = 0;
            record.stepsToNextEvent = 300;
            // tools/anim_golden's Builders.cs hardcodes GameChar.takuya as
            // PlayerChar for every probe. CharSad/CharSadShort read
            // gm.saved.playerChar() rather than taking a character argument
            // (unlike OpenCamp/CloseCamp below, which are passed
            // Kaisa.CHAR_TAKUYA explicitly), so their sprites only match the
            // reference if the record agrees. Left to whatever gameChar was
            // persisted in the simulator's Storage, it does not.
            record.gameChar = Kaisa.CHAR_TAKUYA;
        }
        var saved = new SavedGame(_save, 0, record);
        _gm = new GameManager(_data, db, saved);
        _gm.saveFormat = _save;
        // A probe measures scheduled TIME, and the trace it compares carries
        // the sound's NAME and that time -- both of which are emitted either
        // way, so muting changes nothing a golden diff reads. What it skips
        // is the real Attention call, which on this dev machine fails to
        // preview through the simulator's own audio stack (a Core Audio
        // load error, once per tone, each one a modal dialog that stalls an
        // unattended run) and costs wall-clock time besides. Same discipline
        // as pinning the RNG: a probe should not be at the mercy of the host
        // machine's speaker.
        if (_probeScreens || _probeAnim >= 0) { _gm.audioMgr.muted = true; }

        var screenMgr = new ScreenManager(_gm, root);
        _gm.attachScreenManager(screenMgr);

        // The save is the save: the game carries on where it was left, and
        // the only way to a new one is the menu's own reset. A save with no
        // character chosen has not started yet, so it goes to the selection
        // with its intro -- which is what a reset leaves behind too.
        if (_probeAnim < 0 && !_probeScreens) {
            if (isNewGame) {
                _gm.logicMgr.currentScreen = Kaisa.SCREEN_CHAR_SELECTION;
                _gm.enqueueAnimation(new LoadCharacterSelection(_gm));
            } else {
                _gm.logicMgr.currentScreen = Kaisa.SCREEN_CHARACTER;
                _gm.checkLeaverBuster();
                if (record.wasV2 || record.stepSync.gameGeneration == 0l) {
                    _stepSync.beginGame(record, _stepReader.read(true));
                    saved.touch();
                    _stepSync.flush(saved);
                }
                sampleWatchSteps(true);
                if (!_stepSync.isBlocked()) { _gm.checkPendingEvents(); }
            }
        }

        if (isNewGame && record.wasV2 && !isProbeMode()) {
            saved.touch();
            _stepSync.flush(saved);
        }

        if (!isNewGame && _gm.worldMgr.getBossOfCurrentArea() < 0) {
            _gm.worldMgr.setupWorlds(
                Kaisa.WellKnown.PLAYER_SPIRIT[record.gameChar]);
            saved.commit();
        }

        // The three blinking overlays run forever and would interleave their
        // events into an animation trace, so the animation probe leaves them
        // off; nothing else in the port depends on them running.
        if (_probeAnim < 0) { screenMgr.startFlashRoutines(); }

        if (_probeScreens && runScreenProbe()) { return; }

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

    // Kaisa.Rand.forced only exists in a debug build, so the assignment has to
    // be annotated too -- a plain call site made the RELEASE build fail to
    // compile, which is the build that gets sideloaded.
    (:debug)
    function pinRand(v as Number) as Void {
        if (v >= 0) { Kaisa.Rand.forced = v; }
    }

    (:release)
    function pinRand(v as Number) as Void {
    }

    // The probes exist only in a debug build, so the call sites are annotated
    // too: naming a `(:debug)` member from an unannotated one compiles in
    // debug and fails the RELEASE build, which is the build that gets
    // sideloaded.
    (:debug)
    function runScreenProbe() as Boolean {
        startScreenProbe();
        return true;
    }

    (:release)
    function runScreenProbe() as Boolean {
        return false;
    }

    (:debug)
    function dumpFrameIfAsked() as Void {
        if (_dumpFrames > 0 && _frame % 10 == 0) {
            System.println("=== frame " + _frame + " ===");
            _renderer.dump(_root, 0);
            _dumpFrames -= 1;
        }
    }

    (:release)
    function dumpFrameIfAsked() as Void {
    }

    // Draws the Status app's seven screens with the numbers the C# harness
    // pins (tools/anim_golden AppFixture), so tools/verify_screens.py can diff
    // what each screen builds against what the ORIGINAL Status.cs builds.
    (:debug)
    function startScreenProbe() as Void {
        var record = _gm.saved.record;
        record.currentDistance = 4321;
        record.steps = 8765;
        record.playerExperience = 12 * 12 * 12;     // level is the cube root
        record.spiritPower = 47;
        record.totalBattles = 9;
        record.totalWins = 4;
        record.ddockDigimon[0] = _demoIndex;
        record.ddockDigimon[1] = _demoIndex;
        record.ddockDigimon[2] = _demoIndex;
        record.ddockDigimon[3] = _demoIndex;

        var app = new Status(_gm, _gm.logicMgr, _gm.screenMgr.screenDisplay);
        for (var i = 0; i < 7; i += 1) {
            System.println("=== Status" + i + " ===");
            Kaisa.Trace.enable();
            app.drawScreen();
            Kaisa.Trace.disable();
            System.println("--- Status" + i + " end=0.0000ms");
            app.inputRight();
        }
        // The Database app's three data pages, with the same Digimon and the
        // same extra level the harness pins. The app is put on the Pages
        // screen directly, as the harness does: reaching it by input would
        // mean walking a gallery neither side is testing here.
        var dbApp = new DatabaseApp(_gm, _gm.logicMgr, _gm.screenMgr.screenDisplay);
        dbApp.currentScreen = dbApp.SCREEN_PAGES;
        dbApp.menuIndex = 0;
        dbApp.pageDigimon = _gm.db.getDigimon(_demoIndex);
        _gm.logicMgr.setDigimonExtraLevel(_demoIndex, 2);
        _gm.logicMgr.setDigicodeUnlocked(_demoIndex, true);

        for (var page = 0; page < 3; page += 1) {
            System.println("=== DatabasePage" + page + " ===");
            dbApp.pageIndex = page;
            dbApp.digimonNameSign = null;
            Kaisa.Trace.enable();
            dbApp.drawScreen();
            Kaisa.Trace.disable();
            System.println("--- DatabasePage" + page + " end=0.0000ms");
        }

        // The Map app's three screens: the map with its area markers, the
        // area selection, and the distance the chosen area costs. World 0 is
        // the multi-map one, so the four-quadrant sheet is drawn too.
        _gm.saved.record.currentMap = 0;
        _gm.saved.record.currentArea = 0;
        _gm.saved.record.currentDistance = 4321;
        var mapApp = new Map(_gm, _gm.logicMgr, _gm.screenMgr.screenDisplay);
        var mapNames = ["MapMap", "MapAreas", "MapDistance"];
        for (var screen = 0; screen < 3; screen += 1) {
            System.println("=== " + mapNames[screen] + " ===");
            Kaisa.Trace.enable();
            if (screen == 0) {
                mapApp.startApp();
            } else {
                mapApp.inputA();
            }
            Kaisa.Trace.disable();
            System.println("--- " + mapNames[screen] + " end=0.0000ms");
        }

        // The Battle app's screens: its main menu, the D-Dock chooser, the
        // combat menu, the attack menu, and the call-point bar the regular
        // evolution draws. The state each screen reads is set directly, as
        // the harness does: reaching them by input would mean playing a whole
        // battle.
        var battle = new Battle(_gm, _gm.logicMgr, _gm.screenMgr.screenDisplay);
        battle.enemyDigimon = _gm.db.getDigimon(_demoIndex);
        battle.friendlyDigimon = _gm.db.getDigimon(_demoIndex);
        battle.availableMenuOptions = [0, 1, 2, 3, 4];
        var battleNames = ["BattleMainMenu0", "BattleMainMenu1", "BattleDDocks",
                           "BattleCombat0", "BattleCombat1", "BattleAttack0",
                           "BattleAttack1", "BattleEvolve"];
        var battleScreens = [battle.SCREEN_MAIN_MENU, battle.SCREEN_MAIN_MENU,
                             battle.SCREEN_DDOCKS, battle.SCREEN_COMBAT_MENU,
                             battle.SCREEN_COMBAT_MENU, battle.SCREEN_ATTACK_MENU,
                             battle.SCREEN_ATTACK_MENU, battle.SCREEN_REGULAR_EVOLVE];
        var battleValues = [0, 1, 0, 0, 1, 0, 1, 2];
        for (var i = 0; i < battleNames.size(); i += 1) {
            battle.currentScreen = battleScreens[i];
            if (i < 2) { battle.menuIndex = battleValues[i]; }
            else if (i == 2) { battle.ddockIndex = battleValues[i]; }
            else if (i < 5) { battle.combatMenuIndex = battleValues[i]; }
            else if (i < 7) { battle.attackIndex = battleValues[i]; }
            else { battle.callPointsForEvolution = battleValues[i]; }

            System.println("=== " + battleNames[i] + " ===");
            Kaisa.Trace.enable();
            battle.drawScreen();
            Kaisa.Trace.disable();
            System.println("--- " + battleNames[i] + " end=0.0000ms");
        }

        // The code-input app: five underscores, the letter being chosen, and
        // the code so far.
        var codeApp = new CodeInput(_gm, _gm.logicMgr, _gm.screenMgr.screenDisplay);
        System.println("=== CodeInputStart ===");
        Kaisa.Trace.enable();
        codeApp.startApp();
        Kaisa.Trace.disable();
        System.println("--- CodeInputStart end=0.0000ms");

        // The DigiHunter board: the clock, the arrows and the nine faces.
        var hunter = new DigiHunter(_gm, _gm.logicMgr, _gm.screenMgr.screenDisplay);
        System.println("=== DigiHunterStart ===");
        Kaisa.Trace.enable();
        hunter.startApp();
        Kaisa.Trace.disable();
        System.println("--- DigiHunterStart end=0.0000ms");

        // Camp: the tent it builds while the character walks off.
        var camp = new Camp(_gm, _gm.logicMgr, _gm.screenMgr.screenDisplay);
        System.println("=== CampStart ===");
        Kaisa.Trace.enable();
        camp.startApp();
        Kaisa.Trace.disable();
        System.println("--- CampStart end=0.0000ms");

        // The Jackpot Box's two screens: the keypad, and the blank it shows
        // while the pattern plays.
        var jackpot = new JackpotBox(_gm, _gm.logicMgr, _gm.screenMgr.screenDisplay);
        for (var screen = 0; screen < 2; screen += 1) {
            jackpot.currentScreen = screen;
            System.println("=== Jackpot" + screen + " ===");
            Kaisa.Trace.enable();
            jackpot.drawScreen();
            Kaisa.Trace.disable();
            System.println("--- Jackpot" + screen + " end=0.0000ms");
        }

        // SpeedRunner's board: the lane line, the rocket, the asteroid rows
        // and the finish. Its level generation rolls dice, but only to decide
        // which asteroids are shown later; what startApp BUILDS is fixed.
        var runner = new SpeedRunner(_gm, _gm.logicMgr, _gm.screenMgr.screenDisplay);
        System.println("=== SpeedRunnerStart ===");
        Kaisa.Trace.enable();
        runner.startApp();
        Kaisa.Trace.disable();
        System.println("--- SpeedRunnerStart end=0.0000ms");

        System.println("SCREENEND");
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
            routine = new EncounterEnemy(_gm, _demoIndex, 1.0, null, null);
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
        } else if (_probeAnim == 51) {
            name = "SusanoomonEvolution";
            routine = new SusanoomonEvolution(_gm, Kaisa.CHAR_TAKUYA);
        } else if (_probeAnim == 52) {
            name = "TransitionToMap3";
            // The harness synthesises the stolen-spirit list as agunimon and
            // lobomon, which WellKnown carries as the first spirit of each
            // fusion set.
            routine = new TransitionToMap3(_gm, Kaisa.CHAR_TAKUYA, _demoIndex,
                [Kaisa.WellKnown.SUSANOO_HUMANS[0], Kaisa.WellKnown.SUSANOO_HUMANS[5]]);
        } else if (_probeAnim == 8) {
            name = "SwapDDock";
            // The animation reads the dock it is about to overwrite, so the
            // dock has to hold something -- as it does in the reference, whose
            // stub dock is never empty.
            _gm.logicMgr.setDDockDigimon(1, _demoIndex);
            routine = new SwapDDock(_gm, 1, _demoIndex);
        }
        pinRand(_probeRand);
        System.println("=== " + name + " ===");
        // Enqueueing builds the Anim Parent container the animation draws
        // into; the trace goes on after that, so what it records is the
        // animation and nothing of the host around it.
        _gm.enqueueAnimation(routine);
        Kaisa.Trace.enable();
    }

    // SKELETON SCAFFOLDING for the probes, in RAM only and never committed to
    // a player's save: a fresh save is
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

    // Fifty steps, for testing the journey on a simulator that cannot walk.
    // Debug builds only: the release build has no way to take a step it did
    // not walk.
    (:debug)
    function walkShortcut() as Void {
        if (_gm.logicMgr.shakeDisabled()) { return; }
        for (var i = 0; i < 50 && _gm.saved.savedEvent() == 0; i += 1) {
            _gm.takeAStep();
        }
        _gm.isCharacterWalking = true;
        System.println("WALK 50 -> distance " + _gm.worldMgr.currentDistance()
            + " steps " + _gm.worldMgr.totalSteps());
    }

    (:release)
    function walkShortcut() as Void {
    }

    // Where an input event actually lands, or why it didn't: separate from
    // the gesture-level logging in InputAdapter, which only knows what the
    // touch layer saw, not whether the game acted on it.
    (:debug)
    function logDispatch(where as String, event as Number) as Void {
        System.println("DISPATCH " + Kaisa.Input.eventName(event) + " " + where
            + " anim=" + (_gm.screenMgr.playingAnimations ? "yes" : "no"));
    }

    (:release)
    function logDispatch(where as String, event as Number) as Void {
    }

    function requestStepRefresh() as Void {
        _stepRefreshRequested = true;
    }

    function sampleWatchSteps(fromResume as Boolean) as Void {
        if (isProbeMode() || _gm == null || !_save.access.tryForeground()) {
            _stepRefreshRequested = true;
            return;
        }
        if (fromResume && !_gm.saved.isDirty()) {
            // The background process can only change the fixed header. Keep
            // the foreground model and import its latest source checkpoint.
            var disk = _save.readSlot(0);
            if (disk != null && disk.stepSync.gameGeneration
                    == _gm.saved.record.stepSync.gameGeneration) {
                _gm.saved.record.stepSync = disk.stepSync;
            }
        }
        var day = Time.today().value();
        var now = System.getTimer();
        var age = (now.toLong() - _historyAt.toLong()) & 0xffffffffl;
        var history = fromResume || _historyDay != day || age >= 3600000l;
        var reading = _stepReader.read(history);
        if (history) { _historyDay = day; _historyAt = now; }
        // Visible watch steps and deliberate shakes both count. Only a
        // disabled background interval is checkpointed without travel.
        var backgroundEnabled = BackgroundStepSetting.enabled();
        var traveled = fromResume
            ? _stepSync.reconcileResume(_gm, reading, backgroundEnabled)
            : _stepSync.reconcile(_gm, reading, true);
        logStepSample(reading, traveled);
        _stepRefreshRequested = false;
        // Keep the resume boundary until the disabled interval has a valid
        // live checkpoint. Otherwise a later foreground sample could credit
        // steps from the closed period when Garmin briefly has no reading.
        _resumeStepSample = fromResume && (_stepSync.isBlocked()
            || (!backgroundEnabled && (reading.day == null || reading.steps == null)));
    }

    (:debug)
    function logStepSample(reading as StepObservation, traveled as Number) as Void {
        if (_frame < 80 || traveled > 0) {
            System.println("STEP frame=" + _frame + " day=" + reading.day
                + " count=" + reading.steps + " history=" + reading.history.size()
                + " source=" + _gm.saved.record.stepSync.sourceTotal
                + " credit=" + _gm.saved.record.stepSync.creditedSourceTotal
                + " travel=" + traveled + " distance=" + _gm.worldMgr.currentDistance()
                + " blocked=" + _stepSync.isBlocked());
        }
    }

    (:release)
    function logStepSample(reading as StepObservation, traveled as Number) as Void {
    }

    // port of InputManager.cs: the adapter's twelve abstract events go to
    // LogicManager, which either handles them itself or passes them to the
    // loaded app. Input is dropped entirely while an animation is playing,
    // which is what gm.LockInput does in the original.
    function dispatch(event as Number) as Void {
        if (!isProbeMode() && event != Kaisa.Input.EVT_WALK) {
            _displayAwake.input(System.getTimer());
        }
        if (_gm == null) { return; }
        if (event != Kaisa.Input.EVT_B && event != Kaisa.Input.EVT_B_DOWN
                && event != Kaisa.Input.EVT_B_UP) {
            _firstBackAt = null;
        }
        if (event == Kaisa.Input.EVT_WALK) {
            walkShortcut();
            return;
        }
        if (_gm.isInputLocked) {
            _firstBackAt = null;
            logDispatch("DROPPED (locked)", event);
            return;
        }
        logDispatch("screen=" + _gm.logicMgr.currentScreen, event);
        var lm = _gm.logicMgr;
        // Battle A can finish an event (the last attack or Escape). Read the
        // watch counter while its active marker still blocks travel, so steps
        // taken during the battle do not enter the next event's gate.
        if (!isProbeMode() && event == Kaisa.Input.EVT_A
                && (lm.loadedApp instanceof Battle)
                && (lm.savedEventIsActiveBattle())) {
            sampleWatchSteps(false);
        }
        if (event == Kaisa.Input.EVT_B) {
            if (countBackPress(System.getTimer(), canDoubleBack())) {
                // onStop releases the foreground step lease. Keep the game
                // visible if its final checkpoint cannot be written.
                if (isProbeMode() || _stepSync.flush(_gm.saved)) { System.exit(); }
                return;
            }
        }
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
        if (!canDoubleBack()) { _firstBackAt = null; }
    }

    function canDoubleBack() as Boolean {
        return _gm != null
            && _gm.logicMgr.currentScreen == Kaisa.SCREEN_CHARACTER
            && !_gm.logicMgr.isEventPending && _gm.saved.savedEvent() == 0
            && _gm.worldMgr.currentDistance() != 1;
    }

    // Called only for completed physical Back presses (EVT_B), never from
    // onBack(), which the simulator also emits for unrelated touch gestures.
    function countBackPress(now as Number, eligible as Boolean) as Boolean {
        if (!eligible) { _firstBackAt = null; return false; }
        if (_firstBackAt != null) {
            var elapsed = (now.toLong() - (_firstBackAt as Number).toLong())
                & 0xffffffffl;
            if (elapsed <= DOUBLE_BACK_MS) {
                _firstBackAt = null;
                return true;
            }
        }
        _firstBackAt = now;
        return false;
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

    // Diagnostic only: inspecting a fresh slot must not create a real game
    // with demo levels before the player has chosen a character.
    (:debug)
    function inspectSave() as Void {
        var existing = _save.readSlot(0);
        if (existing == null) {
            _saveStatus = "SAVE EMPTY";
            return;
        }
        var ok = existing.digimonLevel.size() == _data.digimonCount();
        _saveStatus = ok ? "SAVE OK (" + existing.digimonLevel.size() + " digimon)"
                         : "SAVE MISMATCH";
        System.println("SaveFormat: " + _saveStatus);
    }

    (:release)
    function inspectSave() as Void {
    }

    function onShow() as Void {
        _shown = true;
        if (!isProbeMode()) { _displayAwake.show(System.getTimer()); }
        _firstBackAt = null;
        _stepRefreshRequested = true;
        _resumeStepSample = true;
        _timer = new Timer.Timer();
        _timer.start(method(:tick), TICK_MS, true);
        if (!isProbeMode() && _gm != null) {
            sampleWatchSteps(true);
            startShakes();
        }
    }

    function onHide() as Void {
        _displayAwake.hide();
        _firstBackAt = null;
        if (_timer != null) { _timer.stop(); }
        if (_gm != null) { _gm.audioMgr.tickEventReminder(false, 0); }
        flushAndReleaseSteps();
    }

    function flushAndReleaseSteps() as Void {
        _displayAwake.hide();
        if (_shown && !isProbeMode() && _gm != null) {
            sampleWatchSteps(_resumeStepSample);
        }
        stopShakes();
        _shown = false;
        if (_save == null) { return; }
        if (!isProbeMode() && _gm != null && !_stepSync.flush(_gm.saved)) {
            _reloadOnShow = true;
        }
        _save.access.releaseForeground();
    }

    function startShakes() as Void {
        if (_shakeRunning) { return; }
        _shake.reset();
        _pendingShakes = 0;
        try {
            Sensor.registerSensorDataListener(method(:onShakeData), {
                :period => 1,
                :accelerometer => { :enabled => true, :sampleRate => 25 }
            });
            _shakeRunning = true;
        } catch (e) {
            _shakeRunning = false;
        }
    }

    function stopShakes() as Void {
        if (_shakeRunning) {
            try { Sensor.unregisterSensorDataListener(); } catch (e) { }
        }
        _shakeRunning = false;
        _pendingShakes = 0;
        _shake.reset();
    }

    function onShakeData(data as Sensor.SensorData) as Void {
        var accel = data.accelerometerData;
        if (accel == null) { return; }
        _pendingShakes += _shake.count(accel);
        if (_pendingShakes > 8) { _pendingShakes = 8; }
    }

    function tick() as Void {
        _displayAwake.tick(System.getTimer());
        _frame += 1;
        if (_waitingForSave && _save.access.tryForeground()) {
            _waitingForSave = false;
            inspectSave();
            buildScene();
            if (!isProbeMode()) { startShakes(); }
        }
        if (_reloadOnShow && _save.access.tryForeground()) {
            _reloadOnShow = false;
            buildScene();
            if (!isProbeMode()) { startShakes(); }
        }
        if (_queue != null) {
            var events = _queue.drain();
            for (var i = 0; i < events.size(); i += 1) {
                dispatch(events[i]);
            }
        }
        if (_probeInputAt < _probeInputs.size() && _frame > 4
                && _frame % PROBE_INPUT_EVERY == 0) {
            var ev = _probeInputs[_probeInputAt];
            if (_gm != null) {
                System.println("SMOKE f=" + _frame + " send=" + Kaisa.Input.eventName(ev)
                    + " screen=" + _gm.logicMgr.currentScreen
                    + " app=" + ((_gm.logicMgr.loadedApp == null) ? "-" : "yes")
                    + " anim=" + _gm.screenMgr.playingAnimations);
            }
            dispatch(ev);
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
            _gm.audioMgr.tickEventReminder(
                _gm.logicMgr.isEventPending && !_gm.isInputLocked, TICK_MS);
            // PlayerCharacter.UpdateSprite runs on a 0.5 s InvokeRepeating,
            // which is ten frames.
            if (_frame % 10 == 0) { _gm.playerChar.updateSprite(); }
            _gm.tickJackpot(TICK_MS);
            if (_stepRefreshRequested || _frame % 20 == 0) {
                sampleWatchSteps(_resumeStepSample);
            }
            var shakes = _pendingShakes;
            _pendingShakes = 0;
            if (!isProbeMode() && _gm.saved.playerChar() != Kaisa.CHAR_NONE
                    && !_gm.logicMgr.shakeDisabled() && !_stepSync.isBlocked()) {
                for (var i = 0; i < shakes && _gm.saved.savedEvent() == 0; i += 1) {
                    _gm.takeAStep();
                    _idleFrames = 0;
                    _gm.isCharacterWalking = true;
                }
            }
            if (_idleFrames < WALK_IDLE_FRAMES) { _idleFrames += 1; }
            else { _gm.isCharacterWalking = false; }
            _gm.screenMgr.updateDisplay();
            var app = _gm.logicMgr.loadedApp;
            if (app != null) { app.tick(TICK_MS); }
            if (!canDoubleBack()) { _firstBackAt = null; }
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

        dumpFrameIfAsked();
        _renderer.draw(dc, _root);
        drawChrome(dc);
    }

    // Real-device chrome around the emulated 32x32 canvas, entirely outside
    // the 320x320 rect the original's own pixels occupy: two button glyphs
    // in the Left and Right touch sectors, plus the app's name above the
    // canvas.
    function drawChrome(dc as Dc) as Void {
        var midY = dc.getHeight() / 2;
        var origin = (dc.getWidth() - CANVAS) / 2;
        drawSideButton(dc, origin / 2, midY, true);
        drawSideButton(dc, dc.getWidth() - origin / 2, midY, false);

        // Sat too high before: the display is round, and close enough to the
        // true top of the circle the bezel itself clips the ends off a
        // centred line of text. Lower and smaller keeps the whole word inside
        // the part of the top margin the bezel doesn't cut into.
        dc.setColor(LCD, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2,
            origin - dc.getFontHeight(Graphics.FONT_XTINY) - 6,
            Graphics.FONT_XTINY,
            "D-TECTOR", Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Just the chevron, faint: a hint of where to tap rather than a button
    // asking to be pressed. The Left/Right sectors are larger than the glyphs.
    function drawSideButton(dc as Dc, cx as Number, cy as Number, pointLeft as Boolean) as Void {
        var tip = pointLeft ? cx - 9 : cx + 9;
        var back = pointLeft ? cx + 9 : cx - 9;
        dc.setColor(0x3A3A3A, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[tip, cy], [back, cy - 15], [back, cy + 15]] as Array<Graphics.Point2D>);
    }
}
