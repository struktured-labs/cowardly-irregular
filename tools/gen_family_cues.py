#!/usr/bin/env python3
"""The W1 monster-family cues, the tier-2 ice/thunder impacts and the wore-off cue (cowir-main 23993 / 24019).

    python3 tools/gen_family_cues.py <cue_key> <out.ogg>
    python3 tools/gen_family_cues.py --all assets/audio/sfx
    python3 tools/gen_family_cues.py --list

Each cue is ONE event, keyed on the phase where that event is drawn. A phase runs on battle time and a file plays on
real time, so a cue that held two events (a spit's pop and its splat) would drift apart as the battle speed changes.
The families sound ON TOP of the ordinary hit cue (adhoc 24063), which still plays: each is levelled so hit + family is at
most ~+4 dB over the hit alone, because a monster's plain attack plays its family and these are heard every turn.
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
from gen_sequence_beats import SR, N, at, bell, env, hp, lp, mix, sweep, t  # noqa: E402


def _click(rng, n, hpf, tau):
    return hp(rng.standard_normal(n), hpf) * np.exp(-np.arange(n) / tau)


def family_bite(rng):
    crunch = hp(lp(rng.standard_normal(N(.12)), 900), 250) * env(N(.12), .002, 9)
    thud = np.sin(2 * np.pi * np.cumsum(170 * np.exp(-t(.14) * 20) + 60) / SR) * np.exp(-t(.14) * 22)
    return mix(_click(rng, N(.03), 1800, 120), at(0.8 * _click(rng, N(.035), 1200, 160), .022), at(1.1 * crunch, .02), at(0.3 * thud, .02))


def family_bite_big(rng):
    tear = hp(lp(rng.standard_normal(N(.2)), 2600), 500) * env(N(.2), .01, 6) * (0.6 + 0.4 * np.sign(np.sin(2 * np.pi * 38 * t(.2))))
    low = np.sin(2 * np.pi * np.cumsum(130 * np.exp(-t(.22) * 11) + 55) / SR) * np.exp(-t(.22) * 12)
    return mix(family_bite(rng), at(0.9 * tear, .06), at(0.3 * low, .02))


def family_claw(rng):
    y = np.zeros(N(.34))
    for k, off in enumerate((0.0, .045, .09)):
        d = .17
        n = N(d)
        tt = t(d)
        rake = hp(lp(rng.standard_normal(n), 6500 * np.exp(-tt * 9) + 700), 500) * np.sin(np.pi * np.minimum(1, tt / d)) ** .6 * np.exp(-tt * 9)
        y[N(off):N(off) + n] += (1.0 - .15 * k) * rake
    return mix(y, at(0.5 * _click(rng, N(.05), 2500, 300), .1))


def family_slam(rng):
    d = .5
    tt = t(d)
    boom = np.sin(2 * np.pi * np.cumsum(95 * np.exp(-tt * 9) + 38) / SR) * np.exp(-tt * 8)
    thump = lp(rng.standard_normal(N(.09)), 500) * env(N(.09), .002, 8)
    dust = lp(hp(rng.standard_normal(N(.4)), 600), 2600) * env(N(.4), .03, 6) * .35
    smack = hp(lp(rng.standard_normal(N(.07)), 1400), 260) * env(N(.07), .001, 10)
    body = np.sin(2 * np.pi * np.cumsum(330 * np.exp(-tt * 16) + 150) / SR) * np.exp(-tt * 14)
    return mix(0.6 * boom, 0.7 * thump, 1.3 * smack, 0.8 * body, at(1.6 * dust, .04))


def family_slam_quake(rng):
    d = .7
    tt = t(d)
    rumble = lp(rng.standard_normal(len(tt)), 260) * np.minimum(1, tt / .05) * np.exp(-tt * 4.5) * (0.7 + 0.3 * np.sin(2 * np.pi * 13 * tt))
    stones = np.zeros(len(tt))
    for k in range(7):
        p0 = int((0.18 + 0.065 * k + 0.01 * rng.random()) * SR)
        stones[p0:p0 + 500] += hp(rng.standard_normal(500), 1500) * np.exp(-np.arange(500) / 60) * (0.5 - 0.05 * k)
    return mix(family_slam(rng), at(1.4 * rumble, .03), 0.5 * stones)


def family_spit(rng):
    """The LANDING only: the projectile's flight is the bolt phase, drawn in battle time."""
    splat = lp(rng.standard_normal(N(.14)), 2200 * np.exp(-t(.14) * 14) + 300) * env(N(.14), .002, 9)
    blob = np.sin(2 * np.pi * np.cumsum(260 + 180 * np.sin(2 * np.pi * 21 * t(.12))) / SR) * np.exp(-t(.12) * 18) * .4
    wet = hp(lp(rng.standard_normal(N(.2)), 3800), 1200) * env(N(.2), .004, 9) * .45
    return mix(splat, at(blob, .01), wet)


