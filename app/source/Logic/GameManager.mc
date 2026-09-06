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
        worldMgr = new WorldManager(savedIn);
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

    // GameManager.cs:50 -- a per-world flag. The worlds section is packed but
    // its reader belongs with the Map app (SPEC section 8), so this is the
    // default the first world carries until then.
    function showEyes() as Boolean {
        return false;
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
        if (screenMgr != null) {
            screenMgr.enqueueAnimation(routine);
        } else {
            runner.start(routine);
        }
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

    function playButtonA() as Void {}
    function playButtonB() as Void {}
    function playCharHappy() as Void {}
    function playCharSad() as Void {}
}
