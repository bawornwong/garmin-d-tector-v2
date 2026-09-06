import Toybox.Lang;

// port of Logic/Apps/Games/DigiHunter.cs
//
// A three-by-three grid of faces appears and disappears for sixty seconds.
// Left moves the row cursor, Right the column cursor, A hits whatever is
// under them: a white face scores, a black one costs. Faces appear faster as
// the clock runs down.
//
// The 3x3 int[,] becomes a flat nine-element array indexed y * 3 + x, which
// is the same layout Monkey C would give a nested array without the extra
// object per row.
class DigiHunter extends DigiviceApp {
    const STARTING_TIME = 60;
    const GRID = 3;

    var gameStarted as Boolean = false;

    var score as Number = 0;
    var timeRemaining as Number = 60;      // -1 playing end sound, -2 ended
    var tbTime as TextBoxBuilder?;

    var playerX as Number = 0;
    var playerY as Number = 0;
    var sbArrows as Array<SpriteBuilder> = [];
    var faces as Array<Number> = [];       // 0 empty, 1 white, 2 black, -1 dying
    var sbFaces as Array<SpriteBuilder> = [];

    function initialize(gmIn as GameManager, controllerIn, parent as ScreenElement) {
        DigiviceApp.initialize(gmIn, controllerIn, parent);
    }

    function at(y as Number, x as Number) as Number {
        return y * GRID + x;
    }

    function inputA() as Void {
        if (timeRemaining >= 0) {
            attemptDestroy(playerY, playerX);
        } else if (timeRemaining == -2) {
            gm.audioMgr.playButtonA();
            submitScoreAndClose();
        }
    }

    function inputB() as Void {
        if (timeRemaining > 0) {
            gm.audioMgr.playButtonB();
            closeApp(Kaisa.SCREEN_GAMES_TRAVEL_MENU);
        } else if (timeRemaining == -2) {
            // The original plays the A sound here, not the B one.
            gm.audioMgr.playButtonA();
            submitScoreAndClose();
        }
    }

    function inputLeft() as Void {
        if (timeRemaining >= 0) { moveY(); }
    }

    function inputRight() as Void {
        if (timeRemaining >= 0) { moveX(); }
    }

    function startApp() as Void {
        // Animations.StartAppDigiHunter(mark => gameStarted = mark) is the
        // intro: a loading bar, the arrows flashing, then the faces. It is not
        // converted yet, and its only effect on the game is the callback that
        // starts the clock -- so the clock starts immediately here, and the
        // game is playable while the animation waits to be written.
        gm.enqueueAnimation(null);
        gameStarted = true;

        Kaisa.ScreenBuilder.buildTextBox("Time", screen, Kaisa.Font.SMALL)
            .setText("TIME").setSize(18, 5).setPosition(1, 0);
        tbTime = Kaisa.ScreenBuilder.buildTextBox("TimeCount", screen, Kaisa.Font.SMALL)
            .setText(timeRemaining.toString()).setSize(10, 5).setPosition(22, 0);

        sbArrows = [
            Kaisa.ScreenBuilder.buildSprite("Y-Arrow", screen)
                .setSize(3, 6).setPosition(2, 9).setSprite(Kaisa.Sprites.DIGI_HUNTER_ARROWS[0]),
            Kaisa.ScreenBuilder.buildSprite("X-Arrow", screen)
                .setSize(6, 3).setPosition(6, 5).setSprite(Kaisa.Sprites.DIGI_HUNTER_ARROWS[1])
        ];

        faces = [];
        sbFaces = [];
        for (var y = 0; y < GRID; y += 1) {
            for (var x = 0; x < GRID; x += 1) {
                faces.add(0);
                sbFaces.add(Kaisa.ScreenBuilder.buildSprite("Face", screen)
                    .setSize(8, 8).setPosition(5 + (x * 8), 8 + (y * 8)).setSprite(null));
            }
        }

        gm.runner.start(new DigiHunterCountDown(self));
        gm.runner.start(new DigiHunterGenerateFaces(self));
    }

    function moveX() as Void {
        playerX = Kaisa.MathExt.circularAdd(playerX, 1, 2, 0);
        sbArrows[1].setPosition(6 + (playerX * 8), 5);
    }

    function moveY() as Void {
        playerY = Kaisa.MathExt.circularAdd(playerY, 1, 2, 0);
        sbArrows[0].setPosition(2, 9 + (playerY * 8));
    }

    function attemptDestroy(y as Number, x as Number) as Void {
        var face = faces[at(y, x)];
        if (face < 1) {
            gm.audioMgr.playButtonA();
        } else if (face == 1) {
            gm.audioMgr.playSound("speedRunner_Asteroid");
            score += 1;
            gm.runner.start(new DigiHunterDestroyFace(self, y, x));
        } else if (face == 2) {
            gm.audioMgr.playSound("speedRunner_Crash");
            score -= 1;
            gm.runner.start(new DigiHunterDestroyFace(self, y, x));
        }
    }

