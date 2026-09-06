import Toybox.Lang;

// port of Logic/Apps/Games/SpeedRunner.cs
//
// A rocket in one of three lanes, rows of asteroids sliding down at four
// speeds, two crashes allowed, then the finish line. Hold a side to move.
//
// The game's clock is `InvokeRepeating("CustomUpdate", 0f, 0.005f)` -- 200 Hz,
// ten times the port's frame rate. It is translated as a routine that waits
// THIS_DELTA_TIME, so ADR 5's scheduler runs it ten times inside each 50 ms
// frame: the rows advance at exactly the original's rate and the display
// samples the result at 20 fps, which is the trade ADR 5 exists to make.
class SpeedRunner extends DigiviceApp {
    const THIS_DELTA_TIME = 0.005;
    const ROW_COUNT = 70;
    const HAS_FIRST = 0x01;      // an asteroid in the first lane
    const HAS_SECOND = 0x02;
    const HAS_THIRD = 0x04;

    var currentScreen as Number = 0;    // 1: end game
    var rowData as Array<Number> = [];
    // "The times it takes for a row to travel 38 pixels." The original's
    // commented-out alternatives (the real D-Tector's 2.85..0.8, and a
    // "suicide" set) are left in the source, not here.
    var speeds as Array<Float> = [2.0, 1.5, 1.0, 0.75];

    var gameStarted as Boolean = false;
    var rocketPosition as Number = 1;   // 0, 1, 2
    var rowsBeaten as Number = 0;
    var crashes as Number = 0;

    var rocket as SpriteBuilder?;
    var visualRows as Array<ContainerBuilder> = [];
    var finishRow as ContainerBuilder?;
    var speedMarks as Array<SpriteBuilder> = [];

    var timeUntilMovement as Float = 0.0;
    var currentRow as Number = -1;
    var currentSpeed as Number = 0;
    var rowY as Array<Number> = [-6, -6];
    var finishY as Number = -32;
    var lockControls as Boolean = false;
    var lastDirectionTapped as Number = Kaisa.DIR_NONE;

    var _fibers as Array<Fiber> = [];

    function initialize(gmIn as GameManager, controllerIn, parent as ScreenElement) {
        DigiviceApp.initialize(gmIn, controllerIn, parent);
    }

    // --- Input ---

    function inputA() as Void {
        if (currentScreen == 1) {
            gm.audioMgr.playButtonA();
            submitScoreAndClose();
        }
    }

    function inputB() as Void {
        if (currentScreen == 0) {
            gm.audioMgr.playButtonB();
            closeApp(Kaisa.SCREEN_GAMES_TRAVEL_MENU);
        } else if (currentScreen == 1) {
            gm.audioMgr.playButtonA();
            submitScoreAndClose();
        }
    }

    function inputLeftDown() as Void { lastDirectionTapped = Kaisa.DIR_LEFT; }
    function inputRightDown() as Void { lastDirectionTapped = Kaisa.DIR_RIGHT; }

    function inputLeftUp() as Void {
        if (lastDirectionTapped == Kaisa.DIR_LEFT) { lastDirectionTapped = Kaisa.DIR_NONE; }
    }

    function inputRightUp() as Void {
        if (lastDirectionTapped == Kaisa.DIR_RIGHT) { lastDirectionTapped = Kaisa.DIR_NONE; }
    }

