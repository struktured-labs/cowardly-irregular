#!/usr/bin/env python3
"""The Rogue's second hit (struktured ruling via cowir-main 25159): the crossbow bolt landing, after the dagger swing.

    python3 tools/gen_bolt_cues.py <cue_key> <out.ogg>
    python3 tools/gen_bolt_cues.py --all assets/audio/sfx
    python3 tools/gen_bolt_cues.py --list
    python3 tools/gen_bolt_cues.py --selftest

Keys follow play_attack_hit's per-weapon convention (attack_hit_<type>[_crit]), so battle plays the bolt beat with
SoundManager.play_attack_hit("bolt", is_crit) and needs no new player method. The bolt must read as a DIFFERENT
hit from the dagger's whip-crack a beat earlier: a short incoming hiss, a dense THUNK with low body (the dagger cue
has deliberately none), and the shaft's quiver ringing out. The crit adds a bright crack and a short double echo,
the same crit identity the dagger crit carries. Levelled by integrated loudness to sit beside attack_hit_dagger /
attack_hit_dagger_crit (measured -16.6 / -11.1 LUFS). numpy synthesis at 44.1 kHz mono, deterministic seeds.

--selftest renders both cues in memory and checks their shape. It opens no file, walks no directory, runs no
subprocess and writes nothing.
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


def _bolt(rng, crit):
    ## The release: 25 ms of air tearing as the string lets go. Short on purpose: the sheet has no projectile, so the
    ## bolt's beat IS the release frame (rogue attack frame 4, cowir-sprites 25161) and the thunk must land on it.
    n_in = N(.025)
    rise = np.linspace(0, 1, n_in)
    hiss = hp(lp(rng.standard_normal(n_in), 3000 + 6000 * rise), 1800) * rise ** 2.5 * .35
    ## The thunk: a dense lowpassed burst over a falling 150 -> 85 Hz body, the weight the dagger's crack lacks.
    burst = lp(rng.standard_normal(N(.05)), 2600) * env(N(.05), .0004, 9) * 1.2
    body = sweep(150, 85, .16) * env(N(.16), .001, 7) * 1.1
    ## The quiver: the shaft ringing after it lodges, a damped 210 Hz tone with a 28 Hz wobble.
    tq = t(.32)
    quiver = np.sin(2 * np.pi * 210 * tq + 1.4 * np.sin(2 * np.pi * 28 * tq)) * np.exp(-tq * 11) * .45
    hit = mix(burst, body, at(quiver, .012))
    if crit:
        ## The crit identity: a bright crack on the strike and a short double echo of the whole hit.
        crack = hp(rng.standard_normal(N(.035)), 3500) * env(N(.035), .0003, 10) * 1.3
        ring = sum(np.sin(2 * np.pi * f * t(.4)) for f in (4200, 5600, 6800)) * np.exp(-t(.4) * 9) * .12
        core = mix(hit, crack, ring)
        hit = mix(core, at(core * .38, .11), at(core * .16, .22))
    return mix(hiss, at(hit, .025))


def attack_hit_bolt(rng):
    return _bolt(rng, False)


def attack_hit_bolt_crit(rng):
    return _bolt(rng, True)


## key -> (synth, seed, target integrated LUFS). Targets are the dagger pair's own measured levels.
CUES = {
    "attack_hit_bolt": (attack_hit_bolt, 7601, -16.6),
    "attack_hit_bolt_crit": (attack_hit_bolt_crit, 7602, -11.1),
}
## Sample-peak ceiling for the limiter, well under the -1 dBTP the dagger pair meets, because a short dense cue
## overshoots on encode: limiting at -1 measured +3.9 dBTP on the crit's .ogg, -4 gave +0.4, -6 gives -1.9.
PEAK_CEILING = 10 ** (-6.0 / 20)


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


def render(key):
    fn, seed, target = CUES[key]
    y = fn(np.random.default_rng(seed)).astype(float)
    fade = N(.015)
    y[-fade:] *= np.linspace(1, 0, fade)
    y *= PEAK_CEILING / float(np.max(np.abs(y)))
    ## Integrated loudness, not RMS: the pair must match the dagger cues the player hears one beat earlier.
    ## A cue that cannot reach target under the peak ceiling is soft-limited rather than clipped.
    tmp = Path(tempfile.mkdtemp()) / "probe.wav"
    for _ in range(10):
        ## ebur128 needs a 400 ms block: a 0.36 s cue measures as -70 (silence). Pad the PROBE, never the asset.
        _wav(np.concatenate([y, np.zeros(max(0, N(.6) - len(y)))]), tmp)
        got = lufs(tmp)
        if got is None:
            raise SystemExit("REFUSING: %s would not measure, so its level would be a guess" % key)
        y *= 10 ** ((target - got) / 20)
        if np.max(np.abs(y)) > PEAK_CEILING:
            y = np.tanh(y / PEAK_CEILING) * PEAK_CEILING
    tmp.unlink()
    return y


def write(key, out):
    y = render(key)
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

    plain = attack_hit_bolt(np.random.default_rng(7601))
    crit = attack_hit_bolt_crit(np.random.default_rng(7602))
    chk("the thunk lands within 40 ms of the cue start, on the beat", N(.015) < np.argmax(np.abs(plain)) < N(.04))
    lo = np.abs(np.fft.rfft(plain))
    f = np.fft.rfftfreq(len(plain), 1 / SR)
    chk("the bolt carries low body (<200 Hz), the dagger crack's missing weight", lo[(f > 60) & (f < 200)].sum() > .1 * lo.sum())
    chk("the crit is longer than the plain hit (its echo tail)", len(crit) > len(plain))
    chk("CONTROL: the plain hit has no echo, so the length arm measures the echo", len(plain) < N(.5))
    chk("deterministic: the same seed renders the same samples", np.array_equal(plain, attack_hit_bolt(np.random.default_rng(7601))))
    print("selftest: %s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


def main(argv):
    if argv[:1] == ["--selftest"]:
        return selftest()
    if argv[:1] == ["--list"]:
        print("\n".join(sorted(CUES)))
        return 0
    if len(argv) == 2 and argv[0] == "--all":
        for key in sorted(CUES):
            write(key, Path(argv[1]) / (key + ".ogg"))
        return 0
    if len(argv) == 2 and argv[0] in CUES:
        write(argv[0], argv[1])
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
