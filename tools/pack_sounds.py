#!/usr/bin/env python3
"""Sound extractor. Implements ticket 03 of the sound-and-vibration map
(.scratch/sound-and-vibration/issues/03-sound-extractor.md).

The source's 51 sounds are monophonic square waves (measured: a source tone's
loudest partial is often a harmonic, not the fundamental -- e.g.
Battle/encounter_regular.mp3's loudest partial is 5464 Hz, the 5th harmonic of
a 1094 Hz fundamental). A square wave's harmonics fall off as 1/n, so the
fundamental is reliably the LOWEST spectral peak that clears a noise floor --
that is the estimator here, not a full harmonic-product-spectrum search,
which degrades on the button beeps that carry no harmonics at all (a single
peak with nothing below it to rank against).

Pipeline per sound:
  1. Decode to mono float32 PCM at 22050 Hz (ffmpeg).
  2. Per 30ms frame (10ms hop): RMS for silence, then the lowest spectral
     peak clearing a noise floor as that frame's fundamental.
  3. Collapse the frame track into (frequency, duration) notes: a rest ends a
     note; a frequency jump beyond a tolerance starts a new one; runs shorter
     than MIN_NOTE_MS get folded into a neighbour rather than kept as noise.
  4. Round-trip: re-classify every ACTIVE frame in the original signal against
     the note that covers it and report the percentage within tolerance. This
     is the number that answers "reproduction or approximation" -- printed
     per sound, not asserted once for all 40.

Outputs:
  app/source/Data/SoundData.mc  -- GENERATED, one note table per sound plus
                                    the name -> index dictionary the port's
                                    call sites resolve through
  build/sound_index.json        -- the same data, for inspection/diffing
"""
import base64
import json
import os
import re
import struct
import subprocess
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import src, app as app_path

BUILD = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "build")
APP_SRC = app_path("source")

SR = 22050
HOP_S = 0.010
WIN_S = 0.030
HOP = int(SR * HOP_S)
WIN = int(SR * WIN_S)
FFT_N = 4096

# Silence: a frame's RMS below this fraction of the whole clip's peak RMS is a
# rest. Peak picking: a local maximum below this fraction of the frame's own
# peak magnitude is noise, not a partial.
SILENCE_REL = 0.06
PEAK_REL = 0.20
# Two frames are the same note if their fundamentals are within this ratio
# (a semitone is ~5.9%; this is looser, since these are synth tones with
# audible vibrato/drift, not a tuned instrument).
NOTE_TOLERANCE = 0.08
MIN_NOTE_MS = 20
ROUND_TRIP_TOLERANCE = 0.08

