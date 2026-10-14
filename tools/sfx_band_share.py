#!/usr/bin/env python3
"""sfx_band_share.py — exact-FFT band energy share for one or more cues.

WHY EXACT FFT AND NOT FILTERS: a biquad's skirt leaks into the neighbouring band, which is how I
published three wrong band figures for the door family (overlapping bins first, then filter skirt).
One windowed rFFT with hard bin edges cannot do that.

    tools/sfx_band_share.py <file.ogg> [more...]
    tools/sfx_band_share.py --selftest

Moved out of gitignored tmp/ because the figures it produces are quoted in sfx_manifest prompts and
in test headers, and a number nobody else can re-derive is an assertion rather than a measurement.

Reaches: ffmpeg as a subprocess, and under --selftest temp wavs it writes and deletes. It writes no
repo path.
"""
import os
import struct
import subprocess
import sys
import tempfile
import wave

import numpy as np

BANDS = [(40, 250), (250, 1000), (1000, 2000), (2000, 8000)]
SR = 44100


def decode(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(SR),
                          "-f", "s16le", "-"], capture_output=True).stdout
    return np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0


def shares(x):
    """({(lo,hi): percent}, dominant band, peak bin frequency), or (None, None, None)."""
    if x.size == 0:
        return None, None, None
    X = np.fft.rfft(x * np.hanning(x.size))
    p = np.abs(X) ** 2
    f = np.fft.rfftfreq(x.size, 1.0 / SR)
    tot = p[(f >= 20) & (f <= 20000)].sum()
    if tot <= 0:
        return None, None, None
    out = {}
    for lo, hi in BANDS:
        out[(lo, hi)] = 100.0 * p[(f >= lo) & (f < hi)].sum() / tot
    dom = max(out, key=out.get)
    return out, dom, f[int(np.argmax(p))]


def report(path):
    sh, dom, peak = shares(decode(path))
    if sh is None:
        print("%-34s (decoded 0 samples, or silent)" % os.path.basename(path))
        return
    parts = "  ".join("%d-%d %5.1f%%" % (lo, hi, sh[(lo, hi)]) for lo, hi in BANDS)
    print("%-34s %s   dominant %d-%d   peak %.0f Hz"
          % (os.path.basename(path), parts, dom[0], dom[1], peak))


def _tone(path, freq, seconds=0.30, amp=0.4):
    """A real wav on disk, so the selftest exercises the ffmpeg DECODE path and not just the FFT."""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    y = (amp * np.sin(2 * np.pi * freq * t) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(struct.pack("<%dh" % n, *y.tolist()))



def _scratch(prefix):
    """A temp dir inside the REPO's gitignored tmp/, never /tmp — struktured's standing rule, and
    tempfile defaults to /tmp. Resolved from this script's own location so it holds whatever the
    caller's cwd is."""
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    base = os.path.join(root, "tmp")
    os.makedirs(base, exist_ok=True)
    return tempfile.mkdtemp(prefix=prefix, dir=base)

def selftest():
    p = f = 0

    def chk(name, cond, detail=""):
        nonlocal p, f
        if cond:
            p += 1
            print("  ok    %s%s" % (name, ("  " + detail) if detail else ""))
        else:
            f += 1
            print("  FAIL  %s%s" % (name, ("  " + detail) if detail else ""))

    d = _scratch("sfx_band_")
    try:
        ## ONE POSITIVE CONTROL PER BAND. A tool that reported a single band for everything would
        ## still have produced plausible output for every cue I have measured with it, and a
        ## plausible number is believed. Each band has to be shown to be reachable.
        for freq, want in ((120, (40, 250)), (500, (250, 1000)),
                           (1500, (1000, 2000)), (3000, (2000, 8000))):
            wav = os.path.join(d, "t%d.wav" % freq)
            _tone(wav, freq)
            sh, dom, peak = shares(decode(wav))
            if sh is None:
                chk("a %d Hz tone measures at all" % freq, False)
                continue
            chk("a %d Hz tone lands in %d-%d" % (freq, want[0], want[1]), dom == want,
                "got %d-%d at %.1f%%" % (dom[0], dom[1], sh[dom]))
            chk("...and dominates it", sh[dom] > 90.0, "%.1f%%" % sh[dom])
            chk("...and the peak bin IS the tone", abs(peak - freq) < 15.0, "%.0f Hz" % peak)

        ## The four shares partition 20 Hz-20 kHz, so they cannot exceed 100.
        sh, _, _ = shares(decode(os.path.join(d, "t500.wav")))
        chk("the four shares never exceed 100%", sh is not None and sum(sh.values()) <= 100.01,
            "%.2f%%" % (sum(sh.values()) if sh else -1))

        ## NEGATIVE CONTROLS — silence and a non-audio file must yield nothing, not a band.
        silent = os.path.join(d, "silent.wav")
        _tone(silent, 500, amp=0.0)
        chk("silence returns None rather than a fabricated band", shares(decode(silent))[0] is None)
        chk("a non-audio file decodes to nothing", decode(os.path.abspath(__file__)).size == 0)
    finally:
        for fn in os.listdir(d):
            os.unlink(os.path.join(d, fn))
        os.rmdir(d)

    print("selftest: %d passed, %d failed" % (p, f))
    return 1 if f else 0


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    if argv[1] == "--selftest":
        return selftest()
    for path in argv[1:]:
        report(path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
