#!/usr/bin/env python3
"""Drive each app through a press sequence in the RELEASE build and report
crashes.

Why this exists: everything else in tools/ diffs the port against the
original. Nothing ran the build that actually goes on the watch. Release is
where `(:debug)` code is gone, where sound is not muted, and where an
exception is a crash rather than a caught surprise -- and the first time it
was run end to end it found two crashes in an afternoon, both reachable in
ordinary play:

  - choosing an empty D-Dock in a battle (Array Out Of Bounds, an index of -1
    reaching SavedGame.digimonLevel)
  - the Status app after a few presses (Invalid Value: a garbage sprite ref
    read past the end of the packed table, dividing by its own zero width)

Both came from the same root: ADR 7 turns the original's name keys into array
indices, and an out-of-range index does not "miss" the way a dictionary
lookup does. It reads whatever is there.

The verifiers cannot see any of this. They compare traces of one animation at
a time, from a fixed probe state, with input never touching the app.

Usage:
  tools/smoke_apps.py              # every app
  tools/smoke_apps.py Status Maze  # just these

Each app is patched in via _sliceApp, built for release, and driven by
_probeInputs. DTectorView.mc is restored afterwards, including on failure.
The simulator is restarted per app: it wedges after a few runs and then
produces no output at all, which is why a run that yields too few presses is
reported as INCONCLUSIVE rather than as a pass -- silence is not success.
"""
import os
import re
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VIEW = os.path.join(ROOT, "app/source/DTectorView.mc")
SDK = os.environ.get(
    "CIQ_SDK",
    os.path.expanduser("~/Library/Application Support/Garmin/ConnectIQ/Sdks/"
                       "connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2"))

# A, RIGHT, B, LEFT mixed: enough to open menus, page screens, pick entries and
# back out again. Deliberately not a scripted "correct" tour -- the point is to
# hit paths a tour would avoid.
SEQUENCE = "0,9,0,3,9,9,0,0,3,6,9,0,3,0,9,9,9,0,3,3,0,6,0,9,0,3,0,0,9,3,6,0,9,0"
MIN_PRESSES = 5

# label -> how DTectorView should open it. None means the game's own start.
APPS = [
    ("NormalStart", None),
    ("Database", "APP_DATABASE"),
    ("Status", "APP_STATUS"),
    ("Camp", "APP_CAMP"),
    ("Map", "APP_MAP"),
    ("CodeInput", "APP_CODE_INPUT"),
    ("Finder", "APP_FINDER"),
    ("DigiHunter", "APP_DIGI_HUNTER"),
    ("SpeedRunner", "APP_SPEED_RUNNER"),
    ("Maze", "APP_MAZE"),
    ("JackpotBox", "APP_JACKPOT_BOX"),
    ("Battle", "BATTLE"),      # no menu entry; started like an event does
]


def patch(app_const, pristine):
    # Always start from the untouched file: the _sliceApp == 3 branch is the
    # anchor every app after the first is patched into, and patching an
    # already-patched file cannot find it.
    src = pristine
    src = re.sub(r"var _probeInputs as Array<Number> = \[[^\]]*\];",
                 f"var _probeInputs as Array<Number> = [{SEQUENCE}];", src, count=1)
    if app_const == "BATTLE":
        src = re.sub(r"var _sliceApp as Number = \d+;",
                     "var _sliceApp as Number = 4;", src, count=1)
    elif app_const:
        src = re.sub(r"var _sliceApp as Number = \d+;",
                     "var _sliceApp as Number = 3;", src, count=1)
        src = src.replace(
            "        } else if (_sliceApp == 3) {\n"
            "            _gm.logicMgr.openApp(Kaisa.APP_CAMP);",
            "        } else if (_sliceApp == 3) {\n"
            f"            _gm.logicMgr.openApp(Kaisa.{app_const});", 1)
        if f"Kaisa.{app_const}" not in src:
            raise SystemExit(f"could not patch in {app_const} -- did DTectorView change?")
    open(VIEW, "w").write(src)


def restart_simulator():
    subprocess.run(["pkill", "-f", "ConnectIQ.app"], capture_output=True)
    subprocess.run(["pkill", "-f", "monkeydo"], capture_output=True)
    time.sleep(2)
    subprocess.Popen([os.path.join(SDK, "bin/connectiq")],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(8)


def run_one(label, app_const, pristine):
    patch(app_const, pristine)
    build = subprocess.run([os.path.join(ROOT, "tools/build.sh"), "-r"],
                           capture_output=True, text=True, cwd=ROOT)
    if "BUILD SUCCESSFUL" not in build.stdout:
        return f"{label:12s} BUILD FAILED", False
    restart_simulator()
    run = subprocess.run(
        ["timeout", "100", os.path.join(SDK, "bin/monkeydo"),
         "build/dtector.prg", "venu445mm"],
        capture_output=True, text=True, cwd=ROOT)
    out = run.stdout + run.stderr
    presses = out.count("SMOKE")
    if "Error:" in out or "crash" in out:
        detail = out[out.find("Error:"):][:600]
        return f"{label:12s} CRASH after {presses} presses\n{detail}", False
    if presses < MIN_PRESSES:
        # Silence is not success: the simulator wedges and prints nothing.
        return f"{label:12s} INCONCLUSIVE ({presses} presses -- simulator wedged?)", False
    return f"{label:12s} ok ({presses} presses)", True


def main():
    wanted = sys.argv[1:]
    todo = [(l, a) for l, a in APPS if not wanted or l in wanted]
    if not todo:
        raise SystemExit(f"no such app; known: {', '.join(l for l, _ in APPS)}")

    backup = VIEW + ".smokebak"
    shutil.copy(VIEW, backup)
    pristine = open(backup).read()
    ok = True
    try:
        for label, app_const in todo:
            line, passed = run_one(label, app_const, pristine)
            print(line, flush=True)
            ok = ok and passed
    finally:
        shutil.move(backup, VIEW)
        print("DTectorView.mc restored")
    raise SystemExit(0 if ok else 1)


if __name__ == "__main__":
    main()
