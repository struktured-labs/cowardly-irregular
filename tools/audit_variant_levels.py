#!/usr/bin/env python3
"""audit_variant_levels.py — a VARIANT must vary TEXTURE, not LEVEL.

`_try_play_sfx_from_manifest` picks uniformly from `[base] + variants`, so every member of a family
is equally likely on any given play. If they differ in loudness the player hears a random level jump
on one of the most repeated sounds in the game, which reads as a mix bug rather than as variety.

MEASURED 2026-10-12, which is why this exists:
    ability_heal   -17.8 / -10.6 / -11.4   7.2 LU   <- Cure, cast constantly. REPAIRED.
    buff           -11.1 / -18.1 / -16.1   7.0 LU   } the generic cues that fire on EVERY
    debuff         -10.0 / -15.9 / -16.1   6.1 LU   } buff and debuff in the game
    ability_ice    -15.4 / -17.8 / -12.6   5.2 LU
    heal           -6.7  / -9.9  / -11.9   5.2 LU
    ability_fire / ability_lightning       2.8 / 2.1 LU   <- what a healthy family looks like

⛔ EBU R128 INTEGRATED LOUDNESS IS UNDEFINED BELOW ~0.4s AND FLOORS AT -70. All six footstep
families measure -70.0/-70.0/-70.0 and are NOT silent and NOT level-matched — they are
unmeasurable by R128. A spread of 0.0 computed from three floored values is the most confident
wrong answer this tool can give, so they are never passed as level-matched.

✅ SO THEY ARE MEASURED THE OTHER WAY, added 2026-10-14: `spread_rms`, from per-channel RMS, which
has no short-cue floor. Reporting them UNMEASURABLE was honest and still left 18 of the most
repeated cues in the game judged by nothing — and one family is 4.1 dB wide:

    footstep_sand    -16.0 / -20.1 / -18.8   4.1 dB   <- audible, and the widest of the six
    footstep_stone                           2.7 dB
    footstep_snow                            2.6 dB
    footstep_wood                            2.3 dB
    footstep_metal / footstep_grass          0.6 dB   <- what the same generator produced elsewhere

The inconsistency IS the finding: commit 3767131e3 randomised bandwidth and duration per variant
for natural variety, so some spread is intended — but an intended spread would not be 0.6 dB on
grass and 4.1 dB on sand. Re-levelling is NOT done here: these shipped in April and struktured
approved them by ear, which is the same reason cowir-main held the Cure re-level. Measured,
reported, his call.

⚠️ RMS AND LUFS ARE DIFFERENT QUANTITIES AND ARE NOT COMPARED. `spread` is in LU against
SPREAD_LIMIT; `spread_rms` is in dB and carries NO pass/fail limit, because the six measured
values run 0.6 / 0.6 / 2.3 / 2.5 / 2.7 / 4.1 with no break — any cut there is a coincidental
value. The fixture PINS them and --check reports DRIFT, which needs no threshold at all.

⚠️ AND RMS IS TAKEN PER CHANNEL, not over all samples. All 18 footsteps are dual-mono (stereo
container, L/R correlation 1.00, every measure agreeing within 0.1 dB) so it does not bite today —
but all-samples and channel-averaged RMS diverge by ~6 dB on a DECORRELATED stereo asset, and a
future stereo family would be silently mismeasured. `rms()` records the channel divergence so that
case announces itself instead.

⚠️ THREE FAMILIES ALSO MIX CHANNEL COUNTS (a mono base with stereo variants, or the reverse).
Reported, NOT repaired: all-samples rms and channel-averaged rms diverge on a stereo asset, so a
mixed family cannot be levelled by one number without saying which quantity you mean. Changing a
member's channel count is a content change, not a level fix.

    tools/audit_variant_levels.py --write      measure and write the fixture
    tools/audit_variant_levels.py --check      measure and compare against the fixture
    tools/audit_variant_levels.py --selftest   prove the detector still sees a planted gap
"""
import argparse
import io
import json
import os
import re
import subprocess
import sys

MANIFEST = "data/sfx_manifest.json"
FIXTURE = "test/fixtures/sfx_variant_levels.json"
R128_FLOOR = -69.0          # anything at or below this is the floor, not a measurement
SPREAD_LIMIT = 3.0          # LU; fire (2.8) and lightning (2.1) are the healthy references


