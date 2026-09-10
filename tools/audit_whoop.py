#!/usr/bin/env python3
"""Measure the whoop signature and refresh the pinned baseline.

struktured rejected the same sound three times (fireball, then lightning, then the cure spell)
because a fix to one cue left its rotation siblings untouched. The signature is not a pitch glide
-- it is the spectral CENTROID climbing into the late third, landing in the band the ear is most
sensitive in. Static whole-file spectra miss it entirely, which is why two lanes measured these
cues and called them fine.

The baseline lives under test/fixtures, NOT data/, on purpose: test_sfx_reverse_orphan_audit
treats any literal key mention in data/*.json as a CONSUMER, so a baseline there would fake a
consumer for every cue it pins and silently satisfy that audit forever.

The -18dB gate matters: at -45dB the measurement runs deep into the decay tail and EVERY\npercussive cue looks like a sweep (attack_hit_dagger scored 6.3x and is simply a hit dying).\nA whoop GLIDES while still loud; a decay's centroid falls because the highs die first.\n\nGUT cannot do an FFT, so the ratchet is split: this tool measures and writes
test/fixtures/sfx_whoop_baseline.json (see the paragraph above for why NOT data/) (metrics + the sha256 of the exact bytes measured), and the GUT test
asserts the shipped bytes still hash to what was measured. Change a pinned cue and the test reds,
naming this tool -- you must re-measure rather than silently re-roll.
"""
import argparse, hashlib, json, os, subprocess, tempfile
from pathlib import Path
import numpy as np
import soundfile as sf

