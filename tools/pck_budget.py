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


# ── --predict <base-rev> <tip-rev>... [--base-pck <pck>] : a batch's web-pck delta BEFORE it folds ──────
# cowir-main 21216: every READY that adds textures or audio states its predicted web delta, and the fold
# refuses a batch that would take headroom under 8 MiB. One shared model instead of each lane's guess.
# Factors are MEASURED on real web pcks (packed bytes / master bytes), never modelled:
WEB_AUDIO_FACTOR = {
    'voice': 0.729,   # voice_* (not voice_blip_) + boss_line_*, through make_web_voice: .759 pck, 1028 clips
    'sfx':   1.071,   # every other sfx .ogg ships as-is plus container: .759 pck, 339 clips
    'music': 0.523,   # assets/audio/music through make_web_audio's 40 kbps tier: .759 pck, 161 tracks
}
# Godot's lossless .ctex vs PIL's lossless WebP of the same pixels: .760 backdrops 7,140,948 B vs 6.34 MiB.
TEXTURE_FACTOR = 1.07
# ACCURACY (cowir-adhoc 21266): +/-0.5 MiB per release hop, ~6% of a big delta, whichever is larger.
# Measured hop by hop on .754 -> .758 -> .759; a multi-hop total can look far better only because the
# hops' errors cancel. Fine for the 8 MiB floor; NOT for sub-MiB calls near it.
#
# MUSIC by DURATION, not by master bytes (cowir-music 21263: the average x0.523 overstated a 96k mono
# master ~2x, since the tier's ratio depends on each master's bitrate). Packed bytes per nominal byte
# (seconds x kbps x 1000/8), per tier: 40 -> 0.994 MEASURED (161 tracks, .759 pck 87.66 MiB vs 88.18
# nominal); 32 -> 1.092 = cowir-music's measured 32k encode 72.56 MiB x the 40k container 1.062, over
# 70.54 nominal, to be re-measured on the first 32k pck (.761). The tier is read from the TIP's own
# deploy_web.sh default. No duration (no local LFS object) or an unknown tier -> the average, said so.
MUSIC_PACKED_PER_NOMINAL = {40: 0.994, 32: 1.092}
IMAGE_EXT = ('.png', '.jpg', '.jpeg', '.webp')


def _blob(rev, path):
    import subprocess
    r = subprocess.run(["git", "cat-file", "-p", "%s:%s" % (rev, path)], capture_output=True)
    return r.stdout if r.returncode == 0 else None


def _lfs_size(b):
    m = re.match(rb"version https://git-lfs[^\n]*\noid [^\n]*\nsize (\d+)", b or b"")
    return int(m.group(1)) if m else None


def _lfs_object(b):
    """Local path of an LFS pointer's object, or None when it isn't a pointer or isn't fetched."""
    import subprocess
    m = re.match(rb"version https://git-lfs[^\n]*\noid sha256:([0-9a-f]{64})", b or b"")
    if not m:
        return None
    common = subprocess.run(["git", "rev-parse", "--git-common-dir"], capture_output=True, text=True).stdout.strip()
    oid = m.group(1).decode()
    p = os.path.join(common, "lfs", "objects", oid[:2], oid[2:4], oid)
    return p if os.path.isfile(p) else None


def _ogg_seconds(data):
    """Duration of an Ogg Vorbis stream: the last page's granule position / the id header's rate."""
    i = data.find(b"\x01vorbis")
    j = data.rfind(b"OggS")
    if i < 0 or j < 0 or len(data) < j + 14:
        return None
    rate = struct.unpack("<I", data[i + 12:i + 16])[0]
    gran = struct.unpack("<q", data[j + 6:j + 14])[0]
    return gran / float(rate) if rate and gran > 0 else None


def _tier_kbps(rev):
    b = _blob(rev, "tools/deploy_web.sh") or b""
    m = re.search(rb'WEB_AUDIO_KBPS="\$\{WEB_AUDIO_KBPS:-(\d+)\}"', b)
    return int(m.group(1)) if m else None


def _audio_kind(path):
    f = os.path.basename(path)
    if path.startswith("assets/audio/music/"):
        return 'music'
    if path.startswith("assets/audio/sfx/") and (f.startswith("boss_line_") or
                                                  (f.startswith("voice_") and not f.startswith("voice_blip_"))):
        return 'voice'
    return 'sfx'


