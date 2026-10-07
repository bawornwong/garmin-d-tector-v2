import Toybox.Lang;

// port of Logic/Apps/Games/JackpotBox.cs
//
// A pattern of four to ten arrow keys is shown, then repeated back against a
// twelve-second clock. How much of it the player gets right decides which of
// five reward tables the box rolls on, and how strong the attack that opens
// it looks.
//
// The reward itself is LogicManager.applyReward; the animations around it
// (the encounter, the attack, the box resisting or breaking, and the reward's
// own animation) all play now.
class JackpotBox extends DigiviceApp {
    const MINIMUM_LENGTH = 4;
    const MAXIMUM_LENGTH = 10;
    const MINIMUM_TIME = 0.25;
    const MAXIMUM_TIME = 0.75;
    const THRESHOLD_FOR_MEGA_REWARD = 8;

    var currentScreen as Number = 0;    // 0 attack/exit, 1 input, 2 end
    var friendlyDigimon as Number = -1;
    var pattern as Array<Number> = [];  // 0 left, 1 right, 2 up, 3 down
    var delay as Float = 0.5;
    var timeRemaining as Number = 12;
    var playerSelection as Array<Number> = [];
    var currentKey as Number = 0;
    var _finishAfterKey as Boolean = false;

    var keypad as SpriteBuilder?;
    var keys as Array<SpriteBuilder> = [];
    var tbTime as TextBoxBuilder?;
    var tbTimeCount as TextBoxBuilder?;

    var _fibers as Array<Fiber> = [];

    function initialize(gmIn as GameManager, controllerIn, parent as ScreenElement) {
        DigiviceApp.initialize(gmIn, controllerIn, parent);
    }

    // --- Input: on the pattern screen the four buttons ARE the four keys ---

    function inputLeft() as Void {
        if (currentScreen == 0) { gm.audioMgr.playButtonB(); }
        else if (currentScreen == 1) { gm.audioMgr.playButtonA(); inputKey(0); }
    }

    function inputRight() as Void {
        if (currentScreen == 0) { gm.audioMgr.playButtonB(); }
        else if (currentScreen == 1) { gm.audioMgr.playButtonA(); inputKey(1); }
    }

    function inputA() as Void {
        if (currentScreen == 0) {
            gm.audioMgr.playButtonA();
            displayPattern();
        } else if (currentScreen == 1) {
            gm.audioMgr.playButtonA();
            inputKey(3);
        }
    }

    function inputB() as Void {
        if (currentScreen == 0) {
            gm.audioMgr.playButtonB();
            closeApp(Kaisa.SCREEN_GAMES_REWARD_MENU);
        } else if (currentScreen == 1) {
            gm.audioMgr.playButtonA();
            inputKey(2);
        }
    }

    function startApp() as Void {
        var docked = gm.logicMgr.getAllDDockDigimon();
        friendlyDigimon = Kaisa.Tools.getRandomElement(docked);
        if (friendlyDigimon == null) { friendlyDigimon = -1; }

        // Animations.EncounterEnemy("jackpot", 0.5f): the box is drawn from
        // the Digimon sheet but has no row, so its two sprites are passed in.
        gm.enqueueAnimation(new EncounterEnemy(gm, -1, 0.5,
            Kaisa.Sprites.JACKPOT, Kaisa.Sprites.JACKPOT_ATTACK));
        gm.enqueueAnimation(new SummonDigimon(gm, friendlyDigimon));

        pattern = generatePattern(Kaisa.Rand.rangeInt(MINIMUM_LENGTH, MAXIMUM_LENGTH + 1));
        playerSelection = [];
        for (var i = 0; i < pattern.size(); i += 1) { playerSelection.add(-1); }
        delay = Kaisa.Rand.rangeFloat(MINIMUM_TIME, MAXIMUM_TIME);

        drawScreen();
    }

    // The original's Update() calls DrawScreen every frame.
    function tick(elapsedMs as Number) as Void {
        if (_finishAfterKey) {
            _finishAfterKey = false;
            decideBattle();
            return;
        }
        drawScreen();
    }

    function drawScreen() as Void {
        if (currentScreen == 0) {
            setScreen(Kaisa.Sprites.BATTLE_COMBAT_MENU[0]);
        } else if (currentScreen == 1) {
            setScreen(null);            // Constants.EMPTY_SPRITE
        }
    }

    function generatePattern(length as Number) as Array<Number> {
        var out = [] as Array<Number>;
        for (var i = 0; i < length; i += 1) { out.add(Kaisa.Rand.rangeInt(0, 4)); }
        return out;
    }

    function displayPattern() as Void {
        track(gm.runner.start(new JBDisplayPattern(self)));
        currentScreen = 1;
    }

