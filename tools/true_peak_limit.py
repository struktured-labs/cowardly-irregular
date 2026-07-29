#!/usr/bin/env python3
"""True-peak limiter: limit in the OVERSAMPLED domain, not on sample peaks.

Why this exists (2026-07-29): ffmpeg's `alimiter` clamps SAMPLE peaks. Inter-sample
peaks live between samples, so clamping cannot see them -- and squaring the waveform
against a ceiling ADDS high-frequency content, which can make the true peak WORSE.
Measured on w3_ability_physical: +1.1 dBTP in, +1.4 dBTP out. It also cost 2.5-2.6 dB
of K-weighted level on the cues where it did help, which is a level change dressed as
a correctness fix.

This upsamples 4x (zero-stuff + brickwall = sinc reconstruction), computes a gain
envelope against the reconstructed waveform, smooths it with lookahead so the gain
never steps, applies it, and downsamples back. Level survives because only the
overshooting moments are touched.

Usage:
  tools/true_peak_limit.py in.ogg out.ogg [--ceiling-db -1.0]
"""

import argparse
import subprocess
import sys
import tempfile
import wave

import numpy as np


def _upsample4(x: np.ndarray) -> np.ndarray:
    up = np.zeros(len(x) * 4)
    up[::4] = x
    spec = np.fft.rfft(up)
    spec[len(spec) // 4:] = 0
    return np.fft.irfft(spec, len(up)) * 4


def _downsample4(x: np.ndarray, n_out: int) -> np.ndarray:
    spec = np.fft.rfft(x)
    spec[len(spec) // 4:] = 0
    return np.fft.irfft(spec, len(x))[::4][:n_out]


def true_peak_db(x: np.ndarray) -> float:
    return 20 * np.log10(max(np.abs(_upsample4(x)).max(), 1e-12))


def limit(x: np.ndarray, sr: int, ceiling_db: float = -1.0,
          lookahead_ms: float = 1.5) -> np.ndarray:
    ceiling = 10 ** (ceiling_db / 20.0)
    up = _upsample4(x)
    mag = np.abs(up)

    # Per-sample gain needed to sit under the ceiling.
    need = np.ones_like(mag)
    over = mag > ceiling
    if not over.any():
        return x
    need[over] = ceiling / mag[over]

    # Lookahead: take the running MINIMUM so gain is already down before the peak
    # arrives, then smooth so it never steps (a stepped gain is audible as a click).
    w = max(1, int(lookahead_ms * 0.001 * sr * 4))
    pad = np.concatenate([np.ones(w), need, np.ones(w)])
    # running min via a sliding stride trick, cheap enough at these lengths
    strided = np.lib.stride_tricks.sliding_window_view(pad, 2 * w + 1)
    env = strided.min(axis=1)[:len(need)]
    kernel = np.hanning(2 * w + 1)
    kernel /= kernel.sum()
    env = np.convolve(np.concatenate([np.ones(w), env, np.ones(w)]), kernel,
                      mode="same")[w:w + len(need)]
    env = np.minimum(env, need)  # smoothing must never raise gain above what's needed

    return _downsample4(up * env, len(x))


def _read(path: str) -> tuple[np.ndarray, int, int]:
    with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
        subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", path,
                        "-ar", "48000", tmp.name], check=True)
        w = wave.open(tmp.name)
        d = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64)
        ch = w.getnchannels()
        if ch == 2:
            d = d.reshape(-1, 2).mean(axis=1)
        return d / 32768.0, 48000, ch


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--ceiling-db", type=float, default=-1.0)
    args = ap.parse_args()

    x, sr, _ = _read(args.src)
    before = true_peak_db(x)

    ## The vorbis encode RAISES true peak (measured 0.3-0.9 dB on W3-W5 cues), so
    ## limiting to the target lands the shipped file above it. Limit deeper, then
    ## verify the .ogg. The first version of this script printed its own array's
    ## peak and claimed success while the encoded file sat 0.8 dB higher -- the
    ## artifact is the .ogg, not the buffer that produced it.
    target = args.ceiling_db
    y = x
    for headroom in (0.0, 1.0, 2.0, 3.0):
        y = limit(x, sr, target - headroom)
        with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
            with wave.open(tmp.name, "wb") as w:
                w.setnchannels(1)
                w.setsampwidth(2)
                w.setframerate(sr)
                w.writeframes((np.clip(y, -1.0, 1.0) * 32767).astype(np.int16).tobytes())
            subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", tmp.name,
                            "-c:a", "libvorbis", "-q:a", "5", "-ac", "1", args.dst], check=True)
        shipped, _, _ = _read(args.dst)
        after = true_peak_db(shipped)
        if after <= target:
            print(f"  true peak {before:+.1f} -> {after:+.1f} dBTP "
                  f"(target {target:+.1f}, limited at {target - headroom:+.1f})")
            return 0
    print(f"  true peak {before:+.1f} -> {after:+.1f} dBTP "
          f"— FAILED to reach {target:+.1f} even with 3 dB of extra headroom", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())

# MEASURED COST, 2026-07-29 -- read this before proposing a batch pass.
# True-peak limiting is NOT free correctness. On the three worst W3-W5 cues:
#   w3_ability_physical  +1.1 -> -1.5 dBTP   K-wtd cost 0.9 dB   centroid -0.15%  viable
#   w5_ability_physical  +1.8 -> -1.6 dBTP   K-wtd cost 2.4 dB   centroid -6.4%   borderline
#   w4_ability_physical  +1.4 -> -1.6 dBTP   K-wtd cost 3.3 dB   centroid -12.5%  over the gate
# The overshoot in these files is sustained, not a few stray samples, so pulling it
# under the ceiling costs real level -- same finding as ability_ice. Cost is PER FILE:
# run this, measure with sfx_family_levels.py, ship what clears the centroid gate
# (<12%) and flag the rest for re-synthesis. There is no blanket batch.
# Floor cost of ANY rewrite: the ogg re-encode alone moves K-wtd ~0.3 dB.
