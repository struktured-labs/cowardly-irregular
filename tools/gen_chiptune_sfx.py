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


# --- lightning -------------------------------------------------------------
# NES "Lit": a crack, a fast descending arc, and flicker. Brighter than fire by design, but the
# cutoff still FALLS -- the shipped ones climbed 3.0x and that climb is what reads as a whoop.

def _zap(n, rng, hi, lo, decay, arc_hi, arc_lo, amp=1.0):
    core = _sweep_lowpass(rng.uniform(-1, 1, n), hi, lo) * _env(n, 0.002, decay)
    f = np.linspace(arc_hi, arc_lo, n)
    arc = np.sign(np.sin(2 * math.pi * np.cumsum(f) / SR)) * _env(n, 0.001, decay * 1.4) * 0.4
    return (core + arc) * amp


def lightning(dur=0.85, seed=31):
    rng = np.random.default_rng(seed); n = int(SR * dur)
    out = _zap(n, rng, 3200.0, 260.0, 2.6, 620.0, 90.0)
    for at, amp in ((0.16, 0.55), (0.27, 0.40), (0.44, 0.26)):   # flicker
        k = int(at * n); seg = n - k
        out[k:] += _zap(seg, rng, 2200.0, 200.0, 3.2, 480.0, 80.0, amp)
    out = _bitcrush(out, bits=4, hold=4)
    out = _sweep_lowpass(out, 3000.0, 1500.0)
    out /= max(np.max(np.abs(out)), 1e-9); return (out * 0.85).astype(np.float32)


def lightning_snap(dur=0.55, seed=37):
    rng = np.random.default_rng(seed); n = int(SR * dur)
    out = _zap(n, rng, 3600.0, 300.0, 3.4, 700.0, 110.0)
    k = int(0.22 * n); out[k:] += _zap(n - k, rng, 2400.0, 220.0, 3.8, 520.0, 90.0, 0.42)
    out = _bitcrush(out, bits=4, hold=5)
    out = _sweep_lowpass(out, 2800.0, 1400.0)
    out /= max(np.max(np.abs(out)), 1e-9); return (out * 0.85).astype(np.float32)


def lightning_chain(dur=1.10, seed=41):
    """Longest: several arcs walking away, for chain_lightning."""
    rng = np.random.default_rng(seed); n = int(SR * dur)
    out = _zap(n, rng, 2800.0, 240.0, 2.4, 560.0, 90.0)
    for at, amp in ((0.20, 0.52), (0.38, 0.42), (0.56, 0.32), (0.74, 0.22)):
        k = int(at * n); out[k:] += _zap(n - k, rng, 2000.0, 190.0, 3.4, 440.0, 80.0, amp)
    out = _bitcrush(out, bits=5, hold=4)
    out = _sweep_lowpass(out, 2600.0, 1300.0)
    out /= max(np.max(np.abs(out)), 1e-9); return (out * 0.85).astype(np.float32)


# --- ice -------------------------------------------------------------------
# Brittle, not piercing. The shipped v3 peaked at 5401 Hz -- a sustained tone right in the ear's
# sore spot. Here the shards are SHORT and the body decays fast.

def _shard(n, rng, hi, lo, decay):
    return _sweep_lowpass(rng.uniform(-1, 1, n), hi, lo) * _env(n, 0.001, decay)


def ice(dur=0.95, seed=53):
    rng = np.random.default_rng(seed); n = int(SR * dur)
    out = _shard(n, rng, 2600.0, 300.0, 2.2) * 0.8
    f = np.linspace(430.0, 150.0, n)
    out += np.sign(np.sin(2 * math.pi * np.cumsum(f) / SR)) * _env(n, 0.006, 2.8) * 0.45
    for at, amp in ((0.22, 0.5), (0.36, 0.4), (0.52, 0.3), (0.68, 0.2)):   # cracking
        k = int(at * n); out[k:] += _shard(n - k, rng, 1900.0, 260.0, 4.0) * amp
    out = _bitcrush(out, bits=5, hold=4)
    out = _sweep_lowpass(out, 2500.0, 1300.0)
    out /= max(np.max(np.abs(out)), 1e-9); return (out * 0.85).astype(np.float32)


