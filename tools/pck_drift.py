#!/usr/bin/env python3
"""Read the pck size series out of the publish archive, instead of retyping it.

WHY THIS IS IN THE REPO
-----------------------
This lane publishes a pck drift series every release — byte count, delta, margin to the browser
cache line. It was a hand-maintained Python list, retyped into each report. At v3.33.319-alpha I
wrote a figure from the TREND rather than the log and published 175,030,752 where the artifact
said 175,029,856; it was recoverable only because the chain's own `index.pck` line is archived.
A series assembled by hand is a series that can be wrong in a way no control catches.

⛔ TWO LOG FORMATS, AND ONLY ONE IS A BYTE COUNT
    v3.33.312+  index.pck: 166.94 MiB (175.1 MB decimal, 175054352 bytes)   EXACT
    earlier     index.pck: 166 MB                                           IMPRECISE

The older line divides by 1048576 and labels the result MB — a MiB value wearing an MB label,
which is the defect `pck_cache_report.sh` was written to fix. Reading `166` as anything but a
±1 MiB approximation reproduces the error that made this lane publish 13.4 MiB of headroom where
there was 4.8. So an imprecise entry is REPORTED AS SUCH and never converted, never differenced,
and never used for a margin.

Usage:  tools/pck_drift.py --series <archive-dir>
        tools/pck_drift.py --selftest
"""
import sys, os, re

CACHE_LINE = 167772160

EXACT = re.compile(r'index\.pck:\s*[\d.]+\s*MiB\s*\([\d.]+\s*MB decimal,\s*(\d+)\s*bytes\)')
OLD   = re.compile(r'index\.pck:\s*(\d+)\s*MB\s*$', re.M)   # re.M: the line is mid-file, not at EOF
TAG   = re.compile(r'^v(\d+)\.(\d+)\.(\d+)(?:-(.+))?$')


def tag_key(t):
    """Numeric ordering. Lexically 'v3.33.320' sorts BEFORE 'v3.33.9', which would
    silently reorder the whole series and make every delta meaningless."""
    m = TAG.match(t)
    if not m:
        # Real archives hold non-tag directories (rel-<sha> from the pre-tag era). Sort them
        # first, by name, rather than dereferencing a match that is not there — the crash this
        # replaces was invisible to a fixture set containing only well-formed tags.
        return (0, t, 0, 0)
    return (1, int(m.group(1)), int(m.group(2)), int(m.group(3)))


def scan(archive):
    """{tag: (bytes|None, 'exact'|'imprecise'|'absent')} — never silently omits a tag."""
    if not os.path.isdir(archive):
        raise SystemExit("pck_drift: no such archive directory: %s" % archive)
    out = {}
    for tag in sorted(os.listdir(archive), key=tag_key):
        d = os.path.join(archive, tag)
        if not os.path.isdir(d):
            continue
        found = None
        state = 'absent'
        for fn in sorted(os.listdir(d)):
            if not fn.endswith('.log'):
                continue
            try:
                body = open(os.path.join(d, fn), encoding='utf-8', errors='replace').read()
            except OSError:
                continue
            m = EXACT.search(body)
            if m:
                found, state = int(m.group(1)), 'exact'
                break
            if state != 'imprecise' and OLD.search(body):
                state = 'imprecise'
        out[tag] = (found, state)
    if not out:
        raise SystemExit("pck_drift: %s holds no tag directories — nothing measured" % archive)
    return out


def series(archive):
    rows = scan(archive)
    print("%-22s %14s %10s %12s  %s" % ("TAG", "BYTES", "DELTA", "MARGIN", "SOURCE"))
    print("-" * 78)
    prev = None
    exact_n = 0
    for tag in sorted(rows, key=tag_key):
        b, state = rows[tag]
        if state != 'exact':
            print("%-22s %14s %10s %12s  %s" % (tag, "—", "—", "—", state))
            continue
        exact_n += 1
        # a delta is only meaningful between two EXACT readings
        delta = "%+d" % (b - prev) if prev is not None else ""
        margin = CACHE_LINE - b
        print("%-22s %14d %10s %12d  exact" % (tag, b, delta, margin))
        prev = b
    print("-" * 78)
    print("%d tag(s) · %d exact · %d without a byte count"
          % (len(rows), exact_n, len(rows) - exact_n))
    if exact_n < 2:
        print("fewer than two exact readings — no drift can be derived")


