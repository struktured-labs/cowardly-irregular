#!/usr/bin/env python3
"""Does every asset the game reads AS RAW BYTES actually ship raw in the built pck?

WHY THIS EXISTS
---------------
On 2026-09-17 cowir-main found that World 2 through World 6 could not draw their overworld in
ANY exported build. `MapImageLoader.load_rows()` reads its map with
`FileAccess.get_file_as_bytes()`, which needs the ORIGINAL file inside the pack. Five of the six
map PNGs were configured `importer="texture"`, so only the imported artifact could ship:

    data/maps/overworld_w1.png        raw PRESENT   importer="keep"     -> map loads
    data/maps/overworld_w2..w6.png    raw ABSENT    importer="texture"  -> load_rows() -> []

Measured in a real shipped artifact (builds/web/index.pck, 2993 entries): `raw .png entries
outside .godot/ = 1`. One. The other five worlds had no map in the pack at all.

⛔ WHY NOTHING IN THE TREE COULD SEE IT, which is why this check is deploy-side.
The editor and the test suite both read `res://` straight off the working copy, where the PNG is
simply a file. `FileAccess.file_exists()` is TRUE there for all six. The defect does not exist
until the project is PACKED, so no arm in the repo could have failed however wide its corpus.

⛔ AND WHY IT IS NOT THE SAME CHECK AS AN `.import` LINTER.
A source-side guard asserts the `.import` DECLARATION says `keep`. This asserts the BYTES the
player actually receives. Those are different questions, and only the second is what ships: an
export preset's `exclude_filter`, a stale `.godot/`, or a resource the exporter never walked can
each drop a correctly-declared file. Verify the artifact, not the pointer.

HOW THE CORPUS IS DERIVED
-------------------------
Not a hand-written list -- a hand-written list would have had six entries and no way to grow.
Two levels, because the real defect spans two files:

  direct   a raw reader applied to a literal, or to a `const` in the same file
  one hop  a function whose PARAMETER reaches a raw reader is a SINK; every call to that
           function anywhere in src/ is then resolved at the sink's argument index

           MapImageLoader.load_rows(png_path, world_id)   <- param 0 reaches the reader
           SuburbanOverworld.gd:  load_rows(MAP_IMAGE, MAP_WORLD)
           SuburbanOverworld.gd:20  const MAP_IMAGE: String = "res://data/maps/overworld_w2.png"

The argument INDEX is load-bearing: `world_id` is param 1 and is not a path, and a res:// string
passed at a non-sink index is not a raw read. An index-blind version would check the wrong
argument and report on a corpus that is not the one it names.

⚠️ LIMITS, stated because a checker's silence is worth exactly what its corpus is worth.
Only literals and same-file `const`/`var` string initialisers resolve; a path built at runtime
(`"res://data/maps/overworld_w%d.png" % n`) is invisible here and always will be. Only one hop is
followed. This is why a derivation of ZERO BLOCKS rather than passes -- a corpus that collapsed
is the shape that certifies everything.

Usage:  tools/check_raw_assets_shipped.py <index.pck|binary> [--src=DIR] [--quiet]
        tools/check_raw_assets_shipped_selftest.py
Exit:   0 every raw-bytes asset ships raw · 5 at least one does not · 2 could not evaluate
"""
import os
import re
import struct
import sys

# The readers that need the ORIGINAL bytes. `load()`/`preload()`/`ResourceLoader` are deliberately
# absent: those resolve THROUGH the packed .import and are correct on an imported asset.
READER_RE = re.compile(r'(?:FileAccess\s*\.\s*)?(get_file_as_bytes|get_file_as_string|open)\s*\(')
FILEACCESS_OPEN_RE = re.compile(r'FileAccess\s*\.\s*open\s*\(')
# ⚠️ `\s*$` IS LOAD-BEARING. Without it this matched the FIRST OPERAND of an expression and
# reported the fragment as a path -- measured on the real tree, two false positives from one
# cause: `"res://data/cutscenes/" + filename` became the directory, and
# `"res://data/cutscenes/%s.json" % id` became a format template. Neither is a file, and both
# would have blocked a deploy over an asset that does not exist under that name.
CONST_RE = re.compile(
    r'^\s*(?:const|var)\s+([A-Za-z_]\w*)\s*(?::\s*[\w\.\[\],\s]+?\s*)?:?=\s*(["\'])(res://[^"\']+)\2\s*$')
FUNC_RE = re.compile(r'^\s*(?:static\s+)?func\s+([A-Za-z_]\w*)\s*\(([^)]*)\)')


def strip_comment(line):
    """Drop a trailing `#` comment without eating a `#` inside a string literal."""
    out, quote, i = [], None, 0
    while i < len(line):
        c = line[i]
        if quote:
            out.append(c)
            if c == "\\" and i + 1 < len(line):
                out.append(line[i + 1])
                i += 2
                continue
            if c == quote:
                quote = None
        elif c == "#":
            break
        else:
            if c in "\"'":
                quote = c
            out.append(c)
        i += 1
    return "".join(out)


