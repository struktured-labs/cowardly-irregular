#!/usr/bin/env python3
"""Which music master plays where in a demo capture, and whether a bed that comes back RESUMED (cowir-music).

    python3 tools/demo_music_id.py <take.(mp4|avi|wav)> [manifest_key ...]
    python3 tools/demo_music_id.py --selftest

Decodes the take's audio and each candidate master to mono 4 kHz (ffmpeg), finds for every 4 s window the master and
offset with the highest normalised cross-correlation, merges windows whose offsets advance with time into runs, and
judges every RETURN of a non-stinger bed against where THAT bed last stopped, even across another bed (danger):
    OK: RESUME    back within -4..+8 s of where it left off (one window back at most: its last window may straddle the cut)
    OK: WRAP      it had reached its last 8 s and comes back within its first 8 s (a loop, expected)
    FLAG: RESTART anything else, e.g. back to its top from mid-track (the 6fabbfc7f defect)
With no keys, the candidates are every W1-reachable manifest track (aliases skipped).

KNOWN ARTIFACT: a stinger whose start straddles a 4 s window reads "?" or "ends early". Confirm a stinger at 1 s
resolution before calling it truncated (stinger_boss_defeated -> victory bed start must be +9.2 s).

--selftest touches nothing: no file opened, no directory walked, no subprocess, nothing written. It builds synthetic
masters in numpy and checks RESUME, RESTART, WRAP and a lone first play (no verdict) through the same functions.
"""
import json
import subprocess
import sys

import numpy as np

SR = 4000
WIN = 4.0
MATCH_FLOOR = 0.35
SOLID_SCORE = 0.6  # a one-window run is judged only when it is a strong match
MANIFEST = "data/music_manifest.json"
W1_MARKERS = ("medieval", "rat", "mordaine", "harmonia", "slime", "goblin", "bat", "title", "victory", "danger",
              "stinger_", "cave", "castle", "whisper", "imp", "skeleton", "wolf", "mushroom", "brute")
OTHER_WORLDS = ("suburban", "steampunk", "industrial", "digital", "abstract", "futuristic")


