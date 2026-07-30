#!/usr/bin/env python3
"""
gen_fighter_extended.py — Fighter extended sprite animation generator.

Generates additional animations and weapon variants for the fighter job:

Battle State Sprites (AP system):
  advance.png  (4 frames, 1024x256) — aggressive forward lean with AP energy aura
  defer.png    (4 frames, 1024x256) — defensive step-back with blue shield shimmer

Ability-Specific Animations:
  power_strike.png (6 frames, 1536x256) — heavy overhead sword slam
  cleave.png       (6 frames, 1536x256) — wide horizontal sweep hitting all enemies
  provoke.png      (4 frames, 1024x256) — chest-pound taunt with red provoke aura

Weapon Variants (idle.png + attack.png per weapon, in assets/sprites/weapons/<id>/):
  bronze_sword/  — copper/brown short blade
  iron_sword/    — silver/steel standard blade (regenerated for consistency)
  flame_sword/   — red-orange blade with fire particle effect
  ice_blade/     — blue-white blade with frost crystal effect

Style: 256x256 frames, transparent background, SNES 16-bit pixel art with 2x2 super-pixels.
Character ~65px wide x 90px tall, center-bottom positioned. Black outlines, limited palette.
"""

import math
import sys
from pathlib import Path
from PIL import Image
import numpy as np

# ── Paths ─────────────────────────────────────────────────────────────────────

IDLE_PATH  = Path("/home/struktured/projects/cowardly-irregular-sprite-gen/assets/sprites/jobs/fighter/idle.png")
OUT_DIR    = Path("/home/struktured/projects/cowardly-irregular-sprite-gen/assets/sprites/jobs/fighter")
WEAPONS_DIR = Path("/home/struktured/projects/cowardly-irregular-sprite-gen/assets/sprites/weapons")

FRAME_W = 256
FRAME_H = 256

# ── Exact palette from idle.png ───────────────────────────────────────────────

TRANSPARENT   = (0,   0,   0,   0)
C_OUTLINE     = (36,  34,  52,  255)
C_VDARK       = (34,  28,  26,  255)
C_DBROWN      = (50,  43,  40,  255)
C_CRIMSON     = (115, 23,  45,  255)
C_RUST        = (157, 49,  35,  255)
C_RED2        = (180, 32,  42,  255)
C_ORANGE      = (250, 106, 10,  255)
C_ORANGE2     = (249, 163, 27,  255)
C_PURPLE_D    = (64,  51,  83,  255)
C_PURPLE2     = (54,  61,  77,  255)
C_METAL_DK    = (51,  57,  65,  255)
C_METAL       = (76,  78,  86,  255)
C_METAL_MD    = (93,  98,  110, 255)
C_SILVER      = (125, 129, 144, 255)
C_SILVER2     = (174, 179, 204, 255)
C_STEEL_BLU   = (54,  61,  77,  255)
C_SKIN_D      = (113, 65,  59,  255)
C_SKIN_M      = (187, 117, 71,  255)
C_SKIN_L      = (233, 181, 163, 255)
C_HAIR_D      = (34,  28,  26,  255)
C_HAIR        = (79,  53,  36,  255)
C_LEATHER     = (121, 103, 85,  255)
C_TAN         = (187, 117, 71,  255)

# Steel colors — appear ONLY on sword blade
SWORD_STEEL = {
    (174, 179, 204), (125, 129, 144), (76, 78, 86),
    (93, 98, 110),   (51, 57, 65),    (54, 61, 77),
    (36, 34, 52),
}

# AP aura colors (gold/warm)
C_AURA_CORE   = (255, 240, 80,  180)
C_AURA_MID    = (255, 180, 30,  120)
C_AURA_OUTER  = (255, 130, 10,  60)

# Defensive shield shimmer (cool blue)
C_SHIELD_CORE  = (80,  180, 255, 160)
C_SHIELD_MID   = (40,  120, 220, 100)
C_SHIELD_OUTER = (20,  60,  180, 50)

# Provoke aura (aggressive red)
C_PROVOKE_CORE  = (255, 40,  40,  160)
C_PROVOKE_MID   = (200, 20,  20,  100)
C_PROVOKE_OUTER = (150, 10,  10,  50)

# ── Load idle sprite ──────────────────────────────────────────────────────────

_idle_img = Image.open(IDLE_PATH).convert("RGBA")
_idle_np  = np.array(_idle_img, dtype=np.uint8)
IDLE_F1   = _idle_np[:, :FRAME_W, :].copy()
IDLE_F2   = _idle_np[:, FRAME_W:FRAME_W*2, :].copy()

# ── Sword positions (from gen_fighter_all_animations.py analysis) ─────────────

IDLE_SWORD_ANGLE = 218   # blade extends lower-left (SW direction)
IDLE_HILT_X      = 136
IDLE_HILT_Y      = 90

BODY_CX  = 103
HIP_Y    = 136
SHADOW_Y = 160

# ── Pixel drawing helpers ─────────────────────────────────────────────────────

def pp(arr, x, y, color):
    """Place one 2x2 super-pixel. Clips at [0,256)."""
    if color[3] == 0:
        return
    for dy in range(2):
        for dx in range(2):
            px, py = x + dx, y + dy
            if 0 <= px < FRAME_W and 0 <= py < FRAME_H:
                arr[py, px] = color


def p1(arr, x, y, color):
    """Place one 1x1 pixel. Clips at [0,256)."""
    if color[3] == 0:
        return
    if 0 <= x < FRAME_W and 0 <= y < FRAME_H:
        arr[y, x] = color


def pp_blend(arr, x, y, color):
    """Blend a 2x2 super-pixel over existing pixels (for aura/effects)."""
    if color[3] == 0:
        return
    na = color[3] / 255.0
    for dy in range(2):
        for dx in range(2):
            px, py = x + dx, y + dy
            if 0 <= px < FRAME_W and 0 <= py < FRAME_H:
                bg = arr[py, px]
                ba = bg[3] / 255.0
                out_a = na + ba * (1 - na)
                if out_a < 0.001:
                    continue
                nr = int((color[0] * na + bg[0] * ba * (1 - na)) / out_a)
                ng = int((color[1] * na + bg[1] * ba * (1 - na)) / out_a)
                nb = int((color[2] * na + bg[2] * ba * (1 - na)) / out_a)
                arr[py, px] = (nr, ng, nb, int(out_a * 255))


