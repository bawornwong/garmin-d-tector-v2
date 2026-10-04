import Toybox.Lang;
import Toybox.Test;

(:test)
function sourceNotesDecodeOnFirstUse(logger as Test.Logger) as Boolean {
    Kaisa.Sounds._bytes = null;
    var levelUp = Kaisa.Sounds.indexOf("levelUp");
    var note = Kaisa.Sounds.noteAt(levelUp, 1);
    return note[0] == 3068 && note[1] == 110;
}

(:test)
function everyGameEffectHasWatchCue(logger as Test.Logger) as Boolean {
    var audio = new AudioManager(new Runner());
    var covered = 0;
    for (var i = 0; i < Kaisa.Sounds.NAMES.size(); i += 1) {
        var name = Kaisa.Sounds.NAMES[i];
        if (name.equals("buttonA") || name.equals("buttonB")) {
            if (audio.cueFor(name) != -1 || audio.vibeFor(name) != null) { return false; }
            continue;
        }
        var cue = audio.cueFor(name);
        var vibe = audio.vibeFor(name);
        var score = audio.scoreFor(name);
        if (cue < audio.CUE_ACTION || cue > audio.CUE_ALERT
                || vibe == null || vibe.size() == 0
                || score.size() != 1 || score[0].size() != 2
                || score[0][1] != 0) { return false; }
        var tone = score[0][0];
        if (tone != Toybox.Attention.TONE_START
                && tone != Toybox.Attention.TONE_STOP
                && tone != Toybox.Attention.TONE_MSG
                && tone != Toybox.Attention.TONE_SUCCESS
                && tone != Toybox.Attention.TONE_FAILURE) { return false; }
        covered += 1;
    }
    return covered == 38 && audio.cueFor("missingEffect") == -1
        && audio.scoreFor("charHappy")[0][0] == Toybox.Attention.TONE_SUCCESS
        && audio.scoreFor("charSad")[0][0] == Toybox.Attention.TONE_FAILURE
        && audio.scoreFor("buttonA").size() == 0
        && audio.scoreFor("buttonB").size() == 0;
}

(:test)
function stoppingSceneSoundCancelsRemainingSourceNotes(logger as Test.Logger) as Boolean {
    var runner = new Runner();
    var audio = new AudioManager(runner);
    audio._toneFiber = runner.startSilent(
        new SourceSoundRoutine(Kaisa.Sounds.indexOf("levelUp")));
    if (runner.fibers.size() != 1) { return false; }
    audio.stopSound();
    return runner.fibers.size() == 0 && audio._toneFiber == null;
}

(:test)
function doubleBackWindow(logger as Test.Logger) as Boolean {
    var view = new DTectorView();
    if (view.countBackPress(1000, true)) { return false; }
    if (!view.countBackPress(2500, true)) { return false; }
    if (view.countBackPress(3000, true)) { return false; }
    if (view.countBackPress(4501, true)) { return false; }
    if (!view.countBackPress(4550, true)) { return false; }
    if (view.countBackPress(5000, true)) { return false; }
    if (view.countBackPress(5100, false)) { return false; }
    return !view.countBackPress(5200, true)
        && view.countBackPress(5250, true);
}

(:test)
function doubleBackOnlyOnIdleCharacter(logger as Test.Logger) as Boolean {
    var data = new GameData();
    data.load();
    var db = new Database(data);
    db.load();
    var format = new SaveFormat(data);
    var record = format.createDefault("WALKER");
    record.currentDistance = 300;
    var saved = new SavedGame(format, 0, record);
    var gm = new GameManager(data, db, saved);
    var view = new DTectorView();
    view._gm = gm;
    if (!view.canDoubleBack()) { return false; }
    gm.logicMgr.currentScreen = Kaisa.SCREEN_MAIN_MENU;
    if (view.canDoubleBack()) { return false; }
    gm.logicMgr.currentScreen = Kaisa.SCREEN_CHARACTER;
    gm.logicMgr.isEventPending = true;
    if (view.canDoubleBack()) { return false; }
    gm.logicMgr.isEventPending = false;
    saved.setSavedEvent(1);
    if (view.canDoubleBack()) { return false; }
    saved.setSavedEvent(0);
    gm.worldMgr.setCurrentDistance(1);
    return !view.canDoubleBack();
}

(:test)
function eventReminderRepeatsOnlyWhilePromptWaits(logger as Test.Logger) as Boolean {
    var audio = new AudioManager(new Runner());
    audio.muted = true;
    for (var i = 0; i < 31; i += 1) {
        if (audio.tickEventReminder(true, 50)) { return false; }
    }
    if (!audio.tickEventReminder(true, 50)) { return false; }
    for (var i = 0; i < 31; i += 1) {
        if (audio.tickEventReminder(true, 50)) { return false; }
    }
    if (!audio.tickEventReminder(true, 50)) { return false; }
    if (audio.tickEventReminder(false, 0)) { return false; }
    return !audio.tickEventReminder(true, 50);
}
