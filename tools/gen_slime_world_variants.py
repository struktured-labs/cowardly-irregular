#!/usr/bin/env python3
"""Deterministic per-world palette variants of the artist slime sprite.

The artist delivered a green slime (`assets/sprites/monsters/slime.png`,
1408x128, 11 frames). Each of the 6 game worlds has a distinct visual
theme; we hue-rotate the slime in HSV space (preserving value &
saturation pattern, only shifting hue) so the artist's exact pixel
placement, sel-out, and shading discipline are preserved 1:1.

This is NOT ML — pure numpy. Reproducible, fast, no drift.

World 1 (medieval) keeps the original green; we generate variants for
worlds 2-6.

Output: 5 PNGs at the same resolution as the source, written into the
game repo's `assets/sprites/monsters/`.
"""

from __future__ import annotations

import sys
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image

GAME_REPO = Path(__file__).resolve().parents[1].parent / "cowardly-irregular"
SOURCE = GAME_REPO / "assets/sprites/monsters/slime.png"
OUT_DIR = GAME_REPO / "assets/sprites/monsters"


@dataclass(frozen=True)
class Variant:
    name: str          # filename suffix
    hue_shift: float   # degrees, [-180, 180]
    sat_mult: float    # multiplier for saturation
    val_mult: float    # multiplier for value
    description: str


VARIANTS: list[Variant] = [
    Variant("suburban",  +80.0, 0.95, 1.00, "world 2 — sky/pastel blue"),
    Variant("steampunk", -95.0, 1.00, 1.05, "world 3 — polished brass/gold"),
    Variant("industrial", -120.0, 0.85, 0.92, "world 4 — muted rust/oxide"),
    Variant("digital",    +150.0, 1.15, 1.00, "world 5 — neon magenta"),
    Variant("abstract",     0.0, 0.15, 1.00, "world 6 — near-monochrome"),
]


def rgb_to_hsv(rgb: np.ndarray) -> np.ndarray:
    """Vectorized RGB[0,1]->HSV[H in 0..360, S/V in 0..1]."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    cmax = np.maximum(np.maximum(r, g), b)
    cmin = np.minimum(np.minimum(r, g), b)
    delta = cmax - cmin

    h = np.zeros_like(cmax)
    mask = delta > 1e-9
    # red is max
    rm = mask & (cmax == r)
    gm = mask & (cmax == g) & ~rm
    bm = mask & (cmax == b) & ~rm & ~gm
    h[rm] = ((g[rm] - b[rm]) / delta[rm]) % 6
    h[gm] = ((b[gm] - r[gm]) / delta[gm]) + 2
    h[bm] = ((r[bm] - g[bm]) / delta[bm]) + 4
    h = h * 60.0  # 0..360

    s = np.zeros_like(cmax)
    s[cmax > 1e-9] = delta[cmax > 1e-9] / cmax[cmax > 1e-9]
    v = cmax
    return np.stack([h, s, v], axis=-1)


def hsv_to_rgb(hsv: np.ndarray) -> np.ndarray:
    """Vectorized HSV[H 0..360, S/V 0..1]->RGB[0,1]."""
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    h = h % 360.0
    c = v * s
    x = c * (1 - np.abs((h / 60.0) % 2 - 1))
    m = v - c

    r = np.zeros_like(h)
    g = np.zeros_like(h)
    b = np.zeros_like(h)
    seg = (h // 60).astype(int) % 6

    s0, s1, s2, s3, s4, s5 = (seg == i for i in range(6))
    r[s0] = c[s0]; g[s0] = x[s0]
    r[s1] = x[s1]; g[s1] = c[s1]
    g[s2] = c[s2]; b[s2] = x[s2]
    g[s3] = x[s3]; b[s3] = c[s3]
    r[s4] = x[s4]; b[s4] = c[s4]
    r[s5] = c[s5]; b[s5] = x[s5]
    return np.stack([r + m, g + m, b + m], axis=-1)


def apply_variant(rgba: np.ndarray, v: Variant) -> np.ndarray:
    """Hue/sat/val shift on opaque pixels only. Alpha preserved exactly."""
    out = rgba.copy()
    rgb01 = rgba[..., :3].astype(np.float32) / 255.0
    hsv = rgb_to_hsv(rgb01)
    hsv[..., 0] = (hsv[..., 0] + v.hue_shift) % 360.0
    hsv[..., 1] = np.clip(hsv[..., 1] * v.sat_mult, 0.0, 1.0)
    hsv[..., 2] = np.clip(hsv[..., 2] * v.val_mult, 0.0, 1.0)
    rgb_out = hsv_to_rgb(hsv)
    out[..., :3] = np.clip(rgb_out * 255.0 + 0.5, 0, 255).astype(np.uint8)
    # Fully transparent pixels: keep RGB at 0 to avoid edge bleed
    transparent = rgba[..., 3] == 0
    out[transparent, :3] = 0
    return out


def main() -> int:
    if not SOURCE.exists():
        print(f"ERROR: source slime not found at {SOURCE}", file=sys.stderr)
        return 1
    img = Image.open(SOURCE).convert("RGBA")
    rgba = np.array(img)
    print(f"source: {SOURCE} ({img.width}x{img.height})")

    for variant in VARIANTS:
        out_arr = apply_variant(rgba, variant)
        out_path = OUT_DIR / f"slime_{variant.name}.png"
        Image.fromarray(out_arr, "RGBA").save(out_path)
        opaque = (out_arr[:, :, 3] > 0).sum()
        unique = len(np.unique(out_arr[out_arr[:, :, 3] > 0][:, :3].reshape(-1, 3), axis=0))
        print(f"  -> {out_path.name}: {opaque} opaque px, {unique} unique colors  [{variant.description}]")

    return 0


if __name__ == "__main__":
    sys.exit(main())