    function inputKey(key as Number) as Void {
        playerSelection[currentKey] = key;
        currentKey += 1;
        var lastKey = currentKey == playerSelection.size();
        if (lastKey) { currentScreen = 2; } // Ignore more input during the final flash.
        track(gm.runner.start(new JBDisplayChosenKey(self, key, lastKey)));
    }

    function track(f as Fiber) as Void {
        _fibers.add(f);
    }

    function dispose() as Void {
        for (var i = 0; i < _fibers.size(); i += 1) { gm.runner.stop(_fibers[i]); }
        _fibers = [];
        DigiviceApp.dispose();
    }

    function decideBattle() as Void {
        currentScreen = 2;

        var rewardCategory = getRewardCategory();
        var reward = getRandomReward(rewardCategory);

        // "To prevent abusing jackpot to level up fast, level up/down is
        // restricted to certain conditions. If those conditions aren't met,
        // they are replaced with increase/reduce distance."
        var progression = gm.logicMgr.getPlayerLevelProgression();
        if ((reward == Kaisa.REWARD_LEVEL_DOWN && progression > 0.5)
                || (reward == Kaisa.REWARD_FORCE_LEVEL_DOWN && progression == 0.0)) {
            reward = Kaisa.REWARD_INCREASE_DISTANCE_500;
        } else if ((reward == Kaisa.REWARD_LEVEL_UP && progression < 0.5)
                || (reward == Kaisa.REWARD_FORCE_LEVEL_UP && progression == 0.0)) {
            reward = Kaisa.REWARD_REDUCE_DISTANCE_500;
        }

        // The battle against the box: the player attacks with energy, the box
        // does not attack back (attack 3), and then it either resists or is
        // destroyed.
        var friendlySprites = gm.getAllDigimonBattleSprites(friendlyDigimon, 0);
        gm.enqueueAnimation(new LaunchAttack(gm, friendlySprites, 0, false, false));
        gm.enqueueAnimation(new AttackCollision(gm, 0, friendlySprites, 3, null, 0));

        if (rewardCategory < 2) {
            gm.enqueueAnimation(new BoxResists(gm, friendlyDigimon));
        } else {
            gm.enqueueAnimation(new DestroyBox(gm));
            if (Kaisa.Rand.rangeInt(0, 20) > gm.jackpotValue()) {
                reward = Kaisa.REWARD_EMPTY;
            }
        }

        if (reward == Kaisa.REWARD_EMPTY) {
            gm.enqueueRewardAnimation(reward, -1, -1, -1);
        } else if (reward == Kaisa.REWARD_TRIGGER_BATTLE) {
            // JackpotBox.TriggerBattle: close, then fight.
            closeApp(Kaisa.SCREEN_GAMES_REWARD_MENU);
            if (controller instanceof LogicManager) {
                (controller as LogicManager).callRandomBattle(true);
            }
            return;
        } else {
            var objective = (reward == Kaisa.REWARD_PUNISH_DIGIMON) ? friendlyDigimon : -1;
            var result = gm.logicMgr.applyReward(reward, objective);
            objective = result[2];
            // A selection with no eligible Digimon grants nothing. Show the
            // empty-box reaction rather than a blank reward and celebration.
            if (objective < 0 && (reward == Kaisa.REWARD_REWARD_DIGIMON
                    || reward == Kaisa.REWARD_UNLOCK_DIGICODE_OWNED
                    || reward == Kaisa.REWARD_UNLOCK_DIGICODE_NOT_OWNED)) {
                reward = Kaisa.REWARD_EMPTY;
            }
            gm.enqueueRewardAnimation(reward, objective, result[0], result[1]);
        }

        closeApp(Kaisa.SCREEN_GAMES_REWARD_MENU);
    }

    function getCorrectInputCount() as Number {
        var correct = 0;
        for (var i = 0; i < pattern.size(); i += 1) {
            if (playerSelection[i] == pattern[i]) { correct += 1; }
        }
        return correct;
    }

    function getRewardCategory() as Number {
        var percCorrect = getCorrectInputCount().toFloat() / pattern.size();
        var reward;
        if (percCorrect < 0.26) { reward = 0; }
        else if (percCorrect < 0.51) { reward = 1; }
        else if (percCorrect < 0.76) { reward = 2; }
        else { reward = 3; }

        if (percCorrect == 1.0 && pattern.size() >= THRESHOLD_FOR_MEGA_REWARD) {
            reward = 4;
        }
        return reward;
    }

    // The energy rank of the attack that opens the box: full marks on a long
    // pattern goes past the normal maximum.
    function getEnergyRank() as Number {
        var energyDiscountPerMiss = 12.0 / pattern.size();
        var misses = pattern.size() - getCorrectInputCount();
        var rank = Kaisa.MathExt.floorToInt(12.0 - (energyDiscountPerMiss * misses));
        if (rank == 12 && pattern.size() >= THRESHOLD_FOR_MEGA_REWARD && misses == 0) {
            rank = 14;
        }
        return rank;
    }