def shadow_row(arr, cx, y, half_w, alpha=72):
    """Draw a ground shadow ellipse at row y."""
    for sx in range(-half_w, half_w + 1, 2):
        fade = 1.0 - (abs(sx) / half_w) ** 1.3
        a = int(alpha * max(0, fade))
        for off in range(0, 4, 2):
            nx, ny = cx + sx, y + off
            if 0 <= nx < FRAME_W and 0 <= ny < FRAME_H:
                if arr[ny, nx, 3] < 10:
                    arr[ny, nx] = (36, 34, 52, a)


def extract_pixels(arr, y0, y1, x0=0, x1=255):
    """Return list of (x, y, rgba_tuple) for all opaque pixels in region."""
    result = []
    for row in range(y0, min(y1 + 1, FRAME_H)):
        for col in range(x0, min(x1 + 1, FRAME_W)):
            px = tuple(arr[row, col])
            if px[3] > 10:
                result.append((col, row, px))
    return result


def blit_pixels(arr, pixels, dx=0, dy=0, darken=1.0):
    """Draw pixel list with offset and optional darkening."""
    for x, y, col in pixels:
        nx, ny = x + dx, y + dy
        if 0 <= nx < FRAME_W and 0 <= ny < FRAME_H:
            if darken < 1.0:
                r = min(255, int(col[0] * darken))
                g = min(255, int(col[1] * darken))
                b = min(255, int(col[2] * darken))
                arr[ny, nx] = (r, g, b, col[3])
            else:
                arr[ny, nx] = col


def normalize_pixels(pixels):
    """Return pixels with x,y normalized to (0,0) origin."""
    if not pixels:
        return [], 0, 0
    min_x = min(p[0] for p in pixels)
    min_y = min(p[1] for p in pixels)
    normed = [(x - min_x, y - min_y, c) for x, y, c in pixels]
    return normed, min_x, min_y


# ── Sword erase helper ────────────────────────────────────────────────────────

def _erase_sword(arr):
    """Remove the diagonal idle sword blade (steel-colored pixels)."""
    for y in range(FRAME_H):
        for x in range(FRAME_W):
            r, g, b, a = arr[y, x]
            if a > 10 and (r, g, b) in SWORD_STEEL:
                arr[y, x] = TRANSPARENT

    for y in range(130, 170):
        for x in range(50, 160):
            if arr[y, x, 3] > 10 and tuple(arr[y, x, :3]) == (64, 51, 83):
                arr[y, x] = TRANSPARENT

    for y in range(126, 166):
        non_trans = [x for x in range(50, 160) if arr[y, x, 3] > 10]
        if len(non_trans) < 2:
            continue
        best_gap, left_end = 0, 0
        for i in range(len(non_trans) - 1):
            g = non_trans[i + 1] - non_trans[i]
            if g > best_gap:
                best_gap = g
                left_end = non_trans[i]
        if best_gap >= 4 and left_end < 95:
            for x in range(50, left_end + 2):
                if arr[y, x, 3] > 10:
                    arr[y, x] = TRANSPARENT

    for y in range(140, 168):
        for x in range(50, 76):
            if arr[y, x, 3] > 10:
                neighbors = sum(
                    1 for ddx, ddy in [(-2, 0), (2, 0), (0, -2), (0, 2)]
                    if 0 <= x + ddx < FRAME_W and 0 <= y + ddy < FRAME_H
                    and arr[y + ddy, x + ddx, 3] > 10
                )
                if neighbors <= 1:
                    arr[y, x] = TRANSPARENT


_base_nosword = IDLE_F1.copy()
_erase_sword(_base_nosword)


def fresh_frame():
    """Return a copy of idle frame 1 with sword erased."""
    return _base_nosword.copy()


# ── Sword shape renderer ──────────────────────────────────────────────────────

def sword_at_angle(arr, hilt_x, hilt_y, angle_deg, blade_len=52,
                   blade_colors=None, serrated=True):
    """
    Draw a serrated broadsword with hilt at (hilt_x, hilt_y).
    angle_deg: 0=right, 90=up, standard math angles (screen y flipped internally).
    blade_colors: dict with keys 'dark', 'mid', 'light', 'outline' for weapon variants.
    """
    if blade_colors is None:
        blade_colors = {
            'outline': C_OUTLINE,
            'dark':    C_METAL,
            'mid':     C_SILVER2,
            'light':   C_SILVER,
            'edge':    C_METAL_MD,
        }

    rad = math.radians(angle_deg)
    bx = math.cos(rad)
    by = -math.sin(rad)  # flip y for screen coords

    # Perpendicular for width
    px_ = -by
    py_ = bx

    steps = blade_len // 2
    for i in range(steps):
        t = i / max(steps - 1, 1)
        if t < 0.15:
            width = 3
        elif t < 0.85:
            width = 2
        else:
            width = 1

        cx = int(hilt_x + bx * i * 2) & ~1
        cy = int(hilt_y + by * i * 2) & ~1

        # Outline
        ox = int(px_ * (width + 1)) & ~1
        oy = int(py_ * (width + 1)) & ~1
        pp(arr, cx + ox, cy + oy, blade_colors['outline'])
        pp(arr, cx - ox, cy - oy, blade_colors['outline'])

        # Blade colors: dark/mid/light
        for w in range(-width + 1, width):
            bpx = int(cx + px_ * w) & ~1
            bpy = int(cy + py_ * w) & ~1
            if abs(w) == width - 1:
                c = blade_colors['dark']
            elif w == 0:
                c = blade_colors['mid']
            elif w > 0:
                c = blade_colors['light']
            else:
                c = blade_colors['edge']
            pp(arr, bpx, bpy, c)

        # Serrations on one edge (every 5 steps)
        if serrated and i % 5 == 2 and 2 < i < steps - 2:
            sx = int(cx + px_ * (width + 1)) & ~1
            sy = int(cy + py_ * (width + 1)) & ~1
            pp(arr, sx, sy, blade_colors['dark'])

    # Crossguard
    gx = hilt_x
    gy = hilt_y
    for k in range(-7, 8, 2):
        kx = int(gx + px_ * k) & ~1
        ky = int(gy + py_ * k) & ~1
        c = blade_colors['mid'] if abs(k) <= 2 else (
            blade_colors['light'] if abs(k) <= 4 else blade_colors['dark'])
        pp(arr, kx, ky, c)
    pp(arr, int(gx + px_ * -8) & ~1, int(gy + py_ * -8) & ~1, C_OUTLINE)
    pp(arr, int(gx + px_ * 8) & ~1,  int(gy + py_ * 8) & ~1,  C_OUTLINE)

    # Handle
    for i in range(1, 6):
        hpx = int(hilt_x - bx * i * 2) & ~1
        hpy = int(hilt_y - by * i * 2) & ~1
        c = C_LEATHER if i % 2 == 0 else C_DBROWN
        pp(arr, hpx - 2, hpy, c)
        pp(arr, hpx,     hpy, c)

    # Pommel
    ppx = int(hilt_x - bx * 12) & ~1
    ppy = int(hilt_y - by * 12) & ~1
    pp(arr, ppx - 2, ppy,     C_METAL)
    pp(arr, ppx,     ppy,     C_METAL)
    pp(arr, ppx - 2, ppy + 2, C_OUTLINE)
    pp(arr, ppx,     ppy + 2, C_OUTLINE)


