// Numeric parity sweep, C# side: drives the ORIGINAL Logic/Models/Digimon.cs
// over every formula whose result a rounding boundary can move, and prints
// one line per value. The Monkey C side (tools/numeric/ciq) runs the same
// sweep over the ported Logic/Digimon.mc and tools/verify_numeric.py diffs
// the two outputs line for line.
//
// Float results print as their exact 32-bit bit pattern rather than as text:
// a decimal rendering would hide a one-ULP difference, and a one-ULP
// difference is exactly what crosses a floor boundary somewhere else.
using System;
using System.Globalization;
using Kaisa.Digivice;

public static class Sweep {
    static CombatStats Stats(int hp, int en, int cr, int ab) => new CombatStats(hp, en, cr, ab);

    // A Digimon whose only interesting parts are the ones a formula reads.
    static Digimon Make(Stage stage, SpiritType spirit, int baseLevel,
                        CombatStats stats, CombatStats bossStats, string name = "x") {
        return new Digimon(1, 1, name, stage, spirit, "a", Element.Fire, "", new string[0],
                           false, baseLevel, stats, bossStats, false, "abcde");
    }

    static string F(float f) {
        // uint of the IEEE-754 single, so the diff is bit-exact
        return BitConverter.ToUInt32(BitConverter.GetBytes(f), 0)
            .ToString(CultureInfo.InvariantCulture);
    }

    public static void Main() {
        var stats = Stats(40, 25, 15, 20);

        // Digimon.MaxExtraLevel -- CeilToInt(baseLevel * 1.5f) off the Rookie path
        Console.WriteLine("MAXEXTRA");
        foreach (Stage st in new[] { Stage.Rookie, Stage.Champion, Stage.Perfect,
                                     Stage.Mega, Stage.Ultimate, Stage.Armor, Stage.Spirit }) {
            for (int bl = 1; bl <= 100; bl++) {
                Console.WriteLine($"{(int)st} {bl} {Make(st, SpiritType.none, bl, stats, null).MaxExtraLevel}");
            }
        }

        // Digimon.GetSpiritCost -- every (stage, spiritType) branch
        Console.WriteLine("SPIRITCOST");
        foreach (var pair in new (Stage, SpiritType, string)[] {
                     (Stage.Spirit, SpiritType.Human, "x"), (Stage.Spirit, SpiritType.Animal, "x"),
                     (Stage.Spirit, SpiritType.Hybrid, "x"), (Stage.Spirit, SpiritType.Ancient, "x"),
                     (Stage.Spirit, SpiritType.Fusion, "x"), (Stage.Spirit, SpiritType.Child, "x"),
                     (Stage.Armor, SpiritType.none, "x"), (Stage.Rookie, SpiritType.none, "x"),
                     (Stage.Mega, SpiritType.Fusion, "susanoomon") }) {
            var d = Make(pair.Item1, pair.Item2, 10, stats, null, pair.Item3);
            for (int lv = 1; lv <= 100; lv++) {
                Console.WriteLine($"{(int)pair.Item1} {(int)pair.Item2} {pair.Item3} {lv} {d.GetSpiritCost(lv)}");
            }
        }

        // Digimon.GetCallCost -- the whole percLevelDiff ladder
        Console.WriteLine("CALLCOST");
        for (int bl = 1; bl <= 100; bl += 3) {
            for (int lv = 1; lv <= 100; lv += 3) {
                Console.WriteLine($"{bl} {lv} {Make(Stage.Rookie, SpiritType.none, bl, stats, null).GetCallCost(lv)}");
            }
        }

        // Digimon.GetBossLevel -- the Ancient branch rounds
        Console.WriteLine("BOSSLEVEL");
        foreach (var pair in new (Stage, SpiritType)[] {
                     (Stage.Spirit, SpiritType.Ancient), (Stage.Spirit, SpiritType.Human),
                     (Stage.Armor, SpiritType.none), (Stage.Rookie, SpiritType.none) }) {
            var d = Make(pair.Item1, pair.Item2, 10, stats, null);
            for (int lv = 1; lv <= 100; lv++) {
                Console.WriteLine($"{(int)pair.Item1} {(int)pair.Item2} {lv} {d.GetBossLevel(lv)}");
            }
        }

        // Digimon.GetObeyChance / GetIdleChance -- float results, bit-exact
        Console.WriteLine("CHANCES");
        for (int bl = 1; bl <= 60; bl++) {
            var d = Make(Stage.Rookie, SpiritType.none, bl, stats, null);
            for (int lv = 1; lv <= 60; lv += 3) {
                Console.WriteLine($"{bl} {lv} {F(d.GetObeyChance(lv))} {F(d.GetIdleChance(lv))}");
            }
        }

        // Digimon.GetEvolveChance
        Console.WriteLine("EVOLVE");
        for (int bl = 1; bl <= 100; bl += 3) {
            var d = Make(Stage.Rookie, SpiritType.none, bl, stats, null);
            for (int lv = 1; lv <= 100; lv += 7) {
                for (int pts = 1; pts <= 10; pts++) {
                    Console.WriteLine($"{bl} {lv} {pts} {F(d.GetEvolveChance(lv, pts))}");
                }
            }
        }

        // Digimon.GetBossStats -- RoundToInt of a float product, per branch
        Console.WriteLine("BOSSSTATS");
        foreach (var pair in new (Stage, SpiritType)[] {
                     (Stage.Spirit, SpiritType.Human), (Stage.Spirit, SpiritType.Ancient),
                     (Stage.Spirit, SpiritType.Animal), (Stage.Mega, SpiritType.none) }) {
            for (int hp = 1; hp <= 400; hp += 7) {
                var d = Make(pair.Item1, pair.Item2, 10, stats, Stats(hp, hp + 1, hp + 2, hp + 3));
                for (int lv = 1; lv <= 100; lv += 9) {
                    var s = d.GetBossStats(lv);
                    Console.WriteLine($"{(int)pair.Item1} {(int)pair.Item2} {hp} {lv} {s.HP} {s.EN} {s.CR} {s.AB}");
                }
            }
        }

        // Digimon.GetFriendlyStats -- CeilToInt against MaxExtraLevel
        Console.WriteLine("FRIENDLYSTATS");
        for (int bl = 1; bl <= 60; bl += 3) {
            for (int hp = 1; hp <= 300; hp += 11) {
                var d = Make(Stage.Rookie, SpiritType.none, bl, Stats(hp, hp + 5, hp + 9, hp + 13), null);
                int maxExtra = d.MaxExtraLevel;
                for (int extra = 0; extra <= maxExtra; extra += 5) {
                    var s = d.GetFriendlyStats(extra);
                    Console.WriteLine($"{bl} {hp} {extra} {s.HP} {s.EN} {s.CR} {s.AB}");
                }
            }
        }

        // MutableCombatStats.GetEnergyRank
        Console.WriteLine("ENERGYRANK");
        for (int en = 0; en <= 320; en++) {
            Console.WriteLine($"{en} {new MutableCombatStats(1, en, 1, 1).GetEnergyRank()}");
        }

        Console.WriteLine("END");
    }
}
