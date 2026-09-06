import Toybox.Lang;

// port of Logic/Apps/Map.cs
//
// The world map: pan between a world's four maps, pick an area, see the
// distance it costs, and travel there. A world with lockTravel or a single
// map refuses the panning with the error beep.
//
// Areas are numbered from 0 in the data and from 1 on screen, which is why
// the label is `area{n+1}` -- the original's comment says so too.
class Map extends DigiviceApp {
    var currentScreen as Number = 0;    // 0 map, 1 choosing area, 2 distance

    var originalWorld as Number = 0;
    var originalArea as Number = 0;
    var originalMap as Number = 0;
    var displayMap as Number = 0;
    var areasInCurrentMap as Array<Number> = [];

    var cbMap as ContainerBuilder?;
    var currentAreaMarker as RectangleBuilder?;

    var displayArea as Number = 0;
    var hoveredMarker as RectangleBuilder?;
    var hoveredAreaName as TextBoxBuilder?;

    var distanceScreen as SpriteBuilder?;
    var completedMarkers as Array<RectangleBuilder> = [];

    function initialize(gmIn as GameManager, controllerIn, parent as ScreenElement) {
        DigiviceApp.initialize(gmIn, controllerIn, parent);
    }

    function selectedArea() as Number {
        return areasInCurrentMap[displayArea];
    }

    function originalAreaIndexInCurrentMap() as Number {
        for (var i = 0; i < areasInCurrentMap.size(); i += 1) {
            if (areasInCurrentMap[i] == originalArea) { return i; }
        }
        return 0;
    }

    // --- Input ---

    function inputA() as Void {
        if (currentScreen == 0) {
            gm.audioMgr.playButtonA();
            openAreaSelection();
        } else if (currentScreen == 1) {
            gm.audioMgr.playButtonA();
            openViewDistance();
        } else if (currentScreen == 2) {
            gm.audioMgr.playButtonA();
            chooseArea();
        }
    }

    function inputB() as Void {
        if (currentScreen == 0) {
            gm.audioMgr.playButtonB();
            closeApp(Kaisa.SCREEN_MAIN_MENU);
        } else if (currentScreen == 1) {
            gm.audioMgr.playButtonB();
            closeAreaSelection();
        } else if (currentScreen == 2) {
            gm.audioMgr.playButtonB();
            closeViewDistance();
        }
    }

    function inputLeft() as Void { side(Kaisa.DIR_LEFT); }
    function inputRight() as Void { side(Kaisa.DIR_RIGHT); }

    function side(dir as Number) as Void {
        var lockTravel = gm.data.worldLockTravel(originalWorld);
        if (currentScreen == 0) {
            if (lockTravel || !gm.data.worldMultiMap(originalWorld)) {
                gm.audioMgr.playButtonB();
            } else {
                gm.audioMgr.playButtonA();
                navigateMap(dir);
            }
        } else if (currentScreen == 1) {
            if (lockTravel) {
                gm.audioMgr.playButtonB();
            } else {
                gm.audioMgr.playButtonA();
                navigateAreaSelection(dir);
            }
        } else if (currentScreen == 2) {
            gm.audioMgr.playButtonB();
        }
    }

    function startApp() as Void {
        loadInitialMapData();
        drawMap();
    }

    function loadInitialMapData() as Void {
        originalWorld = gm.worldMgr.currentWorld();
        originalMap = gm.worldMgr.currentMap();
        originalArea = gm.worldMgr.currentArea();
        displayArea = originalArea;
        displayMap = originalMap;
        areasInCurrentMap = gm.worldMgr.areasInMap(originalWorld, displayMap);
    }

    function drawMap() as Void {
        cbMap = gm.buildMapScreen(originalWorld, screen);
        focusCurrentMap();
        drawAreaMarkers(true);
    }

    // A multi-map world is a 64x64 sheet of four 32x32 maps; focusing one is
    // sliding that container so the wanted quarter sits on the canvas.
    function focusCurrentMap() as Void {
        if (displayMap == 0) { cbMap.setPosition(0, 0); }
        else if (displayMap == 1) { cbMap.setPosition(0, -32); }
        else if (displayMap == 2) { cbMap.setPosition(-32, -32); }
        else if (displayMap == 3) { cbMap.setPosition(-32, 0); }
        clearMarkers();
        drawAreaMarkers(true);
    }

    function navigateMap(dir as Number) as Void {
        var mapBefore = displayMap;
        if (dir == Kaisa.DIR_LEFT) {
            displayMap = Kaisa.MathExt.circularAdd(displayMap, -1, 3, 0);
        } else {
            displayMap = Kaisa.MathExt.circularAdd(displayMap, 1, 3, 0);
        }
        areasInCurrentMap = gm.worldMgr.areasInMap(originalWorld, displayMap);
        gm.enqueueAnimation(new TravelMap(gm, originalWorld, mapBefore, displayMap, 1.5));
        focusCurrentMap();
    }

