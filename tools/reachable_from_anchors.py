#!/usr/bin/env python3
"""Which .gd files can the engine actually reach?

WHY THIS IS A TOOL AND NOT A PARAGRAPH
--------------------------------------
On 2026-09-11 five lanes each needed this answer and each built the instrument
fresh. Between them the rebuilds produced: a false zero on two live menus (an
exclusion pattern that matched the referring line's own path), a caption fixed
on a screen no player can open, two prompts likewise, 58 lines of dialogue
shipped into a branch nothing calls, and — mine — a run reporting 83 dead files
including the core battle class.

THE TWO RULES THAT MAKE THE ANSWER TRUE
---------------------------------------
1. ANCHOR, don't count referrers. "X is referenced by Y" says nothing until you
   ask whether Y runs. Two levels is still edge-counting. The recursion
   terminates only at a node whose liveness the ENGINE asserts: `run/main_scene`
   and the autoloads, both read from project.godot rather than nominated here.

2. FOLLOW class_name, NOT JUST res://. GDScript resolves `class_name` through a
   GLOBAL registry, so `Combatant.new()` and `var w: WeatherSystem` carry no
   path reference at all. A res://-only closure scored 83 of 282 files dead,
   including Combatant, InteractGeometry, HeadlessBattleResolver and
   BestiarySystem. 28x over-report.

   The direction matters: a path-only walk fails toward FALSE DEATH, and a false
   death is actionable in a way a false life is not — nobody deletes a file
   because a scan called it reachable. 83 is also exactly the size that reads as
   a satisfying cleanup backlog rather than a broken instrument.

STATED BIAS, in the safe direction
----------------------------------
The class_name match is a bare-identifier scan over whole file text, comments
and strings included, so a class mentioned only in a comment counts as
referenced. That inflates LIVE, which is conservative for a death claim: a
stricter matcher could only ever find MORE dead files, never fewer. Names that
survive this generosity are the ones worth acting on.

WHAT THIS DOES NOT ANSWER
-------------------------
Reachable is not the same as reached. A file anchored through a menu the player
can open is live; whether they ever open it is a different question, and this
tool has nothing to say about it. Nor does unreachable mean "delete" — the three
current orphans are pinned by test files and are a content decision.

Usage:
    tools/reachable_from_anchors.py              # report
    tools/reachable_from_anchors.py --selftest   # prove the reader answers both ways
Exit: 0 report produced · 2 a control failed (result withheld) · 3 nothing scanned
"""

import glob
import os
import re
import sys

# Known-live files used as controls. Each is reachable ONLY via class_name — no
# res:// reference anywhere — so they are exactly the cases a path-only walk
# gets wrong. If any reads dead, the reader is broken and no result is printed.
CONTROLS_LIVE = [
    "src/battle/Combatant.gd",
    "src/exploration/InteractGeometry.gd",
    "src/autogrind/HeadlessBattleResolver.gd",
]


def read(path):
    try:
        with open(path, errors="replace") as fh:
            return fh.read()
    except OSError:
        return ""


def anchors(project_godot="project.godot"):
    """main_scene + autoloads, READ from the project file, never nominated here."""
    text = read(project_godot)
    out = []
    main = re.search(r'run/main_scene="res://([^"]+)"', text)
    if main:
        out.append(main.group(1))
    block = re.search(r"\[autoload\](.*?)(\n\[|\Z)", text, re.S)
    if block:
        for line in block.group(1).splitlines():
            hit = re.search(r'=\s*"\*?res://([^"]+)"', line)
            if hit:
                out.append(hit.group(1))
    return out, (main.group(1) if main else None)


def class_registry(files, texts):
    """class_name -> file. The half a res://-only walk cannot see."""
    reg = {}
    for path in files:
        hit = re.search(r"^\s*class_name\s+([A-Za-z_][A-Za-z0-9_]*)", texts[path], re.M)
        if hit:
            reg[hit.group(1)] = path
    return reg


