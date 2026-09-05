#!/usr/bin/env python3
"""Golden trace for the ticket 07 animation prototype.

A faithful transcription of three coroutines from Animations.cs, run with
Unity's coroutine semantics: execute statements, then WaitForSeconds before
the next resume. Emits (scheduled_ms, event) so the Monkey C state machines
can be diffed against it exactly.
"""
import sys

trace = []
now = 0.0


def emit(ev):
    trace.append((now, ev))


def wait(seconds):
    global now
    now += seconds


# --- CharHappyShort, Animations.cs:631 ------------------------------------
def char_happy_short():
    emit("sound charHappy")
    emit("build sprite CharHappy")
    emit("setSprite CharHappy charIdle")          # SetSprite(charIdle) on build
    for _ in range(2):
        emit("setSprite CharHappy charIdle")
        wait(0.5)
        emit("setSprite CharHappy charHappy")
        wait(0.5)
    emit("dispose CharHappy")


# --- CharHappy, Animations.cs:627 -----------------------------------------
def char_happy():
    char_happy_short()
    char_happy_short()


# --- LaunchAttack, Animations.cs:1916 -------------------------------------
def launch_attack(attack, is_enemy, disobeyed):
    launch_dir = "Right" if is_enemy else "Left"
    opposite = "Left" if is_enemy else "Right"
    emit("build sprite Attack")
    emit("setSize Attack 24 24")
    emit("center Attack")
    emit("build sprite Attacker")
    emit("setSize Attacker 24 24")
    emit("center Attacker")
    emit("setSprite Attacker digimon0")
    emit("setComponentSize Attack 24 24")
    emit("snapToSide Attack %s" % launch_dir)
    emit("flip Attacker %s" % str(is_enemy).lower())
    emit("flip Attack %s" % str(is_enemy).lower())

    extra_pixels = 0

    if attack != 3:
        if disobeyed:
            wait(0.1)
            emit("build sprite Disobey")
            emit("setSize Disobey 3 9")
            emit("setPosition Disobey 1 1")
            emit("setSprite Disobey battle_disobey")
            wait(0.3)
            emit("dispose Disobey")
        wait(0.2)
        emit("move Attacker %s 3" % opposite)
        emit("move Attack %s 3" % opposite)

    if attack == 0 or attack == 2:
        emit("setSprite Attacker digimon1")
        emit("setSprite Attack digimon%d" % (3 if attack == 0 else 4))
        # the wide-sprite branch needs a sprite wider than 32; not exercised here
        emit("sound launchAttack")
        for _ in range(38):
            wait(1.7 / 32.0)
            emit("move Attack %s" % launch_dir)
        for _ in range(extra_pixels):
            wait(1.7 / 32.0)
            emit("move Attack %s" % launch_dir)
        wait(0.3)
    elif attack == 1:
        emit("setSprite Attacker digimon2")
        emit("sound launchAttack")
        for i in range(7):
            emit("build sprite Crush%d" % i)
            emit("setSize Crush%d 24 24" % i)
            emit("center Crush%d" % i)
            emit("setSprite Crush%d digimon2" % i)
            emit("flip Crush%d %s" % (i, str(is_enemy).lower()))
            emit("move Crush%d %s %d" % (i, launch_dir, 4 * i))
            wait(0.9 / 7)
        wait(1.5)
    elif attack == 3:
        for _ in range(2):
            wait(0.65)
            emit("flip Attacker True")
            wait(0.65)
            emit("flip Attacker False")

    emit("clearAnimParent")


def run(name, fn, *args):
    global now, trace
    now = 0.0
    trace = []
    fn(*args)
    print("=== %s ===" % name)
    for t, ev in trace:
        print("%9.4f %s" % (t * 1000, ev))
    print("--- %s end=%.4fms events=%d" % (name, now * 1000, len(trace)))


if __name__ == "__main__":
    run("CharHappy", char_happy)
    run("LaunchAttack_a0", launch_attack, 0, False, False)
    run("LaunchAttack_a1_disobey", launch_attack, 1, True, True)
    run("LaunchAttack_a3", launch_attack, 3, False, False)
