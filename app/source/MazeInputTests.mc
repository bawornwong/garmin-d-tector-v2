import Toybox.Lang;
import Toybox.Test;

(:test)
function mazeTapMovesOnceAndHoldRepeats(logger as Test.Logger) as Boolean {
    var data = new GameData();
    data.load();
    var db = new Database(data);
    db.load();
    var format = new SaveFormat(data);
    var rec = format.createDefault("MAZE");
    rec.gameChar = Kaisa.CHAR_TAKUYA;
    var gm = new GameManager(data, db, new SavedGame(format, 0, rec));
    gm.audioMgr.muted = true;
    var app = new Maze(gm, gm.logicMgr, new ContainerBuilder());
    app.currentScreen = 1;
    for (var i = 0; i < app.MAZE_WIDTH * app.MAZE_HEIGHT; i += 1) {
        app.cellPaths.add(0);
    }
    app.cellPaths[0] = app.CELL_PATH_RIGHT;
    app.cellPaths[1] = app.CELL_PATH_RIGHT;

    // A touch sends DOWN and UP before the next runner frame.
    app.inputRightDown();
    app.inputRightUp();
    if (app.playerX != 0 || app.playerY != 0) { return false; }
    gm.runner.advance(500.0d);
    if (app.playerX != 0) { return false; }

    app.inputRightDown();
    if (app.playerX != 1) { return false; }
    gm.runner.advance(100.0d);
    if (app.playerX != 1) { return false; }
    // The routine's 0.15-second Float is slightly above 150 ms when the
    // scheduler promotes it to Double. Check either side of that boundary.
    gm.runner.advance(49.0d);
    if (app.playerX != 1) { return false; }
    gm.runner.advance(2.0d);
    if (app.playerX != 2) { return false; }
    app.inputRightUp();
    gm.runner.advance(500.0d);
    if (app.playerX != 2) { return false; }

    // The other touch zones use the same immediate step in all directions.
    app.playerX = 1;
    app.playerY = 1;
    app.cellPaths[16] = app.CELL_PATH_LEFT | app.CELL_PATH_UP | app.CELL_PATH_DOWN;
    app.inputLeftDown();
    app.inputLeftUp();
    if (app.playerX != 0) { return false; }
    app.playerX = 1;
    app.inputADown();
    app.inputAUp();
    if (app.playerY != 0) { return false; }
    app.playerY = 1;
    app.inputBDown();
    app.inputBUp();
    return app.playerY == 2;
}
