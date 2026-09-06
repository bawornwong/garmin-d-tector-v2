import Toybox.Lang;
import Toybox.Math;

// port of Logic/LogicManager.cs -- the player-stat half of it.
//
// LogicManager.cs is 857 lines and reaches into every app, the animation
// queue and the world map. This carries the parts the Status and Database
// screens need, translated line for line; the rest arrives with the apps that
// call it, and each addition keeps its `port of` line so the two files stay
// diffable (ticket 11 decision 6).
//
// The level formulas are the ones ticket 14 measured and
// tools/verify_numeric.py re-checks: compute in Float, floor last.
class LogicManager {
    var _saved as SavedGame;
    var _db as Database;
    var _gm as GameManager?;

    // LogicManager.cs:19 -- the screen state machine's own fields. The comment
    // at the top of the original file is the rule that governs them: "All
    // menus should have their option set when they are open, not when they are
    // closed."
    var currentScreen as Number = Kaisa.SCREEN_CHARACTER;
    var currentMainMenu as Number = Kaisa.MAIN_MENU_MAP;
    var charSelectionIndex as Number = 0;
    var gamesMenuIndex as Number = 0;
    var gamesRewardMenuIndex as Number = 0;
    var gamesTravelMenuIndex as Number = 0;

    var loadedApp as DigiviceApp?;
    var isEventPending as Boolean = false;

    function initialize(saved as SavedGame, db as Database) {
        _saved = saved;
        _db = db;
    }

    // GameManager builds the managers before it can hand them itself, so the
    // back-reference is set once construction is done.
    function setGameManager(gm as GameManager) as Void {
        _gm = gm;
    }

    function isAppLoaded() as Boolean {
        return loadedApp != null;
    }

    // --- Input management (LogicManager.cs:41) ---

    function inputA() as Void {
        if (currentScreen == Kaisa.SCREEN_CHARACTER) {
            if (isEventPending) {
                _gm.audioMgr.playButtonA();
                triggerEvent();
            } else {
                _gm.audioMgr.playButtonA();
                openGameMenu();
            }
        } else if (currentScreen == Kaisa.SCREEN_MAIN_MENU) {
            if (currentMainMenu == Kaisa.MAIN_MENU_CAMP) {
                _gm.audioMgr.playButtonA();
                openApp(Kaisa.APP_CAMP);
            } else if (_gm.isCharacterDefeated()) {
                _gm.audioMgr.playButtonB();
            } else if (currentMainMenu == Kaisa.MAIN_MENU_MAP) {
                _gm.audioMgr.playButtonA();
                openApp(Kaisa.APP_MAP);
            } else if (currentMainMenu == Kaisa.MAIN_MENU_STATUS) {
                _gm.audioMgr.playButtonA();
                openApp(Kaisa.APP_STATUS);
            } else if (currentMainMenu == Kaisa.MAIN_MENU_GAME) {
                _gm.audioMgr.playButtonA();
                gamesMenuIndex = 0;
                currentScreen = Kaisa.SCREEN_GAMES_MENU;
            } else if (currentMainMenu == Kaisa.MAIN_MENU_DATABASE) {
                _gm.audioMgr.playButtonA();
                openApp(Kaisa.APP_DATABASE);
            } else if (currentMainMenu == Kaisa.MAIN_MENU_DIGITS) {
                _gm.audioMgr.playButtonA();
                openApp(Kaisa.APP_CODE_INPUT);
            }
        } else if (currentScreen == Kaisa.SCREEN_APP) {
            loadedApp.inputA();
        } else if (currentScreen == Kaisa.SCREEN_GAMES_MENU) {
            _gm.audioMgr.playButtonA();
            if (gamesMenuIndex == 0) {
                _gm.audioMgr.playButtonA();
                openApp(Kaisa.APP_FINDER);
            } else if (gamesMenuIndex == 1) {
                gamesRewardMenuIndex = 0;
                currentScreen = Kaisa.SCREEN_GAMES_REWARD_MENU;
            } else {
                gamesTravelMenuIndex = 0;
                currentScreen = Kaisa.SCREEN_GAMES_TRAVEL_MENU;
            }
        } else if (currentScreen == Kaisa.SCREEN_GAMES_REWARD_MENU) {
            if (gamesRewardMenuIndex == 0) {
                _gm.audioMgr.playButtonA();
                openApp(Kaisa.APP_JACKPOT_BOX);
            }
        } else if (currentScreen == Kaisa.SCREEN_GAMES_TRAVEL_MENU) {
            if (gamesTravelMenuIndex == 0) {
                _gm.audioMgr.playButtonA();
                openApp(Kaisa.APP_SPEED_RUNNER);
            } else if (gamesTravelMenuIndex == 2) {
                _gm.audioMgr.playButtonA();
                openApp(Kaisa.APP_DIGI_HUNTER);
            } else if (gamesTravelMenuIndex == 3) {
                _gm.audioMgr.playButtonA();
                openApp(Kaisa.APP_MAZE);
            }
        } else if (currentScreen == Kaisa.SCREEN_CHAR_SELECTION) {
            _gm.audioMgr.playButtonA();
            // SelectCharacterAndCreateGame: new-game creation is not
            // translated yet (it belongs with the Map app and the world
            // rules SPEC section 8 lists as unsurveyed).
        }
    }