# ── Body shift helper ─────────────────────────────────────────────────────────

def shift_upper_body(arr, body_dx, body_dy):
    """Shift upper body (rows 66-135) by (body_dx, body_dy) in-place."""
    if body_dx == 0 and body_dy == 0:
        return arr
    shifted = np.zeros_like(arr)
    src_y0 = max(66, 66 - body_dy)
    src_y1 = min(136, 136 - body_dy)
    dst_y0 = max(66, 66 + body_dy)
    dst_y1 = min(136, 136 + body_dy)
    src_x0 = max(0, -body_dx)
    dst_x0 = max(0, body_dx)
    copy_h = min(src_y1 - src_y0, dst_y1 - dst_y0, 70)
    copy_w = min(FRAME_W - abs(body_dx), FRAME_W)
    shifted[136:] = arr[136:]
    if copy_h > 0 and copy_w > 0:
        shifted[dst_y0:dst_y0+copy_h, dst_x0:dst_x0+copy_w] = \
            arr[src_y0:src_y0+copy_h, src_x0:src_x0+copy_w]
    return shifted


def shift_full_body(arr, body_dx, body_dy):
    """Shift entire character (upper + lower) for hit/recoil effects."""
    if body_dx == 0 and body_dy == 0:
        return arr
    shifted = np.zeros_like(arr)
    src_x0 = max(0, -body_dx)
    dst_x0 = max(0, body_dx)
    copy_w = min(FRAME_W - abs(body_dx), FRAME_W)
    src_y0 = max(0, -body_dy)
    dst_y0 = max(0, body_dy)
    copy_h = min(FRAME_H - abs(body_dy), FRAME_H)
    if copy_h > 0 and copy_w > 0:
        shifted[dst_y0:dst_y0+copy_h, dst_x0:dst_x0+copy_w] = \
            arr[src_y0:src_y0+copy_h, src_x0:src_x0+copy_w]
    return shifted


# ── Aura drawing helpers ──────────────────────────────────────────────────────

def draw_aura(arr, cx, cy, radius, core_color, mid_color, outer_color,
              intensity=1.0, shape='circle', offset_x=0, offset_y=0):
    """
    Draw a glowing aura around a point.
    shape: 'circle' or 'oval' (taller than wide)
    intensity: 0.0-1.0 multiplier for alpha
    """
    for dy in range(-radius, radius + 1, 2):
        for dx in range(-radius, radius + 1, 2):
            if shape == 'oval':
                dist = math.hypot(dx * 0.7, dy)
            else:
                dist = math.hypot(dx, dy)
            if dist > radius:
                continue
            t = dist / radius
            if t < 0.25:
                c = list(core_color)
            elif t < 0.55:
                c = list(mid_color)
            else:
                c = list(outer_color)
            c[3] = int(c[3] * intensity)
            px = (cx + dx + offset_x) & ~1
            py = (cy + dy + offset_y) & ~1
            if 0 <= px < FRAME_W - 1 and 0 <= py < FRAME_H - 1:
                pp_blend(arr, px, py, tuple(c))


def draw_sword_aura(arr, hilt_x, hilt_y, angle_deg, blade_len, aura_color, intensity=1.0):
    """Draw a glow trail along the sword blade."""
    rad = math.radians(angle_deg)
    bx = math.cos(rad)
    by = -math.sin(rad)
    steps = blade_len // 2
    for i in range(steps):
        t = i / max(steps - 1, 1)
        cx = int(hilt_x + bx * i * 2) & ~1
        cy = int(hilt_y + by * i * 2) & ~1
        # Wider glow at base, tighter at tip
        glow_r = int(6 * (1 - t * 0.5))
        c = list(aura_color)
        c[3] = int(c[3] * intensity * (1 - t * 0.3))
        draw_aura(arr, cx, cy, glow_r, tuple(c), tuple(c), tuple(c), intensity=0.6)


def draw_slash_arc(arr, center_x, center_y, start_angle, end_angle,
                   radius, color, width=3):
    """
    Draw a visible slash arc as a curved line (for cleave trail).
    Angles in degrees (screen convention: 0=right, CW positive).
    """
    steps = int(abs(end_angle - start_angle) * 2)
    steps = max(steps, 20)
    for i in range(steps):
        t = i / max(steps - 1, 1)
        a = math.radians(start_angle + (end_angle - start_angle) * t)
        fade = 1.0 - abs(t - 0.5) * 1.2
        fade = max(0.1, fade)
        for r_off in range(-width, width + 1, 2):
            r = radius + r_off
            px = int(center_x + r * math.cos(a)) & ~1
            py = int(center_y + r * math.sin(a)) & ~1
            c = list(color)
            c[3] = int(c[3] * fade)
            if c[3] > 10:
                pp_blend(arr, px, py, tuple(c))


def draw_particles(arr, cx, cy, count, color_list, radius, rng_seed=0,
                   particle_size=2, fade=True):
    """Draw scattered particle dots in a radius around a center point."""
    import random
    rng = random.Random(rng_seed)
    for _ in range(count):
        angle = rng.uniform(0, 2 * math.pi)
        dist = rng.uniform(radius * 0.2, radius)
        px = int(cx + dist * math.cos(angle)) & ~1
        py = int(cy + dist * math.sin(angle)) & ~1
        c = rng.choice(color_list)
        alpha = int(c[3] * (1 - dist / (radius + 1))) if fade else c[3]
        c_mod = (c[0], c[1], c[2], max(30, alpha))
        if particle_size == 2:
            pp_blend(arr, px, py, c_mod)
        else:
            p1(arr, px, py, c_mod)


