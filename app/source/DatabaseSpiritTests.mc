import Toybox.Lang;
import Toybox.Test;

(:test)
function spiritSectionIsReachableAfterQuickNavigation(logger as Test.Logger) as Boolean {
    var data = new GameData();
    data.load();
    var db = new Database(data);
    db.load();
    var format = new SaveFormat(data);
    var rec = format.createDefault("SPIRIT");
    rec.gameChar = Kaisa.CHAR_TAKUYA;
    var saved = new SavedGame(format, 0, rec);
    var gm = new GameManager(data, db, saved);
    gm.logicMgr.setDigimonUnlocked(Kaisa.WellKnown.PLAYER_SPIRIT[0], true);
    var root = new ContainerBuilder();
    var app = new DatabaseApp(gm, gm.logicMgr, root);
    app.startApp();
    for (var i = 0; i < 6; i += 1) { app.inputRight(); }
    if (app.menuIndex != Kaisa.STAGE_SPIRIT) { return false; }
    app.inputA();
    return app.currentScreen == app.SCREEN_MENU_SPIRIT
        && app.availableElements.size() > 0;
}

(:test)
function battleSpiritOptionOpensWithUnlockedSpirit(logger as Test.Logger) as Boolean {
    var data = new GameData();
    data.load();
    var db = new Database(data);
    db.load();
    var format = new SaveFormat(data);
    var rec = format.createDefault("SPIRIT");
    rec.gameChar = Kaisa.CHAR_TAKUYA;
    var saved = new SavedGame(format, 0, rec);
    var gm = new GameManager(data, db, saved);
    gm.logicMgr.setDigimonUnlocked(Kaisa.WellKnown.PLAYER_SPIRIT[0], true);
    var battle = new Battle(gm, gm.logicMgr, new ContainerBuilder());
    battle.menuIndex = 1;
    battle.inputA();
    return battle.currentScreen == battle.SCREEN_SPIRIT_ELEMENTS
        && battle.availableElements.size() > 0;
}

(:test)
function galleryTapMovesBeforeTheNextFrameAndHoldRepeats(logger as Test.Logger) as Boolean {
    var data = new GameData();
    data.load();
    var db = new Database(data);
    db.load();
    var format = new SaveFormat(data);
    var rec = format.createDefault("GALLERY");
    rec.gameChar = Kaisa.CHAR_TAKUYA;
    var gm = new GameManager(data, db, new SavedGame(format, 0, rec));
    gm.audioMgr.muted = true;
    var app = new DatabaseApp(gm, gm.logicMgr, new ContainerBuilder());
    app.currentScreen = app.SCREEN_GALLERY;
    app.galleryList = [0, 1];

    // A short touch queues DOWN and UP before Runner.advance. It must still
    // move one Digimon, then leave no repeat running after release.
    app.inputRightDown();
    app.inputRightUp();
    if (app.galleryIndex != 1) { return false; }
    gm.runner.advance(1000.0d);
    if (app.galleryIndex != 1) { return false; }

    app.inputLeftDown();
    if (app.galleryIndex != 0) { return false; }
    gm.runner.advance(450.0d);
    if (app.galleryIndex != 0) { return false; }
    gm.runner.advance(50.0d);
    if (app.galleryIndex != 1) { return false; }
    app.inputLeftUp();
    gm.runner.advance(1000.0d);
    return app.galleryIndex == 1;
}
