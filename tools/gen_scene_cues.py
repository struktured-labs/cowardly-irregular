#!/usr/bin/env python3
"""Cues a staged scene plays through a `play_sfx` step (cowir-main 24231).

    python3 tools/gen_scene_cues.py <cue_key> <out.ogg>
    python3 tools/gen_scene_cues.py --all assets/audio/sfx
    python3 tools/gen_scene_cues.py --list

scene_tiny_crown_lands: the Rat King's crown on the fountain's rim (world1_briefing_skipped). Thin metal on stone, then a
roll that spins down inside the prop's own animation: tiny_crown.png lands on its frame 0 -> 1 change and is at rest two
frames later at 8 fps (0.25 s), so the last tap falls by ~0.33 s and the ring's tail carries the hold.
numpy synthesis at 44.1 kHz mono, deterministic seeds; it reads no master and rewrites none.
"""
import math
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_sequence_beats import SR, N, at, hp, lp, mix, t  # noqa: E402


def _ring(f, d, dec, g=1.0):
    tt = t(d)
    return g * sum(w * np.sin(2 * np.pi * f * r * tt) * np.exp(-tt * dec * (1 + .4 * i)) for i, (r, w) in enumerate(((1, 1), (2.32, .55), (3.87, .3), (5.9, .15))))


def _tick(rng, g):
    n = N(.012)
    return g * hp(lp(rng.standard_normal(n), 3500), 900) * np.exp(-np.arange(n) / 70)


def scene_tiny_crown_lands(rng):
    land = mix(_tick(rng, 1.0), _ring(3150, .3, 17))
    taps, when, gap, g = [], .09, .06, .5
    while gap > .015:
        taps.append(at(mix(_tick(rng, g), _ring(3250 + 400 * (.06 - gap) / .06, .06, 45, g)), when))
        when += gap
        gap *= 0.8
        g *= 0.86
    return mix(land, *taps)


# key: (generator, seed, active-RMS target dB)
CUES = {"scene_tiny_crown_lands": (scene_tiny_crown_lands, 7601, -23.0)}


def render(key):
    fn, seed, target = CUES[key]
    y = fn(np.random.default_rng(seed)).astype(float)
    fade = N(.03)
    y[-fade:] *= np.linspace(1, 0, fade)
    act = y[np.abs(y) > np.max(np.abs(y)) * 10 ** (-40 / 20)]
    y *= 10 ** ((target - 20 * math.log10(math.sqrt(float(np.mean(act ** 2))))) / 20)
    y *= min(1.0, 10 ** (-1 / 20) / float(np.max(np.abs(y))))
    return y


def write(key, out):
    y = render(key)
    wav = Path(tempfile.mkdtemp()) / "cue.wav"
    with wave.open(str(wav), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(y, -1, 1) * 32767).astype("<i2").tobytes())
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", str(wav), "-c:a", "libvorbis", "-q:a", "5", str(out)], check=True)
    wav.unlink()
    print("wrote %s (%.2fs)" % (out, len(y) / SR))


def main(argv):
    if argv[:1] == ["--list"]:
        print("\n".join(sorted(CUES)))
        return 0
    if len(argv) == 2 and argv[0] == "--all":
        for key in sorted(CUES):
            write(key, Path(argv[1]) / (key + ".ogg"))
        return 0
    if len(argv) == 2 and argv[0] in CUES:
        write(argv[0], argv[1])
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