def closure(start, texts, registry):
    patterns = {
        name: re.compile(r"(?<![A-Za-z0-9_])" + re.escape(name) + r"(?![A-Za-z0-9_])")
        for name in registry
    }
    seen, stack = set(), list(start)
    while stack:
        path = stack.pop()
        if path in seen:
            continue
        seen.add(path)
        text = texts.get(path) or read(path)
        found = set(re.findall(r"res://([A-Za-z0-9_./-]+\.(?:gd|tscn))", text))
        for name, owner in registry.items():
            if patterns[name].search(text):
                found.add(owner)
        for ref in found:
            if ref not in seen:
                stack.append(ref)
    return seen


def run():
    files = sorted(glob.glob("src/**/*.gd", recursive=True))
    if not files:
        print("no src/**/*.gd found — run from the repo root", file=sys.stderr)
        return 3
    texts = {p: read(p) for p in files}
    roots, main = anchors()
    if not roots:
        print("project.godot declared no anchors — refusing to guess", file=sys.stderr)
        return 2

    registry = class_registry(files, texts)
    reached = closure(roots, texts, registry)
    # Intersect with the scanned corpus before counting. `reached` also holds .gd
    # files OUTSIDE src/ (autoloads elsewhere, addons pulled in by a scene), so a
    # bare len() printed "282 of 282 reachable" on the same run that listed 3 dead
    # — a self-contradicting line, caught by reading my own output.
    live_all = {p for p in reached if p.endswith(".gd")}
    live = live_all & set(files)
    dead = sorted(set(files) - live)

    # Controls BEFORE the verdict. A reader that cannot find the combat core has
    # nothing to say about anything else.
    broken = [c for c in CONTROLS_LIVE if os.path.exists(c) and c not in live]
    if broken:
        print("CONTROL FAILED — these are reachable only via class_name and read DEAD:",
              file=sys.stderr)
        for c in broken:
            print("   ", c, file=sys.stderr)
        print("The reader is not following the global class registry. Result withheld.",
              file=sys.stderr)
        return 2

    # Emit the corpus, not just the verdict: the counts ARE the positive control.
    print(f"anchors        main_scene={main}  autoloads={len(roots) - 1}")
    print(f"class_name declarations in src/   {len(registry)}")
    print(f"src/*.gd reachable from an anchor {len(live)} of {len(files)}")
    if len(live) + len(dead) != len(files):
        print("REPORT INCONSISTENT: live + dead != corpus — do not trust this run", file=sys.stderr)
        return 2
    print(f"NOT reachable                     {len(dead)}")
    for path in dead:
        print("   ", path)
    return 0


def selftest():
    """Prove the reader answers BOTH ways rather than asserting it does."""
    files = sorted(glob.glob("src/**/*.gd", recursive=True))
    texts = {p: read(p) for p in files}
    roots, _ = anchors()
    registry = class_registry(files, texts)

    live = {p for p in closure(roots, texts, registry) if p.endswith(".gd")}
    ok = True
    for c in CONTROLS_LIVE:
        good = c in live
        ok &= good
        print(f"  {'PASS' if good else 'FAIL'}  live via class_name only: {c}")

    # Negative: a file nothing can reach must read dead. Synthesised, because the
    # corpus may one day contain no orphan and a check that cannot return a
    # positive is not a check.
    probe = "src/__reachability_probe__.gd"
    texts[probe] = "extends Node\n"
    live2 = {p for p in closure(roots, texts, class_registry(files, texts)) if p.endswith(".gd")}
    good = probe not in live2
    ok &= good
    print(f"  {'PASS' if good else 'FAIL'}  an unreferenced file reads DEAD: {probe}")

    # Negative in the other direction: strip class_name resolution and the
    # controls must FLIP, or the class_name half is doing nothing.
    live3 = {p for p in closure(roots, texts, {}) if p.endswith(".gd")}
    flipped = [c for c in CONTROLS_LIVE if c in live and c not in live3]
    good = len(flipped) == len(CONTROLS_LIVE)
    ok &= good
    print(f"  {'PASS' if good else 'FAIL'}  without class_name resolution all {len(CONTROLS_LIVE)} "
          f"controls flip to dead (flipped {len(flipped)}) — proves that half is load-bearing")
    return 0 if ok else 2


if __name__ == "__main__":
    sys.exit(selftest() if "--selftest" in sys.argv else run())
