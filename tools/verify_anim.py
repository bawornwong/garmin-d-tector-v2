#!/usr/bin/env python3
"""Diff a converted animation against a golden trace of the original.

ADR 4 turns each of Animations.cs's 60 coroutines into a class with a `pc`.
Ticket 08's rule for calling one correct: the events, their arguments and
their scheduled times all match the original's. This runs both sides and
diffs them.

  - the reference compiles the ORIGINAL Logic/Data/Animations.cs (tools/
    anim_golden pulls it out of $DTECTOR_SRC) against display-list stubs, and
    executes it with Unity's coroutine semantics -- including parallel
    StartCoroutine fibers, interleaved by scheduled time
  - the port runs the converted routine in the simulator through the REAL
    display list and the real runner, with the debug trace on. Nothing in the
    port is written for the benefit of this check: the events come out of the
    builders every screen already uses.

Two normalisations, both mechanical:

  - a sprite prints by name, and several SpriteDatabase fields are wired to
    the SAME cell in the Unity scene (`animDistance` and `games_distance` are
    one sprite). Names are therefore canonicalised to the cell they resolve
    to, using the table tools/pack_ui_sprites.py generates.
  - the port's trace carries the host's own container ("Anim Parent"), which
    ScreenManager builds around the animation and the reference has no
    counterpart for. Those lines are dropped.

Usage:
    DTECTOR_SRC=/path/to/D-Tector-v2 tools/verify_anim.py [name ...]

With no names, checks every animation the port has converted.
"""
import json
import os
import re
import subprocess
import time
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SDK = os.environ.get(
    "CIQ_SDK",
    os.path.expanduser("~/Library/Application Support/Garmin/ConnectIQ/Sdks/"
                       "connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2"))
DOTNET = os.environ.get("DOTNET", os.path.expanduser("~/.dotnet/dotnet"))
DEVICE = "venu445mm"
VIEW = os.path.join(ROOT, "app/source/DTectorView.mc")
SPRITE_DB = os.path.join(ROOT, "app/source/Render/SpriteDatabase.mc")

# The probe index DTectorView._probeAnim uses for each converted animation.
CONVERTED = {
    "ChangeDistance": 0,
    "RewardEmpty": 1,
    "PaySpiritPower": 2,
    "AWardSpiritPower": 3,
    "CharHappyShort": 4,
    "CharHappy": 5,
    "OpenCamp": 6,
    "CloseCamp": 7,
    "SwapDDock": 8,
    "LaunchAttack": 9,
}

HOST_ELEMENTS = ("Anim Parent",)


# The reference names a Digimon sprite `agumon` or `agumon:Crush`; the packed
# index keys the same art `Digimon/agumon` and `Digimon/agumon_cr`.
ACTION_SUFFIX = {"Default": "", "Attack": "_at", "Crush": "_cr", "Spirit": "_sp",
                 "SpiritSmall": "_sm", "Black": "_bl", "White": "_wh"}
ATLAS_CLASS = {"atlas_24x24": 0, "atlas_32x32": 1, "atlas_14x16": 2, "atlas_odd": 3}


def sprite_cells():
    """Every name either side can print -> "cell(cls,x,y)".

    Two sources: the generated UI table (SpriteDatabase field names) and the
    sprite index (Digimon art). Canonicalising to the cell is what makes the
    diff immune to a sprite having two names -- `animDistance` and
    `games_distance` are wired to one cell in the Unity scene.
    """
    out = {}
    text = open(SPRITE_DB).read()
    for name, cls, x, y in re.findall(r'\["(\w+)", (\d+), (\d+), (\d+)\]', text):
        out[name] = f"cell({cls},{x},{y})"

    index = json.load(open(os.path.join(ROOT, "build/sprite_index.json")))["sprites"]
    for key, e in index.items():
        cell = f"cell({ATLAS_CLASS[e['atlas']]},{e['x']},{e['y']})"
        # The reference prints the index key itself now that its stub resolves
        # sprites the way Resources.Load does ("Digimon/agumon_at").
        out[key] = cell
        if key.startswith("Digimon/"):
            base = key[len("Digimon/"):]
            out[base] = cell
            for action, suffix in ACTION_SUFFIX.items():
                if suffix and base.endswith(suffix):
                    out[base[: -len(suffix)] + ":" + action] = cell
    return out


