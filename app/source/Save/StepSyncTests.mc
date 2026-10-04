import Toybox.Lang;
import Toybox.Test;

(:test)
function stepLedgerDuplicates(logger as Test.Logger) as Boolean {
    var state = new StepState();
    var ledger = new StepLedger();
    var sample = new StepObservation();
    sample.day = 1700000000;
    sample.steps = 100;
    ledger.observe(state, sample);
    ledger.observe(state, sample);
    sample.steps = 90;
    ledger.observe(state, sample);
    if (state.sourceTotal != 100l) { return false; }
    sample.steps = 120;
    ledger.observe(state, sample);
    return state.sourceTotal == 120l && state.days.size() == 1;
}

(:test)
function stepLedgerMidnightAndArchive(logger as Test.Logger) as Boolean {
    var state = new StepState();
    var ledger = new StepLedger();
    var day = 1700000000;
    var first = new StepObservation();
    first.day = day;
    first.steps = 100;
    ledger.observe(state, first);
    var next = new StepObservation();
    next.day = day + 86400;
    next.steps = 20;
    next.history.add([day, 135]);
    ledger.observe(state, next);
    if (state.sourceTotal != 155l) { return false; }
    for (var i = 2; i < 12; i += 1) {
        var s = new StepObservation();
        s.day = day + 86400 * i;
        s.steps = 100;
        ledger.observe(state, s);
    }
    if (state.days.size() != 10 || state.archivedThrough != day + 86400
            || state.sourceTotal != 1155l) { return false; }
    // A long history response must also fit the ten-day persisted header.
    var history = new StepObservation();
    history.day = day + 86400 * 12;
    history.steps = 25;
    for (var j = 0; j < 12; j += 1) {
        history.history.add([day + 86400 * j, j == 0 ? 100 : (j == 1 ? 135 : 100)]);
    }
    ledger.observe(state, history);
    return state.days.size() == 10 && state.archivedThrough == day + 86400 * 2
        && state.sourceTotal == 1180l;
}

(:test)
function stepHeaderRoundTrip(logger as Test.Logger) as Boolean {
    var rec = new SaveRecord();
    rec.gameChar = Kaisa.CHAR_TAKUYA;
    rec.currentDistance = 222;
    rec.stepsToNextEvent = 100;
    rec.stepSync.sourceTotal = 4294967305l;
    rec.stepSync.creditedSourceTotal = 4294967200l;
    rec.stepSync.days.add(1700000000);
    rec.stepSync.maxima.add(123);
    var h = new StepHeader();
    h.fromRecord(rec);
    var bytes = h.encode();
    var again = new StepHeader();
    if (bytes.size() != STEP_HEADER_SIZE || !again.decode(bytes)) { return false; }
    var originalTotal = rec.stepSync.sourceTotal;
    bytes.add(42);
    h.sync.sourceTotal += 1l;
    var patched = h.replacePrefix(bytes);
    var patchedHeader = new StepHeader();
    return patched.size() == STEP_HEADER_SIZE + 1
        && patched[STEP_HEADER_SIZE] == 42 && patchedHeader.decode(patched)
        && patchedHeader.sync.sourceTotal == originalTotal + 1l
        && again.sync.sourceTotal == originalTotal
        && again.sync.creditedSourceTotal == rec.stepSync.creditedSourceTotal
        && again.sync.days[0] == 1700000000 && again.distance == 222;
}

(:test)
function stepSaveV2Migration(logger as Test.Logger) as Boolean {
    var data = new GameData();
    data.load();
    var format = new SaveFormat(data);
    var old = format.createDefault("WALKER");
    old.steps = 432;
    var v3 = format.encode(old);
    var totals = data.worldTotals();
    var current = format.decode(v3, data.digimonCount(), totals[0], totals[1], totals[2]);
    if (current.wasV2 || current.steps != 432 || !current.name.equals("WALKER")) {
        return false;
    }
    var v2 = []b;
    v2.add(2);
    for (var i = STEP_HEADER_SIZE; i < v3.size(); i += 1) { v2.add(v3[i]); }
    var restored = format.decode(v2, data.digimonCount(), totals[0], totals[1], totals[2]);
    return restored.wasV2 && restored.version == 3
        && restored.name.equals("WALKER") && restored.steps == 432
        && !restored.stepSync.cursorInitialized;
}

