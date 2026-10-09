import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.Test;

(:test)
function configureCarouselShowsEachSetting(logger as Test.Logger) as Boolean {
    var data = new GameData();
    data.load();
    var db = new Database(data);
    db.load();
    var format = new SaveFormat(data);
    var rec = format.createDefault("CONFIG");
    rec.gameChar = Kaisa.CHAR_TAKUYA;
    var gm = new GameManager(data, db, new SavedGame(format, 0, rec));
    var sm = new ScreenManager(gm, new ContainerBuilder());
    gm.attachScreenManager(sm);
    gm.logicMgr.currentScreen = Kaisa.SCREEN_CONFIGURE_MENU;
    var labels = ["VIBE", "SOUND", "GRID", "BG STEP", "STEP", "GAME"];

    for (var index = 0; index < labels.size(); index += 1) {
        gm.logicMgr.configureMenuIndex = index;
        sm.updateDisplay();
        var hasIcon = false;
        var hasLabel = false;
        var hasState = false;
        var hasMultiplier = index != Kaisa.CONFIGURE_STEP_MULTIPLIER;
        for (var j = 0; j < sm.screenDisplay.children.size(); j += 1) {
            var child = sm.screenDisplay.children[j];
            if (child instanceof SpriteBuilder
                    && (child as SpriteBuilder).runtimeBitmap != null) {
                hasIcon = true;
            } else if (child instanceof TextBoxBuilder) {
                var word = (child as TextBoxBuilder).text;
                if (word.equals(labels[index])) {
                    hasLabel = child.font == Kaisa.MenuFont.FACE
                        && child.y == (index == Kaisa.CONFIGURE_STEP_MULTIPLIER ? 21 : 24);
                }
                if (word.equals("MULT")) {
                    hasMultiplier = child.font == Kaisa.MenuFont.FACE && child.y == 27;
                }
                if (index == Kaisa.CONFIGURE_RESET ? word.equals("RESET")
                        : (index == Kaisa.CONFIGURE_STEP_MULTIPLIER
                            ? word.equals("X" + StepMultiplierSetting.value())
                            : (word.equals("ON") || word.equals("OFF")))) {
                    hasState = true;
                }
            }
        }
        if (!hasIcon || !hasLabel || !hasState || !hasMultiplier) { return false; }
    }
    return true;
}

(:test)
function configEntryUsesMenuLetteringAndCompactWordGap(logger as Test.Logger) as Boolean {
    var data = new GameData();
    data.load();
    var db = new Database(data);
    db.load();
    var format = new SaveFormat(data);
    var gm = new GameManager(data, db,
        new SavedGame(format, 0, format.createDefault("CONFIG")));
    var sm = new ScreenManager(gm, new ContainerBuilder());
    gm.logicMgr.currentScreen = Kaisa.SCREEN_MAIN_MENU;
    gm.logicMgr.currentMainMenu = Kaisa.MAIN_MENU_CONFIGURE;
    sm.updateDisplay();
    var hasLabel = false;
    for (var i = 0; i < sm.screenDisplay.children.size(); i += 1) {
        var child = sm.screenDisplay.children[i];
        if (child instanceof TextBoxBuilder && child.text.equals("CONFIG")) {
            hasLabel = child.font == Kaisa.MenuFont.FACE && child.y == 24;
        }
    }
    // The ink in BG STEP is separated by one normal letter gutter and one
    // blank column; the whole label stays inside the canvas.
    var space = Kaisa.TextMetrics.glyph(Kaisa.MenuFont.FACE, 32);
    return hasLabel && space != null && space[3] == 1
        && Kaisa.TextMetrics.lineWidth(Kaisa.MenuFont.FACE, "BG STEP") <= 32;
}

(:test)
function stepMultiplierDefaultsAndConfigSelection(logger as Test.Logger) as Boolean {
    var previous = Storage.getValue(StepMultiplierSetting.KEY);
    Storage.deleteValue(StepMultiplierSetting.KEY);
    var passed = StepMultiplierSetting.value() == 1;
    var data = new GameData();
    data.load();
    var db = new Database(data);
    db.load();
    var format = new SaveFormat(data);
    var gm = new GameManager(data, db,
        new SavedGame(format, 0, format.createDefault("CONFIG")));
    gm.audioMgr.muted = true;
    gm.logicMgr.currentScreen = Kaisa.SCREEN_CONFIGURE_MENU;
    gm.logicMgr.configureMenuIndex = Kaisa.CONFIGURE_BG_STEPS;
    gm.logicMgr.inputRight();
    passed = passed && gm.logicMgr.configureMenuIndex == Kaisa.CONFIGURE_STEP_MULTIPLIER;
    for (var i = 2; i <= 5; i += 1) {
        gm.logicMgr.inputA();
        passed = passed && StepMultiplierSetting.value() == i
            && Storage.getValue(StepMultiplierSetting.KEY) == i;
    }
    gm.logicMgr.inputA();
    passed = passed && StepMultiplierSetting.value() == 1;
    gm.logicMgr.inputRight();
    passed = passed && gm.logicMgr.configureMenuIndex == Kaisa.CONFIGURE_RESET;
    gm.logicMgr.inputRight();
    passed = passed && gm.logicMgr.configureMenuIndex == Kaisa.CONFIGURE_VIBRATION;
    gm.logicMgr.inputLeft();
    passed = passed && gm.logicMgr.configureMenuIndex == Kaisa.CONFIGURE_RESET;
    Storage.setValue(StepMultiplierSetting.KEY, "invalid");
    passed = passed && StepMultiplierSetting.value() == 1;
    StepMultiplierSetting.setValue(0);
    passed = passed && StepMultiplierSetting.value() == 1;
    Storage.setValue(StepMultiplierSetting.KEY, 6);
    passed = passed && StepMultiplierSetting.value() == 1;
    if (previous == null) { Storage.deleteValue(StepMultiplierSetting.KEY); }
    else { Storage.setValue(StepMultiplierSetting.KEY, previous); }
    return passed;
}

(:test)
function backgroundStepSettingDefaultsOnAndCanBeToggled(logger as Test.Logger) as Boolean {
    var previous = Storage.getValue(BackgroundStepSetting.KEY);
    Storage.deleteValue(BackgroundStepSetting.KEY);
    var defaultsOn = BackgroundStepSetting.enabled();
    BackgroundStepSetting.setEnabled(false);
    var turnedOff = !BackgroundStepSetting.enabled();
    BackgroundStepSetting.setEnabled(true);
    var turnedOn = BackgroundStepSetting.enabled();
    if (previous == null) { Storage.deleteValue(BackgroundStepSetting.KEY); }
    else { Storage.setValue(BackgroundStepSetting.KEY, previous); }
    return defaultsOn && turnedOff && turnedOn;
}
