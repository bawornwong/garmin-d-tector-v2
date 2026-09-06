import Toybox.Lang;

// port of Logic/Apps/DigiviceApp.cs and Logic/Apps/IAppController.cs
//
// The C# is a MonoBehaviour with a screenDisplay Image the app draws into and
// twelve empty virtual input methods. Here the screen is a display-list
// container the app owns, and the twelve methods stay exactly as they are:
// they are the abstract input events the adapter already produces (ADR 9).
//
// IAppController is one method, so ticket 11's rule applies: no interface,
// just a base class the host implements (`closeLoadedApp`) and duck typing.
class DigiviceApp {
    var gm as GameManager;
    var controller;                       // whoever can close this app
    var screen as SpriteBuilder;          // the app's own root, DigiviceApp.screenDisplay

    function initialize(gmIn as GameManager, controllerIn, parent as ScreenElement) {
        gm = gmIn;
        controller = controllerIn;
        // screenDisplay is a full-screen Image whose sprite the apps swap for
        // their background art, with every element they build parented to it.
        screen = Kaisa.ScreenBuilder.buildSprite("Screen", parent);
        screen.setSize(Kaisa.Constants.SCREEN_WIDTH, Kaisa.Constants.SCREEN_HEIGHT)
              .setTransparent(true);
    }

    function dispose() as Void {
        screen.dispose();
    }

    // The twelve abstract events, in InputAdapter's order.
    function inputA() as Void {}
    function inputB() as Void {}
    function inputLeft() as Void {}
    function inputRight() as Void {}
    function inputADown() as Void {}
    function inputBDown() as Void {}
    function inputLeftDown() as Void {}
    function inputRightDown() as Void {}
    function inputAUp() as Void {}
    function inputBUp() as Void {}
    function inputLeftUp() as Void {}
    function inputRightUp() as Void {}

    function startApp() as Void {}

    // DigiviceApp.CloseApp
    function closeApp(gotoMenu as Number) as Void {
        controller.closeLoadedApp(gotoMenu);
    }

    // Called once per frame by the host, which is what replaces the original's
    // `InvokeRepeating("DrawScreen", 0, 0.05f)`: the frame already runs at the
    // 50 ms floor, so an app that redraws every frame redraws at the rate the
    // original asked for (ADR 5).
    function tick(elapsedMs as Number) as Void {}

    function setScreen(sprite as Array<Number>?) as Void {
        screen.setSprite(sprite);
    }

    // DigiviceApp.ClearScreen -- destroys every child of the app's screen.
    function clearScreen() as Void {
        while (screen.children.size() > 0) {
            screen.children[0].dispose();
        }
    }
}
