import Toybox.Lang;
import Toybox.Math;

// port of Logic/LogicManager.cs -- the player-stat half of it.
//
// LogicManager.cs is 857 lines and reaches into every app, the animation
// queue and the world map. This carries the parts the Status and Database
// screens need, translated line for line; the rest arrives with the apps that
// call it, and each addition keeps its `port of` line so the two files stay
// diffable (ticket 11 decision 6).
//
// The level formulas are the ones ticket 14 measured and
// tools/verify_numeric.py re-checks: compute in Float, floor last.
class LogicManager {
    var _saved as SavedGame;
    var _db as Database;

    function initialize(saved as SavedGame, db as Database) {
        _saved = saved;
        _db = db;
    }

    // LogicManager.cs:449
    function playerExperience() as Number {
        return _saved.playerExperience();
    }

    // LogicManager.cs:453 -- the level of a player from their experience.
    function getPlayerLevel() as Number {
        var playerXP = _saved.playerExperience();
        if (playerXP == 0) { return 1; }

        var level = Math.pow(playerXP, 1.0 / 3.0);
        return Kaisa.MathExt.floorToInt(level);
    }

    // LogicManager.cs:465 -- how far through the current level the player is,
    // where 0 is the level's base experience rather than zero experience.
    function getPlayerLevelProgression() as Float {
        var floorExperience = Kaisa.MathExt.floorToInt(Math.pow(getPlayerLevel(), 3));
        var topExperience = Kaisa.MathExt.floorToInt(Math.pow(getPlayerLevel() + 1, 3));

        var maxExperienceForLevel = topExperience - floorExperience;
        var playerExperienceForLevel = playerExperience() - floorExperience;

        return playerExperienceForLevel.toFloat() / maxExperienceForLevel;
    }

    // LogicManager.cs:477
    function levelUpPlayer() as Void {
        var playerLevel = getPlayerLevel();
        var nextLevelExp = Math.pow(playerLevel + 1, 3.0);
        _saved.setPlayerExperience(Kaisa.MathExt.ceilToInt(nextLevelExp));
    }

    // LogicManager.cs:485. The C# casts the float difference with (int),
    // which truncates toward zero rather than flooring; both values are
    // positive here, so floorToInt matches.
    function levelDownPlayer() as Void {
        var playerLevel = getPlayerLevel();
        var lastLevelExperience = Math.pow(playerLevel - 1, 3.0);
        var thisLevelExperience = Math.pow(playerLevel, 3.0);
        var nextLevelExperience = Math.pow(playerLevel + 1, 3.0);

        var xp = _saved.playerExperience()
            - Kaisa.MathExt.floorToInt(nextLevelExperience - thisLevelExperience);
        if (xp < lastLevelExperience) {
            xp = Kaisa.MathExt.floorToInt(lastLevelExperience);
        }
        _saved.setPlayerExperience(xp);
    }

    // LogicManager.cs:493 -- the setter clamps at both ends.
    function spiritPower() as Number {
        return _saved.spiritPower();
    }

    function setSpiritPower(value as Number) as Void {
        var totalSpiritPower = value;
        if (totalSpiritPower > Kaisa.Constants.MAX_SPIRIT_POWER) { totalSpiritPower = 99; }
        if (totalSpiritPower < 0) { totalSpiritPower = 0; }
        _saved.setSpiritPower(totalSpiritPower);
    }

    // LogicManager.cs:502
    function totalBattles() as Number {
        return _saved.totalBattles();
    }

    function totalWins() as Number {
        return _saved.totalWins();
    }

    function winPercentage() as Float {
        if (totalBattles() == 0) { return 0.0; }
        return totalWins().toFloat() / totalBattles();
    }

    function increaseTotalBattles() as Number {
        var v = _saved.totalBattles() + 1;
        _saved.setTotalBattles(v);
        return v;
    }

    function increaseTotalWins() as Number {
        var v = _saved.totalWins() + 1;
        _saved.setTotalWins(v);
        return v;
    }

    // LogicManager.cs:560 region "Digimon data". The original addresses these
    // by name; here the index is the identity (ADR 7).
    function getDDockDigimon(ddock as Number) as Number {
        return _saved.ddockDigimon(ddock);
    }

    function getDigimonExtraLevel(digimonIndex as Number) as Number {
        return _saved.digimonExtraLevel(digimonIndex);
    }

    // LogicManager.cs:589
    function isDigimonAtMaxLevel(digimonIndex as Number) as Boolean {
        var d = _db.getDigimon(digimonIndex);
        return (d != null) && (getDigimonExtraLevel(digimonIndex) == d.maxExtraLevel());
    }
}
