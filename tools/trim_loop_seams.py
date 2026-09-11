#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy"]
# ///
"""Trim the fade-out off looping music beds so they wrap at full level.

WHY
    A Suno track is a SONG, and songs fade out. A game loop must not: when the
    stream wraps, the player hears the music die away and snap back to full.

WHAT CHANGED 2026-09-10, AND WHY THE OLD VERSION SAID "ALREADY OK" TO A DEFECT
    This tool used to import classify() from audit_loop_seams, which asks "is
    the last 1.5s far below the track's BODY mean?". That question is wrong in
    two independent ways, both already documented in audit_wrap_seams.py's
    docstring -- and the correction was never carried back here, so the fix
    shipped in the auditor while the tool that acts on it kept the broken test:

      A 1.5s WINDOW AVERAGES AWAY A SHORTER FADE. boss_warden_abstract fades
      over its last ~1.0s. Its tail-1.5s sits about 2 dB under body, so it
      classified ALREADY OK and was REFUSED BY NAME -- while its actual wrap
      stepped +15.0 dB. The refusal message was confident and wrong.

      TAIL-vs-BODY MIS-READS SPARSE MATERIAL, calling a deliberately quiet
      ending a fade when the head is equally quiet and nothing jumps.

    Selection and verification now both use the WRAP: db(first 0.3s) minus
    db(last 0.3s). It compares the two moments the player actually hears back
    to back and needs no reference to the body at all.

    Corollary worth stating because it is what made the bug invisible: a
    superseded instrument does not stop running when a better one is written.
    It stops being READ. This tool kept calling the old one by import.

SAMPLE RATE IS PRESERVED, NOT NORMALISED
    ENCODE used to hardcode 48k. The corpus is not uniformly 48k -- 2 of the
    19 beds measured today are 44.1k -- so every 44.1k track this tool touched
    was silently resampled as a side effect of a trim. Output now matches the
    source rate and channel count.

THE DECLICK IS NOT OPTIONAL
    Cutting at full level leaves a discontinuity, and a loop point is exactly
    where a discontinuity is audible -- every wrap, forever. An 8 ms fade is
    below the threshold of hearing as a fade and removes the edge.

VERIFICATION IS PER-TRACK, BEFORE THE REPLACE
    Each output is re-decoded and measured; the original is only replaced if the
    encoded file's wrap actually holds. A failure leaves the source untouched.

USAGE
    uv run tools/trim_loop_seams.py                 # dry run, all TRIM-SAFE
    uv run tools/trim_loop_seams.py --only <track>  # one track
    uv run tools/trim_loop_seams.py --apply         # write in place
"""
import argparse
import collections
import io
import json
import os
import subprocess
import sys

import numpy as np

MANIFEST = "data/music_manifest.json"
SEAM_S = 0.3
## Above this the wrap is audible as a step. Matches audit_wrap_seams.JUMP_DB.
WRAP_JUMP_DB = 12.0
## A wrap this flat is indistinguishable from continuous playback.
WRAP_OK_DB = 6.0
## The ritardando bound: past this we are eating music, not a fade.
MAX_TRIM_S = 30.0
## A fade invisible at 300ms is short by construction; its repair must be too.
SHORT_FADE_MAX_TRIM_S = 2.0
DECLICK_S = 0.008
CUT_STEP_S = 0.05


def probe(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a:0",
                          "-show_entries", "stream=sample_rate,channels",
                          "-of", "csv=p=0", path], capture_output=True, text=True).stdout.strip()
    sr, ch = out.split(",")
    return int(sr), int(ch)


def decode(path, sr, ch):
    raw = subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-i", path,
                          "-f", "f32le", "-ac", str(ch), "-ar", str(sr), "-"],
                         capture_output=True).stdout
    y = np.frombuffer(raw, dtype="<f4").astype(np.float64)
    return y.reshape(-1, ch) if ch > 1 else y.reshape(-1, 1)


def db(x):
    if x.size == 0:
        return float("-inf")
    r = float(np.sqrt(np.mean(np.square(x))))
    return 20.0 * np.log10(r) if r > 0 else float("-inf")


## ⚠️ ONE WINDOW IS ONLY RIGHT FOR ONE DURATION OF FADE. This selected on a
## single 0.3s window and called ten beds clean that jump 12-52 dB at shorter
## ones — the same averaging failure the 1.5s window had, one level down.
## @cowir-sfx's window sweep, 2026-09-11. No single window catches all ten:
## 10ms finds 3, 50ms finds 6, 100ms finds 1.
SEAM_WINDOWS_S = [0.050, 0.100, 0.300]


## Windows stable enough to ACCEPT a fix on. 10ms is excellent at FINDING a
## short fade and too phase-sensitive to gate one: verifying against it pushed
## battle_abstract from a 0.15s cut to 5.15s, chasing agreement that noise kept
## breaking. Detect wide, accept narrow.
ACCEPT_WINDOWS_S = [0.050, 0.100, 0.300]


