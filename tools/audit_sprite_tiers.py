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

# Derived, not curated. A curated hash list is the thing that let this rot in
# the first place — it only knows the drops someone remembered to add.
#
# A file's MOST RECENT commit decides what its pixels are now. If that commit
# says it took them from an artist source, they are artist pixels.
ARTIST_SOURCE = (
    ".aseprite", "artist drive archive", "artist-normalized",
    "artist tag-rename", "artist idle placeholder", "artist original",
    "restore artist", "artist sprite",
)
# ...unless the same subject also says a machine made them. This exclusion is
# load-bearing: my first attempt was a bare grep for "artist" and it called
# bard_sdxl "9/9 artist-sourced", because its subject says the LoRA was
# ARTIST-TRAINED. Trained-on-artist-work and drawn-by-the-artist are opposite
# claims about the pixels and share a word.
MACHINE_SOURCE = (
    "lora", "sdxl", "ml-gen", "ip-adapter", "controlnet", "gen_",
    "trained", "sweep", "procedural", "gpt-image", "diffusion",
)


def _git(*args: str) -> str:
    r = subprocess.run(["git", *args], cwd=GAME, capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""


def _blob_hash(path: Path) -> str:
    return _git("hash-object", str(path)).strip()


def artist_evidence(rel_path: str) -> list[str]:
    """Sufficient evidence that this entry's pixels are artist-made.

    Accepts BOTH manifest path shapes. The first version handled only
    directories, so it silently examined 13 of 143 entries — every
    monster_sheets and overworld_npc_sheets path is a single PNG — and then
    printed "No T1 entry contains provable artist pixels", a claim about all
    of them. The sentence was true about what it checked and false about
    what it implied. That is why main() now reports coverage and refuses to
    conclude anything if it collapses.
    """
    out = []
    p = GAME / rel_path
    if p.is_file() and p.suffix == ".png":
        pngs = [p]
    elif p.is_dir():
        pngs = sorted(p.glob("*.png"))
    else:
        return out
    for png in pngs:
        rel = png.relative_to(GAME)
        baseline = _git("rev-parse", f"{ARTIST_BASELINE_TAG}:{rel}").strip()
        if baseline and baseline == _blob_hash(png):
            out.append(f"{png.name}: byte-identical to {ARTIST_BASELINE_TAG}")
            continue
        # Walk newest -> oldest and take the FIRST DECISIVE commit. Using
        # only the newest is a false negative in the dangerous direction:
        # mage/idle's last commit is "strip purple canvas bg from mage
        # idle/attack/cast", a cleanup that says nothing about who drew the
        # pixels, and its parent is "artist tag-rename" over an artist drive
        # import. Neutral operations must not erase provenance — they are
        # the normal fate of shipped artist art.
        verdict = None
        for subj in _git("log", "--format=%s", "--", str(rel)).splitlines():
            s = subj.strip().lower()
            machine = any(w in s for w in MACHINE_SOURCE)
            artist = any(w in s for w in ARTIST_SOURCE)
            if machine and not artist:
                verdict = None
                break
            if artist and not machine:
                verdict = f"{png.name}: artist-source commit ({s[:56]})"
                break
        if verdict:
            out.append(verdict)
    return out


def self_check() -> bool:
    """Controls. A classifier nobody has tried to fool is a guess.

    Both directions matter and they fail differently: a false negative
    silently un-protects artist work (the bug this tool exists for), while a
    false positive would have me relabel machine sheets as artist and refuse
    to regenerate my own output.
    """
    must_be_artist = ["assets/sprites/jobs/fighter"]
    must_not_be = [
        "assets/sprites/jobs/bard_sdxl",     # subject says "artist-trained LoRA"
        "assets/sprites/jobs/mage_sdxl",
        "assets/sprites/jobs/guardian",      # v3 LoRA sweep, no artist source
        "assets/sprites/jobs/summoner",
    ]
    ok = True
    for d in must_be_artist:
        if not artist_evidence(d):
            print(f"CONTROL FAILED: {d} must read as artist and did not")
            ok = False
    for d in must_not_be:
        ev = artist_evidence(d)
        if ev:
            print(f"CONTROL FAILED: {d} must NOT read as artist — got {ev[:2]}")
            ok = False
    return ok


def main() -> int:
    if not self_check():
        print("\nControls failed — the classifier is wrong, so every result "
              "below is untrustworthy. Fix it before believing any of this.")
        return 2
    m = json.loads(MANIFEST.read_text())
    findings = []
    examined = 0
    skipped: list[str] = []
    t1_total = sum(
        1 for s in ("sheets", "monster_sheets", "overworld_npc_sheets")
        for v in m.get(s, {}).values()
        if isinstance(v, dict) and v.get("tier") == "T1"
    )
    for section in ("sheets", "monster_sheets", "overworld_npc_sheets"):
        for key, val in sorted(m.get(section, {}).items()):
            if not isinstance(val, dict):
                continue
            tier = val.get("tier", "?")
            if tier != "T1":
                continue
            rel = str(val.get("path", "")).replace("res://", "")
            target = GAME / rel
            if not (target.is_dir() or target.is_file()):
                skipped.append(f"{section}/{key} (path missing: {rel})")
                continue
            examined += 1
            ev = artist_evidence(rel)
            if ev:
                findings.append((section, key, ev))

    for section, key, ev in findings:
        print(f"\nTIER LIE  {section}/{key} is T1 but holds artist pixels:")
        for e in ev[:6]:
            print(f"    {e}")
        if len(ev) > 6:
            print(f"    … +{len(ev)-6} more")

    # COVERAGE CONTROL. Without this the tool once examined 13 of 143 entries
    # and reported a clean sweep — a vacuous pass is indistinguishable from a
    # clean corpus unless the count is stated. Every number below is what was
    # actually looked at, never what was intended.
    print(f"\nexamined {examined} of {t1_total} T1 entries")
    for s in skipped[:5]:
        print(f"  SKIPPED {s}")
    if len(skipped) > 5:
        print(f"  SKIPPED … +{len(skipped)-5} more")
    if examined < t1_total:
        print(f"\n{t1_total - examined} T1 entr(ies) could not be examined — "
              f"this run is INCOMPLETE and its clean result means nothing "
              f"for them.")
        return 2
    print(f"{len(findings)} tier lie(s) found")
    if not findings:
        print("No T1 entry contains provable artist pixels. One-way check: "
              "it proves lies, never innocence.")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