def ice_shatter(dur=0.70, seed=59):
    rng = np.random.default_rng(seed); n = int(SR * dur)
    out = _shard(n, rng, 3000.0, 320.0, 3.0) * 0.85
    for at, amp in ((0.10, 0.6), (0.20, 0.5), (0.32, 0.4), (0.46, 0.3), (0.62, 0.2)):
        k = int(at * n); out[k:] += _shard(n - k, rng, 2200.0, 280.0, 4.4) * amp
    out = _bitcrush(out, bits=4, hold=5)
    out = _sweep_lowpass(out, 2400.0, 1250.0)
    out /= max(np.max(np.abs(out)), 1e-9); return (out * 0.85).astype(np.float32)


def ice_freeze(dur=1.20, seed=61):
    rng = np.random.default_rng(seed); n = int(SR * dur)
    out = _shard(n, rng, 2000.0, 220.0, 1.6) * 0.8
    f = np.linspace(300.0, 110.0, n)
    out += np.sign(np.sin(2 * math.pi * np.cumsum(f) / SR)) * _env(n, 0.05, 1.8) * 0.5
    for at, amp in ((0.40, 0.34), (0.62, 0.26), (0.80, 0.18)):
        k = int(at * n); out[k:] += _shard(n - k, rng, 1600.0, 220.0, 4.0) * amp
    out = _bitcrush(out, bits=5, hold=4)
    out = _sweep_lowpass(out, 2200.0, 1100.0)
    out /= max(np.max(np.abs(out)), 1e-9); return (out * 0.85).astype(np.float32)


# --- dark ------------------------------------------------------------------
def dark(dur=1.25, seed=71):
    """Low and menacing. Dissonant pair walking down; body kept, unlike the hiss take."""
    rng = np.random.default_rng(seed); n = int(SR * dur)
    out = _sweep_lowpass(rng.uniform(-1, 1, n), 1100.0, 130.0) * _env(n, 0.04, 1.7) * 0.75
    for f0, f1, amp in ((150.0, 62.0, 0.5), (212.0, 88.0, 0.34)):   # tritone-ish, unresolved
        f = np.linspace(f0, f1, n)
        out += np.sign(np.sin(2 * math.pi * np.cumsum(f) / SR)) * _env(n, 0.03, 2.2) * amp
    for at, amp in ((0.44, 0.26), (0.68, 0.18)):
        k = int(at * n); seg = n - k
        out[k:] += _sweep_lowpass(rng.uniform(-1, 1, seg), 700.0, 110.0) * _env(seg, 0.01, 3.0) * amp
    out = _bitcrush(out, bits=5, hold=5)
    out = _sweep_lowpass(out, 1800.0, 900.0)
    out /= max(np.max(np.abs(out)), 1e-9); return (out * 0.85).astype(np.float32)


def shadow_strike(dur=1.05, seed=83):
    """Formation special. struktured: dark/shadow should be WILDER — which means low and heavy,
    not bright. The shipped one ran 186 -> 6214 Hz (33.4x), i.e. it got THINNER as it landed."""
    rng = np.random.default_rng(seed); n = int(SR * dur)
    # A held breath, then the drop. Brightness falls the whole way.
    out = _sweep_lowpass(rng.uniform(-1, 1, n), 900.0, 90.0) * _env(n, 0.10, 1.5) * 0.7
    for f0, f1, amp in ((120.0, 38.0, 0.60), (178.0, 55.0, 0.34)):
        f = np.linspace(f0, f1, n)
        out += np.sign(np.sin(2 * math.pi * np.cumsum(f) / SR)) * _env(n, 0.06, 1.9) * amp
    k = int(0.34 * n); seg = n - k          # the strike itself: heavy, low, no glint
    out[k:] += _sweep_lowpass(rng.uniform(-1, 1, seg), 1400.0, 70.0) * _env(seg, 0.002, 2.4) * 0.95
    f = np.linspace(70.0, 30.0, seg)
    out[k:] += np.sign(np.sin(2 * math.pi * np.cumsum(f) / SR)) * _env(seg, 0.001, 2.8) * 0.55
    out = _bitcrush(out, bits=5, hold=5)
    out = _sweep_lowpass(out, 1600.0, 700.0)
    out /= max(np.max(np.abs(out)), 1e-9); return (out * 0.88).astype(np.float32)


