import Toybox.Lang;

// port of Logic/Apps/Camp.cs
//
// The smallest app in the game: pitch camp, wait, and the campfire flickers
// until the player presses A. Its real work is in the three animations it
// enqueues (OpenCamp, CloseCamp, CharHappy), which belong to Animations.cs and
// are not translated yet -- so the app opens and closes, and clearing the
// defeated flag still happens, which is what Camp is for.
class Camp extends DigiviceApp {
    var sbCamp as SpriteBuilder?;
    var animCamp as Fiber?;

    function initialize(gmIn as GameManager, controllerIn, parent as ScreenElement) {
        DigiviceApp.initialize(gmIn, controllerIn, parent);
    }

    function inputA() as Void {
        endCamp();
    }

    function startApp() as Void {
        gm.enqueueAnimation(null);      // Animations.OpenCamp(PlayerSprites)
        sbCamp = Kaisa.ScreenBuilder.buildSprite("Camp", screen)
            .setSize(24, 24).center().setSprite(Kaisa.Sprites.CAMP[0]);
        animCamp = gm.runner.start(new PAnimateCamp(sbCamp));
    }

    function endCamp() as Void {
        gm.enqueueAnimation(null);      // Animations.CloseCamp(PlayerSprites)
        gm.enqueueAnimation(null);      // Animations.CharHappy()
        gm.setCharacterDefeated(false);
        if (animCamp != null) {
            gm.runner.stop(animCamp);
            animCamp = null;
        }
        closeApp(Kaisa.SCREEN_CHARACTER);
    }

    function dispose() as Void {
        if (animCamp != null) {
            gm.runner.stop(animCamp);
            animCamp = null;
        }
        DigiviceApp.dispose();
    }
}

// port of Camp.PAnimateCamp -- 7.5 s of stillness, then the fire alternates
// every half second for as long as the app is open.
class PAnimateCamp extends Routine {
    var sbCamp as SpriteBuilder;
    var altSprite as Boolean = true;

    function initialize(sbCampIn as SpriteBuilder) {
        Routine.initialize();
        sbCamp = sbCampIn;
    }

    function step(rt as Fiber) as Float {
        switch (pc) {
            case 0:
                pc = 1;
                altSprite = true;
                return 7.5;
            case 1:                     // while (true)
                if (altSprite) {
                    sbCamp.setSprite(Kaisa.Sprites.CAMP[1]);
                    altSprite = false;
                    return 0.5;
                } else {
                    sbCamp.setSprite(Kaisa.Sprites.CAMP[0]);
                    altSprite = true;
                    return 0.5;
                }
        }
        return Routine.DONE;
    }
}
