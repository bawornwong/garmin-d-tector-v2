import Toybox.Lang;
import Toybox.Test;

(:test)
function erasingDigimonClearsOnlyItsDDocks(logger as Test.Logger) as Boolean {
    var data = new GameData();
    data.load();
    var db = new Database(data);
    db.load();
    var format = new SaveFormat(data);
    var saved = new SavedGame(format, 0, format.createDefault("DOCK LOSS"));
    var logic = new LogicManager(saved, db);
    var target = db.defaultDigimon;
    var other = db.defaultSpiritDigimon;
    logic.setDigimonUnlocked(target, true);
    logic.setDigimonUnlocked(other, true);
    logic.setDDockDigimon(0, target);
    logic.setDDockDigimon(2, target);
    logic.setDDockDigimon(3, other);

    var result = logic.punishDigimon(target);

    Test.assert(result[0] == 0);
    Test.assert(!logic.getDigimonUnlocked(target));
    logger.debug("D-Docks after punishment: " + logic.getDDockDigimon(0)
        + ", " + logic.getDDockDigimon(2));
    Test.assert(logic.isDDockEmpty(0) && logic.isDDockEmpty(2));
    Test.assert(logic.isDDockEmpty(1) && logic.getDDockDigimon(3) == other);
    return true;
}

// Force the random erase branch so the defeat regression is deterministic.
(:test)
class DDockLossDatabase extends Database {
    function initialize(data as GameData) {
        Database.initialize(data);
    }

    function getEraseChance(index as Number) as Float {
        return -1.0;
    }
}

(:test)
function erasedBattleDigimonLeavesDatabaseAndDDock(logger as Test.Logger) as Boolean {
    var data = new GameData();
    data.load();
    var db = new DDockLossDatabase(data);
    db.load();
    var format = new SaveFormat(data);
    var rec = format.createDefault("DOCK LOSS");
    rec.gameChar = Kaisa.CHAR_TAKUYA;
    var saved = new SavedGame(format, 0, rec);
    var gm = new GameManager(data, db, saved);
    gm.audioMgr.muted = true;
    var root = new ContainerBuilder();
    gm.attachScreenManager(new ScreenManager(gm, root));
    var target = db.defaultDigimon;
    gm.logicMgr.setDigimonUnlocked(target, true);
    gm.logicMgr.setDDockDigimon(2, target);

    var battle = new Battle(gm, gm.logicMgr, root);
    battle.originalDigimon = db.getDigimon(target);
    battle.friendlyDigimon = battle.originalDigimon;
    battle.enemyDigimon = db.getDigimon(db.defaultSpiritDigimon);
    battle.playerLevel = 1;
    gm.logicMgr.loadedApp = battle;
    gm.logicMgr.currentScreen = Kaisa.SCREEN_APP;
    battle.loseBattle();

    Test.assert(!gm.logicMgr.getDigimonUnlocked(target));
    logger.debug("D-Dock after erase: " + gm.logicMgr.getDDockDigimon(2));
    Test.assert(gm.logicMgr.isDDockEmpty(2));
    return true;
}

(:test)
function levelingDownDigimonKeepsItsDDock(logger as Test.Logger) as Boolean {
    var data = new GameData();
    data.load();
    var db = new Database(data);
    db.load();
    var format = new SaveFormat(data);
    var saved = new SavedGame(format, 0, format.createDefault("DOCK LEVEL"));
    var logic = new LogicManager(saved, db);
    var target = db.defaultDigimon;
    logic.setDigimonUnlocked(target, true);
    logic.setDigimonExtraLevel(target, 3);
    logic.setDDockDigimon(1, target);

    var result = logic.punishDigimon(target);

    return result[0] == 1 && logic.getDigimonExtraLevel(target) == 2
        && logic.getDigimonUnlocked(target) && logic.getDDockDigimon(1) == target;
}

(:test)
function losingSpiritClearsItsDDock(logger as Test.Logger) as Boolean {
    var data = new GameData();
    data.load();
    var db = new Database(data);
    db.load();
    var format = new SaveFormat(data);
    var saved = new SavedGame(format, 0, format.createDefault("DOCK SPIRIT"));
    var logic = new LogicManager(saved, db);
    var target = db.playerSpirit[0];
    logic.setDigimonUnlocked(target, true);
    logic.setDDockDigimon(0, target);

    logic.loseSpirit(target);

    return !logic.getDigimonUnlocked(target) && logic.isDDockEmpty(0)
        && saved.lostSpirits().size() == 1 && saved.lostSpirits()[0] == target;
}

(:test)
function loadingSaveRepairsStaleDDocks(logger as Test.Logger) as Boolean {
    var data = new GameData();
    data.load();
    var db = new Database(data);
    db.load();
    var format = new SaveFormat(data);
    var rec = format.createDefault("OLD DOCK");
    var target = db.defaultDigimon;
    var owned = db.defaultSpiritDigimon;
    rec.digimonLevel[owned] = 1;
    rec.ddockDigimon = [target, owned, -1, data.digimonCount()];
    var totals = data.worldTotals();
    var restored = format.decode(format.encode(rec), data.digimonCount(),
        totals[0], totals[1], totals[2]);
    var saved = new SavedGame(format, 0, restored);
    var logic = new LogicManager(saved, db);

    Test.assert(logic.isDDockEmpty(0) && logic.isDDockEmpty(3));
    Test.assert(logic.getDDockDigimon(1) == owned && logic.isDDockEmpty(2));
    Test.assert(saved.isDirty());
    var repaired = format.decode(format.encode(saved.record), data.digimonCount(),
        totals[0], totals[1], totals[2]);
    var reloaded = new SavedGame(format, 0, repaired);
    var reloadedLogic = new LogicManager(reloaded, db);
    return reloadedLogic.isDDockEmpty(0) && reloadedLogic.isDDockEmpty(3)
        && reloadedLogic.getDDockDigimon(1) == owned && !reloaded.isDirty();
}
