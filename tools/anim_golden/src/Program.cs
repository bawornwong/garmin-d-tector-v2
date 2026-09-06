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
        // An optional parameter's own default is what the game passes almost
        // everywhere it calls the coroutine, and it is in the source -- so use
        // it rather than a made-up 1, which had the reference deporting a
        // one-pixel sprite.
        if (p.HasDefaultValue && p.DefaultValue != null) { return p.DefaultValue; }
        if (t == typeof(string)) {
            var n = p.Name.ToLower();
            if (n.Contains("code")) { return "vsjk1"; }
            return "agumon";
        }
        if (t == typeof(int)) {
            // World 1 has a single area in the real data, and the coroutines
            // that take both a world and an area index into it -- so the world
            // the reference plays is 0, which has twelve.
            return p.Name.ToLower().Contains("world") ? 0 : 1;
        }
        if (t == typeof(float)) { return 1f; }
        if (t == typeof(bool)) { return false; }
        if (t == typeof(GameChar)) { return GameChar.takuya; }
        // A lone Sprite parameter gets real art, so the trace names a cell the
        // port can be compared against instead of a placeholder.
        if (t == typeof(Sprite)) { return db.GetDigimonSprite("agumon"); }
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

    // The Status app's seven screens, traced the way an animation is: what a
    // screen builds is a display list, and the numbers on it are events. The
    // app is walked with its own InputRight, so the order the screens come in
    // is the original's too.
    static void TraceStatusApp() {
        var gm = new GameManager(db);
        gm.WorldMgr.CurrentDistance = AppFixture.Distance;
        var status = new Kaisa.Digivice.Apps.Status();
        status.Setup(gm, null);
        status.AttachScreen("Screen");

        for (int i = 0; i < 7; i++) {
            Trace.Log.Now = 0.0;
            Trace.Log.Events.Clear();
            ScreenElement.AnimParent.Clear();
            status.Draw();
            Console.WriteLine("=== Status" + i + " ===");
            foreach (var e in Trace.Log.Events) { Console.WriteLine(e); }
            Console.WriteLine(string.Format("--- Status{0} end=0.0000ms events={1}",
                i, Trace.Log.Events.Count));
            status.InputRight();
        }
    }

    // The Database app's three data pages, which carry the densest numbers in
    // the game: the Digimon's level and HP, its energy, crush and ability, and
    // its code. The app is put on the Pages screen directly -- reaching it by
    // input would mean stubbing the whole gallery -- and each page is drawn.
    static void TraceDatabasePages() {
        var gm = new GameManager(db);
        var app = new Kaisa.Digivice.Apps.DatabaseApp();
        app.Setup(gm, null);
        app.AttachScreen("Screen");
        app.SetPrivate("currentScreen", 3);         // ScreenDatabase.Pages
        app.SetPrivate("menuIndex", 0);
        app.SetPrivate("pageDigimon", Database.GetDigimon(AppFixture.PageDigimon));

        for (int page = 0; page < 3; page++) {
            Trace.Log.Now = 0.0;
            Trace.Log.Events.Clear();
            ScreenElement.AnimParent.Clear();
            app.SetPrivate("pageIndex", page);
            app.SetPrivate("digimonNameSign", null);
            app.Draw();
            Console.WriteLine("=== DatabasePage" + page + " ===");
            foreach (var e in Trace.Log.Events) { Console.WriteLine(e); }
            Console.WriteLine(string.Format("--- DatabasePage{0} end=0.0000ms events={1}",
                page, Trace.Log.Events.Count));
        }
    }

    // The Map app's three screens: the map itself with its area markers, the
    // area selection, and the distance the chosen area costs. World 0 is the
    // multi-map one, so this exercises the four-quadrant sheet as well.
    static void TraceMapScreens() {
        var gm = new GameManager(db);
        gm.WorldMgr.CurrentWorld = 0;
        gm.WorldMgr.CurrentMap = 0;
        gm.WorldMgr.CurrentArea = 0;
        gm.WorldMgr.CurrentDistance = AppFixture.Distance;

        var app = new Kaisa.Digivice.Apps.Map();
        app.Setup(gm, null);
        app.AttachScreen("Screen");

        string[] names = { "MapMap", "MapAreas", "MapDistance" };
        for (int screen = 0; screen < 3; screen++) {
            Trace.Log.Now = 0.0;
            Trace.Log.Events.Clear();
            if (screen == 0) {
                app.StartApp();
            } else if (screen == 1) {
                app.InputA();               // open the area selection
            } else {
                app.InputA();               // open the distance screen
            }
            Console.WriteLine("=== " + names[screen] + " ===");
            foreach (var e in Trace.Log.Events) { Console.WriteLine(e); }
            Console.WriteLine(string.Format("--- {0} end=0.0000ms events={1}",
                names[screen], Trace.Log.Events.Count));
        }
    }

    // The Battle app's screens: its main menu, the D-Dock chooser, the combat
    // menu's five options, the attack menu's four, and the call-point bar the
    // regular evolution draws. The state each screen reads is set directly --
    // reaching them by input would mean playing a whole battle.
    static void TraceBattleScreens() {
        var gm = new GameManager(db);
        var app = new Kaisa.Digivice.Apps.Battle();
        app.Setup(gm, null);
        app.AttachScreen("Screen");

        // (name, screen, the index the screen reads)
        var screens = new (string, int, string, int)[] {
            ("BattleMainMenu0", 0, "menuIndex", 0),
            ("BattleMainMenu1", 0, "menuIndex", 1),
            ("BattleDDocks", 1, "ddockIndex", 0),
            ("BattleCombat0", 5, "combatMenuIndex", 0),
            ("BattleCombat1", 5, "combatMenuIndex", 1),
            ("BattleAttack0", 6, "attackIndex", 0),
            ("BattleAttack1", 6, "attackIndex", 1),
            ("BattleEvolve", 7, "callPointsForEvolution", 2),
        };

        foreach (var (name, screen, field, value) in screens) {
            app.SetPrivate("currentScreen", screen);
            app.SetPrivate(field, value);
            if (screen == 5) {
                app.SetPrivate("availableMenuOptions", new int[] { 0, 1, 2, 3, 4 });
            }
            Trace.Log.Now = 0.0;
            Trace.Log.Events.Clear();
            app.Draw();
            Console.WriteLine("=== " + name + " ===");
            foreach (var e in Trace.Log.Events) { Console.WriteLine(e); }
            Console.WriteLine(string.Format("--- {0} end=0.0000ms events={1}",
                name, Trace.Log.Events.Count));
        }
    }

    // The code-input app: five underscores, the letter being chosen, and the
    // code so far. Its StartApp builds the screen and its UpdateScreen redraws
    // it, so both are exercised.
    static void TraceCodeInputScreen() {
        var gm = new GameManager(db);
        var app = new Kaisa.Digivice.Apps.CodeInput();
        app.Setup(gm, null);
        app.AttachScreen("Screen");

        Trace.Log.Now = 0.0;
        Trace.Log.Events.Clear();
        ScreenElement.AnimParent.Clear();
        app.StartApp();
        Console.WriteLine("=== CodeInputStart ===");
        foreach (var e in Trace.Log.Events) { Console.WriteLine(e); }
        Console.WriteLine(string.Format("--- CodeInputStart end=0.0000ms events={0}",
            Trace.Log.Events.Count));
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
        TraceStatusApp();
        TraceDatabasePages();
        TraceMapScreens();
        TraceBattleScreens();
        TraceCodeInputScreen();

        Console.WriteLine();
        Console.WriteLine("######## SUMMARY ########");
        foreach (var l in summary) { Console.WriteLine(l); }
        Console.WriteLine(string.Format("######## {0} coroutines, {1} traced, {2} failed, {3} events",
            methods.Count, ok, failed, events));
        return 0;
    }
}
