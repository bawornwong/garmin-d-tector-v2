import Toybox.Graphics;
import Toybox.Lang;

// port of ScreenManager.cs
//
// Owns what is on screen when no app is: the character, the menus, the three
// blinking overlays, and the queue that plays animations over whatever is
// showing. The original rebuilds its disposable children every Update (60 Hz);
// the port does the same work once per 50 ms frame, which is the rate the
// display actually changes at.
class ScreenManager {
    var gm as GameManager;
    var root as ContainerBuilder;      // ScreenManager.RootParent
    var screenDisplay as SpriteBuilder;
    var animParent as ContainerBuilder?;

    var defeatedLayer as SpriteBuilder;
    var eventLayer as SpriteBuilder;
    var eyesLayer as SpriteBuilder;

    var playingAnimations as Boolean = false;
    var _queue as Array<Routine> = [];
    var _playing as Fiber?;
    var _configureGear as Graphics.BufferedBitmap?;
    var _configureIcons as Array<Graphics.BufferedBitmap?> = [null, null, null, null, null];

    function initialize(gmIn as GameManager, rootIn as ContainerBuilder) {
        gm = gmIn;
        root = rootIn;

        // The screen sprite itself: everything an app builds is parented to
        // it, and the menus swap its sprite.
        screenDisplay = Kaisa.ScreenBuilder.buildSprite("Screen", root);
        screenDisplay.setSize(Kaisa.Constants.SCREEN_WIDTH, Kaisa.Constants.SCREEN_HEIGHT)
                     .setTransparent(true);

        // ScreenManager.Start: three overlays that blink on their own timers,
        // each SetAsFirstSibling so they draw beneath what follows.
        defeatedLayer = Kaisa.ScreenBuilder.buildSprite("Defeated", root)
            .setSize(6, 7).setPosition(1, 1).setTransparent(true).setActive(false);
        eventLayer = Kaisa.ScreenBuilder.buildSprite("Event", root)
            .setTransparent(true).setActive(false);
        eyesLayer = Kaisa.ScreenBuilder.buildSprite("Eyes", root)
            .setTransparent(true).setActive(false);
    }

    // The three PAFlash* coroutines. They run for the life of the app, so
    // they are started once and never stopped -- as in the original, where
    // they are StartCoroutine'd in Start().
    // Everything the reset entry builds is rebuilt every frame, so it carries
    // the name the display walk clears.
    function disposable(el as ScreenElement) as ScreenElement {
        el.name = "Disposable";
        return el;
    }

    // One word centred across the full 32-pixel width. The bitmap faces carry
    // codes 32..90 only (FontMetrics), so every caller passes UPPERCASE.
    //
    // Centring on the full width rather than on a narrower box is what keeps
    // a word clear of the arrows: they occupy only columns 2-4 and 27-29, so
    // anything up to 22 pixels centred lands between them untouched.
    // TRANSPARENT is load-bearing, not tidiness: Renderer.drawElement fills an
    // opaque element's whole rect with the field colour before drawing it, so
    // a 32-wide box laid over the arrow rows wipes the arrows out. The value
    // box does exactly that, and the arrows vanished until this was set.
    function drawMenuWord(name as String, face as Number, text as String,
                          y as Number, h as Number) as Void {
        disposable(Kaisa.ScreenBuilder.buildTextBox(name, screenDisplay, face)
            .setText(text).setSize(32, h).setPosition(0, y)
            .setTransparent(true)
            .setAlignment(Kaisa.Text.ANCHOR_UPPER_CENTER));
    }

    // The added Config entry has no sprite in the source atlas. Draw its
    // 16-pixel gear once and reuse the bitmap like the Maze's runtime sprite.
    // White pixels are tinted to the current ink colour by Renderer.
    function configureGear() as Graphics.BufferedBitmap? {
        if (_configureGear != null) { return _configureGear; }
        var rows = [0x0660, 0x0660, 0x1ff8, 0x381c,
                    0xe7e7, 0xcc33, 0xc813, 0xc813,
                    0xc813, 0xc813, 0xcc33, 0xe7e7,
                    0x381c, 0x1ff8, 0x0660, 0x0660];
        try {
            _configureGear = Graphics.createBufferedBitmap({ :width => 16,
                                                               :height => 16 }).get();
        } catch (e) {
            return null;
        }
        var dc = (_configureGear as Graphics.BufferedBitmap).getDc();
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        for (var y = 0; y < rows.size(); y += 1) {
            for (var x = 0; x < 16; x += 1) {
                if ((rows[y] & (0x8000 >> x)) != 0) {
                    dc.fillRectangle(x, y, 1, 1);
                }
            }
        }
        return _configureGear;
    }

