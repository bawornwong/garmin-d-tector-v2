import Toybox.Lang;
import Toybox.Test;

// Inspect the losing energy after the actual battle collision has transformed
// it, before the winner's third motion step disposes it.
function losingEnergyBreakIsVisible(friendlyAttack as Number,
                                    enemyAttack as Number,
                                    winner as Number) as Boolean {
    var data = new GameData();
    data.load();
    var db = new Database(data);
    db.load();
    var format = new SaveFormat(data);
    var rec = format.createDefault("COLLISION");
    rec.gameChar = Kaisa.CHAR_TAKUYA;
    var gm = new GameManager(data, db, new SavedGame(format, 0, rec));
    gm.audioMgr.muted = true;
    var root = new ContainerBuilder();
    var screenMgr = new ScreenManager(gm, root);
    gm.attachScreenManager(screenMgr);
    screenMgr.animParent = Kaisa.ScreenBuilder.buildContainer("Anim Parent", root, false)
        .setSize(32, 32);
    var sprites = [null, null, [3, 0, 0, 24, 24], [3, 0, 0, 24, 24], null];
    var collision = new AttackCollision(gm, friendlyAttack, sprites,
                                        enemyAttack, sprites, winner);
    gm.runner.start(collision);
    gm.runner.advance(620.0d);

    var loser = (winner == 0) ? collision.sbEnemyAttack : collision.sbFriendlyAttack;
    return loser != null && loser.parent != null
        && loser.sprite == Kaisa.Sprites.BATTLE_ATTACK_COLLISION
        && loser.width == 7 && loser.x >= 0 && loser.x + loser.width <= 32;
}

(:test)
function enemyEnergyBreaksWhenPlayerEnergyWins(logger as Test.Logger) as Boolean {
    return losingEnergyBreakIsVisible(0, 0, 0);
}

(:test)
function enemyEnergyBreaksWhenPlayerCrushWins(logger as Test.Logger) as Boolean {
    return losingEnergyBreakIsVisible(1, 0, 0);
}

(:test)
function playerEnergyBreaksWhenEnemyEnergyWins(logger as Test.Logger) as Boolean {
    return losingEnergyBreakIsVisible(0, 0, 1);
}

(:test)
function playerEnergyBreaksWhenEnemyCrushWins(logger as Test.Logger) as Boolean {
    return losingEnergyBreakIsVisible(0, 1, 1);
}