(:test)
function stepGateOverflow(logger as Test.Logger) as Boolean {
    var data = new GameData();
    data.load();
    var db = new Database(data);
    db.load();
    var format = new SaveFormat(data);
    var rec = format.createDefault("WALKER");
    rec.gameChar = Kaisa.CHAR_TAKUYA;
    rec.currentDistance = 500;
    rec.stepsToNextEvent = 300;
    var saved = new SavedGame(format, 0, rec);
    var gm = new GameManager(data, db, saved);
    var traveled = (new JourneyStepSync()).applyDelta(gm, 360l, false);
    return traveled == 300 && saved.steps() == 360
        && saved.currentDistance() == 200 && saved.savedEvent() == 1;
}

(:test)
function visibleShakeAndWatchStepsAreAdditive(logger as Test.Logger) as Boolean {
    var data = new GameData();
    data.load();
    var db = new Database(data);
    db.load();
    var format = new SaveFormat(data);
    var rec = format.createDefault("WALKER");
    rec.gameChar = Kaisa.CHAR_TAKUYA;
    rec.currentDistance = 500;
    rec.stepsToNextEvent = 300;
    rec.stepSync.cursorInitialized = true;
    rec.stepSync.gameGeneration = 1l;
    rec.stepSync.days.add(1700000000);
    rec.stepSync.maxima.add(100);
    rec.stepSync.sourceTotal = 100l;
    rec.stepSync.creditedSourceTotal = 100l;
    var saved = new SavedGame(format, 0, rec);
    var gm = new GameManager(data, db, saved);
    gm.attachScreenManager(new ScreenManager(gm, new ContainerBuilder()));
    var sync = new JourneyStepSync();
    var visible = new StepObservation();
    visible.day = 1700000000;
    visible.steps = 110;
    if (sync.reconcile(gm, visible, true) != 10
            || saved.steps() != 10 || saved.currentDistance() != 490
            || rec.stepSync.creditedSourceTotal != 110l
            || rec.stepSync.watchStepsCredited != 10l) { return false; }
    gm.takeAStep();
    if (saved.steps() != 11 || saved.currentDistance() != 489
            || rec.stepSync.watchStepsCredited != 10l) { return false; }
    var closed = new StepObservation();
    closed.day = 1700000000;
    closed.steps = 115;
    return sync.reconcile(gm, closed, true) == 5
        && saved.steps() == 16 && saved.currentDistance() == 484
        && rec.stepSync.watchStepsCredited == 15l;
}

(:test)
function disabledBackgroundStepsDoNotCatchUpOnReopen(logger as Test.Logger) as Boolean {
    var data = new GameData();
    data.load();
    var db = new Database(data);
    db.load();
    var format = new SaveFormat(data);
    var rec = format.createDefault("WALKER");
    rec.gameChar = Kaisa.CHAR_TAKUYA;
    rec.currentDistance = 500;
    rec.stepsToNextEvent = 300;
    rec.stepSync.cursorInitialized = true;
    rec.stepSync.gameGeneration = 1l;
    rec.stepSync.days.add(1700000000);
    rec.stepSync.maxima.add(100);
    rec.stepSync.sourceTotal = 100l;
    rec.stepSync.creditedSourceTotal = 100l;
    var saved = new SavedGame(format, 0, rec);
    var gm = new GameManager(data, db, saved);
    var sync = new JourneyStepSync();
    var reading = new StepObservation();
    reading.day = 1700000000;
    reading.steps = 125;
    if (sync.reconcileResume(gm, reading, false) != 0
            || saved.steps() != 0 || saved.currentDistance() != 500
            || rec.stepSync.creditedSourceTotal != 125l) { return false; }
    reading.steps = 130;
    return sync.reconcileResume(gm, reading, true) == 5
        && saved.steps() == 5 && saved.currentDistance() == 495
        && rec.stepSync.watchStepsCredited == 5l;
}

