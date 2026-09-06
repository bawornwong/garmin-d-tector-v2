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

    function initialize(dataIn as GameData, dbIn as Database, savedIn as SavedGame) {
        data = dataIn;
        db = dbIn;
        saved = savedIn;
        logicMgr = new LogicManager(savedIn, dbIn);
        worldMgr = new WorldManager(savedIn);
        audioMgr = new AudioManager();
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

    // GameManager.GetAllDDockDigimons
    function getAllDDockDigimons() as Array<Number> {
        var out = new [4];
        for (var i = 0; i < 4; i += 1) {
            out[i] = logicMgr.getDDockDigimon(i);
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