def decode(path):
    cmd = ["ffmpeg", "-nostdin", "-v", "error", "-i", path, "-vn", "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"]
    raw = subprocess.run(cmd, capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def best_offset(win, master):
    """Peak normalised cross-correlation of win inside master: (score, offset_seconds)."""
    n = len(win)
    if len(master) < n or not np.any(win):
        return 0.0, 0.0
    w = win - win.mean()
    wn = np.sqrt(np.sum(w * w)) or 1.0
    size = 1 << int(np.ceil(np.log2(len(master) + n)))
    corr = np.fft.irfft(np.fft.rfft(master, size) * np.conj(np.fft.rfft(w, size)), size)[: len(master) - n + 1]
    c2 = np.concatenate([[0.0], np.cumsum(master * master)])
    c1 = np.concatenate([[0.0], np.cumsum(master)])
    energy = (c2[n:] - c2[:-n]) - (c1[n:] - c1[:-n]) ** 2 / n
    score = corr / (wn * np.sqrt(np.maximum(energy, 1e-12)))
    i = int(np.argmax(score))
    return float(score[i]), i / SR


def windows(audio, masters):
    """One row per 4 s window: (t, key or '?' or None for silence, score, offset). masters: key -> (signal, dur, stinger)."""
    n = int(WIN * SR)
    rows = []
    for w0 in range(0, len(audio) - n + 1, n):
        win = audio[w0:w0 + n]
        if np.sqrt(np.mean(win * win)) < 1e-4:
            rows.append((w0 / SR, None, 0.0, 0.0))
            continue
        best = (0.0, None, 0.0)
        for k, (m, _, _) in masters.items():
            sc, off = best_offset(win, m)
            if sc > best[0]:
                best = (sc, k, off)
        rows.append((w0 / SR, best[1] if best[0] >= MATCH_FLOOR else "?", best[0], best[2]))
    return rows


def runs_of(rows):
    """Merge contiguous windows of one master whose offsets advance with time."""
    runs = []
    for t, k, s, off in rows:
        r = runs[-1] if runs else None
        if r and k == r["k"] and k not in (None, "?") and abs((off - r["off0"]) - (t - r["t0"])) < 1.0:
            r["t1"], r["off1"] = t, off
            r["scores"].append(s)
        else:
            runs.append({"k": k, "t0": t, "t1": t, "off0": off, "off1": off, "scores": [s]})
    return runs


def judge(runs, masters):
    """(verdicts, flags): lists of (kind, key, t0, detail). kind in RESUME/WRAP (verdicts), RESTART/STINGER (flags)."""
    last_end, verdicts, flags = {}, [], []
    for r in runs:
        k = r["k"]
        if k not in masters:
            continue
        dur, stinger = masters[k][1], masters[k][2]
        end_here = r["off1"] + WIN
        if stinger and end_here < dur - 0.5:
            flags.append(("STINGER", k, r["t0"], "ends at %.1f s of %.1f s (check at 1 s: a straddled window reads short)" % (end_here, dur)))
        solid = r["t1"] > r["t0"] or float(np.mean(r["scores"])) >= SOLID_SCORE
        if not solid:
            continue
        if not stinger and k in last_end:
            end, back = last_end[k], r["off0"]
            if end - WIN <= back <= end + 2 * WIN:
                verdicts.append(("RESUME", k, r["t0"], "offset %.1f, left off at %.1f" % (back, end)))
            elif end >= dur - 2 * WIN and back <= 2 * WIN:
                verdicts.append(("WRAP", k, r["t0"], "had reached %.1f of %.1f" % (end, dur)))
            else:
                flags.append(("RESTART", k, r["t0"], "offset %.1f, but it left off at %.1f" % (back, end)))
        last_end[k] = end_here
    return verdicts, flags


def w1_keys(tracks):
    return [k for k, v in tracks.items() if not v.get("alias_of") and any(m in k for m in W1_MARKERS)
            and not any(w in k for w in OTHER_WORLDS)]


def selftest():
    """Synthetic masters: seeded noise is unique at every offset, so a window matches exactly one place."""
    rng = np.random.default_rng(784)
    a = rng.standard_normal(int(40 * SR))  # a 40 s bed
    b = rng.standard_normal(int(12 * SR))  # a 12 s danger bed
    masters = {"bed": (a, 40.0, False), "danger": (b, 12.0, False)}
    s = lambda sig, t0, t1: sig[int(t0 * SR):int(t1 * SR)]
    cases = {
        "resume": (np.concatenate([s(a, 0, 20), s(b, 0, 12), s(a, 20, 40)]), ["RESUME"], []),
        "restart": (np.concatenate([s(a, 0, 20), s(b, 0, 12), s(a, 0, 20)]), [], ["RESTART"]),
        "wrap": (np.concatenate([s(a, 20, 40), s(a, 0, 12)]), ["WRAP"], []),
        "first play only": (np.concatenate([s(a, 0, 20), s(b, 0, 12)]), [], []),
    }
    bad = []
    for name, (seg, want_v, want_f) in cases.items():
        rows = windows(seg, masters)
        if any(k in (None, "?") for _, k, _, _ in rows):
            bad.append("%s: a window matched nothing, so the instrument cannot see its own masters" % name)
            continue
        v, f = judge(runs_of(rows), masters)
        got_v = [x[0] for x in v if x[1] == "bed"]
        got_f = [x[0] for x in f]
        if got_v != want_v or got_f != want_f:
            bad.append("%s: verdicts %s flags %s, wanted %s %s" % (name, got_v, got_f, want_v, want_f))
    for b_ in bad:
        print("SELFTEST FAIL:", b_)
    print("demo_music_id selftest: %d of %d cases %s" % (len(cases) - len(bad), len(cases), "ok" if not bad else "FAILED"))
    return 0 if not bad else 1


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    if sys.argv[1] == "--selftest":
        sys.exit(selftest())
    seg = sys.argv[1]
    tracks = json.load(open(MANIFEST))["tracks"]
    masters = {}
    for k in sys.argv[2:] or w1_keys(tracks):
        f = tracks.get(k, {}).get("file")
        if f:
            masters[k] = (decode(f), float(tracks[k].get("duration", 0)), bool(tracks[k].get("stinger")))
    audio = decode(seg)
    rows = windows(audio, masters)
    runs = runs_of(rows)
    print("segment %s  (%.1f s, %d windows of %.0f s, match floor %.2f)" % (seg, len(audio) / SR, len(rows), WIN, MATCH_FLOOR))
    for r in runs:
        ms = float(np.mean(r["scores"])) if r["scores"] else 0.0
        print("  %6.1f-%6.1f s  %-24s offset %6.1f-%6.1f s  score %.2f" % (r["t0"], r["t1"] + WIN, r["k"], r["off0"], r["off1"] + WIN, ms))
    verdicts, flags = judge(runs, masters)
    for kind, k, t0, detail in verdicts:
        print("  OK: %s %s at %.1f s: %s" % (kind, k, t0, detail))
    for kind, k, t0, detail in flags:
        print("  FLAG: %s %s at %.1f s: %s" % (kind, k, t0, detail))
    if not flags:
        print("  no restart or truncated-stinger flags")


if __name__ == "__main__":
    main()
