import Toybox.Lang;

// port of Logic/Apps/DatabaseApp.cs
//
// Six screens in one app: the stage menu, the spirit element menu, the
// gallery of one stage's unlocked Digimon, the three data pages for one
// Digimon, the D-Dock chooser and the D-Dock display. It is the app that
// exercises everything Status did not -- paging, nested menus, per-Digimon
// stats, and three coroutines.
//
// Digimon are indices, not names (ADR 7): `galleryList` holds packed-data
// indices, and `gm.isInDock` compares indices.
class DatabaseApp extends DigiviceApp {
    // The original's private enum ScreenDatabase, with its own TODO to
    // replace it with an int; here it is one.
    const SCREEN_MENU = 0;
    const SCREEN_MENU_SPIRIT = 1;
    const SCREEN_GALLERY = 2;
    const SCREEN_PAGES = 3;
    const SCREEN_DDOCK_LIST = 4;
    const SCREEN_DDOCK_DISPLAY = 5;

    var screenAnimation as Fiber?;
    var currentScreen as Number = 0;
    var menuIndex as Number = 0;

    // Gallery viewer
    var digimonIsInDDock as Boolean = false;
    var galleryList as Array<Number> = [];
    var galleryIndex as Number = 0;

    // Hybrid gallery menu
    var availableElements as Array<Number> = [];
    var elementIndex as Number = 0;

    // Data pages
    var pageIndex as Number = 0;
    var pageDigimon as Digimon?;
    var digimonNameSign as TextBoxBuilder?;

    // D-Dock list/display
    var ddockIndex as Number = 0;

    // DigiviceApp.navigationCoroutine
    var navigation as Fiber?;

    function initialize(gmIn as GameManager, controllerIn, parent as ScreenElement) {
        DigiviceApp.initialize(gmIn, controllerIn, parent);
    }

    function selectedElement() as Number {
        return availableElements[elementIndex];
    }

    // --- Input ---

    function inputA() as Void {
        if (currentScreen == SCREEN_MENU) {
            galleryList = gm.getAllUnlockedDigimonInStage(menuIndex);
            if (galleryList.size() > 0) {
                gm.audioMgr.playButtonA();
                if (menuIndex < 6) {
                    openGallery();
                } else if (menuIndex == 6) {
                    openSpiritMenu();
                }
            } else {
                gm.audioMgr.playButtonB();
            }
        } else if (currentScreen == SCREEN_MENU_SPIRIT) {
            if (selectedElement() < 10) {
                galleryList = gm.getAllUnlockedSpiritsOfElement(selectedElement());
                if (galleryList.size() > 0) {
                    gm.audioMgr.playButtonA();
                    openGallery();
                } else {
                    gm.audioMgr.playButtonB();
                }
            } else {
                galleryList = gm.getAllUnlockedFusionDigimon();
                if (galleryList.size() > 0) {
                    gm.audioMgr.playButtonA();
                    openGallery();
                } else {
                    gm.audioMgr.playButtonB();
                }
            }
        } else if (currentScreen == SCREEN_GALLERY) {
            gm.audioMgr.playButtonA();
            openPages();
        } else if (currentScreen == SCREEN_PAGES) {
            gm.audioMgr.playButtonA();
            openDDockList();
        } else if (currentScreen == SCREEN_DDOCK_LIST) {
            gm.audioMgr.playButtonA();
            openDDockDisplay();
        } else if (currentScreen == SCREEN_DDOCK_DISPLAY) {
            chooseDDock();
        }
    }

