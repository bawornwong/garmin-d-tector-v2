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
        public static void Destroy(GameObject g) { Trace.Log.E("destroy " + g.name); }
        public GameObject gameObject { get { return this; } }
    }
    public class Transform : Object, IEnumerable {
        public void SetAsLastSibling() { }
        public List<Transform> children = new List<Transform>();
        public GameObject gameObject = new GameObject();
        public IEnumerator GetEnumerator() { return children.GetEnumerator(); }
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
        public static int Range(int min, int max) { return r.Next(min, max); }
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
        public static implicit operator Sprite(SpriteSet s) { return new Sprite(s.n); }
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
            emptySprite = new SpriteSet("emptySprite");
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
        public Sprite GetDigimonSprite(string name) { return new Sprite(name); }
        public Sprite GetDigimonSprite(string name, object state) { return new Sprite(name + ":" + state); }
        public Sprite[] GetAllDigimonSprites(string name) { return MakeArr(name); }
        public Sprite[] GetAllDigimonBattleSprites(string name, int rank = 0) { return MakeArr(name + "_battle"); }
        public Sprite[] GetCharacterSprites(GameChar c) { return MakeArr(c.ToString()); }
        public Sprite GetEnergySprite(int rank) { return new Sprite("energy_" + rank); }
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
