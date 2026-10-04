import Toybox.Lang;

// port of Logic/MenuEnums.cs, the enums declared at the foot of
// Logic/Models/Digimon.cs, and Logic/Extensions/Enums.cs.
//
// Monkey C enum members share the enclosing scope, so every member carries
// the prefix of its C# enum (`Stage.Rookie` -> `STAGE_ROOKIE`). The VALUES
// are load-bearing, not just the names: the packed data stores stage, spirit
// type, element and rarity as the raw ordinals of digimonDB.json, which are
// these enums' ordinals (ticket 12 / ADR 7). Reordering a member here
// silently rewrites the database.
module Kaisa {
    enum Direction {
        DIR_LEFT = 0,
        DIR_RIGHT = 1,
        DIR_UP = 2,
        DIR_DOWN = 3,
        DIR_NONE = 4
    }

    enum Screen {
        SCREEN_CHAR_SELECTION = 0,
        SCREEN_CHARACTER = 1,
        SCREEN_MAIN_MENU = 2,
        SCREEN_APP = 3,
        SCREEN_GAMES_MENU = 4,
        SCREEN_GAMES_REWARD_MENU = 5,
        SCREEN_GAMES_TRAVEL_MENU = 6,
        SCREEN_TITLE = 7,       // unused: the reset moved into Configure
        // Not in the original: the Configure submenu, reached from the main
        // menu and shaped like the Games submenu next to it.
        SCREEN_CONFIGURE_MENU = 8
    }

    enum TitleOption {
        TITLE_PLAY = 0,
        TITLE_NEW = 1,
        TITLE_DELETE = 2
    }

    enum MainMenu {
        MAIN_MENU_MAP = 0,
        MAIN_MENU_STATUS = 1,
        MAIN_MENU_GAME = 2,
        MAIN_MENU_DATABASE = 3,
        MAIN_MENU_DIGITS = 4,
        MAIN_MENU_CAMP = 5,
        MAIN_MENU_CONNECT = 6,
        // Not in the original's menu. The original resets a game from its
        // MainMenu scene, which a watch has no room for; that reset lives in
        // here now, alongside the settings a watch needs and a phone did not
        // (its sound and vibration were the phone's to control, and it had no
        // dot-matrix grid to draw).
        MAIN_MENU_CONFIGURE = 7
    }

    // The Configure submenu. Reset sits last, furthest from an accidental
    // press: the four above it are reversible and it is not.
    enum ConfigureMenu {
        CONFIGURE_VIBRATION = 0,
        CONFIGURE_SOUND = 1,
        CONFIGURE_GRID = 2,
        CONFIGURE_BG_STEPS = 3,
        CONFIGURE_RESET = 4
    }

    enum GameMenu {
        GAME_MENU_REWARD = 0,
        GAME_MENU_TRAVEL = 1
    }

    enum GameRewardMenu {
        GAME_REWARD_FIND_BATTLE = 0,
        GAME_REWARD_JACKPOT_BOX = 1,
        GAME_REWARD_ENERGY_WARS = 2,
        GAME_REWARD_DIGI_CATCH = 3
    }

    enum GameTravelMenu {
        GAME_TRAVEL_SPEED_RUNNER = 0,
        GAME_TRAVEL_ASTEROIDS = 1,
        GAME_TRAVEL_DIGI_HUNTER = 2,
        GAME_TRAVEL_MAZE = 3
    }

