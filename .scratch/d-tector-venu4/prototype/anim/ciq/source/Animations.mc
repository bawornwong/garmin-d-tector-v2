import Toybox.Lang;

// Transforms of three coroutines from Animations.cs, picked because they are
// structurally different: a short linear one, one with a computed loop and
// nested branches, and one that calls another coroutine.

// port of Animations.cs:631  CharHappyShort
class CharHappyShort extends Routine {
    var i as Number = 0;

    function initialize() { Routine.initialize(); }

    function step(rt as Runner) as Float {
        switch (pc) {
            case 0:
                // Sprite charIdle = gm.PlayerCharSprites[0];
                // Sprite charHappy = gm.PlayerCharSprites[6];
                rt.emit("sound charHappy");
                rt.emit("build sprite CharHappy");
                rt.emit("setSprite CharHappy charIdle");
                i = 0;
                pc = 1;
                return 0.0;
            case 1:                                    // for (i = 0; i < 2; i++)
                if (i >= 2) { pc = 4; return 0.0; }
                rt.emit("setSprite CharHappy charIdle");
                pc = 2;
                return 0.5;                            // yield 0.5f
            case 2:
                rt.emit("setSprite CharHappy charHappy");
                pc = 3;
                return 0.5;                            // yield 0.5f
            case 3:
                i += 1;
                pc = 1;
                return 0.0;
            case 4:
                rt.emit("dispose CharHappy");
                return -1.0;
        }
        return -1.0;
    }
}

// port of Animations.cs:627  CharHappy
class CharHappy extends Routine {
    function initialize() { Routine.initialize(); }

    function step(rt as Runner) as Float {
        switch (pc) {
            case 0:
                pc = 1;
                rt.call(new CharHappyShort());         // yield return CharHappyShort()
                return 0.0;
            case 1:
                pc = 2;
                rt.call(new CharHappyShort());         // yield return CharHappyShort()
                return 0.0;
            case 2:
                return -1.0;
        }
        return -1.0;
    }
}

// port of Animations.cs:1916  LaunchAttack
class LaunchAttack extends Routine {
    var attack as Number;
    var isEnemy as Boolean;
    var disobeyed as Boolean;

    var launchDir as String = "";
    var opposite as String = "";
    var extraPixels as Number = 0;
    var i as Number = 0;

    function initialize(attackIn as Number, isEnemyIn as Boolean, disobeyedIn as Boolean) {
        Routine.initialize();
        attack = attackIn;
        isEnemy = isEnemyIn;
        disobeyed = disobeyedIn;
    }

    function step(rt as Runner) as Float {
        switch (pc) {
            case 0:
                launchDir = isEnemy ? "Right" : "Left";
                opposite = isEnemy ? "Left" : "Right";
                rt.emit("build sprite Attack");
                rt.emit("setSize Attack 24 24");
                rt.emit("center Attack");
                rt.emit("build sprite Attacker");
                rt.emit("setSize Attacker 24 24");
                rt.emit("center Attacker");
                rt.emit("setSprite Attacker digimon0");
                rt.emit("setComponentSize Attack 24 24");
                rt.emit("snapToSide Attack " + launchDir);
                rt.emit("flip Attacker " + isEnemy);
                rt.emit("flip Attack " + isEnemy);
                extraPixels = 0;

                if (attack != 3) {
                    if (disobeyed) {
                        pc = 1;
                        return 0.1;                    // yield 0.1f
                    }
                    pc = 3;
                    return 0.2;                        // yield 0.2f
                }
                pc = 4;
                return 0.0;

            case 1:                                    // disobeyed branch
                rt.emit("build sprite Disobey");
                rt.emit("setSize Disobey 3 9");
                rt.emit("setPosition Disobey 1 1");
                rt.emit("setSprite Disobey battle_disobey");
                pc = 2;
                return 0.3;                            // yield 0.3f
            case 2:
                rt.emit("dispose Disobey");
                pc = 3;
                return 0.2;                            // yield 0.2f
            case 3:
                rt.emit("move Attacker " + opposite + " 3");
                rt.emit("move Attack " + opposite + " 3");
                pc = 4;
                return 0.0;

            case 4:                                    // dispatch on attack
                if (attack == 0 || attack == 2) {
                    rt.emit("setSprite Attacker digimon1");
                    rt.emit("setSprite Attack digimon" + ((attack == 0) ? 3 : 4));
                    rt.emit("sound launchAttack");
                    i = 0;
                    pc = 5;
                    return 0.0;
                } else if (attack == 1) {
                    rt.emit("setSprite Attacker digimon2");
                    rt.emit("sound launchAttack");
                    i = 0;
                    pc = 8;
                    return 0.0;
                } else if (attack == 3) {
                    i = 0;
                    pc = 10;
                    return 0.0;
                }
                pc = 99;
                return 0.0;

            case 5:                                    // for (i = 0; i < 38; i++)
                if (i >= 38) { i = 0; pc = 6; return 0.0; }
                pc = 51;
                return 1.7 / 32.0;                     // yield 1.7f / 32f
            case 51:
                rt.emit("move Attack " + launchDir);
                i += 1;
                pc = 5;
                return 0.0;
            case 6:                                    // for (i = 0; i < extraPixels; i++)
                if (i >= extraPixels) { pc = 7; return 0.3; }   // then yield 0.3f
                pc = 61;
                return 1.7 / 32.0;
            case 61:
                rt.emit("move Attack " + launchDir);
                i += 1;
                pc = 6;
                return 0.0;
            case 7:
                pc = 99;
                return 0.0;

            case 8:                                    // for (i = 0; i < 7; i++)
                if (i >= 7) { pc = 9; return 1.5; }    // then yield 1.5f
                rt.emit("build sprite Crush" + i);
                rt.emit("setSize Crush" + i + " 24 24");
                rt.emit("center Crush" + i);
                rt.emit("setSprite Crush" + i + " digimon2");
                rt.emit("flip Crush" + i + " " + isEnemy);
                rt.emit("move Crush" + i + " " + launchDir + " " + (4 * i));
                i += 1;
                pc = 8;
                return 0.9 / 7.0;                      // yield 0.9f / 7
            case 9:
                pc = 99;
                return 0.0;

            case 10:                                   // for (i = 0; i < 2; i++)
                if (i >= 2) { pc = 99; return 0.0; }
                pc = 11;
                return 0.65;                           // yield 0.65f
            case 11:
                rt.emit("flip Attacker True");
                pc = 12;
                return 0.65;                           // yield 0.65f
            case 12:
                rt.emit("flip Attacker False");
                i += 1;
                pc = 10;
                return 0.0;

            case 99:
                rt.emit("clearAnimParent");
                return -1.0;
        }
        return -1.0;
    }
}
