#!/usr/bin/env python3
"""The Cave Rat King's counter, "Royal Spite" (struktured via cowir-main 25439/25451: make it "more obvious it's
devastating"; named for wounded-pride spite from a tiny king).

    python3 tools/gen_royal_spite.py <out.ogg>
    python3 tools/gen_royal_spite.py --selftest

Three beats in one cue, ordered the way the hit lands. The TELL: a breath hiss under three rodent chitters climbing
in pitch into an indignant squeal (180 ms), so the player hears it coming. The BITE: an incisor clack, a wet crunch
over a falling 110 -> 45 Hz body and a sub, the weight the shared `counter` thump lacks. The SPITE: a sour royal
brass blat, two detuned saws a minor second apart, falling a fifth, under a short regalia jangle: the fanfare a
king plays for himself when he has been insulted. Levelled to a crit's loudness (attack_hit_dagger_crit, -11.1
LUFS), not to the abilities (~-15.7): it must read as the heaviest single hit in the fight.
numpy synthesis at 44.1 kHz mono, one deterministic seed.

--selftest renders in memory and checks the shape. It opens no file and writes nothing.
"""
import re
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_sequence_beats import SR, N, at, env, hp, lp, mix, sweep, t  # noqa: E402

SEED = 6011
TARGET_LUFS = -11.1
BITE_AT = 0.18          # seconds: the crunch lands here, after the intake; battle aligns the hit frame to it
PEAK_CEILING = 10 ** (-6.0 / 20)   # gen_bolt_cues' measured encode overshoot margin for a dense short cue


def royal_spite(rng):
    ## The intake: breath hiss rising, and three rodent chitters climbing in pitch.
    n_in = N(BITE_AT)
    rise = np.linspace(0, 1, n_in)
    hiss = hp(lp(rng.standard_normal(n_in), 2500 + 5000 * rise), 1200) * rise ** 2 * .25
    chit = np.zeros(n_in)
    for i, (when, f) in enumerate(((.02, 2600), (.07, 3100), (.115, 3700))):
        d = .035
        c = np.sin(2 * np.pi * np.cumsum(np.full(N(d), f) * (1 + .25 * np.sin(2 * np.pi * 70 * t(d)))) / SR)
        c *= env(N(d), .002, 6) * (.22 + .06 * i)
        chit[N(when):N(when) + len(c)] += c[:n_in - N(when)]
    intake = hiss + chit
    ## The bite: incisors clack (two bright clicks 12 ms apart), the crunch, the body.
    clack = mix(hp(rng.standard_normal(N(.006)), 4000) * env(N(.006), .0002, 12) * 1.4,
                at(hp(rng.standard_normal(N(.006)), 3500) * env(N(.006), .0002, 12) * 1.1, .012))
    crunch_n = N(.22)
    grit = lp(rng.standard_normal(crunch_n), 3200) * (rng.random(crunch_n) < .35)
    crunch = grit * env(crunch_n, .001, 5) * 1.1
    body = sweep(110, 45, .45) * env(N(.45), .001, 5) * 1.3
    sub = np.sin(2 * np.pi * 38 * t(.3)) * env(N(.3), .004, 6) * .8
    bite = mix(clack, at(crunch, .004), at(body, .002), at(sub, .002))
    ## The squeal that ends the tell: the last chitter bends up an octave, the indignation.
    sq = sweep(3700, 7400, .05) * env(N(.05), .003, 3) * .3
    intake = mix(intake, at(sq, BITE_AT - .055))[:n_in]
    ## The spite: a sour brass blat (saws a minor second apart, falling a fifth), then the regalia jangling.
    d = .55
    tt = t(d)
    fall = 2 ** (-(7 / 12) * np.clip(tt / .4, 0, 1))
    def saw(f0):
        ph = np.cumsum(f0 * fall) / SR
        return 2 * (ph % 1) - 1
    blat = lp(saw(196) + saw(196 * 2 ** (1 / 12)) * .9, 1800) * env(N(d), .015, 3.5) * .55
    jangle = np.zeros(N(.5))
    for k in range(6):
        when = .03 + .06 * k + rng.uniform(0, .02)
        f = rng.uniform(5200, 7600)
        r = t(.12)
        ring = (np.sin(2 * np.pi * f * r) + .4 * np.sin(2 * np.pi * f * 1.37 * r)) * np.exp(-r * 30) * .07
        s0 = N(when)
        jangle[s0:s0 + len(ring)] += ring[:len(jangle) - s0]
    spite = mix(blat, jangle)
    return mix(intake, at(bite, BITE_AT), at(spite, BITE_AT + .06))


