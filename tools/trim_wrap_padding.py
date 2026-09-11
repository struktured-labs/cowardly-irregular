#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy"]
# ///
"""Remove digital silence from both edges of a looping bed.

WHY THIS EXISTS, AND WHY audit_wrap_seams.py COULD NOT FIND IT
    That tool scores the wrap as db(first 0.3s) - db(last 0.3s) and reports
    what exceeds +12 dB. The metric is a SIGNED DIFFERENCE and only one sign
    was thresholded, so silence at the HEAD drives the score toward -inf and
    lands in the healthiest-looking part of the distribution:

        credits_abstract      0.619s of silent head    scored -66.5 dB  "clean"
        dungeon_dragon_fire   0.596s                          -78.5 dB  "clean"
        village_scriptura     0.618s                          -73.9 dB  "clean"

    Six tenths of a second of dead air at every loop, and the instrument built
    to find dead air at every loop ranked them BEST IN CORPUS. Its docstring
    even wrote the excuse: "Negative = it ends louder than it begins, which is
    audible too but far rarer and usually deliberate." A -78 dB reading is not
    a musical decision about endings, it is a silent head, and the sentence
    that explained the sign away is what kept them out of the report.

    So this measures the defect DIRECTLY -- where does the audio actually start
    and stop -- instead of inferring it from a level difference. A pad is not a
    fade and no crossfade addresses it: crossfade_loop refused two of these on
    CLIPPING HEADROOM ("the master is hot"), which is a true statement about a
    gain change they never needed.

WHAT IT DOES NOT DO
    It changes no levels, applies no fade, and resamples nothing -- the output
    keeps the source rate and channel count, because 2 of the 19 beds are
    44.1 kHz and crossfade_loop's hardcoded 48k would silently respec them.
    The cut lands where |x| crosses -60 dBFS, so the discontinuity it creates
    is by construction at most a -60 dBFS step: inaudible, and no click.
"""
import argparse, json, os, shutil, subprocess, sys
import numpy as np

MANIFEST = "data/music_manifest.json"

## -60 dBFS peak: below this a sample cannot be heard under any playback chain,
## so treating it as silence is a claim about audibility, not about the file.
FLOOR_DB = -60.0

## Under 40ms the wrap gap is shorter than a vorbis frame pair and sits below
## the threshold where a rhythmic discontinuity reads as a stutter. Derived
## from the corpus (the two beds below it are 31ms and 21ms), not chosen.
MIN_PAD_S = 0.040

## Post-encode agreement bounds. Trimming must not move the level at all; the
## length must land where the arithmetic says it will.
LEVEL_TOLERANCE_DB = 0.5
LENGTH_TOLERANCE_S = 0.05


def probe(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a:0",
                          "-show_entries", "stream=sample_rate,channels",
                          "-of", "csv=p=0", path], capture_output=True, text=True).stdout.strip()
    sr, ch = out.split(",")
    return int(sr), int(ch)


def decode(path, sr, ch):
    raw = subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-i", path,
                          "-f", "f32le", "-ac", str(ch), "-ar", str(sr), "-"],
                         capture_output=True).stdout
    y = np.frombuffer(raw, dtype="<f4").astype(np.float64)
    return y.reshape(-1, ch) if ch > 1 else y.reshape(-1, 1)


def db(x):
    if x.size == 0:
        return float("-inf")
    r = float(np.sqrt(np.mean(np.square(x))))
    return 20.0 * np.log10(r) if r > 0 else float("-inf")


def pads(y, sr):
    """Seconds of sub-floor audio at the head and at the tail."""
    loud = np.flatnonzero(np.max(np.abs(y), axis=1) > 10.0 ** (FLOOR_DB / 20.0))
    if loud.size == 0:
        return None
    return loud[0] / sr, (len(y) - 1 - loud[-1]) / sr, int(loud[0]), int(loud[-1])


def encode(y, sr, ch, out_path):
    p = subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y",
                        "-f", "f32le", "-ac", str(ch), "-ar", str(sr), "-i", "-",
                        "-ac", str(ch), "-ar", str(sr), "-c:a", "libvorbis", "-b:a", "96k",
                        out_path], input=y.astype("<f4").tobytes(), capture_output=True)
    return p.returncode == 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="write files (default: dry run)")
    ap.add_argument("--only", action="append", default=[], help="restrict to these track keys")
    args = ap.parse_args()

    if not os.path.exists(MANIFEST):
        sys.exit("run from the repo root: %s not found" % MANIFEST)
    man = json.load(open(MANIFEST, encoding="utf-8"))
    tracks = man["tracks"]

    fixed, skipped, refused = [], 0, []
    for key in sorted(tracks):
        meta = tracks[key]
        if not isinstance(meta, dict) or not meta.get("loop") or meta.get("stinger"):
            continue
        if args.only and key not in args.only:
            continue
        path = meta.get("file", "")
        if not path or not os.path.exists(path):
            continue

        sr, ch = probe(path)
        y = decode(path, sr, ch)
        got = pads(y, sr)
        if got is None:
            refused.append((key, "the whole file is below the silence floor"))
            continue
        head_s, tail_s, first, last = got
        if head_s + tail_s < MIN_PAD_S:
            skipped += 1
            continue

        cut = y[first:last + 1]
        want_len = len(cut) / sr
        print("  %-32s %6.1fs  head %.3fs  tail %.3fs  ->  %6.1fs" %
              (key, len(y) / sr, head_s, tail_s, want_len))
        if not args.apply:
            fixed.append((key, want_len))
            continue

        tmp = path + ".trim.ogg"
        if not encode(cut, sr, ch, tmp):
            refused.append((key, "encode failed"))
            continue

        ## Verify the ENCODED file, not the array that went into it -- the
        ## encoder is the step that can silently repad or reframe.
        vy = decode(tmp, sr, ch)
        vpad = pads(vy, sr)
        why = None
        if abs(len(vy) / sr - want_len) > LENGTH_TOLERANCE_S:
            why = "length %.3fs, wanted %.3fs" % (len(vy) / sr, want_len)
        elif abs(db(vy) - db(cut)) > LEVEL_TOLERANCE_DB:
            why = "level moved %+.2f dB" % (db(vy) - db(cut))
        elif vpad is None or vpad[0] + vpad[1] >= MIN_PAD_S:
            why = "still padded after encode (%.3fs + %.3fs)" % (vpad[0], vpad[1]) if vpad else "encoded to silence"
        if why:
            os.remove(tmp)
            refused.append((key, why))
            continue

        os.replace(tmp, path)
        tracks[key]["duration"] = round(len(vy) / sr, 1)
        fixed.append((key, len(vy) / sr))

    if args.apply and fixed:
        ## The manifest duration has one reader (JukeboxMenu) and drifts silently
        ## when a tool rewrites an OGG without it -- twice already, 107 repairs.
        shutil.copy(MANIFEST, MANIFEST + ".bak")
        with open(MANIFEST, "w", encoding="utf-8") as fh:
            json.dump(man, fh, indent=2, ensure_ascii=False)
            fh.write("\n")

    print("\n  %d trimmed, %d already clean, %d refused" % (len(fixed), skipped, len(refused)))
    for key, why in refused:
        print("    REFUSED %-30s %s" % (key, why))
    if not args.apply and fixed:
        print("  dry run - nothing written. Pass --apply.")
    if args.apply and fixed:
        print("  OGGs rewritten: run --import before any test that load()s them.")
    return 1 if refused else 0


if __name__ == "__main__":
    sys.exit(main())