def wrap_step_accept(y, sr):
    """Worst POSITIVE step across the stable windows — what a fix must satisfy.

    ⛔ THIS WAS abs() AND THAT PENALISED A NORMAL MUSICAL ATTACK. A note that
    ramps in makes the head's 50ms RMS quieter than its 300ms RMS, so a
    PERFECTLY looping track reads negative at the short window. Demanding every
    window land within +/-6 dB therefore refused tracks whose only sin was a
    soft attack: battle_brute reaches +0.4 dB at 300ms after a 300ms cut while
    the 50ms reads -17.0, and the abs() form called that a failure and gave up.

    The defect being removed is a FADE-OUT — the tail quieter than the head,
    i.e. a POSITIVE step. A negative one is a soft intro, which a tail cut
    cannot fix and which classify() already refuses by name up front.
    """
    worst = None
    for ws in ACCEPT_WINDOWS_S:
        n = int(ws * sr)
        if len(y) < 3 * n:
            continue
        step = db(y[:n]) - db(y[-n:])
        if worst is None or step > worst:
            worst = step
    return worst if worst is not None else 0.0


def wrap_step(y, sr):
    """Worst step across every window — a fade hides from any window longer than itself."""
    worst = None
    for ws in SEAM_WINDOWS_S:
        n = int(ws * sr)
        if len(y) < 3 * n:
            continue
        step = db(y[:n]) - db(y[-n:])
        if worst is None or step > worst:
            worst = step
    return worst if worst is not None else 0.0


def classify(y, sr):
    """(verdict, step now, seconds to cut, step after).

    Two rules, both learned by watching the first version misbehave:

    ACT ONLY ON A REAL JUMP, not on everything above the OK bar. Selecting at
    WRAP_OK_DB pulled in 23 tracks whose wrap was merely imperfect and cost
    village_brasston 8.55s of a 20.0s track -- 43% of the piece -- to move a
    number nobody could hear from +9.2 to +0.0.

    TAKE THE SMALLEST CUT THAT WORKS, not the flattest one. Minimising |step|
    across a 30s search happily ate 29.15s of cutscene_w6_no_one_speaks to gain
    a fraction of a dB. That is optimising the instrument instead of repairing
    the defect, and the instrument is a proxy.

    A NEGATIVE step is a different defect and this tool cannot fix it. It means
    the head is far quieter than the tail -- a soft intro, not a fade-out -- and
    the only way a TAIL cut reaches it is by chewing back into quiet material,
    which is exactly where those 29s came from. Named and refused.
    """
    step_now = wrap_step(y, sr)

    ## ⛔ THE CUT MUST BE BOUNDED BY THE DEFECT'S OWN SHAPE. A 10ms RMS window is
    ## phase-sensitive, so a search that must satisfy ALL windows at once will
    ## walk until they coincide — it proposed cutting 22.85s off
    ## boss_tempo_digital, whose last 40 SECONDS sit at full level (+0.6 to +2.8
    ## dB vs body). No outro; the search was chasing noise. A fade only visible
    ## below 300ms is by definition SHORT, so its repair is short: cap the
    ## search at SHORT_FADE_MAX_TRIM_S. A genuine ritardando still shows at
    ## 300ms and keeps the full MAX_TRIM_S budget.
    w300 = int(0.300 * sr)
    long_fade = (db(y[:w300]) - db(y[-w300:])) > WRAP_JUMP_DB
    budget = MAX_TRIM_S if long_fade else SHORT_FADE_MAX_TRIM_S

    if step_now < -WRAP_JUMP_DB:
        return "SOFT INTRO (head far quieter than tail; a tail cut cannot fix it)", step_now, 0.0, step_now
    if step_now <= WRAP_JUMP_DB:
        return "ALREADY OK", step_now, 0.0, step_now
    w = int(SEAM_S * sr)
    head = db(y[:w])
    n = int(CUT_STEP_S * sr)
    for i in range(1, int(budget / CUT_STEP_S) + 1):
        t = y[:len(y) - i * n]
        if len(t) < 3 * sr:
            break
        s = wrap_step_accept(t, sr)
        if s <= WRAP_OK_DB:
            return "TRIM-SAFE", step_now, i * CUT_STEP_S, s
    return "NO CUT HELPS", step_now, 0.0, step_now


