#!/usr/bin/env python3
"""Make a looping ambient bed wrap cleanly when its tail FADES rather than pads.

Companion to trim_wrap_padding.py, not a replacement. That tool cuts digital silence at
the -60 dBFS crossing; a bed that fades toward the floor and ends before reaching it has
NO padding by that criterion, so the silence trimmer correctly reports nothing to do.
Measured on the six weather beds: five have 0.000s of trailing pad and wrap steps up to
+53 dB at a 50 ms window.

Two stages, because trimming alone replaces a fade-out with a hard step:

  1. TRIM   cut where the level last sat within TOL_DB of the steady-state body, so the
            asset ends at playing level instead of part-way down a decay.
  2. WRAP   crossfade the final XFADE seconds over the head (equal-power). The first
            sample then continues from the last by construction, which is what a loop
            needs -- a cut alone leaves head and tail at the same LEVEL but unrelated
            phase, and that is an audible click.

REFUSES rather than half-writing: if the measured wrap step does not improve, or the fade
is so long that trimming would eat the asset (weather_steam is 3.0s of fade in a 5.0s
file -- a generation defect, not a seam defect), the file is left alone and reported.

Rate, channel count and bitrate are read from the source and passed back to the encoder.
No gain change, no resample.
"""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

import numpy as np

MANIFEST = "data/sfx_manifest.json"
ROOT_KEY = "sfx"

## Cut where the body level was last within this much of steady state. 3 dB is half power:
## above it the tail is still "playing", below it a listener hears the bed receding.
TOL_DB = 3.0

## Equal-power crossfade length at the wrap. Long enough to hide a phase discontinuity in
## broadband ambience, short enough not to audibly double the texture.
XFADE = 0.25

## A fade longer than this fraction of the asset is a generation defect: the source was
## made as a one-shot with a decay, and trimming it would leave a bed too short to loop.
MAX_FADE_FRAC = 0.25

## Windows for the reported wrap step. The SHORT one is the honest number for a seam --
## a 250 ms window averages a brief fade away and calls a broken seam clean.
STEP_WIN = 0.050


def probe(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
         "stream=sample_rate,channels,bit_rate", "-of", "json", path],
        capture_output=True, text=True).stdout
    s = json.loads(out)["streams"][0]
    return int(s["sample_rate"]), int(s["channels"]), int(s.get("bit_rate") or 0)


def decode(path, sr, ch):
    raw = subprocess.run(
        ["ffmpeg", "-v", "quiet", "-i", path, "-ac", str(ch), "-ar", str(sr),
         "-f", "f32le", "-"], capture_output=True).stdout
    y = np.frombuffer(raw, dtype=np.float32).astype(np.float64)
    return y.reshape(-1, ch) if ch > 1 else y.reshape(-1, 1)


def encode(y, sr, ch, bitrate, out_path):
    cmd = ["ffmpeg", "-v", "quiet", "-y", "-f", "f32le", "-ar", str(sr), "-ac", str(ch),
           "-i", "-", "-c:a", "libvorbis"]
    if bitrate:
        cmd += ["-b:a", str(bitrate)]
    cmd += [out_path]
    subprocess.run(cmd, input=y.astype(np.float32).tobytes(), check=True)


def db(x):
    if len(x) == 0:
        return -120.0
    return 20 * np.log10(max(float(np.sqrt((x ** 2).mean())), 1e-12))


def wrap_step(y, sr, win=STEP_WIN):
    n = int(win * sr)
    return db(y[:n]) - db(y[-n:])


def fade_start(y, sr):
    """Seconds from the end at which the level last sat within TOL_DB of the body."""
    n = len(y)
    body = db(y[int(0.2 * n):int(0.8 * n)])
    step = int(0.01 * sr)
    win = int(0.10 * sr)
    for i in range(n - win, 0, -step):
        if db(y[i:i + win]) - body > -TOL_DB:
            return (n - i) / sr
    return n / sr


def seam(y, sr):
    """Trim the fade, then equal-power crossfade the tail over the head."""
    fade = fade_start(y, sr)
    cut = len(y) - int(fade * sr)
    t = y[:cut]
    x = int(XFADE * sr)
    if x * 2 >= len(t):
        return None
    fin = np.sqrt(np.linspace(0.0, 1.0, x))[:, None]
    fout = np.sqrt(np.linspace(1.0, 0.0, x))[:, None]
    out = t[:-x].copy()
    out[:x] = t[-x:] * fout + t[:x] * fin
    return out


## One-shots that share the prefix and must NOT be seamed. HAND-LISTED, which is the weakest
## rung of the ladder, so it carries the backward check its class needs: an entry naming a key
## the manifest no longer has, or one that has since started reaching play_ambient, is a
## REFUSAL rather than a silent skip.
ONE_SHOT_EXCLUSIONS = {
    "weather_thunder_distant": "fired through play_battle() as a one-shot; its 1.63s decay is correct design",
}

## A key the src scan MUST find. Positive control naming a known-present member: if the scan
## dies (wrong cwd, a renamed call, the literal going const) this is the assert that notices,
## and it can come back red -- a bare "is the set non-empty" cannot tell a live scan from a
## scan that found one unrelated thing.
SCAN_CONTROL_KEY = "weather_rain"