    enum Reward {
        REWARD_NONE = 0,
        REWARD_EMPTY = 1,
        REWARD_INCREASE_DISTANCE_300 = 2,
        REWARD_INCREASE_DISTANCE_500 = 3,
        REWARD_INCREASE_DISTANCE_2000 = 4,
        REWARD_REDUCE_DISTANCE_500 = 5,
        REWARD_REDUCE_DISTANCE_1000 = 6,
        REWARD_PUNISH_DIGIMON = 7,
        REWARD_REWARD_DIGIMON = 8,
        REWARD_UNLOCK_DIGICODE_OWNED = 9,
        REWARD_UNLOCK_DIGICODE_NOT_OWNED = 10,
        REWARD_DATA_STORM = 11,
        REWARD_LOSE_SPIRIT_POWER_10 = 12,
        REWARD_LOSE_SPIRIT_POWER_50 = 13,
        REWARD_GAIN_SPIRIT_POWER_10 = 14,
        REWARD_GAIN_SPIRIT_POWER_MAX = 15,
        REWARD_LEVEL_DOWN = 16,
        REWARD_LEVEL_UP = 17,
        REWARD_FORCE_LEVEL_DOWN = 18,
        REWARD_FORCE_LEVEL_UP = 19,
        REWARD_TRIGGER_BATTLE = 20
    }

    // Digimon.cs enums. These four are the ones stored in the packed data.
    enum Stage {
        STAGE_ROOKIE = 0,
        STAGE_CHAMPION = 1,
        STAGE_PERFECT = 2,
        STAGE_MEGA = 3,
        STAGE_ULTIMATE = 4,
        STAGE_ARMOR = 5,
        STAGE_SPIRIT = 6,
        STAGE_NONE = 7
    }

    enum SpiritType {
        SPIRIT_HUMAN = 0,
        SPIRIT_ANIMAL = 1,
        SPIRIT_HYBRID = 2,
        SPIRIT_ANCIENT = 3,
        SPIRIT_FUSION = 4,
        SPIRIT_CHILD = 5,
        SPIRIT_NONE = 6
    }

    enum Element {
        ELEMENT_FIRE = 0,
        ELEMENT_LIGHT = 1,
        ELEMENT_THUNDER = 2,
        ELEMENT_WIND = 3,
        ELEMENT_ICE = 4,
        ELEMENT_DARK = 5,
        ELEMENT_EARTH = 6,
        ELEMENT_WOOD = 7,
        ELEMENT_METAL = 8,
        ELEMENT_WATER = 9,
        ELEMENT_NONE = 10
    }

    enum Rarity {
        RARITY_COMMON = 0,
        RARITY_RARE = 1,
        RARITY_EPIC = 2,
        RARITY_LEGENDARY = 3,
        RARITY_BOSS = 4,
        RARITY_NONE = 5
    }

    // SpriteAction doubles as the sprite-ref index in the packed entry, which
    // is why GameData's ACTION_* constants must stay in this order.
    enum SpriteAction {
        SPRITE_DEFAULT = 0,
        SPRITE_ATTACK = 1,
        SPRITE_CRUSH = 2,
        SPRITE_SPIRIT = 3,
        SPRITE_SPIRIT_SMALL = 4,
        SPRITE_BLACK = 5,
        SPRITE_WHITE = 6
    }

    enum GameChar {
        // GameChar.none: the save has no character until the player picks one,
        // which is what sends a fresh game to the selection screen.
        CHAR_NONE = -1,
        CHAR_TAKUYA = 0,
        CHAR_KOJI = 1,
        CHAR_ZOE = 2,
        CHAR_JP = 3,
        CHAR_TOMMY = 4,
        CHAR_KOICHI = 5
    }

    // port of Logic/Extensions/Enums.cs
    //
    // C#'s Next()/Last() walk the enum's own value list by reflection. Monkey
    // C has no reflection, so each call site passes the member count instead
    // -- the enums above are all dense and zero-based, so the wrap arithmetic
    // is the same one Array.IndexOf produced.
    module Enums {
        function next(value as Number, count as Number) as Number {
            var i = value + 1;
            return (i == count) ? 0 : i;
        }

        function last(value as Number, count as Number) as Number {
            var i = value - 1;
            return (i == -1) ? (count - 1) : i;
        }

        function opposite(dir as Number) as Number {
            if (dir == DIR_LEFT) { return DIR_RIGHT; }
            if (dir == DIR_RIGHT) { return DIR_LEFT; }
            if (dir == DIR_UP) { return DIR_DOWN; }
            if (dir == DIR_DOWN) { return DIR_UP; }
            return DIR_LEFT;
        }
    }
}