def _web_excludes(cfg_text):
    """The Web preset's exclude_filter patterns, read from export_presets.cfg's own text."""
    for block in cfg_text.split("[preset.")[1:]:
        if 'platform="Web"' in block:
            m = re.search(r'exclude_filter="([^"]*)"', block)
            return [x.strip() for x in (m.group(1) if m else "").split(",") if x.strip()]
    return []


def _gdignored(path, has_gdignore):
    """True when any ancestor directory of path holds a .gdignore (Godot skips that whole subtree)."""
    parts = path.split("/")[:-1]
    return any(has_gdignore("/".join(parts[:i]) + "/.gdignore") for i in range(1, len(parts) + 1))


def _predict_cost(rev, path):
    b = _blob(rev, path)
    if b is None:
        return 0
    lfs = _lfs_size(b)
    low = path.lower()
    if low.endswith(IMAGE_EXT):
        if lfs is not None:
            return lfs           # an LFS image cannot be decoded from its pointer: raw bytes, flagged in the output
        try:
            from PIL import Image
        except ImportError:
            sys.exit("--predict needs pillow for textures: uv run --no-project --with pillow python tools/pck_budget.py --predict ...")
        import io
        im = Image.open(io.BytesIO(b)); im.load(); o = io.BytesIO(); im.save(o, "WEBP", lossless=True)
        return int(len(o.getvalue()) * TEXTURE_FACTOR)
    raw = lfs if lfs is not None else len(b)
    if low.endswith(".ogg"):
        kind = _audio_kind(path)
        if kind == 'music':
            kbps = _tier_kbps(rev)
            obj = _lfs_object(b)
            data = open(obj, "rb").read() if obj else (b if lfs is None else None)
            sec = _ogg_seconds(data) if data else None
            if sec and kbps in MUSIC_PACKED_PER_NOMINAL:
                return int(min(raw * 1.10, sec * kbps * 1000 / 8.0 * MUSIC_PACKED_PER_NOMINAL[kbps]))
            _MUSIC_FALLBACKS.append(path)
        return int(raw * WEB_AUDIO_FACTOR[kind])
    return raw


_MUSIC_FALLBACKS = []


