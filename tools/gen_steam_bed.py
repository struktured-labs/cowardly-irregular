#!/usr/bin/env python3
"""Synthesise weather_steam as a bed that loops BY CONSTRUCTION.

Why this is not an ElevenLabs regen: the generator returns one-shots. That is how the
defect arose -- the shipped weather_steam is 3.0s of fade in a 5.0s file (60%), tail
-78 dBFS against a -25 dBFS head, +53 dB wrap step at a 50 ms window. Asking a one-shot
generator for a seamless loop and then repairing the seam is the loop we were already in.

Steam is broadband noise, which is the one texture where synthesis beats generation for
this purpose: build the spectrum, inverse-FFT it, and the result is PERIODIC WITH PERIOD
EQUAL TO THE BUFFER. The wrap is seamless as a property of the maths, not of a crossfade
-- head and tail are the same phase because they are the same cycle.

Matched to the shipped asset's own character, measured over its first 2.0s (the part that
is actually the bed rather than the decay):

    RMS -22.1 dBFS · centroid 3278 Hz · flatness 0.0001
    0-250 Hz 47.1% · 250-1k 0.6% · 1k-4k 15.7% · 4k-10k 27.8% · 10k+ 8.9%

The scooped mid is the shape that reads as "pressure vessel" rather than "static": a low
rumble for the body and a high hiss for the escape, with very little between them.

Amplitude modulation uses an INTEGER number of cycles across the buffer for the same
reason as the noise -- a non-integer count would put a step at the wrap and undo the point.
"""

import argparse
import subprocess
import sys
from pathlib import Path

import numpy as np

## ⚠️ A HARDCODED RATE IS THE SHAPE THAT SILENTLY RESAMPLED 19 MUSIC BEDS (cowir-music, 2026-09-11):
## their tool carried SR = 48000 under the word "measured", decoded/encoded/verified at 48k, and so
## resampled every 44.1 kHz source back into agreement before any check looked. This is a GENERATOR,
## not a transformer, so it has no source to preserve — but it OVERWRITES an existing asset, and
## main() refuses if that asset's rate differs from this constant rather than quietly downsampling it.
SR = 44100
DUR = 8.0            # longer than the 5.0s original: a continuous bed repeats less obviously
TARGET_RMS_DB = -22.1

## (low, high, share of total power) measured from the shipped asset's first 2 seconds.
BANDS = [(20, 250, 0.471), (250, 1000, 0.006), (1000, 4000, 0.157),
         (4000, 10000, 0.278), (10000, 20000, 0.089)]

## Breathing. Integer cycle counts over the buffer so the envelope wraps as cleanly as the noise.
BREATHS = [(2, 0.13), (5, 0.06)]


def periodic_noise(n, rng):
    """Noise whose last sample flows into its first: built in the frequency domain."""
    spec = np.zeros(n // 2 + 1, dtype=complex)
    mag = rng.normal(0.0, 1.0, len(spec))
    phase = rng.uniform(0.0, 2.0 * np.pi, len(spec))
    spec = mag * np.exp(1j * phase)
    spec[0] = 0.0                      # no DC
    if n % 2 == 0:
        spec[-1] = spec[-1].real       # Nyquist bin must be real for a real signal
    return np.fft.irfft(spec, n)


def shaped(n, rng):
    """Sum of band-limited periodic noises at the measured power ratios."""
    freqs = np.fft.rfftfreq(n, 1 / SR)
    out = np.zeros(n)
    for lo, hi, share in BANDS:
        base = periodic_noise(n, rng)
        S = np.fft.rfft(base)
        S[(freqs < lo) | (freqs >= hi)] = 0.0
        band = np.fft.irfft(S, n)
        r = np.sqrt((band ** 2).mean())
        if r > 0:
            out += band / r * np.sqrt(share)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="assets/audio/sfx/weather_steam.ogg")
    ap.add_argument("--seed", type=int, default=20260911)
    ap.add_argument("--bitrate", default="80000")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    # REFUSE rather than resample: the file we are about to replace decides the rate.
    if Path(args.out).exists():
        have = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a:0",
                               "-show_entries", "stream=sample_rate", "-of", "csv=p=0", args.out],
                              capture_output=True, text=True).stdout.strip()
        if have and int(have) != SR:
            print(f"  REFUSED: {args.out} is {have} Hz, this generator writes {SR} Hz — "
                  f"writing would resample the asset. Set SR to match, or retarget.")
            return 1

    n = int(DUR * SR)
    rng = np.random.default_rng(args.seed)
    y = shaped(n, rng)

    t = np.arange(n) / SR
    env = np.ones(n)
    for cycles, depth in BREATHS:
        env *= 1.0 + depth * np.sin(2.0 * np.pi * cycles * t / DUR)
    y *= env

    y *= 10 ** (TARGET_RMS_DB / 20) / np.sqrt((y ** 2).mean())
    peak = np.abs(y).max()
    if peak > 0.99:
        y *= 0.99 / peak

    # The claim this file makes about itself, checked before it writes.
    w = int(0.050 * SR)
    step = 20 * np.log10(np.sqrt((y[:w] ** 2).mean()) / np.sqrt((y[-w:] ** 2).mean()))
    print(f"  dur {n/SR:.2f}s  rms {20*np.log10(np.sqrt((y**2).mean())):.1f} dBFS  "
          f"peak {np.abs(y).max():.3f}  wrap step {step:+.2f} dB")
    P = np.abs(np.fft.rfft(y * np.hanning(n))) ** 2
    f = np.fft.rfftfreq(n, 1 / SR)
    print(f"  centroid {(P*f).sum()/P.sum():.0f} Hz")
    for lo, hi, want in BANDS:
        b = (f >= lo) & (f < hi)
        print(f"    {lo:>5}-{hi:<5} Hz  {100*P[b].sum()/P.sum():5.1f}%  (target {100*want:.1f}%)")
    if abs(step) > 1.0:
        print("  REFUSED: wrap step exceeds 1 dB — the construction guarantee did not hold")
        return 1
    if args.dry_run:
        print("  dry run, nothing written")
        return 0

    subprocess.run(["ffmpeg", "-v", "quiet", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1",
                    "-i", "-", "-c:a", "libvorbis", "-b:a", args.bitrate, args.out],
                   input=y.astype(np.float32).tobytes(), check=True)
    print(f"  wrote {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
