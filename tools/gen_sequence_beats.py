#!/usr/bin/env python3
"""Synthesise the per-phase beat cues the ability sequences name in data/vfx_sequences.json (cowir-sfx).

    python3 tools/gen_sequence_beats.py <beat_key> <out.ogg>
    python3 tools/gen_sequence_beats.py --all assets/audio/sfx
    python3 tools/gen_sequence_beats.py --list

GENERATES each cue from numpy at 44.1 kHz mono, the rate the samples are made at; no master is its input. Each
beat is levelled to an ACTIVE-RMS target (samples above -40 dBFS), then peak-capped at -1 dBFS, so a family sits
together: the sequence beats that shipped first measure -16.3 dB (beat_fire_impact and its siblings), and that
is the default here. A beat that plays ON TOP of a weapon hit (the melee overlays) targets lower.
Deterministic: every beat has its own seed, so a re-run writes the same samples.
"""
import math
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

import numpy as np

SR = 44100
REF_DB = -16.3


def t(d):
    return np.arange(int(d * SR)) / SR


def env(n, a=0.005, curve=4.0):
    x = np.arange(n) / SR
    return np.minimum(1, x / max(a, 1e-4)) * np.exp(-curve * x / max(n / SR, 1e-3))


def swell(n, power=2.0):
    return np.sin(np.linspace(0, np.pi, n)) ** power


def lp(x, fc):
    """One-pole lowpass; fc may be a number or a per-sample array (a swept cutoff)."""
    a = np.exp(-2 * np.pi * np.broadcast_to(np.asarray(fc, dtype=float), x.shape) / SR)
    y = np.zeros_like(x)
    s = 0.0
    for i in range(len(x)):
        s = (1 - a[i]) * x[i] + a[i] * s
        y[i] = s
    return y


def hp(x, fc):
    return x - lp(x, fc)


def sweep(f0, f1, d):
    tt = t(d)
    return np.sin(2 * np.pi * np.cumsum(f0 * (f1 / f0) ** (tt / d)) / SR)


def bell(f, d, dec=6.0, parts=((1, 1), (2.76, .45), (5.4, .2))):
    tt = t(d)
    return sum(w * np.sin(2 * np.pi * f * r * tt) * np.exp(-tt * dec * (1 + .5 * r)) for r, w in parts)


def mix(*parts):
    y = np.zeros(max(len(p) for p in parts))
    for p in parts:
        y[:len(p)] += p
    return y


def at(x, sec):
    y = np.zeros(int(sec * SR) + len(x))
    y[int(sec * SR):] = x
    return y


def N(d):
    return int(d * SR)


# --- Fire tier (battle 23590/23593): the tier is heard AT the hit. fire keeps beat_fire_impact. ---
def beat_fira_impact(rng):
    """Fira's eruption: Fire's impact with a longer roar, a deeper sub and a second crackle."""
    return mix(1.5 * lp(rng.standard_normal(N(.95)), 1700) * env(N(.95), .003, 4.5),
               .9 * sweep(66, 29, .95) * env(N(.95), .003, 3.6),
               .3 * hp(lp(rng.standard_normal(N(.6)), 2000), 400) * env(N(.6), .004, 5),
               .28 * hp(rng.standard_normal(N(.3)), 4000) * env(N(.3), .002, 8),
               at(.22 * hp(rng.standard_normal(N(.25)), 3200) * env(N(.25), .002, 7), .16))


def beat_firaga_impact(rng):
    """Firaga's eruption: a wider, hotter roar over a 60->26 Hz fall, with a low whump under the first crack."""
    return mix(2.0 * lp(rng.standard_normal(N(1.05)), 2000) * env(N(1.05), .003, 4.0),
               .9 * sweep(60, 26, 1.05) * env(N(1.05), .003, 3.2),
               .6 * hp(lp(rng.standard_normal(N(.8)), 2200), 400) * env(N(.8), .004, 4.5),
               .7 * sweep(140, 55, .25) * env(N(.25), .002, 6),
               .30 * hp(rng.standard_normal(N(.35)), 3800) * env(N(.35), .002, 7),
               at(.24 * hp(rng.standard_normal(N(.3)), 3000) * env(N(.3), .002, 6), .14),
               at(.18 * hp(rng.standard_normal(N(.25)), 3400) * env(N(.25), .002, 7), .30))


