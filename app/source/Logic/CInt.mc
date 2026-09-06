import Toybox.Lang;
using Kaisa;

// port of Logic/Models/C_Int.cs
//
// "Circular Int": an int that wraps back to its lower bound once its upper
// bound is reached. Monkey C has no operator overloading, so every C#
// operator becomes a named method (ADR 2 / ticket 11) -- `a + b` at the
// original call sites becomes `a.add(b)`.
//
// The original's operators are NOT uniformly non-mutating: `+` and `-`
// build and return a NEW C_Int, but `*`, `/`, `%`, `<<`, `>>`, `++`, `--`
// mutate the receiver in place and return it. That distinction is preserved
// exactly below, because it is observable behaviour, not an implementation
// detail.
//
// KNOWN SOURCE BUG, reproduced deliberately: C#'s `operator /` reads
//   c._varInt = c.GetInsideBounds(c._varInt * b);
// -- multiplication, not division. `div()` below does the same. This is
// not a typo in the port; it is the original's own bug, and ADR 2 forbids
// fixing what the original does not fix.
class CInt {
    var _varInt as Number = 0;
    var lowerBound as Number;
    var upperBound as Number;

    function initialize(val as Number, upperBoundIn as Number, lowerBoundIn as Number) {
        if (upperBoundIn <= lowerBoundIn) {
            throw new Kaisa.IllegalBoundsException(
                "The upper bound of the VarInt must be higher than the lower bound");
        }
        upperBound = upperBoundIn;
        lowerBound = lowerBoundIn;
        setValue(val);
    }

    function range() as Number {
        return upperBound - lowerBound + 1;
    }

    function setValue(val as Number) as CInt {
        if (val < lowerBound || val > upperBound) {
            throw new Kaisa.IllegalBoundsException(
                "The value of the VarInt must be within its bounds.");
        }
        _varInt = val;
        return self;
    }

    function toString() as String {
        return _varInt.toString();
    }

    function toNumber() as Number {
        return _varInt;
    }

    function getInsideBounds(val as Number) as Number {
        var v = val;
        if (v < lowerBound) {
            while (v < lowerBound) { v += range(); }
        }
        if (v > upperBound) {
            while (v > upperBound) { v -= range(); }
        }
        return v;
    }

    // --- non-mutating: builds a new CInt, `a` is unchanged -----------------

    function add(b as CInt) as CInt {
        return addInt(b._varInt);
    }
    function addInt(b as Number) as CInt {
        var c = new CInt(_varInt, upperBound, lowerBound);
        c._varInt = c.getInsideBounds(c._varInt + b);
        return c;
    }

    function sub(b as CInt) as CInt {
        return subInt(b._varInt);
    }
    function subInt(b as Number) as CInt {
        var c = new CInt(_varInt, upperBound, lowerBound);
        c._varInt = c.getInsideBounds(c._varInt - b);
        return c;
    }

    // --- mutating: `a` itself changes, and is returned ---------------------

    function increment() as CInt {
        _varInt = getInsideBounds(_varInt + 1);
        return self;
    }
    function decrement() as CInt {
        _varInt = getInsideBounds(_varInt - 1);
        return self;
    }

    function mul(b as CInt) as CInt {
        return mulInt(b._varInt);
    }
    function mulInt(b as Number) as CInt {
        _varInt = getInsideBounds(_varInt * b);
        return self;
    }

    // see the class comment: this reproduces the source's own bug
    function div(b as CInt) as CInt {
        return divInt(b._varInt);
    }
    function divInt(b as Number) as CInt {
        _varInt = getInsideBounds(_varInt * b);
        return self;
    }

    function mod(b as CInt) as CInt {
        return modInt(b._varInt);
    }
    function modInt(b as Number) as CInt {
        _varInt = _varInt % b;   // the original applies no bounds clamp here either
        return self;
    }

    function shl(b as Number) as CInt {
        _varInt = getInsideBounds(_varInt << b);
        return self;
    }
    function shr(b as Number) as CInt {
        _varInt = getInsideBounds(_varInt >> b);
        return self;
    }

    // --- comparisons: no bounds logic, plain value comparisons -------------

    function eq(b as CInt) as Boolean { return eqInt(b._varInt); }
    function eqInt(b as Number) as Boolean { return _varInt == b; }

    function neq(b as CInt) as Boolean { return neqInt(b._varInt); }
    function neqInt(b as Number) as Boolean { return _varInt != b; }

    function lt(b as CInt) as Boolean { return ltInt(b._varInt); }
    function ltInt(b as Number) as Boolean { return _varInt < b; }

    function gt(b as CInt) as Boolean { return gtInt(b._varInt); }
    function gtInt(b as Number) as Boolean { return _varInt > b; }

    function lte(b as CInt) as Boolean { return lteInt(b._varInt); }
    function lteInt(b as Number) as Boolean { return _varInt <= b; }

    function gte(b as CInt) as Boolean { return gteInt(b._varInt); }
    function gteInt(b as Number) as Boolean { return _varInt >= b; }

    function equalsCInt(other as CInt) as Boolean {
        return _varInt == other._varInt && lowerBound == other.lowerBound
            && upperBound == other.upperBound && range() == other.range();
    }
}