# Resolved once, by hand, from two primary sources cross-checked against each
# other: DigiviceFrontier.unity's AudioManager MonoBehaviour (component
# 2122903411) binds each field to an asset GUID, and each asset's .meta file
# states that GUID -- so this table is a GUID join, not a guess from
# filenames. The key is exactly the string every port call site already
# passes to playSound(), or the port's name for playButtonA/B and
# playCharHappy/Sad's fixed sounds.
#
# Five AudioManager fields resolve to a real asset but are never reached by
# any PlaySound call anywhere in the source's own Scripts/ (verified by grep
# against the checkout, not assumed): charHappyLong, charSadLong,
# attackTravel, attackTravelLong, evolutionArmor. The port correctly has no
# call sites for any of them, and they are deliberately absent below.
#
# Six more source MP3s aren't wired to any AudioManager field at all:
# "UNUSED get_digimon.mp3" and "Battle/Change boss.mp3" say so in their own
# names; Battle/attack_travel_and_explode.mp3 and
# Battle/attack_travel_long_2x.mp3 are unused variants of attack_travel_*;
# punishment.mp3 and unlock_code.mp3 are unused variants superseded by
# punishment2.mp3 and unlock_code_long.mp3, which the wired fields actually
# point at. All 51 source files are accounted for: 40 reachable, 11 dead
# (5 orphaned fields + 6 unwired files), 0 unexplained.
NAME_TO_FILE = {
    "buttonA": "button_a.mp3",
    "buttonB": "button_b.mp3",
    "charHappy": "char_happy.mp3",
    "charSad": "char_sad.mp3",
    "unpleasantBeep": "unpleasant_beep.mp3",
    "gameStart": "game_start.mp3",
    "summonDigimon": "summon_digimon.mp3",
    "unlockDigimon": "unlock_digimon.mp3",
    "unlockCode": "unlock_code_long.mp3",
    "loseDigimon": "lose_digimon.mp3",
    "levelUp": "level_up.mp3",
    "levelDown": "level_down_alt.mp3",
    "reward": "reward.mp3",
    "punishment": "punishment2.mp3",
    "triggerEvent": "event.mp3",
    "travelMap": "map_travel.mp3",
    "digistorm": "digistorm.mp3",
    "changeDock": "change_dock.mp3",
    "encounterDigimon": "Battle/encounter_regular.mp3",
    "encounterDigimonBoss": "Battle/encounter_boss.mp3",
    "launchAttack": "Battle/launch_attack.mp3",
    "launchAttackLong": "Battle/launch_attack_long.mp3",
    "attackTravelVeryLong": "Battle/attack_travel_eternal.mp3",
    "explosion": "Battle/explode.mp3",
    "deport": "Battle/deport_digimon.mp3",
    "deportSpirit": "Battle/deport_spirit.mp3",
    "evolutionRegular": "Battle/evolve_regular.mp3",
    "evolutionSpirit": "Battle/evolve_spirit.mp3",
    "evolutionAncient": "Battle/evolve_ancient.mp3",
    "digiPowerFailed": "Battle/digipower_failed.mp3",
    "digiPowerSucceed": "Battle/digipower_succeed.mp3",
    "levelDownDigimon": "level_down_digimon.mp3",
    "beepLow": "beep_low.mp3",
    "speedRunner_Start": "Game/Speed Runner/rocket_start.mp3",
    "speedRunner_Asteroid": "Game/Speed Runner/rocket_asteroid.mp3",
    "speedRunner_Finish": "Game/Speed Runner/rocket_goal.mp3",
    "speedRunner_Crash": "Game/Speed Runner/rocket_crash.mp3",
    "digiHunter_Start": "Game/DigiHunter/digihunter_start.mp3",
    "stealAllSpirits": "steal_all_spirits.mp3",
    "destroySpirits": "destroy_spirits.mp3",
}


def load_mono(path):
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"],
        capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32)


def frame_fundamentals(x):
    """Per-frame (rms, freq_or_none) using the lowest peak that clears the
    noise floor -- see the module docstring for why this beats HPS here."""
    if x.size == 0:
        return []
    peak_rms = 0.0
    frames = list(range(0, max(1, len(x) - WIN), HOP)) or [0]
    windows = np.hanning(WIN)
    raw = []
    for i in frames:
        seg = x[i:i + WIN]
        if len(seg) < WIN:
            seg = np.pad(seg, (0, WIN - len(seg)))
        seg = seg * windows
        rms = float(np.sqrt((seg ** 2).mean()))
        peak_rms = max(peak_rms, rms)
        raw.append((i / SR, rms, seg))

    out = []
    for t, rms, seg in raw:
        if rms < SILENCE_REL * peak_rms:
            out.append((t, rms, None))
            continue
        mag = np.abs(np.fft.rfft(seg, FFT_N))
        freqs = np.fft.rfftfreq(FFT_N, 1 / SR)
        band = (freqs >= 60) & (freqs <= SR / 2 - 200)
        m, f = mag[band], freqs[band]
        thresh = PEAK_REL * m.max()
        is_peak = (m > thresh) & np.r_[True, m[1:] > m[:-1]] & np.r_[m[:-1] > m[1:], True]
        peak_freqs = f[is_peak]
        fundamental = float(peak_freqs.min()) if peak_freqs.size else float(f[np.argmax(m)])
        out.append((t, rms, fundamental))
    return out


