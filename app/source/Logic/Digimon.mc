import Toybox.Lang;
import Toybox.Math;

// port of Logic/Models/Digimon.cs
//
// One difference of substance from the original, and it is the one ADR 7
// asks for: a Digimon is identified by its **index** into the packed data,
// not by its name. The original stores names in every save field and looks
// them up with a string compare through Database; the port stores the index,
// which is the same row order in the sprite table, the save file and this
// model. `name` is still carried, because the Database and Status screens
// display it, but nothing addresses a Digimon by it.
//
// Every float formula below is translated under ticket 11 decision 2:
// compute in Float, and convert only after the floor/ceil/round. The rounding
// helpers live in Kaisa.MathExt because Mathf.RoundToInt is half-to-even and
// Monkey C's Math.round is not.
class Digimon {
    var index as Number;              // row in the packed data == save index
    var disabled as Boolean;
    var number as Number;
    var order as Number;
    var name as String;
    var stage as Number;
    var spiritType as Number;
    var abilityIndex as Number;       // 0xFF (255) when the Digimon has none
    var element as Number;
    var evolutionIndex as Number;     // -1 when it does not evolve
    var baseLevel as Number;
    var stats as CombatStats;
    var bossStats as CombatStats;
    var isPseudo as Boolean;
    var code as String;
    var rarity as Number;
    var exclusive as Boolean;

    function initialize(indexIn as Number, numberIn as Number, orderIn as Number,
                        nameIn as String, stageIn as Number, spiritTypeIn as Number,
                        abilityIndexIn as Number, elementIn as Number,
                        evolutionIndexIn as Number, disabledIn as Boolean,
                        baseLevelIn as Number, statsIn as CombatStats,
                        bossStatsIn as CombatStats?, isPseudoIn as Boolean,
                        codeIn as String, rarityIn as Number, exclusiveIn as Boolean) {
        index = indexIn;
        number = numberIn;
        order = orderIn;
        name = nameIn;
        stage = stageIn;
        spiritType = spiritTypeIn;
        abilityIndex = abilityIndexIn;
        element = elementIn;
        evolutionIndex = evolutionIndexIn;
        disabled = disabledIn;
        baseLevel = baseLevelIn;
        stats = statsIn;
        // "If the database does not have boss stats for this Digimon, use
        // regular stats instead" -- the original's null-coalescing assignment.
        bossStats = (bossStatsIn == null) ? statsIn : bossStatsIn;
        isPseudo = isPseudoIn;
        code = codeIn;
        rarity = rarityIn;
        exclusive = exclusiveIn;
    }

    // The maximum amount of extra levels a Digimon may have.
    function maxExtraLevel() as Number {
        var maxLevel;
        if (stage == Kaisa.STAGE_ROOKIE) {
            maxLevel = baseLevel * 2;
        } else if (stage == Kaisa.STAGE_SPIRIT || stage == Kaisa.STAGE_ARMOR) {
            maxLevel = 0;
        } else {
            maxLevel = Kaisa.MathExt.ceilToInt(baseLevel * 1.5);
        }
        return maxLevel - baseLevel;
    }

    // The Spirit Cost of this Digimon, based on the player level.
    function getSpiritCost(playerLevel as Number) as Number {
        var baseCost = 20;
        var decay = 20.0;
        if (name.equals("susanoomon")) {
            baseCost = 95;
            decay = 50.0;
        } else if (stage == Kaisa.STAGE_ARMOR) {
            baseCost = 10;
            decay = 20.0;
        } else if (stage == Kaisa.STAGE_SPIRIT) {
            if (spiritType == Kaisa.SPIRIT_HUMAN) {
                baseCost = 20;
                decay = 30.0;
            } else if (spiritType == Kaisa.SPIRIT_ANIMAL) {
                baseCost = 30;
                decay = 30.0;
            } else if (spiritType == Kaisa.SPIRIT_HYBRID) {
                baseCost = 35;
                decay = 40.0;
            } else if (spiritType == Kaisa.SPIRIT_ANCIENT) {
                baseCost = 40;
                decay = 50.0;
            } else if (spiritType == Kaisa.SPIRIT_FUSION) {
                baseCost = 55;
                decay = 60.0;
            } else {
                return 0;
            }
        } else {
            return 0;
        }

        var currentCost = baseCost * Math.pow(0.5, playerLevel / decay);
        return Kaisa.MathExt.floorToInt(currentCost);
    }