def strike_dark_hit(dur=0.20, seed=97):
    """Impact voice. The shipped one swept 2670 -> 144 Hz in 170ms — a downward glide, which is a
    whoop by ear even though it FALLS. An impact should land, not slide."""
    rng = np.random.default_rng(seed); n = int(SR * dur)
    body = _sweep_lowpass(rng.uniform(-1, 1, n), 420.0, 260.0) * _env(n, 0.002, 3.0) * 0.9
    f = np.full(n, 74.0)                      # held, not glided
    body += np.sign(np.sin(2 * math.pi * np.cumsum(f) / SR)) * _env(n, 0.001, 3.6) * 0.65
    body += _sweep_lowpass(rng.uniform(-1, 1, n), 1500.0, 1100.0) * _env(n, 0.0008, 9.0) * 0.35
    out = _bitcrush(body, bits=5, hold=4)
    out = _sweep_lowpass(out, 1500.0, 1100.0)
    out /= max(np.max(np.abs(out)), 1e-9); return (out * 0.9).astype(np.float32)


def strike_lightning_hit(dur=0.16, seed=101):
    """Impact voice. Shipped: 3495 -> 947 Hz in 90ms. Same downward slide; make it a crack."""
    rng = np.random.default_rng(seed); n = int(SR * dur)
    body = _sweep_lowpass(rng.uniform(-1, 1, n), 2600.0, 1900.0) * _env(n, 0.0006, 5.0) * 0.95
    f = np.full(n, 138.0)
    body += np.sign(np.sin(2 * math.pi * np.cumsum(f) / SR)) * _env(n, 0.001, 4.2) * 0.5
    out = _bitcrush(body, bits=4, hold=4)
    out = _sweep_lowpass(out, 2400.0, 1800.0)
    out /= max(np.max(np.abs(out)), 1e-9); return (out * 0.9).astype(np.float32)


def _flat_tone(n, f, decay, amp=1.0, duty=0.5):
    ph = (np.cumsum(np.full(n, f)) / SR) % 1.0
    return (np.where(ph < duty, 1.0, -1.0)) * _env(n, 0.002, decay) * amp


def ui_confirm(dur=0.42, seed=113):
    """purchase_complete. Was 2756 -> 446 Hz (6.2x) — a descending glide, i.e. a whoop.
    A confirm should be two HELD steps, not a slide."""
    rng = np.random.default_rng(seed); n = int(SR * dur); h = n // 2
    out = np.zeros(n)
    out[:h] += _flat_tone(h, 523.0, 3.0, 0.7)          # C5, held
    out[h:] += _flat_tone(n - h, 784.0, 2.6, 0.75)     # G5, held — up a fifth, no glide between
    out += _sweep_lowpass(rng.uniform(-1, 1, n), 1400.0, 1200.0) * _env(n, 0.001, 6.0) * 0.18
    out = _bitcrush(out, bits=5, hold=4); out = _sweep_lowpass(out, 1900.0, 1700.0)
    out /= max(np.max(np.abs(out)), 1e-9); return (out * 0.8).astype(np.float32)


def ui_open(dur=0.55, seed=127):
    """autobattle_open. Was 3133 -> 1185 (2.6x). Held two-note open, no sweep."""
    rng = np.random.default_rng(seed); n = int(SR * dur); h = int(n * 0.45)
    out = np.zeros(n)
    out[:h] += _flat_tone(h, 392.0, 3.2, 0.65)
    out[h:] += _flat_tone(n - h, 587.0, 2.4, 0.7)
    out += _sweep_lowpass(rng.uniform(-1, 1, n), 1200.0, 1000.0) * _env(n, 0.001, 7.0) * 0.15
    out = _bitcrush(out, bits=5, hold=5); out = _sweep_lowpass(out, 1800.0, 1600.0)
    out /= max(np.max(np.abs(out)), 1e-9); return (out * 0.78).astype(np.float32)