def segment_notes(track):
    """Collapse a per-frame (t, rms, freq_or_None) track into notes."""
    notes = []  # [start, end, [freqs]]
    for t, rms, freq in track:
        if freq is None:
            notes.append([t, t + HOP_S, None])
            continue
        if notes and notes[-1][2] is not None:
            ref = np.median(notes[-1][2])
            if abs(freq - ref) / ref <= NOTE_TOLERANCE:
                notes[-1][1] = t + HOP_S
                notes[-1][2].append(freq)
                continue
        notes.append([t, t + HOP_S, [freq]])

    # fold runs shorter than MIN_NOTE_MS into whichever neighbour is closer
    # in pitch (a rest absorbs into silence either way)
    changed = True
    while changed and len(notes) > 1:
        changed = False
        for i, n in enumerate(notes):
            dur_ms = (n[1] - n[0]) * 1000
            if dur_ms >= MIN_NOTE_MS:
                continue
            left = notes[i - 1] if i > 0 else None
            right = notes[i + 1] if i + 1 < len(notes) else None
            target = right if left is None else (left if right is None else
                     (left if (n[2] is None or left[2] is None or
                               abs(np.median(n[2] or [0]) - np.median(left[2] or [0]))
                               <= abs(np.median(n[2] or [0]) - np.median((right[2] or [0]))))
                      else right))
            if target is None:
                break
            if target is right:
                notes[i + 1] = [n[0], right[1],
                                 (None if (n[2] is None and right[2] is None) else
                                  ((n[2] or []) + (right[2] or [])) or None)]
                del notes[i]
            else:
                notes[i - 1] = [left[0], n[1],
                                 (None if (n[2] is None and left[2] is None) else
                                  ((left[2] or []) + (n[2] or [])) or None)]
                del notes[i]
            changed = True
            break

    result = []
    for start, end, freqs in notes:
        dur_ms = round((end - start) * 1000)
        if dur_ms <= 0:
            continue
        freq = round(float(np.median(freqs))) if freqs else 0
        result.append((freq, dur_ms))
    # merge adjacent notes the folding pass left at the same pitch (both
    # rests, or two runs that converged on the same frequency)
    merged = []
    for freq, dur in result:
        if merged and merged[-1][0] == freq:
            merged[-1] = (freq, merged[-1][1] + dur)
        else:
            merged.append((freq, dur))
    return merged


def round_trip_score(track, notes):
    """% of ACTIVE frames whose original fundamental is within tolerance of
    the note covering that frame. The number this whole ticket is for."""
    covered = []
    t = 0.0
    for freq, dur in notes:
        covered.append((t, t + dur / 1000, freq))
        t += dur / 1000
    total = ok = 0
    for ft, rms, freq in track:
        if freq is None:
            continue
        total += 1
        for start, end, nfreq in covered:
            if start <= ft < end:
                if nfreq > 0 and abs(freq - nfreq) / nfreq <= ROUND_TRIP_TOLERANCE:
                    ok += 1
                break
    return (100.0 * ok / total) if total else 100.0


def check_name_coverage():
    """Every name the port passes to playSound must exist in NAME_TO_FILE, and
    nothing in NAME_TO_FILE should be dead.

    An unresolved name is a SILENT failure: AudioManager.play() looks it up,
    gets -1, and returns without a sound. No test in the repo would notice,
    because sound is muted during the screen and animation probes -- so this
    guard is the only thing standing between a renamed sound and a sound that
    quietly stops playing.
    """
    src_text = ""
    for root, _, files in os.walk(os.path.join(APP_SRC)):
        for f in files:
            if f.endswith(".mc"):
                src_text += open(os.path.join(root, f), encoding="utf-8",
                                 errors="replace").read()

    used = set(re.findall(r'playSound\(\s*"([^"]+)"\s*\)', src_text))
    # `playSound(cond ? "a" : "b")`
    for a, b in re.findall(r'playSound\([^)]*\?\s*"([^"]+)"\s*:\s*"([^"]+)"', src_text):
        used |= {a, b}
    # a helper that returns the name, e.g. `function sound() { return "levelUp"; }`
    used |= set(re.findall(r'function sound\(\)[^{]*\{\s*return\s+"([^"]+)"', src_text))
    # the four dedicated methods, whose names are fixed in AudioManager
    used |= {"buttonA", "buttonB", "charHappy", "charSad"}

    missing = sorted(used - set(NAME_TO_FILE))
    dead = sorted(set(NAME_TO_FILE) - used)
    if missing:
        raise SystemExit(
            "sound names used by the port but absent from NAME_TO_FILE "
            f"(they would play SILENTLY): {missing}")
    if dead:
        print(f"  note: in the table but never played: {dead}")
    print(f"  name coverage: {len(used)}/{len(NAME_TO_FILE)}, no silent names")


