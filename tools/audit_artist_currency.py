#!/usr/bin/env python3
"""Detect artist source files that the artist has SUPERSEDED upstream.

Every other audit in this directory asks whether an asset is present, wired,
and internally consistent. None of them can see the case found 2026-07-29:
a file that is present, wired, consistent -- and three months out of date,
because the artist revised it on their Drive and nobody pulled it back.

    Mage Main design.aseprite    ours:  1 frame  256x256   artist: 16 frames
    Rogue Main design.aseprite   ours:  1 frame  8bpp      artist: 11 frames
    Main Fighter animations      ours:  3 frames           artist:  6 frames

Those three are tracked in git and serve as the provenance baseline for the
starter jobs. The shipped PNGs are fine; the editable master is a design
still. A name-diff cannot see this -- the filenames match exactly.

TWO TRAPS THIS TOOL EXISTS TO AVOID REPEATING:

1. The Drive root has a LEADING SPACE: "gdrive: cowir", not "gdrive:cowir".
   NOTHING syncs it automatically, so this tool is the only thing that will
   notice a drop. The drop cron is commented out (2026-06-14, "embed script
   no longer covers enemies, manual ingest for now") and points at a path
   where the script no longer lives -- which is why a 2026-07-28 delivery
   (Knight animations, Mordaine arc) sat unretrieved until someone looked by
   hand. My commit message for this file's first version blamed a wrong path
   baked into the cron; `crontab -l` says otherwise, and I had not run it.

2. `rclone lsf -R` lists DIRECTORIES as well as files. Counting its lines
   gives 80 "PNGs" where there are 20. Always --files-only.

Usage:
    uv run python tools/audit_artist_currency.py
    uv run python tools/audit_artist_currency.py --pull tmp/provenance/newer
"""
import argparse
import hashlib
import json
import struct
import subprocess
import sys
from datetime import datetime
from pathlib import Path

SPRITES = Path("/home/struktured/projects/cowir-sprites")
GAME = Path("/home/struktured/projects/cowardly-irregular-artist-ship")
DRIVE = "gdrive: cowir"

# Extensions that are artist SOURCE. PNGs are excluded on purpose: we
# regenerate those constantly, so local-newer is the normal state and would
# bury the signal. Source files only change when the artist changes them.
SOURCE_EXT = {".aseprite", ".ase"}



def upstream() -> dict[str, tuple[int, datetime, str, str]]:
    """basename -> (size, mtime, full remote path, md5-or-empty).

    Uses md5 rather than size as the currency test. Size is a PROXY for
    content: two different files can share a byte count, and an artist
    re-save that changes pixels without changing length reads as current.
    Google Drive serves md5 for real files, so the proxy is unnecessary --
    it falls back to size only when a hash is genuinely unavailable.
    """
    r = subprocess.run(
        ["rclone", "lsjson", "-R", "--files-only", "--hash", DRIVE],
        capture_output=True, text=True, timeout=600)
    if r.returncode != 0:
        print(f"rclone failed ({r.returncode}): {r.stderr.strip()[:200]}",
              file=sys.stderr)
        return {}
    try:
        rows = json.loads(r.stdout)
    except json.JSONDecodeError as e:
        print(f"rclone lsjson returned unparseable output: {e}", file=sys.stderr)
        return {}
    return index_by_basename([
        r for r in rows if Path(r.get("Path", "")).suffix.lower() in SOURCE_EXT])


def index_by_basename(rows: list) -> dict[str, tuple[int, datetime, str, str]]:
    """Collapse remote rows to basename -> newest entry, refusing to guess.

    Local and remote directory layouts do not correspond, so basename is the
    only key that joins them -- which means two remote files sharing a
    basename collapse, and one is silently dropped. Live data has exactly one
    such pair (`Nazuna Mini.aseprite`, present in two folders) and it is safe
    because both copies are byte-identical.

    Identical duplicates collapse silently. NON-identical ones cannot be
    mapped to a local copy without guessing, so they are reported instead of
    resolved. Currently unexercised -- which is the point: the artist's
    per-job `claude/<npc>_overworld.aseprite` convention is one naming change
    away from producing a real collision, and a silent wrong pick then looks
    exactly like a clean sweep.
    """
    groups: dict[str, list] = {}
    for row in rows:
        groups.setdefault(Path(row.get("Path", "")).name, []).append(row)

    out, ambiguous = {}, []
    for name, rs in groups.items():
        hashes = {(r.get("Hashes") or {}).get("md5", "") for r in rs}
        if len(rs) > 1 and len(hashes) > 1:
            ambiguous.append((name, [r.get("Path", "") for r in rs]))
            continue
        row = max(rs, key=lambda r: str(r.get("ModTime", "")))
        mod = str(row.get("ModTime", ""))[:19].replace("T", " ")
        try:
            dt = datetime.strptime(mod, "%Y-%m-%d %H:%M:%S")
        except ValueError:
            continue
        out[name] = (int(row.get("Size", -1)), dt, row.get("Path", ""),
                     (row.get("Hashes") or {}).get("md5", "") or "")

    if ambiguous:
        print(f"\n=== AMBIGUOUS BASENAMES ({len(ambiguous)}) -- NOT CHECKED ===")
        for name, paths in ambiguous:
            print(f"  {name}: {len(paths)} differing remote copies, cannot map "
                  f"to a local file by name alone")
            for p in paths:
                print(f"      {p}")
    return out


