#!/usr/bin/env python3
"""Mass-fix monster sprite sheets whose non-idle frames are grid-mashed
animation dumps (see audit_broken_sprites.py output).

For each sheet with defective frames:
  1. Identify defective frame indices (score > threshold via audit)
  2. Find nearest clean frame (score=0)
  3. Copy the clean frame's pixels into the defective slot

Preserves animation timing: monsters won't stop animating, they'll just
skip a broken hit/dead frame by re-showing an idle/attack frame.

Trade-off vs full regen: this is fast, deterministic, free, and lossless
w.r.t. artist-approved frames. The monsters still animate, just with
a subset of unique frames. Downside: less visual variety on hit/dead.

Usage:
    uv run python tools/fix_broken_frames.py                     # dry-run
    uv run python tools/fix_broken_frames.py --apply             # write fixes
    uv run python tools/fix_broken_frames.py --score-cutoff 20   # min defect score
"""
import argparse
import json
import shutil
import sys
from pathlib import Path

from PIL import Image

PROJECT = Path(__file__).resolve().parent.parent
GAME_REPO = Path("/home/struktured/projects/cowardly-irregular-artist-ship")
AUDIT_JSON = PROJECT / "tmp" / "broken_sprite_audit.json"


def frame_score(entry: dict) -> int:
    return entry.get("score", 0)


def pick_replacement(frames: list[dict], broken_idx: int) -> int | None:
    """Return the index of the nearest clean frame (score=0). Prefer earlier."""
    n = len(frames)
    for dist in range(1, n):
        for cand in (broken_idx - dist, broken_idx + dist):
            if 0 <= cand < n and frame_score(frames[cand]) == 0:
                return cand
    return None


def fix_sheet(rel_path: str, per_frame: list[dict], score_cutoff: int, apply: bool) -> dict:
    abs_path = GAME_REPO / rel_path
    img = Image.open(abs_path).convert("RGBA")
    W, H = img.size
    frame_w = H  # square frames
    n = W // frame_w

    fixes = []
    for idx, entry in enumerate(per_frame):
        if frame_score(entry) < score_cutoff:
            continue
        replacement = pick_replacement(per_frame, idx)
        if replacement is None:
            fixes.append({"broken_idx": idx, "score": entry["score"], "replacement": None})
            continue
        fixes.append({
            "broken_idx": idx,
            "score": entry["score"],
            "replacement": replacement,
        })
        if apply:
            src_frame = img.crop((replacement * frame_w, 0,
                                  (replacement + 1) * frame_w, H))
            img.paste(src_frame, (idx * frame_w, 0))

    if apply and any(f["replacement"] is not None for f in fixes):
        # Backup once
        backup = abs_path.with_name(abs_path.stem + ".pre_frame_fix" + abs_path.suffix)
        if not backup.exists():
            shutil.copy2(abs_path, backup)
        img.save(abs_path)

    return {"path": rel_path, "fixes": fixes}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true",
                        help="write fixes (default: dry-run)")
    parser.add_argument("--score-cutoff", type=int, default=20,
                        help="minimum frame score to fix (default 20)")
    parser.add_argument("--pattern", default="", help="path substring filter")
    args = parser.parse_args()

    if not AUDIT_JSON.exists():
        print(f"ERROR: {AUDIT_JSON} not found. Run tools/audit_broken_sprites.py first.",
              file=sys.stderr)
        return 1

    audit = json.loads(AUDIT_JSON.read_text())

    # Load manifest to skip files not actually loaded
    manifest = json.loads((GAME_REPO / "data/sprite_manifest.json").read_text())
    loaded = set()

    def walk(n):
        if isinstance(n, dict):
            p = n.get("path")
            if isinstance(p, str) and p.startswith("res://"):
                loaded.add(p.replace("res://", ""))
            for v in n.values(): walk(v)
        elif isinstance(n, list):
            for v in n: walk(v)
    walk(manifest)

    fixed_count = 0
    frame_count = 0
    for r in audit:
        # Skip overworld sheets (grid layout, false positives)
        if "/overworld/" in r["path"] or r["path"].endswith("/overworld.png"):
            continue
        # Skip _raw files (not loaded in game)
        if "_raw.png" in r["path"]:
            continue
        # Skip unloaded assets
        if r["path"] not in loaded:
            continue
        if args.pattern and args.pattern not in r["path"]:
            continue
        # Any frame scored above cutoff?
        if not any(frame_score(f) >= args.score_cutoff for f in r["per_frame"]):
            continue

        result = fix_sheet(r["path"], r["per_frame"], args.score_cutoff, args.apply)
        real_fixes = [f for f in result["fixes"] if f["replacement"] is not None]
        no_clean = [f for f in result["fixes"] if f["replacement"] is None]
        if not (real_fixes or no_clean): continue
        fixed_count += 1
        frame_count += len(real_fixes)

        head = "APPLY" if args.apply else "would fix"
        for f in real_fixes:
            print(f"  {head} {r['path']}: frame {f['broken_idx']} "
                  f"(score {f['score']}) ← frame {f['replacement']}")
        for f in no_clean:
            print(f"  SKIP  {r['path']}: frame {f['broken_idx']} "
                  f"(score {f['score']}) — no clean neighbor")

    print(f"\n{'Fixed' if args.apply else 'Would fix'}: "
          f"{frame_count} broken frames across {fixed_count} sheets")
    return 0


if __name__ == "__main__":
    sys.exit(main())
