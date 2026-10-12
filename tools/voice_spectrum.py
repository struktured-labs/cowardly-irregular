#!/usr/bin/env python3
"""voice_spectrum.py — band energy of voice clips, with the normalisation STATED.

WHY THIS EXISTS, and it is a correction rather than a feature: on 2026-10-12 I published
"ElevenLabs has 7.6% in 11-14 kHz and 1.9% above 14 kHz" twice, to justify a casting
recommendation. Both figures were a MAGNITUDE (amplitude-sum) fraction, not energy, and both were
one clip at the TOP of the range quoted as typical. The same band measured as POWER is 0.19%.

    normalisation      11-14 kHz (EL / free)      >14 kHz (EL / free)
    POWER (energy)        0.194% / 0.004%            0.021% / 0.000%
    MAGNITUDE             4.67%  / 0.45%             1.19%  / 0.000%
    EL magnitude range    1.50-7.90%                 max 2.18%

A 24x gap between two normalisations of one measurement is the whole reason this is a tool and not
a shell one-liner: a number quoted without its normalisation is not a measurement. Every row this
prints carries the word POWER or MAGNITUDE, and --selftest asserts the two DISAGREE on a signal
built to make them disagree, so the distinction cannot quietly stop being made.

⚠️ AND NEITHER NUMBER IS A PERCEPTUAL CLAIM. 99.2% of the energy sits below 8 kHz in both engines,
yet perceptual weight is not proportional to energy — which is why struktured's ear decided the
casting and no spectrum here can. Report these to inform a listening test, never to replace one.

USAGE
    tools/voice_spectrum.py --bands <file>...            per-file rows, both normalisations
    tools/voice_spectrum.py --compare <globA> <globB>    per-group medians
    tools/voice_spectrum.py --selftest
"""
import glob
import json
import math
import statistics
import subprocess
import sys

BANDS = [(0, 8000), (8000, 11000), (11000, 14000), (14000, None)]


def band_fractions(samples, rate):
    """{normalisation: [fraction per band]} for one mono signal.

    POWER is |S|**2 — energy, what "how much of the sound is up there" means.
    MAGNITUDE is |S| — an amplitude sum, which weights quiet high bands far more heavily. Both are
    computed because both get quoted; the caller is made to say which.
    """
    import numpy as np

    x = np.asarray(samples, dtype=np.float64)
    if x.size < 256:
        return None
    spec = np.fft.rfft(x * np.hanning(x.size))
    freqs = np.fft.rfftfreq(x.size, 1.0 / rate)
    mag = np.abs(spec)
    out = {}
    for name, weighted in (("POWER", mag ** 2), ("MAGNITUDE", mag)):
        total = weighted.sum()
        if total <= 0:
            return None
        row = []
        for lo, hi in BANDS:
            sel = (freqs >= lo) if hi is None else ((freqs >= lo) & (freqs < hi))
            row.append(100.0 * weighted[sel].sum() / total)
        out[name] = row
    return out


def decode(path):
    """(samples, rate) via ffmpeg. Raises rather than returning an empty signal: a clip that will
    not decode is 'I cannot answer', not 'no high-frequency content' (the refusal/absence split)."""
    import numpy as np

    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
         "stream=sample_rate", "-of", "json", path],
        capture_output=True, text=True, timeout=60)
    streams = json.loads(probe.stdout or "{}").get("streams") or []
    if not streams:
        raise RuntimeError("no audio stream in %s" % path)
    rate = int(streams[0]["sample_rate"])
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-f", "f32le", "-"],
                         capture_output=True, timeout=120).stdout
    if not raw:
        raise RuntimeError("ffmpeg decoded 0 bytes from %s" % path)
    return np.frombuffer(raw, dtype=np.float32), rate


def cmd_bands(paths):
    bad = 0
    for p in paths:
        try:
            x, rate = decode(p)
        except Exception as exc:
            print("  UNREADABLE  %-40s %s" % (p.split("/")[-1], exc))
            bad += 1
            continue
        fr = band_fractions(x, rate)
        if fr is None:
            print("  TOO SHORT   %s" % p.split("/")[-1])
            bad += 1
            continue
        for norm in ("POWER", "MAGNITUDE"):
            print("  %-34s %5d Hz %-10s 0-8k %6.2f%%  8-11k %5.2f%%  11-14k %5.2f%%  >14k %5.2f%%"
                  % (p.split("/")[-1][:34], rate, norm, *fr[norm]))
    return 1 if bad else 0


