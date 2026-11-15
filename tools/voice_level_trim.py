#!/usr/bin/env python3
"""voice_level_trim.py — derive a per-line `gain_db` so every voice pack sits at one loudness.

WHY, measured rather than assumed (EBU R128 integrated loudness, 654 clips, 2026-10-12):

    pack                  n    median    p5..p95 spread
    fighter (ElevenLabs)  50   -18.0     0.4 LU      <- normalised
    rogue                151   -16.4     3.5 LU
    mage                 151   -16.8     4.4 LU
    cleric               151   -18.5     4.2 LU
    bard                 151   -16.9     4.6 LU

Two defects in one measurement. WITHIN a pack, up to 4.6 LU separates one line from another in the
same voice. BETWEEN packs the medians differ by 2.1 LU, so the Cleric is systematically quieter than
the Rogue in a party where both speak. The ElevenLabs pack is the existence proof that 0.4 LU is
achievable — this is not a limit of the medium, it is that the free-engine renders were never
levelled.

⚠️ A GAIN, NOT A RE-RENDER, AND THAT IS DELIBERATE. struktured approved these clips by ear; this
changes their LEVEL only, lives in one JSON field per clip, and reverts by deleting the field.
Re-encoding 604 approved files to move their level would be an irreversible edit to content he
signed off, for a change a playback gain makes exactly.

⛔ CLIPPING IS CHECKED, NOT HOPED. A quiet line needs positive gain, and the voice player already
sits at VOICE_PLAYER_BASE_DB (-4.0 dB), so the headroom for each clip is its own true peak. Any gain
that would push peak + base above the ceiling is CLAMPED and reported — a clamped line stays quieter
than target rather than clipping, and the tool says which and by how much.

RECORDED DIALOGUE LINES ARE A SECOND CLASS WITH THEIR OWN TARGET (2026-11-14). Every entry carrying a
`line` field is what SoundManager.play_voiced_line can reach (voiced_line_clip selects on `e.has("line")`),
and it applies the same `VOICE_PLAYER_BASE_DB + gain_db`. Those 387 boss lines were rendered to
-16 LUFS under a -1 dBTP ceiling (their commit bodies), and the ceiling held 44 of them more than
1 LU short: measured median -16.4, range -19.4..-15.5, so Voltharion's wind-up bark sat 3.9 LU under
his loudest line. They keep their OWN target, -16, not the party's -18: they were approved at that
level beside the party, and this only closes the spread inside the set.

    tools/voice_level_trim.py --report            measure and print, write nothing
    tools/voice_level_trim.py --apply             write gain_db into data/sfx_manifest.json
    tools/voice_level_trim.py --selftest
"""
import glob
import io
import json
import os
import re
import subprocess
import sys

MANIFEST = "data/sfx_manifest.json"
TARGET_LUFS = -18.0          # the ElevenLabs pack's own median — his stated bar, measured
BASE_DB = -4.0               # SoundManager.VOICE_PLAYER_BASE_DB
PEAK_CEILING_DB = -1.0       # headroom left after base + gain
MAX_GAIN_DB = 6.0            # a line needing more than this is a bad render, not a level problem


def loudness(path):
    """(integrated LUFS, true peak dBFS) or None. Raises nothing silently: a clip that will not
    measure is reported, never defaulted to 0 — that would hand it a gain computed from nothing."""
    out = subprocess.run(["ffmpeg", "-v", "info", "-i", path, "-filter_complex",
                          "ebur128=peak=true:framelog=quiet", "-f", "null", "-"],
                         capture_output=True, text=True, timeout=60).stderr
    i = re.search(r"I:\s*(-?[0-9.]+)\s*LUFS", out)
    p = re.search(r"Peak:\s*(-?[0-9.]+)\s*dBFS", out)
    if not i:
        return None
    peak = float(p.group(1)) if p else 0.0
    return float(i.group(1)), peak


LINE_TARGET_LUFS = -16.0     # the boss lines' own render target, stated in their commit bodies


