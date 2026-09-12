#!/usr/bin/env python3
"""Regenerate data/artist_sprite_ledger.json — content pins for every tracked
sprite under the PINNED_DIRS below.

Why: stale branches and bulk regens have repeatedly reintroduced OLD sprite
bytes over artist work (2026-07-02 bulk-regen revert, PR #5's ~60 pre-purge
conflicts, struktured 2026-08-17: "why does this always happen"). The ledger
makes every sprite-content change a DELIBERATE act: the gate test recomputes
hashes and goes red unless the ledger diff was committed alongside the art.

PINNED_DIRS is HALF OF A PAIR: test_artist_sprite_ledger_regression.gd carries
the same list as its _scan roots, in GDScript. Nothing makes the two agree at
edit time, so that test checks them against each other THROUGH this ledger.
Losing a dir here is the SILENT direction — the dir's pins simply stop being
written, and its files become unenrollABLE rather than unenrolled.

⚠️ This reads `git ls-files`, i.e. TRACKED files only, while the test walks the
FILESYSTEM. New art is invisible here until it is staged — `git add` FIRST, then
pin, or the tool reports success having pinned nothing new (2026-09-11: this is
mechanically why two ninja sheets shipped unpinned in v3.33.298).

Usage: git add <new art> && python3 tools/update_artist_ledger.py   (then review + commit)
"""
import hashlib, json, subprocess, sys, os

os.chdir(os.path.join(os.path.dirname(__file__), ".."))
# The WHOLE sprite tree, not a list of families. A four-entry list pinned 832 of 864 and
# silently omitted backgrounds (2.9 MB), ui (1.5 MB), weapons, tiles, objects and effects --
# the omission is invisible, because a dir nobody listed simply never gets pinned.
PINNED_DIRS = ["assets/sprites"]
tracked = subprocess.run(
    ["git", "ls-files", *PINNED_DIRS],
    capture_output=True, text=True, check=True).stdout.splitlines()
ledger = {}
for p in sorted(tracked):
    if not p.endswith(".png"):
        continue
    with open(p, "rb") as f:
        ledger[p] = hashlib.sha256(f.read()).hexdigest()
out = "data/artist_sprite_ledger.json"
with open(out, "w") as f:
    json.dump(ledger, f, indent=1, sort_keys=True)
    f.write("\n")
print(f"wrote {out}: {len(ledger)} pins")
