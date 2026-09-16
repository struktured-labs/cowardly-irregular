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