def gain_for(lufs, peak, target=TARGET_LUFS):
    """(gain, clamped_by_peak, capped_by_max) — three outcomes, not two.

    ⛔ The cap and the clamp are DIFFERENT facts and reporting only one of them hid the other: a
    clip capped at MAX_GAIN stays off target and nothing said so. "I could not fully do this" must
    not share a report with "done", which is the same distinction the refusals above make."""
    ideal = target - lufs
    want = max(-MAX_GAIN_DB, min(MAX_GAIN_DB, ideal))
    capped = abs(want - ideal) > 0.05
    room = PEAK_CEILING_DB - (peak + BASE_DB)
    if want > room:
        return round(room, 1), True, capped
    return round(want, 1), False, capped


def voice_keys(man):
    return sorted(k for k in man if k.startswith("voice_") and not k.startswith("voice_blip_"))


def line_keys(man):
    """Exactly what play_voiced_line can select: an entry with a `line` field."""
    return sorted(k for k in man if isinstance(man[k], dict) and "line" in man[k])


def classes(man):
    """(name, keys, target). Disjoint by construction, checked rather than assumed."""
    party, lines = voice_keys(man), line_keys(man)
    overlap = set(party) & set(lines)
    if overlap:
        raise SystemExit("REFUSING: %d entries are both a party voice and a recorded line, so their "
                         "target is ambiguous: %s" % (len(overlap), sorted(overlap)[:5]))
    return [("party", party, TARGET_LUFS), ("line", lines, LINE_TARGET_LUFS)]


def measure(man):
    rows, bad = [], []
    for name, keys, target in classes(man):
        for k in keys:
            row = _measure_one(man, k, target, bad)
            if row:
                row["class"] = name
                row["target"] = target
                rows.append(row)
    return rows, bad


def _measure_one(man, k, target, bad):
    f = str(man[k].get("file", ""))
    if not f or not os.path.exists(f):
        bad.append((k, "no file on disk: %r" % f))
        return None
    m = loudness(f)
    if m is None:
        bad.append((k, "would not measure"))
        return None
    lufs, peak = m
    g, clamped, capped = gain_for(lufs, peak, target)
    return {"key": k, "lufs": lufs, "peak": peak, "gain": g, "clamped": clamped, "capped": capped}


def cmd_report(apply_it):
    man_doc = json.load(io.open(MANIFEST, encoding="utf-8"))
    man = man_doc["sfx"]
    rows, bad = measure(man)
    if bad:
        print("REFUSING to apply — %d clip(s) could not be measured:" % len(bad))
        for k, why in bad[:10]:
            print("   %-34s %s" % (k, why))
        return 3
    if not rows:
        print("REFUSING — measured 0 voice clips, so there is nothing to level and a write would be empty")
        return 3
    clamped = [r for r in rows if r["clamped"]]
    moved = [r for r in rows if abs(r["gain"]) >= 0.1]
    for name, _, target in classes(man):
        print("  %-6s %4d clips   target %.1f LUFS" % (name, sum(1 for r in rows if r["class"] == name), target))
    print("voice clips measured: %d" % len(rows))
    print("  gains |g| >= 0.1 dB : %d" % len(moved))
    capped = [r for r in rows if r["capped"]]
    print("  clamped by peak     : %d" % len(clamped))
    print("  CAPPED at %+.0f dB (still off target): %d%s" % (
        MAX_GAIN_DB, len(capped),
        "" if not capped else "  -> " + ", ".join("%s %+.1f short" % (
            r["key"], (r["target"] - r["lufs"]) - r["gain"]) for r in capped[:4])))
    for r in sorted(rows, key=lambda r: r["gain"])[:4]:
        print("     %-36s %6.1f LUFS  peak %5.1f  gain %+5.1f" % (r["key"], r["lufs"], r["peak"], r["gain"]))
    for r in sorted(rows, key=lambda r: -r["gain"])[:4]:
        print("     %-36s %6.1f LUFS  peak %5.1f  gain %+5.1f" % (r["key"], r["lufs"], r["peak"], r["gain"]))
    for r in clamped[:6]:
        print("  CLAMPED %-32s wanted %+.1f, peak %.1f allows %+.1f"
              % (r["key"], r["target"] - r["lufs"], r["peak"], r["gain"]))
    if not apply_it:
        return 0
    n = 0
    for r in rows:
        if abs(r["gain"]) >= 0.1:
            man[r["key"]]["gain_db"] = r["gain"]
            n += 1
        else:
            man[r["key"]].pop("gain_db", None)
    io.open(MANIFEST, "w", encoding="utf-8").write(
        json.dumps(man_doc, indent=2, ensure_ascii=False) + "\n")
    print("wrote gain_db to %d entries (and cleared it from %d already at target)" % (n, len(rows) - n))
    return 0


