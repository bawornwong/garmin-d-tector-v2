#!/usr/bin/env python3
"""Diff what an app's screens BUILD against what the original's do.

The animation goldens (tools/verify_anim.py) prove that a coroutine mutates
the display in the same order as the original. They say nothing about the
screens an app draws between animations -- whether the level really lands on
the level screen, right-aligned, in the right box.

This closes that: the ORIGINAL Status.cs is compiled into the golden harness
(tools/anim_golden) against the same display-list stubs, walked through its
seven screens with its own InputRight, and traced. The port draws the same
seven with the same numbers -- AppFixture in the harness pins them, and
DTectorView._probeScreens writes them into the save record -- and the two
traces are diffed event for event.

Usage: DTECTOR_SRC=... tools/verify_screens.py
"""
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from verify_anim import (DEVICE, DOTNET, ROOT, SDK, VIEW, normalise, reap,
                         restart_simulator, sprite_cells)


def golden():
    """{screen: [lines]} from the harness, which traces Status's screens."""
    src = os.environ.get("DTECTOR_SRC")
    if not src or not os.path.isdir(src):
        raise SystemExit("set DTECTOR_SRC to a checkout of kaisadilla/D-Tector-v2")
    r = subprocess.run([DOTNET, "run", "--project", "tools/anim_golden", "-v", "q"],
                       cwd=ROOT, capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit("the golden harness failed:\n" + r.stdout + r.stderr)

    out, current = {}, None
    for line in r.stdout.splitlines():
        m = re.match(r"=== (Status\d|DatabasePage\d|Map\w+|Battle\w+|CodeInput\w+|DigiHunter\w+) ===$", line)
        if m:
            current = m.group(1)
            out[current] = []
            continue
        if line.startswith("---"):
            current = None
            continue
        if current:
            out[current].append(line)
    return out


def port(attempts=3):
    """{screen: [lines]} from the app running in the simulator."""
    text = open(VIEW).read()
    patched = re.sub(r"var _probeScreens as Boolean = \w+;",
                     "var _probeScreens as Boolean = true;", text)
    open(VIEW, "w").write(patched)
    try:
        b = subprocess.run(["tools/build.sh"], cwd=ROOT, capture_output=True, text=True)
        if b.returncode != 0:
            raise SystemExit("build failed:\n" + b.stdout + b.stderr)
        for _ in range(attempts):
            try:
                r = subprocess.run([os.path.join(SDK, "bin/monkeydo"),
                                    "build/dtector.prg", DEVICE],
                                   cwd=ROOT, capture_output=True, text=True, timeout=120)
                lines = (r.stdout + r.stderr).splitlines()
            except subprocess.TimeoutExpired as e:
                lines = ((e.stdout or b"").decode()
                         + (e.stderr or b"").decode()).splitlines()
            reap()
            out, current = {}, None
            for line in lines:
                m = re.match(r"=== (Status\d|DatabasePage\d|Map\w+|Battle\w+|CodeInput\w+|DigiHunter\w+) ===$", line)
                if m:
                    current = m.group(1)
                    out[current] = []
                    continue
                if line.startswith("---") or line.strip() == "SCREENEND":
                    current = None
                    continue
                if current:
                    out[current].append(line)
            if out:
                return out
            restart_simulator()
        return {}
    finally:
        open(VIEW, "w").write(text)


def drop_queue_start(events):
    """Drop the fiber start that follows an enqueue in the port's stream.

    The original queues an animation and a long-lived coroutine consumes it;
    the port starts the fiber there and then when nothing else is playing
    (ADR 4). Same animation, one extra event, and it is the runner's rather
    than the screen's -- so the enqueue is compared and the start that belongs
    to it is not.
    """
    out = []
    for t, ev in events:
        if ev == "startCoroutine" and out and out[-1][1] == "enqueueAnimation":
            continue
        out.append((t, ev))
    return out


def main():
    cells = sprite_cells()
    want, got = golden(), port()
    if not got:
        raise SystemExit("the app emitted nothing: is the simulator running?")

    failures = 0
    for name in sorted(want):
        a = normalise(want[name], cells)
        b = drop_queue_start(normalise(got.get(name, []), cells))
        bad = []
        for i in range(max(len(a), len(b))):
            x = a[i] if i < len(a) else ("-", "(missing)")
            y = b[i] if i < len(b) else ("-", "(missing)")
            if x != y:
                bad.append((i + 1, x, y))
        if bad:
            failures += 1
            print(f"{name}: {len(a) - len(bad)}/{len(a)} events match")
            for i, x, y in bad[:10]:
                print(f"  event {i}: original {x[0]} {x[1]!r}")
                print(f"            port     {y[0]} {y[1]!r}")
            if len(bad) > 10:
                print(f"  ... and {len(bad) - 10} more")
        else:
            print(f"{name}: {len(a)}/{len(a)} events match")

    print(f"{len(want) - failures}/{len(want)} screens match")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
