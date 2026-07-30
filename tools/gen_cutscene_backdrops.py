"""
gen_cutscene_backdrops.py — Procedural cutscene backdrop generator for Cowardly Irregular
Produces 640x360 JRPG pixel-art style background images for World 1 cutscene dialogue scenes.

Outputs:
  prologue_village.png  — Dawn village, warm gold/pink
  prologue_forest.png   — Dark forest path, golden shafts
  cave_entrance.png     — Rocky cave mouth, cool blue-gray with torch glow
  throne_room.png       — Ancient throne room, dim stone pillars

Style reference: FF6 / Chrono Trigger / EarthBound SNES era
"""

import numpy as np
from PIL import Image, ImageFilter
import math
import os

W, H = 640, 360
OUT_DIR = "/home/struktured/projects/cowardly-irregular-sprite-gen/tmp/generated/backdrops"
os.makedirs(OUT_DIR, exist_ok=True)

# ---------------------------------------------------------------------------
# Core helpers
# ---------------------------------------------------------------------------

def make_canvas() -> np.ndarray:
    """Return blank RGBA float32 canvas (H, W, 4) in 0..1 range."""
    return np.zeros((H, W, 4), dtype=np.float32)


def to_image(canvas: np.ndarray) -> Image.Image:
    clipped = np.clip(canvas, 0.0, 1.0)
    arr8 = (clipped * 255).astype(np.uint8)
    return Image.fromarray(arr8, "RGBA")


def fill_alpha(canvas: np.ndarray) -> None:
    """Set all alpha to 1.0 (opaque)."""
    canvas[:, :, 3] = 1.0


def lerp_color(c1, c2, t):
    t = max(0.0, min(1.0, t))
    return tuple(c1[i] + (c2[i] - c1[i]) * t for i in range(len(c1)))


def fill_gradient_v(canvas: np.ndarray, y0: int, y1: int,
                    col_top, col_bot, alpha=1.0) -> None:
    """Fill vertical gradient band from y0..y1 (exclusive)."""
    for y in range(max(0, y0), min(H, y1)):
        t = (y - y0) / max(1, y1 - y0 - 1)
        c = lerp_color(col_top, col_bot, t)
        canvas[y, :, 0] = c[0]
        canvas[y, :, 1] = c[1]
        canvas[y, :, 2] = c[2]
        canvas[y, :, 3] = alpha


def fill_gradient_v_band(canvas: np.ndarray, y0: int, y1: int,
                         x0: int, x1: int, col_top, col_bot) -> None:
    for y in range(max(0, y0), min(H, y1)):
        t = (y - y0) / max(1, y1 - y0 - 1)
        c = lerp_color(col_top, col_bot, t)
        canvas[y, max(0, x0):min(W, x1), 0] = c[0]
        canvas[y, max(0, x0):min(W, x1), 1] = c[1]
        canvas[y, max(0, x0):min(W, x1), 2] = c[2]
        canvas[y, max(0, x0):min(W, x1), 3] = 1.0


def bayer_dither(canvas: np.ndarray, scale: float = 0.025) -> None:
    """
    Apply 4x4 Bayer ordered dithering to RGB channels.
    Adds ordered noise that mimics SNES colour banding.
    """
    bayer = np.array([
        [ 0,  8,  2, 10],
        [12,  4, 14,  6],
        [ 3, 11,  1,  9],
        [15,  7, 13,  5],
    ], dtype=np.float32) / 16.0 - 0.5  # -0.5..+0.5

    tile = np.tile(bayer, (math.ceil(H / 4), math.ceil(W / 4)))[:H, :W]
    noise = tile[:, :, np.newaxis] * scale
    canvas[:, :, :3] += noise


def quantize_palette(canvas: np.ndarray, levels: int = 24) -> None:
    """Posterize to a limited number of levels per channel (SNES feel)."""
    step = 1.0 / levels
    canvas[:, :, :3] = np.floor(canvas[:, :, :3] / step + 0.5) * step


def draw_rect(canvas: np.ndarray, x, y, w, h, color, alpha=1.0) -> None:
    x, y, w, h = int(x), int(y), int(w), int(h)
    x2 = min(W, x + w)
    y2 = min(H, y + h)
    x = max(0, x)
    y = max(0, y)
    if alpha >= 1.0:
        canvas[y:y2, x:x2, 0] = color[0]
        canvas[y:y2, x:x2, 1] = color[1]
        canvas[y:y2, x:x2, 2] = color[2]
        canvas[y:y2, x:x2, 3] = 1.0
    else:
        # alpha-blend over existing
        bg = canvas[y:y2, x:x2, :3].copy()
        fg = np.array(color[:3], dtype=np.float32)
        canvas[y:y2, x:x2, :3] = bg * (1 - alpha) + fg * alpha
        canvas[y:y2, x:x2, 3] = 1.0


def draw_circle_filled(canvas: np.ndarray, cx, cy, r, color, alpha=1.0) -> None:
    cx, cy, r = int(cx), int(cy), int(r)
    x0, x1 = max(0, cx - r), min(W, cx + r + 1)
    y0, y1 = max(0, cy - r), min(H, cy + r + 1)
    xs = np.arange(x0, x1)
    ys = np.arange(y0, y1)
    xx, yy = np.meshgrid(xs, ys)
    mask = (xx - cx) ** 2 + (yy - cy) ** 2 <= r * r
    if alpha >= 1.0:
        canvas[y0:y1, x0:x1][mask, 0] = color[0]
        canvas[y0:y1, x0:x1][mask, 1] = color[1]
        canvas[y0:y1, x0:x1][mask, 2] = color[2]
        canvas[y0:y1, x0:x1][mask, 3] = 1.0
    else:
        bg = canvas[y0:y1, x0:x1].copy()
        fc = np.array([color[0], color[1], color[2], 1.0], dtype=np.float32)
        blend = bg.copy()
        blend[mask, :3] = bg[mask, :3] * (1 - alpha) + fc[:3] * alpha
        blend[mask, 3] = 1.0
        canvas[y0:y1, x0:x1] = blend


def draw_hline(canvas: np.ndarray, x0, x1, y, color) -> None:
    y = int(y)
    if 0 <= y < H:
        x0, x1 = max(0, int(x0)), min(W, int(x1))
        canvas[y, x0:x1, :3] = color[:3]
        canvas[y, x0:x1, 3] = 1.0


def glow_radial(canvas: np.ndarray, cx, cy, r_inner, r_outer, color,
                max_alpha=0.45) -> None:
    """Soft radial glow blended over existing canvas."""
    x0 = max(0, int(cx - r_outer))
    x1 = min(W, int(cx + r_outer) + 1)
    y0 = max(0, int(cy - r_outer))
    y1 = min(H, int(cy + r_outer) + 1)
    xs = np.arange(x0, x1)
    ys = np.arange(y0, y1)
    xx, yy = np.meshgrid(xs, ys)
    dist = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2).astype(np.float32)
    t = np.clip((dist - r_inner) / max(1, r_outer - r_inner), 0.0, 1.0)
    a = (1.0 - t) * max_alpha
    c = np.array(color[:3], dtype=np.float32)
    bg = canvas[y0:y1, x0:x1, :3]
    canvas[y0:y1, x0:x1, :3] = bg * (1 - a[:, :, np.newaxis]) + c * a[:, :, np.newaxis]
    canvas[y0:y1, x0:x1, 3] = 1.0


