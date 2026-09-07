#!/usr/bin/env python3
"""Re-run bad-frame cleanup on existing raw masterite strips.

Reads *_raw.png files and applies cleanup with calibrated thresholds,
then saves cleaned versions as the final output.

Usage:
    uv run python tools/reclean_masterites.py
    uv run python tools/reclean_masterites.py --dir tmp/generated/masterites_v2 --max-objects 8
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from PIL import Image
from tools.pipeline.cleanup import cleanup_strip, count_significant_objects
import numpy as np


# Calibrated per-world thresholds based on actual generation analysis:
# - Humanoid sprites (suburban): limbs, accessories, hair fragments = 6-12 objects normal
# - Mechanical (industrial): rigid connected bodies = fewer fragments
# - Digital/abstract: variable, but generally more cohesive
WORLD_THRESHOLDS = {
    "suburban": 8,
    "industrial": 6,
    "futuristic": 5,
    "abstract": 5,
}


def detect_world(filename: str) -> str:
    """Detect world from filename."""
    for world in WORLD_THRESHOLDS:
        if world in filename:
            return world
    return "unknown"


def main():
    parser = argparse.ArgumentParser(description="Re-clean masterite raw strips")
    parser.add_argument("--dir", default="tmp/generated/masterites_v2",
                        help="Directory with raw strips")
    parser.add_argument("--max-objects", type=int, default=None,
                        help="Override max objects threshold (default: auto per world)")
    parser.add_argument("--analyze-only", action="store_true",
                        help="Just report object counts, don't clean")
    args = parser.parse_args()

    raw_dir = Path(args.dir)
    raw_files = sorted(raw_dir.glob("*_raw.png"))

    if not raw_files:
        print(f"No *_raw.png files found in {raw_dir}")
        return

    print(f"Found {len(raw_files)} raw strips in {raw_dir}")

    all_reports = {}
    for raw_path in raw_files:
        monster_id = raw_path.stem.replace("_raw", "")
        world = detect_world(monster_id)
        threshold = args.max_objects or WORLD_THRESHOLDS.get(world, 5)

        strip = Image.open(raw_path)
        arr = np.array(strip)
        n_frames = arr.shape[1] // 256

        print(f"\n{monster_id} (world={world}, threshold={threshold}):")
        for i in range(n_frames):
            frame = arr[:, i * 256:(i + 1) * 256]
            n_objects = count_significant_objects(frame)
            opaque = (frame[:, :, 3] > 10).sum()
            status = "BAD" if n_objects > threshold else "ok"
            print(f"  Frame {i}: {n_objects:2d} objects, {opaque:6d} opaque px [{status}]")

        if args.analyze_only:
            continue

        cleaned, report = cleanup_strip(strip, frame_w=256, max_objects=threshold)
        if report:
            print(f"  -> Fixed {len(report)} bad frame(s)")
            for r in report:
                print(f"     Frame {r['bad_frame']}: {r['objects_found']} objects -> frame {r['replaced_with']}")
            all_reports[monster_id] = report
        else:
            print(f"  -> All frames clean")
            cleaned = strip

        out_path = raw_dir / f"{monster_id}.png"
        cleaned.save(out_path)
        print(f"  -> Saved: {out_path}")

    if not args.analyze_only and all_reports:
        # Update metadata
        meta_path = raw_dir / "generation_meta.json"
        if meta_path.exists():
            meta = json.loads(meta_path.read_text())
        else:
            meta = {}
        meta["cleanup_rerun"] = all_reports
        meta["cleanup_thresholds"] = WORLD_THRESHOLDS
        meta_path.write_text(json.dumps(meta, indent=2))
        print(f"\nMetadata updated: {meta_path}")

    total_fixed = sum(len(v) for v in all_reports.values())
    print(f"\nDone: {len(raw_files)} strips processed, {total_fixed} frames fixed")


if __name__ == "__main__":
    main()
