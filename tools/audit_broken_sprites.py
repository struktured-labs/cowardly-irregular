#!/usr/bin/env python3
"""Audit all monster + job sprites for broken/duplicate/stray-object frames.

Detects three defects the main linter doesn't catch:

  1. multi_body — frame has 2+ connected components each ≥ 15% of the
     largest. Indicates duplicated body, side-by-side twin, or two
     characters merged.

  2. stray_object — frame has a small (0.5% to 15% of main body) blob
     detached from the main silhouette by ≥ 8px. Usually a floating
     weapon fragment, halo dot, or generation artifact.

  3. edge_touch — content silhouette touches ≥ 2 opposing frame edges.
     Portraits truncated, sprites clipped by canvas.

Ranks worst offenders and emits a priority repair list.

Usage:
    uv run python tools/audit_broken_sprites.py                    # all sprites
    uv run python tools/audit_broken_sprites.py --pattern monster  # subset
    uv run python tools/audit_broken_sprites.py --json out.json
"""
import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path

from sprite_corpus import banner, default_root

import numpy as np
from PIL import Image
from scipy import ndimage

GAME_REPO = default_root()
SPRITES_ROOT = GAME_REPO / "assets/sprites"

# frame width for known assets; detected from height when unknown
KNOWN_FRAME_SIZES = {
    "monsters": 256,   # AI sheets; slime/bat/goblin are 128 but the mask splitter still works per-frame
    "jobs":     256,
    "portraits": None,  # single-image, treat whole file as one frame
}

ALPHA_THRESHOLD = 32   # a pixel counts as "content" if alpha > this
MIN_COMPONENT_PX = 6   # ignore microscopic dots
MULTI_BODY_RATIO = 0.15  # 2nd component ≥ 15% of largest → multi-body
STRAY_MIN_RATIO = 0.005  # 0.5% of largest → stray
STRAY_MAX_RATIO = 0.15   # ≥ 15% → not stray, multi-body
STRAY_MIN_GAP = 8        # pixels of separation from main


_DECLARED_CELLS: dict[str, tuple[int, int]] | None = None


def declared_cells() -> dict[str, tuple[int, int]]:
    """path -> (frame_w, frame_h) for every manifest entry that declares one.

    ⛔ THE HEURISTIC BELOW IS A STRIP HEURISTIC AND THE CORPUS HAS GRIDS. `H <= 128 -> frame_w =
    128` plus a horizontal-only split turns a 128x128 overworld sheet into ONE frame holding
    SIXTEEN figures — reported as `multi_body x15`, which is the grid being counted rather than a
    broken sprite. Measured 2026-09-17 on the game repo: 275 of 666 files scored non-zero, and the
    overworld sheets among them were all this. A detector that floods hides the findings it has.

    So the DECLARATION wins where there is one and the heuristic is the fallback, which is the
    same repair `audit_sprite_wiring` needed for the same conflation the day before.
    """
    global _DECLARED_CELLS
    if _DECLARED_CELLS is None:
        _DECLARED_CELLS = {}
        mf = GAME_REPO / "data" / "sprite_manifest.json"
        try:
            data = json.loads(mf.read_text())
        except Exception:
            return _DECLARED_CELLS
        for section, node in data.items():
            if not isinstance(node, dict):
                continue
            for entry in node.values():
                if not isinstance(entry, dict):
                    continue
                path = str(entry.get("path", ""))
                fw, fh = entry.get("frame_width"), entry.get("frame_height")
                if path.endswith(".png") and fw and fh:
                    _DECLARED_CELLS[path.replace("res://", "")] = (int(fw), int(fh))
    return _DECLARED_CELLS


