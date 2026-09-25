#!/usr/bin/env python3
"""Arms for check_web_audio_tier.py, each proved to fire AND to stay quiet.

Fixtures are synthetic GDPC v2 files — a real header and a real file table, sizes declared, no
payload — plus a synthetic stage holding .ogg sources and .import sidecars. That is exactly what
the checker reads, so the table is the subject and not a proxy for it. It does mean these arms
prove the CHECKER and never a real build; the real build is verified by running the staged
export, which is the only thing that can.

Two arms exist because the tool was WRONG about them on its first real run, and a selftest that
only covers what you got right is a selftest that agrees with you:
  * the cache line is measured against the pck's FILE size, not the sum of its table entries
    (375,219 B apart on the first 40k stage — both under the line, so it was right by luck)
  * a track is resolved to its artifact through the stage's .import sidecar, not by basename
    (assets/audio/music and assets/audio/sfx share four names in this project)

    tools/check_web_audio_tier_selftest.py      ->  0 all arms as expected, 1 otherwise
"""
import hashlib
import os
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "check_web_audio_tier.py")
LINE = 160 * 1024 * 1024


def write_pck(path, entries, pad=0):
    """entries: [(packed path, declared size)]. pad appends bytes so the FILE exceeds the table."""
    with open(path, "wb") as f:
        f.write(b"GDPC")
        f.write(struct.pack("<I", 2))
        f.write(struct.pack("<III", 4, 4, 1))
        f.write(struct.pack("<I", 0))
        f.write(struct.pack("<Q", 0))
        f.write(b"\0" * (16 * 4))
        f.write(struct.pack("<I", len(entries)))
        for p, size in entries:
            b = p.encode()
            padlen = (-len(b)) % 4
            f.write(struct.pack("<I", len(b) + padlen))
            f.write(b + b"\0" * padlen)
            f.write(struct.pack("<QQ", 0, size))
            f.write(b"\0" * 16)
            f.write(struct.pack("<I", 0))
        if pad:
            f.write(b"\0" * pad)


def build(root, names, src_size=600_000, ratio=1.06, stage_size=None, stage_scramble=False,
          skip_stage=None, skip_entry=None, dup=None, one_off=None, table_pad=0, file_pad=0,
          subdir=("assets", "audio", "music")):
    """A tier, a stage that mirrors it, and a pck whose artifacts wrap the tier's files."""
    tier = os.path.join(root, "tier")
    music = os.path.join(root, "stage", *subdir)
    os.makedirs(tier, exist_ok=True)
    os.makedirs(music, exist_ok=True)
    entries = []
    for i, name in enumerate(names):
        body = bytes([i % 251]) * src_size
        with open(os.path.join(tier, name + ".ogg"), "wb") as f:
            f.write(body)
        if name != skip_stage:
            if stage_scramble:
                staged = bytes([(i + 7) % 251]) * src_size        # same size, other bytes
            elif stage_size:
                staged = (body[:stage_size] if stage_size < src_size
                          else body + b"\0" * (stage_size - src_size))
            else:
                staged = body
            with open(os.path.join(music, name + ".ogg"), "wb") as f:
                f.write(staged)
        art = f".godot/imported/{name}.ogg-{hashlib.md5(name.encode()).hexdigest()}.oggvorbisstr"
        with open(os.path.join(music, name + ".ogg.import"), "w") as f:
            f.write(f'[remap]\n\nimporter="oggvorbisstr"\ntype="AudioStreamOggVorbis"\n'
                    f'uid="uid://c{i:06d}"\npath="res://{art}"\n')
        if name != skip_entry:
            r = one_off[1] if (one_off and name == one_off[0]) else ratio
            entries.append((art, int(src_size * r)))
        if name == dup:
            entries.append((f".godot/imported/other/{name}.ogg-cafe0001.oggvorbisstr",
                            int(src_size * ratio)))
    if table_pad:
        entries.append(("main.tscn", table_pad))
    pck = os.path.join(root, "index.pck")
    write_pck(pck, entries, pad=file_pad)
    return pck, tier, os.path.join(root, "stage")