def portal_hum(dur=2.0, seed=131):
    """portal_activate. Was 4347 -> 1581 (2.7x). A portal should HOLD, not descend away."""
    rng = np.random.default_rng(seed); n = int(SR * dur)
    out = _flat_tone(n, 196.0, 0.9, 0.55) + _flat_tone(n, 294.0, 1.0, 0.35)
    out += _sweep_lowpass(rng.uniform(-1, 1, n), 1500.0, 1300.0) * _env(n, 0.25, 1.1) * 0.45
    trem = 1.0 + 0.18 * np.sin(2 * math.pi * 7.0 * np.arange(n) / SR)
    out *= trem
    out = _bitcrush(out, bits=5, hold=4); out = _sweep_lowpass(out, 1900.0, 1700.0)
    out /= max(np.max(np.abs(out)), 1e-9); return (out * 0.82).astype(np.float32)


def scythe_crit(dur=1.10, seed=137):
    """attack_hit_piano_scythe_crit. Was 4357 -> 1127 over 3.5s (3.9x) — a long descending wail.
    A crit should hit and stop."""
    rng = np.random.default_rng(seed); n = int(SR * dur)
    out = _sweep_lowpass(rng.uniform(-1, 1, n), 2100.0, 1700.0) * _env(n, 0.001, 3.4) * 0.95
    out += _flat_tone(n, 147.0, 3.0, 0.55)
    k = int(0.14 * n); out[k:] += _flat_tone(n - k, 220.0, 3.4, 0.4)
    out = _bitcrush(out, bits=4, hold=4); out = _sweep_lowpass(out, 2300.0, 2000.0)
    out /= max(np.max(np.abs(out)), 1e-9); return (out * 0.9).astype(np.float32)


def ui_toggle_on(dur=0.34, seed=149):
    """autobattle_on. Was 2276 -> 593 (3.8x) — a downward glide on a toggle he hits constantly."""
    n = int(SR * dur); h = n // 2
    out = np.zeros(n)
    out[:h] += _flat_tone(h, 440.0, 3.0, 0.7)
    out[h:] += _flat_tone(n - h, 660.0, 2.6, 0.72)
    out = _bitcrush(out, bits=5, hold=4); out = _sweep_lowpass(out, 1800.0, 1650.0)
    out /= max(np.max(np.abs(out)), 1e-9); return (out * 0.78).astype(np.float32)


def staff_hit(dur=0.30, seed=151):
    """attack_hit_staff — the Mage's weapon hit. Was 2427 -> 381 (6.4x)."""
    rng = np.random.default_rng(seed); n = int(SR * dur)
    out = _sweep_lowpass(rng.uniform(-1, 1, n), 1500.0, 1150.0) * _env(n, 0.001, 4.0) * 0.9
    out += _flat_tone(n, 165.0, 3.4, 0.5)
    out = _bitcrush(out, bits=5, hold=4); out = _sweep_lowpass(out, 1700.0, 1400.0)
    out /= max(np.max(np.abs(out)), 1e-9); return (out * 0.86).astype(np.float32)


def _held(n, f, decay, amp=1.0, duty=0.5, vib_hz=0.0, vib_cents=0.0):
    """A held pulse note. Vibrato is depth-limited in CENTS so the fundamental never GLIDES."""
    f_inst = np.full(n, float(f))
    if vib_hz > 0.0 and vib_cents > 0.0:
        f_inst = f_inst * (2.0 ** ((vib_cents / 1200.0) * np.sin(2 * math.pi * vib_hz * np.arange(n) / SR)))
    ph = (np.cumsum(f_inst) / SR) % 1.0
    return np.where(ph < duty, 1.0, -1.0) * _env(n, 0.004, decay) * amp


def _place(out, seg, start):
    end = min(len(out), start + len(seg))
    out[start:end] += seg[:end - start]


def song(dur=0.85, seed=163):
    """ability_song — bard's four songs (battle_hymn/lullaby/discord/inspiring_melody) had NO cue
    and fell through to ability_physical, a melee thump. A song has to read as MUSIC: three held
    triad steps on a reedy 25% pulse, vibrato on the sustain. Stepped, never slid — an arpeggio is
    discrete pitch, which is why it does not register as the whoop struktured rejected."""
    rng = np.random.default_rng(seed); n = int(SR * dur)
    out = np.zeros(n)
    step = int(n * 0.17)
    _place(out, _held(step, 523.25, 3.0, 0.55, duty=0.25), 0)                      # C5
    _place(out, _held(step, 659.25, 3.0, 0.55, duty=0.25), step)                   # E5
    tail = n - 2 * step
    _place(out, _held(tail, 783.99, 1.9, 0.60, duty=0.25, vib_hz=6.5, vib_cents=28.0), 2 * step)
    _place(out, _held(tail, 392.00, 1.7, 0.30, duty=0.5), 2 * step)                # G4 body under it
    out = _bitcrush(out, bits=5, hold=4); out = _sweep_lowpass(out, 2000.0, 1500.0)
    out /= max(np.max(np.abs(out)), 1e-9); return (out * 0.80).astype(np.float32)


