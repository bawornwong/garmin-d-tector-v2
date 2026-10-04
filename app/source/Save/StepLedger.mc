import Toybox.ActivityMonitor;
import Toybox.Lang;
import Toybox.Time;

const STEP_RECENT_DAYS = 10;

// The watch reports steps per local day, not a lifetime counter. Keep the
// maxima for recent days so a repeated or corrected reading is idempotent.
(:background)
class StepState {

    var gameGeneration as Long = 0l;
    var gateEpoch as Number = 0;
    var notifiedGateEpoch as Number = -1;
    var cursorInitialized as Boolean = false;
    var historyGap as Boolean = false;
    var sourceTotal as Long = 0l;
    var creditedSourceTotal as Long = 0l;
    var watchStepsCredited as Long = 0l;
    var archivedTotal as Long = 0l;
    var archivedThrough as Number = 0;
    var lastInfoDay as Number = 0;
    var lastInfoSteps as Number = 0;
    var lastObservation as Number = 0;
    var quarantineThrough as Number = 0;
    var days as Array<Number> = [];
    var maxima as Array<Number> = [];
}

(:background)
class StepObservation {
    var day as Number? = null;
    var steps as Number? = null;
    var timestamp as Number = 0;
    var history as Array<Array<Number>> = [];
}

(:background)
class GarminStepReader {
    function read(includeHistory as Boolean) as StepObservation {
        var out = new StepObservation();
        var before = Time.today().value();
        var info = ActivityMonitor.getInfo();
        var after = Time.today().value();
        out.timestamp = Time.now().value();
        if (before == after && info != null && info.steps != null) {
            out.day = before;
            out.steps = info.steps;
        }
        if (includeHistory) {
            try {
                var history = ActivityMonitor.getHistory();
                for (var i = 0; i < history.size(); i += 1) {
                    var h = history[i];
                    if (h.startOfDay != null && h.steps != null && h.steps >= 0) {
                        out.history.add([h.startOfDay.value(), h.steps]);
                    }
                }
            } catch (e) {
                // A missing history response must not discard the live steps
                // that this wake can use to detect a story event.
            }
        }
        return out;
    }
}

(:background)
class StepLedger {
    // Mutates the caller's StepState. The caller persists it before crediting
    // the game or displaying an event.
    function observe(state as StepState, reading as StepObservation) as Boolean {
        var oldTotal = state.sourceTotal;
        var oldDay = state.lastInfoDay;
        var oldArchived = state.archivedTotal;
        var oldCount = state.days.size();
        var oldGap = state.historyGap;
        var oldLastSteps = state.lastInfoSteps;
        var oldQuarantine = state.quarantineThrough;
        var oldDays = [] as Array<Number>;
        var oldMaxima = [] as Array<Number>;
        for (var i = 0; i < oldCount; i += 1) {
            oldDays.add(state.days[i]);
            oldMaxima.add(state.maxima[i]);
        }
        var ambiguous = false;
        if (reading.day != null && reading.steps != null && reading.steps >= 0) {
            var day = reading.day as Number;
            if (oldDay != 0 && day != oldDay) {
                var dayDelta = day - oldDay;
                if (dayDelta <= 0 || dayDelta % 86400 != 0) {
                    // A time-zone or clock shift can relabel a single
                    // counter as two days. Prefer an explicit gap.
                    state.historyGap = true;
                    if (day > state.quarantineThrough) { state.quarantineThrough = day; }
                    ambiguous = true;
                } else if (dayDelta > 86400) {
                    // Whole missed days are different: keep any verified
                    // history and live totals while recording the gap.
                    state.historyGap = true;
                }
            }
            state.lastInfoDay = day;
            state.lastInfoSteps = reading.steps as Number;
            if (state.quarantineThrough != 0 && day <= state.quarantineThrough
                    && indexOf(state.days, day) < 0) { ambiguous = true; }
        }

        for (var i = 0; i < reading.history.size(); i += 1) {
            var pair = reading.history[i];
            if (pair.size() < 2) { continue; }
            var hday = pair[0];
            var hsteps = pair[1];
            if (hday <= 0 || hsteps < 0) { continue; }
            if (state.quarantineThrough != 0 && hday <= state.quarantineThrough
                    && indexOf(state.days, hday) < 0) { continue; }
            mergeDay(state, hday, hsteps);
        }
        if (!ambiguous && reading.day != null && reading.steps != null
                && reading.steps >= 0) {
            var liveDay = reading.day as Number;
            mergeDay(state, liveDay, reading.steps as Number);
        }
        archiveOldDays(state);
        for (var i = 1; i < state.days.size(); i += 1) {
            if (state.days[i] - state.days[i - 1] > 86400) {
                state.historyGap = true;
            }
        }
        var total = state.archivedTotal;
        for (var i = 0; i < state.maxima.size(); i += 1) {
            total += state.maxima[i].toLong();
        }
        if (total > state.sourceTotal) { state.sourceTotal = total; }
        var changed = state.sourceTotal != oldTotal || state.lastInfoDay != oldDay
            || state.archivedTotal != oldArchived || state.days.size() != oldCount
            || state.historyGap != oldGap || state.lastInfoSteps != oldLastSteps
            || state.quarantineThrough != oldQuarantine;
        if (!changed) {
            for (var i = 0; i < oldCount; i += 1) {
                if (state.days[i] != oldDays[i] || state.maxima[i] != oldMaxima[i]) {
                    changed = true;
                    break;
                }
            }
        }
        if (changed && reading.timestamp > 0) { state.lastObservation = reading.timestamp; }
        return changed;
    }

    function mergeDay(state as StepState, day as Number, steps as Number) as Void {
        if (day <= state.archivedThrough) { return; }
        var at = indexOf(state.days, day);
        if (at >= 0) {
            if (steps > state.maxima[at]) { state.maxima[at] = steps; }
            return;
        }
        var pos = 0;
        while (pos < state.days.size() && state.days[pos] < day) { pos += 1; }
        state.days.add(day);
        state.maxima.add(steps);
        for (var i = state.days.size() - 1; i > pos; i -= 1) {
            state.days[i] = state.days[i - 1];
            state.maxima[i] = state.maxima[i - 1];
        }
        state.days[pos] = day;
        state.maxima[pos] = steps;
        if (pos > 0 && day - state.days[pos - 1] > 86400) { state.historyGap = true; }
    }

    function archiveOldDays(state as StepState) as Void {
        while (state.days.size() > STEP_RECENT_DAYS) {
            // Archive the oldest day even when Garmin still returns it in
            // history. The header has exactly ten day slots, and late
            // corrections to an archived day cannot be verified safely.
            state.archivedTotal += state.maxima[0].toLong();
            state.archivedThrough = state.days[0];
            var nextDays = [] as Array<Number>;
            var nextMaxima = [] as Array<Number>;
            for (var i = 1; i < state.days.size(); i += 1) {
                nextDays.add(state.days[i]);
                nextMaxima.add(state.maxima[i]);
            }
            state.days = nextDays;
            state.maxima = nextMaxima;
        }
    }

    function indexOf(days as Array<Number>, day as Number) as Number {
        for (var i = 0; i < days.size(); i += 1) {
            if (days[i] == day) { return i; }
        }
        return -1;
    }
}
