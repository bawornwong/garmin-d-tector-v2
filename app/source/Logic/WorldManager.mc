import Toybox.Lang;

// port of Logic/WorldManager.cs -- the distance and step counters.
//
// The rest of WorldManager (area layout, boss assignment, the event
// scheduler, MoveToArea) arrives with the Map app; SPEC section 8 still lists
// the world rules as unsurveyed, and translating them ahead of that survey
// would be guessing.
class WorldManager {
    var _saved as SavedGame;

    function initialize(saved as SavedGame) {
        _saved = saved;
    }

    // WorldManager.cs:80
    function currentDistance() as Number {
        return _saved.currentDistance();
    }

    function setCurrentDistance(v as Number) as Void {
        _saved.setCurrentDistance(v);
    }

    // WorldManager.cs:107
    function totalSteps() as Number {
        return _saved.steps();
    }

    // WorldManager.cs:150. Every so many steps an event becomes pending; the
    // interval is 300 to 500 steps, drawn when the previous one fires.
    function takeSteps(steps as Number) as Void {
        _saved.setStepsToNextEvent(_saved.stepsToNextEvent() - steps);
        _saved.setSteps(_saved.steps() + steps);

        if (_saved.stepsToNextEvent() <= 0 && currentDistance() > 1) {
            _saved.setStepsToNextEvent(Kaisa.Rand.rangeInt(3, 6) * 100);
            _saved.setSavedEvent(1);
        }
    }

    // WorldManager.cs:166 -- reduces the distance and returns how much was
    // actually removed, stopping at the next event's distance.
    //
    // `nextStop` is 1 here because the semiboss checks that would move it are
    // commented out in the original, and the world rules they belong to are
    // unsurveyed (SPEC section 8). The live path is translated exactly; the
    // dead one is not invented.
    function reduceDistance(distance as Number) as Number {
        var nextStop = 1;

        if (currentDistance() - distance <= nextStop) {
            setCurrentDistance(nextStop);
            // The original deliberately does NOT set a boss event here:
            // "Do not trigger boss events unless the player shakes the device
            // or presses B."
            return currentDistance() - 1 - nextStop;
        } else {
            setCurrentDistance(currentDistance() - distance);
            return distance;
        }
    }

    // WorldManager.cs:199 -- bypasses boss encounters.
    function forceReduceDistance(distance as Number) as Void {
        setCurrentDistance(currentDistance() - distance);
    }

    // WorldManager.cs:204
    function increaseDistance(distance as Number) as Void {
        setCurrentDistance(currentDistance() + distance);
    }
}
