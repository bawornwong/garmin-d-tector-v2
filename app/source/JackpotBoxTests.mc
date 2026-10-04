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
