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

A stinger is judged at 1 s resolution, start to the next bed's start (STINGER WHOLE / STINGER CUT): its 4 s windows
straddle its start and read short, which is why every take before this needed a hand probe.

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


def stinger_gaps(audio, masters, runs):
    """Every stinger PLAY, found by a whole-take 1 s scan (a stinger cut under 4 s never fills a 4 s window, so the
    runs cannot be trusted to contain it), with the next non-stinger bed after it: (stinger, start, bed, bed start,
    gap, stinger dur). Whole when gap >= dur - 0.5. A bed from its top is placed exactly (t - offset); a bed that
    RESUMES mid-track is placed at its first matching 1 s window, so its gap reads up to 1 s long."""
    n = int(SR)
    sec = [(float(t), audio[t * n:(t + 1) * n]) for t in range(int(len(audio) / SR))]
    beds = {k: m for k, m in masters.items() if not m[2]}
    out = []
    for k, (m, dur, stinger) in masters.items():
        if not stinger:
            continue
        plays = []  # clusters of 1 s windows agreeing on where the stinger's t=0 is
        for t, w in sec:
            sc, off = best_offset(w, m)
            if sc < SOLID_SCORE:
                continue
            s0 = t - off
            if plays and abs(s0 - plays[-1][-1]) < 0.5:
                plays[-1].append(s0)
            else:
                plays.append([s0])
        for p in plays:
            s0 = float(np.median(p))
            b0, bed = None, None
            for t, w in sec:
                if t < s0 + 0.5:
                    continue
                best = (0.0, None, 0.0)
                for bk, (bm, _, _) in beds.items():
                    sc, off = best_offset(w, bm)
                    if sc > best[0]:
                        best = (sc, bk, off)
                if best[0] >= SOLID_SCORE:
                    bed = best[1]
                    b0 = t - best[2] if best[2] < 2 * WIN else t
                    break
            out.append((k, s0, bed, b0, (b0 - s0) if b0 is not None else None, dur))
    out.sort(key=lambda g: g[1])
    return out


def stinger_whole(gap, dur):
    """The one rule both the report and the selftest use: whole when the next bed starts no earlier than dur - 0.5."""
    return gap is not None and gap >= dur - 0.5


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
    ## A stinger whose start STRADDLES a 4 s window (it starts at 10 s): the 1 s onsets must still read its full length.
    st = rng.standard_normal(int(6 * SR))
    vic = rng.standard_normal(int(16 * SR))
    sm = {"bed": (a, 40.0, False), "sting": (st, 6.0, True), "victory": (vic, 16.0, False)}
    for name, cut, whole in (("stinger whole", 6, True), ("stinger cut at 3 s", 3, False)):
        seg = np.concatenate([s(a, 0, 10), s(st, 0, cut), s(vic, 0, 16)])
        g = stinger_gaps(seg, sm, runs_of(windows(seg, sm)))
        if len(g) != 1 or g[0][4] is None:
            bad.append("%s: found %d stinger gap(s) %s, wanted 1 resolved" % (name, len(g), g))
            continue
        if abs(g[0][4] - cut) > 0.5 or stinger_whole(g[0][4], g[0][5]) != whole:
            bad.append("%s: gap %.2f s, wanted %d s (%s)" % (name, g[0][4], cut, "whole" if whole else "cut"))
    for b_ in bad:
        print("SELFTEST FAIL:", b_)
    print("demo_music_id selftest: %d of %d cases %s" % (len(cases) + 2 - len(bad), len(cases) + 2, "ok" if not bad else "FAILED"))
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
    flags = [f for f in flags if f[0] != "STINGER"]  # the 4 s reading straddles; judged at 1 s below instead
    for k, s0, bed, b0, gap, dur in stinger_gaps(audio, masters, runs):
        if gap is None:
            flags.append(("STINGER", k, s0, "no bed follows it at 1 s (the take may end inside it)"))
        elif stinger_whole(gap, dur):
            verdicts.append(("STINGER WHOLE", k, s0, "%s starts %.2f s after it, of %.1f" % (bed, gap, dur)))
        else:
            flags.append(("STINGER CUT", k, s0, "%s starts %.2f s after it, of %.1f" % (bed, gap, dur)))
    for kind, k, t0, detail in verdicts:
        print("  OK: %s %s at %.1f s: %s" % (kind, k, t0, detail))
    for kind, k, t0, detail in flags:
        print("  FLAG: %s %s at %.1f s: %s" % (kind, k, t0, detail))
    if not flags:
        print("  no restart or truncated-stinger flags")


if __name__ == "__main__":
    main()
