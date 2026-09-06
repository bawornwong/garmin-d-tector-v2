// Enough of the app framework to compile and run the ORIGINAL Status.cs, so
// what its screens build can be diffed against the port's -- the same trick
// the animation goldens play, applied to an app.
//
// The values the screens display are fixed here and the port's probe is given
// the same ones, so a difference in the trace is a difference in what the
// screen shows.
using System;
using UnityEngine;

// Battle.cs carries a `using UnityEditor;` it never uses -- an editor-only
// namespace that does not exist outside the Unity editor.
namespace UnityEditor { }

namespace UnityEngine.UI {
    // Status.cs uses it only in a `using`; the screen it draws into is
    // AppScreen here.
    public class Image { }
}

namespace Kaisa.Digivice.Apps {
    // Battle opens the code-input app inside itself to read a spirit's code.
    // Only its type is named here; nothing a battle SCREEN draws touches it.
    public class CodeInput : DigiviceApp {
        public string ReturnedDigimon { get { return null; } }
        public override void StartApp() { }
        public CodeInput Initialize(params object[] args) { return this; }
    }
}

namespace Kaisa.Digivice {
    // The game's debug log; the apps write to it and nothing reads it here.
    public static class VisualDebug {
        public static void WriteLine(string s) { }
    }

    // The numbers Status draws. One place, so the port's probe can be told the
    // same story.
    public static class AppFixture {
        public const int Distance = 4321;
        public const int TotalSteps = 8765;
        public const int PlayerLevel = 12;
        public const int SpiritPower = 47;
        public const int TotalBattles = 9;
        public const int TotalWins = 4;
        public const int DDockDigimon = 0;      // the row the dock holds
        public const string PageDigimon = "agumon";
        public const int DigimonExtraLevel = 2;
    }

    public interface IAppController {
        void CloseLoadedApp(Screen gotoMenu);
    }

    // The app's own screen sprite: an element like any other, so setting it is
    // an event the diff sees.
    public class AppScreen {
        public SpriteBuilder builder;
        public Sprite sprite {
            set { builder.SetSprite(value); }
        }
        public Transform transform { get { return builder.transform; } }
    }

    public abstract class DigiviceApp {
        protected IAppController controller;
        protected AppScreen screenDisplay = new AppScreen();
        protected Transform Parent { get { return screenDisplay.transform; } }
        protected GameManager gm;
        protected AudioManager audioMgr;

        public virtual void Setup(GameManager gm, IAppController controller) {
            this.gm = gm;
            this.controller = controller;
            audioMgr = gm.audioMgr;
        }
        public virtual void Dispose() { }
        public virtual void InputA() { }
        public virtual void InputB() { }
        public virtual void InputLeft() { }
        public virtual void InputRight() { }
        public virtual void InputADown() { }
        public virtual void InputBDown() { }
        public virtual void InputLeftDown() { }
        public virtual void InputRightDown() { }
        public virtual void InputAUp() { }
        public virtual void InputBUp() { }
        public virtual void InputLeftUp() { }
        public virtual void InputRightUp() { }
        protected Coroutine navigationCoroutine;
        protected virtual System.Collections.IEnumerator AutoNavigateDir(Direction dir) {
            yield return null;
        }
        protected void StartNavigation(Direction dir) { }
        protected void StopNavigation() { }

        public abstract void StartApp();

        // The harness drives the app directly: it gives it a screen element to
        // draw into, and calls the private DrawScreen the game's InvokeRepeating
        // would have called twenty times a second.
        public void AttachScreen(string name) {
            screenDisplay.builder = ScreenElement.BuildSprite(name, ScreenElement.AnimParent);
        }
        // The app's screen state is private, and reaching a data page by input
        // would mean stubbing the whole gallery. The harness sets the field
        // instead, and the port's probe sets its own to the same value.
        public void SetPrivate(string field, object value) {
            var f = GetType().GetField(field,
                System.Reflection.BindingFlags.NonPublic
                | System.Reflection.BindingFlags.Instance);
            if (f == null) { throw new Exception("no field " + field); }
            if (f.FieldType.IsEnum) { value = Enum.ToObject(f.FieldType, value); }
            // A few of these fields are bytes or floats rather than ints.
            else if (value != null && f.FieldType != value.GetType()
                     && f.FieldType.IsPrimitive) {
                value = Convert.ChangeType(value, f.FieldType);
            }
            f.SetValue(this, value);
        }

        public int ScreenChildCount() { return screenDisplay.transform.children.Count; }

        public void Draw() {
            GetType().GetMethod("DrawScreen",
                System.Reflection.BindingFlags.NonPublic
                | System.Reflection.BindingFlags.Instance).Invoke(this, null);
        }
        protected virtual void CloseApp(Screen gotoMenu = Screen.MainMenu) { }
        protected void SetScreen(Sprite sprite) { screenDisplay.sprite = sprite; }
        // DigiviceApp.ClearScreen destroys the screen's children.
        protected void ClearScreen() {
            foreach (Transform child in screenDisplay.transform) {
                GameObject.Destroy(child.gameObject);
            }
        }
        protected void CancelInvoke() { }
        // MonoBehaviour.Destroy, which the apps call unqualified. It has to do
        // the real thing: an empty stub swallowed every ClearScreen and made
        // the reference look like it never cleaned up after a screen.
        protected void Destroy(object o) {
            var g = o as GameObject;
            if (g != null) { GameObject.Destroy(g); }
        }
        protected Coroutine StartCoroutine(System.Collections.IEnumerator r) {
            Trace.Log.E("startCoroutine");
            return Driver.Spawn(r);
        }
        protected void StopCoroutine(Coroutine c) {
            Trace.Log.E("stopCoroutine");
            Driver.Kill(c);
        }
        protected void InvokeRepeating(string method, float delay, float period) { }
    }
}
