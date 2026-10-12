#!/usr/bin/env python3
"""Audit every looping music bed for a fade-out at its loop point.

WHY THIS EXISTS
    A Suno track is a SONG, and songs fade out. A game loop must not: when the
    stream wraps, the player hears the music die to silence and snap back to
    full. It is the largest player-audible defect found in the music lane, and no
    existing guard could see it, because "the track plays" and "loop = true" are
    both true for every one of them.

    Measured 2026-08-05, reproduced unchanged 2026-08-21 -- 138 looping beds:

        ALREADY OK   41    loops cleanly today
        TRIM-SAFE    88    fade laid over playing music
        RITARDANDO    9    the piece is ENDING; a trim cuts a decay
                    ----
                    138    == the corpus, which is the check on these three

    So 97 beds fade at the loop point, of which 88 are safe to trim. This
    docstring said "98" for sixteen days -- a figure this tool has never printed,
    off by one against its own output, and unfalsifiable because no line here
    summed to anything. Quote the breakdown, not a total: a total cannot disagree
    with itself. Re-derive with `python3 tools/audit_loop_seams.py`.

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
import shutil
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
    ## EVERY skip is COUNTED, not just taken. The four `continue`s below used to drop entries
    ## silently, so a path change or a filter bug could shrink the corpus from 146 to 12 and this
    ## tool would print "ALREADY OK 12 ... CLEAN" with its classifier control still passing —
    ## the control proves the INSTRUMENT works and says nothing about the SUBJECT.
    ## @cowir-deploy paid 443 GiB for that exact shape on 2026-10-12, and the CORRECTED cause is the
    ## sharper one: their cleanup probe runs with cwd inside a release worktree and nothing sets its
    ## root, so it scanned that tree's own tmp/ and returned 0 — a correct instrument pointed at the
    ## wrong subject. At 909 MB free against a 5000 MB floor it then certified "the space is held
    ## outside this lane" while the lane sat on hundreds of GB. (Their first diagnosis blamed a
    ## prefix default and they retracted it after measuring; the prefix was not load-bearing.)
    skips = {"file missing": 0, "stinger": 0, "loop=false": 0, "under 5s": 0}
    for tid in sorted(tracks):
        entry = tracks[tid]
        path = str(entry.get("file", ""))
        if not path or not os.path.exists(path):
            skips["file missing"] += 1
            continue
        if tid.startswith("stinger_"):
            skips["stinger"] += 1
            continue                       # stingers are MEANT to end
        if not entry.get("loop", True):
            skips["loop=false"] += 1
            continue                       # non-looping by declaration
        dur = duration(path)
        if dur < 5:
            skips["under 5s"] += 1
            continue
        verdict, delta, trim = classify(path, dur)
        rows.append((tid, verdict, delta, dur, trim))
        if verbose:
            extra = "  trim at %.1fs (-%.1fs)" % (trim, dur - trim) if trim else ""
            print("  %-34s %-11s tail %+6.1f dB  %6.1fs%s" % (tid, verdict, delta, dur, extra))

    if not rows:
        sys.exit("no looping beds measured -- manifest or paths wrong, NOT a clean result")

    ## SUBJECT CONTROL, the twin of self_check()'s instrument control. This is the tool's own
    ## docstring principle ("138 == the corpus, which is the check on these three") applied to
    ## corpus SELECTION rather than to the verdict buckets.
    corpus_ok = True
    accounted = len(rows) + sum(skips.values())
    print("\ncorpus: %d manifest entries = %d measured + %s"
          % (len(tracks), len(rows), " + ".join("%d %s" % (v, k) for k, v in skips.items() if v)))
    if accounted != len(tracks):
        corpus_ok = False
        print("  ⛔ ACCOUNTING DOES NOT CLOSE: %d measured + %d skipped = %d against %d entries."
              % (len(rows), sum(skips.values()), accounted, len(tracks)))
        print("     An entry left the corpus for a reason this tool does not enumerate. Fix that")
        print("     before reading any verdict below.")
    if skips["file missing"]:
        corpus_ok = False
        print("  ⛔ %d manifest entr%s name a file that is not on disk. That is a DEFECT, not a"
              % (skips["file missing"], "y" if skips["file missing"] == 1 else "ies"))
        print("     skip: those beds cannot be measured and cannot play.")

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
        only = list(buckets)[0]
        ok, detail = self_check()
        if ok and not corpus_ok:
            print("\n  WITHHELD: the classifier is proven (%s) but the CORPUS is wrong -- see above."
                  "\n            A verdict over the wrong subject is not a verdict." % detail)
        elif ok and only == "ALREADY OK":
            print("\n  CLEAN: every bed loops without a fade, and the classifier is PROVEN to "
                  "discriminate\n         (%s).\n         The 2026-08-05 defect -- 97 of 138 beds "
                  "fading at the loop point -- is repaired." % detail)
        elif ok:
            print("\n  WARNING: every track classified '%s'. The classifier discriminates (%s), "
                  "so this is a real\n           single-bucket corpus rather than a broken scan -- "
                  "but one bucket of '%s' is not a state\n           this tool was written to "
                  "expect. Read the rows." % (only, detail, only))
        else:
            print("\n  BROKEN: every track classified '%s' AND the classifier failed its own "
                  "control\n          (%s). This output means nothing. Fix the scan, not the "
                  "corpus." % (only, detail))


def self_check():
    """Classify a PLANTED fade and a flat tone. Returns (trustworthy, detail).

    WHY THIS EXISTS
        "Every track is ALREADY OK" has two causes -- a repaired corpus and a
        classifier that cannot say anything else -- and for sixteen days this tool
        printed the pessimistic one unconditionally. On 2026-10-12 the corpus was
        genuinely clean (146/146) and the output told the reader not to trust it,
        which costs the next lane either a wasted re-measurement or the belief that
        the loop seams are still broken.

        A control the corpus cannot influence is the only thing that separates the
        two, so this builds its own inputs: 20 s of tone, one with a 5 s fade-out
        (the defect) and one without. The faded one MUST be flagged and the flat one
        MUST be cleared. Measured when written: TRIM-SAFE at tail -15.3 dB, and
        ALREADY OK at 0.0 dB.
    """
    import tempfile
    if shutil.which("ffmpeg") is None:
        return False, "ffmpeg is not on PATH, so the control could not run"
    with tempfile.TemporaryDirectory(prefix="seam_selfcheck_") as d:
        faded = os.path.join(d, "faded.ogg")
        flat = os.path.join(d, "flat.ogg")
        base = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                "-f", "lavfi", "-i", "sine=frequency=220:duration=20"]
        if subprocess.run(base + ["-af", "afade=t=out:st=15:d=5", "-c:a", "libvorbis", faded],
                          capture_output=True).returncode != 0:
            return False, "ffmpeg could not synthesise the control input"
        if subprocess.run(base + ["-c:a", "libvorbis", flat],
                          capture_output=True).returncode != 0:
            return False, "ffmpeg could not synthesise the control input"
        fv, fd, _ = classify(faded, duration(faded))
        nv, nd, _ = classify(flat, duration(flat))
    if fv == "ALREADY OK":
        return False, "a planted 5 s fade-out was cleared as ALREADY OK at %+.1f dB" % fd
    if nv != "ALREADY OK":
        return False, "a flat tone with no fade was flagged %s at %+.1f dB" % (nv, nd)
    return True, "a planted fade reads %s at %+.1f dB, a flat tone reads ALREADY OK at %+.1f dB" % (fv, fd, nd)


if __name__ == "__main__":
    main()
