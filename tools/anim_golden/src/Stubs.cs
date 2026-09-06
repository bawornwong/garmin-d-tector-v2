// Stubs that let the ORIGINAL Animations.cs compile and run outside Unity.
// Nothing here implements behaviour: every call records an event on the trace,
// and the coroutine driver accumulates WaitForSeconds. The point is that the
// event order and the schedule come from the real source file, not from a
// hand transcription of it.
using System;
using System.Collections;
using System.Collections.Generic;

namespace Trace {
    public static class Log {
        public static double Now = 0.0;
        public static List<string> Events = new List<string>();
        public static void E(string s) {
            Events.Add(string.Format("{0,12:F4} {1}", Now * 1000.0, s));
        }
    }
}

namespace UnityEngine {
    public class Object { public string name = ""; }
    public class Texture { public int width = 24; public int height = 24; }
    public class Sprite : Object {
        public Texture texture = new Texture();
        public Sprite(string n) { name = n; }
        public override string ToString() { return name; }
    }
    public class GameObject : Object {
        // The transform this object belongs to, so destroying it takes the
        // element off the display instead of only logging that it did. Unity
        // defers the removal to the end of the frame; nothing here observes
        // the hierarchy within a frame, and leaving them in made a second
        // ClearAnimParent dispose the first one's elements all over again.
        public Transform owner;
        // An element leaving the display is one event, whether it went through
        // Dispose or through Destroy on its GameObject; the port has only the
        // one word for it.
        public static void Destroy(GameObject g) {
            Trace.Log.E("dispose " + g.name);
            if (g.owner != null && g.owner.parent != null) {
                g.owner.parent.children.Remove(g.owner);
                g.owner.parent = null;
            }
        }
        public GameObject gameObject { get { return this; } }
    }
    public class Transform : Object, IEnumerable {
        public void SetAsLastSibling() { }
        public List<Transform> children = new List<Transform>();
        public Transform parent;
        public GameObject gameObject = new GameObject();
        // A snapshot, because `foreach (Transform child in AnimParent)
        // Destroy(child.gameObject)` is how ClearAnimParent works and the
        // destruction now mutates this list.
        public IEnumerator GetEnumerator() { return new List<Transform>(children).GetEnumerator(); }
        // Destroying a child of AnimParent is a real display event -- it is
        // how an animation cleans up after itself (Animations.ClearAnimParent)
        // -- so the children have to actually be here for the trace to show
        // it. Elements register themselves as they are built.
        public void Clear() { children.Clear(); }
    }
    public struct Color {
        public float r, g, b, a;
        public static Color black { get { return new Color(); } }
        public static Color white { get { return new Color(); } }
    }
    public static class Mathf {
        public static int FloorToInt(float f) { return (int)Math.Floor(f); }
        public static int CeilToInt(float f) { return (int)Math.Ceiling(f); }
        public static int RoundToInt(float f) { return (int)Math.Round(f, MidpointRounding.AwayFromZero); }
        public static float Abs(float f) { return Math.Abs(f); }
        public static float Pow(float a, float b) { return (float)Math.Pow(a, b); }
        public static int Min(int a, int b) { return Math.Min(a, b); }
        public static int Max(int a, int b) { return Math.Max(a, b); }
    }
    public static class Random {
        // deterministic, so goldens are reproducible
        static System.Random r = new System.Random(12345);
        // DTECTOR_RNG pins every roll to one number, which is how a coroutine
        // whose length depends on a roll (DataStorm's escape attempt) can be
        // diffed at all: the port's probe is told the same number and applies
        // it the same way (Kaisa.Rand.forced).
        static int? Fixed {
            get {
                var v = System.Environment.GetEnvironmentVariable("DTECTOR_RNG");
                int n;
                return (v != null && int.TryParse(v, out n)) ? (int?)n : null;
            }
        }
        public static int Range(int min, int max) {
            var f = Fixed;
            if (f != null && max > min) { return min + (f.Value % (max - min)); }
            return r.Next(min, max);
        }
        public static float Range(float min, float max) { return min + (float)r.NextDouble() * (max - min); }
    }
    public class WaitForSeconds {
        public float seconds;
        public WaitForSeconds(float s) { seconds = s; }
    }
    public class Coroutine { public IEnumerator routine; public bool stopped = false; }
    public class MonoBehaviour : Object { }
}

