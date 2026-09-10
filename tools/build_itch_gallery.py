#!/usr/bin/env python3
"""Emit the itch gallery in caption order, numbered, so a bulk upload lands correctly.

WHY THIS EXISTS
---------------
CAPTIONS.md opens with "Order below is the recommended gallery order: itch shows the first
image largest, so the battle leads." That order is real editorial judgement — which shot leads,
which is second, which dungeon ships if only one does.

And it exists ONLY AS PROSE. The files are named by subject (`battle_storm.png`,
`harmonia_village.png`), itch orders a bulk upload by filename, and alphabetical order puts
`battle.png` first and the lead image third. **The curation is destroyed by the upload.**

WHY IT DERIVES RATHER THAN LISTS
--------------------------------
A hand-written order in this script would be a second source of truth that rots the moment
CAPTIONS.md is edited — and CAPTIONS.md is edited every time a shot is re-taken. The order is
parsed FROM the captions:

  * `### \\`name.png\\`` headings before the "Not in this set" section, in file order
  * then the "Baseline set" paragraph, in the order its names appear

WHAT IT REFUSES TO DO
---------------------
Invent a position. A screenshot that ships but has no stated position is reported and NOT
placed, and the script exits 3. Appending unplaced images to the end would look like curation
and would be a guess wearing the same clothes as the eight deliberate choices above it.

Measured 2026-09-10 on the current set: 20 screenshots ship, 17 have a stated position, and
3 do not — `battle.png`, `grimhollow_village.png`, and `eldertree_village.png`. The last is
the interesting one: the captions RESTORE it ("eldertree_village is BACK IN THE SET", after
the masterite silhouette fix) without ever giving it a place in the order.

Usage:  build_itch_gallery.py <itch-assets-dir> [out-dir]
        build_itch_gallery.py --check <itch-assets-dir>     report only, write nothing
        build_itch_gallery.py --selftest
Exit:   0 every shipped screenshot placed · 3 some ship with no stated position · 2 unusable
"""
import os
import re
import shutil
import sys
import tempfile

HEADING_RE = re.compile(r'^### `([a-z0-9_]+)(?:\.png)?`')
TICKED_RE = re.compile(r'`([a-z0-9_]+(?:\.png)?)`')


class Unusable(Exception):
    """Cannot evaluate — distinct from 'evaluated and found incomplete'."""


def derive_order(captions_path):
    if not os.path.isfile(captions_path):
        raise Unusable(f"[gallery] BLOCKED: {captions_path} not found — the order lives there "
                       f"and nowhere else.")
    lines = open(captions_path, encoding="utf-8", errors="replace").read().splitlines()

    cut = next((i for i, l in enumerate(lines) if l.startswith('## Not in this set')), len(lines))

    ordered = []
    for l in lines[:cut]:
        m = HEADING_RE.match(l)
        # A heading carrying DROPPED is a historical record, not a gallery entry. Note this
        # cannot rescue a heading whose DROPPED verdict was later reversed elsewhere in the
        # file — see the eldertree case in the docstring. Superseded status lives where it was
        # written; nothing here can see a retraction fifteen lines further down.
        if m and 'DROPPED' not in l:
            ordered.append(m.group(1) + '.png')

    base = []
    bi = next((i for i, l in enumerate(lines) if l.startswith('### Baseline set')), None)
    if bi is not None:
        for l in lines[bi + 1:bi + 6]:
            if l.startswith('---') or l.startswith('#'):
                break
            for name in TICKED_RE.findall(l):
                base.append(name if name.endswith('.png') else name + '.png')

    if not ordered:
        raise Unusable("[gallery] BLOCKED: no `### `name.png`` headings found before the "
                       "'Not in this set' section. The captions' structure changed; fix this "
                       "parse rather than emitting an order derived from nothing.")

    return list(dict.fromkeys(ordered + base))


def build(assets_dir, out_dir=None, check_only=False):
    shots_dir = os.path.join(assets_dir, "screenshots")
    if not os.path.isdir(shots_dir):
        raise Unusable(f"[gallery] BLOCKED: {shots_dir} not found.")
    on_disk = sorted(f for f in os.listdir(shots_dir) if f.endswith('.png'))
    if not on_disk:
        raise Unusable(f"[gallery] BLOCKED: no screenshots in {shots_dir}. An empty set is not "
                       f"a gallery.")

    order = derive_order(os.path.join(assets_dir, "CAPTIONS.md"))

    placed = [n for n in order if n in on_disk]
    named_but_absent = [n for n in order if n not in on_disk]
    unplaced = [n for n in on_disk if n not in order]

    print(f"[gallery] {len(on_disk)} screenshot(s) ship · {len(placed)} placed by CAPTIONS.md")
    for i, n in enumerate(placed, 1):
        print(f"[gallery]   {i:02d}. {n}")

    rc = 0
    if named_but_absent:
        print(f"[gallery] the captions position {len(named_but_absent)} shot(s) that are NOT "
              f"on disk:", file=sys.stderr)
        for n in named_but_absent:
            print(f"            {n}", file=sys.stderr)
        rc = 3
    if unplaced:
        print(f"[gallery] ⚠ {len(unplaced)} shot(s) SHIP WITH NO STATED POSITION:",
              file=sys.stderr)
        for n in unplaced:
            print(f"            {n}", file=sys.stderr)
        print("          Not placed, and deliberately not appended: appending would look like "
              "curation", file=sys.stderr)
        print("          and would be a guess wearing the same clothes as the deliberate "
              "choices above.", file=sys.stderr)
        print("          Give each a position in CAPTIONS.md, or drop it from screenshots/.",
              file=sys.stderr)
        rc = 3

    if check_only:
        return rc

    out = out_dir or os.path.join(assets_dir, "gallery")
    if os.path.isdir(out):
        shutil.rmtree(out)
    os.makedirs(out)
    for i, n in enumerate(placed, 1):
        shutil.copy2(os.path.join(shots_dir, n), os.path.join(out, f"{i:02d}_{n}"))
    print(f"[gallery] wrote {len(placed)} numbered file(s) to {out}")
    if rc != 0:
        print("[gallery] the gallery is INCOMPLETE — see above.", file=sys.stderr)
    return rc


