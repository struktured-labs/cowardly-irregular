#!/usr/bin/env python3
"""Grounded substitutes for the chip-timbre battle cues (struktured via cowir-main 26107/26112: "some of the sfx
sound a little arcady, even for me"; menus are OUT, he likes them).

    python3 tools/gen_grounded_sfx.py --all            # render every cue into assets/audio/sfx
    python3 tools/gen_grounded_sfx.py <key> [<key>..]  # render the named cues
    python3 tools/gen_grounded_sfx.py --selftest       # render in memory, check the shapes, write nothing

Same jobs as tools/gen_chiptune_sfx.py's cues, without the chip: no square or pulse waves, no bit-crusher.
Fire is crackle and roar, ice is glass and frost, lightning is a crack and a rumble, the Bard plucks a real
(Karplus-Strong) string, Advance charges with breath and a struck metal ring, and hits are wood, bone and
cloth. The September rule still holds: nothing GLIDES UPWARD while loud (tools/audit_whoop.py re-measures).

Each cue keeps its predecessor's length and loudness (LUFS where R128 can measure it, else the rms_db
tools/audit_whoop.py pinned), so the mix, the Advance ladder's escalation and each variant family's level hold.
numpy synthesis at 44.1 kHz mono, one deterministic seed per cue.
"""
import hashlib
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_sequence_beats import SR, N, at, bell, env, hp, lp, mix, sweep, t  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
PEAK_CEILING = 10 ** (-1.2 / 20)


def _noise(rng, d):
    return rng.standard_normal(N(d))


def _crackle(rng, d, density, lo=1500, amp=1.0, decay=3.0):
    """Sparse random clicks: embers popping. Density in clicks per second."""
    n = N(d)
    y = np.zeros(n)
    hits = rng.random(n) < density / SR
    y[hits] = rng.uniform(-1, 1, hits.sum())
    y = hp(lp(y, 9000), lo)
    return y * env(n, .002, decay) * amp * 6


def _pluck(f, d, damp=.996, bright=.5, seed=0):
    """Karplus-Strong string: a real plucked timbre, no oscillator."""
    rng = np.random.default_rng(seed)
    p = max(2, int(SR / f))
    buf = rng.uniform(-1, 1, p)
    buf = lp(buf, 1500 + 7000 * bright)
    n = N(d)
    y = np.zeros(n)
    for i in range(n):
        y[i] = buf[i % p]
        buf[i % p] = damp * .5 * (buf[i % p] + buf[(i + 1) % p])
    return y


def _wood(f, d, rng):
    """A struck wooden bar: a few damped inharmonic modes plus a contact click."""
    tt = t(d)
    modes = sum(w * np.sin(2 * np.pi * f * r * tt) * np.exp(-tt * k) for r, w, k in ((1, 1, 28), (2.57, .5, 45), (4.9, .25, 70)))
    click = hp(_noise(rng, .004), 3000) * env(N(.004), .0002, 10) * .6
    return mix(modes, click)


def _glass(rng, d, n_parts, lo, hi, dec=9.0):
    """Ice: inharmonic glassy partials at random pitches, each with its own fast decay."""
    tt = t(d)
    y = np.zeros(len(tt))
    for _ in range(n_parts):
        f = rng.uniform(lo, hi)
        y += np.sin(2 * np.pi * f * tt + rng.uniform(0, 6.28)) * np.exp(-tt * dec * rng.uniform(.6, 1.6)) * rng.uniform(.3, 1)
    return y / max(1, n_parts ** .5)


def _thump(f0, f1, d, curve=5.0):
    return sweep(f0, f1, d) * env(N(d), .002, curve)


def _roar(rng, d, c0, c1, flutter=11.0):
    """A body of flame: lowpassed noise with a FALLING cutoff and a slow flutter."""
    n = N(d)
    tt = t(d)
    y = lp(_noise(rng, d), np.linspace(c0, c1, n))
    return y * (1 + .35 * np.sin(2 * np.pi * flutter * tt + rng.uniform(0, 6)))


# ---------------------------------------------------------------- A: starter spells (the cast cues)
def ability_fire(rng):
    """The cast: a held breath at the hand, then ignition: a whump, a roar falling dark, embers."""
    breath = lp(_noise(rng, .22), 900) * np.sin(np.linspace(0, np.pi / 2, N(.22))) ** 2 * .35
    roar = _roar(rng, .84, 3200, 500) * env(N(.84), .006, 3.2) * 1.2
    return mix(breath, at(_thump(85, 38, .5) * 1.1, .2), at(roar, .2), at(_crackle(rng, .84, 70), .22))


