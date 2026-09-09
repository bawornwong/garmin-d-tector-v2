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

    // The Configure submenu, laid out like every other menu in the game:
    // `< subject >` up top with the navigation arrows either side, and the
    // line underneath saying what it currently is.
    //
    // The other menus put a 32x32 SPRITE in that upper slot. The sheet has
    // no icon for "sound" or "grid" -- these settings do not exist in the
    // original, so nothing was ever drawn for them -- so the subject is set
    // in the Big face instead, which is the closest the assets get to an
    // icon. The ARROWS overlay is the same one the character selection
    // uses, so left/right reads as navigation exactly as it does there.
    function drawConfigureMenu() as Void {
        screenDisplay.setSprite(Kaisa.Sprites.EMPTY_SPRITE);
        var sb = Kaisa.ScreenBuilder.buildSprite("Arrows", screenDisplay)
            .setSprite(Kaisa.Sprites.ARROWS).setTransparent(true);
        sb.name = "Disposable";

        var i = gm.logicMgr.configureMenuIndex;
        var value = "NEW";          // the reset, read with its subject: NEW GAME
        var subject = "GAME";
        if (i == Kaisa.CONFIGURE_VIBRATION) {
            // "VIBE", not "VIBRATE": the latter sets 32 pixels wide in the
            // Regular face, exactly the width of the screen, with no margin
            // either side. In the Big face it is 42 and ran off both edges.
            value = Kaisa.Prefs.vibrationOn() ? "ON" : "OFF";
            subject = "VIBE";
        } else if (i == Kaisa.CONFIGURE_SOUND) {
            value = Kaisa.Prefs.soundOn() ? "ON" : "OFF";
            subject = "SOUND";
        } else if (i == Kaisa.CONFIGURE_GRID) {
            value = Kaisa.Prefs.gridOn() ? "ON" : "OFF";
            subject = "GRID";
        }

        // The value takes the slot the other menus fill with their icon --
        // between the arrows, in the Big face. Widest is "OFF"/"NEW" at 18
        // pixels, which centred spans columns 7..24 and so clears the arrows
        // at 2-4 and 27-29.
        drawMenuWord("CfgValue", Kaisa.Font.BIG, value, 10, 8);
        // The subject sits on row 24, which is where MAIN_MENU's own sprites
        // bake their labels ("MAP", "GAME"). Widest is "SOUND" at 25.
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
                // This entry is not in the original, so the sheet has no
                // sprite for it -- and the neighbouring MAIN_MENU sprites
                // bake their arrows in, so without the overlay this would be
                // the one entry in the ring with none. The word goes on row
                // 24, where those same sprites bake their labels.
                screenDisplay.setSprite(Kaisa.Sprites.EMPTY_SPRITE);
                var arr = Kaisa.ScreenBuilder.buildSprite("Arrows", screenDisplay)
                    .setSprite(Kaisa.Sprites.ARROWS).setTransparent(true);
                arr.name = "Disposable";
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
