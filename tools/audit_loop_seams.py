#!/usr/bin/env python3
"""Audit every looping music bed for a fade-out at its loop point.

WHY THIS EXISTS
    A Suno track is a SONG, and songs fade out. A game loop must not: when the
    stream wraps, the player hears the music die to silence and snap back to
    full. Measured 2026-08-05: 98 of 138 looping beds do this. It is the largest
    player-audible defect found in the music lane, and no existing guard could
    see it, because "the track plays" and "loop = true" are both true for all 98.

WHAT IT REPORTS, and the distinction that matters for a fix
    Trimming the fade is only safe when the material UNDER the fade is at full
    level -- i.e. the song was still playing and the fade was laid on top. Where
    a track genuinely ENDS (final chord, decaying tail, nothing beneath), a trim
    leaves a cut mid-decay that can sound worse than the fade it replaced.

        TRIM-SAFE     level recovers to near the body mean before the fade
        RITARDANDO    level declines gradually -- the piece is ending, not faded
        ALREADY OK    tail already at full level; loops cleanly today

    This does NOT modify anything. It prints a plan; a human decides.

USAGE
    python3 tools/audit_loop_seams.py            # summary
    python3 tools/audit_loop_seams.py --verbose  # per-track
"""
import json
import os
import subprocess
import sys

MANIFEST = "data/music_manifest.json"
# A tail this far under the track's own mean is a fade, not a mix choice.
FADE_THRESHOLD_DB = -12.0
# Within this of the body mean counts as "full level" when scanning backwards.
FULL_LEVEL_TOLERANCE_DB = 4.0
MAX_FADE_SCAN_S = 45
# A fade longer than this is not a fade laid over playing music -- it is the piece
# winding down. Trimming it amputates a real ending rather than removing a tail.
#
# This bound is the whole reason the RITARDANDO branch can fire. Without it the
# backward scan finds SOME full-level moment within MAX_FADE_SCAN_S for any fade
# of any length and calls it trim-safe: a deliberately-constructed 40 s fade
# classified TRIM-SAFE with a trim point 21 s early, which would have discarded
# the entire ending. Verified 2026-08-06, and the tell was the first run
# reporting 97/0 -- a safety branch that never fires on a 138-track corpus is
# decorative, not reassuring.
#
# 8 s is chosen against the measured distribution, not picked: 94 of 97 fades in
# this library are under 6 s and three are 12-29 s, so the gap is real and wide.
# Re-derive it if the corpus changes rather than trusting the constant.
MAX_TRIM_S = 8.0


def mean_db(path, start=None, dur=None):
    cmd = ["ffmpeg", "-hide_banner", "-nostats"]
    if start is not None:
        cmd += ["-ss", str(start)]
    if dur is not None:
        cmd += ["-t", str(dur)]
    cmd += ["-i", path, "-af", "volumedetect", "-f", "null", "-"]
    out = subprocess.run(cmd, capture_output=True, text=True).stderr
    for line in out.splitlines():
        if "mean_volume" in line:
            try:
                return float(line.split("mean_volume:")[1].split("dB")[0])
            except (IndexError, ValueError):
                return None
    return None


def duration(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "csv=p=0", path], capture_output=True, text=True).stdout.strip()
    try:
        return float(out)
    except ValueError:
        return 0.0


def classify(path, dur):
    """Return (verdict, tail_delta_db, trim_point_s or None)."""
    body = mean_db(path, 0, max(1.0, dur - 15))
    tail = mean_db(path, max(0.0, dur - 1.5), 1.5)
    if body is None or tail is None:
        return "UNREADABLE", 0.0, None
    delta = tail - body
    if delta >= FADE_THRESHOLD_DB:
        return "ALREADY OK", delta, None
    # Walk backwards a second at a time; find the last window still at full level.
    trim = None
    for back in range(1, MAX_FADE_SCAN_S):
        t = dur - back
        if t <= 1:
            break
        m = mean_db(path, t - 1, 1)
        if m is not None and m > body - FULL_LEVEL_TOLERANCE_DB:
            trim = t
            break
    if trim is None:
        # Never recovers to full level within the scan window: the piece is
        # winding down rather than being faded. Trimming cuts a decay.
        return "RITARDANDO", delta, None
    if (dur - trim) > MAX_TRIM_S:
        # Full level exists back there, but reaching it costs more music than any
        # fade-out is worth. That is an ending, not a tail.
        return "RITARDANDO", delta, trim
    return "TRIM-SAFE", delta, trim


def main():
    verbose = "--verbose" in sys.argv
    if not os.path.exists(MANIFEST):
        sys.exit("run from the repo root: %s not found" % MANIFEST)
    data = json.load(open(MANIFEST))
    tracks = data.get("tracks", data)

    rows = []
    for tid in sorted(tracks):
        entry = tracks[tid]
        path = str(entry.get("file", ""))
        if not path or not os.path.exists(path):
            continue
        if tid.startswith("stinger_"):
            continue                       # stingers are MEANT to end
        if not entry.get("loop", True):
            continue                       # non-looping by declaration
        dur = duration(path)
        if dur < 5:
            continue
        verdict, delta, trim = classify(path, dur)
        rows.append((tid, verdict, delta, dur, trim))
        if verbose:
            extra = "  trim at %.1fs (-%.1fs)" % (trim, dur - trim) if trim else ""
            print("  %-34s %-11s tail %+6.1f dB  %6.1fs%s" % (tid, verdict, delta, dur, extra))

    if not rows:
        sys.exit("no looping beds measured -- manifest or paths wrong, NOT a clean result")

    buckets = {}
    for _, v, _, _, _ in rows:
        buckets[v] = buckets.get(v, 0) + 1
    print("\nlooping music beds measured: %d" % len(rows))
    for v in ("ALREADY OK", "TRIM-SAFE", "RITARDANDO", "UNREADABLE"):
        if v in buckets:
            print("  %-11s %4d" % (v, buckets[v]))

    trimmable = [r for r in rows if r[1] == "TRIM-SAFE"]
    if trimmable:
        saved = sum(r[3] - r[4] for r in trimmable)
        print("\n  %d tracks are trim-safe; %.0f s of fade total (avg %.1f s each)"
              % (len(trimmable), saved, saved / len(trimmable)))
    rit = [r for r in rows if r[1] == "RITARDANDO"]
    if rit:
        print("\n  %d NEED A HUMAN -- these end rather than fade, so a trim cuts a decay:" % len(rit))
        for tid, _, delta, dur, _ in rit[:12]:
            print("      %-34s tail %+6.1f dB  %6.1fs" % (tid, delta, dur))

    # Control: the classifier must be able to say more than one thing. A run that
    # labels everything identically is a broken measurement wearing a clean result.
    if len(buckets) < 2:
        print("\n  WARNING: every track classified '%s' -- the classifier is not "
              "discriminating and this output should not be trusted" % list(buckets)[0])


if __name__ == "__main__":
    main()
