# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy"]
# ///
"""compose_inn_ditty.py -- the inn rest jingle, composed in code (Suno submit is parked; struktured 2026-11-01).

A classic JRPG "rest" motif: I - IV - V7 - I in F major at 100 BPM, a soft pulse lead over a triangle bass and
chord arpeggios, resolving onto a held tonic. 8-bit voices to sit with W1's medieval chip bed. Deterministic:
the same run writes the same samples. Writes a 44.1 kHz mono master, then ffmpeg encodes 96 kbps Ogg and
loudness-normalises it to the other stingers (-17 LUFS, measured: save_point -17.0, quest_complete -17.3).

    uv run tools/compose_inn_ditty.py [out.ogg]      (default assets/audio/music/inn_rest_ditty.ogg, then trimmed)
"""
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 44100
BPM = 100.0
BEAT = 60.0 / BPM
TARGET_LUFS = -17.0
DEFAULT_DST = "assets/audio/music/inn_rest_ditty.ogg"


def hz(note: str) -> float:
    names = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
    n, acc, octave = note[0], note[1:-1], int(note[-1])
    semi = names[n] + (1 if acc == "#" else -1 if acc == "b" else 0)
    return 440.0 * 2 ** ((semi + 12 * (octave + 1) - 69) / 12.0)


def env(n: int, attack: float, release: float) -> np.ndarray:
    e = np.ones(n)
    a, r = min(int(attack * SR), n), min(int(release * SR), n)
    if a:
        e[:a] = np.linspace(0.0, 1.0, a)
    if r:
        e[n - r:] *= np.linspace(1.0, 0.0, r)
    return e


def pulse(f: float, n: int, duty: float = 0.25, vibrato: float = 0.0) -> np.ndarray:
    t = np.arange(n) / SR
    phase = np.cumsum(f * (1 + vibrato * np.sin(2 * np.pi * 5.0 * t) * np.clip(t / 0.25, 0, 1)) / SR)
    return np.where((phase % 1.0) < duty, 1.0, -1.0)


def tri(f: float, n: int) -> np.ndarray:
    phase = (np.arange(n) * f / SR) % 1.0
    return 4 * np.abs(phase - 0.5) - 1


def place(buf: np.ndarray, start_beats: float, sig: np.ndarray) -> None:
    i = int(start_beats * BEAT * SR)
    j = min(len(buf), i + len(sig))
    buf[i:j] += sig[: j - i]


def compose() -> np.ndarray:
    total_beats = 8.0 + 1.6
    out = np.zeros(int(total_beats * BEAT * SR) + SR)
    # Lead: (note, start, beats). The last note holds into the tail so the cadence resolves.
    lead = [("A4", 0, .5), ("C5", .5, .5), ("F5", 1, 1),
            ("D5", 2, .5), ("C5", 2.5, .5), ("Bb4", 3, 1),
            ("A4", 4, .5), ("G4", 4.5, .5), ("E4", 5, .5), ("G4", 5.5, .5),
            ("F4", 6, 3.4)]
    for note, start, beats in lead:
        n = int(beats * BEAT * SR)
        rel = 1.2 if beats > 2 else 0.08
        place(out, start, 0.20 * pulse(hz(note), n, 0.25, 0.006 if beats > 0.75 else 0.0) * env(n, 0.012, rel))
    # Bass: one root per chord, the last one held under the tail.
    for note, start, beats in [("F2", 0, 2), ("Bb2", 2, 2), ("C3", 4, 2), ("F2", 6, 3.4)]:
        n = int(beats * BEAT * SR)
        place(out, start, 0.32 * tri(hz(note), n) * env(n, 0.02, 0.9 if beats > 2 else 0.12))
    # Arpeggios: eighth notes through each chord, low and soft.
    chords = [["F3", "A3", "C4", "A3"], ["Bb3", "D4", "F4", "D4"], ["C4", "E4", "G4", "Bb3"], ["F3", "A3", "C4", "F4"]]
    for ci, chord in enumerate(chords):
        for k, note in enumerate(chord):
            n = int(0.5 * BEAT * SR)
            place(out, ci * 2 + k * 0.5, 0.10 * tri(hz(note), n) * env(n, 0.005, 0.18))
    # The final chord rings: a soft triangle F major under the held lead.
    for note in ["F3", "A3", "C4"]:
        n = int(3.4 * BEAT * SR)
        place(out, 6, 0.07 * tri(hz(note), n) * env(n, 0.05, 1.4))
    # Warmth: a short feedback echo, then a gentle fade over the last 0.6 s that stops at -20 dB and
    # closes in 10 ms: a fade to zero leaves ~130 ms under audit_wrap_seams' -60 dB pad floor.
    d = int(0.21 * SR)
    wet = out.copy()
    for k in range(1, 4):
        wet[d * k:] += out[: len(out) - d * k] * (0.28 ** k)
    out = wet
    end = int(total_beats * BEAT * SR)
    out = out[:end]
    f = int(0.6 * SR)
    out[-f:] *= 0.1 + 0.9 * np.linspace(1.0, 0.0, f) ** 1.5
    c = int(0.010 * SR)
    out[-c:] *= np.linspace(1.0, 0.0, c)
    return out / max(1e-9, np.max(np.abs(out))) * 0.89


def main() -> int:
    dst = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_DST
    pcm = (compose() * 32767).astype(np.int16)
    with tempfile.NamedTemporaryFile(suffix=".wav", dir="tmp", delete=False) as tf:
        with wave.open(tf.name, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(pcm.tobytes())
        src = tf.name
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", src, "-af",
                    "loudnorm=I=%g:TP=-1.5:LRA=11" % TARGET_LUFS, "-ar", str(SR), "-ac", "1",
                    "-c:a", "libvorbis", "-b:a", "96k", dst], check=True)
    subprocess.run(["rm", "-f", src])
    if dst == DEFAULT_DST:
        # The encoder still leaves ~60 ms under the pad floor; the repo's own trimmer takes it off, as audit_wrap_seams asks.
        subprocess.run(["uv", "run", "tools/trim_wrap_padding.py", "--only", "inn_rest_ditty", "--apply"], check=True)
    print("wrote %s (%.2f s)" % (dst, len(pcm) / SR))
    return 0


if __name__ == "__main__":
    sys.exit(main())
