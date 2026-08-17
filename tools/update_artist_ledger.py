#!/usr/bin/env python3
"""Regenerate data/artist_sprite_ledger.json — content pins for every tracked
sprite under assets/sprites/jobs/** and assets/sprites/monsters/**.

Why: stale branches and bulk regens have repeatedly reintroduced OLD sprite
bytes over artist work (2026-07-02 bulk-regen revert, PR #5's ~60 pre-purge
conflicts, struktured 2026-08-17: "why does this always happen"). The ledger
makes every sprite-content change a DELIBERATE act: the gate test recomputes
hashes and goes red unless the ledger diff was committed alongside the art.

Usage: python3 tools/update_artist_ledger.py   (then review + commit the diff)
"""
import hashlib, json, subprocess, sys, os

os.chdir(os.path.join(os.path.dirname(__file__), ".."))
tracked = subprocess.run(
    ["git", "ls-files", "assets/sprites/jobs", "assets/sprites/monsters"],
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
