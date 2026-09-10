#!/usr/bin/env python3
"""Prove the web pck contains everything the export OWES, by derivation not by size.

WHY THIS EXISTS
---------------
make_web_stage.sh gates the pck on size, and only in one direction:

    [ "$SZ" -ge "$PCK_LIMIT" ] && BLOCKED        # too big
    (no lower bound)

A build that LOST content shrinks, so it passes with MORE headroom and reports a better
number: "pck 164.8 MiB · headroom 25.0 MiB · FITS" reads healthier the more has gone
missing. The failure drives the metric AWAY from the threshold.

There was a shrink guard. I wrote it, and it covers music only:

    PACKED=$(grep -c 'Storing File.*assets/audio/music/' ...)
    [ "$PACKED" -ge "$EXPECT" ] || BLOCKED

Measured on a real build: 3326 files packed, 161 guarded (4.8%), 3165 unguarded (95.2%) —
sprites, cutscenes, scripts, every imported asset. And the comment directly above that guard
already said "A shrinking pck is ALSO what dropping content looks like, so size alone cannot
tell success from regression." The hazard was named correctly and then one asset class was
guarded, because that was the class I was worried about that week. A correct comment above a
partial guard is stronger camouflage than no comment at all.

WHY A FLOOR WOULD HAVE BEEN WRONG
---------------------------------
The obvious fix is a minimum pck size or a minimum file count from the last good build. That
is residual-only calibration: a floor at the observed minimum blesses any dropout smaller than
historical churn AND goes stale the moment content lands. Wrong in two directions at once, and
both worsen with time. A bound from the CONTRACT survives the corpus changing; a bound from
the corpus does not.

WHAT THE CONTRACT IS
--------------------
Godot already writes down what it owes, per file:

  * every `<asset>.import` declares `dest_files` — the artifacts that source produces
  * every non-excluded `.gd` compiles to exactly one `.gdc`
  * every non-excluded `.tscn` exports to exactly one `.scn`

So the question "did the build come out whole" has an exact answer with no dial in it, and a
missing artifact is named rather than inferred from a number moving.

Verified on v3.33.293-alpha's real stage: 1230 non-excluded .import files declaring 2458
artifacts, 281 .gd -> 281 .gdc, 7 .tscn -> 7 .scn, 0 missing. Coverage 2746 of 3326 stored
entries (82.6%), against 161 (4.8%) before.

WHAT IT DOES NOT COVER, stated so the number is not read as "everything"
-----------------------------------------------------------------------
The remaining ~17% is engine and project furniture the export synthesises rather than derives
from a source file — project.godot, the exported scene bundles' own index entries, shader
caches. Those have no per-file declaration to check against, so they are OUT of scope rather
than silently assumed fine.

Usage:  check_pck_complete.py <stage-dir> <export-log>
        check_pck_complete.py --selftest
Exit:   0 complete · 4 something the export owed is missing · 2 could not evaluate
"""
import fnmatch
import os
import re
import sys
import tempfile

STORED_RE = re.compile(r'Storing File: res://(\S+)')
DEST_RE = re.compile(r'"res://([^"]+)"')


def _exclusions(stage):
    """The Web preset's exclude_filter, with the parse ASSERTED.

    str.find returns -1 on a miss and Python slices happily with it, so an unasserted parse
    yields a plausible-looking pattern list built from the file header. This is the same
    hardened parse make_web_stage.sh already uses, and for the same reason.
    """
    p = os.path.join(stage, "export_presets.cfg")
    if not os.path.isfile(p):
        raise SystemExit(f"[pck] BLOCKED: {p} not found — cannot derive what the export owes.")
    s = open(p, encoding="utf-8", errors="replace").read()
    i = s.find('name="Web"')
    j = s.find('exclude_filter="', i)
    k = s.find('"', j + 16)
    if i < 0 or j < 0 or k < 0:
        raise SystemExit(
            f'[pck] BLOCKED: could not locate the Web preset\'s exclude_filter in {p} '
            f'(name="Web" at {i}, exclude_filter at {j}, closing quote at {k}). '
            f'Fix this parse rather than letting it derive from garbage.')
    return [x.strip() for x in s[j + 16:k].split(",") if x.strip()]


def _is_excluded(rel, pats):
    return any(fnmatch.fnmatch(rel, p) or rel.startswith(p.rstrip('*')) for p in pats)


