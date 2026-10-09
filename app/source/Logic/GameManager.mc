import Toybox.Lang;
import Toybox.System;

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
    // The save FORMAT, as opposed to the loaded game: making a new record or
    // erasing the slot needs it, and those belong to the title screen.
    var saveFormat as SaveFormat?;
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
        runner = new Runner();
        audioMgr = new AudioManager(runner);
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

    // A record for a game that has not started: the save format's defaults
    // plus the name the player gave it. GameLoader.CreateNewGame writes one of
    // these before the digivice scene opens.
    function freshRecord(name as String) as SaveRecord {
        return saveFormat.createDefault(name);
    }

    // GameManager.cs:180 -- the punishment for quitting mid-battle, applied
    // on the next launch. `leaverBusterDigimonLoss` is -1 rather than "" when
    // there is nothing to lose (ADR 7: Digimon are indices).
    function checkLeaverBuster() as Void {
        if (!saved.record.isLeaverBusterActive) { return; }
        // An unfinished event battle restarts from its saved event marker.
        // Applying the quit penalty here would change the player's progress
        // before they get that retry, and could leave them defeated at Camp.
        if (logicMgr.savedEventIsActiveBattle()) {
            disableLeaverBuster();
            return;
        }

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
    // the step count by one." A detected wrist shake calls this while the
    // watch app is visible. The character screen's B button also handles
    // the final kilometre (LogicManager.inputB).
    function takeAStep() as Void {
        // One physical shake earns the selected number of game steps, with
        // the same first-gate limit used for Garmin walking credit.
        (new JourneyStepSync()).applyDelta(self, 1l, false);
        if (saved.savedEvent() != 0 && !saved.commit()) { return; }
        checkPendingEvents();
    }

    // One model step without sound or event presentation. Used by catch-up
    // walking until the first pending story event or boss stop.
    function takeModelStep() as Void {
        worldMgr.takeSteps(1);
        worldMgr.reduceDistance(1);
        if (worldMgr.currentDistance() == 1) { saved.setSavedEvent(2); }
    }

    // GameManager.cs:205 -- whether a saved event should start now. An app on
    // screen defers it (the Status app excepted, as in the original), and so
    // does an animation still playing.
    function checkPendingEvents() as Void {
        if (logicMgr.isAppLoaded() && !(logicMgr.loadedApp instanceof Status)) { return; }
        if (screenMgr.playingAnimations) { return; }
        if (logicMgr.isEventPending) { return; }
        // An interrupted encounter stays saved. A defeated character needs
        // to reach Camp before it can be offered again.
        if (isCharacterDefeated()) { return; }

        var savedEvent = saved.savedEvent();
        if (savedEvent == 0) { return; }
        // Showing the prompt is not the same as posting a watch notification.
        // Keep this gate eligible if the player closes the app before acting.
        if (!saved.commit()) { return; }
        if (savedEvent == logicMgr.SAVE_EVENT_RANDOM_WAITING
                || savedEvent == logicMgr.SAVE_EVENT_RANDOM_ACTIVE
                || savedEvent == logicMgr.SAVE_EVENT_STORM_STAY_ACTIVE
                || savedEvent == logicMgr.SAVE_EVENT_STORM_MOVED_ACTIVE) {
            logicMgr.enqueueRegularEvent();
            if (logicMgr.isAppLoaded()) { logicMgr.closeLoadedApp(Kaisa.SCREEN_CHARACTER); }
        } else if (savedEvent == logicMgr.SAVE_EVENT_BOSS_WAITING
                || savedEvent == logicMgr.SAVE_EVENT_BOSS_ACTIVE) {
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
        (new JourneyStepSync()).beginGame(saved.record,
            (new GarminStepReader()).read(true));

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
    // The null guard is what is left of the port's scaffolding: every one of
    // Animations.cs's 53 coroutines is translated and every call site passes
    // one, so nothing reaches here with null any more.
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

// Keep source sound names in traces so screen and animation verification is
// intact. Menu inputs use vibration only. Debug simulator builds play the
// source's note data; release builds use one short watch-supported cue.
class AudioManager {
    const CUE_ACTION = 0;
    const CUE_POSITIVE = 1;
    const CUE_NEGATIVE = 2;
    const CUE_ALERT = 3;

    var _runner as Runner;
    var _toneFiber as Fiber?;
    var _lastUiVibeAt as Number = -1000;
    var _lastSceneVibeAt as Number = -1000;
    var _eventReminderMs as Number = 0;
    const EVENT_REMINDER_MS = 1600;
    // Set by DTectorView for a screen/anim probe: the trace ("sound X") is
    // what the golden diffs compare, at its SCHEDULED time, and that stays
    // identical either way. What mute skips is the real Attention call --
    // on the dev machine this project builds on, that call's own failure to
    // preview through the simulator's audio stack cost real wall-clock time,
    // which is exactly what a probe must never be at the mercy of (the same
    // reason the RNG is pinned and seedSkeletonStats is probe-only).
    var muted as Boolean = false;

    function initialize(runnerIn as Runner) {
        _runner = runnerIn;
    }

    function playButtonA() as Void { Kaisa.Trace.event("sound buttonA"); vibrateUi(0); }
    function playButtonB() as Void { Kaisa.Trace.event("sound buttonB"); vibrateUi(3); }
    function playMenuMove(dir as Number) as Void {
        Kaisa.Trace.event((dir == Kaisa.DIR_LEFT) ? "sound menuLeft" : "sound menuRight");
        vibrateUi((dir == Kaisa.DIR_LEFT) ? 2 : 1);
    }
    function rejectUnavailable() as Void {
        if (muted || !(Toybox.Attention has :vibrate)) { return; }
        if (!System.getDeviceSettings().vibrateOn || !Kaisa.Prefs.vibrationOn()) { return; }
        // A short buzz followed by a stronger, longer stop signal. This is
        // distinct from the single tap used for Back or normal menu input.
        Toybox.Attention.vibrate([
            new Toybox.Attention.VibeProfile(85, 110),
            new Toybox.Attention.VibeProfile(0, 85),
            new Toybox.Attention.VibeProfile(100, 240)
        ] as Array<Toybox.Attention.VibeProfile>);
    }
    function playCharHappy() as Void { Kaisa.Trace.event("sound charHappy"); play("charHappy"); }
    function playCharSad() as Void { Kaisa.Trace.event("sound charSad"); play("charSad"); }
    function playSound(s as String) as Void { Kaisa.Trace.event("sound " + s); play(s); }

    // Attention cannot cancel a tone already handed to the device. In the
    // simulator, stopping the fiber prevents further source-note chunks.
    function stopSound() as Void {
        Kaisa.Trace.event("stopSound");
        _runner.stopSilent(_toneFiber);
        _toneFiber = null;
        if (!muted) { emitSimulatorAudioStop(); }
    }

    // Venu 4's speaker cannot synthesize the source's frequencies. The SDK's
    // SUCCESS sample has a five-note, ~1.7 s contour close to the six-note,
    // ~1.6 s charHappy effect; FAILURE similarly falls for charSad. Play each
    // as one built-in sample. Stacking several Garmin alerts previously made
    // the result sound like a ringtone. Other effects keep their short cues.
    // Each pair remains [tone, delay] for the watch-cue coverage test.
    function scoreFor(name as String) as Array<Array<Number>> {
        var A = Toybox.Attention;
        if (name.equals("charHappy")) { return [[A.TONE_SUCCESS, 0]]; }
        if (name.equals("charSad")) { return [[A.TONE_FAILURE, 0]]; }
        var cue = cueFor(name);
        if (cue == CUE_POSITIVE) { return [[A.TONE_START, 0]]; }
        if (cue == CUE_NEGATIVE) { return [[A.TONE_STOP, 0]]; }
        if (cue == CUE_ALERT) { return [[A.TONE_MSG, 0]]; }
        // TONE_KEY can be silenced separately by the watch's key-tone setting.
        if (cue == CUE_ACTION) { return [[A.TONE_MSG, 0]]; }
        return [];
    }

    // Every source effect is classified; button feedback has its own short
    // vibration patterns and never calls Attention.playTone.
    function cueFor(name as String) as Number {
        if (name.equals("buttonA") || name.equals("buttonB")
                || Kaisa.Sounds.indexOf(name) < 0) { return -1; }
        if (name.equals("charHappy") || name.equals("digiPowerSucceed")
                || name.equals("evolutionAncient") || name.equals("evolutionRegular")
                || name.equals("evolutionSpirit") || name.equals("gameStart")
                || name.equals("levelUp") || name.equals("reward")
                || name.equals("speedRunner_Finish") || name.equals("summonDigimon")
                || name.equals("unlockCode") || name.equals("unlockDigimon")) {
            return CUE_POSITIVE;
        }
        if (name.equals("charSad") || name.equals("destroySpirits")
                || name.equals("digiPowerFailed") || name.equals("levelDown")
                || name.equals("levelDownDigimon") || name.equals("loseDigimon")
                || name.equals("punishment") || name.equals("speedRunner_Crash")
                || name.equals("unpleasantBeep")) {
            return CUE_NEGATIVE;
        }
        if (name.equals("digistorm") || name.equals("encounterDigimon")
                || name.equals("encounterDigimonBoss") || name.equals("explosion")
                || name.equals("stealAllSpirits") || name.equals("triggerEvent")) {
            return CUE_ALERT;
        }
        return CUE_ACTION;
    }

    function vibeFor(name as String) as Array? {
        var V = Toybox.Attention;
        var cue = cueFor(name);
        if (name.equals("triggerEvent")) {
            // Four hard, close beats. Seven profiles stay below Garmin's
            // eight-profile limit and leave a distinct gap before repeating.
            return [new V.VibeProfile(100, 110), new V.VibeProfile(0, 35),
                    new V.VibeProfile(100, 110), new V.VibeProfile(0, 35),
                    new V.VibeProfile(100, 110), new V.VibeProfile(0, 35),
                    new V.VibeProfile(100, 250)];
        } else if (cue == CUE_POSITIVE) {
            return [new V.VibeProfile(50, 120), new V.VibeProfile(0, 80),
                    new V.VibeProfile(50, 120)];
        } else if (cue == CUE_NEGATIVE) {
            return [new V.VibeProfile(80, 300)];
        } else if (cue == CUE_ALERT) {
            return [new V.VibeProfile(70, 100), new V.VibeProfile(0, 70),
                    new V.VibeProfile(70, 100), new V.VibeProfile(0, 70),
                    new V.VibeProfile(70, 100)];
        } else if (cue == CUE_ACTION) {
            return [new V.VibeProfile(40, 100)];
        }
        return null;
    }

    // Deliberately untraced, like the sound fiber: the original has no
    // vibration at all, so any event emitted here would have no counterpart
    // in the golden reference and would desync every diff that follows it.
    // Switching vibration ON in the Configure menu: a buzz is the only
    // confirmation a buzz can have. Not part of the curated event table --
    // it belongs to the menu, not to a game moment.
    function confirmVibration() as Void {
        if (!(Toybox.Attention has :vibrate)) { return; }
        if (!System.getDeviceSettings().vibrateOn) { return; }
        if (!Kaisa.Prefs.vibrationOn()) { return; }
        Toybox.Attention.vibrate(
            [new Toybox.Attention.VibeProfile(50, 150)]
                as Array<Toybox.Attention.VibeProfile>);
    }

    function vibrate(name as String) as Void {
        if (!(Toybox.Attention has :vibrate)) { return; }
        if (!System.getDeviceSettings().vibrateOn) { return; }
        if (!Kaisa.Prefs.vibrationOn()) { return; }
        var now = System.getTimer();
        if (cueFor(name) == CUE_ALERT && now >= _lastSceneVibeAt
                && now - _lastSceneVibeAt < 800) { return; }
        var profiles = vibeFor(name);
        if (profiles == null) { return; }
        Toybox.Attention.vibrate(profiles as Array<Toybox.Attention.VibeProfile>);
    }

    // A scene can begin before its first source sound cue. Give monster
    // encounters and story cut scenes a distinct, immediate four-beat cue.
    function vibrateScene() as Void {
        if (muted || !(Toybox.Attention has :vibrate)) { return; }
        if (!System.getDeviceSettings().vibrateOn || !Kaisa.Prefs.vibrationOn()) { return; }
        _lastSceneVibeAt = System.getTimer();
        Toybox.Attention.vibrate([
            new Toybox.Attention.VibeProfile(100, 130),
            new Toybox.Attention.VibeProfile(0, 35),
            new Toybox.Attention.VibeProfile(100, 130),
            new Toybox.Attention.VibeProfile(0, 35),
            new Toybox.Attention.VibeProfile(100, 130),
            new Toybox.Attention.VibeProfile(0, 35),
            new Toybox.Attention.VibeProfile(100, 300)
        ] as Array<Toybox.Attention.VibeProfile>);
    }

    // The prompt stays visible until an action starts the encounter. Only
    // the foreground tick calls this, so a closed app cannot keep buzzing.
    function tickEventReminder(pending as Boolean, elapsedMs as Number) as Boolean {
        if (!pending) { _eventReminderMs = 0; return false; }
        _eventReminderMs += elapsedMs;
        if (_eventReminderMs < EVENT_REMINDER_MS) { return false; }
        _eventReminderMs = 0;
        if (!muted) { vibrate("triggerEvent"); }
        return true;
    }

    // A shorter, uneven double beat follows the storm across the screen.
    // The animation spaces calls apart so profiles never form a continuous buzz.
    function vibrateStormPulse(phase as Number) as Void {
        if (muted || !(Toybox.Attention has :vibrate)) { return; }
        if (!System.getDeviceSettings().vibrateOn || !Kaisa.Prefs.vibrationOn()) { return; }
        var strong = phase % 2 == 0;
        Toybox.Attention.vibrate([
            new Toybox.Attention.VibeProfile(strong ? 75 : 55, 90),
            new Toybox.Attention.VibeProfile(0, 70),
            new Toybox.Attention.VibeProfile(strong ? 95 : 80, strong ? 190 : 140)
        ] as Array<Toybox.Attention.VibeProfile>);
    }

    function play(name as String) as Void {
        _runner.stopSilent(_toneFiber);
        _toneFiber = null;
        if (!muted) { emitSimulatorAudioStop(); }
        if (muted) { return; }
        var cue = cueFor(name);
        if (cue < 0) { return; }
        vibrate(name);
        if (!Kaisa.Prefs.soundOn()) { return; }
        emitSimulatorAudioPlay(name);
        if (!(Toybox.Attention has :playTone)) { return; }
        // The game setting gates both playback paths. The device setting
        // gates Garmin's native tone; a debug Mac preview can still play with
        // simulator Tones off so the two paths do not echo each other.
        if (!System.getDeviceSettings().tonesOn) { return; }
        playEffectTone(name);
    }

    // A local development runner can play the source MP3 on the Mac when the
    // simulator's ToneProfile audio backend is silent. The release build and
    // muted verification probes emit no bridge messages.
    (:debug)
    function emitSimulatorAudioPlay(name as String) as Void {
        System.println("SIM_AUDIO " + name);
    }

    (:release)
    function emitSimulatorAudioPlay(name as String) as Void {
    }

    (:debug)
    function emitSimulatorAudioStop() as Void {
        System.println("SIM_AUDIO_STOP");
    }

    (:release)
    function emitSimulatorAudioStop() as Void {
    }

    (:debug)
    function playEffectTone(name as String) as Void {
        if (name.equals("charHappy")) {
            _toneFiber = _runner.startSilent(new HappySoundRoutine());
            return;
        }
        var idx = Kaisa.Sounds.indexOf(name);
        if (idx >= 0) {
            _toneFiber = _runner.startSilent(new SourceSoundRoutine(idx));
        }
    }

    (:release)
    function playEffectTone(name as String) as Void {
        var score = scoreFor(name);
        if (score.size() > 0) {
            Toybox.Attention.playTone(score[0][0] as Toybox.Attention.Tone);
        }
    }

    // Limit bursts so a rapid run through a menu does not build a long queue
    // of vibration. The input itself still moves on every press.
    function vibrateUi(cue as Number) as Void {
        var now = System.getTimer();
        if (now >= _lastUiVibeAt && now - _lastUiVibeAt < 120) {
            return;
        }
        if (muted || !(Toybox.Attention has :vibrate)) { return; }
        if (!System.getDeviceSettings().vibrateOn || !Kaisa.Prefs.vibrationOn()) { return; }
        _lastUiVibeAt = now;
        var strength = cue == 3 ? 65 : (cue == 0 ? 50 : 40);
        var duration = cue == 3 ? 140 : (cue == 0 ? 100 : 70);
        Toybox.Attention.vibrate(
            [new Toybox.Attention.VibeProfile(strength, duration)]
                as Array<Toybox.Attention.VibeProfile>);
    }
}

// The simulator can synthesize ToneProfile notes. On Venu 4 hardware these
// calls can be silent even though the same API reports support. Keep this
// original-audio preview out of the release build.
(:debug)
class SourceSoundRoutine extends Routine {
    const CHUNK_MS = 220;
    var _soundIndex as Number;
    var _n as Number = 0;
    var _remainMs as Number = 0;

    function initialize(idx as Number) {
        Routine.initialize();
        _soundIndex = idx;
    }

    function step(rt as Fiber) as Float {
        var count = Kaisa.Sounds.COUNTS[_soundIndex];
        if (_n >= count) { return Routine.DONE; }
        var note = Kaisa.Sounds.noteAt(_soundIndex, _n);
        if (note[0] == 0) {
            var restMs = (_remainMs > 0) ? _remainMs : note[1];
            _remainMs = 0;
            _n += 1;
            return restMs.toFloat() / 1000.0;
        }

        var profiles = new [0];
        var totalMs = 0;
        while (_n < count && totalMs < CHUNK_MS) {
            note = Kaisa.Sounds.noteAt(_soundIndex, _n);
            var freq = note[0];
            if (freq == 0) { break; }
            var left = (_remainMs > 0) ? _remainMs : note[1];
            var room = CHUNK_MS - totalMs;
            if (left > room) {
                profiles.add(new Toybox.Attention.ToneProfile(freq, room));
                totalMs += room;
                _remainMs = left - room;
            } else {
                profiles.add(new Toybox.Attention.ToneProfile(freq, left));
                totalMs += left;
                _remainMs = 0;
                _n += 1;
            }
        }
        if (profiles.size() > 0) {
            Toybox.Attention.playTone({ :toneProfile => profiles });
        }
        return totalMs.toFloat() / 1000.0;
    }
}

// The extractor mistakes some strong odd harmonics of char_happy.mp3 for
// fundamentals. These six frequencies and onsets were measured from the MP3;
// one call keeps the complete melody intact in the simulator.
(:debug)
class HappySoundRoutine extends Routine {
    function initialize() { Routine.initialize(); }

    function step(rt as Fiber) as Float {
        var profiles = [
            new Toybox.Attention.ToneProfile(819, 234),
            new Toybox.Attention.ToneProfile(1093, 340),
            new Toybox.Attention.ToneProfile(1024, 149),
            new Toybox.Attention.ToneProfile(910, 150),
            new Toybox.Attention.ToneProfile(1024, 150),
            new Toybox.Attention.ToneProfile(1093, 537)
        ];
        Toybox.Attention.playTone({ :toneProfile => profiles });
        return Routine.DONE;
    }
}
