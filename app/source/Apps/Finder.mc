import Toybox.Lang;

// port of Logic/Apps/Games/Finder.cs
//
// Hold A and a loading bar sweeps the screen; each sweep is one attempt at
// finding a battle, with a 1-in-10 chance. Five failures show the error
// screen; a success runs the completion bar and starts a battle.
//
// Two of its three loops are coroutines, and they are the app's own rather
// than Animations.cs's, so they live here beside it -- as DatabaseApp's and
// Camp's do.
class Finder extends DigiviceApp {
    var sbHourglass as SpriteBuilder?;
    var rbBlackScreen as RectangleBuilder?;
    var sbLoading as SpriteBuilder?;
    var loadingCoroutine as Fiber?;

    var tries as Number = 0;
    var result as Number = 0;      // 0 nothing, 1 loading, 2 failure, 3 succeed
    var state as Boolean = false;
    var _frames as Number = 0;

    function initialize(gmIn as GameManager, controllerIn, parent as ScreenElement) {
        DigiviceApp.initialize(gmIn, controllerIn, parent);
    }

    function inputB() as Void {
        if (result == 0) {
            gm.audioMgr.playButtonB();
            closeApp(Kaisa.SCREEN_GAMES_MENU);
        }
    }

    function inputADown() as Void {
        // Remove error screen.
        if (result == 2) {
            gm.audioMgr.playButtonA();
            result = 0;
        } else if (result != 3) {
            gm.audioMgr.playButtonA();
            tries = 0;
            startLoadingBar();
        }
    }

    function inputAUp() as Void {
        if (result != 3) {
            result = 0;
            stopLoadingBar();
        }
    }

    function startApp() as Void {
        displayPressASprite();
    }

    // InvokeRepeating("DisplayPressASprite", 0f, 0.75f) -- 0.75 s is fifteen
    // frames at the 50 ms floor.
    function tick(elapsedMs as Number) as Void {
        _frames += 1;
        if (_frames % 15 == 0) { displayPressASprite(); }
    }

    function displayPressASprite() as Void {
        if (result == 0) {
            setScreen(state ? Kaisa.Sprites.PRESS_A_BUTTON[1]
                            : Kaisa.Sprites.PRESS_A_BUTTON[0]);
            state = !state;
        }
    }

    function startLoadingBar() as Void {
        result = 1;
        rbBlackScreen = Kaisa.ScreenBuilder.buildRectangle("BlackScreen0", screen).setSize(32, 32);
        sbLoading = Kaisa.ScreenBuilder.buildSprite("Loading", screen)
            .setSprite(Kaisa.Sprites.LOADING).placeOutside(Kaisa.DIR_UP);
        loadingCoroutine = gm.runner.start(new AnimateLoadingBar(self));
    }

    function stopLoadingBar() as Void {
        if (loadingCoroutine != null) {
            gm.runner.stop(loadingCoroutine);
            loadingCoroutine = null;
            if (rbBlackScreen != null) { rbBlackScreen.dispose(); rbBlackScreen = null; }
            if (sbLoading != null) { sbLoading.dispose(); sbLoading = null; }
            if (sbHourglass != null) { sbHourglass.dispose(); sbHourglass = null; }
        }
    }

    function dispose() as Void {
        stopLoadingBar();
        DigiviceApp.dispose();
    }

    // Called by AnimateLoadingBar when a sweep succeeds.
    function startSuccessBar() as Void {
        gm.runner.start(new AnimateSuccessBar(self));
    }

    // The tail of AnimateSuccessBar: close, then start the battle the search
    // found. Battle is step 8 and is not translated, so the app closes and the
    // call site says what is missing rather than pretending it happened.
    function finishSuccess() as Void {
        closeApp(Kaisa.SCREEN_MAIN_MENU);
        // logicMgr.CallRandomBattle(true) -- waits on Battle.
    }
}

// port of Finder.AnimateLoadingBar
class AnimateLoadingBar extends Routine {
    var app as Finder;
    var i as Number = 0;

    function initialize(appIn as Finder) {
        Routine.initialize();
        app = appIn;
    }

    function step(rt as Fiber) as Float {
        switch (pc) {
            case 0:
                app.sbHourglass = Kaisa.ScreenBuilder.buildSprite("Hourglass", app.screen)
                    .setSprite(Kaisa.Sprites.HOURGLASS);
                pc = 1;
                return 0.5;
            case 1:
                app.sbHourglass.dispose();
                app.sbHourglass = null;
                pc = 2;
                return 0.0;
            case 2:                                 // while (result == 1)
                if (app.result != 1) { pc = 6; return 0.0; }
                if (app.tries == 5) {
                    app.result = 2;
                    pc = 6;
                    return 0.0;
                }
                if (Kaisa.Rand.rangeInt(0, 10) == 0) {
                    app.result = 3;
                    pc = 6;
                    return 0.0;
                }
                app.sbLoading.placeOutside(Kaisa.DIR_UP);
                i = 0;
                pc = 3;
                return 0.0;
            case 3:                                 // for (i = 0; i < 64; i++)
                if (i >= 64) { pc = 5; return 0.0; }
                app.sbLoading.move(Kaisa.DIR_DOWN, 1);
                pc = 4;
                return 1.75 / 64;
            case 4:
                i += 1;
                pc = 3;
                return 0.0;
            case 5:
                app.tries += 1;
                pc = 2;
                return 0.0;
            case 6:
                if (app.result == 2) {
                    app.setScreen(Kaisa.Sprites.ERROR);
                    app.rbBlackScreen.dispose();
                    app.rbBlackScreen = null;
                    app.sbLoading.dispose();
                    app.sbLoading = null;
                } else if (app.result == 3) {
                    app.startSuccessBar();
                }
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Finder.AnimateSuccessBar
class AnimateSuccessBar extends Routine {
    var app as Finder;
    var sbSuccessBar as SpriteBuilder?;
    var i as Number = 0;

    function initialize(appIn as Finder) {
        Routine.initialize();
        app = appIn;
    }

    function step(rt as Fiber) as Float {
        switch (pc) {
            case 0:
                sbSuccessBar = Kaisa.ScreenBuilder.buildSprite("LoadingSuccessful", app.screen)
                    .setSize(32, 82)
                    .setSprite(Kaisa.Sprites.LOADING_COMPLETE)
                    .placeOutside(Kaisa.DIR_UP);
                i = 0;
                pc = 1;
                return 0.0;
            case 1:                                 // for (i = 0; i < 82 + 32; i++)
                if (i >= 82 + 32) { pc = 3; return 0.0; }
                sbSuccessBar.move(Kaisa.DIR_DOWN, 1);
                pc = 2;
                return 1.75 / 64;
            case 2:
                i += 1;
                pc = 1;
                return 0.0;
            case 3:
                app.finishSuccess();
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}