    // The added settings have no source sprites. Draw small monochrome
    // icons once and reuse them like the main menu's bitmap art.
    function configureIcon(index as Number) as Graphics.BufferedBitmap? {
        if (index < 0 || index >= _configureIcons.size()) { return null; }
        if (_configureIcons[index] != null) { return _configureIcons[index]; }
        try {
            _configureIcons[index] = Graphics.createBufferedBitmap({
                :width => 16, :height => 16 }).get();
        } catch (e) {
            return null;
        }
        var dc = (_configureIcons[index] as Graphics.BufferedBitmap).getDc();
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        if (index == Kaisa.CONFIGURE_VIBRATION) {
            // Watch body, straps and two vibration waves.
            dc.fillRectangle(6, 1, 5, 2); dc.fillRectangle(6, 13, 5, 2);
            dc.fillRectangle(4, 3, 9, 1); dc.fillRectangle(4, 12, 9, 1);
            dc.fillRectangle(4, 4, 1, 8); dc.fillRectangle(12, 4, 1, 8);
            dc.fillRectangle(7, 6, 3, 4);
            dc.fillRectangle(2, 5, 1, 6); dc.fillRectangle(1, 6, 1, 4);
            dc.fillRectangle(14, 5, 1, 6); dc.fillRectangle(15, 6, 1, 4);
        } else if (index == Kaisa.CONFIGURE_SOUND) {
            // Speaker and two sound waves.
            dc.fillRectangle(2, 5, 4, 6); dc.fillRectangle(6, 4, 2, 8);
            dc.fillRectangle(8, 3, 2, 10);
            dc.fillRectangle(12, 5, 1, 6); dc.fillRectangle(14, 3, 1, 10);
            dc.fillRectangle(15, 4, 1, 8);
        } else if (index == Kaisa.CONFIGURE_GRID) {
            for (var y = 0; y < 3; y += 1) {
                for (var x = 0; x < 3; x += 1) {
                    dc.fillRectangle(3 + x * 4, 3 + y * 4, 3, 3);
                }
            }
        } else if (index == Kaisa.CONFIGURE_BG_STEPS) {
            // Two footprints for steps counted while the app is closed.
            dc.fillRectangle(3, 3, 4, 5); dc.fillRectangle(4, 2, 2, 1);
            dc.fillRectangle(2, 8, 3, 3);
            dc.fillRectangle(9, 7, 4, 5); dc.fillRectangle(10, 6, 2, 1);
            dc.fillRectangle(11, 12, 3, 3);
        } else {
            // Circular restart arrow.
            dc.fillRectangle(5, 2, 7, 1); dc.fillRectangle(3, 3, 2, 2);
            dc.fillRectangle(12, 3, 2, 2); dc.fillRectangle(2, 5, 1, 6);
            dc.fillRectangle(14, 5, 1, 5); dc.fillRectangle(3, 11, 2, 2);
            dc.fillRectangle(5, 13, 6, 1); dc.fillRectangle(11, 12, 3, 1);
            dc.fillRectangle(12, 10, 4, 1); dc.fillRectangle(13, 11, 1, 2);
            dc.fillRectangle(14, 13, 1, 1);
        }
        return _configureIcons[index];
    }

