import Toybox.Lang;
import Toybox.Test;

(:test)
function jackpotRepeatedKeyHasVisiblePause(logger as Test.Logger) as Boolean {
    var data = new GameData();
    data.load();
    var db = new Database(data);
    db.load();
    var format = new SaveFormat(data);
    var rec = format.createDefault("JACKPOT");
    rec.gameChar = Kaisa.CHAR_TAKUYA;
    var gm = new GameManager(data, db, new SavedGame(format, 0, rec));
    gm.audioMgr.muted = true;
    var app = new JackpotBox(gm, gm.logicMgr, new ContainerBuilder());
    app.pattern = [0, 0];
    app.delay = 0.25;
    app.displayPattern();

    var firstOn = -1;
    var firstOff = -1;
    var secondOn = -1;
    var wasLit = false;
    for (var ms = 50; ms <= 5000; ms += 50) {
        gm.runner.advance(50.0d);
        var lit = app.keys.size() > 0 && app.keys[0].active;
        if (lit && !wasLit && firstOn < 0) { firstOn = ms; }
        else if (!lit && wasLit && firstOff < 0) { firstOff = ms; }
        else if (lit && !wasLit && firstOff >= 0) { secondOn = ms; break; }
        wasLit = lit;
    }
    // The hourglass lasts 0.75 s; leave another 0.20 s blank before cue 1.
    return firstOn >= 900 && firstOn <= 1000 && firstOff - firstOn >= 600
        && secondOn - firstOff >= 150 && secondOn - firstOff <= 250;
}

class JackpotLastKeyProbe extends JackpotBox {
    var battleDecided as Boolean = false;

    function initialize(gmIn as GameManager, controllerIn, parent as ScreenElement) {
        JackpotBox.initialize(gmIn, controllerIn, parent);
    }

    function decideBattle() as Void {
        battleDecided = true;
    }
}

(:test)
function jackpotFinalInputIsShownBeforeAttack(logger as Test.Logger) as Boolean {
    var data = new GameData();
    data.load();
    var db = new Database(data);
    db.load();
    var format = new SaveFormat(data);
    var rec = format.createDefault("LASTKEY");
    rec.gameChar = Kaisa.CHAR_TAKUYA;
    var gm = new GameManager(data, db, new SavedGame(format, 0, rec));
    gm.audioMgr.muted = true;
    var app = new JackpotLastKeyProbe(gm, gm.logicMgr, new ContainerBuilder());
    app.pattern = [0];
    app.playerSelection = [-1];
    app.currentScreen = 1;
    app.keys = [Kaisa.ScreenBuilder.buildSprite("Last Key", app.screen)
        .setSprite(Kaisa.Sprites.JACKPOT_KEYS[0]).setActive(false)];

    app.inputKey(0);
    gm.runner.advance(50.0d);
    var shownBeforeAttack = app.keys[0].active && !app.battleDecided;
    app.inputLeft();
    var ignoresExtraInput = app.currentKey == 1;
    gm.runner.advance(150.0d);
    var heldLongEnough = app.keys[0].active && !app.battleDecided;
    gm.runner.advance(50.0d);
    var pulseCompletedBeforeAttack = !app.keys[0].active && !app.battleDecided;
    app.tick(50);
    return shownBeforeAttack && ignoresExtraInput && heldLongEnough
        && pulseCompletedBeforeAttack
        && app.battleDecided && app.playerSelection[0] == 0;
}

function jackpotAnimationShowsSprite(el as ScreenElement?, sprite as Array<Number>) as Boolean {
    if (el == null || !el.active) { return false; }
    if (el instanceof SpriteBuilder) {
        var shown = (el as SpriteBuilder).sprite;
        if (shown != null && shown.size() == sprite.size()) {
            var same = true;
            for (var i = 0; i < sprite.size(); i += 1) {
                if (shown[i] != sprite[i]) { same = false; break; }
            }
            if (same) { return true; }
        }
    }
    for (var j = 0; j < el.children.size(); j += 1) {
        if (jackpotAnimationShowsSprite(el.children[j], sprite)) { return true; }
    }
    return false;
}

