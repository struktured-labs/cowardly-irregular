#!/usr/bin/env python3
"""Arms for check_raw_assets_shipped.py, each proved to fire AND to stay quiet.

Fixtures are synthetic GDPC v2 files -- a real header and a real file table, declared sizes, no
payload -- plus a synthetic `src/` tree of .gd files. Those two ARE what the checker reads, so
the arms have the real subject rather than a proxy for it. They therefore prove the CHECKER and
never a real build; a real build is only ever certified by running it against a real pck, which
tools/deploy_web.sh gate 3c does on every web deploy.

⛔ FOUR ARMS EXIST BECAUSE THE TOOL WAS WRONG ABOUT THEM ON ITS FIRST RUN AGAINST THE REAL TREE,
and a selftest that only covers what you got right is a selftest that agrees with you:

  * a res:// literal that is an OPERAND is not a path. `"res://data/cutscenes/" + filename`
    and `"res://data/cutscenes/%s.json" % id` were both captured as whole initialisers and
    reported MISSING -- two blocks over assets that exist under no such name.
  * a path built at runtime is neither present nor absent, so it is PRINTED as skipped rather
    than silently dropped from the corpus.
  * the sink's ARGUMENT INDEX has to be used. `load_rows(png_path, world_id)` reads param 0;
    an index-blind version checks `world_id` and reports on a corpus it is not naming.
  * a bare `open(` is somebody else's method, not FileAccess.

    tools/check_raw_assets_shipped_selftest.py      ->  0 all arms as expected, 1 otherwise
"""
import os
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "check_raw_assets_shipped.py")

PASS, BLOCK, CANNOT = 0, 5, 2


def write_pck(path, entries, magic=b"GDPC", flags=0):
    """entries: list of packed paths. No payload -- the file table is the whole subject."""
    with open(path, "wb") as f:
        f.write(magic)
        f.write(struct.pack("<I", 2))
        f.write(struct.pack("<III", 4, 4, 1))
        f.write(struct.pack("<I", flags))
        f.write(struct.pack("<Q", 0))
        f.write(b"\0" * (16 * 4))
        f.write(struct.pack("<I", len(entries)))
        for name in entries:
            raw = name.encode("utf-8")
            pad = (-len(raw)) % 4
            f.write(struct.pack("<I", len(raw) + pad))
            f.write(raw + b"\0" * pad)
            f.write(struct.pack("<QQ", 0, 0))
            f.write(b"\0" * 16)
            f.write(struct.pack("<I", 0))