# ══════════════════════════════════════════════════════════════════════════════
# ADVANCE ANIMATION (4 frames, 1024x256)
# ══════════════════════════════════════════════════════════════════════════════
#
# Fighter leans aggressively forward, sword raised high, AP energy aura building.
# F0: slight forward lean, sword starts rising — first stirrings of aura
# F1: deeper lean, sword at shoulder height — aura glow beginning around blade
# F2: full forward stance, sword raised high — bright aura surrounds character
# F3: sword overhead at peak — maximum glow, aura radiates from whole body

_advance_frames = [
    # (body_dx, body_dy, hilt_x, hilt_y, sword_angle, blade_len, aura_intensity)
    (-1,  -1, 134,  88, 160, 50, 0.20),   # F0: slight lean, subtle first aura
    (-2,  -2, 130,  82, 120, 52, 0.45),   # F1: deeper lean, aura building
    (-4,  -2, 126,  78,  90, 54, 0.70),   # F2: full forward stance, bright aura
    (-5,  -3, 124,  72,  70, 56, 1.00),   # F3: sword overhead, max aura
]


def _gen_advance_frame(fdata):
    body_dx, body_dy, hilt_x, hilt_y, sword_angle, blade_len, aura_int = fdata

    arr = IDLE_F1.copy()
    arr = shift_upper_body(arr, body_dx, body_dy)

    # Erase idle sword (crude pass for speed)
    _erase_sword(arr)

    shadow_row(arr, BODY_CX + body_dx // 2, SHADOW_Y, 22)

    # Draw body aura (gold/warm energy field) around character center
    char_cx = BODY_CX + body_dx
    char_cy = 115 + body_dy  # approximate torso center

    if aura_int > 0.1:
        draw_aura(arr, char_cx, char_cy, 36,
                  C_AURA_CORE, C_AURA_MID, C_AURA_OUTER,
                  intensity=aura_int * 0.5, shape='oval')

    # Draw the sword
    sword_at_angle(arr, hilt_x + body_dx, hilt_y + body_dy, sword_angle, blade_len)

    # Draw sword energy aura (glow trail along blade)
    if aura_int > 0.2:
        draw_sword_aura(arr, hilt_x + body_dx, hilt_y + body_dy,
                        sword_angle, blade_len,
                        C_AURA_MID, intensity=aura_int * 0.8)

    # Gold particle sparks scattered around at higher intensities
    if aura_int >= 0.45:
        spark_colors = [C_AURA_CORE, C_AURA_MID, C_ORANGE2]
        draw_particles(arr, char_cx, char_cy - 10,
                       count=int(12 * aura_int),
                       color_list=spark_colors,
                       radius=30, rng_seed=int(aura_int * 100),
                       particle_size=2, fade=True)

    return Image.fromarray(arr, 'RGBA')


def generate_advance():
    frames = [_gen_advance_frame(fd) for fd in _advance_frames]
    strip = Image.new("RGBA", (FRAME_W * 4, FRAME_H), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * FRAME_W, 0))
    return strip


# ══════════════════════════════════════════════════════════════════════════════
# DEFER ANIMATION (4 frames, 1024x256)
# ══════════════════════════════════════════════════════════════════════════════
#
# Fighter steps back into defensive crouch, shield arm raised.
# F0: slight step back, weight shifting
# F1: shield arm raising, body starting to crouch
# F2: full defensive crouch, shield arm up, blue shimmer beginning
# F3: settled defensive stance, full shimmer around shield side

_defer_frames = [
    # (body_dx, body_dy, hilt_x, hilt_y, sword_angle, blade_len, shimmer_int)
    (2,  1, 136,  90, 210, 50, 0.15),  # F0: slight step back
    (4,  2, 136,  92, 215, 50, 0.35),  # F1: shield raising
    (6,  3, 136,  94, 220, 48, 0.65),  # F2: full defensive crouch
    (6,  3, 136,  94, 218, 48, 0.85),  # F3: settled, full shimmer
]


def _gen_defer_frame(fdata):
    body_dx, body_dy, hilt_x, hilt_y, sword_angle, blade_len, shimmer_int = fdata

    arr = IDLE_F1.copy()
    arr = shift_full_body(arr, body_dx, body_dy)

    # Erase idle sword
    _erase_sword(arr)

    shadow_row(arr, BODY_CX + body_dx // 2, SHADOW_Y + body_dy // 2, 20)

    # Draw defensive shield-side shimmer (left side of character = shield arm side)
    shield_cx = BODY_CX + body_dx - 8   # slightly left (shield arm side)
    shield_cy = 105 + body_dy

    if shimmer_int > 0.1:
        draw_aura(arr, shield_cx, shield_cy, 28,
                  C_SHIELD_CORE, C_SHIELD_MID, C_SHIELD_OUTER,
                  intensity=shimmer_int * 0.6, shape='oval')

    # Cool particles (frost-blue) on shield side
    if shimmer_int >= 0.35:
        shield_colors = [C_SHIELD_CORE, C_SHIELD_MID, (160, 220, 255, 140)]
        draw_particles(arr, shield_cx, shield_cy,
                       count=int(8 * shimmer_int),
                       color_list=shield_colors,
                       radius=22, rng_seed=int(shimmer_int * 200),
                       particle_size=2, fade=True)

    # Draw the sword (stays near idle angle — not raised in defensive stance)
    sword_at_angle(arr, hilt_x + body_dx, hilt_y + body_dy, sword_angle, blade_len)

    return Image.fromarray(arr, 'RGBA')


def generate_defer():
    frames = [_gen_defer_frame(fd) for fd in _defer_frames]
    strip = Image.new("RGBA", (FRAME_W * 4, FRAME_H), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * FRAME_W, 0))
    return strip


# ══════════════════════════════════════════════════════════════════════════════
# POWER STRIKE ANIMATION (6 frames, 1536x256)
# ══════════════════════════════════════════════════════════════════════════════
#
# Heavy overhead sword slam — more dramatic than basic attack.
# F0: wind-up start, body straightens, sword begins rising
# F1: sword raised high behind head (120°), body leaning back hard
# F2: sword at absolute peak (80°), arm fully extended upward
# F3: massive downward slam begins (-10°), body lurches forward hard
# F4: impact flash — sword hits down (-50°), body at max forward
# F5: recovery — sword following through low (180°), body returning

