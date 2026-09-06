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
}
