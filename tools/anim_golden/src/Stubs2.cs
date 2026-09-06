
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
        public List<Area> areas = new List<Area> { new Area(), new Area() };
        public int[] GetAreasInMap(int m) { return new int[] { 0, 1 }; }
    }
    public enum DFont { Regular, Big, Small }
    public enum SpriteAction { Default, Attack, Crush, Spirit, Small, Black, White, SpiritSmall }

    public class Digimon {
        public string name = "agumon";
        public int stage = 0, baseLevel = 4, element = 0, spiritType = 0;
        public string abilityName = "flames_1";
        public string evolution = "greymon";
    }

    public static class Database {
        public static List<World> Worlds = new List<World> { new World(), new World() };
        public static Digimon GetDigimon(string name) { var d = new Digimon(); d.name = name; return d; }
    }

    public static class BuilderArrayExt {
        public static void Move(this SpriteBuilder[] a, Direction d) { foreach (var b in a) { b.Move(d); } }
        public static void Move(this SpriteBuilder[] a, Direction d, int n) { foreach (var b in a) { b.Move(d, n); } }
        public static void SetActive(this SpriteBuilder[] a, bool v) { foreach (var b in a) { b.SetActive(v); } }
        public static void Dispose(this SpriteBuilder[] a) { foreach (var b in a) { b.Dispose(); } }
    }

    public static class SpriteArrayExt {
        public static Sprite[] ReorderedAs(this Sprite[] a, params int[] order) { return a; }
        public static Sprite[] ReorderedAs(this SpriteSet s, params int[] order) { return (Sprite[])s; }
        public static Sprite[] ReorderedAs(this SpriteSet s, object o) { return (Sprite[])s; }
    }
}
