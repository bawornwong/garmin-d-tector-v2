import Toybox.Lang;
import Toybox.System;

// port of Logic/Apps/AppLoader.cs
//
// The original instantiates one prefab per app and pulls its component off;
// with the prefabs gone, loading an app is just constructing it. What is kept
// is the App enum and the single entry point, so LogicManager's Open* methods
// read exactly as they do in the C#.
//
// Apps not yet translated return null and say so once. LogicManager treats a
// null app as "nothing opened" and stays on the menu, which is the least
// confusing thing a half-built port can do -- better than a black screen with
// no way back.
module Kaisa {
    enum App {
        APP_MAP = 0,
        APP_STATUS = 1,
        APP_DATABASE = 2,
        APP_CODE_INPUT = 3,
        APP_CAMP = 4,
        APP_CONNECT = 5,
        APP_FINDER = 6,
        APP_BATTLE = 7,
        APP_JACKPOT_BOX = 8,
        APP_ENERGY_WARS = 9,
        APP_DIGI_CATCH = 10,
        APP_SPEED_RUNNER = 11,
        APP_ASTEROIDS = 12,
        APP_DIGI_HUNTER = 13,
        APP_MAZE = 14
    }
}

class AppLoader {
    var gm as GameManager;

    function initialize(gmIn as GameManager) {
        gm = gmIn;
    }

    // AppLoader.LoadApp<T>. `parent` is the screen root the app draws into,
    // which the original gets from gm.RootParent.
    function loadApp(app as Number, controller, parent as ScreenElement) as DigiviceApp? {
        if (app == Kaisa.APP_STATUS) { return new Status(gm, controller, parent); }
        if (app == Kaisa.APP_DATABASE) { return new DatabaseApp(gm, controller, parent); }
        if (app == Kaisa.APP_CAMP) { return new Camp(gm, controller, parent); }
        if (app == Kaisa.APP_CODE_INPUT) {
            // LogicManager.OpenDigits passes false: a wrong code stays on the
            // error screen instead of closing with the default Digimon.
            return new CodeInput(gm, controller, parent).setSubmitError(false);
        }

        if (app == Kaisa.APP_FINDER) { return new Finder(gm, controller, parent); }

        // Map, Connect, Battle, JackpotBox, EnergyWars,
        // DigiCatch, SpeedRunner, Asteroids, DigiHunter, Maze -- steps 8 and 9
        // of SPEC's order of work.
        System.println("AppLoader: app " + app + " is not translated yet");
        return null;
    }
}