// Exercise the whole empty-box branch and inspect every displayed animation
// frame. A happy character sprite anywhere after the empty roll is the watch
// symptom, even if the queued reward animation itself is correct.
function jackpotEmptyBoxShowsSadForCharacter(gameChar as Number) as Boolean {
    var data = new GameData();
    data.load();
    var db = new Database(data);
    db.load();
    var format = new SaveFormat(data);
    var rec = format.createDefault("EMPTYBOX");
    rec.gameChar = gameChar;
    // Every possible roll (0..19) is above this test-only value.
    rec.jackpotValue = -1;
    var gm = new GameManager(data, db, new SavedGame(format, 0, rec));
    gm.audioMgr.muted = true;
    var root = new ContainerBuilder();
    var screenMgr = new ScreenManager(gm, root);
    gm.attachScreenManager(screenMgr);

    var app = new JackpotBox(gm, gm.logicMgr, screenMgr.screenDisplay);
    app.friendlyDigimon = 0;
    app.pattern = [0, 0, 0, 0];
    app.playerSelection = [0, 0, 0, 0];
    gm.logicMgr.loadedApp = app;
    gm.logicMgr.currentScreen = Kaisa.SCREEN_APP;

    // Any initial reward is replaced with Empty after the box breaks.
    app.decideBattle();

    var characterSprites = gm.characterSprites(gameChar);
    var sawEmpty = false;
    var sawSad = false;
    var sawHappy = false;
    for (var ms = 0; ms < 60000 && screenMgr.playingAnimations; ms += 50) {
        gm.runner.advance(50.0d);
        screenMgr.updateQueue();
        var frame = screenMgr.animParent;
        if (jackpotAnimationShowsSprite(frame, Kaisa.Sprites.STATUS_DDOCK_EMPTY)) {
            sawEmpty = true;
        }
        if (jackpotAnimationShowsSprite(frame, characterSprites[7])) {
            sawSad = true;
        }
        if (jackpotAnimationShowsSprite(frame, characterSprites[6])) {
            sawHappy = true;
        }
    }
    return sawEmpty && sawSad && !sawHappy && !screenMgr.playingAnimations;
}

(:test)
function jackpotEmptyBoxShowsSadCharacter(logger as Test.Logger) as Boolean {
    for (var gameChar = Kaisa.CHAR_TAKUYA;
            gameChar <= Kaisa.CHAR_KOICHI; gameChar += 1) {
        if (!jackpotEmptyBoxShowsSadForCharacter(gameChar)) { return false; }
    }
    return true;
}

(:debug)
class JackpotDigimonRewardProbe extends JackpotBox {
    var forcedReward as Number = Kaisa.REWARD_REWARD_DIGIMON;
    function initialize(gmIn as GameManager, controllerIn, parent as ScreenElement) {
        JackpotBox.initialize(gmIn, controllerIn, parent);
    }

    function getRandomReward(category as Number) as Number {
        return forcedReward;
    }
}

(:debug)
function jackpotRewardDisplaysSelectedDigimon(reward as Number, newDigimon as Boolean,
        logger as Test.Logger) as Boolean {
    var data = new GameData();
    data.load();
    var db = new Database(data);
    db.load();
    var format = new SaveFormat(data);
    var rec = format.createDefault("DIGIMONREWARD");
    rec.gameChar = Kaisa.CHAR_TAKUYA;
    rec.jackpotValue = 20;
    for (var i = 0; i < rec.digimonLevel.size(); i += 1) {
        rec.digimonLevel[i] = newDigimon ? 0 : 1;
    }
    var gm = new GameManager(data, db, new SavedGame(format, 0, rec));
    gm.audioMgr.muted = true;
    var root = new ContainerBuilder();
    var screenMgr = new ScreenManager(gm, root);
    gm.attachScreenManager(screenMgr);
    var app = new JackpotDigimonRewardProbe(gm, gm.logicMgr, screenMgr.screenDisplay);
    app.forcedReward = reward;
    // 0 selects an owned common Digimon; 6000000 selects from the database.
    var roll = newDigimon ? 6000000 : 0;
    var candidates;
    if (reward == Kaisa.REWARD_UNLOCK_DIGICODE_OWNED) {
        candidates = gm.logicMgr.getAllUnlockedDigimon();
    } else if (reward == Kaisa.REWARD_UNLOCK_DIGICODE_NOT_OWNED) {
        candidates = db.getAllDigimonOfRarity(Kaisa.RARITY_COMMON, 100);
    } else if (newDigimon) {
        candidates = db.getAllDigimonOfRarity(Kaisa.RARITY_COMMON,
            gm.logicMgr.getPlayerLevel() + 20);
    } else {
        candidates = gm.logicMgr.unlockedOfRarity(Kaisa.RARITY_COMMON);
    }
    var awarded = candidates[roll % candidates.size()];
    app.friendlyDigimon = db.defaultDigimon;
    app.pattern = [0, 0, 0, 0];
    app.playerSelection = [0, 0, 0, 0];
    gm.logicMgr.loadedApp = app;
    gm.logicMgr.currentScreen = Kaisa.SCREEN_APP;
    var previousRoll = Kaisa.Rand.forced;
    Kaisa.Rand.forced = roll;
    app.decideBattle();
    Kaisa.Rand.forced = previousRoll;

    var sawAwarded = false;
    var sawHappy = false;
    var sawEmpty = false;
    for (var ms = 0; ms < 60000 && screenMgr.playingAnimations; ms += 50) {
        gm.runner.advance(50.0d);
        screenMgr.updateQueue();
        // Only inspect the reward, after the attack and box animation.
        if (screenMgr._playing != null && screenMgr._playing.stack.size() > 0
                && (screenMgr._playing.stack[0] instanceof SummonDigimon
                    || screenMgr._playing.stack[0] instanceof RewardCode)) {
            sawAwarded = sawAwarded || jackpotAnimationShowsSprite(screenMgr.animParent,
                gm.digimonSprite(awarded, data.ACTION_BASE));
        }
        sawHappy = sawHappy || jackpotAnimationShowsSprite(screenMgr.animParent,
            gm.characterSprites(rec.gameChar)[6]);
        sawEmpty = sawEmpty || jackpotAnimationShowsSprite(screenMgr.animParent,
            Kaisa.Sprites.STATUS_DDOCK_EMPTY);
    }
    logger.debug("Awarded Digimon shown=" + sawAwarded + ", happy=" + sawHappy
        + ", empty=" + sawEmpty);
    var rewardSaved = gm.logicMgr.getDigimonUnlocked(awarded);
    if (reward == Kaisa.REWARD_REWARD_DIGIMON && !newDigimon) {
        rewardSaved = rewardSaved && gm.logicMgr.getDigimonExtraLevel(awarded) > 0;
    } else if (reward != Kaisa.REWARD_REWARD_DIGIMON) {
        rewardSaved = rewardSaved && gm.logicMgr.getDigicodeUnlocked(awarded);
    }
    return sawAwarded && sawHappy && !sawEmpty && rewardSaved
        && !screenMgr.playingAnimations;
}