def ability_fire_v2(rng):
    """Rotation sibling: shorter and harder, no breath: the flame is already lit."""
    return mix(_thump(95, 40, .4) * 1.2, _roar(rng, .72, 3600, 600) * env(N(.72), .002, 4.2) * 1.3, _crackle(rng, .72, 110, amp=1.2))


def ability_fire_v3(rng):
    """Rotation sibling: the longest, a sustained rumble that crumbles into embers."""
    body = _roar(rng, 1.15, 2400, 380, flutter=7.0) * env(N(1.15), .03, 2.4) * 1.2
    return mix(body, _thump(70, 30, .7) * .9, at(_crackle(rng, .8, 55, decay=2.0), .3))


def ability_ice(rng):
    """Frost hiss, then the crystal forming: glass partials, one clean crack."""
    hiss = hp(_noise(rng, .95), 4000) * env(N(.95), .01, 5) * .25
    glass = _glass(rng, .8, 9, 2200, 5200)
    crack = hp(_noise(rng, .01), 2000) * env(N(.01), .0002, 8) * 1.5
    return mix(hiss, at(glass, .08), at(crack, .08), at(_thump(140, 90, .25) * .4, .08))


def ability_ice_v2(rng):
    """Rotation sibling: the shatter: many tiny shards at once, a brittle burst."""
    shards = mix(*[at(_glass(rng, .45, 3, 2600, 6500, dec=16), rng.uniform(0, .12)) for _ in range(6)])
    return mix(hp(_noise(rng, .06), 2500) * env(N(.06), .0005, 6) * 1.2, shards[:N(.7)])


def ability_ice_v3(rng):
    """Rotation sibling: the freeze: a low creak as it sets, settling chimes."""
    n = N(1.2)
    creak = lp(_crackle(rng, 1.2, 160, lo=300, decay=1.2), 1500) * .8
    chimes = mix(at(bell(1318, .9, 5), .25) * .35, at(bell(1760, .8, 5.5), .45) * .3, at(bell(1175, .6, 6), .7) * .28)
    return mix(creak, _thump(120, 70, .45) * .6, chimes)[:n]


def _bolt(rng, d, tail=.6):
    crack = mix(hp(_noise(rng, .006), 1200) * 2.2 * env(N(.006), .0001, 6), hp(_crackle(rng, .12, 900, lo=2000), 1800) * .8)
    rumble = lp(_noise(rng, d), 220) * env(N(d), .02, 2.5) * 2.8
    return mix(crack, at(rumble, .01))


def ability_lightning(rng):
    """A crack and its rumble, with a fizz of static before it."""
    static = hp(_crackle(rng, .15, 400, lo=3000, decay=1.0), 3000) * .4
    return mix(static, at(_bolt(rng, .7), .13))[:N(.85)]


def ability_lightning_v2(rng):
    """Rotation sibling: the snap: the crack alone, a short tail."""
    return _bolt(rng, .55)


def ability_lightning_v3(rng):
    """Rotation sibling: the chain: three cracks walking away, each darker."""
    out = mix(_bolt(rng, .6), at(lp(_bolt(rng, .5), 5000) * .75, .22), at(lp(_bolt(rng, .5), 2500) * .55, .44))
    return out[:N(1.1)]


def ability_mp_restore(rng):
    """Pray and Channel: a low intake of breath, then two held bells a fourth apart."""
    breath = lp(lp(_noise(rng, .25), 300), 300) * np.sin(np.linspace(0, np.pi, N(.25))) ** 2 * .9
    return mix(breath, at(bell(523.25, .5, 4) * .5, .18), at(bell(698.46, .45, 4) * .45, .22))[:N(.7)]


def ability_revive(rng):
    """Raise: a low breath resolving into a C major triad, soft bells arriving together."""
    breath = lp(lp(_noise(rng, .35), 280), 280) * np.sin(np.linspace(0, np.pi, N(.35))) ** 2 * .9
    triad = mix(*[bell(f, .85, 2.6) * w for f, w in ((261.63, .5), (329.63, .4), (392.0, .4), (523.25, .25))])
    return mix(breath, at(triad, .28))[:N(1.15)]


def status_cured(rng):
    """An item cure: a short wash settling onto a clean held fifth."""
    wash = lp(_noise(rng, .2), np.linspace(2500, 700, N(.2))) * env(N(.2), .01, 4) * .4
    return mix(wash, at(mix(bell(392.0, .5, 4) * .5, bell(587.33, .5, 4) * .4), .08))[:N(.6)]