def family_spray(rng):
    d = .42
    tt = t(d)
    hiss = hp(lp(rng.standard_normal(len(tt)), 5200 - 2500 * tt / d), 900) * np.minimum(1, tt / .015) * np.exp(-tt * 6)
    patter = np.zeros(len(tt))
    for k in range(10):
        p0 = int((0.16 + 0.024 * k + 0.008 * rng.random()) * SR)
        patter[p0:p0 + 300] += lp(rng.standard_normal(300), 2400) * np.exp(-np.arange(300) / 45) * 0.6
    return mix(hiss, patter)


def family_screech(rng):
    d = .6
    tt = t(d)
    f = 1500 * (1 + .35 * np.sin(np.pi * tt / d)) * (1 + .04 * np.sin(2 * np.pi * 31 * tt))
    ph = 2 * np.pi * np.cumsum(f) / SR

    def saw(p):
        return 2 * ((p / (2 * np.pi)) % 1) - 1

    voice = hp(lp(saw(ph) + .7 * saw(ph * 1.013) + .4 * saw(ph * 1.5), 5200), 700)
    rasp = hp(rng.standard_normal(len(tt)), 2500) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 62 * tt)))
    return (voice + .45 * rasp) * np.minimum(1, tt / .03) * np.minimum(1, (d - tt) / .12)


def family_drain(rng):
    """The life flying BACK (the reversed bolt): the outgoing dark already carries the void beats."""
    d = .46
    back = sum(w * sweep(f, f * 1.9, d) for f, w in ((300, 1.0), (452, .5), (905, .2))) * np.sin(np.linspace(0, np.pi, N(d))) ** 1.3
    air = hp(lp(rng.standard_normal(N(d)), 2600), 500) * np.sin(np.linspace(0, np.pi, N(d))) ** 2 * .3
    return mix(back, air)


def family_cloud(rng):
    thup = lp(rng.standard_normal(N(.08)), 700) * env(N(.08), .003, 9)
    d = .8
    tt = t(d)
    gas = hp(lp(rng.standard_normal(len(tt)), 1500 + 900 * np.sin(np.pi * tt / d)), 350) * np.sin(np.pi * tt / d) ** 1.3 * .7
    bubbles = np.zeros(len(tt))
    for k in range(6):
        p0 = int((0.15 + 0.1 * k + 0.02 * rng.random()) * SR)
        n = N(.05)
        bubbles[p0:p0 + n] += np.sin(2 * np.pi * np.cumsum(380 + 500 * t(.05) / .05 + 60 * k) / SR) * np.exp(-t(.05) * 40) * .35
    return mix(thup, at(gas, .04), bubbles)