def normalise(lines, cells):
    """(time, event) pairs, with sprite names canonicalised and host lines out."""
    out = []
    for line in lines:
        m = re.match(r"\s*([\d.]+)\s+(.*)$", line)
        if not m:
            continue
        t, ev = m.group(1), m.group(2).rstrip()
        if any((" " + h) in ev or ev.endswith(h) for h in HOST_ELEMENTS):
            continue
        if ev.startswith("setSprite "):
            head, _, sprite = ev.rpartition(" ")
            # The port prints `sprite(cls,x,y)` for art the debug name table
            # does not carry (every Digimon sprite); that IS the cell.
            m2 = re.fullmatch(r"sprite\((\d+),(\d+),(\d+)\)", sprite)
            if m2:
                sprite = f"cell({m2.group(1)},{m2.group(2)},{m2.group(3)})"
            else:
                sprite = cells.get(sprite, sprite)
            ev = head + " " + sprite
        out.append((float(t), ev))
    return out


def golden(names):
    """{name: [lines]} from the C# harness, which traces every coroutine."""
    src = os.environ.get("DTECTOR_SRC")
    if not src or not os.path.isdir(src):
        raise SystemExit("set DTECTOR_SRC to a checkout of kaisadilla/D-Tector-v2")
    r = subprocess.run([DOTNET, "run", "--project", "tools/anim_golden", "-v", "q"],
                       cwd=ROOT, capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit("the golden harness failed:\n" + r.stdout + r.stderr)

    out, current = {}, None
    for line in r.stdout.splitlines():
        m = re.match(r"=== (\w+) ===$", line)
        if m:
            current = m.group(1) if m.group(1) in names else None
            if current:
                out[current] = []
            continue
        if current is None or line.startswith("---"):
            continue
        out[current].append(line)
    return out


def run_probe(index, attempts=3):
    """Build the app with _probeAnim = index, run it, return its trace lines."""
    text = open(VIEW).read()
    patched = re.sub(r"var _probeAnim as Number = -?\d+;",
                     f"var _probeAnim as Number = {index};", text)
    open(VIEW, "w").write(patched)
    try:
        b = subprocess.run(["tools/build.sh"], cwd=ROOT, capture_output=True, text=True)
        if b.returncode != 0:
            raise SystemExit("build failed:\n" + b.stdout + b.stderr)
        # The simulator drops a launch now and then -- it is not ready for the
        # next app the instant the last one exited -- and a dropped launch
        # looks exactly like an animation that emitted nothing. Retrying is
        # the difference between a real diff and a flake.
        for attempt in range(attempts):
            try:
                r = subprocess.run([os.path.join(SDK, "bin/monkeydo"),
                                    "build/dtector.prg", DEVICE],
                                   cwd=ROOT, capture_output=True, text=True,
                                   timeout=120)
                lines = (r.stdout + r.stderr).splitlines()
            except subprocess.TimeoutExpired as e:
                lines = ((e.stdout or b"").decode()
                         + (e.stderr or b"").decode()).splitlines()
            out = trace_of(lines)
            if out:
                return out
            time.sleep(3)
        return []
    finally:
        open(VIEW, "w").write(text)


def trace_of(lines):
    """The probe's own events: what it printed between its banner and ANIMEND."""
    started, out = False, []
    for line in lines:
        if line.startswith("==="):
            started = True
            continue
        if line.strip() == "ANIMEND":
            break
        if started:
            out.append(line)
    return out


def main():
    names = sys.argv[1:] or sorted(CONVERTED)
    unknown = [n for n in names if n not in CONVERTED]
    if unknown:
        raise SystemExit(f"not converted yet: {', '.join(unknown)}")

    cells = sprite_cells()
    goldens = golden(set(names))

    failures = 0
    for name in names:
        want = normalise(goldens.get(name, []), cells)
        got = normalise(run_probe(CONVERTED[name]), cells)

        bad = []
        for i in range(max(len(want), len(got))):
            a = want[i] if i < len(want) else ("-", "(missing)")
            b = got[i] if i < len(got) else ("-", "(missing)")
            if a != b:
                bad.append((i + 1, a, b))

        if bad:
            failures += 1
            print(f"{name}: {len(want) - len(bad)}/{len(want)} events match")
            for i, a, b in bad[:10]:
                print(f"  event {i}: original {a[0]} {a[1]!r}")
                print(f"            port     {b[0]} {b[1]!r}")
            if len(bad) > 10:
                print(f"  ... and {len(bad) - 10} more")
        else:
            end = want[-1][0] if want else 0.0
            print(f"{name}: {len(want)}/{len(want)} events match, "
                  f"end={end:.4f}ms")

    print(f"{len(names) - failures}/{len(names)} animations match")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