def looping_keys():
    """Keys actually played on the looping path, read from the CONSUMER not from a name.

    A `weather_` prefix is not a corpus: weather_thunder_distant matches it and is a one-shot
    fired through play_battle(), so its 1.63s decay is correct design. Sweeping it in would
    have reported a correct asset as a defect. WeatherSystem spells every ambient as a literal
    precisely so a scan can see them.
    """
    keys = set()
    for path in Path("src").rglob("*.gd"):
        for m in re.finditer(r'play_ambient\(\s*"([^"]+)"', path.read_text(errors="ignore")):
            keys.add(m.group(1))
    return keys


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--prefix", default="weather_", help="manifest key prefix to process")
    ap.add_argument("--write", action="store_true", help="write files (default: dry run)")
    args = ap.parse_args()

    sfx = json.load(open(MANIFEST))[ROOT_KEY]
    looped = looping_keys()

    ## SET DIFFERENCE, not a narrowing filter. Every prefixed key in the MANIFEST -- a register
    ## that does not shrink when the src scan dies -- must land in exactly one bucket, and an
    ## unclassified key REFUSES. The previous shape was `k in looped`, which drains silently:
    ## a dead scan produced an empty corpus and printed its complement as "NOT a looping bed,
    ## skipped: <every weather key>", a confident and entirely wrong inventory with exit 0.
    ## Draining is now the loudest outcome rather than the quietest.
    prefixed = sorted(k for k in sfx if k.startswith(args.prefix))
    keys = [k for k in prefixed if k in looped]
    excluded = [k for k in prefixed if k not in looped and k in ONE_SHOT_EXCLUSIONS]
    unclassified = [k for k in prefixed if k not in looped and k not in ONE_SHOT_EXCLUSIONS]

    print(f"corpus: {len(prefixed)} manifest keys matching {args.prefix!r} -> "
          f"{len(keys)} looping, {len(excluded)} excluded one-shot, {len(unclassified)} unclassified")

    if SCAN_CONTROL_KEY.startswith(args.prefix) and SCAN_CONTROL_KEY not in looped:
        print(f"  REFUSED: the src scan did not find {SCAN_CONTROL_KEY}, which reaches play_ambient(). "
              f"The scan is dead, so every 'not a looping bed' verdict below would be an artifact.")
        return 1

    ## Backward arm on the hand list: an exclusion that no longer excludes anything is an
    ## unfalsifiable claim, the same shape as an inert allowlist entry.
    stale = [k for k in ONE_SHOT_EXCLUSIONS if k not in sfx or k in looped]
    if stale:
        for k in stale:
            why = "gone from the manifest" if k not in sfx else "now REACHES play_ambient()"
            print(f"  REFUSED: exclusion {k!r} is {why} — remove it, or it excuses nothing forever")
        return 1

    if unclassified:
        for k in unclassified:
            print(f"  REFUSED: {k} is in the manifest, does not reach play_ambient(), and is not "
                  f"named in ONE_SHOT_EXCLUSIONS — classify it before this tool touches anything")
        return 1

    if excluded:
        for k in excluded:
            print(f"  one-shot, not seamed: {k} — {ONE_SHOT_EXCLUSIONS[k]}")
    print(f"{'key':24} {'dur':>7} {'fade':>7} {'step before':>12} {'step after':>11}  result")

    done, refused = [], []
    for k in keys:
        path = sfx[k]["file"]
        if not Path(path).exists():
            refused.append((k, "file missing")); continue
        sr, ch, br = probe(path)
        y = decode(path, sr, ch)
        dur = len(y) / sr
        fade = fade_start(y, sr)
        before = wrap_step(y, sr)

        if fade / dur > MAX_FADE_FRAC:
            print(f"{k:24} {dur:6.2f}s {fade:6.2f}s {before:+11.1f} {'--':>11}  REGENERATE "
                  f"({100*fade/dur:.0f}% of the asset is fade)")
            refused.append((k, f"fade is {100*fade/dur:.0f}% of the asset"))
            continue

        out = seam(y, sr)
        if out is None:
            refused.append((k, "too short to crossfade")); continue
        after = wrap_step(out, sr)
        ## MAGNITUDE, not the signed value. A tail LOUDER than the head is a discontinuity too,
        ## and comparing signed steps called weather_rain (-3.6 -> +1.9) "no improvement" when
        ## |step| had almost halved. Only a PRECONDITION may be one-sided; this is the subject.
        if abs(after) >= abs(before):
            print(f"{k:24} {dur:6.2f}s {fade:6.2f}s {before:+11.1f} {after:+10.1f}  REFUSED (no improvement)")
            refused.append((k, f"step {before:+.1f} -> {after:+.1f}")); continue

        verdict = "would write" if not args.write else "written"
        if args.write:
            encode(out, sr, ch, br, path)
            chk = decode(path, sr, ch)
            after = wrap_step(chk, sr)
            verdict = f"written, verified {after:+.1f}"
        print(f"{k:24} {dur:6.2f}s {fade:6.2f}s {before:+11.1f} {after:+10.1f}  {verdict}")
        done.append(k)

    print(f"\nprocessed {len(done)}, refused {len(refused)}")
    for k, why in refused:
        print(f"  REFUSED {k}: {why}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