def light_shaft(canvas: np.ndarray, x_center, y_top, y_bot, width_top, width_bot,
                color, max_alpha=0.18) -> None:
    """Draw a tapered light shaft (trapezoid) blended softly."""
    for y in range(max(0, int(y_top)), min(H, int(y_bot))):
        t = (y - y_top) / max(1, y_bot - y_top)
        half = width_top / 2 + (width_bot / 2 - width_top / 2) * t
        edge_fade = math.sin(t * math.pi) * max_alpha
        x0 = int(x_center - half)
        x1 = int(x_center + half)
        for x in range(max(0, x0), min(W, x1)):
            edge_t = abs(x - x_center) / max(1, half)
            a = edge_fade * (1.0 - edge_t * edge_t)
            canvas[y, x, :3] = canvas[y, x, :3] * (1 - a) + np.array(color[:3]) * a
            canvas[y, x, 3] = 1.0


# ---------------------------------------------------------------------------
# Noise helpers (simple deterministic)
# ---------------------------------------------------------------------------

def value_noise_1d(x: float, seed: int = 0) -> float:
    xi = int(x) + seed * 1291
    h0 = (xi * 1619 + 31337) & 0xFFFF
    h1 = ((xi + 1) * 1619 + 31337) & 0xFFFF
    v0 = (h0 / 0xFFFF) * 2.0 - 1.0
    v1 = (h1 / 0xFFFF) * 2.0 - 1.0
    fx = x - int(x)
    fx = fx * fx * (3.0 - 2.0 * fx)  # smoothstep
    return v0 + (v1 - v0) * fx


def fbm_1d(x: float, octaves: int = 4, seed: int = 0) -> float:
    val = 0.0
    amp = 0.5
    freq = 1.0
    for _ in range(octaves):
        val += value_noise_1d(x * freq, seed) * amp
        amp *= 0.5
        freq *= 2.0
        seed += 7
    return val  # ~-1..1


# ---------------------------------------------------------------------------
# Drawing primitives — architectural
# ---------------------------------------------------------------------------

def draw_thatched_roof(canvas, x, y, width, height, col_thatch, col_dark, col_shadow):
    """Draw a triangular thatched roof with SNES-style shading.
    Apex is at (x + width//2, y), base spans (x, y+height).
    row=0 is the peak (narrow), row=height-1 is the base (full-width).
    """
    # Main triangle fill — grows wider as row increases (apex at top)
    for row in range(height):
        t = row / max(1, height - 1)
        half_w = int(width / 2 * t + 1)
        cx = x + width // 2
        row_color = lerp_color(col_thatch, col_dark, t * 0.45)
        draw_hline(canvas, cx - half_w, cx + half_w, y + row, row_color)
    # Horizontal thatch lines (texture bands across the slope)
    for row in range(3, height, 5):
        t = row / max(1, height - 1)
        half_w = int(width / 2 * t)
        cx = x + width // 2
        draw_hline(canvas, cx - half_w, cx + half_w, y + row, col_shadow)
        if row + 1 < height:
            draw_hline(canvas, cx - half_w + 2, cx + half_w - 2, y + row + 1, col_shadow)


