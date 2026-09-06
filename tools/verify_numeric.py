#!/usr/bin/env python3
"""Run the numeric parity sweep on both sides and diff it.

Ticket 14 proved the port's numeric rules on four formulas. This is the same
check as a repeatable tool, over every formula in Logic/Models/Digimon.cs
whose result a rounding boundary can move -- and over the real code on both
sides, which is the part that makes it worth running:

  - the C# side compiles the ORIGINAL Digimon.cs (tools/numeric/numeric.csproj
    pulls it straight out of $DTECTOR_SRC) against a shim that provides only
    Mathf and the one Database method it references
  - the Monkey C side compiles the PORTED app/source/Logic/Digimon.mc, pulled
    in by tools/numeric/ciq/monkey.jungle's sourcePath

Neither side is a transcription of the formulas, so a mismatch is a real
behaviour difference rather than a typo in the test (ADR 12).

Float results are compared as IEEE-754 bit patterns: a decimal rendering
would hide the one-ULP difference the check exists to catch, since a ULP is
what crosses a floor boundary in the level and stat formulas.

Usage:
    DTECTOR_SRC=/path/to/D-Tector-v2 tools/verify_numeric.py

Takes a few minutes: the simulator prints about 16,000 lines through the
console at 250 lines per 50 ms tick.
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SDK = os.environ.get(
    "CIQ_SDK",
    os.path.expanduser("~/Library/Application Support/Garmin/ConnectIQ/Sdks/"
                       "connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2"))
KEY = os.environ.get("CIQ_KEY", os.path.join(ROOT, ".scratch/keys/developer_key.der"))
DOTNET = os.environ.get("DOTNET", os.path.expanduser("~/.dotnet/dotnet"))
DEVICE = "venu445mm"


def run(cmd, **kw):
    return subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, **kw)


def csharp_side(out_dir):
    src = os.environ.get("DTECTOR_SRC")
    if not src or not os.path.isdir(src):
        raise SystemExit("set DTECTOR_SRC to a checkout of kaisadilla/D-Tector-v2")
    r = run([DOTNET, "run", "--project", "tools/numeric", "-v", "q"])
    if r.returncode != 0:
        raise SystemExit("C# sweep failed:\n" + r.stdout + r.stderr)
    path = os.path.join(out_dir, "gold_num.txt")
    open(path, "w").write(r.stdout)
    return path


def monkeyc_side(out_dir):
    prg = os.path.join(out_dir, "numsweep.prg")
    r = run([os.path.join(SDK, "bin/monkeyc"),
             "-f", "tools/numeric/ciq/monkey.jungle", "-o", prg,
             "-y", KEY, "-d", DEVICE, "-w"])
    if r.returncode != 0:
        raise SystemExit("Monkey C sweep build failed:\n" + r.stdout + r.stderr)
    # monkeydo needs the simulator already running (tools/build.sh's usual
    # companion: "$SDK/bin/connectiq" &)
    r = run([os.path.join(SDK, "bin/monkeydo"), prg, DEVICE], timeout=900)
    path = os.path.join(out_dir, "ciq_num.txt")
    open(path, "w").write(r.stdout + r.stderr)
    return path


def main():
    out_dir = os.environ.get("TMPDIR", "/tmp")
    gold = csharp_side(out_dir)
    got = monkeyc_side(out_dir)

    a = open(gold).read().splitlines()
    b = [l for l in open(got).read().splitlines() if l.strip() != ""]

    if not b or b[-1] != "END":
        raise SystemExit(f"the Monkey C sweep did not finish: {len(b)} lines, "
                         f"last {b[-1] if b else '(none)'!r}")

    bad = []
    for i in range(max(len(a), len(b))):
        x = a[i] if i < len(a) else "(missing)"
        y = b[i] if i < len(b) else "(missing)"
        if x != y:
            bad.append((i + 1, x, y))

    for line, x, y in bad[:20]:
        print(f"  line {line}: C# {x!r} != Monkey C {y!r}")
    if len(bad) > 20:
        print(f"  ... and {len(bad) - 20} more")
    print(f"{len(a) - len(bad)}/{len(a)} values match")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
