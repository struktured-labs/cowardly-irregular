#!/usr/bin/env python3
"""
Fix idle frame drift by duplicating frame 0 when frames diverge too much.

For job idle animations (2 frames): if width or height drift > threshold,
replace frame 1 with a copy of frame 0.

For monster strips (8 frames): idle is frames 0-1. If those two diverge,
replace frame 1 with frame 0. Leave frames 2-7 (attack/hit/dead) alone
since pose variation is expected there.

This is the "nuclear option" for the user-reported bugs — better to have
two identical idle frames than two wildly different ones that cause visual
splitting.
"""

import argparse
from pathlib import Path

from PIL import Image

GAME_REPO = Path("/home/struktured/projects/cowardly-irregular")
GAME_MONSTERS = GAME_REPO / "assets" / "sprites" / "monsters"
GAME_JOBS = GAME_REPO / "assets" / "sprites" / "jobs"

FRAME_SIZE = 256
DRIFT_THRESHOLD = 30  # pixels — if center or size drifts more than this, fix it

PROTECTED = {
    "fighter": {"idle", "walk", "attack", "hit", "dead", "cast", "defend", "item", "victory",
                "advance", "defer", "cleave", "power_strike", "provoke", "slash"},
    "rogue": {"idle", "attack", "cast"},
}


def measure_frame(img: Image.Image, frame_idx: int) -> dict | None:
    frame = img.crop((frame_idx * FRAME_SIZE, 0, (frame_idx + 1) * FRAME_SIZE, FRAME_SIZE))
    alpha = frame.split()[3]
    bbox = alpha.point(lambda p: 255 if p > 10 else 0).getbbox()
    if not bbox:
        return None
    return {
        "cx": (bbox[0] + bbox[2]) / 2,
        "cy": (bbox[1] + bbox[3]) / 2,
        "w": bbox[2] - bbox[0],
        "h": bbox[3] - bbox[1],
    }


def frames_drift_too_much(m0: dict, m1: dict) -> bool:
    cx_drift = abs(m0["cx"] - m1["cx"])
    cy_drift = abs(m0["cy"] - m1["cy"])
    w_drift = abs(m0["w"] - m1["w"])
    h_drift = abs(m0["h"] - m1["h"])
    return (cx_drift > DRIFT_THRESHOLD or cy_drift > DRIFT_THRESHOLD or
            w_drift > DRIFT_THRESHOLD or h_drift > DRIFT_THRESHOLD)


def fix_strip_idle(strip_path: Path, idle_frames: tuple = (0, 1)) -> bool:
    """If idle frames diverge, copy frame 0 over frame 1. Returns True if fixed."""
    img = Image.open(strip_path).convert("RGBA")
    w, h = img.size
    n_frames = w // FRAME_SIZE

    f0, f1 = idle_frames
    if f1 >= n_frames:
        return False

    m0 = measure_frame(img, f0)
    m1 = measure_frame(img, f1)
    if m0 is None or m1 is None:
        return False

    if not frames_drift_too_much(m0, m1):
        return False

    # Copy frame 0 content into frame 1's slot
    frame0 = img.crop((f0 * FRAME_SIZE, 0, (f0 + 1) * FRAME_SIZE, FRAME_SIZE))
    img.paste(frame0, (f1 * FRAME_SIZE, 0))
    img.save(strip_path)
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--threshold", type=int, default=DRIFT_THRESHOLD)
    args = parser.parse_args()

    threshold = args.threshold

    print(f"Drift threshold: {threshold}px\n")

    fixed_monsters = 0
    print("=== MONSTERS (idle = frames 0-1) ===")
    for png in sorted(GAME_MONSTERS.glob("*.png")):
        if "pre_normalize" in png.name or "import" in png.name:
            continue
        if fix_strip_idle(png, idle_frames=(0, 1)):
            print(f"  FIXED {png.name}")
            fixed_monsters += 1

    fixed_jobs = 0
    print("\n=== JOBS (idle.png = 2-frame strip) ===")
    for job_dir in sorted(GAME_JOBS.iterdir()):
        if not job_dir.is_dir():
            continue
        job = job_dir.name
        if job in PROTECTED and "idle" in PROTECTED[job]:
            continue

        idle_path = job_dir / "idle.png"
        if idle_path.exists():
            if fix_strip_idle(idle_path, idle_frames=(0, 1)):
                print(f"  FIXED {job}/idle")
                fixed_jobs += 1

    print(f"\nTotal fixed: {fixed_monsters} monsters + {fixed_jobs} job idles")


if __name__ == "__main__":
    main()