    function inputB() as Void {
        if (currentScreen == SCREEN_MENU) {
            gm.audioMgr.playButtonB();
            closeApp(Kaisa.SCREEN_MAIN_MENU);
        } else if (currentScreen == SCREEN_MENU_SPIRIT) {
            gm.audioMgr.playButtonB();
            closeSpiritMenu();
        } else if (currentScreen == SCREEN_GALLERY) {
            gm.audioMgr.playButtonB();
            closeGallery();
        } else if (currentScreen == SCREEN_PAGES) {
            gm.audioMgr.playButtonB();
            closePages();
        } else if (currentScreen == SCREEN_DDOCK_LIST) {
            gm.audioMgr.playButtonB();
            closeDDockList();
        } else if (currentScreen == SCREEN_DDOCK_DISPLAY) {
            gm.audioMgr.playButtonB();
            closeDDockDisplay();
        }
    }

    function inputLeft() as Void {
        navigate(Kaisa.DIR_LEFT);
    }

    function inputRight() as Void {
        navigate(Kaisa.DIR_RIGHT);
    }

    // InputLeft and InputRight differ only in the direction they pass.
    function navigate(dir as Number) as Void {
        if (currentScreen == SCREEN_MENU) {
            gm.audioMgr.playButtonA();
            navigateStageMenu(dir);
        } else if (currentScreen == SCREEN_MENU_SPIRIT) {
            gm.audioMgr.playButtonA();
            navigateSpiritMenu(dir);
        } else if (currentScreen == SCREEN_PAGES) {
            gm.audioMgr.playButtonA();
            navigatePages(dir);
        } else if (currentScreen == SCREEN_DDOCK_LIST || currentScreen == SCREEN_DDOCK_DISPLAY) {
            gm.audioMgr.playButtonA();
            navigateDDock(dir);
        }
    }

    function inputLeftDown() as Void {
        holdNavigation(Kaisa.DIR_LEFT);
    }

    function inputRightDown() as Void {
        holdNavigation(Kaisa.DIR_RIGHT);
    }

    function holdNavigation(dir as Number) as Void {
        if (currentScreen == SCREEN_GALLERY) {
            if (galleryList.size() <= 1) {
                gm.audioMgr.playButtonB();
            } else {
                startNavigation(dir);
            }
        }
    }

    function inputLeftUp() as Void {
        stopNavigation();
    }

    function inputRightUp() as Void {
        stopNavigation();
    }

    // DigiviceApp.StartNavigation / StopNavigation, with AutoNavigateDir as a
    // routine: hold a side to page the gallery, fast, until released.
    function startNavigation(dir as Number) as Void {
        stopNavigation();
        navigation = gm.runner.start(new AutoNavigateDir(self, dir));
    }

    function stopNavigation() as Void {
        if (navigation != null) {
            gm.runner.stop(navigation);
            navigation = null;
        }
    }

    function dispose() as Void {
        stopNavigation();
        stopScreenAnimation();
        DigiviceApp.dispose();
    }

    function stopScreenAnimation() as Void {
        if (screenAnimation != null) {
            gm.runner.stop(screenAnimation);
            screenAnimation = null;
        }
    }

    function startApp() as Void {
        drawScreen();
    }

    // The original redraws only when something changes -- there is no
    // InvokeRepeating here, unlike Status -- so tick() stays empty and every
    // navigate/open/close call ends in drawScreen().

