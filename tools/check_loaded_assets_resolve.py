#!/usr/bin/env python3
"""Does every asset the game LOADS have something in the pack that can serve it?

WHY THIS EXISTS — IT IS THE MIRROR OF check_raw_assets_shipped.py, AND THE TWO DISAGREE
--------------------------------------------------------------------------------------
Those two tools ask opposite questions about the same setting, and the same one-word edit is
correct for one and fatal for the other:

    FileAccess.get_file_as_bytes(p)   needs the ORIGINAL bytes   -> importer="keep"   REQUIRED
    load(p) / preload(p)              needs the IMPORTED artifact -> importer="keep"  FATAL

`keep` produces no imported artifact, so a sheet set to `keep` returns null from `load()`,
`HybridSpriteLoader` falls back to procedural, and the character still draws — the failure is
silent and looks like art that was never made. Six files carry `keep` today and all six are the
overworld maps, which are read as raw bytes and must. If anyone ever "fixes" a sprite the way
the maps were fixed, this is what reds. (cowir-sprites built the source-side half against
sprite_manifest.json; this one verifies the ARTIFACT, for every load() consumer in src/.)

⛔ WHY IT HAS TO READ BYTES AND NOT JUST THE FILE TABLE.
An imported asset does not resolve by name. The pack carries `foo.png.import`, a text file whose
`path=` names the real artifact under `.godot/imported/`, and `load("res://foo.png")` follows it.
A `.tscn` or `.gd` resolves through a `.remap` the same way. So "is foo.png in the pack" is the
wrong question twice over: the raw file is usually ABSENT for a healthy imported asset, and
PRESENT-but-unloadable for a `keep` one. The pointer has to be followed to the artifact.

Measured against the real shipped web pck, 186 load() consumers derived from src/:
    remap -> artifact PRESENT   175      .gd and .tscn
    direct entry                  3
    import -> artifact PRESENT    2
    nothing serves it             6      ALL added after that pck was built — stale subject,
                                         not a defect. Dated before believing.

Usage:  tools/check_loaded_assets_resolve.py <pack|executable> [--src=DIR] [--quiet]
        tools/check_loaded_assets_resolve_selftest.py
Exit:   0 every loaded asset resolves · 5 at least one does not · 2 could not evaluate
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import check_raw_assets_shipped as raw                        # noqa: E402

# `load`/`preload` must not match `.load(` on some other object, so a preceding word char or dot
# disqualifies the bare forms. ResourceLoader.exists() is included deliberately: a caller that
# asks exists() before load() is making the same demand of the pack.
LOADER_RE = re.compile(r'(?:ResourceLoader\s*\.\s*(?:load|exists)|(?<![\w.])(?:pre)?load)\s*\(')
# `path="res://..."` and its per-platform variants (`path.s3tc=`, `path.etc2=`) inside a packed
# .import or .remap. Anchored to the line start: a `path=` inside a quoted value is not a key.
PATH_RE = re.compile(rb'^path(?:\.[\w]+)?="([^"]+)"', re.M)


def loader_consumers(src_dir):
    """res:// path -> set of 'file:line' sites that LOAD it. Derived, never listed."""
    found = {}
    for path in raw.gd_files(src_dir):
        lines = raw.read_lines(path)
        consts = raw.file_consts(lines)
        rel = os.path.relpath(path)
        for i, ln in enumerate(lines):
            for m in LOADER_RE.finditer(ln):
                args = raw.split_args(ln[m.end():])
                if not args:
                    continue
                v = raw.resolve(args[0], consts)
                if v and v.startswith("res://") and not raw.is_template(v):
                    found.setdefault(v, set()).add("%s:%d" % (rel, i + 1))
    return found


def _targets(blob):
    return [t.decode("utf-8", "replace")[len("res://"):] if t.startswith(b"res://")
            else t.decode("utf-8", "replace") for t in PATH_RE.findall(blob)]


def resolve_in_pack(f, base, table, res_path):
    """How the pack serves load(res_path): (verdict, detail). verdict None means it cannot."""
    inside = res_path[len("res://"):]
    for sidecar, kind in ((inside + ".import", "import"), (inside + ".remap", "remap")):
        if sidecar in table:
            tgts = _targets(raw.pck_read(f, base, table[sidecar]))
            if not tgts:
                # An .import with no path= is a `keep` asset: the raw file ships and there is no
                # imported artifact. Correct for a raw-bytes reader, fatal for load().
                return None, ('%s carries no path= — it is importer="keep", so the pack has no '
                              "imported artifact and load() returns null" % sidecar)
            present = [t for t in tgts if t in table]
            if present:
                return kind, present[0]
            return None, ("%s points at %s, which is NOT in the pack"
                          % (sidecar, ", ".join(tgts)))
    if inside in table:
        return "direct", inside
    return None, "no entry, no .import and no .remap — nothing in the pack can serve it"


def main(argv):
    opts = dict(a[2:].split("=", 1) for a in argv if a.startswith("--") and "=" in a)
    flags = [a for a in argv if a.startswith("--") and "=" not in a]
    args = [a for a in argv if not a.startswith("--")]
    if len(args) != 1:
        print("usage: check_loaded_assets_resolve.py <pack|executable> [--src=DIR] [--quiet]",
              file=sys.stderr)
        return 2
    pack, src, quiet = args[0], opts.get("src", "src"), "--quiet" in flags

    if not os.path.isfile(pack):
        print("[load] BLOCKED: %s does not exist. A check that cannot read its subject is not a "
              "passing one." % pack, file=sys.stderr)
        return 2
    if not os.path.isdir(src):
        print("[load] BLOCKED: %s is not a directory -- the consumer list cannot be derived." % src,
              file=sys.stderr)
        return 2
    try:
        f, base, table = raw.pck_table(pack)
    except Exception as exc:                                  # noqa: BLE001
        print("[load] BLOCKED: could not read %s: %s" % (pack, exc), file=sys.stderr)
        return 2

    consumers = loader_consumers(src)
    if not consumers:
        # The vacuity floor: a derivation that collapsed certifies everything.
        print("[load] BLOCKED: derived ZERO load() consumers from %s/. Either the readers were "
              "renamed or the derivation broke; a PASS here would be a sweep over nothing." % src,
              file=sys.stderr)
        f.close()
        return 2

    kinds, broken = {}, []
    for res_path in sorted(consumers):
        kind, detail = resolve_in_pack(f, base, table, res_path)
        if kind is None:
            broken.append((res_path, detail, sorted(consumers[res_path])))
        kinds[kind or "UNRESOLVED"] = kinds.get(kind or "UNRESOLVED", 0) + 1
    f.close()

    for res_path, detail, where in broken:
        print("[load] BLOCKED: %s is LOADED but the pack cannot serve it." % res_path,
              file=sys.stderr)
        print("[load]   loaded at: %s" % ", ".join(where), file=sys.stderr)
        print("[load]   %s" % detail, file=sys.stderr)

    if not quiet:
        for k in sorted(kinds):
            print("[load]   %-24s %d" % (k, kinds[k]))
    print("[load] %d pack entries · %d asset(s) loaded · %d resolve · %d BROKEN"
          % (len(table), len(consumers), len(consumers) - len(broken), len(broken)))
    return 5 if broken else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
