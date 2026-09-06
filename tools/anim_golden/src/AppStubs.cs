// Enough of the app framework to compile and run the ORIGINAL Status.cs, so
// what its screens build can be diffed against the port's -- the same trick
// the animation goldens play, applied to an app.
//
// The values the screens display are fixed here and the port's probe is given
// the same ones, so a difference in the trace is a difference in what the
// screen shows.
using System;
using UnityEngine;

namespace UnityEngine.UI {
    // Status.cs uses it only in a `using`; the screen it draws into is
    // AppScreen here.
    public class Image { }
}

namespace Kaisa.Digivice {
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
        public abstract void StartApp();

        // The harness drives the app directly: it gives it a screen element to
        // draw into, and calls the private DrawScreen the game's InvokeRepeating
        // would have called twenty times a second.
        public void AttachScreen(string name) {
            screenDisplay.builder = ScreenElement.BuildSprite(name, ScreenElement.AnimParent);
        }
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
        protected void InvokeRepeating(string method, float delay, float period) { }
    }
}
