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

// port of Animations.cs:1916  LaunchAttack
//
// One side's attack leaving its Digimon and crossing the screen. Four shapes
// in one coroutine: energy and ability travel (0 and 2), crush is a trail of
// seven copies (1), and 3 is the Digimon refusing to attack at all -- it just
// turns around twice.
//
// `digimonSprites` is a battle sprite set: 0 default, 1 attack, 2 crush,
// 3 energy, 4 ability (GameManager.getAllDigimonBattleSprites).
class LaunchAttack extends Routine {
    var gm as GameManager;
    var digimonSprites as Array;
    var attack as Number;
    var isEnemy as Boolean;
    var disobeyed as Boolean;

    var launchDir as Number = Kaisa.DIR_LEFT;
    var sbAttack as SpriteBuilder?;
    var sbDigimon as SpriteBuilder?;
    var sbDisobey as SpriteBuilder?;
    var extraPixels as Number = 0;
    var i as Number = 0;

    function initialize(gmIn as GameManager, digimonSpritesIn as Array,
                        attackIn as Number, isEnemyIn as Boolean, disobeyedIn as Boolean) {
        Routine.initialize();
        gm = gmIn;
        digimonSprites = digimonSpritesIn;
        attack = attackIn;
        isEnemy = isEnemyIn;
        disobeyed = disobeyedIn;
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                launchDir = isEnemy ? Kaisa.DIR_RIGHT : Kaisa.DIR_LEFT;
                sbAttack = Kaisa.ScreenBuilder.buildSprite("Attack", parent)
                    .setSize(24, 24).center();
                sbDigimon = Kaisa.ScreenBuilder.buildSprite("Attacker", parent)
                    .setSize(24, 24).center().setSprite(digimonSprites[0]);
                sbAttack.setComponentSize(24, 24);

                sbAttack.snapComponentToSide(launchDir, true);
                sbDigimon.flipHorizontal(isEnemy);
                sbAttack.flipHorizontal(isEnemy);

                extraPixels = 0;

                if (attack != 3) {
                    if (disobeyed) { pc = 1; return 0.1; }
                    pc = 3;
                    return 0.2;
                }
                pc = 4;
                return 0.0;
            case 1:                                 // show the exclamation mark
                sbDisobey = Kaisa.ScreenBuilder.buildSprite("Disobey", parent)
                    .setSize(3, 9).setPosition(1, 1).setSprite(Kaisa.Sprites.BATTLE_DISOBEY);
                pc = 2;
                return 0.3;
            case 2:
                sbDisobey.dispose();
                pc = 3;
                return 0.2;
            case 3:
                sbDigimon.move(Kaisa.Enums.opposite(launchDir), 3);
                sbAttack.move(Kaisa.Enums.opposite(launchDir), 3);
                pc = 4;
                return 0.0;
            case 4:
                if (attack == 0 || attack == 2) {
                    sbDigimon.setSprite(digimonSprites[1]);
                    sbAttack.setSprite((attack == 0) ? digimonSprites[3] : digimonSprites[4]);

                    // A wide ability sprite is launched from further back and
                    // takes extra steps to clear the screen.
                    if (attack == 2 && digimonSprites[4] != null && digimonSprites[4][3] > 32) {
                        sbAttack.setSize(digimonSprites[4][3], 24)
                                .move(Kaisa.Enums.opposite(launchDir), sbAttack.width - 24)
                                .centerComponent();
                        sbDigimon.move(Kaisa.Enums.opposite(launchDir), 1);
                        extraPixels = sbAttack.width - 24;
                        gm.audioMgr.playSound("launchAttackLong");
                    } else {
                        gm.audioMgr.playSound("launchAttack");
                    }
                    i = 0;
                    pc = 5;
                    return 0.0;
                } else if (attack == 1) {
                    sbDigimon.setSprite(digimonSprites[2]);
                    gm.audioMgr.playSound("launchAttack");
                    i = 0;
                    pc = 9;
                    return 0.0;
                } else {
                    i = 0;
                    pc = 11;
                    return 0.0;
                }
            case 5:                                 // for (i = 0; i < 38; i++)
                if (i >= 38) { i = 0; pc = 7; return 0.0; }
                pc = 6;
                return 1.7 / 32;
            case 6:
                sbAttack.move(launchDir, 1);
                i += 1;
                pc = 5;
                return 0.0;
            case 7:                                 // for (i = 0; i < extraPixels; i++)
                if (i >= extraPixels) { pc = 15; return 0.3; }
                pc = 8;
                return 1.7 / 32;
            case 8:
                sbAttack.move(launchDir, 1);
                i += 1;
                pc = 7;
                return 0.0;
            case 9:                                 // crush: seven trailing copies
                if (i >= 7) { pc = 15; return 1.5; }
                Kaisa.ScreenBuilder.buildSprite("Crush" + i, parent)
                    .setSize(24, 24).center().setSprite(digimonSprites[2])
                    .flipHorizontal(isEnemy).move(launchDir, 4 * i);
                pc = 10;
                return 0.9 / 7;
            case 10:
                i += 1;
                pc = 9;
                return 0.0;
            case 11:                                // attack == 3: it turns away
                if (i >= 2) { pc = 15; return 0.0; }
                pc = 12;
                return 0.65;
            case 12:
                sbDigimon.flipHorizontal(true);
                pc = 13;
                return 0.65;
            case 13:
                sbDigimon.flipHorizontal(false);
                i += 1;
                pc = 11;
                return 0.0;
            case 15:
                Kaisa.ScreenBuilder.clearAnimParent(parent);
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:1986  AttackCollision
//
// The two attacks meet in the middle. The first 16 steps are always the same
// -- both sides walk one pixel towards each other -- and what happens on
// contact is a table of five outcomes indexed by (friendlyAttack,
// enemyAttack), each of them a nested coroutine in the original and a Routine
// of its own here.
//
// `winner` is 0 friendly, 1 enemy, 2 tie. `extraPixels` carries the two
// widths a wider-than-32 ability adds to each side's travel, which the
// outcomes need after the collision -- so it lives on the class, as the
// captured local it is in the original.
class AttackCollision extends Routine {
    var gm as GameManager;
    var friendlyAttack as Number;
    var friendlySprites as Array;
    var enemyAttack as Number;
    var enemySprites as Array;
    var winner as Number;

    var sbFriendlyAttack as SpriteBuilder?;
    var sbEnemyAttack as SpriteBuilder?;
    var extraPixels as Array<Number> = [0, 0];
    var i as Number = 0;

    function initialize(gmIn as GameManager, friendlyAttackIn as Number,
                        friendlySpritesIn as Array, enemyAttackIn as Number,
                        enemySpritesIn as Array, winnerIn as Number) {
        Routine.initialize();
        gm = gmIn;
        friendlyAttack = friendlyAttackIn;
        friendlySprites = friendlySpritesIn;
        enemyAttack = enemyAttackIn;
        enemySprites = enemySpritesIn;
        winner = winnerIn;
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                sbFriendlyAttack = Kaisa.ScreenBuilder.buildSprite("FriendlyAttack", parent)
                    .setSize(24, 24);
                sbFriendlyAttack.center().placeOutside(Kaisa.DIR_RIGHT);
                sbEnemyAttack = Kaisa.ScreenBuilder.buildSprite("EnemyAttack", parent)
                    .setSize(24, 24);
                sbEnemyAttack.center().placeOutside(Kaisa.DIR_LEFT);
                sbEnemyAttack.flipHorizontal(true);

                extraPixels = [0, 0];

                // Place the friendly attack above if he won.
                if (winner == 0) { sbFriendlyAttack.setAsLastSibling(); }

                if (friendlyAttack == 0) {
                    sbFriendlyAttack.setSprite(friendlySprites[3]);
                } else if (friendlyAttack == 1) {
                    sbFriendlyAttack.setSprite(friendlySprites[2]);
                } else if (friendlyAttack == 2) {
                    sbFriendlyAttack.setSprite(friendlySprites[4]);
                    if (friendlySprites[4] != null && friendlySprites[4][3] > 32) {
                        extraPixels[0] = friendlySprites[4][3] - 24;
                        sbFriendlyAttack.setSize(friendlySprites[4][3], 24)
                            .move(Kaisa.DIR_RIGHT, extraPixels[0])
                            .centerComponent()
                            .placeOutside(Kaisa.DIR_RIGHT);
                    }
                } else if (friendlyAttack == 3) {
                    sbFriendlyAttack.setActive(false);
                }
                if (enemyAttack == 0) {
                    sbEnemyAttack.setSprite(enemySprites[3]);
                } else if (enemyAttack == 1) {
                    sbEnemyAttack.setSprite(enemySprites[2]);
                } else if (enemyAttack == 2) {
                    sbEnemyAttack.setSprite(enemySprites[4]);
                    if (enemySprites[4] != null && enemySprites[4][3] > 32) {
                        extraPixels[1] = enemySprites[4][3] - 24;
                        sbEnemyAttack.setSize(enemySprites[4][3], 24)
                            .move(Kaisa.DIR_LEFT, extraPixels[1])
                            .centerComponent()
                            .placeOutside(Kaisa.DIR_LEFT);
                    }
                } else if (enemyAttack == 3) {
                    sbEnemyAttack.setActive(false);
                }

                gm.audioMgr.playSound("attackTravelVeryLong");
                i = 0;
                pc = 1;
                return 0.0;
            case 1:                                 // for (i = 0; i < 16; i++)
                if (i >= 16) { pc = 3; return 0.0; }
                sbFriendlyAttack.move(Kaisa.DIR_LEFT, 1);
                sbEnemyAttack.move(Kaisa.DIR_RIGHT, 1);
                pc = 2;
                return 0.6 / 16;
            case 2:
                i += 1;
                pc = 1;
                return 0.0;
            case 3:
                // The pattern of the table is: tie, player win, player lose.
                pc = 4;
                rt.call(outcome());
                return 0.0;
            case 4:
                Kaisa.ScreenBuilder.clearAnimParent(parent);
                return Routine.DONE;
        }
        return Routine.DONE;
    }

    function outcome() as Routine {
        if (friendlyAttack == 0) {
            if (enemyAttack == 0) { return new EnergyOrAbilityCollides(self); }
            else if (enemyAttack == 1) { return new EnergyVsCrush(self); }
            else if (enemyAttack == 2) { return new EnergyVsAbility(self); }
            return new CrushVsAbility(self);
        } else if (friendlyAttack == 1) {
            if (enemyAttack == 0) { return new EnergyVsCrush(self); }
            else if (enemyAttack == 1) { return new CrushCollides(self); }
            return new CrushVsAbility(self);
        } else if (friendlyAttack == 2) {
            if (enemyAttack == 0) { return new EnergyVsAbility(self); }
            else if (enemyAttack == 2) { return new EnergyOrAbilityCollides(self); }
            return new CrushVsAbility(self);
        }
        // friendlyAttack == 3: reuse this animation because it's identical.
        return new CrushVsAbility(self);
    }

    // The two local functions the outcomes share.
    function transformAttackIntoCollision(sb as SpriteBuilder) as Void {
        sb.setSprite(Kaisa.Sprites.BATTLE_ATTACK_COLLISION);
        sb.setSize(7, 24);
    }

    function transformAttackIntoBigCollision(sb as SpriteBuilder) as Void {
        sb.setSprite(Kaisa.Sprites.BATTLE_ATTACK_COLLISION_BIG);
        sb.setSize(15, 32);
        sb.setPosition(8, 0);
    }
}

// AttackCollision._EnergyOrAbilityCollides
class EnergyOrAbilityCollides extends Routine {
    var a as AttackCollision;
    var i as Number = 0;

