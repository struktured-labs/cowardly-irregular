#!/usr/bin/env python3
"""Where each voice line plays in a demo capture, and how many times a theme STARTS (cowir-sfx).

    python3 tools/demo_sfx_qc.py find   <take> <clip.ogg> [clip.ogg ...]
    python3 tools/demo_sfx_qc.py starts <take> <master.ogg> [--from 1.0] [--secs 6] [--floor 0.3]
    python3 tools/demo_sfx_qc.py --selftest

find    normalised cross-correlation of each clip against the whole take: FOUND at t (score >= 0.5) or MISSING.
starts  counts the places the master's opening (a slice from --from for --secs, skipping silence at 0) appears
        at least 5 s apart. A RESUMED bed does not replay its opening, so a take with one danger break that resumes
        reads COUNT 1, and a RESTART reads 2.

KNOWN LIMIT, measured on the .784 force-danger take: COUNT 1 does not say WHERE the one start is. That take's only
opening was at 441 s, which looks like "the first start was missed" until later slices are mapped (40 s of theme at
500 s = the same play shifted by the danger break). Use cowir-music's tools/demo_music_id.py for the RESUME verdict;
this counts openings and finds lines, it does not judge a return.

--selftest touches nothing: no file opened, no subprocess, nothing written. It builds a synthetic take in numpy and
checks, through the same functions, that a planted clip is FOUND at its time, an absent one is MISSING, and that
one, two and zero planted openings count 1, 2 and 0.
"""
import subprocess
import sys

import numpy as np

SR = 8000
FOUND_FLOOR = 0.5
APART_S = 5.0


def decode(path, start=None, secs=None):
    cmd = ["ffmpeg", "-nostdin", "-v", "error"]
    if start is not None:
        cmd += ["-ss", str(start)]
    if secs is not None:
        cmd += ["-t", str(secs)]
    cmd += ["-i", path, "-vn", "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"]
    raw = subprocess.run(cmd, capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def score_curve(take, clip):
    """Normalised cross-correlation of clip at every offset in take."""
    c = clip - clip.mean()
    n = len(c)
    if n == 0 or len(take) < n:
        return np.zeros(1)
    c /= np.linalg.norm(c) + 1e-12
    size = 1 << int(np.ceil(np.log2(len(take) + n)))
    xc = np.fft.irfft(np.fft.rfft(take, size) * np.conj(np.fft.rfft(c, size)), size)[: len(take) - n + 1]
    cs = np.concatenate([[0.0], np.cumsum(take * take)])
    return xc / np.sqrt(np.maximum(cs[n:] - cs[:-n], 1e-12))


def find(take, clip):
    """(found, seconds, score) for the best placement of clip in take."""
    s = score_curve(take, clip)
    k = int(np.argmax(s))
    return bool(s[k] >= FOUND_FLOOR), k / SR, float(s[k])


def starts(take, opening, floor):
    """[(seconds, score)] for every peak >= floor at least APART_S apart, in time order."""
    s = score_curve(take, opening)
    hits = []
    for k in np.argsort(-s):
        if s[k] < floor:
            break
        if all(abs(k - h) > APART_S * SR for h, _ in hits):
            hits.append((int(k), float(s[k])))
    return [(k / SR, v) for k, v in sorted(hits)]


def selftest():
    rng = np.random.default_rng(3)
    t = np.arange(int(1.5 * SR)) / SR
    line = np.sin(2 * np.pi * 220 * t * (1 + 0.3 * t)) * np.hanning(len(t))
    other = np.sin(2 * np.pi * 523 * t) * rng.standard_normal(len(t)) * 0.5
    take = 0.05 * rng.standard_normal(60 * SR)
    take[int(20 * SR): int(20 * SR) + len(line)] += line
    ok, at, sc = find(take, line)
    assert ok and abs(at - 20.0) < 0.01, f"planted line not FOUND at 20.0 s: {ok} {at:.2f} {sc:.2f}"
    ok, _, sc = find(take, other)
    assert not ok, f"an absent clip read FOUND (score {sc:.2f}): the floor cannot say MISSING"
    ## SMOOTHED noise: white noise matches at one sample, so the 5 s de-dupe was never exercised; a pure chord
    ## repeats and half-matches itself shifted. Low-passed noise has a broad peak and no period (both mutation-measured).
    opening = np.convolve(rng.standard_normal(6 * SR), np.ones(80) / 80, mode="same")
    for planted in ([10.0], [10.0, 40.0], []):
        tk = 0.05 * rng.standard_normal(60 * SR)
        for p in planted:
            tk[int(p * SR): int(p * SR) + len(opening)] += opening
        got = starts(tk, opening, 0.3)
        assert [round(a) for a, _ in got] == [round(p) for p in planted], f"planted {planted}, counted {got}"
    print("selftest OK: find FOUND/MISSING, starts 1 / 2 / 0")


def main(argv):
    if argv[:1] == ["--selftest"]:
        selftest()
        return 0
    if len(argv) >= 3 and argv[0] == "find":
        take = decode(argv[1])
        missing = 0
        for clip in argv[2:]:
            ok, at, sc = find(take, decode(clip))
            missing += not ok
            print(f"{clip.split('/')[-1]:32s} {'FOUND' if ok else 'MISSING'} at {at:7.2f}s  score {sc:.2f}")
        return 1 if missing else 0
    if len(argv) >= 3 and argv[0] == "starts":
        opts = {"--from": 1.0, "--secs": 6.0, "--floor": 0.3}
        rest = argv[3:]
        for i in range(0, len(rest) - 1, 2):
            if rest[i] in opts:
                opts[rest[i]] = float(rest[i + 1])
        hits = starts(decode(argv[1]), decode(argv[2], opts["--from"], opts["--secs"]), opts["--floor"])
        for at, sc in hits:
            print(f"opening at {at:7.1f}s  score {sc:.2f}")
        print(f"COUNT {len(hits)}")
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
