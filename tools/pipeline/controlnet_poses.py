"""
ControlNet pose skeleton loader for the sprite generation pipeline.

Pose skeletons are pre-extracted by tools/extract_pose_skeletons.py and stored
under tools/pose_skeletons/{animation}/frame_{NN}.png.

Job-specific overrides can be placed under tools/pose_skeletons/{job}/{animation}/frame_{NN}.png.
These take priority over the default fighter poses.
"""

from pathlib import Path

from PIL import Image

from .config import PROJECT_DIR

POSE_SKELETONS_DIR = PROJECT_DIR / "tools" / "pose_skeletons"


def load_pose_skeleton(animation: str, frame_idx: int, job: str = None) -> "Image.Image | None":
    """Load pose skeleton for given animation frame.

    Checks job-specific override first, then default poses.
    Returns None if no skeleton is available (caller should skip ControlNet for that frame).

    Args:
        animation: Animation name (e.g. 'idle', 'attack', 'walk').
        frame_idx: Zero-based frame index within the animation strip.
        job: Optional job ID (e.g. 'mage', 'rogue'). When provided, looks for
             a job-specific pose override before falling back to default fighter poses.

    Returns:
        PIL Image (RGB) of the 768x768 skeleton on black background, or None.
    """
    frame_filename = f"frame_{frame_idx:02d}.png"
    candidates = []

    if job:
        candidates.append(POSE_SKELETONS_DIR / job / animation / frame_filename)

    candidates.append(POSE_SKELETONS_DIR / animation / frame_filename)

    for path in candidates:
        if path.exists():
            return Image.open(str(path)).convert("RGB")

    return None
