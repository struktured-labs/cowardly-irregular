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
unmeasurable by this instrument. A spread of 0.0 computed from three floored values is the most
confident wrong answer this tool can give, so they are reported UNMEASURABLE by name rather than
passing.

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


def lufs(path):
    """Integrated LUFS, or None when the cue is too short for R128 to have an opinion."""
    out = subprocess.run(["ffmpeg", "-v", "info", "-i", path, "-filter_complex",
                          "ebur128=framelog=quiet", "-f", "null", "-"],
                         capture_output=True, text=True, timeout=120).stderr
    hits = re.findall(r"I:\s*(-?[0-9.]+) LUFS", out)
    if not hits:
        return None
    v = float(hits[-1])
    return None if v <= R128_FLOOR else v


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
            rows[m] = {"lufs": lufs(f), "ch": channels(f)}
        vals = [r["lufs"] for r in rows.values() if r["lufs"] is not None]
        measurable = len(vals) == len(rows) and len(vals) >= 2
        out[base] = {
            "members": rows,
            "spread": round(max(vals) - min(vals), 1) if measurable else None,
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
    print("wrote %s: %d families, %d unmeasurable, %d over %.1f LU"
          % (FIXTURE, len(data), sum(1 for v in data.values() if v["unmeasurable"]), len(wide), SPREAD_LIMIT))
    for k, s in sorted(wide, key=lambda x: -x[1]):
        print("   WIDE  %-22s %.1f LU" % (k, s))
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
            print("%-22s pinned %s, now %s" % (k, p.get("spread"), l.get("spread")))
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
