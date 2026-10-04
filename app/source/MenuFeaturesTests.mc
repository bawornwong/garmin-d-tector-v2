import Toybox.Lang;
import Toybox.Test;

(:test)
function mainMenuKeepsConnectBetweenCampAndConfig(logger as Test.Logger) as Boolean {
    var data = new GameData();
    data.load();
    var db = new Database(data);
    db.load();
    var format = new SaveFormat(data);
    var rec = format.createDefault("MENU");
    rec.gameChar = Kaisa.CHAR_TAKUYA;
    var gm = new GameManager(data, db, new SavedGame(format, 0, rec));
    gm.audioMgr.muted = true;
    var menu = gm.logicMgr;
    menu.currentScreen = Kaisa.SCREEN_MAIN_MENU;
    menu.currentMainMenu = Kaisa.MAIN_MENU_CAMP;
    menu.inputRight();
    if (menu.currentMainMenu != Kaisa.MAIN_MENU_CONNECT) { return false; }
    menu.inputA();
    if (menu.currentScreen != Kaisa.SCREEN_MAIN_MENU
            || menu.currentMainMenu != Kaisa.MAIN_MENU_CONNECT
            || menu.loadedApp != null) { return false; }
    menu.inputRight();
    if (menu.currentMainMenu != Kaisa.MAIN_MENU_CONFIGURE) { return false; }
    menu.inputLeft();
    if (menu.currentMainMenu != Kaisa.MAIN_MENU_CONNECT) { return false; }
    menu.currentMainMenu = Kaisa.MAIN_MENU_CONFIGURE;
    menu.inputRight();
    if (menu.currentMainMenu != Kaisa.MAIN_MENU_MAP) { return false; }
    menu.inputLeft();
    return menu.currentMainMenu == Kaisa.MAIN_MENU_CONFIGURE;
}

(:test)
function gameMenusSkipUnimplementedEntries(logger as Test.Logger) as Boolean {
    var data = new GameData();
    data.load();
    var db = new Database(data);
    db.load();
    var format = new SaveFormat(data);
    var rec = format.createDefault("MENU");
    rec.gameChar = Kaisa.CHAR_TAKUYA;
    var gm = new GameManager(data, db, new SavedGame(format, 0, rec));
    gm.audioMgr.muted = true;
    var menu = gm.logicMgr;
    menu.currentScreen = Kaisa.SCREEN_GAMES_REWARD_MENU;
    menu.gamesRewardMenuIndex = 0;
    menu.inputRight();
    if (menu.gamesRewardMenuIndex != 0) { return false; }
    menu.inputLeft();
    if (menu.gamesRewardMenuIndex != 0) { return false; }
    menu.currentScreen = Kaisa.SCREEN_GAMES_TRAVEL_MENU;
    menu.gamesTravelMenuIndex = 0;
    menu.inputRight();
    if (menu.gamesTravelMenuIndex != 2) { return false; }
    menu.inputLeft();
    if (menu.gamesTravelMenuIndex != 0) { return false; }
    menu.inputLeft();
    return menu.gamesTravelMenuIndex == 3;
}
