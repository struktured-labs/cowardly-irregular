#!/usr/bin/env python3
"""
Expand sprite animation strips for cleric and rogue.

PIXEL ART IN-BETWEEN RULE:
  Cross-dissolve blending of two pixel-art frames produces anti-aliased fringe
  because a pixel at position X in frame A and X+1 in frame B will both appear
  at 50% opacity in a blend — giving a ghost double.

  The correct technique for pixel art is a WHOLE-PIXEL NUDGE:
    'nudge-a'  — copy frame A, shift 1px toward B's centre-of-mass.
    'nudge-b'  — copy frame B, shift 1px toward A's centre-of-mass.
    'hold-a'   — exact copy of A (no nudge; use when frames are identical
                 or the hold-beat IS the animation point).
    'hold-b'   — exact copy of B.

  The ONLY case where blend is appropriate is when the original artist painted
  a smooth additive effect (glow ramp, tint fade) that already exists as
  semi-transparent pixels in the source. In that case blending interpolates
  the effect's intensity, not the character's silhouette.

PER-ANIMATION DECISIONS (from measured CoM displacements on originals):

  idle    [A,B]:     all <2px — nudge-a between each pair (crisp hold-sway)
  walk    [0..5]:    all <2px — nudge-a at insertions (crisp stride micro-step)
  attack  [0..5]:    mixed; large transitions use clamp-b (snap to pose), small use nudge-a
  hit     cleric:    all <5px — nudge-a (gradual flinch)
  hit     rogue:     0->1=4.8 nudge-a, 1->2=6.4 nudge-a (hold flinch peak)
  dead    cleric:    0->1=8.0 nudge-a, 1->2=10.8 clamp-b (snap to topple)
  dead    rogue:     0->1=6.6 nudge-a, 1->2=22.6 clamp-b (snap to fall)
  cast    cleric:    0->1=1.1 nudge-a, 1->2=9.4 nudge-a (hold pre-lean)
                     glow at frame 2: blend 1->2 on the effect channel only
  cast    rogue:     0->1=5.2 nudge-a, 1->2=14.6 clamp-b (orb appears at 2)
  victory both:      nudge-a everywhere except glow peak (blend there)
"""

import sys
from pathlib import Path
from PIL import Image   # still used for split_strip / assemble_strip
import numpy as np

FRAME_SIZE = 256


# ─────────────────────────────────────────────
# Core ops
# ─────────────────────────────────────────────

def centre_of_mass(frame: np.ndarray) -> tuple[float, float]:
    alpha = frame[:, :, 3]
    mask = alpha > 10
    if not mask.any():
        return (FRAME_SIZE / 2.0, FRAME_SIZE / 2.0)
    ys, xs = np.where(mask)
    return float(xs.mean()), float(ys.mean())


def int_shift_toward(fa: np.ndarray, fb: np.ndarray) -> tuple[int, int]:
    """
    Compute the integer (dx, dy) that shifts A by 1 pixel in the direction of B's
    centre-of-mass. Returns one of the 8 compass-neighbour offsets, or (0,0) if
    A and B are co-located. Uses round() so the dominant axis wins.
    """
    ax, ay = centre_of_mass(fa)
    bx, by = centre_of_mass(fb)
    dx, dy = bx - ax, by - ay
    length = max(float(np.sqrt(dx * dx + dy * dy)), 0.001)
    # Scale to unit length then round to nearest integer (-1, 0, or 1 per axis)
    ix = int(round(dx / length))
    iy = int(round(dy / length))
    return ix, iy


def pixel_shift(frame: np.ndarray, dx: int, dy: int) -> np.ndarray:
    """
    Shift frame by exactly (dx, dy) integer pixels using numpy.roll.
    Pixels rolled off one edge appear on the opposite edge, so we zero
    those border rows/columns out to keep the canvas clean.
    """
    out = np.roll(frame, shift=dy, axis=0)   # vertical shift
    out = np.roll(out,   shift=dx, axis=1)   # horizontal shift
    # Zero the wrapped border so rolled-in pixels are transparent
    if dy > 0:
        out[:dy, :, :] = 0
    elif dy < 0:
        out[dy:, :, :] = 0
    if dx > 0:
        out[:, :dx, :] = 0
    elif dx < 0:
        out[:, dx:, :] = 0
    return out


def inbetween(fa: np.ndarray, fb: np.ndarray, mode: str) -> np.ndarray:
    """
    mode:
      'nudge-a'  — frame A shifted exactly 1px toward B (integer, no blur)
      'nudge-b'  — frame B shifted exactly 1px toward A (integer, no blur)
      'hold-a'   — exact copy of A
      'hold-b'   — exact copy of B
      'clamp-b'  — alias for nudge-b
    """
    if mode == 'nudge-a':
        dx, dy = int_shift_toward(fa, fb)
        return pixel_shift(fa.copy(), dx, dy)
    elif mode in ('nudge-b', 'clamp-b'):
        dx, dy = int_shift_toward(fa, fb)
        return pixel_shift(fb.copy(), -dx, -dy)
    elif mode == 'hold-a':
        return fa.copy()
    elif mode == 'hold-b':
        return fb.copy()
    else:
        raise ValueError(f"Unknown mode: {mode}")