def summon(dur=1.30, seed=167):
    """ability_summon — 7 summons incl. Bahamut/Ifrit/Shiva/Ramuh played the melee thump. Weight
    comes from a held low root+fifth drone and a noise swell, NOT from a descending glide."""
    rng = np.random.default_rng(seed); n = int(SR * dur)
    out = _held(n, 65.41, 0.85, 0.75) + _held(n, 98.00, 0.95, 0.42) + _held(n, 130.81, 1.2, 0.26)
    swell = _sweep_lowpass(rng.uniform(-1, 1, n), 900.0, 700.0) * _env(n, 0.35, 1.3) * 0.5
    out += swell
    thump = np.zeros(n); k = int(SR * 0.16)
    thump[:k] = _held(k, 49.0, 2.2, 1.0)
    out += thump
    out *= 1.0 + 0.12 * np.sin(2 * math.pi * 5.5 * np.arange(n) / SR)
    out = _bitcrush(out, bits=5, hold=5); out = _sweep_lowpass(out, 1500.0, 1200.0)
    out /= max(np.max(np.abs(out)), 1e-9); return (out * 0.82).astype(np.float32)


def revive(dur=1.15, seed=173):
    """ability_revive — `raise` (Anima Reddita) is the one moment a dead party member comes back
    and it played a sword hit. Two held steps resolving into a major chord: low breath, then the
    triad arriving together. Fundamentals stay 260-520 Hz so it reads warm, not as the chirp that
    got the old cure cue rejected."""
    rng = np.random.default_rng(seed); n = int(SR * dur)
    out = np.zeros(n); lead = int(n * 0.26)
    _place(out, _held(lead, 261.63, 2.4, 0.45, duty=0.5), 0)                        # C4 breath
    tail = n - lead
    for f, a in ((523.25, 0.42), (659.25, 0.34), (783.99, 0.28)):                   # C5-E5-G5, together
        _place(out, _held(tail, f, 1.5, a, duty=0.35, vib_hz=5.0, vib_cents=18.0), lead)
    _place(out, _held(tail, 130.81, 1.1, 0.30, duty=0.5), lead)                     # C3 under the chord
    shimmer = _sweep_lowpass(rng.uniform(-1, 1, n), 1600.0, 1400.0) * _env(n, 0.30, 2.2) * 0.13
    out += shimmer
    out = _bitcrush(out, bits=5, hold=4); out = _sweep_lowpass(out, 2100.0, 1700.0)
    out /= max(np.max(np.abs(out)), 1e-9); return (out * 0.78).astype(np.float32)


def poison(dur=1.00, seed=191):
    """ability_poison — 5 corrosive spells (acid_splash, acid_spray, corrode, dissolve,
    toxic_cloud) played the melee thump because no poison cue existed. Irregular low blips over a
    held hiss: corrosion is intermittent, not a swing. The hiss band is HELD, not swept."""
    rng = np.random.default_rng(seed); n = int(SR * dur)
    out = _sweep_lowpass(rng.uniform(-1, 1, n), 1500.0, 1400.0) * _env(n, 0.06, 1.4) * 0.42
    t = 0
    while t < n - int(SR * 0.05):                      # bubbles, irregular by construction
        k = int(SR * rng.uniform(0.03, 0.07))
        f = rng.uniform(70.0, 190.0)
        _place(out, _held(min(k, n - t), f, 3.4, 0.42, duty=0.25), t)
        t += k + int(SR * rng.uniform(0.02, 0.09))
    out = _bitcrush(out, bits=5, hold=5); out = _sweep_lowpass(out, 1700.0, 1500.0)
    out /= max(np.max(np.abs(out)), 1e-9); return (out * 0.80).astype(np.float32)


