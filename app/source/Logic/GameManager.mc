import Toybox.Lang;

// port of GameManager.cs -- the object every app is handed, carrying the
// managers and the few screen helpers that live next to them.
//
// GameManager.cs is 545 lines of Unity wiring (prefabs, scene objects, the
// audio source, the debug console) around a small core: the managers, the
// saved game, and a handful of builders. The wiring does not survive the
// port; the core is translated as the apps need it.
class GameManager {
    var data as GameData;
    var _jackpotMs as Number = 0;
    var db as Database;
    var saved as SavedGame;
    var logicMgr as LogicManager;
    var worldMgr as WorldManager;
    var audioMgr as AudioManager;
    var runner as Runner;
    var appLoader as AppLoader;
    var screenMgr as ScreenManager?;
    var playerChar as PlayerCharacter;

    var isCharacterWalking as Boolean = false;
    var isInputLocked as Boolean = false;

    function initialize(dataIn as GameData, dbIn as Database, savedIn as SavedGame) {
        data = dataIn;
        db = dbIn;
        saved = savedIn;
        logicMgr = new LogicManager(savedIn, dbIn);
        worldMgr = new WorldManager(savedIn, dataIn);
        audioMgr = new AudioManager();
        runner = new Runner();
        appLoader = new AppLoader(self);
        playerChar = new PlayerCharacter(self, savedIn.playerChar());
        logicMgr.setGameManager(self);
    }

    // GameManager.Awake's tail: the screen manager needs the root element,
    // which the view owns, so it is attached rather than constructed here.
    function attachScreenManager(sm as ScreenManager) as Void {
        screenMgr = sm;
    }

    // GameManager.cs:40 -- the jackpot's odds improve the longer the game
    // goes unplayed: IncreaseJackpotValue ticks it up every five minutes to a
    // maximum of 20.
    function jackpotValue() as Number {
        return saved.record.jackpotValue;
    }

    function setJackpotValue(v as Number) as Void {
        saved.record.jackpotValue = v;
        saved.touch();
    }

    // GameManager.cs:180 -- the punishment for quitting mid-battle, applied
    // on the next launch. `leaverBusterDigimonLoss` is -1 rather than "" when
    // there is nothing to lose (ADR 7: Digimon are indices).
    function checkLeaverBuster() as Void {
        if (!saved.record.isLeaverBusterActive) { return; }

        var expLoss = saved.record.leaverBusterExpLoss;
        var digimonLoss = saved.record.leaverBusterDigimonLoss;
        logicMgr.removePlayerExperience(expLoss);

        if (digimonLoss >= 0) {
            if (data.stage(digimonLoss) != Kaisa.STAGE_SPIRIT) {
                logicMgr.punishDigimon(digimonLoss);
            } else {
                logicMgr.loseSpirit(digimonLoss);
            }
        }

        worldMgr.increaseDistance(2000);
        logicMgr.increaseTotalBattles();
        disableLeaverBuster();
    }

    // GameManager.cs:115 IncreaseJackpotValue -- "InvokeRepeating", every five
    // minutes, to a ceiling of 20. The port counts frames rather than starting
    // a fiber for it: the runner's fibers belong to animations, and a
    // five-minute wait would sit in the queue forever.
    function tickJackpot(elapsedMs as Number) as Void {
        _jackpotMs += elapsedMs;
        if (_jackpotMs < 300000) { return; }
        _jackpotMs -= 300000;
        if (jackpotValue() < 20) { setJackpotValue(jackpotValue() + 1); }
    }

    // GameManager.cs:239 -- "Reduces distance by 1, if possible, and increases
    // the step count by one." One step is one shake of the original; the port
    // has no shake, so the character screen's B button stands in for it when
    // the player is one kilometre out (LogicManager.inputB).
    function takeAStep() as Void {
        worldMgr.takeSteps(1);
        worldMgr.reduceDistance(1);
        if (worldMgr.currentDistance() == 1) { saved.setSavedEvent(2); }
        checkPendingEvents();
    }