_power_strike_frames = [
    # (body_dx, body_dy, hilt_x, hilt_y, sword_angle, blade_len, impact_flash)
    (0,  -2, 134,  86, 155, 50, False),  # F0: wind-up start
    (-3, -4, 128,  78, 115, 54, False),  # F1: sword raised behind head
    (-4, -5, 124,  72,  80, 58, False),  # F2: absolute peak, arm fully extended
    (4,  -1, 134,  88,  -5, 56, False),  # F3: slam begins, huge forward lunge
    (6,   2, 138,  96, -50, 54, True),   # F4: impact at bottom — flash
    (2,   0, 136,  90, 185, 50, False),  # F5: follow-through recovery
]


def _gen_power_strike_frame(fdata):
    body_dx, body_dy, hilt_x, hilt_y, sword_angle, blade_len, impact_flash = fdata

    arr = IDLE_F1.copy()
    arr = shift_upper_body(arr, body_dx, body_dy)
    _erase_sword(arr)

    shadow_row(arr, BODY_CX + body_dx // 2, SHADOW_Y, 22)

    # Impact flash: bright white/yellow flash radiating from sword tip on impact frame
    if impact_flash:
        # Sword tip position
        rad = math.radians(sword_angle)
        tip_x = int(hilt_x + body_dx + math.cos(rad) * blade_len)
        tip_y = int(hilt_y + body_dy - math.sin(rad) * blade_len)
        draw_aura(arr, tip_x, tip_y, 20,
                  (255, 255, 220, 200), (255, 220, 100, 140), (255, 180, 60, 80),
                  intensity=1.0)
        # Impact sparks
        spark_colors = [(255, 255, 220, 180), (255, 200, 80, 150), C_ORANGE2]
        draw_particles(arr, tip_x, tip_y, count=16,
                       color_list=spark_colors,
                       radius=26, rng_seed=42, particle_size=2, fade=True)

    sword_at_angle(arr, hilt_x + body_dx, hilt_y + body_dy, sword_angle, blade_len)

    return Image.fromarray(arr, 'RGBA')


def generate_power_strike():
    frames = [_gen_power_strike_frame(fd) for fd in _power_strike_frames]
    strip = Image.new("RGBA", (FRAME_W * 6, FRAME_H), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * FRAME_W, 0))
    return strip


# ══════════════════════════════════════════════════════════════════════════════
# CLEAVE ANIMATION (6 frames, 1536x256)
# ══════════════════════════════════════════════════════════════════════════════
#
# Wide horizontal sweep hitting all enemies. Sword trail arc visible mid-swing.
# F0-F1: wind-up (sword pulled to left/back)
# F2-F3: wide horizontal slash with trail arc visible
# F4-F5: follow-through and recovery

# For cleave, body pivots more (torso rotation implied by shoulder position)
_cleave_frames = [
    # (body_dx, body_dy, hilt_x, hilt_y, sword_angle, blade_len, show_trail, trail_start_angle)
    (-2,  -1, 132,  84, 170, 50, False, 0),    # F0: wind-up start
    (-4,  -1, 126,  82, 220, 52, False, 0),    # F1: sword pulled left-back
    (-2,   0, 130,  84, 180, 54, True,  220),  # F2: sweep begins — trail starts
    (2,    0, 134,  86,  30, 54, True,  180),  # F3: mid-sweep, full trail arc
    (5,    0, 138,  88, -20, 52, True,   30),  # F4: right side follow-through
    (3,    0, 136,  90, 215, 50, False, 0),    # F5: recovery near idle
]

# Trail arc color (sword motion trail)
C_TRAIL     = (200, 220, 255, 90)
C_TRAIL_MID = (180, 200, 240, 60)


def _gen_cleave_frame(fdata):
    body_dx, body_dy, hilt_x, hilt_y, sword_angle, blade_len, \
        show_trail, trail_start = fdata

    arr = IDLE_F1.copy()
    arr = shift_upper_body(arr, body_dx, body_dy)
    _erase_sword(arr)

    shadow_row(arr, BODY_CX + body_dx // 2, SHADOW_Y, 24)

    # Draw sword trail arc (arc swept from trail_start to current sword_angle)
    if show_trail:
        # Arc center roughly at body torso
        arc_cx = BODY_CX + body_dx
        arc_cy = 110 + body_dy
        arc_radius = blade_len + 12

        # Normalize angles so start < end and we always go clockwise
        # In screen space, screen-angle = -math_angle for y-flip
        sa = -(trail_start)   # convert to screen angle (clockwise)
        ea = -(sword_angle)
        if ea < sa:
            ea += 360
        # Only draw if arc spans at least 20 degrees
        if ea - sa > 15:
            draw_slash_arc(arr, arc_cx, arc_cy, sa, ea,
                           arc_radius, C_TRAIL, width=5)
            draw_slash_arc(arr, arc_cx, arc_cy, sa, ea,
                           arc_radius - 6, C_TRAIL_MID, width=3)

    sword_at_angle(arr, hilt_x + body_dx, hilt_y + body_dy, sword_angle, blade_len)

    return Image.fromarray(arr, 'RGBA')


def generate_cleave():
    frames = [_gen_cleave_frame(fd) for fd in _cleave_frames]
    strip = Image.new("RGBA", (FRAME_W * 6, FRAME_H), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * FRAME_W, 0))
    return strip


# ══════════════════════════════════════════════════════════════════════════════
# PROVOKE ANIMATION (4 frames, 1024x256)
# ══════════════════════════════════════════════════════════════════════════════
#
# Fighter pounds chest and taunts enemies with a red provoke aura.
# F0: straighten up tall, head raised, chest out — sword lowered slightly
# F1: fist drawn back to chest, body leaning forward slightly
# F2: roar/taunt — body forward, fist pounding chest, red provoke aura erupts
# F3: settle into aggressive stance — aura dims to steady pulse

_provoke_frames = [
    # (body_dx, body_dy, hilt_x, hilt_y, sword_angle, blade_len, aura_int, pounding)
    (0,  -3, 136,  88, 220, 50, 0.10, False),  # F0: stand tall
    (-1, -2, 134,  86, 215, 50, 0.30, True),   # F1: fist to chest
    (-2,  0, 132,  86, 210, 50, 1.00, True),   # F2: roar with full aura
    (-1, -1, 134,  88, 218, 52, 0.50, False),  # F3: aggressive rest stance
]