    function submitScoreAndClose() as Void {
        gm.submitGameScore(calculateScore());
        closeApp(Kaisa.SCREEN_GAMES_TRAVEL_MENU);
    }

    function calculateScore() as Number {
        return (score > 0) ? score * 15 : 0;
    }
}

// port of DigiHunter.CountDown
class DigiHunterCountDown extends Routine {
    var app as DigiHunter;

    function initialize(appIn as DigiHunter) {
        Routine.initialize();
        app = appIn;
    }

    function step(rt as Fiber) as Float {
        switch (pc) {
            case 0:                                 // while (!gameStarted)
                if (!app.gameStarted) { return 0.05; }
                pc = 1;
                return 1.0;
            case 1:                                 // while (timeRemaining > 0)
                if (app.timeRemaining <= 0) { pc = 2; return 0.0; }
                app.timeRemaining -= 1;
                app.tbTime.setText(app.timeRemaining.toString());
                return 1.0;
            case 2:
                app.timeRemaining = -1;
                app.gm.audioMgr.playSound("speedRunner_Finish");
                pc = 3;
                return 1.5;
            case 3:
                app.timeRemaining = -2;
                for (var i = 0; i < app.sbFaces.size(); i += 1) {
                    app.sbFaces[i].dispose();
                }
                Kaisa.ScreenBuilder.buildTextBox("End", app.screen, Kaisa.Font.SMALL)
                    .setText("END").setPosition(6, 17);
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of DigiHunter.GenerateFaces -- faces appear at a rate that rises as the
// clock falls, each one scheduling its own disappearance.
class DigiHunterGenerateFaces extends Routine {
    const BASE_MIN = 0.75;
    const BASE_MAX = 1.5;

    var app as DigiHunter;

    function initialize(appIn as DigiHunter) {
        Routine.initialize();
        app = appIn;
    }

    function step(rt as Fiber) as Float {
        switch (pc) {
            case 0:                                 // while (!gameStarted)
                if (!app.gameStarted) { return 0.05; }
                pc = 1;
                return 0.0;
            case 1:                                 // while (timeRemaining > 0)
                if (app.timeRemaining <= 0) { return Routine.DONE; }

                var x = Kaisa.Rand.rangeInt(0, 3);
                var y = Kaisa.Rand.rangeInt(0, 3);

                var elapsed = (app.STARTING_TIME - app.timeRemaining).toFloat()
                    / app.STARTING_TIME;
                var nextMin = BASE_MIN - ((0.75 * BASE_MIN) * elapsed);
                var nextMax = BASE_MAX - ((0.75 * BASE_MAX) * elapsed);

                if (app.faces[app.at(y, x)] == 0) {
                    var face = Kaisa.Rand.rangeInt(1, 3);       // 1 white, 2 black
                    app.faces[app.at(y, x)] = face;
                    app.sbFaces[app.at(y, x)].setSprite(
                        Kaisa.Sprites.DIGI_HUNTER_FACES[face - 1]);
                    app.gm.runner.start(new DigiHunterDestroyFaceAfterDelay(
                        app, y, x, Kaisa.Rand.rangeFloat(BASE_MIN * 2.0, BASE_MAX * 2.0)));
                }

                return Kaisa.Rand.rangeFloat(nextMin, nextMax);
        }
        return Routine.DONE;
    }
}

// port of DigiHunter.DestroyFaceAfterDelay -- polls in 0.05 s steps so that a
// face the player already hit stops its own timer.
class DigiHunterDestroyFaceAfterDelay extends Routine {
    var app as DigiHunter;
    var y as Number;
    var x as Number;
    var delay as Float;
    var accDelay as Float = 0.0;

    function initialize(appIn as DigiHunter, yIn as Number, xIn as Number, delayIn as Float) {
        Routine.initialize();
        app = appIn;
        y = yIn;
        x = xIn;
        delay = delayIn;
    }

    function step(rt as Fiber) as Float {
        switch (pc) {
            case 0:                                 // while (accDelay < delay)
                if (accDelay >= delay) { pc = 1; return 0.0; }
                if (app.faces[app.at(y, x)] < 1) { return Routine.DONE; }
                accDelay += 0.05;
                return 0.05;
            case 1:
                app.faces[app.at(y, x)] = 0;
                app.sbFaces[app.at(y, x)].setSprite(null);
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of DigiHunter.DestroyFace
class DigiHunterDestroyFace extends Routine {
    var app as DigiHunter;
    var y as Number;
    var x as Number;

    function initialize(appIn as DigiHunter, yIn as Number, xIn as Number) {
        Routine.initialize();
        app = appIn;
        y = yIn;
        x = xIn;
    }

    function step(rt as Fiber) as Float {
        switch (pc) {
            case 0:
                app.faces[app.at(y, x)] = -1;
                app.sbFaces[app.at(y, x)].setSprite(Kaisa.Sprites.DIGI_HUNTER_EXPLOSION);
                pc = 1;
                return 0.35;
            case 1:
                app.sbFaces[app.at(y, x)].setSprite(null);
                app.faces[app.at(y, x)] = 0;
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}
