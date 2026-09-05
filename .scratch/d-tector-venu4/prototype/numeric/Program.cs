// C# reference for the numeric parity test (ticket 14).
//
// Reproduces Unity's arithmetic exactly: Mathf.Pow is (float)Math.Pow, every
// intermediate is a 32-bit float, and the floor/ceil happen where the original
// puts them. The Monkey C side runs the same sweeps and the two are diffed.
using System;

public static class Program {
    static float Pow(float a, float b) { return (float)Math.Pow(a, b); }
    static int FloorToInt(float f) { return (int)Math.Floor(f); }
    static int CeilToInt(float f) { return (int)Math.Ceiling(f); }

    // LogicManager.cs:453  GetPlayerLevel
    static int GetPlayerLevel(int playerXP) {
        if (playerXP == 0) { return 1; }
        float level = Pow(playerXP, 1f / 3f);
        return FloorToInt(level);
    }

    // LogicManager.cs:846  GetExperienceGained
    static uint GetExperienceGained(int friendlyLevel, int enemyLevel) {
        float a = 30 * enemyLevel;
        float b = Pow((2 * enemyLevel) + 10, 2.5f);
        float c = Pow(enemyLevel + friendlyLevel + 10, 2.5f);
        float d = 0.025f + (0.025f * friendlyLevel);
        if (d > 0.5f) { d = 0.5f; }
        float expGained = ((a * (b / c)) + 1) * d;
        return (uint)CeilToInt(expGained);
    }

    // Digimon.cs:73  GetSpiritCost
    static int GetSpiritCost(int baseCost, float decay, int playerLevel) {
        float currentCost = baseCost * Pow(0.5f, playerLevel / decay);
        return FloorToInt(currentCost);
    }

    // Digimon.cs:117  GetCallCost
    static int GetCallCost(int baseLevel, int playerLevel) {
        float percLevelDiff = baseLevel / (float)playerLevel;
        int levelDiff = playerLevel - baseLevel;
        if (percLevelDiff < 0.55f && levelDiff >= 10) { return 0; }
        if (percLevelDiff < 0.75f && levelDiff >= 5) { return 1; }
        if (percLevelDiff < 0.90f && levelDiff >= 2) { return 2; }
        if (percLevelDiff < 1f && levelDiff >= 1) { return 3; }
        if (percLevelDiff == 1f) { return 4; }
        if (percLevelDiff < 1.30f) { return 5; }
        if (percLevelDiff < 1.60f) { return 6; }
        if (percLevelDiff < 2f) { return 7; }
        if (percLevelDiff < 3f) { return 8; }
        return 9;
    }

    public static int Main(string[] args) {
        // 1. every XP at which the player's level changes -- the only thing a
        //    floor boundary can move
        Console.WriteLine("LEVELTRANS");
        int prev = GetPlayerLevel(0);
        for (int xp = 1; xp <= 300000; xp++) {
            int l = GetPlayerLevel(xp);
            if (l != prev) { Console.WriteLine(xp + " " + l); prev = l; }
        }

        // 2. experience gained, every level pair
        Console.WriteLine("EXPGRID");
        for (int f = 1; f <= 51; f++) {
            string row = "";
            for (int e = 1; e <= 51; e++) {
                row += (e > 1 ? "," : "") + GetExperienceGained(f, e);
            }
            Console.WriteLine(f + ":" + row);
        }

        // 3. spirit cost, every (baseCost, decay) the source uses
        Console.WriteLine("SPIRITCOST");
        int[] bases = { 20, 95, 10, 20, 30, 35, 40, 55 };
        float[] decays = { 20f, 50f, 20f, 30f, 30f, 40f, 50f, 60f };
        for (int k = 0; k < bases.Length; k++) {
            string row = "";
            for (int lv = 1; lv <= 99; lv++) {
                row += (lv > 1 ? "," : "") + GetSpiritCost(bases[k], decays[k], lv);
            }
            Console.WriteLine(bases[k] + "/" + decays[k] + ":" + row);
        }

        // 4. call cost, every (baseLevel, playerLevel) pair
        Console.WriteLine("CALLCOST");
        for (int b = 1; b <= 51; b++) {
            string row = "";
            for (int p = 1; p <= 51; p++) {
                row += (p > 1 ? "," : "") + GetCallCost(b, p);
            }
            Console.WriteLine(b + ":" + row);
        }
        Console.WriteLine("END");
        Margin.Report();
        return 0;
    }
}
