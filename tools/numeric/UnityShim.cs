// The parts of UnityEngine and Kaisa.Digivice that Logic/Models/Digimon.cs
// touches, so the ORIGINAL file can be compiled and swept unmodified.
//
// Compiling the real source rather than a hand-copy is the whole point: a
// transcribed reference would only prove the transcription (ADR 12). The
// shim is therefore deliberately tiny -- Mathf, and the one Database method
// Digimon's Rarity property calls.
using System;

namespace UnityEngine {
    public static class Mathf {
        public static float Pow(float f, float p) => (float)Math.Pow(f, p);
        public static float Abs(float f) => Math.Abs(f);
        public static int FloorToInt(float f) => (int)Math.Floor(f);
        public static int CeilToInt(float f) => (int)Math.Ceiling(f);
        public static int RoundToInt(float f) => (int)Math.Round(f);
    }
}

namespace Kaisa.Digivice {
    public static class Database {
        // Digimon.Rarity is never read by the sweep; the member only has to
        // exist for the file to compile.
        public static Rarity GetDigimonRarity(string digimon) => Rarity.none;
    }
}