def run(pck, tier, *args):
    r = subprocess.run([sys.executable, TOOL, pck, tier, *args], capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


def main():
    fails = []

    def check(label, got, want, hay="", needle=""):
        ok = got == want and (not needle or needle in hay)
        print(f"  {'ok  ' if ok else 'FAIL'} {label}: exit {got} (want {want})"
              + ("" if ok or not needle else f" / missing {needle!r}"))
        if not ok:
            fails.append(label)

    names = [f"track{i:03d}" for i in range(161)]
    with tempfile.TemporaryDirectory(dir=os.path.join(HERE, "..", "tmp")) as root:
        def sub(n):
            d = os.path.join(root, n)
            os.makedirs(d, exist_ok=True)
            return d

        # ── the baseline, and it must be QUIET: an arm that fires on a correct tier cannot
        #    distinguish a wrong one.
        pck, tier, stage = build(sub("a"), names)
        ec, out = run(pck, tier, f"--stage={stage}", "--expect-tracks=161")
        check("correct tier passes", ec, 0, out, "161/161 byte-identical")
        check("...and resolves via the sidecars", 0 if "via the stage .import sidecars" in out else 1, 0)
        check("...and reports UNDER the line", 0 if "UNDER the cache line" in out else 1, 0)

        # ── ARM 1, exact: the stage is carrying audio that is not this tier.
        pck, tier, stage = build(sub("b"), names, stage_size=720_000)
        ec, out = run(pck, tier, f"--stage={stage}")
        check("a stage at another bitrate FAILS", ec, 5, out, "carrying OTHER audio")
        pck, tier, stage = build(sub("c"), names, stage_scramble=True)
        ec, out = run(pck, tier, f"--stage={stage}")
        check("same size, different bytes FAILS", ec, 5, out, "different bytes")
        pck, tier, stage = build(sub("d"), names, skip_stage="track042")
        ec, out = run(pck, tier, f"--stage={stage}")
        check("a track never swapped in FAILS", ec, 5, out, "track042")

        # ── ARM 2, per-file: one artifact is not a wrapper around its source. The median
        #    absorbs a single file, which is exactly why this arm exists alongside it.
        pck, tier, stage = build(sub("e"), names, one_off=("track007", 2.0))
        ec, out = run(pck, tier, f"--stage={stage}")
        check("one corrupt artifact FAILS", ec, 5, out, "track007")
        check("...and the median stays inside its band", 0 if "MEDIAN" not in out else 1, 0)

        # ── ARM 3, median: every artifact shifted together, none far enough alone.
        #    ratio 1.25 keeps all 161 inside the per-file band [0.95, 1.30].
        pck, tier, stage = build(sub("f"), names, ratio=1.25)
        ec, out = run(pck, tier, f"--stage={stage}")
        check("a whole-population shift FAILS on the median", ec, 5, out, "MEDIAN packed/tier")
        check("...with no per-file line at all", 0 if "outside [0.95" not in out else 1, 0)

        # ── the artifact is declared but absent from the pck
        pck, tier, stage = build(sub("g"), names, skip_entry="track013")
        ec, out = run(pck, tier, f"--stage={stage}")
        check("an imported track missing from the pck FAILS", ec, 5, out, "is NOT in the pck")

        # ── the ruling's other half: a TIER CHANGE must not remove tracks.
        pck, tier, stage = build(sub("h"), names[:158])
        ec, out = run(pck, tier, f"--stage={stage}", "--expect-tracks=161")
        check("158 tracks against an expected 161 FAILS", ec, 5, out, "must not remove tracks")
        ec, out = run(pck, tier, f"--stage={stage}", "--expect-tracks=158")
        check("...and 158 against 158 passes", ec, 0)

        # ── the cache line, and WHICH size it reads. table_pad puts the ENTRIES over the line;
        #    file_pad puts only the FILE over it. Both must be seen; the second is the bug the
        #    first real run exposed.
        pck, tier, stage = build(sub("i"), names, file_pad=LINE)
        ec, out = run(pck, tier, f"--stage={stage}")
        check("over the line is ADVISORY by default", ec, 0, out, "advisory, not a block")
        ec, out = run(pck, tier, f"--stage={stage}", "--require-under-cache-line")
        check("over the line FAILS when required", ec, 5, out, "AT OR OVER")
        # The control for the bug itself: entries summing past the line while the FILE is under
        # it must NOT fire. Before this, the arm read the table and would have.
        pck, tier, stage = build(sub("j"), names, table_pad=LINE)
        ec, out = run(pck, tier, f"--stage={stage}", "--require-under-cache-line")
        check("a TABLE total over the line does not fire — the FILE decides", ec, 0, out, "UNDER the cache line")

        # ── without --stage: the basename join, which must REFUSE a collision rather than pick.
        pck, tier, stage = build(sub("k"), names, dup="track013")
        ec, out = run(pck, tier)
        check("ambiguous basename REFUSES", ec, 5, out, "attribution is ambiguous")
        pck, tier, stage = build(sub("l"), names)
        ec, out = run(pck, tier)
        check("...and an unambiguous one still passes without --stage", ec, 0, out, "by basename")

        # ── inputs that cannot be measured are BLOCKED, never passed.
        ec, out = run(os.path.join(root, "nope.pck"), tier)
        check("a missing pck is BLOCKED", ec, 2, out, "does not exist")
        notpck = os.path.join(root, "not.pck")
        open(notpck, "wb").write(b"NOTAPACKFILE" * 8)
        ec, out = run(notpck, tier)
        check("a non-pck file is BLOCKED", ec, 2, out, "no GDPC magic")
        empty = sub("emptytier")
        ec, out = run(pck, empty)
        check("an EMPTY tier is BLOCKED, not vacuously passed", ec, 2, out, "satisfy every ratio")
        ec, out = run(pck, tier, "--stage=/nonexistent/stage")
        check("a --stage that is not a directory is BLOCKED", ec, 2, out, "WEAKER question")

        # ── --subdir: the web VOICE tier lives under assets/audio/sfx and brings its own bands.
        #    Voice lines are ~16 KB, so the fixed import overhead weighs more than on a 500 KB
        #    bed; the music bands must not be silently reused for them.
        SFX = ("assets", "audio", "sfx")
        VB = ("--ratio-band=0.95,1.60", "--median-band=1.00,1.40")
        voice = [f"voice_fighter_line{i:03d}" for i in range(40)]
        pck, tier, stage = build(sub("v1"), voice, src_size=16_000, ratio=1.35, subdir=SFX)
        ec, out = run(pck, tier, f"--stage={stage}", "--subdir=assets/audio/sfx", *VB)
        check("a voice tier under sfx passes with its own bands", ec, 0, out, "40/40 byte-identical")
        # The same fixture judged by the MUSIC bands must fail: 1.35 is outside 1.30 / 1.16. This is
        # the arm that proves the override is APPLIED, not merely parsed.
        ec, out = run(pck, tier, f"--stage={stage}", "--subdir=assets/audio/sfx",
                      "--ratio-band=0.95,1.30", "--median-band=1.00,1.16")
        check("...and FAILS under the music bands (the override is live)", ec, 5, out, "MEDIAN")
        # Wrong directory: without --subdir the checker looks in music/, where no voice was staged.
        ec, out = run(pck, tier, f"--stage={stage}")
        check("the voice tier checked against music/ FAILS", ec, 5, out, "never swapped in")
        pck, tier, stage = build(sub("v2"), voice, src_size=16_000, ratio=1.50, subdir=SFX)
        ec, out = run(pck, tier, f"--stage={stage}", "--subdir=assets/audio/sfx", *VB)
        check("a voice pck packed 1.50x the tier FAILS its own median band", ec, 5, out, "MEDIAN")
        ec, out = run(pck, tier, f"--stage={stage}", "--subdir=assets/audio/sfx")
        check("--subdir WITHOUT its own bands is BLOCKED", ec, 2, out, "wrong yardstick")
        ec, out = run(pck, tier, f"--stage={stage}", "--subdir=assets/audio/sfx", *VB,
                      f"--record={os.path.join(root, 'ref.txt')}")
        check("--subdir with --record is BLOCKED (the music reference)", ec, 2, out, "packed_music_bytes")
        check("...and wrote no record", 0 if not os.path.exists(os.path.join(root, "ref.txt")) else 1, 0)
        ec, out = run(pck, tier, f"--stage={stage}", "--subdir=assets/audio/sfx",
                      "--ratio-band=wide", "--median-band=1.00,1.40")
        check("a malformed band is BLOCKED", ec, 2, out, "not LO,HI")

    print(f"\n{'FAILED: ' + ', '.join(fails) if fails else 'all arms as expected'}")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