    function drawScreen() as Void {
        // "Stop all coroutines, except if the digimon name sign has a value
        // and we are still in the 'Pages' screen."
        if (!(digimonNameSign != null && currentScreen == SCREEN_PAGES)) {
            stopScreenAnimation();
        }
        // "Destroy all children, except the ones called 'NameSign' if we are
        // in the 'Pages' screen."
        //
        // The kept child is stepped over rather than disposed and re-added:
        // the original never destroys it, and the screen diff sees the
        // difference (tools/verify_screens.py).
        var kept = 0;
        var i = 0;
        while (i < screen.children.size()) {
            var child = screen.children[i];
            if (currentScreen == SCREEN_PAGES && child.name.equals("NameSign")) {
                kept += 1;
                i += 1;
            } else {
                child.dispose();        // dispose unlinks, so i stays put
            }
        }
        // Unity turns a destroyed GameObject's reference into null; the port
        // drops it here instead.
        if (kept == 0) {
            digimonNameSign = null;
        }

        if (currentScreen == SCREEN_MENU) {
            setScreen(Kaisa.Sprites.DATABASE_SECTIONS[menuIndex]);
        } else if (currentScreen == SCREEN_MENU_SPIRIT) {
            if (selectedElement() < 10) {
                setScreen(Kaisa.Sprites.ELEMENTS[selectedElement()]);
            } else {
                setScreen(Kaisa.Sprites.DATABASE_SPIRIT_FUSION);
            }
        } else if (currentScreen == SCREEN_GALLERY) {
            var displayDigimon = galleryList[galleryIndex];
            digimonIsInDDock = gm.isInDock(displayDigimon);
            setScreen(digimonIsInDDock ? Kaisa.Sprites.INVERTED_ARROWS_SMALL
                                       : Kaisa.Sprites.ARROWS_SMALL);

            var spriteRegular = gm.data.spriteRef(displayDigimon, gm.data.ACTION_BASE);
            var spriteAlt = gm.data.spriteRef(displayDigimon, gm.data.ACTION_AT);

            // GetInvertedSprite in the original swaps to a second, inverted
            // copy of the art. Here inversion is a draw-time tint (ADR 3), so
            // the element carries the flag instead of a different sprite.
            var builder = Kaisa.ScreenBuilder.buildSprite("DigimonDisplay", screen)
                .setSize(24, 24).center().setSprite(spriteRegular)
                .invertColors(digimonIsInDDock).setTransparent(!digimonIsInDDock);

            screenAnimation = gm.runner.start(
                new AnimateSprite(builder, spriteRegular, spriteAlt));
        } else if (currentScreen == SCREEN_PAGES) {
            drawPages();
        } else if (currentScreen == SCREEN_DDOCK_LIST) {
            setScreen(Kaisa.Sprites.DATABASE_DDOCKS[ddockIndex]);
        } else if (currentScreen == SCREEN_DDOCK_DISPLAY) {
            setScreen(Kaisa.Sprites.STATUS_DDOCK[ddockIndex]);
            gm.buildDDockScreenElement(ddockIndex, screen);
        }
    }