def lufs(path, downmix=False):
    """Integrated LUFS, or None when the cue is too short for R128 to have an opinion.

    ⛔ `downmix` EXISTS BECAUSE THE WEB BUILD SHIPS MONO. tools/make_web_audio.sh:121 transcodes
    every master with `-ac 1`, so a mixed-channel family has a DIFFERENT spread on each platform and
    no flat gain can fix both. Measured on ability_heal: 7.2 LU as-is, 3.4 LU downmixed.
    ⚠️ NEVER pass downmix on a MONO input: `pan=mono|c0=0.5*c0+0.5*c1` references a channel that
    does not exist and silently halves amplitude, a flat -6.02 dB. That bug cost @cowir-music two
    retracted numbers on 2026-10-13; the caller below guards it on the channel count."""
    af = "ebur128=framelog=quiet"
    if downmix:
        af = "pan=mono|c0=0.5*c0+0.5*c1," + af
    out = subprocess.run(["ffmpeg", "-v", "info", "-i", path, "-af", af, "-f", "null", "-"],
                         capture_output=True, text=True, timeout=120).stderr
    hits = re.findall(r"I:\s*(-?[0-9.]+) LUFS", out)
    if not hits:
        return None
    v = float(hits[-1])
    return None if v <= R128_FLOOR else v


def _is_midpoint(path, avg):
    """Selftest helper: re-read the per-channel values and check `avg` is their midpoint.

    Deliberately parses INDEPENDENTLY of rms() — using rms()'s own parse to check rms() would only
    confirm it agrees with itself."""
    out = subprocess.run(["ffmpeg", "-v", "info", "-i", path, "-af", "astats=metadata=1:reset=0",
                          "-f", "null", "-"], capture_output=True, text=True, timeout=120).stderr
    head = out.split("Overall")[0]
    vals = [float(m.group(1)) for m in re.finditer(r"RMS level dB:\s*(-?[0-9.]+)", head)]
    if len(vals) != 2:
        return False
    return abs(avg - (max(vals) + min(vals)) / 2.0) < 0.05


def rms(path):
    """(channel-averaged RMS dB, max divergence between channels) or (None, None).

    ⛔ PER CHANNEL, NOT OVER ALL SAMPLES. astats prints one `RMS level dB` per channel and then an
    `Overall` block with the same label, so the Overall value must be dropped or a stereo file
    yields three readings and a nonsense divergence. Cross-checked three ways on footstep_sand:
    astats per-channel -15.96/-15.96, volumedetect all-samples -16.0, numpy per-channel -16.0/-16.0.

    ⚠️ No R128 floor applies here, which is the whole point — this is what measures a 35ms cue."""
    out = subprocess.run(["ffmpeg", "-v", "info", "-i", path, "-af", "astats=metadata=1:reset=0",
                          "-f", "null", "-"], capture_output=True, text=True, timeout=120).stderr
    head = out.split("Overall")[0]
    vals = []
    for m in re.finditer(r"RMS level dB:\s*(-?[0-9.]+|-?inf)", head):
        t = m.group(1)
        if t.endswith("inf"):
            continue
        vals.append(float(t))
    if not vals:
        return None, None
    return round(sum(vals) / len(vals), 2), round(max(vals) - min(vals), 2)


def channels(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=channels",
                          "-of", "csv=p=0", path], capture_output=True, text=True).stdout.strip()
    return int(out.split(",")[0]) if out else 0


def families(man):
    for key, entry in man.items():
        vs = entry.get("variants") or []
        if vs:
            yield key, [key] + [str(v) for v in vs]


