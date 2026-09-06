
namespace UnityEngine {
    public struct Vector2Int {
        public int x, y;
        public Vector2Int(int x, int y) { this.x = x; this.y = y; }
    }
    public enum TextAnchor { UpperLeft, UpperCenter, UpperRight, MiddleLeft, MiddleCenter, MiddleRight, LowerLeft, LowerCenter, LowerRight }
}

namespace Kaisa.Digivice {
    using UnityEngine;
    using System.Collections.Generic;
    public class Area { public int number = 0; public int map = 0; public int distance = 6000; public Vector2Int coords = new Vector2Int(18, 21); }
    public class World {
        public int number = 0; public bool multiMap = true; public string worldSprite = "frontier_initial";
        public List<Area> areas = new List<Area>();
        // World.GetAreasInMap
        public int[] GetAreasInMap(int m) {
            var l = new List<int>();
            foreach (var a in areas) { if (a.map == m) { l.Add(a.number); } }
            return l.ToArray();
        }
    }
    public enum DFont { Regular, Big, Small }

    public static class Database {
        // The real worlds, read out of the checkout's worlds.json -- the same
        // file the packer reads. A made-up pair of two-area worlds made
        // DisplayNewArea draw a map that does not exist.
        public static List<World> Worlds = LoadWorlds();

        static List<World> LoadWorlds() {
            var worlds = new List<World>();
            var src = System.Environment.GetEnvironmentVariable("DTECTOR_SRC");
            var path = (src == null) ? null : src + "/Assets/Resources/worlds.json";
            if (path == null || !System.IO.File.Exists(path)) { return worlds; }
            var doc = System.Text.Json.JsonDocument.Parse(System.IO.File.ReadAllText(path));
            foreach (var w in doc.RootElement.EnumerateArray()) {
                var world = new World();
                world.number = w.GetProperty("number").GetInt32();
                world.multiMap = w.GetProperty("multiMap").GetBoolean();
                world.worldSprite = w.GetProperty("worldSprite").GetString();
                foreach (var a in w.GetProperty("areas").EnumerateArray()) {
                    var area = new Area();
                    area.number = a.GetProperty("number").GetInt32();
                    area.map = a.GetProperty("map").GetInt32();
                    area.distance = a.GetProperty("distance").GetInt32();
                    var c = a.GetProperty("coords");
                    area.coords = new Vector2Int(c.GetProperty("x").GetInt32(),
                                                 c.GetProperty("y").GetInt32());
                    world.areas.Add(area);
                }
                worlds.Add(world);
            }
            return worlds;
        }
        // The real rows, out of digimonDB.json -- the same file the packer
        // reads -- built through the original's own Digimon constructor, so
        // the stats a screen prints come from the original's arithmetic.
        public static List<Digimon> Digimons = LoadDigimons();

        static List<Digimon> LoadDigimons() {
            var rows = new List<Digimon>();
            var src = System.Environment.GetEnvironmentVariable("DTECTOR_SRC");
            var path = (src == null) ? null : src + "/Assets/Resources/digimonDB.json";
            if (path == null || !System.IO.File.Exists(path)) { return rows; }
            var doc = System.Text.Json.JsonDocument.Parse(System.IO.File.ReadAllText(path));
            foreach (var d in doc.RootElement.EnumerateArray()) {
                // Most rows have no extra evolutions, and the field is null
                // rather than an empty list for those.
                var extra = new List<string>();
                var extraField = d.GetProperty("extraEvolutions");
                if (extraField.ValueKind == System.Text.Json.JsonValueKind.Array) {
                    foreach (var e in extraField.EnumerateArray()) { extra.Add(e.GetString()); }
                }
                rows.Add(new Digimon(
                    d.GetProperty("number").GetInt32(),
                    d.GetProperty("order").GetInt32(),
                    d.GetProperty("name").GetString(),
                    (Stage)d.GetProperty("stage").GetInt32(),
                    (SpiritType)d.GetProperty("spiritType").GetInt32(),
                    d.GetProperty("abilityName").GetString(),
                    (Element)d.GetProperty("element").GetInt32(),
                    d.GetProperty("evolution").GetString(),
                    extra.ToArray(),
                    d.GetProperty("disabled").GetBoolean(),
                    d.GetProperty("baseLevel").GetInt32(),
                    Stats(d, "stats"),
                    Stats(d, "bossStats"),
                    d.GetProperty("isPseudo").GetBoolean(),
                    d.GetProperty("code").GetString()));
            }
            return rows;
        }

        static CombatStats Stats(System.Text.Json.JsonElement row, string field) {
            var s = row.GetProperty(field);
            if (s.ValueKind == System.Text.Json.JsonValueKind.Null) { return null; }
            return new CombatStats(s.GetProperty("HP").GetInt32(),
                                   s.GetProperty("EN").GetInt32(),
                                   s.GetProperty("CR").GetInt32(),
                                   s.GetProperty("AB").GetInt32());
        }

        // Digimon.rarity reads it; nothing a screen draws depends on it, and
        // the packed data carries the real value for the port.
        public static Rarity GetDigimonRarity(string name) { return Rarity.Common; }

        public static Digimon GetDigimon(string name) {
            foreach (var d in Digimons) {
                if (d.name == name.ToLower()) { return d; }
            }
            return null;
        }
    }

    public static class BuilderArrayExt {
        public static void Move(this SpriteBuilder[] a, Direction d) { foreach (var b in a) { b.Move(d); } }
        public static void Move(this SpriteBuilder[] a, Direction d, int n) { foreach (var b in a) { b.Move(d, n); } }
        public static void SetActive(this SpriteBuilder[] a, bool v) { foreach (var b in a) { b.SetActive(v); } }
        public static void Dispose(this SpriteBuilder[] a) { foreach (var b in a) { b.Dispose(); } }
    }

    public static class SpriteArrayExt {
        // Tools.cs:65 -- newArray[i] = array[indices[i]]. Returning the array
        // unchanged made LevelDown look identical to LevelUp, which is the one
        // thing that animation does differently.
        public static Sprite[] ReorderedAs(this Sprite[] a, params int[] order) {
            var b = new Sprite[order.Length];
            for (int i = 0; i < b.Length; i++) { b[i] = a[order[i]]; }
            return b;
        }
        public static Sprite[] ReorderedAs(this SpriteSet s, params int[] order) {
            return ((Sprite[])s).ReorderedAs(order);
        }
    }
}
