#!/usr/bin/env python3
"""Resolve a data/sprite_manifest.json conflict ENTRY BY ENTRY, and prove what it did.

WHY THIS EXISTS. On 2026-09-06 cowir-sprites resolved a one-line cave_rat conflict with
`git checkout --theirs data/sprite_manifest.json` and silently lost their FIGHTER edits --
which had auto-merged cleanly and were nowhere near the conflict. `--theirs` and `--ours`
replace the WHOLE FILE; the conflict was one entry, the loss was everything else they had
added. They caught it only by re-reading both sides afterwards. This manifest now has ~113
entries and three lanes writing to it, so that resolution shape will keep costing work.

WHAT IT DOES. Takes the three sides git already gives you during a conflict and produces a
union at ENTRY granularity:
    base    the common ancestor          (git show :1:data/sprite_manifest.json)
    ours    the branch being rebased ON  (git show :2:...)
    theirs  the commit being replayed    (git show :3:...)
For every section and every id:
  - only one side changed it     -> take that side
  - both changed it identically  -> take it
  - both changed it differently  -> REPORT and refuse (a real conflict needs a human)
  - one side deleted it          -> REPORT and refuse (deletion is never accidental here)
An id added by only one side is kept. That is the case --theirs destroys.

IT REFUSES RATHER THAN GUESSES. A tool that silently picks a winner on a genuine
disagreement is the same defect as --theirs with better manners.

USAGE, mid-conflict:
    python3 tools/merge_sprite_manifest.py            # writes the merged file, or refuses
    python3 tools/merge_sprite_manifest.py --dry-run  # report only

ENSURE_ASCII=False ON PURPOSE. The manifest on main is fully literal-unicode; writing it
with Python's default re-escapes ~119 unrelated lines and manufactures the next conflict.
"""
import json, subprocess, sys
from pathlib import Path

# Repo root from GIT, not from __file__ arithmetic. Found on first live use: mid-rebase the
# tool may only exist as a copy extracted from a later commit (it cannot be in the working
# tree while an EARLIER commit is the one conflicting), and parent.parent then resolved to
# the scratch dir -- it read the right stages and wrote the merge to a path nobody reads.
def _repo_root() -> Path:
    import subprocess as _sp
    r = _sp.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit("not inside a git repository")
    return Path(r.stdout.strip())


REPO = _repo_root()
TARGET = "data/sprite_manifest.json"


def stage(n: int):
    r = subprocess.run(["git", "show", f":{n}:{TARGET}"], capture_output=True, text=True, cwd=str(REPO))
    if r.returncode != 0:
        return None
    return json.loads(r.stdout)


def merge_section(name, base, ours, theirs, problems):
    out = dict(ours)
    ids = set(base) | set(ours) | set(theirs)
    added_ours = added_theirs = taken_theirs = 0
    for i in sorted(ids):
        b, o, t = base.get(i), ours.get(i), theirs.get(i)
        if o == t:
            continue                       # agree (including both-absent)
        if b is None:
            if o is None:                  # theirs added it
                out[i] = t
                added_theirs += 1
            elif t is None:                # ours added it
                added_ours += 1
            else:
                problems.append(f"{name}.{i}: both sides ADDED it with different content")
            continue
        if o == b:                         # only theirs touched it
            if t is None:
                problems.append(f"{name}.{i}: theirs DELETED an entry ours kept")
            else:
                out[i] = t
                taken_theirs += 1
            continue
        if t == b:                         # only ours touched it
            if o is None:
                problems.append(f"{name}.{i}: ours DELETED an entry theirs kept")
            continue
        problems.append(f"{name}.{i}: both sides CHANGED it differently")
    return out, added_ours, added_theirs, taken_theirs


def main():
    base, ours, theirs = stage(1), stage(2), stage(3)
    if base is None or ours is None or theirs is None:
        sys.exit("not in a conflicted merge/rebase for %s (no :1:/:2:/:3: stages)" % TARGET)

    problems = []
    merged = dict(ours)
    totals = [0, 0, 0]
    for section in sorted(set(base) | set(ours) | set(theirs)):
        b, o, t = base.get(section), ours.get(section), theirs.get(section)
        if not (isinstance(b, dict) and isinstance(o, dict) and isinstance(t, dict)):
            if o != t:
                problems.append(f"section {section!r} is not an object on all three sides -- resolve by hand")
            continue
        merged[section], ao, at, tt = merge_section(section, b, o, t, problems)
        totals[0] += ao; totals[1] += at; totals[2] += tt
        if ao or at or tt:
            print(f"  {section}: kept {ao} ours-only, took {at} theirs-only, took {tt} theirs-modified")

    print(f"  TOTAL kept-from-ours {totals[0]} · taken-from-theirs {totals[1] + totals[2]}")
    if problems:
        print("\n  REAL CONFLICTS -- resolving by hand is the only correct move:")
        for p in problems:
            print(f"    {p}")
        sys.exit(1)

    if "--dry-run" in sys.argv:
        print("  --dry-run: nothing written")
        return
    (REPO / TARGET).write_text(json.dumps(merged, indent=2, ensure_ascii=False) + "\n")
    print(f"  wrote {TARGET} -- now run `git add {TARGET}` and verify BOTH sides' entries survived")


if __name__ == "__main__":
    main()
