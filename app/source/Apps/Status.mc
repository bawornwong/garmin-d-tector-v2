import Toybox.Lang;

// port of Logic/Apps/Status.cs
//
// Seven screens the player pages through with left/right: distance, level,
// victories, and the four D-Docks. The original redraws the whole thing 20
// times a second (`InvokeRepeating("DrawScreen", 0, 0.05f)`) and rebuilds its
// elements from scratch each time; the port keeps that, because the frame
// already runs at 20 fps and the screen is three elements deep.
class Status extends DigiviceApp {
    var currentScreen as Number = 0;
    // Where B goes back to. The menu opens this app the way the original does;
    // the character screen also pages it (LogicManager.pageStatus), and then
    // backing out belongs to the character screen rather than the menu.
    var returnScreen as Number = Kaisa.SCREEN_MAIN_MENU;

    function initialize(gmIn as GameManager, controllerIn, parent as ScreenElement) {
        DigiviceApp.initialize(gmIn, controllerIn, parent);
    }

    // --- Input ---

    function inputA() as Void {
        gm.audioMgr.playButtonB();
    }

    function inputB() as Void {
        gm.audioMgr.playButtonB();
        closeApp(returnScreen);
    }

    function inputLeft() as Void {
        gm.audioMgr.playButtonA();
        currentScreen = Kaisa.MathExt.circularAdd(currentScreen, -1, 6, 0);
    }

    function inputRight() as Void {
        gm.audioMgr.playButtonA();
        currentScreen = Kaisa.MathExt.circularAdd(currentScreen, 1, 6, 0);
    }

    function startApp() as Void {
        drawScreen();
    }

    function tick(elapsedMs as Number) as Void {
        drawScreen();
    }

    function drawScreen() as Void {
        clearScreen();

        if (currentScreen == 0) {
            setScreen(Kaisa.Sprites.STATUS_DISTANCE);
            var distance = gm.worldMgr.currentDistance().toString();
            var steps = gm.worldMgr.totalSteps().toString();
            Kaisa.ScreenBuilder.buildTextBox("TextDistance", screen, Kaisa.Font.REGULAR)
                .setText(distance).setSize(31, 5).setPosition(0, 10)
                .setAlignment(Kaisa.Text.ANCHOR_UPPER_RIGHT);
            Kaisa.ScreenBuilder.buildTextBox("TextSteps", screen, Kaisa.Font.REGULAR)
                .setText(steps).setSize(31, 5).setPosition(0, 26)
                .setAlignment(Kaisa.Text.ANCHOR_UPPER_RIGHT);
        } else if (currentScreen == 1) {
            setScreen(Kaisa.Sprites.STATUS_LEVEL);
            var level = gm.logicMgr.getPlayerLevel().toString();
            var spirits = gm.logicMgr.spiritPower().toString();
            Kaisa.ScreenBuilder.buildTextBox("TextLevel", screen, Kaisa.Font.REGULAR)
                .setText(level).setSize(31, 5).setPosition(0, 10)
                .setAlignment(Kaisa.Text.ANCHOR_UPPER_RIGHT);
            Kaisa.ScreenBuilder.buildTextBox("TextSpirits", screen, Kaisa.Font.REGULAR)
                .setText(spirits).setSize(31, 5).setPosition(0, 26)
                .setAlignment(Kaisa.Text.ANCHOR_UPPER_RIGHT);
        } else if (currentScreen == 2) {
            setScreen(Kaisa.Sprites.STATUS_VICTORIES);
            var fVictoryPerc = gm.logicMgr.winPercentage();
            var iVictoryPerc = Kaisa.MathExt.roundToInt(fVictoryPerc * 100);
            // "The victory percentage is never 100% or 0%, unless the player
            // has won or lost every single battle they've played."
            if (iVictoryPerc == 100 && fVictoryPerc != 1.0) { iVictoryPerc = 99; }
            if (iVictoryPerc == 0 && fVictoryPerc != 0.0) { iVictoryPerc = 1; }

            var victoryPerc = iVictoryPerc.toString();
            var winCount = gm.logicMgr.totalWins().toString();
            Kaisa.ScreenBuilder.buildTextBox("TextLevel", screen, Kaisa.Font.REGULAR)
                .setText(victoryPerc).setSize(24, 5).setPosition(0, 10)
                .setAlignment(Kaisa.Text.ANCHOR_UPPER_RIGHT);
            Kaisa.ScreenBuilder.buildTextBox("TextSpirits", screen, Kaisa.Font.REGULAR)
                .setText(winCount).setSize(31, 5).setPosition(0, 26)
                .setAlignment(Kaisa.Text.ANCHOR_UPPER_RIGHT);
        } else {
            var ddockNumber = currentScreen - 3;
            gm.buildDDockScreenElement(ddockNumber, screen);
        }
    }
}