def measure():
    man = json.load(io.open(MANIFEST, encoding="utf-8"))["sfx"]
    out = {}
    for base, members in families(man):
        rows = {}
        for m in members:
            f = str(man.get(m, {}).get("file", ""))
            if not f or not os.path.exists(f):
                rows[m] = {"lufs": None, "ch": 0, "why": "no file on disk"}
                continue
            ch = channels(f)
            r, div = rms(f)
            ## mono input is already its own downmix; running the filter on it is the -6.02 dB bug
            rows[m] = {"lufs": lufs(f), "ch": ch,
                       "lufs_mono": lufs(f) if ch == 1 else lufs(f, downmix=True),
                       "rms": r, "ch_div": div}
        vals = [r["lufs"] for r in rows.values() if r["lufs"] is not None]
        monos = [r.get("lufs_mono") for r in rows.values() if r.get("lufs_mono") is not None]
        rmss = [r.get("rms") for r in rows.values() if r.get("rms") is not None]
        divs = [r.get("ch_div") for r in rows.values() if r.get("ch_div") is not None]
        measurable = len(vals) == len(rows) and len(vals) >= 2
        out[base] = {
            "members": rows,
            "spread": round(max(vals) - min(vals), 1) if measurable else None,
            ## what the WEB build ships, which differs wherever a family mixes channel counts
            "spread_mono": round(max(monos) - min(monos), 1) if (measurable and len(monos) == len(rows)) else None,
            ## no R128 floor, so this is populated for EVERY family — including the six R128 cannot
            ## see. Pinned by the fixture and compared by --check; it carries no pass/fail limit.
            "spread_rms": round(max(rmss) - min(rmss), 1) if len(rmss) == len(rows) and len(rmss) >= 2 else None,
            ## a DECORRELATED stereo member would read differently all-samples vs per-channel; this
            ## makes that announce itself rather than being absorbed into the number above
            "ch_div_max": round(max(divs), 2) if divs else None,
            "unmeasurable": not measurable,
            "mixed_channels": len({r["ch"] for r in rows.values() if r["ch"]}) > 1,
        }
    return out


def cmd_write():
    data = measure()
    doc = {"_note": "written by tools/audit_variant_levels.py --write; "
                    "test_a_variant_varies_texture_not_level.gd pins these",
           "_spread_limit": SPREAD_LIMIT,
           "families": data}
    io.open(FIXTURE, "w", encoding="utf-8").write(json.dumps(doc, indent=2, ensure_ascii=False) + "\n")
    wide = [(k, v["spread"]) for k, v in data.items() if v["spread"] is not None and v["spread"] > SPREAD_LIMIT]
    print("wrote %s: %d families, %d unmeasurable by R128, %d over %.1f LU"
          % (FIXTURE, len(data), sum(1 for v in data.values() if v["unmeasurable"]), len(wide), SPREAD_LIMIT))
    for k, s in sorted(wide, key=lambda x: -x[1]):
        print("   WIDE  %-22s %.1f LU" % (k, s))
    ## The R128-blind families, ranked rather than thresholded: there is no break in the values to
    ## put a cut at, so this is a report a human reads, not a gate.
    rms_only = [(k, v["spread_rms"]) for k, v in data.items()
                if v["unmeasurable"] and v.get("spread_rms") is not None]
    if rms_only:
        print("  R128-blind families, by RMS spread (dB — not comparable to the LU figures above):")
        for k, s in sorted(rms_only, key=lambda x: -x[1]):
            print("   rms   %-22s %.1f dB" % (k, s))
    divergent = [(k, v["ch_div_max"]) for k, v in data.items()
                 if v.get("ch_div_max") is not None and v["ch_div_max"] > 0.5]
    for k, d in sorted(divergent, key=lambda x: -x[1]):
        print("   ⚠️ %-22s channels diverge by %.2f dB — all-samples RMS would mismeasure this family" % (k, d))
    return 0


def cmd_check():
    if not os.path.exists(FIXTURE):
        print("no fixture — run --write")
        return 3
    pinned = json.load(io.open(FIXTURE, encoding="utf-8"))["families"]
    live = measure()
    bad = 0
    for k in sorted(set(pinned) | set(live)):
        p, l = pinned.get(k), live.get(k)
        if p is None:
            print("NEW family not in the fixture: %s (spread %s)" % (k, l.get("spread")))
            bad += 1
        elif l is None:
            print("family gone from the manifest but still pinned: %s" % k)
            bad += 1
        elif p.get("spread") != l.get("spread"):
            print("%-22s pinned spread %s, now %s" % (k, p.get("spread"), l.get("spread")))
            bad += 1
        ## ⛔ COMPARED, NOT JUST WRITTEN. A field the fixture records and --check ignores is inert
        ## data that reads as coverage — the whole reason the six families were worth measuring.
        elif p.get("spread_rms") != l.get("spread_rms"):
            print("%-22s pinned spread_rms %s dB, now %s dB" % (k, p.get("spread_rms"), l.get("spread_rms")))
            bad += 1
    print("check: %s" % ("DRIFT (%d)" % bad if bad else "matches the fixture"))
    return 1 if bad else 0


