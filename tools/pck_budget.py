#!/usr/bin/env python3
"""Read a Godot 4 .pck's own file table and answer budget questions about it.

WHY THIS IS IN THE REPO
-----------------------
Every figure this lane put on struktured's web-size decision came from throwaway scripts in a
gitignored tmp/ directory: the 160.00 MiB browser cache line, the 6.94 MiB cost of the seven
ambient beds, the 3.14 MiB unreachable-art tranche. Four lanes cite those numbers and nobody but
this session could re-derive or check them. Same defect as the detached .ec and the store
read-back verdict, both already fixed: the instrument behind a decision was not in the record.

TWO MISTAKES THIS TOOL EXISTS TO NOT REPEAT
-------------------------------------------
1. DO NOT join imported artifacts to sources BY BASENAME. The pck stores imports as
   `.godot/imported/<basename>-<32 hex>.<ext>` with the directory erased, and `attack.png` /
   `idle.png` each live in ~20 directories. A basename join reported 1.89 MiB where the truth
   was 0.14 MiB -- 13x too high. The hash is md5("res://" + source path), confirmed against four
   independently-resolved pairs; that is exact and collision-free.
2. COUNT ALL THREE COMPONENTS. Removing a source drops its imported artifact AND its packed
   `.import` entry AND the index record of each (4B path-len + path + 8B offset + 8B size +
   16B md5 + 4B flags = 40 + len(path)). Counting only the first understated the ambient tranche
   by 2,718 B and the sprite tranche by 3,520 B -- and at one point that was larger than the
   whole remaining margin, which would have published "the plan is dead" when it was not.

THE CACHE LINE is not an itch limit. Measured 2026-09-11/12 on chromium, at default and at 2 GB
disk cache: a single resource of 167,772,160 B is served FROM CACHE on reload and anything
larger is re-fetched. A synthetic random file at exactly the pck's size behaves identically, so
it is size -- not the pck, not Godot's XHR loader. index.wasm (43.7 MiB) caching in the same run
is the control proving the measurement can see a cache hit at all. Chromium-family only;
Firefox and Safari are NOT measured.
"""
import struct, sys, os, hashlib, re, collections

CACHE_LINE = 167772160          # measured, see module docstring
PCK_WARN   = 180000000          # deploy_web.sh
PCK_LIMIT  = 199000000          # itch refuses an HTML5 embed at/above 200 MB

IMPORTED = re.compile(r'^\.godot/imported/(?P<base>.+?)-[0-9a-f]{32}\.(?P<ext>[a-z0-9]+)$')


def parse(path):
    """Entries as (res-relative path, size). Raises rather than returning a short list."""
    with open(path, 'rb') as f:
        if f.read(4) != b'GDPC':
            raise SystemExit("pck_budget: not a pck (bad magic): %s" % path)
        pack_format, vmaj, vmin, vpat = struct.unpack('<IIII', f.read(16))
        if pack_format >= 2:
            struct.unpack('<I', f.read(4))          # flags
            struct.unpack('<Q', f.read(8))          # file base
        f.read(16 * 4)                              # reserved
        (count,) = struct.unpack('<I', f.read(4))
        out = {}
        for _ in range(count):
            (plen,) = struct.unpack('<I', f.read(4))
            p = f.read(plen).rstrip(b'\x00').decode('utf-8', 'replace')
            off, size = struct.unpack('<QQ', f.read(16))
            f.read(16)
            if pack_format >= 2:
                struct.unpack('<I', f.read(4))
            out[p.replace('res://', '')] = size
    if len(out) != count:
        raise SystemExit("pck_budget: header says %d entries, parsed %d" % (count, len(out)))
    return out, count, (vmaj, vmin, vpat)


def index_record_bytes(path):
    """What the pck's own table spends on one entry."""
    return 40 + len(path)


def artifact_for(sizes, src):
    """The imported artifact for a source path, by DERIVATION not basename."""
    h = hashlib.md5(("res://" + src).encode()).hexdigest()
    pref = ".godot/imported/%s-%s." % (os.path.basename(src), h)
    for q in sizes:
        if q.startswith(pref):
            return q
    return None


def removal_cost(sizes, srcs):
    """Exact bytes the pck loses if these sources are removed. Unresolved are NAMED."""
    art = imp = idx = 0
    rows, missing = [], []
    for src in srcs:
        a = artifact_for(sizes, src)
        if a is None:
            missing.append(src)
            continue
        art += sizes[a]; idx += index_record_bytes(a)
        i_sz = 0
        imp_path = src + ".import"
        if imp_path in sizes:
            i_sz = sizes[imp_path]
            imp += i_sz; idx += index_record_bytes(imp_path)
        rows.append((src, sizes[a], i_sz))
    return dict(artifact=art, imports=imp, index=idx,
                total=art + imp + idx, rows=rows, missing=missing)