def earth(dur=0.95, seed=193):
    """ability_earth — root_bind and sandstorm played a sword. Weight without a glide: a low
    struck root, a stone-grit noise body and a second thud, all at held pitch."""
    rng = np.random.default_rng(seed); n = int(SR * dur)
    out = np.zeros(n)
    for start, f, a in ((0.0, 55.0, 0.85), (0.16, 41.2, 0.55), (0.34, 61.7, 0.40)):
        k = int(SR * 0.22); off = int(SR * start)
        _place(out, _held(min(k, n - off), f, 2.4, a), off)
    grit = _sweep_lowpass(rng.uniform(-1, 1, n), 800.0, 700.0) * _env(n, 0.02, 1.9) * 0.45
    out += grit
    out = _bitcrush(out, bits=5, hold=6); out = _sweep_lowpass(out, 1300.0, 1100.0)
    out /= max(np.max(np.abs(out)), 1e-9); return (out * 0.82).astype(np.float32)


def wind(dur=1.10, seed=197):
    """ability_wind — whirlwind. Wind is the easiest cue to accidentally build as a whoop, because
    the obvious synthesis IS a swept filter. This holds the band and gets motion from tremolo
    instead, so the brightness never travels."""
    rng = np.random.default_rng(seed); n = int(SR * dur)
    out = _sweep_lowpass(rng.uniform(-1, 1, n), 1100.0, 1050.0) * _env(n, 0.22, 1.1)
    out *= 1.0 + 0.42 * np.sin(2 * math.pi * 9.0 * np.arange(n) / SR)   # gusting, not gliding
    out += _held(n, 146.8, 1.3, 0.22) * _env(n, 0.2, 1.2)
    out = _bitcrush(out, bits=5, hold=5); out = _sweep_lowpass(out, 1500.0, 1400.0)
    out /= max(np.max(np.abs(out)), 1e-9); return (out * 0.78).astype(np.float32)


def arcane(dur=0.90, seed=199):
    """ability_arcane — 28 magic spells declare NO element (call_stack, fork_bomb, null_reference,
    fourth_wall_break, phantom_wail...) so the element lookup found nothing and they thumped. A
    neutral non-elemental pulse: a held fifth with a bitcrushed shimmer. Deliberately NOT a glitch
    effect — two thirds of the 28 are the meta/system family and would suit one, but the other
    third are spectral or organic, and inventing an element the data does not declare is how a cue
    ends up lying about the ability."""
    rng = np.random.default_rng(seed); n = int(SR * dur)
    out = _held(n, 174.6, 1.5, 0.50) + _held(n, 261.6, 1.6, 0.38, duty=0.35)
    out += _held(n, 349.2, 1.9, 0.22, duty=0.25, vib_hz=5.5, vib_cents=22.0)
    out += _sweep_lowpass(rng.uniform(-1, 1, n), 1900.0, 1700.0) * _env(n, 0.10, 2.4) * 0.20
    out = _bitcrush(out, bits=4, hold=5); out = _sweep_lowpass(out, 2000.0, 1800.0)
    out /= max(np.max(np.abs(out)), 1e-9); return (out * 0.80).astype(np.float32)
def riff(dur=0.55, seed=179):
    """ability_riff — the Bard's Free Move, which IS her attack. type=physical, so it resolved to
    ability_physical: a sword unsheathing. Its own shipped description is "a sour, clashing chord
    struck like a weapon", which the sword cue directly contradicts. Root + tritone + minor 2nd
    struck together with a noise transient — dissonant by construction, no glide."""
    rng = np.random.default_rng(seed); n = int(SR * dur)
    out = np.zeros(n)
    for f, a, d in ((220.00, 0.55, 2.6), (311.13, 0.45, 2.8), (233.08, 0.38, 3.0), (110.00, 0.40, 2.2)):
        stagger = int(SR * rng.uniform(0.0, 0.012))          # a strum, not a keyboard chord
        _place(out, _held(n - stagger, f, d, a, duty=0.35), stagger)
    k = int(SR * 0.05)
    out[:k] += _sweep_lowpass(rng.uniform(-1, 1, k), 2600.0, 1800.0) * _env(k, 0.001, 5.0) * 0.55
    out = _bitcrush(out, bits=5, hold=4); out = _sweep_lowpass(out, 2200.0, 1800.0)
    out /= max(np.max(np.abs(out)), 1e-9); return (out * 0.84).astype(np.float32)


