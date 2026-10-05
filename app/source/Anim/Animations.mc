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
                newDigimonSpriteCr = gm.digimonSprite(newDigimon, gm.data.ACTION_CR);

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
    // Null where the enemy has no sprites at all: the Jackpot Box's fight
    // passes attack 3, which never reads them.
    var enemySprites as Array?;
    var winner as Number;

    var sbFriendlyAttack as SpriteBuilder?;
    var sbEnemyAttack as SpriteBuilder?;
    var extraPixels as Array<Number> = [0, 0];
    var i as Number = 0;

    function initialize(gmIn as GameManager, friendlyAttackIn as Number,
                        friendlySpritesIn as Array, enemyAttackIn as Number,
                        enemySpritesIn as Array?, winnerIn as Number) {
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
        // Both attacks meet at their leading edges. Keep the enemy's right
        // edge at the contact point when its 24+ pixel sprite becomes 7 pixels;
        // otherwise the whole collision stays left of the 32-pixel canvas.
        if (sb == sbEnemyAttack) { sb.setX(sb.x + sb.width - 7); }
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

// port of Animations.cs:291  SummonDigimon
//
// The screen flashes black, then the give-power sprite pulses through it, and
// the Digimon is standing there when it clears. The element is named after the
// Digimon, as in the original -- the only place a name reaches the display
// list, and debug-visible only.
class SummonDigimon extends Routine {
    var gm as GameManager;
    var digimonIndex as Number;

    var sbDigimon as SpriteBuilder?;
    var sbBlackScreen as SpriteBuilder?;
    var i as Number = 0;

    function initialize(gmIn as GameManager, digimonIndexIn as Number) {
        Routine.initialize();
        gm = gmIn;
        digimonIndex = digimonIndexIn;
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                gm.audioMgr.playSound("summonDigimon");
                sbDigimon = Kaisa.ScreenBuilder.buildSprite(gm.data.name(digimonIndex), parent)
                    .setSize(24, 24).center().setActive(false);
                sbBlackScreen = Kaisa.ScreenBuilder.buildSprite("BlackScreen", parent)
                    .setSprite(Kaisa.Sprites.BLACK_SCREEN);
                i = 0;
                pc = 1;
                return 0.0;
            case 1:                                 // for (i = 0; i < 4; i++)
                if (i >= 4) { i = 0; pc = 4; return 0.0; }
                sbBlackScreen.setActive(false);
                pc = 2;
                return 0.15;
            case 2:
                sbBlackScreen.setActive(true);
                pc = 3;
                return 0.15;
            case 3:
                i += 1; pc = 1; return 0.0;
            case 4:                                 // for (i = 0; i < 4; i++)
                if (i >= 4) { i = 0; pc = 7; return 0.0; }
                sbBlackScreen.setSprite(Kaisa.Sprites.GIVE_POWER_INVERTED);
                pc = 5;
                return 0.15;
            case 5:
                sbBlackScreen.setSprite(Kaisa.Sprites.BLACK_SCREEN);
                pc = 6;
                return 0.15;
            case 6:
                i += 1; pc = 4; return 0.0;
            case 7:
                sbBlackScreen.setSprite(Kaisa.Sprites.GIVE_POWER_INVERTED);
                pc = 8;
                return 0.15;
            case 8:
                sbBlackScreen.setSprite(Kaisa.Sprites.GIVE_POWER);
                pc = 9;
                return 0.15;
            case 9:
                sbBlackScreen.setSprite(Kaisa.Sprites.GIVE_POWER_INVERTED);
                sbDigimon.setSprite(gm.digimonSprite(digimonIndex, gm.data.ACTION_BASE))
                         .setActive(true);
                i = 0;
                pc = 10;
                return 0.15;
            case 10:                                // for (i = 0; i < 2; i++)
                if (i >= 2) { pc = 13; return 0.0; }
                sbBlackScreen.setTransparent(true);
                sbBlackScreen.setSprite(Kaisa.Sprites.GIVE_POWER);
                pc = 11;
                return 0.15;
            case 11:
                sbBlackScreen.setTransparent(false);
                sbBlackScreen.setSprite(Kaisa.Sprites.GIVE_POWER_INVERTED);
                pc = 12;
                return 0.15;
            case 12:
                i += 1; pc = 10; return 0.0;
            case 13:
                sbBlackScreen.setTransparent(true);
                sbBlackScreen.setSprite(Kaisa.Sprites.GIVE_POWER);
                pc = 14;
                return 0.20;
            case 14:
                sbBlackScreen.setActive(false);
                pc = 15;
                return 0.20;
            case 15:
                sbBlackScreen.setActive(true);
                pc = 16;
                return 0.15;
            case 16:
                sbBlackScreen.setActive(false);
                pc = 17;
                return 0.90;
            case 17:
                sbBlackScreen.setActive(true);
                pc = 18;
                return 0.15;
            case 18:
                sbBlackScreen.setActive(false);
                pc = 19;
                return 1.25;
            case 19:
                sbDigimon.setSprite(gm.digimonSprite(digimonIndex, gm.data.ACTION_CR));
                pc = 20;
                return 0.75;
            case 20:
                sbDigimon.setSprite(gm.digimonSprite(digimonIndex, gm.data.ACTION_BASE));
                pc = 21;
                return 0.15;
            case 21:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:354  UnlockDigimon -- a curtain wipes the Digimon off
// the screen and the D-Tector flashes in its place.
class UnlockDigimon extends Routine {
    var gm as GameManager;
    var digimonIndex as Number;
    var useSpiritForm as Boolean;

    var sbDigimon as SpriteBuilder?;
    var sbCurtain as SpriteBuilder?;
    var sbPower as SpriteBuilder?;
    var i as Number = 0;

    function initialize(gmIn as GameManager, digimonIndexIn as Number,
                        useSpiritFormIn as Boolean) {
        Routine.initialize();
        gm = gmIn;
        digimonIndex = digimonIndexIn;
        useSpiritForm = useSpiritFormIn;
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                gm.audioMgr.playSound("unlockDigimon");
                sbDigimon = Kaisa.ScreenBuilder.buildSprite(gm.data.name(digimonIndex), parent)
                    .setSize(24, 24).center()
                    .setSprite(gm.digimonSprite(digimonIndex,
                        useSpiritForm ? gm.data.ACTION_SP : gm.data.ACTION_BASE));
                sbCurtain = Kaisa.ScreenBuilder.buildSprite("BlackScreen", parent)
                    .setSprite(Kaisa.Sprites.CURTAIN).setTransparent(true);
                sbCurtain.placeOutside(Kaisa.DIR_DOWN);
                i = 0;
                pc = 1;
                return 0.15;
            case 1:                                 // for (i = 0; i < 32; i++)
                if (i >= 32) { i = 0; pc = 3; return 0.0; }
                sbCurtain.move(Kaisa.DIR_UP, 1);
                pc = 2;
                return 1.5 / 32;
            case 2:
                i += 1; pc = 1; return 0.0;
            case 3:                                 // for (i = 0; i < 32; i++)
                if (i >= 32) { pc = 5; return 0.75; }
                sbCurtain.move(Kaisa.DIR_UP, 1);
                sbDigimon.move(Kaisa.DIR_UP, 1);
                pc = 4;
                return 1.5 / 32;
            case 4:
                i += 1; pc = 3; return 0.0;
            case 5:
                sbDigimon.dispose();
                sbCurtain.dispose();
                Kaisa.ScreenBuilder.buildSprite("DTector", parent)
                    .setSprite(Kaisa.Sprites.D_TECTOR);
                sbPower = Kaisa.ScreenBuilder.buildSprite("Power", parent)
                    .setSprite(Kaisa.Sprites.GIVE_MASSIVE_POWER_INVERTED)
                    .setTransparent(true);
                sbPower.setActive(false);
                i = 0;
                pc = 6;
                return 0.30;
            case 6:                                 // for (i = 0; i < 5; i++)
                if (i >= 5) { pc = 9; return 0.45; }
                sbPower.setActive(true);
                pc = 7;
                return 0.15;
            case 7:
                sbPower.setActive(false);
                pc = 8;
                return 0.15;
            case 8:
                i += 1; pc = 6; return 0.0;
            case 9:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:1229  RegularEvolution -- the Digimon blinks and comes
// back as its evolved form. A successful evolution then holds its pose, like
// SummonDigimon, before the animation queue returns to battle.
class RegularEvolution extends Routine {
    var gm as GameManager;
    var digimonBefore as Number;
    var digimonAfter as Number;

    var sbDigimon as SpriteBuilder?;
    var sbGivePower as SpriteBuilder?;
    var i as Number = 0;

    function initialize(gmIn as GameManager, digimonBeforeIn as Number,
                        digimonAfterIn as Number) {
        Routine.initialize();
        gm = gmIn;
        digimonBefore = digimonBeforeIn;
        digimonAfter = digimonAfterIn;
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                sbDigimon = Kaisa.ScreenBuilder.buildSprite("Digimon", parent)
                    .setSize(24, 24).center()
                    .setSprite(gm.digimonSprite(digimonBefore, gm.data.ACTION_BASE));
                // SOURCE ODDITY, reproduced: the flash element is named
                // "Digimon" too.
                sbGivePower = Kaisa.ScreenBuilder.buildSprite("Digimon", parent)
                    .setSprite(Kaisa.Sprites.GIVE_POWER).setTransparent(true)
                    .setActive(false);
                gm.audioMgr.playSound("evolutionRegular");
                i = 0;
                pc = 1;
                return 0.0;
            case 1:                                 // for (i = 0; i < 2; i++)
                if (i >= 2) { i = 0; pc = 4; return 0.5; }
                pc = 2;
                return 0.5;
            case 2:
                sbGivePower.setActive(true);
                pc = 3;
                return 0.1;
            case 3:
                sbGivePower.setActive(false);
                i += 1;
                pc = 1;
                return 0.0;
            case 4:                                 // for (i = 0; i < 5; i++)
                if (i >= 5) { pc = 7; return 0.25; }
                if (i == 2) {
                    sbDigimon.setSprite(gm.digimonSprite(digimonAfter, gm.data.ACTION_BASE));
                }
                sbDigimon.setActive(false);
                pc = 5;
                return 0.25;
            case 5:
                sbDigimon.setActive(true);
                pc = 6;
                return 0.25;
            case 6:
                i += 1; pc = 4; return 0.0;
            case 7:
                sbGivePower.setActive(true);
                pc = 8;
                return 0.1;
            case 8:
                sbGivePower.setActive(false);
                pc = 9;
                return 0.25;
            case 9:
                if (digimonBefore == digimonAfter) { return Routine.DONE; }
                sbDigimon.setSprite(gm.digimonSprite(digimonAfter, gm.data.ACTION_CR));
                pc = 10;
                return 0.75;
            case 10:
                sbDigimon.setSprite(gm.digimonSprite(digimonAfter, gm.data.ACTION_BASE));
                pc = 11;
                return 0.15;
            case 11:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:1260  SpiritEvolution
//
// The long one: the character flashes, turns into the spirit, four copies of
// the spirit fly apart, the screen goes black and the new Digimon steps out
// from behind a curtain. TOTAL DURATION: 25.6s.
class SpiritEvolution extends Routine {
    var gm as GameManager;
    var character as Number;
    var digimonIndex as Number;

    var sCharacter as Array = [];
    var sDigimon as Array = [];
    var sbBackground as SpriteBuilder?;
    var sbCharacter as SpriteBuilder?;
    var sbGiveMassivePower as SpriteBuilder?;
    var sbDigimon as Array<SpriteBuilder?> = [null, null, null, null];
    var sbBlackSprite as SpriteBuilder?;
    var i as Number = 0;

    function initialize(gmIn as GameManager, characterIn as Number,
                        digimonIndexIn as Number) {
        Routine.initialize();
        gm = gmIn;
        character = characterIn;
        digimonIndex = digimonIndexIn;
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                sCharacter = gm.characterSprites(character);
                sDigimon = gm.getAllDigimonSprites(digimonIndex);

                sbBackground = Kaisa.ScreenBuilder.buildSprite("BlackBackground", parent)
                    .setSprite(Kaisa.Sprites.BLACK_SCREEN).setActive(false);
                sbCharacter = Kaisa.ScreenBuilder.buildSprite("Char", parent)
                    .setSprite(sCharacter[0]);
                gm.audioMgr.playSound("evolutionSpirit");
                pc = 1;
                return 0.5;
            case 1:
                sbGiveMassivePower = Kaisa.ScreenBuilder.buildSprite("GivePower", parent)
                    .setSprite(Kaisa.Sprites.GIVE_MASSIVE_POWER_INVERTED).setTransparent(true);
                i = 0;
                pc = 2;
                return 0.0;
            case 2:                                 // for (i = 0; i < 3; i++)
                if (i >= 3) { pc = 5; return 0.0; }
                pc = 3;
                return 0.2;
            case 3:
                sbGiveMassivePower.setActive(false);
                pc = 4;
                return 0.4;
            case 4:
                sbGiveMassivePower.setActive(true);
                i += 1;
                pc = 2;
                return 0.0;
            case 5:
                sbCharacter.setSprite(sCharacter[9]);
                pc = 6;
                return 0.2;
            case 6:
                sbGiveMassivePower.setActive(false);
                pc = 7;
                return 0.3;
            case 7:
                sbGiveMassivePower.setActive(true);
                pc = 8;
                return 0.2;
            case 8:
                sbGiveMassivePower.setActive(false);
                pc = 9;
                return 0.2;
            case 9:
                sbCharacter.placeOutside(Kaisa.DIR_DOWN);
                sbCharacter.setSprite(sCharacter[0]);
                sbDigimon[0] = Kaisa.ScreenBuilder.buildSprite("Spirit", parent)
                    .setSize(24, 24).setSprite(sDigimon[3]).center();
                i = 0;
                pc = 10;
                return 0.0;
            case 10:                                // for (i = 0; i < 2; i++)
                if (i >= 2) { pc = 13; return 0.7; }
                pc = 11;
                return 0.15;
            case 11:
                sbDigimon[0].setActive(false);
                pc = 12;
                return 0.25;
            case 12:
                sbDigimon[0].setActive(true);
                i += 1;
                pc = 10;
                return 0.0;
            case 13:
                for (var n = 1; n < 4; n += 1) {
                    sbDigimon[n] = Kaisa.ScreenBuilder.buildSprite("Spirit", parent)
                        .setSize(24, 24).setSprite(sDigimon[3]).center();
                    sbDigimon[n].setTransparent(true);
                }
                i = 0;
                pc = 14;
                return 0.0;
            case 14:                                // for (i = 0; i < 32; i++)
                if (i >= 32) { pc = 16; return 0.0; }
                sbDigimon[0].move(Kaisa.DIR_LEFT, 1);
                sbDigimon[1].move(Kaisa.DIR_RIGHT, 1);
                sbDigimon[2].move(Kaisa.DIR_UP, 1);
                sbDigimon[3].move(Kaisa.DIR_DOWN, 1);
                pc = 15;
                return 3.0 / 32;
            case 15:
                i += 1; pc = 14; return 0.0;
            case 16:
                for (var n = 1; n < 4; n += 1) { sbDigimon[n].dispose(); }
                i = 0;
                pc = 17;
                return 0.3;
            case 17:                                // for (i = 0; i < 64; i++)
                if (i >= 64) { pc = 19; return 0.7; }
                sbCharacter.move(Kaisa.DIR_UP, 1);
                pc = 18;
                return 1.0 / 64;
            case 18:
                i += 1; pc = 17; return 0.0;
            case 19:
                sbBackground.setActive(true);
                i = 0;
                pc = 20;
                return 0.5;
            case 20:                                // for (i = 0; i < 3; i++)
                if (i >= 3) { pc = 23; return 0.0; }
                sbBackground.setSprite(Kaisa.Sprites.GIVE_POWER);
                pc = 21;
                return 0.1;
            case 21:
                sbBackground.setSprite(Kaisa.Sprites.BLACK_SCREEN);
                pc = 22;
                return 0.5;
            case 22:
                i += 1; pc = 20; return 0.0;
            case 23:
                sbBlackSprite = Kaisa.ScreenBuilder.buildSprite("BlackSprite", parent)
                    .setSprite(sDigimon[4]);
                pc = 24;
                return 0.1;
            case 24:
                sbBlackSprite.setActive(false);
                pc = 25;
                return 0.5;
            case 25:
                sbBlackSprite.setActive(true);
                i = 0;
                pc = 26;
                return 0.1;
            case 26:                                // for (i = 0; i < 3; i++)
                if (i >= 3) { pc = 29; return 0.0; }
                sbBlackSprite.setActive(false);
                pc = 27;
                return 0.3;
            case 27:
                sbBlackSprite.setActive(true);
                pc = 28;
                return 0.2;
            case 28:
                i += 1; pc = 26; return 0.0;
            case 29:
                sbBlackSprite.setActive(false);
                pc = 30;
                return 0.3;
            case 30:
                sbBlackSprite.setActive(true);
                pc = 31;
                return 0.1;
            case 31:
                sbBackground.setActive(false);
                sbBlackSprite.setActive(false);
                pc = 32;
                return 0.5;
            case 32:
                sbDigimon[0].setSprite(sDigimon[0]).center();
                pc = 33;
                return 0.2;
            case 33:
                sbBlackSprite.placeOutside(Kaisa.DIR_DOWN);
                sbBlackSprite.setSprite(Kaisa.Sprites.CURTAIN).setTransparent(true);
                sbBlackSprite.setActive(true);
                i = 0;
                pc = 34;
                return 0.0;
            case 34:                                // for (i = 0; i < 64; i++)
                if (i >= 64) { pc = 36; return 0.6; }
                sbBlackSprite.move(Kaisa.DIR_UP, 1);
                pc = 35;
                return 3.0 / 64;
            case 35:
                i += 1; pc = 34; return 0.0;
            case 36:
                sbDigimon[0].setSprite(sDigimon[1]);
                pc = 37;
                return 0.8;
            case 37:
                sbDigimon[0].setSprite(sDigimon[0]);
                pc = 38;
                return 0.6;
            case 38:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:1380  FusionSpiritEvolution
//
// The fusion evolution: the same opening flashes as SpiritEvolution, then the
// ten small spirits fly in one pair at a time, a cover wipes down over the
// transcendent spirit, and the Digimon runs in twice before the final curtain.
//
// Which ten spirits depends on which fusion this is; the source picks them by
// name, and Kaisa.WellKnown carries the two lists resolved to indices at build
// time (ADR 7, tools/gen_wellknown.py).
class FusionSpiritEvolution extends Routine {
    var gm as GameManager;
    var character as Number;
    var digimonIndex as Number;

    var sCharacter as Array = [];
    var sDigimon as Array = [];
    var sHumans as Array = [];
    var sAnimals as Array = [];

    var sbBackground as SpriteBuilder?;
    var sbCharacter as SpriteBuilder?;
    var sbGiveMassivePower as SpriteBuilder?;
    var sbSmallHuman as SpriteBuilder?;
    var sbSmallAnimal as SpriteBuilder?;
    var sbTranscendent as SpriteBuilder?;
    var sbCover as RectangleBuilder?;
    var sbCurtain as SpriteBuilder?;
    var sbGivePower as SpriteBuilder?;
    var i as Number = 0;
    var j as Number = 0;

    function initialize(gmIn as GameManager, characterIn as Number,
                        digimonIndexIn as Number) {
        Routine.initialize();
        gm = gmIn;
        character = characterIn;
        digimonIndex = digimonIndexIn;
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                sCharacter = gm.characterSprites(character);
                sDigimon = gm.getAllDigimonSprites(digimonIndex);

                var set = (digimonIndex == Kaisa.WellKnown.FUSION_TRIGGER) ? 0 : 1;
                sHumans = [];
                sAnimals = [];
                for (var n = 0; n < 5; n += 1) {
                    sHumans.add(gm.digimonSprite(Kaisa.WellKnown.FUSION_HUMANS[set][n],
                                                 gm.data.ACTION_SM));
                    sAnimals.add(gm.digimonSprite(Kaisa.WellKnown.FUSION_ANIMALS[set][n],
                                                  gm.data.ACTION_SM));
                }

                // Common animation.
                sbBackground = Kaisa.ScreenBuilder.buildSprite("BlackBackground", parent)
                    .setSprite(Kaisa.Sprites.BLACK_SCREEN).setActive(false);
                sbCharacter = Kaisa.ScreenBuilder.buildSprite("Char", parent)
                    .setSprite(sCharacter[0]);
                gm.audioMgr.playSound("evolutionSpirit");
                pc = 1;
                return 0.5;
            case 1:
                // SOURCE ODDITY, reproduced: the power flash is named "Char"
                // as well.
                sbGiveMassivePower = Kaisa.ScreenBuilder.buildSprite("Char", parent)
                    .setSprite(Kaisa.Sprites.GIVE_MASSIVE_POWER_INVERTED).setTransparent(true);
                i = 0;
                pc = 2;
                return 0.0;
            case 2:                                 // for (i = 0; i < 3; i++)
                if (i >= 3) { pc = 5; return 0.0; }
                pc = 3;
                return 0.2;
            case 3:
                sbGiveMassivePower.setActive(false);
                pc = 4;
                return 0.4;
            case 4:
                sbGiveMassivePower.setActive(true);
                i += 1; pc = 2; return 0.0;
            case 5:
                sbCharacter.setSprite(sCharacter[9]);
                pc = 6;
                return 0.2;
            case 6:
                sbGiveMassivePower.setActive(false);
                pc = 7;
                return 0.3;
            case 7:
                sbGiveMassivePower.setActive(true);
                pc = 8;
                return 0.2;
            case 8:
                sbGiveMassivePower.setActive(false);
                pc = 9;
                return 0.2;
            case 9:
                // Small spirits display -- total animation duration: 3.0 s.
                sbCharacter.dispose();
                sbSmallHuman = Kaisa.ScreenBuilder.buildSprite("Human", parent).setSize(14, 16);
                sbSmallAnimal = Kaisa.ScreenBuilder.buildSprite("Animal", parent).setSize(14, 16);
                i = 0;
                pc = 10;
                return 0.0;
            case 10:                                // for (i = 0; i < 5; i++)
                if (i >= 5) { pc = 15; return 0.0; }
                sbSmallHuman.setY(16).placeOutside(Kaisa.DIR_LEFT).move(Kaisa.DIR_LEFT, 1);
                sbSmallAnimal.setY(16).placeOutside(Kaisa.DIR_RIGHT).move(Kaisa.DIR_RIGHT, 1);
                sbSmallHuman.setSprite(sHumans[i]);
                sbSmallAnimal.setSprite(sAnimals[i]);
                j = 0;
                pc = 11;
                return 0.0;
            case 11:                                // for (j = 0; j < 4; j++)
                if (j >= 4) { j = 0; pc = 13; return 0.0; }
                sbSmallHuman.move(Kaisa.DIR_RIGHT, 4);
                sbSmallAnimal.move(Kaisa.DIR_LEFT, 4);
                pc = 12;
                return 0.6 / 10;
            case 12:
                j += 1; pc = 11; return 0.0;
            case 13:                                // for (j = 0; j < 6; j++)
                if (j >= 6) { i += 1; pc = 10; return 0.0; }
                sbSmallHuman.move(Kaisa.DIR_UP, 4);
                sbSmallAnimal.move(Kaisa.DIR_UP, 4);
                pc = 14;
                return 0.6 / 10;
            case 14:
                j += 1; pc = 13; return 0.0;
            case 15:
                sbSmallHuman.dispose();
                sbSmallAnimal.dispose();
                // Create Transcendent spirit -- total animation duration: 3.2 s.
                sbTranscendent = Kaisa.ScreenBuilder.buildSprite("Transcendent", parent)
                    .setSize(24, 24).setSprite(sDigimon[3]).center();
                sbCover = Kaisa.ScreenBuilder.buildRectangle("Cover", parent)
                    .setSize(32, 32).setColor(false);
                sbCurtain = Kaisa.ScreenBuilder.buildSprite("Curtain", parent)
                    .setSprite(Kaisa.Sprites.CURTAIN_SPECIAL[0]).placeOutside(Kaisa.DIR_UP);
                sbCurtain.setTransparent(true);
                sbGivePower = Kaisa.ScreenBuilder.buildSprite("MassivePower", parent)
                    .setSprite(Kaisa.Sprites.GIVE_MASSIVE_POWER_INVERTED);
                sbGivePower.setTransparent(true);
                sbGivePower.setActive(false);
                i = 0;
                pc = 16;
                return 0.0;
            case 16:                                // for (i = 0; i < 32; i++)
                if (i >= 32) { pc = 18; return 0.0; }
                if (i == 14 || i == 28) { sbGivePower.setActive(true); }
                if (i == 15 || i == 29) { sbGivePower.setActive(false); }
                sbCover.move(Kaisa.DIR_DOWN, 1);
                sbCurtain.move(Kaisa.DIR_DOWN, 1);
                pc = 17;
                return 3.2 / 32;
            case 17:
                i += 1; pc = 16; return 0.0;
            case 18:
                sbCurtain.placeOutside(Kaisa.DIR_DOWN);
                sbGivePower.dispose();
                i = 0;
                pc = 19;
                return 0.0;
            case 19:                                // flash spirit
                if (i >= 3) { i = 0; pc = 22; return 0.0; }
                sbTranscendent.setActive(false);
                pc = 20;
                return 0.35;
            case 20:
                sbTranscendent.setActive(true);
                pc = 21;
                return 0.35;
            case 21:
                i += 1; pc = 19; return 0.0;
            case 22:                                // for (i = 0; i < 32; i++)
                if (i >= 32) { i = 0; pc = 24; return 0.0; }
                sbTranscendent.move(Kaisa.DIR_UP, 1);
                pc = 23;
                return 1.4 / 32;
            case 23:
                i += 1; pc = 22; return 0.0;
            case 24:                                // the Digimon runs twice
                sbTranscendent.setSprite(sDigimon[2]);
                sbTranscendent.setY(4).placeOutside(Kaisa.DIR_RIGHT);
                i = 0;
                pc = 25;
                return 0.0;
            case 25:                                // for (i = 0; i < 12; i++)
                if (i >= 12) { pc = 27; return 0.7; }
                sbTranscendent.move(Kaisa.DIR_LEFT, 6);
                pc = 26;
                return 1.0 / 12;
            case 26:
                i += 1; pc = 25; return 0.0;
            case 27:
                sbTranscendent.setSprite(sDigimon[2]);
                sbTranscendent.placeOutside(Kaisa.DIR_RIGHT);
                i = 0;
                pc = 28;
                return 0.0;
            case 28:                                // for (i = 0; i < 14; i++)
                if (i >= 14) { pc = 30; return 0.0; }
                sbTranscendent.move(Kaisa.DIR_LEFT, 2);
                pc = 29;
                return 0.7 / 14;
            case 29:
                i += 1; pc = 28; return 0.0;
            case 30:
                sbTranscendent.setSprite(sDigimon[0]);
                // Final curtain.
                sbCurtain.setSprite(Kaisa.Sprites.CURTAIN).setTransparent(true);
                sbCurtain.setActive(true);
                i = 0;
                pc = 31;
                return 0.0;
            case 31:                                // for (i = 0; i < 64; i++)
                if (i >= 64) { pc = 33; return 0.6; }
                sbCurtain.move(Kaisa.DIR_UP, 1);
                pc = 32;
                return 3.0 / 64;
            case 32:
                i += 1; pc = 31; return 0.0;
            case 33:
                sbTranscendent.setSprite(sDigimon[1]);
                pc = 34;
                return 0.8;
            case 34:
                sbTranscendent.setSprite(sDigimon[0]);
                pc = 35;
                return 0.6;
            case 35:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:1667  AncientEvolution
//
// The two spirits the ancient is made of rise past the screen in turn, then
// the spiral and circle turn, and the ancient Digimon is left standing. Which
// two spirits those are comes from WellKnown.ANCIENT_SPIRITS, the switch the
// original writes over the Digimon's name.
class AncientEvolution extends Routine {
    var gm as GameManager;
    var character as Number;
    var digimonIndex as Number;

    var sAncient as Array<Number>?;
    var sAncientAt as Array<Number>?;
    var sHumanSpirit as Array<Number>?;
    var sAnimalSpirit as Array<Number>?;
    var sCharacter as Array = [];

    var sbSpiral as SpriteBuilder?;
    var sbCircle as SpriteBuilder?;
    var sbDigimon as SpriteBuilder?;
    var sbGiveMassivePower as SpriteBuilder?;
    var i as Number = 0;
    var j as Number = 0;

    function initialize(gmIn as GameManager, characterIn as Number,
                        digimonIndexIn as Number) {
        Routine.initialize();
        gm = gmIn;
        character = characterIn;
        digimonIndex = digimonIndexIn;
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                sAncient = gm.digimonSprite(digimonIndex, gm.data.ACTION_BASE);
                sAncientAt = gm.digimonSprite(digimonIndex, gm.data.ACTION_AT);
                // The switch has no default: a Digimon that is not one of the
                // ten leaves both spirits null, and the animation shows
                // nothing where they would be.
                sHumanSpirit = null;
                sAnimalSpirit = null;
                for (var n = 0; n < Kaisa.WellKnown.ANCIENT_SPIRITS.size(); n += 1) {
                    var row = Kaisa.WellKnown.ANCIENT_SPIRITS[n];
                    if (row[0] == digimonIndex) {
                        sHumanSpirit = gm.digimonSprite(row[1], gm.data.ACTION_SP);
                        sAnimalSpirit = gm.digimonSprite(row[2], gm.data.ACTION_SP);
                        break;
                    }
                }
                sCharacter = gm.characterSprites(character);

                sbSpiral = Kaisa.ScreenBuilder.buildSprite("Spiral", parent);
                sbCircle = Kaisa.ScreenBuilder.buildSprite("Circle", parent).setTransparent(true);
                sbDigimon = Kaisa.ScreenBuilder.buildSprite("Digimon", parent)
                    .setSize(24, 24).center().placeOutside(Kaisa.DIR_DOWN);
                sbGiveMassivePower = Kaisa.ScreenBuilder.buildSprite("GivePower", parent)
                    .setSprite(Kaisa.Sprites.GIVE_MASSIVE_POWER_INVERTED).setTransparent(true);
                sbGiveMassivePower.setActive(false);

                gm.audioMgr.playSound("evolutionAncient");

                // Show human spirit.
                sbDigimon.setSprite(sHumanSpirit);
                i = 0;
                pc = 1;
                return 0.0;
            case 1:                                 // for (i = 0; i < 28; i++)
                if (i >= 28) { i = 0; pc = 3; return 0.2; }
                sbDigimon.move(Kaisa.DIR_UP, 1);
                pc = 2;
                return 0.95 / 28;
            case 2:
                i += 1; pc = 1; return 0.0;
            case 3:                                 // for (i = 0; i < 3; i++)
                if (i >= 3) { i = 0; pc = 6; return 0.0; }
                sbGiveMassivePower.setActive(true);
                pc = 4;
                return 0.1;
            case 4:
                sbGiveMassivePower.setActive(false);
                pc = 5;
                return 0.3;
            case 5:
                i += 1; pc = 3; return 0.0;
            case 6:                                 // for (i = 0; i < 28; i++)
                if (i >= 28) { pc = 8; return 0.0; }
                sbDigimon.move(Kaisa.DIR_UP, 1);
                pc = 7;
                return 0.95 / 28;
            case 7:
                i += 1; pc = 6; return 0.0;
            case 8:                                 // show animal spirit
                sbDigimon.setSprite(sAnimalSpirit);
                sbDigimon.placeOutside(Kaisa.DIR_DOWN);
                i = 0;
                pc = 9;
                return 0.0;
            case 9:                                 // for (i = 0; i < 28; i++)
                if (i >= 28) { i = 0; pc = 11; return 0.2; }
                sbDigimon.move(Kaisa.DIR_UP, 1);
                pc = 10;
                return 0.95 / 28;
            case 10:
                i += 1; pc = 9; return 0.0;
            case 11:                                // for (i = 0; i < 3; i++)
                if (i >= 3) { i = 0; pc = 14; return 0.0; }
                sbGiveMassivePower.setActive(true);
                pc = 12;
                return 0.1;
            case 12:
                sbGiveMassivePower.setActive(false);
                pc = 13;
                return 0.3;
            case 13:
                i += 1; pc = 11; return 0.0;
            case 14:                                // for (i = 0; i < 28; i++)
                if (i >= 28) { pc = 16; return 0.0; }
                sbDigimon.move(Kaisa.DIR_UP, 1);
                pc = 15;
                return 0.95 / 28;
            case 15:
                i += 1; pc = 14; return 0.0;
            case 16:                                // spiral and circle
                sbGiveMassivePower.setSprite(sCharacter[0]).setTransparent(false);
                i = 0;
                pc = 17;
                return 0.0;
            case 17:                                // for (i = 0; i < 2; i++)
                if (i >= 2) { pc = 22; return 0.15; }
                sbGiveMassivePower.setActive(false);
                sbCircle.setSprite(Kaisa.Sprites.ANCIENT_CIRCLE[0]);
                j = 0;
                pc = 18;
                return 0.0;
            case 18:                                // for (j = 0; j < 3; j++)
                if (j >= 3) { pc = 21; return 0.0; }
                sbSpiral.setSprite(Kaisa.Sprites.ANCIENT_SPIRAL[0]);
                pc = 19;
                return 0.3;
            case 19:
                sbSpiral.setSprite(Kaisa.Sprites.ANCIENT_SPIRAL[1]);
                pc = 20;
                return 0.3;
            case 20:
                j += 1; pc = 18; return 0.0;
            case 21:
                sbGiveMassivePower.setActive(true);
                i += 1;
                pc = 17;
                return 0.3;
            case 22:
                sbGiveMassivePower.setSprite(sCharacter[9]);
                pc = 23;
                return 0.4;
            case 23:
                sbGiveMassivePower.dispose();
                j = 0;
                pc = 24;
                return 0.0;
            case 24:                                // for (j = 0; j < 3; j++)
                if (j >= 3) { i = 0; pc = 27; return 0.0; }
                if (j == 1) { sbCircle.setSprite(Kaisa.Sprites.ANCIENT_CIRCLE[1]); }
                if (j == 2) { sbCircle.setSprite(Kaisa.Sprites.ANCIENT_CIRCLE[2]); }
                sbSpiral.setSprite(Kaisa.Sprites.ANCIENT_SPIRAL[0]);
                pc = 25;
                return 0.3;
            case 25:
                sbSpiral.setSprite(Kaisa.Sprites.ANCIENT_SPIRAL[1]);
                pc = 26;
                return 0.3;
            case 26:
                j += 1; pc = 24; return 0.0;
            case 27:
                sbSpiral.dispose();
                sbCircle.setSprite(Kaisa.Sprites.BLACK_SCREEN);
                i = 0;
                pc = 28;
                return 0.0;
            case 28:                                // for (i = 0; i < 2; i++)
                if (i >= 2) { pc = 31; return 0.2; }
                pc = 29;
                return 0.2;
            case 29:
                sbCircle.setActive(false);
                pc = 30;
                return 0.2;
            case 30:
                sbCircle.setActive(true);
                i += 1; pc = 28; return 0.0;
            case 31:
                sbCircle.setActive(false);
                sbDigimon.setSprite(sAncient).center();
                i = 0;
                pc = 32;
                return 0.0;
            case 32:                                // for (i = 0; i < 2; i++)
                if (i >= 2) { pc = 35; return 0.0; }
                sbDigimon.setActive(true);
                pc = 33;
                return 0.15;
            case 33:
                sbDigimon.setActive(false);
                pc = 34;
                return 0.3;
            case 34:
                i += 1; pc = 32; return 0.0;
            case 35:
                sbDigimon.setActive(true);
                pc = 36;
                return 0.4;
            case 36:
                sbDigimon.setSprite(sAncientAt);
                pc = 37;
                return 0.55;
            case 37:
                sbDigimon.setSprite(sAncient);
                pc = 38;
                return 0.7;
            case 38:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:651  CharSadShort -- the character's disappointed
// bounce, the counterpart of CharHappyShort.
class CharSadShort extends Routine {
    var gm as GameManager;
    var sbChar as SpriteBuilder?;
    var charIdle as Array<Number>?;
    var charSad as Array<Number>?;
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
                charSad = sprites[7];
                gm.audioMgr.playSound("charSad");
                sbChar = Kaisa.ScreenBuilder.buildSprite("CharSad", gm.screenMgr.animParent)
                    .setSprite(charIdle);
                i = 0;
                pc = 1;
                return 0.0;
            case 1:                                 // for (i = 0; i < 2; i++)
                if (i >= 2) { pc = 4; return 0.0; }
                sbChar.setSprite(charIdle);
                pc = 2;
                return 0.475;
            case 2:
                sbChar.setSprite(charSad);
                pc = 3;
                return 0.475;
            case 3:
                i += 1; pc = 1; return 0.0;
            case 4:
                sbChar.dispose();
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:647  CharSad -- two CharSadShorts back to back.
class CharSad extends Routine {
    var gm as GameManager;

    function initialize(gmIn as GameManager) {
        Routine.initialize();
        gm = gmIn;
    }

    function step(rt as Fiber) as Float {
        switch (pc) {
            case 0:
                pc = 1;
                rt.call(new CharSadShort(gm));
                return 0.0;
            case 1:
                pc = 2;
                rt.call(new CharSadShort(gm));
                return 0.0;
            case 2:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// The reward screens -- LevelUp, LevelDown, RewardDistance and
// RewardSpiritPower -- are the same animation four times over: a four-frame
// background cycles while an icon fades in, the icon rises, and a label and a
// number count from the old value to the new one. The original repeats the
// code four times; the port does too (ADR 2), differing only where they do.
//
// port of Animations.cs:1057  LevelUp
class LevelUp extends Routine {
    var gm as GameManager;
    var levelBefore as Number;
    var levelAfter as Number;

    var sbLevelUpBG as SpriteBuilder?;
    var sbLevelUpIcon as SpriteBuilder?;
    var tbLevel as TextBoxBuilder?;
    var i as Number = 0;
    var cycle as Number = 0;

    function initialize(gmIn as GameManager, levelBeforeIn as Number,
                        levelAfterIn as Number) {
        Routine.initialize();
        gm = gmIn;
        levelBefore = levelBeforeIn;
        levelAfter = levelAfterIn;
    }

    // LevelDown is this animation with the background frames reordered, so
    // the two share everything but this and the sound.
    function background(n as Number) as Array<Number> {
        return Kaisa.Sprites.REWARD_BACKGROUND[n];
    }

    function sound() as String { return "levelUp"; }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                sbLevelUpBG = Kaisa.ScreenBuilder.buildSprite("LevelUpBackground", parent)
                    .setSprite(background(0));
                sbLevelUpIcon = Kaisa.ScreenBuilder.buildSprite("LevelUpIcon", parent)
                    .setSize(16, 16).setSprite(Kaisa.Sprites.REWARDS[0]).center()
                    .setActive(false).setTransparent(false);
                gm.audioMgr.playSound(sound());
                i = 0;
                cycle = 0;
                pc = 1;
                return 0.0;
            case 1:                                 // for (i = 0; i < 2; i++)
                if (i >= 2) { cycle = 0; pc = 3; return 0.0; }
                if (cycle >= 4) { cycle = 0; i += 1; pc = 1; return 0.0; }
                sbLevelUpBG.setSprite(background(cycle));
                pc = 2;
                return 0.125;
            case 2:
                cycle += 1; pc = 1; return 0.0;
            case 3:                                 // for (cycle = 0; cycle < 4; cycle++)
                if (cycle >= 4) { i = 0; cycle = 0; pc = 5; return 0.0; }
                sbLevelUpIcon.setActive(cycle % 2 == 0);
                sbLevelUpBG.setSprite(background(cycle));
                pc = 4;
                return 0.125;
            case 4:
                cycle += 1; pc = 3; return 0.0;
            case 5:
                sbLevelUpIcon.setActive(true);
                pc = 6;
                return 0.0;
            case 6:                                 // for (i = 0; i < 4; i++)
                if (i >= 4) { i = 0; pc = 8; return 0.0; }
                if (cycle >= 4) { cycle = 0; i += 1; pc = 6; return 0.0; }
                sbLevelUpBG.setSprite(background(cycle));
                pc = 7;
                return 0.125;
            case 7:
                cycle += 1; pc = 6; return 0.0;
            case 8:
                sbLevelUpBG.setActive(false);
                pc = 9;
                return 0.0;
            case 9:                                 // for (i = 0; i < 9; i++)
                if (i >= 9) { pc = 11; return 0.0; }
                sbLevelUpIcon.move(Kaisa.DIR_UP, 1);
                pc = 10;
                return 0.5 / 9;
            case 10:
                i += 1; pc = 9; return 0.0;
            case 11:
                Kaisa.ScreenBuilder.buildTextBox("Level", parent, Kaisa.Font.REGULAR)
                    .setText("LEVEL").setSize(32, 5).setPosition(0, 17)
                    .setAlignment(Kaisa.Text.ANCHOR_UPPER_CENTER);
                tbLevel = Kaisa.ScreenBuilder.buildTextBox("LevelNumber", parent, Kaisa.Font.REGULAR)
                    .setText(levelBefore.toString()).setSize(29, 5).setPosition(2, 24)
                    .setAlignment(Kaisa.Text.ANCHOR_UPPER_RIGHT);
                gm.audioMgr.playButtonA();
                pc = 12;
                return 1.0;
            case 12:
                tbLevel.setText(levelAfter.toString());
                gm.audioMgr.playButtonA();
                pc = 13;
                return 1.0;
            case 13:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:1101  LevelDown -- LevelUp with the background frames
// reordered (0, 3, 2, 1), so the ring turns the other way, and its own sound.
class LevelDown extends LevelUp {
    function initialize(gmIn as GameManager, levelBeforeIn as Number,
                        levelAfterIn as Number) {
        LevelUp.initialize(gmIn, levelBeforeIn, levelAfterIn);
    }

    function background(n as Number) as Array<Number> {
        var order = [0, 3, 2, 1];
        return Kaisa.Sprites.REWARD_BACKGROUND[order[n]];
    }

    function sound() as String { return "levelDown"; }
}

// port of Animations.cs:2319  RewardDistance -- LevelUp's screen with the
// distance icon and a DISTANCE label, and six background cycles instead of
// four. Punishment and reward differ only in the icon and the sound.
class RewardDistance extends Routine {
    var gm as GameManager;
    var isPunishment as Boolean;
    var distanceBefore as Number;
    var distanceAfter as Number;

    var sbRewardBg as SpriteBuilder?;
    var sbDistanceUp as SpriteBuilder?;
    var tbLevel as TextBoxBuilder?;
    var i as Number = 0;
    var cycle as Number = 0;

    function initialize(gmIn as GameManager, isPunishmentIn as Boolean,
                        distanceBeforeIn as Number, distanceAfterIn as Number) {
        Routine.initialize();
        gm = gmIn;
        isPunishment = isPunishmentIn;
        distanceBefore = distanceBeforeIn;
        distanceAfter = distanceAfterIn;
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                sbRewardBg = Kaisa.ScreenBuilder.buildSprite("DistanceBackground", parent)
                    .setSprite(Kaisa.Sprites.REWARD_BACKGROUND[0]);
                sbDistanceUp = Kaisa.ScreenBuilder.buildSprite("DistanceIcon", parent)
                    .setSize(16, 16)
                    .setSprite(isPunishment ? Kaisa.Sprites.REWARDS[2] : Kaisa.Sprites.REWARDS[1])
                    .center().setActive(false).setTransparent(false);
                gm.audioMgr.playSound(isPunishment ? "punishment" : "reward");
                i = 0;
                cycle = 0;
                pc = 1;
                return 0.0;
            case 1:                                 // for (i = 0; i < 2; i++)
                if (i >= 2) { cycle = 0; pc = 3; return 0.0; }
                if (cycle >= 4) { cycle = 0; i += 1; pc = 1; return 0.0; }
                sbRewardBg.setSprite(Kaisa.Sprites.REWARD_BACKGROUND[cycle]);
                pc = 2;
                return 0.125;
            case 2:
                cycle += 1; pc = 1; return 0.0;
            case 3:                                 // for (cycle = 0; cycle < 4; cycle++)
                if (cycle >= 4) { i = 0; cycle = 0; pc = 5; return 0.0; }
                sbDistanceUp.setActive(cycle % 2 == 0);
                sbRewardBg.setSprite(Kaisa.Sprites.REWARD_BACKGROUND[cycle]);
                pc = 4;
                return 0.125;
            case 4:
                cycle += 1; pc = 3; return 0.0;
            case 5:
                sbDistanceUp.setActive(true);
                pc = 6;
                return 0.0;
            case 6:                                 // for (i = 0; i < 6; i++)
                if (i >= 6) { i = 0; pc = 8; return 0.0; }
                if (cycle >= 4) { cycle = 0; i += 1; pc = 6; return 0.0; }
                sbRewardBg.setSprite(Kaisa.Sprites.REWARD_BACKGROUND[cycle]);
                pc = 7;
                return 0.125;
            case 7:
                cycle += 1; pc = 6; return 0.0;
            case 8:
                sbRewardBg.setActive(false);
                pc = 9;
                return 0.0;
            case 9:                                 // for (i = 0; i < 9; i++)
                if (i >= 9) { pc = 11; return 0.0; }
                sbDistanceUp.move(Kaisa.DIR_UP, 1);
                pc = 10;
                return 0.5 / 9;
            case 10:
                i += 1; pc = 9; return 0.0;
            case 11:
                Kaisa.ScreenBuilder.buildTextBox("Distance", parent, Kaisa.Font.SMALL)
                    .setText("DISTANCE").setSize(32, 5).setPosition(0, 17);
                tbLevel = Kaisa.ScreenBuilder.buildTextBox("DistanceNumber", parent, Kaisa.Font.REGULAR)
                    .setText(distanceBefore.toString()).setSize(29, 5).setPosition(2, 24)
                    .setAlignment(Kaisa.Text.ANCHOR_UPPER_RIGHT);
                gm.audioMgr.playButtonA();
                pc = 12;
                return 1.0;
            case 12:
                tbLevel.setText(distanceAfter.toString());
                gm.audioMgr.playButtonA();
                pc = 13;
                return 1.0;
            case 13:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:2368  RewardSpiritPower -- the same screen again, with
// the spirit icon and a SPIRITS label. SOURCE ODDITY, reproduced: its two
// elements are still named for the level-up screen it was copied from.
class RewardSpiritPower extends Routine {
    var gm as GameManager;
    var isPunishment as Boolean;
    var spiritsBefore as Number;
    var spiritsAfter as Number;

    var sbRewardBg as SpriteBuilder?;
    var sbSpiritPower as SpriteBuilder?;
    var tbLevel as TextBoxBuilder?;
    var i as Number = 0;
    var cycle as Number = 0;

    function initialize(gmIn as GameManager, isPunishmentIn as Boolean,
                        spiritsBeforeIn as Number, spiritsAfterIn as Number) {
        Routine.initialize();
        gm = gmIn;
        isPunishment = isPunishmentIn;
        spiritsBefore = spiritsBeforeIn;
        spiritsAfter = spiritsAfterIn;
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                sbRewardBg = Kaisa.ScreenBuilder.buildSprite("LevelUpBackground", parent)
                    .setSprite(Kaisa.Sprites.REWARD_BACKGROUND[0]);
                sbSpiritPower = Kaisa.ScreenBuilder.buildSprite("LevelUpIcon", parent)
                    .setSize(16, 16).setSprite(Kaisa.Sprites.REWARDS[3]).center()
                    .setActive(false).setTransparent(false);
                gm.audioMgr.playSound(isPunishment ? "punishment" : "reward");
                i = 0;
                cycle = 0;
                pc = 1;
                return 0.0;
            case 1:
                if (i >= 2) { cycle = 0; pc = 3; return 0.0; }
                if (cycle >= 4) { cycle = 0; i += 1; pc = 1; return 0.0; }
                sbRewardBg.setSprite(Kaisa.Sprites.REWARD_BACKGROUND[cycle]);
                pc = 2;
                return 0.125;
            case 2:
                cycle += 1; pc = 1; return 0.0;
            case 3:
                if (cycle >= 4) { i = 0; cycle = 0; pc = 5; return 0.0; }
                sbSpiritPower.setActive(cycle % 2 == 0);
                sbRewardBg.setSprite(Kaisa.Sprites.REWARD_BACKGROUND[cycle]);
                pc = 4;
                return 0.125;
            case 4:
                cycle += 1; pc = 3; return 0.0;
            case 5:
                sbSpiritPower.setActive(true);
                pc = 6;
                return 0.0;
            case 6:                                 // for (i = 0; i < 6; i++)
                if (i >= 6) { i = 0; pc = 8; return 0.0; }
                if (cycle >= 4) { cycle = 0; i += 1; pc = 6; return 0.0; }
                sbRewardBg.setSprite(Kaisa.Sprites.REWARD_BACKGROUND[cycle]);
                pc = 7;
                return 0.125;
            case 7:
                cycle += 1; pc = 6; return 0.0;
            case 8:
                sbRewardBg.setActive(false);
                pc = 9;
                return 0.0;
            case 9:
                if (i >= 9) { pc = 11; return 0.0; }
                sbSpiritPower.move(Kaisa.DIR_UP, 1);
                pc = 10;
                return 0.5 / 9;
            case 10:
                i += 1; pc = 9; return 0.0;
            case 11:
                Kaisa.ScreenBuilder.buildTextBox("SpiritPower", parent, Kaisa.Font.SMALL)
                    .setText("SPIRITS").setSize(32, 5).setPosition(1, 17);
                tbLevel = Kaisa.ScreenBuilder.buildTextBox("SpiritPowerNumber", parent, Kaisa.Font.REGULAR)
                    .setText(spiritsBefore.toString()).setSize(29, 5).setPosition(2, 24)
                    .setAlignment(Kaisa.Text.ANCHOR_UPPER_RIGHT);
                gm.audioMgr.playButtonA();
                pc = 12;
                return 1.0;
            case 12:
                tbLevel.setText(spiritsAfter.toString());
                gm.audioMgr.playButtonA();
                pc = 13;
                return 1.0;
            case 13:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:473  LevelUpDigimon -- the Digimon takes power, then
// the D-Tector does.
class LevelUpDigimon extends Routine {
    var gm as GameManager;
    var digimonIndex as Number;

    var sbDigimon as SpriteBuilder?;
    var sbPower as SpriteBuilder?;
    var i as Number = 0;

    function initialize(gmIn as GameManager, digimonIndexIn as Number) {
        Routine.initialize();
        gm = gmIn;
        digimonIndex = digimonIndexIn;
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                gm.audioMgr.playSound("unlockDigimon");
                sbDigimon = Kaisa.ScreenBuilder.buildSprite(gm.data.name(digimonIndex), parent)
                    .setSize(24, 24).center()
                    .setSprite(gm.digimonSprite(digimonIndex, gm.data.ACTION_BASE));
                sbPower = Kaisa.ScreenBuilder.buildSprite("Power", parent)
                    .setSprite(Kaisa.Sprites.GIVE_POWER).setTransparent(true).setActive(false);
                i = 0;
                pc = 1;
                return 0.0;
            case 1:                                 // for (i = 0; i < 2; i++)
                if (i >= 2) { i = 0; pc = 4; return 0.0; }
                pc = 2;
                return 0.40;
            case 2:
                sbPower.setActive(true);
                pc = 3;
                return 0.15;
            case 3:
                sbPower.setActive(false);
                i += 1; pc = 1; return 0.0;
            case 4:                                 // for (i = 0; i < 2; i++)
                if (i >= 2) { pc = 7; return 0.0; }
                pc = 5;
                return 0.20;
            case 5:
                sbPower.setActive(true);
                pc = 6;
                return 0.15;
            case 6:
                sbPower.setActive(false);
                i += 1; pc = 4; return 0.0;
            case 7:
                sbPower.setSprite(Kaisa.Sprites.GIVE_POWER_INVERTED);
                pc = 8;
                return 0.20;
            case 8:
                sbPower.setActive(true);
                pc = 9;
                return 0.15;
            case 9:
                sbPower.setActive(false);
                pc = 10;
                return 0.20;
            case 10:
                sbPower.setActive(true);
                pc = 11;
                return 0.20;
            case 11:
                sbPower.setSprite(Kaisa.Sprites.GIVE_MASSIVE_POWER_INVERTED);
                pc = 12;
                return 0.20;
            case 12:
                sbPower.setActive(false);
                pc = 13;
                return 0.20;
            case 13:
                sbPower.setActive(true);
                pc = 14;
                return 0.15;
            case 14:
                sbPower.setActive(false);
                pc = 15;
                return 0.20;
            case 15:
                sbPower.setActive(true);
                pc = 16;
                return 0.15;
            case 16:
                sbPower.setActive(false);
                // Give power to D-Tector.
                sbDigimon.setSize(32, 32).center().setSprite(Kaisa.Sprites.D_TECTOR);
                sbPower.setSprite(Kaisa.Sprites.GIVE_MASSIVE_POWER_INVERTED);
                sbPower.setActive(false);
                i = 0;
                pc = 17;
                return 0.30;
            case 17:                                // for (i = 0; i < 5; i++)
                if (i >= 5) { pc = 20; return 1.0; }
                sbPower.setActive(true);
                pc = 18;
                return 0.15;
            case 18:
                sbPower.setActive(false);
                pc = 19;
                return 0.15;
            case 19:
                i += 1; pc = 17; return 0.0;
            case 20:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:537  EraseDigimon -- the Digimon flickers out.
class EraseDigimon extends Routine {
    var gm as GameManager;
    var digimonIndex as Number;

    var sbDigimon as SpriteBuilder?;
    var sbGivePower as SpriteBuilder?;
    var i as Number = 0;

    function initialize(gmIn as GameManager, digimonIndexIn as Number) {
        Routine.initialize();
        gm = gmIn;
        digimonIndex = digimonIndexIn;
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                sbDigimon = Kaisa.ScreenBuilder.buildSprite("Digimon", parent)
                    .setSize(24, 24)
                    .setSprite(gm.digimonSprite(digimonIndex, gm.data.ACTION_BASE));
                sbDigimon.center();
                sbDigimon.setActive(false);
                // SOURCE ODDITY, reproduced: the flash element is named
                // "Digimon" too.
                sbGivePower = Kaisa.ScreenBuilder.buildSprite("Digimon", parent)
                    .setSprite(Kaisa.Sprites.GIVE_POWER);
                sbGivePower.setTransparent(true);
                sbGivePower.setActive(false);
                gm.audioMgr.playSound("loseDigimon");
                pc = 1;
                return 0.2;
            case 1:
                sbDigimon.setActive(true);
                pc = 2;
                return 1.0;
            case 2:
                sbGivePower.setActive(true);
                pc = 3;
                return 0.05;
            case 3:
                sbGivePower.setActive(false);
                pc = 4;
                return 0.9;
            case 4:
                sbGivePower.setActive(true);
                pc = 5;
                return 0.05;
            case 5:
                sbGivePower.setActive(false);
                sbDigimon.setActive(false);
                i = 0;
                pc = 6;
                return 0.0;
            case 6:                                 // for (i = 0; i < 5; i++)
                if (i >= 5) { pc = 9; return 0.0; }
                pc = 7;
                return 0.3;
            case 7:
                sbDigimon.setActive(true);
                pc = 8;
                return 0.1;
            case 8:
                sbDigimon.setActive(false);
                i += 1; pc = 6; return 0.0;
            case 9:
                sbGivePower.setActive(true);
                pc = 10;
                return 0.3;
            case 10:
                sbGivePower.setActive(false);
                pc = 11;
                return 0.4;
            case 11:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:575  LevelDownDigimon -- the Digimon blinks while the
// massive-power sprite alternates over it.
class LevelDownDigimon extends Routine {
    var gm as GameManager;
    var digimonIndex as Number;

    var sbDigimon as SpriteBuilder?;
    var sbPower as SpriteBuilder?;
    var i as Number = 0;

    function initialize(gmIn as GameManager, digimonIndexIn as Number) {
        Routine.initialize();
        gm = gmIn;
        digimonIndex = digimonIndexIn;
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                sbDigimon = Kaisa.ScreenBuilder.buildSprite(gm.data.name(digimonIndex), parent)
                    .setSize(24, 24).center()
                    .setSprite(gm.digimonSprite(digimonIndex, gm.data.ACTION_BASE));
                sbPower = Kaisa.ScreenBuilder.buildSprite("Power", parent)
                    .setTransparent(true).setActive(false);
                gm.audioMgr.playSound("levelDownDigimon");
                i = 0;
                pc = 1;
                return 0.0;
            case 1:                                 // for (i = 0; i < 2; i++)
                if (i >= 2) { i = 0; pc = 4; return 0.0; }
                pc = 2;
                return 0.20;
            case 2:
                sbDigimon.setActive(false);
                pc = 3;
                return 0.15;
            case 3:
                sbDigimon.setActive(true);
                i += 1; pc = 1; return 0.0;
            case 4:                                 // for (i = 0; i < 2; i++)
                if (i >= 2) { i = 0; pc = 7; return 0.0; }
                pc = 5;
                return 0.15;
            case 5:
                sbDigimon.setActive(false);
                pc = 6;
                return 0.15;
            case 6:
                sbDigimon.setActive(true);
                i += 1; pc = 4; return 0.0;
            case 7:                                 // for (i = 0; i < 3; i++)
                if (i >= 3) { pc = 11; return 0.40; }
                pc = 8;
                return 0.20;
            case 8:
                sbPower.setSprite(Kaisa.Sprites.GIVE_MASSIVE_POWER).setActive(true);
                pc = 9;
                return 0.20;
            case 9:
                sbPower.setSprite(Kaisa.Sprites.GIVE_MASSIVE_POWER_INVERTED).setActive(true);
                pc = 10;
                return 0.20;
            case 10:
                sbPower.setActive(false);
                i += 1; pc = 7; return 0.0;
            case 11:
                sbPower.setSprite(Kaisa.Sprites.GIVE_MASSIVE_POWER).setActive(true);
                pc = 12;
                return 0.20;
            case 12:
                sbPower.setSprite(Kaisa.Sprites.GIVE_MASSIVE_POWER_INVERTED).setActive(true);
                pc = 13;
                return 0.20;
            case 13:
                sbPower.setActive(false);
                pc = 14;
                return 0.60;
            case 14:
                sbPower.setSprite(Kaisa.Sprites.GIVE_MASSIVE_POWER).setActive(true);
                pc = 15;
                return 0.20;
            case 15:
                sbPower.setSprite(Kaisa.Sprites.GIVE_MASSIVE_POWER_INVERTED).setActive(true);
                pc = 16;
                return 0.20;
            case 16:
                sbPower.setActive(false);
                i = 0;
                pc = 17;
                return 0.30;
            case 17:                                // for (i = 0; i < 2; i++)
                if (i >= 2) { pc = 20; return 0.50; }
                pc = 18;
                return 0.15;
            case 18:
                sbDigimon.setActive(false);
                pc = 19;
                return 0.15;
            case 19:
                sbDigimon.setActive(true);
                i += 1; pc = 17; return 0.0;
            case 20:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:2418  RewardCode -- the Digimon drifts down in a
// bubble, the bubble flashes, and its five-character code is displayed before
// the D-Tector takes the power.
class RewardCode extends Routine {
    var gm as GameManager;
    var digimonIndex as Number;
    var code as String;

    var sbDigimon as SpriteBuilder?;
    var sbBubble as SpriteBuilder?;
    var sbPower as SpriteBuilder?;
    var tbCode as TextBoxBuilder?;
    var i as Number = 0;

    function initialize(gmIn as GameManager, digimonIndexIn as Number,
                        codeIn as String) {
        Routine.initialize();
        gm = gmIn;
        digimonIndex = digimonIndexIn;
        code = codeIn;
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                sbDigimon = Kaisa.ScreenBuilder.buildSprite("Digimon", parent)
                    .setSize(24, 24).center().placeOutside(Kaisa.DIR_UP)
                    .move(Kaisa.DIR_UP, 4)
                    .setSprite(gm.digimonSprite(digimonIndex, gm.data.ACTION_BASE));
                sbBubble = Kaisa.ScreenBuilder.buildSprite("Bubble", parent)
                    .placeOutside(Kaisa.DIR_UP).setSprite(Kaisa.Sprites.BUBBLE);
                gm.audioMgr.playSound("unlockCode");
                i = 0;
                pc = 1;
                return 0.0;
            case 1:                                 // for (i = 0; i < 64; i++)
                if (i >= 64) { pc = 3; return 0.0; }
                sbBubble.setActive(i % 2 == 1);
                if (i % 2 == 0) {
                    sbDigimon.move(Kaisa.DIR_DOWN, 1);
                    sbBubble.move(Kaisa.DIR_DOWN, 1);
                }
                pc = 2;
                return 4.0 / 64;
            case 2:
                i += 1; pc = 1; return 0.0;
            case 3:
                sbBubble.setActive(false).setTransparent(true);
                pc = 4;
                return 0.15;
            case 4:
                sbBubble.setActive(true);
                i = 0;
                pc = 5;
                return 1.0;
            case 5:                                 // for (i = 0; i < 3; i++)
                if (i >= 3) { i = 0; pc = 8; return 0.0; }
                sbBubble.setActive(false);
                pc = 6;
                return 0.25;
            case 6:
                sbBubble.setActive(true);
                pc = 7;
                return 0.4;
            case 7:
                i += 1; pc = 5; return 0.0;
            case 8:                                 // for (i = 0; i < 3; i++)
                if (i >= 3) { pc = 11; return 0.0; }
                sbBubble.setActive(false);
                pc = 9;
                return 0.25;
            case 9:
                sbBubble.setActive(true);
                pc = 10;
                return 0.2;
            case 10:
                i += 1; pc = 8; return 0.0;
            case 11:
                sbBubble.setActive(false);
                pc = 12;
                return 1.0;
            case 12:
                sbDigimon.dispose();
                gm.audioMgr.playButtonA();
                sbBubble.setTransparent(false)
                    .setSprite(Kaisa.Sprites.DATABASE_PAGES[2]).setActive(true);
                tbCode = Kaisa.ScreenBuilder.buildTextBox("Code", parent, Kaisa.Font.BIG)
                    .setText(code).setSize(30, 8).setPosition(2, 23)
                    .setAlignment(Kaisa.Text.ANCHOR_UPPER_RIGHT);
                pc = 13;
                return 3.0;
            case 13:
                tbCode.dispose();
                sbBubble.setSprite(Kaisa.Sprites.D_TECTOR);
                sbPower = Kaisa.ScreenBuilder.buildSprite("Power", parent)
                    .setSprite(Kaisa.Sprites.GIVE_MASSIVE_POWER_INVERTED).setTransparent(true);
                sbPower.setActive(false);
                i = 0;
                pc = 14;
                return 0.30;
            case 14:                                // for (i = 0; i < 5; i++)
                if (i >= 5) { return Routine.DONE; }
                sbPower.setActive(true);
                pc = 15;
                return 0.15;
            case 15:
                sbPower.setActive(false);
                pc = 16;
                return 0.15;
            case 16:
                i += 1; pc = 14; return 0.0;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:773  DisplayNewArea -- the map of the area the player
// has just reached, then its distance.
class DisplayNewArea extends Routine {
    var gm as GameManager;
    var world as Number;
    var area as Number;
    var distance as Number;

    function initialize(gmIn as GameManager, worldIn as Number, areaIn as Number,
                        distanceIn as Number) {
        Routine.initialize();
        gm = gmIn;
        world = worldIn;
        area = areaIn;
        distance = distanceIn;
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                var cbMap = gm.buildMapScreen(world, parent);
                var row = gm.data.worldArea(world, area);
                var map = row[1];

                if (map == 0) { cbMap.setPosition(0, 0); }
                else if (map == 1) { cbMap.setPosition(0, -32); }
                else if (map == 2) { cbMap.setPosition(-32, -32); }
                else if (map == 3) { cbMap.setPosition(-32, 0); }

                // Spawn the area name and marker.
                var areaPosY = (map == 0 || map == 3) ? 1 : 26;
                var n = area + 1;
                Kaisa.ScreenBuilder.buildTextBox("AreaName", parent, Kaisa.Font.SMALL)
                    .setText("area" + ((n < 10) ? "0" : "") + n)
                    .setPosition(2, areaPosY);
                Kaisa.ScreenBuilder.buildRectangle("OptionMarker", parent)
                    .setSize(2, 2).setFlickPeriodMs(250, true)
                    .setPosition(row[3], row[4]);

                // Draw the completed area markers. SOURCE ODDITY, reproduced:
                // the completion check asks world 0 whatever world this is.
                var areasInCurrentMap = gm.worldMgr.areasInMap(world, map);
                for (var k = 0; k < areasInCurrentMap.size(); k += 1) {
                    var i = areasInCurrentMap[k];
                    if (gm.worldMgr.getAreaCompleted(0, i)) {
                        var marker = gm.data.worldArea(world, i);
                        Kaisa.ScreenBuilder.buildRectangle("Area" + i + "Marker", parent)
                            .setSize(2, 2).setPosition(marker[3], marker[4]);
                    }
                }
                pc = 1;
                return 2.25;
            case 1:
                // Display distance.
                Kaisa.ScreenBuilder.buildSprite("DistanceBackground", parent)
                    .setSprite(Kaisa.Sprites.MAP_DISTANCE_SCREEN);
                Kaisa.ScreenBuilder.buildTextBox("Distance", parent, Kaisa.Font.REGULAR)
                    .setText(distance.toString()).setSize(25, 5).setPosition(6, 25)
                    .setAlignment(Kaisa.Text.ANCHOR_UPPER_RIGHT);
                pc = 2;
                return 2.5;
            case 2:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:2482  DataStorm -- the storm sweeps in, the character
// notices it and runs, and either it carries them to a new area or they get
// away. How long they spend trying to escape is a roll, which is why the
// verifier pins the roll on both sides.
class DataStorm extends Routine {
    var gm as GameManager;
    var character as Array;
    var moveToNewArea as Boolean;

    var sbCharacter as SpriteBuilder?;
    var sbDigistorm as Array<SpriteBuilder?> = [null, null];
    var sbExclamation as SpriteBuilder?;
    var timeTryingToEscape as Number = 0;
    var stormVibeFrames as Number = 0;
    var i as Number = 0;
    var j as Number = 0;

    function initialize(gmIn as GameManager, characterIn as Array,
                        moveToNewAreaIn as Boolean) {
        Routine.initialize();
        gm = gmIn;
        character = characterIn;
        moveToNewArea = moveToNewAreaIn;
    }

    // The storm is two 40-wide sprites chasing each other, and both take the
    // same frame at the same time.
    function stormFrame(n as Number) as Void {
        var f = Kaisa.Sprites.DIGISTORM[Kaisa.MathExt.floorToInt(n / 2.0) % 2];
        sbDigistorm[0].setSprite(f);
        sbDigistorm[1].setSprite(f);
        stormVibeFrames += 1;
        if (stormVibeFrames % 12 == 0) {
            gm.audioMgr.vibrateStormPulse(stormVibeFrames / 12);
        }
    }

    function stormMove(direction as Number) as Void {
        sbDigistorm[0].move(direction, 1);
        sbDigistorm[1].move(direction, 1);
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                sbCharacter = Kaisa.ScreenBuilder.buildSprite("Character", parent)
                    .setSprite(character[2]).setActive(false);
                sbDigistorm[0] = Kaisa.ScreenBuilder.buildSprite("Digistorm", parent)
                    .setSize(40, 32).setSprite(Kaisa.Sprites.DIGISTORM[0])
                    .placeOutside(Kaisa.DIR_RIGHT);
                sbDigistorm[1] = Kaisa.ScreenBuilder.buildSprite("Digistorm", parent)
                    .setSize(40, 32).setSprite(Kaisa.Sprites.DIGISTORM[0])
                    .placeOutside(Kaisa.DIR_RIGHT).move(Kaisa.DIR_RIGHT, 40);
                gm.audioMgr.playSound("digistorm");
                i = 0;
                j = 0;
                pc = 1;
                return 0.0;
            case 1:                                 // for (i = 0; i < 2; i++)
                if (i >= 2) { pc = 3; return 0.0; }
                if (j >= 40) { j = 0; i += 1; pc = 1; return 0.0; }
                stormMove(Kaisa.DIR_LEFT);
                stormFrame(j);
                pc = 2;
                return 4.0 / 40;
            case 2:
                j += 1; pc = 1; return 0.0;
            case 3:
                sbDigistorm[0].placeOutside(Kaisa.DIR_RIGHT);
                sbDigistorm[1].placeOutside(Kaisa.DIR_RIGHT).move(Kaisa.DIR_RIGHT, 40);
                sbExclamation = Kaisa.ScreenBuilder.buildSprite("Exclamation", parent)
                    .setSize(3, 9).setPosition(26, 1).setSprite(Kaisa.Sprites.BATTLE_DISOBEY);
                sbCharacter.setActive(true);
                pc = 4;
                return 0.5;
            case 4:
                sbExclamation.dispose();
                sbCharacter.setSprite(character[0]);
                i = 0;
                pc = 5;
                return 0.0;
            case 5:                                 // for (i = 0; i < 4; i++)
                if (i >= 4) { i = 0; pc = 7; return 0.0; }
                sbCharacter.setSprite(character[4 + (i % 2)]);
                sbCharacter.move(Kaisa.DIR_LEFT, 1);
                pc = 6;
                return 0.1;
            case 6:
                i += 1; pc = 5; return 0.0;
            case 7:                                 // for (i = 0; i < 20; i++)
                if (i >= 20) {
                    timeTryingToEscape = Kaisa.Rand.rangeInt(0, 40);   // default was 20
                    i = 0;
                    pc = moveToNewArea ? 9 : 15;
                    return 0.0;
                }
                sbCharacter.setSprite(character[4 + (i % 2)]);
                stormMove(Kaisa.DIR_LEFT);
                stormFrame(i);
                pc = 8;
                return 4.0 / 40;
            case 8:
                i += 1; pc = 7; return 0.0;
            case 9:                                 // carried off: the escape attempt
                if (i >= timeTryingToEscape) { i = 0; pc = 11; return 0.0; }
                sbCharacter.setSprite(character[4 + (i % 2)]);
                stormFrame(i);
                pc = 10;
                return 4.0 / 40;
            case 10:
                i += 1; pc = 9; return 0.0;
            case 11:                                // for (i = 0; i < 20; i++)
                if (i >= 20) { i = 0; pc = 13; return 0.0; }
                sbCharacter.setSprite(character[4 + (i % 2)]);
                stormMove(Kaisa.DIR_LEFT);
                stormFrame(i);
                pc = 12;
                return 4.0 / 40;
            case 12:
                i += 1; pc = 11; return 0.0;
            case 13:                                // for (i = 0; i < 40; i++)
                if (i >= 40) { pc = 20; return 0.0; }
                stormMove(Kaisa.DIR_LEFT);
                stormFrame(i);
                pc = 14;
                return 4.0 / 40;
            case 14:
                i += 1; pc = 13; return 0.0;
            case 15:                                // got away: the escape attempt
                if (i >= timeTryingToEscape) { i = 0; pc = 17; return 0.0; }
                sbCharacter.setSprite(character[4 + (i % 2)]);
                stormFrame(i);
                pc = 16;
                return 4.0 / 40;
            case 16:
                i += 1; pc = 15; return 0.0;
            case 17:                                // for (i = 0; i < 30; i++)
                if (i >= 30) { pc = 19; return 0.75; }
                sbCharacter.setSprite(character[4 + (i % 2)]);
                sbCharacter.move(Kaisa.DIR_LEFT, 1);
                stormMove(Kaisa.DIR_RIGHT);
                stormFrame(i);
                pc = 18;
                return 4.0 / 40;
            case 18:
                i += 1; pc = 17; return 0.0;
            case 19:
                gm.audioMgr.stopSound();
                gm.logicMgr.finishStorm();
                return Routine.DONE;
            case 20:
                gm.audioMgr.stopSound();
                gm.logicMgr.finishStorm();
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:54  StartGameAnimation
//
// The opening: the character runs on, rides the Trailmon in, is ambushed by
// the enemy Digimon, takes the spirit and destroys it, and the D-Tector takes
// the power. Fifty-three seconds, and the longest coroutine in the game.
class StartGameAnimation extends Routine {
    var gm as GameManager;
    var character as Number;
    var spiritIndex as Number;
    var spiritEnergy as Number;
    var enemyIndex as Number;
    var enemyEnergy as Number;

    var sCharacter as Array = [];
    var sSpirit as Array = [];
    var sEnemyDigimon as Array = [];
    var sSpiritEnergy as Array<Number>?;
    var sEnemyEnergy as Array<Number>?;

    var sbCharacter as SpriteBuilder?;
    var sbClouds as SpriteBuilder?;
    var sbTrailmon as SpriteBuilder?;
    var sbWindow1 as RectangleBuilder?;
    var sbWindow2 as RectangleBuilder?;
    var sbWindow3 as RectangleBuilder?;
    var sbDisobey as SpriteBuilder?;
    var sbAttack as SpriteBuilder?;
    var sbEnemy as SpriteBuilder?;
    var cbSpirit as ContainerBuilder?;
    var sbSpiritEmerging as SpriteBuilder?;
    var sbSpirit as SpriteBuilder?;
    var sbCurtain as SpriteBuilder?;
    var sbPower as SpriteBuilder?;
    var i as Number = 0;

    function initialize(gmIn as GameManager, characterIn as Number,
                        spiritIndexIn as Number, spiritEnergyIn as Number,
                        enemyIndexIn as Number, enemyEnergyIn as Number) {
        Routine.initialize();
        gm = gmIn;
        character = characterIn;
        spiritIndex = spiritIndexIn;
        spiritEnergy = spiritEnergyIn;
        enemyIndex = enemyIndexIn;
        enemyEnergy = enemyEnergyIn;
    }

    // The run cycle: two frames, each held for two steps.
    function runFrame(n as Number) as Void {
        sbCharacter.setSprite((Kaisa.MathExt.floorToInt(n / 2.0) % 2 == 0)
                              ? sCharacter[4] : sCharacter[5]);
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                sCharacter = gm.characterSprites(character);
                sSpirit = gm.getAllDigimonSprites(spiritIndex);
                sEnemyDigimon = gm.getAllDigimonSprites(enemyIndex);
                sSpiritEnergy = gm.data.energySpriteRef(spiritEnergy);
                sEnemyEnergy = gm.data.energySpriteRef(enemyEnergy);

                sbCharacter = Kaisa.ScreenBuilder.buildSprite("Character", parent)
                    .setSprite(sCharacter[0]).placeOutside(Kaisa.DIR_RIGHT);
                i = 0;
                pc = 1;
                return 0.0;
            case 1:                                 // for (i = 0; i < 32; i++)
                if (i >= 32) { pc = 3; return 0.0; }
                runFrame(i);
                sbCharacter.move(Kaisa.DIR_LEFT, 1);
                pc = 2;
                return 2.0 / 32;
            case 2:
                i += 1; pc = 1; return 0.0;
            case 3:
                pc = 4;
                rt.call(new CharHappy(gm));
                return 0.0;
            case 4:
                sbCharacter.placeOutside(Kaisa.DIR_RIGHT);
                gm.audioMgr.playSound("gameStart");
                // SOURCE ODDITY, reproduced: the clouds and the Trailmon are
                // both named "Character".
                sbClouds = Kaisa.ScreenBuilder.buildSprite("Character", parent)
                    .setSize(76, 32).setSprite(Kaisa.Sprites.GAME_START_CLOUDS);
                sbTrailmon = Kaisa.ScreenBuilder.buildSprite("Character", parent)
                    .setSize(118, 15).setSprite(Kaisa.Sprites.GAME_START_TRAILMON)
                    .setY(9).placeOutside(Kaisa.DIR_RIGHT);
                i = 0;
                pc = 5;
                return 0.0;
            case 5:                                 // for (i = 0; i < 75; i++)
                if (i >= 75) { i = 0; pc = 7; return 0.0; }
                if (i % 2 == 0) { sbClouds.move(Kaisa.DIR_LEFT, 1); }
                sbTrailmon.move(Kaisa.DIR_LEFT, 1);
                pc = 6;
                return 4.2 / 75;
            case 6:
                i += 1; pc = 5; return 0.0;
            case 7:                                 // for (i = 0; i < 32; i++)
                if (i >= 32) { i = 0; pc = 9; return 0.0; }
                if (i < 12 && i % 2 == 0) { sbClouds.move(Kaisa.DIR_LEFT, 1); }
                sbTrailmon.move(Kaisa.DIR_LEFT, 1);
                pc = 8;
                return 3.4 / 32;
            case 8:
                i += 1; pc = 7; return 0.0;
            case 9:                                 // for (i = 0; i < 11; i++)
                if (i >= 11) { i = 0; pc = 11; return 0.0; }
                sbTrailmon.move(Kaisa.DIR_LEFT, 1);
                pc = 10;
                return 2.6 / 11;
            case 10:
                i += 1; pc = 9; return 0.0;
            case 11:
                // SOURCE ODDITY, reproduced: all three windows are named
                // "Window1".
                sbWindow1 = Kaisa.ScreenBuilder.buildRectangle("Window1", parent)
                    .setSize(0, 5).setPosition(7, 14);
                sbWindow2 = Kaisa.ScreenBuilder.buildRectangle("Window1", parent)
                    .setSize(0, 5).setPosition(17, 14);
                sbWindow3 = Kaisa.ScreenBuilder.buildRectangle("Window1", parent)
                    .setSize(0, 5).setPosition(27, 14);
                i = 0;
                pc = 12;
                return 0.0;
            case 12:                                // for (i = 0; i < 2; i++)
                if (i >= 2) { pc = 14; return 0.0; }
                sbWindow1.setSize(i + 1, 5).move(Kaisa.DIR_LEFT, 1);
                sbWindow2.setSize(i + 1, 5).move(Kaisa.DIR_LEFT, 1);
                sbWindow3.setSize(i + 1, 5).move(Kaisa.DIR_LEFT, 1);
                pc = 13;
                return 0.8 / 2;
            case 13:
                i += 1; pc = 12; return 0.0;
            case 14:
                sbClouds.dispose();
                sbTrailmon.dispose();
                sbWindow1.dispose();
                sbWindow2.dispose();
                sbWindow3.dispose();
                i = 0;
                pc = 15;
                return 0.5;
            case 15:                                // for (i = 0; i < 32; i++)
                if (i >= 32) { pc = 17; return 0.0; }
                runFrame(i);
                sbCharacter.move(Kaisa.DIR_LEFT, 1);
                pc = 16;
                return 2.0 / 32;
            case 16:
                i += 1; pc = 15; return 0.0;
            case 17:
                sbCharacter.setSprite(sCharacter[0]);
                sbDisobey = Kaisa.ScreenBuilder.buildSprite("Disobey", parent)
                    .setSize(3, 9).setPosition(1, 1).setSprite(Kaisa.Sprites.BATTLE_DISOBEY);
                pc = 18;
                return 0.5;
            case 18:
                sbDisobey.dispose();
                sbCharacter.setActive(false);
                pc = 19;
                return 0.4;
            case 19:
                sbAttack = Kaisa.ScreenBuilder.buildSprite("Attack", parent)
                    .setSize(24, 24).setSprite(sEnemyEnergy).center()
                    .move(Kaisa.DIR_LEFT, 3).flipHorizontal(true).setActive(false);
                sbEnemy = Kaisa.ScreenBuilder.buildSprite(gm.data.name(enemyIndex), parent)
                    .setSize(24, 24).setSprite(sEnemyDigimon[0]).flipHorizontal(true).center();
                pc = 20;
                return 0.15;
            case 20:
                sbEnemy.setActive(false);
                pc = 21;
                return 0.4;
            case 21:
                sbEnemy.setActive(true);
                pc = 22;
                return 0.15;
            case 22:
                sbEnemy.setActive(false);
                pc = 23;
                return 0.4;
            case 23:
                sbEnemy.setSprite(sEnemyDigimon[1]).move(Kaisa.DIR_LEFT, 3).setActive(true);
                sbAttack.setActive(true);
                i = 0;
                pc = 24;
                return 0.0;
            case 24:                                // for (i = 0; i < 38; i++)
                if (i >= 38) { i = 0; pc = 26; return 0.0; }
                pc = 25;
                return 1.7 / 38;
            case 25:
                sbAttack.move(Kaisa.DIR_RIGHT, 1);
                i += 1; pc = 24; return 0.0;
            case 26:
                sbEnemy.setActive(false);
                sbAttack.placeOutside(Kaisa.DIR_LEFT);
                i = 0;
                pc = 27;
                return 0.0;
            case 27:                                // for (i = 0; i < 32; i++)
                if (i >= 32) { i = 0; pc = 29; return 0.0; }
                pc = 28;
                return 1.5 / 32;
            case 28:
                sbAttack.move(Kaisa.DIR_RIGHT, 1);
                i += 1; pc = 27; return 0.0;
            case 29:
                sbAttack.placeOutside(Kaisa.DIR_LEFT);
                cbSpirit = Kaisa.ScreenBuilder.buildContainer("Spirit", parent, true)
                    .setSize(24, 24).setPosition(8, 4).setMaskActive(true);
                // SOURCE ODDITY, reproduced: the emerging spirit is named
                // after the ENEMY.
                sbSpiritEmerging = Kaisa.ScreenBuilder.buildSprite(gm.data.name(enemyIndex), cbSpirit)
                    .setSize(24, 24).setPosition(0, 21).setSprite(sSpirit[3]);
                Kaisa.ScreenBuilder.buildSprite("Platform", cbSpirit)
                    .setSize(22, 3).setPosition(1, 21)
                    .setSprite(Kaisa.Sprites.GAME_START_SPIRIT_PLATFORM);
                i = 0;
                pc = 30;
                return 0.0;
            case 30:                                // for (i = 0; i < 21; i++)
                if (i >= 21) { i = 0; pc = 32; return 0.0; }
                sbSpiritEmerging.move(Kaisa.DIR_UP, 1);
                pc = 31;
                return 1.0 / 21;
            case 31:
                i += 1; pc = 30; return 0.0;
            case 32:                                // for (i = 0; i < 8; i++)
                if (i >= 8) { pc = 34; return 0.0; }
                pc = 33;
                return 0.4 / 8;
            case 33:
                sbAttack.move(Kaisa.DIR_RIGHT, 1);
                i += 1; pc = 32; return 0.0;
            case 34:
                sbAttack.dispose();
                sbAttack = Kaisa.ScreenBuilder.buildSprite("Collision", parent)
                    .setSprite(Kaisa.Sprites.BATTLE_ATTACK_COLLISION_SMALL)
                    .setSize(7, 15).setPosition(0, 8);
                pc = 35;
                return 0.4;
            case 35:
                sbAttack.dispose();
                cbSpirit.setPosition(4, 4);
                i = 0;
                pc = 36;
                return 0.15;
            case 36:                                // for (i = 0; i < 24; i++)
                if (i >= 24) { i = 0; pc = 38; return 0.0; }
                pc = 37;
                return 1.5 / 24;
            case 37:
                cbSpirit.move(Kaisa.DIR_UP, 1);
                i += 1; pc = 36; return 0.0;
            case 38:
                cbSpirit.dispose();
                sbSpirit = Kaisa.ScreenBuilder.buildSprite("Spirit", parent)
                    .setSize(24, 24).setSprite(sSpirit[3]).center()
                    .placeOutside(Kaisa.DIR_LEFT).setTransparent(true);
                sbCharacter.center().placeOutside(Kaisa.DIR_RIGHT)
                    .setTransparent(true).setActive(true);
                i = 0;
                pc = 39;
                return 0.0;
            case 39:                                // for (i = 0; i < 30; i++)
                if (i >= 30) { pc = 41; return 0.0; }
                sbSpirit.move(Kaisa.DIR_RIGHT, 1);
                sbCharacter.move(Kaisa.DIR_LEFT, 1);
                pc = 40;
                return 2.8 / 30;
            case 40:
                i += 1; pc = 39; return 0.0;
            case 41:
                sbSpirit.setTransparent(false);
                pc = 42;
                return 0.25;
            case 42:
                sbSpirit.setActive(false);
                pc = 43;
                return 0.25;
            case 43:
                sbSpirit.setActive(true);
                pc = 44;
                return 0.25;
            case 44:
                sbSpirit.setActive(false);
                pc = 45;
                return 0.25;
            case 45:
                sbSpirit.dispose();
                sbCharacter.setSize(24, 24).center().setSprite(sSpirit[0]);
                pc = 46;
                return 0.5;
            case 46:
                sbCharacter.move(Kaisa.DIR_RIGHT, 3).setSprite(sSpirit[1]);
                pc = 47;
                return 0.3;
            case 47:
                sbCharacter.move(Kaisa.DIR_LEFT, 3).setSprite(sSpirit[0]);
                pc = 48;
                return 0.3;
            case 48:
                sbCharacter.move(Kaisa.DIR_RIGHT, 3);
                pc = 49;
                return 0.15;
            case 49:
                sbCharacter.move(Kaisa.DIR_RIGHT, 3).setSprite(sSpirit[1]);
                sbAttack = Kaisa.ScreenBuilder.buildSprite("Attack", parent)
                    .setSize(24, 24).setSprite(sSpiritEnergy).setPosition(10, 4);
                sbCharacter.setTransparent(false);
                sbCharacter.setAsLastSibling();
                i = 0;
                pc = 50;
                return 0.0;
            case 50:                                // for (i = 0; i < 38; i++)
                if (i >= 38) { i = 0; pc = 52; return 0.0; }
                pc = 51;
                return 1.5 / 38;
            case 51:
                sbAttack.move(Kaisa.DIR_LEFT, 1);
                i += 1; pc = 50; return 0.0;
            case 52:
                sbCharacter.setActive(false);
                sbAttack.placeOutside(Kaisa.DIR_RIGHT);
                i = 0;
                pc = 53;
                return 0.0;
            case 53:                                // for (i = 0; i < 32; i++)
                if (i >= 32) { i = 0; pc = 55; return 0.0; }
                pc = 54;
                return 1.4 / 32;
            case 54:
                sbAttack.move(Kaisa.DIR_LEFT, 1);
                i += 1; pc = 53; return 0.0;
            case 55:
                sbAttack.placeOutside(Kaisa.DIR_RIGHT);
                sbEnemy.setActive(true).center().setSprite(sEnemyDigimon[0]);
                i = 0;
                pc = 56;
                return 0.0;
            case 56:                                // for (i = 0; i < 4; i++)
                if (i >= 4) { i = 0; pc = 58; return 0.0; }
                pc = 57;
                return 0.4 / 4;
            case 57:
                sbAttack.move(Kaisa.DIR_LEFT, 1);
                i += 1; pc = 56; return 0.0;
            case 58:
                sbAttack.dispose();
                sbEnemy.flipHorizontal(false);
                i = 0;
                pc = 59;
                return 0.0;
            case 59:                                // for (i = 0; i < 2; i++)
                if (i >= 2) { pc = 62; return 0.0; }
                sbEnemy.setSprite(Kaisa.Sprites.BATTLE_EXPLOSION[0]);
                pc = 60;
                return 0.5;
            case 60:
                sbEnemy.setSprite(Kaisa.Sprites.BATTLE_EXPLOSION[1]);
                pc = 61;
                return 0.5;
            case 61:
                i += 1; pc = 59; return 0.0;
            case 62:
                sbEnemy.setActive(false);
                sbCharacter.setSize(32, 32).setPosition(0, 0)
                    .setSprite(sCharacter[0]).setActive(true);
                pc = 63;
                return 0.3;
            case 63:
                sbSpirit = Kaisa.ScreenBuilder.buildSprite("Spirit", parent)
                    .setSize(24, 24).center().setSprite(sSpirit[0]);
                pc = 64;
                return 0.3;
            case 64:
                sbSpirit.setActive(false);
                pc = 65;
                return 0.3;
            case 65:
                sbSpirit.setActive(true);
                pc = 66;
                return 0.3;
            case 66:
                sbSpirit.setActive(false);
                pc = 67;
                return 0.3;
            case 67:
                sbEnemy.flipHorizontal(true).setSprite(sEnemyDigimon[0])
                    .placeOutside(Kaisa.DIR_LEFT).setActive(true);
                sbCharacter.setSprite(sCharacter[9]);
                i = 0;
                pc = 68;
                return 0.15;
            case 68:                                // for (i = 0; i < 26; i++)
                if (i >= 26) { pc = 70; return 0.0; }
                sbEnemy.move(Kaisa.DIR_RIGHT, 1);
                sbCharacter.move(Kaisa.DIR_RIGHT, 1);
                pc = 69;
                return 3.3 / 32;
            case 69:
                i += 1; pc = 68; return 0.0;
            case 70:
                sbEnemy.setActive(false);
                pc = 71;
                return 0.6;
            case 71:
                sbCharacter.setActive(false);
                sbEnemy.flipHorizontal(false).center().setActive(true);
                pc = 72;
                return 0.45;
            case 72:
                sbCurtain = Kaisa.ScreenBuilder.buildSprite("Curtain", parent)
                    .setSprite(Kaisa.Sprites.CURTAIN).placeOutside(Kaisa.DIR_DOWN)
                    .setTransparent(true);
                i = 0;
                pc = 73;
                return 0.0;
            case 73:                                // for (i = 0; i < 64; i++)
                if (i >= 64) { i = 0; pc = 75; return 0.0; }
                if (i > 31) { sbEnemy.move(Kaisa.DIR_UP, 1); }
                sbCurtain.move(Kaisa.DIR_UP, 1);
                pc = 74;
                return 3.4 / 64;
            case 74:
                i += 1; pc = 73; return 0.0;
            case 75:
                Kaisa.ScreenBuilder.buildSprite("DTector", parent)
                    .setSprite(Kaisa.Sprites.D_TECTOR);
                sbPower = Kaisa.ScreenBuilder.buildSprite("Power", parent)
                    .setSprite(Kaisa.Sprites.GIVE_MASSIVE_POWER_INVERTED)
                    .setTransparent(true);
                i = 0;
                pc = 76;
                return 0.0;
            case 76:                                // for (i = 0; i < 5; i++)
                if (i >= 5) { pc = 79; return 0.0; }
                sbPower.setActive(true);
                pc = 77;
                return 0.15;
            case 77:
                sbPower.setActive(false);
                pc = 78;
                return 0.15;
            case 78:
                i += 1; pc = 76; return 0.0;
            case 79:
                pc = 80;
                rt.call(new CharHappy(gm));
                return 0.0;
            case 80:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:860  EncounterEnemy -- the enemy fades in out of the
// give-power flashes and strikes a pose. `finalDelay` is how long the last
// frame is held, which the Jackpot Box shortens.
class EncounterEnemy extends Routine {
    var gm as GameManager;
    var digimonIndex as Number;
    var finalDelay as Float;
    // The Jackpot Box is encountered like a Digimon but is not one -- it has
    // art on the Digimon sheet and no row in the database -- so the two
    // sprites it draws can be given directly. Null means "look them up from
    // the index", which is what every other caller does.
    var spriteBase as Array<Number>?;
    var spriteAttack as Array<Number>?;

    var sbDigimon as SpriteBuilder?;
    var sbGivePower as SpriteBuilder?;
    var i as Number = 0;

    function initialize(gmIn as GameManager, digimonIndexIn as Number,
                        finalDelayIn as Float, spriteBaseIn as Array<Number>?,
                        spriteAttackIn as Array<Number>?) {
        Routine.initialize();
        gm = gmIn;
        digimonIndex = digimonIndexIn;
        finalDelay = finalDelayIn;
        spriteBase = spriteBaseIn;
        spriteAttack = spriteAttackIn;
    }

    function base() as Array<Number>? {
        return (spriteBase != null)
            ? spriteBase : gm.digimonSprite(digimonIndex, gm.data.ACTION_BASE);
    }

    function attack() as Array<Number>? {
        return (spriteAttack != null)
            ? spriteAttack : gm.digimonSprite(digimonIndex, gm.data.ACTION_AT);
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                sbDigimon = Kaisa.ScreenBuilder.buildSprite("Enemy", parent)
                    .setSize(24, 24).center().setSprite(base());
                sbDigimon.flipHorizontal(true);
                sbDigimon.setActive(false);
                sbGivePower = Kaisa.ScreenBuilder.buildSprite("Power", parent)
                    .setSprite(Kaisa.Sprites.GIVE_POWER).setTransparent(true);
                sbGivePower.setActive(false);
                i = 0;
                pc = 1;
                return 0.0;
            case 1:                                 // for (i = 0; i < 3; i++)
                if (i >= 3) { i = 0; pc = 4; return 0.5; }
                pc = 2;
                return 0.5;
            case 2:
                sbGivePower.setActive(true);
                pc = 3;
                return 0.1;
            case 3:
                sbGivePower.setActive(false);
                i += 1; pc = 1; return 0.0;
            case 4:
                sbGivePower.setActive(true);
                i = 0;
                pc = 5;
                return 0.0;
            case 5:                                 // for (i = 0; i < 2; i++)
                if (i >= 2) { pc = 8; return 0.25; }
                pc = 6;
                return 0.25;
            case 6:
                sbDigimon.setActive(false);
                sbGivePower.setActive(true);
                pc = 7;
                return 0.1;
            case 7:
                sbDigimon.setActive(true);
                sbGivePower.setActive(false);
                i += 1; pc = 5; return 0.0;
            case 8:
                sbDigimon.setActive(false);
                sbGivePower.setActive(true);
                pc = 9;
                return 0.1;
            case 9:
                sbGivePower.setActive(false);
                pc = 10;
                return 0.35;
            case 10:
                gm.audioMgr.playSound("encounterDigimon");
                sbDigimon.setActive(true);
                pc = 11;
                return 0.35;
            case 11:
                sbDigimon.setSprite(attack());
                pc = 12;
                return 0.6;
            case 12:
                sbDigimon.setSprite(base());
                pc = 13;
                return 0.6;
            case 13:
                sbDigimon.setSprite(attack());
                pc = 14;
                return finalDelay;
            case 14:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:909  EncounterBoss -- the same idea with the massive
// power sprite and its own rhythm.
class EncounterBoss extends Routine {
    var gm as GameManager;
    var digimonIndex as Number;

    var sbDigimon as SpriteBuilder?;
    var sbGivePower as SpriteBuilder?;
    var i as Number = 0;

    function initialize(gmIn as GameManager, digimonIndexIn as Number) {
        Routine.initialize();
        gm = gmIn;
        digimonIndex = digimonIndexIn;
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                sbDigimon = Kaisa.ScreenBuilder.buildSprite("Enemy", parent)
                    .setSize(24, 24).center()
                    .setSprite(gm.digimonSprite(digimonIndex, gm.data.ACTION_BASE));
                sbDigimon.flipHorizontal(true);
                sbDigimon.setActive(false);
                sbGivePower = Kaisa.ScreenBuilder.buildSprite("MassivePower", parent)
                    .setSprite(Kaisa.Sprites.GIVE_MASSIVE_POWER).setTransparent(true);
                sbGivePower.setActive(false);
                pc = 1;
                return 0.5;
            case 1:
                sbGivePower.setActive(true);
                pc = 2;
                return 0.1;
            case 2:
                sbGivePower.setActive(false);
                gm.audioMgr.playSound("encounterDigimonBoss");
                i = 0;
                pc = 3;
                return 0.0;
            case 3:                                 // for (i = 0; i < 3; i++)
                if (i >= 3) { i = 0; pc = 6; return 0.0; }
                pc = 4;
                return 0.5;
            case 4:
                sbGivePower.setActive(true);
                pc = 5;
                return 0.1;
            case 5:
                sbGivePower.setActive(false);
                i += 1; pc = 3; return 0.0;
            case 6:
                sbDigimon.setActive(true);
                i = 0;
                pc = 7;
                return 0.0;
            case 7:                                 // for (i = 0; i < 2; i++)
                if (i >= 2) { pc = 10; return 0.25; }
                pc = 8;
                return 0.25;
            case 8:
                sbGivePower.setActive(true);
                pc = 9;
                return 0.1;
            case 9:
                sbGivePower.setActive(false);
                i += 1; pc = 7; return 0.0;
            case 10:
                sbDigimon.setActive(false);
                pc = 11;
                return 0.15;
            case 11:
                sbDigimon.setActive(true);
                pc = 12;
                return 0.5;
            case 12:
                sbDigimon.setSprite(gm.digimonSprite(digimonIndex, gm.data.ACTION_AT));
                pc = 13;
                return 0.5;
            case 13:
                sbDigimon.setSprite(gm.digimonSprite(digimonIndex, gm.data.ACTION_BASE));
                pc = 14;
                return 0.5;
            case 14:
                sbDigimon.setSprite(gm.digimonSprite(digimonIndex, gm.data.ACTION_AT));
                pc = 15;
                return 0.75;
            case 15:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:955  SpendCallPoints -- the call-point bar, with the
// points spent disappearing off the right.
class SpendCallPoints extends Routine {
    var gm as GameManager;
    var pointsBefore as Number;
    var pointsAfter as Number;

    var sbCallPoints as SpriteBuilder?;
    var callPoints as Array<RectangleBuilder?> = [];

    function initialize(gmIn as GameManager, pointsBeforeIn as Number,
                        pointsAfterIn as Number) {
        Routine.initialize();
        gm = gmIn;
        pointsBefore = pointsBeforeIn;
        pointsAfter = pointsAfterIn;
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                sbCallPoints = Kaisa.ScreenBuilder.buildSprite("CallPointScreen", parent)
                    .setSprite(Kaisa.Sprites.BATTLE_CALL_POINTS_SCREEN);
                callPoints = [];
                for (var i = 0; i < pointsBefore; i += 1) {
                    callPoints.add(Kaisa.ScreenBuilder.buildRectangle("CallPoint" + i, sbCallPoints)
                        .setSize(2, 5).setPosition(1 + (3 * i), 25));
                }
                pc = 1;
                return 1.0;
            case 1:
                gm.audioMgr.playButtonA();
                for (var i = callPoints.size() - 1; i > pointsAfter - 1; i -= 1) {
                    callPoints[i].dispose();
                }
                pc = 2;
                return 1.0;
            case 2:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:972  DeportSprite -- four copies of a sprite fly apart.
// `dim` is the size, which DeportDigimon leaves at 24.
class DeportSprite extends Routine {
    var gm as GameManager;
    var sprite as Array<Number>?;
    var dim as Number;

    var spDigimon as Array<SpriteBuilder?> = [null, null, null, null];
    var i as Number = 0;

    function initialize(gmIn as GameManager, spriteIn as Array<Number>?,
                        dimIn as Number) {
        Routine.initialize();
        gm = gmIn;
        sprite = spriteIn;
        dim = dimIn;
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                for (var n = 0; n < 4; n += 1) {
                    spDigimon[n] = Kaisa.ScreenBuilder.buildSprite("Deport" + n, parent)
                        .setSize(dim, dim).setSprite(sprite).setTransparent(true)
                        .setActive(false).center();
                }
                spDigimon[0].setActive(true);
                gm.audioMgr.playSound("deport");
                i = 0;
                pc = 1;
                return 0.0;
            case 1:                                 // for (i = 0; i < 2; i++)
                if (i >= 2) { pc = 4; return 0.0; }
                pc = 2;
                return 0.25;
            case 2:
                spDigimon[0].setActive(false);
                pc = 3;
                return 0.25;
            case 3:
                spDigimon[0].setActive(true);
                i += 1; pc = 1; return 0.0;
            case 4:
                spDigimon[1].setActive(true);
                spDigimon[2].setActive(true);
                spDigimon[3].setActive(true);
                i = 0;
                pc = 5;
                return 0.75;
            case 5:                                 // for (i = 0; i < 32; i++)
                if (i >= 32) { pc = 7; return 0.2; }
                spDigimon[0].move(Kaisa.DIR_LEFT, 1);
                spDigimon[1].move(Kaisa.DIR_RIGHT, 1);
                spDigimon[2].move(Kaisa.DIR_UP, 1);
                spDigimon[3].move(Kaisa.DIR_DOWN, 1);
                pc = 6;
                return 1.5 / 32;
            case 6:
                i += 1; pc = 5; return 0.0;
            case 7:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:968  DeportDigimon -- DeportSprite of the Digimon.
class DeportDigimon extends Routine {
    var gm as GameManager;
    var digimonIndex as Number;

    function initialize(gmIn as GameManager, digimonIndexIn as Number) {
        Routine.initialize();
        gm = gmIn;
        digimonIndex = digimonIndexIn;
    }

    function step(rt as Fiber) as Float {
        switch (pc) {
            case 0:
                pc = 1;
                rt.call(new DeportSprite(gm,
                    gm.digimonSprite(digimonIndex, gm.data.ACTION_BASE), 24));
                return 0.0;
            case 1:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:1003  DeportSpirit -- the spirit splits in two and
// leaves, and the character takes the power it left behind.
class DeportSpirit extends Routine {
    var gm as GameManager;
    var digimonIndex as Number;
    var character as Number;

    var sCharacter as Array = [];
    var spDigimon as Array<SpriteBuilder?> = [null, null];
    var spCharacter as SpriteBuilder?;
    var spGivePower as SpriteBuilder?;
    var i as Number = 0;

    function initialize(gmIn as GameManager, digimonIndexIn as Number,
                        characterIn as Number) {
        Routine.initialize();
        gm = gmIn;
        digimonIndex = digimonIndexIn;
        character = characterIn;
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                sCharacter = gm.characterSprites(character);
                gm.audioMgr.playSound("deportSpirit");
                for (var n = 0; n < 2; n += 1) {
                    spDigimon[n] = Kaisa.ScreenBuilder.buildSprite("Deport" + n, parent)
                        .setSize(24, 24)
                        .setSprite(gm.digimonSprite(digimonIndex, gm.data.ACTION_BASE))
                        .setTransparent(true).setActive(true).center();
                }
                i = 0;
                pc = 1;
                return 0.25;
            case 1:                                 // for (i = 0; i < 16; i++)
                if (i >= 16) { i = 0; pc = 3; return 0.0; }
                spDigimon[0].move(Kaisa.DIR_UP, 1);
                spDigimon[1].move(Kaisa.DIR_DOWN, 1);
                pc = 2;
                return 1.75 / 16;
            case 2:
                i += 1; pc = 1; return 0.0;
            case 3:                                 // for (i = 0; i < 3; i++)
                if (i >= 3) { pc = 6; return 0.0; }
                spDigimon[0].setActive(true);
                spDigimon[1].setActive(true);
                pc = 4;
                return 0.1;
            case 4:
                spDigimon[0].setActive(false);
                spDigimon[1].setActive(false);
                pc = 5;
                return 0.3;
            case 5:
                i += 1; pc = 3; return 0.0;
            case 6:
                spDigimon[0].dispose();
                spDigimon[1].dispose();
                pc = 7;
                return 0.3;
            case 7:
                spCharacter = Kaisa.ScreenBuilder.buildSprite("Character", parent)
                    .setSprite(sCharacter[0]).setActive(false);
                spGivePower = Kaisa.ScreenBuilder.buildSprite("GivePower", parent)
                    .setSprite(Kaisa.Sprites.GIVE_MASSIVE_POWER_INVERTED).setTransparent(true);
                i = 0;
                pc = 8;
                return 0.0;
            case 8:                                 // for (i = 0; i < 3; i++)
                if (i >= 3) { pc = 11; return 0.2; }
                if (i == 2) { spCharacter.setActive(true); }
                spGivePower.setActive(true);
                pc = 9;
                return 0.1;
            case 9:
                spGivePower.setActive(false);
                pc = 10;
                return 0.3;
            case 10:
                i += 1; pc = 8; return 0.0;
            case 11:
                spGivePower.setActive(true);
                pc = 12;
                return 0.1;
            case 12:
                spGivePower.setActive(false);
                pc = 13;
                return 1.0;
            case 13:
                spGivePower.setActive(true);
                pc = 14;
                return 0.7;
            case 14:
                spGivePower.setActive(false);
                spCharacter.setSprite(sCharacter[9]);
                pc = 15;
                return 0.9;
            case 15:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:398  ReceiveSpirit -- the spirit drops onto a platform.
class ReceiveSpirit extends Routine {
    var gm as GameManager;
    var digimonIndex as Number;

    var sbDigimon as SpriteBuilder?;
    var i as Number = 0;

    function initialize(gmIn as GameManager, digimonIndexIn as Number) {
        Routine.initialize();
        gm = gmIn;
        digimonIndex = digimonIndexIn;
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                Kaisa.ScreenBuilder.buildRectangle("Platform", parent)
                    .setSize(26, 1).setPosition(3, 29);
                sbDigimon = Kaisa.ScreenBuilder.buildSprite(gm.data.name(digimonIndex), parent)
                    .setSize(24, 24).flipHorizontal(true).center()
                    .setSprite(gm.digimonSprite(digimonIndex, gm.data.ACTION_SP))
                    .placeOutside(Kaisa.DIR_UP);
                i = 0;
                pc = 1;
                return 0.15;
            case 1:                                 // for (i = 0; i < 28; i++)
                if (i >= 28) { pc = 3; return 0.75; }
                sbDigimon.move(Kaisa.DIR_DOWN, 1);
                pc = 2;
                return 2.5 / 28;
            case 2:
                i += 1; pc = 1; return 0.0;
            case 3:
                sbDigimon.flipHorizontal(false);
                pc = 4;
                return 0.75;
            case 4:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:418  LoseSpirit -- the enemy's attractor drags the
// spirit off the screen, and the enemy leaves with it.
class LoseSpirit extends Routine {
    var gm as GameManager;
    var spiritLost as Number;
    var enemyIndex as Number;

    var sbSpiritLost as SpriteBuilder?;
    var sbAttractor as SpriteBuilder?;
    var sbEnemyDigimon as SpriteBuilder?;
    var i as Number = 0;

    function initialize(gmIn as GameManager, spiritLostIn as Number,
                        enemyIndexIn as Number) {
        Routine.initialize();
        gm = gmIn;
        spiritLost = spiritLostIn;
        enemyIndex = enemyIndexIn;
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                // SOURCE ODDITY, reproduced: the spirit is named "Enemy" too.
                sbSpiritLost = Kaisa.ScreenBuilder.buildSprite("Enemy", parent)
                    .setSize(24, 24).center().setX(8)
                    .setSprite(gm.digimonSprite(spiritLost, gm.data.ACTION_SP))
                    .setActive(false);
                sbAttractor = Kaisa.ScreenBuilder.buildSprite("Attractor", parent)
                    .setSize(3, 24).center().setX(20)
                    .setSprite(Kaisa.Sprites.STEAL_SPIRIT_ATTRACTOR);
                sbEnemyDigimon = Kaisa.ScreenBuilder.buildSprite("Enemy", parent)
                    .setSize(24, 24).center().setX(0)
                    .setSprite(gm.digimonSprite(enemyIndex, gm.data.ACTION_BASE))
                    .flipHorizontal(true);
                gm.audioMgr.playSound("attackTravelVeryLong");
                i = 0;
                pc = 1;
                return 0.0;
            case 1:                                 // for (i = 0; i < 12; i++)
                if (i >= 12) { pc = 3; return 0.0; }
                sbAttractor.move(Kaisa.DIR_RIGHT, 1);
                pc = 2;
                return 2.0 / 32;
            case 2:
                i += 1; pc = 1; return 0.0;
            case 3:
                sbEnemyDigimon.setActive(false);
                sbSpiritLost.setActive(true);
                sbAttractor.placeOutside(Kaisa.DIR_LEFT);
                i = 0;
                pc = 4;
                return 0.0;
            case 4:                                 // for (i = 0; i < 8; i++)
                if (i >= 8) { i = 0; pc = 6; return 0.0; }
                sbAttractor.move(Kaisa.DIR_RIGHT, 1);
                pc = 5;
                return 2.0 / 32;
            case 5:
                i += 1; pc = 4; return 0.0;
            case 6:                                 // for (i = 0; i < 32; i++)
                if (i >= 32) { pc = 8; return 0.0; }
                sbAttractor.move(Kaisa.DIR_LEFT, 1);
                sbSpiritLost.move(Kaisa.DIR_LEFT, 1);
                pc = 7;
                return 2.0 / 32;
            case 7:
                i += 1; pc = 6; return 0.0;
            case 8:
                sbEnemyDigimon.setActive(true);
                sbSpiritLost.move(Kaisa.DIR_RIGHT, 40 + 28);
                sbAttractor.move(Kaisa.DIR_RIGHT, 40 + 28);
                i = 0;
                pc = 9;
                return 0.0;
            case 9:                                 // for (i = 0; i < 42; i++)
                if (i >= 42) { pc = 11; return 0.0; }
                sbAttractor.move(Kaisa.DIR_LEFT, 1);
                sbSpiritLost.move(Kaisa.DIR_LEFT, 1);
                pc = 10;
                return 2.0 / 32;
            case 10:
                i += 1; pc = 9; return 0.0;
            case 11:
                sbSpiritLost.setActive(false);
                sbAttractor.setActive(false);
                i = 0;
                pc = 12;
                return 0.75;
            case 12:                                // for (i = 0; i < 16; i++)
                if (i >= 16) { pc = 14; return 0.2; }
                sbEnemyDigimon.move(Kaisa.DIR_UP, 2);
                pc = 13;
                return 0.6 / 16;
            case 13:
                i += 1; pc = 12; return 0.0;
            case 14:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:668  AwardDistance -- the minigame score screen: the
// score, then the distance it bought, counted from the old value to the new.
class AwardDistance extends Routine {
    var gm as GameManager;
    var score as Number;
    var distanceBefore as Number;
    var distanceAfter as Number;

    var tbDistance as TextBoxBuilder?;

    function initialize(gmIn as GameManager, scoreIn as Number,
                        distanceBeforeIn as Number, distanceAfterIn as Number) {
        Routine.initialize();
        gm = gmIn;
        score = scoreIn;
        distanceBefore = distanceBeforeIn;
        distanceAfter = distanceAfterIn;
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                gm.audioMgr.playButtonA();
                Kaisa.ScreenBuilder.buildSprite("Score", parent)
                    .setSize(32, 5).setPosition(1, 1).setSprite(Kaisa.Sprites.GAMES_SCORE);
                pc = 1;
                return 1.0;
            case 1:
                gm.audioMgr.playButtonA();
                Kaisa.ScreenBuilder.buildTextBox("ScoreText", parent, Kaisa.Font.REGULAR)
                    .setText(score.toString()).setSize(31, 5).setPosition(1, 9)
                    .setAlignment(Kaisa.Text.ANCHOR_UPPER_RIGHT);
                pc = 2;
                return 1.0;
            case 2:
                gm.audioMgr.playButtonA();
                Kaisa.ScreenBuilder.buildSprite("Distance", parent)
                    .setSize(32, 5).setPosition(1, 18).setSprite(Kaisa.Sprites.GAMES_DISTANCE);
                pc = 3;
                return 1.0;
            case 3:
                gm.audioMgr.playButtonA();
                tbDistance = Kaisa.ScreenBuilder.buildTextBox("DistanceText", parent, Kaisa.Font.REGULAR)
                    .setText(distanceBefore.toString()).setSize(31, 5).setPosition(1, 26)
                    .setAlignment(Kaisa.Text.ANCHOR_UPPER_RIGHT);
                pc = 4;
                return 1.0;
            case 4:
                gm.audioMgr.playCharHappy();
                tbDistance.setText(distanceAfter.toString());
                pc = 5;
                return 2.0;
            case 5:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:698  TravelMap -- the map scrolls from one quadrant of
// a multi-map world to another. Adjacent quadrants slide once; opposite ones
// slide twice, each half taking half the duration.
class TravelMap extends Routine {
    var gm as GameManager;
    var world as Number;
    var mapBefore as Number;
    var mapAfter as Number;
    var animDuration as Float;

    var cbMap as ContainerBuilder?;
    var animationDir as Number = Kaisa.DIR_RIGHT;
    var firstDir as Number = Kaisa.DIR_UP;
    var secondDir as Number = Kaisa.DIR_LEFT;
    var i as Number = 0;

    function initialize(gmIn as GameManager, worldIn as Number, mapBeforeIn as Number,
                        mapAfterIn as Number, animDurationIn as Float) {
        Routine.initialize();
        gm = gmIn;
        world = worldIn;
        mapBefore = mapBeforeIn;
        mapAfter = mapAfterIn;
        animDuration = animDurationIn;
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                cbMap = gm.buildMapScreen(world, parent);

                if (mapBefore == 0) { cbMap.setPosition(0, 0); }
                else if (mapBefore == 1) { cbMap.setPosition(0, -32); }
                else if (mapBefore == 2) { cbMap.setPosition(-32, -32); }
                else if (mapBefore == 3) { cbMap.setPosition(-32, 0); }

                // Both areas are on the same map.
                if (mapBefore == mapAfter) { pc = 5; return animDuration; }

                // The maps are consecutive.
                if ((mapBefore - mapAfter).abs() == 1
                        || (mapBefore == 0 && mapAfter == 3)
                        || (mapBefore == 3 && mapAfter == 0)) {
                    animationDir = Kaisa.DIR_RIGHT;
                    if (mapBefore == 0 && mapAfter == 3) { animationDir = Kaisa.DIR_LEFT; }
                    else if (mapBefore == 0 && mapAfter == 1) { animationDir = Kaisa.DIR_UP; }
                    else if (mapBefore == 1 && mapAfter == 0) { animationDir = Kaisa.DIR_DOWN; }
                    else if (mapBefore == 1 && mapAfter == 2) { animationDir = Kaisa.DIR_LEFT; }
                    else if (mapBefore == 2 && mapAfter == 1) { animationDir = Kaisa.DIR_RIGHT; }
                    else if (mapBefore == 2 && mapAfter == 3) { animationDir = Kaisa.DIR_DOWN; }
                    else if (mapBefore == 3 && mapAfter == 2) { animationDir = Kaisa.DIR_UP; }
                    else if (mapBefore == 3 && mapAfter == 0) { animationDir = Kaisa.DIR_RIGHT; }
                    i = 0;
                    pc = 1;
                    return 0.0;
                }

                // Opposite corners: two slides. The four cases differ only in
                // which way each half goes.
                if (mapBefore == 0 && mapAfter == 2) {
                    firstDir = Kaisa.DIR_UP; secondDir = Kaisa.DIR_LEFT;
                } else if (mapBefore == 2 && mapAfter == 0) {
                    firstDir = Kaisa.DIR_DOWN; secondDir = Kaisa.DIR_RIGHT;
                } else if (mapBefore == 1 && mapAfter == 3) {
                    firstDir = Kaisa.DIR_LEFT; secondDir = Kaisa.DIR_DOWN;
                } else if (mapBefore == 3 && mapAfter == 1) {
                    firstDir = Kaisa.DIR_RIGHT; secondDir = Kaisa.DIR_UP;
                } else {
                    pc = 5;                     // no branch matched, as in the source
                    return 0.0;
                }
                i = 0;
                pc = 3;
                return 0.0;
            case 1:                                 // for (i = 0; i < 32; i++)
                if (i >= 32) { pc = 5; return 0.0; }
                cbMap.move(animationDir, 1);
                pc = 2;
                return animDuration / 32;
            case 2:
                i += 1; pc = 1; return 0.0;
            case 3:                                 // the first half
                if (i >= 32) { i = 0; pc = 6; return 0.0; }
                cbMap.move(firstDir, 1);
                pc = 4;
                return animDuration / 64;
            case 4:
                i += 1; pc = 3; return 0.0;
            case 5:
                cbMap.dispose();
                return Routine.DONE;
            case 6:                                 // the second half
                if (i >= 32) { pc = 5; return 0.0; }
                cbMap.move(secondDir, 1);
                pc = 7;
                return animDuration / 64;
            case 7:
                i += 1; pc = 6; return 0.0;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:808  ForcedTravelMap -- the map slide the game plays
// when it moves the player itself, then the new area's screen.
class ForcedTravelMap extends Routine {
    var gm as GameManager;
    var world as Number;
    var areaBefore as Number;
    var areaAfter as Number;
    var newDistance as Number;

    function initialize(gmIn as GameManager, worldIn as Number, areaBeforeIn as Number,
                        areaAfterIn as Number, newDistanceIn as Number) {
        Routine.initialize();
        gm = gmIn;
        world = worldIn;
        areaBefore = areaBeforeIn;
        areaAfter = areaAfterIn;
        newDistance = newDistanceIn;
    }

    function step(rt as Fiber) as Float {
        switch (pc) {
            case 0:
                var mapBefore = gm.data.worldArea(world, areaBefore)[1];
                var mapAfter = gm.data.worldArea(world, areaAfter)[1];
                gm.audioMgr.playSound("travelMap");
                pc = 1;
                rt.call(new TravelMap(gm, world, mapBefore, mapAfter, 3.5));
                return 0.0;
            case 1:
                pc = 2;
                rt.call(new DisplayNewArea(gm, world, areaAfter, newDistance));
                return 0.0;
            case 2:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:2263  DestroyBox -- the Jackpot Box explodes and is
// left broken. The box draws from the Digimon sheet but has no Digimon row, so
// its cells are named constants (tools/pack_ui_sprites.py).
class DestroyBox extends Routine {
    var gm as GameManager;
    var sbBox as SpriteBuilder?;
    var i as Number = 0;

    function initialize(gmIn as GameManager) {
        Routine.initialize();
        gm = gmIn;
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                // SOURCE ODDITY, reproduced: the box is named "Loser".
                sbBox = Kaisa.ScreenBuilder.buildSprite("Loser", parent)
                    .setSize(24, 24).center().flipHorizontal(true)
                    .setSprite(Kaisa.Sprites.JACKPOT);
                gm.audioMgr.stopSound();
                pc = 1;
                return 0.5;
            case 1:
                gm.audioMgr.playSound("explosion");
                sbBox.flipHorizontal(false);
                sbBox.center();
                i = 0;
                pc = 2;
                return 0.0;
            case 2:                                 // for (i = 0; i < 2; i++)
                if (i >= 2) { pc = 5; return 0.15; }
                sbBox.setSprite(Kaisa.Sprites.BATTLE_EXPLOSION[0]);
                pc = 3;
                return 0.5;
            case 3:
                sbBox.setSprite(Kaisa.Sprites.BATTLE_EXPLOSION[1]);
                pc = 4;
                return 0.5;
            case 4:
                i += 1; pc = 2; return 0.0;
            case 5:
                sbBox.flipHorizontal(true).setSprite(Kaisa.Sprites.JACKPOT_SPIRIT);
                pc = 6;
                return 0.85;
            case 6:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:2285  BoxResists -- the box shrugs the attack off and
// the player's crush sprite is sent flying past it.
class BoxResists extends Routine {
    var gm as GameManager;
    var friendlyIndex as Number;

    var sbBox as SpriteBuilder?;
    var sbGivePower as SpriteBuilder?;
    var i as Number = 0;

    function initialize(gmIn as GameManager, friendlyIndexIn as Number) {
        Routine.initialize();
        gm = gmIn;
        friendlyIndex = friendlyIndexIn;
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                sbBox = Kaisa.ScreenBuilder.buildSprite("Loser", parent)
                    .setSize(24, 24).center().setSprite(Kaisa.Sprites.JACKPOT)
                    .flipHorizontal(true);
                sbGivePower = Kaisa.ScreenBuilder.buildSprite("Loser", parent)
                    .setSprite(Kaisa.Sprites.GIVE_MASSIVE_POWER_INVERTED)
                    .setTransparent(true).setActive(false);
                gm.audioMgr.stopSound();
                pc = 1;
                return 0.5;
            case 1:
                sbBox.center();
                i = 0;
                pc = 2;
                return 0.0;
            case 2:                                 // for (i = 0; i < 2; i++)
                if (i >= 2) { pc = 5; return 0.25; }
                sbGivePower.setActive(true);
                pc = 3;
                return 0.15;
            case 3:
                sbGivePower.setActive(false);
                pc = 4;
                return 0.35;
            case 4:
                i += 1; pc = 2; return 0.0;
            case 5:
                gm.audioMgr.playSound("attackTravelVeryLong");
                sbBox.flipHorizontal(false)
                    .setSprite(gm.digimonSprite(friendlyIndex, gm.data.ACTION_CR))
                    .placeOutside(Kaisa.DIR_LEFT);
                i = 0;
                pc = 6;
                return 0.0;
            case 6:                                 // for (i = 0; i < 64; i++)
                if (i >= 64) { pc = 8; return 0.0; }
                sbBox.move(Kaisa.DIR_RIGHT, 1);
                pc = 7;
                return 0.6 / 16;
            case 7:
                i += 1; pc = 6; return 0.0;
            case 8:
                gm.audioMgr.stopSound();
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:1814  BoostFailed -- the sacrifice flashes and is
// erased, and nothing comes of it.
class BoostFailed extends Routine {
    var gm as GameManager;
    var sacrifice as Number;

    var sbDigimon as SpriteBuilder?;
    var sbGivePower as SpriteBuilder?;
    var i as Number = 0;

    function initialize(gmIn as GameManager, sacrificeIn as Number) {
        Routine.initialize();
        gm = gmIn;
        sacrifice = sacrificeIn;
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                gm.audioMgr.playSound("digiPowerFailed");
                // SOURCE ODDITY, reproduced: both elements are "GivePower".
                sbDigimon = Kaisa.ScreenBuilder.buildSprite("GivePower", parent)
                    .setSize(24, 24)
                    .setSprite(gm.digimonSprite(sacrifice, gm.data.ACTION_BASE)).center();
                sbGivePower = Kaisa.ScreenBuilder.buildSprite("GivePower", parent)
                    .setSprite(Kaisa.Sprites.GIVE_POWER_INVERTED);
                i = 0;
                pc = 1;
                return 0.0;
            case 1:                                 // for (i = 0; i < 2; i++)
                if (i >= 2) { i = 0; pc = 5; return 0.4; }
                sbGivePower.setSprite(Kaisa.Sprites.GIVE_POWER_INVERTED).setActive(true);
                pc = 2;
                return 0.2;
            case 2:
                sbGivePower.setSprite(Kaisa.Sprites.GIVE_POWER);
                pc = 3;
                return 0.2;
            case 3:
                sbGivePower.setActive(false);
                pc = 4;
                return 0.45;
            case 4:
                i += 1; pc = 1; return 0.0;
            case 5:
                sbDigimon.setActive(false);
                i = 0;
                pc = 6;
                return 0.0;
            case 6:                                 // for (i = 0; i < 2; i++)
                if (i >= 2) { i = 0; pc = 9; return 0.0; }
                pc = 7;
                return 0.60;
            case 7:
                sbDigimon.setActive(true);
                pc = 8;
                return 0.45;
            case 8:
                sbDigimon.setActive(false);
                i += 1; pc = 6; return 0.0;
            case 9:                                 // for (i = 0; i < 5; i++)
                if (i >= 5) { pc = 12; return 0.5; }
                pc = 10;
                return 0.30;
            case 10:
                sbDigimon.setActive(true);
                pc = 11;
                return 0.1;
            case 11:
                sbDigimon.setActive(false);
                i += 1; pc = 9; return 0.0;
            case 12:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:1851  BoostSucceed -- the same opening, then a curtain
// wipes the sacrifice away and the boosted Digimon is behind it.
class BoostSucceed extends Routine {
    var gm as GameManager;
    var digimonIndex as Number;
    var sacrifice as Number;

    var sbDigimon as SpriteBuilder?;
    var sbGivePower as SpriteBuilder?;
    var sbCurtain as SpriteBuilder?;
    var i as Number = 0;

    function initialize(gmIn as GameManager, digimonIndexIn as Number,
                        sacrificeIn as Number) {
        Routine.initialize();
        gm = gmIn;
        digimonIndex = digimonIndexIn;
        sacrifice = sacrificeIn;
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                gm.audioMgr.playSound("digiPowerSucceed");
                sbDigimon = Kaisa.ScreenBuilder.buildSprite("GivePower", parent)
                    .setSize(24, 24)
                    .setSprite(gm.digimonSprite(sacrifice, gm.data.ACTION_BASE)).center();
                sbGivePower = Kaisa.ScreenBuilder.buildSprite("GivePower", parent)
                    .setSprite(Kaisa.Sprites.GIVE_POWER_INVERTED);
                i = 0;
                pc = 1;
                return 0.0;
            case 1:                                 // for (i = 0; i < 2; i++)
                if (i >= 2) { i = 0; pc = 5; return 0.4; }
                sbGivePower.setSprite(Kaisa.Sprites.GIVE_POWER_INVERTED).setActive(true);
                pc = 2;
                return 0.2;
            case 2:
                sbGivePower.setSprite(Kaisa.Sprites.GIVE_POWER);
                pc = 3;
                return 0.2;
            case 3:
                sbGivePower.setActive(false);
                pc = 4;
                return 0.45;
            case 4:
                i += 1; pc = 1; return 0.0;
            case 5:
                sbCurtain = Kaisa.ScreenBuilder.buildSprite("GivePower", parent)
                    .setSprite(Kaisa.Sprites.CURTAIN).placeOutside(Kaisa.DIR_UP);
                i = 0;
                pc = 6;
                return 0.0;
            case 6:                                 // for (i = 0; i < 64; i++)
                if (i >= 64) { pc = 8; return 0.0; }
                if (i == 32) { sbDigimon.setActive(false); }
                sbCurtain.move(Kaisa.DIR_DOWN, 1);
                pc = 7;
                return 3.5 / 64;
            case 7:
                i += 1; pc = 6; return 0.0;
            case 8:
                sbDigimon.setSprite(gm.digimonSprite(digimonIndex, gm.data.ACTION_BASE))
                         .setActive(true);
                pc = 9;
                return 0.5;
            case 9:
                sbCurtain.setTransparent(true);
                i = 0;
                pc = 10;
                return 0.0;
            case 10:                                // for (i = 0; i < 64; i++)
                if (i >= 64) { i = 0; pc = 12; return 0.4; }
                if (i == 32) { sbDigimon.setActive(true); }
                sbCurtain.move(Kaisa.DIR_UP, 1);
                pc = 11;
                return 3.5 / 64;
            case 11:
                i += 1; pc = 10; return 0.0;
            case 12:
                sbCurtain.setSprite(Kaisa.Sprites.GIVE_MASSIVE_POWER_INVERTED)
                         .setPosition(0, 0);
                i = 0;
                pc = 13;
                return 0.0;
            case 13:                                // for (i = 0; i < 2; i++)
                if (i >= 2) { pc = 16; return 0.1; }
                pc = 14;
                return 0.1;
            case 14:
                sbCurtain.setActive(false);
                pc = 15;
                return 0.4;
            case 15:
                sbCurtain.setActive(true);
                i += 1; pc = 13; return 0.0;
            case 16:
                sbCurtain.setActive(false);
                pc = 17;
                return 1.0;
            case 17:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:2720  EnemyEscapes -- the enemy looks around, bolts,
// and the player's Digimon is left standing there.
class EnemyEscapes extends Routine {
    var gm as GameManager;
    var enemyIndex as Number;
    var friendlyIndex as Number;

    var sEnemy as Array = [];
    var sFriendly as Array = [];
    var sbEnemy as SpriteBuilder?;
    var sbDisobey as SpriteBuilder?;
    var sbFriendly as SpriteBuilder?;
    var i as Number = 0;

    function initialize(gmIn as GameManager, enemyIndexIn as Number,
                        friendlyIndexIn as Number) {
        Routine.initialize();
        gm = gmIn;
        enemyIndex = enemyIndexIn;
        friendlyIndex = friendlyIndexIn;
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                sEnemy = gm.getAllDigimonSprites(enemyIndex);
                sFriendly = gm.getAllDigimonSprites(friendlyIndex);
                sbEnemy = Kaisa.ScreenBuilder.buildSprite("Enemy", parent)
                    .setSize(24, 24).center().setSprite(sEnemy[0]).flipHorizontal(true);
                pc = 1;
                return 0.65;
            case 1:
                sbEnemy.flipHorizontal(false);
                pc = 2;
                return 0.65;
            case 2:
                sbEnemy.flipHorizontal(true);
                pc = 3;
                return 0.3;
            case 3:
                sbEnemy.flipHorizontal(false);
                pc = 4;
                return 0.3;
            case 4:
                sbEnemy.flipHorizontal(true);
                pc = 5;
                return 0.3;
            case 5:
                sbEnemy.flipHorizontal(false);
                sbDisobey = Kaisa.ScreenBuilder.buildSprite("Disobey", parent)
                    .setSize(3, 9).setPosition(1, 1).setSprite(Kaisa.Sprites.BATTLE_DISOBEY);
                pc = 6;
                return 0.3;
            case 6:
                sbDisobey.setActive(false);
                pc = 7;
                return 0.3;
            case 7:
                gm.audioMgr.playSound("launchAttack");
                sbEnemy.setSprite(sEnemy[2]);
                i = 0;
                pc = 8;
                return 0.0;
            case 8:                                 // for (i = 0; i < 32; i++)
                if (i >= 32) { pc = 10; return 0.75; }
                sbEnemy.move(Kaisa.DIR_LEFT, 1);
                pc = 9;
                return 0.8 / 32;
            case 9:
                i += 1; pc = 8; return 0.0;
            case 10:
                // SOURCE ODDITY, reproduced: the player's Digimon is built as
                // "Enemy" as well.
                sbFriendly = Kaisa.ScreenBuilder.buildSprite("Enemy", parent)
                    .setSize(24, 24).center().setSprite(sFriendly[0]);
                pc = 11;
                return 0.5;
            case 11:
                pc = 12;
                return 0.45;
            case 12:
                sbFriendly.flipHorizontal(true);
                pc = 13;
                return 0.45;
            case 13:
                sbFriendly.flipHorizontal(false);
                pc = 14;
                return 0.85;
            case 14:
                sbFriendly.setSprite(sFriendly[1]);
                sbDisobey.setActive(true);
                pc = 15;
                return 0.3;
            case 15:
                sbFriendly.setSprite(sFriendly[0]);
                pc = 16;
                return 0.3;
            case 16:
                sbDisobey.dispose();
                pc = 17;
                return 0.5;
            case 17:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:2665  TransitionToMap1 -- the screen blinks out, seven
// silent seconds pass, and the player wakes up somewhere else.
class TransitionToMap1 extends Routine {
    var gm as GameManager;
    var character as Number;

    var sCharacter as Array = [];
    var sbCharacter as SpriteBuilder?;
    var sbBlackScreen as SpriteBuilder?;
    var sbCurtain as SpriteBuilder?;
    var i as Number = 0;

    function initialize(gmIn as GameManager, characterIn as Number) {
        Routine.initialize();
        gm = gmIn;
        character = characterIn;
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                sCharacter = gm.characterSprites(character);
                sbCharacter = Kaisa.ScreenBuilder.buildSprite("Character", parent)
                    .setSprite(sCharacter[0]);
                sbBlackScreen = Kaisa.ScreenBuilder.buildSprite("Black Screen", parent)
                    .setSprite(Kaisa.Sprites.BLACK_SCREEN).setActive(false);
                sbCurtain = Kaisa.ScreenBuilder.buildSprite("Curtain", parent)
                    .setSprite(Kaisa.Sprites.CURTAIN).placeOutside(Kaisa.DIR_UP);
                i = 0;
                pc = 1;
                return 0.0;
            case 1:                                 // for (i = 0; i < 2; i++)
                if (i >= 2) { i = 0; pc = 4; return 0.0; }
                pc = 2;
                return 0.5;
            case 2:
                sbBlackScreen.setActive(true);
                pc = 3;
                return 0.1;
            case 3:
                sbBlackScreen.setActive(false);
                i += 1; pc = 1; return 0.0;
            case 4:                                 // for (i = 0; i < 2; i++)
                if (i >= 2) { pc = 7; return 0.2; }
                pc = 5;
                return 0.3;
            case 5:
                sbBlackScreen.setActive(true);
                pc = 6;
                return 0.1;
            case 6:
                sbBlackScreen.setActive(false);
                i += 1; pc = 4; return 0.0;
            case 7:
                sbBlackScreen.setActive(true);
                pc = 8;
                return 0.5;
            case 8:
                gm.audioMgr.playSound("unpleasantBeep");
                sbCharacter.setActive(false);
                pc = 9;
                return 7.0;
            case 9:
                sbBlackScreen.setActive(false);
                pc = 10;
                return 0.1;
            case 10:
                sbBlackScreen.setActive(true);
                i = 0;
                pc = 11;
                return 0.0;
            case 11:                                // for (i = 0; i < 2; i++)
                if (i >= 2) { pc = 14; return 0.1; }
                pc = 12;
                return 0.2;
            case 12:
                sbBlackScreen.setActive(false);
                pc = 13;
                return 0.1;
            case 13:
                sbBlackScreen.setActive(true);
                i += 1; pc = 11; return 0.0;
            case 14:
                sbBlackScreen.setActive(false);
                pc = 15;
                return 0.2;
            case 15:
                sbBlackScreen.setActive(true);
                pc = 16;
                return 0.1;
            case 16:
                sbBlackScreen.setActive(false);
                pc = 17;
                return 0.3;
            case 17:
                sbBlackScreen.setActive(true);
                pc = 18;
                return 0.1;
            case 18:
                sbBlackScreen.setActive(false);
                i = 0;
                pc = 19;
                return 0.0;
            case 19:                                // for (i = 0; i < 64; i++)
                if (i >= 64) { pc = 21; return 0.5; }
                if (i == 32) { sbCharacter.setSprite(sCharacter[7]).setActive(true); }
                sbCurtain.move(Kaisa.DIR_DOWN, 1);
                pc = 20;
                return 4.0 / 64;
            case 20:
                i += 1; pc = 19; return 0.0;
            case 21:
                pc = 22;
                rt.call(new DisplayNewArea(gm, gm.worldMgr.currentWorld(),
                                           gm.worldMgr.currentArea(),
                                           gm.worldMgr.currentDistance()));
                return 0.0;
            case 22:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:24  LoadCharacterSelection -- the opening flicker
// before the character-selection screen.
class LoadCharacterSelection extends Routine {
    var gm as GameManager;

    var sbCurtain as SpriteBuilder?;
    var i as Number = 0;

    function initialize(gmIn as GameManager) {
        Routine.initialize();
        gm = gmIn;
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                Kaisa.ScreenBuilder.buildSprite("Character", parent)
                    .setSprite(Kaisa.Sprites.TAKUYA[0]);
                // SOURCE ODDITY, reproduced: the curtain is a second
                // "Character".
                sbCurtain = Kaisa.ScreenBuilder.buildSprite("Character", parent);
                i = 0;
                pc = 1;
                return 0.0;
            case 1:                                 // for (i = 0; i < 2; i++)
                if (i >= 2) { i = 0; pc = 4; return 0.0; }
                sbCurtain.setSprite(Kaisa.Sprites.BLACK_SCREEN);
                pc = 2;
                return 0.15;
            case 2:
                sbCurtain.setSprite(Kaisa.Sprites.EMPTY_SPRITE);
                pc = 3;
                return 0.25;
            case 3:
                i += 1; pc = 1; return 0.0;
            case 4:
                sbCurtain.setSprite(Kaisa.Sprites.CURTAIN);
                i = 0;
                pc = 5;
                return 0.0;
            case 5:                                 // for (i = 0; i < 3; i++)
                if (i >= 3) { i = 0; pc = 8; return 0.0; }
                pc = 6;
                return 0.15;
            case 6:
                sbCurtain.setSprite(Kaisa.Sprites.EMPTY_SPRITE);
                pc = 7;
                return 0.25;
            case 7:
                sbCurtain.setSprite(Kaisa.Sprites.CURTAIN);
                i += 1; pc = 5; return 0.0;
            case 8:                                 // for (i = 0; i < 32; i++)
                if (i >= 32) { pc = 10; return 1.0; }
                sbCurtain.move(Kaisa.DIR_UP, 1);
                pc = 9;
                return 2.0 / 32;
            case 9:
                i += 1; pc = 8; return 0.0;
            case 10:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:2601  StartAppDigiHunter -- the minigame's opening: a
// loading bar, the arrows flashing, then the board of faces and START.
//
// The original takes a callback and calls it at the end; the port takes the
// app and sets its flag, which is the only thing that callback ever does.
class StartAppDigiHunter extends Routine {
    var gm as GameManager;
    var app as DigiHunter?;

    var rbLoadingBar as RectangleBuilder?;
    var sbArrows as Array<SpriteBuilder?> = [null, null, null, null, null, null];
    var sbWhiteFaces as Array<SpriteBuilder?> = [null, null, null, null];
    var sbBlackFaces as Array<SpriteBuilder?> = [null, null, null, null, null];
    var tbStart as TextBoxBuilder?;
    var i as Number = 0;

    function initialize(gmIn as GameManager, appIn as DigiHunter?) {
        Routine.initialize();
        gm = gmIn;
        app = appIn;
    }

    function setArrows(active as Boolean) as Void {
        for (var n = 0; n < sbArrows.size(); n += 1) { sbArrows[n].setActive(active); }
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                gm.audioMgr.playSound("digiHunter_Start");
                pc = 1;
                return 0.5;
            case 1:
                rbLoadingBar = Kaisa.ScreenBuilder.buildRectangle("Loading Bar", parent)
                    .setSize(1, 4).setPosition(30, 0);
                i = 0;
                pc = 2;
                return 0.0;
            case 2:                                 // for (i = 0; i < 29; i++)
                if (i >= 29) { pc = 4; return 0.0; }
                rbLoadingBar.move(Kaisa.DIR_LEFT, 1).setSize(i + 2, 4);
                pc = 3;
                return 1.25 / 29;
            case 3:
                i += 1; pc = 2; return 0.0;
            case 4:
                for (var n = 0; n < 3; n += 1) {
                    sbArrows[n] = Kaisa.ScreenBuilder.buildSprite("Vertical Arrow", parent)
                        .setSize(3, 6).setPosition(2, 9 + (n * 8))
                        .setSprite(Kaisa.Sprites.DIGI_HUNTER_ARROWS[0]);
                }
                for (var n = 0; n < 3; n += 1) {
                    sbArrows[3 + n] = Kaisa.ScreenBuilder.buildSprite("Horizontal Arrow", parent)
                        .setSize(6, 3).setPosition(6 + (n * 8), 5)
                        .setSprite(Kaisa.Sprites.DIGI_HUNTER_ARROWS[1]);
                }
                i = 0;
                pc = 5;
                return 0.0;
            case 5:                                 // for (i = 0; i < 3; i++)
                if (i >= 3) { i = 0; pc = 8; return 0.0; }
                setArrows(true);
                pc = 6;
                return 0.2;
            case 6:
                setArrows(false);
                pc = 7;
                return 0.2;
            case 7:
                i += 1; pc = 5; return 0.0;
            case 8:
                sbWhiteFaces[0] = face(parent, true, 13, 8);
                sbWhiteFaces[1] = face(parent, true, 5, 16);
                sbWhiteFaces[2] = face(parent, true, 21, 16);
                sbWhiteFaces[3] = face(parent, true, 13, 24);
                sbBlackFaces[0] = face(parent, false, 5, 8);
                sbBlackFaces[1] = face(parent, false, 21, 8);
                sbBlackFaces[2] = face(parent, false, 13, 16);
                sbBlackFaces[3] = face(parent, false, 5, 24);
                sbBlackFaces[4] = face(parent, false, 21, 24);
                i = 0;
                pc = 9;
                return 0.0;
            case 9:                                 // for (i = 0; i < 3; i++)
                if (i >= 3) { pc = 12; return 0.0; }
                setFaces(sbWhiteFaces, true);
                setFaces(sbBlackFaces, false);
                pc = 10;
                return 0.2;
            case 10:
                setFaces(sbWhiteFaces, false);
                setFaces(sbBlackFaces, true);
                pc = 11;
                return 0.2;
            case 11:
                i += 1; pc = 9; return 0.0;
            case 12:
                setFaces(sbBlackFaces, false);
                sbArrows[0].setActive(true);
                sbArrows[3].setActive(true);
                tbStart = Kaisa.ScreenBuilder.buildTextBox("Start", parent, Kaisa.Font.SMALL)
                    .setText("START").setPosition(6, 17);
                pc = 13;
                return 0.5;
            case 13:
                tbStart.setActive(false);
                pc = 14;
                return 0.5;
            case 14:
                tbStart.setActive(true);
                pc = 15;
                return 0.5;
            case 15:
                if (app != null) { app.markEnded(true); }
                return Routine.DONE;
        }
        return Routine.DONE;
    }

    function face(parent as ScreenElement, white as Boolean, x as Number,
                  y as Number) as SpriteBuilder {
        return Kaisa.ScreenBuilder.buildSprite(white ? "White face" : "Black face", parent)
            .setSize(8, 8).setPosition(x, y)
            .setSprite(Kaisa.Sprites.DIGI_HUNTER_FACES[white ? 0 : 1]);
    }

    function setFaces(faces as Array<SpriteBuilder?>, active as Boolean) as Void {
        for (var n = 0; n < faces.size(); n += 1) { faces[n].setActive(active); }
    }
}

// port of Animations.cs:1519  SusanoomonEvolution
//
// The two fusions show their five spirits each, all twenty fly past, and
// Susanoomon is formed behind a curtain. The twenty spirits and the three
// Digimon it names are resolved to indices at build time (WellKnown).
class SusanoomonEvolution extends Routine {
    var gm as GameManager;
    var character as Number;

    var sCharacter as Array = [];
    var sSusanoomon as Array = [];
    var sbBackground as SpriteBuilder?;
    var sbCharacter as SpriteBuilder?;
    var sbGiveMassivePower as SpriteBuilder?;
    var sbTranscendent as SpriteBuilder?;
    var sbSmallSpirit as SpriteBuilder?;
    var sbSmallHuman as SpriteBuilder?;
    var sbSmallAnimal as SpriteBuilder?;
    var sbCurtain as SpriteBuilder?;
    var i as Number = 0;
    var j as Number = 0;

    function initialize(gmIn as GameManager, characterIn as Number) {
        Routine.initialize();
        gm = gmIn;
        character = characterIn;
    }

    // The five positions the small spirit takes, in order.
    function spiritPosition(n as Number) as Void {
        if (n == 0) { sbSmallSpirit.setPosition(9, 0); }
        else if (n == 1) { sbSmallSpirit.setPosition(0, 7); }
        else if (n == 2) { sbSmallSpirit.setPosition(18, 7); }
        else if (n == 3) { sbSmallSpirit.setPosition(2, 16); }
        else if (n == 4) { sbSmallSpirit.setPosition(16, 16); }
    }

    function smallSpirit(list as Array<Number>, n as Number) as Array<Number>? {
        return gm.digimonSprite(list[n], gm.data.ACTION_SM);
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                sCharacter = gm.characterSprites(character);
                sSusanoomon = gm.getAllDigimonSprites(Kaisa.WellKnown.SUSANOOMON);

                // Common animation.
                sbBackground = Kaisa.ScreenBuilder.buildSprite("BlackBackground", parent)
                    .setSprite(Kaisa.Sprites.BLACK_SCREEN).setActive(false);
                sbCharacter = Kaisa.ScreenBuilder.buildSprite("Char", parent)
                    .setSprite(sCharacter[0]);
                gm.audioMgr.playSound("evolutionSpirit");
                pc = 1;
                return 0.5;
            case 1:
                sbGiveMassivePower = Kaisa.ScreenBuilder.buildSprite("Char", parent)
                    .setSprite(Kaisa.Sprites.GIVE_MASSIVE_POWER_INVERTED).setTransparent(true);
                i = 0;
                pc = 2;
                return 0.0;
            case 2:                                 // for (i = 0; i < 3; i++)
                if (i >= 3) { pc = 5; return 0.0; }
                pc = 3;
                return 0.2;
            case 3:
                sbGiveMassivePower.setActive(false);
                pc = 4;
                return 0.4;
            case 4:
                sbGiveMassivePower.setActive(true);
                i += 1; pc = 2; return 0.0;
            case 5:
                sbCharacter.setSprite(sCharacter[9]);
                pc = 6;
                return 0.2;
            case 6:
                sbGiveMassivePower.setActive(false);
                pc = 7;
                return 0.3;
            case 7:
                sbGiveMassivePower.setActive(true);
                pc = 8;
                return 0.2;
            case 8:
                sbGiveMassivePower.setActive(false);
                pc = 9;
                return 0.2;
            case 9:
                sbCharacter.placeOutside(Kaisa.DIR_DOWN);
                sbCharacter.setSprite(sCharacter[0]);
                sbTranscendent = Kaisa.ScreenBuilder.buildSprite("Transcendent", parent)
                    .setSize(24, 24)
                    .setSprite(gm.digimonSprite(Kaisa.WellKnown.KAISERGREYMON, gm.data.ACTION_SP))
                    .center();
                sbSmallSpirit = Kaisa.ScreenBuilder.buildSprite("SmallSpirit", parent)
                    .setSize(14, 16).setActive(false);
                i = 0;
                pc = 10;
                return 0.0;
            case 10:                                // KaiserGreymon: for (i < 4)
                if (i >= 4) { i = 0; pc = 13; return 0.0; }
                pc = 11;
                return 0.15;
            case 11:
                sbTranscendent.setActive(false);
                pc = 12;
                return 0.15;
            case 12:
                sbTranscendent.setActive(true);
                i += 1; pc = 10; return 0.0;
            case 13:                                // its five spirits
                if (i >= 5) { i = 0; pc = 17; return 0.0; }
                pc = 14;
                return 0.1;
            case 14:
                sbTranscendent.setActive(false);
                sbSmallSpirit.setSprite(smallSpirit(Kaisa.WellKnown.SUSANOO_HUMANS, i));
                spiritPosition(i);
                sbSmallSpirit.setActive(true);
                pc = 15;
                return 0.28;
            case 15:
                sbSmallSpirit.setActive(false);
                sbTranscendent.setActive(true);
                pc = 16;
                return 0.0;
            case 16:
                i += 1; pc = 13; return 0.0;
            case 17:                                // MagnaGarurumon
                sbTranscendent.setSprite(
                    gm.digimonSprite(Kaisa.WellKnown.MAGNAGARURUMON, gm.data.ACTION_SP));
                i = 0;
                pc = 18;
                return 0.0;
            case 18:                                // for (i = 0; i < 4; i++)
                if (i >= 4) { i = 0; pc = 21; return 0.0; }
                pc = 19;
                return 0.15;
            case 19:
                sbTranscendent.setActive(false);
                pc = 20;
                return 0.15;
            case 20:
                sbTranscendent.setActive(true);
                i += 1; pc = 18; return 0.0;
            case 21:                                // its five spirits
                if (i >= 5) { i = 0; pc = 25; return 0.0; }
                pc = 22;
                return 0.1;
            case 22:
                sbTranscendent.setActive(false);
                sbSmallSpirit.setSprite(smallSpirit(Kaisa.WellKnown.SUSANOO_HUMANS, 5 + i));
                spiritPosition(i);
                sbSmallSpirit.setActive(true);
                pc = 23;
                return 0.28;
            case 23:
                sbSmallSpirit.setActive(false);
                sbTranscendent.setActive(true);
                pc = 24;
                return 0.0;
            case 24:
                i += 1; pc = 21; return 0.0;
            case 25:
                sbTranscendent.setActive(false);
                i = 0;
                pc = 26;
                return 0.0;
            case 26:                                // the player, quickly, upwards
                if (i >= 12) { pc = 28; return 0.0; }
                sbCharacter.move(Kaisa.DIR_UP, 6);
                pc = 27;
                return 1.0 / 12;
            case 27:
                i += 1; pc = 26; return 0.0;
            case 28:                                // all twenty spirits
                sbSmallHuman = Kaisa.ScreenBuilder.buildSprite("Human", parent).setSize(14, 16);
                sbSmallAnimal = Kaisa.ScreenBuilder.buildSprite("Animal", parent).setSize(14, 16);
                i = 0;
                pc = 29;
                return 0.0;
            case 29:                                // for (i = 0; i < 10; i++)
                if (i >= 10) { pc = 34; return 0.0; }
                sbSmallHuman.setY(16).placeOutside(Kaisa.DIR_LEFT).move(Kaisa.DIR_LEFT, 1);
                sbSmallAnimal.setY(16).placeOutside(Kaisa.DIR_RIGHT).move(Kaisa.DIR_RIGHT, 1);
                sbSmallHuman.setSprite(smallSpirit(Kaisa.WellKnown.SUSANOO_HUMANS, i));
                sbSmallAnimal.setSprite(smallSpirit(Kaisa.WellKnown.SUSANOO_ANIMALS, i));
                j = 0;
                pc = 30;
                return 0.0;
            case 30:                                // for (j = 0; j < 4; j++)
                if (j >= 4) { j = 0; pc = 32; return 0.0; }
                sbSmallHuman.move(Kaisa.DIR_RIGHT, 4);
                sbSmallAnimal.move(Kaisa.DIR_LEFT, 4);
                pc = 31;
                return 0.6 / 10;
            case 31:
                j += 1; pc = 30; return 0.0;
            case 32:                                // for (j = 0; j < 6; j++)
                if (j >= 6) { i += 1; pc = 29; return 0.0; }
                sbSmallHuman.move(Kaisa.DIR_UP, 4);
                sbSmallAnimal.move(Kaisa.DIR_UP, 4);
                pc = 33;
                return 0.6 / 10;
            case 33:
                j += 1; pc = 32; return 0.0;
            case 34:
                sbSmallHuman.dispose();
                sbSmallAnimal.dispose();
                // Form Susanoomon.
                sbTranscendent.setSprite(sSusanoomon[0]).setActive(true);
                sbCurtain = Kaisa.ScreenBuilder.buildSprite("Curtain", parent)
                    .setSprite(Kaisa.Sprites.CURTAIN_SPECIAL[1]);
                i = 0;
                pc = 35;
                return 0.0;
            case 35:                                // for (i = 0; i < 32; i++)
                if (i >= 32) { pc = 37; return 0.0; }
                sbCurtain.move(Kaisa.DIR_UP, 1);
                pc = 36;
                return 2.2 / 32;
            case 36:
                i += 1; pc = 35; return 0.0;
            case 37:
                sbCurtain.placeOutside(Kaisa.DIR_DOWN);
                sbTranscendent.setSprite(sSusanoomon[1]);
                pc = 38;
                return 0.8;
            case 38:
                sbTranscendent.setSprite(sSusanoomon[0]);
                pc = 39;
                return 0.6;
            case 39:
                return Routine.DONE;
        }
        return Routine.DONE;
    }
}

// port of Animations.cs:2771  TransitionToMap3
//
// The last of the three transitions and the longest: the player runs, the
// absorbers take every spirit they have collected, the enemy appears and
// destroys them four at a time, and leaves.
class TransitionToMap3 extends Routine {
    var gm as GameManager;
    var character as Number;
    var enemyIndex as Number;
    var stolenSpirits as Array<Number>;

    var sCharacter as Array = [];
    var sEnemyDigimon as Array = [];
    var sbAllSpirits as Array<SpriteBuilder?> = [];
    var sbCharacter as SpriteBuilder?;
    var sbAbsorber as Array<SpriteBuilder?> = [null, null];
    var sbEnemyDigimon as SpriteBuilder?;
    var rbEnemyDigimonInverted as RectangleBuilder?;
    var sbSpirit as Array<SpriteBuilder?> = [null, null, null, null];
    var i as Number = 0;
    var group as Number = 0;

    function initialize(gmIn as GameManager, characterIn as Number,
                        enemyIndexIn as Number, stolenSpiritsIn as Array<Number>) {
        Routine.initialize();
        gm = gmIn;
        character = characterIn;
        enemyIndex = enemyIndexIn;
        stolenSpirits = stolenSpiritsIn;
    }

    function smallSpirit(n as Number) as Array<Number>? {
        return gm.digimonSprite(stolenSpirits[n], gm.data.ACTION_SM);
    }

    function setAbsorbers(active as Boolean) as Void {
        sbAbsorber[0].setActive(active);
        sbAbsorber[1].setActive(active);
    }

    function step(rt as Fiber) as Float {
        var parent = gm.screenMgr.animParent;
        switch (pc) {
            case 0:
                sCharacter = gm.characterSprites(character);
                sEnemyDigimon = gm.getAllDigimonSprites(enemyIndex);

                sbAllSpirits = [];
                for (var n = 0; n < stolenSpirits.size(); n += 1) {
                    var sb = Kaisa.ScreenBuilder.buildSprite("Spirit", parent)
                        .setSize(14, 16).setSprite(smallSpirit(n));
                    sb.setPosition(32 + (Kaisa.MathExt.floorToInt(n / 2.0) * 16),
                                   (n % 2) * 16);
                    sbAllSpirits.add(sb);
                }

                sbCharacter = Kaisa.ScreenBuilder.buildSprite("Character", parent)
                    .setSprite(sCharacter[4]);
                sbAbsorber[0] = Kaisa.ScreenBuilder.buildSprite("Absorber0", parent)
                    .setSize(16, 32).setPosition(0, 0)
                    .setSprite(Kaisa.Sprites.SPIRIT_ABSORBER[0]).setActive(false);
                sbAbsorber[1] = Kaisa.ScreenBuilder.buildSprite("Absorber1", parent)
                    .setSize(16, 32).setPosition(16, 0)
                    .setSprite(Kaisa.Sprites.SPIRIT_ABSORBER[1]).setActive(false);
                i = 0;
                pc = 1;
                return 0.0;
            case 1:                                 // the character runs
                if (i >= 5) { i = 0; pc = 4; return 0.0; }
                sbCharacter.setSprite(sCharacter[4]);
                pc = 2;
                return 0.25;
            case 2:
                sbCharacter.setSprite(sCharacter[5]);
                pc = 3;
                return 0.25;
            case 3:
                i += 1; pc = 1; return 0.0;
            case 4:                                 // the absorbers appear
                if (i == 0) { gm.audioMgr.playSound("stealAllSpirits"); }
                if (i >= 5) { i = 0; pc = 7; return 0.0; }
                setAbsorbers(true);
                pc = 5;
                return 0.35;
            case 5:
                setAbsorbers(false);
                pc = 6;
                return 0.35;
            case 6:
                i += 1; pc = 4; return 0.0;
            case 7:                                 // the camera pans
                if (i >= 16) { i = 0; pc = 9; return 0.0; }
                sbCharacter.move(Kaisa.DIR_RIGHT, 1);
                pc = 8;
                return 1.0 / 16;
            case 8:
                i += 1; pc = 7; return 0.0;
            case 9:
                sbAbsorber[1].setSprite(Kaisa.Sprites.SPIRIT_ABSORBER[0]);
                i = 0;
                pc = 10;
                return 0.0;
            case 10:                                // the spirits are absorbed
                if (i >= 192) { pc = 12; return 0.35; }
                sbAbsorber[1].setActive(Kaisa.MathExt.floorToInt(i / 7.0) % 2 == 0);
                for (var n = 0; n < sbAllSpirits.size(); n += 1) {
                    sbAllSpirits[n].move(Kaisa.DIR_LEFT, 1);
                }
                pc = 11;
                return 1.5 / 32;
            case 11:
                i += 1; pc = 10; return 0.0;
            case 12:
                sbAbsorber[1].setActive(false);
                sbCharacter.setActive(false);

                // The enemy appears.
                sbEnemyDigimon = Kaisa.ScreenBuilder.buildSprite("Enemy", parent)
                    .setSize(24, 24).flipHorizontal(true).center()
                    .setSprite(sEnemyDigimon[0]);
                rbEnemyDigimonInverted = Kaisa.ScreenBuilder.buildRectangle("Enemy inverted", parent)
                    .setSize(32, 32).setColor(true).setActive(false);
                Kaisa.ScreenBuilder.buildSprite("Enemy", rbEnemyDigimonInverted)
                    .setSize(24, 24).flipHorizontal(true).setPosition(4, 4)
                    .setInvertedSprite(sEnemyDigimon[1]);
                i = 0;
                pc = 13;
                return 0.0;
            case 13:                                // for (i = 0; i < 3; i++)
                if (i >= 3) { i = 0; pc = 16; return 0.0; }
                sbEnemyDigimon.setActive(false);
                pc = 14;
                return 0.25;
            case 14:
                sbEnemyDigimon.setActive(true);
                pc = 15;
                return 0.25;
            case 15:
                i += 1; pc = 13; return 0.0;
            case 16:
                sbEnemyDigimon.setSprite(sEnemyDigimon[1]);
                i = 0;
                pc = 17;
                return 0.0;
            case 17:                                // for (i = 0; i < 3; i++)
                if (i >= 3) { pc = 20; return 0.0; }
                rbEnemyDigimonInverted.setActive(false);
                pc = 18;
                return 0.25;
            case 18:
                rbEnemyDigimonInverted.setActive(true);
                pc = 19;
                return 0.25;
            case 19:
                i += 1; pc = 17; return 0.0;
            case 20:
                rbEnemyDigimonInverted.setActive(false);
                pc = 21;
                return 0.25;
            case 21:
                sbEnemyDigimon.setActive(false);
                group = 0;
                pc = 22;
                return 0.0;
            case 22:                                // four spirits at a time
                if (group >= stolenSpirits.size()) { pc = 30; return 0.1; }
                sbSpirit[0] = spiritAt(parent, "Spirit1", group, 1, 0);
                sbSpirit[1] = spiritAt(parent, "Spirit2", group + 1, 17, 0);
                sbSpirit[2] = spiritAt(parent, "Spirit3", group + 2, 1, 16);
                sbSpirit[3] = spiritAt(parent, "Spirit4", group + 3, 17, 16);
                pc = 23;
                return 0.4;
            case 23:
                gm.audioMgr.playSound("destroySpirits");
                sbSpirit[0].setSprite(Kaisa.Sprites.SPIRIT_EXPLOSION);
                pc = 24;
                return 0.2;
            case 24:
                sbSpirit[0].setSprite(Kaisa.Sprites.EMPTY_SPRITE);
                sbSpirit[3].setSprite(Kaisa.Sprites.SPIRIT_EXPLOSION);
                pc = 25;
                return 0.2;
            case 25:
                sbSpirit[3].setSprite(Kaisa.Sprites.EMPTY_SPRITE);
                sbSpirit[1].setSprite(Kaisa.Sprites.SPIRIT_EXPLOSION);
                pc = 26;
                return 0.2;
            case 26:
                sbSpirit[1].setSprite(Kaisa.Sprites.EMPTY_SPRITE);
                sbSpirit[2].setSprite(Kaisa.Sprites.SPIRIT_EXPLOSION);
                pc = 27;
                return 0.2;
            case 27:
                sbSpirit[2].setSprite(Kaisa.Sprites.EMPTY_SPRITE);
                group += 4;
                pc = 22;
                return 0.0;
            case 30:
                Kaisa.ScreenBuilder.clearAnimParent(parent);
                sbEnemyDigimon = Kaisa.ScreenBuilder.buildSprite("Enemy", parent)
                    .setSize(24, 24).flipHorizontal(true).center()
                    .setSprite(sEnemyDigimon[1]);
                pc = 31;
                return 0.4;
            case 31:
                sbEnemyDigimon.setSprite(sEnemyDigimon[0]);
                i = 0;
                pc = 32;
                return 0.25;
            case 32:                                // for (i = 0; i < 16; i++)
                if (i >= 16) { pc = 34; return 0.5; }
                sbEnemyDigimon.move(Kaisa.DIR_UP, 2);
                pc = 33;
                return 0.8 / 16;
            case 33:
                i += 1; pc = 32; return 0.0;
            case 34:
                return Routine.DONE;
        }
        return Routine.DONE;
    }

    // One of the four spirits in a group; the slots past the end of the list
    // draw the empty sprite, as the original's `?? emptySprite` does.
    function spiritAt(parent as ScreenElement, name as String, n as Number,
                      x as Number, y as Number) as SpriteBuilder {
        var ref = (n < stolenSpirits.size()) ? smallSpirit(n) : Kaisa.Sprites.EMPTY_SPRITE;
        return Kaisa.ScreenBuilder.buildSprite(name, parent)
            .setSize(14, 16).setPosition(x, y).setSprite(ref);
    }
}