def summary(pck):
    sizes, count, godot = parse(pck)
    fsz = os.path.getsize(pck)
    total = sum(sizes.values())
    print("pck            %s" % pck)
    print("godot          %d.%d.%d · %d entries" % (godot[0], godot[1], godot[2], count))
    print("file size      %d B = %.2f MiB" % (fsz, fsz / 1048576))
    print("entries sum    %d B = %.2f MiB (%.1f%% of the file)"
          % (total, total / 1048576, 100.0 * total / fsz))
    if total > fsz:
        raise SystemExit("pck_budget: entries exceed the file — parse is wrong")
    if total < fsz * 0.80:
        raise SystemExit("pck_budget: entries account for <80% of the file — parse is suspect")
    groups = collections.defaultdict(lambda: [0, 0])
    for p, s in sizes.items():
        m = IMPORTED.match(p)
        if m:
            ext = m.group('ext')
            k = {'oggvorbisstr': 'audio (imported)', 'sample': 'audio (imported)',
                 'ctex': 'textures (imported)', 'stex': 'textures (imported)',
                 'fontdata': 'fonts (imported)'}.get(ext, 'other (imported) .%s' % ext)
        else:
            parts = p.split('/')
            k = '%s/%s (raw)' % (parts[0], parts[1]) if len(parts) > 1 else p
        groups[k][0] += 1
        groups[k][1] += s
    print()
    print("%-34s %6s %14s %9s" % ("CATEGORY", "FILES", "BYTES", "MiB"))
    for k, (n, b) in sorted(groups.items(), key=lambda kv: -kv[1][1]):
        print("%-34s %6d %14d %9.2f" % (k, n, b, b / 1048576))
    print()
    over = fsz - CACHE_LINE
    if over > 0:
        print("CACHE: OVER the browser cache line by %.2f MiB — a returning web player"
              " re-downloads %.2f MiB every visit." % (over / 1048576, fsz / 1048576))
    else:
        print("CACHE: under the browser cache line with %.2f MiB spare." % (-over / 1048576))
    print("       cacheable at or below %.2f MiB (%d B), measured on chromium."
          % (CACHE_LINE / 1048576, CACHE_LINE))
    if fsz >= PCK_LIMIT:
        print("       itch: AT OR OVER the %.2f MiB embed limit." % (PCK_LIMIT / 1048576))
    elif fsz >= PCK_WARN:
        print("       itch: within %.2f MiB of the embed limit." % ((PCK_LIMIT - fsz) / 1048576))


def cost(pck, srcs):
    sizes, _, _ = parse(pck)
    r = removal_cost(sizes, srcs)
    print("%-56s %11s %8s" % ("SOURCE", "ARTIFACT", "IMPORT"))
    for src, a, i in r['rows']:
        print("%-56s %11d %8d" % (src[-56:], a, i))
    for m in r['missing']:
        print("UNRESOLVED (not counted): %s" % m)
    print("-" * 78)
    print("%-56s %11d" % ("imported artifacts", r['artifact']))
    print("%-56s %11d" % ("packed .import entries", r['imports']))
    print("%-56s %11d" % ("index records", r['index']))
    print("%-56s %11d B = %.4f MiB" % ("TOTAL REMOVED", r['total'], r['total'] / 1048576))
    fsz = os.path.getsize(pck)
    print()
    print("pck %d B · after removal %d B · margin to the cache line %+d B"
          % (fsz, fsz - r['total'], CACHE_LINE - (fsz - r['total'])))
    if r['missing']:
        raise SystemExit("pck_budget: %d source(s) unresolved — the total is a FLOOR, not the answer"
                         % len(r['missing']))


# ── selftest ─────────────────────────────────────────────────────────────────────────────
def _write_pck(path, entries):
    """Minimal GDPC writer, used ONLY by the selftest to build a pck with known contents."""
    blobs, table = b'', b''
    for p, payload in entries:
        raw = p.encode()
        table += struct.pack('<I', len(raw)) + raw
        table += struct.pack('<QQ', len(blobs), len(payload)) + b'\x00' * 16 + struct.pack('<I', 0)
        blobs += payload
    head = b'GDPC' + struct.pack('<IIII', 2, 4, 4, 1) + struct.pack('<I', 0) \
        + struct.pack('<Q', 0) + b'\x00' * 64 + struct.pack('<I', len(entries))
    with open(path, 'wb') as f:
        f.write(head + table + blobs)