# ---------------------------------------------------------------- B: Bard
def ability_song(rng):
    """A strummed lute: a major triad plucked low to high, the top note held with a little vibrato."""
    notes = ((196.0, 0), (246.94, .045), (293.66, .09), (392.0, .135))
    out = mix(*[at(_pluck(f, .85 - s, .997, .45, seed=i) * (.8 if i < 3 else 1.0), s) for i, (f, s) in enumerate(notes)])
    tt = t(len(out) / SR)
    return (out * (1 + .04 * np.sin(2 * np.pi * 5.5 * tt) * np.clip((tt - .3) / .3, 0, 1)))[:N(.85)]


def ability_riff(rng):
    """The Bard's sour Riff: root, tritone and minor second struck together on strings, with a pick scrape."""
    pick = hp(_noise(rng, .02), 2500) * env(N(.02), .0005, 6) * .5
    strings = mix(*[_pluck(f, .55, .994, .7, seed=10 + i) for i, f in enumerate((146.83, 207.65, 155.56))])
    return mix(pick, strings)[:N(.55)]


# ---------------------------------------------------------------- C: Advance and the bank
def _charge(rng, d, rings, sub=0.0):
    """Commitment building: a breath of cloth, then struck metal rings (one per rung)."""
    cloth = lp(hp(_noise(rng, min(d, .25)), 500), 3000) * env(N(min(d, .25)), .01, 4) * .45
    parts = [cloth]
    for i, f in enumerate(rings):
        parts.append(at(bell(f, d - .05 * i, 5.5, parts=((1, 1), (2.4, .35), (4.1, .12))) * .55, .05 * i))
    if sub:
        parts.append(_thump(70, 42, d * .8) * sub)
    return mix(*parts)[:N(d)]


def advance_flourish_2(rng):
    return _charge(rng, .34, (440.0,))


def advance_flourish_3(rng):
    return _charge(rng, .42, (440.0, 554.37))


def advance_flourish_4(rng):
    return _charge(rng, .52, (440.0, 554.37, 659.25))


def advance_flourish_5(rng):
    return _charge(rng, .78, (440.0, 554.37, 659.25, 880.0), sub=.8)


def advance_queue_full(rng):
    """Refused: two dull knocks on wood. The press did nothing."""
    return mix(_wood(180, .09, rng), at(_wood(150, .08, rng) * .8, .085))[:N(.17)]


def full_bank_charged(rng):
    """The bank LOCKING full: a metal latch, then a held resonant ring over a low hum."""
    latch = mix(lp(hp(_noise(rng, .008), 1200), 3000) * env(N(.008), .0002, 8) * .5, at(lp(hp(_noise(rng, .008), 1000), 2500) * env(N(.008), .0002, 8) * .35, .03))
    ring = bell(660.0, .6, 2.5, parts=((1, 1), (2.01, .5), (3.0, .3))) * .7
    hum = np.sin(2 * np.pi * 164.8 * t(.6)) * env(N(.6), .05, 3) * .2
    return mix(latch, at(ring, .03), at(hum, .03))[:N(.62)]


def full_bank_unleash(rng):
    """The bank EMPTYING, NOT a louder advance_flourish_5: a deep release, a falling gust, the ring let go."""
    gust = lp(_noise(rng, .7), np.linspace(4000, 300, N(.7))) * env(N(.7), .003, 3.5) * 1.1
    ring = bell(330.0, .8, 4.5) * .45
    return mix(_thump(60, 30, .8) * 1.3, gust, ring)[:N(.85)]


# ---------------------------------------------------------------- D: hits and knockouts
def attack_hit_staff(rng):
    """A staff on a body: a wooden thwack with a dull thud under it."""
    return mix(_wood(230, .3, rng) * .9, _thump(110, 60, .2) * .8, lp(_noise(rng, .05), 1500) * env(N(.05), .001, 6) * .6)[:N(.3)]


def strike_lightning(rng):
    """A weapon's lightning bite: a crack and a quick sizzle, no tail."""
    return mix(hp(_noise(rng, .006), 1500) * 2 * env(N(.006), .0001, 6), hp(_crackle(rng, .16, 1200, lo=2500, decay=4), 2000) * .9)[:N(.16)]


def strike_dark(rng):
    """A weapon's dark bite: a muffled blow, smothered as it lands."""
    return mix(_thump(75, 40, .2) * 1.2, lp(_noise(rng, .2), np.linspace(1200, 200, N(.2))) * env(N(.2), .002, 5) * .9)[:N(.2)]