    // GameManager.cs:205 -- whether a saved event should start now. An app on
    // screen defers it (the Status app excepted, as in the original), and so
    // does an animation still playing.
    function checkPendingEvents() as Void {
        if (logicMgr.isAppLoaded() && !(logicMgr.loadedApp instanceof Status)) { return; }
        if (screenMgr.playingAnimations) { return; }

        var savedEvent = saved.savedEvent();
        if (savedEvent == 0) { return; }
        if (savedEvent == 1) {
            logicMgr.enqueueRegularEvent();
            if (logicMgr.isAppLoaded()) { logicMgr.closeLoadedApp(Kaisa.SCREEN_CHARACTER); }
        } else if (savedEvent == 2) {
            logicMgr.enqueueBossEvent();
            if (logicMgr.isAppLoaded()) { logicMgr.closeLoadedApp(Kaisa.SCREEN_CHARACTER); }
        }
    }

    // GameManager.cs:131 CreateNewGame -- everything a fresh save needs, and
    // the opening animation.
    //
    // The original's `Random.Range(0, 2147483647)` seeds are the three battle
    // seeds AttackChooser reads; Math.rand() is the port's source for them
    // (ticket 11 decision 4).
    function createNewGame(chosenGameChar as Number) as Void {
        var randomInitial = data.initial(Kaisa.Rand.rangeInt(0, data.initialCount()));
        var playerSpirit = Kaisa.WellKnown.PLAYER_SPIRIT[chosenGameChar];

        saved.record.gameChar = chosenGameChar;

        for (var i = 0; i < saved.record.battleSeed.size(); i += 1) {
            saved.record.battleSeed[i] = Kaisa.Rand.rangeInt(0, 2147483647);
        }

        saved.record.cheatsUsed = false;
        saved.record.stepsToNextEvent = 300;
        saved.touch();
        worldMgr.moveToArea(0, 0);
        logicMgr.setDigimonUnlocked(playerSpirit, true);
        logicMgr.setDigimonUnlocked(randomInitial, true);
        logicMgr.setSpiritPower(99);

        worldMgr.setupWorlds(playerSpirit);

        var spiritEnergy = db.getDigimon(playerSpirit).getBossStats(1).getEnergyRank();
        var enemyEnergy = db.getDigimon(randomInitial).getRegularStats().getEnergyRank();

        enqueueAnimation(new StartGameAnimation(self, chosenGameChar, playerSpirit,
                                                spiritEnergy, randomInitial, enemyEnergy));

        logicMgr.currentScreen = Kaisa.SCREEN_CHARACTER;
        // The original writes the save as it goes; the port batches and this
        // is the point the new game becomes real.
        saved.commit();
    }