    function startApp() as Void {
        generateLevel();

        Kaisa.ScreenBuilder.buildRectangle("Line", screen).setSize(1, 32).setPosition(6, 0);
        rocket = Kaisa.ScreenBuilder.buildSprite("Rocket", screen)
            .setSize(8, 8).setPosition(15, 32).setSprite(Kaisa.Sprites.SPEED_RUNNER_ROCKET);
        track(gm.runner.start(new SRSpawnRocket(self, 0.0)));

        visualRows = [];
        for (var i = 0; i < 2; i += 1) {
            var row = Kaisa.ScreenBuilder.buildContainer("Row" + i, screen, true)
                .setSize(24, 6).setPosition(7, -6);
            for (var j = 0; j < 3; j += 1) {
                Kaisa.ScreenBuilder.buildSprite("Asteroid" + j, row)
                    .setSize(7, 6).setPosition(j * 8, 0)
                    .setSprite(Kaisa.Sprites.SPEED_RUNNER_ROCKET_ASTEROID);
            }
            visualRows.add(row);
        }

        finishRow = Kaisa.ScreenBuilder.buildContainer("FinishRow", screen, true)
            .setSize(25, 32).setPosition(7, -32);
        for (var i = 0; i < 2; i += 1) {
            Kaisa.ScreenBuilder.buildSprite("FinishLine" + i, finishRow)
                .setSize(6, 32).setPosition(1 + (i * 17), 0)
                .setSprite(Kaisa.Sprites.SPEED_RUNNER_ROCKET_FINISH);
        }

        speedMarks = [];
        for (var i = 0; i < 4; i += 1) {
            var mark = Kaisa.ScreenBuilder.buildSprite("SpeedMark" + i, screen)
                .setSize(3, 5).setPosition(2, 26 - (i * 6))
                .setSprite(Kaisa.Sprites.SPEED_RUNNER_ROCKET_SPEED_MARK);
            mark.setActive(false);
            speedMarks.add(mark);
        }

        track(gm.runner.start(new SRCustomUpdate(self)));
    }

    // SpeedRunner overrides CloseApp with StopAllCoroutines(); the port tracks
    // its own fibers rather than stopping every fiber in the runner, since the
    // runner is shared with the host's overlays.
    function track(f as Fiber) as Void {
        _fibers.add(f);
    }

    function stopAll() as Void {
        for (var i = 0; i < _fibers.size(); i += 1) {
            gm.runner.stop(_fibers[i]);
        }
        _fibers = [];
    }

    function closeApp(gotoMenu as Number) as Void {
        stopAll();
        DigiviceApp.closeApp(gotoMenu);
    }

    function dispose() as Void {
        stopAll();
        DigiviceApp.dispose();
    }

    // The body of CustomUpdate, one 5 ms step.
    function customUpdate() as Void {
        if (!gameStarted) { return; }

        if (!lockControls) {
            // Set the position of the rocket wherever the player is tapping.
            if (lastDirectionTapped == Kaisa.DIR_LEFT) { rocketPosition = 0; }
            else if (lastDirectionTapped == Kaisa.DIR_RIGHT) { rocketPosition = 2; }
            else { rocketPosition = 1; }
        }

        rocket.setPosition(8 * (rocketPosition + 1) - 1, rocket.y);

        // Update the speed after x rows have been beaten THIS ROUND.
        if (currentSpeed != 3) {
            var rowsBeatenThisRound = rowsBeaten - (ROW_COUNT - rowData.size());
            if (rowsBeatenThisRound == 0) {
                speedMarks[0].setActive(true);
            } else if (rowsBeatenThisRound == 1) {
                speedMarks[1].setActive(true);
                currentSpeed = 1;
            } else if (rowsBeatenThisRound == 3) {
                speedMarks[2].setActive(true);
                currentSpeed = 2;
            } else if (rowsBeatenThisRound == 6) {
                speedMarks[3].setActive(true);
                currentSpeed = 3;
            }
        }

        // If no row has been generated yet, or the latest row reached y = 16.
        if (currentRow == -1
                || (currentRow < rowData.size() && rowY[visualRowIndex(currentRow)] == 16)) {
            currentRow += 1;
            if (currentRow < rowData.size()) {
                rowY[visualRowIndex(currentRow)] = -6;
                enableAsteroids(currentRow);
            }
        }

        // The part of the update that only triggers on a fixed time.
        timeUntilMovement += THIS_DELTA_TIME;
        if (timeUntilMovement <= (speeds[currentSpeed] / 38)) { return; }

        timeUntilMovement = 0.0;
        rowY[0] += 1;
        // If we aren't in row 0 (because else this would apply to row -1).
        if (currentRow > 0) {
            rowY[1] += 1;
            if (currentRow < rowData.size()) {
                if (rowY[visualRowIndex(currentRow - 1)] == 31) {
                    gm.audioMgr.playSound("speedRunner_Asteroid");
                    rowsBeaten += 1;
                }
            }
        }

        // If the current row is the finish line, and it has not reached y = 0.
        if (currentRow == rowData.size() && finishY < 0) {
            finishY += 1;
            finishRow.setPosition(7, finishY);
            if (finishY == 0) {                     // win the game
                gm.audioMgr.playSound("speedRunner_Finish");
                rowsBeaten += 1;
                lockControls = true;
                track(gm.runner.start(new SRElevateRocket(self)));
            }
        }

        if (currentRow > 0 && currentRow < rowData.size()) {
            var lowerRowY = rowY[visualRowIndex(currentRow - 1)];
            // If the lower row is where it could crash with the rocket.
            if (lowerRowY >= 20 && lowerRowY <= 29) {
                if (isAsteroidAtPos(currentRow - 1, rocketPosition)) {
                    crash();
                    crashRocket();
                }
            }
        } else if (currentRow == rowData.size()) {
            // The finish row colliding gives the player no second chance.
            if (finishY >= -6 && finishY < -1) {
                if (rocketPosition != 1) {
                    crash();
                    track(gm.runner.start(new SRLoseGame(self)));
                }
            }
        }

        visualRows[0].setPosition(7, rowY[0]);
        visualRows[1].setPosition(7, rowY[1]);
    }

