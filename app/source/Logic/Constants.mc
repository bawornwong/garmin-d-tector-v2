import Toybox.Lang;

// port of Constants.cs and Preferences.cs
//
// PIXEL_SIZE is deliberately absent. In Unity it converted game pixels to
// canvas units at every RectTransform; here the display list is already in
// game pixels and the renderer applies its own SCALE, so a PIXEL_SIZE in the
// logic layer would be a second, conflicting scale factor.
module Kaisa {
    module Constants {
        const GAME_VERSION = "0.20.0513a";

        const SCREEN_WIDTH = 32;
        const SCREEN_HEIGHT = 32;

        // The speed at which attacks always travel, in seconds per game pixel.
        // Kept as Float: the animation schedule multiplies it out to
        // milliseconds and ADR 5's scheduler keeps the fractional part.
        const ATTACK_TRAVEL_SPEED = 0.05;    // 0.06f
        const CRUSH_TRAVEL_SPEED = 0.035;    // 0.04f

        const MAX_SPIRIT_POWER = 99;
        const DEFAULT_DIGIMON = "numemon";
        const DEFAULT_SPIRIT_DIGIMON = "flamemon";
    }

    // port of Preferences.cs. The original reads these from PlayerPrefs with
    // these values as the defaults; the port carries them as the defaults the
    // renderer starts with, and they are a draw-time tint rather than baked
    // art (ADR 3), so a settings screen can still change them later.
    module Preferences {
        const ACTIVE_COLOR = 0x000000;
        const BACKGROUND_COLOR = 0x819376;
    }
}