    // GameManager.cs:446 EnqueueRewardAnimation -- every reward's animation,
    // and the character's reaction after it.
    //
    // `objective` is a Digimon index rather than a name (ADR 7), and the two
    // results are the numbers the reward changed; where the original passes
    // them as `object` and casts, they are Numbers here, with -1 standing for
    // the null the PunishDigimon and RewardDigimon branches test for.
    function enqueueRewardAnimation(reward as Number, objective as Number,
                                    resultBefore as Number, resultAfter as Number) as Void {
        if (reward == Kaisa.REWARD_EMPTY) {
            enqueueAnimation(new RewardEmpty(self));
            enqueueAnimation(new CharSad(self));
        } else if (reward == Kaisa.REWARD_INCREASE_DISTANCE_300
                || reward == Kaisa.REWARD_INCREASE_DISTANCE_500
                || reward == Kaisa.REWARD_INCREASE_DISTANCE_2000) {
            enqueueAnimation(new RewardDistance(self, true, resultBefore, resultAfter));
            enqueueAnimation(new CharSad(self));
        } else if (reward == Kaisa.REWARD_REDUCE_DISTANCE_500
                || reward == Kaisa.REWARD_REDUCE_DISTANCE_1000) {
            enqueueAnimation(new RewardDistance(self, false, resultBefore, resultAfter));
            enqueueAnimation(new CharHappy(self));
        } else if (reward == Kaisa.REWARD_PUNISH_DIGIMON) {
            if (resultAfter == -1) {
                enqueueAnimation(new EraseDigimon(self, objective));
            } else {
                enqueueAnimation(new LevelDownDigimon(self, objective));
            }
            enqueueAnimation(new CharSad(self));
        } else if (reward == Kaisa.REWARD_REWARD_DIGIMON) {
            enqueueAnimation(new SummonDigimon(self, objective));
            if (resultBefore == -1) {
                enqueueAnimation(new UnlockDigimon(self, objective, false));
            } else {
                enqueueAnimation(new LevelUpDigimon(self, objective));
            }
            enqueueAnimation(new CharHappy(self));
        } else if (reward == Kaisa.REWARD_UNLOCK_DIGICODE_OWNED) {
            enqueueAnimation(new RewardCode(self, objective, data.code(objective)));
            enqueueAnimation(new CharHappy(self));
        } else if (reward == Kaisa.REWARD_UNLOCK_DIGICODE_NOT_OWNED) {
            enqueueAnimation(new RewardCode(self, objective, data.code(objective)));
            enqueueAnimation(new UnlockDigimon(self, objective, false));
            enqueueAnimation(new CharHappy(self));
        } else if (reward == Kaisa.REWARD_DATA_STORM) {
            // The original passes the move-to-new-area flag as resultBefore.
            var moveToNewArea = (resultBefore == 1);
            enqueueAnimation(new DataStorm(self, characterSprites(saved.playerChar()),
                                           moveToNewArea));
            if (moveToNewArea) {
                enqueueAnimation(new DisplayNewArea(self, worldMgr.currentWorld(),
                                                    worldMgr.currentArea(),
                                                    worldMgr.currentDistance()));
            } else {
                enqueueAnimation(new CharHappy(self));
            }
        } else if (reward == Kaisa.REWARD_LOSE_SPIRIT_POWER_10
                || reward == Kaisa.REWARD_LOSE_SPIRIT_POWER_50) {
            enqueueAnimation(new RewardSpiritPower(self, true, resultBefore, resultAfter));
            enqueueAnimation(new CharSad(self));
        } else if (reward == Kaisa.REWARD_GAIN_SPIRIT_POWER_10
                || reward == Kaisa.REWARD_GAIN_SPIRIT_POWER_MAX) {
            enqueueAnimation(new RewardSpiritPower(self, false, resultBefore, resultAfter));
            enqueueAnimation(new CharHappy(self));
        } else if (reward == Kaisa.REWARD_LEVEL_DOWN
                || reward == Kaisa.REWARD_FORCE_LEVEL_DOWN) {
            enqueueAnimation(new LevelDown(self, resultBefore, resultAfter));
            enqueueAnimation(new CharSad(self));
        } else if (reward == Kaisa.REWARD_LEVEL_UP
                || reward == Kaisa.REWARD_FORCE_LEVEL_UP) {
            enqueueAnimation(new LevelUp(self, resultBefore, resultAfter));
            enqueueAnimation(new CharHappy(self));
        }
    }

    // GameManager.cs:301 -- "Returns one of the three seeds of this game at
    // random."
    function getRandomSavedSeed() as Number {
        return saved.randomSeed(Kaisa.Rand.rangeInt(0, 3));
    }

    // GameManager.cs:429 -- LeaverBuster remembers what a player would have
    // lost if they quit mid-battle, so the loss can be applied next launch.
    function updateLeaverBuster(expLoss as Number, digimonLoss as Number) as Void {
        saved.record.isLeaverBusterActive = true;
        saved.record.leaverBusterExpLoss = expLoss;
        saved.record.leaverBusterDigimonLoss = digimonLoss;
        saved.touch();
    }

    function disableLeaverBuster() as Void {
        saved.record.isLeaverBusterActive = false;
        saved.record.leaverBusterExpLoss = 0;
        saved.record.leaverBusterDigimonLoss = -1;
        saved.touch();
    }

    // GameManager.cs:526 -- finishing a world moves the player to the next
    // one, and CompleteWorld2 also strips the player of their human and
    // animal spirits, which is why the animation is given the list before the
    // stripping and not after.
    function completeWorld(world as Number) as Void {
        if (world == 0) {
            worldMgr.moveToArea(1, 0);
            setCharacterDefeated(true);
            enqueueAnimation(new TransitionToMap1(self, saved.playerChar()));
        } else if (world == 2) {
            worldMgr.moveToArea(3, 0);
            setCharacterDefeated(true);
            enqueueAnimation(new TransitionToMap3(self, saved.playerChar(),
                worldMgr.getBossOfCurrentArea(),
                getAllUnlockedHumanAndAnimalSpirits()));
            var spirits = getAllUnlockedHumanAndAnimalSpirits();
            for (var i = 0; i < spirits.size(); i += 1) {
                logicMgr.loseSpirit(spirits[i]);
            }
        }
    }