    function inputB() as Void {
        if (currentScreen == Kaisa.SCREEN_CHARACTER) {
            if (isEventPending) {
                _gm.audioMgr.playButtonB();
                triggerEvent();
            } else {
                // The original also has a shortcut here that takes a step when
                // CurrentDistance == 1, standing in for shaking the phone;
                // TakeAStep belongs to the world rules and is not translated.
                _gm.audioMgr.playButtonB();
            }
        } else if (currentScreen == Kaisa.SCREEN_MAIN_MENU) {
            _gm.audioMgr.playButtonB();
            closeGameMenu();
        } else if (currentScreen == Kaisa.SCREEN_APP) {
            loadedApp.inputB();
        } else if (currentScreen == Kaisa.SCREEN_GAMES_MENU) {
            _gm.audioMgr.playButtonB();
            currentScreen = Kaisa.SCREEN_MAIN_MENU;
        } else if (currentScreen == Kaisa.SCREEN_GAMES_REWARD_MENU) {
            _gm.audioMgr.playButtonB();
            currentScreen = Kaisa.SCREEN_GAMES_MENU;
        } else if (currentScreen == Kaisa.SCREEN_GAMES_TRAVEL_MENU) {
            _gm.audioMgr.playButtonB();
            currentScreen = Kaisa.SCREEN_GAMES_MENU;
        } else if (currentScreen == Kaisa.SCREEN_CHAR_SELECTION) {
            _gm.audioMgr.playButtonB();
        }
    }

    function inputLeft() as Void {
        inputSide(Kaisa.DIR_LEFT);
    }

    function inputRight() as Void {
        inputSide(Kaisa.DIR_RIGHT);
    }

    // InputLeft and InputRight are the same method with the direction and the
    // circular-add sign flipped.
    function inputSide(dir as Number) as Void {
        var delta = (dir == Kaisa.DIR_LEFT) ? -1 : 1;
        if (isEventPending) {
            _gm.audioMgr.playButtonA();
            triggerEvent();
        } else if (currentScreen == Kaisa.SCREEN_APP) {
            if (dir == Kaisa.DIR_LEFT) { loadedApp.inputLeft(); }
            else { loadedApp.inputRight(); }
        } else if (currentScreen == Kaisa.SCREEN_CHARACTER) {
            _gm.audioMgr.playButtonA();
            openGameMenu();
        } else if (currentScreen == Kaisa.SCREEN_MAIN_MENU) {
            _gm.audioMgr.playButtonA();
            // NavigateMenu<T> walks the enum with Next()/Last(); MainMenu has
            // seven members.
            currentMainMenu = (dir == Kaisa.DIR_LEFT)
                ? Kaisa.Enums.last(currentMainMenu, 7)
                : Kaisa.Enums.next(currentMainMenu, 7);
        } else if (currentScreen == Kaisa.SCREEN_GAMES_MENU) {
            _gm.audioMgr.playButtonA();
            gamesMenuIndex = Kaisa.MathExt.circularAdd(gamesMenuIndex, delta, 2, 0);
        } else if (currentScreen == Kaisa.SCREEN_GAMES_REWARD_MENU) {
            _gm.audioMgr.playButtonA();
            gamesRewardMenuIndex = Kaisa.MathExt.circularAdd(gamesRewardMenuIndex, delta, 2, 0);
        } else if (currentScreen == Kaisa.SCREEN_GAMES_TRAVEL_MENU) {
            _gm.audioMgr.playButtonA();
            gamesTravelMenuIndex = Kaisa.MathExt.circularAdd(gamesTravelMenuIndex, delta, 3, 0);
        } else if (currentScreen == Kaisa.SCREEN_CHAR_SELECTION) {
            _gm.audioMgr.playButtonA();
            charSelectionIndex = Kaisa.MathExt.circularAdd(charSelectionIndex, delta, 5, 0);
        }
    }