    function crash() as Void {
        gm.audioMgr.playSound("speedRunner_Crash");
        rocket.setSprite(Kaisa.Sprites.SPEED_RUNNER_ROCKET_EXPLOSION);
        gameStarted = false;
        rowY[0] = -6;
        rowY[1] = -6;
    }

    // The original's local function _CrashRocket.
    function crashRocket() as Void {
        if (crashes < 2 && currentRow < rowData.size()) {
            track(gm.runner.start(new SRSpawnRocket(self, 0.5)));
            rowsBeaten += 1;
            crashes += 1;
            rowData = rowData.slice(currentRow, null);
            currentRow = -1;
            currentSpeed = 0;
            for (var i = 0; i < speedMarks.size(); i += 1) {
                speedMarks[i].setActive(false);
            }
        } else {
            track(gm.runner.start(new SRLoseGame(self)));
        }
    }

    function visualRowIndex(logicRow as Number) as Number {
        return logicRow % 2;
    }

    function enableAsteroids(logicRow as Number) as Void {
        var visualRow = visualRows[visualRowIndex(logicRow)];
        for (var i = 0; i < 3; i += 1) {
            visualRow.setChildActive(i, isAsteroidAtPos(logicRow, i));
        }
    }

    function isAsteroidAtPos(logicRow as Number, posIndex as Number) as Boolean {
        if (posIndex == 0) { return (rowData[logicRow] & HAS_FIRST) == HAS_FIRST; }
        if (posIndex == 1) { return (rowData[logicRow] & HAS_SECOND) == HAS_SECOND; }
        if (posIndex == 2) { return (rowData[logicRow] & HAS_THIRD) == HAS_THIRD; }
        return false;
    }

    // "Add two asteroids to each row. A third of the times, the second
    // asteroid will be the same as the first and that line will only contain
    // one." A row is redrawn if it repeats the previous one.
    function generateLevel() as Void {
        rowData = [] as Array<Number>;
        for (var i = 0; i < ROW_COUNT; i += 1) {
            rowData.add(0);
            var again = true;
            while (again) {
                rowData[i] = 0;
                for (var attempt = 0; attempt < 2; attempt += 1) {
                    var pick = Kaisa.Rand.rangeInt(0, 3);
                    if (pick == 0) { rowData[i] |= HAS_FIRST; }
                    else if (pick == 1) { rowData[i] |= HAS_SECOND; }
                    else { rowData[i] |= HAS_THIRD; }
                }
                again = (i > 0 && rowData[i] == rowData[i - 1]);
            }
        }
    }

    function calculateScore() as Number {
        var score = (rowsBeaten * 6) - (80 * crashes);
        return (score > 0) ? score : 0;
    }

    function submitScoreAndClose() as Void {
        gm.submitGameScore(calculateScore());
        closeApp(Kaisa.SCREEN_GAMES_TRAVEL_MENU);
    }
}

// SpeedRunner's 200 Hz clock as a routine (see the class comment).
class SRCustomUpdate extends Routine {
    var app as SpeedRunner;

    function initialize(appIn as SpeedRunner) {
        Routine.initialize();
        app = appIn;
    }