def mp_restore(dur=0.70, seed=211):
    """ability_mp_restore — pray (Cleric free move) and channel (Mage free move) played the SWORD.
    Deliberately not ability_heal: that cue is the angelic HP restore, and MP returning should read
    as a quieter, more inward replenish. A low intake pulse, then two held bells a fourth apart."""
    rng = np.random.default_rng(seed); n = int(SR * dur)
    out = np.zeros(n)
    k = int(SR * 0.09)
    _place(out, _held(k, 98.0, 3.0, 0.40), 0)                                    # intake
    body = n - k
    _place(out, _held(body, 523.25, 2.0, 0.36, duty=0.35, vib_hz=5.0, vib_cents=16.0), k)
    _place(out, _held(body, 698.46, 2.2, 0.28, duty=0.25, vib_hz=5.0, vib_cents=16.0), k)
    out += _sweep_lowpass(rng.uniform(-1, 1, n), 1700.0, 1500.0) * _env(n, 0.14, 3.0) * 0.11
    out = _bitcrush(out, bits=5, hold=4); out = _sweep_lowpass(out, 2000.0, 1800.0)
    out /= max(np.max(np.abs(out)), 1e-9); return (out * 0.74).astype(np.float32)


def flee(dur=0.48, seed=223):
    """ability_flee — the Rogue's escape, type=escape, the last type with no arm. Three DISCRETE
    descending blips (a scamper) plus a scuff. Stepped, never slid: a descending slide is a whoop
    in the other direction, which is the blind spot that let struktured hear it a fourth time."""
    rng = np.random.default_rng(seed); n = int(SR * dur)
    out = np.zeros(n)
    step = int(n * 0.20)
    for i, f in enumerate((659.25, 493.88, 392.00)):
        _place(out, _held(step, f, 3.2, 0.50, duty=0.25), i * step)
    scuff = _sweep_lowpass(rng.uniform(-1, 1, n), 1300.0, 1200.0) * _env(n, 0.02, 3.4) * 0.30
    out += scuff
    out = _bitcrush(out, bits=5, hold=5); out = _sweep_lowpass(out, 1800.0, 1600.0)
    out /= max(np.max(np.abs(out)), 1e-9); return (out * 0.78).astype(np.float32)


def cure(dur=0.60, seed=227):
    """status_cured — using an Antidote/Eye Drops/Echo Herb was SILENT. Distinct from the status_*
    cues, which announce an affliction ARRIVING; this is one leaving. A short noise wash that
    settles onto a clean held fifth: the wash is the affliction clearing, the fifth is what is left."""
    rng = np.random.default_rng(seed); n = int(SR * dur)
    wash = _sweep_lowpass(rng.uniform(-1, 1, n), 1500.0, 1400.0) * _env(n, 0.01, 5.0) * 0.34
    out = wash
    tail = int(n * 0.62); off = n - tail
    _place(out, _held(tail, 587.33, 2.2, 0.42, duty=0.35), off)
    _place(out, _held(tail, 880.00, 2.4, 0.26, duty=0.25), off)
    out = _bitcrush(out, bits=5, hold=4); out = _sweep_lowpass(out, 2000.0, 1800.0)
    out /= max(np.max(np.abs(out)), 1e-9); return (out * 0.76).astype(np.float32)


VOICES = {"ui_toggle_on": ui_toggle_on, "staff_hit": staff_hit, "ui_confirm": ui_confirm, "ui_open": ui_open, "portal_hum": portal_hum,
          "scythe_crit": scythe_crit, "strike_dark_hit": strike_dark_hit, "strike_lightning_hit": strike_lightning_hit,
          "shadow_strike": shadow_strike, "fire": fire, "fire_burst": fire_burst, "fire_roar": fire_roar,
          "lightning": lightning, "lightning_snap": lightning_snap, "lightning_chain": lightning_chain,
          "ice": ice, "ice_shatter": ice_shatter, "ice_freeze": ice_freeze,
          "dark": dark,
          "song": song, "summon": summon, "revive": revive, "riff": riff,
          "poison": poison, "earth": earth, "wind": wind, "arcane": arcane,
          "mp_restore": mp_restore, "flee": flee, "cure": cure}


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