    // The down/up halves only ever reach a loaded app.
    function inputADown() as Void { if (currentScreen == Kaisa.SCREEN_APP) { loadedApp.inputADown(); } }
    function inputBDown() as Void { if (currentScreen == Kaisa.SCREEN_APP) { loadedApp.inputBDown(); } }
    function inputLeftDown() as Void { if (currentScreen == Kaisa.SCREEN_APP) { loadedApp.inputLeftDown(); } }
    function inputRightDown() as Void { if (currentScreen == Kaisa.SCREEN_APP) { loadedApp.inputRightDown(); } }
    function inputAUp() as Void { if (currentScreen == Kaisa.SCREEN_APP) { loadedApp.inputAUp(); } }
    function inputBUp() as Void { if (currentScreen == Kaisa.SCREEN_APP) { loadedApp.inputBUp(); } }
    function inputLeftUp() as Void { if (currentScreen == Kaisa.SCREEN_APP) { loadedApp.inputLeftUp(); } }
    function inputRightUp() as Void { if (currentScreen == Kaisa.SCREEN_APP) { loadedApp.inputRightUp(); } }

    // The pending-event delegate. Events belong to the world rules, so for now
    // nothing sets isEventPending and this only clears it.
    function triggerEvent() as Void {
        isEventPending = false;
    }

    // LogicManager.cs:311
    function openGameMenu() as Void {
        currentMainMenu = 0;
        currentScreen = Kaisa.SCREEN_MAIN_MENU;
    }

    function closeGameMenu() as Void {
        currentScreen = Kaisa.SCREEN_CHARACTER;
    }

    // The Open* methods are one shape repeated fifteen times in the original;
    // here they are that shape once, since AppLoader already switches on the
    // App enum. An app that is not translated yet returns null, and the menu
    // stays where it was.
    function openApp(app as Number) as Void {
        var loaded = _gm.appLoader.loadApp(app, self, _gm.screenMgr.screenDisplay);
        if (loaded == null) { return; }
        currentScreen = Kaisa.SCREEN_APP;
        loadedApp = loaded;
        loadedApp.startApp();
    }

    // LogicManager.cs:381 -- IAppController.CloseLoadedApp.
    function closeLoadedApp(newScreen as Number) as Void {
        if (loadedApp == null) { return; }

        // The CodeInput branch (unlock the entered Digimon, then three
        // animations) waits on CodeInput itself.

        if (isEventPending) { currentScreen = Kaisa.SCREEN_CHARACTER; }
        else { currentScreen = newScreen; }

        loadedApp.dispose();
        loadedApp = null;
        // The save is RAM-resident (ADR 8); closing an app is one of the
        // checkpoints where it is worth writing.
        _saved.commit();
    }

    // LogicManager.cs:449
    function playerExperience() as Number {
        return _saved.playerExperience();
    }

    // LogicManager.cs:453 -- the level of a player from their experience.
    function getPlayerLevel() as Number {
        var playerXP = _saved.playerExperience();
        if (playerXP == 0) { return 1; }

        var level = Math.pow(playerXP, 1.0 / 3.0);
        return Kaisa.MathExt.floorToInt(level);
    }

    // LogicManager.cs:465 -- how far through the current level the player is,
    // where 0 is the level's base experience rather than zero experience.
    function getPlayerLevelProgression() as Float {
        var floorExperience = Kaisa.MathExt.floorToInt(Math.pow(getPlayerLevel(), 3));
        var topExperience = Kaisa.MathExt.floorToInt(Math.pow(getPlayerLevel() + 1, 3));

        var maxExperienceForLevel = topExperience - floorExperience;
        var playerExperienceForLevel = playerExperience() - floorExperience;

        return playerExperienceForLevel.toFloat() / maxExperienceForLevel;
    }

    // LogicManager.cs:477
    function levelUpPlayer() as Void {
        var playerLevel = getPlayerLevel();
        var nextLevelExp = Math.pow(playerLevel + 1, 3.0);
        _saved.setPlayerExperience(Kaisa.MathExt.ceilToInt(nextLevelExp));
    }

