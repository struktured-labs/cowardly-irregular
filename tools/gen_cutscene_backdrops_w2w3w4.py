"""
gen_cutscene_backdrops_w2w3w4.py — Procedural cutscene backdrop generator
Worlds 2 (Suburban), 3 (Steampunk), 4 (Industrial) for Cowardly Irregular.

Outputs (640x360 RGBA PNG, darkened ~20-25% for dialogue readability):
  suburban_neighborhood.png
  suburban_school.png
  suburban_park.png
  steampunk_workshop.png
  steampunk_airship.png
  industrial_factory.png
  industrial_furnace.png

Style: FF6 / Chrono Trigger / EarthBound SNES 16-bit pixel art aesthetic.
"""

import numpy as np
from PIL import Image
import math
import os

W, H = 640, 360
OUT_DIR = "/home/struktured/projects/cowardly-irregular-sprite-gen/tmp/generated/backdrops"
os.makedirs(OUT_DIR, exist_ok=True)

# ---------------------------------------------------------------------------
# Core helpers (mirrors gen_cutscene_backdrops.py)
# ---------------------------------------------------------------------------

def make_canvas() -> np.ndarray:
    return np.zeros((H, W, 4), dtype=np.float32)


def to_image(canvas: np.ndarray) -> Image.Image:
    clipped = np.clip(canvas, 0.0, 1.0)
    arr8 = (clipped * 255).astype(np.uint8)
    return Image.fromarray(arr8, "RGBA")


def fill_alpha(canvas: np.ndarray) -> None:
    canvas[:, :, 3] = 1.0


def lerp_color(c1, c2, t):
    t = max(0.0, min(1.0, t))
    return tuple(c1[i] + (c2[i] - c1[i]) * t for i in range(len(c1)))


def fill_gradient_v(canvas, y0, y1, col_top, col_bot, alpha=1.0):
    for y in range(max(0, y0), min(H, y1)):
        t = (y - y0) / max(1, y1 - y0 - 1)
        c = lerp_color(col_top, col_bot, t)
        canvas[y, :, 0] = c[0]
        canvas[y, :, 1] = c[1]
        canvas[y, :, 2] = c[2]
        canvas[y, :, 3] = alpha


def fill_gradient_v_band(canvas, y0, y1, x0, x1, col_top, col_bot):
    for y in range(max(0, y0), min(H, y1)):
        t = (y - y0) / max(1, y1 - y0 - 1)
        c = lerp_color(col_top, col_bot, t)
        canvas[y, max(0, x0):min(W, x1), 0] = c[0]
        canvas[y, max(0, x0):min(W, x1), 1] = c[1]
        canvas[y, max(0, x0):min(W, x1), 2] = c[2]
        canvas[y, max(0, x0):min(W, x1), 3] = 1.0


def bayer_dither(canvas, scale=0.025):
    bayer = np.array([
        [ 0,  8,  2, 10],
        [12,  4, 14,  6],
        [ 3, 11,  1,  9],
        [15,  7, 13,  5],
    ], dtype=np.float32) / 16.0 - 0.5
    tile = np.tile(bayer, (math.ceil(H / 4), math.ceil(W / 4)))[:H, :W]
    noise = tile[:, :, np.newaxis] * scale
    canvas[:, :, :3] += noise


def quantize_palette(canvas, levels=24):
    step = 1.0 / levels
    canvas[:, :, :3] = np.floor(canvas[:, :, :3] / step + 0.5) * step


def draw_rect(canvas, x, y, w, h, color, alpha=1.0):
    x, y, w, h = int(x), int(y), int(w), int(h)
    x2 = min(W, x + w)
    y2 = min(H, y + h)
    x = max(0, x)
    y = max(0, y)
    if x2 <= x or y2 <= y:
        return
    if alpha >= 1.0:
        canvas[y:y2, x:x2, 0] = color[0]
        canvas[y:y2, x:x2, 1] = color[1]
        canvas[y:y2, x:x2, 2] = color[2]
        canvas[y:y2, x:x2, 3] = 1.0
    else:
        bg = canvas[y:y2, x:x2, :3].copy()
        fg = np.array(color[:3], dtype=np.float32)
        canvas[y:y2, x:x2, :3] = bg * (1 - alpha) + fg * alpha
        canvas[y:y2, x:x2, 3] = 1.0


def draw_circle_filled(canvas, cx, cy, r, color, alpha=1.0):
    cx, cy, r = int(cx), int(cy), int(r)
    x0, x1 = max(0, cx - r), min(W, cx + r + 1)
    y0, y1 = max(0, cy - r), min(H, cy + r + 1)
    xs = np.arange(x0, x1)
    ys = np.arange(y0, y1)
    if xs.size == 0 or ys.size == 0:
        return
    xx, yy = np.meshgrid(xs, ys)
    mask = (xx - cx) ** 2 + (yy - cy) ** 2 <= r * r
    if alpha >= 1.0:
        canvas[y0:y1, x0:x1][mask, 0] = color[0]
        canvas[y0:y1, x0:x1][mask, 1] = color[1]
        canvas[y0:y1, x0:x1][mask, 2] = color[2]
        canvas[y0:y1, x0:x1][mask, 3] = 1.0
    else:
        bg = canvas[y0:y1, x0:x1].copy()
        blend = bg.copy()
        blend[mask, :3] = bg[mask, :3] * (1 - alpha) + np.array(color[:3]) * alpha
        blend[mask, 3] = 1.0
        canvas[y0:y1, x0:x1] = blend


def draw_hline(canvas, x0, x1, y, color):
    y = int(y)
    if 0 <= y < H:
        x0, x1 = max(0, int(x0)), min(W, int(x1))
        canvas[y, x0:x1, :3] = color[:3]
        canvas[y, x0:x1, 3] = 1.0


def draw_vline(canvas, x, y0, y1, color):
    x = int(x)
    if 0 <= x < W:
        y0, y1 = max(0, int(y0)), min(H, int(y1))
        canvas[y0:y1, x, :3] = color[:3]
        canvas[y0:y1, x, 3] = 1.0


def glow_radial(canvas, cx, cy, r_inner, r_outer, color, max_alpha=0.45):
    x0 = max(0, int(cx - r_outer))
    x1 = min(W, int(cx + r_outer) + 1)
    y0 = max(0, int(cy - r_outer))
    y1 = min(H, int(cy + r_outer) + 1)
    if x1 <= x0 or y1 <= y0:
        return
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


def light_shaft(canvas, x_center, y_top, y_bot, width_top, width_bot, color, max_alpha=0.18):
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


def draw_mist_layer(canvas, y_start, y_end, col_mist, density=0.35):
    for y in range(max(0, y_start), min(H, y_end)):
        t_vert = (y - y_start) / max(1, y_end - y_start)
        alpha_base = math.sin(t_vert * math.pi) * density
        xs = np.arange(W)
        wave = 0.5 + 0.5 * np.sin(xs * 0.04 + y * 0.2)
        alphas = (wave * alpha_base).clip(0, 1)
        bg = canvas[y, :, :3].copy()
        c = np.array(col_mist[:3])
        canvas[y, :, :3] = bg * (1 - alphas[:, np.newaxis]) + c * alphas[:, np.newaxis]
        canvas[y, :, 3] = 1.0


def value_noise_1d(x, seed=0):
    xi = int(x) + seed * 1291
    h0 = (xi * 1619 + 31337) & 0xFFFF
    h1 = ((xi + 1) * 1619 + 31337) & 0xFFFF
    v0 = (h0 / 0xFFFF) * 2.0 - 1.0
    v1 = (h1 / 0xFFFF) * 2.0 - 1.0
    fx = x - int(x)
    fx = fx * fx * (3.0 - 2.0 * fx)
    return v0 + (v1 - v0) * fx


def fbm_1d(x, octaves=4, seed=0):
    val = 0.0
    amp = 0.5
    freq = 1.0
    for _ in range(octaves):
        val += value_noise_1d(x * freq, seed) * amp
        amp *= 0.5
        freq *= 2.0
        seed += 7
    return val


# ---------------------------------------------------------------------------
# Shared architectural primitives
# ---------------------------------------------------------------------------