    // Same carousel as the main menu: arrows at the sides, a central icon,
    // and the subject along the bottom. The state is a small line above the
    // icon so ON/OFF no longer takes the place of the subject's picture.
    function drawConfigureMenu() as Void {
        screenDisplay.setSprite(Kaisa.Sprites.EMPTY_SPRITE);
        var sb = Kaisa.ScreenBuilder.buildSprite("Arrows", screenDisplay)
            .setSprite(Kaisa.Sprites.ARROWS).setTransparent(true);
        sb.name = "Disposable";

        var i = gm.logicMgr.configureMenuIndex;
        var state = "RESET";
        var subject = "GAME";
        if (i == Kaisa.CONFIGURE_VIBRATION) {
            state = Kaisa.Prefs.vibrationOn() ? "ON" : "OFF";
            subject = "VIBE";
        } else if (i == Kaisa.CONFIGURE_SOUND) {
            state = Kaisa.Prefs.soundOn() ? "ON" : "OFF";
            subject = "SOUND";
        } else if (i == Kaisa.CONFIGURE_GRID) {
            state = Kaisa.Prefs.gridOn() ? "ON" : "OFF";
            subject = "GRID";
        } else if (i == Kaisa.CONFIGURE_BG_STEPS) {
            state = BackgroundStepSetting.enabled() ? "ON" : "OFF";
            subject = "BG STEP";
        }
        drawMenuWord("CfgState", Kaisa.Font.SMALL, state, 1, 5);
        disposable(Kaisa.ScreenBuilder.buildSprite("CfgIcon", screenDisplay)
            .setSize(16, 16).setPosition(8, 6).setTransparent(true)
            .setRuntimeBitmap(configureIcon(i), 16, 16));
        drawMenuWord("CfgSubject", Kaisa.Font.REGULAR, subject, 24, 5);
    }

    function startFlashRoutines() as Void {
        gm.runner.start(new PAFlashDefeatedEffect(defeatedLayer));
        gm.runner.start(new PAFlashEventEffect(eventLayer));
        gm.runner.start(new PAFlashEyesEffect(eyesLayer));
    }

    // ScreenManager.EnqueueAnimation + ConsumeQueue. The queue plays one
    // animation at a time with input locked, under an "Anim Parent" container
    // that is thrown away when it finishes.
    function enqueueAnimation(animation as Routine?) as Void {
        if (animation == null) { return; }
        _queue.add(animation);
        if (!playingAnimations) { consumeNext(); }
    }

    function consumeNext() as Void {
        if (_queue.size() == 0) {
            playingAnimations = false;
            _playing = null;
            if (animParent != null) {
                animParent.dispose();
                animParent = null;
            }
            gm.unlockInput();
            // ScreenManager.cs:101 -- the queue draining is when a saved event
            // gets its chance: nothing else is on screen now.
            gm.checkPendingEvents();
            return;
        }
        playingAnimations = true;
        gm.lockInput();
        if (animParent != null) { animParent.dispose(); }
        animParent = Kaisa.ScreenBuilder.buildContainer("Anim Parent", root, false)
            .setSize(32, 32);
        var next = _queue[0];
        _queue = _queue.slice(1, null);
        if (next instanceof EncounterEnemy || next instanceof EncounterBoss
                || next instanceof DataStorm || next instanceof StartGameAnimation
                || next instanceof DisplayNewArea
                || next instanceof TransitionToMap1
                || next instanceof TransitionToMap3) {
            gm.audioMgr.vibrateScene();
        }
        _playing = gm.runner.start(next);
    }

    // Called once per frame by the host: the queue advances when the fiber
    // playing the current animation has finished.
    function updateQueue() as Void {
        if (playingAnimations && (_playing == null || !_playing.isRunning())) {
            consumeNext();
        }
    }

