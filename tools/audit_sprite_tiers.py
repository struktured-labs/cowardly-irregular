#!/usr/bin/env python3
"""Catch tier lies in sprite_manifest.json by checking git, not the manifest.

WHY THIS EXISTS
---------------
`tier` is the field that decides what I am allowed to touch. Nothing in the
game reads it — the only consumers are the generation tools in this repo and
one GUT audit. So a wrong tier changes exactly one thing: whether an AI
regeneration will happily overwrite artist work.

On 2026-07-29 `sheets.fighter` was labelled:

    "tier": "T1",
    "generator": "gen_full_sweep.py (v2 jrpg_pixel_style LoRA)"

while being 9/9 artist art — 7 PNGs byte-identical to the v0.15.0 artist
baseline, and idle/attack holding the artist's own drive-archive renders
(4cab90d0). The generator string was true when it was written and described
a directory whose contents were later replaced by 68b049d0 / 4cab90d0. It
rotted in place.

CLAUDE.md names fighter as THE example of artist work to protect. The one
piece of metadata encoding that protection said "AI-generated, safe to
regenerate."

The manifest cannot audit itself: its tier and its generator string agreed
with each other perfectly (0 contradictions across 143 entries). Both were
wrong together, because both were written at the same moment and neither was
revisited. Provenance has to be checked against something outside the file
that claims it — here, git.

WHAT IT CHECKS
--------------
  BASELINE_MATCH  a PNG byte-identical to its v0.15.0 version is artist art
                  by definition (that tag IS the artist baseline). Any sheet
                  containing one must not be T1.
  ARTIST_COMMIT   a PNG whose current content came from a commit that says it
                  imported artist work is artist art. Same rule.

Both are *sufficient* conditions, never necessary — a sheet with no hits is
unproven, not proven-AI. This tool finds tier lies; it cannot certify tiers.
That asymmetry is deliberate: the expensive mistake is treating artist work
as disposable, not the reverse.

Usage:
    uv run python tools/audit_sprite_tiers.py
"""
import json
import subprocess
import sys
from pathlib import Path

GAME = Path("/home/struktured/projects/cowardly-irregular-artist-ship")
MANIFEST = GAME / "data" / "sprite_manifest.json"

ARTIST_BASELINE_TAG = "v0.15.0"
# Commits whose subject states they imported artist-authored pixels. Add to
# this list when a new artist drop lands; a missing entry weakens the check
# but cannot make it lie, since every rule here is sufficient-not-necessary.
ARTIST_IMPORT_COMMITS = {
    "4cab90d0",  # fighter/mage/rogue idle+attack from artist drive archive
}


def _git(*args: str) -> str:
    r = subprocess.run(["git", *args], cwd=GAME, capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""


def _blob_hash(path: Path) -> str:
    return _git("hash-object", str(path)).strip()


def artist_evidence(rel_dir: str) -> list[str]:
    """Sufficient evidence that this directory holds artist pixels."""
    out = []
    d = GAME / rel_dir
    if not d.is_dir():
        return out
    for png in sorted(d.glob("*.png")):
        rel = png.relative_to(GAME)
        baseline = _git("rev-parse", f"{ARTIST_BASELINE_TAG}:{rel}").strip()
        if baseline and baseline == _blob_hash(png):
            out.append(f"{png.name}: byte-identical to {ARTIST_BASELINE_TAG}")
            continue
        last = _git("log", "-1", "--format=%h", "--", str(rel)).strip()
        if last in ARTIST_IMPORT_COMMITS:
            out.append(f"{png.name}: content from {last} (artist import)")
    return out


def main() -> int:
    m = json.loads(MANIFEST.read_text())
    findings = []
    for section in ("sheets", "monster_sheets", "overworld_npc_sheets"):
        for key, val in sorted(m.get(section, {}).items()):
            if not isinstance(val, dict):
                continue
            tier = val.get("tier", "?")
            if tier != "T1":
                continue
            rel = str(val.get("path", "")).replace("res://", "")
            if not (GAME / rel).is_dir():
                continue
            ev = artist_evidence(rel)
            if ev:
                findings.append((section, key, ev))

    for section, key, ev in findings:
        print(f"\nTIER LIE  {section}/{key} is T1 but holds artist pixels:")
        for e in ev[:6]:
            print(f"    {e}")
        if len(ev) > 6:
            print(f"    … +{len(ev)-6} more")

    print(f"\n{len(findings)} tier lie(s) found")
    if not findings:
        print("No T1 entry contains provable artist pixels. Note this is a "
              "one-way check: it proves lies, never innocence.")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
