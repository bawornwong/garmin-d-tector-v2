import Toybox.Lang;
import Toybox.Test;

(:test)
function activeEventsSurviveSaveRoundTrip(logger as Test.Logger) as Boolean {
    var data = new GameData();
    data.load();
    var format = new SaveFormat(data);
    var totals = data.worldTotals();
    var active = [3, 4, 5, 6];
    for (var i = 0; i < active.size(); i += 1) {
        var rec = format.createDefault("EVENT");
        rec.gameChar = Kaisa.CHAR_TAKUYA;
        rec.pendingEvent = active[i];
        rec.stepSync.gateEpoch = 7;
        var restored = format.decode(format.encode(rec), data.digimonCount(),
            totals[0], totals[1], totals[2]);
        if (restored.pendingEvent != active[i]
                || restored.stepSync.gateEpoch != 7) { return false; }
    }
    return true;
}

(:test)
function interruptedEventKeepsItsKindUntilFinished(logger as Test.Logger) as Boolean {
    var data = new GameData();
    data.load();
    var db = new Database(data);
    db.load();
    var format = new SaveFormat(data);
    var rec = format.createDefault("EVENT");
    rec.pendingEvent = 4; // Data Storm applied without a world move.
    rec.stepSync.gateEpoch = 7;
    var saved = new SavedGame(format, 0, rec);
    var gm = new GameManager(data, db, saved);
    var logic = gm.logicMgr;
    if (logic.kindForSavedEvent(saved.savedEvent()) != logic.EVENT_DATA_STORM
            || saved.savedEvent() != 4) { return false; }
    saved.setSavedEvent(3); // Interrupted monster encounter.
    if (logic.kindForSavedEvent(saved.savedEvent()) != logic.EVENT_RANDOM_BATTLE) {
        return false;
    }
    logic.finishEvent();
    return saved.savedEvent() == 0
        && saved.record.stepSync.gateEpoch == 8;
}

(:test)
function reopeningActiveEventShowsPromptAgain(logger as Test.Logger) as Boolean {
    var data = new GameData();
    data.load();
    var db = new Database(data);
    db.load();
    var format = new SaveFormat(data);
    var markers = [3, 4, 5, 6];
    var kinds = [1, 2, 2, 3];
    for (var i = 0; i < markers.size(); i += 1) {
        var rec = format.createDefault("EVENT");
        rec.gameChar = Kaisa.CHAR_TAKUYA;
        rec.pendingEvent = markers[i];
        rec.stepSync.notifiedGateEpoch = rec.stepSync.gateEpoch;
        var saved = new SavedGame(format, 0, rec);
        var gm = new GameManager(data, db, saved);
        gm.audioMgr.muted = true;
        gm.attachScreenManager(new ScreenManager(gm, new ContainerBuilder()));
        gm.checkPendingEvents();
        if (!gm.logicMgr.isEventPending
                || gm.logicMgr.pendingEvent != kinds[i]
                || saved.savedEvent() != markers[i]) { return false; }
    }
    return true;
}

(:test)
function interruptedEventBattleRestartsWithoutQuitPenalty(logger as Test.Logger) as Boolean {
    var data = new GameData();
    data.load();
    var db = new Database(data);
    db.load();
    var format = new SaveFormat(data);
    var rec = format.createDefault("EVENT");
    rec.gameChar = Kaisa.CHAR_TAKUYA;
    rec.pendingEvent = 3;
    rec.isLeaverBusterActive = true;
    rec.leaverBusterExpLoss = 10;
    rec.leaverBusterDigimonLoss = Kaisa.WellKnown.PLAYER_SPIRIT[0];
    rec.playerExperience = 100;
    rec.currentDistance = 500;
    var saved = new SavedGame(format, 0, rec);
    var gm = new GameManager(data, db, saved);
    gm.checkLeaverBuster();
    return saved.savedEvent() == 3
        && !rec.isLeaverBusterActive
        && rec.playerExperience == 100
        && rec.currentDistance == 500
        && gm.logicMgr.isEventPending == false;
}

(:test)
function unresolvedPromptCanStillNotifyAfterAppCloses(logger as Test.Logger) as Boolean {
    var data = new GameData();
    data.load();
    var db = new Database(data);
    db.load();
    var format = new SaveFormat(data);
    var rec = format.createDefault("EVENT");
    rec.gameChar = Kaisa.CHAR_TAKUYA;
    rec.pendingEvent = 4; // Data Storm waiting for the player's action.
    rec.stepSync.cursorInitialized = true;
    rec.stepSync.gateEpoch = 7;
    rec.stepSync.notifiedGateEpoch = 6;
    var saved = new SavedGame(format, 0, rec);
    var gm = new GameManager(data, db, saved);
    gm.audioMgr.muted = true;
    gm.attachScreenManager(new ScreenManager(gm, new ContainerBuilder()));
    gm.checkPendingEvents();
    var header = new StepHeader();
    header.fromRecord(rec);
    return gm.logicMgr.isEventPending
        && header.sync.notifiedGateEpoch == 6
        && (new StepBackground()).shouldNotify(header);
}

(:test)
function defeatedPlayerDefersInterruptedEventUntilRecovery(logger as Test.Logger) as Boolean {
    var data = new GameData();
    data.load();
    var db = new Database(data);
    db.load();
    var format = new SaveFormat(data);
    var rec = format.createDefault("EVENT");
    rec.gameChar = Kaisa.CHAR_TAKUYA;
    rec.pendingEvent = 3;
    rec.isPlayerDefeated = true;
    rec.stepSync.notifiedGateEpoch = rec.stepSync.gateEpoch;
    var saved = new SavedGame(format, 0, rec);
    var gm = new GameManager(data, db, saved);
    gm.audioMgr.muted = true;
    gm.attachScreenManager(new ScreenManager(gm, new ContainerBuilder()));
    gm.checkPendingEvents();
    if (gm.logicMgr.isEventPending || saved.savedEvent() != 3) { return false; }
    rec.isPlayerDefeated = false;
    gm.checkPendingEvents();
    return gm.logicMgr.isEventPending
        && gm.logicMgr.pendingEvent == gm.logicMgr.EVENT_RANDOM_BATTLE
        && saved.savedEvent() == 3;
}