def selftest():
    p = f = 0

    def chk(name, cond):
        nonlocal p, f
        if cond:
            p += 1
            print("  ok    %s" % name)
        else:
            f += 1
            print("  FAIL  %s" % name)

    ## The arithmetic, which is the whole tool.
    g, c, _ = gain_for(-22.0, -1.2)
    chk("a quiet clip is RAISED toward target", g > 0)
    ## My first expectation here was WRONG and the arm caught it: peak -1.2 with a -4.0 base leaves
    ## 4.2 dB of room, so the 4.0 dB this clip wants FITS and must not be clamped. A case that does
    ## clamp needs a peak hotter than that — which is the point of measuring rather than assuming.
    chk("...and NOT clamped when its own peak leaves room", not c and abs(g - 4.0) < 0.05)
    g, c, _ = gain_for(-22.0, -0.2)
    chk("a quiet clip with a HOT peak is clamped instead of clipping",
        c and abs(g - (PEAK_CEILING_DB - (-0.2 + BASE_DB))) < 0.05)
    chk("...and the clamped gain leaves the peak at the ceiling, not above", -0.2 + BASE_DB + g <= PEAK_CEILING_DB + 0.01)
    g, c, _ = gain_for(-22.0, -12.0)
    chk("the same clip with headroom gets the full gain", abs(g - 4.0) < 0.05 and not c)
    g, c, _ = gain_for(-13.0, -0.5)
    chk("a LOUD clip is cut, never clamped (a cut needs no headroom)", g < 0 and not c)
    g, _, _ = gain_for(-18.0, -6.0)
    chk("a clip already at target gets ~0", abs(g) < 0.05)
    g, _, _ = gain_for(-40.0, -30.0)
    chk("an absurdly quiet clip is capped at MAX_GAIN, not raised 22 dB", abs(g - MAX_GAIN_DB) < 0.05)

    ## The line class: its own target, and the same headroom rule.
    g, c, _ = gain_for(-19.4, -0.7, LINE_TARGET_LUFS)
    chk("a quiet boss line is raised to the LINE target, not the party one", abs(g - 3.4) < 0.05 and not c)
    g, _, _ = gain_for(-16.0, -1.0, LINE_TARGET_LUFS)
    chk("CONTROL: a boss line already at -16 gets ~0 (under the party target it would be cut 2 dB)", abs(g) < 0.05)
    fake = {"voice_a_1": {"file": "x"}, "boss_line_b_1": {"file": "y", "line": "Hi.", "speaker": "B"},
            "voice_blip_c": {"file": "z"}, "ui_d": {"file": "w"}}
    cl = {n: (k, t) for n, k, t in classes(fake)}
    chk("the line class is exactly the entries play_voiced_line can select (has `line`)",
        cl["line"] == (["boss_line_b_1"], LINE_TARGET_LUFS))
    chk("CONTROL: the party class keeps blips and non-voice cues out", cl["party"] == (["voice_a_1"], TARGET_LUFS))
    try:
        classes({"voice_x": {"file": "x", "line": "Hi."}})
        chk("an entry in BOTH classes is refused rather than given one target silently", False)
    except SystemExit:
        chk("an entry in BOTH classes is refused rather than given one target silently", True)

    ## The refusals. A clip that will not measure must not receive a gain computed from a default.
    chk("loudness() returns None rather than a number for a non-file",
        loudness("tools/voice_level_trim.py") is None)

    ## And the real path, only if the tree has clips — the selftest must not depend on assets.
    sample = sorted(glob.glob("assets/audio/sfx/voice_*.ogg"))
    sample = [s for s in sample if "/voice_blip_" not in s]
    if sample:
        m = loudness(sample[0])
        chk("a real voice clip measures as speech-shaped loudness", m is not None and -40 < m[0] < -5)
    else:
        print("  skip  no voice clips in this tree")

    print("selftest: %d passed, %d failed" % (p, f))
    return 1 if f else 0


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    if argv[1] == "--selftest":
        return selftest()
    if argv[1] == "--report":
        return cmd_report(False)
    if argv[1] == "--apply":
        return cmd_report(True)
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
