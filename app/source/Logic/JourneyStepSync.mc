import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

// Turns an absolute, durable watch source total into exactly-once game
// credit. This object persists for the life of a foreground view so a failed
// save can be retried without applying the same RAM delta twice.
class JourneyStepSync {
    const SAVE_AFTER_STEPS = 25l;
    const SAVE_AFTER_MS = 30000l;

    var _ledger as StepLedger = new StepLedger();
    var _blocked as Boolean = false;
    var _unflushed as Long = 0l;
    var _lastCommit as Number = 0;

    function isBlocked() as Boolean { return _blocked; }

    function beginGame(record as SaveRecord, reading as StepObservation) as Void {
        _blocked = false;
        _unflushed = 0l;
        _lastCommit = System.getTimer();
        var old = record.stepSync.gameGeneration;
        var sync = new StepState();
        sync.gameGeneration = Time.now().value().toLong() * 1000000l
                            + (System.getTimer() % 1000000).toLong();
        if (sync.gameGeneration <= old) { sync.gameGeneration = old + 1l; }
        var baseline = new StepObservation();
        baseline.day = reading.day;
        baseline.steps = reading.steps;
        baseline.timestamp = reading.timestamp;
        if (reading.day != null) {
            // Earlier history can arrive later. It predates this game's
            // baseline and must never become fresh journey credit.
            sync.archivedThrough = (reading.day as Number) - 1;
        }
        _ledger.observe(sync, baseline);
        if (reading.day != null && reading.steps != null) {
            sync.cursorInitialized = true;
            sync.creditedSourceTotal = sync.sourceTotal;
        }
        record.stepSync = sync;
    }

    // When background sync is off, advance the watch cursor at the first
    // foreground reading without awarding steps taken while the app was shut.
    // Commit that cursor now so turning the setting back on cannot import them.
    function reconcileResume(gm as GameManager, reading as StepObservation,
                             backgroundEnabled as Boolean) as Number {
        if (backgroundEnabled) { return reconcile(gm, reading, true); }
        reconcile(gm, reading, false);
        flush(gm.saved);
        return 0;
    }

    // Returns game travel steps, not all credited watch steps.
    function reconcile(gm as GameManager, reading as StepObservation,
                       fromResume as Boolean) as Number {
        var saved = gm.saved;
        if (_blocked) {
            if (!saved.commit()) { return 0; }
            _blocked = false;
            _unflushed = 0l;
            _lastCommit = System.getTimer();
            gm.checkPendingEvents();
        }
        var sync = saved.record.stepSync;
        if (saved.playerChar() == Kaisa.CHAR_NONE) { return 0; }
        if (!sync.cursorInitialized) {
            if (reading.day == null || reading.steps == null) { return 0; }
            var fresh = new StepState();
            fresh.gameGeneration = sync.gameGeneration;
            fresh.gateEpoch = sync.gateEpoch;
            fresh.notifiedGateEpoch = sync.notifiedGateEpoch;
            var baseline = new StepObservation();
            baseline.day = reading.day;
            baseline.steps = reading.steps;
            baseline.timestamp = reading.timestamp;
            fresh.archivedThrough = (reading.day as Number) - 1;
            _ledger.observe(fresh, baseline);
            fresh.creditedSourceTotal = fresh.sourceTotal;
            fresh.cursorInitialized = true;
            saved.record.stepSync = fresh;
            saved.touch();
            if (!saved.commit()) { _blocked = true; }
            return 0;
        }
        var changed = _ledger.observe(sync, reading);

        var delta = sync.sourceTotal - sync.creditedSourceTotal;
        if (delta <= 0l) {
            if (changed) { saved.touch(); }
            maybeCommit(saved, false);
            return 0;
        }
        // Background sync is off: checkpoint closed-period steps without
        // awarding them. Visible samples use the crediting branch below.
        if (!fromResume) {
            sync.creditedSourceTotal = sync.sourceTotal;
            saved.touch();
            _unflushed += delta;
            maybeCommit(saved, false);
            return 0;
        }
        var hadEvent = saved.savedEvent() != 0;
        var travel = applyDelta(gm, delta, fromResume);
        sync.watchStepsCredited += delta;
        sync.creditedSourceTotal = sync.sourceTotal;
        saved.touch();
        _unflushed += delta;
        var eventPending = saved.savedEvent() != 0;
        if (!maybeCommit(saved, eventPending)) { return travel; }
        // Steps credited while an encounter is already in progress are
        // statistics only; they must not close its Battle app and re-prompt.
        if (eventPending && !hadEvent) {
            if (fromResume && gm.logicMgr.isAppLoaded()) {
                gm.logicMgr.closeLoadedApp(Kaisa.SCREEN_CHARACTER);
            }
            gm.checkPendingEvents();
        }
        return travel;
    }

    // Kept separate from storage and UI so the gate accounting can be tested
    // with a synthetic source delta.
    function applyDelta(gm as GameManager, delta as Long,
                        fromResume as Boolean) as Number {
        var saved = gm.saved;
        var travel = 0;
        var canTravel = saved.savedEvent() == 0 && !gm.logicMgr.isEventPending
            && !gm.isCharacterDefeated()
            && (fromResume || !gm.logicMgr.shakeDisabled());
        if (canTravel) {
            var distance = gm.worldMgr.currentDistance();
            var toGate = distance == 1 ? 1 : distance - 1;
            if (distance > 1) {
                var eventSteps = saved.stepsToNextEvent();
                if (eventSteps < 1) { eventSteps = 1; }
                if (eventSteps < toGate) { toGate = eventSteps; }
            }
            var budget = delta < toGate.toLong() ? delta.toNumber() : toGate;
            for (var i = 0; i < budget; i += 1) {
                gm.takeModelStep();
                travel += 1;
                if (saved.savedEvent() != 0) { break; }
            }
        }
        gm.worldMgr.addStatisticSteps(delta - travel.toLong());
        return travel;
    }

    function flush(saved as SavedGame) as Boolean {
        if (!saved.commit()) { _blocked = true; return false; }
        _blocked = false;
        _unflushed = 0l;
        _lastCommit = System.getTimer();
        return true;
    }

    function maybeCommit(saved as SavedGame, urgent as Boolean) as Boolean {
        var now = System.getTimer();
        var elapsed = (now.toLong() - _lastCommit.toLong()) & 0xffffffffl;
        if (urgent || _unflushed >= SAVE_AFTER_STEPS
                || elapsed >= SAVE_AFTER_MS) {
            return flush(saved);
        }
        return true;
    }
}