def evaluate(stage, logpath):
    pats = _exclusions(stage)
    if not os.path.isfile(logpath):
        raise SystemExit(f"[pck] BLOCKED: export log {logpath} not found — an absent log is "
                         f"not an empty one, and neither is evidence of a complete pck.")
    log = open(logpath, encoding="utf-8", errors="replace").read()
    stored = set(STORED_RE.findall(log))
    if not stored:
        raise SystemExit("[pck] BLOCKED: the export log lists no stored files at all. That is a "
                         "broken log or a failed export, not a complete build.")

    owed, missing = 0, []

    # 1. imported assets — godot's own per-source declaration
    for root, dirs, files in os.walk(stage):
        dirs[:] = [d for d in dirs if d not in ('.git', '.godot')]
        for f in files:
            if not f.endswith('.import'):
                continue
            rel = os.path.relpath(os.path.join(root, f), stage)
            if _is_excluded(rel, pats) or _is_excluded(rel[:-7], pats):
                continue
            txt = open(os.path.join(root, f), encoding="utf-8", errors="replace").read()
            for dest in DEST_RE.findall(txt):
                if dest.startswith('.godot/imported/'):
                    owed += 1
                    if dest not in stored:
                        missing.append(f"{dest}   (owed by {rel})")

    # 2. scripts and scenes — a 1:1 mapping, so a COUNT is exact here rather than a proxy
    counts = {}
    for ext, packed_ext in (('.gd', '.gdc'), ('.tscn', '.scn')):
        on_disk = []
        for root, dirs, files in os.walk(stage):
            dirs[:] = [d for d in dirs if d not in ('.git', '.godot')]
            for f in files:
                if f.endswith(ext):
                    rel = os.path.relpath(os.path.join(root, f), stage)
                    if not _is_excluded(rel, pats):
                        on_disk.append(rel)
        packed = [p for p in stored if p.endswith(packed_ext)]
        counts[ext] = (len(on_disk), len(packed))
        owed += len(on_disk)
        if len(packed) < len(on_disk):
            missing.append(f"{len(on_disk) - len(packed)} missing {packed_ext} "
                           f"({len(on_disk)} {ext} on disk, {len(packed)} packed)")

    print(f"[pck] contract: {owed} artifact(s) owed by the stage")
    print(f"[pck]   imported assets declared by .import dest_files")
    for ext, (d, p) in counts.items():
        print(f"[pck]   {ext} -> {'.gdc' if ext == '.gd' else '.scn'}: {d} on disk, {p} packed")
    print(f"[pck]   stored entries in the pck: {len(stored)}")

    if missing:
        print(f"[pck] BLOCKED: {len(missing)} thing(s) the export OWED are not in the pck.",
              file=sys.stderr)
        print("      The pck did not merely shrink — these are named, and a size gate cannot",
              file=sys.stderr)
        print("      see them because a smaller pck passes with MORE headroom.", file=sys.stderr)
        for m in missing[:20]:
            print(f"        {m}", file=sys.stderr)
        if len(missing) > 20:
            print(f"        ... and {len(missing) - 20} more", file=sys.stderr)
        return 4
    print("[pck] complete: everything the stage owes is in the pck")
    return 0