    function initialize(parentIn as AttackCollision) {
        Routine.initialize();
        a = parentIn;
    }

    function step(rt as Fiber) as Float {
        switch (pc) {
            case 0:
                if (a.winner == 0) {
                    a.transformAttackIntoCollision(a.sbEnemyAttack);
                    i = 0; pc = 1; return 0.0;
                } else if (a.winner == 1) {
                    a.transformAttackIntoCollision(a.sbFriendlyAttack);
                    i = 0; pc = 5; return 0.0;
                }
                // winner == 2: reuse the friendly attack as the big collision.
                a.sbEnemyAttack.dispose();
                a.transformAttackIntoBigCollision(a.sbFriendlyAttack);
                pc = 9;
                return 0.15;
            case 1:                                 // for (i = 0; i < 40; i++)
                if (i >= 40) { i = 0; pc = 3; return 0.0; }
                if (i == 3) { a.sbEnemyAttack.dispose(); }
                a.sbFriendlyAttack.move(Kaisa.DIR_LEFT, 1);
                pc = 2;
                return 0.6 / 16;
            case 2:
                i += 1; pc = 1; return 0.0;
            case 3:                                 // for (i = 0; i < extraPixels[0]; i++)
                if (i >= a.extraPixels[0]) { return Routine.DONE; }
                a.sbFriendlyAttack.move(Kaisa.DIR_LEFT, 1);
                pc = 4;
                return 0.6 / 16;
            case 4:
                i += 1; pc = 3; return 0.0;
            case 5:
                if (i >= 40) { i = 0; pc = 7; return 0.0; }
                if (i == 3) { a.sbFriendlyAttack.dispose(); }
                a.sbEnemyAttack.move(Kaisa.DIR_RIGHT, 1);
                pc = 6;
                return 0.6 / 16;
            case 6:
                i += 1; pc = 5; return 0.0;
            case 7:                                 // for (i = 0; i < extraPixels[1]; i++)
                if (i >= a.extraPixels[1]) { return Routine.DONE; }
                a.sbEnemyAttack.move(Kaisa.DIR_RIGHT, 1);
                pc = 8;
                return 0.6 / 16;
            case 8:
                i += 1; pc = 7; return 0.0;
            case 9:
                a.gm.audioMgr.stopSound();
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// AttackCollision._EnergyVsCrush
class EnergyVsCrush extends Routine {
    var a as AttackCollision;
    var winnerSprite as SpriteBuilder?;
    var loserSprite as SpriteBuilder?;
    var winnerDirection as Number = Kaisa.DIR_LEFT;
    var i as Number = 0;

    function initialize(parentIn as AttackCollision) {
        Routine.initialize();
        a = parentIn;
    }

    function step(rt as Fiber) as Float {
        switch (pc) {
            case 0:
                winnerSprite = (a.winner == 0) ? a.sbFriendlyAttack : a.sbEnemyAttack;
                loserSprite = (a.winner == 0) ? a.sbEnemyAttack : a.sbFriendlyAttack;
                winnerDirection = (a.winner == 0) ? Kaisa.DIR_LEFT : Kaisa.DIR_RIGHT;
                a.transformAttackIntoCollision(loserSprite);
                i = 0;
                pc = 1;
                return 0.0;
            case 1:                                 // for (i = 0; i < 16; i++)
                if (i >= 16) { return Routine.DONE; }
                if (i == 3) { loserSprite.dispose(); }
                winnerSprite.move(winnerDirection, 1);
                pc = 2;
                return 0.6 / 16;
            case 2:
                i += 1; pc = 1; return 0.0;
        }
        return Routine.DONE;
    }
}

// AttackCollision._EnergyVsAbility -- the ability breaks in two and the
// halves slide off past the energy panel that broke them.
class EnergyVsAbility extends Routine {
    var a as AttackCollision;
    var winnerSprite as SpriteBuilder?;
    var loserSprite as SpriteBuilder?;
    var winnerDirection as Number = Kaisa.DIR_LEFT;
    var cbBrokenAbilityUp as ContainerBuilder?;
    var cbBrokenAbilityDown as ContainerBuilder?;
    var i as Number = 0;

    function initialize(parentIn as AttackCollision) {
        Routine.initialize();
        a = parentIn;
    }

    function step(rt as Fiber) as Float {
        var parent = a.gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                winnerSprite = (a.winner == 0) ? a.sbFriendlyAttack : a.sbEnemyAttack;
                loserSprite = (a.winner == 0) ? a.sbEnemyAttack : a.sbFriendlyAttack;
                winnerSprite.setTransparent(true);  // the energy panel is transparent

                var brokenAbilityX = loserSprite.x;
                var brokenAbilitySprite = loserSprite.sprite;
                winnerDirection = (a.winner == 0) ? Kaisa.DIR_LEFT : Kaisa.DIR_RIGHT;
                var loserExtra = a.extraPixels[(a.winner == 0) ? 1 : 0];

                cbBrokenAbilityUp = Kaisa.ScreenBuilder.buildContainer("AbilityUp", parent, true)
                    .setSize(24 + loserExtra, 12).setMaskActive(true);
                cbBrokenAbilityUp.setPosition(brokenAbilityX, 4);
                Kaisa.ScreenBuilder.buildSprite("AbilityUpSprite", cbBrokenAbilityUp)
                    .setSize(24 + loserExtra, 24).centerComponent()
                    .setPosition(0, 0).setSprite(brokenAbilitySprite)
                    .flipHorizontal(a.winner == 0);

                cbBrokenAbilityDown = Kaisa.ScreenBuilder.buildContainer("AbilityDown", parent, true)
                    .setSize(24 + loserExtra, 12).setMaskActive(true);
                cbBrokenAbilityDown.setPosition(brokenAbilityX, 16);
                Kaisa.ScreenBuilder.buildSprite("AbilityDownSprite", cbBrokenAbilityDown)
                    .setSize(24 + loserExtra, 24).centerComponent()
                    .setPosition(0, -12).setSprite(brokenAbilitySprite)
                    .flipHorizontal(a.winner == 0);

                loserSprite.dispose();
                // Place the winning attack above everything else.
                winnerSprite.setAsLastSibling();
                i = 0;
                pc = 1;
                return 0.0;
            case 1:                                 // for (i = 0; i < 32; i++)
                if (i >= 32) { i = 0; pc = 3; return 0.0; }
                cbBrokenAbilityUp.move(Kaisa.Enums.opposite(winnerDirection), 1)
                                 .move(Kaisa.DIR_UP, 1);
                cbBrokenAbilityDown.move(Kaisa.Enums.opposite(winnerDirection), 1)
                                   .move(Kaisa.DIR_DOWN, 1);
                winnerSprite.move(winnerDirection, 1);
                pc = 2;
                return 0.6 / 16;
            case 2:
                i += 1; pc = 1; return 0.0;
            case 3:                                 // for (i = 0; i < extraPixels[winner]; i++)
                if (i >= a.extraPixels[a.winner]) { return Routine.DONE; }
                winnerSprite.move(winnerDirection, 1);
                pc = 4;
                return 0.6 / 16;
            case 4:
                i += 1; pc = 3; return 0.0;
        }
        return Routine.DONE;
    }
}

// AttackCollision._CrushCollides
class CrushCollides extends Routine {
    var a as AttackCollision;
    var pushDirection as Number = Kaisa.DIR_LEFT;
    var i as Number = 0;

    function initialize(parentIn as AttackCollision) {
        Routine.initialize();
        a = parentIn;
    }

    function step(rt as Fiber) as Float {
        switch (pc) {
            case 0:
                i = 0;
                if (a.winner == 2) { pc = 1; return 0.0; }
                pushDirection = (a.winner == 0) ? Kaisa.DIR_LEFT : Kaisa.DIR_RIGHT;
                pc = 4;
                return 0.0;
            case 1:                                 // a tie: they bounce apart
                if (i >= 40) { pc = 3; return 0.0; }
                a.sbFriendlyAttack.move(Kaisa.DIR_RIGHT, 1);
                a.sbEnemyAttack.move(Kaisa.DIR_LEFT, 1);
                pc = 2;
                return 0.6 / 16;
            case 2:
                i += 1; pc = 1; return 0.0;
            case 3:
                a.gm.audioMgr.stopSound();
                return Routine.DONE;
            case 4:                                 // the winner pushes the loser
                if (i >= 40) { return Routine.DONE; }
                a.sbFriendlyAttack.move(pushDirection, 1);
                a.sbEnemyAttack.move(pushDirection, 1);
                pc = 5;
                return 0.6 / 16;
            case 5:
                i += 1; pc = 4; return 0.0;
        }
        return Routine.DONE;
    }
}

// AttackCollision._CrushVsAbility -- the ability rolls straight over the
// crush, which is removed at the frame it is completely covered.
class CrushVsAbility extends Routine {
    var a as AttackCollision;
    var winnerSprite as SpriteBuilder?;
    var loserSprite as SpriteBuilder?;
    var winnerDirection as Number = Kaisa.DIR_LEFT;
    var i as Number = 0;

    function initialize(parentIn as AttackCollision) {
        Routine.initialize();
        a = parentIn;
    }

    function step(rt as Fiber) as Float {
        switch (pc) {
            case 0:
                winnerSprite = (a.winner == 0) ? a.sbFriendlyAttack : a.sbEnemyAttack;
                loserSprite = (a.winner == 0) ? a.sbEnemyAttack : a.sbFriendlyAttack;
                winnerDirection = (a.winner == 0) ? Kaisa.DIR_LEFT : Kaisa.DIR_RIGHT;
                i = 0;
                pc = 1;
                return 0.0;
            case 1:                                 // for (i = 0; i < 40; i++)
                if (i >= 40) { i = 0; pc = 3; return 0.0; }
                if (i == 16) { loserSprite.dispose(); }
                winnerSprite.move(winnerDirection, 1);
                pc = 2;
                return 0.6 / 16;
            case 2:
                i += 1; pc = 1; return 0.0;
            case 3:                                 // for (i = 0; i < extraPixels[winner]; i++)
                if (i >= a.extraPixels[a.winner]) { return Routine.DONE; }
                winnerSprite.move(winnerDirection, 1);
                pc = 4;
                return 0.6 / 16;
            case 4:
                i += 1; pc = 3; return 0.0;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:2181  DestroyLoser
//
// What happens to the Digimon that lost the exchange, which depends on what
// beat it: an energy shot explodes it where it stands, a crush drags it off
// the screen first, and an ability rolls over it. Then the LIFE sign counts
// the hit points down.
//
// `winningAbility` null means the caller does not want the ability win
// animation to play, as the original's note says.
class DestroyLoser extends Routine {
    var gm as GameManager;
    var loserSprites as Array;
    var winningAttack as Number;
    var winningAbility as Array<Number>?;
    var isEnemy as Boolean;
    var loserHPbefore as Number;
    var loserHPnow as Number;

    var sbLoser as SpriteBuilder?;
    var sbAbility as SpriteBuilder?;
    var cbLifeSign as ContainerBuilder?;
    var winningDirection as Number = Kaisa.DIR_LEFT;
    var extraPixels as Number = 0;
    var i as Number = 0;

    function initialize(gmIn as GameManager, loserSpritesIn as Array,
                        winningAttackIn as Number, winningAbilityIn as Array<Number>?,
                        isEnemyIn as Boolean, loserHPbeforeIn as Number,
                        loserHPnowIn as Number) {
        Routine.initialize();
        gm = gmIn;
        loserSprites = loserSpritesIn;
        winningAttack = winningAttackIn;
        winningAbility = winningAbilityIn;
        isEnemy = isEnemyIn;
        loserHPbefore = loserHPbeforeIn;
        loserHPnow = loserHPnowIn;
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                sbLoser = Kaisa.ScreenBuilder.buildSprite("Loser", parent)
                    .setSize(24, 24).center();
                // Flip the sprite if the loser is the enemy.
                sbLoser.flipHorizontal(isEnemy);
                winningDirection = isEnemy ? Kaisa.DIR_LEFT : Kaisa.DIR_RIGHT;

                if (winningAttack == 0) {
                    sbLoser.setSprite(loserSprites[0]);
                    pc = 1;
                    return 0.5;
                } else if (winningAttack == 1) {
                    sbLoser.setSprite(loserSprites[2]);
                    sbLoser.placeOutside(Kaisa.Enums.opposite(winningDirection));
                    i = 0;
                    pc = 3;
                    return 0.0;
                } else if (winningAttack == 2 && winningAbility != null) {
                    extraPixels = 0;
                    sbLoser.setSprite(loserSprites[0]);
                    // SOURCE ODDITY, reproduced: the ability element is built
                    // with the same name as the loser.
                    sbAbility = Kaisa.ScreenBuilder.buildSprite("Loser", parent)
                        .setSize(24, 24).setSprite(winningAbility).center();
                    if (winningAbility[3] > 32) {
                        sbAbility.setSize(winningAbility[3], 24).centerComponent();
                        extraPixels = sbAbility.width - 24;
                    }
                    sbAbility.placeOutside(Kaisa.Enums.opposite(winningDirection));
                    // Flip the ability if the loser is the ally.
                    sbAbility.flipHorizontal(!isEnemy);
                    i = 0;
                    pc = 6;
                    return 0.0;
                }
                gm.audioMgr.stopSound();
                pc = 10;
                return 0.0;
            case 1:                                 // energy: it just explodes
                pc = 2;
                rt.call(new ExplodeLoser(self));
                return 0.0;
            case 2:
                pc = 10;
                return 0.0;
            case 3:                                 // crush: for (i = 0; i < 64; i++)
                if (i >= 64) { pc = 5; return 0.0; }
                sbLoser.move(winningDirection, 1);
                pc = 4;
                return 0.6 / 16;
            case 4:
                i += 1; pc = 3; return 0.0;
            case 5:
                pc = 2;
                rt.call(new ExplodeLoser(self));
                return 0.0;
            case 6:                                 // ability: for (i = 0; i < 64; i++)
                if (i >= 64) { i = 0; pc = 8; return 0.0; }
                if (i == 28) { sbLoser.setActive(false); }
                sbAbility.move(winningDirection, 1);
                pc = 7;
                return Kaisa.Constants.ATTACK_TRAVEL_SPEED;
            case 7:
                i += 1; pc = 6; return 0.0;
            case 8:                                 // for (i = 0; i < extraPixels; i++)
                if (i >= extraPixels) { gm.audioMgr.stopSound(); pc = 10; return 0.0; }
                if (i == 28) { sbLoser.setActive(false); }
                sbAbility.move(winningDirection, 1);
                pc = 9;
                return Kaisa.Constants.ATTACK_TRAVEL_SPEED;
            case 9:
                i += 1; pc = 8; return 0.0;
            case 10:
                // No animation is done when a digimon loses to an ability.
                sbLoser.setActive(true).setSprite(loserSprites[0]);
                pc = 11;
                return 0.5;
            case 11:
                cbLifeSign = Kaisa.ScreenBuilder.buildStatSign("LIFE", parent);
                pc = 12;
                return 0.5;
            case 12:
                gm.audioMgr.playButtonA();
                (cbLifeSign.getChildBuilder(1) as TextBoxBuilder).setText(loserHPbefore.toString());
                pc = 13;
                return 0.75;
            case 13:
                gm.audioMgr.playButtonA();
                (cbLifeSign.getChildBuilder(1) as TextBoxBuilder).setText(loserHPnow.toString());
                pc = 14;
                return 0.75;
            case 14:
                Kaisa.ScreenBuilder.clearAnimParent(parent);
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// DestroyLoser._ExplodeLoser
class ExplodeLoser extends Routine {
    var d as DestroyLoser;
    var i as Number = 0;

    function initialize(parentIn as DestroyLoser) {
        Routine.initialize();
        d = parentIn;
    }

    function step(rt as Fiber) as Float {
        switch (pc) {
            case 0:
                d.gm.audioMgr.playSound("explosion");
                d.sbLoser.flipHorizontal(false);
                d.sbLoser.center();
                i = 0;
                pc = 1;
                return 0.0;
            case 1:                                 // for (i = 0; i < 2; i++)
                if (i >= 2) { pc = 4; return 0.25; }
                d.sbLoser.setSprite(Kaisa.Sprites.BATTLE_EXPLOSION[0]);
                pc = 2;
                return 0.5;
            case 2:
                d.sbLoser.setSprite(Kaisa.Sprites.BATTLE_EXPLOSION[1]);
                pc = 3;
                return 0.5;
            case 3:
                i += 1; pc = 1; return 0.0;
            case 4:
                d.sbLoser.flipHorizontal(d.isEnemy);
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:1159  DisplayTurn -- one exchange of the battle, from
// both attacks leaving to the loser losing its hit points. It is nothing but
// a sequence of the three animations above.
class DisplayTurn extends Routine {
    var gm as GameManager;
    var friendlyIndex as Number;
    var friendlyAttack as Number;
    var friendlyEnergyRank as Number;
    var enemyIndex as Number;
    var enemyAttack as Number;
    var enemyEnergyRank as Number;
    var winner as Number;
    var disobeyed as Boolean;
    var loserHPbefore as Number;
    var loserHPnow as Number;

    var friendlySprites as Array = [];
    var enemySprites as Array = [];

    function initialize(gmIn as GameManager, friendlyIndexIn as Number,
                        friendlyAttackIn as Number, friendlyEnergyRankIn as Number,
                        enemyIndexIn as Number, enemyAttackIn as Number,
                        enemyEnergyRankIn as Number, winnerIn as Number,
                        disobeyedIn as Boolean, loserHPbeforeIn as Number,
                        loserHPnowIn as Number) {
        Routine.initialize();
        gm = gmIn;
        friendlyIndex = friendlyIndexIn;
        friendlyAttack = friendlyAttackIn;
        friendlyEnergyRank = friendlyEnergyRankIn;
        enemyIndex = enemyIndexIn;
        enemyAttack = enemyAttackIn;
        enemyEnergyRank = enemyEnergyRankIn;
        winner = winnerIn;
        disobeyed = disobeyedIn;
        loserHPbefore = loserHPbeforeIn;
        loserHPnow = loserHPnowIn;
    }

    function step(rt as Fiber) as Float {
        switch (pc) {
            case 0:
                friendlySprites = gm.getAllDigimonBattleSprites(friendlyIndex, friendlyEnergyRank);
                enemySprites = gm.getAllDigimonBattleSprites(enemyIndex, enemyEnergyRank);
                pc = 1;
                rt.call(new LaunchAttack(gm, friendlySprites, friendlyAttack, false, disobeyed));
                return 0.0;
            case 1:
                pc = 2;
                rt.call(new LaunchAttack(gm, enemySprites, enemyAttack, true, false));
                return 0.0;
            case 2:
                pc = 3;
                rt.call(new AttackCollision(gm, friendlyAttack, friendlySprites,
                                            enemyAttack, enemySprites, winner));
                return 0.0;
            case 3:
                if (winner == 0) {
                    // If the enemy used crush (and you, ability), skip the
                    // ability animation.
                    var abilitySprite = (enemyAttack == 1) ? null : friendlySprites[4];
                    pc = 4;
                    rt.call(new DestroyLoser(gm, enemySprites, friendlyAttack, abilitySprite,
                                             true, loserHPbefore, loserHPnow));
                    return 0.0;
                } else if (winner == 1) {
                    var abilitySprite = (friendlyAttack == 1) ? null : enemySprites[4];
                    pc = 4;
                    rt.call(new DestroyLoser(gm, friendlySprites, enemyAttack, abilitySprite,
                                             false, loserHPbefore, loserHPnow));
                    return 0.0;
                }
                return Routine.DONE;
            case 4:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}