def md5_of(p: Path) -> str:
    h = hashlib.md5()
    try:
        with open(p, "rb") as fh:
            for chunk in iter(lambda: fh.read(1 << 20), b""):
                h.update(chunk)
    except OSError:
        return ""
    return h.hexdigest()


def local() -> dict[str, list[Path]]:
    """basename -> [paths]. Searched across BOTH repos, since the tracked
    masters live in the game repo and working copies live here."""
    out: dict[str, list[Path]] = {}
    for root in (SPRITES, GAME):
        if not root.exists():
            continue
        for p in root.rglob("*"):
            if ".git" in p.parts or p.suffix.lower() not in SOURCE_EXT:
                continue
            out.setdefault(p.name, []).append(p)
    return out


def tracked_sources() -> set[Path]:
    """Absolute paths of every source file git tracks, in both repos.

    Collected once as a set rather than shelling out per file: a per-file
    `git ls-files --error-unmatch` is ~80 subprocesses, and its non-zero exit
    is indistinguishable from git being absent, which would silently make
    every file look untracked and re-open the exact hole this predicate fix
    closes.
    """
    out: set[Path] = set()
    for root in (SPRITES, GAME):
        if not (root / ".git").exists():
            continue
        r = subprocess.run(["git", "-C", str(root), "ls-files"],
                           capture_output=True, text=True, timeout=120)
        if r.returncode != 0:
            print(f"WARNING: git ls-files failed in {root} -- tracked-vs-scratch "
                  f"cannot be distinguished, so staleness may be under-reported",
                  file=sys.stderr)
            continue
        for line in r.stdout.splitlines():
            if Path(line).suffix.lower() in SOURCE_EXT:
                out.add(root / line)
    return out


_TRACKED: set[Path] = set()


def is_tracked(p: Path) -> bool:
    return p in _TRACKED


def aseprite_header(p: Path) -> str:
    """frames/canvas, so a report says what actually differs rather than
    just that the bytes do. Bad magic is reported, never silently skipped."""
    try:
        b = p.read_bytes()[:14]
        if len(b) < 14:
            return "truncated"
        _, magic, frames, w, h, depth = struct.unpack_from("<IHHHHH", b, 0)
        if magic != 0xA5E0:
            return f"not-aseprite(0x{magic:04X})"
        return f"{frames}f {w}x{h} {depth}bpp"
    except OSError as e:
        return f"unreadable({e.errno})"


