// Display-list stubs. Every mutation records an event; nothing renders.
using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace Kaisa.Digivice {

    public class ScreenElement {
        public string name;
        public int Width = 24, Height = 24;
        protected ScreenElement(string n) { name = n; Trace.Log.E("build " + Kind() + " " + n); }
        protected virtual string Kind() { return "element"; }

        public static SpriteBuilder BuildSprite(string n, Transform p) { return new SpriteBuilder(n); }
        public static TextBoxBuilder BuildTextBox(string n, Transform p, object f = null, object g = null, object h = null) { return new TextBoxBuilder(n); }
        public static TextBoxBuilder BuildTextBox(string n, Transform p) { return new TextBoxBuilder(n); }
        public static RectangleBuilder BuildRectangle(string n, Transform p) { return new RectangleBuilder(n); }
        public static ContainerBuilder BuildContainer(string n, Transform p) { return new ContainerBuilder(n); }
        public static ContainerBuilder BuildStatSign(string n, Transform p, object a = null, object b = null) { return new ContainerBuilder(n); }

        protected void L(string op) { Trace.Log.E(op + " " + name); }
        protected void L(string op, object a) { Trace.Log.E(op + " " + name + " " + a); }
        protected void L(string op, object a, object b) { Trace.Log.E(op + " " + name + " " + a + " " + b); }
        public void Dispose() { L("dispose"); }
        public void SetActive() { L("setActive"); }
        public void SetAsLastSibling() { L("setAsLastSibling"); }
    }

    public class SpriteBuilder : ScreenElement {

        public int X = 0, Y = 0;
        public string Text = "";
        public Sprite Sprite = null;
        public Transform transform = new Transform();
        public UnityEngine.Vector2Int Position { get { return new UnityEngine.Vector2Int(X, Y); } }
        public SpriteBuilder InvertColors(bool v = true) { L("invertColors", v); return this; }
        public SpriteBuilder SetMaskActive(bool v) { L("setMaskActive", v); return this; }
        public SpriteBuilder SetComponentPosition(int x, int y) { L("setComponentPosition", x, y); return this; }
        public SpriteBuilder SetFlickPeriod(float f) { L("setFlickPeriod", f); return this; }
        public ScreenElement GetChildBuilder(int i) { return new TextBoxBuilder(name + ".child" + i); }
        public SpriteBuilder SetColor(object c) { L("setColor"); return this; }

        public SpriteBuilder(string n) : base(n) { }
        protected override string Kind() { return "sprite"; }
        public SpriteBuilder SetSprite(Sprite s) { L("setSprite", s == null ? "null" : s.name); return this; }
        public SpriteBuilder SetSize(int w, int h) { Width = w; Height = h; L("setSize", w, h); return this; }
        public SpriteBuilder SetPosition(UnityEngine.Vector2Int v) { L("setPosition", v.x, v.y); return this; }
        public SpriteBuilder SetPosition(int x, int y) { L("setPosition", x, y); return this; }
        public SpriteBuilder SetX(int x) { L("setX", x); return this; }
        public SpriteBuilder SetY(int y) { L("setY", y); return this; }
        public SpriteBuilder Center() { L("center"); return this; }
        public SpriteBuilder CenterComponent() { L("centerComponent"); return this; }
        public SpriteBuilder SetActive(bool v) { L("setActive", v); return this; }
        public SpriteBuilder SetTransparent(bool v) { L("setTransparent", v); return this; }
        public SpriteBuilder FlipHorizontal(bool v) { L("flip", v); return this; }
        public SpriteBuilder Move(Direction d) { L("move", d); return this; }
        public SpriteBuilder Move(Direction d, int n) { L("move", d, n); return this; }
        public SpriteBuilder PlaceOutside(Direction d) { L("placeOutside", d); return this; }
        public SpriteBuilder SnapComponentToSide(Direction d, bool v) { L("snapToSide", d); return this; }
        public SpriteBuilder SetComponentSize(int w, int h) { L("setComponentSize", w, h); return this; }
    }

    public class TextBoxBuilder : ScreenElement {

        public int X = 0, Y = 0;
        public string Text = "";
        public Sprite Sprite = null;
        public Transform transform = new Transform();
        public UnityEngine.Vector2Int Position { get { return new UnityEngine.Vector2Int(X, Y); } }
        public TextBoxBuilder InvertColors(bool v = true) { L("invertColors", v); return this; }
        public TextBoxBuilder SetMaskActive(bool v) { L("setMaskActive", v); return this; }
        public TextBoxBuilder SetComponentPosition(int x, int y) { L("setComponentPosition", x, y); return this; }
        public TextBoxBuilder SetFlickPeriod(float f) { L("setFlickPeriod", f); return this; }
        public ScreenElement GetChildBuilder(int i) { return new TextBoxBuilder(name + ".child" + i); }
        public TextBoxBuilder SetColor(object c) { L("setColor"); return this; }

        public TextBoxBuilder(string n) : base(n) { }
        protected override string Kind() { return "textbox"; }
        public TextBoxBuilder SetText(string s) { L("setText", "\"" + s + "\""); return this; }
        public TextBoxBuilder SetSize(int w, int h) { Width = w; Height = h; L("setSize", w, h); return this; }
        public TextBoxBuilder SetPosition(UnityEngine.Vector2Int v) { L("setPosition", v.x, v.y); return this; }
        public TextBoxBuilder SetPosition(int x, int y) { L("setPosition", x, y); return this; }
        public TextBoxBuilder SetX(int x) { L("setX", x); return this; }
        public TextBoxBuilder SetY(int y) { L("setY", y); return this; }
        public TextBoxBuilder Center() { L("center"); return this; }
        public TextBoxBuilder CenterComponent() { L("centerComponent"); return this; }
        public TextBoxBuilder SetActive(bool v) { L("setActive", v); return this; }
        public TextBoxBuilder SetTransparent(bool v) { L("setTransparent", v); return this; }
        public TextBoxBuilder SetAlignment(object a) { L("setAlignment", a); return this; }
        public TextBoxBuilder SetComponentSize(int w, int h) { L("setComponentSize", w, h); return this; }
        public TextBoxBuilder Move(Direction d) { L("move", d); return this; }
        public TextBoxBuilder Move(Direction d, int n) { L("move", d, n); return this; }
        public TextBoxBuilder PlaceOutside(Direction d) { L("placeOutside", d); return this; }
    }

    public class RectangleBuilder : ScreenElement {

        public int X = 0, Y = 0;
        public string Text = "";
        public Sprite Sprite = null;
        public Transform transform = new Transform();
        public UnityEngine.Vector2Int Position { get { return new UnityEngine.Vector2Int(X, Y); } }
        public RectangleBuilder InvertColors(bool v = true) { L("invertColors", v); return this; }
        public RectangleBuilder SetMaskActive(bool v) { L("setMaskActive", v); return this; }
        public RectangleBuilder SetComponentPosition(int x, int y) { L("setComponentPosition", x, y); return this; }
        public RectangleBuilder SetFlickPeriod(float f) { L("setFlickPeriod", f); return this; }
        public ScreenElement GetChildBuilder(int i) { return new TextBoxBuilder(name + ".child" + i); }
        public RectangleBuilder SetColor(object c) { L("setColor"); return this; }

        public RectangleBuilder(string n) : base(n) { }
        protected override string Kind() { return "rect"; }
        public RectangleBuilder SetSize(int w, int h) { Width = w; Height = h; L("setSize", w, h); return this; }
        public RectangleBuilder SetPosition(UnityEngine.Vector2Int v) { L("setPosition", v.x, v.y); return this; }
        public RectangleBuilder SetPosition(int x, int y) { L("setPosition", x, y); return this; }
        public RectangleBuilder SetX(int x) { L("setX", x); return this; }
        public RectangleBuilder SetY(int y) { L("setY", y); return this; }
        public RectangleBuilder Center() { L("center"); return this; }
        public RectangleBuilder SetActive(bool v) { L("setActive", v); return this; }
        public RectangleBuilder SetColor(Color c) { L("setColor"); return this; }
        public RectangleBuilder Move(Direction d) { L("move", d); return this; }
        public RectangleBuilder Move(Direction d, int n) { L("move", d, n); return this; }
        public RectangleBuilder PlaceOutside(Direction d) { L("placeOutside", d); return this; }
    }

    public class ContainerBuilder : ScreenElement {

        public int X = 0, Y = 0;
        public string Text = "";
        public Sprite Sprite = null;
        public Transform transform = new Transform();
        public UnityEngine.Vector2Int Position { get { return new UnityEngine.Vector2Int(X, Y); } }
        public ContainerBuilder InvertColors(bool v = true) { L("invertColors", v); return this; }
        public ContainerBuilder SetMaskActive(bool v) { L("setMaskActive", v); return this; }
        public ContainerBuilder SetComponentPosition(int x, int y) { L("setComponentPosition", x, y); return this; }
        public ContainerBuilder SetFlickPeriod(float f) { L("setFlickPeriod", f); return this; }
        public ScreenElement GetChildBuilder(int i) { return new TextBoxBuilder(name + ".child" + i); }
        public ContainerBuilder SetColor(object c) { L("setColor"); return this; }

        public ContainerBuilder(string n) : base(n) { }
        protected override string Kind() { return "container"; }
        public ContainerBuilder SetSize(int w, int h) { Width = w; Height = h; L("setSize", w, h); return this; }
        public ContainerBuilder SetPosition(UnityEngine.Vector2Int v) { L("setPosition", v.x, v.y); return this; }
        public ContainerBuilder SetPosition(int x, int y) { L("setPosition", x, y); return this; }
        public ContainerBuilder Center() { L("center"); return this; }
        public ContainerBuilder SetActive(bool v) { L("setActive", v); return this; }
        public ContainerBuilder Move(Direction d) { L("move", d); return this; }
        public ContainerBuilder Move(Direction d, int n) { L("move", d, n); return this; }
        public ContainerBuilder PlaceOutside(Direction d) { L("placeOutside", d); return this; }
    }

    public class ScreenManager { public Transform animParent = new Transform(); }
    public class InputManager { public void ConsumeLastKey(params object[] a) { } }
    public class WorldManager {
        public int CurrentDistance = 100;
        public int CurrentWorld = 0;
        public int CurrentArea = 0;
        public bool GetAreaCompleted(int w, int a) { return false; }
        public int GetAreaDistance(int w, int a) { return 1000; }
        public string GetArea(int w, int a) { return "area" + a; }
    }

    public class GameManager {
        public ScreenManager screenMgr = new ScreenManager();
        public InputManager inputMgr = new InputManager();
        public WorldManager WorldMgr = new WorldManager();
        public SpriteDatabase spriteDB;
        public Sprite[] PlayerCharSprites;
        public GameManager(SpriteDatabase db) {
            spriteDB = db;
            PlayerCharSprites = db.GetCharacterSprites(GameChar.takuya);
        }
        public void UnlockInput() { Trace.Log.E("unlockInput"); }
        public ContainerBuilder BuildMapScreen(int w, Transform p = null) { return new ContainerBuilder("MapScreen"); }
        public SpriteBuilder GetDDockScreenElement(int d, Transform p = null) { return new SpriteBuilder("DDock" + d); }
        public Coroutine StartCoroutine(IEnumerator r) {
            Trace.Log.E("startCoroutine");
            return Driver.Spawn(r);
        }
        public void StopCoroutine(Coroutine c) { Trace.Log.E("stopCoroutine"); c.stopped = true; }
    }
}