(:test)
function losingEventBattleClearsPendingEncounter(logger as Test.Logger) as Boolean {
    var data = new GameData();
    data.load();
    var db = new Database(data);
    db.load();
    var format = new SaveFormat(data);
    var rec = format.createDefault("EVENT");
    rec.gameChar = Kaisa.CHAR_TAKUYA;
    rec.pendingEvent = 3;
    rec.stepSync.gateEpoch = 7;
    var saved = new SavedGame(format, 0, rec);
    var gm = new GameManager(data, db, saved);
    gm.audioMgr.muted = true;
    var root = new ContainerBuilder();
    gm.attachScreenManager(new ScreenManager(gm, root));
    var battle = new Battle(gm, gm.logicMgr, root);
    var digimon = db.getDigimon(Kaisa.WellKnown.PLAYER_SPIRIT[0]);
    battle.originalDigimon = digimon;
    battle.friendlyDigimon = digimon;
    battle.enemyDigimon = digimon;
    battle.playerLevel = 1;
    gm.logicMgr.loadedApp = battle;
    gm.logicMgr.currentScreen = Kaisa.SCREEN_APP;
    battle.loseBattle();
    return saved.savedEvent() == 0
        && saved.record.stepSync.gateEpoch == 8
        && !gm.logicMgr.isEventPending;
}

(:test)
function escapingBossBattleClearsPendingEncounter(logger as Test.Logger) as Boolean {
    var data = new GameData();
    data.load();
    var db = new Database(data);
    db.load();
    var format = new SaveFormat(data);
    var rec = format.createDefault("EVENT");
    rec.gameChar = Kaisa.CHAR_TAKUYA;
    rec.pendingEvent = 6;
    rec.stepSync.gateEpoch = 7;
    var saved = new SavedGame(format, 0, rec);
    var gm = new GameManager(data, db, saved);
    gm.audioMgr.muted = true;
    var root = new ContainerBuilder();
    gm.attachScreenManager(new ScreenManager(gm, root));
    var battle = new Battle(gm, gm.logicMgr, root);
    battle.playerLevel = 1;
    gm.logicMgr.loadedApp = battle;
    gm.logicMgr.currentScreen = Kaisa.SCREEN_APP;
    battle.escapeBattle();
    return saved.savedEvent() == 0
        && saved.record.stepSync.gateEpoch == 8
        && !gm.logicMgr.isEventPending;
}

(:test)
function watchStepsDuringEventBattleDoNotReopenEventPrompt(logger as Test.Logger) as Boolean {
    var data = new GameData();
    data.load();
    var db = new Database(data);
    db.load();
    var format = new SaveFormat(data);
    var rec = format.createDefault("EVENT");
    rec.gameChar = Kaisa.CHAR_TAKUYA;
    rec.pendingEvent = 3;
    rec.currentDistance = 500;
    var gm = new GameManager(data, db, new SavedGame(format, 0, rec));
    gm.audioMgr.muted = true;
    var screenMgr = new ScreenManager(gm, new ContainerBuilder());
    gm.attachScreenManager(screenMgr);
    var sync = new JourneyStepSync();
    var reading = new StepObservation();
    reading.day = 1700000000;
    reading.steps = 100;
    sync.reconcile(gm, reading, true);

    gm.checkPendingEvents();
    if (!gm.logicMgr.isEventPending) { return false; }
    gm.logicMgr.inputA();
    if (!(gm.logicMgr.loadedApp instanceof Battle)
            || gm.logicMgr.isEventPending) { return false; }

    reading.steps = 101;
    sync.reconcile(gm, reading, true);
    gm.runner.advance(20000.0d);
    screenMgr.updateQueue();
    return gm.logicMgr.loadedApp instanceof Battle
        && !gm.logicMgr.isEventPending
        && gm.saved.savedEvent() == 3
        && gm.saved.currentDistance() == 500;
}

(:test)
function watchStepReachingNewEventStillOpensPrompt(logger as Test.Logger) as Boolean {
    var data = new GameData();
    data.load();
    var db = new Database(data);
    db.load();
    var format = new SaveFormat(data);
    var rec = format.createDefault("EVENT");
    rec.gameChar = Kaisa.CHAR_TAKUYA;
    rec.currentDistance = 500;
    rec.stepsToNextEvent = 1;
    var gm = new GameManager(data, db, new SavedGame(format, 0, rec));
    gm.audioMgr.muted = true;
    var screenMgr = new ScreenManager(gm, new ContainerBuilder());
    gm.attachScreenManager(screenMgr);
    var sync = new JourneyStepSync();
    var reading = new StepObservation();
    reading.day = 1700000000;
    reading.steps = 100;
    sync.reconcile(gm, reading, true);

    gm.logicMgr.loadedApp = new Status(gm, gm.logicMgr, screenMgr.screenDisplay);
    gm.logicMgr.currentScreen = Kaisa.SCREEN_APP;
    reading.steps = 101;
    sync.reconcile(gm, reading, true);
    return gm.logicMgr.loadedApp == null
        && gm.logicMgr.isEventPending
        && gm.saved.savedEvent() == gm.logicMgr.SAVE_EVENT_RANDOM_WAITING
        && gm.saved.currentDistance() == 499;
}
