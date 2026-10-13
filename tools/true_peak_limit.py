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


def probe(path: str) -> tuple[int, int]:
    """(sample_rate, channels) of the file on disk. The FILE's own format, never a default:
    this tool forced `-ar 48000` on decode and wrote its output from that, so a 44.1 kHz master
    came back resampled — the same defect test_audio_tools_do_not_assume_one_sample_rate was
    written for after crossfade_loop.py carried `SR = 48000`. Measured 2026-10-12: 19 of 161 music
    masters are 44.1 kHz, and in the sfx bank 114 of 200 sampled are STEREO with 54 at 192 kHz."""
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
                          "stream=sample_rate,channels", "-of", "csv=p=0", path],
                         capture_output=True, text=True, check=True).stdout.strip()
    parts = [x for x in out.replace("\n", ",").split(",") if x]
    if len(parts) < 2:
        raise RuntimeError("ffprobe gave no rate/channels for %s: %r" % (path, out))
    return int(parts[0]), int(parts[1])


def _read(path: str, sr: int) -> tuple[np.ndarray, int]:
    """Decode at the file's OWN rate. `sr` is passed in rather than chosen here so one probe
    answers for both the decode and the encode, and they cannot drift apart."""
    with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
        subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", path,
                        "-ar", str(sr), tmp.name], check=True)
        w = wave.open(tmp.name)
        d = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64)
        ch = w.getnchannels()
        if ch == 2:
            d = d.reshape(-1, 2).mean(axis=1)
        return d / 32768.0, ch


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--ceiling-db", type=float, default=-1.0)
    args = ap.parse_args()

    sr, ch = probe(args.src)
    ## ⛔ REFUSE a stereo master rather than silently downmixing it. The limiter works on a mono
    ## sum by construction, and the encode below forces `-ac 1`, so a stereo source came out MONO
    ## with no warning — a destructive change nobody asked a peak limiter for. 114 of 200 sampled
    ## sfx masters are stereo, including the three this file's own cost note was measured on, so
    ## this is the common case and not an edge. "I cannot do this" must not share an exit with
    ## "done": refusing costs a rerun, downmixing costs the master.
    if ch != 1:
        print("REFUSED: %s is %d-channel and this limiter is mono-only — it would ship a MONO "
              "file over your master. Downmix deliberately first, or extend the limiter to apply "
              "its envelope per channel." % (args.src, ch), file=sys.stderr)
        return 2
    x, _ = _read(args.src, sr)
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
            ## -ar is EXPLICIT so the output carries the input's rate rather than whatever the
            ## intermediate wav happened to be written at.
            subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", tmp.name,
                            "-c:a", "libvorbis", "-q:a", "5", "-ac", "1",
                            "-ar", str(sr), args.dst], check=True)
        ## ASSERT THE FORMAT ON THE ARTIFACT, BEFORE the decode that would mask it: re-reading at
        ## `sr` makes a resampled file agree with expectation, which is exactly how crossfade_loop's
        ## 48 kHz assumption verified itself clean for months.
        out_sr, out_ch = probe(args.dst)
        if out_sr != sr or out_ch != 1:
            print("the encoder changed the format: %s is %d Hz/%dch from a %d Hz/1ch source"
                  % (args.dst, out_sr, out_ch, sr), file=sys.stderr)
            return 3
        shipped, _ = _read(args.dst, sr)
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