    // GameManager.cs:335
    function getAllUnlockedHumanAndAnimalSpirits() as Array<Number> {
        var out = [] as Array<Number>;
        var n = data.orderCount();
        for (var k = 0; k < n; k += 1) {
            var i = data.orderIndex(k);
            if (db.isDisabled(i)) { continue; }
            if (data.stage(i) == Kaisa.STAGE_SPIRIT) {
                var st = data.spiritType(i);
                if ((st == Kaisa.SPIRIT_HUMAN || st == Kaisa.SPIRIT_ANIMAL)
                        && logicMgr.getDigimonUnlocked(i)) {
                    out.add(i);
                }
            }
        }
        return out;
    }

    // GameManager.cs:44
    function isCharacterDefeated() as Boolean {
        return saved.record.isPlayerDefeated;
    }

    function setCharacterDefeated(val as Boolean) as Void {
        saved.record.isPlayerDefeated = val;
        saved.touch();
    }

    // GameManager.cs:48
    function isEventActive() as Boolean {
        return logicMgr.isEventPending;
    }

    // GameManager.cs:50
    function showEyes() as Boolean {
        return data.worldShowEyes(worldMgr.currentWorld());
    }

    // GameManager.cs:257
    function lockInput() as Void {
        isInputLocked = true;
    }

    function unlockInput() as Void {
        isInputLocked = false;
    }

    // GameManager.cs:254 -- the ten sprites of one character.
    function characterSprites(gameChar as Number) as Array {
        if (gameChar == Kaisa.CHAR_KOJI) { return Kaisa.Sprites.KOJI; }
        if (gameChar == Kaisa.CHAR_ZOE) { return Kaisa.Sprites.ZOE; }
        if (gameChar == Kaisa.CHAR_JP) { return Kaisa.Sprites.JP; }
        if (gameChar == Kaisa.CHAR_TOMMY) { return Kaisa.Sprites.TOMMY; }
        if (gameChar == Kaisa.CHAR_KOICHI) { return Kaisa.Sprites.KOICHI; }
        return Kaisa.Sprites.TAKUYA;
    }

    // GameManager.cs:262 -- the sprite the character is showing right now.
    function playerCharSprite() as Array<Number>? {
        return characterSprites(saved.playerChar())[playerChar.currentSprite];
    }

    // GameManager.EnqueueAnimation. The original queues an animation coroutine
    // and plays it over whatever screen is loaded.
    //
    // NOT TRANSLATED YET: Animations.cs is 2,902 lines and belongs to step 7
    // of SPEC's order of work. Call sites pass null until their animation is
    // converted, so the game logic around them stays line-for-line and the
    // holes are visible here rather than scattered.
    function enqueueAnimation(routine as Routine?) as Void {
        if (routine == null) { return; }
        Kaisa.Trace.event("enqueueAnimation");
        if (screenMgr != null) {
            screenMgr.enqueueAnimation(routine);
        } else {
            runner.start(routine);
        }
    }

    // GameManager.cs:268 -- applies a minigame's score to the distance and
    // plays the animation for beating it.
    function submitGameScore(score as Number) as Void {
        var oldDistance = worldMgr.currentDistance();
        worldMgr.reduceDistance(score);
        var newDistance = worldMgr.currentDistance();
        worldMgr.takeSteps(Kaisa.MathExt.roundToInt(score / 5.0));
        enqueueAnimation(new AwardDistance(self, score, oldDistance, newDistance));
    }

    // GameManager.GetDDockScreenElement -- the dock plate with its Digimon.
    // The dock stores a Digimon index, -1 when empty (ADR 7).
    function buildDDockScreenElement(ddock as Number, parent as ScreenElement) as SpriteBuilder {
        var digimonIndex = logicMgr.getDDockDigimon(ddock);
        var sprite = null;
        if (digimonIndex >= 0) {
            sprite = data.spriteRef(digimonIndex, data.ACTION_BASE);
        }
        return Kaisa.ScreenBuilder.buildDDockScreenElement(ddock, sprite, parent);
    }