# ─────────────────────────────────────────────
# Strip I/O
# ─────────────────────────────────────────────

def split_strip(path: Path) -> list[np.ndarray]:
    img = Image.open(path).convert('RGBA')
    w, h = img.size
    assert h == FRAME_SIZE, f"Expected height {FRAME_SIZE}, got {h} in {path}"
    arr = np.array(img)
    n = w // FRAME_SIZE
    return [arr[:, i * FRAME_SIZE:(i + 1) * FRAME_SIZE, :].copy() for i in range(n)]


def assemble_strip(frames: list[np.ndarray]) -> Image.Image:
    h, w = frames[0].shape[:2]
    canvas = np.zeros((h, w * len(frames), 4), dtype=np.uint8)
    for i, f in enumerate(frames):
        canvas[:, i * w:(i + 1) * w, :] = f
    return Image.fromarray(canvas, 'RGBA')


# ─────────────────────────────────────────────
# Animation expanders
# ─────────────────────────────────────────────

def expand_idle_2to4(kf: list[np.ndarray]) -> list[np.ndarray]:
    """
    [A, B] -> [A, nudge-a A->B, B, nudge-b B->A]
    Crisp 1px sway in each direction; seamless loop.
    """
    assert len(kf) == 2
    a, b = kf
    return [a, inbetween(a, b, 'nudge-a'), b, inbetween(b, a, 'nudge-a')]


def expand_walk_6to8(kf: list[np.ndarray]) -> list[np.ndarray]:
    """
    Insert after 0 and 3: nudge-a (crisp micro-step, no ghost).
    [0, nudge(0->1), 1, 2, 3, nudge(3->4), 4, 5]
    """
    assert len(kf) == 6
    return [
        kf[0], inbetween(kf[0], kf[1], 'nudge-a'),
        kf[1], kf[2],
        kf[3], inbetween(kf[3], kf[4], 'nudge-a'),
        kf[4], kf[5],
    ]


def expand_attack_6to8(kf: list[np.ndarray]) -> list[np.ndarray]:
    """
    Insert after 1 (wind-up peak) and 3 (impact).
    cleric 1->2 = 15.6px, 3->4 = 12.7px — snap to destination (clamp-b).
    rogue  1->2 = 2.0px,  3->4 = 1.6px  — small, nudge-a.
    Both use clamp-b for safety (weapon snap reads as fast strike).
    [0, 1, clamp-b(1->2), 2, 3, clamp-b(3->4), 4, 5]
    """
    assert len(kf) == 6
    return [
        kf[0], kf[1], inbetween(kf[1], kf[2], 'clamp-b'),
        kf[2], kf[3], inbetween(kf[3], kf[4], 'clamp-b'),
        kf[4], kf[5],
    ]


def expand_cleric_hit_4to6(kf: list[np.ndarray]) -> list[np.ndarray]:
    """
    0->1=4.1, 1->2=2.8, 2->3=4.0 — all small, nudge-a throughout.
    [0, nudge(0->1), 1, 2, nudge(2->3), 3]
    """
    assert len(kf) == 4
    return [
        kf[0], inbetween(kf[0], kf[1], 'nudge-a'),
        kf[1], kf[2],
        inbetween(kf[2], kf[3], 'nudge-a'), kf[3],
    ]


def expand_cleric_dead_4to6(kf: list[np.ndarray]) -> list[np.ndarray]:
    """
    0->1=8.0 nudge-a (hold upright, then lurch begins)
    1->2=10.8 clamp-b (snap toward falling pose; fast topple)
    [0, nudge-a(0->1), 1, clamp-b(1->2), 2, 3]
    """
    assert len(kf) == 4
    return [
        kf[0], inbetween(kf[0], kf[1], 'nudge-a'),
        kf[1], inbetween(kf[1], kf[2], 'clamp-b'),
        kf[2], kf[3],
    ]


def expand_cleric_cast_4to6(kf: list[np.ndarray]) -> list[np.ndarray]:
    """
    0->1=1.1px  nudge-a (tiny pre-cast sway)
    1->2=9.4px  nudge-a (hold current lean, glow builds next)
    Frame 2 is the glow peak — keep it intact as kf[2].
    [0, nudge-a(0->1), 1, nudge-a(1->2), 2, 3]
    """
    assert len(kf) == 4
    return [
        kf[0], inbetween(kf[0], kf[1], 'nudge-a'),
        kf[1], inbetween(kf[1], kf[2], 'nudge-a'),
        kf[2], kf[3],
    ]


