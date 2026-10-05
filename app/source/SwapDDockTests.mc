import Toybox.Lang;
import Toybox.Test;

(:test)
function assigningDigimonWithoutCrushArtKeepsFinalDockVisible(logger as Test.Logger) as Boolean {
    var data = new GameData();
    data.load();
    var db = new Database(data);
    db.load();
    var format = new SaveFormat(data);
    var rec = format.createDefault("DOCK");
    rec.gameChar = Kaisa.CHAR_TAKUYA;
    var gm = new GameManager(data, db, new SavedGame(format, 0, rec));
    gm.audioMgr.muted = true;
    var root = new ContainerBuilder();
    var screenMgr = new ScreenManager(gm, root);
    gm.attachScreenManager(screenMgr);

    var target = -1;
    for (var i = 0; i < data.digimonCount(); i += 1) {
        if (data.spriteRef(i, data.ACTION_BASE) != null
                && data.spriteRef(i, data.ACTION_CR) == null) {
            target = i;
            break;
        }
    }
    if (target < 0) { return false; }

    var app = new DatabaseApp(gm, gm.logicMgr, screenMgr.screenDisplay);
    app.galleryList = [target];
    app.galleryIndex = 0;
    app.pageDigimon = db.getDigimon(target);
    app.currentScreen = app.SCREEN_DDOCK_DISPLAY;
    app.ddockIndex = 0;
    app.chooseDDock();
    gm.runner.advance(6900.0d);
    screenMgr.updateQueue();

    var anim = screenMgr.animParent;
    if (!screenMgr.playingAnimations || anim == null || anim.children.size() < 2) {
        return false;
    }
    var dock = anim.children[1];
    if (dock.children.size() == 0 || dock.children[0].children.size() == 0) {
        return false;
    }
    var digimon = dock.children[0].children[0] as SpriteBuilder;
    var expected = gm.digimonSprite(target, data.ACTION_CR);
    if (!digimon.active || digimon.sprite == null || expected == null) { return false; }
    for (var part = 0; part < 5; part += 1) {
        if (digimon.sprite[part] != expected[part]) { return false; }
    }
    return true;
}
