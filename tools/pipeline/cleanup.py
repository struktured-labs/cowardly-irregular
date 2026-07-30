"""Bad-frame detection and cleanup for monster sprite strips.

Detects frames with multiple significant objects (>3) and replaces
them with the nearest good neighbor frame. This fixes SDXL's tendency
to sometimes generate sprite sheets or multi-character compositions
in individual frames.
"""
import numpy as np
from PIL import Image
from scipy import ndimage


def count_significant_objects(frame_arr: np.ndarray, min_size_fraction: float = 0.005) -> int:
    """Count the number of significant (non-tiny) objects in a single frame.

    Args:
        frame_arr: RGBA numpy array of a single frame.
        min_size_fraction: Minimum fraction of total opaque pixels for an
            object to be considered "significant". Default 0.5% filters
            out dust/orphan pixels while catching real multi-character issues.

    Returns:
        Number of significant connected components.
    """
    mask = frame_arr[:, :, 3] > 10
    if not mask.any():
        return 0

    total_opaque = mask.sum()
    min_size = max(20, int(total_opaque * min_size_fraction))

    labeled, n_components = ndimage.label(mask, structure=ndimage.generate_binary_structure(2, 2))

    significant = 0
    for i in range(1, n_components + 1):
        if (labeled == i).sum() >= min_size:
            significant += 1

    return significant


def detect_bad_frames(strip: Image.Image, frame_w: int = 256,
                      max_objects: int = 3) -> list[int]:
    """Detect frames in a horizontal strip that have too many objects.

    Args:
        strip: Horizontal sprite strip (N*frame_w x frame_h).
        frame_w: Width of each frame.
        max_objects: Maximum allowed significant objects per frame.

    Returns:
        List of bad frame indices.
    """
    arr = np.array(strip)
    n_frames = arr.shape[1] // frame_w
    bad = []

    for i in range(n_frames):
        frame = arr[:, i * frame_w:(i + 1) * frame_w]
        n_objects = count_significant_objects(frame)
        if n_objects > max_objects:
            bad.append(i)

    return bad


def find_nearest_good(bad_idx: int, bad_set: set, n_frames: int) -> int:
    """Find the nearest good frame index to a bad frame.

    Searches outward from bad_idx, preferring left (earlier) frames.
    """
    for dist in range(1, n_frames):
        for candidate in [bad_idx - dist, bad_idx + dist]:
            if 0 <= candidate < n_frames and candidate not in bad_set:
                return candidate
    return 0  # fallback: frame 0 is always the reference


def cleanup_strip(strip: Image.Image, frame_w: int = 256,
                  max_objects: int = 3) -> tuple[Image.Image, list[dict]]:
    """Detect and fix bad frames in a sprite strip.

    Bad frames (>max_objects significant objects) are replaced by copying
    the nearest good neighbor frame.

    Args:
        strip: Horizontal sprite strip.
        frame_w: Width of each frame.
        max_objects: Maximum allowed significant objects per frame.

    Returns:
        (cleaned_strip, report) where report is a list of dicts describing
        each replacement made.
    """
    arr = np.array(strip)
    n_frames = arr.shape[1] // frame_w
    bad_indices = detect_bad_frames(strip, frame_w, max_objects)

    if not bad_indices:
        return strip, []

    bad_set = set(bad_indices)
    report = []

    for bad_idx in bad_indices:
        n_objects = count_significant_objects(
            arr[:, bad_idx * frame_w:(bad_idx + 1) * frame_w]
        )
        good_idx = find_nearest_good(bad_idx, bad_set, n_frames)
        # Copy good frame into bad frame's slot
        good_frame = arr[:, good_idx * frame_w:(good_idx + 1) * frame_w].copy()
        arr[:, bad_idx * frame_w:(bad_idx + 1) * frame_w] = good_frame
        report.append({
            "bad_frame": bad_idx,
            "objects_found": n_objects,
            "replaced_with": good_idx,
        })

    return Image.fromarray(arr), report