def trim_one(src, keep_s, sr, ch, tmp):
    fade_st = max(0.0, keep_s - DECLICK_S)
    cmd = ["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", src,
           "-t", "%.3f" % keep_s,
           "-af", "afade=t=out:st=%.3f:d=%.3f" % (fade_st, DECLICK_S),
           "-ac", str(ch), "-ar", str(sr), "-c:a", "libvorbis", "-b:a", "96k", tmp]
    return subprocess.run(cmd, capture_output=True).returncode == 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--only")
    ap.add_argument("--limit", type=int)
    args = ap.parse_args()

    if not os.path.exists(MANIFEST):
        sys.exit("run from the repo root: %s not found" % MANIFEST)
    doc = json.load(open(MANIFEST, encoding="utf-8"),
                    object_pairs_hook=collections.OrderedDict)
    tracks = doc["tracks"]

    rows = []
    for key, meta in sorted(tracks.items()):
        if not meta.get("loop") or meta.get("stinger"):
            continue
        path = meta.get("file")
        if not path or not os.path.exists(path):
            continue
        if args.only and key != args.only:
            continue
        sr, ch = probe(path)
        y = decode(path, sr, ch)
        if len(y) < 3 * sr:
            continue
        verdict, step_now, cut_s, step_after = classify(y, sr)
        if verdict != "TRIM-SAFE":
            ## Refused by name rather than silently skipped: asking for a track
            ## and getting nothing back is indistinguishable from a no-op.
            if args.only:
                print("REFUSED: %s is %s (wrap %+.1f dB). This tool only removes fades "
                      "laid over playing music." % (key, verdict, step_now))
                return 2
            continue
        w300 = int(0.300 * sr)
        cut_budget = MAX_TRIM_S if (db(y[:w300]) - db(y[-w300:])) > WRAP_JUMP_DB else SHORT_FADE_MAX_TRIM_S
        rows.append((key, path, sr, ch, len(y) / sr, cut_s, step_now, step_after, cut_budget))
    if args.limit:
        rows = rows[:args.limit]

    print("%-32s %8s %8s  %s" % ("track", "dur", "cut", "wrap before -> after"))
    ok = failed = 0
    updated = []
    for key, path, sr, ch, dur, cut_s, step_now, step_after, cut_budget in rows:
        if not args.apply:
            print("%-32s %7.1fs %7.2fs  %+.1f -> %+.1f dB  (dry run)"
                  % (key, dur, cut_s, step_now, step_after))
            continue
        tmp = path + ".trim.tmp.ogg"
        ## The cut point is chosen on the DECODED array; the check below measures
        ## the ENCODED file, which is the step that can reframe or repad. Those
        ## are different artifacts, so a candidate can clear selection and miss
        ## verification by a fraction of a dB. Step deeper rather than giving up
        ## -- but never past MAX_TRIM_S, the ritardando bound that must not move.
        why = None
        accepted = None
        keep = dur - cut_s
        ## The retry must honour the SAME budget as the search, or a track
        ## selected at 0.15s gets trimmed to 5.15s by the deeper-cut loop.
        while keep > 1.0 and (dur - keep) <= cut_budget:
            if not trim_one(path, keep, sr, ch, tmp):
                why = "ffmpeg failed"
                break
            vy = decode(tmp, sr, ch)
            if len(vy) == 0:
                why = "unreadable output"
                break
            new_dur = len(vy) / sr
            if abs(new_dur - keep) > 0.5:
                why = "duration %.2fs != cut point %.2fs" % (new_dur, keep)
                break
            s = wrap_step_accept(vy, sr)
            if s <= WRAP_OK_DB:
                accepted = (keep, new_dur, s)
                why = None
                break
            why = "encoded wrap still %+.1f dB after %.2fs of cut" % (s, dur - keep)
            keep -= 0.5
        if accepted is None:
            if os.path.exists(tmp):
                os.remove(tmp)
            print("%-32s %7.1fs %7.2fs  REJECTED (%s) - source untouched"
                  % (key, dur, cut_s, why or "no cut within MAX_TRIM_S passed"))
            failed += 1
            continue
        keep, new_dur, s = accepted
        os.replace(tmp, path)
        ## The manifest duration describes a file we just shortened. Left stale it
        ## is a quiet lie: 107 entries drifted after the 2026-08-26 trim and had to
        ## be repaired by hand downstream. new_dur is measured, not predicted.
        tracks[key]["duration"] = round(new_dur, 1)
        updated.append(key)
        print("%-32s %7.1fs %7.2fs  %+.1f -> %+.1f dB  trimmed"
              % (key, dur, dur - keep, step_now, s))
        ok += 1

    if args.apply:
        if updated:
            with io.open(MANIFEST, "w", encoding="utf-8") as fh:
                fh.write(json.dumps(doc, indent=2, ensure_ascii=False) + "\n")
            print("\n  manifest durations rewritten for %d track(s)" % len(updated))
            print("  OGGs rewritten: run --import before any test that load()s them.")
        print("\n  trimmed %d, rejected %d, of %d TRIM-SAFE candidates" % (ok, failed, len(rows)))
    else:
        print("\n  %d TRIM-SAFE candidate(s). Nothing written; pass --apply." % len(rows))
    ## A batch --apply that REJECTED tracks printed the count and returned 0, so
    ## "3 rejected" and "all clean" were the same exit status. The --only path
    ## already returned 2; the batch path did not.
    if args.apply and failed:
        print("  EXIT 1: %d track(s) rejected or failed during --apply" % failed)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