def write_src(root, files):
    for rel, text in files.items():
        p = os.path.join(root, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(text)
    return root


# The real one-hop shape: the reader is in one file, the literal in another, and only the
# sink's own parameter index is a path.
LOADER = '''extends Node
static func load_rows(png_path: String, world_id: String) -> Array:
\tvar bytes := FileAccess.get_file_as_bytes(png_path)
\treturn []
static func load_second(world_id: String, png_path: String) -> Array:
\tvar bytes := FileAccess.get_file_as_bytes(png_path)
\treturn []
'''


def run(pck, src, extra=()):
    r = subprocess.run([sys.executable, TOOL, pck, "--src=" + src] + list(extra),
                       capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


def main():
    passed = failed = 0

    def arm(label, got, want):
        nonlocal passed, failed
        if got == want:
            print("  ok    %-58s %s" % (label, got))
            passed += 1
        else:
            print("  FAIL  %-58s got %r want %r" % (label, got, want))
            failed += 1

    with tempfile.TemporaryDirectory(prefix="rawassets.") as d:
        have = os.path.join(d, "have.pck")
        lack = os.path.join(d, "lack.pck")
        write_pck(have, ["data/present.json", "data/maps/overworld_w1.png", "data/pre#sent.json"])
        write_pck(lack, ["data/present.json", "data/pre#sent.json"])

        # ---- direct read: ONE variable moves, the pck, and the verdict follows it -----------
        direct = write_src(os.path.join(d, "direct"), {"A.gd":
            'extends Node\nconst P := "res://data/maps/overworld_w1.png"\n'
            'func f():\n\tvar b := FileAccess.get_file_as_bytes(P)\n'})
        ec, out = run(have, direct)
        arm("direct read, asset IS in the pck", ec, PASS)
        ec, out = run(lack, direct)
        arm("  ...same source, pck lacking it, BLOCKS", ec, BLOCK)
        arm("  ...and the message names the reading site", "A.gd:4" in out, True)
        arm("  ...and names the asset", "res://data/maps/overworld_w1.png" in out, True)

        # ---- one hop through a helper: the actual W2-W6 shape -------------------------------
        hop = write_src(os.path.join(d, "hop"), {
            "MapImageLoader.gd": LOADER,
            "Suburban.gd": 'extends Node\nconst MAP_IMAGE: String = "res://data/maps/overworld_w1.png"\n'
                           'const MAP_WORLD := "w2"\n'
                           'func _ready():\n\tfor row in MapImageLoader.load_rows(MAP_IMAGE, MAP_WORLD):\n\t\tpass\n'})
        ec, out = run(have, hop)
        arm("one hop via a const in ANOTHER file, present", ec, PASS)
        ec, out = run(lack, hop)
        arm("  ...and absent, BLOCKS", ec, BLOCK)
        arm("  ...crediting the CALLER, not the reader", "Suburban.gd:5" in out, True)

        hoplit = write_src(os.path.join(d, "hoplit"), {
            "MapImageLoader.gd": LOADER,
            "B.gd": 'extends Node\nfunc _ready():\n'
                    '\tMapImageLoader.load_rows("res://data/maps/overworld_w1.png", "w2")\n'})
        arm("one hop with a literal at the call site", run(lack, hoplit)[0], BLOCK)

        # ---- the argument INDEX is used, proved by moving only the index --------------------
        idx = write_src(os.path.join(d, "idx"), {
            "MapImageLoader.gd": LOADER,
            "C.gd": 'extends Node\nfunc _ready():\n'
                    '\tMapImageLoader.load_rows("res://data/present.json", "res://data/absent.png")\n'})
        arm("a res:// at a NON-sink index is not checked", run(lack, idx)[0], PASS)
        idx2 = write_src(os.path.join(d, "idx2"), {
            "MapImageLoader.gd": LOADER,
            "C.gd": 'extends Node\nfunc _ready():\n'
                    '\tMapImageLoader.load_second("res://data/present.json", "res://data/absent.png")\n'})
        arm("  ...and the SAME args at the sink index DO block", run(lack, idx2)[0], BLOCK)

        # ---- a res:// literal that is an OPERAND is not a path (two real false positives) ---
        operand = write_src(os.path.join(d, "operand"), {"D.gd":
            'extends Node\nconst OK := "res://data/present.json"\n'
            'func f(filename):\n'
            '\tvar path := "res://data/cutscenes/" + filename\n'
            '\tvar g := FileAccess.open(path, FileAccess.READ)\n'
            '\tvar h := FileAccess.get_file_as_bytes(OK)\n'})
        ec, out = run(lack, operand)
        arm("a literal + variable is NOT captured as a path", ec, PASS)
        arm("  ...and its fragment appears nowhere", "res://data/cutscenes/" in out, False)
        fmt = write_src(os.path.join(d, "fmt"), {"E.gd":
            'extends Node\nconst OK := "res://data/present.json"\n'
            'func f(cid):\n'
            '\tvar path = "res://data/cutscenes/%s.json" % cid\n'
            '\tvar g := FileAccess.open(path, FileAccess.READ)\n'
            '\tvar h := FileAccess.get_file_as_bytes(OK)\n'})
        arm("a `%` format literal is NOT captured as a path", run(lack, fmt)[0], PASS)
        # ⛔ THE FLOOR. Without this the two arms above pass if capture is broken ENTIRELY.
        whole = write_src(os.path.join(d, "whole"), {"F.gd":
            'extends Node\nconst P := "res://data/absent.png"\n'
            'func f():\n\tvar g := FileAccess.open(P, FileAccess.READ)\n'})
        arm("  FLOOR: a whole-statement const IS still captured", run(lack, whole)[0], BLOCK)

        # ---- a runtime-built path is neither present nor absent: printed, not dropped -------
        tmpl = write_src(os.path.join(d, "tmpl"), {"G.gd":
            'extends Node\nconst OK := "res://data/present.json"\nconst DIR := "res://data/cutscenes/"\n'
            'func f():\n\tvar a := FileAccess.open(DIR, FileAccess.READ)\n'
            '\tvar b := FileAccess.get_file_as_bytes(OK)\n'})
        ec, out = run(lack, tmpl)
        arm("a directory const does not block", ec, PASS)
        arm("  ...and is PRINTED as skipped, not dropped", "1 skipped as runtime-built" in out, True)

        # ---- comments, and a `#` that is not one --------------------------------------------
        cmt = write_src(os.path.join(d, "cmt"), {"H.gd":
            'extends Node\nconst OK := "res://data/present.json"\n'
            'func f():\n\t# FileAccess.get_file_as_bytes("res://data/absent.png")\n'
            '\tvar b := FileAccess.get_file_as_bytes(OK)\n'})
        arm("a commented-out read is not a consumer", run(lack, cmt)[0], PASS)
        hashy = write_src(os.path.join(d, "hashy"), {"I.gd":
            'extends Node\nfunc f():\n'
            '\tvar b := FileAccess.get_file_as_bytes("res://data/pre#sent.json")\n'})
        arm("a `#` INSIDE a string does not truncate it", run(lack, hashy)[0], PASS)

        # ---- only RAW readers count; load()/preload() resolve through the .import ----------
        loaded = write_src(os.path.join(d, "loaded"), {"J.gd":
            'extends Node\nconst OK := "res://data/present.json"\n'
            'func f():\n\tvar t = load("res://data/absent.png")\n'
            '\tvar u = preload("res://data/absent.png")\n'
            '\tvar b := FileAccess.get_file_as_bytes(OK)\n'})
        arm("load()/preload() of an imported asset is fine", run(lack, loaded)[0], PASS)
        foreign = write_src(os.path.join(d, "foreign"), {"K.gd":
            'extends Node\nconst OK := "res://data/present.json"\n'
            'func f(dir):\n\tvar x = dir.open("res://data/absent.png")\n'
            '\tvar b := FileAccess.get_file_as_bytes(OK)\n'})
        arm("a bare `open(` is not FileAccess.open", run(lack, foreign)[0], PASS)
        arm("  ...FLOOR: FileAccess.open on it DOES block", run(lack, write_src(
            os.path.join(d, "faopen"), {"L.gd":
                'extends Node\nfunc f():\n\tvar x = FileAccess.open("res://data/absent.png", FileAccess.READ)\n'}
            ))[0], BLOCK)

        # ---- cannot-evaluate is its OWN exit code, never a pass ------------------------------
        empty = write_src(os.path.join(d, "empty"), {"M.gd": 'extends Node\nfunc f():\n\tpass\n'})
        ec, out = run(lack, empty)
        arm("a derivation of ZERO blocks (vacuity floor)", ec, CANNOT)
        arm("  ...and says the corpus collapsed", "ZERO raw-bytes assets" in out, True)
        arm("an absent pck cannot evaluate", run(os.path.join(d, "nope.pck"), direct)[0], CANNOT)
        arm("an absent src dir cannot evaluate", run(have, os.path.join(d, "nosrc"))[0], CANNOT)
        bad = os.path.join(d, "bad.pck")
        write_pck(bad, ["data/present.json"], magic=b"XXXX")
        ec, out = run(bad, direct)
        arm("a non-GDPC file cannot evaluate", ec, CANNOT)
        arm("  ...and says the magic is wrong", "GDPC" in out, True)
        enc = os.path.join(d, "enc.pck")
        write_pck(enc, ["data/present.json"], flags=1)
        ec, out = run(enc, direct)
        arm("an ENCRYPTED directory cannot evaluate", ec, CANNOT)
        arm("  ...and says so rather than reading garbage", "ENCRYPTED" in out, True)

        # ---- --quiet changes the volume, never the verdict ----------------------------------
        q_ec, q_out = run(lack, direct, ["--quiet"])
        arm("--quiet keeps the verdict", q_ec, BLOCK)
        arm("  ...and still names the blocked asset", "overworld_w1.png" in q_out, True)
        arm("  ...and drops the per-asset roll", "ships raw" in q_out, False)

    print("\nselftest: %d passed, %d failed" % (passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
