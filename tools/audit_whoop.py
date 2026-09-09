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
data/sfx_whoop_baseline.json (metrics + the sha256 of the exact bytes measured), and the GUT test
asserts the shipped bytes still hash to what was measured. Change a pinned cue and the test reds,
naming this tool -- you must re-measure rather than silently re-roll.
"""
import argparse, hashlib, json, os, subprocess, tempfile
from pathlib import Path
import numpy as np
import soundfile as sf

# Cues struktured rejected by ear, plus every slot their rotation can reach.
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
]
# BIDIRECTIONAL. The first version only looked for a RISE, so strike_dark sweeping 2670 -> 144 Hz
# scored "ok" -- a fall is a sweep and reads as a whoop just as much. That one-directional blind
# spot is why he heard it a fourth time.
SWEEP_MAX, LAND_MAX = 2.5, 2000.0


def measure(path, nwin=10, gate_db=-18.0):
    wav = tempfile.mktemp(suffix=".wav")
    subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-ac", "1", "-ar", "22050", wav], check=True)
    x, sr = sf.read(wav)
    os.unlink(wav)
    if x.ndim > 1:
        x = x.mean(1)
    peak = np.max(np.abs(x)) + 1e-12
    n = len(x) // nwin
    cents = []
    for i in range(nwin):
        seg = x[i * n:(i + 1) * n]
        if len(seg) < 64:
            continue
        if 20 * np.log10((np.sqrt(np.mean(seg ** 2)) + 1e-12) / peak) < gate_db:
            continue
        X = np.abs(np.fft.rfft(seg * np.hanning(len(seg)))) + 1e-12
        f = np.fft.rfftfreq(len(seg), 1 / sr)
        cents.append(float((f * X).sum() / X.sum()))
    # NEVER return silently on too-few windows. The -18dB gate dropped 46 of 264 W1 cues (17%)
    # because their loud part spans fewer than 3 windows, and "no result" was being read as
    # "nothing to report" -- attack_hit_staff (2.8x) and autobattle_on (3.8x) hid there.
    if len(cents) < 3 and gate_db > -42.0:
        m = measure(path, nwin, gate_db - 12.0)
        m["gate_widened"] = True
        return m
    third = max(1, len(cents) // 3)
    early = float(np.mean(cents[:third])) if cents else 0.0
    late = float(np.mean(cents[-third:])) if cents else 0.0
    ratio = late / max(early, 1e-9)
    sweep = max(ratio, 1.0 / max(ratio, 1e-9))
    return {
        "early_hz": round(early, 1),
        "late_hz": round(late, 1),
        "sweep": round(sweep, 2),
        "direction": "rise" if ratio > 1.0 else "fall",
        "whoops": bool(sweep >= SWEEP_MAX and max(early, late) >= LAND_MAX),
        "gate_widened": False,
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--write", action="store_true", help="refresh the pinned baseline")
    a = ap.parse_args()
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
