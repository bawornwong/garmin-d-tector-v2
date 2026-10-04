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
    var labels = ["VIBE", "SOUND", "GRID", "BG STEP", "GAME"];

    for (var index = 0; index < labels.size(); index += 1) {
        gm.logicMgr.configureMenuIndex = index;
        sm.updateDisplay();
        var hasIcon = false;
        var hasLabel = false;
        var hasState = false;
        for (var j = 0; j < sm.screenDisplay.children.size(); j += 1) {
            var child = sm.screenDisplay.children[j];
            if (child instanceof SpriteBuilder
                    && (child as SpriteBuilder).runtimeBitmap != null) {
                hasIcon = true;
            } else if (child instanceof TextBoxBuilder) {
                var word = (child as TextBoxBuilder).text;
                if (word.equals(labels[index])) { hasLabel = true; }
                if (index == Kaisa.CONFIGURE_RESET ? word.equals("RESET")
                        : (word.equals("ON") || word.equals("OFF"))) {
                    hasState = true;
                }
            }
        }
        if (!hasIcon || !hasLabel || !hasState) { return false; }
    }
    return true;
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
