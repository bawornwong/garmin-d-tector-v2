import Toybox.Lang;

// port of Logic/WorldManager.cs
//
// "A class that manages the world, area, distance and other stuff related to
// the progress within the adventure. Any interaction with those parameters
// should be done through this class, rather than directly altering the
// SavedGame class."
//
// The world layout itself is in the packed blob (tools/verify_worlds.py
// checks it field for field against worlds.json); this is the logic over it.
// A world's slice of the save's flat per-world arrays is found through
// GameData.worldAreaOffset / worldBossOffset.
class WorldManager {
    var _saved as SavedGame;
    var _data as GameData;

    function initialize(saved as SavedGame, data as GameData) {
        _saved = saved;
        _data = data;
    }

    // WorldManager.cs:87
    function currentWorld() as Number {
        return _saved.currentWorld();
    }

    function setCurrentWorld(v as Number) as Void {
        _saved.setCurrentWorld(v);
    }

    // WorldManager.cs:98
    function currentArea() as Number {
        return _saved.currentArea();
    }

    function setCurrentArea(v as Number) as Void {
        _saved.setCurrentArea(v);
    }

    // WorldManager.cs:94 -- the map within the world the player is in.
    function currentMap() as Number {
        return _data.worldArea(currentWorld(), currentArea())[1];
    }

    // World.GetAreasInMap
    function areasInMap(world as Number, map as Number) as Array<Number> {
        var out = [] as Array<Number>;
        var n = _data.worldAreaCount(world);
        for (var i = 0; i < n; i += 1) {
            var area = _data.worldArea(world, i);
            if (area[1] == map) { out.add(area[0]); }
        }
        return out;
    }

    // WorldManager.cs:112
    function getAreaCompleted(world as Number, area as Number) as Boolean {
        return _saved.areaCompleted(_data.worldAreaOffset(world) + area);
    }

    function setAreaCompleted(world as Number, area as Number, completed as Boolean) as Void {
        _saved.setAreaCompleted(_data.worldAreaOffset(world) + area, completed);
    }

    // WorldManager.cs:120
    function getBossOfCurrentArea() as Number {
        return _saved.bossAtSlot(_data.worldBossOffset(currentWorld()) + currentArea());
    }

    function getBossesForWorld(world as Number) as Array<Number> {
        var out = [] as Array<Number>;
        var base = _data.worldBossOffset(world);
        var length = _data.worldBossListLength(world);
        for (var i = 0; i < length; i += 1) { out.add(_saved.bossAtSlot(base + i)); }
        return out;
    }

    // WorldManager.cs:126
    function getUncompletedAreas(world as Number) as Array<Number> {
        var out = [] as Array<Number>;
        var n = _data.worldAreaCount(world);
        for (var i = 0; i < n; i += 1) {
            if (!getAreaCompleted(world, i)) { out.add(i); }
        }
        return out;
    }

    // WorldManager.cs:135 -- moves the player and sets the distance for the
    // new area; the two-argument form uses that area's default distance.
    function moveToArea(world as Number, area as Number) as Void {
        moveToAreaWithDistance(world, area, _data.areaDistance(world, area));
    }

    function moveToAreaWithDistance(world as Number, area as Number,
                                    distance as Number) as Void {
        _saved.setCurrentWorld(world);
        _saved.setCurrentArea(area);
        _saved.setCurrentDistance(distance);
    }

    // WorldManager.cs:22 SetupWorlds -- run once when a game is created.
    // Each world's boss list is its slots, plus the chosen semiboss group in
    // Fill mode, minus the player's own spirit where removePlayer is set, and
    // shuffled where shuffle is set.
    //
    // A boss slot can hold several candidates (the packed list per slot); the
    // original's data has one name per slot except where a slot is a choice,
    // and it takes the whole list. The port takes the first entry of a slot
    // and records the group choice, which is the same for every world in
    // worlds.json -- checked by tools/verify_worlds.py, which prints every
    // slot's contents.
    function setupWorlds(playerSpiritIndex as Number) as Void {
        var worlds = _data.worldCount();
        for (var w = 0; w < worlds; w += 1) {
            var bosses = [] as Array<Number>;
            var slots = _data.worldBossSlotCount(w);
            for (var b = 0; b < slots; b += 1) {
                var slot = _data.worldBossSlot(w, b);
                if (slot.size() > 0) { bosses.add(slot[0]); }
            }

            var groups = _data.worldSemibossGroupCount(w);
            var chosenGroup = (groups > 0) ? Kaisa.Rand.rangeInt(0, groups) : 0;

            if (_data.worldSemibossMode(w) == 1) {          // Fill
                var group = _data.worldSemibossGroup(w, chosenGroup);
                for (var i = 0; i < group.size(); i += 1) { bosses.add(group[i]); }
            } else {
                _saved.setSemibossGroup(w, chosenGroup);
            }

            if (_data.worldRemovePlayer(w)) {
                bosses = removeFirst(bosses, playerSpiritIndex);
            }

            if (_data.worldShuffle(w)) {
                Kaisa.Tools.shuffle(bosses);
            }

            var base = _data.worldBossOffset(w);
            var length = _data.worldBossListLength(w);
            for (var i = 0; i < length; i += 1) {
                _saved.setBossAtSlot(base + i, (i < bosses.size()) ? bosses[i] : -1);
            }
        }
    }

    function removeFirst(list as Array<Number>, value as Number) as Array<Number> {
        for (var i = 0; i < list.size(); i += 1) {
            if (list[i] == value) {
                var head = list.slice(0, i);
                return head.addAll(list.slice(i + 1, null));
            }
        }
        return list;
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