    // SpriteDatabase.GetDigimonSprite's fallback chain: an attack sprite
    // falls back to the default, a crush sprite to the attack sprite (and so
    // on to the default), a spirit sprite to the default.
    function digimonSprite(digimonIndex as Number, action as Number) as Array<Number>? {
        var ref = data.spriteRef(digimonIndex, action);
        if (ref != null) { return ref; }
        if (action == data.ACTION_CR) { return digimonSprite(digimonIndex, data.ACTION_AT); }
        if (action == data.ACTION_AT || action == data.ACTION_SP
                || action == data.ACTION_SM || action == data.ACTION_BL) {
            return data.spriteRef(digimonIndex, data.ACTION_BASE);
        }
        return null;
    }

    // SpriteDatabase.GetAllDigimonBattleSprites -- "all the sprites used in
    // combat, in order: 0: default, 1: attack, 2: crush, 3: energy, 4:
    // ability."
    function getAllDigimonBattleSprites(digimonIndex as Number,
                                        energyRank as Number) as Array {
        var ability = data.abilityIndex(digimonIndex);
        return [
            digimonSprite(digimonIndex, data.ACTION_BASE),
            digimonSprite(digimonIndex, data.ACTION_AT),
            digimonSprite(digimonIndex, data.ACTION_CR),
            data.energySpriteRef(energyRank),
            (ability == 0xFF) ? null : data.abilitySpriteRef(ability)
        ];
    }

    // SpriteDatabase.GetAllDigimonSprites -- 0: default, 1: attack, 2: crush,
    // 3: spirit, 4: black.
    function getAllDigimonSprites(digimonIndex as Number) as Array {
        return [
            digimonSprite(digimonIndex, data.ACTION_BASE),
            digimonSprite(digimonIndex, data.ACTION_AT),
            digimonSprite(digimonIndex, data.ACTION_CR),
            digimonSprite(digimonIndex, data.ACTION_SP),
            digimonSprite(digimonIndex, data.ACTION_BL)
        ];
    }

    // GameManager.cs:281 BuildMapScreen -- a world's map art: one 32x32
    // sprite, or a 64x64 sheet of four for a multi-map world.
    function buildMapScreen(world as Number, parent as ScreenElement) as ContainerBuilder {
        var cbMap = Kaisa.ScreenBuilder.buildContainer("Map Container", parent, true);
        if (data.worldMultiMap(world)) {
            cbMap.setSize(64, 64);
            Kaisa.ScreenBuilder.buildSprite("Map 0", cbMap)
                .setSprite(data.worldMapSprite(world, 0));
            Kaisa.ScreenBuilder.buildSprite("Map 1", cbMap)
                .setSprite(data.worldMapSprite(world, 1)).setPosition(0, 32);
            Kaisa.ScreenBuilder.buildSprite("Map 2", cbMap)
                .setSprite(data.worldMapSprite(world, 2)).setPosition(32, 32);
            Kaisa.ScreenBuilder.buildSprite("Map 3", cbMap)
                .setSprite(data.worldMapSprite(world, 3)).setPosition(32, 0);
        } else {
            cbMap.setSize(32, 32);
            Kaisa.ScreenBuilder.buildSprite("Map 0", cbMap)
                .setSprite(data.worldMapSprite(world, 0));
        }
        return cbMap;
    }

    // GameManager.GetAllDDockDigimons -- all four slots, empty ones included.
    function getAllDDockDigimons() as Array<Number> {
        var out = new [4];
        for (var i = 0; i < 4; i += 1) {
            out[i] = logicMgr.getDDockDigimon(i);
        }
        return out;
    }

    // GameManager.cs:417
    function isInDock(digimonIndex as Number) as Boolean {
        for (var i = 0; i < 4; i += 1) {
            if (logicMgr.getDDockDigimon(i) == digimonIndex) { return true; }
        }
        return false;
    }

    // GameManager.cs:313, which ends in .OrderBy(d => d.order).
    //
    // `order` is an editorial field and does NOT follow row order: checking it
    // (tools/verify_gallery.py) found all eight stages disagreeing, one of them
    // by 200 rows. So the sorted sequence is packed at build time and walked
    // here -- the alternative is sorting up to 136 rows on a menu press.
    // The other two queries below do NOT sort in the original, so they stay in
    // row order.
    function getAllUnlockedDigimonInStage(stage as Number) as Array<Number> {
        var out = [] as Array<Number>;
        var n = data.orderCount();
        for (var k = 0; k < n; k += 1) {
            var i = data.orderIndex(k);
            if (db.isDisabled(i)) { continue; }
            if (data.stage(i) == stage && logicMgr.getDigimonUnlocked(i)) {
                out.add(i);
            }
        }
        return out;
    }