namespace Kaisa.Digivice {
    using UnityEngine;

    public enum GameChar { takuya, koji, zoe, jp, tommy, koichi }

    public class SpriteSet {
        string n;
        public SpriteSet(string n) { this.n = n; }
        public Sprite this[int i] { get { return new Sprite(n + "_" + i); } }
        public int Length { get { return 16; } }
        public static implicit operator Sprite(SpriteSet s) {
            return (s == null) ? null : new Sprite(s.n);
        }
        public static implicit operator Sprite[](SpriteSet s) {
            var a = new Sprite[16];
            for (int i = 0; i < 16; i++) { a[i] = new Sprite(s.n + "_" + i); }
            return a;
        }
    }

    public class SpriteDatabase {
        public SpriteSet ancientCircle;
        public SpriteSet ancientSpiral;
        public SpriteSet animDistance;
        public SpriteSet battle_attackCollision;
        public SpriteSet battle_attackCollisionBig;
        public SpriteSet battle_attackCollisionSmall;
        public SpriteSet battle_callPoints_screen;
        public SpriteSet battle_disobey;
        public SpriteSet battle_explosion;
        public SpriteSet battle_gainingSP;
        public SpriteSet blackBars;
        public SpriteSet blackScreen;
        public SpriteSet bubble;
        public SpriteSet camp;
        public SpriteSet curtain;
        public SpriteSet curtainSpecial;
        public SpriteSet dTector;
        public SpriteSet database_pages;
        public SpriteSet digiHunter_arrows;
        public SpriteSet digiHunter_faces;
        public SpriteSet digistorm;
        public SpriteSet emptySprite;
        public SpriteSet gameStart_clouds;
        public SpriteSet gameStart_spiritPlatform;
        public SpriteSet gameStart_trailmon;
        public SpriteSet games_distance;
        public SpriteSet games_score;
        public SpriteSet giveMassivePower;
        public SpriteSet giveMassivePowerInverted;
        public SpriteSet givePower;
        public SpriteSet givePowerInverted;
        public SpriteSet map_distanceScreen;
        public SpriteSet rewardBackground;
        public SpriteSet rewards;
        public SpriteSet spirit_absorber;
        public SpriteSet spirit_explosion;
        public SpriteSet status_ddock;
        public SpriteSet status_ddockEmpty;
        public SpriteSet stealSpiritAttractor;
        public SpriteSet takuya;
        public SpriteDatabase() {
            ancientCircle = new SpriteSet("ancientCircle");
            ancientSpiral = new SpriteSet("ancientSpiral");
            animDistance = new SpriteSet("animDistance");
            battle_attackCollision = new SpriteSet("battle_attackCollision");
            battle_attackCollisionBig = new SpriteSet("battle_attackCollisionBig");
            battle_attackCollisionSmall = new SpriteSet("battle_attackCollisionSmall");
            battle_callPoints_screen = new SpriteSet("battle_callPoints_screen");
            battle_disobey = new SpriteSet("battle_disobey");
            battle_explosion = new SpriteSet("battle_explosion");
            battle_gainingSP = new SpriteSet("battle_gainingSP");
            blackBars = new SpriteSet("blackBars");
            blackScreen = new SpriteSet("blackScreen");
            bubble = new SpriteSet("bubble");
            camp = new SpriteSet("camp");
            curtain = new SpriteSet("curtain");
            curtainSpecial = new SpriteSet("curtainSpecial");
            dTector = new SpriteSet("dTector");
            database_pages = new SpriteSet("database_pages");
            digiHunter_arrows = new SpriteSet("digiHunter_arrows");
            digiHunter_faces = new SpriteSet("digiHunter_faces");
            digistorm = new SpriteSet("digistorm");
            // Left unassigned in the Unity scene, so it really is null at
            // runtime -- and the port emits null for it. Naming it here made
            // the reference draw a sprite the game does not have.
            emptySprite = null;
            gameStart_clouds = new SpriteSet("gameStart_clouds");
            gameStart_spiritPlatform = new SpriteSet("gameStart_spiritPlatform");
            gameStart_trailmon = new SpriteSet("gameStart_trailmon");
            games_distance = new SpriteSet("games_distance");
            games_score = new SpriteSet("games_score");
            giveMassivePower = new SpriteSet("giveMassivePower");
            giveMassivePowerInverted = new SpriteSet("giveMassivePowerInverted");
            givePower = new SpriteSet("givePower");
            givePowerInverted = new SpriteSet("givePowerInverted");
            map_distanceScreen = new SpriteSet("map_distanceScreen");
            rewardBackground = new SpriteSet("rewardBackground");
            rewards = new SpriteSet("rewards");
            spirit_absorber = new SpriteSet("spirit_absorber");
            spirit_explosion = new SpriteSet("spirit_explosion");
            status_ddock = new SpriteSet("status_ddock");
            status_ddockEmpty = new SpriteSet("status_ddockEmpty");
            stealSpiritAttractor = new SpriteSet("stealSpiritAttractor");
            takuya = new SpriteSet("takuya");
        }
        static Sprite[] MakeArr(string n) {
            var a = new Sprite[16];
            for (int i = 0; i < a.Length; i++) { a[i] = new Sprite(n + "_" + i); }
            return a;
        }
        // The sprite index the packers produce, so the stub can resolve the
        // same art the port does -- including the fallback chain and each
        // sprite's real size, which LaunchAttack branches on.
        static Dictionary<string, int[]> index;
        static void LoadIndex() {
            if (index != null) { return; }
            index = new Dictionary<string, int[]>();
            var path = System.Environment.GetEnvironmentVariable("SPRITE_INDEX");
            if (path == null) { path = "build/sprite_index.json"; }
            if (!System.IO.File.Exists(path)) { return; }
            var text = System.IO.File.ReadAllText(path);
            var re = new System.Text.RegularExpressions.Regex(
                "\"([^\"]+)\": \\{[^}]*?\"w\": (\\d+),\\s*\"h\": (\\d+)");
            foreach (System.Text.RegularExpressions.Match m in re.Matches(text)) {
                index[m.Groups[1].Value] = new int[] {
                    int.Parse(m.Groups[2].Value), int.Parse(m.Groups[3].Value) };
            }
        }
        static Sprite Resolve(string key) {
            LoadIndex();
            if (!index.ContainsKey(key)) { return null; }
            var s = new Sprite(key);
            s.texture.width = index[key][0];
            s.texture.height = index[key][1];
            return s;
        }

