import Toybox.Lang;
import Toybox.Test;

function evolutionPoseRefMatches(actual as Array<Number>?, expected as Array<Number>?) as Boolean {
    if (actual == null || expected == null) { return false; }
    for (var i = 0; i < 5; i += 1) {
        if (actual[i] != expected[i]) { return false; }
    }
    return true;
}

function regularEvolutionPoseFixture() as Array {
    var data = new GameData();
    data.load();
    var db = new Database(data);
    db.load();
    var format = new SaveFormat(data);
    var rec = format.createDefault("EVOLVE");
    rec.gameChar = Kaisa.CHAR_TAKUYA;
    var gm = new GameManager(data, db, new SavedGame(format, 0, rec));
    gm.audioMgr.muted = true;
    var screenMgr = new ScreenManager(gm, new ContainerBuilder());
    gm.attachScreenManager(screenMgr);
    var target = -1;
    for (var i = 0; i < data.digimonCount(); i += 1) {
        var base = data.spriteRef(i, data.ACTION_BASE);
        var crush = data.spriteRef(i, data.ACTION_CR);
        if (base != null && crush != null
                && !evolutionPoseRefMatches(base, crush)) {
            target = i;
            break;
        }
    }
    return [gm, screenMgr, target];
}

(:test)
function regularEvolutionSuccessShowsDigimonPose(logger as Test.Logger) as Boolean {
    var fixture = regularEvolutionPoseFixture();
    var gm = fixture[0] as GameManager;
    var screenMgr = fixture[1] as ScreenManager;
    var target = fixture[2] as Number;
    if (target < 0) { return false; }
    var animation = new RegularEvolution(gm, Kaisa.WellKnown.DEFAULT_DIGIMON, target);
    gm.enqueueAnimation(animation);
    gm.runner.advance(4850.0d);
    screenMgr.updateQueue();
    var poseStarted = screenMgr.playingAnimations
        && animation.sbDigimon != null && animation.sbDigimon.active
        && evolutionPoseRefMatches(animation.sbDigimon.sprite,
                                   gm.digimonSprite(target, gm.data.ACTION_CR));
    gm.runner.advance(600.0d);
    screenMgr.updateQueue();
    var poseHeld = screenMgr.playingAnimations
        && evolutionPoseRefMatches(animation.sbDigimon.sprite,
                                   gm.digimonSprite(target, gm.data.ACTION_CR));
    gm.runner.advance(150.0d);
    screenMgr.updateQueue();
    var returnedToBase = screenMgr.playingAnimations
        && evolutionPoseRefMatches(animation.sbDigimon.sprite,
                                   gm.digimonSprite(target, gm.data.ACTION_BASE));
    gm.runner.advance(150.0d);
    screenMgr.updateQueue();
    return poseStarted && poseHeld && returnedToBase && !screenMgr.playingAnimations;
}

(:test)
function regularEvolutionFailureDoesNotShowPose(logger as Test.Logger) as Boolean {
    var fixture = regularEvolutionPoseFixture();
    var gm = fixture[0] as GameManager;
    var screenMgr = fixture[1] as ScreenManager;
    var target = fixture[2] as Number;
    if (target < 0) { return false; }
    var animation = new RegularEvolution(gm, target, target);
    gm.enqueueAnimation(animation);
    gm.runner.advance(4850.0d);
    screenMgr.updateQueue();

    return !screenMgr.playingAnimations
        && evolutionPoseRefMatches(animation.sbDigimon.sprite,
                                   gm.digimonSprite(target, gm.data.ACTION_BASE));
}
