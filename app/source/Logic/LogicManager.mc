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
    // Which event is waiting on the character screen, in place of the
    // original's `triggerEvent` delegate.
    const EVENT_NONE = 0;
    const EVENT_RANDOM_BATTLE = 1;
    const EVENT_DATA_STORM = 2;
    const EVENT_BOSS_BATTLE = 3;
    var pendingEvent as Number = EVENT_NONE;

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
            selectCharacterAndCreateGame();
        }
    }

    function inputB() as Void {
        if (currentScreen == Kaisa.SCREEN_CHARACTER) {
            if (isEventPending) {
                _gm.audioMgr.playButtonB();
                triggerEvent();
            } else if (_gm.worldMgr.currentDistance() == 1) {
                // "Alternative to shaking the phone to trigger a boss battle."
                _gm.takeAStep();
            } else {
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

    // LogicManager.cs:256 EnqueueRegularEvent / EnqueueBossEvent.
    //
    // The original holds the pending event as a delegate it assigns and adds a
    // clean-up lambda to; Monkey C has no delegates, so the event is a kind
    // (EVENT_* below) and triggerEvent dispatches on it. The clean-up the
    // lambda does -- clearing the saved event and the flag -- happens there
    // too, and in the same order.
    function enqueueRegularEvent() as Void {
        if (loadedApp == null) { currentScreen = Kaisa.SCREEN_CHARACTER; }
        _gm.audioMgr.playSound("triggerEvent");
        isEventPending = true;
        pendingEvent = (Kaisa.Rand.rangeFloat(0.0, 1.0) < 0.85)
            ? EVENT_RANDOM_BATTLE : EVENT_DATA_STORM;
    }

    function enqueueBossEvent() as Void {
        if (loadedApp == null) { currentScreen = Kaisa.SCREEN_CHARACTER; }
        _gm.audioMgr.playSound("triggerEvent");
        isEventPending = true;
        pendingEvent = EVENT_BOSS_BATTLE;
    }

    function triggerEvent() as Void {
        // The event runs first and the clean-up after, because that is the
        // order the original's delegate chain has them in: the battle or the
        // storm starts while the flag is still set.
        if (pendingEvent == EVENT_RANDOM_BATTLE) {
            callRandomBattle(false);            // CallRandomBattleForEvent
        } else if (pendingEvent == EVENT_DATA_STORM) {
            triggerDataStorm();
        } else if (pendingEvent == EVENT_BOSS_BATTLE) {
            callBossBattle();
        }

        _saved.setSavedEvent(0);
        isEventPending = false;
        pendingEvent = EVENT_NONE;
    }

    // LogicManager.cs:809
    function triggerDataStorm() as Void {
        var result = applyDataStorm();
        _gm.enqueueAnimation(new DataStorm(_gm,
            _gm.characterSprites(_saved.playerChar()), result[0] == 1));
    }

    // LogicManager.cs:306
    function selectCharacterAndCreateGame() as Void {
        _gm.createNewGame(charSelectionIndex);
    }

    // LogicManager.cs:289 -- a random battle against a Digimon near the
    // player's level; `reduceDistance` decides whether winning shortens the
    // journey.
    function callRandomBattle(reduceDistance as Boolean) as Void {
        var enemy = _db.getRandomDigimonForBattle(getPlayerLevel());
        if (enemy == null) { return; }
        startBattle(enemy.index, reduceDistance, false);
    }

    // LogicManager.cs:294 -- the boss of the area the player is standing in.
    function callBossBattle() as Void {
        var boss = _gm.worldMgr.getBossOfCurrentArea();
        if (boss < 0) { return; }
        startBattle(boss, true, true);
    }

    // LogicManager.cs:300 CallFixedBattle
    function callFixedBattle(digimonIndex as Number, alterDistance as Boolean,
                             isBossBattle as Boolean) as Void {
        startBattle(digimonIndex, alterDistance, isBossBattle);
    }

    function startBattle(enemyIndex as Number, alterDistance as Boolean,
                         isBossBattle as Boolean) as Void {
        var battle = _gm.appLoader.loadApp(Kaisa.APP_BATTLE, self,
                                           _gm.screenMgr.screenDisplay);
        if (battle == null) { return; }
        currentScreen = Kaisa.SCREEN_APP;
        loadedApp = (battle as Battle).setup(enemyIndex, alterDistance, isBossBattle);
        loadedApp.startApp();
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

        // LogicManager.cs:384 -- a code entered successfully unlocks the
        // Digimon it names, and plays three animations.
        if (loadedApp instanceof CodeInput) {
            var digimon = (loadedApp as CodeInput).returnedDigimon;
            if (digimon >= 0) {
                setDigimonUnlocked(digimon, true);
                setDigicodeUnlocked(digimon, true);

                _gm.enqueueAnimation(new SummonDigimon(_gm, digimon));
                _gm.enqueueAnimation(new UnlockDigimon(_gm, digimon, false));
                _gm.enqueueAnimation(new CharHappy(_gm));
            }
        }

        if (isEventPending) { currentScreen = Kaisa.SCREEN_CHARACTER; }
        else { currentScreen = newScreen; }

        loadedApp.dispose();
        loadedApp = null;
        _gm.checkPendingEvents();
        // The save is RAM-resident (ADR 8); closing an app is one of the
        // checkpoints where it is worth writing.
        _saved.commit();
    }

    // LogicManager.cs:412 -- "Adds an amount of experience to the player, and
    // returns true if their level changed. This method will disable player
    // insurance if able."
    function addPlayerExperience(val as Number) as Boolean {
        var before = getPlayerLevel();
        var xp = _saved.playerExperience() + val;
        if (xp > 1000000) { xp = 1000000; }
        _saved.setPlayerExperience(xp);
        _saved.setPlayerInsured(false);
        return before != getPlayerLevel();
    }

    // LogicManager.cs:429 -- the mirror, with the insurance that softens the
    // first level a player loses: it eats one loss, then re-arms when a level
    // does go.
    function removePlayerExperience(val as Number) as Boolean {
        var before = getPlayerLevel();

        if (_saved.isPlayerInsured()) {
            _saved.setPlayerInsured(false);
        } else {
            _saved.setPlayerExperience(_saved.playerExperience() - val);
        }
        if (_saved.playerExperience() < 0) { _saved.setPlayerExperience(0); }

        var now = getPlayerLevel();
        if (now < before) { _saved.setPlayerInsured(true); }
        return before != now;
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

    // LogicManager.cs:570 -- unlocking sets the stored level to 1, which is
    // "owned at base level"; locking is the only way the level goes to 0.
    function setDigimonUnlocked(digimonIndex as Number, val as Boolean) as Void {
        if (val) {
            if (_saved.digimonLevel(digimonIndex) == 0) {
                _saved.setDigimonLevel(digimonIndex, 1);
            }
        } else {
            _saved.setDigimonLevel(digimonIndex, 0);
        }
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

    // LogicManager.cs:572 -- every Digimon the player owns, as indices.
    function getAllUnlockedDigimon() as Array<Number> {
        var out = [] as Array<Number>;
        var n = _db.count();
        for (var i = 0; i < n; i += 1) {
            if (_db.isDisabled(i)) { continue; }
            if (getDigimonUnlocked(i)) { out.add(i); }
        }
        return out;
    }

    // LogicManager.cs:597 -- "Unlocks or levels up a Digimon. Returns true if
    // it levels up a Digimon, false if it unlocks it." Returns
    // [leveledUp, levelBefore, levelAfter], the out parameters as an array
    // (ticket 11 decision 5).
    function rewardDigimon(digimonIndex as Number) as Array<Number> {
        var levelBefore = getDigimonExtraLevel(digimonIndex);
        if (getDigimonUnlocked(digimonIndex)) {
            setDigimonExtraLevel(digimonIndex, levelBefore + 1);
            return [1, levelBefore, getDigimonExtraLevel(digimonIndex)];
        }
        setDigimonUnlocked(digimonIndex, true);
        return [0, levelBefore, 0];
    }

    // LogicManager.cs:618 -- "Erases or levels down a Digimon."
    function punishDigimon(digimonIndex as Number) as Array<Number> {
        var levelBefore = getDigimonExtraLevel(digimonIndex);
        if (levelBefore > 0) {
            setDigimonExtraLevel(digimonIndex, levelBefore - 1);
            return [1, levelBefore, getDigimonExtraLevel(digimonIndex)];
        }
        setDigimonUnlocked(digimonIndex, false);
        return [0, levelBefore, -1];
    }

    // LogicManager.cs:637 -- "Locks a Spirit and adds it to the list of
    // spirits lost by the player."
    function loseSpirit(spiritIndex as Number) as Void {
        setDigimonUnlocked(spiritIndex, false);
        _saved.addLostSpirit(spiritIndex);
    }

    // LogicManager.cs:645 -- unlocks a random lost spirit and returns it.
    function recoverSpirit() as Number {
        var lost = _saved.lostSpirits();
        if (lost.size() == 0) { return -1; }
        var index = Kaisa.Rand.rangeInt(0, lost.size());
        var recovered = lost[index];
        _saved.removeLostSpiritAt(index);
        setDigimonUnlocked(recovered, true);
        return recovered;
    }

    function isAnySpiritLost() as Boolean {
        return _saved.lostSpirits().size() > 0;
    }

    // LogicManager.cs:682 ApplyReward. The C# has two `out object` parameters
    // whose type depends on the reward -- levels, distances, a boolean and an
    // area for the data storm -- so the port returns [before, after] and the
    // animation that consumes them knows which reward it is showing.
    //
    // SOURCE BUG, reproduced: the LevelUp branch calls LevelDownPlayer, not
    // LevelUpPlayer. Only ForceLevelUp levels the player up.
    function applyReward(reward as Number, objective as Number) as Array<Number> {
        if (reward == Kaisa.REWARD_INCREASE_DISTANCE_300) {
            return distanceReward(300, true);
        } else if (reward == Kaisa.REWARD_INCREASE_DISTANCE_500) {
            return distanceReward(500, true);
        } else if (reward == Kaisa.REWARD_INCREASE_DISTANCE_2000) {
            return distanceReward(2000, true);
        } else if (reward == Kaisa.REWARD_REDUCE_DISTANCE_500) {
            return distanceReward(500, false);
        } else if (reward == Kaisa.REWARD_REDUCE_DISTANCE_1000) {
            return distanceReward(1000, false);
        } else if (reward == Kaisa.REWARD_PUNISH_DIGIMON) {
            var r = punishDigimon(objective);
            return [r[1], r[2]];
        } else if (reward == Kaisa.REWARD_REWARD_DIGIMON) {
            var rarity = randomRewardRarity();
            var rewarded;
            // "30% chance to forcibly select a Digimon already owned."
            if (Kaisa.Rand.rangeFloat(0.0, 1.0) < 0.3) {
                rewarded = Kaisa.Tools.getRandomElement(unlockedOfRarity(rarity));
            } else {
                rewarded = Kaisa.Tools.getRandomElement(
                    _db.getAllDigimonOfRarity(rarity, getPlayerLevel() + 20));
            }
            if (rewarded == null) { return [-1, -1]; }
            var r = rewardDigimon(rewarded);
            return [r[1], r[2]];
        } else if (reward == Kaisa.REWARD_UNLOCK_DIGICODE_OWNED) {
            var owned = Kaisa.Tools.getRandomElement(getAllUnlockedDigimon());
            if (owned != null) { setDigicodeUnlocked(owned, true); }
            return [-1, -1];
        } else if (reward == Kaisa.REWARD_UNLOCK_DIGICODE_NOT_OWNED) {
            var rarity = randomRewardRarity();
            var chosen = Kaisa.Tools.getRandomElement(_db.getAllDigimonOfRarity(rarity, 100));
            if (chosen != null) {
                setDigimonUnlocked(chosen, true);
                setDigicodeUnlocked(chosen, true);
            }
            return [-1, -1];
        } else if (reward == Kaisa.REWARD_DATA_STORM) {
            // resultBefore is 1 when the player was moved; resultAfter is the
            // area they ended in.
            return applyDataStorm();
        } else if (reward == Kaisa.REWARD_LOSE_SPIRIT_POWER_10) {
            return spiritPowerReward(-10);
        } else if (reward == Kaisa.REWARD_LOSE_SPIRIT_POWER_50) {
            return spiritPowerReward(-50);
        } else if (reward == Kaisa.REWARD_GAIN_SPIRIT_POWER_10) {
            return spiritPowerReward(10);
        } else if (reward == Kaisa.REWARD_GAIN_SPIRIT_POWER_MAX) {
            var before = spiritPower();
            setSpiritPower(Kaisa.Constants.MAX_SPIRIT_POWER);
            return [before, spiritPower()];
        } else if (reward == Kaisa.REWARD_LEVEL_DOWN) {
            if (getPlayerLevelProgression() < 0.5) { return levelChange(false); }
        } else if (reward == Kaisa.REWARD_FORCE_LEVEL_DOWN) {
            if (getPlayerLevelProgression() > 0.0) { return levelChange(false); }
        } else if (reward == Kaisa.REWARD_LEVEL_UP) {
            // The original levels the player DOWN here; see the note above.
            if (getPlayerLevelProgression() < 0.5) { return levelChange(false); }
        } else if (reward == Kaisa.REWARD_FORCE_LEVEL_UP) {
            if (getPlayerLevelProgression() > 0.0) { return levelChange(true); }
        }
        // Reward.TriggerBattle calls CallRandomBattle, which waits on Battle.
        return [-1, -1];
    }

    function distanceReward(amount as Number, increase as Boolean) as Array<Number> {
        var before = _gm.worldMgr.currentDistance();
        if (increase) { _gm.worldMgr.increaseDistance(amount); }
        else { _gm.worldMgr.reduceDistance(amount); }
        return [before, _gm.worldMgr.currentDistance()];
    }

    function spiritPowerReward(delta as Number) as Array<Number> {
        var before = spiritPower();
        setSpiritPower(before + delta);
        return [before, spiritPower()];
    }

    function levelChange(up as Boolean) as Array<Number> {
        var before = getPlayerLevel();
        if (up) { levelUpPlayer(); } else { levelDownPlayer(); }
        return [before, getPlayerLevel()];
    }

    // The rarity ladder both Digimon rewards draw on.
    function randomRewardRarity() as Number {
        var rng = Kaisa.Rand.rangeFloat(0.0, 1.0);
        if (rng < 0.50) { return Kaisa.RARITY_COMMON; }
        if (rng < 0.80) { return Kaisa.RARITY_RARE; }
        if (rng < 0.95) { return Kaisa.RARITY_EPIC; }
        return Kaisa.RARITY_LEGENDARY;
    }

    function unlockedOfRarity(rarity as Number) as Array<Number> {
        var out = [] as Array<Number>;
        var owned = getAllUnlockedDigimon();
        for (var i = 0; i < owned.size(); i += 1) {
            if (_db.getDigimonRarity(owned[i]) == rarity) { out.add(owned[i]); }
        }
        return out;
    }

    // LogicManager.cs:817 -- "Triggers a Datastorm, and returns true if the
    // player has been moved. It outputs the new area." Returns
    // [moved, newArea].
    function applyDataStorm() as Array<Number> {
        var newArea = _gm.worldMgr.currentArea();
        var moveArea = Kaisa.Rand.rangeFloat(0.0, 1.0) < 0.33;
        var uncompleted = _gm.worldMgr.getUncompletedAreas(_gm.worldMgr.currentWorld());

        if (uncompleted.size() < 2) { moveArea = false; }

        if (moveArea) {
            newArea = Kaisa.Tools.getRandomElement(uncompleted);
            _gm.worldMgr.moveToAreaWithDistance(_gm.worldMgr.currentWorld(), newArea,
                _gm.worldMgr.currentDistance() + 1000);
            // The original's TODO here: "Chance to be moved to world 9."
        }
        return [moveArea ? 1 : 0, newArea];
    }

    // LogicManager.cs:846 -- the experience the winner of a battle takes from
    // the loser. tools/verify_numeric.py checks this formula.
    function getExperienceGained(friendlyLevel as Number, enemyLevel as Number) as Number {
        var a = (30 * enemyLevel).toFloat();
        var b = Math.pow((2 * enemyLevel) + 10, 2.5);
        var c = Math.pow(enemyLevel + friendlyLevel + 10, 2.5);
        var d = 0.025 + (0.025 * friendlyLevel);
        if (d > 0.5) { d = 0.5; }
        return Kaisa.MathExt.ceilToInt(((a * (b / c)) + 1) * d);
    }

    // LogicManager.cs:589
    function isDigimonAtMaxLevel(digimonIndex as Number) as Boolean {
        var d = _db.getDigimon(digimonIndex);
        return (d != null) && (getDigimonExtraLevel(digimonIndex) == d.maxExtraLevel());
    }
}
