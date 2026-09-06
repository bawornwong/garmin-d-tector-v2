import Toybox.Lang;
import Toybox.System;

// The coroutine runtime (ADR 4 + ADR 5). Every `IEnumerator` in the source
// becomes a Routine; every `StartCoroutine` becomes a Fiber; the Runner
// schedules them.
//
// ADR 4: a coroutine is a class with a `pc`. Each `yield return new
// WaitForSeconds(t)` is a resume point that returns t and records where to
// continue; each C# local that survives a yield becomes a field. Control flow
// stays real Monkey C, so the compiler type-checks the translation and the
// file still diffs against the original.
//
// ADR 5: the runner keeps the ORIGINAL schedule in floating-point
// milliseconds, not the frame cadence. Each tick advances a budget by 50 ms
// and runs every step whose scheduled time has arrived -- so the 36 waits
// shorter than one tick still happen, several inside one frame, and an
// animation's total duration matches the original exactly instead of
// drifting. Up to 11 events were observed landing in a single frame.
//
// What the ticket 07 prototype lacked and this adds is concurrency: the
// original runs animations, the app's own auto-repeat and per-app loops at
// the same time, so fibers are independent and each carries its own call
// stack and its own next-step time.
class Routine {
    // Return values of step(), in seconds. Anything >= 0 is a wait.
    static const DONE = -1.0;         // the coroutine returned
    static const NEXT_FRAME = -2.0;   // `yield return null`: resume next tick

    var pc as Number = 0;

    function initialize() {
    }

    // Runs one step and returns how long to wait before the next one.
    function step(rt as Fiber) as Float {
        return DONE;
    }
}

// One `StartCoroutine`: a call stack of Routines and the time its next step
// is due. A routine that yields another routine pushes onto this stack and
// resumes when the child returns -- Unity's `yield return SubCoroutine()`.
class Fiber {
    var stack as Array<Routine> = [];
    var nextMs as Float = 0.0;
    var runner as Runner;

    function initialize(r as Routine, runnerIn as Runner, startMs as Float) {
        runner = runnerIn;
        nextMs = startMs;
        stack.add(r);
    }

    // `yield return SubCoroutine()`: the caller returns 0.0 after this, and
    // the child runs at the same scheduled time.
    function call(r as Routine) as Void {
        stack.add(r);
    }

    function isRunning() as Boolean {
        return stack.size() > 0;
    }

    // StopCoroutine: drops the whole stack, so the parent does not resume.
    function stop() as Void {
        stack = [];
    }

    // The trace hook the golden diffs read (ADR 12). Debug-only: the release
    // build has no reason to carry it, and a trace line inside a motion loop
    // would cost more than the step it describes.
    (:debug)
    function emit(ev as String) as Void {
        runner.emit(ev);
    }

    (:release)
    function emit(ev as String) as Void {
    }
}

class Runner {
    // A step that neither waits nor finishes is a bug in a converted routine
    // (usually a `for` head that forgets to advance); without this the frame
    // would hang until the watchdog killed the app.
    const RUNAWAY_STEPS = 20000;

    var fibers as Array<Fiber> = [];
    var nowMs as Float = 0.0;       // scheduled time of the step being run
    var budgetMs as Float = 0.0;    // time the display has actually reached
    var tick as Number = 0;
    var steps as Number = 0;
    var _inStep as Boolean = false;   // true while a routine's step is running

    function initialize() {
    }

    // StartCoroutine. Unity runs the new coroutine's body up to its first
    // yield inside StartCoroutine itself, so a fiber started from INSIDE a
    // step begins at that step's scheduled time -- not at the frame budget,
    // which is up to a whole tick later and made every event of a background
    // animation land 50 ms late against the reference trace. A fiber started
    // between frames (an app reacting to a press) has no scheduled time to
    // inherit and begins at the budget.
    function start(r as Routine) as Fiber {
        // The original's StartCoroutine and StopCoroutine are traced events in
        // their own right -- an animation that starts a background loop is
        // doing something observable -- so the port records them where the
        // fiber is actually created and dropped.
        Kaisa.Trace.event("startCoroutine");
        var f = new Fiber(r, self, _inStep ? nowMs : budgetMs);
        fibers.add(f);
        return f;
    }

    function stop(f as Fiber?) as Void {
        if (f == null) { return; }
        Kaisa.Trace.event("stopCoroutine");
        f.stop();
        fibers.remove(f);
    }

    function stopAll() as Void {
        fibers = [];
    }

    function isRunning() as Boolean {
        return fibers.size() > 0;
    }

    (:debug)
    function emit(ev as String) as Void {
        Kaisa.Trace.event(ev);
    }

    (:release)
    function emit(ev as String) as Void {
    }

    // An event's timestamp is the step's SCHEDULED time, not the frame's:
    // that is the clock the C# reference prints, and the whole point of ADR
    // 5's scheduler is that the two agree.
    (:debug)
    function setTraceClock(t as Float) as Void {
        Kaisa.Trace.nowMs = t;
    }

    (:release)
    function setTraceClock(t as Float) as Void {
    }

    // Advances the whole runtime by one display frame.
    function advance(dtMs as Float) as Void {
        tick += 1;
        budgetMs += dtMs;

        while (true) {
            // The due fiber with the earliest scheduled step, so concurrent
            // animations interleave in the order the original would have run
            // them rather than in fiber-creation order.
            var due = null;
            for (var i = 0; i < fibers.size(); i += 1) {
                var f = fibers[i];
                if (f.isRunning() && f.nextMs <= budgetMs
                        && (due == null || f.nextMs < due.nextMs)) {
                    due = f;
                }
            }
            if (due == null) { return; }

            nowMs = due.nextMs;
            setTraceClock(nowMs);
            var top = due.stack[due.stack.size() - 1];
            _inStep = true;
            var w = top.step(due);
            _inStep = false;
            steps += 1;

            if (w == Routine.DONE) {
                due.stack.remove(top);
                if (!due.isRunning()) { fibers.remove(due); }
            } else if (w == Routine.NEXT_FRAME) {
                // `yield return null` waits for the next frame, not for a
                // duration: the four sites that use it are synchronising with
                // the display, not timing anything.
                due.nextMs = budgetMs + dtMs;
            } else {
                due.nextMs += w * 1000.0;
            }

            if (steps > RUNAWAY_STEPS) {
                System.println("Runner: runaway, " + steps + " steps in one frame");
                return;
            }
        }
    }
}
