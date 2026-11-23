#!/usr/bin/env python3
"""The boss-charge cues (cowir-sfx, on battle's BossCadence): one for the breath being drawn, one for it breaking.

    python3 tools/gen_charge_cues.py <cue_key> <out.ogg>
    python3 tools/gen_charge_cues.py --all assets/audio/sfx
    python3 tools/gen_charge_cues.py --list

boss_charge_gather plays on BattleManager.boss_charge_changed(boss, true): the turn a boss spends winding up, so it must
read as a THREAT ARRIVING, not as a hit. It rises and never resolves, because the resolution is the signature itself,
which keeps its own ability cue. boss_charge_broken plays on boss_charge_broken: the gathered power snaps and spills out,
the player's reward for landing a stun or silence in time. It falls where the gather rose, so the pair reads as one
breath taken and lost. Both are short and dry so a charge-time music sting (cowir-music's) can sit over them.
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
from gen_sequence_beats import SR, N, at, env, hp, lp, mix, sweep  # noqa: E402


def boss_charge_gather(rng):
    d = 1.15
    n = N(d)
    rise = np.linspace(0, 1, n)
    ## The inhale: air drawn in, its band opening upward as it swells, so the ear hears it come TOWARD the room.
    inhale = hp(lp(rng.standard_normal(n), 900 + 4200 * rise ** 1.5), 300) * rise ** 2.2
    ## The power: a low body climbing a fifth and a half, with its own octave, both swelling to the cut.
    body = (sweep(70, 155, d) + .45 * sweep(140, 310, d)) * rise ** 1.6
    ## Tension at the top: a narrow shimmer whose tremolo speeds up as the breath fills.
    trem = 0.5 + 0.5 * np.sin(2 * np.pi * np.cumsum(6 + 18 * rise) / SR)
    shimmer = hp(lp(rng.standard_normal(n), 7000), 3500) * rise ** 3 * trem
    y = mix(.8 * inhale, .9 * body, .35 * shimmer)
    ## Held, not resolved: a 60 ms fade at the very end, so it stops at its loudest rather than decaying.
    f = N(.06)
    y[-f:] *= np.linspace(1, 0, f)
    return y


def boss_charge_broken(rng):
    ## The snap: a bright crack with a hard edge, the moment the stun lands on the breath.
    crack = 1.4 * hp(lp(rng.standard_normal(N(.06)), 6500), 1200) * env(N(.06), .0005, 14)
    ## The deflation: the gather's own climb run backwards and faster, power draining out.
    fall = .9 * (sweep(240, 55, .5) + .35 * sweep(480, 110, .5)) * env(N(.5), .002, 5)
    ## The spill: scattered sparks ticking away, thinning as they go.
    sparks = mix(*[at((.5 - .6 * o) * hp(rng.standard_normal(N(.025)), float(rng.uniform(2500, 5500))) * env(N(.025), .0005, 12), float(o))
                   for o in np.sort(rng.uniform(.04, .45, 10))])
    puff = .45 * lp(rng.standard_normal(N(.3)), 1400) * env(N(.3), .004, 6)
    return mix(crack, at(fall, .01), sparks, at(puff, .01))


## key -> (synth, seed, active-RMS target dB, tanh drive). The gather sits under the battle cues it precedes; the break is
## a reward and lands at a hit's level.
CUES = {
    "boss_charge_gather": (boss_charge_gather, 7501, -19.0, 0.0),
    "boss_charge_broken": (boss_charge_broken, 7502, -17.5, 1.6),
}


def render(key):
    fn, seed, target, drive = CUES[key]
    y = fn(np.random.default_rng(seed)).astype(float)
    if drive > 0.0:
        y = np.tanh(drive * y / float(np.max(np.abs(y))))
    fade = N(.02)
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