def selftest():
    import tempfile, shutil
    p = f = 0
    def chk(name, got, want):
        nonlocal p, f
        if got == want:
            p += 1; print("  ok    %-52s %s" % (name, got))
        else:
            f += 1; print("  FAIL  %-52s got %r want %r" % (name, got, want))

    d = tempfile.mkdtemp(prefix="pckbudget.", dir=os.path.join(os.getcwd(), "tmp")
                         if os.path.isdir(os.path.join(os.getcwd(), "tmp")) else None)
    try:
        src_a = "assets/x/one.png"
        src_b = "assets/y/one.png"          # SAME basename, different directory
        src_c = "assets/z/lonely.png"       # artifact but no .import
        ha = hashlib.md5(("res://" + src_a).encode()).hexdigest()
        hb = hashlib.md5(("res://" + src_b).encode()).hexdigest()
        hc = hashlib.md5(("res://" + src_c).encode()).hexdigest()
        art_a = ".godot/imported/one.png-%s.ctex" % ha
        art_b = ".godot/imported/one.png-%s.ctex" % hb
        art_c = ".godot/imported/lonely.png-%s.ctex" % hc
        pck = os.path.join(d, "t.pck")
        _write_pck(pck, [
            (art_a, b'A' * 1000), (src_a + ".import", b'i' * 100),
            (art_b, b'B' * 7000), (src_b + ".import", b'i' * 100),
            (art_c, b'C' * 500),
        ])
        sizes, count, _ = parse(pck)
        chk("parses every declared entry", len(sizes), 5)
        chk("sizes are the real payload sizes", sizes[art_b], 7000)

        # 1/2 — the collision the basename join got wrong. Same basename, different source:
        #       each must resolve to ITS OWN artifact, not whichever was found first.
        chk("colliding basename resolves to its own artifact (a)", artifact_for(sizes, src_a), art_a)
        chk("colliding basename resolves to its own artifact (b)", artifact_for(sizes, src_b), art_b)
        chk("…and the two differ", artifact_for(sizes, src_a) != artifact_for(sizes, src_b), True)

        # 3 — all three components, computed by hand
        want = 1000 + 100 + index_record_bytes(art_a) + index_record_bytes(src_a + ".import")
        chk("cost counts artifact + import + both index records",
            removal_cost(sizes, [src_a])['total'], want)
        # 4 — a source with no .import counts the artifact and ONE index record
        chk("no .import -> artifact + one index record",
            removal_cost(sizes, [src_c])['total'], 500 + index_record_bytes(art_c))
        # 5 — an unresolvable source is NAMED, never silently zero
        r = removal_cost(sizes, ["assets/nope/ghost.png"])
        chk("unresolved source is reported", r['missing'], ["assets/nope/ghost.png"])
        chk("…and contributes nothing rather than guessing", r['total'], 0)
        # 6 — index record arithmetic is the documented formula
        chk("index record = 40 + len(path)", index_record_bytes("ab"), 42)

        # 7 — the derivation against a REAL pair resolved independently from a staging tree
        chk("md5 derivation matches a real resolved pair",
            hashlib.md5(b"res://assets/sprites/weapons/bronze_sword/attack.png").hexdigest(),
            "d08f44f7ba587a731bf7d6adcf3a3144")

        # 8 — a non-pck is refused rather than parsed into nonsense
        bad = os.path.join(d, "bad.pck")
        open(bad, 'wb').write(b'NOPE' + b'\x00' * 100)
        try:
            parse(bad); chk("non-pck is refused", "parsed", "SystemExit")
        except SystemExit:
            chk("non-pck is refused", "SystemExit", "SystemExit")
    finally:
        shutil.rmtree(d, ignore_errors=True)
    print()
    print("selftest: %d passed, %d failed" % (p, f))
    return 0 if f == 0 else 1


if __name__ == '__main__':
    a = sys.argv[1:]
    if not a or a[0] in ('-h', '--help'):
        print(__doc__); print("usage: %s --summary <pck> | --cost <pck> <src>... | --selftest"
                              % sys.argv[0]); sys.exit(2)
    if a[0] == '--selftest':
        sys.exit(selftest())
    if a[0] == '--summary' and len(a) == 2:
        summary(a[1]); sys.exit(0)
    if a[0] == '--cost' and len(a) >= 3:
        cost(a[1], a[2:]); sys.exit(0)
    print("usage: %s --summary <pck> | --cost <pck> <src>... | --selftest" % sys.argv[0]); sys.exit(2)