(:test)
function stepsDuringActiveEventCannotOpenTheNextEvent(logger as Test.Logger) as Boolean {
    var data = new GameData();
    data.load();
    var db = new Database(data);
    db.load();
    var format = new SaveFormat(data);
    var rec = format.createDefault("WALKER");
    rec.gameChar = Kaisa.CHAR_TAKUYA;
    rec.currentDistance = 500;
    rec.stepsToNextEvent = 300;
    rec.pendingEvent = 3;
    var saved = new SavedGame(format, 0, rec);
    var gm = new GameManager(data, db, saved);
    var sync = new JourneyStepSync();
    if (sync.applyDelta(gm, 400l, false) != 0
            || saved.steps() != 400 || saved.currentDistance() != 500) { return false; }
    gm.logicMgr.finishEvent();
    if (sync.applyDelta(gm, 299l, false) != 299
            || saved.savedEvent() != 0 || saved.stepsToNextEvent() != 1) { return false; }
    return sync.applyDelta(gm, 1l, false) == 1
        && saved.savedEvent() == 1 && saved.steps() == 700;
}

(:test)
function stepTravelContinuesWhileStatusIsOpen(logger as Test.Logger) as Boolean {
    var data = new GameData();
    data.load();
    var db = new Database(data);
    db.load();
    var format = new SaveFormat(data);
    var rec = format.createDefault("WALKER");
    rec.gameChar = Kaisa.CHAR_TAKUYA;
    rec.currentDistance = 500;
    rec.stepsToNextEvent = 300;
    var saved = new SavedGame(format, 0, rec);
    var gm = new GameManager(data, db, saved);
    gm.logicMgr.loadedApp = new Status(gm, gm.logicMgr, new ContainerBuilder());
    gm.logicMgr.currentScreen = Kaisa.SCREEN_APP;
    var traveled = (new JourneyStepSync()).applyDelta(gm, 10l, false);
    return traveled == 10 && saved.currentDistance() == 490
        && saved.steps() == 10 && saved.stepsToNextEvent() == 290;
}

(:test)
function stepLedgerNullAndTimeZone(logger as Test.Logger) as Boolean {
    var state = new StepState();
    var ledger = new StepLedger();
    var sample = new StepObservation();
    sample.day = 1700000000;
    sample.steps = 100;
    ledger.observe(state, sample);
    sample.steps = null;
    ledger.observe(state, sample);
    if (state.sourceTotal != 100l) { return false; }
    sample.day = 1700000000 + 3600;
    sample.steps = 105;
    ledger.observe(state, sample);
    sample.steps = 130;
    ledger.observe(state, sample);
    if (state.sourceTotal != 100l || !state.historyGap) { return false; }
    sample.day = 1700000000 + 3600 + 86400;
    sample.steps = 20;
    ledger.observe(state, sample);
    return state.sourceTotal == 120l;
}

(:test)
function stepLedgerMissingDays(logger as Test.Logger) as Boolean {
    var state = new StepState();
    var ledger = new StepLedger();
    var day = 1700000000;
    var first = new StepObservation();
    first.day = day;
    first.steps = 100;
    ledger.observe(state, first);
    var later = new StepObservation();
    later.day = day + 86400 * 3;
    later.steps = 20;
    later.history.add([day + 86400 * 2, 50]);
    ledger.observe(state, later);
    return state.historyGap && state.sourceTotal == 170l
        && state.days.size() == 3;
}