    function drawPages() as Void {
        if (digimonNameSign == null) {
            // string.Format("{0:000} {1}", number, name)
            var name = pad3(pageDigimon.number) + " " + pageDigimon.name;
            var nameBuilder = Kaisa.ScreenBuilder.buildTextBox("NameSign", screen, Kaisa.Font.BIG)
                .setText(name).setSize(32, 7).setPosition(32, 0);
            nameBuilder.setFitSizeToContent(true);
            digimonNameSign = nameBuilder;
            screenAnimation = gm.runner.start(
                new AnimateName(nameBuilder, nameBuilder.componentWidth));
        }

        var playerLevel = gm.logicMgr.getPlayerLevel();
        var digimonExtraLevel = gm.logicMgr.getDigimonExtraLevel(pageDigimon.index);
        var realLevel;
        var stats;

        // "If the Digimon is Spirit- or Armor-Stage."
        if (menuIndex == 5 || menuIndex == 6) {
            realLevel = pageDigimon.getBossLevel(playerLevel);
            stats = pageDigimon.getBossStats(playerLevel);
        } else {
            realLevel = pageDigimon.getFriendlyLevel(digimonExtraLevel);
            stats = pageDigimon.getFriendlyStats(digimonExtraLevel);
        }

        var element = pageDigimon.element;

        if (pageIndex == 0) {
            setScreen(Kaisa.Sprites.DATABASE_PAGES[0]);
            Kaisa.ScreenBuilder.buildTextBox("Level", screen, Kaisa.Font.REGULAR)
                .setText(realLevel.toString()).setSize(15, 5).setPosition(16, 9)
                .setAlignment(Kaisa.Text.ANCHOR_UPPER_RIGHT);
            Kaisa.ScreenBuilder.buildTextBox("HP", screen, Kaisa.Font.REGULAR)
                .setText(stats.hp.toString()).setSize(15, 5).setPosition(16, 17)
                .setAlignment(Kaisa.Text.ANCHOR_UPPER_RIGHT);
            Kaisa.ScreenBuilder.buildSprite("Element", screen)
                .setSize(30, 5).setPosition(1, 25)
                .setSprite(Kaisa.Sprites.ELEMENT_NAMES[element]);
        } else if (pageIndex == 1) {
            setScreen(Kaisa.Sprites.DATABASE_PAGES[1]);
            Kaisa.ScreenBuilder.buildTextBox("Energy", screen, Kaisa.Font.REGULAR)
                .setText(stats.en.toString()).setSize(15, 5).setPosition(16, 9)
                .setAlignment(Kaisa.Text.ANCHOR_UPPER_RIGHT);
            Kaisa.ScreenBuilder.buildTextBox("Crush", screen, Kaisa.Font.REGULAR)
                .setText(stats.cr.toString()).setSize(15, 5).setPosition(16, 17)
                .setAlignment(Kaisa.Text.ANCHOR_UPPER_RIGHT);
            Kaisa.ScreenBuilder.buildTextBox("Ability", screen, Kaisa.Font.REGULAR)
                .setText(stats.ab.toString()).setSize(15, 5).setPosition(16, 25)
                .setAlignment(Kaisa.Text.ANCHOR_UPPER_RIGHT);
        } else if (pageIndex == 2) {
            setScreen(Kaisa.Sprites.DATABASE_PAGES[2]);
            Kaisa.ScreenBuilder.buildTextBox("Code", screen, Kaisa.Font.BIG)
                .setText(pageDigimon.code).setSize(30, 8).setPosition(2, 23)
                .setAlignment(Kaisa.Text.ANCHOR_UPPER_RIGHT);
        }
    }

    // string.Format("{0:000}", n)
    function pad3(n as Number) as String {
        var s = n.toString();
        while (s.length() < 3) { s = "0" + s; }
        return s;
    }

    // --- Navigation ---

    function navigateStageMenu(dir as Number) as Void {
        if (dir == Kaisa.DIR_LEFT) { menuIndex = Kaisa.MathExt.circularAdd(menuIndex, -1, 7, 0); }
        else { menuIndex = Kaisa.MathExt.circularAdd(menuIndex, 1, 7, 0); }
        drawScreen();
    }

    function openSpiritMenu() as Void {
        availableElements = [];
        // HashSet<int> in the original; here a sorted insert into a small
        // array, since the result is sorted immediately afterwards anyway.
        for (var i = 0; i < galleryList.size(); i += 1) {
            addElement(gm.data.element(galleryList[i]));
        }
        if (gm.getAllUnlockedFusionDigimon().size() > 0) {
            addElement(10);
        }

        elementIndex = 0;
        currentScreen = SCREEN_MENU_SPIRIT;
        drawScreen();
    }

    // The set-then-sort of the original, done as an ordered insert.
    function addElement(element as Number) as Void {
        for (var i = 0; i < availableElements.size(); i += 1) {
            if (availableElements[i] == element) { return; }
            if (availableElements[i] > element) {
                var head = availableElements.slice(0, i);
                head.add(element);
                availableElements = head.addAll(availableElements.slice(i, null));
                return;
            }
        }
        availableElements.add(element);
    }

    function navigateSpiritMenu(dir as Number) as Void {
        var upper = availableElements.size() - 1;
        if (dir == Kaisa.DIR_LEFT) { elementIndex = Kaisa.MathExt.circularAdd(elementIndex, -1, upper, 0); }
        else { elementIndex = Kaisa.MathExt.circularAdd(elementIndex, 1, upper, 0); }
        drawScreen();
    }

    function closeSpiritMenu() as Void {
        currentScreen = SCREEN_MENU;
        drawScreen();
    }

