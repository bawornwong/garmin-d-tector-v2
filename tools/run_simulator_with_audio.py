#!/usr/bin/env python3
"""Run the debug app and mirror gameplay sounds with the source MP3s on macOS.

The Connect IQ simulator's ToneProfile backend can be silent on macOS even
when tonesOn is true. The watch app emits SIM_AUDIO lines only in debug
builds; this runner turns those lines into local afplay calls. It does not
change the release app or send audio anywhere.
"""

import argparse
import ast
import os
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parent.parent
MAP_SOURCE = ROOT / "tools" / "pack_sounds.py"


def sound_files():
    tree = ast.parse(MAP_SOURCE.read_text())
    for statement in tree.body:
        if isinstance(statement, ast.Assign) and any(
            isinstance(target, ast.Name) and target.id == "NAME_TO_FILE"
            for target in statement.targets
        ):
            return ast.literal_eval(statement.value)
    raise RuntimeError(f"NAME_TO_FILE missing in {MAP_SOURCE}")


def sdk_path():
    configured = os.environ.get("CIQ_SDK")
    if configured:
        return Path(configured)
    config = Path.home() / "Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg"
    return Path(config.read_text().strip())


def stop_player(player):
    if player is None or player.poll() is not None:
        return
    player.terminate()
    try:
        player.wait(timeout=1)
    except subprocess.TimeoutExpired:
        player.kill()
        player.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path,
                        help="checkout of kaisadilla/D-Tector-v2")
    parser.add_argument("--prg", type=Path, default=ROOT / "build/dtector-simulator.prg")
    parser.add_argument("--device", default="venu445mm")
    args = parser.parse_args()

    audio_dir = (args.source / "Assets/Audio").resolve()
    files = sound_files()
    missing = [name for name, relative in files.items()
               if not (audio_dir / relative).is_file()]
    if missing:
        parser.error(f"source MP3s missing for: {', '.join(missing)}")
    if not args.prg.is_file():
        parser.error(f"debug PRG missing: {args.prg}; run tools/build.sh first")
    monkeydo = sdk_path() / "bin/monkeydo"
    if not monkeydo.is_file():
        parser.error(f"monkeydo missing: {monkeydo}")

    print("Simulator must already be open. Use its Settings → Tones switch to"
          " silence native tones if they echo the MP3 preview.", flush=True)
    process = subprocess.Popen(
        [str(monkeydo), str(args.prg.resolve()), args.device],
        cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, bufsize=1,
    )
    player = None
    try:
        for raw_line in process.stdout:
            line = raw_line.rstrip("\n")
            if line == "SIM_AUDIO_STOP":
                stop_player(player)
                player = None
            elif line.startswith("SIM_AUDIO "):
                stop_player(player)
                player = None
                name = line[len("SIM_AUDIO "):]
                relative = files.get(name)
                if relative is None:
                    print(f"Unknown sound name: {name}", file=sys.stderr, flush=True)
                else:
                    player = subprocess.Popen(["/usr/bin/afplay", str(audio_dir / relative)])
                    print(f"Playing original sound: {name}", flush=True)
            else:
                print(line, flush=True)
    except KeyboardInterrupt:
        process.terminate()
    finally:
        stop_player(player)
        if process.poll() is None:
            process.terminate()
        process.wait()
    return process.returncode


if __name__ == "__main__":
    sys.exit(main())