def draw_stone_pillar(canvas, x, y, w, h, col_light, col_mid, col_dark):
    """Draw a stone pillar with beveled highlights."""
    # Main body
    draw_rect(canvas, x, y, w, h, col_mid)
    # Left highlight
    draw_rect(canvas, x, y, max(2, w // 5), h, col_light)
    # Right shadow
    draw_rect(canvas, x + w - max(2, w // 5), y, max(2, w // 5), h, col_dark)
    # Capital (top block)
    cap_h = max(4, h // 8)
    draw_rect(canvas, x - 2, y, w + 4, cap_h, col_light)
    draw_hline(canvas, x - 2, x + w + 2, y + cap_h, col_dark)
    # Base
    draw_rect(canvas, x - 2, y + h - cap_h, w + 4, cap_h, col_mid)
    draw_hline(canvas, x - 2, x + w + 2, y + h - cap_h, col_dark)


def draw_banner(canvas, x, y, w, h, col_main, col_trim, col_worn):
    """Draw a tattered hanging banner."""
    draw_rect(canvas, x, y, w, h, col_main)
    # Trim stripes
    draw_rect(canvas, x, y, w, max(3, h // 8), col_trim)
    draw_rect(canvas, x, y + h - max(3, h // 8), w, max(3, h // 8), col_trim)
    # Worn vertical stripe
    draw_rect(canvas, x + w // 2 - 1, y, 2, h, col_worn)
    # Ragged bottom — cut alternating columns
    rng = np.random.default_rng(x + y)
    raggedness = max(2, h // 5)
    for col_off in range(0, w, 2):
        cut = int(rng.integers(0, raggedness))
        by = y + h - cut
        draw_rect(canvas, x + col_off, by, 2, cut, (0, 0, 0, 0))
        # restore alpha for already-drawn pixels above cut
        canvas[by:by + cut, x + col_off:x + col_off + 2, 3] = 0.0


def draw_tree_silhouette(canvas, cx, base_y, trunk_h, canopy_r,
                         col_trunk, col_canopy, col_canopy_hi, col_canopy_shadow):
    """Draw SNES-style round-topped tree."""
    trunk_w = max(4, canopy_r // 4)
    tx = cx - trunk_w // 2
    # Trunk
    draw_rect(canvas, tx, base_y - trunk_h, trunk_w, trunk_h, col_trunk)
    # Shadow on trunk right
    draw_rect(canvas, tx + trunk_w - 2, base_y - trunk_h, 2, trunk_h, col_canopy_shadow)
    # Canopy layers (3 circles for depth)
    cy = base_y - trunk_h
    draw_circle_filled(canvas, cx, cy, canopy_r, col_canopy_shadow)
    draw_circle_filled(canvas, cx - 3, cy - 2, canopy_r - 2, col_canopy)
    draw_circle_filled(canvas, cx - 5, cy - 5, canopy_r - 5, col_canopy_hi)


def draw_cottage(canvas, x, base_y, width, wall_h,
                 col_wall, col_wall_dark, col_roof, col_roof_dark,
                 col_roof_shadow, col_window, col_door):
    """Draw an SNES-style thatched cottage."""
    roof_h = width // 2
    wall_y = base_y - wall_h
    # Wall
    draw_rect(canvas, x, wall_y, width, wall_h, col_wall)
    # Wall shadow right edge
    draw_rect(canvas, x + width - 3, wall_y, 3, wall_h, col_wall_dark)
    # Roof
    draw_thatched_roof(canvas, x, wall_y - roof_h, width, roof_h,
                       col_roof, col_roof_dark, col_roof_shadow)
    # Chimney
    chim_x = x + width - width // 4
    chim_h = roof_h // 2 + 4
    draw_rect(canvas, chim_x, wall_y - roof_h - chim_h + 4, 6, chim_h, col_wall_dark)
    # Window
    win_w, win_h = max(8, width // 5), max(6, wall_h // 3)
    win_x = x + width // 4 - win_w // 2
    win_y = wall_y + wall_h // 3
    draw_rect(canvas, win_x, win_y, win_w, win_h, col_window)
    draw_hline(canvas, win_x, win_x + win_w, win_y + win_h // 2, col_wall_dark)
    draw_rect(canvas, win_x + win_w // 2 - 1, win_y, 2, win_h, col_wall_dark)
    # Door
    door_w = max(8, width // 5)
    door_h = max(12, wall_h // 2)
    door_x = x + width // 2 + width // 8
    door_y = wall_y + wall_h - door_h
    draw_rect(canvas, door_x, door_y, door_w, door_h, col_door)
    draw_rect(canvas, door_x + door_w // 2 - 1, door_y, 1, door_h, col_wall_dark)


def draw_steeple(canvas, x, base_y, width, wall_h,
                 col_stone, col_stone_dark, col_stone_light, col_window):
    """Draw a simple chapel steeple."""
    # Main tower body
    draw_rect(canvas, x, base_y - wall_h, width, wall_h, col_stone)
    draw_rect(canvas, x, base_y - wall_h, 3, wall_h, col_stone_light)
    draw_rect(canvas, x + width - 3, base_y - wall_h, 3, wall_h, col_stone_dark)
    # Pointed spire — row=0 is the very tip (top pixel), widens toward base
    spire_h = wall_h // 2
    cx = x + width // 2
    for row in range(spire_h):
        # t=0 at tip (row=0), t=1 at base (row=spire_h-1)
        t = row / max(1, spire_h - 1)
        hw = max(1, int(width // 2 * t))
        y = base_y - wall_h - spire_h + row
        draw_hline(canvas, cx - hw, cx + hw, y, col_stone_dark)
    # Arched window
    win_w = max(6, width // 3)
    win_y = base_y - wall_h + wall_h // 4
    win_x = x + width // 2 - win_w // 2
    win_h = max(8, wall_h // 3)
    draw_rect(canvas, win_x, win_y, win_w, win_h, col_window)
    # Arch top (filled circle overhang)
    draw_circle_filled(canvas, x + width // 2, win_y + 1, win_w // 2, col_window)


def draw_mist_layer(canvas, y_start, y_end, col_mist, density=0.35) -> None:
    """Wispy horizontal mist band via dithered horizontal stripes."""
    rng = np.random.default_rng(y_start)
    for y in range(max(0, y_start), min(H, y_end)):
        t_vert = (y - y_start) / max(1, y_end - y_start)
        alpha_base = math.sin(t_vert * math.pi) * density
        xs = np.arange(W)
        # Wave pattern
        wave = 0.5 + 0.5 * np.sin(xs * 0.04 + y * 0.2)
        alphas = (wave * alpha_base).clip(0, 1)
        bg = canvas[y, :, :3].copy()
        c = np.array(col_mist[:3])
        canvas[y, :, :3] = bg * (1 - alphas[:, np.newaxis]) + c * alphas[:, np.newaxis]
        canvas[y, :, 3] = 1.0


def draw_cobblestone_floor(canvas, y_start, y_end,
                           col_stone, col_grout, col_shadow) -> None:
    """Draw a simple cobblestone/tile floor."""
    stone_w = 28
    stone_h = 16
    for row_idx, y in enumerate(range(y_start, y_end, stone_h)):
        offset = (row_idx % 2) * (stone_w // 2)
        row_t = (y - y_start) / max(1, y_end - y_start)
        for x in range(-offset, W + stone_w, stone_w):
            # Stone face
            draw_rect(canvas, x + 1, y + 1, stone_w - 2, stone_h - 2, col_stone)
            # Grout lines
            draw_hline(canvas, x, x + stone_w, y, col_grout)
            draw_rect(canvas, x, y, 1, stone_h, col_grout)
            # Shadow under each stone
            draw_hline(canvas, x + 1, x + stone_w, y + stone_h - 2, col_shadow)
            draw_rect(canvas, x + stone_w - 2, y + 1, 2, stone_h - 2, col_shadow)


# ---------------------------------------------------------------------------
# Backdrop 1 — prologue_village.png
# ---------------------------------------------------------------------------

def gen_prologue_village():
    canvas = make_canvas()

    # --- Sky gradient: deep navy to warm dawn gold/pink ---
    sky_top    = (0.10, 0.08, 0.25)  # deep violet-navy
    sky_mid    = (0.35, 0.18, 0.28)  # dusky rose
    sky_dawn   = (0.72, 0.42, 0.18)  # amber dawn
    sky_horiz  = (0.88, 0.65, 0.30)  # warm gold horizon
    horizon_y  = H * 3 // 5

    # Two-pass gradient: top half deep, bottom near-horizon warm
    for y in range(horizon_y + 10):
        t = y / max(1, horizon_y + 9)
        if t < 0.45:
            c = lerp_color(sky_top, sky_mid, t / 0.45)
        else:
            c = lerp_color(sky_mid, sky_dawn, (t - 0.45) / 0.55)
        canvas[y, :, 0] = c[0]
        canvas[y, :, 1] = c[1]
        canvas[y, :, 2] = c[2]
        canvas[y, :, 3] = 1.0
    # Horizon glow strip
    for y in range(horizon_y - 8, horizon_y + 12):
        t = abs(y - horizon_y) / 10
        c = lerp_color(sky_horiz, sky_dawn, t)
        canvas[y, :, 0] = c[0]
        canvas[y, :, 1] = c[1]
        canvas[y, :, 2] = c[2]
        canvas[y, :, 3] = 1.0

    # Ground gradient: dark earth -> warm dirt
    ground_top  = (0.28, 0.22, 0.14)
    ground_bot  = (0.20, 0.16, 0.10)
    fill_gradient_v(canvas, horizon_y, H, ground_top, ground_bot)

    # --- Sun / dawn glow on horizon ---
    glow_radial(canvas, W // 2 + 30, horizon_y - 2, 20, 110, (1.0, 0.88, 0.55), max_alpha=0.55)
    # Sun disc
    draw_circle_filled(canvas, W // 2 + 30, horizon_y - 2, 18, (1.0, 0.95, 0.72), alpha=0.85)
    draw_circle_filled(canvas, W // 2 + 30, horizon_y - 2, 14, (1.0, 1.0, 0.90), alpha=0.95)

    # --- Stars (few remain at dawn) ---
    star_positions = [
        (60, 18), (140, 8), (220, 25), (310, 5), (410, 15),
        (500, 10), (580, 28), (30, 40), (480, 35),
    ]
    for sx, sy in star_positions:
        draw_rect(canvas, sx, sy, 1, 1, (1.0, 0.98, 0.90), alpha=0.5)

    # --- Background hills (3 layers) ---
    # Farthest hill layer — cool blue-purple tint
    hill_col_far = (0.32, 0.24, 0.32)
    for x in range(W):
        h_val = 0.5 + 0.5 * fbm_1d(x * 0.008, seed=42)
        hy = int(horizon_y - 12 - h_val * 22)
        draw_rect(canvas, x, hy, 1, horizon_y - hy, hill_col_far)

    # Mid hills — warmer, slightly darker
    hill_col_mid = (0.25, 0.18, 0.12)
    for x in range(W):
        h_val = 0.5 + 0.5 * fbm_1d(x * 0.012 + 10, seed=73)
        hy = int(horizon_y - 5 - h_val * 18)
        draw_rect(canvas, x, hy, 1, horizon_y - hy + 2, hill_col_mid)

    # Nearer ground fill
    fill_gradient_v(canvas, horizon_y, H, ground_top, ground_bot)

    # --- Village path (dirt road) ---
    path_col   = (0.55, 0.44, 0.28)
    path_edge  = (0.42, 0.33, 0.20)
    road_cx    = W // 2 - 20
    for y in range(horizon_y, H):
        perspective_t = (y - horizon_y) / max(1, H - horizon_y)
        half = int(10 + perspective_t * 55)
        draw_hline(canvas, road_cx - half, road_cx + half, y, path_col)
        draw_hline(canvas, road_cx - half, road_cx - half + 2, y, path_edge)
        draw_hline(canvas, road_cx + half - 2, road_cx + half, y, path_edge)

    # --- Ground texture — grass patches ---
    grass_hi   = (0.30, 0.42, 0.18)
    grass_dark = (0.18, 0.28, 0.10)
    rng = np.random.default_rng(7)
    for _ in range(300):
        gx = int(rng.integers(0, W))
        gy = int(rng.integers(horizon_y + 2, H - 4))
        gw = int(rng.integers(3, 9))
        gc = grass_hi if rng.random() > 0.4 else grass_dark
        draw_rect(canvas, gx, gy, gw, 2, gc)

    # --- Mist near horizon ---
    mist_col = (0.90, 0.75, 0.55)
    draw_mist_layer(canvas, horizon_y - 10, horizon_y + 20, mist_col, density=0.45)
    draw_mist_layer(canvas, horizon_y + 5, horizon_y + 35, (0.85, 0.72, 0.50), density=0.30)

    # --- Background cottages (far, silhouette) ---
    sil = (0.18, 0.12, 0.10)
    sil_roof = (0.14, 0.10, 0.08)
    sil_window = (0.72, 0.60, 0.32)

    # Far-left cottage silhouette
    bx, by = 70, horizon_y - 2
    draw_cottage(canvas, bx, by, 44, 22,
                 sil, (0.12, 0.08, 0.06), sil_roof, (0.10, 0.07, 0.05),
                 (0.10, 0.07, 0.05), sil_window, (0.20, 0.12, 0.08))

    # Steeple / chapel left of center
    draw_steeple(canvas, 168, horizon_y + 2, 28, 60,
                 sil, (0.10, 0.07, 0.05), (0.22, 0.15, 0.12),
                 sil_window)

    # Right background cottages
    draw_cottage(canvas, 360, horizon_y, 50, 25,
                 sil, (0.12, 0.08, 0.06), sil_roof, (0.10, 0.07, 0.05),
                 (0.10, 0.07, 0.05), sil_window, (0.20, 0.12, 0.08))
    draw_cottage(canvas, 440, horizon_y - 4, 38, 20,
                 sil, (0.12, 0.08, 0.06), sil_roof, (0.10, 0.07, 0.05),
                 (0.10, 0.07, 0.05), sil_window, (0.20, 0.12, 0.08))
    draw_cottage(canvas, 510, horizon_y + 2, 54, 28,
                 sil, (0.12, 0.08, 0.06), sil_roof, (0.10, 0.07, 0.05),
                 (0.10, 0.07, 0.05), sil_window, (0.20, 0.12, 0.08))

    # --- Foreground cottages (midground, more detail) ---
    wall_col  = (0.68, 0.55, 0.38)
    wall_dark = (0.50, 0.40, 0.28)
    roof_col  = (0.55, 0.40, 0.22)
    roof_dark = (0.40, 0.28, 0.14)
    roof_shad = (0.30, 0.20, 0.10)
    win_col   = (0.85, 0.72, 0.35)
    door_col  = (0.40, 0.28, 0.18)

    # Left foreground cottage
    draw_cottage(canvas, 30, H - 40, 80, 55,
                 wall_col, wall_dark, roof_col, roof_dark, roof_shad,
                 win_col, door_col)
    # Right foreground cottage
    draw_cottage(canvas, 510, H - 38, 90, 52,
                 wall_col, wall_dark, (0.52, 0.38, 0.20), roof_dark, roof_shad,
                 win_col, door_col)

    # --- Fence posts along road edges ---
    fence_col  = (0.50, 0.38, 0.22)
    fence_dark = (0.35, 0.26, 0.15)
    for i, fx in enumerate(range(250, 490, 20)):
        # Left fence
        lx = road_cx - 60 - i * 3
        ly = horizon_y + 15 + i * 4
        draw_rect(canvas, lx, ly - 14, 3, 14, fence_col)
        draw_rect(canvas, lx - 4, ly - 8, 10, 3, fence_col)
        draw_rect(canvas, lx - 4, ly - 4, 10, 2, fence_dark)

    # --- Foreground trees ---
    trunk_col = (0.30, 0.20, 0.10)
    can_hi    = (0.20, 0.38, 0.12)
    can_mid   = (0.15, 0.28, 0.08)
    can_shad  = (0.10, 0.18, 0.05)
    draw_tree_silhouette(canvas, 8,  H - 10, 60, 30, trunk_col, can_mid, can_hi, can_shad)
    draw_tree_silhouette(canvas, 620, H - 8, 65, 28, trunk_col, can_mid, can_hi, can_shad)

    # --- Dawn light shafts from sun ---
    shaft_col = (1.0, 0.88, 0.55)
    light_shaft(canvas, W // 2 + 30, 0, horizon_y + 20, 6, 120, shaft_col, max_alpha=0.08)
    light_shaft(canvas, W // 2 - 20, 0, horizon_y + 10, 4, 80, shaft_col, max_alpha=0.05)

    # --- Final atmosphere ---
    bayer_dither(canvas, scale=0.018)
    quantize_palette(canvas, levels=28)
    fill_alpha(canvas)

    # Darken slightly (dialogues overlay on top, need contrast)
    canvas[:, :, :3] *= 0.80

    return to_image(canvas)


# ---------------------------------------------------------------------------
# Backdrop 2 — prologue_forest.png
# ---------------------------------------------------------------------------

def gen_prologue_forest():
    canvas = make_canvas()

    # --- Sky: deep forest canopy overhead, narrow strip of sky at vanishing point ---
    sky_strip  = (0.35, 0.52, 0.72)  # blue sky visible through canopy gap
    sky_dawn   = (0.65, 0.78, 0.48)  # yellow-green canopy glow
    canopy_top = (0.06, 0.16, 0.04)  # dark canopy at top
    canopy_mid = (0.08, 0.22, 0.06)
    ground_col = (0.10, 0.16, 0.07)
    ground_bot = (0.07, 0.11, 0.04)
    path_col   = (0.42, 0.32, 0.18)
    path_edge  = (0.30, 0.22, 0.12)
    horizon_y  = H * 2 // 5  # forest path vanishes high up

    # Canopy overhead
    fill_gradient_v(canvas, 0, horizon_y - 20, canopy_top, canopy_mid)
    # Sky strip near vanishing point
    fill_gradient_v(canvas, horizon_y - 20, horizon_y + 10, sky_dawn, sky_strip)
    # Ground
    fill_gradient_v(canvas, horizon_y + 10, H, ground_col, ground_bot)

    # --- Path receding to horizon (perspective) ---
    road_cx = W // 2 + 10
    for y in range(horizon_y - 5, H):
        perspective_t = (y - (horizon_y - 5)) / max(1, H - horizon_y + 5)
        half = int(4 + perspective_t * 62)
        bright_t = 1.0 - perspective_t * 0.5
        pc = (path_col[0] * bright_t, path_col[1] * bright_t, path_col[2] * bright_t)
        draw_hline(canvas, road_cx - half, road_cx + half, y, pc)
        draw_hline(canvas, road_cx - half, road_cx - half + 2, y, path_edge)
        draw_hline(canvas, road_cx + half - 2, road_cx + half, y, path_edge)

    # Path dirt texture
    rng = np.random.default_rng(99)
    dirt_hi = (0.50, 0.40, 0.24)
    dirt_lo = (0.32, 0.24, 0.14)
    for _ in range(180):
        dx = int(rng.integers(road_cx - 55, road_cx + 55))
        dy = int(rng.integers(horizon_y + 10, H - 2))
        perspective_t = (dy - horizon_y) / max(1, H - horizon_y)
        half_road = int(4 + perspective_t * 62)
        if abs(dx - road_cx) < half_road - 3:
            dc = dirt_hi if rng.random() > 0.5 else dirt_lo
            draw_rect(canvas, dx, dy, int(rng.integers(2, 6)), 1, dc)

    # --- Forest floor — roots and undergrowth ---
    under_col = (0.12, 0.20, 0.07)
    under_hi  = (0.18, 0.30, 0.10)
    for _ in range(220):
        ux = int(rng.integers(0, W))
        uy = int(rng.integers(horizon_y + 5, H - 2))
        uw = int(rng.integers(4, 14))
        uc = under_hi if rng.random() > 0.45 else under_col
        draw_rect(canvas, ux, uy, uw, int(rng.integers(1, 3)), uc)

    # --- Far tree layer (most distant, cool tint, smaller) ---
    far_trunk  = (0.18, 0.12, 0.06)
    far_can    = (0.08, 0.20, 0.05)
    far_can_hi = (0.12, 0.28, 0.08)
    far_can_sh = (0.05, 0.12, 0.03)
    far_tree_xs = [40, 90, 140, 200, 260, 310, 390, 450, 510, 560, 600]
    for tx in far_tree_xs:
        draw_tree_silhouette(canvas, tx, horizon_y + 25, 40, 18,
                             far_trunk, far_can, far_can_hi, far_can_sh)

    # --- Mid tree layer ---
    mid_trunk  = (0.22, 0.15, 0.08)
    mid_can    = (0.10, 0.26, 0.06)
    mid_can_hi = (0.16, 0.36, 0.10)
    mid_can_sh = (0.06, 0.15, 0.03)
    mid_tree_xs = [0, 80, 550, 630]  # flank the path
    mid_sizes   = [(55, 28), (65, 32), (50, 26), (60, 30)]
    for (tx, (th, tr)) in zip(mid_tree_xs, mid_sizes):
        draw_tree_silhouette(canvas, tx, horizon_y + 55, th, tr,
                             mid_trunk, mid_can, mid_can_hi, mid_can_sh)

    # --- Near foreground trees (massive, partially off-screen) ---
    fg_trunk  = (0.28, 0.18, 0.10)
    fg_can    = (0.12, 0.30, 0.07)
    fg_can_hi = (0.20, 0.42, 0.12)
    fg_can_sh = (0.07, 0.17, 0.04)
    # Left giant tree
    draw_tree_silhouette(canvas, -10, H + 10, 120, 72,
                         fg_trunk, fg_can, fg_can_hi, fg_can_sh)
    draw_tree_silhouette(canvas, 130, H + 5, 100, 58,
                         fg_trunk, fg_can, fg_can_hi, fg_can_sh)
    # Right giant tree
    draw_tree_silhouette(canvas, W + 10, H + 10, 125, 70,
                         fg_trunk, fg_can, fg_can_hi, fg_can_sh)
    draw_tree_silhouette(canvas, 490, H + 5, 105, 55,
                         fg_trunk, fg_can, fg_can_hi, fg_can_sh)

    # --- Canopy overhang at top (dark arch overhead) ---
    can_arch_col = (0.05, 0.14, 0.03)
    for x in range(W):
        # Arch depth: deeper at edges, shallower in center
        center_dist = abs(x - W // 2) / (W // 2)
        arch_depth  = int(20 + center_dist * 55 + fbm_1d(x * 0.015, seed=5) * 18)
        draw_rect(canvas, x, 0, 1, min(arch_depth, H // 2), can_arch_col)

    # Canopy edge with highlight
    can_edge_col = (0.14, 0.32, 0.08)
    for x in range(W):
        center_dist = abs(x - W // 2) / (W // 2)
        arch_depth  = int(20 + center_dist * 55 + fbm_1d(x * 0.015, seed=5) * 18)
        draw_rect(canvas, x, arch_depth, 1, 4, can_edge_col)

    # --- Golden light shafts from above ---
    shaft_col = (0.85, 0.78, 0.38)
    shaft_positions = [
        (W // 2 + 5, 0, H, 3, 30, 0.20),
        (W // 2 - 25, 0, H, 2, 20, 0.12),
        (W // 2 + 40, 0, H, 2, 18, 0.10),
        (W // 2 - 60, 15, H, 3, 25, 0.09),
        (W // 2 + 80, 10, H, 2, 16, 0.08),
    ]
    for (sx, sy, ey, wt, wb, ma) in shaft_positions:
        light_shaft(canvas, sx, sy, ey, wt, wb, shaft_col, max_alpha=ma)

    # --- Fireflies / magic motes in the forest ---
    mote_col = (0.85, 0.92, 0.55)
    mote_positions = [
        (180, 180), (220, 240), (350, 200), (420, 260),
        (95, 220), (480, 190), (530, 250), (145, 300),
    ]
    for mx, my in mote_positions:
        glow_radial(canvas, mx, my, 0, 8, mote_col, max_alpha=0.28)
        draw_rect(canvas, mx, my, 2, 2, mote_col, alpha=0.9)

    # --- Ground fog ---
    draw_mist_layer(canvas, H - 55, H, (0.25, 0.38, 0.18), density=0.22)

    bayer_dither(canvas, scale=0.016)
    quantize_palette(canvas, levels=26)
    fill_alpha(canvas)
    canvas[:, :, :3] *= 0.75  # moody underexposure
    return to_image(canvas)


# ---------------------------------------------------------------------------
# Backdrop 3 — cave_entrance.png
# ---------------------------------------------------------------------------

def gen_cave_entrance():
    canvas = make_canvas()

    # --- Sky: overcast late afternoon, cool gray-blue ---
    sky_top   = (0.28, 0.35, 0.48)
    sky_bot   = (0.42, 0.48, 0.56)
    ground_col = (0.32, 0.30, 0.28)
    ground_bot = (0.22, 0.20, 0.18)
    horizon_y  = H * 11 // 20

    fill_gradient_v(canvas, 0, horizon_y, sky_top, sky_bot)
    fill_gradient_v(canvas, horizon_y, H, ground_col, ground_bot)

    # --- Rocky hillside gradient overlay ---
    # Rocks are cool gray with purple tint
    hill_col  = (0.40, 0.38, 0.42)
    hill_dark = (0.25, 0.22, 0.28)

    # Hillside fills from right, cave is in center-left
    for x in range(W):
        t = x / (W - 1)
        h_val = 0.5 + 0.5 * fbm_1d(x * 0.010 + 5, seed=12)
        hy = int(horizon_y - 10 - h_val * 55)
        draw_rect(canvas, x, hy, 1, H - hy, hill_col)

    # Cliff face texture — noise-based rock strata and cracks
    cliff_shadow = (0.20, 0.18, 0.24)
    cliff_mid    = (0.35, 0.32, 0.38)
    cliff_hi     = (0.52, 0.50, 0.55)

    # Horizontal rock strata lines (natural sediment layers)
    for y in range(horizon_y - 5, H, 8):
        layer_val = fbm_1d(y * 0.04, seed=88)
        layer_col = lerp_color(cliff_shadow, cliff_hi, 0.5 + layer_val * 0.4)
        draw_hline(canvas, 0, W, y, layer_col)
        draw_hline(canvas, 0, W, y + 1, cliff_shadow)

    # Vertical crack lines (organic, noise-driven)
    for cx_crack in range(40, W, int(W / 7)):
        jitter = int(fbm_1d(cx_crack * 0.1, seed=22) * 18)
        for y in range(horizon_y, H):
            xc = cx_crack + jitter + int(fbm_1d(y * 0.08, seed=cx_crack) * 6)
            draw_rect(canvas, xc, y, 1, 1, cliff_shadow)

    # Surface highlights — small bright flecks (quartz / mica)
    rng_rock = np.random.default_rng(333)
    for _ in range(180):
        fx = int(rng_rock.integers(0, W))
        fy = int(rng_rock.integers(horizon_y, H))
        draw_rect(canvas, fx, fy, 2, 1, cliff_hi)

    # --- Cave mouth (dark arch) ---
    cave_cx = W // 2 - 30
    cave_bot = H - 30
    cave_w   = 130
    cave_h   = 140

    # Cave interior — very dark
    cave_void   = (0.04, 0.03, 0.06)
    cave_inner  = (0.06, 0.05, 0.08)

    # Draw arch: ellipse interior
    for y in range(cave_bot - cave_h, cave_bot + 1):
        t = (y - (cave_bot - cave_h)) / max(1, cave_h)
        # Arch top is elliptical
        if t < 0.45:
            arch_half = int(cave_w / 2 * math.sqrt(max(0, 1 - ((t / 0.45 - 1) ** 2))))
        else:
            arch_half = cave_w // 2
        x0 = cave_cx - arch_half
        x1 = cave_cx + arch_half
        # Interior darkness gradient
        inner_t = 1.0 - abs(y - cave_bot) / cave_h
        ic = lerp_color(cave_void, cave_inner, inner_t * 0.6)
        draw_hline(canvas, x0, x1, y, ic)

    # Cave arch stone frame
    frame_col   = (0.48, 0.44, 0.50)
    frame_dark  = (0.28, 0.24, 0.30)
    frame_light = (0.62, 0.58, 0.64)
    frame_thick = 10
    for y in range(cave_bot - cave_h - 5, cave_bot + 1):
        t = (y - (cave_bot - cave_h - 5)) / max(1, cave_h + 5)
        if t < 0.45:
            arch_half = int(cave_w / 2 * math.sqrt(max(0, 1 - ((t / 0.45 - 1) ** 2))))
        else:
            arch_half = cave_w // 2
        # Outer edge
        x0_out = cave_cx - arch_half - frame_thick
        x1_out = cave_cx + arch_half + frame_thick
        x0_in  = cave_cx - arch_half
        x1_in  = cave_cx + arch_half
        draw_hline(canvas, x0_out, x0_in, y, frame_col)
        draw_hline(canvas, x1_in,  x1_out, y, frame_col)
        # Highlights left
        draw_hline(canvas, x0_out, x0_out + 2, y, frame_light)
        # Shadow right
        draw_hline(canvas, x1_out - 2, x1_out, y, frame_dark)

    # Stone texture on arch frame (mortar lines)
    mortar_col = (0.22, 0.20, 0.24)
    for stone_y in range(cave_bot - cave_h, cave_bot, 16):
        for stone_x in range(cave_cx - cave_w // 2 - frame_thick,
                              cave_cx + cave_w // 2 + frame_thick, 18):
            draw_rect(canvas, stone_x, stone_y, frame_thick + 2, 1, mortar_col)
            draw_rect(canvas, stone_x, stone_y + 1, 1, 14, mortar_col)

    # --- Torch light on sides of cave entrance ---
    torch_left_x  = cave_cx - cave_w // 2 - frame_thick - 12
    torch_right_x = cave_cx + cave_w // 2 + frame_thick + 12
    torch_y = cave_bot - cave_h // 3

    torch_col = (0.95, 0.70, 0.25)
    for tx, side in [(torch_left_x, -1), (torch_right_x, 1)]:
        # Torch glow
        glow_radial(canvas, tx, torch_y, 0, 55, torch_col, max_alpha=0.42)
        glow_radial(canvas, tx, torch_y, 0, 20, (1.0, 0.90, 0.55), max_alpha=0.55)
        # Torch bracket
        draw_rect(canvas, tx - 2, torch_y, 5, 14, (0.40, 0.32, 0.22))
        # Flame
        draw_circle_filled(canvas, tx, torch_y - 5, 5, (1.0, 0.80, 0.20), alpha=0.9)
        draw_circle_filled(canvas, tx, torch_y - 8, 3, (1.0, 0.95, 0.60), alpha=0.8)

    # --- Bones / debris near entrance ---
    bone_col   = (0.80, 0.78, 0.72)
    bone_dark  = (0.55, 0.52, 0.48)
    # Skull-like shape left of entrance
    skull_x = cave_cx - cave_w // 2 - 22
    skull_y = cave_bot - 12
    draw_circle_filled(canvas, skull_x, skull_y, 7, bone_col, alpha=0.9)
    draw_circle_filled(canvas, skull_x, skull_y, 5, bone_col, alpha=0.95)
    draw_rect(canvas, skull_x - 3, skull_y + 4, 3, 4, bone_col)
    draw_rect(canvas, skull_x + 1, skull_y + 4, 3, 4, bone_col)
    draw_rect(canvas, skull_x - 1, skull_y - 2, 2, 2, cave_void)
    draw_rect(canvas, skull_x + 2, skull_y - 2, 2, 2, cave_void)
    # Scattered bone pieces right
    for bx, by, bw, bh in [(cave_cx + 75, cave_bot - 8, 14, 3),
                             (cave_cx + 65, cave_bot - 5, 3, 10),
                             (cave_cx + 90, cave_bot - 6, 18, 2),
                             (cave_cx - 80, cave_bot - 4, 10, 2)]:
        draw_rect(canvas, bx, by, bw, bh, bone_col)
        draw_rect(canvas, bx, by + bh - 1, bw, 1, bone_dark)

    # --- Rocks scattered on ground ---
    rock_col  = (0.42, 0.40, 0.44)
    rock_dark = (0.28, 0.26, 0.30)
    rock_hi   = (0.58, 0.56, 0.60)
    for rx, ry, rr in [(60, H - 20, 12), (150, H - 16, 8), (520, H - 22, 14),
                        (580, H - 15, 9), (cave_cx - 90, H - 12, 6),
                        (cave_cx + 100, H - 14, 7)]:
        draw_circle_filled(canvas, rx, ry, rr, rock_col, alpha=0.9)
        draw_circle_filled(canvas, rx - 2, ry - 2, max(2, rr - 3), rock_hi, alpha=0.6)
        draw_hline(canvas, rx - rr + 2, rx + rr - 2, ry + rr - 2, rock_dark)

    # --- Ominous mist from cave mouth ---
    draw_mist_layer(canvas, cave_bot - 30, cave_bot + 5,
                    (0.35, 0.32, 0.42), density=0.28)

    # --- Overcast cloud layer in sky — wispy horizontal smears ---
    cloud_col  = (0.50, 0.54, 0.62)
    cloud_dark = (0.38, 0.42, 0.50)
    # Draw elongated cloud bands (horizontal ellipses, not tall circles)
    for cx_c, cy_c, cw, ch in [
        (80,  30, 100, 14), (230, 18, 130, 10), (400, 40, 110, 12),
        (540, 22, 90,  11), (160, 55,  80, 9),  (500, 55,  70, 8),
    ]:
        # Horizontal ellipse via row-by-row
        for dy in range(-ch, ch + 1):
            t_v = dy / max(1, ch)
            half_w = int(cw * math.sqrt(max(0, 1 - t_v * t_v)))
            cy_row = cy_c + dy
            if 0 <= cy_row < horizon_y:
                alpha_row = 0.22 * (1.0 - abs(t_v))
                bg = canvas[cy_row, max(0, cx_c - half_w):min(W, cx_c + half_w), :3].copy()
                c = np.array(cloud_col[:3])
                canvas[cy_row, max(0, cx_c - half_w):min(W, cx_c + half_w), :3] = (
                    bg * (1 - alpha_row) + c * alpha_row
                )

    bayer_dither(canvas, scale=0.020)
    quantize_palette(canvas, levels=24)
    fill_alpha(canvas)
    canvas[:, :, :3] *= 0.78
    return to_image(canvas)


# ---------------------------------------------------------------------------
# Backdrop 4 — throne_room.png
# ---------------------------------------------------------------------------

def gen_throne_room():
    canvas = make_canvas()

    # --- Background: stone wall, dark and imposing ---
    wall_top  = (0.12, 0.10, 0.14)
    wall_bot  = (0.18, 0.16, 0.20)
    fill_gradient_v(canvas, 0, H, wall_top, wall_bot)

    # --- Stone wall tile texture ---
    stone_col   = (0.22, 0.20, 0.26)
    stone_light = (0.30, 0.28, 0.34)
    stone_dark  = (0.12, 0.10, 0.14)
    mortar_col  = (0.10, 0.09, 0.12)

    stone_w, stone_h = 48, 24
    for row, sy in enumerate(range(0, H - 80, stone_h)):
        offset = (row % 2) * (stone_w // 2)
        for sx in range(-offset, W + stone_w, stone_w):
            # Stone face gradient
            for dy in range(1, stone_h - 1):
                t = dy / max(1, stone_h - 2)
                sc = lerp_color(stone_light, stone_col, t)
                draw_hline(canvas, sx + 1, sx + stone_w - 1, sy + dy, sc)
            # Left highlight
            draw_rect(canvas, sx + 1, sy + 1, 2, stone_h - 2, stone_light)
            # Bottom shadow
            draw_hline(canvas, sx + 1, sx + stone_w - 1, sy + stone_h - 2, stone_dark)
            # Mortar
            draw_hline(canvas, sx, sx + stone_w, sy, mortar_col)
            draw_rect(canvas, sx, sy, 1, stone_h, mortar_col)

    # --- Floor (darker stone tiles) ---
    floor_y = H * 2 // 3
    floor_col   = (0.16, 0.14, 0.18)
    floor_light = (0.22, 0.20, 0.25)
    floor_dark  = (0.10, 0.09, 0.12)
    grout_col   = (0.09, 0.08, 0.10)

    draw_cobblestone_floor(canvas, floor_y, H, floor_col, grout_col, floor_dark)

    # Floor highlight near bottom (light from above)
    for y in range(floor_y, floor_y + 20):
        t = (y - floor_y) / 20
        fl_hi = lerp_color((0.25, 0.23, 0.30), floor_col, t)
        canvas[y, :, 0] = fl_hi[0]
        canvas[y, :, 1] = fl_hi[1]
        canvas[y, :, 2] = fl_hi[2]

    # --- Far-wall window recess (stained glass silhouette) — drawn before pillars/throne ---
    win_cx = W // 2
    win_y  = 18
    win_w  = 68
    win_h  = 88
    win_col      = (0.10, 0.07, 0.15)  # very dark purple recess
    win_col_pane = (0.16, 0.12, 0.26)  # slightly lighter pane
    # Arched window rect base
    draw_rect(canvas, win_cx - win_w // 2, win_y, win_w, win_h, win_col)
    # Arch top — semi-circular
    for ax in range(win_w):
        ay = int(win_w // 2 - math.sqrt(max(0, (win_w // 2) ** 2 - (ax - win_w // 2) ** 2)))
        draw_rect(canvas, win_cx - win_w // 2 + ax, win_y + ay,
                  1, win_h - ay, win_col_pane if ax % 12 < 6 else win_col)
    # Cross mullion (stone dividers)
    draw_rect(canvas, win_cx - 2, win_y, 4, win_h, (0.08, 0.06, 0.10))
    draw_rect(canvas, win_cx - win_w // 2, win_y + win_h // 3, win_w, 4, (0.08, 0.06, 0.10))
    # Faint amber glow from window (candlelight beyond)
    glow_radial(canvas, win_cx, win_y + win_h // 2, 5, 50,
                (0.60, 0.48, 0.22), max_alpha=0.12)

    # --- Stone pillars (3 each side) ---
    pillar_col   = (0.28, 0.25, 0.32)
    pillar_light = (0.42, 0.38, 0.46)
    pillar_dark  = (0.16, 0.14, 0.18)

    pillar_base_y = floor_y
    pillar_h      = floor_y  # pillars go floor to ceiling
    pillar_w      = 34

    left_pillar_xs  = [30, 175, 295]
    right_pillar_xs = [W - 30 - pillar_w, W - 175 - pillar_w, W - 295 - pillar_w]

    for px in left_pillar_xs + right_pillar_xs:
        draw_stone_pillar(canvas, px, 0, pillar_w, pillar_base_y,
                          pillar_light, pillar_col, pillar_dark)

    # --- Tattered banners between pillars (drawn after pillars) ---
    banner_main  = (0.35, 0.08, 0.08)   # dark crimson
    banner_trim  = (0.55, 0.42, 0.10)   # tarnished gold
    banner_worn  = (0.25, 0.06, 0.06)   # very dark red

    banner_positions = [
        (left_pillar_xs[0] + pillar_w + 4, 14, 58, 105),
        (left_pillar_xs[1] + pillar_w + 4, 10, 54, 98),
        (right_pillar_xs[0] - 62, 16, 58, 105),
        (right_pillar_xs[1] - 58, 11, 54, 98),
    ]
    for (bx, by, bw, bh) in banner_positions:
        draw_banner(canvas, bx, by, bw, bh, banner_main, banner_trim, banner_worn)

    # --- Throne in center-rear (drawn after banners, over everything) ---
    throne_cx = W // 2
    throne_base_y = floor_y - 5
    throne_w = 92
    throne_h = 125

    # Throne dais (raised platform steps)
    dais_col  = (0.20, 0.18, 0.24)
    dais_hi   = (0.34, 0.30, 0.38)
    draw_rect(canvas, throne_cx - throne_w // 2 - 22, throne_base_y - 8,
              throne_w + 44, 8, dais_hi)
    draw_rect(canvas, throne_cx - throne_w // 2 - 14, throne_base_y - 16,
              throne_w + 28, 8, dais_col)
    draw_rect(canvas, throne_cx - throne_w // 2 - 7, throne_base_y - 22,
              throne_w + 14, 6, dais_hi)

    # Throne seat
    throne_col  = (0.28, 0.22, 0.12)  # dark aged wood
    throne_hi   = (0.42, 0.34, 0.18)
    throne_dark = (0.16, 0.13, 0.07)

    # Seat base
    seat_y = throne_base_y - 40
    draw_rect(canvas, throne_cx - throne_w // 2, seat_y, throne_w, 18, throne_col)
    draw_rect(canvas, throne_cx - throne_w // 2, seat_y, throne_w, 3, throne_hi)
    draw_rect(canvas, throne_cx - throne_w // 2, seat_y, 5, 18, throne_hi)
    draw_rect(canvas, throne_cx + throne_w // 2 - 5, seat_y, 5, 18, throne_dark)

    # Backrest
    back_h = throne_h - 42
    back_y = seat_y - back_h
    draw_rect(canvas, throne_cx - throne_w // 2, back_y, throne_w, back_h, throne_col)
    draw_rect(canvas, throne_cx - throne_w // 2, back_y, 5, back_h, throne_hi)
    draw_rect(canvas, throne_cx + throne_w // 2 - 5, back_y, 5, back_h, throne_dark)
    # Inner panel detail
    inner_pad = 10
    draw_rect(canvas, throne_cx - throne_w // 2 + inner_pad, back_y + inner_pad,
              throne_w - inner_pad * 2, back_h - inner_pad * 2, throne_dark)
    draw_rect(canvas, throne_cx - throne_w // 2 + inner_pad, back_y + inner_pad,
              throne_w - inner_pad * 2, 2, throne_hi)

    # Crown-top finials
    fin_col = (0.58, 0.44, 0.14)  # tarnished gold
    fin_glow = (0.80, 0.65, 0.28)
    for fx in [throne_cx - throne_w // 2 + 6, throne_cx - 5, throne_cx + throne_w // 2 - 16]:
        draw_rect(canvas, fx, back_y - 14, 9, 14, fin_col)
        draw_circle_filled(canvas, fx + 4, back_y - 14, 6, fin_col)
        draw_circle_filled(canvas, fx + 4, back_y - 16, 3, fin_glow)

    # Armrests
    draw_rect(canvas, throne_cx - throne_w // 2, seat_y - 12, 13, 30, throne_hi)
    draw_rect(canvas, throne_cx - throne_w // 2, seat_y - 12, 13, 3, fin_col)
    draw_rect(canvas, throne_cx + throne_w // 2 - 13, seat_y - 12, 13, 30, throne_col)
    draw_rect(canvas, throne_cx + throne_w // 2 - 13, seat_y - 12, 13, 3, fin_col)

    # --- Overhead light beams from high windows (off-screen above) ---
    beam_col = (0.78, 0.72, 0.48)
    beam_data = [
        (128, 0, H, 8, 48, 0.16),
        (W - 138, 0, H, 8, 46, 0.15),
        (throne_cx, 0, floor_y + 25, 6, 32, 0.20),
        (215, 0, H - 40, 5, 22, 0.09),
        (W - 225, 0, H - 40, 5, 22, 0.09),
    ]
    for (bx, by, ey, wt, wb, ma) in beam_data:
        light_shaft(canvas, bx, by, ey, wt, wb, beam_col, max_alpha=ma)

    # Dust motes in beams
    mote_col = (0.92, 0.88, 0.62)
    rng = np.random.default_rng(444)
    for _ in range(32):
        mx = int(rng.integers(90, W - 90))
        my = int(rng.integers(20, floor_y - 10))
        draw_rect(canvas, mx, my, 1, 1, mote_col, alpha=float(rng.uniform(0.3, 0.7)))

    # --- Fog of cold air low near ground ---
    draw_mist_layer(canvas, floor_y - 5, floor_y + 40, (0.28, 0.25, 0.35), density=0.18)

    bayer_dither(canvas, scale=0.022)
    quantize_palette(canvas, levels=22)
    fill_alpha(canvas)
    canvas[:, :, :3] *= 0.72  # dim and ominous
    return to_image(canvas)


# ---------------------------------------------------------------------------
# Main — generate all 4 backdrops
# ---------------------------------------------------------------------------

def main():
    tasks = [
        ("prologue_village.png", gen_prologue_village),
        ("prologue_forest.png",  gen_prologue_forest),
        ("cave_entrance.png",    gen_cave_entrance),
        ("throne_room.png",      gen_throne_room),
    ]

    for filename, gen_fn in tasks:
        print(f"Generating {filename}...")
        img = gen_fn()
        out_path = os.path.join(OUT_DIR, filename)
        img.save(out_path, "PNG")
        actual_size = img.size
        print(f"  Saved {out_path} ({actual_size[0]}x{actual_size[1]})")

    print("\nAll 4 backdrops generated.")
    print(f"Output directory: {OUT_DIR}")


if __name__ == "__main__":
    main()