    function getRandomReward(category as Number) as Number {
        var rng = Kaisa.Rand.rangeFloat(0.0, 1.0);
        if (category == 0) {
            if (rng < 0.40) { return Kaisa.REWARD_INCREASE_DISTANCE_500; }
            if (rng < 0.60) { return Kaisa.REWARD_PUNISH_DIGIMON; }
            if (rng < 0.70) { return Kaisa.REWARD_DATA_STORM; }
            if (rng < 0.80) { return Kaisa.REWARD_LOSE_SPIRIT_POWER_10; }
            if (rng < 0.90) { return Kaisa.REWARD_FORCE_LEVEL_DOWN; }
            if (rng < 0.95) { return Kaisa.REWARD_PUNISH_DIGIMON; }
            return Kaisa.REWARD_INCREASE_DISTANCE_2000;
        }
        if (category == 1) {
            if (rng < 0.40) { return Kaisa.REWARD_INCREASE_DISTANCE_500; }
            if (rng < 0.65) { return Kaisa.REWARD_TRIGGER_BATTLE; }
            if (rng < 0.75) { return Kaisa.REWARD_PUNISH_DIGIMON; }
            if (rng < 0.85) { return Kaisa.REWARD_DATA_STORM; }
            if (rng < 0.95) { return Kaisa.REWARD_LOSE_SPIRIT_POWER_10; }
            return Kaisa.REWARD_LEVEL_DOWN;
        }
        if (category == 2) {
            if (rng < 0.35) { return Kaisa.REWARD_REDUCE_DISTANCE_500; }
            if (rng < 0.65) { return Kaisa.REWARD_TRIGGER_BATTLE; }
            if (rng < 0.80) { return Kaisa.REWARD_INCREASE_DISTANCE_300; }
            if (rng < 0.90) { return Kaisa.REWARD_GAIN_SPIRIT_POWER_10; }
            return Kaisa.REWARD_REWARD_DIGIMON;
        }
        if (category == 3) {
            if (rng < 0.30) { return Kaisa.REWARD_REDUCE_DISTANCE_500; }
            if (rng < 0.55) { return Kaisa.REWARD_GAIN_SPIRIT_POWER_10; }
            if (rng < 0.80) { return Kaisa.REWARD_REWARD_DIGIMON; }
            if (rng < 0.95) { return Kaisa.REWARD_LEVEL_UP; }
            return Kaisa.REWARD_UNLOCK_DIGICODE_OWNED;
        }
        if (category == 4) {
            if (rng < 0.55) { return Kaisa.REWARD_REWARD_DIGIMON; }
            if (rng < 0.65) { return Kaisa.REWARD_REDUCE_DISTANCE_1000; }
            if (rng < 0.75) { return Kaisa.REWARD_FORCE_LEVEL_UP; }
            if (rng < 0.85) { return Kaisa.REWARD_GAIN_SPIRIT_POWER_MAX; }
            if (rng < 0.95) { return Kaisa.REWARD_UNLOCK_DIGICODE_OWNED; }
            return Kaisa.REWARD_UNLOCK_DIGICODE_NOT_OWNED;
        }
        return Kaisa.REWARD_NONE;
    }
}

// port of JackpotBox.PADisplayPattern -- shows the pattern, wipes the screen,
// then readies the player and starts the clock.
class JBDisplayPattern extends Routine {
    const FIRST_KEY_PAUSE_SECONDS = 0.20;
    const KEY_ON_SECONDS = 0.65;
    const KEY_OFF_SECONDS = 0.20;

    var app as JackpotBox;
    var hourglass as SpriteBuilder?;
    var rbBlackScreen as RectangleBuilder?;
    var sbLoading as SpriteBuilder?;
    var i as Number = 0;

    function initialize(appIn as JackpotBox) {
        Routine.initialize();
        app = appIn;
    }

