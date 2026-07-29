#!/usr/bin/env python3
"""Compare SFX levels across a PERCEPTUAL FAMILY, not across a processing batch.

Why this exists (2026-07-29): the 2026-07-25 declip batch (a674e423) processed
ability_ice/lightning/heal together and level-matched them to 0.2 dB -- genuinely
good work. But ability_fire had been declipped nine days earlier by a different
recipe (354dfd73) and was NOT in the batch, so it never entered the comparison.
Result: the batch widened a pre-existing fire-vs-rest gap from ~3.4 dB to ~5.8 dB.
The sibling check was real; its SCOPE was the batch when the peer group is the family.

Run this against the family BEFORE and AFTER any batch operation.

INSTRUMENT NOTES -- these cost real time to establish, do not re-derive them:
  * Integrated LUFS (ebur128 "I") is INVALID on sub-3s SFX. R128 gates 400ms
    blocks and needs ~3s; on a 1.3s cue it returns garbage. The tell is LRA
    reporting exactly 0.00. It claimed ability_lightning sat 8.1 LU below
    ability_ice when RMS puts them 0.2 dB apart.
  * ebur128 "Peak" (true peak) is likewise unreliable here: it reported
    ability_ice at +10.5 dBTP where 4x oversampling gives +1.6 -- off by 8.9 dB.
  * Use RMS for level and 4x-oversampled peak for true peak. Both are computed
    here directly rather than read off a broadcast meter.
  * Judge TIMBRE damage by spectral centroid, not brilliance %. Brilliance is a
    relative band percentage, so it moves whenever any other band moves and
    flags level changes as timbre changes.

Usage:
  tools/sfx_family_levels.py ability_fire ability_ice ability_lightning ability_heal
  tools/sfx_family_levels.py --spread 3.0 ability_fire ability_ice ability_lightning
"""

import argparse
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

import numpy as np

SFX_DIR = Path(__file__).resolve().parent.parent / "assets" / "audio" / "sfx"


def decode(ogg: Path) -> tuple[np.ndarray, int]:
    with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
        subprocess.run(
            ["ffmpeg", "-y", "-v", "error", "-i", str(ogg), "-ar", "48000", tmp.name],
            check=True,
        )
        w = wave.open(tmp.name)
        d = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64)
        if w.getnchannels() == 2:
            d = d.reshape(-1, 2).mean(axis=1)
        return d / 32768.0, w.getframerate()


def db(x: float) -> float:
    return 10 * np.log10(max(x, 1e-12))


def k_weighted_rms_db(d: np.ndarray, sr: int) -> float:
    """ITU-R BS.1770 K-weighting, then plain RMS -- LKFS without the gating.

    Plain RMS is correct for comparing ONE sound before/after processing, but it
    over-weights bass when comparing DIFFERENT sounds: a 139 Hz-centroid cue and a
    6000 Hz-centroid cue at equal RMS are not equally loud. K-weighting is the
    frequency weighting R128 uses; the part of R128 that breaks on short files is
    the 400ms block GATING, not the filter. So we take the filter and skip the gate.
    Coefficients are the BS.1770 48 kHz reference pair.
    """
    if sr != 48000:
        raise ValueError(f"K-weighting coefficients are 48 kHz; got {sr}")

    def biquad(x, b, a):
        y = np.zeros_like(x)
        x1 = x2 = y1 = y2 = 0.0
        for i, xn in enumerate(x):
            yn = b[0] * xn + b[1] * x1 + b[2] * x2 - a[1] * y1 - a[2] * y2
            y[i] = yn
            x2, x1 = x1, xn
            y2, y1 = y1, yn
        return y

    shelf_b = [1.53512485958697, -2.69169618940638, 1.19839281085285]
    shelf_a = [1.0, -1.69065929318241, 0.73248077421585]
    hp_b = [1.0, -2.0, 1.0]
    hp_a = [1.0, -1.99004745483398, 0.99007225036621]
    y = biquad(biquad(d, shelf_b, shelf_a), hp_b, hp_a)
    return db((y ** 2).mean())


def true_peak_db(d: np.ndarray) -> float:
    """True peak by definition: 4x sinc reconstruction, then sample peak."""
    up = np.zeros(len(d) * 4)
    up[::4] = d
    spec = np.fft.rfft(up)
    spec[len(spec) // 4:] = 0
    up = np.fft.irfft(spec, len(up)) * 4
    return 20 * np.log10(max(np.abs(up).max(), 1e-12))


def centroid_hz(d: np.ndarray, sr: int) -> float:
    mag = np.abs(np.fft.rfft(d * np.hanning(len(d))))
    freqs = np.fft.rfftfreq(len(d), 1.0 / sr)
    return float((freqs * mag).sum() / mag.sum()) if mag.sum() > 0 else 0.0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("keys", nargs="+", help="SFX basenames, no .ogg")
    ap.add_argument("--spread", type=float, default=3.0,
                    help="max acceptable RMS spread across the family, dB (default 3.0)")
    args = ap.parse_args()

    rows = []
    for key in args.keys:
        path = SFX_DIR / f"{key}.ogg"
        if not path.exists():
            print(f"MISSING: {path}", file=sys.stderr)
            return 2
        d, sr = decode(path)
        rows.append({
            "key": key,
            "rms": db((d ** 2).mean()),
            "lk": k_weighted_rms_db(d, sr),
            "peak": 20 * np.log10(max(np.abs(d).max(), 1e-12)),
            "tp": true_peak_db(d),
            "centroid": centroid_hz(d, sr),
        })

    print(f"{'key':<22}{'K-wtd':>9}{'RMS':>9}{'peak':>9}{'truepeak':>10}{'centroid':>11}")
    for r in rows:
        print(f"{r['key']:<22}{r['lk']:>9.1f}{r['rms']:>9.1f}{r['peak']:>9.1f}"
              f"{r['tp']:>+10.1f}{r['centroid']:>10.0f}Hz")

    fail = False

    over = [r for r in rows if r["tp"] > 0.0]
    if over:
        print(f"\nOVER FULL SCALE (true peak > 0 dBFS): "
              f"{', '.join(f'{r['key']} {r['tp']:+.1f}' for r in over)}")
        fail = True

    # Spread is judged on K-weighted level: it is the cross-cue comparison, and
    # plain RMS would rank a bass-heavy cue as loud when it is not heard that way.
    loud, quiet = max(rows, key=lambda r: r["lk"]), min(rows, key=lambda r: r["lk"])
    spread = loud["lk"] - quiet["lk"]
    print(f"\nfamily K-weighted spread: {spread:.1f} dB "
          f"({loud['key']} loudest, {quiet['key']} quietest; limit {args.spread:.1f})")
    if spread > args.spread:
        print(f"OUTLIER: {loud['key']} sits {spread:.1f} dB above {quiet['key']}. "
              f"Same-tier cues should read as peers -- a gap this size is heard as "
              f"'that spell is stronger'.")
        fail = True

    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())
