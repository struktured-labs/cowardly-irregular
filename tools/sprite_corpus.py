#!/usr/bin/env python3
"""Name the tree a sprite-lane tool is ABOUT, which is not the tree you are in.

⛔ TWENTY-THREE TOOLS IN THIS DIRECTORY HARDCODE
`/home/struktured/projects/cowardly-irregular-artist-ship` as their root. That
is the sprite lane's convention and NOT a bug: artist deliveries land in a
dedicated checkout. The defect was that their OUTPUT never said so, and a
finding with no corpus reads as a finding about the repo you are standing in.

📌 THE COST, measured on myself 2026-09-16, which is why this exists.
`audit_sprite_wiring.py` reported cartographer_wraith and dark_knight as ORPHAN
with 0 refs. Both are TRUE of the audited tree (108 monster_sheets entries,
neither registered) and FALSE of the game repo (114 entries, both wired, the
manifest pointing at those exact bytes — sha-verified identical). I wrote the
finding into a commit as a live game defect before checking which tree produced
it. The audited checkout was 30 days stale; the gaps had been closed weeks
earlier.

🔑 The fleet rule is "state the corpus as part of the claim". A tool that PRINTS
findings has to state it FOR the reader, because the reader is the one who will
quote it — and a stale corpus is invisible in a finding that looks current.

⚠️ SHARED RATHER THAN COPIED, deliberately. This fleet counted 18 redundant
private comment-strippers in one day; five private banners would be the same
mistake with a different subject. If a sixth tool needs this, import it.
"""
from __future__ import annotations

import datetime
import os
import subprocess
from pathlib import Path

STALE_DAYS = 7


def _git(root: Path, *args: str) -> str:
    try:
        return subprocess.run(["git", "-C", str(root), *args],
                              capture_output=True, text=True,
                              timeout=20).stdout.strip()
    except Exception:
        return ""


def banner(root: Path) -> str:
    """One block naming the audited tree, its revision, and how stale it is."""
    if not Path(root).exists():
        return (f"CORPUS: {root}\n"
                f"        ⛔ THIS PATH DOES NOT EXIST — every check below will "
                f"report an empty, clean-looking corpus")
    head = _git(root, "rev-parse", "--short", "HEAD") or "?"
    branch = _git(root, "rev-parse", "--abbrev-ref", "HEAD") or "?"
    when = _git(root, "log", "-1", "--format=%cs") or "?"
    age = ""
    try:
        days = (datetime.date.today() - datetime.date.fromisoformat(when)).days
        if days >= STALE_DAYS:
            age = f"  ⚠️ {days} days stale"
    except ValueError:
        pass
    return (f"CORPUS: {root}\n"
            f"        {branch} @ {head}, last commit {when}{age}\n"
            f"        findings below are about THAT tree, not your working directory")


ARTIST_SHIP = Path("/home/struktured/projects/cowardly-irregular-artist-ship")
ROOT_ENV = "COWIR_SPRITE_ROOT"


def default_root() -> Path:
    """The tree a READ-ONLY sprite auditor should examine.

    Defaults to the artist-delivery checkout, unchanged, so every existing
    invocation keeps its corpus. `COWIR_SPRITE_ROOT=<path>` points the audit at
    another tree — normally the game repo you are standing in, which until now
    could not be audited by these tools at all. That is what let the delivery
    tree sit 30 days stale with nobody noticing: there was no second reading to
    disagree with it.

    ⛔ READ-ONLY TOOLS ONLY, and the asymmetry is deliberate. The 18 GENERATORS
    that share this root write PNGs. A redirect on those is a footgun pointed at
    artist work — CLAUDE.md's rule is that AI generation must never overwrite
    artist assets, and an env var that silently retargets writes is exactly how
    that happens by accident. Generators keep their literal path.
    """
    return Path(os.environ.get(ROOT_ENV) or ARTIST_SHIP)