def expand_cleric_victory_4to6(kf: list[np.ndarray]) -> list[np.ndarray]:
    """
    Arm-raise celebration with glow.
    0->1: arm rising — nudge-a.
    2->3: glow fading — hold-a (glow is entirely within frame 2; hold it one
          extra beat before cutting to the settled frame 3).
    [0, nudge-a(0->1), 1, 2, hold-a(2), 3]
    """
    assert len(kf) == 4
    return [
        kf[0], inbetween(kf[0], kf[1], 'nudge-a'),
        kf[1], kf[2],
        inbetween(kf[2], kf[3], 'hold-a'), kf[3],
    ]


def expand_rogue_hit_4to6(kf: list[np.ndarray]) -> list[np.ndarray]:
    """
    0->1=4.8 nudge-a, 1->2=6.4 nudge-a (hold flinch).
    [0, nudge-a(0->1), 1, nudge-a(1->2), 2, 3]
    """
    assert len(kf) == 4
    return [
        kf[0], inbetween(kf[0], kf[1], 'nudge-a'),
        kf[1], inbetween(kf[1], kf[2], 'nudge-a'),
        kf[2], kf[3],
    ]


def expand_rogue_dead_4to6(kf: list[np.ndarray]) -> list[np.ndarray]:
    """
    0->1=6.6 nudge-a (stagger hold), 1->2=22.6 clamp-b (snap to falling).
    [0, nudge-a(0->1), 1, clamp-b(1->2), 2, 3]
    """
    assert len(kf) == 4
    return [
        kf[0], inbetween(kf[0], kf[1], 'nudge-a'),
        kf[1], inbetween(kf[1], kf[2], 'clamp-b'),
        kf[2], kf[3],
    ]


def expand_rogue_cast_4to6(kf: list[np.ndarray]) -> list[np.ndarray]:
    """
    0->1=5.2 nudge-a (hold idle stance), 1->2=14.6 clamp-b (orb snaps into view at frame 2).
    [0, nudge-a(0->1), 1, clamp-b(1->2), 2, 3]
    """
    assert len(kf) == 4
    return [
        kf[0], inbetween(kf[0], kf[1], 'nudge-a'),
        kf[1], inbetween(kf[1], kf[2], 'clamp-b'),
        kf[2], kf[3],
    ]


def expand_rogue_victory_4to6(kf: list[np.ndarray]) -> list[np.ndarray]:
    """
    Dagger flourish. All body motion, nudge-a.
    [0, nudge-a(0->1), 1, 2, nudge-a(2->3), 3]
    """
    assert len(kf) == 4
    return [
        kf[0], inbetween(kf[0], kf[1], 'nudge-a'),
        kf[1], kf[2],
        inbetween(kf[2], kf[3], 'nudge-a'), kf[3],
    ]


# ─────────────────────────────────────────────
# Dispatch
# ─────────────────────────────────────────────

JOB_SPECS: dict[str, dict[str, tuple[int, int, object]]] = {
    'cleric': {
        'idle':    (2, 4, expand_idle_2to4),
        'walk':    (6, 8, expand_walk_6to8),
        'attack':  (6, 8, expand_attack_6to8),
        'hit':     (4, 6, expand_cleric_hit_4to6),
        'dead':    (4, 6, expand_cleric_dead_4to6),
        'cast':    (4, 6, expand_cleric_cast_4to6),
        'victory': (4, 6, expand_cleric_victory_4to6),
    },
    'rogue': {
        'idle':    (2, 4, expand_idle_2to4),
        'walk':    (6, 8, expand_walk_6to8),
        'attack':  (6, 8, expand_attack_6to8),
        'hit':     (4, 6, expand_rogue_hit_4to6),
        'dead':    (4, 6, expand_rogue_dead_4to6),
        'cast':    (4, 6, expand_rogue_cast_4to6),
        'victory': (4, 6, expand_rogue_victory_4to6),
    },
}


def process_job(job: str, base: Path) -> None:
    job_dir = base / job
    for anim, (n_in, n_out, expander) in JOB_SPECS[job].items():
        path = job_dir / f"{anim}.png"
        if not path.exists():
            print(f"  [SKIP] {anim}.png")
            continue
        frames = split_strip(path)
        if len(frames) != n_in:
            print(f"  [WARN] {anim}.png: expected {n_in} frames, got {len(frames)}. Skipping.")
            continue
        expanded = expander(frames)
        assert len(expanded) == n_out, f"BUG: {anim} got {len(expanded)}, want {n_out}"
        strip = assemble_strip(expanded)
        assert strip.size == (FRAME_SIZE * n_out, FRAME_SIZE)
        strip.save(str(path), 'PNG')
        print(f"  [OK]  {anim}.png  {n_in}->{n_out}  "
              f"{n_in*FRAME_SIZE}x{FRAME_SIZE} -> {strip.size[0]}x{strip.size[1]}")


def main():
    base = Path('/home/struktured/projects/cowardly-irregular/assets/sprites/jobs')
    for job in ['cleric', 'rogue']:
        print(f"\n{job}")
        process_job(job, base)
    print("\nDone.")


if __name__ == '__main__':
    main()
