#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy"]
# ///
"""Turn a track that ENDS into a track that LOOPS, by crossfading the wrap.

WHY THIS EXISTS
    tools/trim_loop_seams.py fixes a fade laid OVER playing music: cut it off and
    full-level material is already there. It correctly REFUSES the other kind —
    a ritardando, where the piece genuinely winds down and there is nothing at
    full level underneath. Nine beds are in that class, and they include
    overworld_medieval and dungeon_medieval, the two tracks a World 1 player
    hears more than any other music in the game. Measured 2026-09-09:
    overworld_medieval body -14.2 dB, final second -45.4 dB. It dies to silence
    and snaps back to full every 198 seconds, forever.

    "Regenerate them" was the previous answer here and it was too quick. A
    crossfade loop is the standard way a song becomes a game loop, and it fits
    a ritardando exactly BECAUSE it discards the decay rather than trying to
    trim it.

WHAT IT DOES
    1. Find where the piece stops being at full level (the ritardando onset) and
       throw the decay away. Unlike the trim tool there is no MAX_TRIM_S bound
       here — a long cut is the POINT, not a red flag, because we are not
       claiming to preserve an ending. We are deleting one on purpose.
    2. Equal-power crossfade the body's own tail over its own head. The output's
       first X seconds are (head fading in) + (tail fading out), so when the
       stream wraps, the material the player is already hearing continues
       underneath the restart instead of stopping.

    Output length is body - X. Nothing is invented; every sample is the track's.

WHY EQUAL-POWER, NOT LINEAR
    Head and tail are uncorrelated musical material. A linear (amplitude)
    crossfade of uncorrelated signals dips ~3 dB in the middle — an audible hole
    exactly at the loop point, which is the thing we came to fix. sin/cos keeps
    SUM OF SQUARES constant instead, so perceived loudness holds across the
    blend. The cost is that peaks can add, so the result is checked for clipping
    and the run is REFUSED rather than silently limited.

VERIFICATION IS ON THE SEAM, NOT THE FILE
    "Louder tail" is not the claim. The claim is that the wrap is INAUDIBLE, so
    the check compares the last second to the first second of the OUTPUT — the
    two the player actually hears back to back — and requires both to sit near
    the body mean. --preview writes the wrap itself (tail + head spliced, twice)
    for before and after, which is the only way a human can judge this in
    seconds rather than by waiting out a 3-minute track.

USAGE
    python3 tools/crossfade_loop.py --only overworld_medieval            # dry run
    python3 tools/crossfade_loop.py --only overworld_medieval --preview  # + wrap audio
    python3 tools/crossfade_loop.py --only overworld_medieval --apply
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
SR = 48000
# Encoding of the existing corpus, measured rather than assumed: vorbis 48k mono 96k.
ENCODE = ["-ac", "1", "-ar", str(SR), "-c:a", "libvorbis", "-b:a", "96k"]
# Seconds of overlap. Long enough to hide a splice in a sustained bed, short
# enough that the head is not smothered by the tail on entry.
DEFAULT_XFADE_S = 4.0
# Within this of the body mean counts as "still playing".
FULL_LEVEL_TOLERANCE_DB = 4.0
# How far back to look for the ritardando onset.
MAX_SCAN_S = 60.0
# The seam is only fixed if BOTH sides of the wrap sit this close to the body.
SEAM_TOLERANCE_DB = 4.0
# ENTRY GATE. A tail this far under the track's own mean is a fade; anything
# shallower is a mix choice and must be left alone. Without this the tool
# happily rebuilt tracks that already loop fine — battle_skate_punk's tail is
# -2.8 dB and it was offered a 0.5s cut. trim_loop_seams has the equivalent
# gate (classify() must say TRIM-SAFE); this one shipped without it, so a bare
# --apply would have modified good audio across the corpus.
# Same value audit_loop_seams uses to call something a fade rather than a dip.
FADE_THRESHOLD_DB = -12.0


def decode(path):
    """Whole file as float32 mono at SR."""
    raw = subprocess.run(
        ["ffmpeg", "-nostdin", "-v", "error", "-i", path,
         "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"],
        capture_output=True).stdout
    return np.frombuffer(raw, dtype="<f4").astype(np.float64)


def encode(samples, out_path):
    proc = subprocess.run(
        ["ffmpeg", "-nostdin", "-v", "error", "-y",
         "-f", "f32le", "-ac", "1", "-ar", str(SR), "-i", "-"] + ENCODE + [out_path],
        input=samples.astype("<f4").tobytes(), capture_output=True)
    return proc.returncode == 0


def db(x):
    """RMS in dBFS. Silence returns -inf rather than raising."""
    if len(x) == 0:
        return float("-inf")
    r = float(np.sqrt(np.mean(np.square(x))))
    return 20.0 * np.log10(r) if r > 0 else float("-inf")


def find_body_end(y, body_db):
    """Last moment the piece is still at full level, walking back in 0.5s steps."""
    n = len(y)
    step = SR // 2
    limit = min(int(MAX_SCAN_S * SR), n - SR)
    back = step
    while back < limit:
        w = y[n - back - SR: n - back]
        if db(w) > body_db - FULL_LEVEL_TOLERANCE_DB:
            return n - back
        back += step
    return None


def body_end_candidates(y, body_db):
    """Every cut point worth trying, shallowest first.

    The FIRST point that reads 'full level' can still sit inside the decay:
    a tolerance wide enough to survive a track's own dynamics (4 dB) also
    admits a window already 3 dB down. dungeon_medieval failed exactly there —
    the blend inherited a quiet tail and the seam landed 22 dB under the body.
    Cutting deeper is free here, because unlike the trim tool this one is not
    preserving an ending, so offer successive cut points and let the SEAM
    decide. Same shape as trim_loop_seams' deeper-cut retry.
    """
    first = find_body_end(y, body_db)
    if first is None:
        return
    n = len(y)
    step = SR // 2
    end = first
    while end > SR * 10 and (n - end) < MAX_SCAN_S * SR:
        yield end
        end -= step


def crossfade_loop(body, xfade_n):
    """Equal-power fold of the body's tail over its own head."""
    n = len(body)
    t = np.linspace(0.0, 1.0, xfade_n, endpoint=False)
    fade_in = np.sin(t * np.pi / 2.0)
    fade_out = np.cos(t * np.pi / 2.0)
    blend = body[:xfade_n] * fade_in + body[n - xfade_n:] * fade_out
    return np.concatenate([blend, body[xfade_n: n - xfade_n]])