def cmd_compare(globs):
    for g in globs:
        files = sorted(glob.glob(g))
        if not files:
            print("  %-28s NO FILES MATCHED — a group with no members is not a clean result" % g)
            continue
        rows = {"POWER": [], "MAGNITUDE": []}
        for p in files:
            try:
                x, rate = decode(p)
            except Exception:
                continue
            fr = band_fractions(x, rate)
            if fr:
                for k in rows:
                    rows[k].append(fr[k])
        if not rows["POWER"]:
            print("  %-28s nothing decodable" % g)
            continue
        print("  %s   n=%d" % (g, len(rows["POWER"])))
        for norm in ("POWER", "MAGNITUDE"):
            med = [statistics.median(c) for c in zip(*rows[norm])]
            hi = [max(c) for c in zip(*rows[norm])]
            print("     %-10s median  0-8k %6.2f%%  8-11k %5.2f%%  11-14k %5.2f%%  >14k %5.2f%%"
                  % (norm, *med))
            print("     %-10s max     0-8k %6.2f%%  8-11k %5.2f%%  11-14k %5.2f%%  >14k %5.2f%%"
                  % ("", *hi))
    return 0


def selftest():
    import numpy as np

    p = f = 0

    def chk(name, cond):
        nonlocal p, f
        if cond:
            p += 1
            print("  ok    %s" % name)
        else:
            f += 1
            print("  FAIL  %s" % name)

    rate = 48000
    t = np.arange(rate) / float(rate)
    low = np.sin(2 * math.pi * 1000 * t)
    high = np.sin(2 * math.pi * 13000 * t)

    fr = band_fractions(low, rate)
    chk("a 1 kHz tone is ~all in 0-8k", fr["POWER"][0] > 99.0 and fr["POWER"][2] < 0.1)
    fr = band_fractions(high, rate)
    chk("a 13 kHz tone is ~all in 11-14k", fr["POWER"][2] > 99.0 and fr["POWER"][0] < 0.1)

    ## THE POINT OF THE TOOL: the two normalisations must give DIFFERENT answers, or nobody is
    ## forced to say which they quoted. A quiet high tone under a loud low one is the shape of
    ## speech, and it is where the 0.19%-vs-4.67% discrepancy came from.
    mixed = low + 0.02 * high
    fr = band_fractions(mixed, rate)
    pw, mg = fr["POWER"][2], fr["MAGNITUDE"][2]
    chk("POWER and MAGNITUDE disagree on a quiet high band", mg > pw * 3.0)
    chk("MAGNITUDE over-reports vs POWER, never under", mg > pw)
    chk("each normalisation sums to 100%",
        all(abs(sum(fr[n]) - 100.0) < 0.5 for n in ("POWER", "MAGNITUDE")))

    ## A signal too short to transform is a refusal, not a zero.
    chk("a too-short signal returns None rather than 0%", band_fractions(np.zeros(16), rate) is None)
    chk("silence returns None rather than 0%", band_fractions(np.zeros(4096), rate) is None)

    ## Real decode path, only if a clip is there — the selftest must not depend on the asset tree.
    sample = sorted(glob.glob("assets/audio/sfx/voice_*.ogg"))
    if sample:
        try:
            x, r = decode(sample[0])
            fr = band_fractions(x, r)
            chk("a real clip decodes and is speech-shaped (0-8k dominant)", fr["POWER"][0] > 90.0)
        except Exception as exc:
            chk("a real clip decodes (%s)" % str(exc)[:40], False)
    else:
        print("  skip  no voice clips in this tree to decode")

    print("selftest: %d passed, %d failed" % (p, f))
    return 1 if f else 0


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    if argv[1] == "--selftest":
        return selftest()
    if argv[1] == "--bands" and len(argv) > 2:
        return cmd_bands(argv[2:])
    if argv[1] == "--compare" and len(argv) > 2:
        return cmd_compare(argv[2:])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