def convention_cell(rel: str) -> tuple[int, int] | None:
    """The cell size the RUNTIME slices an overworld sheet at, for sheets the manifest omits.

    ⛔ THE MANIFEST DECLARES 10 OF 116 OVERWORLD MONSTER SHEETS — that section is an audit ledger
    and the art is reached by PATH CONVENTION (see HybridSpriteLoader.npc_overworld_path). So
    `declared_cells()` alone still left 85 grid sheets on the strip heuristic, reported as
    `multi_body x15` through `x63` — the grid being counted, not a defect.

    32px is not a guess: RoamingMonster.FRAME_W, OverworldNPC._ARCHETYPE_FRAME_W and
    OverworldPlayer.SPRITE_SIZE are all 32, and every one of the 85 sheets is 128x128. A detector
    should slice the way the engine slices, or it is measuring a picture the game never draws.
    """
    if "/overworld/" in rel or Path(rel).name.startswith("overworld"):
        return (32, 32)
    return None


def split_cells(img: np.ndarray, fw: int, fh: int) -> list[np.ndarray]:
    """Every cell of a GRID sheet, row-major. One frame when the sheet is a single cell."""
    H, W = img.shape[:2]
    if fw <= 0 or fh <= 0:
        return [img]
    cols, rows = max(1, W // fw), max(1, H // fh)
    return [img[r * fh:(r + 1) * fh, c * fw:(c + 1) * fw]
            for r in range(rows) for c in range(cols)]


def split_frames(img: np.ndarray, frame_w: int) -> list[np.ndarray]:
    """Split a horizontal strip into square-ish frames of frame_w wide."""
    H, W = img.shape[:2]
    if W <= frame_w * 1.1:
        return [img]
    n = W // frame_w
    return [img[:, i * frame_w:(i + 1) * frame_w] for i in range(n)]


def analyze_frame(frame: np.ndarray) -> dict:
    """Run all 3 checks on a single square frame."""
    if frame.shape[2] < 4:
        return {"skipped": "no_alpha"}
    mask = frame[:, :, 3] > ALPHA_THRESHOLD
    if not mask.any():
        return {"empty": True}

    labeled, n = ndimage.label(mask)
    if n == 0:
        return {"empty": True}

    sizes = ndimage.sum_labels(mask, labeled, range(1, n + 1))
    order = np.argsort(sizes)[::-1]  # largest first
    # Drop microscopic noise
    order = [i for i in order if sizes[i] >= MIN_COMPONENT_PX]
    if not order:
        return {"empty": True}
    biggest = int(sizes[order[0]])
    biggest_id = order[0] + 1

    # --- multi_body ---
    seconds = [int(sizes[i]) for i in order[1:] if sizes[i] / biggest >= MULTI_BODY_RATIO]

    # --- stray_object ---
    strays = []
    main_ys, main_xs = np.where(labeled == biggest_id)
    main_ymin, main_ymax = main_ys.min(), main_ys.max()
    main_xmin, main_xmax = main_xs.min(), main_xs.max()
    for i in order[1:]:
        size = int(sizes[i])
        ratio = size / biggest
        if not (STRAY_MIN_RATIO <= ratio < STRAY_MAX_RATIO):
            continue
        ys, xs = np.where(labeled == i + 1)
        # Compute min distance to main bbox
        dy = max(0, main_ymin - ys.max(), ys.min() - main_ymax)
        dx = max(0, main_xmin - xs.max(), xs.min() - main_xmax)
        gap = max(dx, dy)
        if gap >= STRAY_MIN_GAP:
            strays.append({"size": size, "gap": gap, "at": (int(xs.mean()), int(ys.mean()))})

    # --- edge_touch ---
    H, W = mask.shape
    edges_touched = []
    if mask[0, :].any(): edges_touched.append("top")
    if mask[-1, :].any(): edges_touched.append("bottom")
    if mask[:, 0].any(): edges_touched.append("left")
    if mask[:, -1].any(): edges_touched.append("right")
    edge_defect = (
        {"top", "bottom"}.issubset(edges_touched)
        or {"left", "right"}.issubset(edges_touched)
    )

    return {
        "components": len(order),
        "biggest_px": biggest,
        "multi_body": len(seconds),
        "seconds_px": seconds,
        "strays": strays,
        "edges_touched": edges_touched,
        "edge_defect": edge_defect,
    }


def score_frame(analysis: dict) -> int:
    """Higher = worse."""
    if analysis.get("empty") or analysis.get("skipped"):
        return 0
    s = 0
    s += 10 * analysis["multi_body"]   # multi-body is the big deal
    s += 4 * len(analysis["strays"])   # strays are minor to moderate
    s += 6 if analysis["edge_defect"] else 0
    return s


def audit_file(path: Path) -> dict:
    img = np.array(Image.open(path).convert("RGBA"))
    H, W = img.shape[:2]
    # Guess frame width: monster/job sheets 256 or 128; portrait single 256
    rel = str(path.relative_to(GAME_REPO)) if str(path).startswith(str(GAME_REPO)) else str(path)
    cell = declared_cells().get(rel)
    if cell is None:
        cell = convention_cell(rel)
    if cell is not None:
        frame_w = cell[0]
        frames = split_cells(img, cell[0], cell[1])
    else:
        if "portraits" in str(path):
            frame_w = W
        elif H <= 128:
            frame_w = 128
        else:
            frame_w = 256
        frames = split_frames(img, frame_w)
    results = []
    for idx, frame in enumerate(frames):
        a = analyze_frame(frame)
        a["frame_idx"] = idx
        a["score"] = score_frame(a)
        results.append(a)
    max_score = max(r["score"] for r in results) if results else 0
    worst = [r for r in results if r["score"] == max_score and max_score > 0]
    return {
        "path": str(path.relative_to(GAME_REPO)),
        "frames": len(frames),
        "frame_w": frame_w,
        "max_score": max_score,
        "worst_frames": [r["frame_idx"] for r in worst],
        "per_frame": results,
    }


def main() -> int:
    print(banner(GAME_REPO))
    print()
    parser = argparse.ArgumentParser()
    parser.add_argument("--pattern", default="",
                        help="substring filter on path (e.g. 'monsters' or 'fighter')")
    parser.add_argument("--json", type=Path, help="write full report to path")
    parser.add_argument("--top", type=int, default=25, help="show top N")
    args = parser.parse_args()

    scan_dirs = [
        SPRITES_ROOT / "monsters",
        SPRITES_ROOT / "jobs",
        SPRITES_ROOT / "portraits",
    ]

    files = []
    for d in scan_dirs:
        if not d.exists(): continue
        for p in d.rglob("*.png"):
            # skip backups + import artifacts
            name = p.name
            if any(k in name for k in [".pre_", "_backup", ".import"]):
                continue
            if args.pattern and args.pattern not in str(p):
                continue
            files.append(p)

    print(f"Scanning {len(files)} sprite files ...")
    reports = []
    for p in files:
        try:
            r = audit_file(p)
            reports.append(r)
        except Exception as e:
            print(f"  ERROR on {p.name}: {e}", file=sys.stderr)

    reports.sort(key=lambda r: r["max_score"], reverse=True)

    print(f"\n=== Top {args.top} worst offenders ===")
    for r in reports[:args.top]:
        if r["max_score"] == 0: break
        # Get one worst-frame summary
        wf = r["per_frame"][r["worst_frames"][0]]
        summary_parts = []
        if wf["multi_body"]:
            summary_parts.append(f"multi_body×{wf['multi_body']} (2nd={wf['seconds_px']})")
        if wf["strays"]:
            summary_parts.append(f"strays={len(wf['strays'])}")
        if wf["edge_defect"]:
            summary_parts.append(f"edge={'+'.join(wf['edges_touched'])}")
        print(f"  score={r['max_score']:3d}  frame={r['worst_frames'][0]:2d}/{r['frames']:2d}  "
              f"{r['path']}  [{', '.join(summary_parts)}]")

    print(f"\nTotal files with score > 0: "
          f"{sum(1 for r in reports if r['max_score'] > 0)} / {len(reports)}")

    if args.json:
        args.json.write_text(json.dumps(reports, indent=2, default=int))
        print(f"Wrote full report to {args.json}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
