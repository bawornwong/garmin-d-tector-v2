// Display-list stubs. Every mutation records an event; nothing renders.
using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace Kaisa.Digivice {

    public class ScreenElement {
        public string name;
        // The prefabs' own sizeDelta, in game pixels (Unity units / 24):
        // SolidSprite 768x768, TextBox 768x120, Rectangle and Container 24x24.
        // It decides where Center() puts an element that was never sized, so a
        // made-up default silently moves the first frame of OpenCamp.
        public int Width = 32, Height = 32;
        // Every element an animation builds goes under the parent it was
        // built into -- usually AnimParent, the container ScreenManager makes
        // for the animation being played, but a composite builds its parts
        // inside its own container. It matters because ClearAnimParent
        // destroys AnimParent's DIRECT children only: a stat sign is one
        // disposal, not three, which is also what the port's display list
        // does.
        public static Transform AnimParent { get { return ScreenManager.Shared.animParent; } }
        public Transform transform = new Transform();
        protected ScreenElement(string n, Transform p) {
            name = n;
            Trace.Log.E("build " + Kind() + " " + n);
            transform.gameObject.name = n;
            transform.gameObject.owner = transform;
            if (p != null) { p.children.Add(transform); transform.parent = p; }
        }
        protected virtual string Kind() { return "element"; }
        // The children a composite builder made, so GetChildBuilder hands back
        // the element that is really on the display rather than a new one.
        public List<ScreenElement> Children = new List<ScreenElement>();

        public static SpriteBuilder BuildSprite(string n, Transform p) { return new SpriteBuilder(n, p); }
        public static TextBoxBuilder BuildTextBox(string n, Transform p, object f = null, object g = null, object h = null) { return new TextBoxBuilder(n, p); }
        public static TextBoxBuilder BuildTextBox(string n, Transform p) { return new TextBoxBuilder(n, p); }
        public static RectangleBuilder BuildRectangle(string n, Transform p) { return new RectangleBuilder(n, p); }
        // The container prefab starts transparent and BuildContainer sets that
        // property whichever way the caller asked -- an event, and one the
        // port emits, so the reference has to as well.
        public static ContainerBuilder BuildContainer(string n, Transform p, bool transparent = true) {
            var cb = new ContainerBuilder(n, p);
            cb.SetTransparent(transparent);
            return cb;
        }
        // ScreenElement.cs:193 BuildStatSign, which is not a one-liner: it is a
        // black band with a label textbox and an empty value textbox, and the
        // animations fill the value through GetChildBuilder(1). Stubbing it as
        // a bare container hid six display events and invented a "LIFE.child1"
        // element the game never builds.
        public static ContainerBuilder BuildStatSign(string message, Transform p, object a = null, object b = null) {
            ContainerBuilder cbSign = BuildContainer("Sign", p, false).SetBackgroundBlack(true).SetSize(32, 17).SetPosition(0, 15);
            TextBoxBuilder sbMessage = BuildTextBox("Sign", cbSign.transform, DFont.Small)
                .SetText(message)
                .SetSize(28, 5)
                .SetPosition(2, 2)
                .InvertColors(true);
            TextBoxBuilder sbValue = BuildTextBox("Sign", cbSign.transform, DFont.Small)
                .SetSize(28, 5)
                .SetPosition(2, 10)
                .SetAlignment(TextAnchor.UpperRight)
                .InvertColors(true);
            cbSign.Children.Add(sbMessage);
            cbSign.Children.Add(sbValue);
            return cbSign;
        }

        // One vocabulary for both sides of the diff. Monkey C has no enum
        // names and prints booleans lower case, so the reference is normalised
        // here rather than the port being made to fake C# formatting: an enum
        // prints as its ordinal (which is what the port stores) and a bool as
        // true/false.
        protected static string Fmt(object o) {
            if (o == null) { return "null"; }
            if (o is bool) { return ((bool)o) ? "true" : "false"; }
            if (o.GetType().IsEnum) { return ((int)o).ToString(); }
            return o.ToString();
        }
        // The original's BaseCenter / BasePlaceOutside / SnapComponentToSide
        // are composites: each calls BaseSetPosition, BaseSetX/Y or
        // SetComponentX/Y, and those log in their own right. Stubbing only the
        // outer call under-reports what the animation did to the display --
        // which is how RewardEmpty first "failed" its diff against a port that
        // was faithfully emitting both.
        protected const int SCREEN = 32;
        protected static int Half(int screen, int size) {
            return (int)System.Math.Round((screen - size) / 2f, System.MidpointRounding.ToEven);
        }
        protected void L(string op) { Trace.Log.E(op + " " + name); }
        protected void L(string op, object a) { Trace.Log.E(op + " " + name + " " + Fmt(a)); }
        protected void L(string op, object a, object b) { Trace.Log.E(op + " " + name + " " + Fmt(a) + " " + Fmt(b)); }
        public void Dispose() { L("dispose"); }
        public void SetActive() { L("setActive"); }
        public void SetAsLastSibling() { L("setAsLastSibling"); }
    }

    public class SpriteBuilder : ScreenElement {

        public int X = 0, Y = 0;
        public string Text = "";
        public Sprite Sprite = null;
        public UnityEngine.Vector2Int Position { get { return new UnityEngine.Vector2Int(X, Y); } }
        public SpriteBuilder InvertColors(bool v = true) { L("invertColors", v); return this; }
        public SpriteBuilder SetMaskActive(bool v) { L("setMaskActive", v); return this; }
        public SpriteBuilder SetComponentPosition(int x, int y) { ComponentX = x; ComponentY = y; L("setComponentPosition", x, y); return this; }
        public SpriteBuilder SetFlickPeriod(float f) { L("setFlickPeriod", f); return this; }
        public ScreenElement GetChildBuilder(int i) { return new TextBoxBuilder(name + ".child" + i); }
        public SpriteBuilder SetColor(object c) { L("setColor"); return this; }

        public SpriteBuilder(string n, Transform p = null) : base(n, p) { }
        protected override string Kind() { return "sprite"; }
        public SpriteBuilder SetSprite(Sprite s) { L("setSprite", s == null ? "null" : s.name); return this; }
        // SpriteBuilder.BaseSetSize is overridden in the original to resize the
        // component as well, and the component resize logs in its own right.
        public SpriteBuilder SetSize(int w, int h) { Width = w; Height = h; L("setSize", w, h); SetComponentSize(w, h); return this; }
        public SpriteBuilder SetPosition(UnityEngine.Vector2Int v) { L("setPosition", v.x, v.y); return this; }
        public SpriteBuilder SetPosition(int x, int y) { L("setPosition", x, y); return this; }
        public SpriteBuilder SetX(int x) { L("setX", x); return this; }
        public SpriteBuilder SetY(int y) { L("setY", y); return this; }
        public SpriteBuilder Center() { L("center"); SetPosition(Half(SCREEN, Width), Half(SCREEN, Height)); return this; }
        public SpriteBuilder CenterComponent() { L("centerComponent"); SetComponentPosition(Half(Width, ComponentWidth), Half(Height, ComponentHeight)); return this; }
        public SpriteBuilder SetActive(bool v) { L("setActive", v); return this; }
        public SpriteBuilder SetTransparent(bool v) { L("setTransparent", v); return this; }
        public SpriteBuilder FlipHorizontal(bool v) { L("flip", v); return this; }
        public SpriteBuilder Move(Direction d) { L("move", d, 1); return this; }
        public SpriteBuilder Move(Direction d, int n) { L("move", d, n); return this; }
        public SpriteBuilder PlaceOutside(Direction d) {
            L("placeOutside", d);
            if (d == Direction.Up) { SetY(-Height); }
            else if (d == Direction.Down) { SetY(SCREEN); }
            else if (d == Direction.Left) { SetX(-Width); }
            else if (d == Direction.Right) { SetX(SCREEN); }
            return this;
        }
        public SpriteBuilder SnapComponentToSide(Direction d, bool v) {
            L("snapToSide", d);
            if (v) { CenterComponent(); }
            if (d == Direction.Left) { SetComponentX(0); }
            else if (d == Direction.Right) { SetComponentX(Width - ComponentWidth); }
            else if (d == Direction.Up) { SetComponentY(0); }
            else if (d == Direction.Down) { SetComponentY(Height - ComponentHeight); }
            return this;
        }
        public int ComponentWidth = 24, ComponentHeight = 24;
        public int ComponentX = 0, ComponentY = 0;
        public SpriteBuilder SetComponentSize(int w, int h) { ComponentWidth = w; ComponentHeight = h; L("setComponentSize", w, h); return this; }
        // SetComponentX/Y go through SetComponentPosition in the original, so
        // they keep the other axis rather than zeroing it.
        public SpriteBuilder SetComponentX(int x) { return SetComponentPosition(x, ComponentY); }
        public SpriteBuilder SetComponentY(int y) { return SetComponentPosition(ComponentX, y); }
    }

    public class TextBoxBuilder : ScreenElement {

        public int X = 0, Y = 0;
        // A property rather than a field: `tbLevel.Text = "12"` is how several
        // animations change their text, and it mutates the display exactly as
        // SetText does, so it has to appear in the trace.
        string _text = "";
        public string Text {
            get { return _text; }
            set { _text = value; L("setText", value); }
        }
        public Sprite Sprite = null;
        public UnityEngine.Vector2Int Position { get { return new UnityEngine.Vector2Int(X, Y); } }
        public TextBoxBuilder InvertColors(bool v = true) { L("invertColors", v); return this; }
        public TextBoxBuilder SetMaskActive(bool v) { L("setMaskActive", v); return this; }
        public TextBoxBuilder SetComponentPosition(int x, int y) { L("setComponentPosition", x, y); return this; }
        public TextBoxBuilder SetFlickPeriod(float f) { L("setFlickPeriod", f); return this; }
        public ScreenElement GetChildBuilder(int i) { return new TextBoxBuilder(name + ".child" + i); }
        public TextBoxBuilder SetColor(object c) { L("setColor"); return this; }

        public TextBoxBuilder(string n, Transform p = null) : base(n, p) { Width = 32; Height = 5; }
        protected override string Kind() { return "textBox"; }
        public TextBoxBuilder SetText(string s) { Text = s; return this; }
        // TextBoxBuilder.BaseSetSize resizes the component too.
        public TextBoxBuilder SetSize(int w, int h) { Width = w; Height = h; L("setSize", w, h); SetComponentSize(w, h); return this; }
        public TextBoxBuilder SetPosition(UnityEngine.Vector2Int v) { L("setPosition", v.x, v.y); return this; }
        public TextBoxBuilder SetPosition(int x, int y) { L("setPosition", x, y); return this; }
        public TextBoxBuilder SetX(int x) { L("setX", x); return this; }
        public TextBoxBuilder SetY(int y) { L("setY", y); return this; }
        public TextBoxBuilder Center() { L("center"); SetPosition(Half(SCREEN, Width), Half(SCREEN, Height)); return this; }
        public TextBoxBuilder CenterComponent() { L("centerComponent"); SetComponentPosition(Half(Width, ComponentWidth), Half(Height, ComponentHeight)); return this; }
        public TextBoxBuilder SetActive(bool v) { L("setActive", v); return this; }
        public TextBoxBuilder SetTransparent(bool v) { L("setTransparent", v); return this; }
        public TextBoxBuilder SetAlignment(object a) { L("setAlignment", a); return this; }
        public int ComponentWidth = 32, ComponentHeight = 5;
        public TextBoxBuilder SetComponentSize(int w, int h) { ComponentWidth = w; ComponentHeight = h; L("setComponentSize", w, h); return this; }
        public TextBoxBuilder Move(Direction d) { L("move", d, 1); return this; }
        public TextBoxBuilder Move(Direction d, int n) { L("move", d, n); return this; }
        public TextBoxBuilder PlaceOutside(Direction d) {
            L("placeOutside", d);
            if (d == Direction.Up) { SetY(-Height); }
            else if (d == Direction.Down) { SetY(SCREEN); }
            else if (d == Direction.Left) { SetX(-Width); }
            else if (d == Direction.Right) { SetX(SCREEN); }
            return this;
        }
    }

    public class RectangleBuilder : ScreenElement {

        public int X = 0, Y = 0;
        public string Text = "";
        public Sprite Sprite = null;
        public UnityEngine.Vector2Int Position { get { return new UnityEngine.Vector2Int(X, Y); } }
        public RectangleBuilder InvertColors(bool v = true) { L("invertColors", v); return this; }
        public RectangleBuilder SetMaskActive(bool v) { L("setMaskActive", v); return this; }
        public RectangleBuilder SetComponentPosition(int x, int y) { L("setComponentPosition", x, y); return this; }
        public RectangleBuilder SetFlickPeriod(float f) { L("setFlickPeriod", f); return this; }
        public ScreenElement GetChildBuilder(int i) { return new TextBoxBuilder(name + ".child" + i); }
        public RectangleBuilder SetColor(object c) { L("setColor"); return this; }

        public RectangleBuilder(string n, Transform p = null) : base(n, p) { Width = 1; Height = 1; }
        protected override string Kind() { return "rectangle"; }
        public RectangleBuilder SetSize(int w, int h) { Width = w; Height = h; L("setSize", w, h); return this; }
        public RectangleBuilder SetPosition(UnityEngine.Vector2Int v) { L("setPosition", v.x, v.y); return this; }
        public RectangleBuilder SetPosition(int x, int y) { L("setPosition", x, y); return this; }
        public RectangleBuilder SetX(int x) { L("setX", x); return this; }
        public RectangleBuilder SetY(int y) { L("setY", y); return this; }
        public RectangleBuilder Center() { L("center"); SetPosition(Half(SCREEN, Width), Half(SCREEN, Height)); return this; }
        public RectangleBuilder SetActive(bool v) { L("setActive", v); return this; }
        public RectangleBuilder SetColor(Color c) { L("setColor"); return this; }
        public RectangleBuilder Move(Direction d) { L("move", d, 1); return this; }
        public RectangleBuilder Move(Direction d, int n) { L("move", d, n); return this; }
        public RectangleBuilder PlaceOutside(Direction d) {
            L("placeOutside", d);
            if (d == Direction.Up) { SetY(-Height); }
            else if (d == Direction.Down) { SetY(SCREEN); }
            else if (d == Direction.Left) { SetX(-Width); }
            else if (d == Direction.Right) { SetX(SCREEN); }
            return this;
        }
    }

    public class ContainerBuilder : ScreenElement {

        public int X = 0, Y = 0;
        public string Text = "";
        public Sprite Sprite = null;
        public UnityEngine.Vector2Int Position { get { return new UnityEngine.Vector2Int(X, Y); } }
        public ContainerBuilder InvertColors(bool v = true) { L("invertColors", v); return this; }
        public ContainerBuilder SetMaskActive(bool v) { L("setMaskActive", v); return this; }
        public ContainerBuilder SetComponentPosition(int x, int y) { L("setComponentPosition", x, y); return this; }
        public ContainerBuilder SetFlickPeriod(float f) { L("setFlickPeriod", f); return this; }
        public ScreenElement GetChildBuilder(int i) { return Children[i]; }
        public ContainerBuilder SetColor(object c) { L("setColor"); return this; }
        public ContainerBuilder SetTransparent(bool v) { L("setTransparent", v); return this; }
        // Silent on both sides: the flag decides how the container paints, and
        // nothing reads it back.
        public ContainerBuilder SetBackgroundBlack(bool v) { return this; }

        public ContainerBuilder(string n, Transform p = null) : base(n, p) { Width = 1; Height = 1; }
        protected override string Kind() { return "container"; }
        public ContainerBuilder SetSize(int w, int h) { Width = w; Height = h; L("setSize", w, h); return this; }
        public ContainerBuilder SetPosition(UnityEngine.Vector2Int v) { L("setPosition", v.x, v.y); return this; }
        public ContainerBuilder SetPosition(int x, int y) { L("setPosition", x, y); return this; }
        public ContainerBuilder SetX(int x) { L("setX", x); return this; }
        public ContainerBuilder SetY(int y) { L("setY", y); return this; }
        public ContainerBuilder Center() { L("center"); SetPosition(Half(SCREEN, Width), Half(SCREEN, Height)); return this; }
        public ContainerBuilder SetActive(bool v) { L("setActive", v); return this; }
        public ContainerBuilder Move(Direction d) { L("move", d, 1); return this; }
        public ContainerBuilder Move(Direction d, int n) { L("move", d, n); return this; }
        public ContainerBuilder PlaceOutside(Direction d) {
            L("placeOutside", d);
            if (d == Direction.Up) { SetY(-Height); }
            else if (d == Direction.Down) { SetY(SCREEN); }
            else if (d == Direction.Left) { SetX(-Width); }
            else if (d == Direction.Right) { SetX(SCREEN); }
            return this;
        }
    }

    public class ScreenManager {
        public static ScreenManager Shared = new ScreenManager();
        public Transform animParent = new Transform();
    }
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
        public ScreenManager screenMgr = ScreenManager.Shared;
        public InputManager inputMgr = new InputManager();
        public WorldManager WorldMgr = new WorldManager();
        public SpriteDatabase spriteDB;
        public Sprite[] PlayerCharSprites;
        public GameManager(SpriteDatabase db) {
            spriteDB = db;
            PlayerCharSprites = db.GetCharacterSprites(GameChar.takuya);
        }
        public void UnlockInput() { Trace.Log.E("unlockInput"); }
        // GameManager.cs:281 BuildMapScreen -- a container with one map
        // sprite, or four for a multi-map world. Stubbing it as a bare
        // "MapScreen" container hid every one of those.
        public ContainerBuilder BuildMapScreen(int w, Transform p = null) {
            ContainerBuilder cbMap = ScreenElement.BuildContainer("Map Container", p);
            string worldSprite = Database.Worlds[w].worldSprite;
            if (Database.Worlds[w].multiMap) {
                cbMap.SetSize(64, 64);
                ScreenElement.BuildSprite("Map 0", cbMap.transform).SetSprite(spriteDB.GetWorldSprite(worldSprite, 0));
                ScreenElement.BuildSprite("Map 1", cbMap.transform).SetSprite(spriteDB.GetWorldSprite(worldSprite, 1)).SetPosition(0, 32);
                ScreenElement.BuildSprite("Map 2", cbMap.transform).SetSprite(spriteDB.GetWorldSprite(worldSprite, 2)).SetPosition(32, 32);
                ScreenElement.BuildSprite("Map 3", cbMap.transform).SetSprite(spriteDB.GetWorldSprite(worldSprite, 3)).SetPosition(32, 0);
            }
            else {
                cbMap.SetSize(32, 32);
                ScreenElement.BuildSprite("Map 0", cbMap.transform).SetSprite(spriteDB.GetWorldSprite(worldSprite, 0));
            }
            return cbMap;
        }
        // GameManager.GetDDockScreenElement builds TWO sprites -- the dock
        // plate and the Digimon standing in it -- and returns the second. The
        // dock's own name is the literal "$DDock{ddock}": the original wrote a
        // C# interpolation without the $ prefix, so the brace text IS the name.
        public SpriteBuilder GetDDockScreenElement(int d, Transform p = null) {
            new SpriteBuilder("$DDock{ddock}").SetSprite(spriteDB.status_ddock[d]);
            return new SpriteBuilder("DigimonDDock" + d)
                .SetSize(24, 24).SetPosition(4, 8).SetSprite(new Sprite("agumon"));
        }
        public Coroutine StartCoroutine(IEnumerator r) {
            Trace.Log.E("startCoroutine");
            return Driver.Spawn(r);
        }
        public void StopCoroutine(Coroutine c) {
            Trace.Log.E("stopCoroutine");
            c.stopped = true;
            Driver.Kill(c);
        }
    }
}