    function drawAreaMarkers(displayOriginalArea as Boolean) as Void {
        clearMarkers();
        var shown = gm.worldMgr.areasInMap(originalWorld, displayMap);
        for (var k = 0; k < shown.size(); k += 1) {
            var i = shown[k];
            var area = gm.data.worldArea(originalWorld, i);
            if (gm.worldMgr.getAreaCompleted(originalWorld, i)) {
                completedMarkers.add(
                    Kaisa.ScreenBuilder.buildRectangle("Area " + i + " Marker", screen)
                        .setSize(2, 2).setPosition(area[3], area[4]));
            }
            if (displayOriginalArea && originalArea == i) {
                currentAreaMarker =
                    Kaisa.ScreenBuilder.buildRectangle("Current Area Marker", screen)
                        .setSize(2, 2).setPosition(area[3], area[4]).setFlickPeriodMs(250, true);
                completedMarkers.add(currentAreaMarker);
            }
        }
    }

    function clearMarkers() as Void {
        for (var i = 0; i < completedMarkers.size(); i += 1) {
            completedMarkers[i].dispose();
        }
        completedMarkers = [];
        currentAreaMarker = null;
    }

    function openAreaSelection() as Void {
        currentScreen = 1;
        // "If the player is entering the map he already is in, start hovering
        // in his current area, rather than the 'area 0' of that map."
        displayArea = (displayMap == originalMap) ? originalAreaIndexInCurrentMap() : 0;

        if (currentAreaMarker != null) { currentAreaMarker.setActive(false); }

        var area = gm.data.worldArea(originalWorld, selectedArea());
        hoveredMarker = Kaisa.ScreenBuilder.buildRectangle("OptionMarker", screen)
            .setSize(2, 2).setFlickPeriodMs(250, true).setPosition(area[3], area[4]);
        hoveredAreaName = Kaisa.ScreenBuilder.buildTextBox("AreaName", screen, Kaisa.Font.SMALL)
            .setText("area").setPosition(28, 5);

        if (displayMap == 0 || displayMap == 3) {
            hoveredAreaName.setPosition(2, 1);
        } else {
            hoveredAreaName.setPosition(2, 26);
        }
        hoveredAreaName.setText(areaLabel(selectedArea()));
    }

    // string.Format("area{0:00}", n + 1) -- areas are 1-based on screen.
    function areaLabel(area as Number) as String {
        var n = area + 1;
        return "area" + ((n < 10) ? "0" : "") + n;
    }

    function navigateAreaSelection(dir as Number) as Void {
        var upper = areasInCurrentMap.size() - 1;
        if (dir == Kaisa.DIR_LEFT) {
            displayArea = Kaisa.MathExt.circularAdd(displayArea, -1, upper, 0);
        } else {
            displayArea = Kaisa.MathExt.circularAdd(displayArea, 1, upper, 0);
        }
        var area = gm.data.worldArea(originalWorld, selectedArea());
        hoveredMarker.setPosition(area[3], area[4]);
        hoveredAreaName.setText(areaLabel(selectedArea()));
    }

    function closeAreaSelection() as Void {
        currentScreen = 0;
        hoveredMarker.dispose();
        hoveredAreaName.dispose();
        if (currentAreaMarker != null) { currentAreaMarker.setActive(true); }
    }

    function openViewDistance() as Void {
        currentScreen = 2;
        // "If the area chosen is the area the player is already in, the
        // distance will not change."
        var areaDist = (selectedArea() == originalArea)
            ? gm.worldMgr.currentDistance()
            : gm.data.worldArea(originalWorld, selectedArea())[2];

        distanceScreen = Kaisa.ScreenBuilder.buildSprite("DistanceScreen", screen)
            .setSprite(Kaisa.Sprites.MAP_DISTANCE_SCREEN);
        Kaisa.ScreenBuilder.buildTextBox("Distance", distanceScreen, Kaisa.Font.REGULAR)
            .setText(areaDist.toString()).setSize(25, 5).setPosition(6, 25)
            .setAlignment(Kaisa.Text.ANCHOR_UPPER_RIGHT);
    }

    function closeViewDistance() as Void {
        currentScreen = 1;
        distanceScreen.dispose();
    }

    function chooseArea() as Void {
        if (selectedArea() != originalArea) {
            gm.worldMgr.moveToArea(originalWorld, selectedArea());
        }
        closeApp(Kaisa.SCREEN_CHARACTER);
    }
}