def draw_suburban_house(canvas, x, base_y, width, wall_h,
                        col_wall, col_wall_dark, col_roof, col_roof_hi,
                        col_window, col_door, col_trim, lit=True):
    """SNES-style suburban house: flat roof pitch, siding, lit or unlit window."""
    roof_h = width // 3
    wall_y = base_y - wall_h

    # Siding (wall) with horizontal stripe texture
    draw_rect(canvas, x, wall_y, width, wall_h, col_wall)
    # Siding lines (horizontal)
    for sy in range(wall_y + 4, wall_y + wall_h, 6):
        draw_hline(canvas, x + 1, x + width - 1, sy, col_wall_dark)
    # Right shadow edge
    draw_rect(canvas, x + width - 3, wall_y, 3, wall_h, col_wall_dark)

    # Gable roof (triangular)
    cx_roof = x + width // 2
    for row in range(roof_h):
        t = row / max(1, roof_h - 1)
        hw = int(width / 2 * t + 1)
        ry = wall_y - roof_h + row
        rc = lerp_color(col_roof_hi, col_roof, t)
        draw_hline(canvas, cx_roof - hw, cx_roof + hw, ry, rc)
    # Roof ridge line
    draw_hline(canvas, cx_roof - 2, cx_roof + 2, wall_y - roof_h, col_roof)
    # Roof overhang shadow at eave
    draw_hline(canvas, x - 2, x + width + 2, wall_y, col_wall_dark)

    # Trim (fascia) on eave
    draw_hline(canvas, x, x + width, wall_y - 1, col_trim)

    # Chimney
    chim_x = x + width * 3 // 4
    chim_h = roof_h // 2 + 6
    draw_rect(canvas, chim_x, wall_y - roof_h - chim_h + 6, 7, chim_h, col_wall_dark)
    draw_rect(canvas, chim_x - 1, wall_y - roof_h - chim_h + 4, 9, 3, col_wall_dark)

    # Window (glowing amber if lit, dark if not)
    win_w = max(10, width // 4)
    win_h = max(10, wall_h // 3)
    win_x = x + width // 5
    win_y = wall_y + wall_h // 4
    win_col = (0.90, 0.78, 0.40) if lit else (0.14, 0.16, 0.22)
    draw_rect(canvas, win_x, win_y, win_w, win_h, win_col)
    # Window cross frame
    draw_hline(canvas, win_x, win_x + win_w, win_y + win_h // 2, col_trim)
    draw_vline(canvas, win_x + win_w // 2, win_y, win_y + win_h, col_trim)
    # Window frame border
    draw_rect(canvas, win_x - 1, win_y - 1, win_w + 2, 2, col_trim)
    draw_rect(canvas, win_x - 1, win_y + win_h - 1, win_w + 2, 2, col_trim)
    if lit:
        glow_radial(canvas, win_x + win_w // 2, win_y + win_h // 2, 2, 22,
                    (0.90, 0.75, 0.35), max_alpha=0.30)

    # Front door
    door_w = max(8, width // 6)
    door_h = max(14, wall_h // 2)
    door_x = x + width // 2 + width // 6
    door_y = base_y - door_h
    draw_rect(canvas, door_x, door_y, door_w, door_h, col_door)
    # Door knob
    draw_rect(canvas, door_x + door_w - 3, door_y + door_h // 2, 2, 2, col_trim)

    # Lawn strip (darker green)
    lawn_col = lerp_color(col_wall, (0.22, 0.38, 0.14), 0.6)


def draw_streetlight(canvas, x, base_y, height,
                     col_post, col_lamp, on=True):
    """Draw a classic suburban streetlight pole."""
    # Post
    draw_rect(canvas, x - 1, base_y - height, 3, height, col_post)
    # Arm extending left
    arm_len = 14
    arm_y = base_y - height + 4
    draw_hline(canvas, x - arm_len, x, arm_y, col_post)
    draw_rect(canvas, x - 1, arm_y, 2, 6, col_post)
    # Lamp housing
    lamp_x = x - arm_len - 6
    lamp_y = arm_y - 4
    draw_rect(canvas, lamp_x, lamp_y, 12, 8, col_post)
    # Lamp glass
    lamp_col = (0.98, 0.95, 0.70) if on else (0.30, 0.30, 0.28)
    draw_rect(canvas, lamp_x + 2, lamp_y + 2, 8, 4, lamp_col)
    if on:
        glow_radial(canvas, lamp_x + 6, lamp_y + 4, 2, 55,
                    (0.95, 0.90, 0.55), max_alpha=0.28)


def draw_gear(canvas, cx, cy, r_outer, r_inner, teeth, col_gear, col_shadow, col_hi):
    """Draw a flat gear shape — used for steampunk scenes."""
    # Outer ring
    draw_circle_filled(canvas, cx, cy, r_outer, col_gear)
    draw_circle_filled(canvas, cx, cy, r_inner, col_shadow)
    draw_circle_filled(canvas, cx, cy, max(2, r_inner - 3), col_gear)
    # Hub hole
    draw_circle_filled(canvas, cx, cy, max(2, r_inner // 3), (0.08, 0.06, 0.04))
    # Teeth (rectangles around circumference)
    tooth_w = max(3, int(2 * math.pi * r_outer / (teeth * 2.5)))
    tooth_h = max(4, r_outer // 5)
    for i in range(teeth):
        angle = 2 * math.pi * i / teeth
        tx = int(cx + (r_outer - tooth_h // 2) * math.cos(angle))
        ty = int(cy + (r_outer - tooth_h // 2) * math.sin(angle))
        draw_rect(canvas, tx - tooth_w // 2, ty - tooth_h // 2,
                  tooth_w, tooth_h, col_gear)
    # Highlight arc (top-left)
    for angle_deg in range(200, 290, 4):
        a = math.radians(angle_deg)
        hx = int(cx + (r_outer - 2) * math.cos(a))
        hy = int(cy + (r_outer - 2) * math.sin(a))
        draw_rect(canvas, hx, hy, 2, 2, col_hi)


def draw_pipe(canvas, x0, y0, x1, y1, thickness, col_pipe, col_hi, col_shadow):
    """Draw a thick horizontal or vertical pipe."""
    if abs(x1 - x0) >= abs(y1 - y0):
        # Horizontal
        lx, rx = min(x0, x1), max(x0, x1)
        draw_rect(canvas, lx, y0 - thickness // 2, rx - lx, thickness, col_pipe)
        draw_hline(canvas, lx, rx, y0 - thickness // 2, col_hi)
        draw_hline(canvas, lx, rx, y0 - thickness // 2 + 1, col_hi)
        draw_hline(canvas, lx, rx, y0 + thickness // 2, col_shadow)
        # Pipe end cap left
        draw_rect(canvas, lx, y0 - thickness // 2, 4, thickness, col_shadow)
        draw_rect(canvas, rx - 4, y0 - thickness // 2, 4, thickness, col_shadow)
    else:
        # Vertical
        ty, by = min(y0, y1), max(y0, y1)
        draw_rect(canvas, x0 - thickness // 2, ty, thickness, by - ty, col_pipe)
        draw_vline(canvas, x0 - thickness // 2, ty, by, col_hi)
        draw_vline(canvas, x0 - thickness // 2 + 1, ty, by, col_hi)
        draw_vline(canvas, x0 + thickness // 2, ty, by, col_shadow)


def draw_locker_bank(canvas, x, y, w, h, num_lockers, col_metal, col_dark, col_handle):
    """Draw a row of school lockers."""
    locker_w = w // num_lockers
    for i in range(num_lockers):
        lx = x + i * locker_w
        # Locker body
        draw_rect(canvas, lx + 1, y + 1, locker_w - 2, h - 2, col_metal)
        # Left highlight
        draw_vline(canvas, lx + 1, y + 1, y + h - 1, col_dark)
        # Right shadow
        draw_vline(canvas, lx + locker_w - 2, y + 1, y + h - 1, col_dark)
        # Vertical divider (between lockers)
        draw_vline(canvas, lx, y, y + h, col_dark)
        # Horizontal vent slots (3 per locker)
        for sv in range(3):
            vy = y + h // 5 + sv * (h // 4)
            draw_hline(canvas, lx + 3, lx + locker_w - 3, vy, col_dark)
            draw_hline(canvas, lx + 3, lx + locker_w - 3, vy + 1, col_dark)
        # Handle / latch
        hx = lx + locker_w // 2 - 1
        hy = y + h // 2
        draw_rect(canvas, hx, hy, 3, 5, col_handle)
    # Top and bottom rails
    draw_hline(canvas, x, x + w, y, col_dark)
    draw_hline(canvas, x, x + w, y + h, col_dark)


# ---------------------------------------------------------------------------
# Backdrop 1 — suburban_neighborhood.png
# ---------------------------------------------------------------------------

def gen_suburban_neighborhood():
    canvas = make_canvas()

    # Sky: warm dusk orange-pink gradient
    sky_top   = (0.45, 0.22, 0.32)   # deep rose-magenta
    sky_mid   = (0.72, 0.38, 0.20)   # burnt orange
    sky_horiz = (0.90, 0.62, 0.28)   # warm amber horizon
    horizon_y = H * 11 // 20         # ~220px

    fill_gradient_v(canvas, 0, horizon_y, sky_top, sky_mid)
    # Horizon glow band
    for y in range(horizon_y - 10, horizon_y + 8):
        t = abs(y - horizon_y) / 10.0
        c = lerp_color(sky_horiz, sky_mid, t)
        canvas[y, :, :3] = c
        canvas[y, :, 3] = 1.0

    # Sun low on horizon (partially behind houses)
    sun_x = W * 3 // 4
    sun_y = horizon_y - 4
    glow_radial(canvas, sun_x, sun_y, 0, 130, (1.0, 0.75, 0.35), max_alpha=0.50)
    draw_circle_filled(canvas, sun_x, sun_y, 22, (1.0, 0.92, 0.62), alpha=0.88)
    draw_circle_filled(canvas, sun_x, sun_y, 18, (1.0, 0.97, 0.82), alpha=0.95)

    # Ground: asphalt road + sidewalk + lawn
    road_y = horizon_y
    ground_col = (0.20, 0.20, 0.22)  # asphalt
    lawn_col   = (0.22, 0.35, 0.14)
    side_col   = (0.52, 0.50, 0.46)  # concrete sidewalk

    # Asphalt road (bottom half)
    fill_gradient_v(canvas, road_y, H, ground_col, (0.16, 0.16, 0.18))

    # Road center dashed yellow line
    dash_y = road_y + (H - road_y) // 2 + 8
    for dx in range(0, W, 40):
        draw_rect(canvas, dx, dash_y, 22, 3, (0.75, 0.68, 0.18))

    # Road edge curb
    curb_y = road_y + 20
    draw_rect(canvas, 0, curb_y - 2, W, 5, (0.40, 0.38, 0.34))
    draw_hline(canvas, 0, W, curb_y - 2, (0.58, 0.55, 0.50))

    # Sidewalk strip
    walk_y = curb_y + 3
    walk_h = 18
    draw_rect(canvas, 0, walk_y, W, walk_h, side_col)
    # Sidewalk crack lines (vertical)
    for cx_s in range(0, W, 48):
        draw_vline(canvas, cx_s, walk_y, walk_y + walk_h, (0.42, 0.40, 0.37))
    draw_hline(canvas, 0, W, walk_y, (0.60, 0.58, 0.54))
    draw_hline(canvas, 0, W, walk_y + walk_h, (0.36, 0.34, 0.30))

    # Lawn
    lawn_y = walk_y + walk_h
    draw_rect(canvas, 0, lawn_y, W, H - lawn_y, lawn_col)
    draw_hline(canvas, 0, W, lawn_y, (0.28, 0.44, 0.18))
    # Grass texture (short vertical dashes)
    rng = np.random.default_rng(42)
    for _ in range(200):
        gx = int(rng.integers(0, W))
        gy = int(rng.integers(lawn_y + 1, min(H, lawn_y + 14)))
        gc = (0.26, 0.42, 0.16) if rng.random() > 0.4 else (0.30, 0.48, 0.20)
        draw_rect(canvas, gx, gy, 2, int(rng.integers(3, 7)), gc)

    # Picket fence
    fence_y = lawn_y + 2
    fence_top = fence_y - 14
    fence_post_w = 4
    fence_gap = 10
    fence_col   = (0.90, 0.88, 0.84)
    fence_dark  = (0.65, 0.62, 0.58)
    # Horizontal rails
    draw_hline(canvas, 0, W, fence_y - 10, fence_col)
    draw_hline(canvas, 0, W, fence_y - 5,  fence_col)
    draw_hline(canvas, 0, W, fence_y - 9,  fence_dark)
    draw_hline(canvas, 0, W, fence_y - 4,  fence_dark)
    # Picket posts
    for px in range(0, W, fence_gap + fence_post_w):
        draw_rect(canvas, px, fence_top, fence_post_w, fence_y + 2 - fence_top, fence_col)
        draw_vline(canvas, px + fence_post_w - 1, fence_top, fence_y + 2, fence_dark)
        # Pointed top
        draw_rect(canvas, px + 1, fence_top - 4, 2, 4, fence_col)

    # Houses (background row — 5 houses)
    house_configs = [
        # x, wall_h, width, wall_col, roof_col, lit
        (10,  70, 100, (0.72, 0.62, 0.50), (0.48, 0.25, 0.18), True),
        (125, 75, 110, (0.60, 0.68, 0.58), (0.35, 0.30, 0.22), True),
        (250, 65,  95, (0.78, 0.70, 0.55), (0.50, 0.28, 0.20), False),
        (360, 78, 115, (0.65, 0.58, 0.72), (0.28, 0.22, 0.35), True),
        (490, 70, 105, (0.70, 0.64, 0.52), (0.42, 0.22, 0.16), True),
    ]
    wall_dark_col = (0.45, 0.40, 0.32)
    door_col = (0.48, 0.28, 0.14)
    trim_col = (0.90, 0.88, 0.82)
    for hx, hwall, hwidth, hwall_col, hroof_col, hlit in house_configs:
        roof_hi = lerp_color(hroof_col, (0.80, 0.70, 0.55), 0.35)
        draw_suburban_house(canvas, hx, horizon_y + 1, hwidth, hwall,
                            hwall_col, wall_dark_col, hroof_col, roof_hi,
                            (0.85, 0.75, 0.38) if hlit else (0.12, 0.14, 0.20),
                            door_col, trim_col, lit=hlit)

    # Mailboxes (near curb)
    mailbox_col   = (0.45, 0.42, 0.62)
    mailbox_dark  = (0.28, 0.26, 0.42)
    mailbox_posts = [55, 180, 300, 430, 555]
    for mpx in mailbox_posts:
        # Post
        draw_rect(canvas, mpx, walk_y - 14, 3, 14, (0.40, 0.38, 0.34))
        # Box body
        draw_rect(canvas, mpx - 5, walk_y - 20, 14, 8, mailbox_col)
        # Rounded top (flat arch)
        draw_hline(canvas, mpx - 5, mpx + 9, walk_y - 20, mailbox_dark)
        draw_rect(canvas, mpx - 5, walk_y - 20, 2, 8, (0.55, 0.52, 0.72))
        # Flag (red, raised)
        draw_rect(canvas, mpx + 7, walk_y - 22, 2, 6, (0.40, 0.38, 0.34))
        draw_rect(canvas, mpx + 9, walk_y - 24, 5, 4, (0.75, 0.20, 0.18))

    # Parked car (mid-road, left side)
    car_x = 80
    car_y = road_y + 30
    car_w, car_h = 80, 28
    car_body_col = (0.28, 0.38, 0.58)
    car_dark     = (0.18, 0.25, 0.40)
    car_glass    = (0.55, 0.70, 0.82)
    # Body
    draw_rect(canvas, car_x, car_y + 10, car_w, car_h - 10, car_body_col)
    # Cabin roof
    draw_rect(canvas, car_x + 12, car_y, car_w - 28, 12, car_body_col)
    draw_rect(canvas, car_x + 12, car_y, 3, 12, lerp_color(car_body_col, (1,1,1), 0.3))
    # Windows
    draw_rect(canvas, car_x + 14, car_y + 1, 20, 9, car_glass)
    draw_rect(canvas, car_x + 38, car_y + 1, 18, 9, car_glass)
    # Window divider
    draw_vline(canvas, car_x + 35, car_y, car_y + 12, car_dark)
    # Wheels
    for wx in [car_x + 12, car_x + car_w - 18]:
        draw_circle_filled(canvas, wx, car_y + car_h, 9, (0.12, 0.12, 0.12))
        draw_circle_filled(canvas, wx, car_y + car_h, 5, (0.28, 0.26, 0.24))
    # Headlight glow (dusk, lights on)
    draw_rect(canvas, car_x + car_w - 3, car_y + 12, 3, 6, (0.95, 0.92, 0.70))
    glow_radial(canvas, car_x + car_w, car_y + 15, 0, 30, (0.95, 0.90, 0.55), max_alpha=0.18)
    # Tail light
    draw_rect(canvas, car_x, car_y + 12, 3, 6, (0.75, 0.18, 0.14))

    # Streetlights (4 positions)
    sl_col = (0.35, 0.33, 0.30)
    for slx in [140, 310, 470]:
        draw_streetlight(canvas, slx, walk_y + walk_h, 58, sl_col, (1.0, 0.95, 0.70), on=True)

    # Distant silhouette trees (far background)
    tree_dark = (0.28, 0.20, 0.30)
    for tx_t in [30, 220, 380, 600]:
        draw_circle_filled(canvas, tx_t, horizon_y - 22, 18, tree_dark, alpha=0.65)
        draw_circle_filled(canvas, tx_t + 10, horizon_y - 26, 14, tree_dark, alpha=0.55)
        draw_rect(canvas, tx_t - 2, horizon_y - 22, 4, 22, tree_dark, alpha=0.65)

    # Dusk atmosphere
    bayer_dither(canvas, scale=0.018)
    quantize_palette(canvas, levels=28)
    fill_alpha(canvas)
    canvas[:, :, :3] *= 0.78   # darken for dialogue
    return to_image(canvas)


# ---------------------------------------------------------------------------
# Backdrop 2 — suburban_school.png
# ---------------------------------------------------------------------------

def gen_suburban_school():
    canvas = make_canvas()

    # Base wall: off-white institutional paint, slight green tint (hospital green)
    wall_top  = (0.72, 0.74, 0.68)
    wall_bot  = (0.64, 0.66, 0.60)
    fill_gradient_v(canvas, 0, H, wall_top, wall_bot)

    # Wainscoting band (darker lower wall)
    wain_y = H * 3 // 4
    wain_col  = (0.52, 0.54, 0.50)
    wain_dark = (0.40, 0.42, 0.38)
    draw_rect(canvas, 0, wain_y, W, H - wain_y, wain_col)
    draw_hline(canvas, 0, W, wain_y, (0.30, 0.32, 0.28))
    draw_hline(canvas, 0, W, wain_y + 1, (0.60, 0.62, 0.56))

    # Checkered floor tiles (cream & slightly darker cream)
    tile_y = H * 5 // 6
    tile_size = 24
    tile_light = (0.82, 0.80, 0.74)
    tile_dark  = (0.70, 0.68, 0.62)
    tile_grout = (0.55, 0.53, 0.48)
    for row, ty in enumerate(range(tile_y, H + tile_size, tile_size)):
        for col_i, tx in enumerate(range(0, W + tile_size, tile_size)):
            tc = tile_light if (row + col_i) % 2 == 0 else tile_dark
            draw_rect(canvas, tx, ty, tile_size - 1, tile_size - 1, tc)
        # Grout lines
        draw_hline(canvas, 0, W, ty, tile_grout)
    for tx_g in range(0, W + tile_size, tile_size):
        draw_vline(canvas, tx_g, tile_y, H, tile_grout)

    # Floor reflection (glossy wax)
    for y in range(tile_y, tile_y + 20):
        t = (y - tile_y) / 20.0
        a = 0.12 * (1 - t)
        canvas[y, :, :3] = canvas[y, :, :3] * (1 - a) + np.array([0.90, 0.88, 0.80]) * a

    # Locker banks — left wall
    locker_metal = (0.48, 0.55, 0.60)
    locker_dark  = (0.30, 0.36, 0.40)
    locker_handle = (0.65, 0.60, 0.45)
    # Left bank
    draw_locker_bank(canvas, 0, 20, 210, wain_y - 20, 7,
                     locker_metal, locker_dark, locker_handle)
    # Right bank
    draw_locker_bank(canvas, W - 210, 20, 210, wain_y - 20, 7,
                     locker_metal, locker_dark, locker_handle)

    # Bulletin board (center-left, above wainscoting)
    board_x, board_y, board_w, board_h = 240, 30, 160, 90
    draw_rect(canvas, board_x - 4, board_y - 4, board_w + 8, board_h + 8, (0.40, 0.32, 0.22))
    draw_rect(canvas, board_x, board_y, board_w, board_h, (0.62, 0.45, 0.28))
    # Papers pinned on board
    paper_configs = [
        (board_x + 8,  board_y + 8,  55, 35, (0.90, 0.88, 0.82)),
        (board_x + 70, board_y + 6,  45, 30, (0.85, 0.88, 0.90)),
        (board_x + 10, board_y + 50, 50, 28, (0.90, 0.86, 0.82)),
        (board_x + 68, board_y + 42, 60, 36, (0.88, 0.90, 0.84)),
    ]
    for px, py, pw, ph, pc in paper_configs:
        draw_rect(canvas, px, py, pw, ph, pc)
        # Text lines on paper
        for line in range(3):
            draw_hline(canvas, px + 4, px + pw - 4, py + 8 + line * 7, (0.55, 0.52, 0.48))
        # Pushpin
        draw_circle_filled(canvas, px + pw // 2, py + 2, 3, (0.75, 0.18, 0.14))
    # Board label
    draw_hline(canvas, board_x, board_x + board_w, board_y - 1, (0.28, 0.22, 0.16))

    # Classroom door (right side of hallway)
    door_x = W - 130
    door_y = 50
    door_w = 60
    door_h = wain_y - 50
    door_col  = (0.55, 0.45, 0.30)
    door_dark = (0.35, 0.28, 0.18)
    door_frame = (0.42, 0.34, 0.22)
    # Frame
    draw_rect(canvas, door_x - 5, door_y - 5, door_w + 10, door_h + 8, door_frame)
    # Door body
    draw_rect(canvas, door_x, door_y, door_w, door_h, door_col)
    # Door panels (raised)
    draw_rect(canvas, door_x + 5, door_y + 8,  door_w - 10, door_h // 2 - 12, door_dark)
    draw_rect(canvas, door_x + 5, door_y + door_h // 2 + 4, door_w - 10, door_h // 2 - 16, door_dark)
    # Door knob
    draw_circle_filled(canvas, door_x + 8, door_y + door_h // 2, 4, (0.75, 0.68, 0.40))
    # Door window (frosted)
    dwin_w, dwin_h = door_w - 14, 20
    draw_rect(canvas, door_x + 7, door_y + 10, dwin_w, dwin_h, (0.70, 0.75, 0.78))
    draw_rect(canvas, door_x + 7, door_y + 10, dwin_w, 2, (0.55, 0.60, 0.64))
    # Light leak under door
    glow_radial(canvas, door_x + door_w // 2, door_y + door_h,
                0, 40, (0.95, 0.92, 0.70), max_alpha=0.12)

    # Fluorescent ceiling lights
    ceiling_light_col  = (0.95, 0.95, 0.88)
    ceiling_light_dim  = (0.78, 0.78, 0.72)  # one flickering
    # Fixture housings
    for fx in [120, 320, 500]:
        draw_rect(canvas, fx - 40, 0, 80, 6, (0.45, 0.46, 0.42))
        draw_rect(canvas, fx - 36, 3, 72, 3, ceiling_light_col)
        draw_hline(canvas, fx - 36, fx + 36, 6, ceiling_light_dim)
    # Central light is flickering (slightly dim/yellow)
    draw_rect(canvas, 280, 3, 72, 3, (0.88, 0.85, 0.68))  # flicker

    # Ceiling light cones (downward glow)
    for fx in [120, 500]:
        light_shaft(canvas, fx, 6, H // 2, 70, 160,
                    (0.95, 0.95, 0.80), max_alpha=0.10)
    # Flickering middle light — dimmer, warmer
    light_shaft(canvas, 320, 6, H // 2, 65, 150,
                (0.90, 0.85, 0.60), max_alpha=0.07)

    # Hallway vanishing point (depth illusion)
    # Darker stripe near vanishing point center
    vp_x = W // 2 + 10
    for y in range(0, H):
        t = y / H
        darkness = 0.06 * (1.0 - t) * math.exp(-abs(y - H // 3) * 0.015)
        canvas[y, vp_x - 30:vp_x + 30, :3] *= (1 - darkness)

    # Corridor ceiling-wall junction molding
    draw_rect(canvas, 0, 0, W, 8, (0.40, 0.42, 0.38))
    draw_hline(canvas, 0, W, 8, (0.62, 0.64, 0.58))

    # Eerie empty feel — slight vignette
    xs = np.arange(W, dtype=np.float32)
    ys = np.arange(H, dtype=np.float32)
    xx, yy = np.meshgrid(xs, ys)
    vign_x = ((xx - W / 2) / (W / 2)) ** 2
    vign_y = ((yy - H / 2) / (H / 2)) ** 2
    vign = np.clip(vign_x + vign_y, 0, 1) * 0.30
    canvas[:, :, :3] *= (1 - vign[:, :, np.newaxis])

    bayer_dither(canvas, scale=0.016)
    quantize_palette(canvas, levels=26)
    fill_alpha(canvas)
    canvas[:, :, :3] *= 0.76   # dim for dialogue + eerie feel
    return to_image(canvas)


# ---------------------------------------------------------------------------
# Backdrop 3 — suburban_park.png
# ---------------------------------------------------------------------------

def gen_suburban_park():
    canvas = make_canvas()

    # Twilight sky: deep purple-blue gradient
    sky_top  = (0.12, 0.08, 0.28)   # deep indigo
    sky_mid  = (0.22, 0.14, 0.40)   # violet
    sky_horiz = (0.35, 0.20, 0.48)  # purple near horizon
    horizon_y = H * 11 // 20

    fill_gradient_v(canvas, 0, horizon_y, sky_top, sky_mid)
    # Horizon glow (slight warm bleed from gone sun)
    for y in range(horizon_y - 15, horizon_y + 5):
        t = (y - (horizon_y - 15)) / 20.0
        c = lerp_color((0.55, 0.28, 0.48), sky_horiz, t)
        canvas[y, :, :3] = c
        canvas[y, :, 3] = 1.0

    # Stars (scattered dots in upper sky)
    rng = np.random.default_rng(77)
    star_col = (0.92, 0.90, 1.00)
    for _ in range(60):
        sx = int(rng.integers(0, W))
        sy = int(rng.integers(0, horizon_y - 30))
        size = 1 if rng.random() > 0.3 else 2
        draw_rect(canvas, sx, sy, size, size, star_col, alpha=float(rng.uniform(0.4, 0.9)))

    # Ground: dark park grass
    ground_col = (0.10, 0.18, 0.08)
    ground_bot = (0.08, 0.14, 0.06)
    fill_gradient_v(canvas, horizon_y, H, ground_col, ground_bot)

    # Walking path (lighter curved arc across mid-ground)
    path_col  = (0.35, 0.32, 0.26)
    path_edge = (0.28, 0.26, 0.20)
    path_y_center = horizon_y + 40
    for x in range(W):
        # Gentle curve
        curve = int(12 * math.sin(x * math.pi / W))
        py = path_y_center + curve
        path_hw = 18
        draw_hline(canvas, x - 1, x + 1, py - path_hw, path_edge)
        for dy in range(-path_hw + 1, path_hw):
            draw_rect(canvas, x, py + dy, 1, 1, path_col)
        draw_hline(canvas, x - 1, x + 1, py + path_hw, path_edge)

    # Park bench (center)
    bench_cx = W // 2 + 20
    bench_y  = path_y_center + 8
    bench_col  = (0.38, 0.28, 0.16)
    bench_dark = (0.24, 0.18, 0.10)
    bench_leg  = (0.22, 0.20, 0.18)
    # Seat planks
    for plank in range(3):
        draw_rect(canvas, bench_cx - 28, bench_y + plank * 3, 56, 2, bench_col)
        draw_hline(canvas, bench_cx - 28, bench_cx + 28, bench_y + plank * 3, bench_dark)
    # Back rest
    for plank in range(3):
        draw_rect(canvas, bench_cx - 28, bench_y - 14 + plank * 4, 56, 2, bench_col)
    # Legs
    for lx in [bench_cx - 22, bench_cx + 18]:
        draw_rect(canvas, lx, bench_y + 8, 3, 10, bench_leg)
        draw_rect(canvas, lx - 4, bench_y + 16, 12, 2, bench_leg)  # foot

    # Large oak tree (dominant, left-center)
    oak_cx  = W // 3
    oak_base = horizon_y + 70
    trunk_col   = (0.28, 0.20, 0.12)
    trunk_dark  = (0.18, 0.13, 0.08)
    can_dark    = (0.06, 0.18, 0.04)   # dark twilight canopy
    can_mid     = (0.09, 0.24, 0.06)
    can_hi      = (0.12, 0.30, 0.08)
    can_shadow  = (0.04, 0.12, 0.03)

    # Trunk
    trunk_w = 14
    draw_rect(canvas, oak_cx - trunk_w // 2, oak_base - 70, trunk_w, 70, trunk_col)
    draw_rect(canvas, oak_cx + trunk_w // 2 - 3, oak_base - 70, 3, 70, trunk_dark)
    # Root flares
    draw_rect(canvas, oak_cx - trunk_w, oak_base - 8, trunk_w // 2, 8, trunk_col)
    draw_rect(canvas, oak_cx + trunk_w // 2, oak_base - 8, trunk_w // 2, 8, trunk_col)

    # Canopy layers (asymmetric for natural look)
    for r, ox, oy, col in [
        (42, 0,   0,   can_shadow),
        (38, -4, -3,   can_dark),
        (32, -8, -6,   can_mid),
        (22, -14,-12,  can_hi),
        (18, 6,  -4,   can_mid),
    ]:
        draw_circle_filled(canvas, oak_cx + ox, oak_base - 68 + oy, r, col)

    # Smaller trees on right side (silhouettes)
    sm_tree_col = (0.08, 0.16, 0.05)
    sm_tree_hi  = (0.10, 0.20, 0.07)
    for stx, str_h, str_r in [(W - 80, 40, 22), (W - 40, 30, 16)]:
        st_base = horizon_y + 45
        draw_rect(canvas, stx - 3, st_base - str_h, 6, str_h, trunk_col)
        draw_circle_filled(canvas, stx, st_base - str_h, str_r, sm_tree_col)
        draw_circle_filled(canvas, stx - 4, st_base - str_h - 4, str_r - 4, sm_tree_hi)

    # Distant houses silhouette on horizon
    house_sil = (0.20, 0.15, 0.30)
    for hsx, hsw, hsh in [(0, 70, 35), (80, 55, 28), (180, 65, 32),
                           (420, 70, 38), (510, 60, 30), (590, 50, 25)]:
        draw_rect(canvas, hsx, horizon_y - hsh, hsw, hsh, house_sil)
        # Roof peak
        for pr in range(hsh // 2):
            t = pr / max(1, hsh // 2 - 1)
            hw = int(hsw // 2 * (1 - t))
            draw_hline(canvas, hsx + hw, hsx + hsw - hw,
                       horizon_y - hsh - hsh // 2 + pr, house_sil)
        # Lit windows (warm amber dots)
        draw_rect(canvas, hsx + 12, horizon_y - hsh + 10, 8, 6, (0.75, 0.62, 0.28), alpha=0.7)
        draw_rect(canvas, hsx + 30, horizon_y - hsh + 10, 8, 6, (0.72, 0.58, 0.24), alpha=0.6)

    # Playground silhouettes (far background)
    play_col = (0.18, 0.16, 0.24)
    # Swing set
    sw_x = W - 200
    sw_y = horizon_y + 15
    # A-frame legs
    draw_rect(canvas, sw_x - 20, sw_y, 3, 30, play_col)
    draw_rect(canvas, sw_x + 17, sw_y, 3, 30, play_col)
    draw_hline(canvas, sw_x - 22, sw_x + 22, sw_y - 1, play_col)
    # Swing chains
    for sc in [sw_x - 8, sw_x + 8]:
        draw_vline(canvas, sc, sw_y, sw_y + 20, play_col)
        draw_rect(canvas, sc - 5, sw_y + 18, 10, 3, play_col)  # seat
    # Slide (simple triangle ramp)
    sl_base_x = W - 310
    draw_rect(canvas, sl_base_x, horizon_y + 5, 5, 40, play_col)  # pole
    for sr in range(30):
        t = sr / 30
        draw_hline(canvas, sl_base_x - int(t * 38), sl_base_x, horizon_y + 5 + sr, play_col)

    # Fireflies (tiny glowing dots scattered near ground)
    firefly_col = (0.85, 0.95, 0.40)
    for _ in range(18):
        ffx = int(rng.integers(40, W - 40))
        ffy = int(rng.integers(horizon_y + 10, H - 30))
        draw_circle_filled(canvas, ffx, ffy, 2, firefly_col, alpha=float(rng.uniform(0.5, 0.9)))
        glow_radial(canvas, ffx, ffy, 0, 8, firefly_col, max_alpha=0.25)

    # Path lamp (single park light near bench)
    lamp_x = bench_cx + 50
    lamp_base = path_y_center + 20
    draw_rect(canvas, lamp_x - 1, lamp_base - 55, 3, 55, (0.35, 0.33, 0.30))
    draw_circle_filled(canvas, lamp_x, lamp_base - 55, 7, (0.35, 0.33, 0.30))
    draw_circle_filled(canvas, lamp_x, lamp_base - 55, 4, (0.98, 0.94, 0.68))
    glow_radial(canvas, lamp_x, lamp_base - 55, 2, 70,
                (0.95, 0.88, 0.55), max_alpha=0.32)

    # Soft ground mist
    draw_mist_layer(canvas, H - 50, H, (0.25, 0.22, 0.35), density=0.20)

    bayer_dither(canvas, scale=0.020)
    quantize_palette(canvas, levels=26)
    fill_alpha(canvas)
    canvas[:, :, :3] *= 0.80
    return to_image(canvas)


# ---------------------------------------------------------------------------
# Backdrop 4 — steampunk_workshop.png
# ---------------------------------------------------------------------------

def gen_steampunk_workshop():
    canvas = make_canvas()

    # Base: warm wood-paneled walls, amber light
    wall_col   = (0.38, 0.26, 0.14)
    wall_light = (0.50, 0.35, 0.18)
    wall_dark  = (0.24, 0.16, 0.08)
    fill_gradient_v(canvas, 0, H, wall_light, wall_col)

    # Wood plank texture (horizontal boards)
    for board_y in range(0, H, 18):
        draw_hline(canvas, 0, W, board_y, wall_dark)
        draw_hline(canvas, 0, W, board_y + 1, lerp_color(wall_light, wall_col, board_y / H))
        # Wood grain variation
        rng_grain = np.random.default_rng(board_y * 3 + 7)
        grain_col = lerp_color(wall_col, wall_light, float(rng_grain.uniform(0.1, 0.4)))
        offset = int(rng_grain.integers(0, W // 3))
        draw_hline(canvas, offset, offset + int(rng_grain.integers(40, 120)),
                   board_y + 9, grain_col)

    # Workbench (lower third)
    bench_y = H * 2 // 3
    bench_col  = (0.45, 0.30, 0.14)
    bench_dark = (0.28, 0.18, 0.08)
    bench_top  = (0.55, 0.40, 0.20)
    bench_edge = (0.22, 0.14, 0.06)
    draw_rect(canvas, 0, bench_y, W, H - bench_y, bench_col)
    draw_hline(canvas, 0, W, bench_y, bench_top)
    draw_hline(canvas, 0, W, bench_y + 1, bench_top)
    draw_hline(canvas, 0, W, bench_y + 2, bench_dark)
    # Bench wood planks
    for bpx in range(0, W, 60):
        draw_vline(canvas, bpx, bench_y, H, bench_edge)
    # Bench legs
    for bl in [30, W - 40]:
        draw_rect(canvas, bl, bench_y + 6, 12, H - bench_y - 6, bench_dark)
        draw_vline(canvas, bl + 1, bench_y + 6, H, lerp_color(bench_col, (1,1,1), 0.2))

    # Floor (worn stone)
    floor_y = H - 40
    floor_col  = (0.30, 0.26, 0.22)
    floor_dark = (0.20, 0.17, 0.14)
    floor_grout = (0.18, 0.15, 0.12)
    draw_cobblestone_floor_simple(canvas, floor_y, H, floor_col, floor_dark, floor_grout)

    # Hanging lamps (3 pendant lamps from ceiling)
    lamp_col  = (0.55, 0.42, 0.20)
    lamp_glow = (0.95, 0.75, 0.35)
    lamp_ys   = [(W // 6, 50), (W // 2, 40), (W * 5 // 6, 55)]
    for lx, ly in lamp_ys:
        # Cord
        draw_vline(canvas, lx, 0, ly, (0.20, 0.16, 0.10))
        # Lamp housing (cone shape)
        cone_h = 20
        for cr in range(cone_h):
            t = cr / max(1, cone_h - 1)
            hw = int(3 + t * 14)
            row_col = lerp_color(lamp_col, (0.35, 0.26, 0.10), t * 0.5)
            draw_hline(canvas, lx - hw, lx + hw, ly + cr, row_col)
        # Lamp bottom glow
        draw_circle_filled(canvas, lx, ly + cone_h, 5, lamp_glow, alpha=0.9)
        glow_radial(canvas, lx, ly + cone_h, 0, 80, (0.90, 0.65, 0.25), max_alpha=0.40)
        glow_radial(canvas, lx, ly + cone_h, 0, 30, (1.0, 0.85, 0.45), max_alpha=0.55)

    # Gears on walls (large decorative, background)
    brass_col   = (0.72, 0.55, 0.22)
    brass_dark  = (0.45, 0.32, 0.12)
    brass_hi    = (0.90, 0.75, 0.40)
    copper_col  = (0.65, 0.35, 0.18)
    copper_dark = (0.40, 0.22, 0.10)
    copper_hi   = (0.82, 0.50, 0.28)

    # Large wall gear, left
    draw_gear(canvas, 80, 120, 55, 30, 14, brass_col, brass_dark, brass_hi)
    # Medium gear, right wall
    draw_gear(canvas, W - 90, 100, 42, 22, 11, copper_col, copper_dark, copper_hi)
    # Small interlocked gear
    draw_gear(canvas, W - 45, 148, 20, 10, 8, brass_col, brass_dark, brass_hi)
    # Tiny accent gear
    draw_gear(canvas, 135, 95, 15, 7, 6, copper_col, copper_dark, copper_hi)

    # Pipes running along top and sides
    pipe_col  = (0.60, 0.42, 0.20)
    pipe_hi   = (0.80, 0.62, 0.35)
    pipe_dark = (0.35, 0.24, 0.10)
    # Top horizontal pipe
    draw_pipe(canvas, 0, 12, W, 12, 12, pipe_col, pipe_hi, pipe_dark)
    # Left vertical pipe
    draw_pipe(canvas, 40, 12, 40, bench_y, 10, pipe_col, pipe_hi, pipe_dark)
    # Right vertical pipe
    draw_pipe(canvas, W - 40, 12, W - 40, bench_y, 10, pipe_col, pipe_hi, pipe_dark)
    # Valve on left pipe
    draw_circle_filled(canvas, 40, 80, 10, brass_col)
    draw_circle_filled(canvas, 40, 80, 6, brass_dark)
    draw_rect(canvas, 28, 78, 24, 4, brass_hi)  # valve handle

    # Blueprints pinned to wall (center-upper)
    bp_x, bp_y, bp_w, bp_h = 220, 25, 200, 110
    draw_rect(canvas, bp_x - 3, bp_y - 3, bp_w + 6, bp_h + 6, wall_dark)
    draw_rect(canvas, bp_x, bp_y, bp_w, bp_h, (0.18, 0.28, 0.45))  # blueprint blue
    # Blueprint grid lines
    bp_line_col = (0.28, 0.42, 0.62)
    for bly in range(bp_y + 8, bp_y + bp_h, 12):
        draw_hline(canvas, bp_x, bp_x + bp_w, bly, bp_line_col)
    for blx in range(bp_x + 8, bp_x + bp_w, 12):
        draw_vline(canvas, blx, bp_y, bp_y + bp_h, bp_line_col)
    # Blueprint drawing (gear/machine schematic lines)
    schematic_col = (0.75, 0.88, 1.00)
    draw_circle_filled(canvas, bp_x + bp_w // 2, bp_y + bp_h // 2, 30, (0.20, 0.32, 0.50))
    draw_circle_filled(canvas, bp_x + bp_w // 2, bp_y + bp_h // 2, 25, (0.28, 0.42, 0.62))
    # Gear teeth lines on blueprint
    for t_ang in range(0, 360, 30):
        a = math.radians(t_ang)
        tx_s = int(bp_x + bp_w // 2 + 26 * math.cos(a))
        ty_s = int(bp_y + bp_h // 2 + 26 * math.sin(a))
        draw_rect(canvas, tx_s - 2, ty_s - 2, 4, 4, schematic_col)
    # Dimension lines
    draw_hline(canvas, bp_x + 8, bp_x + bp_w - 8, bp_y + bp_h - 12, schematic_col)
    draw_vline(canvas, bp_x + 8, bp_y + bp_h - 18, bp_y + bp_h - 6, schematic_col)
    draw_vline(canvas, bp_x + bp_w - 8, bp_y + bp_h - 18, bp_y + bp_h - 6, schematic_col)
    # Pushpin
    draw_circle_filled(canvas, bp_x + bp_w // 2, bp_y - 1, 4, (0.80, 0.20, 0.14))

    # Half-built machine on workbench (right side)
    mach_x = W - 200
    mach_y = bench_y - 60
    # Machine body (brass box)
    draw_rect(canvas, mach_x, mach_y + 20, 80, 40, brass_col)
    draw_hline(canvas, mach_x, mach_x + 80, mach_y + 20, brass_hi)
    draw_rect(canvas, mach_x, mach_y + 20, 3, 40, brass_hi)
    draw_rect(canvas, mach_x + 77, mach_y + 20, 3, 40, brass_dark)
    # Gears on machine
    draw_gear(canvas, mach_x + 20, mach_y + 38, 14, 7, 6, brass_col, brass_dark, brass_hi)
    draw_gear(canvas, mach_x + 50, mach_y + 38, 10, 5, 5, copper_col, copper_dark, copper_hi)
    # Machine pipe/exhaust
    draw_rect(canvas, mach_x + 60, mach_y, 8, 22, pipe_col)
    draw_rect(canvas, mach_x + 57, mach_y, 14, 5, pipe_col)  # cap

    # Small tools on bench (left side)
    tool_col = (0.50, 0.45, 0.38)
    draw_rect(canvas, 60, bench_y + 4, 40, 4, tool_col)  # spanner
    draw_circle_filled(canvas, 100, bench_y + 6, 5, tool_col)
    draw_circle_filled(canvas, 100, bench_y + 6, 3, bench_dark)
    draw_rect(canvas, 110, bench_y + 3, 28, 6, (0.60, 0.55, 0.42))  # file/ruler
    # Scattered bolts
    for bx_t in [140, 150, 158]:
        draw_circle_filled(canvas, bx_t, bench_y + 8, 3, brass_col)
        draw_circle_filled(canvas, bx_t, bench_y + 8, 1, brass_dark)

    # Warm ambient glow from lamps
    glow_radial(canvas, W // 2, 80, 0, W // 2, (0.80, 0.58, 0.22), max_alpha=0.15)

    # Steam wisps from pipe joints
    steam_col = (0.78, 0.75, 0.70)
    draw_mist_layer(canvas, 8, 22, steam_col, density=0.20)

    bayer_dither(canvas, scale=0.022)
    quantize_palette(canvas, levels=24)
    fill_alpha(canvas)
    canvas[:, :, :3] *= 0.78
    return to_image(canvas)


def draw_cobblestone_floor_simple(canvas, y_start, y_end, col_stone, col_shadow, col_grout):
    stone_w = 32
    stone_h = 16
    for row_idx, y in enumerate(range(y_start, y_end, stone_h)):
        offset = (row_idx % 2) * (stone_w // 2)
        for x in range(-offset, W + stone_w, stone_w):
            draw_rect(canvas, x + 1, y + 1, stone_w - 2, stone_h - 2, col_stone)
            draw_hline(canvas, x, x + stone_w, y, col_grout)
            draw_rect(canvas, x, y, 1, stone_h, col_grout)
            draw_hline(canvas, x + 1, x + stone_w, y + stone_h - 2, col_shadow)
            draw_rect(canvas, x + stone_w - 2, y + 1, 2, stone_h - 2, col_shadow)


# ---------------------------------------------------------------------------
# Backdrop 5 — steampunk_airship.png
# ---------------------------------------------------------------------------

def gen_steampunk_airship():
    canvas = make_canvas()

    # Sky: cool blue-gray with high altitude feel
    sky_top   = (0.35, 0.42, 0.58)   # steel blue
    sky_mid   = (0.55, 0.62, 0.72)   # lighter mid
    sky_horiz = (0.72, 0.76, 0.80)   # pale horizon
    horizon_y = H * 3 // 4

    fill_gradient_v(canvas, 0, horizon_y, sky_top, sky_mid)
    fill_gradient_v(canvas, horizon_y - 20, horizon_y + 10, sky_mid, sky_horiz)

    # Sun glint (high, small — high altitude)
    sun_x, sun_y = W * 3 // 4 + 40, 40
    glow_radial(canvas, sun_x, sun_y, 0, 90, (1.0, 0.95, 0.82), max_alpha=0.30)
    draw_circle_filled(canvas, sun_x, sun_y, 14, (1.0, 0.97, 0.88), alpha=0.75)

    # Clouds (layered, receding in perspective)
    cloud_configs = [
        # y, x_center, w, h, alpha, col
        (80,  120, 180, 40, 0.65, (0.88, 0.90, 0.95)),
        (100, 400, 220, 35, 0.60, (0.84, 0.86, 0.92)),
        (140, 280, 150, 28, 0.50, (0.80, 0.82, 0.88)),
        (200, 500, 200, 22, 0.45, (0.78, 0.80, 0.86)),
        (230, 80,  140, 18, 0.40, (0.76, 0.78, 0.84)),
        # Clouds below/near deck level
        (300, 180, 320, 50, 0.70, (0.82, 0.84, 0.90)),
        (320, 480, 250, 45, 0.65, (0.80, 0.82, 0.88)),
    ]
    for cy_c, cx_c, cw, ch, ca, cc in cloud_configs:
        # Cloud: overlapping ellipses
        draw_circle_filled(canvas, cx_c, cy_c, ch, cc, alpha=ca)
        draw_circle_filled(canvas, cx_c + cw // 4, cy_c - ch // 3, int(ch * 0.8), cc, alpha=ca)
        draw_circle_filled(canvas, cx_c - cw // 4, cy_c - ch // 4, int(ch * 0.7), cc, alpha=ca * 0.8)
        draw_rect(canvas, cx_c - cw // 2, cy_c, cw, ch // 2, cc, alpha=ca)

    # Distant city of spires on horizon
    city_y = horizon_y - 5
    city_col   = (0.32, 0.28, 0.38)   # silhouette, cool purple-gray
    city_brass = (0.55, 0.42, 0.20)   # lit brass towers
    # Skyline buildings
    buildings = [
        (20, city_y, 35, 55),  (70, city_y, 28, 40),  (110, city_y, 42, 70),
        (165, city_y, 22, 35), (200, city_y, 38, 62), (250, city_y, 30, 45),
        (300, city_y, 25, 30), (340, city_y, 45, 80), (400, city_y, 28, 50),
        (440, city_y, 35, 65), (490, city_y, 20, 38), (520, city_y, 40, 55),
        (575, city_y, 32, 48), (620, city_y, 30, 42),
    ]
    for bx, by, bw, bh in buildings:
        draw_rect(canvas, bx, by - bh, bw, bh, city_col)
        # Spire
        spire_h = bh // 3
        for sr in range(spire_h):
            t = sr / max(1, spire_h - 1)
            hw = int(bw // 2 * (1 - t))
            draw_hline(canvas, bx + bw // 2 - hw, bx + bw // 2 + hw,
                       by - bh - spire_h + sr, city_col)
        # Brass-lit tower windows
        if bw > 30:
            for wy in range(by - bh + 8, by - 5, 14):
                draw_rect(canvas, bx + 4, wy, 6, 5, (0.70, 0.55, 0.25), alpha=0.7)
                draw_rect(canvas, bx + bw - 10, wy, 6, 5, (0.65, 0.50, 0.22), alpha=0.6)

    # Smokestacks (3, with smoke plumes)
    smoke_col = (0.32, 0.30, 0.30)
    for ssx in [90, 200, 420]:
        ss_base = city_y - 5
        ss_h = 40
        draw_rect(canvas, ssx, ss_base - ss_h, 8, ss_h, smoke_col)
        draw_rect(canvas, ssx - 2, ss_base - ss_h, 12, 5, smoke_col)  # cap
        # Smoke plume
        for sp in range(6):
            plume_y = ss_base - ss_h - sp * 12 - 8
            draw_circle_filled(canvas, ssx + 4 + sp * 4, plume_y,
                               6 + sp * 2, (0.42, 0.40, 0.38), alpha=0.35 - sp * 0.04)

    # Below the deck — vast cloud sea (drawn AFTER city so clouds sit in front)
    cloud_sea_y = horizon_y - 15  # slightly overlap horizon to merge seamlessly
    fill_gradient_v(canvas, cloud_sea_y, H, (0.78, 0.80, 0.85), (0.65, 0.68, 0.74))
    # Cloud tops texture in cloud sea
    for cy_s in range(cloud_sea_y, H, 20):
        wave_amp = 8
        for x in range(0, W, 2):
            wave = int(wave_amp * math.sin(x * 0.05 + cy_s * 0.1))
            wy = cy_s + wave
            if 0 <= wy < H:
                cc_w = (0.82, 0.84, 0.88)
                draw_rect(canvas, x, wy, 2, 3, cc_w, alpha=0.20)
    # Horizon blend strip so cloud sea meets sky smoothly
    for y in range(cloud_sea_y - 10, cloud_sea_y + 10):
        if 0 <= y < H:
            t = (y - (cloud_sea_y - 10)) / 20.0
            canvas[y, :, :3] = np.clip(
                canvas[y, :, :3] * (1 - t * 0.4) + np.array([0.78, 0.80, 0.85]) * t * 0.4, 0, 1)

    # Airship deck (foreground, lower portion)
    deck_y  = H * 9 // 16   # ~200px
    deck_h  = H - deck_y
    brass_col  = (0.68, 0.50, 0.20)
    brass_hi   = (0.88, 0.72, 0.38)
    brass_dark = (0.42, 0.30, 0.10)
    wood_col   = (0.48, 0.32, 0.14)
    wood_dark  = (0.30, 0.20, 0.08)
    iron_col   = (0.35, 0.33, 0.30)
    iron_dark  = (0.20, 0.18, 0.16)

    # Deck boards
    draw_rect(canvas, 0, deck_y, W, deck_h, wood_col)
    for plk_x in range(0, W, 36):
        draw_vline(canvas, plk_x, deck_y, H, wood_dark)
        draw_vline(canvas, plk_x + 1, deck_y, H, lerp_color(wood_col, (1,1,1), 0.15))
    # Deck edge rail
    draw_hline(canvas, 0, W, deck_y, brass_hi)
    draw_hline(canvas, 0, W, deck_y + 1, brass_col)
    draw_hline(canvas, 0, W, deck_y + 2, brass_dark)

    # Brass railing (left and right sides of deck)
    rail_h = 35
    rail_top_y = deck_y - rail_h
    # Left railing
    draw_rect(canvas, 0, rail_top_y, 8, rail_h + 4, brass_col)
    draw_vline(canvas, 0, rail_top_y, deck_y + 4, brass_hi)
    draw_vline(canvas, 7, rail_top_y, deck_y + 4, brass_dark)
    # Top cap
    draw_rect(canvas, -2, rail_top_y, 12, 5, brass_hi)
    # Vertical balusters
    for bx_r in range(0, 80, 18):
        draw_rect(canvas, bx_r + 10, rail_top_y + 5, 5, rail_h - 5, brass_col)
        draw_vline(canvas, bx_r + 11, rail_top_y + 5, deck_y, brass_hi)

    # Right railing
    draw_rect(canvas, W - 8, rail_top_y, 8, rail_h + 4, brass_col)
    draw_vline(canvas, W - 8, rail_top_y, deck_y + 4, brass_hi)
    draw_vline(canvas, W - 1, rail_top_y, deck_y + 4, brass_dark)
    draw_rect(canvas, W - 10, rail_top_y, 12, 5, brass_hi)
    for bx_r in range(0, 80, 18):
        draw_rect(canvas, W - bx_r - 15, rail_top_y + 5, 5, rail_h - 5, brass_col)
        draw_vline(canvas, W - bx_r - 14, rail_top_y + 5, deck_y, brass_hi)

    # Steam vents on deck surface
    vent_y = deck_y + 8
    for svx in [120, 280, 460]:
        draw_rect(canvas, svx - 6, vent_y - 5, 12, 10, iron_col)
        draw_rect(canvas, svx - 4, vent_y - 3, 8, 6, iron_dark)
        draw_rect(canvas, svx - 8, vent_y - 2, 16, 4, iron_col)  # rim
    # Steam puff layer above deck (drawn once, not per vent)
    draw_mist_layer(canvas, deck_y - 22, deck_y + 2,
                    (0.85, 0.84, 0.82), density=0.14)

    # Propeller (right side, partially visible)
    prop_cx = W - 30
    prop_cy = deck_y - 20
    draw_circle_filled(canvas, prop_cx, prop_cy, 8, brass_col)
    draw_circle_filled(canvas, prop_cx, prop_cy, 5, brass_dark)
    # Blades
    for ba in [0, 90, 180, 270]:
        a = math.radians(ba + 20)
        blade_len = 28
        bex = int(prop_cx + blade_len * math.cos(a))
        bey = int(prop_cy + blade_len * math.sin(a))
        for bl_s in range(blade_len):
            t = bl_s / blade_len
            bx_b = int(prop_cx + bl_s * math.cos(a))
            by_b = int(prop_cy + bl_s * math.sin(a))
            bw_b = max(2, int(8 * (1 - t)))
            perp_a = a + math.pi / 2
            draw_rect(canvas, bx_b - bw_b // 2, by_b - bw_b // 2,
                      bw_b, bw_b, brass_col)

    # Rope/rigging lines
    rigging_col = (0.25, 0.20, 0.12)
    for rig_data in [(0, rail_top_y, 180, rail_top_y - 30),
                     (180, rail_top_y - 30, W, rail_top_y),
                     (80, rail_top_y, 80, deck_y - 10)]:
        rx0, ry0, rx1, ry1 = rig_data
        steps = max(abs(rx1 - rx0), abs(ry1 - ry0))
        for rs in range(steps):
            t = rs / max(1, steps)
            rix = int(rx0 + (rx1 - rx0) * t)
            riy = int(ry0 + (ry1 - ry0) * t)
            draw_rect(canvas, rix, riy, 1, 1, rigging_col)

    bayer_dither(canvas, scale=0.020)
    quantize_palette(canvas, levels=26)
    fill_alpha(canvas)
    canvas[:, :, :3] *= 0.80
    return to_image(canvas)


# ---------------------------------------------------------------------------
# Backdrop 6 — industrial_factory.png
# ---------------------------------------------------------------------------

def gen_industrial_factory():
    canvas = make_canvas()

    # Base environment: dark concrete/iron interior
    ceiling_col = (0.16, 0.16, 0.18)
    floor_col   = (0.22, 0.22, 0.24)
    wall_col    = (0.20, 0.20, 0.22)
    fill_gradient_v(canvas, 0, H, ceiling_col, floor_col)

    # Ceiling grid (industrial steel beam grid)
    beam_col  = (0.28, 0.27, 0.26)
    beam_hi   = (0.38, 0.37, 0.36)
    beam_dark = (0.14, 0.13, 0.12)
    # Main horizontal beams
    for by in [0, 30, 60]:
        draw_rect(canvas, 0, by, W, 14, beam_col)
        draw_hline(canvas, 0, W, by, beam_hi)
        draw_hline(canvas, 0, W, by + 13, beam_dark)
    # Vertical cross-beams
    for bx in range(0, W + 60, 80):
        draw_rect(canvas, bx, 0, 10, 75, beam_col)
        draw_vline(canvas, bx, 0, 75, beam_hi)
        draw_vline(canvas, bx + 9, 0, 75, beam_dark)

    # Harsh fluorescent lights on ceiling
    fluor_col = (0.92, 0.96, 0.88)
    fluor_housing = (0.30, 0.30, 0.28)
    for fx in range(80, W, 160):
        draw_rect(canvas, fx - 50, 2, 100, 8, fluor_housing)
        draw_rect(canvas, fx - 46, 4, 92, 4, fluor_col)
        # Harsh downward light cones
        light_shaft(canvas, fx, 10, H * 2 // 3, 90, 200,
                    (0.88, 0.92, 0.78), max_alpha=0.22)

    # Factory floor
    factory_floor_y = H * 7 // 10
    floor_tile_col   = (0.28, 0.28, 0.30)
    floor_tile_dark  = (0.18, 0.18, 0.20)
    floor_tile_grout = (0.14, 0.14, 0.16)
    draw_rect(canvas, 0, factory_floor_y, W, H - factory_floor_y, floor_tile_col)
    # Floor tiles
    for ty in range(factory_floor_y, H, 20):
        draw_hline(canvas, 0, W, ty, floor_tile_grout)
    for tx in range(0, W, 40):
        draw_vline(canvas, tx, factory_floor_y, H, floor_tile_grout)
    draw_hline(canvas, 0, W, factory_floor_y, floor_tile_dark)
    draw_hline(canvas, 0, W, factory_floor_y + 1, (0.38, 0.38, 0.40))

    # Hazard stripes on floor (yellow/black)
    haz_y = factory_floor_y + 8
    haz_h = 14
    haz_yellow = (0.78, 0.70, 0.12)
    haz_black  = (0.10, 0.10, 0.10)
    stripe_w = 22
    for sx in range(0, W + stripe_w, stripe_w * 2):
        draw_rect(canvas, sx, haz_y, stripe_w, haz_h, haz_yellow)
        draw_rect(canvas, sx + stripe_w, haz_y, stripe_w, haz_h, haz_black)
    # Border lines
    draw_hline(canvas, 0, W, haz_y, (0.55, 0.50, 0.08))
    draw_hline(canvas, 0, W, haz_y + haz_h, (0.55, 0.50, 0.08))

    # Assembly line conveyor belt (center)
    conv_y = factory_floor_y - 35
    conv_h = 28
    conv_col   = (0.30, 0.28, 0.26)
    conv_belt  = (0.22, 0.20, 0.18)
    conv_roller = (0.42, 0.40, 0.38)
    # Belt frame
    draw_rect(canvas, 0, conv_y, W, conv_h, conv_col)
    draw_hline(canvas, 0, W, conv_y, (0.45, 0.43, 0.40))
    draw_hline(canvas, 0, W, conv_y + conv_h, (0.16, 0.15, 0.14))
    # Belt surface
    draw_rect(canvas, 0, conv_y + 4, W, conv_h - 8, conv_belt)
    # Belt segment lines
    for bsx in range(0, W, 18):
        draw_vline(canvas, bsx, conv_y + 4, conv_y + conv_h - 4, (0.28, 0.26, 0.24))
    # Rollers at each end
    for rx in [0, W - 14]:
        draw_rect(canvas, rx, conv_y, 14, conv_h, conv_roller)
        draw_vline(canvas, rx + 1, conv_y, conv_y + conv_h, (0.55, 0.52, 0.48))
        draw_vline(canvas, rx + 12, conv_y, conv_y + conv_h, (0.28, 0.26, 0.24))

    # Objects on conveyor (product boxes)
    box_col   = (0.52, 0.42, 0.28)
    box_dark  = (0.32, 0.25, 0.16)
    box_light = (0.65, 0.55, 0.38)
    for bx_c, bw, bh in [(80, 30, 20), (180, 26, 18), (320, 32, 22), (450, 28, 18), (570, 24, 16)]:
        by_c = conv_y + 4
        draw_rect(canvas, bx_c, by_c, bw, bh, box_col)
        draw_hline(canvas, bx_c, bx_c + bw, by_c, box_light)
        draw_rect(canvas, bx_c, by_c, 2, bh, box_light)
        draw_rect(canvas, bx_c + bw - 2, by_c, 2, bh, box_dark)

    # Robotic arms (3, overhead — dark mechanical silhouettes)
    arm_col  = (0.24, 0.22, 0.22)
    arm_hi   = (0.38, 0.36, 0.34)
    arm_joint = (0.35, 0.32, 0.30)
    arm_glow  = (1.00, 0.62, 0.10)   # welding spark

    arm_positions = [(W // 5, conv_y - 10), (W // 2, conv_y - 5), (W * 4 // 5, conv_y - 8)]
    for ai, (ax, ay) in enumerate(arm_positions):
        # Mount on ceiling
        draw_rect(canvas, ax - 8, 60, 16, 20, arm_col)
        # Upper arm
        ua_angle = math.radians(60 + ai * 15)
        ua_len = 55
        ua_ex = int(ax + ua_len * math.cos(ua_angle))
        ua_ey = int(60 + 20 + ua_len * math.sin(ua_angle))
        for us in range(ua_len):
            t = us / ua_len
            ux = int(ax + us * math.cos(ua_angle))
            uy = int(60 + 20 + us * math.sin(ua_angle))
            draw_rect(canvas, ux - 4, uy - 4, 8, 8, arm_col)
        # Joint
        draw_circle_filled(canvas, ua_ex, ua_ey, 8, arm_joint)
        draw_circle_filled(canvas, ua_ex, ua_ey, 5, arm_col)
        # Lower arm (angled toward conveyor)
        la_angle = math.radians(95 + ai * 10)
        la_len = 50
        la_ex = int(ua_ex + la_len * math.cos(la_angle))
        la_ey = int(ua_ey + la_len * math.sin(la_angle))
        for ls in range(la_len):
            lx_a = int(ua_ex + ls * math.cos(la_angle))
            ly_a = int(ua_ey + ls * math.sin(la_angle))
            draw_rect(canvas, lx_a - 3, ly_a - 3, 6, 6, arm_col)
        # End effector
        draw_rect(canvas, la_ex - 6, la_ey - 4, 12, 8, arm_hi)
        # Welding spark on arm 2 (center)
        if ai == 1:
            glow_radial(canvas, la_ex, la_ey, 0, 25, arm_glow, max_alpha=0.70)
            draw_circle_filled(canvas, la_ex, la_ey, 4, (1.0, 0.90, 0.55), alpha=0.95)
            # Spark particles
            rng_sp = np.random.default_rng(555)
            for _ in range(8):
                spx = la_ex + int(rng_sp.integers(-12, 12))
                spy = la_ey + int(rng_sp.integers(-8, 8))
                draw_rect(canvas, spx, spy, 2, 2, arm_glow,
                          alpha=float(rng_sp.uniform(0.5, 0.9)))

    # Wall with safety signage (right side)
    sign_bg = (0.65, 0.58, 0.12)
    sign_text_col = (0.08, 0.08, 0.08)
    # Warning triangle sign
    tri_x, tri_y = W - 75, 90
    draw_rect(canvas, tri_x, tri_y, 50, 44, sign_bg)
    draw_rect(canvas, tri_x, tri_y, 50, 3, sign_text_col)
    draw_rect(canvas, tri_x, tri_y + 41, 50, 3, sign_text_col)
    draw_rect(canvas, tri_x, tri_y, 3, 44, sign_text_col)
    draw_rect(canvas, tri_x + 47, tri_y, 3, 44, sign_text_col)
    # Exclamation mark
    draw_rect(canvas, tri_x + 22, tri_y + 8, 6, 18, sign_text_col)
    draw_rect(canvas, tri_x + 22, tri_y + 30, 6, 6, sign_text_col)

    # Pipes along upper walls
    pipe_col  = (0.38, 0.35, 0.32)
    pipe_hi   = (0.52, 0.48, 0.44)
    pipe_dark = (0.22, 0.20, 0.18)
    draw_pipe(canvas, 0, 78, W, 78, 10, pipe_col, pipe_hi, pipe_dark)
    draw_pipe(canvas, 0, 92, W // 2, 92, 7, (0.42, 0.30, 0.20),
              (0.58, 0.44, 0.28), (0.26, 0.18, 0.10))

    # Ambient sparks floating (light industrial haze)
    rng_amb = np.random.default_rng(321)
    for _ in range(20):
        sx_a = int(rng_amb.integers(0, W))
        sy_a = int(rng_amb.integers(70, factory_floor_y))
        draw_rect(canvas, sx_a, sy_a, 2, 2, (0.90, 0.65, 0.20),
                  alpha=float(rng_amb.uniform(0.3, 0.7)))

    # Industrial haze / air pollution layer
    draw_mist_layer(canvas, 65, 100, (0.28, 0.26, 0.22), density=0.18)

    bayer_dither(canvas, scale=0.018)
    quantize_palette(canvas, levels=22)
    fill_alpha(canvas)
    canvas[:, :, :3] *= 0.78
    return to_image(canvas)


# ---------------------------------------------------------------------------
# Backdrop 7 — industrial_furnace.png
# ---------------------------------------------------------------------------

def gen_industrial_furnace():
    canvas = make_canvas()

    # Base: deep darkness, iron black
    fill_gradient_v(canvas, 0, H, (0.06, 0.04, 0.04), (0.10, 0.06, 0.04))

    # Iron wall texture (dark riveted plates)
    wall_plate  = (0.14, 0.10, 0.08)
    wall_dark   = (0.08, 0.05, 0.04)
    wall_rivet  = (0.20, 0.15, 0.10)
    plate_w, plate_h = 80, 60
    for row_idx, py in enumerate(range(0, H, plate_h)):
        offset = (row_idx % 2) * (plate_w // 2)
        for px in range(-offset, W + plate_w, plate_w):
            draw_rect(canvas, px + 1, py + 1, plate_w - 2, plate_h - 2, wall_plate)
            # Plate shadow/depth
            draw_hline(canvas, px, px + plate_w, py, wall_dark)
            draw_rect(canvas, px, py, 1, plate_h, wall_dark)
            draw_hline(canvas, px + 1, px + plate_w, py + plate_h - 1, wall_dark)
            # Rivets (corners of each plate)
            for rvx, rvy in [(px + 5, py + 5), (px + plate_w - 8, py + 5),
                              (px + 5, py + plate_h - 8), (px + plate_w - 8, py + plate_h - 8)]:
                draw_circle_filled(canvas, rvx, rvy, 3, wall_rivet)
                draw_circle_filled(canvas, rvx, rvy, 2, wall_dark)
                draw_rect(canvas, rvx - 1, rvy - 1, 1, 1, (0.35, 0.28, 0.18))  # highlight

    # Furnace core — massive central glowing chamber
    furnace_cx = W // 2
    furnace_base = H + 30  # extends below screen
    furnace_top_y = H // 3
    furnace_w = 260

    # Furnace arch opening
    arch_col_inner = (0.10, 0.04, 0.02)
    arch_col_glow  = (0.85, 0.35, 0.06)
    arch_col_hot   = (1.00, 0.72, 0.20)
    arch_col_core  = (1.00, 0.92, 0.75)

    # Molten glow radiating from below
    glow_radial(canvas, furnace_cx, H + 10, 0, 320, (0.90, 0.28, 0.06), max_alpha=0.70)
    glow_radial(canvas, furnace_cx, H + 10, 0, 200, (1.00, 0.55, 0.12), max_alpha=0.65)
    glow_radial(canvas, furnace_cx, H + 10, 0, 120, (1.00, 0.80, 0.28), max_alpha=0.55)
    glow_radial(canvas, furnace_cx, H + 10, 0, 60,  arch_col_core, max_alpha=0.50)

    # Furnace opening (tall arch)
    arch_h = H - furnace_top_y
    arch_w = furnace_w
    for y in range(furnace_top_y, H):
        t = (y - furnace_top_y) / max(1, H - furnace_top_y)
        # Arch shape: full rect at base, narrows toward top
        if t < 0.3:
            half_arch = int(arch_w / 2 * math.sqrt(max(0, 1 - ((t / 0.3 - 1) ** 2))))
        else:
            half_arch = arch_w // 2
        x0_a = furnace_cx - half_arch
        x1_a = furnace_cx + half_arch
        # Interior fill (gradient from hot core to dark surround)
        inner_t = 1.0 - t * 0.6
        ic = lerp_color((0.08, 0.04, 0.02), arch_col_glow, inner_t)
        draw_hline(canvas, x0_a, x1_a, y, ic)

    # Furnace frame (massive iron arch)
    arch_frame_col   = (0.28, 0.20, 0.14)
    arch_frame_hi    = (0.42, 0.32, 0.20)
    arch_frame_dark  = (0.14, 0.10, 0.06)
    frame_thick = 20
    for y in range(furnace_top_y - 5, H):
        t = (y - (furnace_top_y - 5)) / max(1, H - furnace_top_y + 5)
        if t < 0.3:
            arch_half = int(arch_w / 2 * math.sqrt(max(0, 1 - ((t / 0.3 - 1) ** 2))))
        else:
            arch_half = arch_w // 2
        x0_f = furnace_cx - arch_half - frame_thick
        x1_f = furnace_cx + arch_half + frame_thick
        x0_i = furnace_cx - arch_half
        x1_i = furnace_cx + arch_half
        if x0_f >= 0:
            draw_hline(canvas, x0_f, x0_i, y, arch_frame_col)
        if x1_i < W:
            draw_hline(canvas, x1_i, x1_f, y, arch_frame_col)
        # Highlights
        draw_hline(canvas, max(0, x0_f), min(W, x0_f + 3), y, arch_frame_hi)
        draw_hline(canvas, max(0, x1_f - 3), min(W, x1_f), y, arch_frame_dark)
    # Riveted frame detail
    for rv_y in range(furnace_top_y, H, 20):
        draw_circle_filled(canvas, furnace_cx - arch_w // 2 - frame_thick + 6, rv_y, 3, wall_rivet)
        draw_circle_filled(canvas, furnace_cx + arch_w // 2 + frame_thick - 6, rv_y, 3, wall_rivet)

    # Molten metal channels on floor (leading from furnace)
    channel_col  = (0.90, 0.45, 0.08)
    channel_hi   = (1.00, 0.75, 0.25)
    channel_edge = (0.30, 0.18, 0.08)
    channel_floor_y = H * 4 // 5
    # Main channel (center)
    draw_rect(canvas, furnace_cx - 15, channel_floor_y, 30, H - channel_floor_y, channel_col)
    draw_vline(canvas, furnace_cx - 15, channel_floor_y, H, channel_edge)
    draw_vline(canvas, furnace_cx + 15, channel_floor_y, H, channel_edge)
    # Channel highlight (top of molten flow)
    draw_vline(canvas, furnace_cx - 13, channel_floor_y, H, channel_hi)
    draw_vline(canvas, furnace_cx - 12, channel_floor_y, H, channel_hi)
    # Glow from channel
    glow_radial(canvas, furnace_cx, H - 10, 0, 100, channel_col, max_alpha=0.35)

    # Side channels (branch left and right)
    for scx, scw in [(furnace_cx - 80, 12), (furnace_cx + 68, 12)]:
        draw_rect(canvas, scx, H - 30, scw, 30, (0.65, 0.30, 0.06))
        draw_vline(canvas, scx, H - 30, H, channel_edge)
        draw_vline(canvas, scx + scw, H - 30, H, channel_edge)
        glow_radial(canvas, scx + scw // 2, H - 15, 0, 40, channel_col, max_alpha=0.25)

    # Iron catwalks (dark platforms, top portion)
    catwalk_col  = (0.18, 0.14, 0.12)
    catwalk_grat = (0.24, 0.20, 0.16)
    catwalk_edge = (0.10, 0.08, 0.06)
    # Left catwalk
    cw_y = H // 3 + 20
    cw_h = 12
    draw_rect(canvas, 0, cw_y, furnace_cx - arch_w // 2 - frame_thick - 5, cw_h, catwalk_col)
    # Grating texture (crosshatch)
    for gx in range(0, furnace_cx - arch_w // 2, 8):
        draw_vline(canvas, gx, cw_y, cw_y + cw_h, catwalk_grat)
    draw_hline(canvas, 0, furnace_cx - arch_w // 2, cw_y, catwalk_edge)
    draw_hline(canvas, 0, furnace_cx - arch_w // 2, cw_y + cw_h, catwalk_edge)
    # Support beams under left catwalk
    for sx in [30, 100]:
        draw_rect(canvas, sx - 3, cw_y + cw_h, 6, H // 3, catwalk_col)

    # Right catwalk
    rw_x = furnace_cx + arch_w // 2 + frame_thick + 5
    draw_rect(canvas, rw_x, cw_y, W - rw_x, cw_h, catwalk_col)
    for gx in range(rw_x, W, 8):
        draw_vline(canvas, gx, cw_y, cw_y + cw_h, catwalk_grat)
    draw_hline(canvas, rw_x, W, cw_y, catwalk_edge)
    draw_hline(canvas, rw_x, W, cw_y + cw_h, catwalk_edge)
    for sx in [rw_x + 40, rw_x + 110]:
        draw_rect(canvas, sx - 3, cw_y + cw_h, 6, H // 3, catwalk_col)

    # Catwalk railings
    rail_col = (0.28, 0.22, 0.16)
    rail_hi  = (0.42, 0.34, 0.22)
    # Left rail
    draw_hline(canvas, 0, furnace_cx - arch_w // 2 - frame_thick - 5, cw_y - 15, rail_col)
    for rp in range(0, furnace_cx - arch_w // 2 - 30, 20):
        draw_vline(canvas, rp, cw_y - 15, cw_y, rail_col)
    # Right rail
    draw_hline(canvas, rw_x, W, cw_y - 15, rail_col)
    for rp in range(rw_x, W, 20):
        draw_vline(canvas, rp, cw_y - 15, cw_y, rail_col)

    # Heat shimmer effect (wavy horizontal distortion bands)
    shimmer_col = (0.95, 0.55, 0.15)
    for sh_y in range(H * 2 // 5, H * 4 // 5, 6):
        shimmer_alpha = 0.04 * (1 - abs(sh_y - H // 2) / (H // 3))
        if shimmer_alpha > 0:
            wave = np.sin(np.arange(W) * 0.15 + sh_y * 0.08) * shimmer_alpha
            canvas[sh_y, :, 0] = np.clip(canvas[sh_y, :, 0] + wave, 0, 1)
            canvas[sh_y, :, 1] = np.clip(canvas[sh_y, :, 1] + wave * 0.4, 0, 1)

    # Embers / floating ash (bright orange particles)
    rng_emb = np.random.default_rng(888)
    for _ in range(30):
        ex = int(rng_emb.integers(furnace_cx - 100, furnace_cx + 100))
        ey = int(rng_emb.integers(furnace_top_y, H * 2 // 3))
        ec = (1.0, float(rng_emb.uniform(0.5, 0.8)), 0.10)
        draw_circle_filled(canvas, ex, ey, int(rng_emb.integers(1, 3)), ec,
                           alpha=float(rng_emb.uniform(0.6, 0.95)))
        glow_radial(canvas, ex, ey, 0, 8, ec, max_alpha=0.20)

    # Overall orange-red ambient fill from below
    glow_radial(canvas, W // 2, H, 0, W, (0.80, 0.22, 0.04), max_alpha=0.20)

    bayer_dither(canvas, scale=0.024)
    quantize_palette(canvas, levels=20)
    fill_alpha(canvas)
    canvas[:, :, :3] *= 0.80   # additional darkening
    return to_image(canvas)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    tasks = [
        ("suburban_neighborhood.png", gen_suburban_neighborhood),
        ("suburban_school.png",        gen_suburban_school),
        ("suburban_park.png",          gen_suburban_park),
        ("steampunk_workshop.png",     gen_steampunk_workshop),
        ("steampunk_airship.png",      gen_steampunk_airship),
        ("industrial_factory.png",     gen_industrial_factory),
        ("industrial_furnace.png",     gen_industrial_furnace),
    ]

    for filename, gen_fn in tasks:
        print(f"Generating {filename}...")
        img = gen_fn()
        out_path = os.path.join(OUT_DIR, filename)
        img.save(out_path, "PNG")
        w, h = img.size
        print(f"  Saved {out_path} ({w}x{h})")

    print(f"\nAll {len(tasks)} backdrops generated.")
    print(f"Output directory: {OUT_DIR}")


if __name__ == "__main__":
    main()