        public Sprite GetDigimonSprite(string name) { return Resolve("Digimon/" + name); }
        public Sprite GetDigimonSprite(string name, object state) {
            var st = state == null ? "Default" : state.ToString();
            if (st == "Attack") {
                return Resolve("Digimon/" + name + "_at") ?? GetDigimonSprite(name);
            }
            if (st == "Crush") {
                return Resolve("Digimon/" + name + "_cr") ?? GetDigimonSprite(name, "Attack");
            }
            if (st == "Spirit") {
                return Resolve("Digimon/" + name + "_sp") ?? GetDigimonSprite(name);
            }
            if (st == "SpiritSmall") {
                return Resolve("Digimon/" + name + "_sm") ?? GetDigimonSprite(name);
            }
            if (st == "Black") {
                return Resolve("Digimon/" + name + "_bl") ?? GetDigimonSprite(name);
            }
            return GetDigimonSprite(name);
        }
        // SpriteDatabase.cs:176 -- 0: default, 1: attack, 2: crush, 3: spirit,
        // 4: black. The placeholder array it used to return named sprites
        // "agumon_3", which resolve to no art at all, so a trace could not say
        // whether the port had drawn the right one.
        public Sprite[] GetAllDigimonSprites(string name) {
            return new Sprite[] {
                GetDigimonSprite(name),
                GetDigimonSprite(name, "Attack"),
                GetDigimonSprite(name, "Crush"),
                GetDigimonSprite(name, "Spirit"),
                GetDigimonSprite(name, "Black")
            };
        }
        public Sprite[] GetAllDigimonBattleSprites(string name, int rank = 0) {
            return new Sprite[] {
                GetDigimonSprite(name),
                GetDigimonSprite(name, "Attack"),
                GetDigimonSprite(name, "Crush"),
                GetEnergySprite(rank),
                GetAbilitySprite(Database.GetDigimon(name).abilityName)
            };
        }
        public Sprite[] GetCharacterSprites(GameChar c) { return MakeArr(c.ToString()); }
        public Sprite GetEnergySprite(int rank) { return Resolve("Energies/energy_" + rank); }
        public Sprite GetWorldSprite(string world, int map) { return Resolve("Maps/" + world + "_" + map); }
        public Sprite GetAbilitySprite(string abilityName) { return Resolve("Abilities/" + abilityName); }
        public Sprite GetInvertedSprite(Sprite s) { return new Sprite("inv:" + s.name); }
    }

