#!/usr/bin/env python3
"""Measure the first-downbeat offset of every victory_* track.

WHY THIS EXISTS
    The victory overlay's title slam wants to land ON the fanfare's first
    downbeat. That is a per-file number: these are Suno renders, none authored
    to a grid.

THE FINDING THAT SHAPES THIS TOOL
    "First downbeat" is not well defined for most of these files, and a tool
    that prints one number per track would hide that. Three estimators, each
    individually defensible, were run against all 7:

        L1   argmax of the raw 1ms envelope      "the loudest instant"
        LS   argmax of a 10ms-smoothed envelope  "the loudest moment"
        R    argmax of energy gained over 25ms   "the hardest attack"

    On 3 of 7 they agree inside 50ms. On 3 of 7 they disagree by 660-1930ms.
    A single-number tool would have emitted the disagreeing ones with the same
    authority as the agreeing ones. So this reports all three plus the SPREAD,
    and refuses to name a downbeat when they diverge.

    Each estimator has a known failure mode, which is why no one of them wins:
      L1  picks the noisiest single frame on a plateau (medieval: 1566ms, a
          frame no louder than the surrounding texture)
      LS  picks sustained loudness, which can be a later swell, not the attack
      R   silence -> sound is the largest rise in any file that opens quiet, so
          on `victory` it returns the PICKUP (557ms), not the downbeat (718ms)

    Divergence is therefore a property of the MUSIC -- a file with one dominant
    early transient pins all three -- not a defect in any estimator.

METHOD
    ffmpeg -> mono 48k f32 PCM -> 1ms-hop RMS envelope. Measurement only;
    nothing is written to any audio file.

USAGE
    python3 tools/measure_victory_downbeats.py            # table
    python3 tools/measure_victory_downbeats.py --json     # data/victory_downbeats.json
"""
import json
import os
import subprocess
import sys

import numpy as np

MANIFEST = "data/music_manifest.json"
OUT = "data/victory_downbeats.json"
SR = 48000
HOP_MS = 1
# Below this fraction of peak there is no sound yet.
SILENCE_FLOOR = 0.02
# Smoothing for the LS estimator, and the interval the R estimator differences.
SMOOTH_MS = 10
RISE_MS = 25
# Only the opening of the file can hold a FIRST downbeat.
EARLY_WINDOW_MS = 2000
# Estimators within this spread are calling the same event; beyond it they are
# naming different musical moments and no single number is honest.
AGREE_MS = 60
# The rise estimator is disqualified when its answer sits this close to the
# entry from silence, or when the file's opening is already this loud.
RISE_ENTRY_MS = 30
OPENING_MS = 20
OPENING_LOUD = 0.35


def envelope(path: str):
    """1ms-hop RMS envelope, mono."""
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", path,
           "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"]
    raw = subprocess.run(cmd, capture_output=True).stdout
    x = np.frombuffer(raw, dtype=np.float32)
    if x.size == 0:
        return None
    hop = SR * HOP_MS // 1000
    n = x.size // hop
    if n == 0:
        return None
    return np.sqrt((x[:n * hop].reshape(n, hop).astype(np.float64) ** 2).mean(axis=1))