def split_args(text):
    """Arguments of a call, given everything after its opening paren. Stops at the close."""
    args, cur, depth, quote = [], "", 0, None
    for ch in text:
        if quote:
            cur += ch
            if ch == quote:
                quote = None
            continue
        if ch in "\"'":
            quote = ch
            cur += ch
            continue
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            if depth == 0:
                break
            depth -= 1
        elif ch == "," and depth == 0:
            args.append(cur)
            cur = ""
            continue
        cur += ch
    args.append(cur)
    return [a.strip() for a in args]


def resolve(arg, consts):
    """A literal, or a same-file const naming one. Anything else is unresolvable, and says so."""
    m = re.fullmatch(r'(["\'])(.*)\1', arg)
    if m:
        return m.group(2)
    if re.fullmatch(r'[A-Za-z_]\w*', arg):
        return consts.get(arg)
    return None


def is_template(path):
    """A path no pck entry can equal: a runtime format string, or a directory. Neither present
    nor absent -- and silently dropping either is how a corpus shrinks with nobody noticing, so
    these are PRINTED as skipped rather than quietly removed."""
    return "%" in path or path.endswith("/")


def gd_files(src_dir):
    out = []
    for root, _dirs, files in os.walk(src_dir):
        for name in sorted(files):
            if name.endswith(".gd"):
                out.append(os.path.join(root, name))
    return sorted(out)


