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
    Near zero = it loops. Negative = it ends louder than it begins.

    ⚠️ THE STEP IS A SIGNED DIFFERENCE AND ONLY ONE SIGN WAS THRESHOLDED, which
    is how this tool ranked its worst tracks best in corpus for weeks. The line
    above used to end "...which is audible too but far rarer and usually
    deliberate", and that clause is what did the damage: a SILENT HEAD drives
    the score toward -inf, so a bed with 0.6s of dead air at every loop reads
    as maximally clean and the docstring supplies the excuse for the sign.

        credits_abstract      0.619s silent head    -66.5 dB   "clean"
        dungeon_dragon_fire   0.596s                -78.5 dB   "clean"
        battle_mushroom       0.450s                -60.8 dB   "clean"

    battle_mushroom is the one that settles it: under its pad sat a REAL +21.0
    dB fade, revealed the moment the silence came off. The pad was not merely
    invisible to the metric, it was CONCEALING a defect the metric exists to
    find. So the pad check below is not a second opinion, it is the arm that
    makes the level reading mean anything at all.

THIS DOES NOT MODIFY ANYTHING. tools/crossfade_loop.py fixes what it finds.
"""
import json, os, subprocess, sys
import numpy as np

MANIFEST = "data/music_manifest.json"
SR = 48000
## ⚠️ ONE WINDOW IS NOT ENOUGH, and this tool already knew why about a DIFFERENT
## number. Its docstring says a 1.5s window "AVERAGES AWAY A SHORT STEEP FADE" —
## correct, and it never asked whether 0.3s was short enough. It is not.
## @cowir-sfx swept window length on their weather beds 2026-09-11 and the same
## sweep on this corpus found EIGHT beds reading clean at 300ms and jumping past
## 12 dB at 10ms, worst +31.8 (ambient_steampunk). Verified as real 50-100ms
## fades, not phase noise: monotonic decline over the final 100ms, final-10ms
## peak 0.0013 against a track peak of 1.515.
##
## So measure at SEVERAL windows and take the worst. A fade is caught by any
## window shorter than itself; a single window is only ever right for one
## duration of defect.
## 10ms is NOT in the shipped set, and the reason is the finding: it is what
## revealed the 50-100ms fades that 0.3s averaged away, and it is too
## phase-sensitive to ship. It produced 2 false positives of 10 —
## cutscene_w2_coordinator_memo (negative at every stable window: a soft intro)
## and boss_arbiter_abstract (+12.5 at 10ms, +10.0/+8.2/+1.9 at the rest). A
## window good at FINDING a defect can still be wrong to JUDGE by.
SEAM_WINDOWS_S = [0.050, 0.100, 0.300]
SEAM_S = 0.3  # kept: the reporting window, and what the pinned history was measured at
JUMP_DB = 12.0

## -60 dBFS peak: below this a sample is inaudible under any playback chain.
FLOOR_DB = -60.0
## Under 40ms a wrap gap is too short to read as a stutter. Derived from the
## corpus (the two beds beneath it measured 31ms and 21ms), not chosen.
MIN_PAD_S = 0.040

# Beds no tool can fix. EMPTY as of 2026-09-10, and the emptying is the point:
# all three former entries were MISDIAGNOSES of mine, pinned on a refusal
# message I did not read carefully. crossfade_loop declined them saying "the
# SEAM is fine, the master is hot" -- a statement about CLIPPING HEADROOM for a
# gain change -- and I recorded that as "no cut point yields a flat wrap", which
# is a statement about the seam and is not what it said.
#
#     overworld_industrial   +75.7 dB   0.31s of trailing SILENCE   -> trimmed
#     ambient_steampunk      +74.4 dB   0.74s of trailing SILENCE   -> trimmed
#     boss_warden_abstract   +15.0 dB   a 1.0s fade the 1.5s window averaged away
#
# None needed a crossfade; two needed no gain change whatsoever. A pin is a
# claim that something is impossible, so it earns more scepticism than a bug
# report, not less -- it is the entry that stops anyone looking again.
KNOWN_UNFIXABLE = {
    "boss_tempo_digital": "quiet intro AND quiet tail — +32.9 dB at 50ms but -5.7 at 300ms, "
                          "opposite signs. No TAIL cut reconciles them; last 40s are at full level",
    "overworld_industrial": "structure, not a fade — -9.4 at 50ms vs +30.6 at 100ms uncut, and the "
                            "sign keeps flipping at every cut depth out to 2s",
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
    padded = []
    for key, meta in sorted(tracks.items()):
        if not meta.get("loop") or meta.get("stinger"):
            continue
        path = meta.get("file", "")
        if not path or not os.path.exists(path):
            continue
        y = decode(path)
        if len(y) < 3 * SR:
            continue
        ## Worst across every window — a fade hides from any window longer
        ## than itself, so one number cannot speak for all fade durations.
        worst = None
        for ws in SEAM_WINDOWS_S:
            n = int(ws * SR)
            if len(y) < 3 * n:
                continue
            step = db(y[:n]) - db(y[-n:])
            if worst is None or step > worst[0]:
                worst = (step, ws)
        if worst is None:
            continue
        rows.append((worst[0], key, worst[1]))
        loud = np.flatnonzero(np.abs(y) > 10.0 ** (FLOOR_DB / 20.0))
        if loud.size:
            head_pad, tail_pad = loud[0] / SR, (len(y) - 1 - loud[-1]) / SR
            if head_pad + tail_pad >= MIN_PAD_S:
                padded.append((head_pad + tail_pad, key, head_pad, tail_pad))
    rows.sort(reverse=True)
    padded.sort(reverse=True)

    jumps = [r for r in rows if r[0] > JUMP_DB]
    print("%-34s %s" % ("track", "wrap step (tail -> head)"))
    for step, key, ws in jumps:
        note = KNOWN_UNFIXABLE.get(key)
        print("  %-32s %+7.1f dB @%4.0fms   %s" % (key, step, ws * 1000, "PINNED: " + note if note else "*** NEW ***"))
    print("\n  %d looping beds measured, %d jump more than %.0f dB" % (len(rows), len(jumps), JUMP_DB))

    ## Reported separately because a pad is a different defect with a different
    ## fix, and because the level reading above cannot see it -- silence at the
    ## head flatters the score instead of hurting it.
    if padded:
        print("\n%-34s %s" % ("track", "digital silence at the wrap"))
        for total, key, h, t in padded:
            print("  %-32s head %.3fs + tail %.3fs = %.3fs" % (key, h, t, total))
        print("  -> run: uv run tools/trim_wrap_padding.py --apply")
    else:
        print("  0 beds carry silence padding at the wrap")

    new = [k for _, k, _w in jumps if k not in KNOWN_UNFIXABLE]
    stale = [k for k in KNOWN_UNFIXABLE if k not in {kk for _, kk, _w in jumps}]
    if stale:
        print("  PINNED entries that now loop cleanly (remove them): %s" % ", ".join(stale))
    if new:
        print("  NEW jumps not pinned: %s" % ", ".join(new))
        print("  -> run: uv run tools/crossfade_loop.py --only <track> --apply")
    return 1 if (new or stale or padded) else 0


if __name__ == "__main__":
    sys.exit(main())