    public class AudioManager {
        public string attackTravelVeryLong;
        public string changeDock;
        public string charHappy;
        public string charSad;
        public string deport;
        public string deportSpirit;
        public string destroySpirits;
        public string digiHunter_Start;
        public string digiPowerFailed;
        public string digiPowerSucceed;
        public string digistorm;
        public string encounterDigimon;
        public string encounterDigimonBoss;
        public string evolutionAncient;
        public string evolutionRegular;
        public string evolutionSpirit;
        public string explosion;
        public string gameStart;
        public string launchAttack;
        public string launchAttackLong;
        public string levelDown;
        public string levelDownDigimon;
        public string levelUp;
        public string loseDigimon;
        public string punishment;
        public string reward;
        public string stealAllSpirits;
        public string summonDigimon;
        public string travelMap;
        public string unlockCode;
        public string unlockDigimon;
        public string unpleasantBeep;
        public AudioManager() {
            attackTravelVeryLong = "attackTravelVeryLong";
            changeDock = "changeDock";
            charHappy = "charHappy";
            charSad = "charSad";
            deport = "deport";
            deportSpirit = "deportSpirit";
            destroySpirits = "destroySpirits";
            digiHunter_Start = "digiHunter_Start";
            digiPowerFailed = "digiPowerFailed";
            digiPowerSucceed = "digiPowerSucceed";
            digistorm = "digistorm";
            encounterDigimon = "encounterDigimon";
            encounterDigimonBoss = "encounterDigimonBoss";
            evolutionAncient = "evolutionAncient";
            evolutionRegular = "evolutionRegular";
            evolutionSpirit = "evolutionSpirit";
            explosion = "explosion";
            gameStart = "gameStart";
            launchAttack = "launchAttack";
            launchAttackLong = "launchAttackLong";
            levelDown = "levelDown";
            levelDownDigimon = "levelDownDigimon";
            levelUp = "levelUp";
            loseDigimon = "loseDigimon";
            punishment = "punishment";
            reward = "reward";
            stealAllSpirits = "stealAllSpirits";
            summonDigimon = "summonDigimon";
            travelMap = "travelMap";
            unlockCode = "unlockCode";
            unlockDigimon = "unlockDigimon";
            unpleasantBeep = "unpleasantBeep";
        }
        public void PlaySound(string s) { Trace.Log.E("sound " + s); }
        public void StopSound() { Trace.Log.E("stopSound"); }
        public void PlayButtonA() { Trace.Log.E("sound buttonA"); }
        public void PlayCharHappy() { Trace.Log.E("sound charHappy"); }
    }
}

namespace UnityEngine.Rendering {
    public enum ShadowCastingMode { Off, On }
}
