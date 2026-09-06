// Generates a golden trace for EVERY coroutine in the original Animations.cs,
// by reflection, so nothing has to be transcribed by hand.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using Kaisa.Digivice;
using UnityEngine;

public static class Program {
    static SpriteDatabase db;

    static object Arg(ParameterInfo p) {
        var t = p.ParameterType;
        if (t == typeof(string)) {
            var n = p.Name.ToLower();
            if (n.Contains("code")) { return "vsjk1"; }
            return "agumon";
        }
        if (t == typeof(int)) { return 1; }
        if (t == typeof(float)) { return 1f; }
        if (t == typeof(bool)) { return false; }
        if (t == typeof(GameChar)) { return GameChar.takuya; }
        if (t == typeof(Sprite)) { return new Sprite("sprite"); }
        if (t == typeof(Sprite[])) {
            // A Sprite[] parameter is either a character's ten sprites or a
            // Digimon's set, and which one decides what the trace says. The
            // port's probe passes the character sprites where the parameter is
            // named for a character, so the reference has to as well or the
            // two runs are not of the same animation.
            var pn = p.Name.ToLower();
            if (pn.Contains("char")) { return db.GetCharacterSprites(GameChar.takuya); }
            // Every other Sprite[] in Animations.cs is a battle sprite set:
            // {default, attack, crush, energy, ability}. Energy rank 1 is what
            // the port's probe passes too.
            return db.GetAllDigimonBattleSprites("agumon", 1);
        }
        if (t == typeof(List<string>)) { return new List<string> { "agunimon", "lobomon" }; }
        if (t == typeof(Action<bool>)) { return (Action<bool>)(b => { }); }
        if (t.IsValueType) { return Activator.CreateInstance(t); }
        return null;
    }

    public static int Main(string[] args) {
        db = new SpriteDatabase();
        var audio = new AudioManager();
        var gm = new GameManager(db);
        Animations.Initialize(gm, audio, db);

        var methods = typeof(Animations)
            .GetMethods(BindingFlags.Public | BindingFlags.Static)
            .Where(m => m.ReturnType == typeof(IEnumerator))
            .OrderBy(m => m.Name)
            .ToList();

        int ok = 0, failed = 0, events = 0;
        var summary = new List<string>();
        foreach (var m in methods) {
            var ps = m.GetParameters().Select(Arg).ToArray();
            try {
                var it = (IEnumerator)m.Invoke(null, ps);
                // Every coroutine is traced against an EMPTY display, because
                // that is what the port's probe gives it: one animation into a
                // freshly built Anim Parent. Without this the elements every
                // earlier coroutine left behind are still registered, and the
                // next one's ClearAnimParent disposes them too -- which showed
                // up as AttackCollision disposing a Spiral it never built.
                ScreenElement.AnimParent.Clear();
                Driver.Run(it);
                Console.WriteLine("=== " + m.Name + " ===");
                foreach (var e in Trace.Log.Events) { Console.WriteLine(e); }
                Console.WriteLine(string.Format("--- {0} end={1:F4}ms events={2}",
                    m.Name, Trace.Log.Now * 1000.0, Trace.Log.Events.Count));
                summary.Add(string.Format("OK   {0,-28} {1,10:F1}ms {2,5} events",
                    m.Name, Trace.Log.Now * 1000.0, Trace.Log.Events.Count));
                events += Trace.Log.Events.Count;
                ok++;
            } catch (Exception ex) {
                var inner = ex.InnerException != null ? ex.InnerException : ex;
                summary.Add(string.Format("FAIL {0,-28} {1}", m.Name,
                    inner.GetType().Name + ": " + inner.Message));
                failed++;
            }
        }
        Console.WriteLine();
        Console.WriteLine("######## SUMMARY ########");
        foreach (var l in summary) { Console.WriteLine(l); }
        Console.WriteLine(string.Format("######## {0} coroutines, {1} traced, {2} failed, {3} events",
            methods.Count, ok, failed, events));
        return 0;
    }
}
