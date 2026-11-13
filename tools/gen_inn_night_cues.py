#!/usr/bin/env python3
"""The inn night's three cues (cowir-main 24205), keyed on InnRestSequence's beats.

    python3 tools/gen_inn_night_cues.py <cue_key> <out.ogg>
    python3 tools/gen_inn_night_cues.py --all assets/audio/sfx
    python3 tools/gen_inn_night_cues.py --list

The ditty that scores the night (inn_rest_ditty, 5.70 s) keeps 89% of its energy under 800 Hz and under 3% above
2.5 kHz, so the night air and the dawn birds are written ABOVE it and the lamp plays in the 0.6 s before it starts.
All three share one voice (the cutscene player), so each replaces the last and one stop cuts whichever is sounding.
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
from gen_sequence_beats import SR, N, at, env, hp, lp, mix, t  # noqa: E402


def inn_night_falls(rng):
    """The lamp turned down and the room settling: fits the 0.6 s fade before the ditty's first note."""
    click = hp(rng.standard_normal(N(.02)), 2500) * np.exp(-np.arange(N(.02)) / 90)
    d = .5
    tt = t(d)
    wick = sum(w * np.sin(2 * np.pi * np.cumsum(f * (1 - .35 * tt / d)) / SR) for f, w in ((1320, 1.0), (1980, .4))) * np.exp(-tt * 7) * np.minimum(1, tt / .01)
    breath = hp(lp(rng.standard_normal(len(tt)), 2600 * np.exp(-tt * 4) + 500), 300) * np.exp(-tt * 6) * .5
    creak = np.sin(2 * np.pi * np.cumsum(190 + 60 * np.sin(2 * np.pi * 9 * t(.16))) / SR) * env(N(.16), .02, 7) * .35
    return mix(click, at(0.7 * wick, .015), at(breath, .02), at(creak, .3))


def inn_night_air(rng):
    """Crickets and a breath of air, all above 3 kHz so the ditty's bass has the floor to itself."""
    d = 4.0
    tt = t(d)
    y = np.zeros(len(tt))
    for f, rate, phase, g in ((4300, 17.0, 0.0, 1.0), (5200, 21.0, 1.3, .7), (6100, 14.0, 2.1, .5)):
        chirp = (np.sin(2 * np.pi * rate * tt + phase) > 0.2).astype(float)
        burst = (np.sin(2 * np.pi * 0.9 * tt + phase * 2) > -0.2).astype(float)
        y += g * np.sin(2 * np.pi * f * tt) * lp(chirp * burst, 400)
    air = hp(rng.standard_normal(len(tt)), 3500) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.31 * tt)) * .25
    shape = np.minimum(1, tt / .5) * np.minimum(1, (d - tt) / .7)
    return hp(y + air, 3000) * shape


def inn_dawn(rng):
    """Two birds and the light coming up: lands where the rest is named, over the ditty's last note and tail."""
    def chirp(f0, f1, d):
        tt = t(d)
        return np.sin(2 * np.pi * np.cumsum(f0 + (f1 - f0) * (tt / d) ** .6) / SR) * np.sin(np.pi * tt / d) ** .7

    bird_a = mix(chirp(3100, 4300, .09), at(chirp(3400, 4600, .08), .13), at(chirp(3000, 4100, .11), .27))
    bird_b = mix(chirp(4200, 3300, .07), at(chirp(4400, 3500, .07), .11))
    d = 1.3
    tt = t(d)
    warm = sum(w * np.sin(2 * np.pi * f * tt) for f, w in ((523.25, 1.0), (783.99, .6), (1046.5, .35))) * np.sin(np.pi * tt / d) ** 1.5 * .28
    shimmer = hp(rng.standard_normal(len(tt)), 6000) * (tt / d) * np.minimum(1, (d - tt) / .3) * .12
    return mix(warm, shimmer, at(0.9 * bird_a, .1), at(0.7 * bird_b, .62), at(0.6 * bird_a, .9))


# key: (generator, seed, active-RMS target dB)
CUES = {"inn_night_falls": (inn_night_falls, 7501, -21.0), "inn_night_air": (inn_night_air, 7502, -31.0), "inn_dawn": (inn_dawn, 7503, -21.0)}


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
