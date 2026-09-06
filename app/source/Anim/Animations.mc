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
