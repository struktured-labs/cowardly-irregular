#!/usr/bin/env python3
"""Arms for check_loaded_assets_resolve.py, each proved to fire AND to stay quiet.

Fixtures are synthetic GDPC v2 packs WITH REAL PAYLOAD BYTES, because this checker follows a
pointer: it reads a packed `.import`/`.remap`, parses its `path=`, and looks the target up. A
name-only fixture could not exercise any of that.

⛔ EVERY FIXTURE USES A NON-ZERO `file_base`, AND THAT IS THE POINT OF THE `.pck`/EMBEDDED PAIR.
Entry offsets in format v2 are relative to `file_base`, and a standalone .pck has pack_start 0 —
so `off+file_base` and `off+file_base+pack_start` are INDISTINGUISHABLE there. Only an embedded
pack separates them, and reading a real artifact with the wrong formula returns x86 instructions
that parse as nothing. Both container shapes are therefore tested against the same table.

    tools/check_loaded_assets_resolve_selftest.py      ->  0 all arms as expected, 1 otherwise
"""
import os
import re
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "check_loaded_assets_resolve.py")
PASS, BLOCK, CANNOT = 0, 5, 2


def pack_bytes(files, magic=b"GDPC", flags=0):
    """files: {packed path: payload bytes}. Real payloads, real offsets, non-zero file_base."""
    names = list(files)
    head = [magic, struct.pack("<I", 2), struct.pack("<III", 4, 4, 1)]
    # table size has to be known before file_base can be chosen, so measure it first
    tbl = b""
    for nm in names:
        raw = nm.encode("utf-8")
        pad = (-len(raw)) % 4
        tbl += (struct.pack("<I", len(raw) + pad) + raw + b"\0" * pad
                + struct.pack("<QQ", 0, 0) + b"\0" * 16 + struct.pack("<I", 0))
    header_len = 4 + 4 + 12 + 4 + 8 + 64 + 4 + len(tbl)
    file_base = header_len + 64        # deliberately NOT the header end: a gap the reader
                                       # must honour rather than assume payloads follow the table
    tbl = b""
    off = 0
    for nm in names:
        raw = nm.encode("utf-8")
        pad = (-len(raw)) % 4
        blob = files[nm]
        tbl += (struct.pack("<I", len(raw) + pad) + raw + b"\0" * pad
                + struct.pack("<QQ", off, len(blob)) + b"\0" * 16 + struct.pack("<I", 0))
        off += len(blob)
    head += [struct.pack("<I", flags), struct.pack("<Q", file_base), b"\0" * 64,
             struct.pack("<I", len(names)), tbl]
    body = b"".join(head)
    body += b"\xAB" * (file_base - len(body))          # the gap; must never be read as content
    for nm in names:
        body += files[nm]
    return body


def write_pack(path, files, **kw):
    with open(path, "wb") as f:
        f.write(pack_bytes(files, **kw))


def write_embedded(path, files, prefix=b"\x7fELF" + b"E" * 4096, **kw):
    body = pack_bytes(files, **kw)
    with open(path, "wb") as f:
        f.write(prefix + body + struct.pack("<Q", len(body)) + b"GDPC")


def write_src(root, files):
    for rel, text in files.items():
        p = os.path.join(root, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "w", encoding="utf-8").write(text)
    return root


def imp(target):
    return ('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\npath="%s"\n'
            % target).encode()


KEEP_IMPORT = b'[remap]\n\nimporter="keep"\n'


