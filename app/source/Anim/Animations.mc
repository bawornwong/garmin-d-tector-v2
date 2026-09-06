import Toybox.Lang;

// port of Logic/Data/Animations.cs -- the conversion of its 60 coroutines,
// one class each (ADR 4). This file grows as they are converted; every one
// carries its `port of` line so it diffs against the original.
//
// Converted so far, and why these first: the four the survey called LINEAR
// (no `if`, no `for`, no sub-call) plus the two they depend on, which
// together cover every mechanism the runner has -- waits, display-list
// mutation, a parallel fiber that is later stopped, and a loop.
//
// Each is checked against a golden trace generated from the ORIGINAL C#
// (tools/verify_anim.py); the events below come from the real display list,
// not from hand-written trace calls.
//
// The animations draw into gm.screenMgr.animParent, the container
// ScreenManager builds for the animation it is currently playing -- the
// original's `AnimParent`.

// port of Animations.cs:1148  ChangeDistance
class ChangeDistance extends Routine {
    var gm as GameManager;
    var distanceBefore as Number;
    var distanceAfter as Number;
    var tbLevel as TextBoxBuilder?;

    function initialize(gmIn as GameManager, before as Number, after as Number) {
        Routine.initialize();
        gm = gmIn;
        distanceBefore = before;
        distanceAfter = after;
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                Kaisa.ScreenBuilder.buildSprite("Distance", parent)
                    .setSize(32, 5).setPosition(0, 17)
                    .setSprite(Kaisa.Sprites.ANIM_DISTANCE);
                tbLevel = Kaisa.ScreenBuilder.buildTextBox("DistanceNumber", parent, Kaisa.Font.REGULAR)
                    .setText(distanceBefore.toString()).setSize(29, 5).setPosition(2, 24)
                    .setAlignment(Kaisa.Text.ANCHOR_UPPER_RIGHT);

                gm.audioMgr.playButtonA();
                pc = 1;
                return 1.0;
            case 1:
                tbLevel.setText(distanceAfter.toString());
                gm.audioMgr.playButtonA();
                pc = 2;
                return 1.0;
            case 2:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:2313  RewardEmpty
class RewardEmpty extends Routine {
    var gm as GameManager;

    function initialize(gmIn as GameManager) {
        Routine.initialize();
        gm = gmIn;
    }

    function step(rt as Fiber) as Float {
        switch (pc) {
            case 0:
                Kaisa.ScreenBuilder.buildSprite("Empty, sorry :(", gm.screenMgr.animParent)
                    .setSize(24, 24).center().setSprite(Kaisa.Sprites.STATUS_DDOCK_EMPTY);
                pc = 1;
                return 2.0;
            case 1:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:1906  AnimateSPScreen
//
// The background of the spirit-power screens, alternating forever. The
// original's `while (background != null)` never goes false on its own: the
// loop is ended by whoever started it calling StopCoroutine.
class AnimateSPScreen extends Routine {
    var background as SpriteBuilder;

    function initialize(backgroundIn as SpriteBuilder) {
        Routine.initialize();
        background = backgroundIn;
    }

    function step(rt as Fiber) as Float {
        switch (pc) {
            case 0:
                background.setSprite(Kaisa.Sprites.BATTLE_GAINING_SP[0]);
                pc = 1;
                return 0.2;
            case 1:
                background.setSprite(Kaisa.Sprites.BATTLE_GAINING_SP[1]);
                pc = 0;
                return 0.2;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:1206  PaySpiritPower
//
// The first converted coroutine that runs another one IN PARALLEL: the
// background animation is started as its own fiber and stopped three seconds
// later, which is the case ticket 08 called out as beyond the ticket 07
// prototype's runner.
class PaySpiritPower extends Routine {
    var gm as GameManager;
    var spBefore as Number;
    var spAfter as Number;
    var bgAnimation as Fiber?;
    var tbSpirits as TextBoxBuilder?;

    function initialize(gmIn as GameManager, before as Number, after as Number) {
        Routine.initialize();
        gm = gmIn;
        spBefore = before;
        spAfter = after;
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                var sbSPBackground = Kaisa.ScreenBuilder.buildSprite("SPBackground", parent);
                bgAnimation = gm.runner.start(new AnimateSPScreen(sbSPBackground));

                tbSpirits = Kaisa.ScreenBuilder.buildTextBox("SPAmount", parent, Kaisa.Font.SMALL)
                    .setText(spBefore.toString()).setSize(32, 11).setPosition(0, 21)
                    .setAlignment(Kaisa.Text.ANCHOR_UPPER_RIGHT);
                tbSpirits.invertColors(true);
                tbSpirits.setComponentSize(28, 5);
                tbSpirits.setComponentPosition(2, 3);
                tbSpirits.setActive(false);

                pc = 1;
                return 1.0;
            case 1:
                gm.audioMgr.playButtonA();
                tbSpirits.setActive(true);
                pc = 2;
                return 1.0;
            case 2:
                gm.audioMgr.playButtonA();
                tbSpirits.setText(spAfter.toString());
                pc = 3;
                return 1.0;
            case 3:
                gm.runner.stop(bgAnimation);
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:1179  AWardSpiritPower
//
// The same shape as PaySpiritPower with a counting loop in the middle. The
// original declares `void IncreaseSP()` as a local function AFTER the loop
// that calls it, which C# allows and Monkey C does not; it becomes a method.
class AWardSpiritPower extends Routine {
    var gm as GameManager;
    var spBefore as Number;
    var bgAnimation as Fiber?;
    var tbSpirits as TextBoxBuilder?;
    var i as Number = 0;

    function initialize(gmIn as GameManager, before as Number) {
        Routine.initialize();
        gm = gmIn;
        spBefore = before;
    }

    function increaseSP() as Void {
        spBefore += (spBefore >= 99) ? 0 : 1;
        tbSpirits.setText(spBefore.toString());
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                var sbSPBackground = Kaisa.ScreenBuilder.buildSprite("SPBackground", parent);
                bgAnimation = gm.runner.start(new AnimateSPScreen(sbSPBackground));

                tbSpirits = Kaisa.ScreenBuilder.buildTextBox("SPAmount", parent, Kaisa.Font.SMALL)
                    .setText(spBefore.toString()).setSize(32, 11).setPosition(0, 21)
                    .setAlignment(Kaisa.Text.ANCHOR_UPPER_RIGHT);
                tbSpirits.invertColors(true);
                tbSpirits.setComponentSize(28, 5);
                tbSpirits.setComponentPosition(2, 3);
                tbSpirits.setActive(false);

                pc = 1;
                return 0.4;
            case 1:
                tbSpirits.setActive(true);
                pc = 2;
                return 0.2;
            case 2:                                 // for (i = 0; i < 3; i++)
                i = 0;
                pc = 3;
                return 0.0;
            case 3:
                if (i >= 3) { pc = 5; return 0.0; }
                increaseSP();
                pc = 4;
                return 0.4;
            case 4:
                i += 1;
                pc = 3;
                return 0.0;
            case 5:
                pc = 6;
                return 0.4;
            case 6:
                gm.runner.stop(bgAnimation);
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:631  CharHappyShort
class CharHappyShort extends Routine {
    var gm as GameManager;
    var charIdle as Array<Number>?;
    var charHappy as Array<Number>?;
    var sbChar as SpriteBuilder?;
    var i as Number = 0;

    function initialize(gmIn as GameManager) {
        Routine.initialize();
        gm = gmIn;
    }

    function step(rt as Fiber) as Float {
        switch (pc) {
            case 0:
                var sprites = gm.characterSprites(gm.saved.playerChar());
                charIdle = sprites[0];
                charHappy = sprites[6];

                gm.audioMgr.playSound("charHappy");

                sbChar = Kaisa.ScreenBuilder.buildSprite("CharHappy", gm.screenMgr.animParent)
                    .setSprite(charIdle);

                i = 0;
                pc = 1;
                return 0.0;
            case 1:                             // for (i = 0; i < 2; i++)
                if (i >= 2) { pc = 4; return 0.0; }
                sbChar.setSprite(charIdle);
                pc = 2;
                return 0.5;
            case 2:
                sbChar.setSprite(charHappy);
                pc = 3;
                return 0.5;
            case 3:
                i += 1;
                pc = 1;
                return 0.0;
            case 4:
                sbChar.dispose();
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:627  CharHappy -- two CharHappyShorts back to back,
// and the first converted coroutine that yields another one.
class CharHappy extends Routine {
    var gm as GameManager;

    function initialize(gmIn as GameManager) {
        Routine.initialize();
        gm = gmIn;
    }

    function step(rt as Fiber) as Float {
        switch (pc) {
            case 0:
                pc = 1;
                rt.call(new CharHappyShort(gm));    // yield return CharHappyShort()
                return 0.0;
            case 1:
                pc = 2;
                rt.call(new CharHappyShort(gm));
                return 0.0;
            case 2:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:2567  OpenCamp -- the character walks off to the left
// and the camp walks in from the right. TOTAL DURATION: 7.2s.
class OpenCamp extends Routine {
    var gm as GameManager;
    var character as Array;
    var sbCharacter as SpriteBuilder?;
    var i as Number = 0;

    function initialize(gmIn as GameManager, characterIn as Array) {
        Routine.initialize();
        gm = gmIn;
        character = characterIn;
    }

    function step(rt as Fiber) as Float {
        switch (pc) {
            case 0:
                sbCharacter = Kaisa.ScreenBuilder.buildSprite("Character", gm.screenMgr.animParent)
                    .center().setSprite(character[0]);
                pc = 1;
                return 0.2;
            case 1:                             // for (i = 0; i < 32; i++)
                i = 0;
                pc = 2;
                return 0.0;
            case 2:
                if (i >= 32) { pc = 4; return 0.0; }
                sbCharacter.setSprite(character[4 + (i % 2)]);
                sbCharacter.move(Kaisa.DIR_LEFT, 1);
                pc = 3;
                return 3.0 / 32;
            case 3:
                i += 1;
                pc = 2;
                return 0.0;
            case 4:
                sbCharacter.setSize(24, 24).setY(4).move(Kaisa.DIR_RIGHT, 4)
                           .setSprite(Kaisa.Sprites.CAMP[0]);
                i = 0;
                pc = 5;
                return 0.0;
            case 5:                             // for (i = 0; i < 32; i++)
                if (i >= 32) { pc = 7; return 0.0; }
                sbCharacter.move(Kaisa.DIR_RIGHT, 1);
                pc = 6;
                return 3.0 / 32;
            case 6:
                i += 1;
                pc = 5;
                return 0.0;
            case 7:
                pc = 8;
                return 1.0;
            case 8:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:2584  CloseCamp -- the reverse. TOTAL DURATION: 7.2s.
class CloseCamp extends Routine {
    var gm as GameManager;
    var character as Array;
    var sbCharacter as SpriteBuilder?;
    var i as Number = 0;

    function initialize(gmIn as GameManager, characterIn as Array) {
        Routine.initialize();
        gm = gmIn;
        character = characterIn;
    }

    function step(rt as Fiber) as Float {
        switch (pc) {
            case 0:
                sbCharacter = Kaisa.ScreenBuilder.buildSprite("Character", gm.screenMgr.animParent)
                    .setSize(24, 24).center().setSprite(Kaisa.Sprites.CAMP[0]);
                i = 0;
                pc = 1;
                return 0.0;
            case 1:                             // for (i = 0; i < 32; i++)
                if (i >= 32) { pc = 3; return 0.0; }
                sbCharacter.move(Kaisa.DIR_LEFT, 1);
                pc = 2;
                return 3.0 / 32;
            case 2:
                i += 1;
                pc = 1;
                return 0.0;
            case 3:
                sbCharacter.setSize(32, 32).setY(0).move(Kaisa.DIR_LEFT, 4)
                           .flipHorizontal(true).setSprite(character[0]);
                i = 0;
                pc = 4;
                return 0.0;
            case 4:                             // for (i = 0; i < 32; i++)
                if (i >= 32) { pc = 6; return 0.0; }
                sbCharacter.setSprite(character[4 + (i % 2)]);
                sbCharacter.move(Kaisa.DIR_RIGHT, 1);
                pc = 5;
                return 3.0 / 32;
            case 5:
                i += 1;
                pc = 4;
                return 0.0;
            case 6:
                sbCharacter.setSprite(character[0]);
                pc = 7;
                return 0.2;
            case 7:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:816  SwapDDock
//
// Black bars slide the D-Dock plate up, the Digimon inside it changes, the
// plate slides back, and the new Digimon flashes five times. The waits are
// computed -- animDuration / 32 -- which is 46.875 ms: shorter than a frame,
// so ADR 5's scheduler is what keeps the two 1.5 s sweeps exact.
class SwapDDock extends Routine {
    var gm as GameManager;
    var ddock as Number;
    var newDigimon as Number;               // a packed-data index (ADR 7)
    var animDuration as Float = 1.5;
    var newDigimonSprite as Array<Number>?;
    var newDigimonSpriteCr as Array<Number>?;
    var bBlackBars as SpriteBuilder?;
    var bDDock as SpriteBuilder?;
    var bDDockSprite as SpriteBuilder?;
    var i as Number = 0;

    function initialize(gmIn as GameManager, ddockIn as Number, newDigimonIn as Number) {
        Routine.initialize();
        gm = gmIn;
        ddock = ddockIn;
        newDigimon = newDigimonIn;
    }

    function step(rt as Fiber) as Float {
        switch (pc) {
            case 0:
                newDigimonSprite = gm.data.spriteRef(newDigimon, gm.data.ACTION_BASE);
                newDigimonSpriteCr = gm.data.spriteRef(newDigimon, gm.data.ACTION_CR);

                gm.audioMgr.playSound("changeDock");

                bBlackBars = Kaisa.ScreenBuilder.buildSprite("BlackBars", gm.screenMgr.animParent)
                    .setSprite(Kaisa.Sprites.BLACK_BARS).placeOutside(Kaisa.DIR_DOWN);
                bDDock = Kaisa.ScreenBuilder.buildSprite("DDock", gm.screenMgr.animParent)
                    .setSprite(Kaisa.Sprites.STATUS_DDOCK[ddock]);
                bDDockSprite = gm.buildDDockScreenElement(ddock, bDDock);

                pc = 1;
                return 0.75;
            case 1:                             // for (i = 0; i < 32; i++)
                i = 0;
                pc = 2;
                return 0.0;
            case 2:
                if (i >= 32) { pc = 4; return 0.0; }
                bBlackBars.move(Kaisa.DIR_UP, 1);
                bDDock.move(Kaisa.DIR_UP, 1);
                pc = 3;
                return animDuration / 32;
            case 3:
                i += 1;
                pc = 2;
                return 0.0;
            case 4:
                bDDockSprite.setSprite(newDigimonSprite);
                pc = 5;
                return 0.75;
            case 5:                             // for (i = 0; i < 32; i++)
                i = 0;
                pc = 6;
                return 0.0;
            case 6:
                if (i >= 32) { pc = 8; return 0.0; }
                bBlackBars.move(Kaisa.DIR_DOWN, 1);
                bDDock.move(Kaisa.DIR_DOWN, 1);
                pc = 7;
                return animDuration / 32;
            case 7:
                i += 1;
                pc = 6;
                return 0.0;
            case 8:
                pc = 9;
                return 0.5;
            case 9:
                // "Originally this started after 0.175 seconds."
                gm.audioMgr.playSound("charHappy");
                bDDockSprite.setSprite(newDigimonSpriteCr);
                i = 0;
                pc = 10;
                return 0.0;
            case 10:                            // for (i = 0; i < 5; i++)
                if (i >= 5) { pc = 13; return 0.0; }
                bDDockSprite.setActive(false);
                pc = 11;
                return 0.175;
            case 11:
                bDDockSprite.setActive(true);
                pc = 12;
                return 0.175;
            case 12:
                i += 1;
                pc = 10;
                return 0.0;
            case 13:
                pc = 14;
                return 0.5;
            case 14:
                bBlackBars.dispose();
                bDDock.dispose();
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}