def wrap_step_ok(out):
    """Is the wrap a CLICK? Level continuity cannot answer this.

    Two segments can match in RMS and still jump in waveform, which is a tick
    every loop. Compare the single sample step the wrap creates against the
    distribution of every other step in the track — the music's own dynamics
    set the scale, so there is no threshold to tune.

    ⚠️ NOT sufficient alone, and the control proves it: the ORIGINAL fading
    files pass this too, because a fade ends near zero and a head starts near
    zero. It is the companion to the level check, never a replacement. Neither
    speaks to beat alignment or harmony across the wrap; that needs an ear, and
    is what --preview is for.
    """
    steps = np.abs(np.diff(out))
    wrap = abs(float(out[0] - out[-1]))
    return wrap <= float(np.percentile(steps, 99)), wrap


def wrap_sample(y, seconds=3.0):
    """What the player hears ACROSS the loop point: tail then head, twice."""
    k = int(seconds * SR)
    one = np.concatenate([y[-k:], y[:k]])
    return np.concatenate([one, one])


def process(key, path, xfade_s, apply_it, preview_dir):
    y = decode(path)
    if len(y) < SR * 10:
        return key, "unreadable or too short", None
    dur = len(y) / SR
    body_db = db(y[: max(SR, len(y) - int(30 * SR))])

    tail_db = db(y[-int(1.5 * SR):])
    if tail_db - body_db > FADE_THRESHOLD_DB:
        return key, "tail is only %.1f dB under body - not a fade, leave it alone" % (tail_db - body_db), None

    xfade_n = int(xfade_s * SR)
    attempts = 0
    chosen = None
    for end in body_end_candidates(y, body_db):
        body = y[:end]
        if len(body) < xfade_n * 3:
            break
        attempts += 1
        cand = crossfade_loop(body, xfade_n)
        pk = float(np.max(np.abs(cand)))
        g = 1.0
        if pk >= 1.0:
            g = 0.99 / pk
            if 20.0 * np.log10(g) < -3.0:
                continue
        scaled = cand * g
        level_ok = (db(scaled[-SR:]) > body_db - SEAM_TOLERANCE_DB
                    and db(scaled[:SR]) > body_db - SEAM_TOLERANCE_DB)
        click_ok, _ = wrap_step_ok(scaled)
        if level_ok and click_ok:
            chosen = (end, cand)
            break
    if chosen is None:
        if attempts == 0:
            return key, "never returns to full level within %.0fs" % MAX_SCAN_S, None
        return key, "no cut point in %d tries gave a seam within %.0f dB of body" % (
            attempts, SEAM_TOLERANCE_DB), None
    end, out = chosen
    body = y[:end]
    peak = float(np.max(np.abs(out)))
    # These beds are mastered near full scale, so summing head over tail
    # overshoots by design, not by accident. Shortening the crossfade barely
    # moves the peak (the overlap still sums two full-level signals), and
    # attenuating only the blend region digs a hole exactly at the loop point
    # this tool exists to fill. A UNIFORM trim is the honest fix: it is the
    # same everywhere, so the seam stays flat and no dynamics change. Sub-JND
    # in practice (~0.7 dB measured); a large one means something pathological,
    # so that is still a refusal.
    gain_db = 0.0
    if peak >= 1.0:
        gain = 0.99 / peak
        gain_db = 20.0 * np.log10(gain)
        if gain_db < -3.0:
            return key, "needs %.1f dB of trim to stop clipping - too hot to fold" % gain_db, None
        out = out * gain

    # The two seconds the player actually hears back to back.
    seam_out = db(out[-SR:])
    seam_in = db(out[:SR])
    _click_ok, wrap_step = wrap_step_ok(out)
    ok = (seam_out > body_db - SEAM_TOLERANCE_DB) and (seam_in > body_db - SEAM_TOLERANCE_DB)

    info = {
        "dur_before": dur,
        "dur_after": len(out) / SR,
        "cut": dur - end / SR,
        "body_db": body_db,
        "tail_before": db(y[-SR:]),
        "seam_out": seam_out,
        "seam_in": seam_in,
        "peak": peak,
        "gain_db": gain_db,
        "wrap_step": wrap_step,
        "ok": ok,
    }
    if not ok:
        return key, "seam still %.1f/%.1f dB vs body %.1f" % (seam_out, seam_in, body_db), info

    if preview_dir:
        os.makedirs(preview_dir, exist_ok=True)
        encode(wrap_sample(y), os.path.join(preview_dir, "%s_BEFORE_wrap.ogg" % key))
        encode(wrap_sample(out), os.path.join(preview_dir, "%s_AFTER_wrap.ogg" % key))

    if apply_it:
        tmp = path + ".xfade.tmp.ogg"
        if not encode(out, tmp):
            return key, "ffmpeg encode failed - source untouched", info
        os.replace(tmp, path)
    return key, None, info


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", action="append", default=[],
                    help="track key; repeatable. Default: every looping bed that needs it.")
    ap.add_argument("--xfade", type=float, default=DEFAULT_XFADE_S)
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--preview", metavar="DIR", nargs="?", const="tmp/loop_preview",
                    default=None, help="write before/after wrap audio for listening")
    args = ap.parse_args()

    if not os.path.exists(MANIFEST):
        sys.exit("run from the repo root: %s not found" % MANIFEST)
    doc = json.load(open(MANIFEST, encoding="utf-8"),
                    object_pairs_hook=collections.OrderedDict)
    tracks = doc["tracks"]

    keys = args.only or [k for k, v in tracks.items() if v.get("loop") and v.get("file")]
    missing = [k for k in keys if k not in tracks]
    if missing:
        sys.exit("not in the manifest: %s" % ", ".join(missing))

    print("%-30s %8s %8s %7s  %s" % ("track", "before", "after", "cut", "seam out/in vs body"))
    changed, refused = [], []
    for key in keys:
        path = tracks[key].get("file", "")
        if not path or not os.path.exists(path):
            continue
        k, why, info = process(key, path, args.xfade, args.apply, args.preview)
        if why:
            print("%-30s REFUSED: %s" % (key, why))
            refused.append(key)
            continue
        print("%-30s %7.1fs %7.1fs %6.1fs  %+.1f / %+.1f dB (was %+.1f)%s" % (
            key, info["dur_before"], info["dur_after"], info["cut"],
            info["seam_out"] - info["body_db"], info["seam_in"] - info["body_db"],
            info["tail_before"] - info["body_db"],
            "  [trim %.2f dB]" % info["gain_db"] if info["gain_db"] else ""))
        if args.apply:
            tracks[key]["duration"] = round(info["dur_after"], 1)
            changed.append(key)

    if args.apply and changed:
        with io.open(MANIFEST, "w", encoding="utf-8") as fh:
            fh.write(json.dumps(doc, indent=2, ensure_ascii=False) + "\n")
        print("\n  rewrote %d file(s) and their manifest durations" % len(changed))
    elif not args.apply:
        print("\n  dry run - nothing written. Pass --apply.")
    if refused:
        print("  refused %d: %s" % (len(refused), ", ".join(refused)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
