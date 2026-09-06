// Unity's coroutine semantics, reimplemented so the original Animations.cs can
// be executed outside Unity and traced.
//
// Rules being reproduced:
//   - `yield return new WaitForSeconds(t)` advances that coroutine's own clock
//     by t and lets anything scheduled earlier run first
//   - `yield return OtherCoroutine()` runs the child to completion before the
//     parent resumes, on the same clock
//   - `yield return null` waits one frame; the harness uses Unity's nominal
//     60 Hz frame, which is only observable where a coroutine yields null and
//     nothing else
//   - StartCoroutine runs a SECOND coroutine in parallel from now on, and
//     StopCoroutine ends it -- the case PaySpiritPower and AWardSpiritPower
//     use for their background animation
//
// Parallel fibers matter to the diff: the port's runner interleaves them by
// scheduled time (ADR 5), so the reference has to interleave them the same way
// or the two traces cannot be compared at all.
using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace Kaisa.Digivice {
    public static class Driver {
        const double FRAME = 1.0 / 60.0;

        class Fiber {
            public Stack<IEnumerator> stack = new Stack<IEnumerator>();
            public double next;
            public bool stopped;
        }

        static List<Fiber> fibers = new List<Fiber>();
        static Dictionary<Coroutine, Fiber> handles = new Dictionary<Coroutine, Fiber>();

        public static Coroutine Spawn(IEnumerator r) {
            var f = new Fiber();
            f.stack.Push(r);
            f.next = Trace.Log.Now;
            fibers.Add(f);
            var c = new Coroutine();
            c.routine = r;
            handles[c] = f;
            return c;
        }

        public static void Kill(Coroutine c) {
            Fiber f;
            if (c != null && handles.TryGetValue(c, out f)) { f.stopped = true; }
        }

        public static void Run(IEnumerator root) {
            Trace.Log.Now = 0.0;
            Trace.Log.Events.Clear();
            fibers.Clear();
            handles.Clear();

            var main = new Fiber();
            main.stack.Push(root);
            main.next = 0.0;
            fibers.Add(main);

            int guard = 0;
            while (true) {
                if (++guard > 2000000) { throw new Exception("runaway coroutine"); }

                fibers.RemoveAll(f => f.stopped || f.stack.Count == 0);
                // The main fiber finishing ends the animation, exactly as it
                // does in the game: ScreenManager's queue moves on and the
                // parent's StopCoroutine has already run.
                if (!fibers.Contains(main) || fibers.Count == 0) { break; }

                Fiber due = null;
                foreach (var f in fibers) {
                    if (due == null || f.next < due.next) { due = f; }
                }

                Trace.Log.Now = due.next;
                var top = due.stack.Peek();
                if (!top.MoveNext()) { due.stack.Pop(); continue; }

                var y = top.Current;
                if (y is WaitForSeconds) {
                    due.next += ((WaitForSeconds)y).seconds;
                } else if (y is IEnumerator) {
                    due.stack.Push((IEnumerator)y);
                } else if (y == null) {
                    due.next += FRAME;
                }
            }
        }
    }
}
