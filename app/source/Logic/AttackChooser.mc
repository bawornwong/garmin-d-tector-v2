import Toybox.Lang;

// port of Logic/AttackChooser.cs
//
// Picks the enemy's attack each turn, weighted by its own stats: a Digimon
// with high CR crushes more often. The weights are 30 + the stat, so even a
// zero stat is chosen sometimes.
//
// The original seeds a System.Random with `seed * digimon.GetHashCode()`, so
// the same enemy in the same battle plays the same sequence -- the seed comes
// from the save's three battle seeds. Two things stand in the way of copying
// that literally, and neither changes what the player sees:
//
//   - C#'s string GetHashCode is implementation-defined, and Monkey C has no
//     equivalent. The port seeds from the Digimon's INDEX, which is the same
//     identity by ADR 7.
//   - Monkey C has no seedable RNG object; Math.srand seeds one global
//     sequence, which a per-enemy chooser cannot own. So this carries its own
//     LCG -- the constants are Numerical Recipes' -- which is deterministic,
//     cheap, and reproduces what the original guarantees: the same enemy in
//     the same battle attacks the same way twice (ticket 11 decision 4).
class AttackChooser {
    var _state as Number;
    var _stats as MutableCombatStats;

    function initialize(seed as Number, digimonIndex as Number,
                        digimonStats as MutableCombatStats) {
        _state = seed * (digimonIndex + 1);
        _stats = digimonStats;
    }

    // The next attack: 0 energy, 1 crush, 2 ability.
    function next() as Number {
        var chanceEN = 30 + _stats.en;
        var chanceCR = 30 + _stats.cr;
        var chanceAB = 30 + _stats.ab;

        var total = chanceEN + chanceCR + chanceAB;
        var rngNumber = nextInt(total);

        if (rngNumber < chanceEN) { return 0; }
        if (rngNumber < (chanceEN + chanceCR)) { return 1; }
        return 2;
    }

    // A 31-bit linear congruential step, kept positive.
    function nextInt(bound as Number) as Number {
        _state = (_state * 1103515245 + 12345) & 0x7FFFFFFF;
        if (bound <= 0) { return 0; }
        return _state % bound;
    }
}