def run(pack, src, extra=()):
    r = subprocess.run([sys.executable, TOOL, pack, "--src=" + src] + list(extra),
                       capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


def main():
    passed = failed = 0

    def arm(label, got, want):
        nonlocal passed, failed
        if got == want:
            print("  ok    %-58s %s" % (label, got)); passed += 1
        else:
            print("  FAIL  %-58s got %r want %r" % (label, got, want)); failed += 1

    with tempfile.TemporaryDirectory(prefix="loadres.") as d:
        ART = ".godot/imported/hero.png-abc.ctex"
        good = {"assets/hero.png.import": imp("res://" + ART), ART: b"CTEXDATA",
                "src/Thing.gd.remap": imp("res://src/Thing.gdc"), "src/Thing.gdc": b"GDC",
                "data/plain.json": b"{}"}
        orphan = dict(good); del orphan[ART]
        keep = dict(good); keep["assets/hero.png.import"] = KEEP_IMPORT
        keep["assets/hero.png"] = b"\x89PNG"

        p_good = os.path.join(d, "good.pck"); write_pack(p_good, good)
        p_orph = os.path.join(d, "orph.pck"); write_pack(p_orph, orphan)
        p_keep = os.path.join(d, "keep.pck"); write_pack(p_keep, keep)
        e_good = os.path.join(d, "good.x86_64"); write_embedded(e_good, good)
        e_orph = os.path.join(d, "orph.x86_64"); write_embedded(e_orph, orphan)

        png = write_src(os.path.join(d, "png"), {"A.gd":
            'extends Node\nfunc f():\n\tvar t = load("res://assets/hero.png")\n'})

        # ---- follow the pointer: only the ARTIFACT's presence may move the verdict ----------
        arm("an imported asset with its artifact RESOLVES", run(p_good, png)[0], PASS)
        ec, out = run(p_orph, png)
        arm("  ...artifact missing from the pack BLOCKS", ec, BLOCK)
        arm("  ...and names the sidecar and its target",
            "hero.png.import points at .godot/imported/hero.png-abc.ctex" in out, True)
        arm("  ...and names the loading site", "A.gd:3" in out, True)

        # ⛔ THE MIRROR ARM. `keep` is REQUIRED for a raw-bytes reader and FATAL for load().
        ec, out = run(p_keep, png)
        arm("importer=\"keep\" under a load() BLOCKS", ec, BLOCK)
        arm("  ...and says why load() returns null", 'importer="keep"' in out, True)

        # ---- the same table in both containers must give the same answer --------------------
        arm("an EMBEDDED pack resolves identically", run(e_good, png)[0], PASS)
        arm("  ...and blocks identically", run(e_orph, png)[0], BLOCK)
        arm("  FLOOR: .pck and embedded agree on the same table",
            run(e_orph, png)[0] == run(p_orph, png)[0], True)

        # ---- .remap (scripts and scenes) and direct entries ---------------------------------
        gd = write_src(os.path.join(d, "gd"), {"B.gd":
            'extends Node\nconst S := preload("res://src/Thing.gd")\n'})
        arm("preload() of a .gd resolves via .remap", run(p_good, gd)[0], PASS)
        direct = write_src(os.path.join(d, "direct"), {"C.gd":
            'extends Node\nfunc f():\n\tvar j = load("res://data/plain.json")\n'})
        arm("a direct entry with no sidecar resolves", run(p_good, direct)[0], PASS)
        gone = write_src(os.path.join(d, "gone"), {"D.gd":
            'extends Node\nfunc f():\n\tvar x = load("res://assets/nothing.tres")\n'})
        ec, out = run(p_good, gone)
        arm("an asset with NO entry and no sidecar BLOCKS", ec, BLOCK)
        arm("  ...and says nothing can serve it", "nothing in the pack can serve it" in out, True)

        # ---- the boundary with the raw-bytes checker: each ignores the other's consumers -----
        rawread = write_src(os.path.join(d, "rawread"), {"E.gd":
            'extends Node\nconst OK := "res://data/plain.json"\n'
            'func f():\n\tvar b := FileAccess.get_file_as_bytes("res://assets/hero.png")\n'
            '\tvar j = load(OK)\n'})
        arm("a FileAccess read is NOT a load() consumer", run(p_keep, rawread)[0], PASS)
        method = write_src(os.path.join(d, "method"), {"F.gd":
            'extends Node\nfunc f(db):\n\tvar x = db.load("res://assets/nothing.tres")\n'
            '\tvar j = load("res://data/plain.json")\n'})
        arm("a bare obj.load( is not ResourceLoader", run(p_good, method)[0], PASS)
        rl = write_src(os.path.join(d, "rl"), {"G.gd":
            'extends Node\nfunc f():\n\tif ResourceLoader.exists("res://assets/nothing.tres"):\n\t\tpass\n'})
        arm("  FLOOR: ResourceLoader.exists IS a consumer", run(p_good, rl)[0], BLOCK)

        # ---- cannot-evaluate is its own exit code, never a pass -----------------------------
        empty = write_src(os.path.join(d, "empty"), {"H.gd": 'extends Node\nfunc f():\n\tpass\n'})
        ec, out = run(p_good, empty)
        arm("a derivation of ZERO blocks (vacuity floor)", ec, CANNOT)
        arm("  ...and says the corpus collapsed", "ZERO load() consumers" in out, True)
        arm("an absent pack cannot evaluate", run(os.path.join(d, "no.pck"), png)[0], CANNOT)
        arm("an absent src dir cannot evaluate", run(p_good, os.path.join(d, "nosrc"))[0], CANNOT)
        bad = os.path.join(d, "bad.pck"); write_pack(bad, good, magic=b"XXXX")
        arm("a non-GDPC file cannot evaluate", run(bad, png)[0], CANNOT)
        enc = os.path.join(d, "enc.pck"); write_pack(enc, good, flags=1)
        ec, out = run(enc, png)
        arm("an ENCRYPTED directory cannot evaluate", ec, CANNOT)
        arm("  ...and says so rather than reading garbage", "ENCRYPTED" in out, True)

        # ---- THE PARTITION: every attempt lands in a bucket, and the buckets SUM ------------
        # ⛔ 403 of 478 attempts resolved on the real tree; the other 75 vanished from the
        # report. A green over a corpus that cannot say what it dropped reads as covering all
        # 478. Same defect as gate 3c's, same fix.
        part = write_src(os.path.join(d, "part"), {"P.gd":
            'extends Node\nfunc f(runtime_path):\n'
            '\tvar a = load("res://data/plain.json")\n'
            '\tvar b = load("user://mods/x.tres")\n'
            '\tvar c = load(runtime_path)\n'})
        ec, out = run(p_good, part)
        arm("an UNRESOLVABLE argument is counted, not dropped", "UNRESOLVABLE 1" in out, True)
        arm("  ...and a user:// path is counted out of scope", "user:// 1" in out, True)
        arm("  ...and it does not block on their account", ec, PASS)
        # PIN THE VALUE, NOT THE SPELLING. This used to assert bool(m) on a regex over
        # the line's prose, so it went red when a bucket was ADDED -- a correct change --
        # and would have stayed green if a bucket had reported the wrong number. Parse the
        # buckets and assert the arithmetic instead: they must sum to the attempts.
        m = re.search(r"resolution attempts (\d+) = res:// (\d+) . user:// (\d+) . "
                      r"uid:// (\d+) . other (\d+) . runtime-built (\d+) . UNRESOLVABLE (\d+)",
                      out)
        arm("  ...and the partition LINE is printed", bool(m), True)
        got = [int(x) for x in m.groups()] if m else [0, 1, 0, 0, 0, 0, 0]
        arm("  ...and its buckets SUM to the attempts", sum(got[1:]), got[0])

        # ⛔ THE CATCH-ALL WAS NAMED FOR ONE SCHEME. The final `else` filed EVERYTHING that
        # was not res:// under user:// -- the EXEMPT bucket, because user:// files are not
        # packed by design. A uid:// load is legal in Godot 4.4, is seen perfectly well
        # statically, and simply cannot be followed by this tool (it resolves through
        # .godot/uid_cache.bin, which this does not read). Filing it under a scheme it does
        # not have turned "I cannot check this" into "this needs no checking".
        # It measured 0 on the real tree, so only a malformed fixture ever reached it.
        sch = write_src(os.path.join(d, "sch"), {"S.gd":
            'extends Node\nfunc f():\n'
            '\n\tvar z = load("res://data/plain.json")\n'
            '\n\tvar a = load("user://saves/slot1.tres")\n'
            '\n\tvar b = load("uid://bges4odyxxuhl")\n'
            '\n\tvar c = load("assets/no_scheme_at_all.png")\n'})
        ec, out = run(p_good, sch)
        arm("a uid:// target gets its OWN bucket", "uid:// 1" in out, True)
        arm("  ...and a scheme-less target is 'other'", "other 1" in out, True)
        arm("  ...and user:// is STILL just the one", "user:// 1" in out, True)
        arm("  ...and both unfollowable sites are NAMED", out.count("CANNOT follow"), 1)
        arm("  ...naming uid by value", "uid://bges4odyxxuhl" in out, True)
        arm("  ...naming the scheme-less one by value",
            "assets/no_scheme_at_all.png" in out, True)
        arm("  ...and neither blocks the publish", ec, PASS)
        # THE DISCRIMINATING PARTNER: a real user:// path is exempt BY DESIGN and must not
        # be dragged into the uncertified list by the fix. Without this, moving everything
        # into "cannot follow" would pass every arm above.
        usr = write_src(os.path.join(d, "usr"), {"U.gd":
            'extends Node\nfunc f():\n\n\tvar z = load("res://data/plain.json")\n\n\tvar a = load("user://saves/slot1.tres")\n'})
        ec, out = run(p_good, usr)
        arm("a user:// path alone is NOT called unfollowable",
            "CANNOT follow" in out, False)
        arm("  ...and still does not block", ec, PASS)
        # ⛔ ARMING THE SUM CHECK ITSELF. It guards a state a healthy tool never produces, so
        # a mutation removing it left every arm green -- a guard nobody had watched say yes.
        # PARTITION_DRIFT_PROBE perturbs the attempt count by one; the check must then refuse.
        import os as _os
        _env = dict(_os.environ); _env["PARTITION_DRIFT_PROBE"] = "1"
        _r = subprocess.run([sys.executable, TOOL, p_good, "--src=" + png],
                            capture_output=True, text=True, env=_env)
        arm("a partition that does not SUM is REFUSED", _r.returncode, CANNOT)
        arm("  ...and says a site fell through",
            "partition does not sum" in (_r.stdout + _r.stderr), True)

        # ---- --quiet changes the volume, never the verdict ----------------------------------
        q_ec, q_out = run(p_orph, png, ["--quiet"])
        arm("--quiet keeps the verdict", q_ec, BLOCK)
        arm("  ...and still names the blocked asset", "hero.png" in q_out, True)

    print("\nselftest: %d passed, %d failed" % (passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
