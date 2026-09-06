import Toybox.Lang;
import Toybox.Math;

// port of Logic/Extensions/MathExt.cs and Logic/Extensions/Tools.cs, plus the
// Random.Range shim ticket 11 decision 4 calls for.
module Kaisa {
    module MathExt {
        // Circular add: upper bound + 1 == lower bound. The C# byte and int
        // overloads differ only in the cast, and Monkey C has no byte, so
        // callers that held a byte clamp their own storage.
        function circularAdd(a as Number, b as Number,
                             upperBound as Number, lowerBound as Number) as Number {
            return getInsideBounds(a + b, upperBound, lowerBound);
        }

        // The original loops rather than taking a modulo, and so does this:
        // the two agree for every input the game produces, but the loop is
        // what the source guarantees for inputs far outside the range.
        function getInsideBounds(val as Number, upperBound as Number,
                                 lowerBound as Number) as Number {
            var range = upperBound - lowerBound + 1;
            var v = val;
            while (v < lowerBound) { v += range; }
            while (v > upperBound) { v -= range; }
            return v;
        }

        // Mathf.FloorToInt / CeilToInt. Math.floor and Math.ceil return the
        // input's type in Monkey C, so the conversion is explicit (ticket 11
        // decision 2).
        function floorToInt(f as Float) as Number {
            return Math.floor(f).toNumber();
        }

        function ceilToInt(f as Float) as Number {
            return Math.ceil(f).toNumber();
        }

        // Mathf.RoundToInt, which is System.Math.Round: **half to even**, not
        // half away from zero. Monkey C's Math.round rounds halves away from
        // zero, so a value landing exactly on .5 would differ -- 2.5 gives 2
        // in Unity and 3 here. Written out rather than assumed safe: the boss
        // and spirit stat formulas round products of floats thousands of times
        // per playthrough, and the numeric parity sweep would only find the
        // disagreement if the port could express it in the first place.
        function roundToInt(f as Float) as Number {
            var fl = Math.floor(f);
            var diff = f - fl;
            if (diff > 0.5) { return fl.toNumber() + 1; }
            if (diff < 0.5) { return fl.toNumber(); }
            var n = fl.toNumber();
            return ((n % 2) == 0) ? n : n + 1;
        }
    }

    // port of UnityEngine.Random.Range, which the source calls 33 times.
    //
    // Unity does not seed deterministically, so the sequence was never
    // reproducible between runs; what has to match is the BOUNDS and the
    // probabilities (ticket 11 decision 4). The two overloads differ in
    // exactly the way that is easy to get wrong:
    //
    //   Random.Range(int, int)     -- max EXCLUSIVE
    //   Random.Range(float, float) -- max INCLUSIVE
    //
    // An off-by-one here changes drop rates rather than crashing, so the
    // split is preserved in the names.
    module Rand {
        function rangeInt(minInclusive as Number, maxExclusive as Number) as Number {
            var span = maxExclusive - minInclusive;
            if (span <= 0) { return minInclusive; }
            return minInclusive + (Math.rand() % span);
        }

        function rangeFloat(minInclusive as Float, maxInclusive as Float) as Float {
            // Math.rand() is a non-negative Number with no documented upper
            // bound beyond the 32-bit signed range, so the unit interval is
            // built from its low 24 bits: 2^24 keeps every step exactly
            // representable in a Float.
            var unit = (Math.rand() % 16777216).toFloat() / 16777215.0;
            return minInclusive + (maxInclusive - minInclusive) * unit;
        }
    }

    module Tools {
        // Fisher-Yates, the same walk the source does, over Math.rand().
        function shuffle(list as Array) as Array {
            var i = list.size();
            while (i > 1) {
                i -= 1;
                var k = Rand.rangeInt(0, i + 1);
                var tempValue = list[k];
                list[k] = list[i];
                list[i] = tempValue;
            }
            return list;
        }

        function fill(array as Array, value) as Array {
            for (var i = 0; i < array.size(); i += 1) {
                array[i] = value;
            }
            return array;
        }

        function getRandomIndex(array as Array) as Number {
            return Rand.rangeInt(0, array.size());
        }

        // Returns null for an empty array, where C# returns default(T).
        function getRandomElement(array as Array) {
            if (array.size() == 0) { return null; }
            return array[getRandomIndex(array)];
        }

        function subArray(array as Array, index as Number, length as Number) as Array {
            return array.slice(index, index + length);
        }

        function reorderedAs(array as Array, indices as Array<Number>) as Array {
            var newArray = new [indices.size()];
            for (var i = 0; i < newArray.size(); i += 1) {
                newArray[i] = array[indices[i]];
            }
            return newArray;
        }
    }
}