# Cues struktured rejected by ear, plus every slot their rotation can reach.
# ------------------------------------------------------------------------------------------------
# A CORPUS FLAG IS A REVIEW ITEM, NOT A DEFECT. Triaged all 5 flags on main 2026-09-09 (v3.33.246):
# ZERO were defects. Recorded so the next reader does not "fix" them, and so the precision of this
# tool on real content is on the record rather than implied by the flag count.
#
#   w6_ability_fire        DELIBERATE. Its prompt is "Pure rising tone -- concept of heat", and
#                          w6_ability_ice is "Pure descending tone -- concept of cold". The abstract
#                          world's ENTIRE vocabulary is pure glides, authored as a mirrored pair.
#                          ⛔ Do not fix one without the other, and do not fix either without
#                          struktured -- this instrument flags a design language, not a bug.
#   ability_bypass_puzzle  DELIBERATE. Skiptrotter's warp: the glide IS the semantic (you are being
#                          moved past content). 13.71x, the corpus maximum, and on purpose.
#   formation_arcane_tempest  borderline; a storm crescendo, quiet (-14 dB), 2.56x.
#   advance_mage_2         ARTIFACT. Two struck celesta chimes (a wrong note, then the right one),
#                          not a glide -- one outlier window at 2849 among a settled ~1050.
#   attack_hit_axe_crit    ARTIFACT. An impact bouncing down 2859->125; rho_energy +0.70 says the
#                          centroid is largely falling WITH the level, just under the 0.75 cut.
#
# A step-wise "monotonic fraction" was tried to separate the two artifacts and REJECTED on
# measurement: local wobble dominates it, so the genuine w6_ability_fire glide scored 0.60 while the
# axe impact scored 0.78 -- it inverts the very cases it was built to separate. Rank correlation is
# used precisely because it tolerates wobble while a step count cannot.
# ------------------------------------------------------------------------------------------------
PINNED = [
    "ability_fire", "ability_fire_v2", "ability_fire_v3",
    "ability_lightning", "ability_lightning_v2", "ability_lightning_v3",
    "ability_ice", "ability_ice_v2", "ability_ice_v3",
    "ability_dark",
    "ability_heal", "ability_heal_v2", "ability_heal_v3",
    "heal", "heal_v2", "heal_v3",
    "formation_shadow_strike", "status_poison", "status_pacify",
    # IMPACT side. struktured heard the whoop on impact after every CAST cue was clean:
    # EffectSystem routes spell impacts to strike_<element>, a separate family my first audit
    # never covered.
    "strike_fire", "strike_ice", "strike_lightning", "strike_dark", "strike_holy",
    "weakness_flash",
    # Everything else a W1 battle/shop/menu can reach that was found gliding.
    "purchase_complete", "autobattle_open", "portal_activate", "attack_hit_piano_scythe_crit",
    # Found only after the silent-skip fix: their loud part is under 3 windows.
    "autobattle_on", "attack_hit_staff",
    # New cue families, pinned at birth: song/summon/revival abilities had NO cue and played
    # ability_physical. Synthesised, so the sha256 here is what stops a later regenerate.
    "ability_song", "ability_summon", "ability_revive",
    "ability_poison", "ability_earth", "ability_wind", "ability_arcane",
    # the two world heals, no longer borrowing the base (2026-09-10)
    "w2_ability_heal", "w3_ability_heal",
    "ability_mp_restore", "ability_flee",
    "advance_flourish_2", "advance_flourish_3", "advance_flourish_4", "advance_flourish_5",
    # The two per-job press ladders whose DIRECTION is the joke: fighter ascends, rogue INVERTS
    # (quieter every press). rms_db is recorded so the GUT side can assert that shape.
    "advance_fighter_1", "advance_fighter_2", "advance_fighter_3", "advance_fighter_4", "advance_fighter_5",
    "advance_rogue_1", "advance_rogue_2", "advance_rogue_3", "advance_rogue_4", "advance_rogue_5",
    "advance_cleric_1", "advance_cleric_2", "advance_cleric_3", "advance_cleric_4", "advance_cleric_5",
    # advance_mage_2 is deliberately NOT pinned: it is the documented detector ARTIFACT in the
    # triage note above (two struck celesta chimes, one outlier window at 2849 Hz among a settled
    # ~1050). Pinning it would record whoops=true and red the ratchet over a non-defect, and
    # exempting it there would be a suppression. The ladder guard asserts rungs 3-5, which is the
    # escalation claim; rung 2's level is not part of it.
    "advance_mage_1", "advance_mage_3", "advance_mage_4", "advance_mage_5",
    "advance_bard_1", "advance_bard_2", "advance_bard_3", "advance_bard_4", "advance_bard_5",
    "full_bank_unleash",
    "status_cured",
    "ability_riff",
]
# BIDIRECTIONAL. The first version only looked for a RISE, so strike_dark sweeping 2670 -> 144 Hz
# scored "ok" -- a fall is a sweep and reads as a whoop just as much. That one-directional blind
# spot is why he heard it a fourth time.
SWEEP_MAX, LAND_MAX = 2.5, 2000.0
# 2026-09-09: the previous measurement was mean-of-thirds, which COMPRESSES a monotonic ramp --
# the early third is already climbing and the late third has already climbed. A synthetic glide
# with a TRUE centroid ratio of 3.43x reported 2.10x, under this 2.5x threshold. It fired on the
# extremes (18.6x, 6.4x) and so looked like it worked, while being blind to the ~3.4x case
# struktured actually complained about. Excursion is now min/max over the gated trajectory.
#
# Excursion alone flags SPEECH (a consonant swings the centroid in one window): bare min/max put
# 13 of 30 voice_* cues on the list. So two more terms, both of which the module docstring above
# already asserted in prose and neither of which was implemented:
#   RHO_TIME_MIN   a whoop TRENDS; texture merely swings.
#   RHO_ENERGY_MAX "a whoop GLIDES while still loud; a decay's centroid falls because the highs
#                  die first" -- so a decay artifact has centroid and level falling TOGETHER,
#                  a POSITIVE rank correlation. SIGNED, deliberately: a RISING glide under a
#                  decay correlates NEGATIVELY, and an abs() here rejected it as a decay.
RHO_TIME_MIN, RHO_ENERGY_MAX = 0.75, 0.75