(:test)
function stepGameBaselineAndCap(logger as Test.Logger) as Boolean {
    var rec = new SaveRecord();
    var sample = new StepObservation();
    sample.day = 1700000000;
    sample.steps = 2000;
    sample.history.add([1700000000 - 86400, 9000]);
    (new JourneyStepSync()).beginGame(rec, sample);
    if (!rec.stepSync.cursorInitialized || rec.stepSync.sourceTotal != 2000l
            || rec.stepSync.creditedSourceTotal != 2000l
            || rec.stepSync.watchStepsCredited != 0l) { return false; }
    var lateHistory = new StepObservation();
    lateHistory.day = sample.day;
    lateHistory.steps = 2000;
    lateHistory.history.add([1700000000 - 86400, 9000]);
    (new StepLedger()).observe(rec.stepSync, lateHistory);
    if (rec.stepSync.sourceTotal != 2000l) { return false; }
    var firstGeneration = rec.stepSync.gameGeneration;
    var unavailable = new StepObservation();
    (new JourneyStepSync()).beginGame(rec, unavailable);
    if (rec.stepSync.cursorInitialized || rec.stepSync.sourceTotal != 0l) { return false; }
    sample.steps = 2600;
    (new JourneyStepSync()).beginGame(rec, sample);
    if (rec.stepSync.gameGeneration == firstGeneration
            || rec.stepSync.creditedSourceTotal != 2600l
            || rec.stepSync.watchStepsCredited != 0l) { return false; }
    var data = new GameData();
    data.load();
    var saved = new SavedGame(new SaveFormat(data), 0, rec);
    rec.steps = 2147483645;
    (new WorldManager(saved, data)).addStatisticSteps(10l);
    return saved.steps() == 2147483647;
}

(:test)
function stepNotificationGateAndHandoff(logger as Test.Logger) as Boolean {
    var h = new StepHeader();
    h.gameChar = Kaisa.CHAR_TAKUYA;
    h.distance = 500;
    h.stepsToEvent = 300;
    h.sync.cursorInitialized = true;
    h.sync.sourceTotal = 360l;
    h.sync.creditedSourceTotal = 0l;
    var service = new StepBackground();
    if (!service.shouldNotify(h)) { return false; }
    h.sync.notifiedGateEpoch = h.sync.gateEpoch;
    if (service.shouldNotify(h)) { return false; }
    var fg = new StepAccess();
    var bg = new StepAccess();
    if (!fg.tryForeground()) { return false; }
    if (bg.beginBackground()) { fg.releaseForeground(); bg.endBackground(); return false; }
    fg.releaseForeground();
    if (!bg.beginBackground()) { return false; }
    var waited = !fg.tryForeground();
    bg.endBackground();
    var acquired = fg.tryForeground();
    fg.releaseForeground();
    return waited && acquired;
}

(:test)
function stepWakeDetectsReachedEvent(logger as Test.Logger) as Boolean {
    var h = new StepHeader();
    h.gameChar = Kaisa.CHAR_TAKUYA;
    h.distance = 500;
    h.stepsToEvent = 300;
    h.sync.cursorInitialized = true;
    var ledger = new StepLedger();
    var service = new StepBackground();
    var reading = new StepObservation();
    reading.day = 1700000000;
    reading.steps = 100;
    ledger.observe(h.sync, reading);
    h.sync.creditedSourceTotal = h.sync.sourceTotal;
    reading.steps = 399;
    ledger.observe(h.sync, reading);
    if (service.shouldNotify(h)) { return false; }
    reading.steps = 400;
    ledger.observe(h.sync, reading);
    if (!service.shouldNotify(h)) { return false; }
    h.sync.notifiedGateEpoch = h.sync.gateEpoch;
    ledger.observe(h.sync, reading);
    if (service.shouldNotify(h)) { return false; }
    h.sync.gateEpoch += 1;
    h.pendingEvent = 1;
    return service.shouldNotify(h);
}