def beat_firaga_detonate(rng):
    """Firaga's SECOND detonation: a short inward suck, then the biggest boom of the family and a long rumble."""
    suck = lp(rng.standard_normal(N(.09)), 2400) * np.linspace(0, 1, N(.09)) ** 3 * .6
    boom = mix(2.2 * lp(rng.standard_normal(N(1.1)), 1800) * env(N(1.1), .002, 3.2),
               1.0 * sweep(55, 22, 1.1) * env(N(1.1), .002, 2.8),
               .7 * hp(lp(rng.standard_normal(N(.9)), 2200), 380) * env(N(.9), .003, 3.6),
               .9 * sweep(180, 48, .22) * env(N(.22), .001, 6),
               .35 * hp(rng.standard_normal(N(.2)), 3500) * env(N(.2), .001, 10))
    return mix(suck, at(boom, .09))


# --- Fighter / Rogue overlays (sprites 23770/23781). They sound ON TOP of the weapon hit. ---
def beat_power_strike_impact(rng):
    """Power Strike's ground crack: a stone crack, a 90->38 Hz thud, then rubble ticking down."""
    rubble = mix(*[at(.35 * lp(rng.standard_normal(N(.05)), float(rng.uniform(900, 2200))) * env(N(.05), .001, 9), float(o))
                   for o in np.sort(rng.uniform(.10, .5, 9))])
    return mix(1.4 * hp(lp(rng.standard_normal(N(.12)), 3500), 700) * env(N(.12), .0008, 8),
               .8 * sweep(90, 38, .45) * env(N(.45), .002, 5),
               1.1 * hp(lp(rng.standard_normal(N(.35)), 1400), 250) * env(N(.35), .002, 6),
               1.6 * rubble)


def beat_cleave_sweep(rng):
    """Cleave's crescent: one blade whoosh across the whole line, bright in the middle, with a thin steel shimmer."""
    n = N(.42)
    fc = 350 + 1500 * swell(n, 1.5)
    src = rng.standard_normal(n)
    whoosh = lp(lp(src, fc) - lp(src, fc * .35), 2600) * swell(n, 2.0)
    return mix(whoosh, .05 * bell(1568, .42, dec=7, parts=((1, 1), (1.5, .5))) * swell(n, 1.0))


def beat_shield_bash_impact(rng):
    """Shield Bash: a blunt wall, not a cut. A dull thud, a 110->55 Hz body and a short flat clang of plate."""
    return mix(lp(rng.standard_normal(N(.3)), 520) * env(N(.3), .002, 8),
               1.1 * sweep(110, 55, .35) * env(N(.35), .002, 6),
               .9 * hp(lp(rng.standard_normal(N(.12)), 1800), 350) * env(N(.12), .001, 9),
               .9 * bell(318, .45, dec=9, parts=((1, 1), (2.31, .7), (3.87, .4))))


def beat_backstab_crit(rng):
    """Backstab's crit bloom: a thin fast slice, then a dark tone dropping away under it."""
    return mix(hp(rng.standard_normal(N(.07)), 5000) * env(N(.07), .0006, 9),
               at(.8 * sweep(900, 280, .26) * env(N(.26), .002, 7), .03),
               at(.6 * sweep(120, 60, .2) * env(N(.2), .002, 7), .03))


def beat_smoke_bomb_puff(rng):
    """Smoke Bomb's billow: a soft burst that opens fast and thins slowly. No click, no tone."""
    n = N(.75)
    e = np.minimum(1, np.arange(n) / (SR * .03)) * np.exp(-3.2 * np.arange(n) / n)
    return lp(lp(rng.standard_normal(n), np.linspace(1300, 380, n)), 1800) * e


