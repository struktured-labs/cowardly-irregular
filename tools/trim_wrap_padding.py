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
    keeps the source rate and channel count, and that is now ASSERTED after the
    encode rather than merely intended (see the verification block below).
    ⚠️ "2 of the 19 beds are 44.1 kHz" stood here and counted the trim
    population, not the corpus. I then replaced it with "19 of 165 tracks",
    which counted manifest ENTRIES -- battle_brute.ogg is named by five keys
    (the monster-family ruling), so the alias was counted five times. The
    denominator is 161 DISTINCT files, of which 19 are 44.1 kHz; the directory
    holds 163 .ogg because two sfx_ability_* files sit there unreferenced by
    either manifest. Three denominators, one corpus -- say which you mean.
    The cut lands where |x| crosses -60 dBFS, so the discontinuity it creates
    is by construction at most a -60 dBFS step: inaudible, and no click.
"""
import argparse, json, os, shutil, subprocess, sys
import numpy as np

MANIFEST = "data/music_manifest.json"

## -60 dBFS peak: below this a sample cannot be heard under any playback chain,
## so treating it as silence is a claim about audibility, not about the file.
FLOOR_DB = -60.0

## ⛔ THE ORIGINAL JUSTIFICATION HERE WAS VOID. It read "Derived from the corpus
## (the two beds below it are 31ms and 21ms), not chosen" — and that corpus was
## measured with the PEAK floor this file now documents as broken. A threshold
## derived from a defective instrument is not derived; it inherits the defect
## and wears the word "derived" as cover.
##
## Re-derived 2026-09-11 with the 10ms RMS floor, and the real reason is
## SELF-REFERENCE: this tool cuts on the window boundary BEFORE the first loud
## window, so every file it writes keeps exactly one sub-floor window — 10ms —
## by construction. 33 beds now sit at precisely 10ms and 4 at 20ms, and that
## population is the tool's own residue, not a defect.
##
## So the floor is not about vorbis frames or stutter perception: it must simply
## sit ABOVE THE TOOL'S OWN CUT RESIDUE, or the tool flags its own output
## forever. One window is 10ms; 40ms is 4x that. Anything at or below 20ms would
## make this instrument a perpetual-motion machine.
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


## ⛔ A PER-SAMPLE PEAK FLOOR IS DEFEATED BY ONE SAMPLE, and it was. The first
## version tested `max(abs(sample)) > -60 dBFS` per sample, so a single stray
## value inside the first millisecond made the whole head "loud" and the pad
## measured 0.8ms. Measured 2026-09-11: this tool trimmed 19 beds and MISSED 30
## MORE — a larger population than it caught — including battle_snake with
## 1,510ms of head silence reported as 0.0ms. boss_curator_medieval reads
## -100 dB RMS for 520ms while carrying a transient in its first millisecond.
##
## Scan 10ms WINDOWS by RMS instead. One sample cannot move a 480-sample mean,
## which is the whole point.
WINDOW_S = 0.010


def pads(y, sr):
    """Seconds of sub-floor audio at the head and at the tail, by windowed RMS."""
    w = int(WINDOW_S * sr)
    if w <= 0 or len(y) < w:
        return None
    nw = len(y) // w
    mono = y[:nw * w].reshape(nw, -1)
    rms = np.sqrt(np.mean(np.square(mono), axis=1))
    loud = np.flatnonzero(rms > 10.0 ** (FLOOR_DB / 20.0))
    if loud.size == 0:
        return None
    ## Cut on the window boundary BEFORE the first loud window, so a soft attack
    ## inside that window is never clipped.
    first = max(0, int(loud[0]) - 1) * w
    last = min(nw - 1, int(loud[-1]) + 1) * w + w - 1
    last = min(last, len(y) - 1)
    return first / sr, (len(y) - 1 - last) / sr, first, last


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
        ## ⛔ ONE SKIP WAS ANSWERING TWO DIFFERENT QUESTIONS. Excluding stingers is
        ## right for a WRAP check — they do not loop, so there is no join — and
        ## wrong for a PAD check: a stinger with 510ms of leading silence is
        ## half a second between pressing Limit Break and hearing it, and
        ## trailing silence delays the bed it resumes. Measured 2026-09-11:
        ## 5 of 19 stingers carry >=40ms, worst job_cleric_special at
        ## 510ms head + 660ms tail inside a 14.7s file.
        ##
        ## The `loop` skip stays: a track with no file and no loop is not a bed.
        if not isinstance(meta, dict):
            continue
        if not meta.get("loop") and not meta.get("stinger"):
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
        ## ⛔ THE RATE GUARANTEE WAS DOCUMENTED AND UNVERIFIABLE. The docstring
        ## promises "resamples nothing -- the output keeps the source rate and
        ## channel count", written because crossfade_loop's hardcoded 48k had
        ## silently respecced 44.1k tracks. Nothing here checked it, and the
        ## check that looks like it would is the one that HIDES it: decode()
        ## below asks ffmpeg for `sr`, so a temp file written at the wrong rate
        ## is resampled back before the length and level comparisons ever see
        ## it. Both would pass. Knowing a property and ENCODING it are different
        ## things, and a verification that cannot fail on the property is the
        ## more confident of the two.
        enc_sr, enc_ch = probe(tmp)
        if (enc_sr, enc_ch) != (sr, ch):
            os.remove(tmp)
            refused.append((key, "encoder changed the format: %d Hz/%dch in, %d Hz/%dch out"
                                 % (sr, ch, enc_sr, enc_ch)))
            continue

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