    function openGallery() as Void {
        // For the spirit menu the list is rebuilt from the chosen element.
        // SOURCE BUG, reproduced: this branch filters on `elementIndex`, the
        // position within availableElements, rather than on SelectedElement,
        // the element it points at -- and it APPENDS to galleryList, which
        // InputA already filled. Both are the original's behaviour.
        if (menuIndex == 6) {
            var n = gm.data.orderCount();
            if (elementIndex < 10) {
                for (var k = 0; k < n; k += 1) {
                    var i = gm.data.orderIndex(k);
                    if (gm.data.stage(i) == menuIndex && gm.data.element(i) == elementIndex
                            && gm.data.spiritType(i) != Kaisa.SPIRIT_FUSION
                            && gm.logicMgr.getDigimonUnlocked(i)) {
                        galleryList.add(i);
                    }
                }
            }
            if (elementIndex == 10) {
                for (var k = 0; k < n; k += 1) {
                    var i = gm.data.orderIndex(k);
                    if (gm.data.stage(i) == menuIndex
                            && gm.data.spiritType(i) == Kaisa.SPIRIT_FUSION
                            && gm.logicMgr.getDigimonUnlocked(i)) {
                        galleryList.add(i);
                    }
                }
            }
        }

        galleryIndex = 0;
        currentScreen = SCREEN_GALLERY;
        drawScreen();
    }

    function navigateGallery(dir as Number) as Void {
        var maxIndex = galleryList.size() - 1;
        if (dir == Kaisa.DIR_LEFT) { galleryIndex = Kaisa.MathExt.circularAdd(galleryIndex, -1, maxIndex, 0); }
        else { galleryIndex = Kaisa.MathExt.circularAdd(galleryIndex, 1, maxIndex, 0); }
        drawScreen();
    }

    function closeGallery() as Void {
        if (menuIndex < 6) {
            currentScreen = SCREEN_MENU;
        } else if (menuIndex == 6) {
            currentScreen = SCREEN_MENU_SPIRIT;
        }
        drawScreen();
    }

    function openPages() as Void {
        currentScreen = SCREEN_PAGES;
        pageIndex = 0;
        pageDigimon = gm.db.getDigimon(galleryList[galleryIndex]);
        drawScreen();
    }

    function navigatePages(dir as Number) as Void {
        var upperBound = gm.logicMgr.getDigicodeUnlocked(pageDigimon.index) ? 2 : 1;
        if (dir == Kaisa.DIR_LEFT) { pageIndex = Kaisa.MathExt.circularAdd(pageIndex, -1, upperBound, 0); }
        else { pageIndex = Kaisa.MathExt.circularAdd(pageIndex, 1, upperBound, 0); }
        drawScreen();
    }

    function closePages() as Void {
        currentScreen = SCREEN_GALLERY;
        digimonNameSign = null;
        drawScreen();
    }

    function openDDockList() as Void {
        currentScreen = SCREEN_DDOCK_LIST;
        ddockIndex = 0;
        drawScreen();
    }

    function navigateDDock(dir as Number) as Void {
        if (dir == Kaisa.DIR_LEFT) { ddockIndex = Kaisa.MathExt.circularAdd(ddockIndex, -1, 3, 0); }
        else { ddockIndex = Kaisa.MathExt.circularAdd(ddockIndex, 1, 3, 0); }
        drawScreen();
    }

    function closeDDockList() as Void {
        currentScreen = SCREEN_PAGES;
        drawScreen();
    }

    function openDDockDisplay() as Void {
        currentScreen = SCREEN_DDOCK_DISPLAY;
        drawScreen();
    }

    function closeDDockDisplay() as Void {
        currentScreen = SCREEN_DDOCK_LIST;
        drawScreen();
    }