def selftest():
    import tempfile, shutil
    p = f = 0
    def chk(name, got, want):
        nonlocal p, f
        if got == want:
            p += 1; print("  ok    %-52s %s" % (name, got))
        else:
            f += 1; print("  FAIL  %-52s got %r want %r" % (name, got, want))

    base = os.path.join(os.getcwd(), "tmp") if os.path.isdir(os.path.join(os.getcwd(), "tmp")) else None
    d = tempfile.mkdtemp(prefix="pckdrift.", dir=base)
    try:
        def mk(tag, line):
            os.makedirs(os.path.join(d, tag), exist_ok=True)
            with open(os.path.join(d, tag, "publish_all_web.log"), "w") as fh:
                fh.write("noise\n" + line + "\nmore noise\n")

        mk("v3.33.9-alpha",   "[deploy] index.pck: 160 MB")
        mk("v3.33.10-alpha",  "[deploy] index.pck: 166.94 MiB (175.1 MB decimal, 175054352 bytes)")
        mk("v3.33.11-alpha",  "[deploy] index.pck: 166.95 MiB (175.1 MB decimal, 175055352 bytes)")
        os.makedirs(os.path.join(d, "v3.33.12-alpha"), exist_ok=True)
        open(os.path.join(d, "v3.33.12-alpha", "x.log"), "w").write("nothing relevant\n")
        # a NON-TAG directory: real archives carry rel-<sha> dirs from the pre-tag era, and
        # their absence from this fixture set is what let a crash ship past a 9/9 selftest
        mk("rel-ceeedf00", "[deploy] index.pck: 150 MB")

        r = scan(d)
        # 1/2 — the two formats must be told apart, and the old one must NOT become a byte count
        chk("new form parses to exact bytes",    r["v3.33.10-alpha"], (175054352, 'exact'))
        chk("old MB form yields NO byte count",  r["v3.33.9-alpha"],  (None, 'imprecise'))
        chk("…and is not read as 160 bytes/MiB", r["v3.33.9-alpha"][0], None)
        # 3 — a tag with neither is named, not dropped
        chk("tag with no pck line is reported",  r["v3.33.12-alpha"], (None, 'absent'))
        chk("no tag is silently omitted",        len(r), 5)
        chk("a NON-TAG dir does not crash the sort", "rel-ceeedf00" in r, True)
        chk("…and sorts before every real tag",
            sorted(r, key=tag_key)[0], "rel-ceeedf00")
        # 4 — NUMERIC ordering. Lexically 'v3.33.10' < 'v3.33.9' and the series would invert.
        chk("numeric tag ordering",
            [t.split('.')[2].split('-')[0] for t in sorted(r, key=tag_key) if t.startswith('v')],
            ["9", "10", "11", "12"])
        chk("…and lexical ordering would differ", sorted(r) != sorted(r, key=tag_key), True)
        # 5 — an empty archive refuses rather than printing an empty series
        e = tempfile.mkdtemp(prefix="empty.", dir=base)
        try:
            scan(e); chk("empty archive refuses", "returned", "SystemExit")
        except SystemExit:
            chk("empty archive refuses", "SystemExit", "SystemExit")
        finally:
            shutil.rmtree(e, ignore_errors=True)
        try:
            scan(os.path.join(d, "nope")); chk("missing dir refuses", "returned", "SystemExit")
        except SystemExit:
            chk("missing dir refuses", "SystemExit", "SystemExit")
    finally:
        shutil.rmtree(d, ignore_errors=True)
    print()
    print("selftest: %d passed, %d failed" % (p, f))
    return 0 if f == 0 else 1


if __name__ == '__main__':
    a = sys.argv[1:]
    if a[:1] == ['--selftest']:
        sys.exit(selftest())
    if a[:1] == ['--series'] and len(a) == 2:
        series(a[1]); sys.exit(0)
    print(__doc__)
    print("usage: %s --series <archive-dir> | --selftest" % sys.argv[0])
    sys.exit(2)