def _rho(a, b):
    """Spearman rank correlation. Rank-based so a monotonic curve of any shape reads 1.0 --
    a glide is monotonic but not linear, and Pearson would under-read it."""
    if len(a) < 3:
        return 0.0
    ra = np.argsort(np.argsort(np.asarray(a, dtype=float))).astype(float)
    rb = np.argsort(np.argsort(np.asarray(b, dtype=float))).astype(float)
    ra -= ra.mean()
    rb -= rb.mean()
    d = np.sqrt((ra * ra).sum() * (rb * rb).sum())
    return float((ra * rb).sum() / d) if d > 0 else 0.0


def measure(path, nwin=16, gate_db=-18.0):
    wav = tempfile.mktemp(suffix=".wav")
    subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-ac", "1", "-ar", "22050", wav], check=True)
    x, sr = sf.read(wav)
    os.unlink(wav)
    if x.ndim > 1:
        x = x.mean(1)
    peak = np.max(np.abs(x)) + 1e-12
    n = len(x) // nwin
    cents, levels = [], []
    for i in range(nwin):
        seg = x[i * n:(i + 1) * n]
        if len(seg) < 64:
            continue
        db = 20 * np.log10((np.sqrt(np.mean(seg ** 2)) + 1e-12) / peak)
        if db < gate_db:
            continue
        X = np.abs(np.fft.rfft(seg * np.hanning(len(seg)))) + 1e-12
        f = np.fft.rfftfreq(len(seg), 1 / sr)
        cents.append(float((f * X).sum() / X.sum()))
        levels.append(float(db))
    # NEVER return silently on too-few windows. The -18dB gate dropped 46 of 264 W1 cues (17%)
    # because their loud part spans fewer than 3 windows, and "no result" was being read as
    # "nothing to report" -- attack_hit_staff (2.8x) and autobattle_on (3.8x) hid there.
    if len(cents) < 3 and gate_db > -42.0:
        m = measure(path, nwin, gate_db - 12.0)
        m["gate_widened"] = True
        return m
    rms_db = float(20.0 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-12))
    lo, hi = float(min(cents)), float(max(cents))
    sweep = hi / max(lo, 1e-9)
    rho_time = _rho(cents, list(range(len(cents))))
    rho_energy = _rho(cents, levels)
    # early/late are kept for continuity with older baselines and for reading the direction; they
    # are NO LONGER what `sweep` is computed from.
    third = max(1, len(cents) // 3)
    early = float(np.mean(cents[:third]))
    late = float(np.mean(cents[-third:]))
    return {
        "early_hz": round(early, 1),
        "late_hz": round(late, 1),
        "rms_db": round(rms_db, 1),
        "low_hz": round(lo, 1),
        "high_hz": round(hi, 1),
        "sweep": round(sweep, 2),
        "rho_time": round(rho_time, 2),
        "rho_energy": round(rho_energy, 2),
        "direction": "rise" if late > early else "fall",
        "whoops": bool(sweep >= SWEEP_MAX and abs(rho_time) >= RHO_TIME_MIN
                       and rho_energy < RHO_ENERGY_MAX and hi >= LAND_MAX),
        "gate_widened": False,
    }


def _synth(f0, f1, decay, dur=1.0, sr=22050, width=0.25, seed=5):
    """Narrowband noise whose CENTRE glides f0->f1, so the centroid IS the centre by construction.

    A control has to INSTANTIATE the measured quantity, not merely look like the defect. My first
    control was a square-wave glide -- raise a square's fundamental and you get FEWER harmonics
    under Nyquist, so its centroid barely moves. It reported "ok" and read as a blind instrument
    when it was a blind control.
    """
    rng = np.random.default_rng(seed)
    n = int(sr * dur)
    centre = np.linspace(f0, f1, n)
    t = np.arange(n) / sr
    y = np.zeros(n)
    for k in np.linspace(1 - width, 1 + width, 24):
        y += np.sin(2 * np.pi * np.cumsum(centre * k) / sr + rng.uniform(0, 6.28))
    y /= np.max(np.abs(y))
    env = np.exp(-t * decay) * np.minimum(1.0, t / 0.02)
    return (y * env).astype(np.float32), sr


def selftest():
    """Prove the detector still catches the defect it exists for. `--selftest` before trusting a run.

    Every arm is REQUIRED to have a reason it is here; a control that merely exercises the code
    path certifies nothing. The HELD arm is the load-bearing one: it must read back its own
    construction frequency, or the centroid arithmetic is wrong and every other arm is noise.
    """
    import wave
    arms = [
        ("rising glide 1400->4800, sustained", (1400, 4800, 0.0), True),
        ("falling glide 4800->1400, sustained", (4800, 1400, 0.0), True),
        ("rising glide under a MILD decay", (1400, 4800, 1.0), True),
        ("held 3000, no glide", (3000, 3000, 0.0), False),
        ("impact: bright->dull WITH the decay", (4200, 600, 3.0), False),
        ("quiet low band 200->600 (lands under LAND_MAX)", (200, 600, 0.0), False),
    ]
    ok = True
    print("  %-46s %8s %8s %9s   %s" % ("arm", "sweep", "rho_t", "rho_e", "verdict"))
    for label, (f0, f1, dec), expect in arms:
        y, sr = _synth(f0, f1, dec)
        tmp = tempfile.mktemp(suffix=".wav")
        with wave.open(tmp, "wb") as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
            w.writeframes((np.clip(y, -1, 1) * 32767).astype("<i2").tobytes())
        m = measure(tmp)
        os.unlink(tmp)
        good = (m["whoops"] == expect)
        ok = ok and good
        print("  %-46s %7.2fx %8.2f %9.2f   %-5s %s" % (
            label, m["sweep"], m["rho_time"], m["rho_energy"],
            "WHOOP" if m["whoops"] else "ok", "PASS" if good else "*** FAIL ***"))
    # The held arm must READ BACK its construction value, or nothing above means anything.
    y, sr = _synth(3000, 3000, 0.0)
    tmp = tempfile.mktemp(suffix=".wav")
    with wave.open(tmp, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
        w.writeframes((np.clip(y, -1, 1) * 32767).astype("<i2").tobytes())
    m = measure(tmp); os.unlink(tmp)
    within = abs(m["high_hz"] - 3000.0) < 60.0
    ok = ok and within
    print("  %-46s %7.0f Hz vs 3000 constructed   %s" % (
        "CALIBRATION: held tone reads back its own centre", m["high_hz"], "PASS" if within else "*** FAIL ***"))
    print("\n  selftest: %s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--write", action="store_true", help="refresh the pinned baseline")
    ap.add_argument("--selftest", action="store_true", help="prove the detector still catches a synthetic whoop")
    a = ap.parse_args()
    if a.selftest:
        raise SystemExit(selftest())
    root = Path(__file__).resolve().parent.parent
    sfx = json.loads((root / "data/sfx_manifest.json").read_text())["sfx"]
    out, bad = {}, []
    for key in PINNED:
        rel = sfx.get(key, {}).get("file")
        if not rel or not (root / rel).exists():
            print(f"  MISSING  {key}")
            continue
        p = root / rel
        m = measure(p)
        m["sha256"] = hashlib.sha256(p.read_bytes()).hexdigest()
        m["file"] = rel
        out[key] = m
        flag = "WHOOP" if m["whoops"] else "ok"
        print(f"  {flag:6s} {key:26s} {m['early_hz']:7.0f} -> {m['late_hz']:7.0f}  {m['sweep']:5.2f}x {m['direction']}")
        if m["whoops"]:
            bad.append(key)
    if a.write:
        (root / "test/fixtures/sfx_whoop_baseline.json").write_text(
            json.dumps({"_note": "written by tools/audit_whoop.py --write; the GUT test pins these hashes",
                        "sweep_max": SWEEP_MAX, "land_max_hz": LAND_MAX, "cues": out}, indent=2) + "\n")
        print(f"\n  wrote baseline for {len(out)} cues")
    if bad:
        print(f"\n  WHOOPING: {bad}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