    // The cost to call this Digimon from a D-Dock, based on the player level.
    function getCallCost(playerLevel as Number) as Number {
        var percLevelDiff = baseLevel.toFloat() / playerLevel;
        var levelDiff = playerLevel - baseLevel;

        if (percLevelDiff < 0.55 && levelDiff >= 10) { return 0; }
        if (percLevelDiff < 0.75 && levelDiff >= 5) { return 1; }
        if (percLevelDiff < 0.90 && levelDiff >= 2) { return 2; }
        if (percLevelDiff < 1.0 && levelDiff >= 1) { return 3; }
        if (percLevelDiff == 1.0) { return 4; }
        if (percLevelDiff < 1.30) { return 5; }
        if (percLevelDiff < 1.60) { return 6; }
        if (percLevelDiff < 2.0) { return 7; }
        if (percLevelDiff < 3.0) { return 8; }
        if (percLevelDiff < 4.0) { return 9; }
        return 10;
    }

    // The actual level of a player-controlled Digimon, from the extra level
    // stored in the save.
    function getFriendlyLevel(digimonExtraLevel as Number) as Number {
        return baseLevel + digimonExtraLevel;
    }

    // The level of the Digimon as a boss, based on the player level.
    function getBossLevel(playerLevel as Number) as Number {
        if (stage == Kaisa.STAGE_SPIRIT) {
            if (spiritType == Kaisa.SPIRIT_ANCIENT) {
                var level = 20 + (playerLevel * 0.8);
                return Kaisa.MathExt.roundToInt(level);
            }
            return playerLevel;
        } else if (stage == Kaisa.STAGE_ARMOR) {
            return (playerLevel < 10) ? 10 : playerLevel;
        }
        return playerLevel;
    }

    // The chance (0..1) that this Digimon obeys. The original notes that the
    // Digimon the player CALLED is the one to ask, even after it evolved.
    function getObeyChance(playerLevel as Number) as Float {
        var currentBaseLevel = (stage == Kaisa.STAGE_SPIRIT || stage == Kaisa.STAGE_ARMOR)
            ? getBossLevel(playerLevel) : baseLevel;
        var levelDiff = currentBaseLevel - playerLevel;

        if (levelDiff <= 0) { return 1.0; }
        if (levelDiff >= 10) { return 0.0; }

        return 1.0 - (Math.pow(levelDiff, 2) / 100.0);
    }

    // The chance (0..1) that this Digimon attacks at all.
    //
    // The original's formula divides by Mathf.Pow(10f, -0.5f), i.e. multiplies
    // by about 3.16, so this returns values far above 1 for most inputs. That
    // is what the source does and what its call sites compare against, so it
    // is reproduced rather than corrected (ADR 2).
    function getIdleChance(playerLevel as Number) as Float {
        var currentBaseLevel = (stage == Kaisa.STAGE_SPIRIT || stage == Kaisa.STAGE_ARMOR)
            ? getBossLevel(playerLevel) : baseLevel;
        var levelDiff = currentBaseLevel - playerLevel;

        if (levelDiff <= 0) { return 1.0; }
        if (levelDiff >= 20) { return 0.0; }

        return (Math.pow(10.0, 1.5) - Math.pow(levelDiff / 2.0, 1.5)) / Math.pow(10.0, -0.5);
    }

    // Stats as a boss, based on the player level. Some friendly Digimon --
    // the Spirit-stage ones -- use these too.
    function getBossStats(playerLevel as Number) as MutableCombatStats {
        var bossLevel = getBossLevel(playerLevel);
        var hp;
        var en;
        var cr;
        var ab;
        if (stage == Kaisa.STAGE_SPIRIT) {
            hp = getStatAsSpiritBoss(bossStats.hp, bossLevel);
            en = getStatAsSpiritBoss(bossStats.en, bossLevel);
            cr = getStatAsSpiritBoss(bossStats.cr, bossLevel);
            ab = getStatAsSpiritBoss(bossStats.ab, bossLevel);
        } else {
            hp = getStatAsRegularBoss(bossStats.hp, bossLevel);
            en = getStatAsRegularBoss(bossStats.en, bossLevel);
            cr = getStatAsRegularBoss(bossStats.cr, bossLevel);
            ab = getStatAsRegularBoss(bossStats.ab, bossLevel);
        }
        return new MutableCombatStats(hp, en, cr, ab);
    }

    // Stats from the Digimon's actual level. Not for Spirit- or Armor-stage.
    function getFriendlyStats(digimonExtraLevel as Number) as MutableCombatStats {
        return new MutableCombatStats(
            getStatAsFriendly(stats.hp, digimonExtraLevel),
            getStatAsFriendly(stats.en, digimonExtraLevel),
            getStatAsFriendly(stats.cr, digimonExtraLevel),
            getStatAsFriendly(stats.ab, digimonExtraLevel));
    }

    function getRegularStats() as MutableCombatStats {
        return new MutableCombatStats(stats.hp, stats.en, stats.cr, stats.ab);
    }