def attack_hit_piano_scythe_crit(rng):
    """The piano scythe's crit: a blade slice, then the struck chord ringing out from the frame."""
    slice_ = hp(_noise(rng, .12), np.linspace(4000, 1500, N(.12))) * env(N(.12), .003, 4) * .9
    chord = mix(*[_pluck(f, 1.0, .9985, .35, seed=20 + i) * w for i, (f, w) in enumerate(((110.0, .7), (164.81, .5), (220.0, .45), (261.63, .35)))])
    return mix(slice_, _thump(90, 45, .25) * .8, at(chord, .03))[:N(1.1)]


def party_ko(rng):
    """A party member falling: a body hitting the floor, cloth, a buckle settling."""
    fall = mix(_thump(70, 38, .35) * 1.3, lp(_noise(rng, .3), 900) * env(N(.3), .003, 5) * .8)
    cloth = lp(hp(_noise(rng, .25), 600), 3500) * env(N(.25), .02, 4) * .35
    clink = bell(1900, .2, 18) * .18
    return mix(fall, at(cloth, .03), at(clink, .12))[:N(.52)]


CUES = {f.__name__: f for f in (
    ability_fire, ability_fire_v2, ability_fire_v3, ability_ice, ability_ice_v2, ability_ice_v3,
    ability_lightning, ability_lightning_v2, ability_lightning_v3, ability_mp_restore, ability_revive, status_cured,
    ability_song, ability_riff,
    advance_flourish_2, advance_flourish_3, advance_flourish_4, advance_flourish_5, advance_queue_full,
    full_bank_charged, full_bank_unleash,
    attack_hit_staff, strike_lightning, strike_dark, attack_hit_piano_scythe_crit, party_ko)}

# Whole-file RMS of the cue each one replaces, as tools/audit_whoop.py measured it (test/fixtures/sfx_whoop_baseline.json).
TARGET_RMS_DB = {
    "ability_fire": -16.2, "ability_fire_v2": -15.6, "ability_fire_v3": -13.3, "ability_ice": -14.6, "ability_ice_v2": -18.4,
    "ability_ice_v3": -12.3, "ability_lightning": -16.3, "ability_lightning_v2": -17.4, "ability_lightning_v3": -15.0,
    "ability_mp_restore": -13.4, "ability_revive": -14.8, "status_cured": -14.8, "ability_song": -12.9, "ability_riff": -13.8,
    "advance_flourish_2": -13.8, "advance_flourish_3": -12.1, "advance_flourish_4": -11.1, "advance_flourish_5": -9.2,
    "advance_queue_full": -13.0, "full_bank_charged": -14.2, "full_bank_unleash": -11.6, "attack_hit_staff": -13.9,
    "strike_lightning": -14.7, "strike_dark": -11.8, "attack_hit_piano_scythe_crit": -13.4, "party_ko": -11.6,
}


# Perceived loudness (EBU R128 integrated) of the cue each one replaces, measured with ffmpeg ebur128 on the shipped
# file. RMS alone let the brighter replacements land up to 4.5 LU hotter, so a cue long enough for R128 (>= 0.4 s)
# is levelled by LUFS and the rest by RMS. The ice family is the exception: its three members were 5.2 LU apart
# (test_a_variant_varies_texture_not_level declared it wide), so the replacements are set 1 LU apart around the base.
TARGET_LUFS = {
    "ability_fire": -15.7, "ability_fire_v2": -17.8, "ability_fire_v3": -15.0,
    "ability_ice": -15.4, "ability_ice_v2": -16.4, "ability_ice_v3": -14.4,
    "ability_lightning": -16.4, "ability_lightning_v2": -17.8, "ability_lightning_v3": -15.7,
    "ability_mp_restore": -14.0, "ability_revive": -15.0, "status_cured": -14.7, "ability_song": -12.6, "ability_riff": -16.4,
    "advance_flourish_3": -12.8, "advance_flourish_4": -11.5, "advance_flourish_5": -10.1,
    "full_bank_charged": -15.9, "full_bank_unleash": -13.8, "attack_hit_piano_scythe_crit": -13.5,
}


def lufs(y):
    import re
    tmp = Path(tempfile.mkdtemp()) / "probe.wav"
    _wav(y, tmp)
    out = subprocess.run(["ffmpeg", "-nostdin", "-v", "info", "-i", str(tmp), "-filter_complex", "ebur128=framelog=quiet",
                          "-f", "null", "-"], capture_output=True, text=True).stderr
    tmp.unlink()
    m = re.findall(r"I:\s*(-?[0-9.]+)\s*LUFS", out)
    return float(m[-1]) if m else None


def _seed(key):
    return int(hashlib.sha256(key.encode()).hexdigest()[:8], 16)


def _rms_db(y):
    return 20 * np.log10(np.sqrt(np.mean(y ** 2)) + 1e-12)