def predict(base, tips, base_pck=None):
    import subprocess, fnmatch
    head = tips[-1]
    cfg = _blob(head, "export_presets.cfg")
    excl = _web_excludes(cfg.decode("utf-8", "replace") if cfg else "")
    cache = {}
    def has_gd(p):
        if p not in cache:
            cache[p] = subprocess.run(["git", "cat-file", "-e", "%s:%s" % (head, p)], capture_output=True).returncode == 0
        return cache[p]
    final = {}
    for t in tips:   # the LAST tip to touch a path decides its content, like a fold in this order
        out = subprocess.run(["git", "diff", "--name-status", "--no-renames", "%s...%s" % (base, t)],
                             capture_output=True, text=True).stdout
        for line in out.splitlines():
            st, p = line.split("\t", 1)
            final[p] = (st, t)
    by = collections.Counter(); skipped = collections.Counter(); n = 0
    for p, (st, t) in sorted(final.items()):
        if p.endswith((".import", ".uid")) or any(fnmatch.fnmatch(p, x) for x in excl):
            skipped["export exclude / sidecar"] += 1; continue
        if _gdignored(p, has_gd):
            skipped[".gdignore"] += 1; continue
        new = 0 if st == "D" else _predict_cost(t, p)
        old = _predict_cost(base, p)
        low = p.lower()
        k = ("textures" if low.endswith(IMAGE_EXT) else
             "audio:" + _audio_kind(p) if low.endswith(".ogg") else "other")
        by[k] += new - old; n += 1
    tot = sum(by.values())
    print("predict %s -> %s : %d shipped path(s) changed" % (base, " + ".join(tips), n))
    if _MUSIC_FALLBACKS:
        print("  note: %d music file(s) costed by the AVERAGE factor (no local LFS object or unknown tier): %s"
              % (len(_MUSIC_FALLBACKS), ", ".join(sorted(set(_MUSIC_FALLBACKS))[:3])))
    for k, v in sorted(by.items(), key=lambda kv: -abs(kv[1])):
        print("  %-14s %+9.2f MiB" % (k, v / 1048576.0))
    print("  %-14s %+9.2f MiB   (skipped: %s)" % ("TOTAL", tot / 1048576.0,
          ", ".join("%d %s" % (c, w) for w, c in skipped.items()) or "none"))
    if base_pck:
        size = os.path.getsize(base_pck) + tot
        print("  predicted web pck %.2f MiB · headroom %.2f MiB to %.2f (floor 8 MiB: %s)" % (
            size / 1048576.0, (PCK_LIMIT - size) / 1048576.0, PCK_LIMIT / 1048576.0,
            "OK" if PCK_LIMIT - size >= 8 * 1048576 else "UNDER, needs his say"))
    return tot


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
        # 9 — --predict's pure parts: audio routing, LFS pointer, the Web preset filter, .gdignore
        chk("predict: party voice -> voice tier", _audio_kind("assets/audio/sfx/voice_mage_hit_01.ogg"), 'voice')
        chk("predict: boss line -> voice tier", _audio_kind("assets/audio/sfx/boss_line_glacius_03.ogg"), 'voice')
        chk("predict: CONTROL voice_blip is NOT voice", _audio_kind("assets/audio/sfx/voice_blip_a.ogg"), 'sfx')
        chk("predict: music -> music tier", _audio_kind("assets/audio/music/town/harmonia.ogg"), 'music')
        chk("predict: LFS pointer size is read", _lfs_size(b"version https://git-lfs.github.com/spec/v1\noid sha256:ab\nsize 36820\n"), 36820)
        chk("predict: CONTROL a real ogg is not a pointer", _lfs_size(b"OggS\x00\x02" + b"\x00" * 40), None)
        cfg = '[preset.0]\nplatform="Linux"\nexclude_filter="a/*"\n[preset.1]\nplatform="Web"\nexclude_filter="docs/*, tmp/*"\n'
        chk("predict: the WEB preset's filter, not another's", _web_excludes(cfg), ["docs/*", "tmp/*"])
        g = {"voice_refs/.gdignore"}.__contains__
        chk("predict: a .gdignore'd subtree is skipped", _gdignored("voice_refs/x/y.wav", g), True)
        chk("predict: CONTROL an unignored path is kept", _gdignored("assets/sprites/a.png", g), False)
        # an Ogg: a vorbis id header (rate 48000) and a last page with granule 96000 -> 2.0 s
        idh = b"\x01vorbis" + struct.pack("<I", 0) + b"\x01" + struct.pack("<I", 48000) + b"\x00" * 20
        last = b"OggS\x00\x04" + struct.pack("<q", 96000) + b"\x00" * 20
        chk("predict: ogg duration = last granule / rate", _ogg_seconds(b"OggS" + b"\x00" * 24 + idh + last), 2.0)
        chk("predict: CONTROL not an ogg -> no duration", _ogg_seconds(b"RIFF" + b"\x00" * 60), None)
        chk("predict: CONTROL a non-pointer has no LFS object", _lfs_object(b"OggS..."), None)
    finally:
        shutil.rmtree(d, ignore_errors=True)
    print()
    print("selftest: %d passed, %d failed" % (p, f))
    return 0 if f == 0 else 1


if __name__ == '__main__':
    a = sys.argv[1:]
    if not a or a[0] in ('-h', '--help'):
        print(__doc__); print("usage: %s --summary <pck> | --cost <pck> <src>... | --predict <base> <tip>... [--base-pck <pck>] | --selftest"
                              % sys.argv[0]); sys.exit(2)
    if a[0] == '--selftest':
        sys.exit(selftest())
    if a[0] == '--summary' and len(a) == 2:
        summary(a[1]); sys.exit(0)
    if a[0] == '--cost' and len(a) >= 3:
        cost(a[1], a[2:]); sys.exit(0)
    if a[0] == '--predict':
        bp = None
        if '--base-pck' in a:
            i = a.index('--base-pck')
            if i + 1 >= len(a):
                sys.exit("--base-pck needs a path")
            bp = a[i + 1]; a = a[:i] + a[i + 2:]
        if len(a) < 3:   # was: counted before --base-pck was stripped, so no tip at all -> IndexError
            sys.exit("usage: --predict <base> <tip>... [--base-pck <pck>]  (at least one tip)")
        predict(a[1], a[2:], bp); sys.exit(0)
    print("usage: %s --summary <pck> | --cost <pck> <src>... | --predict <base> <tip>... [--base-pck <pck>] | --selftest" % sys.argv[0]); sys.exit(2)
