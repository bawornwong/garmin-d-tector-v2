import Toybox.Lang;

// Source switches for menu entries whose apps do not exist yet. Connect stays
// visible and rejects selection; the others are hidden until enabled here.
// Change a switch and rebuild. No save migration or watch-side setting is involved.
module Kaisa {
    module MenuFeatures {
        const SHOW_CONNECT = true;
        const SHOW_ENERGY_WARS = false;
        const SHOW_DIGI_CATCH = false;
        const SHOW_ASTEROIDS = false;

        function visible(screen as Number, index as Number) as Boolean {
            if (screen == Kaisa.SCREEN_MAIN_MENU) {
                return index >= 0 && index < 8
                    && (index != Kaisa.MAIN_MENU_CONNECT || SHOW_CONNECT);
            }
            if (screen == Kaisa.SCREEN_GAMES_REWARD_MENU) {
                return index >= 0 && index < 3
                    && (index != 1 || SHOW_ENERGY_WARS)
                    && (index != 2 || SHOW_DIGI_CATCH);
            }
            if (screen == Kaisa.SCREEN_GAMES_TRAVEL_MENU) {
                return index >= 0 && index < 4
                    && (index != 1 || SHOW_ASTEROIDS);
            }
            return false;
        }

        function advance(screen as Number, current as Number,
                         delta as Number) as Number {
            var count = 0;
            if (screen == Kaisa.SCREEN_MAIN_MENU) { count = 8; }
            else if (screen == Kaisa.SCREEN_GAMES_REWARD_MENU) { count = 3; }
            else if (screen == Kaisa.SCREEN_GAMES_TRAVEL_MENU) { count = 4; }
            if (count == 0) { return current; }

            var candidate = current;
            for (var i = 0; i < count; i += 1) {
                candidate = Kaisa.MathExt.circularAdd(candidate, delta, count - 1, 0);
                if (visible(screen, candidate)) { return candidate; }
            }
            return current;
        }
    }
}