def read_lines(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return [strip_comment(ln) for ln in fh.read().splitlines()]
    except OSError:
        return []


def file_consts(lines):
    consts = {}
    for ln in lines:
        m = CONST_RE.match(ln)
        if m:
            consts[m.group(1)] = m.group(3)
    return consts


def reader_first_args(lines):
    """Every raw-reader call in these lines, as (line index, first argument text)."""
    hits = []
    for i, ln in enumerate(lines):
        for m in READER_RE.finditer(ln):
            if m.group(1) == "open" and not FILEACCESS_OPEN_RE.search(ln[:m.end()]):
                continue          # a bare `open(` is somebody else's method, not FileAccess
            args = split_args(ln[m.end():])
            if args:
                hits.append((i, args[0]))
    return hits


def find_sinks(files):
    """(function name -> set of parameter indices that reach a raw reader inside it)."""
    sinks = {}
    for path in files:
        lines = read_lines(path)
        defs = [(i, m) for i, ln in enumerate(lines) for m in [FUNC_RE.match(ln)] if m]
        for n, (start, m) in enumerate(defs):
            end = defs[n + 1][0] if n + 1 < len(defs) else len(lines)
            params = []
            for p in split_args(m.group(2) + ")"):
                p = re.split(r'[:=]', p, 1)[0].strip()
                if p:
                    params.append(p)
            body = lines[start + 1:end]
            for _i, arg in reader_first_args(body):
                if arg in params:
                    sinks.setdefault(m.group(1), set()).add(params.index(arg))
    return sinks


def derive(src_dir):
    """(res:// path -> sites), sinks, and a PARTITION of every resolution attempt.

    ⛔ THE PARTITION MUST SUM, and that is the point of it. This tool used to print
    "30 asset(s) read as raw bytes" while silently dropping every argument it could not
    resolve -- measured 2026-09-17: 38 of 77 attempts resolved to a res:// path and the
    other 39 vanished from the report. A floor on what was READ is not a floor on what
    reached the VERDICT; a corpus that cannot say what it dropped is a corpus you cannot
    size. Every attempt now lands in exactly one bucket and main() refuses if they do not
    add up.

    ⚠️ THE UNIT IS A RESOLUTION ATTEMPT, not a call site: the one-hop pass resolves one
    argument per (site, sink index), so a line calling two sinks contributes two. Stated
    here because the number is meaningless without it.
    """
    files = gd_files(src_dir)
    sinks = find_sinks(files)
    found = {}
    stats = {"res": 0, "user": 0, "template": 0, "unresolved": 0, "attempts": 0}

    def record(path, where):
        stats["attempts"] += 1
        if path is None:
            stats["unresolved"] += 1
        elif is_template(path):
            # Counted here AND still recorded: main() prints these as `skipped`, and a
            # template that vanishes from the per-asset roll is the silent drop this
            # partition exists to prevent. (Caught by this file's own arm, which went red
            # the moment the record stopped happening.)
            stats["template"] += 1
            found.setdefault(path, set()).add(where)
        elif path.startswith("res://"):
            stats["res"] += 1
            found.setdefault(path, set()).add(where)
        else:
            stats["user"] += 1

    for path in files:
        lines = read_lines(path)
        consts = file_consts(lines)
        rel = os.path.relpath(path)
        for i, arg in reader_first_args(lines):
            record(resolve(arg, consts), "%s:%d" % (rel, i + 1))
        for i, ln in enumerate(lines):
            if FUNC_RE.match(ln):
                continue          # the sink's own definition is not a call to it
            for fname, idxs in sinks.items():
                for m in re.finditer(r'(?:[A-Za-z_]\w*\s*\.\s*)?\b%s\s*\(' % re.escape(fname), ln):
                    args = split_args(ln[m.end():])
                    for idx in idxs:
                        if idx < len(args):
                            record(resolve(args[idx], consts), "%s:%d" % (rel, i + 1))
    return found, sinks, stats


def _pack_start(f):
    """Byte offset of the GDPC header: 0 for a .pck, or the embedded pack inside an executable.

    ⛔ THE DESKTOP CHANNELS DO NOT SHIP A .pck AT ALL. export_presets.cfg sets
    `binary_format/embed_pck=true` for Linux and Windows, so the pack is appended to the
    executable and the only .pck on disk belongs to web. A checker that reads .pck files
    covers ONE of the three channels this lane publishes, and reports nothing about two.

    Godot writes a 12-byte footer at the very end: [u64 embedded block size][u32 "GDPC"].
    Measured against both real artifacts (godot 4.4.1, pack format v2):
        cowardly-irregular.x86_64  312,010,384 B  pack at n-ds-12 = 69,688,024   2758 entries
        cowardly-irregular.exe     344,062,096 B  pack at n-ds-12 = 97,520,128   2956 entries
    """
    f.seek(0, 2)
    n = f.tell()
    f.seek(0)
    if f.read(4) == b"GDPC":
        return 0                                   # a standalone .pck
    if n < 12:
        raise ValueError("too small to be a pack or to carry one")
    f.seek(n - 4)
    if f.read(4) != b"GDPC":
        raise ValueError("no GDPC at the head, and no GDPC footer at the tail — this file "
                         "neither is a pack nor carries one")
    f.seek(n - 12)
    ds = struct.unpack("<Q", f.read(8))[0]
    start = n - ds - 12
    # VERIFY the footer actually locates a header rather than trusting the size it declares.
    # A truncated or rewritten binary keeps its tail magic and points nowhere.
    if start < 0 or start > n - 4:
        raise ValueError("embedded pack size %d does not fit in a %d-byte file" % (ds, n))
    f.seek(start)
    if f.read(4) != b"GDPC":
        raise ValueError("the footer declares a %d-byte pack, but there is no GDPC header at "
                         "offset %d — the file is truncated or the pack was rewritten"
                         % (ds, start))
    return start


def pck_table(path):
    """(base, {packed path: (offset, size)}) for a .pck or an embedded pack.

    ⛔ `base` IS NOT OPTIONAL AND IS NOT THE PACK START. Format v2 carries a `file_base` field
    and EVERY entry offset is relative to it, so an entry's bytes live at
    pack_start + file_base + offset. Measured against both real artifacts, with the wrong
    combinations kept as the control:

        builds/web/index.pck        packstart 0          file_base 286,288
          off+file_base             [remap] importer="oggvorbisstr"      ✅
          off+packstart             binary garbage                      ⛔
        cowardly-irregular.x86_64   packstart 69,688,024 file_base 262,408
          off+file_base             x86 instructions                    ⛔  <- the tell
          off+file_base+packstart   [remap] importer="oggvorbisstr"     ✅

    The .pck case cannot distinguish the right formula from one wrong one, because its pack
    start is 0. Only the embedded artifact separates them.

    Raises on anything it cannot honestly enumerate.
    """
    f = open(path, "rb")
    start = _pack_start(f)
    f.seek(start + 4)
    ver = struct.unpack("<I", f.read(4))[0]
    f.read(12)                                               # godot major/minor/patch
    file_base = 0
    if ver >= 2:
        flags = struct.unpack("<I", f.read(4))[0]
        if flags & 1:
            raise ValueError("the pack directory is ENCRYPTED; its file table cannot be read, "
                             "so this check cannot certify anything about it")
        file_base = struct.unpack("<Q", f.read(8))[0]
    f.read(16 * 4)                                           # reserved
    n = struct.unpack("<I", f.read(4))[0]
    out = {}
    for _ in range(n):
        ln = struct.unpack("<I", f.read(4))[0]
        nm = f.read(ln).rstrip(b"\0").decode("utf-8", "replace")
        off, size = struct.unpack("<QQ", f.read(16))
        f.read(16)                                           # md5
        if ver >= 2:
            f.read(4)                                        # per-file flags
        out[nm] = (off, size)
    if len(out) == 0 and n != 0:
        raise ValueError("file table declared %d entries and yielded none" % n)
    return f, start + file_base, out


def pck_read(f, base, entry):
    """The bytes of one packed entry. entry is the (offset, size) pair from pck_table."""
    off, size = entry
    f.seek(base + off)
    return f.read(size)


def pck_entries(path):
    """Every path inside a Godot pack, whether a .pck or embedded in an executable."""
    f, _base, table = pck_table(path)
    f.close()
    return set(table)


def main(argv):
    opts = dict(a[2:].split("=", 1) for a in argv if a.startswith("--") and "=" in a)
    flags = [a for a in argv if a.startswith("--") and "=" not in a]
    args = [a for a in argv if not a.startswith("--")]
    if len(args) != 1:
        print("usage: check_raw_assets_shipped.py <pack|executable> [--src=DIR] [--quiet]",
              file=sys.stderr)
        return 2
    pck, src, quiet = args[0], opts.get("src", "src"), "--quiet" in flags

    if not os.path.isfile(pck):
        print("[raw] BLOCKED: %s does not exist. A check that cannot read its subject is not a "
              "passing one." % pck, file=sys.stderr)
        return 2
    if not os.path.isdir(src):
        print("[raw] BLOCKED: %s is not a directory -- the consumer list cannot be derived, so "
              "there is nothing to certify." % src, file=sys.stderr)
        return 2
    try:
        entries = pck_entries(pck)
    except Exception as exc:                                  # noqa: BLE001
        print("[raw] BLOCKED: could not read %s: %s" % (pck, exc), file=sys.stderr)
        return 2

    all_found, sinks, stats = derive(src)
    templates = sorted(p for p in all_found if is_template(p))
    consumers = {p: v for p, v in all_found.items() if not is_template(p)}
    if not consumers:
        # The vacuity floor. This is a control against the derivation collapsing, NOT a claim of
        # completeness: it only proves the corpus is non-empty, never that it is the whole set.
        print("[raw] BLOCKED: derived ZERO raw-bytes assets from %s/. Either the readers were "
              "renamed or the derivation broke; both mean a PASS here would be a sweep over "
              "nothing." % src, file=sys.stderr)
        return 2

    missing = [(p, sorted(consumers[p])) for p in sorted(consumers)
               if p[len("res://"):] not in entries]

    for res_path, where in missing:
        print("[raw] BLOCKED: %s is read AS RAW BYTES but does NOT ship raw." % res_path,
              file=sys.stderr)
        print("[raw]   read at: %s" % ", ".join(where), file=sys.stderr)
        print("[raw]   the pack can only carry its imported artifact, which a FileAccess read "
              "cannot use -- the call returns empty and the caller sees a missing file.",
              file=sys.stderr)
        print("[raw]   fix: set importer=\"keep\" in %s.import and re-import." %
              res_path[len("res://"):], file=sys.stderr)

    if not quiet:
        for res_path in sorted(consumers):
            state = "MISSING" if res_path[len("res://"):] not in entries else "ships raw"
            print("[raw]   %-9s %s" % (state, res_path))
        for res_path in templates:
            print("[raw]   %-9s %s  (built at runtime -- outside what this can check)"
                  % ("skipped", res_path))
    # ⛔ THE PARTITION MUST ACCOUNT FOR EVERY ATTEMPT. A bucket that stops being reachable,
    # or a new branch that forgets to record, shows up here as a mismatch rather than as a
    # quietly smaller corpus.
    # A test-only seam. The sum check guards a state a healthy tool never produces, so
    # without this it is a guard nobody has watched say yes -- measured: removing the check
    # left every arm green. Same shape as this lane's BUTLER= and SEED_REAL_BASE= seams.
    if os.environ.get("PARTITION_DRIFT_PROBE"):
        stats["attempts"] += 1
    _sum = stats["res"] + stats["user"] + stats["template"] + stats["unresolved"]
    if _sum != stats["attempts"]:
        print("[raw] BLOCKED: the partition does not sum — %d attempt(s), %d bucketed. A site "
              "fell through, so the corpus this reports is not the one it read."
              % (stats["attempts"], _sum), file=sys.stderr)
        return 2
    print("[raw] resolution attempts %d = res:// %d · user:// %d · runtime-built %d · "
          "UNRESOLVABLE %d" % (stats["attempts"], stats["res"], stats["user"],
                               stats["template"], stats["unresolved"]))
    print("[raw]   UNRESOLVABLE means a path this cannot see statically (a parameter, or a "
          "string built at runtime). It is NOT a pass for those sites.")
    print("[raw] %d pck entries · %d sink function(s) · %d asset(s) read as raw bytes · "
          "%d ship raw · %d MISSING · %d skipped as runtime-built"
          % (len(entries), len(sinks), len(consumers), len(consumers) - len(missing),
             len(missing), len(templates)))
    return 5 if missing else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))