    // LogicManager.cs:485. The C# casts the float difference with (int),
    // which truncates toward zero rather than flooring; both values are
    // positive here, so floorToInt matches.
    function levelDownPlayer() as Void {
        var playerLevel = getPlayerLevel();
        var lastLevelExperience = Math.pow(playerLevel - 1, 3.0);
        var thisLevelExperience = Math.pow(playerLevel, 3.0);
        var nextLevelExperience = Math.pow(playerLevel + 1, 3.0);

        var xp = _saved.playerExperience()
            - Kaisa.MathExt.floorToInt(nextLevelExperience - thisLevelExperience);
        if (xp < lastLevelExperience) {
            xp = Kaisa.MathExt.floorToInt(lastLevelExperience);
        }
        _saved.setPlayerExperience(xp);
    }

    // LogicManager.cs:493 -- the setter clamps at both ends.
    function spiritPower() as Number {
        return _saved.spiritPower();
    }

    function setSpiritPower(value as Number) as Void {
        var totalSpiritPower = value;
        if (totalSpiritPower > Kaisa.Constants.MAX_SPIRIT_POWER) { totalSpiritPower = 99; }
        if (totalSpiritPower < 0) { totalSpiritPower = 0; }
        _saved.setSpiritPower(totalSpiritPower);
    }

    // LogicManager.cs:502
    function totalBattles() as Number {
        return _saved.totalBattles();
    }

    function totalWins() as Number {
        return _saved.totalWins();
    }

    function winPercentage() as Float {
        if (totalBattles() == 0) { return 0.0; }
        return totalWins().toFloat() / totalBattles();
    }

    function increaseTotalBattles() as Number {
        var v = _saved.totalBattles() + 1;
        _saved.setTotalBattles(v);
        return v;
    }

    function increaseTotalWins() as Number {
        var v = _saved.totalWins() + 1;
        _saved.setTotalWins(v);
        return v;
    }

    // LogicManager.cs:560 region "Digimon data". The original addresses these
    // by name; here the index is the identity (ADR 7).
    function getDDockDigimon(ddock as Number) as Number {
        return _saved.ddockDigimon(ddock);
    }

    // LogicManager.cs:559 -- "unlocked" is a stored level above zero.
    function getDigimonUnlocked(digimonIndex as Number) as Boolean {
        return _saved.digimonLevel(digimonIndex) > 0;
    }

    // LogicManager.cs:584
    function getDigimonExtraLevel(digimonIndex as Number) as Number {
        return _saved.digimonLevel(digimonIndex) - 1;
    }

    // LogicManager.cs:563 -- clamps to the Digimon's own maximum, and cannot
    // be used to LOCK a Digimon (the floor of 1 is on the extra level, so the
    // stored level never goes below 2 through here).
    function setDigimonExtraLevel(digimonIndex as Number, val as Number) as Void {
        var d = _db.getDigimon(digimonIndex);
        if (d == null) { return; }
        var v = val;
        var maxExtraLevel = d.maxExtraLevel();
        if (v > maxExtraLevel) { v = maxExtraLevel; }
        if (v < 1) { v = 1; }
        _saved.setDigimonLevel(digimonIndex, v + 1);
    }

    // LogicManager.cs:591
    function getDigicodeUnlocked(digimonIndex as Number) as Boolean {
        return _saved.digicodeUnlocked(digimonIndex);
    }

    function setDigicodeUnlocked(digimonIndex as Number, val as Boolean) as Void {
        _saved.setDigicodeUnlocked(digimonIndex, val);
    }

    // LogicManager.cs:660 -- "The player only has 4 D-Docks."
    function setDDockDigimon(ddock as Number, digimonIndex as Number) as Void {
        if (ddock > 3) { return; }
        _saved.setDDockDigimon(ddock, digimonIndex);
    }

    // LogicManager.cs:664. An empty dock is -1 here, "" in the original.
    function isDDockEmpty(ddock as Number) as Boolean {
        return _saved.ddockDigimon(ddock) < 0;
    }

    // LogicManager.cs:666 -- only the docks that hold something.
    function getAllDDockDigimon() as Array<Number> {
        var notEmpty = [] as Array<Number>;
        for (var i = 0; i < 4; i += 1) {
            var d = _saved.ddockDigimon(i);
            if (d >= 0) { notEmpty.add(d); }
        }
        return notEmpty;
    }

    // LogicManager.cs:589
    function isDigimonAtMaxLevel(digimonIndex as Number) as Boolean {
        var d = _db.getDigimon(digimonIndex);
        return (d != null) && (getDigimonExtraLevel(digimonIndex) == d.maxExtraLevel());
    }
}
