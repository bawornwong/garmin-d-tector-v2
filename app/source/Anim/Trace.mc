import Toybox.Lang;
import Toybox.System;

// The event trace the animation golden diffs read (ADR 12, ticket 08's
// "identical means the event and schedule diff").
//
// The point of tracing the REAL display list rather than a stubbed one is
// that the check then covers the ported routine as it actually runs -- the
// builder calls, their arguments and their scheduled times -- instead of a
// second transcription written to be compared against the first.
//
// Every function here exists twice, `(:debug)` and `(:release)`, because a
// call site cannot be annotated: the release build compiles the empty pair
// and the calls cost nothing.
module Kaisa {
    module Trace {
        // Set by Runner before each step, so an event's timestamp is the
        // step's SCHEDULED time rather than whenever the frame got round to
        // it -- the same clock the C# harness prints.
        (:debug) var nowMs as Double = 0.0d;
        (:debug) var enabled as Boolean = false;

        (:debug)
        function event(text as String) as Void {
            if (!enabled) { return; }
            System.println(nowMs.format("%12.4f") + " " + text);
        }

        (:release)
        function event(text as String) as Void {
        }

        // The display-list hooks. `name` is the element's name, which is what
        // the original's trace keys on too.
        (:debug)
        function el(name as String, op as String) as Void {
            event(op + " " + name);
        }

        (:release)
        function el(name as String, op as String) as Void {
        }

        (:debug)
        function el1(name as String, op as String, a) as Void {
            event(op + " " + name + " " + a);
        }

        (:release)
        function el1(name as String, op as String, a) as Void {
        }

        (:debug)
        function el2(name as String, op as String, a, b) as Void {
            event(op + " " + name + " " + a + " " + b);
        }

        (:release)
        function el2(name as String, op as String, a, b) as Void {
        }

        // A sprite reference prints as its SpriteDatabase field name, which is
        // what the original prints; Kaisa.Sprites carries the reverse table in
        // debug builds only.
        (:debug)
        function sprite(name as String, op as String, ref as Array<Number>?) as Void {
            event(op + " " + name + " " + Kaisa.Sprites.nameOf(ref));
        }

        (:release)
        function sprite(name as String, op as String, ref as Array<Number>?) as Void {
        }

        // The original sets an inverted COPY of a sprite, and prints it as
        // "inv:<the sprite it was made from>".
        (:debug)
        function invertedSprite(name as String, ref as Array<Number>?) as Void {
            event("setSprite " + name + " inv:" + Kaisa.Sprites.nameOf(ref));
        }

        (:release)
        function invertedSprite(name as String, ref as Array<Number>?) as Void {
        }
    }
}