# ── self-test ────────────────────────────────────────────────────────────────
def selftest():
    passed = failed = 0
    saw0 = saw3 = False

    def arm(name, want, fn):
        nonlocal passed, failed, saw0, saw3
        try:
            got = fn()
        except Unusable:
            got = 2
        if got == 0:
            saw0 = True
        if got == 3:
            saw3 = True
        if got == want:
            passed += 1
            print(f"  ok    {name:54} exit {got}")
        else:
            failed += 1
            print(f"  FAIL  {name:54} exit {got} (wanted {want})")

    CAPS = """# Captions
Order below is the recommended gallery order.

### `lead.png` — **lead image**
text
### `second.png`
text
### `gone.png` — DROPPED AGAIN
this one is a historical record, not an entry

### Baseline set (shot whenever)
`third` · `fourth` — villages.

---

## Not in this set, and why
- **`never_shot.png` — DROPPED.** reason
### `decoy.png`
a heading AFTER the cut must not enter the order
"""

    with tempfile.TemporaryDirectory() as d:
        a = os.path.join(d, "assets")
        os.makedirs(os.path.join(a, "screenshots"))
        open(os.path.join(a, "CAPTIONS.md"), "w").write(CAPS)
        for n in ("lead.png", "second.png", "third.png", "fourth.png"):
            open(os.path.join(a, "screenshots", n), "w").write(n)

        arm("every shipped shot is placed", 0, lambda: build(a, os.path.join(d, "o1")))

        # ORDER, not just membership: the whole point is that alphabetical is wrong.
        got = sorted(os.listdir(os.path.join(d, "o1")))
        want = ["01_lead.png", "02_second.png", "03_third.png", "04_fourth.png"]
        if got == sorted(want) and got[0].startswith("01_lead"):
            passed += 1
            print(f"  ok    {'numbering follows caption order, not alphabetical':54} 01=lead")
        else:
            failed += 1
            print(f"  FAIL  {'numbering follows caption order':54} {got}")

        # a shot that ships with no stated position
        open(os.path.join(a, "screenshots", "orphan.png"), "w").write("x")
        arm("a shipped shot with no stated position", 3, lambda: build(a, os.path.join(d, "o2")))
        # ...and it must NOT be silently appended
        if not any("orphan" in f for f in os.listdir(os.path.join(d, "o2"))):
            passed += 1
            print(f"  ok    {'unplaced shot is NOT appended to the gallery':54} absent")
        else:
            failed += 1
            print(f"  FAIL  {'unplaced shot leaked into the gallery':54} present")
        os.remove(os.path.join(a, "screenshots", "orphan.png"))

        # a DROPPED heading must not enter the order even though it parses as a heading
        arm("DROPPED heading stays out", 0, lambda: build(a, os.path.join(d, "o3")))
        if not any("gone" in f for f in os.listdir(os.path.join(d, "o3"))):
            passed += 1
            print(f"  ok    {'DROPPED heading not placed':54} absent")
        else:
            failed += 1
            print(f"  FAIL  {'DROPPED heading was placed':54} present")

        # headings after the "Not in this set" cut must not enter the order
        if not any("decoy" in f for f in os.listdir(os.path.join(d, "o3"))):
            passed += 1
            print(f"  ok    {'heading after the cut is excluded':54} absent")
        else:
            failed += 1
            print(f"  FAIL  {'heading after the cut leaked in':54} present")

        # the captions naming a shot that is not on disk
        os.remove(os.path.join(a, "screenshots", "fourth.png"))
        arm("captions position a shot that is missing", 3, lambda: build(a, os.path.join(d, "o4")))
        open(os.path.join(a, "screenshots", "fourth.png"), "w").write("x")

        empty = os.path.join(d, "empty")
        os.makedirs(os.path.join(empty, "screenshots"))
        open(os.path.join(empty, "CAPTIONS.md"), "w").write(CAPS)
        arm("no screenshots at all", 2, lambda: build(empty, os.path.join(d, "o5")))

        nocaps = os.path.join(d, "nocaps")
        os.makedirs(os.path.join(nocaps, "screenshots"))
        open(os.path.join(nocaps, "screenshots", "lead.png"), "w").write("x")
        open(os.path.join(nocaps, "CAPTIONS.md"), "w").write("# nothing parseable here\n")
        arm("captions with no headings — must not guess", 2,
            lambda: build(nocaps, os.path.join(d, "o6")))

    print()
    print(f"selftest: {passed} passed, {failed} failed")
    if not (saw0 and saw3):
        print(f"selftest: BROKEN — outcomes seen: complete={saw0} incomplete={saw3}; both "
              f"required", file=sys.stderr)
        return 1
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    try:
        if len(sys.argv) > 1 and sys.argv[1] == "--selftest":
            sys.exit(selftest())
        if len(sys.argv) > 2 and sys.argv[1] == "--check":
            sys.exit(build(sys.argv[2], check_only=True))
        if len(sys.argv) < 2:
            print("usage: build_itch_gallery.py <itch-assets-dir> [out-dir] | --check <dir> | "
                  "--selftest", file=sys.stderr)
            sys.exit(2)
        sys.exit(build(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None))
    except Unusable as e:
        print(str(e), file=sys.stderr)
        sys.exit(2)
