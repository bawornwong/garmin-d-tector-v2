import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.Test;

(:test)
function stepMultiplierScalesShakeWalkingAndResume(logger as Test.Logger) as Boolean {
    var previous = Storage.getValue(StepMultiplierSetting.KEY);
    var passed = true;
    for (var multiplier = 1; multiplier <= 5; multiplier += 1) {
        StepMultiplierSetting.setValue(multiplier);
        passed = checkMultipliedJourney(multiplier) && passed;
    }
    if (previous == null) { Storage.deleteValue(StepMultiplierSetting.KEY); }
    else { Storage.setValue(StepMultiplierSetting.KEY, previous); }
    return passed;
}

function checkMultipliedJourney(multiplier as Number) as Boolean {
    var data = new GameData();
    data.load();
    var db = new Database(data);
    db.load();
    var format = new SaveFormat(data);
    var rec = format.createDefault("MULT");
    rec.gameChar = Kaisa.CHAR_TAKUYA;
    rec.currentDistance = 500;
    rec.stepsToNextEvent = 300;
    var saved = new SavedGame(format, 0, rec);
    var gm = new GameManager(data, db, saved);
    gm.attachScreenManager(new ScreenManager(gm, new ContainerBuilder()));
    var sync = new JourneyStepSync();
    var sample = new StepObservation();
    sample.day = 1700000000;
    sample.steps = 100;
    sync.beginGame(rec, sample);
    sample.steps = 110;
    if (sync.reconcile(gm, sample, true) != 10 * multiplier) { return false; }
    gm.takeAStep();
    sample.steps = 115;
    if (sync.reconcileResume(gm, sample, true) != 5 * multiplier
            || sync.reconcileResume(gm, sample, true) != 0
            || saved.steps() != 16 * multiplier
            || saved.currentDistance() != 500 - 16 * multiplier
            || rec.stepSync.creditedSourceTotal != 115l
            || rec.stepSync.watchStepsCredited != 15l) { return false; }
    // A setting change affects only new physical deltas, including statistics
    // while travel is blocked by an event.
    StepMultiplierSetting.setValue(5);
    if (sync.reconcile(gm, sample, true) != 0) { return false; }
    rec.pendingEvent = 3;
    sample.steps = 117;
    if (sync.reconcile(gm, sample, true) != 0
            || saved.steps() != 16 * multiplier + 10
            || saved.currentDistance() != 500 - 16 * multiplier) { return false; }
    rec.pendingEvent = 0;
    rec.currentDistance = 10;
    rec.stepsToNextEvent = 300;
    var service = new StepBackground();
    var header = new StepHeader();
    header.fromRecord(rec);
    header.sync.sourceTotal = header.sync.creditedSourceTotal + 1l;
    if (service.shouldNotify(header)) { return false; }
    header.sync.sourceTotal += 1l;
    if (!service.shouldNotify(header)) { return false; }
    // Two physical steps at X5 stop at the boss and still count all ten.
    var before = saved.steps();
    if (sync.applyDelta(gm, 2l, false) != 9 || saved.currentDistance() != 1
            || saved.savedEvent() != 2 || saved.steps() != before + 10) { return false; }
    rec.pendingEvent = 0;
    rec.currentDistance = 500;
    rec.stepsToNextEvent = 3;
    // One shake can reach an encounter; its excess never reduces travel.
    gm.takeAStep();
    if (saved.currentDistance() != 497 || saved.savedEvent() != 1
            || saved.steps() != before + 15) { return false; }
    rec.steps = 2147483645;
    sync.applyDelta(gm, 2l, false);
    return saved.steps() == 2147483647;
}
