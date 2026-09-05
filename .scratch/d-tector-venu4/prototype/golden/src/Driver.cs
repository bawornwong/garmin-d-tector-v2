// Unity's coroutine semantics, reimplemented: pump the IEnumerator, and when
// it yields a WaitForSeconds, advance the clock by that many seconds. Nested
// IEnumerators run to completion before the parent resumes, exactly as
// `yield return OtherCoroutine()` does in Unity.
using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace Kaisa.Digivice {
    public static class Driver {
        static List<Coroutine> parallel = new List<Coroutine>();

        public static Coroutine Spawn(IEnumerator r) {
            var c = new Coroutine();
            c.routine = r;
            parallel.Add(c);
            return c;
        }

        public static void Run(IEnumerator root) {
            Trace.Log.Now = 0.0;
            Trace.Log.Events.Clear();
            parallel.Clear();
            Pump(root);
        }

        static void Pump(IEnumerator r) {
            var stack = new Stack<IEnumerator>();
            stack.Push(r);
            int guard = 0;
            while (stack.Count > 0) {
                if (++guard > 2000000) { throw new Exception("runaway coroutine"); }
                var top = stack.Peek();
                if (!top.MoveNext()) { stack.Pop(); continue; }
                var y = top.Current;
                if (y is WaitForSeconds) {
                    Trace.Log.Now += ((WaitForSeconds)y).seconds;
                } else if (y is IEnumerator) {
                    stack.Push((IEnumerator)y);
                } else if (y == null) {
                    // yield return null: one frame
                }
            }
        }
    }
}
