#!/usr/bin/env python3
"""Arms for check_web_audio_tier.py, each proved to fire AND to stay quiet.

Fixtures are synthetic GDPC v2 files: a real header and a real file table, sizes declared and
no payload. That is exactly what the checker reads, so the table is the subject and not a proxy
for it — but it means these arms prove the CHECKER, never a real build. The real build is
verified by running the staged export, which is the only thing that can.

    tools/check_web_audio_tier_selftest.py      ->  0 all arms as expected, 1 otherwise
"""
import os, struct, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "check_web_audio_tier.py")
LINE = 160 * 1024 * 1024


def write_pck(path, entries):
    """entries: list of (packed path, declared size)."""
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
            pad = (-len(b)) % 4
            f.write(struct.pack("<I", len(b) + pad))
            f.write(b + b"\0" * pad)
            f.write(struct.pack("<QQ", 0, size))
            f.write(b"\0" * 16)
            f.write(struct.pack("<I", 0))


def build(root, tracks, ratio=1.09, pck_pad=0, skip=None, dup=None):
    tier = os.path.join(root, "tier")
    os.makedirs(tier, exist_ok=True)
    entries = []
    for name, src in tracks.items():
        with open(os.path.join(tier, name + ".ogg"), "wb") as f:
            f.write(b"\0" * src)
        if name == skip:
            continue
        entries.append((f".godot/imported/{name}.ogg-deadbeef.oggstr", int(src * ratio)))
        if name == dup:
            entries.append((f".godot/imported/other/{name}.ogg-cafe0001.oggstr", int(src * ratio)))
    if pck_pad:
        entries.append(("main.tscn", pck_pad))
    pck = os.path.join(root, "index.pck")
    write_pck(pck, entries)
    return pck, tier


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

    with tempfile.TemporaryDirectory(dir=os.path.join(HERE, "..", "tmp")) as root:
        good = {f"track{i:03d}": 600_000 for i in range(161)}

        # 1-2. the baseline, and it must be QUIET: an arm that fires on a correct tier
        #      cannot distinguish a wrong one.
        pck, tier = build(os.path.join(root, "a"), good)
        ec, out = run(pck, tier)
        check("correct 40k tier passes", ec, 0, out, "161/161")
        check("correct tier reports UNDER the line", 0 if "UNDER the cache line" in out else 1, 0)

        # 3. the arm @cowir-sfx asked for: the count is right, the AUDIO is not.
        #    A 48k artifact against a 40k source lands near 1.31x, outside [0.95, 1.30].
        pck2, tier2 = build(os.path.join(root, "c"), good)
        # one entry rewritten at a 48k artifact's size against its 40k source
        entries = [(f".godot/imported/track{i:03d}.ogg-deadbeef.oggstr",
                    int(600_000 * (1.40 if i == 7 else 1.09))) for i in range(161)]
        write_pck(pck2, entries)
        ec, out = run(pck2, tier2)
        check("a 48k artifact in a 40k tier FAILS", ec, 5, out, "track007")
        check("...and names it as not the staged tier", 0 if "NOT the staged tier" in out else 1, 0)

        # 4. a track staged but absent from the pck
        pck, tier = build(os.path.join(root, "d"), good, skip="track042")
        ec, out = run(pck, tier)
        check("a track missing from the pck FAILS", ec, 5, out, "track042")

        # 5. two artifacts sharing a basename — attribution by basename must refuse,
        #    not silently pick one (this lane published a 13x-wrong figure that way).
        pck, tier = build(os.path.join(root, "e"), good, dup="track013")
        ec, out = run(pck, tier)
        check("ambiguous basename FAILS", ec, 5, out, "attribution is ambiguous")

        # 6. the ruling's other half: a TIER CHANGE must not remove tracks.
        fewer = {f"track{i:03d}": 600_000 for i in range(158)}
        pck, tier = build(os.path.join(root, "f"), fewer)
        ec, out = run(pck, tier, "--expect-tracks=161")
        check("158 tracks against an expected 161 FAILS", ec, 5, out, "must not remove tracks")
        ec, out = run(pck, tier, "--expect-tracks=158")
        check("...and 158 against 158 passes", ec, 0)

        # 7. the cache line: advisory by default, blocking only when asked.
        pck, tier = build(os.path.join(root, "g"), good, pck_pad=LINE)
        ec, out = run(pck, tier)
        check("over the line is ADVISORY by default", ec, 0, out, "advisory, not a block")
        ec, out = run(pck, tier, "--require-under-cache-line")
        check("over the line FAILS when required", ec, 5, out, "AT OR OVER")

        # 8. inputs that cannot be measured are BLOCKED, never passed.
        ec, out = run(os.path.join(root, "nope.pck"), tier)
        check("a missing pck is BLOCKED", ec, 2, out, "does not exist")
        notpck = os.path.join(root, "not.pck")
        open(notpck, "wb").write(b"NOTAPACKFILE" * 8)
        ec, out = run(notpck, tier)
        check("a non-pck file is BLOCKED", ec, 2, out, "no GDPC magic")
        empty = os.path.join(root, "emptytier")
        os.makedirs(empty)
        ec, out = run(pck, empty)
        check("an EMPTY tier is BLOCKED, not vacuously passed", ec, 2, out, "would pass every ratio")

    print(f"\n{'FAILED: ' + ', '.join(fails) if fails else 'all arms as expected'}")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