    function chooseDDock() as Void {
        gm.enqueueAnimation(new SwapDDock(gm, ddockIndex, pageDigimon.index));

        // "If the chosen Digimon is already in a ddock, swap those ddocks."
        if (digimonIsInDDock) {
            var ddocks = gm.getAllDDockDigimons();
            for (var i = 0; i < ddocks.size(); i += 1) {
                if (ddocks[i] == pageDigimon.index) {
                    gm.logicMgr.setDDockDigimon(i, ddocks[ddockIndex]);
                }
            }
        }
        gm.logicMgr.setDDockDigimon(ddockIndex, pageDigimon.index);
        closeDDockDisplay();
        closeDDockList();
        closePages();
        closeGallery();
        drawScreen();
    }
}

// port of DatabaseApp.AnimateSprite -- the gallery's idle twitch: the Digimon
// stands still, then flicks to its attack pose twice.
class AnimateSprite extends Routine {
    var builder as SpriteBuilder;
    var spriteRegular as Array<Number>?;
    var spriteAlt as Array<Number>?;

    function initialize(builderIn as SpriteBuilder, regular as Array<Number>?,
                        alt as Array<Number>?) {
        Routine.initialize();
        builder = builderIn;
        spriteRegular = regular;
        spriteAlt = alt;
    }

    function step(rt as Fiber) as Float {
        switch (pc) {
            case 0:
                pc = 1;
                return 2.5;
            case 1:
                builder.setSprite(spriteAlt);
                pc = 2;
                return 0.4;
            case 2:
                builder.setSprite(spriteRegular);
                pc = 3;
                return 0.4;
            case 3:
                builder.setSprite(spriteAlt);
                pc = 4;
                return 0.4;
            case 4:
                builder.setSprite(spriteRegular);
                pc = 0;                 // while (true)
                return 0.0;
        }
        return Routine.DONE;
    }
}

// port of DatabaseApp.AnimateName -- the name sign scrolls in from the right,
// runs off the left, pauses, repeats.
//
// The original's first `yield return null` waits a frame for Unity's content
// fitter to have measured the text; the port measures the string itself, so
// the wait is kept (it is a real frame of delay in the original's timing) but
// the width is already known.
class AnimateName extends Routine {
    var builder as TextBoxBuilder;
    var goWidth as Number;
    var i as Number = 0;

    function initialize(builderIn as TextBoxBuilder, width as Number) {
        Routine.initialize();
        builder = builderIn;
        goWidth = width;
    }

    function step(rt as Fiber) as Float {
        switch (pc) {
            case 0:
                pc = 1;
                return Routine.NEXT_FRAME;      // yield return null
            case 1:
                builder.setPosition(32, 0);
                i = 0;
                pc = 2;
                return 0.0;
            case 2:                             // for (i = 0; i < goWidth + 32; i++)
                if (i >= goWidth + 32) { pc = 4; return 0.0; }
                builder.move(Kaisa.DIR_LEFT, 1);
                pc = 3;
                return 0.1;
            case 3:
                i += 1;
                pc = 2;
                return 0.0;
            case 4:
                pc = 1;                         // while (true)
                return 1.5;
        }
        return Routine.DONE;
    }
}

// port of DatabaseApp.AutoNavigateDir -- hold a side and the gallery pages,
// once immediately, then every 0.12 s after a 0.35 s delay.
class AutoNavigateDir extends Routine {
    var app as DatabaseApp;
    var dir as Number;

    function initialize(appIn as DatabaseApp, dirIn as Number) {
        Routine.initialize();
        app = appIn;
        dir = dirIn;
    }

    function step(rt as Fiber) as Float {
        switch (pc) {
            case 0:
                app.gm.audioMgr.playButtonA();
                app.navigateGallery(dir);
                pc = 1;
                return 0.35;
            case 1:
                pc = 2;
                return 0.12;
            case 2:
                app.gm.audioMgr.playButtonA();
                app.navigateGallery(dir);
                pc = 1;                         // while (true)
                return 0.0;
        }
        return Routine.DONE;
    }
}