def _wav(y, path):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(y, -1, 1) * 32767).astype("<i2").tobytes())


def lufs(path):
    out = subprocess.run(["ffmpeg", "-nostdin", "-v", "info", "-i", str(path), "-filter_complex",
                          "ebur128=framelog=quiet", "-f", "null", "-"], capture_output=True, text=True).stderr
    m = re.search(r"I:\s*(-?[0-9.]+)\s*LUFS", out)
    return float(m.group(1)) if m else None


def render():
    y = royal_spite(np.random.default_rng(SEED)).astype(float)
    fade = N(.03)
    y[-fade:] *= np.linspace(1, 0, fade)
    y *= PEAK_CEILING / float(np.max(np.abs(y)))
    tmp = Path(tempfile.mkdtemp()) / "probe.wav"
    for _ in range(10):
        _wav(y, tmp)
        got = lufs(tmp)
        if got is None:
            raise SystemExit("REFUSING: the cue would not measure, so its level would be a guess")
        y *= 10 ** ((TARGET_LUFS - got) / 20)
        if np.max(np.abs(y)) > PEAK_CEILING:
            y = np.tanh(y / PEAK_CEILING) * PEAK_CEILING
    tmp.unlink()
    return y


def write(out):
    y = render()
    wav = Path(tempfile.mkdtemp()) / "cue.wav"
    _wav(y, wav)
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", str(wav), "-c:a", "libvorbis", "-q:a", "5", str(out)], check=True)
    wav.unlink()
    print("wrote %s (%.2fs)" % (out, len(y) / SR))


def selftest():
    ok = True

    def chk(name, cond):
        nonlocal ok
        ok &= bool(cond)
        print(("  ok    " if cond else "  FAIL  ") + name)

    y = royal_spite(np.random.default_rng(SEED))
    a = np.abs(y)
    pre, post = a[:N(BITE_AT)], a[N(BITE_AT):N(BITE_AT + .05)]
    chk("the loudest moment is the bite, not the tell or the blat", N(BITE_AT) <= np.argmax(a) < N(BITE_AT + .05))
    chk("the intake is a tell, well under the bite (< -9 dB)", pre.max() < post.max() * 10 ** (-9 / 20))
    f = np.fft.rfftfreq(len(y), 1 / SR)
    spec = np.abs(np.fft.rfft(y))
    chk("the bite carries sub weight (< 120 Hz)", spec[(f > 30) & (f < 120)].sum() > .1 * spec.sum())
    tail = y[N(BITE_AT + .25):N(BITE_AT + .55)]
    tf = np.fft.rfftfreq(len(tail), 1 / SR)
    ts = np.abs(np.fft.rfft(tail)) ** 2   # POWER: magnitude sums overweight the broadband crunch/jangle floor
    lo_mid = ts[(tf > 120) & (tf < 1500)].sum()
    chk("after the bite the blat carries the cue (energy mostly 120-1500 Hz)", lo_mid > .5 * ts.sum())
    peak = tf[np.argmax(ts * ((tf > 120) & (tf < 400)))]
    chk("the blat has fallen below its 196 Hz start by then (the deflation)", 120 < peak < 190)
    pre = y[:N(BITE_AT)]
    pf = np.fft.rfftfreq(len(pre), 1 / SR)
    ps = np.abs(np.fft.rfft(pre)) ** 2
    chk("CONTROL: the tell is NOT in that band (the arm above measures the blat)", ps[(pf > 120) & (pf < 1500)].sum() < .5 * ps.sum())
    chk("short enough to sit under one hit (< 1.4 s)", len(y) < N(1.4))
    chk("deterministic: the same seed renders the same samples", np.array_equal(y, royal_spite(np.random.default_rng(SEED))))
    print("selftest: %s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


def main(argv):
    if argv[:1] == ["--selftest"]:
        return selftest()
    if len(argv) == 1:
        write(argv[0])
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