def beat_scan_lock(rng):
    """Scan's brackets locking: two quick rising blips and a confirm tick."""
    blip = lambda f, d: np.sign(np.sin(2 * np.pi * f * t(d))) * env(N(d), .001, 6) * .5
    return mix(blip(1175, .05), at(blip(1568, .05), .07), at(.9 * bell(2349, .2, dec=12, parts=((1, 1), (2.0, .3))), .14))


# --- Cleric (cutscenes 23771/23775). Heals carry NO beat (struktured: choir only); Raise is a revive. ---
def beat_raise_halo(rng):
    """Raise's ground halo: a warm bell chord blooming open over a breath of air and a soft low body."""
    n = N(1.1)
    chord = sum(w * bell(f, 1.1, dec=2.6, parts=((1, 1), (2.0, .35), (3.0, .12)))
                for f, w in ((523.25, 1.0), (783.99, .8), (1046.5, .6), (1318.5, .4)))
    bloom = np.minimum(1, np.arange(n) / (SR * .06))
    air = .35 * hp(lp(rng.standard_normal(n), 5000), 1500) * swell(n, 1.2)
    return mix(chord * bloom, air, .5 * sweep(131, 131, 1.1) * env(n, .05, 3))


BEATS = {
    "beat_fira_impact": (beat_fira_impact, 11, REF_DB + 1.0),
    "beat_firaga_impact": (beat_firaga_impact, 13, REF_DB + 2.0),
    "beat_firaga_detonate": (beat_firaga_detonate, 17, REF_DB + 2.3),
    "beat_power_strike_impact": (beat_power_strike_impact, 19, -18.0),
    "beat_cleave_sweep": (beat_cleave_sweep, 23, -18.0),
    "beat_shield_bash_impact": (beat_shield_bash_impact, 29, -18.0),
    "beat_backstab_crit": (beat_backstab_crit, 31, -18.0),
    "beat_smoke_bomb_puff": (beat_smoke_bomb_puff, 37, -19.0),
    "beat_scan_lock": (beat_scan_lock, 41, -19.0),
    "beat_raise_halo": (beat_raise_halo, 43, REF_DB),
}


## tanh drive: the low body sets the peak, so without it a bigger tier cannot be louder under the -1 dBFS cap.
DRIVE = {"beat_fira_impact": 1.6, "beat_firaga_impact": 2.2, "beat_firaga_detonate": 2.6,
         "beat_power_strike_impact": 2.0, "beat_shield_bash_impact": 2.0}


## A two-pole lowpass AFTER the drive: saturation adds harmonics above 4 kHz, and fire must stay a rumble, not a hiss.
DARKEN = {"beat_fira_impact": 3200.0, "beat_firaga_impact": 3200.0, "beat_firaga_detonate": 2800.0}


def render(key):
    fn, seed, target = BEATS[key]
    y = fn(np.random.default_rng(seed)).astype(float)
    drive = DRIVE.get(key, 0.0)
    if drive > 0.0:
        y = np.tanh(drive * y / float(np.max(np.abs(y))))
    if key in DARKEN:
        y = lp(lp(y, DARKEN[key]), DARKEN[key])
    fade = N(.03)
    y[-fade:] *= np.linspace(1, 0, fade)
    act = y[np.abs(y) > np.max(np.abs(y)) * 10 ** (-40 / 20)]
    y *= 10 ** ((target - 20 * math.log10(math.sqrt(float(np.mean(act ** 2))))) / 20)
    y *= min(1.0, 10 ** (-1 / 20) / float(np.max(np.abs(y))))
    return y


def write(key, out):
    y = render(key)
    wav = Path(tempfile.mkdtemp()) / "beat.wav"
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
        print("\n".join(sorted(BEATS)))
        return 0
    if len(argv) == 2 and argv[0] == "--all":
        for key in sorted(BEATS):
            write(key, Path(argv[1]) / (key + ".ogg"))
        return 0
    if len(argv) == 2 and argv[0] in BEATS:
        write(argv[0], argv[1])
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
