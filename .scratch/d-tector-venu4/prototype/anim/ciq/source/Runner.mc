import Toybox.Lang;
import Toybox.System;

// One coroutine, transformed into a resumable state machine.
//
// Every `yield return new WaitForSeconds(t)` in the original becomes a
// resume point: the step returns t and records where to continue. Every C#
// local that survives a yield becomes a field. Control flow stays as real
// Monkey C, so the compiler still type-checks it and the file still diffs
// against the original line for line.
class Routine {
    var pc as Number = 0;

    function initialize() {}

    // returns seconds to wait before the next step, or -1 when finished
    function step(rt as Runner) as Float {
        return -1.0;
    }
}

// Drives routines on a fixed 50 ms tick while keeping the ORIGINAL schedule.
//
// The tick is the display's, not the animation's. Each tick advances a budget
// by 50 ms and runs every step whose scheduled time has arrived, so waits
// shorter than a tick still happen -- several in one frame -- and the total
// duration of an animation matches the original exactly instead of drifting.
class Runner {
    var stack as Array<Routine> = [];
    var nowMs as Float = 0.0;      // scheduled time of the step being run
    var nextMs as Float = 0.0;     // scheduled time of the next step
    var budgetMs as Float = 0.0;   // time the display has actually reached
    var tick as Number = 0;
    var steps as Number = 0;

    function initialize() {}

    function call(r as Routine) as Void {
        stack.add(r);
    }

    function isRunning() as Boolean {
        return stack.size() > 0;
    }

    function emit(ev as String) as Void {
        System.println("TRACE " + nowMs.format("%9.4f") + " " + ev +
            "  [tick " + tick + "]");
    }

    function advance(dtMs as Float) as Void {
        tick += 1;
        budgetMs += dtMs;
        while (stack.size() > 0 && nextMs <= budgetMs) {
            nowMs = nextMs;
            var top = stack[stack.size() - 1];
            var w = top.step(self);
            steps += 1;
            if (w < 0.0) {
                stack.remove(top);
            } else {
                nextMs += w * 1000.0;
            }
            if (steps > 20000) { return; }   // runaway guard
        }
    }
}
