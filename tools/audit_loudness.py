#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Measure every music bed's perceived loudness and flag outliers.

WHY THIS EXISTS, AND WHY IT FOUND NOTHING
    Written 2026-09-10 to test a hypothesis that turned out to be FALSE: that the
    corpus was unevenly levelled and the player heard a volume jump at area
    transitions. Measured across 165 tracks:

        median -15.1 LUFS · stdev 1.5 dB · full spread 6.7 dB
        tracks more than 6 LU from median: ZERO
        worst single deviation: 3.6 LU (cutscene_w1_warden_farewell, -18.7)

    The corpus is well levelled. Keeping the instrument rather than the
    conclusion, because the conclusion is only true of today's corpus and NINE
    Suno tracks are staged behind a ToS block. A bed arriving at -8 LUFS would
    be a 7 LU outlier and audible against everything around it, and nothing else
    in the repo would notice.

⚠️ TRUE PEAK IS NOT A DEFECT HERE, and the number looks alarming without this
    note: 108 of 165 masters exceed 0 dBTP, up to +3.9. That is fine, because
    SoundManager.MUSIC_VOLUME_CEILING_DB is -10.0 — at slider 100% the hottest
    master lands at -6.1 dBFS, with 6 dB of margin. The peak column is reported
    for completeness, NOT gated. Gating it would fail 65% of a corpus that
    cannot clip in the chain that plays it.

    It does explain a message crossfade_loop.py prints, which I misread once:
    "the SEAM is fine, the master is hot" is about headroom for a gain change
    INSIDE the file, not about the playback chain.

WHAT IT GATES
    Deviation from the corpus MEDIAN, not from a fixed target. A fixed -14 LUFS
    (streaming convention) would be a bound imported from another medium; the
    median is what this game's own mix is built around, and SFX channel offsets
    (-6 battle, -12 ability, -16 UI) are tuned relative to it.

COST
    ~10 minutes: every track is fully decoded through ffmpeg's EBU R128 filter.
    Too slow for a GUT test, which is why this is a tool. Run it when a music
    batch lands, the way tools/audit_wrap_seams.py is run.
"""
import argparse, json, os, re, statistics, subprocess, sys

MANIFEST = "data/music_manifest.json"
BASELINE = "data/loudness_baseline.json"

## Derived, not chosen: today's worst deviation is 3.6 LU and nothing exceeds
## 6. A bound at 6 has margin over the real corpus and still catches the case
## this defends -- a bed mastered a full 7+ LU off the house level.
OUTLIER_LU = 6.0
## Below this a "median" is not describing a corpus.
MIN_TRACKS = 100


def measure(path: str):
    r = subprocess.run(["ffmpeg", "-nostdin", "-hide_banner", "-nostats", "-i", path,
                        "-af", "loudnorm=print_format=json", "-f", "null", "-"],
                       capture_output=True, text=True)
    m = re.search(r'\{[^{}]*"input_i"[^{}]*\}', r.stderr, re.S)
    if not m:
        return None
    d = json.loads(m.group(0))
    try:
        return float(d["input_i"]), float(d["input_tp"]), float(d["input_lra"])
    except (KeyError, ValueError):
        return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", action="append", default=[], help="restrict to these track keys")
    ap.add_argument("--json", help="also write raw measurements here")
    args = ap.parse_args()

    if not os.path.exists(MANIFEST):
        sys.exit("run from the repo root: %s not found" % MANIFEST)
    tracks = json.load(open(MANIFEST, encoding="utf-8"))["tracks"]

    rows, unreadable = [], []
    for key in sorted(tracks):
        meta = tracks[key]
        if not isinstance(meta, dict):
            continue
        if args.only and key not in args.only:
            continue
        path = meta.get("file", "")
        if not path or not os.path.exists(path):
            continue
        got = measure(path)
        if got is None:
            unreadable.append(key)
            continue
        rows.append((got[0], got[1], got[2], key))

    if args.json:
        json.dump(rows, open(args.json, "w"))
    if not rows:
        sys.exit("measured nothing -- is ffmpeg on PATH?")

    lufs = [r[0] for r in rows]

    ## ⛔ THE MEDIAN MUST COME FROM THE CORPUS, NEVER FROM THE SELECTION. The
    ## first version computed it over `rows`, so `--only <one track>` compared a
    ## track against ITSELF: deviation 0, "0 outliers", every time — vacuous in
    ## the exact path this tool exists for, checking a freshly landed bed. A full
    ## run records the baseline; --only reads it and REFUSES if it is absent
    ## rather than silently inventing one.
    if args.only:
        if not os.path.exists(BASELINE):
            sys.exit("--only needs a corpus baseline: run the full audit once to write %s" % BASELINE)
        med = float(json.load(open(BASELINE))["median_lufs"])
        print("  baseline %.1f LUFS from %s (%d tracks)"
              % (med, BASELINE, json.load(open(BASELINE))["n_tracks"]))
    else:
        med = statistics.median(lufs)
    print("  %d tracks measured (EBU R128 integrated loudness)" % len(rows))
    print("  median %.1f LUFS · stdev %.1f dB · spread %.1f .. %.1f (%.1f dB)"
          % (med, statistics.pstdev(lufs), min(lufs), max(lufs), max(lufs) - min(lufs)))

    out = [(abs(l - med), l, k) for l, tp, lra, k in rows if abs(l - med) > OUTLIER_LU]
    out.sort(reverse=True)
    print("\n  outliers beyond %.0f LU from median: %d" % (OUTLIER_LU, len(out)))
    for dev, l, k in out:
        print("    %-34s %7.1f LUFS  %+.1f LU vs median" % (k, l, l - med))

    hot = sorted(((tp, k) for l, tp, lra, k in rows if tp > 0.0), reverse=True)
    print("\n  masters above 0 dBTP: %d of %d  (NOT gated -- the music bus plays at"
          " -10 dB, so the hottest lands at %.1f dBFS)"
          % (len(hot), len(rows), (hot[0][0] - 10.0) if hot else -10.0))
    for tp, k in hot[:5]:
        print("    %-34s %+5.1f dBTP" % (k, tp))

    if unreadable:
        print("\n  UNREADABLE (%d): %s" % (len(unreadable), ", ".join(unreadable)))

    ## A corpus too small to have a meaningful median must not report "0 outliers".
    if len(rows) < MIN_TRACKS and not args.only:
        print("\n  REFUSED: only %d tracks measured; a median over fewer than %d is not a"
              " corpus baseline and '0 outliers' would be vacuous" % (len(rows), MIN_TRACKS))
        return 2
    ## Only a full run may write the baseline -- a --only run has no standing to.
    if not args.only:
        json.dump({"median_lufs": round(med, 2), "n_tracks": len(rows),
                   "outlier_bound_lu": OUTLIER_LU},
                  open(BASELINE, "w"), indent=2)
        print("\n  baseline written: %s (median %.1f LUFS over %d tracks)"
              % (BASELINE, med, len(rows)))
    return 1 if (out or unreadable) else 0


if __name__ == "__main__":
    sys.exit(main())
