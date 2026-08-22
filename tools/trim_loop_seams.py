#!/usr/bin/env python3
"""Trim the fade-out off looping music beds so they wrap at full level.

WHY
    A Suno track is a SONG, and songs fade out. A game loop must not: when the
    stream wraps, the player hears the music die to silence and snap back to full.
    tools/audit_loop_seams.py finds them; this removes them.

WHAT IT WILL AND WILL NOT TOUCH
    Only TRIM-SAFE, as classified by the audit — the level recovers to near the
    body mean before the fade, so there is full-level material under it. RITARDANDO
    (the piece genuinely ends) and ALREADY OK are never touched, and asking for one
    by name is refused rather than silently skipped.

THE DECLICK IS NOT OPTIONAL
    Cutting at full level leaves a discontinuity, and a loop point is exactly where
    a discontinuity is audible — every wrap, forever. An 8 ms fade is below the
    threshold of hearing as a fade and removes the edge.

VERIFICATION IS PER-TRACK, BEFORE THE REPLACE
    A trim that leaves the tail still quiet has not fixed anything, and a trim that
    overshoots has eaten music. Each output is measured against BOTH bounds and the
    original is only replaced if it passes. A failure leaves the source untouched.

USAGE
    python3 tools/trim_loop_seams.py                 # dry run, all TRIM-SAFE
    python3 tools/trim_loop_seams.py --only <track>  # one track
    python3 tools/trim_loop_seams.py --limit 3       # first N
    python3 tools/trim_loop_seams.py --apply         # write in place
"""
import argparse
import json
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from audit_loop_seams import MANIFEST, classify, duration, mean_db, FULL_LEVEL_TOLERANCE_DB

DECLICK_S = 0.008
# The trimmed tail must land within this of the body mean, or the trim did not work.
TAIL_TOLERANCE_DB = 4.0
# Encoding of the existing corpus, measured rather than assumed: vorbis 48k mono 96k.
ENCODE = ["-ac", "1", "-ar", "48000", "-c:a", "libvorbis", "-b:a", "96k"]


def trim_one(src, trim_at, tmp):
    fade_st = max(0.0, trim_at - DECLICK_S)
    cmd = ["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", src,
           "-t", "%.3f" % trim_at,
           "-af", "afade=t=out:st=%.3f:d=%.3f" % (fade_st, DECLICK_S)] + ENCODE + [tmp]
    return subprocess.run(cmd, capture_output=True).returncode == 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--only")
    ap.add_argument("--limit", type=int)
    args = ap.parse_args()

    tracks = json.load(open(MANIFEST))["tracks"]
    rows = []
    for key, meta in sorted(tracks.items()):
        if not meta.get("loop"):
            continue
        path = meta.get("file")
        if not path or not os.path.exists(path):
            continue
        if args.only and key != args.only:
            continue
        dur = duration(path)
        if dur is None:
            continue
        verdict, delta, trim = classify(path, dur)
        if verdict != "TRIM-SAFE":
            if args.only:
                print("REFUSED: %s is %s, not TRIM-SAFE. This tool only removes fades laid "
                      "over playing music." % (key, verdict))
                return 2
            continue
        rows.append((key, path, dur, delta, trim))
    if args.limit:
        rows = rows[:args.limit]

    print("%-34s %8s %8s %8s  %s" % ("track", "dur", "trim@", "cut", "result"))
    ok = failed = 0
    for key, path, dur, delta, trim in rows:
        cut = dur - trim
        if not args.apply:
            print("%-34s %7.1fs %7.1fs %7.1fs  (dry run)" % (key, dur, trim, cut))
            continue
        tmp = path + ".trim.tmp.ogg"
        if not trim_one(path, trim, tmp):
            print("%-34s %7.1fs %7.1fs %7.1fs  FFMPEG FAILED - source untouched" % (key, dur, trim, cut))
            failed += 1
            continue
        new_dur = duration(tmp)
        body = mean_db(tmp, 0, max(1.0, new_dur - 5)) if new_dur else None
        tail = mean_db(tmp, max(0.0, new_dur - 1.0), 1.0) if new_dur else None
        why = None
        if new_dur is None or body is None or tail is None:
            why = "unreadable output"
        elif abs(new_dur - trim) > 0.5:
            why = "duration %.1fs != trim point %.1fs" % (new_dur, trim)
        elif tail < body - TAIL_TOLERANCE_DB:
            why = "tail still %.1f dB under body - the fade was not removed" % (tail - body)
        if why:
            os.remove(tmp)
            print("%-34s %7.1fs %7.1fs %7.1fs  REJECTED (%s) - source untouched" % (key, dur, trim, cut, why))
            failed += 1
            continue
        shutil.move(tmp, path)
        print("%-34s %7.1fs %7.1fs %7.1fs  trimmed, tail %+0.1f dB vs body" % (key, dur, trim, cut, tail - body))
        ok += 1

    if args.apply:
        print("\n  trimmed %d, rejected %d, of %d TRIM-SAFE candidates" % (ok, failed, len(rows)))
    else:
        print("\n  %d TRIM-SAFE candidates, %.1fs of fade total. Nothing written; pass --apply."
              % (len(rows), sum(r[2] - r[4] for r in rows)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
