#!/usr/bin/env python3
"""Synthesise NES/Atari-era SFX for Cowardly Irregular.

ElevenLabs makes REALISTIC audio. struktured asked for a "rumbly atari noise similar to FF1 fire
but with our own twist" and rejected the generated fire as a "WHOOOOP" whose pitch was "not human
ear friendly" -- measured as a spectral centroid swelling 1.4k -> 4.8kHz, straight through the
band the ear is most sensitive in. Generation cannot reliably hit a chiptune target; synthesis
can, and it lets us pin the centroid by construction instead of rolling again.

FF1's fire is the NES noise channel with a falling period. Ours: that, plus a sub thump for the
rumble, bitcrushed for the era, with a short reversed pre-swell as the twist so it still reads as
magic being cast rather than an explosion.
"""
import argparse, math, subprocess, sys, tempfile
from pathlib import Path
import numpy as np

SR = 44100


def _env(n, attack, decay, floor=0.0):
    a = max(1, int(attack * n))
    e = np.empty(n, dtype=np.float64)
    e[:a] = np.linspace(0.0, 1.0, a)
    e[a:] = np.linspace(1.0, floor, n - a) ** decay
    return e


def _sweep_lowpass(x, f_start, f_end, sr=SR):
    """One-pole lowpass whose cutoff glides start->end. Keeps the centroid falling, which is the
    whole point: a rising centroid is what the rejected sound did."""
    n = len(x)
    cutoff = np.linspace(f_start, f_end, n)
    alpha = 1.0 - np.exp(-2.0 * math.pi * cutoff / sr)
    y = np.empty(n)
    acc = 0.0
    for i in range(n):
        acc += alpha[i] * (x[i] - acc)
        y[i] = acc
    return y


def _bitcrush(x, bits, hold):
    """Quantise + sample-and-hold. This is the era grit; `hold` is the effective downsample."""
    levels = 2 ** bits
    q = np.round(x * (levels / 2 - 1)) / (levels / 2 - 1)
    if hold > 1:
        idx = (np.arange(len(q)) // hold) * hold
        q = q[np.clip(idx, 0, len(q) - 1)]
    return q


def fire(dur=0.90, seed=7):
    rng = np.random.default_rng(seed)
    n = int(SR * dur)
    t = np.arange(n) / SR

    # Noise core: cutoff falls 1900 -> 170 Hz, so brightness DECAYS instead of swelling.
    noise = rng.uniform(-1.0, 1.0, n)
    core = _sweep_lowpass(noise, 1900.0, 170.0) * _env(n, 0.012, 2.2)

    # Sub thump: descending square, the "rumbly" half.
    f = np.linspace(96.0, 44.0, n)
    sub = np.sign(np.sin(2 * math.pi * np.cumsum(f) / SR)) * _env(n, 0.004, 3.4) * 0.55

    # FF1's fire stutters rather than sustaining — two extra noise hits, quieter and lower.
    body = core + sub
    for at, amp in ((0.26, 0.45), (0.46, 0.28)):
        k = int(at * n)
        seg = n - k
        h = _sweep_lowpass(rng.uniform(-1, 1, seg), 900.0, 130.0) * _env(seg, 0.006, 2.6) * amp
        body[k:] += h

    # Our twist: a short reversed swell in front, so it reads as a CAST, not a detonation.
    pre_n = int(0.16 * SR)
    pre = _sweep_lowpass(rng.uniform(-1, 1, pre_n), 700.0, 240.0)
    pre *= np.linspace(0.0, 0.5, pre_n) ** 2.0
    out = np.concatenate([pre, body])

    out = _bitcrush(out, bits=5, hold=4)          # 5-bit, ~11 kHz effective
    # Sample-and-hold aliases energy back above 4kHz -- authentic to the chip, but that band is
    # exactly what struktured rejected as "not human ear friendly". Real NES output went through an
    # analog lowpass on the way to the speaker; without one the crush undoes the falling sweep.
    out = _sweep_lowpass(out, 2600.0, 1500.0)
    out /= max(np.max(np.abs(out)), 1e-9)
    return (out * 0.85).astype(np.float32)


def fire_burst(dur=0.72, seed=11):
    """Rotation sibling: shorter, harder hit, no pre-swell. Same voice, different phrasing."""
    rng = np.random.default_rng(seed)
    n = int(SR * dur)
    core = _sweep_lowpass(rng.uniform(-1, 1, n), 2200.0, 150.0) * _env(n, 0.006, 2.8)
    f = np.linspace(110.0, 40.0, n)
    sub = np.sign(np.sin(2 * math.pi * np.cumsum(f) / SR)) * _env(n, 0.003, 3.8) * 0.62
    out = core + sub
    k = int(0.30 * n)
    seg = n - k
    out[k:] += _sweep_lowpass(rng.uniform(-1, 1, seg), 800.0, 120.0) * _env(seg, 0.005, 3.0) * 0.36
    out = _bitcrush(out, bits=4, hold=5)
    out = _sweep_lowpass(out, 2400.0, 1300.0)
    out /= max(np.max(np.abs(out)), 1e-9)
    return (out * 0.85).astype(np.float32)


def fire_roar(dur=1.15, seed=23):
    """Rotation sibling: longest, a sustained rumble with a slow crumble rather than a hit."""
    rng = np.random.default_rng(seed)
    n = int(SR * dur)
    core = _sweep_lowpass(rng.uniform(-1, 1, n), 1500.0, 200.0) * _env(n, 0.055, 1.5)
    f = np.linspace(78.0, 48.0, n)
    sub = np.sign(np.sin(2 * math.pi * np.cumsum(f) / SR)) * _env(n, 0.02, 2.0) * 0.50
    out = core + sub
    for at, amp in ((0.34, 0.30), (0.58, 0.24), (0.78, 0.18)):
        k = int(at * n); seg = n - k
        out[k:] += _sweep_lowpass(rng.uniform(-1, 1, seg), 700.0, 110.0) * _env(seg, 0.008, 3.2) * amp
    out = _bitcrush(out, bits=5, hold=4)
    out = _sweep_lowpass(out, 2200.0, 1200.0)
    out /= max(np.max(np.abs(out)), 1e-9)
    return (out * 0.85).astype(np.float32)


VOICES = {"fire": fire, "fire_burst": fire_burst, "fire_roar": fire_roar}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("voice", choices=sorted(VOICES))
    ap.add_argument("out")
    ap.add_argument("--seed", type=int, default=7)
    a = ap.parse_args()
    y = VOICES[a.voice](seed=a.seed)
    wav = Path(tempfile.mktemp(suffix=".wav"))
    import wave
    with wave.open(str(wav), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(y, -1, 1) * 32767).astype("<i2").tobytes())
    out = Path(a.out); out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(wav), "-c:a", "libvorbis",
                    "-q:a", "4", "-ac", "1", str(out)], check=True)
    wav.unlink(missing_ok=True)
    print("wrote %s (%.2fs, %d bytes)" % (out, len(y) / SR, out.stat().st_size))


if __name__ == "__main__":
    main()