(:test)
function jackpotDigimonRewardDisplaysAwardedDigimon(logger as Test.Logger) as Boolean {
    return jackpotRewardDisplaysSelectedDigimon(Kaisa.REWARD_REWARD_DIGIMON, false, logger)
        && jackpotRewardDisplaysSelectedDigimon(Kaisa.REWARD_REWARD_DIGIMON, true, logger);
}

(:test)
function jackpotCodeRewardDisplaysSelectedDigimon(logger as Test.Logger) as Boolean {
    return jackpotRewardDisplaysSelectedDigimon(Kaisa.REWARD_UNLOCK_DIGICODE_OWNED, false, logger)
        && jackpotRewardDisplaysSelectedDigimon(Kaisa.REWARD_UNLOCK_DIGICODE_NOT_OWNED, true, logger);
}

(:test)
function jackpotNoEligibleDigimonShowsEmptyAndSad(logger as Test.Logger) as Boolean {
    var data = new GameData();
    data.load();
    var db = new Database(data);
    db.load();
    var format = new SaveFormat(data);
    var rec = format.createDefault("NOELIGIBLE");
    rec.gameChar = Kaisa.CHAR_TAKUYA;
    rec.jackpotValue = 20;
    var gm = new GameManager(data, db, new SavedGame(format, 0, rec));
    gm.audioMgr.muted = true;
    var screenMgr = new ScreenManager(gm, new ContainerBuilder());
    gm.attachScreenManager(screenMgr);
    var app = new JackpotDigimonRewardProbe(gm, gm.logicMgr, screenMgr.screenDisplay);
    app.friendlyDigimon = db.defaultDigimon;
    app.pattern = [0, 0, 0, 0];
    app.playerSelection = [0, 0, 0, 0];
    gm.logicMgr.loadedApp = app;
    gm.logicMgr.currentScreen = Kaisa.SCREEN_APP;
    var previousRoll = Kaisa.Rand.forced;
    Kaisa.Rand.forced = 0;
    app.decideBattle();
    Kaisa.Rand.forced = previousRoll;
    var sawEmpty = false;
    var sawSad = false;
    var sawHappy = false;
    for (var ms = 0; ms < 60000 && screenMgr.playingAnimations; ms += 50) {
        gm.runner.advance(50.0d);
        screenMgr.updateQueue();
        sawEmpty = sawEmpty || jackpotAnimationShowsSprite(screenMgr.animParent,
            Kaisa.Sprites.STATUS_DDOCK_EMPTY);
        sawSad = sawSad || jackpotAnimationShowsSprite(screenMgr.animParent,
            gm.characterSprites(rec.gameChar)[7]);
        sawHappy = sawHappy || jackpotAnimationShowsSprite(screenMgr.animParent,
            gm.characterSprites(rec.gameChar)[6]);
    }
    return sawEmpty && sawSad && !sawHappy && !screenMgr.playingAnimations
        && gm.logicMgr.getAllUnlockedDigimon().size() == 0;
}