    function step(rt as Fiber) as Float {
        switch (pc) {
            case 0:
                app.gm.lockInput();

                app.keypad = Kaisa.ScreenBuilder.buildSprite("Keypad", app.screen)
                    .setSize(24, 24).center().setSprite(Kaisa.Sprites.JACKPOT_PAD);
                app.keys = [
                    Kaisa.ScreenBuilder.buildSprite("Key Left", app.screen)
                        .setSize(8, 12).setPosition(4, 10)
                        .setSprite(Kaisa.Sprites.JACKPOT_KEYS[0]).setTransparent(true).setActive(false),
                    Kaisa.ScreenBuilder.buildSprite("Key Right", app.screen)
                        .setSize(8, 12).setPosition(20, 10)
                        .setSprite(Kaisa.Sprites.JACKPOT_KEYS[1]).setTransparent(true).setActive(false),
                    Kaisa.ScreenBuilder.buildSprite("Key Up", app.screen)
                        .setSize(12, 8).setPosition(10, 4)
                        .setSprite(Kaisa.Sprites.JACKPOT_KEYS[2]).setTransparent(true).setActive(false),
                    Kaisa.ScreenBuilder.buildSprite("Key Down", app.screen)
                        .setSize(12, 8).setPosition(10, 20)
                        .setSprite(Kaisa.Sprites.JACKPOT_KEYS[3]).setTransparent(true).setActive(false)
                ];

                hourglass = Kaisa.ScreenBuilder.buildSprite("Hourglass", app.screen)
                    .setSprite(Kaisa.Sprites.HOURGLASS);
                pc = 1;
                return 0.75;
            case 1:
                hourglass.dispose();
                i = 0;
                pc = 2;
                // Let the empty keypad settle before revealing the first key.
                return FIRST_KEY_PAUSE_SECONDS;
            case 2:                                 // for each key of the pattern
                if (i >= app.pattern.size()) { pc = 4; return 0.0; }
                app.gm.audioMgr.playSound("beepLow");
                app.keys[app.pattern[i]].setActive(true);
                pc = 3;
                return KEY_ON_SECONDS;
            case 3:
                app.keys[app.pattern[i]].setActive(false);
                i += 1;
                pc = 2;
                // Keep a blank frame between cues, even when the same key
                // appears twice in a row.
                return KEY_OFF_SECONDS;
            case 4:
                rbBlackScreen = Kaisa.ScreenBuilder.buildRectangle("BlackScreen0", app.screen)
                    .setSize(32, 32);
                sbLoading = Kaisa.ScreenBuilder.buildSprite("Loading", app.screen)
                    .setSprite(Kaisa.Sprites.LOADING).placeOutside(Kaisa.DIR_UP);
                i = 0;
                pc = 5;
                return 0.0;
            case 5:                                 // for (i = 0; i < 64; i++)
                if (i >= 64) { pc = 7; return 0.0; }
                sbLoading.move(Kaisa.DIR_DOWN, 1);
                pc = 6;
                return (app.delay * 2.0) / 64;
            case 6:
                i += 1;
                pc = 5;
                return 0.0;
            case 7:
                rbBlackScreen.dispose();
                sbLoading.dispose();

                // Ready the player.
                app.keypad.move(Kaisa.DIR_DOWN, 4);
                for (var k = 0; k < app.keys.size(); k += 1) {
                    app.keys[k].move(Kaisa.DIR_DOWN, 4);
                }
                app.tbTime = Kaisa.ScreenBuilder.buildTextBox("Time", app.screen, Kaisa.Font.SMALL)
                    .setText("TIME").setSize(18, 5).setPosition(1, 1);
                app.tbTimeCount = Kaisa.ScreenBuilder.buildTextBox("TimeCount", app.screen, Kaisa.Font.SMALL)
                    .setText(app.timeRemaining.toString()).setSize(10, 5).setPosition(22, 1);
                app.track(app.gm.runner.start(new JBTimeCount(app)));

                app.gm.unlockInput();
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of JackpotBox.PADisplayChosenKey -- the key the player just pressed
// lights for a quarter second. (The original's LockInput calls around it are
// commented out; so are they here.)
class JBDisplayChosenKey extends Routine {
    var app as JackpotBox;
    var key as Number;
    var lastKey as Boolean;

    function initialize(appIn as JackpotBox, keyIn as Number, lastKeyIn as Boolean) {
        Routine.initialize();
        app = appIn;
        key = keyIn;
        lastKey = lastKeyIn;
    }

    function step(rt as Fiber) as Float {
        switch (pc) {
            case 0:
                app.keys[key].setActive(true);
                pc = 1;
                return 0.25;
            case 1:
                app.keys[key].setActive(false);
                if (lastKey) { app._finishAfterKey = true; }
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of JackpotBox.TimeCount -- twelve seconds, then the box is decided
// whether the player finished the pattern or not.
class JBTimeCount extends Routine {
    var app as JackpotBox;

    function initialize(appIn as JackpotBox) {
        Routine.initialize();
        app = appIn;
    }

    function step(rt as Fiber) as Float {
        switch (pc) {
            case 0:
                pc = 1;
                return 1.0;
            case 1:                                 // while (timeRemaining > -1)
                if (app.currentScreen == 2) { return Routine.DONE; }
                if (app.timeRemaining <= -1) { pc = 2; return 0.0; }
                app.timeRemaining -= 1;
                app.tbTimeCount.setText(app.timeRemaining.toString());
                return 1.0;
            case 2:
                if (app.currentScreen == 2) { return Routine.DONE; }
                app.decideBattle();
                app.tbTime.dispose();
                app.tbTimeCount.dispose();
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}