def _draw_chest_pound(arr, body_dx, body_dy, intensity):
    """
    Draw a clenched fist hitting the chest area.
    The idle fighter has arm detail on the right side ~x=110-130, y=100-120.
    We add a simple fist shape punching inward.
    """
    # Fist center (approximately right arm hitting chest)
    fist_cx = 110 + body_dx
    fist_cy = 112 + body_dy

    # Fist: small box of skin pixels with outline
    skin_colors = [C_SKIN_M, C_SKIN_L, C_SKIN_D]
    for dy in range(-4, 6, 2):
        for dx in range(-4, 6, 2):
            # Rounded corners
            if abs(dx) + abs(dy) > 8:
                continue
            px = (fist_cx + dx) & ~1
            py = (fist_cy + dy) & ~1
            if 0 <= px < FRAME_W and 0 <= py < FRAME_H:
                dist = math.hypot(dx, dy)
                if dist <= 2:
                    c = C_SKIN_L
                elif dist <= 5:
                    c = C_SKIN_M
                else:
                    c = C_OUTLINE
                arr[py, px] = c
                if px + 1 < FRAME_W:
                    arr[py, px + 1] = c
                if py + 1 < FRAME_H:
                    arr[py + 1, px] = c
                if px + 1 < FRAME_W and py + 1 < FRAME_H:
                    arr[py + 1, px + 1] = c

    # Impact stars/lines radiating from fist point of contact
    if intensity >= 0.5:
        for star_angle in range(0, 360, 45):
            rad = math.radians(star_angle)
            for dist in range(6, int(14 * intensity), 2):
                sx = int(fist_cx + math.cos(rad) * dist) & ~1
                sy = int(fist_cy + math.sin(rad) * dist) & ~1
                if dist < 8:
                    c = (255, 220, 80, int(180 * intensity))
                else:
                    c = (200, 80, 30, int(100 * intensity))
                pp_blend(arr, sx, sy, c)


def _gen_provoke_frame(fdata):
    body_dx, body_dy, hilt_x, hilt_y, sword_angle, blade_len, aura_int, pounding = fdata

    arr = IDLE_F1.copy()
    arr = shift_upper_body(arr, body_dx, body_dy)
    _erase_sword(arr)

    shadow_row(arr, BODY_CX + body_dx // 2, SHADOW_Y, 22)

    # Red provoke aura radiating from chest/torso
    char_cx = BODY_CX + body_dx
    char_cy = 108 + body_dy

    if aura_int > 0.05:
        draw_aura(arr, char_cx, char_cy, 40,
                  C_PROVOKE_CORE, C_PROVOKE_MID, C_PROVOKE_OUTER,
                  intensity=aura_int * 0.55, shape='circle')

    # Menace particles shooting outward at high intensity
    if aura_int >= 0.5:
        menace_colors = [C_PROVOKE_CORE, C_PROVOKE_MID, (255, 80, 80, 120)]
        draw_particles(arr, char_cx, char_cy - 5,
                       count=int(14 * aura_int),
                       color_list=menace_colors,
                       radius=38, rng_seed=int(aura_int * 50),
                       particle_size=2, fade=True)

    # Chest pound fist visual
    if pounding:
        _draw_chest_pound(arr, body_dx, body_dy, aura_int)

    # Sword lowered/at-side during provoke
    sword_at_angle(arr, hilt_x + body_dx, hilt_y + body_dy, sword_angle, blade_len)

    return Image.fromarray(arr, 'RGBA')


def generate_provoke():
    frames = [_gen_provoke_frame(fd) for fd in _provoke_frames]
    strip = Image.new("RGBA", (FRAME_W * 4, FRAME_H), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * FRAME_W, 0))
    return strip


# ══════════════════════════════════════════════════════════════════════════════
# WEAPON VARIANT SYSTEM
# ══════════════════════════════════════════════════════════════════════════════

# Standard attack frame data for weapon variants (matches existing attack.png poses)
_WEAPON_IDLE_ANGLE  = IDLE_SWORD_ANGLE   # 218°
_WEAPON_IDLE_HX     = IDLE_HILT_X        # 136
_WEAPON_IDLE_HY     = IDLE_HILT_Y        # 90

_WEAPON_ATTACK_FRAME = (4, 0, 138, 88, 15, 54)  # F3 from attack: peak slash pose

WEAPON_BLADE_COLORS = {
    'bronze_sword': {
        'outline': (89,  55,  20,  255),   # dark brown outline
        'dark':    (128, 89,  51,  255),   # dark copper
        'mid':     (191, 140, 89,  255),   # mid copper
        'light':   (230, 179, 128, 255),   # bright copper highlight
        'edge':    (160, 110, 65,  255),   # edge copper
    },
    'iron_sword': {
        'outline': C_OUTLINE,
        'dark':    C_METAL,
        'mid':     C_SILVER2,
        'light':   C_SILVER,
        'edge':    C_METAL_MD,
    },
    'flame_sword': {
        'outline': (100, 20,  0,   255),   # deep dark red outline
        'dark':    (153, 51,  26,  255),   # deep ember red
        'mid':     (230, 102, 51,  255),   # mid flame orange
        'light':   (255, 204, 102, 255),   # bright fire yellow
        'edge':    (200, 75,  30,  255),   # orange-red edge
    },
    'ice_blade': {
        'outline': (30,  60,  100, 255),   # deep ice-blue outline
        'dark':    (77,  128, 179, 255),   # dark ice blue
        'mid':     (128, 204, 255, 255),   # mid frost blue
        'light':   (204, 242, 255, 255),   # bright ice highlight
        'edge':    (100, 170, 220, 255),   # ice edge blue
    },
}

# Blade lengths per weapon (bronze is shorter)
WEAPON_BLADE_LEN = {
    'bronze_sword': 42,
    'iron_sword':   52,
    'flame_sword':  54,
    'ice_blade':    54,
}


def _gen_weapon_idle_frame(weapon_id):
    """Generate a weapon idle frame using the weapon's blade colors."""
    colors = WEAPON_BLADE_COLORS[weapon_id]
    blade_len = WEAPON_BLADE_LEN[weapon_id]

    arr = IDLE_F1.copy()
    _erase_sword(arr)
    shadow_row(arr, BODY_CX, SHADOW_Y, 22)
    sword_at_angle(arr, _WEAPON_IDLE_HX, _WEAPON_IDLE_HY,
                   _WEAPON_IDLE_ANGLE, blade_len, blade_colors=colors)

    # Elemental passive effects on idle blade
    _add_weapon_effect(arr, _WEAPON_IDLE_HX, _WEAPON_IDLE_HY,
                       _WEAPON_IDLE_ANGLE, blade_len, weapon_id, intensity=0.6)

    return Image.fromarray(arr, 'RGBA')