    // ScreenManager.UpdateDisplay, once per frame.
    function updateDisplay() as Void {
        // "foreach child ... if tag == disposable, Destroy": the CharSelection
        // arrows are the only disposable, and they are rebuilt below.
        clearDisposables();

        var showLayer = 0;    // 0: none, 1: defeated, 2: event, 3: eyes
        if (gm.logicMgr.currentScreen == Kaisa.SCREEN_CHARACTER) {
            if (gm.isCharacterDefeated()) { showLayer = 1; }
            else if (gm.isEventActive()) { showLayer = 2; }
            else if (gm.showEyes()) { showLayer = 3; }
        }
        defeatedLayer.setActive(showLayer == 1);
        eventLayer.setActive(showLayer == 2);
        eyesLayer.setActive(showLayer == 3);

        var screen = gm.logicMgr.currentScreen;
        if (screen == Kaisa.SCREEN_CHAR_SELECTION) {
            var sb = Kaisa.ScreenBuilder.buildSprite("Arrows", screenDisplay)
                .setSprite(Kaisa.Sprites.ARROWS).setTransparent(true);
            sb.name = "Disposable";
            screenDisplay.setSprite(
                gm.characterSprites(gm.logicMgr.charSelectionIndex)[0]);
        } else if (screen == Kaisa.SCREEN_CHARACTER) {
            screenDisplay.setSprite(gm.playerCharSprite());
        } else if (screen == Kaisa.SCREEN_MAIN_MENU) {
            if (gm.logicMgr.currentMainMenu == Kaisa.MAIN_MENU_CONFIGURE) {
                // Added menu entry: match the original icon, arrows, and
                // label positions with a small runtime gear in the centre.
                screenDisplay.setSprite(Kaisa.Sprites.EMPTY_SPRITE);
                var arr = Kaisa.ScreenBuilder.buildSprite("Arrows", screenDisplay)
                    .setSprite(Kaisa.Sprites.ARROWS).setTransparent(true);
                arr.name = "Disposable";
                var gear = Kaisa.ScreenBuilder.buildSprite("ConfigGear", screenDisplay)
                    .setSize(16, 16).setPosition(8, 4).setTransparent(true)
                    .setRuntimeBitmap(configureGear(), 16, 16);
                gear.name = "Disposable";
                drawMenuWord("Configure", Kaisa.Font.REGULAR, "CONFIG", 24, 5);
            } else {
                screenDisplay.setSprite(Kaisa.Sprites.MAIN_MENU[gm.logicMgr.currentMainMenu]);
            }
        } else if (screen == Kaisa.SCREEN_CONFIGURE_MENU) {
            drawConfigureMenu();
        } else if (screen == Kaisa.SCREEN_GAMES_MENU) {
            screenDisplay.setSprite(Kaisa.Sprites.GAME_SECTIONS[gm.logicMgr.gamesMenuIndex]);
        } else if (screen == Kaisa.SCREEN_GAMES_REWARD_MENU) {
            screenDisplay.setSprite(Kaisa.Sprites.GAMES_REWARD[gm.logicMgr.gamesRewardMenuIndex]);
        } else if (screen == Kaisa.SCREEN_GAMES_TRAVEL_MENU) {
            screenDisplay.setSprite(Kaisa.Sprites.GAMES_TRAVEL[gm.logicMgr.gamesTravelMenuIndex]);
        } else {
            // Screen.App: the loaded app owns the display, and emptySprite is
            // unassigned in the Unity scene -- it draws nothing (null here).
            screenDisplay.setSprite(null);
        }
    }

    function clearDisposables() as Void {
        var i = 0;
        while (i < screenDisplay.children.size()) {
            var child = screenDisplay.children[i];
            if (child.name.equals("Disposable")) {
                child.dispose();
            } else {
                i += 1;
            }
        }
    }
}

// port of ScreenManager.PAFlashDefeatedEffect
class PAFlashDefeatedEffect extends Routine {
    var layer as SpriteBuilder;

    function initialize(layerIn as SpriteBuilder) {
        Routine.initialize();
        layer = layerIn;
    }

    function step(rt as Fiber) as Float {
        switch (pc) {
            case 0:
                layer.setSprite(Kaisa.Sprites.DEFEATED_SYMBOL);
                pc = 1;
                return 0.5;
            case 1:
                layer.setSprite(null);      // spriteDB.emptySprite
                pc = 0;
                return 0.5;
        }
        return Routine.DONE;
    }
}

// port of ScreenManager.PAFlashEventEffect
class PAFlashEventEffect extends Routine {
    var layer as SpriteBuilder;

    function initialize(layerIn as SpriteBuilder) {
        Routine.initialize();
        layer = layerIn;
    }

    function step(rt as Fiber) as Float {
        switch (pc) {
            case 0:
                layer.setSprite(Kaisa.Sprites.TRIGGER_EVENT);
                pc = 1;
                return 0.2;
            case 1:
                layer.setSprite(null);
                pc = 0;
                return 0.2;
        }
        return Routine.DONE;
    }
}

// port of ScreenManager.PAFlashEyesEffect -- the only animation in the game
// whose waits are random.
class PAFlashEyesEffect extends Routine {
    var layer as SpriteBuilder;

    function initialize(layerIn as SpriteBuilder) {
        Routine.initialize();
        layer = layerIn;
    }

    function step(rt as Fiber) as Float {
        switch (pc) {
            case 0:
                layer.setSprite(Kaisa.Sprites.EYES[0]);
                pc = 1;
                return Kaisa.Rand.rangeFloat(0.25, 1.0);
            case 1:
                layer.setSprite(Kaisa.Sprites.EYES[1]);
                pc = 0;
                return Kaisa.Rand.rangeFloat(0.25, 1.0);
        }
        return Routine.DONE;
    }
}