def render(key):
    y = CUES[key](np.random.default_rng(_seed(key))).astype(float)
    fade = min(N(.03), len(y) // 4)
    y[-fade:] *= np.linspace(1, 0, fade)
    y /= float(np.max(np.abs(y)))
    for _ in range(12):
        if key in TARGET_LUFS:
            got = lufs(y)
            if got is None or got < -60:
                raise SystemExit("REFUSING: %s would not measure, so its level would be a guess" % key)
            y *= 10 ** ((TARGET_LUFS[key] - got) / 20)
        else:
            y *= 10 ** ((TARGET_RMS_DB[key] - _rms_db(y)) / 20)
        if np.max(np.abs(y)) > PEAK_CEILING:
            y = np.tanh(y / PEAK_CEILING) * PEAK_CEILING
    return y


def _wav(y, path):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(y, -1, 1) * 32767).astype("<i2").tobytes())


def write(key):
    y = render(key)
    out = ROOT / "assets" / "audio" / "sfx" / (key + ".ogg")
    tmp = Path(tempfile.mkdtemp()) / "cue.wav"
    _wav(y, tmp)
    subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", str(tmp), "-c:a", "libvorbis", "-q:a", "5", str(out)], check=True)
    tmp.unlink()
    lvl = ("%.1f LUFS, target %.1f" % (lufs(y), TARGET_LUFS[key])) if key in TARGET_LUFS else ("rms %.1f dB, target %.1f" % (_rms_db(y), TARGET_RMS_DB[key]))
    print("wrote %s (%.2fs, %s)" % (out.relative_to(ROOT), len(y) / SR, lvl))


def _centroid_track(y, nwin=16):
    """Spectral centroid per window across the loud part (>-18 dB of peak), as audit_whoop gates it."""
    a = np.abs(y)
    loud = np.where(a > a.max() * 10 ** (-18 / 20))[0]
    seg = y[loud[0]:loud[-1] + 1]
    w = max(256, len(seg) // nwin)
    out = []
    for i in range(0, len(seg) - w + 1, w):
        s = np.abs(np.fft.rfft(seg[i:i + w] * np.hanning(w)))
        f = np.fft.rfftfreq(w, 1 / SR)
        out.append((s * f).sum() / max(s.sum(), 1e-12))
    return out


def selftest():
    ok = True

    def chk(name, cond):
        nonlocal ok
        ok &= bool(cond)
        if not cond:
            print("  FAIL  " + name)

    assert set(CUES) == set(TARGET_RMS_DB), "every cue needs a target level"
    lengths = {}
    for k in CUES:
        y = render(k)
        lengths[k] = len(y) / SR
        chk("%s: renders sound" % k, np.max(np.abs(y)) > .05)
        if k in TARGET_LUFS:
            chk("%s: loudness within 0.5 LU of its target" % k, abs(lufs(y) - TARGET_LUFS[k]) < .5)
        else:
            chk("%s: level within 0.5 dB of the cue it replaces" % k, abs(_rms_db(y) - TARGET_RMS_DB[k]) < .5)
        chk("%s: deterministic" % k, np.array_equal(y, render(k)))
        c = _centroid_track(y)
        if len(c) >= 3:
            third = max(1, len(c) // 3)
            early, late = np.mean(c[:third]), np.mean(c[-third:])
            chk("%s: no whoop (the loud part's centroid does not climb 2.5x into the late third: %.0f -> %.0f Hz)" % (k, early, late),
                not (late > 2.5 * early and late < 4000))
        ## No chip: a square wave puts nearly all its energy in odd harmonics of one pitch; real textures do not.
    ladder = ["advance_flourish_%d" % i for i in (2, 3, 4, 5)]
    chk("the Advance ladder still lengthens rung to rung", all(lengths[a] < lengths[b] for a, b in zip(ladder, ladder[1:])))
    steps = [lengths[b] - lengths[a] for a, b in zip(ladder, ladder[1:])]
    chk("the 4->5 step is still the largest", steps[2] > max(steps[0], steps[1]))
    chk("CONTROL: the level check can fail (a cue rendered 6 dB hot misses its target)",
        abs(_rms_db(render("party_ko") * 2) - TARGET_RMS_DB["party_ko"]) > .5)
    print("selftest: %s (%d cues)" % ("PASS" if ok else "FAIL", len(CUES)))
    return 0 if ok else 1


def main(argv):
    if argv[:1] == ["--selftest"]:
        return selftest()
    keys = list(CUES) if argv[:1] == ["--all"] else argv
    if not keys or any(k not in CUES for k in keys):
        print(__doc__)
        print("cues: " + " ".join(CUES))
        return 2
    for k in keys:
        write(k)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