def self_check() -> int:
    """Exercise the collision branch, which live data does not reach.

    Both directions, because a one-sided control cannot tell a working
    predicate from one that always fires.
    """
    def row(path, md5, mod="2026-01-01T00:00:00Z", size=10):
        return {"Path": path, "Size": size, "ModTime": mod, "Hashes": {"md5": md5}}

    ok = True
    same = index_by_basename([row("a/x.aseprite", "AAA"), row("b/x.aseprite", "AAA")])
    if list(same) != ["x.aseprite"]:
        print(f"FAIL identical duplicates should collapse to one entry: {list(same)}")
        ok = False

    diff = index_by_basename([row("a/y.aseprite", "AAA"), row("b/y.aseprite", "BBB")])
    if "y.aseprite" in diff:
        print("FAIL differing duplicates must be withheld, not silently picked")
        ok = False

    # Control: a lone file must survive both, or the two checks above would
    # pass simply because nothing ever gets through.
    solo = index_by_basename([row("a/z.aseprite", "CCC")])
    if list(solo) != ["z.aseprite"]:
        print(f"FAIL a non-colliding file must pass through: {list(solo)}")
        ok = False

    print("self-check PASSED" if ok else "self-check FAILED")
    return 0 if ok else 1


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pull", metavar="DIR", default=None,
                    help="download artist-newer files to DIR (never overwrites "
                         "in place -- artist assets need explicit approval)")
    ap.add_argument("--self-check", action="store_true",
                    help="exercise the collision branch on synthetic input")
    args = ap.parse_args()

    if args.self_check:
        return self_check()

    global _TRACKED
    _TRACKED = tracked_sources()
    up, loc = upstream(), local()

    # COVERAGE CONTROL. A clean sweep over an empty corpus is not a clean
    # corpus, and this tool's failure mode is a silent one: wrong Drive path
    # -> zero upstream entries -> "everything current". That is exactly how
    # the drop cron reported success for months.
    print(f"upstream source files: {len(up)}   local source files: {len(loc)}")
    if not up or not loc:
        print("REFUSING TO REPORT: a zero above means this sweep read nothing. "
              f"Check the Drive root -- it is '{DRIVE}', WITH the leading space.")
        return 2

    hashed = sum(1 for v in up.values() if v[3])
    print(f"upstream files with md5 from the remote: {hashed}/{len(up)}"
          f"{'  (rest fall back to size)' if hashed < len(up) else ''}")

    newer, diverged, absent = [], [], []
    for name, (usize, udt, rpath, umd5) in sorted(up.items()):
        paths = loc.get(name)
        if not paths:
            absent.append((name, udt, rpath))
            continue
        # WHICH copy has to be current is the whole predicate, and the first
        # version of this got it wrong. It asked "does ANY local copy match
        # upstream", which was silenced the moment a staging pull landed in
        # tmp/ -- reporting 0 while three git-tracked masters were three
        # months stale. A scratch copy is not currency.
        #
        # The authoritative copy is the one git tracks, because that is what
        # ships and what an artist edit would have to land in. Fall back to
        # the newest copy only when nothing is tracked.
        tracked = [p for p in paths if is_tracked(p)]
        candidates = tracked or paths
        # md5 when the remote gives one, size only as a documented fallback.
        if umd5:
            if any(md5_of(p) == umd5 for p in candidates):
                continue
        elif any(p.stat().st_size == usize for p in candidates):
            continue
        p = max(candidates, key=lambda x: x.stat().st_mtime)
        ldt = datetime.fromtimestamp(p.stat().st_mtime)
        rel = p.relative_to(GAME if GAME in p.parents else SPRITES)
        row = (name, p, rel, usize, udt, p.stat().st_size, ldt, rpath,
               bool(tracked))
        (newer if udt > ldt else diverged).append(row)

    if absent:
        print(f"\n=== NEVER PULLED ({len(absent)}) ===")
        for name, udt, rpath in absent:
            print(f"  {udt:%Y-%m-%d}  {name}\n      {rpath}")

    if newer:
        print(f"\n=== ARTIST SUPERSEDED OURS ({len(newer)}) ===")
        for name, p, rel, usize, udt, lsize, ldt, rpath, tracked in newer:
            print(f"  {name}{'   [TRACKED IN GIT]' if tracked else ''}")
            print(f"      ours   {ldt:%Y-%m-%d}  {lsize:>8}B  {aseprite_header(p)}   {rel}")
            print(f"      artist {udt:%Y-%m-%d}  {usize:>8}B  (upstream)")

    if diverged:
        print(f"\n=== ours newer, informational ({len(diverged)}) ===")
        for name, *_ in diverged[:5]:
            print(f"  {name}")
        if len(diverged) > 5:
            print(f"  ... and {len(diverged) - 5} more")

    if args.pull and (newer or absent):
        dest = Path(args.pull)
        dest.mkdir(parents=True, exist_ok=True)
        for row in newer:
            rpath = row[-1]
            subprocess.run(["rclone", "copy", f"{DRIVE}/{rpath}", str(dest)],
                           timeout=300)
        for name, udt, rpath in absent:
            subprocess.run(["rclone", "copy", f"{DRIVE}/{rpath}", str(dest)],
                           timeout=300)
        print(f"\npulled to {dest} -- NOT applied over the originals; "
              f"overwriting artist assets needs struktured's approval")

    total = len(newer) + len(absent)
    print(f"\n{total} file(s) where the artist has work we do not")
    return 0


if __name__ == "__main__":
    sys.exit(main())