def main():
    check_name_coverage()
    results = {}
    scores = []
    for name in sorted(NAME_TO_FILE):
        rel = NAME_TO_FILE[name]
        path = src("Assets/Audio", rel)
        x = load_mono(path)
        track = frame_fundamentals(x)
        notes = segment_notes(track)
        score = round_trip_score(track, notes)
        scores.append(score)
        results[name] = notes
        total_ms = sum(d for _, d in notes)
        flag = "" if score >= 90 else "  <-- LOW, inspect"
        print(f"  {name:24s} {len(notes):4d} notes  {total_ms/1000:7.2f}s  "
              f"round-trip {score:5.1f}%{flag}")

    print(f"\nTOTAL: {len(results)} sounds, "
          f"average round-trip {sum(scores)/len(scores):.1f}%, "
          f"worst {min(scores):.1f}%")

    os.makedirs(BUILD, exist_ok=True)
    with open(os.path.join(BUILD, "sound_index.json"), "w") as f:
        json.dump({"notes": {n: results[n] for n in results},
                   "roundTrip": dict(zip(sorted(NAME_TO_FILE), scores))},
                  f, indent=1)
    print(f"wrote {os.path.join(BUILD, 'sound_index.json')}")

    write_mc(results)
    print(f"wrote {app_path('source/Data/SoundData.mc')}")



# A single literal array of ~4,100 numbers overflows monkeyc's const type
# checker (a Java StackOverflowError in ConstTypeChecker, recursing once per
# array element) -- discovered building this. ADR 6 already solved exactly
# this shape of problem for the Digimon database: pack as bytes, carry the
# bytes as base64 in a string resource, decode once at startup. NAMES/
# OFFSETS/COUNTS stay literal arrays (40 elements each, nowhere near the
# ceiling); only the per-note data moves to the packed blob.
CHUNK = 32000       # ADR 6's string-resource cap, with margin under 32,767
MAX_CHUNKS = 2       # current data needs 1; the 2nd slot is headroom, per
                     # ADR 6's fixed-slot rule -- Monkey C has no dynamic
                     # String->Symbol lookup, so every slot loadChunk() names
                     # must exist as a real resource or the build fails


