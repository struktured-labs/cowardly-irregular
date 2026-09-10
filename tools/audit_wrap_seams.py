#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy"]
# ///
"""Measure the WRAP of every looping bed: the last 0.3s against the first 0.3s.

WHY THIS REPLACES audit_loop_seams.py's TAIL TEST
    That tool asks "is the last 1.5s far below the track's body mean?". Both
    halves of that question are wrong, in opposite directions, and between them
    they hid 41 of 146 beds for weeks:

    1.5s AVERAGES AWAY A SHORT STEEP FADE. Measured on boss_tempo_industrial:
        last 2.0s -19.9 · 1.5s -22.7 · 1.0s -47.1 · 0.5s -51.8 · 0.2s -54.5
        head 0.2s -10.9
      The old gate read -9.2 against body and said "not a fade, leave it alone"
      while the final fifth of a second sat 44 dB below where the track restarts.

    TAIL-vs-BODY MIS-READS SPARSE MATERIAL. A deliberately sparse piece (the W6
      procedural bed) has a tail 26.7 dB under its body and NO audible jump,
      because its head is 18 dB under body too. The old test calls that a fade.

    The wrap is tail -> HEAD. It is immune to both: a short window sees the
    seam, and comparing the two moments the player actually hears back to back
    needs no reference to the body at all.

WHAT A JUMP MEANS
    Positive = the music STEPS UP when it wraps: dies away, snaps back to full.
    Near zero = it loops. Negative = it ends louder than it begins, which is
    audible too but far rarer and usually deliberate.

THIS DOES NOT MODIFY ANYTHING. tools/crossfade_loop.py fixes what it finds.
"""
import json, os, subprocess, sys
import numpy as np

MANIFEST = "data/music_manifest.json"
SR = 48000
SEAM_S = 0.3
JUMP_DB = 12.0

# Beds crossfade_loop cannot fix, verified 2026-09-10. Kept as a PINNED
# population, not an exemption: a new entry here means someone decided, and a
# name dropping off means the tool can now fix it and this list is stale.
KNOWN_UNFIXABLE = {
    "overworld_industrial": "no cut point yields a flat wrap",
    "ambient_steampunk": "unreachable anyway — play_ambient reads the SFX manifest",
    "boss_warden_abstract": "no cut point yields a flat wrap",
}


def decode(path):
    raw = subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-i", path,
                          "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"],
                         capture_output=True).stdout
    return np.frombuffer(raw, dtype="<f4").astype(np.float64)


def db(x):
    if len(x) == 0:
        return float("-inf")
    r = float(np.sqrt(np.mean(np.square(x))))
    return 20.0 * np.log10(r) if r > 0 else float("-inf")


def main():
    if not os.path.exists(MANIFEST):
        sys.exit("run from the repo root: %s not found" % MANIFEST)
    tracks = json.load(open(MANIFEST, encoding="utf-8"))["tracks"]
    w = int(SEAM_S * SR)
    rows = []
    for key, meta in sorted(tracks.items()):
        if not meta.get("loop") or meta.get("stinger"):
            continue
        path = meta.get("file", "")
        if not path or not os.path.exists(path):
            continue
        y = decode(path)
        if len(y) < 3 * SR:
            continue
        rows.append((db(y[:w]) - db(y[-w:]), key))
    rows.sort(reverse=True)

    jumps = [r for r in rows if r[0] > JUMP_DB]
    print("%-34s %s" % ("track", "wrap step (tail -> head)"))
    for step, key in jumps:
        note = KNOWN_UNFIXABLE.get(key)
        print("  %-32s %+7.1f dB   %s" % (key, step, "PINNED: " + note if note else "*** NEW ***"))
    print("\n  %d looping beds measured, %d jump more than %.0f dB" % (len(rows), len(jumps), JUMP_DB))

    new = [k for _, k in jumps if k not in KNOWN_UNFIXABLE]
    stale = [k for k in KNOWN_UNFIXABLE if k not in {kk for _, kk in jumps}]
    if stale:
        print("  PINNED entries that now loop cleanly (remove them): %s" % ", ".join(stale))
    if new:
        print("  NEW jumps not pinned: %s" % ", ".join(new))
        print("  -> run: uv run tools/crossfade_loop.py --only <track> --apply")
    return 1 if (new or stale) else 0


if __name__ == "__main__":
    sys.exit(main())