# ── self-test ────────────────────────────────────────────────────────────────
# Builds a miniature stage and a synthetic export log, and runs the SHIPPED evaluate().
# Both outcomes are required: a check that has only ever returned 0 is a claim about the
# check, not about the pck.
def selftest():
    passed = failed = 0
    saw_ok = saw_block = False

    def arm(name, want, fn):
        nonlocal passed, failed, saw_ok, saw_block
        try:
            got = fn()
        except SystemExit as e:
            got = 2 if not isinstance(e.code, int) else e.code
        if got == 0:
            saw_ok = True
        if got == 4:
            saw_block = True
        if got == want:
            passed += 1
            print(f"  ok    {name:52} exit {got}")
        else:
            failed += 1
            print(f"  FAIL  {name:52} exit {got} (wanted {want})")

    with tempfile.TemporaryDirectory() as d:
        stage = os.path.join(d, "stage")
        os.makedirs(os.path.join(stage, "assets", "sprites"))
        os.makedirs(os.path.join(stage, "src"))
        os.makedirs(os.path.join(stage, "tools"))
        open(os.path.join(stage, "export_presets.cfg"), "w").write(
            '[preset.0]\nname="Web"\nexclude_filter="tools/*, assets/sprites/skip_*.png"\n')
        open(os.path.join(stage, "assets/sprites/hero.png"), "w").write("x")
        open(os.path.join(stage, "assets/sprites/hero.png.import"), "w").write(
            '[remap]\ndest_files=["res://.godot/imported/hero.png-aaa.ctex"]\n')
        open(os.path.join(stage, "assets/sprites/skip_me.png"), "w").write("x")
        open(os.path.join(stage, "assets/sprites/skip_me.png.import"), "w").write(
            '[remap]\ndest_files=["res://.godot/imported/skip_me.png-bbb.ctex"]\n')
        open(os.path.join(stage, "src/Game.gd"), "w").write("extends Node\n")
        open(os.path.join(stage, "tools/helper.gd"), "w").write("extends Node\n")

        def write_log(entries):
            p = os.path.join(d, "export.log")
            open(p, "w").write("".join(f"\tsavepack: step 2: Storing File: res://{e}\n" for e in entries))
            return p

        COMPLETE = [".godot/imported/hero.png-aaa.ctex", "src/Game.gdc"]
        arm("complete pck", 0, lambda: evaluate(stage, write_log(COMPLETE)))

        # THE CASE THE SIZE GATE CANNOT SEE: an artifact silently absent. The pck is SMALLER,
        # so the size gate passes with more headroom and reports a better number.
        arm("an imported asset missing", 4,
            lambda: evaluate(stage, write_log(["src/Game.gdc"])))
        arm("a compiled script missing", 4,
            lambda: evaluate(stage, write_log([".godot/imported/hero.png-aaa.ctex"])))

        # An EXCLUDED source must not be owed — otherwise the check blocks every correct
        # build, which is how a guard gets disabled.
        #
        # ASSERT ON THE OWED COUNT, NOT THE EXIT CODE. Checking exit 0 here would be a
        # duplicate of "complete pck": it passes for the same reason and would still pass if
        # exclusions were ignored in a way that happened not to change the verdict. The
        # stage contains 4 candidate sources (hero.png, skip_me.png, src/Game.gd,
        # tools/helper.gd); exactly 2 survive the filter, so 2 is the number that proves the
        # exclusion ran.
        import io as _io, contextlib as _ctx

        def _owed(log):
            buf = _io.StringIO()
            with _ctx.redirect_stdout(buf):
                evaluate(stage, log)
            m = re.search(r'contract: (\d+) artifact', buf.getvalue())
            return int(m.group(1)) if m else -1

        got = _owed(write_log(COMPLETE))
        if got == 2:
            passed += 1
            print(f"  ok    {'excluded sources are not owed (2 of 4)':52} owed {got}")
        else:
            failed += 1
            print(f"  FAIL  {'excluded sources are not owed (2 of 4)':52} owed {got} (wanted 2)")

        # ...and that arm must be able to fail: with an empty filter all 4 are owed.
        open(os.path.join(stage, "export_presets.cfg"), "w").write(
            '[preset.0]\nname="Web"\nexclude_filter=""\n')
        got_all = _owed(write_log(COMPLETE))
        open(os.path.join(stage, "export_presets.cfg"), "w").write(
            '[preset.0]\nname="Web"\nexclude_filter="tools/*, assets/sprites/skip_*.png"\n')
        if got_all == 4:
            passed += 1
            print(f"  ok    {'CONTROL: empty filter owes all 4':52} owed {got_all}")
        else:
            failed += 1
            print(f"  FAIL  {'CONTROL: empty filter owes all 4':52} owed {got_all} (wanted 4)")

        arm("empty export log", 2, lambda: evaluate(stage, write_log([])))
        arm("export log missing", 2, lambda: evaluate(stage, os.path.join(d, "nope.log")))

        bad = os.path.join(d, "badstage")
        os.makedirs(bad)
        open(os.path.join(bad, "export_presets.cfg"), "w").write("[preset.0]\nname=\"Linux\"\n")
        arm("Web preset absent — parse must not guess", 2,
            lambda: evaluate(bad, write_log(COMPLETE)))

    print()
    print(f"selftest: {passed} passed, {failed} failed")
    if not (saw_ok and saw_block):
        print(f"selftest: BROKEN — outcomes seen: complete={saw_ok} blocked={saw_block}; "
              f"both required", file=sys.stderr)
        return 1
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--selftest":
        sys.exit(selftest())
    if len(sys.argv) != 3:
        print(__doc__.strip().splitlines()[-3], file=sys.stderr)
        sys.exit(2)
    sys.exit(evaluate(sys.argv[1], sys.argv[2]))
