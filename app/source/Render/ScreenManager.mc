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

    // One centred word on the 32x32 screen. The bitmap faces carry codes
    // 32..90 only (FontMetrics), so every caller passes UPPERCASE.
    function drawMenuWord(name as String, text as String, y as Number) as Void {
        disposable(Kaisa.ScreenBuilder.buildTextBox(name, screenDisplay, Kaisa.Font.REGULAR)
            .setText(text).setSize(32, 5).setPosition(0, y)
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
        var subject = "RESET";
        var state = null;
        if (i == Kaisa.CONFIGURE_VIBRATION) {
            subject = "VIBRATE";
            state = Kaisa.Prefs.vibrationOn() ? "ON" : "OFF";
        } else if (i == Kaisa.CONFIGURE_SOUND) {
            subject = "SOUND";
            state = Kaisa.Prefs.soundOn() ? "ON" : "OFF";
        } else if (i == Kaisa.CONFIGURE_GRID) {
            subject = "GRID";
            state = Kaisa.Prefs.gridOn() ? "ON" : "OFF";
        }

        // Between the arrows, which sit at the left and right edges.
        disposable(Kaisa.ScreenBuilder.buildTextBox("CfgSubject", screenDisplay,
                Kaisa.Font.BIG)
            .setText(subject).setSize(24, 8).setPosition(4, 10)
            .setAlignment(Kaisa.Text.ANCHOR_UPPER_CENTER));
        if (state != null) {
            disposable(Kaisa.ScreenBuilder.buildTextBox("CfgState", screenDisplay,
                    Kaisa.Font.REGULAR)
                .setText(state).setSize(32, 5).setPosition(0, 22)
                .setAlignment(Kaisa.Text.ANCHOR_UPPER_CENTER));
        }
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
                // No sprite in the sheet -- this entry is not in the
                // original's menu -- so it says so in words, the way the
                // reset it replaced did.
                screenDisplay.setSprite(Kaisa.Sprites.EMPTY_SPRITE);
                drawMenuWord("Configure", "CONFIG", 13);
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