def _gen_weapon_attack_frame(weapon_id):
    """Generate weapon attack frame (using F3 peak slash pose)."""
    body_dx, body_dy, hilt_x, hilt_y, sword_angle, blade_len_base = _WEAPON_ATTACK_FRAME
    colors = WEAPON_BLADE_COLORS[weapon_id]
    blade_len = WEAPON_BLADE_LEN[weapon_id]

    arr = IDLE_F1.copy()
    arr = shift_upper_body(arr, body_dx, body_dy)
    _erase_sword(arr)
    shadow_row(arr, BODY_CX + body_dx // 2, SHADOW_Y, 22)
    sword_at_angle(arr, hilt_x + body_dx, hilt_y + body_dy,
                   sword_angle, blade_len, blade_colors=colors)

    # Elemental effects on attack blade (more intense on attack)
    _add_weapon_effect(arr, hilt_x + body_dx, hilt_y + body_dy,
                       sword_angle, blade_len, weapon_id, intensity=1.0)

    return Image.fromarray(arr, 'RGBA')


def _add_weapon_effect(arr, hilt_x, hilt_y, angle, blade_len, weapon_id, intensity=0.8):
    """Add elemental particle/glow effects to a weapon blade."""
    if weapon_id == 'bronze_sword':
        return  # Bronze: plain metal, no effects

    elif weapon_id == 'iron_sword':
        return  # Iron: plain steel, no effects

    elif weapon_id == 'flame_sword':
        # Fire particles along blade
        flame_colors = [
            (255, 100, 20,  160),
            (255, 200, 50,  120),
            (220, 60,  10,  100),
        ]
        # Glow aura along blade
        draw_sword_aura(arr, hilt_x, hilt_y, angle, blade_len,
                        (230, 102, 51, 100), intensity=intensity * 0.7)

        # Fire particles on upper half of blade (where the flame concentrates)
        rad = math.radians(angle)
        bx = math.cos(rad)
        by = -math.sin(rad)
        for i in range(0, blade_len // 2, 4):
            t = i / (blade_len // 2)
            cx = int(hilt_x + bx * i * 2) & ~1
            cy = int(hilt_y + by * i * 2) & ~1
            draw_particles(arr, cx, cy, count=3,
                           color_list=flame_colors,
                           radius=8, rng_seed=i * 3 + 7,
                           particle_size=2, fade=True)

    elif weapon_id == 'ice_blade':
        # Frost crystal particles along blade
        frost_colors = [
            (128, 204, 255, 150),
            (204, 242, 255, 120),
            (77,  128, 179, 100),
        ]
        # Cool blue glow
        draw_sword_aura(arr, hilt_x, hilt_y, angle, blade_len,
                        (100, 170, 255, 90), intensity=intensity * 0.7)

        # Crystal particles scattered around blade
        rad = math.radians(angle)
        bx = math.cos(rad)
        by = -math.sin(rad)
        for i in range(0, blade_len // 2, 6):
            cx = int(hilt_x + bx * i * 2) & ~1
            cy = int(hilt_y + by * i * 2) & ~1
            draw_particles(arr, cx, cy, count=2,
                           color_list=frost_colors,
                           radius=10, rng_seed=i * 5 + 11,
                           particle_size=2, fade=True)

        # Cold mist at blade tip
        rad = math.radians(angle)
        tip_x = int(hilt_x + math.cos(rad) * blade_len) & ~1
        tip_y = int(hilt_y - math.sin(rad) * blade_len) & ~1
        draw_aura(arr, tip_x, tip_y, 10,
                  (180, 230, 255, 100), (100, 180, 255, 60), (60, 130, 200, 30),
                  intensity=intensity * 0.5)


def generate_weapon_variant(weapon_id, out_dir):
    """Generate idle.png and attack.png for a weapon variant."""
    out_dir.mkdir(parents=True, exist_ok=True)

    # Idle: 2-frame strip (like standard idle)
    f0 = _gen_weapon_idle_frame(weapon_id)

    # Frame 1: subtle breathing bob
    f0_arr = np.array(f0)
    f1_arr = f0_arr.copy()
    f1_arr[65:135, :] = f0_arr[66:136, :]
    f1_arr[65, :] = 0
    f1 = Image.fromarray(f1_arr, 'RGBA')

    idle_strip = Image.new("RGBA", (FRAME_W * 2, FRAME_H), (0, 0, 0, 0))
    idle_strip.paste(f0, (0, 0))
    idle_strip.paste(f1, (FRAME_W, 0))
    idle_strip.save(out_dir / "idle.png")

    # Attack: single peak-slash frame (reused from attack pose)
    attack_frame = _gen_weapon_attack_frame(weapon_id)
    # Make a 3-frame strip (wind-up, slash, recovery) for minimal animation
    # F0: near-idle wind-up
    wf0_arr = IDLE_F1.copy()
    _erase_sword(wf0_arr)
    shadow_row(wf0_arr, BODY_CX, SHADOW_Y, 22)
    sword_at_angle(wf0_arr, IDLE_HILT_X, IDLE_HILT_Y - 10, 120,
                   WEAPON_BLADE_LEN[weapon_id],
                   blade_colors=WEAPON_BLADE_COLORS[weapon_id])
    wf0 = Image.fromarray(wf0_arr, 'RGBA')

    # F2: recovery
    wf2_arr = IDLE_F1.copy()
    _erase_sword(wf2_arr)
    shadow_row(wf2_arr, BODY_CX, SHADOW_Y, 22)
    sword_at_angle(wf2_arr, IDLE_HILT_X, IDLE_HILT_Y, 210,
                   WEAPON_BLADE_LEN[weapon_id],
                   blade_colors=WEAPON_BLADE_COLORS[weapon_id])
    _add_weapon_effect(wf2_arr, IDLE_HILT_X, IDLE_HILT_Y, 210,
                       WEAPON_BLADE_LEN[weapon_id], weapon_id, intensity=0.4)
    wf2 = Image.fromarray(wf2_arr, 'RGBA')

    attack_strip = Image.new("RGBA", (FRAME_W * 3, FRAME_H), (0, 0, 0, 0))
    attack_strip.paste(wf0, (0, 0))
    attack_strip.paste(attack_frame, (FRAME_W, 0))
    attack_strip.paste(wf2, (FRAME_W * 2, 0))
    attack_strip.save(out_dir / "attack.png")

    return idle_strip, attack_strip


# ══════════════════════════════════════════════════════════════════════════════
# VALIDATION
# ══════════════════════════════════════════════════════════════════════════════

def validate_strip(strip, name, expected_frames, expected_w, expected_h=FRAME_H):
    """Assert strip dimensions and that each frame has opaque pixels."""
    assert strip.width  == expected_w, \
        f"{name}: width {strip.width} != {expected_w}"
    assert strip.height == expected_h, \
        f"{name}: height {strip.height} != {expected_h}"
    arr = np.array(strip)
    for i in range(expected_frames):
        frame = arr[:, i * FRAME_W:(i + 1) * FRAME_W, :]
        opaque = int((frame[:, :, 3] > 10).sum())
        assert opaque >= 300, \
            f"{name} frame {i}: only {opaque} opaque pixels (expected >=300)"
    # Corner pixels should be transparent (background check)
    assert arr[0, 0, 3] == 0, f"{name}: top-left corner not transparent"
    print(f"  {name}: {expected_w}x{expected_h}, {expected_frames} frames — PASS")


def check_file_reasonable(path, min_bytes=2000):
    """Check that a saved PNG file is not empty or trivially small."""
    size = path.stat().st_size
    assert size >= min_bytes, \
        f"{path.name}: file too small ({size} bytes, expected >={min_bytes})"
    return size


# ══════════════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════════════

def main():
    print("=== Fighter extended sprite animation generator ===\n")

    # Validate idle frame loaded correctly
    opaque_count = int((IDLE_F1[:, :, 3] > 10).sum())
    print(f"Idle frame loaded: {opaque_count} opaque pixels (expected >3000)")
    assert opaque_count > 3000, "Idle frame looks empty!"

    # ── Battle State Sprites ─────────────────────────────────────────────────

    print("\n[Battle State] Generating ADVANCE (4 frames)...")
    advance_strip = generate_advance()
    advance_path = OUT_DIR / "advance.png"
    advance_strip.save(advance_path)
    validate_strip(advance_strip, "advance", 4, FRAME_W * 4)
    check_file_reasonable(advance_path)

    print("[Battle State] Generating DEFER (4 frames)...")
    defer_strip = generate_defer()
    defer_path = OUT_DIR / "defer.png"
    defer_strip.save(defer_path)
    validate_strip(defer_strip, "defer", 4, FRAME_W * 4)
    check_file_reasonable(defer_path)

    # ── Ability Sprites ──────────────────────────────────────────────────────

    print("\n[Ability] Generating POWER_STRIKE (6 frames)...")
    ps_strip = generate_power_strike()
    ps_path = OUT_DIR / "power_strike.png"
    ps_strip.save(ps_path)
    validate_strip(ps_strip, "power_strike", 6, FRAME_W * 6)
    check_file_reasonable(ps_path)

    print("[Ability] Generating CLEAVE (6 frames)...")
    cleave_strip = generate_cleave()
    cleave_path = OUT_DIR / "cleave.png"
    cleave_strip.save(cleave_path)
    validate_strip(cleave_strip, "cleave", 6, FRAME_W * 6)
    check_file_reasonable(cleave_path)

    print("[Ability] Generating PROVOKE (4 frames)...")
    provoke_strip = generate_provoke()
    provoke_path = OUT_DIR / "provoke.png"
    provoke_strip.save(provoke_path)
    validate_strip(provoke_strip, "provoke", 4, FRAME_W * 4)
    check_file_reasonable(provoke_path)

    # ── Weapon Variants ──────────────────────────────────────────────────────

    weapons = [
        ('bronze_sword', "copper/brown short blade"),
        ('iron_sword',   "silver/steel standard blade"),
        ('flame_sword',  "red-orange blade with fire particles"),
        ('ice_blade',    "blue-white blade with frost crystals"),
    ]

    print("\n[Weapons] Generating weapon variants...")
    for weapon_id, description in weapons:
        print(f"  {weapon_id}: {description}")
        out_dir = WEAPONS_DIR / weapon_id
        idle_s, attack_s = generate_weapon_variant(weapon_id, out_dir)
        validate_strip(idle_s,   f"{weapon_id}/idle",   2, FRAME_W * 2)
        validate_strip(attack_s, f"{weapon_id}/attack", 3, FRAME_W * 3)
        check_file_reasonable(out_dir / "idle.png",   min_bytes=1000)
        check_file_reasonable(out_dir / "attack.png", min_bytes=1000)

    # ── Summary ──────────────────────────────────────────────────────────────

    print("\n=== Output file verification ===")
    outputs = [
        (OUT_DIR / "advance.png",     (FRAME_W * 4, FRAME_H)),
        (OUT_DIR / "defer.png",       (FRAME_W * 4, FRAME_H)),
        (OUT_DIR / "power_strike.png",(FRAME_W * 6, FRAME_H)),
        (OUT_DIR / "cleave.png",      (FRAME_W * 6, FRAME_H)),
        (OUT_DIR / "provoke.png",     (FRAME_W * 4, FRAME_H)),
    ]
    for weapon_id, _ in weapons:
        outputs.append((WEAPONS_DIR / weapon_id / "idle.png",   (FRAME_W * 2, FRAME_H)))
        outputs.append((WEAPONS_DIR / weapon_id / "attack.png", (FRAME_W * 3, FRAME_H)))

    all_ok = True
    for fpath, (ew, eh) in outputs:
        if not fpath.exists():
            print(f"  MISSING: {fpath}")
            all_ok = False
            continue
        img = Image.open(fpath)
        ok = img.size == (ew, eh)
        size_kb = fpath.stat().st_size // 1024
        status = "PASS" if ok else f"FAIL (got {img.size})"
        rel = fpath.relative_to(Path("/home/struktured/projects/cowardly-irregular-sprite-gen"))
        print(f"  {rel}: {ew}x{eh} {size_kb}KB — {status}")
        if not ok:
            all_ok = False

    print()
    if all_ok:
        print("All outputs generated and validated successfully.")
        print("\nTo register in sprite_manifest.json, add entries under 'party_sheets':")
        print("  fighter.advance, fighter.defer, fighter.power_strike, fighter.cleave, fighter.provoke")
        print("And weapon entries under 'weapon_sheets' (new section).")
    else:
        print("Some checks FAILED — see above.")
        sys.exit(1)


if __name__ == "__main__":
    main()