    // The chance that any Digimon evolves INTO this one -- call it on the
    // result of the digivolution, not on the Digimon attempting it.
    function getEvolveChance(playerLevel as Number, extraPoints as Number) as Float {
        var multiplier = (extraPoints - 1) / 20.0;
        var extraLevel = Kaisa.MathExt.floorToInt(playerLevel * multiplier);
        // SOURCE ODDITY, reproduced: the comment says the minimum is
        // extraPoints - 1, and the guard tests for that, but the assignment
        // sets extraPoints. Both are kept as written (ADR 2).
        if (extraLevel < extraPoints - 1) { extraLevel = extraPoints; }

        var level = playerLevel + extraLevel;
        var levelDiff = baseLevel - level;
        if (levelDiff <= 0) { return 1.0; }
        if (levelDiff >= 10) { return 0.05; }

        var a = Math.pow(levelDiff, 2.0);
        var b = levelDiff / 10.0;
        var evolChance = 1.0 - (a / 100.0) + (0.05 * b);
        if (evolChance < 0.05) { evolChance = 0.05; }
        return evolChance;
    }

    function getStatAsSpiritBoss(stat as Number, bossLevel as Number) as Number {
        var riggedStat;
        if (spiritType == Kaisa.SPIRIT_HUMAN) {
            // 25% of the stat, rising to 75% at level 100.
            riggedStat = (0.25 + (0.005 * bossLevel)) * stat;
        } else if (spiritType == Kaisa.SPIRIT_ANCIENT) {
            // 20% of the stat, rising to 100% at level 100.
            riggedStat = (0.20 + (0.008 * bossLevel)) * stat;
        } else {
            // 30% of the stat, rising to 100% at level 100.
            riggedStat = (0.30 + (0.007 * bossLevel)) * stat;
        }
        return Kaisa.MathExt.roundToInt(riggedStat);
    }

    function getStatAsRegularBoss(stat as Number, bossLevel as Number) as Number {
        return Kaisa.MathExt.roundToInt((0.20 + (0.008 * bossLevel)) * stat);
    }

    function getStatAsFriendly(stat as Number, currentExtraLevel as Number) as Number {
        if (currentExtraLevel == 0) { return stat; }
        // Interpolates the stat between 100% at zero extra levels and 150% at
        // the maximum, which is what makes max-level stats come out round.
        var multiplier = 1.0 + (0.5 * (currentExtraLevel.toFloat() / maxExtraLevel()));
        return Kaisa.MathExt.ceilToInt(stat * multiplier);
    }
}

class CombatStats {
    var hp as Number;
    var en as Number;
    var cr as Number;
    var ab as Number;

    function initialize(hpIn as Number, enIn as Number, crIn as Number, abIn as Number) {
        hp = hpIn;
        en = enIn;
        cr = crIn;
        ab = abIn;
    }

    function toString() as String {
        return "HP: " + hp + ", EN: " + en + ", CR: " + cr + ", AB: " + ab + ".";
    }
}

class MutableCombatStats {
    var hp as Number;
    var en as Number;
    var cr as Number;
    var ab as Number;
    var maxHP as Number;

    function initialize(hpIn as Number, enIn as Number, crIn as Number, abIn as Number) {
        hp = hpIn;
        en = enIn;
        cr = crIn;
        ab = abIn;
        maxHP = hpIn;
    }

    function toString() as String {
        return "HP: " + hp + ", EN: " + en + ", CR: " + cr + ", AB: " + ab + ".";
    }

    function getMissingHP() as Number {
        return maxHP - hp;
    }

    // Reduces HP so the Digimon is missing exactly this much, floored at 1.
    function applyMissingHP(amount as Number) as Void {
        hp = maxHP - amount;
        if (hp < 1) { hp = 1; }
    }

    // Damage of an attack by index (0: energy, 1: crush, 2: ability).
    function getAttackDamage(attackIndex as Number) as Number {
        if (attackIndex == 0) { return en; }
        if (attackIndex == 1) { return cr; }
        if (attackIndex == 2) { return ab; }
        return 0;
    }

    // The energy sprite to draw for this much EN.
    function getEnergyRank() as Number {
        if (en < 20) { return 0; }
        if (en < 30) { return 1; }
        if (en < 45) { return 2; }
        if (en < 60) { return 3; }
        if (en < 75) { return 4; }
        if (en < 90) { return 5; }
        if (en < 105) { return 6; }
        if (en < 120) { return 7; }
        if (en < 135) { return 8; }
        if (en < 150) { return 9; }
        if (en < 175) { return 10; }
        if (en < 200) { return 11; }
        if (en < 225) { return 12; }
        if (en < 250) { return 13; }
        if (en < 275) { return 14; }
        return 15;
    }
}