    function step(rt as Fiber) as Float {
        app.customUpdate();
        return app.THIS_DELTA_TIME;
    }
}

// port of SpeedRunner.IASpawnRocket
class SRSpawnRocket extends Routine {
    var app as SpeedRunner;
    var delay as Float;
    var tbStart as TextBoxBuilder?;
    var i as Number = 0;

    function initialize(appIn as SpeedRunner, delayIn as Float) {
        Routine.initialize();
        app = appIn;
        delay = delayIn;
    }

    function step(rt as Fiber) as Float {
        switch (pc) {
            case 0:
                pc = 1;
                return delay;
            case 1:
                app.gm.audioMgr.playSound("speedRunner_Start");
                app.rocket.setPosition(15, 32);
                app.rocket.setSprite(Kaisa.Sprites.SPEED_RUNNER_ROCKET);
                i = 0;
                pc = 2;
                return 0.0;
            case 2:                                 // for (i = 0; i < 8; i++)
                if (i >= 8) { pc = 4; return 0.0; }
                pc = 3;
                return 1.0 / 8;
            case 3:
                app.rocket.move(Kaisa.DIR_UP, 1);
                i += 1;
                pc = 2;
                return 0.0;
            case 4:
                tbStart = Kaisa.ScreenBuilder.buildTextBox("Start", app.screen, Kaisa.Font.SMALL)
                    .setText("START").setSize(24, 5).setPosition(9, 8);
                pc = 5;
                return 0.5;
            case 5:
                tbStart.setActive(false);
                pc = 6;
                return 0.5;
            case 6:
                tbStart.setActive(true);
                pc = 7;
                return 1.0;
            case 7:
                tbStart.setActive(false);
                app.gameStarted = true;
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of SpeedRunner.IALoseGame
class SRLoseGame extends Routine {
    var app as SpeedRunner;

    function initialize(appIn as SpeedRunner) {
        Routine.initialize();
        app = appIn;
    }

    function step(rt as Fiber) as Float {
        switch (pc) {
            case 0:
                app.gm.lockInput();
                for (var i = 0; i < app.speedMarks.size(); i += 1) {
                    app.speedMarks[i].setActive(false);
                }
                app.finishRow.setActive(false);
                pc = 1;
                return 0.5;
            case 1:
                Kaisa.ScreenBuilder.buildTextBox("Game Over", app.screen, Kaisa.Font.SMALL)
                    .setText("GAME\nOVER").setSize(24, 11).setPosition(9, 8);
                pc = 2;
                return 0.5;
            case 2:
                app.currentScreen = 1;
                app.gm.unlockInput();
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of SpeedRunner.IAElevateRocket -- ends in a forever loop blinking the
// GOAL! sign, which the app's own disposal stops.
class SRElevateRocket extends Routine {
    var app as SpeedRunner;
    var tbGoal as TextBoxBuilder?;
    var i as Number = 0;

    function initialize(appIn as SpeedRunner) {
        Routine.initialize();
        app = appIn;
    }

    function step(rt as Fiber) as Float {
        switch (pc) {
            case 0:
                app.gm.lockInput();
                i = 0;
                pc = 1;
                return 0.0;
            case 1:                                 // for (i = 0; i < 32; i++)
                if (i >= 32) { pc = 3; return 0.0; }
                app.rocket.move(Kaisa.DIR_UP, 1);
                pc = 2;
                return 1.5 / 32;
            case 2:
                i += 1;
                pc = 1;
                return 0.0;
            case 3:
                for (var k = 0; k < app.speedMarks.size(); k += 1) {
                    app.speedMarks[k].setActive(false);
                }
                app.finishRow.setActive(false);
                pc = 4;
                return 0.5;
            case 4:
                tbGoal = Kaisa.ScreenBuilder.buildTextBox("Goal", app.screen, Kaisa.Font.SMALL)
                    .setText("GOAL!").setSize(24, 5).setPosition(9, 8);
                pc = 5;
                return 0.5;
            case 5:
                app.currentScreen = 1;
                app.gm.unlockInput();
                pc = 6;
                return 0.0;
            case 6:                                 // while (true)
                tbGoal.setActive(!tbGoal.active);
                return 0.5;
        }
        return Routine.DONE;
    }
}