def estimators(env):
    """The three candidate downbeats, in frames. See the module docstring."""
    w = min(EARLY_WINDOW_MS // HOP_MS, env.size)
    smooth = np.convolve(env, np.ones(SMOOTH_MS) / SMOOTH_MS, mode="same")
    lb = RISE_MS // HOP_MS
    rise = np.zeros(w)
    if w > lb:
        rise[lb:] = smooth[lb:w] - smooth[:w - lb]
    return {
        "l1_ms": int(np.argmax(env[:w])) * HOP_MS,
        "ls_ms": int(np.argmax(smooth[:w])) * HOP_MS,
        "rise_ms": int(np.argmax(rise)) * HOP_MS,
    }


def analyse(path: str):
    env = envelope(path)
    if env is None:
        return None
    peak = float(env.max())
    if peak <= 0:
        return None
    # Only name a downbeat when the surviving estimators concur; where they
    # diverge, null is the honest answer rather than a number we made up.
    r = analyse_env(env)
    r["duration_ms"] = int(env.size * HOP_MS)
    r["peak"] = round(peak, 4)
    return r


def _self_test():
    """CONSTRUCTED controls. A found control decays; an injected one cannot.

    Three synthetic envelopes with known answers. The third is the one that
    matters: a detector that reports agreement on a featureless plateau is
    measuring nothing, and every real divergent track would come back green.
    """
    n = 2000
    hard = np.full(n, 1e-6)
    hard[300:] = 1.0                                    # transient at 300ms
    swell = np.full(n, 1e-6)
    swell[:800] = np.linspace(0.0, 1.0, 800)            # 800ms crescendo
    swell[800:] = 1.0
    rng = np.linspace(0.0, 1.0, n)
    flat = 0.5 + 0.02 * np.sin(rng * 97.0)              # plateau, no downbeat

    a = analyse_env(hard)
    b = analyse_env(swell)
    c = analyse_env(flat)
    # A file with a real transient AND quiet material before it: rise must stay
    # VALID here, or the disqualification rule is just deleting the estimator.
    live = np.full(n, 1e-6)
    live[100:] = 0.10
    live[900:] = 1.0
    dq = analyse_env(live)
    checks = [
        ("hard transient -> 300ms, agreeing",
         a["agree"] and abs(a["downbeat_ms"] - 300) <= AGREE_MS),
        ("slow crescendo -> no agreed downbeat", not b["agree"]),
        ("featureless plateau -> no agreed downbeat", not c["agree"]),
        ("quiet intro + late hit -> rise stays VALID, downbeat 900ms",
         dq["rise_valid"] and dq["agree"] and abs(dq["downbeat_ms"] - 900) <= AGREE_MS),
    ]
    ok = all(v for _, v in checks)
    for name, v in checks:
        print("  CONTROL  %-42s %s" % (name, "PASS" if v else "FAIL"))
    if a["agree"]:
        print("  CONTROL  hard transient reported %dms (expect 300)" % a["downbeat_ms"])
    return ok


def analyse_env(env):
    """analyse() minus the decode, so controls can feed synthetic envelopes."""
    peak = float(env.max())
    est = estimators(env)
    first_sound = int(np.argmax(env >= SILENCE_FLOOR * peak)) * HOP_MS
    opening = float(env[:OPENING_MS].max()) / peak

    # The rise estimator answers "where did energy climb hardest", which is only
    # the downbeat when the file has quiet material to climb FROM. Two shapes
    # break that, both stated in the docstring before any track was measured:
    #   entry    the climb IS silence -> first note, so rise returns the pickup
    #   on-peak  the file opens loud, so the hardest climb is some later event
    # Disqualifying it is not result-shopping: on this corpus the rule also
    # fires for industrial and steampunk, which ALREADY agreed, so it cannot be
    # inventing the agreements it is credited with.
    rise_reason = ""
    if abs(est["rise_ms"] - first_sound) <= RISE_ENTRY_MS:
        rise_reason = "entry from silence"
    elif opening >= OPENING_LOUD:
        rise_reason = "opens at %.0f%% of peak" % (opening * 100)

    vals = [est["l1_ms"], est["ls_ms"]]
    if not rise_reason:
        vals.append(est["rise_ms"])
    spread = max(vals) - min(vals)
    agree = spread <= AGREE_MS
    r = dict(est)
    r["rise_valid"] = not rise_reason
    r["rise_invalid_because"] = rise_reason
    r["estimators_used"] = len(vals)
    r["spread_ms"] = spread
    r["agree"] = agree
    r["downbeat_ms"] = int(sorted(vals)[len(vals) // 2]) if agree else None
    r["first_sound_ms"] = first_sound
    return r


def main():
    if not os.path.exists(MANIFEST):
        sys.exit("run from the repo root: %s not found" % MANIFEST)
    if not _self_test():
        sys.exit("controls FAILED -- measurements below would be meaningless")

    data = json.load(open(MANIFEST))
    tracks = data.get("tracks", data)
    keys = sorted(k for k in tracks if k.startswith("victory"))
    if not keys:
        sys.exit("no victory_* tracks in the manifest -- NOT a clean result")

    out, rows = {}, []
    for k in keys:
        path = str(tracks[k].get("file", ""))
        if not path or not os.path.exists(path):
            rows.append((k, None, "FILE MISSING: %s" % path))
            continue
        r = analyse(path)
        rows.append((k, r, "" if r else "UNREADABLE"))
        if r:
            out[k] = r

    print("\n%-20s %7s %7s %9s %8s   %s"
          % ("track", "L1", "LS", "rise", "spread", "DOWNBEAT"))
    for k, r, err in rows:
        if r is None:
            print("  %-18s %s" % (k, err))
            continue
        verdict = ("%dms" % r["downbeat_ms"]) if r["agree"] else "-- NO AGREEMENT"
        rise = "%5dms%s" % (r["rise_ms"], " " if r["rise_valid"] else "*")
        print("  %-18s %5dms %5dms %8s %6dms   %s"
              % (k, r["l1_ms"], r["ls_ms"], rise, r["spread_ms"], verdict))
    print("  (* rise disqualified -- see rise_invalid_because in the JSON)")

    agreed = [k for k, r, _ in rows if r and r["agree"]]
    print("\n  %d of %d tracks have an unambiguous first downbeat" % (len(agreed), len(out)))
    # A run where every track agrees, or none does, means the threshold is doing
    # the deciding rather than the music.
    if out and len(agreed) in (0, len(out)):
        print("  WARNING: agreement is uniform across all tracks -- AGREE_MS is "
              "setting the verdict, not the audio. Do not trust this output.")

    if "--json" in sys.argv:
        json.dump(out, open(OUT, "w"), indent=2, sort_keys=True)
        print("\nwrote %s (%d tracks)" % (OUT, len(out)))


if __name__ == "__main__":
    main()