    // GameManager.cs:322
    function getAllUnlockedSpiritsOfElement(element as Number) as Array<Number> {
        var out = [] as Array<Number>;
        var n = db.count();
        for (var i = 0; i < n; i += 1) {
            if (db.isDisabled(i)) { continue; }
            if (data.stage(i) == Kaisa.STAGE_SPIRIT
                    && data.element(i) == element
                    && data.spiritType(i) != Kaisa.SPIRIT_FUSION
                    && logicMgr.getDigimonUnlocked(i)) {
                out.add(i);
            }
        }
        return out;
    }

    // GameManager.cs:360 -- "Returns true if the player has both the Human
    // and Animal form of a spirit."
    function hasBothFormsOfSpirit(element as Number) as Boolean {
        var count = 0;
        var n = db.count();
        for (var i = 0; i < n; i += 1) {
            if (db.isDisabled(i)) { continue; }
            if (data.stage(i) == Kaisa.STAGE_SPIRIT && data.element(i) == element) {
                var st = data.spiritType(i);
                if ((st == Kaisa.SPIRIT_HUMAN || st == Kaisa.SPIRIT_ANIMAL)
                        && logicMgr.getDigimonUnlocked(i)) {
                    count += 1;
                }
            }
        }
        return count == 2;
    }

    // GameManager.cs:376 -- whether the player holds every spirit a fusion
    // needs. The original branches on the fusion's NAME; the same two fusions
    // are matched by index here, and the five elements each one counts come
    // from WellKnown (tools/gen_wellknown.py parses them out of the source).
    //
    // A fusion that is neither of those two counts all twenty spirits, which
    // is what the original's `else` does.
    function hasAllSpiritsForFusion(fusionIndex as Number) as Boolean {
        var elements = null;
        for (var i = 0; i < Kaisa.WellKnown.FUSION_ELEMENTS.size(); i += 1) {
            var row = Kaisa.WellKnown.FUSION_ELEMENTS[i];
            if (row[0] == fusionIndex) { elements = row[1]; break; }
        }

        var count = 0;
        var n = db.count();
        for (var i = 0; i < n; i += 1) {
            if (data.stage(i) != Kaisa.STAGE_SPIRIT) { continue; }
            var type = data.spiritType(i);
            if (type != Kaisa.SPIRIT_HUMAN && type != Kaisa.SPIRIT_ANIMAL) { continue; }
            if (elements != null && elements.indexOf(data.element(i)) < 0) { continue; }
            if (logicMgr.getDigimonUnlocked(i)) { count += 1; }
        }

        return (elements != null) ? (count == 10) : (count == 20);
    }

    // GameManager.cs:348
    function getAllUnlockedFusionDigimon() as Array<Number> {
        var out = [] as Array<Number>;
        var n = db.count();
        for (var i = 0; i < n; i += 1) {
            if (db.isDisabled(i)) { continue; }
            if (data.stage(i) == Kaisa.STAGE_SPIRIT
                    && data.spiritType(i) == Kaisa.SPIRIT_FUSION
                    && logicMgr.getDigimonUnlocked(i)) {
                out.add(i);
            }
        }
        return out;
    }
}

// port of AudioManager.cs, which ADR 11 puts out of scope: Connect IQ has no
// API that can play the original's clips on this device. The call sites are
// kept -- `audioMgr.playButtonA()` sits in the middle of ported input
// handlers -- so that the translation stays line-for-line and sound can be
// reconsidered in one place rather than hunted for later.
class AudioManager {
    function initialize() {
    }

    // The trace calls are what the golden animation diffs compare against;
    // they compile away in release along with the rest of Kaisa.Trace.
    function playButtonA() as Void { Kaisa.Trace.event("sound buttonA"); }
    function playButtonB() as Void { Kaisa.Trace.event("sound buttonB"); }
    function playCharHappy() as Void { Kaisa.Trace.event("sound charHappy"); }
    function playCharSad() as Void { Kaisa.Trace.event("sound charSad"); }
    function playSound(s as String) as Void { Kaisa.Trace.event("sound " + s); }
    function stopSound() as Void { Kaisa.Trace.event("stopSound"); }
}