def family_dust(rng):
    """The grit HITTING and raining back: the whip-up and the throw are drawn phases."""
    hit = hp(rng.standard_normal(N(.12)), 2200) * env(N(.12), .004, 8)
    body = hp(lp(rng.standard_normal(N(.1)), 1500), 400) * env(N(.1), .003, 9) * .6
    rain = hp(rng.standard_normal(N(.45)), 3500) * np.exp(-t(.45) * 6) * (rng.random(N(.45)) > .55) * .5
    return mix(hit, body, at(rain, .08))


def beat_blizzara_impact(rng):
    shards = mix(*[at(bell(f, .5, 7.0, ((1, 1), (2.41, .5), (4.3, .25))) * g, o) for f, g, o in ((1980, .5, .02), (2640, .4, .07), (3520, .32, .13), (4400, .22, .2))])
    hiss = hp(lp(rng.standard_normal(N(.85)), 7000), 2200) * env(N(.85), .02, 4.5) * .45
    drop = np.sin(2 * np.pi * np.cumsum(140 * np.exp(-t(.5) * 7) + 48) / SR) * np.exp(-t(.5) * 6)
    body = lp(hp(rng.standard_normal(N(.2)), 300), 1500) * env(N(.2), .003, 8)
    return mix(_click(rng, N(.06), 1800, 240), 1.3 * shards, at(hiss, .03), 0.5 * drop, 1.2 * body)


def beat_thundara_impact(rng):
    """ONE bigger strike: thundara's second strike is its own eruption phase, with the tier-1 crack."""
    tail = 1.1
    zap = sweep(2600, 180, .18) * np.exp(-t(.18) * 12) * np.sign(np.sin(2 * np.pi * 95 * t(.18)))
    roll = lp(rng.standard_normal(N(tail)), 420 * np.exp(-t(tail) * 2.2) + 90) * env(N(tail), .01, 3.6) * 1.6
    snap = hp(lp(rng.standard_normal(N(.12)), 3200), 500) * env(N(.12), .002, 9)
    return mix(_click(rng, N(.05), 900, 200), 0.6 * zap, at(roll, .02), 0.7 * snap)


def effect_wore_off(rng):
    d = .34
    tt = t(d)
    tone = sum(w * np.sin(2 * np.pi * np.cumsum(f * (1 - .18 * tt / d)) / SR) for f, w in ((880, 1.0), (1318.5, .45))) * np.minimum(1, tt / .02) * np.exp(-tt * 11)
    air = hp(lp(rng.standard_normal(len(tt)), 3200), 700) * np.sin(np.pi * tt / d) ** 2 * .35
    return tone + air


# key: (generator, seed, active-RMS target dB, tanh drive). Drive lifts a short transient's body under its own peak.
CUES = {
    "family_bite": (family_bite, 7201, -19.5, 2.5),
    "family_bite_big": (family_bite_big, 7206, -19.5, 2.5),
    "family_claw": (family_claw, 7202, -19.5, 0.0),
    "family_slam": (family_slam, 7203, -21.5, 2.0),
    "family_slam_quake": (family_slam_quake, 7207, -20.0, 2.0),
    "family_spit": (family_spit, 7204, -20.0, 0.0),
    "family_spray": (family_spray, 7208, -20.5, 0.0),
    "family_screech": (family_screech, 7205, -20.0, 0.0),
    "family_drain": (family_drain, 7209, -20.0, 0.0),
    "family_cloud": (family_cloud, 7210, -20.5, 0.0),
    "family_dust": (family_dust, 7211, -20.5, 2.0),
    "beat_blizzara_impact": (beat_blizzara_impact, 7401, -17.8, 0.0),
    "beat_thundara_impact": (beat_thundara_impact, 7402, -17.4, 2.2),
    "effect_wore_off": (effect_wore_off, 7301, -24.0, 0.0),
}


def render(key):
    fn, seed, target, drive = CUES[key]
    y = fn(np.random.default_rng(seed)).astype(float)
    if drive > 0.0:
        y = np.tanh(drive * y / float(np.max(np.abs(y))))
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
