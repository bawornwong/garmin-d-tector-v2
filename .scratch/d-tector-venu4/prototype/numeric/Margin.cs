// How close does each formula come to a floor/ceil boundary? A parity test
// that passes with no headroom is luck; this measures the headroom.
using System;

public static class Margin {
    static float Pow(float a, float b) { return (float)Math.Pow(a, b); }

    public static void Report() {
        Console.WriteLine("### MARGIN ###");

        double worst = 1.0; string worstAt = "";
        for (int xp = 1; xp <= 300000; xp++) {
            float level = Pow(xp, 1f / 3f);
            double frac = level - Math.Floor(level);
            double d = Math.Min(frac, 1.0 - frac);
            if (d < worst) { worst = d; worstAt = "xp=" + xp + " level=" + level.ToString("R"); }
        }
        Console.WriteLine("GetPlayerLevel   closest to a floor boundary: " +
            worst.ToString("E3") + "  at " + worstAt);

        worst = 1.0; worstAt = "";
        for (int f = 1; f <= 51; f++) {
            for (int e = 1; e <= 51; e++) {
                float a = 30 * e;
                float b = Pow((2 * e) + 10, 2.5f);
                float c = Pow(e + f + 10, 2.5f);
                float d2 = 0.025f + (0.025f * f);
                if (d2 > 0.5f) { d2 = 0.5f; }
                float exp = ((a * (b / c)) + 1) * d2;
                double frac = exp - Math.Floor(exp);
                double d = Math.Min(frac, 1.0 - frac);
                if (d < worst) { worst = d; worstAt = "friendly=" + f + " enemy=" + e + " exp=" + exp.ToString("R"); }
            }
        }
        Console.WriteLine("GetExperienceGained closest to a ceil boundary: " +
            worst.ToString("E3") + "  at " + worstAt);

        int[] bases = { 20, 95, 10, 20, 30, 35, 40, 55 };
        float[] decays = { 20f, 50f, 20f, 30f, 30f, 40f, 50f, 60f };
        worst = 1.0; worstAt = "";
        for (int k = 0; k < bases.Length; k++) {
            for (int lv = 1; lv <= 99; lv++) {
                float cost = bases[k] * Pow(0.5f, lv / decays[k]);
                double frac = cost - Math.Floor(cost);
                double d = Math.Min(frac, 1.0 - frac);
                if (d < worst) { worst = d; worstAt = "base=" + bases[k] + " decay=" + decays[k] + " level=" + lv + " cost=" + cost.ToString("R"); }
            }
        }
        Console.WriteLine("GetSpiritCost    closest to a floor boundary: " +
            worst.ToString("E3") + "  at " + worstAt);

        // GetCallCost compares against literal thresholds, so the margin is
        // the distance from percLevelDiff to the nearest threshold it tests
        float[] th = { 0.55f, 0.75f, 0.90f, 1f, 1.30f, 1.60f, 2f, 3f };
        worst = 1.0; worstAt = "";
        for (int b = 1; b <= 51; b++) {
            for (int p = 1; p <= 51; p++) {
                float perc = b / (float)p;
                foreach (float t in th) {
                    double d = Math.Abs(perc - t);
                    if (d < worst && d > 0.0) { worst = d; worstAt = "base=" + b + " player=" + p + " perc=" + perc.ToString("R"); }
                }
            }
        }
        Console.WriteLine("GetCallCost      closest to a threshold (excluding exact hits): " +
            worst.ToString("E3") + "  at " + worstAt);
        Console.WriteLine("GetCallCost      exact threshold hits are intentional (perc == 1f returns 4)");
    }
}
