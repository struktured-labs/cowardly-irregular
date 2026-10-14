#!/usr/bin/env python3
"""sfx_envelope_accent.py — locate a cue's ARRIVAL accent: the envelope's local maximum inside a
stated late window, reported against the engage and the body.

⛔ WHY A LOCAL MAX AND NOT A RISE. My first version took the largest 10 ms rise after the body and
reported 0.250 s for freight_lift — that is the 38 Hz chain tremolo's own ripple, not the seat. A
DIFFERENCING detector on a modulated layer measures the modulator, and it answers confidently. The
local maximum in a named window cannot make that mistake, and the --selftest below pins exactly
that case so the wrong form cannot come back.

⚠️ AND PICK THE WINDOW FROM THE FASTEST MODULATOR IN THE CUE. A 10 ms RMS window covers 0.38 of a
cycle at 38 Hz and ALIASES, which reported a 10 dB null in freight_lift that does not exist. The
tell is that the swing GROWS as the window shrinks (15.9 -> 18.7 -> 20.7 dB at 10/4/2 ms) whereas a
real hole's depth is window-independent.

    tools/sfx_envelope_accent.py <file.ogg> <window_lo_s> <window_hi_s>
    tools/sfx_envelope_accent.py --selftest

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

SR = 44100
WIN_S = 0.010


def decode(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(SR),
                          "-f", "s16le", "-"], capture_output=True).stdout
    return np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0


def envelope(x, win_s=WIN_S):
    w = max(1, int(win_s * SR))
    n = x.size // w
    return np.array([20 * np.log10(max(1e-12, np.sqrt((x[i * w:(i + 1) * w] ** 2).mean())))
                     for i in range(n)]), w


def accent(x, lo, hi, win_s=WIN_S):
    """(time_s, level_dB, engage_dB, body_peak_dB) for the local max inside [lo, hi)."""
    env, w = envelope(x, win_s)
    if env.size == 0:
        return None
    i_lo, i_hi = int(lo / win_s), min(env.size, int(hi / win_s))
    if i_hi <= i_lo:
        return None
    sel = env[i_lo:i_hi]
    j = int(np.argmax(sel)) + i_lo
    engage = float(env[:2].max()) if env.size >= 2 else float(env[0])
    body = float(env[2:i_lo].max()) if i_lo > 2 else float("nan")
    return j * win_s, float(env[j]), engage, body


def report(path, lo, hi):
    x = decode(path)
    if x.size == 0:
        print("%-22s (decoded 0 samples)" % os.path.basename(path))
        return 1
    a = accent(x, lo, hi)
    if a is None:
        print("window %.3f-%.3f s is outside a %.3f s file" % (lo, hi, x.size / SR))
        return 1
    t, lvl, engage, body = a
    c = np.concatenate(([0.0], np.cumsum(x ** 2)))
    W = int(0.25 * SR)
    if x.size > W:
        ms = (c[W:] - c[:-W]) / W
        loud = 20 * np.log10(max(1e-12, np.sqrt(ms.max())))
    else:
        loud = 20 * np.log10(max(1e-12, np.sqrt((x ** 2).mean())))
    print("%-22s dur %.4f s" % (os.path.basename(path), x.size / SR))
    print("  engage (0.00-0.02)   %6.1f dB" % engage)
    print("  motor body peak      %6.1f dB" % body)
    print("  arrival accent       %6.1f dB  at %.3f s   (window %.2f-%.2f)" % (lvl, t, lo, hi))
    print("  arrival - body       %+6.1f dB" % (lvl - body))
    print("  arrival - engage     %+6.1f dB" % (lvl - engage))
    print("  peak %.2f dBFS   loudest-250ms %.1f"
          % (20 * np.log10(max(1e-12, np.abs(x).max())), loud))
    return 0


def _write(path, y):
    y = (np.clip(y, -1.0, 1.0) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(struct.pack("<%dh" % y.size, *y.tolist()))


def _synth(accent_at=0.30, tremolo_hz=0.0, seconds=0.41):
    """A quiet body with ONE loud burst at accent_at, optionally amplitude-modulated.

    The tremolo arm is the whole point: it is the shape that made the rise-based detector report
    the modulator instead of the burst."""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    body = 0.08 * np.sin(2 * np.pi * 330 * t)
    if tremolo_hz > 0:
        body *= (0.5 + 0.5 * np.sin(2 * np.pi * tremolo_hz * t)) ** 1.5
    burst = np.zeros(n)
    i0, i1 = int(accent_at * SR), int((accent_at + 0.05) * SR)
    seg = np.arange(i1 - i0) / float(i1 - i0)
    burst[i0:i1] = 0.55 * np.sin(2 * np.pi * 180 * t[i0:i1]) * (1.0 - seg)
    y = body + burst
    y[:int(0.02 * SR)] += 0.30 * np.sin(2 * np.pi * 140 * t[:int(0.02 * SR)])  # the engage
    return y



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

    d = _scratch("sfx_accent_")
    try:
        ## POSITIVE CONTROL: a burst planted at a known time must be found there.
        plain = os.path.join(d, "plain.wav")
        _write(plain, _synth(accent_at=0.30))
        a = accent(decode(plain), 0.26, 0.40)
        chk("a burst planted at 0.300 s is located there", a is not None and abs(a[0] - 0.30) <= 0.02,
            "got %.3f s" % (a[0] if a else -1))
        chk("...and reads ABOVE the body it sits on", a is not None and a[1] > a[3] + 3.0,
            "accent %.1f vs body %.1f" % ((a[1], a[3]) if a else (0, 0)))

        ## ⛔ THE REGRESSION CONTROL, and the reason this tool exists in this form. Same burst, body
        ## modulated at 38 Hz. A rise-based detector reports a tremolo trough->peak step instead of
        ## the burst; the local max must still find 0.300.
        trem = os.path.join(d, "trem.wav")
        _write(trem, _synth(accent_at=0.30, tremolo_hz=38.0))
        a2 = accent(decode(trem), 0.26, 0.40)
        chk("a 38 Hz tremolo does not move the located accent",
            a2 is not None and abs(a2[0] - 0.30) <= 0.02, "got %.3f s" % (a2[0] if a2 else -1))

        ## ...and that the naive form really would have failed, so the control is not decorative.
        env, _ = envelope(decode(trem))
        rises = [(i, env[i] - env[i - 1]) for i in range(int(0.10 / WIN_S), env.size)]
        worst = max(rises, key=lambda r: r[1])[0] * WIN_S
        chk("the REJECTED rise-based form is shown to pick the modulator", abs(worst - 0.30) > 0.02,
            "largest rise at %.3f s, not 0.300" % worst)

        ## A burst elsewhere must NOT be reported inside a window that excludes it.
        early = os.path.join(d, "early.wav")
        _write(early, _synth(accent_at=0.10))
        a3 = accent(decode(early), 0.26, 0.40)
        chk("a window that excludes the burst does not report it",
            a3 is not None and abs(a3[0] - 0.10) > 0.02, "got %.3f s" % (a3[0] if a3 else -1))

        ## REFUSALS: a window off the end of the file, and a non-audio input.
        chk("a window past the end of the file returns None",
            accent(decode(plain), 9.0, 9.5) is None)
        chk("a non-audio file decodes to nothing", decode(os.path.abspath(__file__)).size == 0)

        ## The aliasing fact in the docstring, asserted rather than only described: on a modulated
        ## body the measured swing GROWS as the window shrinks.
        x = decode(trem)
        sw = []
        for ms in (10, 4, 2):
            e, _ = envelope(x, ms / 1000.0)
            seg = e[int(0.10 / (ms / 1000.0)):int(0.26 / (ms / 1000.0))]
            sw.append(seg.max() - seg.min())
        chk("swing grows as the window shrinks (the aliasing tell)", sw[0] < sw[1] < sw[2],
            "%.1f / %.1f / %.1f dB at 10/4/2 ms" % tuple(sw))
    finally:
        for fn in os.listdir(d):
            os.unlink(os.path.join(d, fn))
        os.rmdir(d)

    print("selftest: %d passed, %d failed" % (p, f))
    return 1 if f else 0


def main(argv):
    if len(argv) >= 2 and argv[1] == "--selftest":
        return selftest()
    if len(argv) < 4:
        print(__doc__)
        return 2
    return report(argv[1], float(argv[2]), float(argv[3]))


if __name__ == "__main__":
    sys.exit(main(sys.argv))