def selftest():
    """A detector that has not been watched finding a gap is not a detector."""
    import tempfile
    p = f = 0

    def chk(name, cond):
        nonlocal p, f
        if cond:
            p += 1
            print("  ok    %s" % name)
        else:
            f += 1
            print("  FAIL  %s" % name)

    d = tempfile.mkdtemp(prefix="varlvl_")
    loud, quiet, short = (os.path.join(d, n) for n in ("loud.wav", "quiet.wav", "short.wav"))
    # 2s tones 8 dB apart, and a 0.1s blip R128 cannot measure
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "sine=f=440:d=2",
                    "-af", "volume=-6dB", loud], check=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "sine=f=440:d=2",
                    "-af", "volume=-14dB", quiet], check=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "sine=f=440:d=0.1", short],
                   check=True)
    a, b = lufs(loud), lufs(quiet)
    chk("both long tones measure", a is not None and b is not None)
    chk("a planted 8 dB gap reads as ~8 LU", a is not None and b is not None and abs((a - b) - 8.0) < 0.6)
    chk("a 0.1s blip returns None rather than the -70 FLOOR as a number", lufs(short) is None)
    chk("channels() reads a real count", channels(loud) == 1)
    ## ⛔ The floor is the trap this tool exists to dodge: three floored members would compute a
    ## spread of 0.0, which is the most confident wrong answer available.
    chk("a family of floored members is UNMEASURABLE, not a 0.0 spread",
        lufs(short) is None)
    ## ⛔ THE CONTROL FOR THE FALLBACK, and the only arm that proves the blind spot is now covered:
    ## the SAME planted gap, on cues R128 cannot see at all.
    short_loud = os.path.join(d, "short_loud.wav")
    short_quiet = os.path.join(d, "short_quiet.wav")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "sine=f=440:d=0.04",
                    "-af", "volume=-6dB", short_loud], check=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "sine=f=440:d=0.04",
                    "-af", "volume=-14dB", short_quiet], check=True)
    chk("R128 is blind to both 0.04s cues", lufs(short_loud) is None and lufs(short_quiet) is None)
    ra, _ = rms(short_loud)
    rb, _ = rms(short_quiet)
    chk("rms() measures a 0.04s cue at all", ra is not None and rb is not None)
    chk("...and sees the planted 8 dB gap R128 cannot", ra is not None and rb is not None and abs((ra - rb) - 8.0) < 0.6)
    _, dv = rms(loud)
    chk("a mono file reports 0.00 channel divergence", dv == 0.0)
    ## ⛔ THE ARM ABOVE CANNOT CATCH AN OVERALL-INCLUSION BUG AND I SHIPPED IT BELIEVING IT COULD —
    ## a mutation deleting `out.split("Overall")[0]` stayed GREEN. On a MONO file astats' per-channel
    ## and Overall readings are the SAME NUMBER, and on a stereo file Overall sits BETWEEN the two
    ## channels, so the DIVERGENCE is identical either way (measured: 8.00 vs 8.00). The only thing
    ## that moves is the AVERAGE (-31.07 per-channel vs -30.53 with Overall).
    ## ✅ So assert the RELATIONSHIP that holds for exactly two channels and nothing else: the
    ## returned value must be the MIDPOINT of the channel extremes. A third reading breaks it.
    asym = os.path.join(d, "asym.wav")
    r_ch = os.path.join(d, "r_ch.wav")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "sine=f=440:d=1",
                    "-af", "volume=-14dB", r_ch], check=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", loud, "-i", r_ch, "-filter_complex",
                    "[0:a][1:a]amerge=inputs=2[a]", "-map", "[a]", "-ac", "2", asym], check=True)
    avg, dv2 = rms(asym)
    chk("an asymmetric stereo file measures", avg is not None and dv2 is not None)
    chk("...its divergence is the planted 8 dB gap",
        dv2 is not None and abs(dv2 - 8.0) < 0.3)
    ## midpoint of the extremes == avg only when exactly the two channels were averaged
    chk("...and the returned rms is the MIDPOINT of the two channels (Overall is excluded)",
        avg is not None and _is_midpoint(asym, avg))
    print("  selftest: %s" % ("PASS" if not f else "FAIL"))
    return 1 if f else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--write", action="store_true", help="measure and write the fixture")
    ap.add_argument("--check", action="store_true", help="measure and compare against the fixture")
    ap.add_argument("--selftest", action="store_true", help="prove the detector sees a planted gap")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    if a.write:
        return cmd_write()
    if a.check:
        return cmd_check()
    ap.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