def write_mc(results):
    names = sorted(results)
    offsets, counts = [], []
    packed = bytearray()
    for name in names:
        offsets.append(len(packed) // 4)
        counts.append(len(results[name]))
        for freq, dur in results[name]:
            packed += struct.pack("<HH", freq, dur)

    b64 = base64.b64encode(bytes(packed)).decode("ascii")
    chunks = [b64[i:i + CHUNK] for i in range(0, len(b64), CHUNK)] or [""]
    assert len(chunks) <= MAX_CHUNKS, (
        f"sound data needs {len(chunks)} string chunks; SoundData.mc's "
        f"loadChunk() and MAX_CHUNKS here only allow {MAX_CHUNKS} -- raise both")
    while len(chunks) < MAX_CHUNKS:
        chunks.append("")

    with open(app_path("resources/strings/sound_strings.xml"), "w") as f:
        f.write("<strings>\n")
        for i, c in enumerate(chunks):
            f.write(f'    <string id="SoundData{i}">{c}</string>\n')
        f.write("</strings>\n")
    real_chunks = sum(1 for c in chunks if c)
    print(f"packed {len(packed):,} bytes -> base64 {len(b64):,} chars across "
          f"{real_chunks} string resource(s) (padded to {MAX_CHUNKS} slots)")

    def wrap(items, per_line=8, fmt="{}"):
        lines = []
        for i in range(0, len(items), per_line):
            lines.append("            " + ", ".join(fmt.format(v) for v in items[i:i + per_line]) + ",")
        return "\n".join(lines)

    load_chunk_lines = "\n".join(
        f'        if (i == {i}) {{ return WatchUi.loadResource(Rez.Strings.SoundData{i}) as String; }}'
        for i in range(MAX_CHUNKS))

    lines = [
        "import Toybox.Lang;",
        "import Toybox.StringUtil;",
        "import Toybox.WatchUi;",
        "",
        "// GENERATED by tools/pack_sounds.py from the source MP3s -- do not",
        "// edit. Regenerate with `tools/pack_sounds.py`.",
        "//",
        "// Every sound is a sequence of (frequency Hz, duration ms) notes,",
        "// extracted from the source's own square-wave audio (ticket 03 of",
        "// .scratch/sound-and-vibration/map.md). freq 0 is a rest.",
        "//",
        "// Notes are packed as bytes (UINT16 freq, UINT16 dur, little-endian)",
        "// and carried as base64 in string resources -- the same move ADR 6",
        "// makes for the Digimon database, forced here by the same wall: a",
        "// literal array past a few thousand elements overflows monkeyc's",
        "// const type checker (a real StackOverflowError, not a heap limit).",
        "// NAMES[i] -> OFFSETS[i]/COUNTS[i] index into the decoded bytes,",
        "// 4 bytes per note.",
        "module Kaisa {",
        "    module Sounds {",
        f"        const NAMES = [",
    ]
    lines.append(wrap([f'"{n}"' for n in names], per_line=4))
    lines.append("        ];")
    lines.append(f"        const OFFSETS = [")
    lines.append(wrap(offsets))
    lines.append("        ];")
    lines.append(f"        const COUNTS = [")
    lines.append(wrap(counts))
    lines.append("        ];")
    lines.append("")
    lines.append("        var _bytes as ByteArray?;")
    lines.append("        var _byName as Dictionary? = null;")
    lines.append("")
    lines.append("        // Called once, same as GameData.load() -- see DTectorApp's startup.")
    lines.append("        function load() as Void {")
    lines.append("            _bytes = []b;")
    lines.append("            var i = 0;")
    lines.append("            while (true) {")
    lines.append("                var sym = loadChunk(i);")
    lines.append("                if (sym == null) { break; }")
    lines.append("                var s = sym as String;")
    lines.append("                if (s.length() > 0) {")
    lines.append("                    var chunkBytes = StringUtil.convertEncodedString(s, {")
    lines.append("                        :fromRepresentation => StringUtil.REPRESENTATION_STRING_BASE64,")
    lines.append("                        :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY")
    lines.append("                    }) as ByteArray;")
    lines.append("                    (_bytes as ByteArray).addAll(chunkBytes);")
    lines.append("                }")
    lines.append("                i += 1;")
    lines.append("            }")
    lines.append("        }")
    lines.append("")
    lines.append("        function loadChunk(i as Number) as String? {")
    lines.append(load_chunk_lines)
    lines.append("            return null;")
    lines.append("        }")
    lines.append("")
    lines.append("        // Call sites resolve their string through this rather than a linear scan.")
    lines.append("        function indexOf(name as String) as Number {")
    lines.append("            if (_byName == null) {")
    lines.append("                var d = {};")
    lines.append("                for (var i = 0; i < NAMES.size(); i += 1) { d[NAMES[i]] = i; }")
    lines.append("                _byName = d;")
    lines.append("            }")
    lines.append("            var idx = _byName.get(name);")
    lines.append("            return (idx == null) ? -1 : idx;")
    lines.append("        }")
    lines.append("")
    lines.append("        // (frequency Hz, duration ms) for note `n` of sound `soundIndex`;")
    lines.append("        // freq 0 is a rest.")
    lines.append("        function noteAt(soundIndex as Number, n as Number) as Array<Number> {")
    lines.append("            var off = (OFFSETS[soundIndex] + n) * 4;")
    lines.append("            var bytes = _bytes as ByteArray;")
    lines.append("            var freq = bytes.decodeNumber(Lang.NUMBER_FORMAT_UINT16,")
    lines.append("                { :offset => off, :endianness => Lang.ENDIAN_LITTLE });")
    lines.append("            var dur = bytes.decodeNumber(Lang.NUMBER_FORMAT_UINT16,")
    lines.append("                { :offset => off + 2, :endianness => Lang.ENDIAN_LITTLE });")
    lines.append("            return [freq, dur];")
    lines.append("        }")
    lines.append("    }")
    lines.append("}")
    lines.append("")

    with open(app_path("source/Data/SoundData.mc"), "w") as f:
        f.write("\n".join(lines))


if __name__ == "__main__":
    main()
