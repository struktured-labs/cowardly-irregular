#!/usr/bin/env python3
"""
Mage EXTENDED sprite generator for Cowardly Irregular.
Generates additional animations beyond the base 9:
  - advance.png      (4 frames, 1024x256) — levitation + arcane runes
  - defer.png        (4 frames, 1024x256) — cloak wrap + arcane barrier
  - cast_fire.png    (6 frames, 1536x256) — fire spell: staff raised, fireball forms
  - cast_ice.png     (6 frames, 1536x256) — ice spell: crystals + blizzard
  - cast_lightning.png (6 frames, 1536x256) — lightning: bolt strikes through orb
  - cast_fira.png    (6 frames, 1536x256) — powered fire: massive fireball

Palette and drawing primitives are identical to gen_mage_sprites.py.
"""

from PIL import Image, ImageDraw
import os
import math

OUT_DIR = "/home/struktured/projects/cowardly-irregular-sprite-gen/assets/sprites/jobs/mage"
os.makedirs(OUT_DIR, exist_ok=True)

FRAME_W = 256
FRAME_H = 256

# ── Colour palette (identical to gen_mage_sprites.py) ─────────────────────────
C_OUTLINE     = (10,  10,  22,  255)

# Hat
C_HAT_LT      = (55,  55,  155, 255)
C_HAT_MID     = (30,  30,  105, 255)
C_HAT_DK      = (14,  14,  58,  255)
C_HAT_BRIM_LT = (45,  45,  135, 255)
C_HAT_BRIM_MID= (28,  28,  95,  255)

# Robes
C_ROBE_LT     = (45,  50,  130, 255)
C_ROBE_MID    = (25,  28,  85,  255)
C_ROBE_DK     = (12,  14,  45,  255)
C_ROBE_FOLD   = (18,  20,  65,  255)

# Silver trim
C_TRIM_LT     = (210, 218, 238, 255)
C_TRIM_MID    = (155, 163, 195, 255)
C_TRIM_DK     = (88,  95,  122, 255)

# Eyes
C_EYE_CORE    = (200, 255, 255, 255)
C_EYE_BRIGHT  = (20,  220, 255, 255)
C_EYE_DIM     = (0,   150, 200, 255)

# Face shadow
C_FACE        = (18,  15,  35,  255)
C_FACE_DK     = (8,   6,   18,  255)

# Skin
C_SKIN_LT     = (255, 230, 205, 255)
C_SKIN_MID    = (225, 195, 168, 255)
C_SKIN_DK     = (175, 142, 118, 255)

# Staff (wood)
C_STAFF_LT    = (185, 148, 98,  255)
C_STAFF_MID   = (135, 100, 58,  255)
C_STAFF_DK    = (82,  58,  28,  255)

# Orb (base cyan)
C_ORB_CORE    = (230, 255, 255, 255)
C_ORB_MID     = (55,  215, 255, 255)
C_ORB_DK      = (8,   118, 178, 255)

# Boots
C_BOOT_LT     = (115, 85,  55,  255)
C_BOOT_MID    = (78,  56,  32,  255)
C_BOOT_DK     = (42,  28,  12,  255)

# Base magic effects (cyan)
C_MAGIC_WHITE = (255, 255, 255, 255)
C_MAGIC_CYAN  = (80,  220, 255, 255)
C_MAGIC_BLUE  = (20,  140, 220, 200)
C_MAGIC_FAINT = (0,   80,  160, 80)

# Fire colours
C_FIRE_WHITE  = (255, 255, 200, 255)
C_FIRE_YELLOW = (255, 220, 50,  255)
C_FIRE_ORANGE = (255, 130, 20,  255)
C_FIRE_RED    = (220, 40,  10,  255)
C_FIRE_DARK   = (120, 20,  5,   255)

# Ice colours
C_ICE_WHITE   = (235, 248, 255, 255)
C_ICE_LT      = (175, 230, 255, 255)
C_ICE_MID     = (100, 190, 240, 255)
C_ICE_DK      = (40,  110, 195, 255)
C_ICE_FROST   = (210, 240, 255, 180)

# Lightning colours
C_BOLT_WHITE  = (255, 255, 255, 255)
C_BOLT_YELLOW = (255, 240, 80,  255)
C_BOLT_ARC    = (200, 210, 255, 255)
C_BOLT_GLOW   = (120, 140, 255, 200)

# Potion
C_POTION_LT   = (80,  220, 100, 255)
C_POTION_MID  = (50,  170, 75,  255)
C_POTION_CORK = (140, 100, 60,  255)

TRANSPARENT   = (0, 0, 0, 0)


# ── Drawing primitives (identical to gen_mage_sprites.py) ────────────────────

def px(img, x, y, color):
    if 0 <= x < img.width and 0 <= y < img.height:
        img.putpixel((x, y), color)

def hline(img, x0, x1, y, color):
    for x in range(min(x0, x1), max(x0, x1) + 1):
        px(img, x, y, color)

def vline(img, x, y0, y1, color):
    for y in range(min(y0, y1), max(y0, y1) + 1):
        px(img, x, y, color)

def filled_rect(img, x0, y0, x1, y1, color):
    for y in range(min(y0, y1), max(y0, y1) + 1):
        hline(img, x0, x1, y, color)

def circle_filled(img, cx, cy, r, color):
    for dy in range(-r, r + 1):
        dx_max = int(math.sqrt(r * r - dy * dy))
        for dx in range(-dx_max, dx_max + 1):
            px(img, cx + dx, cy + dy, color)

def circle_outline(img, cx, cy, r, color):
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            d2 = dx*dx + dy*dy
            r2_inner = (r - 1) ** 2
            if r2_inner < d2 <= r * r:
                px(img, cx + dx, cy + dy, color)

def draw_line(img, x0, y0, x1, y1, color, width=1):
    dx = abs(x1 - x0)
    dy = abs(y1 - y0)
    sx = 1 if x0 < x1 else -1
    sy = 1 if y0 < y1 else -1
    err = dx - dy
    pts = []
    cx, cy = x0, y0
    for _ in range(max(dx, dy) * 2 + 1):
        pts.append((cx, cy))
        if cx == x1 and cy == y1:
            break
        e2 = 2 * err
        if e2 > -dy:
            err -= dy
            cx += sx
        if e2 < dx:
            err += dx
            cy += sy
    for (bx, by) in pts:
        for wx in range(-(width // 2), (width // 2) + 1):
            px(img, bx + wx, by, color)

def glow(img, cx, cy, r_max, color_rgb):
    """Soft radial glow by alpha-blending."""
    r, g, b = color_rgb
    for dy in range(-r_max, r_max + 1):
        for dx in range(-r_max, r_max + 1):
            dist = math.sqrt(dx*dx + dy*dy)
            if dist <= r_max:
                t = 1.0 - dist / r_max
                a = int(200 * t * t)
                bx_c, by_c = cx + dx, cy + dy
                if 0 <= bx_c < img.width and 0 <= by_c < img.height:
                    ex, ey, eb, ea = img.getpixel((bx_c, by_c))
                    if ea == 0:
                        img.putpixel((bx_c, by_c), (r, g, b, a))
                    else:
                        ta = a / 255.0
                        nr = int(ex + (r - ex) * ta * 0.6)
                        ng = int(ey + (g - ey) * ta * 0.6)
                        nb = int(eb + (b - eb) * ta * 0.6)
                        img.putpixel((bx_c, by_c), (nr, ng, nb, 255))

def alpha_blend_pixel(img, x, y, color_rgba):
    """Blend color_rgba onto existing pixel."""
    if not (0 <= x < img.width and 0 <= y < img.height):
        return
    cr, cg, cb, ca = color_rgba
    er, eg, eb, ea = img.getpixel((x, y))
    if ea == 0:
        img.putpixel((x, y), (cr, cg, cb, ca))
    else:
        t = ca / 255.0
        nr = int(er + (cr - er) * t)
        ng = int(eg + (cg - eg) * t)
        nb = int(eb + (cb - eb) * t)
        img.putpixel((x, y), (nr, ng, nb, 255))


# ── Staff ─────────────────────────────────────────────────────────────────────

def draw_staff(img, x0, y0, x1, y1, orb_bright=0.5, orb_color=None):
    """Draw wooden staff from (x0,y0) bottom to (x1,y1) top with crystal orb.
    orb_color: RGB tuple for orb tint, or None for default cyan.
    """
    dx = x1 - x0
    dy = y1 - y0
    length = math.sqrt(dx*dx + dy*dy)
    if length < 1:
        return
    steps = max(int(length * 1.5), 2)
    for i in range(steps + 1):
        t = i / steps
        sx = int(x0 + dx * t)
        sy = int(y0 + dy * t)
        if t > 0.8:
            col = C_STAFF_DK
        elif t > 0.4:
            col = C_STAFF_MID
        else:
            col = C_STAFF_LT
        if abs(dx) > abs(dy):
            px(img, sx, sy,     C_OUTLINE)
            px(img, sx, sy + 1, col)
            px(img, sx, sy - 1, C_STAFF_LT if t < 0.3 else C_STAFF_MID)
        else:
            px(img, sx,     sy, C_OUTLINE)
            px(img, sx + 1, sy, col)
            px(img, sx - 1, sy, C_STAFF_LT if t < 0.3 else C_STAFF_MID)

    # Orb at top
    ox, oy = x1, y1
    orb_r = 6

    if orb_color is None:
        glow_col = (0, 180, 230)
        orb_mid = C_ORB_MID
        orb_inner = (int(55 + 100 * orb_bright), 215, 255, 255)
    else:
        gr, gg, gb = orb_color
        glow_col = (gr // 2, gg // 2, gb // 2)
        orb_mid = (int(gr * 0.7), int(gg * 0.7), int(gb * 0.7), 255)
        orb_inner = (int(gr * 0.4 + 100 * orb_bright), int(gg * 0.4 + 100 * orb_bright), int(gb * 0.4), 255)

    glow_r = int(8 + 6 * orb_bright)
    glow(img, ox, oy, glow_r, glow_col)
    circle_filled(img, ox, oy, orb_r, C_ORB_DK)
    circle_filled(img, ox, oy, orb_r - 1, orb_mid)
    circle_filled(img, ox, oy, orb_r - 3, orb_inner)
    px(img, ox - 2, oy - 2, C_ORB_CORE)
    px(img, ox - 1, oy - 2, C_ORB_CORE)
    px(img, ox - 2, oy - 1, C_ORB_CORE)
    circle_outline(img, ox, oy, orb_r, C_OUTLINE)


# ── Hat ───────────────────────────────────────────────────────────────────────

def draw_hat(img, brim_cx, brim_cy, tilt_px=0):
    hat_h = 55
    tip_x = brim_cx + tilt_px
    tip_y = brim_cy - hat_h

    for y in range(tip_y, brim_cy):
        t = (y - tip_y) / hat_h
        half_w = max(int(t * 15), 1)
        cx_row = int(brim_cx + tilt_px * (1.0 - t))
        for x in range(cx_row - half_w, cx_row + half_w + 1):
            dist = abs(x - cx_row) / half_w
            if dist < 0.25:
                col = C_HAT_LT
            elif dist < 0.65:
                col = C_HAT_MID
            else:
                col = C_HAT_DK
            px(img, x, y, col)
        px(img, cx_row - half_w - 1, y, C_OUTLINE)
        px(img, cx_row + half_w + 1, y, C_OUTLINE)

    px(img, tip_x, tip_y, C_HAT_LT)
    px(img, tip_x, tip_y - 1, C_OUTLINE)

    band_y = brim_cy - 6
    for by in range(band_y, band_y + 3):
        half_w = max(int((1.0 - (brim_cy - by) / hat_h) * 15), 1)
        cx_band = int(brim_cx + tilt_px * (1.0 - (brim_cy - by) / hat_h))
        for x in range(cx_band - half_w - 1, cx_band + half_w + 2):
            col = C_TRIM_LT if by == band_y else (C_TRIM_MID if by == band_y + 1 else C_TRIM_DK)
            px(img, x, by, col)

    brim_half_w = 24
    for y in range(brim_cy - 4, brim_cy + 3):
        t = (y - (brim_cy - 4)) / 6.0
        half_w = int(brim_half_w - 4 + t * 6)
        for x in range(brim_cx - half_w, brim_cx + half_w + 1):
            dist = abs(x - brim_cx) / half_w
            if dist < 0.5:
                col = C_HAT_BRIM_LT
            else:
                col = C_HAT_BRIM_MID
            px(img, x, y, col)
        px(img, brim_cx - half_w - 1, y, C_OUTLINE)
        px(img, brim_cx + half_w + 1, y, C_OUTLINE)
    hline(img, brim_cx - brim_half_w - 2, brim_cx + brim_half_w + 2, brim_cy - 5, C_OUTLINE)
    hline(img, brim_cx - brim_half_w - 2, brim_cx + brim_half_w + 2, brim_cy + 2, C_OUTLINE)


# ── Robes ─────────────────────────────────────────────────────────────────────

def draw_robes(img, cx, waist_y, hem_y, bob=0, sway=0):
    hem_y = hem_y + bob
    sway_cx = cx + sway

    for y in range(waist_y, hem_y + 1):
        t = (y - waist_y) / max(hem_y - waist_y, 1)
        half_w = int(7 + 25 * (t ** 0.7))
        half_w = min(half_w, 30)
        row_cx = cx + int(sway * t * 0.5)

        xl = row_cx - half_w
        xr = row_cx + half_w

        for x in range(xl + 1, xr):
            dist = abs(x - row_cx) / half_w
            if dist < 0.20:
                col = C_ROBE_LT
            elif dist < 0.55:
                col = C_ROBE_MID
            elif dist < 0.78:
                col = C_ROBE_FOLD
            else:
                col = C_ROBE_DK
            px(img, x, y, col)

        px(img, xl, y, C_OUTLINE)
        px(img, xr, y, C_OUTLINE)

        if 0.2 < t < 0.9:
            if (y % 8) < 2:
                fold_x_l = row_cx - int(half_w * 0.5)
                fold_x_r = row_cx + int(half_w * 0.5)
                px(img, fold_x_l, y, C_ROBE_FOLD)
                px(img, fold_x_r, y, C_ROBE_FOLD)
                if (y % 8) == 0:
                    px(img, fold_x_l - 1, y, C_ROBE_DK)
                    px(img, fold_x_r + 1, y, C_ROBE_DK)

    for dy in range(-3, 1):
        by = hem_y + dy
        t = (by - waist_y) / max(hem_y - waist_y, 1)
        half_w = int(7 + 25 * (t ** 0.7))
        row_cx = cx + int(sway * t * 0.5)
        if dy == -2:
            hline(img, row_cx - half_w - 1, row_cx + half_w + 1, by, C_TRIM_DK)
        elif dy == -1:
            hline(img, row_cx - half_w - 1, row_cx + half_w + 1, by, C_TRIM_MID)
        elif dy == 0:
            hline(img, row_cx - half_w - 1, row_cx + half_w + 1, by, C_TRIM_LT)

    for y in range(waist_y + 12, hem_y - 5):
        if (y % 3) < 2:
            px(img, cx,     y, C_TRIM_MID)
            px(img, cx + 1, y, C_TRIM_LT if (y % 3) == 0 else C_TRIM_MID)

    return xl, xr


# ── Boots ─────────────────────────────────────────────────────────────────────

def draw_boots(img, cx, foot_y, spread=10, bob=0):
    foot_y = foot_y + bob
    for side in (-1, 1):
        bx = cx + side * spread
        for y in range(foot_y - 18, foot_y + 1):
            t = (y - (foot_y - 18)) / 18.0
            half_w = int(5 + t * 2)
            for x in range(bx - half_w, bx + half_w + 1):
                dist = abs(x - bx) / half_w
                if dist < 0.4:
                    col = C_BOOT_LT
                elif dist < 0.7:
                    col = C_BOOT_MID
                else:
                    col = C_BOOT_DK
                px(img, x, y, col)
            px(img, bx - half_w - 1, y, C_OUTLINE)
            px(img, bx + half_w + 1, y, C_OUTLINE)
        sole_y = foot_y
        toe_w = int(8 + (1 if side == -1 else 0))
        hline(img, bx - toe_w, bx + toe_w, sole_y, C_BOOT_MID)
        hline(img, bx - toe_w, bx + toe_w, sole_y - 1, C_BOOT_LT)
        hline(img, bx - toe_w - 1, bx + toe_w + 1, sole_y + 1, C_OUTLINE)
        px(img, bx - toe_w - 1, sole_y, C_OUTLINE)
        px(img, bx + toe_w + 1, sole_y, C_OUTLINE)


# ── Body / chest / shoulders ──────────────────────────────────────────────────

def draw_chest(img, cx, chest_y):
    for y in range(chest_y, chest_y + 20):
        t = (y - chest_y) / 19.0
        half_w = int(10 + t * 4)
        for x in range(cx - half_w, cx + half_w + 1):
            dist = abs(x - cx) / half_w
            if dist < 0.3:
                col = C_ROBE_LT
            elif dist < 0.65:
                col = C_ROBE_MID
            else:
                col = C_ROBE_DK
            px(img, x, y, col)
        px(img, cx - half_w - 1, y, C_OUTLINE)
        px(img, cx + half_w + 1, y, C_OUTLINE)

    collar_y = chest_y + 1
    hline(img, cx - 8, cx + 8, collar_y, C_TRIM_LT)
    hline(img, cx - 9, cx + 9, collar_y + 1, C_TRIM_MID)
    hline(img, cx - 9, cx + 9, collar_y + 2, C_TRIM_DK)

    for side in (-1, 1):
        sx = cx + side * 13
        shoulder_w = 10
        for y in range(chest_y + 2, chest_y + 12):
            hline(img, sx - shoulder_w // 2, sx + shoulder_w // 2, y,
                  C_ROBE_LT if y < chest_y + 6 else C_ROBE_MID)
        hline(img, sx - shoulder_w // 2, sx + shoulder_w // 2, chest_y + 2, C_TRIM_MID)
        px(img, sx - shoulder_w // 2 - 1, chest_y + 2, C_OUTLINE)
        px(img, sx + shoulder_w // 2 + 1, chest_y + 2, C_OUTLINE)


# ── Face ──────────────────────────────────────────────────────────────────────

def draw_face(img, cx, cy, eyes_open=True, half_closed=False, eye_color=None):
    """Dark shadowed face with glowing eyes. eye_color overrides default cyan."""
    face_r = 11
    circle_filled(img, cx, cy, face_r, C_FACE)
    circle_filled(img, cx, cy, face_r - 2, C_FACE_DK)
    circle_outline(img, cx, cy, face_r, C_OUTLINE)
    circle_outline(img, cx, cy, face_r + 1, C_OUTLINE)

    if eye_color is None:
        e_bright = C_EYE_BRIGHT
        e_core   = C_EYE_CORE
        glow_col = (0, 200, 240)
    else:
        er, eg, eb = eye_color
        e_bright = (er, eg, eb, 255)
        e_core   = (min(255, er + 55), min(255, eg + 55), min(255, eb + 55), 255)
        glow_col = (er // 2, eg // 2, eb // 2)

    if eyes_open:
        ey = cy + 1
        lx = cx - 4
        glow(img, lx, ey, 5, glow_col)
        hline(img, lx - 2, lx + 2, ey, e_bright)
        px(img, lx - 1, ey - 1, e_core)
        px(img, lx,     ey - 1, e_core)
        px(img, lx + 1, ey - 1, e_core)
        rx = cx + 4
        glow(img, rx, ey, 5, glow_col)
        hline(img, rx - 2, rx + 2, ey, e_bright)
        px(img, rx - 1, ey - 1, e_core)
        px(img, rx,     ey - 1, e_core)
        px(img, rx + 1, ey - 1, e_core)
    elif half_closed:
        ey = cy + 2
        lx = cx - 4
        rx = cx + 4
        hline(img, lx - 1, lx + 1, ey, C_EYE_DIM)
        hline(img, rx - 1, rx + 1, ey, C_EYE_DIM)


# ── Arms ──────────────────────────────────────────────────────────────────────

def draw_arm(img, shoulder_x, shoulder_y, hand_x, hand_y, side='left'):
    dx = hand_x - shoulder_x
    dy = hand_y - shoulder_y
    length = math.sqrt(dx*dx + dy*dy)
    if length < 1:
        return
    steps = max(int(length), 2)
    for i in range(steps + 1):
        t = i / steps
        ax = int(shoulder_x + dx * t)
        ay = int(shoulder_y + dy * t)
        half_w = max(1, int(4 - t * 2))
        for w in range(-half_w, half_w + 1):
            dist = abs(w) / max(half_w, 1)
            if side == 'left':
                col = C_ROBE_DK if dist > 0.5 else (C_ROBE_LT if dist < 0.2 else C_ROBE_MID)
            else:
                col = C_ROBE_MID if dist > 0.5 else (C_ROBE_LT if dist < 0.2 else C_ROBE_MID)
            if abs(dy) >= abs(dx):
                px(img, ax + w, ay, col)
            else:
                px(img, ax, ay + w, col)
        if abs(dy) >= abs(dx):
            px(img, ax - half_w - 1, ay, C_OUTLINE)
            px(img, ax + half_w + 1, ay, C_OUTLINE)
        else:
            px(img, ax, ay - half_w - 1, C_OUTLINE)
            px(img, ax, ay + half_w + 1, C_OUTLINE)


def draw_hand(img, hx, hy):
    circle_filled(img, hx, hy, 4, C_SKIN_MID)
    px(img, hx - 1, hy - 1, C_SKIN_LT)
    px(img, hx,     hy - 1, C_SKIN_LT)
    circle_outline(img, hx, hy, 4, C_OUTLINE)


# ── Magic effects ─────────────────────────────────────────────────────────────

def draw_magic_burst(img, cx, cy, size=25, bright=1.0):
    """Cyan magic burst."""
    for dy in range(-size - 8, size + 9):
        for dx in range(-size - 8, size + 9):
            dist = math.sqrt(dx*dx + dy*dy)
            if dist <= size + 8:
                bx_c, by_c = cx + dx, cy + dy
                if not (0 <= bx_c < img.width and 0 <= by_c < img.height):
                    continue
                if dist <= size * 0.22:
                    col = C_MAGIC_WHITE
                elif dist <= size * 0.45:
                    t = (dist - size * 0.22) / (size * 0.23)
                    r = int(255 - t * 155)
                    g = int(255 - t * 35)
                    b = 255
                    col = (r, g, b, 255)
                elif dist <= size:
                    t = (dist - size * 0.45) / (size * 0.55)
                    r = int(20 + t * 0)
                    g = int(200 - t * 40)
                    b = int(255 - t * 35)
                    col = (r, g, b, 255)
                elif dist <= size + 8:
                    t = (dist - size) / 8.0
                    a_val = int(200 * (1.0 - t) * (1.0 - t))
                    col = (0, 160, 220, a_val)
                    bx_e, by_e, bb_e, ba_e = img.getpixel((bx_c, by_c))
                    if ba_e == 0:
                        img.putpixel((bx_c, by_c), col)
                    else:
                        tv = a_val / 255.0
                        img.putpixel((bx_c, by_c),
                            (int(bx_e + (0 - bx_e) * tv * 0.5),
                             int(by_e + (160 - by_e) * tv * 0.5),
                             int(bb_e + (220 - bb_e) * tv * 0.5),
                             255))
                    continue
                else:
                    continue
                img.putpixel((bx_c, by_c), col)

    for ang_deg in range(0, 360, 24):
        a = math.radians(ang_deg)
        r_start = int(size * 0.35)
        r_end   = int(size * 1.1)
        for r in range(r_start, r_end + 1):
            sx = cx + int(math.cos(a) * r)
            sy = cy + int(math.sin(a) * r)
            t  = (r - r_start) / (r_end - r_start)
            col = C_MAGIC_WHITE if t < 0.5 else C_MAGIC_CYAN
            px(img, sx, sy, col)

    circle_outline(img, cx, cy, size + 1, C_OUTLINE)


def draw_magic_circle(img, cx, cy, r, dot_every=15):
    circle_outline(img, cx, cy, r, C_MAGIC_CYAN)
    circle_outline(img, cx, cy, r + 1, (0, 140, 200, 120))
    for ang_deg in range(0, 360, dot_every):
        a = math.radians(ang_deg)
        dx = cx + int(math.cos(a) * r)
        dy = cy + int(math.sin(a) * r)
        px(img, dx, dy, C_EYE_CORE)


def draw_barrier(img, cx, cy, r, intensity=1.0):
    for ang_deg in range(-70, 71, 1):
        a = math.radians(ang_deg)
        for ri in range(r - 3, r + 4):
            sx = cx + int(math.cos(a) * ri)
            sy = cy + int(math.sin(a) * ri)
            dist_from_centre = abs(ri - r)
            alpha = int(intensity * (180 - dist_from_centre * 55))
            if alpha > 0:
                if 0 <= sx < img.width and 0 <= sy < img.height:
                    er, eg, eb, ea = img.getpixel((sx, sy))
                    t = alpha / 255.0
                    nr = int(er + (80 - er) * t * 0.7)
                    ng = int(eg + (220 - eg) * t * 0.7)
                    nb = int(eb + (255 - eb) * t * 0.7)
                    img.putpixel((sx, sy), (nr, ng, nb, 255))
    for ang_deg in range(-65, 66, 18):
        a = math.radians(ang_deg)
        sx = cx + int(math.cos(a) * r)
        sy = cy + int(math.sin(a) * r)
        px(img, sx, sy, C_EYE_CORE)


# ── Cloak wrap overlay (for defer animation) ─────────────────────────────────

def draw_cloak_wrap(img, cx, waist_y, hem_y, wrap_amount=0.0):
    """
    Overlay cloak wings folding inward around the mage.
    wrap_amount: 0.0=open, 1.0=fully wrapped.
    Draws two dark wing flaps that fold from the sides inward.
    """
    # Cloak wing: left and right robe edges pulled inward and darkened
    robe_half_w_top = 14
    robe_half_w_bot = 30

    for y in range(waist_y, hem_y + 1):
        t = (y - waist_y) / max(hem_y - waist_y, 1)
        base_hw = int(robe_half_w_top + (robe_half_w_bot - robe_half_w_top) * (t ** 0.7))
        # wrap_amount causes the cloak edge to come in from outside
        cloak_edge = int(base_hw * (1.0 + 0.4 * (1.0 - wrap_amount)))
        cloak_inner = int(base_hw * (1.0 - wrap_amount * 0.5))

        # Left cloak flap
        for x in range(cx - cloak_edge, cx - cloak_inner):
            local_t = (x - (cx - cloak_edge)) / max(cloak_edge - cloak_inner, 1)
            a = int(200 * (1.0 - local_t) * wrap_amount)
            if a > 0:
                bx, by = x, y
                if 0 <= bx < img.width and 0 <= by < img.height:
                    er, eg, eb, ea = img.getpixel((bx, by))
                    if ea > 0:
                        tf = a / 255.0
                        nr = int(er * (1.0 - tf * 0.6))
                        ng = int(eg * (1.0 - tf * 0.6))
                        nb = int(eb + (80 - eb) * tf * 0.3)
                        img.putpixel((bx, by), (nr, ng, nb, 255))

        # Right cloak flap
        for x in range(cx + cloak_inner, cx + cloak_edge):
            local_t = ((cx + cloak_edge) - x) / max(cloak_edge - cloak_inner, 1)
            a = int(200 * (1.0 - local_t) * wrap_amount)
            if a > 0:
                bx, by = x, y
                if 0 <= bx < img.width and 0 <= by < img.height:
                    er, eg, eb, ea = img.getpixel((bx, by))
                    if ea > 0:
                        tf = a / 255.0
                        nr = int(er * (1.0 - tf * 0.6))
                        ng = int(eg * (1.0 - tf * 0.6))
                        nb = int(eb + (80 - eb) * tf * 0.3)
                        img.putpixel((bx, by), (nr, ng, nb, 255))

    # Cloak fold edge lines (dark outlines at wrap boundary)
    if wrap_amount > 0.1:
        for y in range(waist_y, hem_y + 1):
            t = (y - waist_y) / max(hem_y - waist_y, 1)
            base_hw = int(robe_half_w_top + (robe_half_w_bot - robe_half_w_top) * (t ** 0.7))
            fold_x_l = cx - int(base_hw * (1.0 - wrap_amount * 0.5))
            fold_x_r = cx + int(base_hw * (1.0 - wrap_amount * 0.5))
            if (y % 4) < 2:
                px(img, fold_x_l, y, C_ROBE_DK)
                px(img, fold_x_r, y, C_ROBE_DK)


# ── Arcane barrier (fuller version for defer) ─────────────────────────────────

def draw_arcane_barrier_full(img, cx, cy, r, intensity=1.0):
    """
    Full-surround arcane shield bubble (differs from draw_barrier which is arc-only).
    """
    for ang_deg in range(0, 360, 1):
        a = math.radians(ang_deg)
        for ri in range(r - 4, r + 5):
            sx = cx + int(math.cos(a) * ri)
            sy = cy + int(math.sin(a) * ri)
            dist_from_edge = abs(ri - r)
            alpha = int(intensity * (160 - dist_from_edge * 38))
            if alpha > 0 and 0 <= sx < img.width and 0 <= sy < img.height:
                er, eg, eb, ea = img.getpixel((sx, sy))
                t = alpha / 255.0
                nr = int(er + (40 - er) * t * 0.5)
                ng = int(eg + (180 - eg) * t * 0.5)
                nb = int(eb + (255 - eb) * t * 0.5)
                img.putpixel((sx, sy), (nr, ng, nb, 255))

    # Shimmer dots around circle
    for ang_deg in range(0, 360, 20):
        a = math.radians(ang_deg)
        sx = cx + int(math.cos(a) * r)
        sy = cy + int(math.sin(a) * r)
        px(img, sx, sy, C_ICE_WHITE)


# ── Arcane rune circle (for advance animation) ────────────────────────────────

def draw_rune_ring(img, cx, cy, r, n_runes=6, bright=1.0):
    """
    Draw a ring of arcane rune marks around (cx, cy).
    n_runes: number of rune positions.
    """
    # Outer ring
    circle_outline(img, cx, cy, r, (int(80 * bright), int(220 * bright), 255, 255))
    circle_outline(img, cx, cy, r - 2, (int(40 * bright), int(160 * bright), 220, 180))

    # Spoke lines from ring to inner
    for i in range(n_runes):
        a = math.radians(i * 360 / n_runes)
        x0 = cx + int(math.cos(a) * (r - 6))
        y0 = cy + int(math.sin(a) * (r - 6))
        x1 = cx + int(math.cos(a) * (r - 16))
        y1 = cy + int(math.sin(a) * (r - 16))
        col = (int(100 * bright), int(220 * bright), 255, 255)
        draw_line(img, x0, y0, x1, y1, col)

    # Rune glyphs at each spoke end (simplified cross + dot)
    for i in range(n_runes):
        a = math.radians(i * 360 / n_runes)
        rx = cx + int(math.cos(a) * r)
        ry = cy + int(math.sin(a) * r)
        c = (int(200 * bright), 255, 255, 255)
        px(img, rx, ry, c)
        px(img, rx + 1, ry, c)
        px(img, rx - 1, ry, c)
        px(img, rx, ry + 1, c)
        px(img, rx, ry - 1, c)


# ── Fire effects ───────────────────────────────────────────────────────────────

def draw_fire_burst(img, cx, cy, size=22, power=1.0):
    """
    Fire explosion: white-yellow core, orange mid, red outer, dark ember fringe.
    power: 0..1 scales intensity and size.
    """
    eff_size = int(size * power)
    for dy in range(-eff_size - 10, eff_size + 11):
        for dx in range(-eff_size - 10, eff_size + 11):
            dist = math.sqrt(dx*dx + dy*dy)
            if dist <= eff_size + 10:
                bx_c = cx + dx
                by_c = cy + dy
                if not (0 <= bx_c < img.width and 0 <= by_c < img.height):
                    continue
                if dist <= eff_size * 0.20:
                    col = C_FIRE_WHITE
                elif dist <= eff_size * 0.40:
                    t = (dist - eff_size * 0.20) / (eff_size * 0.20)
                    r = 255
                    g = int(255 - t * 35)
                    b = int(200 - t * 150)
                    col = (r, g, b, 255)
                elif dist <= eff_size * 0.65:
                    t = (dist - eff_size * 0.40) / (eff_size * 0.25)
                    r = 255
                    g = int(220 - t * 90)
                    b = int(50 - t * 30)
                    col = (r, g, b, 255)
                elif dist <= eff_size:
                    t = (dist - eff_size * 0.65) / (eff_size * 0.35)
                    r = int(220 - t * 100)
                    g = int(130 - t * 110)
                    b = int(20 - t * 15)
                    col = (r, g, b, 255)
                elif dist <= eff_size + 10:
                    t = (dist - eff_size) / 10.0
                    a_val = int(160 * (1.0 - t) * (1.0 - t))
                    col = (180, 40, 5, a_val)
                    er, eg, eb, ea = img.getpixel((bx_c, by_c))
                    if ea == 0:
                        img.putpixel((bx_c, by_c), col)
                    else:
                        tv = a_val / 255.0
                        img.putpixel((bx_c, by_c),
                            (int(er + (180 - er) * tv * 0.4),
                             int(eg + (40 - eg) * tv * 0.4),
                             int(eb + (5 - eb) * tv * 0.4),
                             255))
                    continue
                else:
                    continue
                img.putpixel((bx_c, by_c), col)

    # Fire spikes
    for ang_deg in range(0, 360, 18):
        a = math.radians(ang_deg)
        spike_len = int(eff_size * 0.6 + eff_size * 0.5 * power)
        for r in range(int(eff_size * 0.4), int(eff_size * 0.4) + spike_len):
            sx = cx + int(math.cos(a) * r)
            sy = cy + int(math.sin(a) * r)
            t = (r - eff_size * 0.4) / spike_len
            col = C_FIRE_YELLOW if t < 0.4 else (C_FIRE_ORANGE if t < 0.7 else C_FIRE_RED)
            px(img, sx, sy, col)

    circle_outline(img, cx, cy, eff_size + 2, C_OUTLINE)


def draw_fireball(img, cx, cy, r=12):
    """Draw a compact fireball orb."""
    for dy in range(-r - 4, r + 5):
        for dx in range(-r - 4, r + 5):
            dist = math.sqrt(dx*dx + dy*dy)
            bx_c = cx + dx
            by_c = cy + dy
            if not (0 <= bx_c < img.width and 0 <= by_c < img.height):
                continue
            if dist <= r * 0.3:
                col = C_FIRE_WHITE
            elif dist <= r * 0.6:
                col = C_FIRE_YELLOW
            elif dist <= r:
                col = C_FIRE_ORANGE
            elif dist <= r + 4:
                t = (dist - r) / 4.0
                a_val = int(180 * (1.0 - t))
                col = (200, 60, 10, a_val)
                alpha_blend_pixel(img, bx_c, by_c, col)
                continue
            else:
                continue
            img.putpixel((bx_c, by_c), col)
    circle_outline(img, cx, cy, r, C_OUTLINE)


def draw_fire_spiral(img, cx, cy, r, n_arms=3, phase=0.0, intensity=1.0):
    """Flame spirals rotating around a point."""
    for arm in range(n_arms):
        base_angle = phase + arm * (2 * math.pi / n_arms)
        for i in range(40):
            t = i / 39.0
            angle = base_angle + t * math.pi * 1.5
            ri = int(r * 0.2 + r * 0.8 * t)
            sx = cx + int(math.cos(angle) * ri)
            sy = cy + int(math.sin(angle) * ri)
            if t < 0.3:
                col = C_FIRE_YELLOW
            elif t < 0.6:
                col = C_FIRE_ORANGE
            else:
                a_val = int(180 * (1.0 - t) * intensity)
                col = (200, 50, 10, a_val)
                alpha_blend_pixel(img, sx, sy, col)
                continue
            px(img, sx, sy, col)


def draw_fire_particles(img, cx, cy, count, spread, phase=0.0, rising=True):
    """Scattered fire ember particles."""
    for i in range(count):
        a = phase + i * (2 * math.pi / count)
        r = int(spread * 0.3 + spread * 0.7 * ((i * 7) % count) / count)
        sx = cx + int(math.cos(a) * r)
        sy = cy + int(math.sin(a) * r) - (int(r * 0.4) if rising else 0)
        col = C_FIRE_ORANGE if (i % 3) != 0 else C_FIRE_RED
        px(img, sx, sy, col)
        if i % 2 == 0:
            px(img, sx + 1, sy, C_FIRE_YELLOW)


# ── Ice effects ───────────────────────────────────────────────────────────────

def draw_ice_crystal(img, cx, cy, size=12, angle_offset=0.0):
    """Draw a single hexagonal ice crystal."""
    for i in range(6):
        a = angle_offset + math.radians(i * 60)
        ax = cx + int(math.cos(a) * size)
        ay = cy + int(math.sin(a) * size)
        bx = cx + int(math.cos(a + math.pi / 3) * size)
        by = cy + int(math.sin(a + math.pi / 3) * size)
        draw_line(img, cx, cy, ax, ay, C_ICE_MID)
        draw_line(img, ax, ay, bx, by, C_ICE_LT)

    # Core
    circle_filled(img, cx, cy, size // 3, C_ICE_MID)
    circle_filled(img, cx, cy, size // 5, C_ICE_WHITE)
    # Outline
    circle_outline(img, cx, cy, size // 3, C_OUTLINE)

    # Facet highlights along spokes
    for i in range(6):
        a = angle_offset + math.radians(i * 60)
        mid = size // 2
        mx = cx + int(math.cos(a) * mid)
        my = cy + int(math.sin(a) * mid)
        px(img, mx, my, C_ICE_WHITE)


def draw_ice_ground(img, cx, foot_y, spread=40, intensity=1.0):
    """Ice floor cracks spreading from mage's feet."""
    for arm in range(5):
        a = math.radians(-160 + arm * 40)
        length = int(spread * intensity)
        for r in range(0, length):
            sx = cx + int(math.cos(a) * r)
            sy = foot_y + int(math.sin(a) * r * 0.3)
            col = C_ICE_MID if r < length // 2 else C_ICE_LT
            px(img, sx, sy, col)
            # Branch cracks
            if r == length // 3 or r == 2 * length // 3:
                for branch_a in [a + 0.4, a - 0.4]:
                    for br in range(0, length // 3):
                        bsx = sx + int(math.cos(branch_a) * br)
                        bsy = sy + int(math.sin(branch_a) * br * 0.3)
                        px(img, bsx, bsy, C_ICE_DK)


def draw_blizzard_swirl(img, cx, cy, r, phase=0.0, intensity=1.0):
    """Swirling blizzard wind lines around mage."""
    for arm in range(4):
        base_a = phase + arm * math.pi / 2
        for i in range(30):
            t = i / 29.0
            angle = base_a + t * math.pi
            ri = int(r * 0.3 + r * 0.7 * t)
            sx = cx + int(math.cos(angle) * ri)
            sy = cy + int(math.sin(angle) * ri)
            a_val = int(180 * (1.0 - t) * intensity)
            col = (210, 240, 255, a_val)
            alpha_blend_pixel(img, sx, sy, col)
            alpha_blend_pixel(img, sx + 1, sy, (255, 255, 255, a_val // 2))


def draw_ice_shard(img, tip_x, tip_y, base_x, base_y, width=6):
    """Draw a pointed ice shard projectile."""
    dx = base_x - tip_x
    dy = base_y - tip_y
    length = math.sqrt(dx*dx + dy*dy)
    if length < 1:
        return
    nx = -dy / length
    ny = dx / length

    steps = max(int(length), 2)
    for i in range(steps + 1):
        t = i / steps
        mx = int(tip_x + dx * t)
        my = int(tip_y + dy * t)
        half_w = int(width * t * 0.5)
        for w in range(-half_w, half_w + 1):
            sx = mx + int(nx * w)
            sy = my + int(ny * w)
            dist = abs(w) / max(half_w, 1) if half_w > 0 else 0
            if dist < 0.3:
                col = C_ICE_WHITE
            elif dist < 0.6:
                col = C_ICE_LT
            else:
                col = C_ICE_MID
            px(img, sx, sy, col)

    # Outline
    for i in range(steps + 1):
        t = i / steps
        mx = int(tip_x + dx * t)
        my = int(tip_y + dy * t)
        half_w = int(width * t * 0.5)
        px(img, mx + int(nx * (half_w + 1)), my + int(ny * (half_w + 1)), C_OUTLINE)
        px(img, mx - int(nx * (half_w + 1)), my - int(ny * (half_w + 1)), C_OUTLINE)


def draw_frost_particles(img, cx, cy, count, spread, phase=0.0):
    """Scatter frost crystal dots."""
    for i in range(count):
        a = phase + i * (2 * math.pi / count)
        r = int(spread * 0.4 + spread * 0.6 * ((i * 5) % count) / count)
        sx = cx + int(math.cos(a) * r)
        sy = cy + int(math.sin(a) * r)
        col = C_ICE_WHITE if (i % 3) == 0 else C_ICE_LT
        px(img, sx, sy, col)
        px(img, sx, sy - 1, C_ICE_MID)


# ── Lightning effects ─────────────────────────────────────────────────────────

def draw_lightning_bolt(img, x0, y0, x1, y1, jaggedness=8, width=2, bright=True):
    """Draw a jagged lightning bolt from (x0,y0) to (x1,y1)."""
    dx = x1 - x0
    dy = y1 - y0
    length = math.sqrt(dx*dx + dy*dy)
    segments = max(jaggedness, 2)

    # Generate jag points
    points = [(x0, y0)]
    for i in range(1, segments):
        t = i / segments
        base_x = x0 + dx * t
        base_y = y0 + dy * t
        # Perpendicular offset
        perp_x = -dy / length
        perp_y = dx / length
        offset = (((i * 37) % 20) - 10) * (length / 80)
        jx = int(base_x + perp_x * offset)
        jy = int(base_y + perp_y * offset)
        points.append((jx, jy))
    points.append((x1, y1))

    # Draw outer glow
    for i in range(len(points) - 1):
        ax, ay = points[i]
        bx, by = points[i + 1]
        draw_line(img, ax, ay, bx, by, C_BOLT_GLOW, width + 3)

    # Draw bolt body
    for i in range(len(points) - 1):
        ax, ay = points[i]
        bx, by = points[i + 1]
        draw_line(img, ax, ay, bx, by, C_BOLT_ARC, width + 1)

    # Draw bright core
    for i in range(len(points) - 1):
        ax, ay = points[i]
        bx, by = points[i + 1]
        core_col = C_BOLT_WHITE if bright else C_BOLT_YELLOW
        draw_line(img, ax, ay, bx, by, core_col, width)


def draw_lightning_sparks(img, cx, cy, n_sparks=12, max_len=20, phase=0.0):
    """Short spark arcs radiating from a point."""
    for i in range(n_sparks):
        a = phase + i * (2 * math.pi / n_sparks)
        length = int(max_len * 0.5 + max_len * 0.5 * ((i * 7) % n_sparks) / n_sparks)
        ex = cx + int(math.cos(a) * length)
        ey = cy + int(math.sin(a) * length)
        draw_line(img, cx, cy, ex, ey, C_BOLT_YELLOW, 1)
        px(img, ex, ey, C_BOLT_WHITE)


def draw_electric_orb(img, cx, cy, r, intensity=1.0):
    """Electrically charged orb — yellow-white instead of blue."""
    glow_r = int((r + 6) * intensity)
    glow(img, cx, cy, glow_r, (180, 200, 255))
    circle_filled(img, cx, cy, r, C_ORB_DK)
    circle_filled(img, cx, cy, r - 1, C_BOLT_GLOW)
    circle_filled(img, cx, cy, r - 3, C_BOLT_YELLOW)
    if intensity > 0.7:
        circle_filled(img, cx, cy, r - 5, C_BOLT_WHITE)
    px(img, cx - 2, cy - 2, C_BOLT_WHITE)
    circle_outline(img, cx, cy, r, C_OUTLINE)


def draw_sky_flash(img, intensity=1.0):
    """Full-frame sky flash — brightens the top area of the frame."""
    flash_h = int(FRAME_H * 0.45)
    for y in range(flash_h):
        t_y = 1.0 - y / flash_h
        for x in range(FRAME_W):
            if 0 <= x < img.width and 0 <= y < img.height:
                er, eg, eb, ea = img.getpixel((x, y))
                if ea > 0:
                    a = t_y * intensity * 0.7
                    nr = int(er + (255 - er) * a)
                    ng = int(eg + (255 - eg) * a)
                    nb = int(eb + (255 - eb) * a)
                    img.putpixel((x, y), (nr, ng, nb, 255))
                else:
                    a_val = int(40 * t_y * intensity)
                    if a_val > 0:
                        img.putpixel((x, y), (200, 210, 255, a_val))


# ══════════════════════════════════════════════════════════════════════════════
# Master frame builder (identical interface to gen_mage_sprites.py)
# ══════════════════════════════════════════════════════════════════════════════

def make_frame(**kw):
    """
    Draw a full mage frame.
    Accepts all the same parameters as gen_mage_sprites.py's make_frame,
    plus extended parameters for new effect types.

    Extended parameters:
      cloak_wrap          — 0..1 cloak wrap amount
      rune_ring_cx/cy/r   — if set, draw rune ring
      rune_ring_bright    — 0..1
      arcane_barrier_full — bool, draw full-surround barrier
      arcane_barrier_cx/cy/r/intensity
      fire_burst_x/y/size/power — coloured fire burst
      fireball_x/y/r      — compact fireball
      fire_spiral_cx/cy/r/phase — spiral flames around point
      fire_particles_cx/cy/count/spread/phase — embers
      ice_crystals        — list of (cx,cy,size,angle_offset)
      ice_ground          — bool
      ice_ground_spread/intensity
      blizzard_cx/cy/r/phase/intensity — swirling blizzard
      ice_shard_from/to   — (x,y) tuples for shard projectile
      frost_particles_cx/cy/count/spread/phase
      lightning_from/to   — (x,y) for bolt
      lightning_jagged    — jaggedness segments
      lightning_sparks_cx/cy/phase
      electric_orb        — bool (replaces normal orb on staff)
      sky_flash           — 0..1 full-frame brightness flash
      eye_color           — RGB tuple for eye glow override
      hover_y_off         — extra upward offset for levitation effect
    """
    img = Image.new("RGBA", (FRAME_W, FRAME_H), TRANSPARENT)

    cx       = kw.get('cx', FRAME_W // 2)
    foot_y   = kw.get('foot_y', FRAME_H - 30)
    hat_tilt = kw.get('hat_tilt', 0)
    sway     = kw.get('body_sway', 0)
    bob      = kw.get('robe_bob', 0)
    bspr     = kw.get('boot_spread', 10)
    orb_br   = kw.get('orb_bright', 0.5)
    eyes_open= kw.get('eyes_open', True)
    half_cl  = kw.get('half_closed', False)
    staff_vis= kw.get('staff_visible', True)
    eye_col  = kw.get('eye_color', None)
    hover_off= kw.get('hover_y_off', 0)   # negative = upward

    # Derived positions (hover lifts everything up)
    effective_foot_y = foot_y - hover_off
    rcx      = cx + sway
    waist_y  = effective_foot_y - 108
    hem_y    = effective_foot_y - 20
    chest_y  = kw.get('chest_y', waist_y - 2)
    face_cy  = waist_y - 20

    lhx = kw.get('left_hand_x',  cx - 22)
    lhy = kw.get('left_hand_y',  waist_y + 30)
    rhx = kw.get('right_hand_x', cx + 20)
    rhy = kw.get('right_hand_y', waist_y + 30)
    stx = kw.get('staff_top_x',  cx - 28)
    sty = kw.get('staff_top_y',  waist_y - 55)

    lshx = cx - 18
    rshy = waist_y + 5
    rshx = cx + 18

    # Orb colour override for elemental spells
    orb_color = kw.get('orb_color', None)

    # ── Draw order: back-to-front ─────────────────────────────────────────────

    # Sky flash (behind everything)
    if 'sky_flash' in kw and kw['sky_flash'] > 0:
        draw_sky_flash(img, kw['sky_flash'])

    # Rune ring (behind mage)
    if 'rune_ring_cx' in kw:
        draw_rune_ring(img,
                       kw['rune_ring_cx'], kw['rune_ring_cy'],
                       r=kw.get('rune_ring_r', 50),
                       n_runes=kw.get('rune_ring_n', 6),
                       bright=kw.get('rune_ring_bright', 1.0))

    # Blizzard swirl (behind mage)
    if 'blizzard_cx' in kw:
        draw_blizzard_swirl(img,
                            kw['blizzard_cx'], kw['blizzard_cy'],
                            r=kw.get('blizzard_r', 55),
                            phase=kw.get('blizzard_phase', 0.0),
                            intensity=kw.get('blizzard_intensity', 1.0))

    # Ice ground cracks
    if kw.get('ice_ground', False):
        draw_ice_ground(img, cx, foot_y,
                        spread=kw.get('ice_ground_spread', 40),
                        intensity=kw.get('ice_ground_intensity', 1.0))

    # 1. Staff (behind body)
    if staff_vis:
        draw_staff(img, lhx, lhy, stx, sty, orb_br, orb_color=orb_color)

    # Ice shard projectile (behind mage body but drawn early)
    if 'ice_shard_from' in kw:
        fx, fy = kw['ice_shard_from']
        tx, ty = kw['ice_shard_to']
        draw_ice_shard(img, tx, ty, fx, fy, width=kw.get('ice_shard_width', 8))

    # 2. Boots
    draw_boots(img, rcx, effective_foot_y + bob, spread=bspr, bob=0)

    # 3. Robes
    draw_robes(img, rcx, waist_y, hem_y, bob=bob, sway=sway // 2)

    # Cloak wrap overlay (on top of robes)
    if kw.get('cloak_wrap', 0) > 0:
        draw_cloak_wrap(img, rcx, waist_y, hem_y, wrap_amount=kw['cloak_wrap'])

    # 4. Chest / shoulders
    draw_chest(img, rcx, chest_y)

    # 5. Left arm
    draw_arm(img, lshx, rshy, lhx, lhy, side='left')
    draw_hand(img, lhx, lhy)

    # 6. Right arm
    draw_arm(img, rshx, rshy, rhx, rhy, side='right')
    draw_hand(img, rhx, rhy)

    # 7. Face
    draw_face(img, cx + 2, face_cy, eyes_open=eyes_open, half_closed=half_cl,
              eye_color=eye_col)

    # 8. Hat
    draw_hat(img, cx + 1, face_cy - 13, tilt_px=hat_tilt)

    # ── Magic overlays (drawn in front of mage) ───────────────────────────────

    # Electric orb replacement on staff
    if kw.get('electric_orb', False):
        draw_electric_orb(img, stx, sty, r=6, intensity=orb_br)

    # Arcane full barrier
    if kw.get('arcane_barrier_full', False):
        bcx = kw.get('arcane_barrier_cx', cx)
        bcy = kw.get('arcane_barrier_cy', face_cy + 15)
        br  = kw.get('arcane_barrier_r', 55)
        draw_arcane_barrier_full(img, bcx, bcy, br,
                                 intensity=kw.get('arcane_barrier_intensity', 1.0))

    # Ice crystals scattered around
    if 'ice_crystals' in kw:
        for cryst in kw['ice_crystals']:
            draw_ice_crystal(img, cryst[0], cryst[1],
                             size=cryst[2] if len(cryst) > 2 else 10,
                             angle_offset=cryst[3] if len(cryst) > 3 else 0.0)

    # Frost particles
    if 'frost_particles_cx' in kw:
        draw_frost_particles(img,
                             kw['frost_particles_cx'], kw['frost_particles_cy'],
                             count=kw.get('frost_particles_count', 12),
                             spread=kw.get('frost_particles_spread', 40),
                             phase=kw.get('frost_particles_phase', 0.0))

    # Fire burst
    if 'fire_burst_x' in kw:
        draw_fire_burst(img, kw['fire_burst_x'], kw['fire_burst_y'],
                        size=kw.get('fire_burst_size', 22),
                        power=kw.get('fire_burst_power', 1.0))

    # Fireball orb
    if 'fireball_x' in kw:
        draw_fireball(img, kw['fireball_x'], kw['fireball_y'],
                      r=kw.get('fireball_r', 12))

    # Fire spiral
    if 'fire_spiral_cx' in kw:
        draw_fire_spiral(img,
                         kw['fire_spiral_cx'], kw['fire_spiral_cy'],
                         r=kw.get('fire_spiral_r', 30),
                         n_arms=kw.get('fire_spiral_arms', 3),
                         phase=kw.get('fire_spiral_phase', 0.0),
                         intensity=kw.get('fire_spiral_intensity', 1.0))

    # Fire particles
    if 'fire_particles_cx' in kw:
        draw_fire_particles(img,
                            kw['fire_particles_cx'], kw['fire_particles_cy'],
                            count=kw.get('fire_particles_count', 16),
                            spread=kw.get('fire_particles_spread', 35),
                            phase=kw.get('fire_particles_phase', 0.0))

    # Lightning bolt
    if 'lightning_from' in kw:
        fx, fy = kw['lightning_from']
        tx, ty = kw['lightning_to']
        draw_lightning_bolt(img, fx, fy, tx, ty,
                            jaggedness=kw.get('lightning_jagged', 8),
                            width=kw.get('lightning_width', 2),
                            bright=kw.get('lightning_bright', True))

    # Lightning sparks
    if 'lightning_sparks_cx' in kw:
        draw_lightning_sparks(img,
                              kw['lightning_sparks_cx'], kw['lightning_sparks_cy'],
                              n_sparks=kw.get('lightning_sparks_n', 12),
                              max_len=kw.get('lightning_sparks_len', 20),
                              phase=kw.get('lightning_sparks_phase', 0.0))

    # Hover shadow (if levitating, draw reduced/faded shadow on ground)
    if hover_off > 0:
        shadow_y = foot_y + 2
        shadow_w = max(4, int(20 - hover_off * 0.5))
        shadow_a = max(40, int(120 - hover_off * 2))
        for sx in range(cx - shadow_w, cx + shadow_w + 1):
            alpha_blend_pixel(img, sx, shadow_y, (10, 10, 30, shadow_a))
            alpha_blend_pixel(img, sx, shadow_y + 1, (10, 10, 30, shadow_a // 2))

    return img


# ══════════════════════════════════════════════════════════════════════════════
# Strip assembly helpers
# ══════════════════════════════════════════════════════════════════════════════

def make_strip(n_frames):
    return Image.new("RGBA", (FRAME_W * n_frames, FRAME_H), TRANSPARENT)

def put_frame(strip, frame_idx, frame_img):
    strip.paste(frame_img, (frame_idx * FRAME_W, 0))

def save_strip(strip, name):
    path = os.path.join(OUT_DIR, name)
    strip.save(path, "PNG")
    size_kb = os.path.getsize(path) // 1024
    print(f"  Saved {path}  ({strip.width}x{strip.height}, {size_kb} KB)")
    return path


# ══════════════════════════════════════════════════════════════════════════════
# Character anchor constants
# ══════════════════════════════════════════════════════════════════════════════
CX   = FRAME_W // 2   # 128
FOOT = FRAME_H - 32   # 224


# ══════════════════════════════════════════════════════════════════════════════
# 1. advance.png — 4 frames
# Mage floats off ground, arcane runes circle, staff blazes
# ══════════════════════════════════════════════════════════════════════════════
print("Generating advance.png ...")
strip = make_strip(4)

# Frame 0: slight hover (4px), runes not yet visible
put_frame(strip, 0, make_frame(
    cx=CX, foot_y=FOOT,
    hover_y_off=4,
    left_hand_x=CX - 26, left_hand_y=FOOT - 104,
    staff_top_x=CX - 34, staff_top_y=FOOT - 188,
    right_hand_x=CX + 22, right_hand_y=FOOT - 100,
    hat_tilt=-1, orb_bright=0.6,
))

# Frame 1: hover 10px, rune ring appears at low brightness
put_frame(strip, 1, make_frame(
    cx=CX, foot_y=FOOT,
    hover_y_off=10,
    left_hand_x=CX - 27, left_hand_y=FOOT - 110,
    staff_top_x=CX - 33, staff_top_y=FOOT - 192,
    right_hand_x=CX + 20, right_hand_y=FOOT - 106,
    hat_tilt=-2, orb_bright=0.75,
    rune_ring_cx=CX, rune_ring_cy=FOOT - 50,
    rune_ring_r=48, rune_ring_n=6, rune_ring_bright=0.5,
))

# Frame 2: full levitation (18px), rune circle fully formed
put_frame(strip, 2, make_frame(
    cx=CX, foot_y=FOOT,
    hover_y_off=18,
    left_hand_x=CX - 28, left_hand_y=FOOT - 115,
    staff_top_x=CX - 32, staff_top_y=FOOT - 196,
    right_hand_x=CX + 18, right_hand_y=FOOT - 112,
    hat_tilt=-3, orb_bright=0.9,
    rune_ring_cx=CX, rune_ring_cy=FOOT - 55,
    rune_ring_r=55, rune_ring_n=8, rune_ring_bright=1.0,
))

# Frame 3: peak levitation (22px), staff blazing with orb at full power
put_frame(strip, 3, make_frame(
    cx=CX, foot_y=FOOT,
    hover_y_off=22,
    left_hand_x=CX - 30, left_hand_y=FOOT - 118,
    staff_top_x=CX - 30, staff_top_y=FOOT - 200,
    right_hand_x=CX + 15, right_hand_y=FOOT - 115,
    hat_tilt=-4, orb_bright=1.0,
    rune_ring_cx=CX, rune_ring_cy=FOOT - 58,
    rune_ring_r=58, rune_ring_n=8, rune_ring_bright=1.0,
))

save_strip(strip, "advance.png")


# ══════════════════════════════════════════════════════════════════════════════
# 2. defer.png — 4 frames
# Mage wraps cloak, orb dims, arcane barrier shimmers around them
# ══════════════════════════════════════════════════════════════════════════════
print("Generating defer.png ...")
strip = make_strip(4)

# Frame 0: beginning to pull cloak inward, slight hunch
put_frame(strip, 0, make_frame(
    cx=CX, foot_y=FOOT,
    left_hand_x=CX - 18, left_hand_y=FOOT - 98,
    staff_top_x=CX - 22, staff_top_y=FOOT - 185,
    right_hand_x=CX + 14, right_hand_y=FOOT - 100,
    hat_tilt=-1, orb_bright=0.45,
    body_sway=-2,
    cloak_wrap=0.2,
))

# Frame 1: hunched deeper, cloak half-wrapped, barrier starting to form
put_frame(strip, 1, make_frame(
    cx=CX - 2, foot_y=FOOT,
    left_hand_x=CX - 12, left_hand_y=FOOT - 96,
    staff_top_x=CX - 16, staff_top_y=FOOT - 182,
    right_hand_x=CX + 8, right_hand_y=FOOT - 98,
    hat_tilt=-2, orb_bright=0.30,
    body_sway=-4,
    cloak_wrap=0.5,
    arcane_barrier_full=True,
    arcane_barrier_cx=CX - 2, arcane_barrier_cy=FOOT - 75, arcane_barrier_r=52,
    arcane_barrier_intensity=0.45,
))

# Frame 2: fully wrapped, barrier shimmering at half brightness
put_frame(strip, 2, make_frame(
    cx=CX - 4, foot_y=FOOT,
    left_hand_x=CX - 6, left_hand_y=FOOT - 94,
    staff_top_x=CX - 10, staff_top_y=FOOT - 180,
    right_hand_x=CX + 2, right_hand_y=FOOT - 95,
    hat_tilt=-3, orb_bright=0.18,
    body_sway=-6,
    cloak_wrap=0.85,
    arcane_barrier_full=True,
    arcane_barrier_cx=CX - 4, arcane_barrier_cy=FOOT - 75, arcane_barrier_r=52,
    arcane_barrier_intensity=0.80,
))

# Frame 3: fully cloaked protective pose, orb dim, barrier visible
put_frame(strip, 3, make_frame(
    cx=CX - 4, foot_y=FOOT,
    left_hand_x=CX - 6, left_hand_y=FOOT - 93,
    staff_top_x=CX - 10, staff_top_y=FOOT - 178,
    right_hand_x=CX + 2, right_hand_y=FOOT - 94,
    hat_tilt=-3, orb_bright=0.12,
    body_sway=-6,
    cloak_wrap=1.0,
    arcane_barrier_full=True,
    arcane_barrier_cx=CX - 4, arcane_barrier_cy=FOOT - 75, arcane_barrier_r=52,
    arcane_barrier_intensity=0.65,
    eyes_open=False, half_closed=True,
))

save_strip(strip, "defer.png")


# ══════════════════════════════════════════════════════════════════════════════
# 3. cast_fire.png — 6 frames
# Fire spell: staff raised → flames spiral from orb → fireball forms → launches
# Orb shifts to warm orange during cast
# ══════════════════════════════════════════════════════════════════════════════
print("Generating cast_fire.png ...")
strip = make_strip(6)

# Warm orange orb tint for fire magic
FIRE_ORB = (255, 140, 20)

# Frame 0: staff raised, orb warming up (orange tint beginning)
put_frame(strip, 0, make_frame(
    cx=CX, foot_y=FOOT,
    left_hand_x=CX - 26, left_hand_y=FOOT - 108,
    staff_top_x=CX - 30, staff_top_y=FOOT - 192,
    right_hand_x=CX + 22, right_hand_y=FOOT - 105,
    hat_tilt=0, orb_bright=0.55,
    orb_color=FIRE_ORB,
))

# Frame 1: staff angled forward/up, small fire particles around orb
put_frame(strip, 1, make_frame(
    cx=CX, foot_y=FOOT,
    left_hand_x=CX - 22, left_hand_y=FOOT - 115,
    staff_top_x=CX - 18, staff_top_y=FOOT - 196,
    right_hand_x=CX + 24, right_hand_y=FOOT - 110,
    hat_tilt=1, orb_bright=0.70,
    orb_color=FIRE_ORB,
    fire_particles_cx=CX - 18, fire_particles_cy=FOOT - 196,
    fire_particles_count=8, fire_particles_spread=18,
    fire_particles_phase=0.2,
))

# Frame 2: flames spiral from orb, staff nearly horizontal thrust
put_frame(strip, 2, make_frame(
    cx=CX - 2, foot_y=FOOT,
    left_hand_x=CX - 16, left_hand_y=FOOT - 112,
    staff_top_x=CX + 20, staff_top_y=FOOT - 182,
    right_hand_x=CX + 20, right_hand_y=FOOT - 112,
    hat_tilt=2, orb_bright=0.85,
    orb_color=FIRE_ORB,
    fire_spiral_cx=CX + 20, fire_spiral_cy=FOOT - 182,
    fire_spiral_r=24, fire_spiral_arms=3, fire_spiral_phase=0.0,
    fire_particles_cx=CX + 20, fire_particles_cy=FOOT - 182,
    fire_particles_count=12, fire_particles_spread=22,
    fire_particles_phase=0.5,
))

# Frame 3: full thrust, fireball fully formed at orb tip
put_frame(strip, 3, make_frame(
    cx=CX - 4, foot_y=FOOT,
    left_hand_x=CX - 12, left_hand_y=FOOT - 110,
    staff_top_x=CX + 42, staff_top_y=FOOT - 168,
    right_hand_x=CX + 18, right_hand_y=FOOT - 112,
    hat_tilt=4, orb_bright=1.0,
    orb_color=FIRE_ORB,
    fireball_x=CX + 42, fireball_y=FOOT - 168, fireball_r=14,
    fire_particles_cx=CX + 42, fire_particles_cy=FOOT - 168,
    fire_particles_count=14, fire_particles_spread=28,
    fire_particles_phase=0.8,
    eye_color=(255, 120, 20),
))

# Frame 4: fireball launches forward (away from mage), trail visible
put_frame(strip, 4, make_frame(
    cx=CX - 4, foot_y=FOOT,
    left_hand_x=CX - 12, left_hand_y=FOOT - 110,
    staff_top_x=CX + 42, staff_top_y=FOOT - 168,
    right_hand_x=CX + 18, right_hand_y=FOOT - 112,
    hat_tilt=4, orb_bright=0.95,
    orb_color=FIRE_ORB,
    fireball_x=CX + 80, fireball_y=FOOT - 155, fireball_r=13,
    fire_burst_x=CX + 80, fire_burst_y=FOOT - 155,
    fire_burst_size=14, fire_burst_power=0.7,
    eye_color=(255, 120, 20),
))

# Frame 5: follow-through, staff lowering, embers settle
put_frame(strip, 5, make_frame(
    cx=CX, foot_y=FOOT,
    left_hand_x=CX - 22, left_hand_y=FOOT - 105,
    staff_top_x=CX - 10, staff_top_y=FOOT - 186,
    right_hand_x=CX + 22, right_hand_y=FOOT - 102,
    hat_tilt=1, orb_bright=0.5,
    orb_color=FIRE_ORB,
    fire_particles_cx=CX - 10, fire_particles_cy=FOOT - 186,
    fire_particles_count=6, fire_particles_spread=14,
    fire_particles_phase=1.2,
))

save_strip(strip, "cast_fire.png")


# ══════════════════════════════════════════════════════════════════════════════
# 4. cast_ice.png — 6 frames
# Ice spell: staff plants → crystals form → blizzard swirl → shard launches
# ══════════════════════════════════════════════════════════════════════════════
print("Generating cast_ice.png ...")
strip = make_strip(6)

# Ice-blue orb tint
ICE_ORB = (160, 230, 255)

# Frame 0: staff plants on ground (bottom), mage bracing
put_frame(strip, 0, make_frame(
    cx=CX, foot_y=FOOT,
    left_hand_x=CX - 20, left_hand_y=FOOT - 60,
    staff_top_x=CX - 22, staff_top_y=FOOT - 145,
    right_hand_x=CX + 22, right_hand_y=FOOT - 105,
    hat_tilt=-1, orb_bright=0.45,
    orb_color=ICE_ORB,
))

# Frame 1: ice cracks forming at feet from staff plant
put_frame(strip, 1, make_frame(
    cx=CX, foot_y=FOOT,
    left_hand_x=CX - 20, left_hand_y=FOOT - 60,
    staff_top_x=CX - 22, staff_top_y=FOOT - 145,
    right_hand_x=CX + 22, right_hand_y=FOOT - 108,
    hat_tilt=-1, orb_bright=0.60,
    orb_color=ICE_ORB,
    ice_ground=True, ice_ground_spread=28, ice_ground_intensity=0.6,
    ice_crystals=[(CX - 35, FOOT - 5, 7, 0.0), (CX + 30, FOOT - 3, 6, 0.5)],
))

# Frame 2: blizzard wind swirl begins, crystals appearing around mage
put_frame(strip, 2, make_frame(
    cx=CX, foot_y=FOOT,
    left_hand_x=CX - 24, left_hand_y=FOOT - 62,
    staff_top_x=CX - 24, staff_top_y=FOOT - 148,
    right_hand_x=CX + 28, right_hand_y=FOOT - 118,
    hat_tilt=-2, orb_bright=0.75,
    orb_color=ICE_ORB,
    ice_ground=True, ice_ground_spread=40, ice_ground_intensity=1.0,
    ice_crystals=[
        (CX - 40, FOOT - 80, 9, 0.0),
        (CX + 38, FOOT - 70, 8, 0.8),
        (CX - 28, FOOT - 130, 7, 0.3),
    ],
    blizzard_cx=CX, blizzard_cy=FOOT - 80,
    blizzard_r=52, blizzard_phase=0.0, blizzard_intensity=0.6,
    frost_particles_cx=CX, frost_particles_cy=FOOT - 80,
    frost_particles_count=10, frost_particles_spread=48, frost_particles_phase=0.0,
))

# Frame 3: full blizzard, mage eyes glowing bright ice-blue, large crystals
put_frame(strip, 3, make_frame(
    cx=CX, foot_y=FOOT,
    left_hand_x=CX - 26, left_hand_y=FOOT - 64,
    staff_top_x=CX - 26, staff_top_y=FOOT - 150,
    right_hand_x=CX + 32, right_hand_y=FOOT - 125,
    hat_tilt=-3, orb_bright=0.90,
    orb_color=ICE_ORB,
    ice_ground=True, ice_ground_spread=48, ice_ground_intensity=1.0,
    ice_crystals=[
        (CX - 45, FOOT - 85, 12, 0.0),
        (CX + 42, FOOT - 75, 11, 0.9),
        (CX - 30, FOOT - 138, 9, 0.4),
        (CX + 18, FOOT - 148, 8, 1.2),
    ],
    blizzard_cx=CX, blizzard_cy=FOOT - 85,
    blizzard_r=58, blizzard_phase=0.8, blizzard_intensity=1.0,
    frost_particles_cx=CX, frost_particles_cy=FOOT - 85,
    frost_particles_count=16, frost_particles_spread=55, frost_particles_phase=0.6,
    eye_color=(140, 220, 255),
))

# Frame 4: ice shard forming at right hand, launching rightward
put_frame(strip, 4, make_frame(
    cx=CX - 4, foot_y=FOOT,
    left_hand_x=CX - 26, left_hand_y=FOOT - 64,
    staff_top_x=CX - 26, staff_top_y=FOOT - 150,
    right_hand_x=CX + 28, right_hand_y=FOOT - 118,
    hat_tilt=-2, orb_bright=1.0,
    orb_color=ICE_ORB,
    ice_ground=True, ice_ground_spread=48, ice_ground_intensity=0.8,
    blizzard_cx=CX, blizzard_cy=FOOT - 85,
    blizzard_r=55, blizzard_phase=1.6, blizzard_intensity=0.8,
    ice_shard_from=(CX + 28, FOOT - 118),
    ice_shard_to=(CX + 95, FOOT - 130),
    ice_shard_width=9,
    frost_particles_cx=CX + 95, frost_particles_cy=FOOT - 130,
    frost_particles_count=8, frost_particles_spread=20, frost_particles_phase=0.3,
    eye_color=(140, 220, 255),
))

# Frame 5: follow-through, frost settling, shard gone
put_frame(strip, 5, make_frame(
    cx=CX, foot_y=FOOT,
    left_hand_x=CX - 22, left_hand_y=FOOT - 62,
    staff_top_x=CX - 22, staff_top_y=FOOT - 146,
    right_hand_x=CX + 24, right_hand_y=FOOT - 108,
    hat_tilt=-1, orb_bright=0.55,
    orb_color=ICE_ORB,
    ice_ground=True, ice_ground_spread=35, ice_ground_intensity=0.5,
    frost_particles_cx=CX, frost_particles_cy=FOOT - 80,
    frost_particles_count=6, frost_particles_spread=30, frost_particles_phase=1.0,
))

save_strip(strip, "cast_ice.png")


# ══════════════════════════════════════════════════════════════════════════════
# 5. cast_lightning.png — 6 frames
# Lightning: staff thrust skyward → arcs crackle → sky flash → bolt strikes down
# ══════════════════════════════════════════════════════════════════════════════
print("Generating cast_lightning.png ...")
strip = make_strip(6)

# Lightning-charged orb (yellow-white)
LIGHTNING_ORB = (220, 240, 80)

# Frame 0: staff thrust skyward overhead, arm up high
put_frame(strip, 0, make_frame(
    cx=CX, foot_y=FOOT,
    left_hand_x=CX + 4, left_hand_y=FOOT - 135,
    staff_top_x=CX + 12, staff_top_y=FOOT - 218,
    right_hand_x=CX + 28, right_hand_y=FOOT - 110,
    hat_tilt=-2, orb_bright=0.50,
    orb_color=LIGHTNING_ORB,
))

# Frame 1: electric sparks begin crackling down the staff
put_frame(strip, 1, make_frame(
    cx=CX, foot_y=FOOT,
    left_hand_x=CX + 4, left_hand_y=FOOT - 138,
    staff_top_x=CX + 12, staff_top_y=FOOT - 220,
    right_hand_x=CX + 28, right_hand_y=FOOT - 112,
    hat_tilt=-3, orb_bright=0.70,
    orb_color=LIGHTNING_ORB,
    electric_orb=True,
    lightning_sparks_cx=CX + 12, lightning_sparks_cy=FOOT - 220,
    lightning_sparks_n=8, lightning_sparks_len=14, lightning_sparks_phase=0.0,
))

# Frame 2: heavy arcing along full staff length, sky starts to brighten
put_frame(strip, 2, make_frame(
    cx=CX, foot_y=FOOT,
    left_hand_x=CX + 4, left_hand_y=FOOT - 138,
    staff_top_x=CX + 12, staff_top_y=FOOT - 222,
    right_hand_x=CX + 30, right_hand_y=FOOT - 114,
    hat_tilt=-4, orb_bright=0.85,
    orb_color=LIGHTNING_ORB,
    electric_orb=True,
    sky_flash=0.3,
    lightning_sparks_cx=CX + 12, lightning_sparks_cy=FOOT - 222,
    lightning_sparks_n=14, lightning_sparks_len=22, lightning_sparks_phase=0.5,
    lightning_from=(CX + 12, FOOT - 222),
    lightning_to=(CX + 12, FOOT - 180),
    lightning_jagged=6, lightning_width=2, lightning_bright=True,
    eye_color=(220, 240, 80),
))

# Frame 3: sky flash, bolt strikes from sky down through orb — impact frame
put_frame(strip, 3, make_frame(
    cx=CX, foot_y=FOOT,
    left_hand_x=CX + 4, left_hand_y=FOOT - 138,
    staff_top_x=CX + 12, staff_top_y=FOOT - 222,
    right_hand_x=CX + 30, right_hand_y=FOOT - 114,
    hat_tilt=-5, orb_bright=1.0,
    orb_color=LIGHTNING_ORB,
    electric_orb=True,
    sky_flash=0.9,
    lightning_from=(CX + 12, 0),
    lightning_to=(CX + 12, FOOT - 222),
    lightning_jagged=10, lightning_width=3, lightning_bright=True,
    lightning_sparks_cx=CX + 12, lightning_sparks_cy=FOOT - 222,
    lightning_sparks_n=16, lightning_sparks_len=28, lightning_sparks_phase=1.0,
    eye_color=(255, 255, 120),
))

# Frame 4: discharge — bolt arcs from orb outward (horizontal), flash fading
put_frame(strip, 4, make_frame(
    cx=CX - 2, foot_y=FOOT,
    left_hand_x=CX + 2, left_hand_y=FOOT - 132,
    staff_top_x=CX + 22, staff_top_y=FOOT - 210,
    right_hand_x=CX + 28, right_hand_y=FOOT - 110,
    hat_tilt=-3, orb_bright=0.95,
    orb_color=LIGHTNING_ORB,
    electric_orb=True,
    sky_flash=0.4,
    lightning_from=(CX + 22, FOOT - 210),
    lightning_to=(CX + 105, FOOT - 175),
    lightning_jagged=8, lightning_width=2, lightning_bright=True,
    lightning_sparks_cx=CX + 105, lightning_sparks_cy=FOOT - 175,
    lightning_sparks_n=10, lightning_sparks_len=16, lightning_sparks_phase=0.3,
    eye_color=(220, 240, 80),
))

# Frame 5: recovery, staff lowering, sparks dissipating
put_frame(strip, 5, make_frame(
    cx=CX, foot_y=FOOT,
    left_hand_x=CX - 4, left_hand_y=FOOT - 110,
    staff_top_x=CX - 10, staff_top_y=FOOT - 192,
    right_hand_x=CX + 24, right_hand_y=FOOT - 105,
    hat_tilt=-1, orb_bright=0.55,
    orb_color=LIGHTNING_ORB,
    lightning_sparks_cx=CX - 10, lightning_sparks_cy=FOOT - 192,
    lightning_sparks_n=6, lightning_sparks_len=10, lightning_sparks_phase=0.8,
))

save_strip(strip, "cast_lightning.png")


# ══════════════════════════════════════════════════════════════════════════════
# 6. cast_fira.png — 6 frames
# Stronger fire: larger flames, brighter eyes, massive final fireball.
# Clearly distinguishable from cast_fire by scale and intensity.
# ══════════════════════════════════════════════════════════════════════════════
print("Generating cast_fira.png ...")
strip = make_strip(6)

# Deep fiery orange-red orb for Fira (hotter than Fire)
FIRA_ORB = (255, 80, 10)

# Frame 0: dramatic pose — staff thrust skyward first, robes billowing
put_frame(strip, 0, make_frame(
    cx=CX, foot_y=FOOT,
    left_hand_x=CX + 6, left_hand_y=FOOT - 132,
    staff_top_x=CX + 16, staff_top_y=FOOT - 212,
    right_hand_x=CX + 26, right_hand_y=FOOT - 108,
    hat_tilt=-2, orb_bright=0.60,
    orb_color=FIRA_ORB,
    body_sway=-3,
))

# Frame 1: intense fire particles erupt from orb, eyes blazing orange
put_frame(strip, 1, make_frame(
    cx=CX, foot_y=FOOT,
    left_hand_x=CX + 8, left_hand_y=FOOT - 136,
    staff_top_x=CX + 18, staff_top_y=FOOT - 218,
    right_hand_x=CX + 28, right_hand_y=FOOT - 112,
    hat_tilt=-2, orb_bright=0.75,
    orb_color=FIRA_ORB,
    fire_particles_cx=CX + 18, fire_particles_cy=FOOT - 218,
    fire_particles_count=18, fire_particles_spread=30,
    fire_particles_phase=0.0,
    eye_color=(255, 100, 10),
))

# Frame 2: massive fire spiral forms — three-arm spiral larger than cast_fire
put_frame(strip, 2, make_frame(
    cx=CX - 2, foot_y=FOOT,
    left_hand_x=CX + 4, left_hand_y=FOOT - 130,
    staff_top_x=CX + 30, staff_top_y=FOOT - 200,
    right_hand_x=CX + 22, right_hand_y=FOOT - 115,
    hat_tilt=2, orb_bright=0.90,
    orb_color=FIRA_ORB,
    fire_spiral_cx=CX + 30, fire_spiral_cy=FOOT - 200,
    fire_spiral_r=38, fire_spiral_arms=4, fire_spiral_phase=0.0,
    fire_particles_cx=CX + 30, fire_particles_cy=FOOT - 200,
    fire_particles_count=20, fire_particles_spread=40,
    fire_particles_phase=0.3,
    eye_color=(255, 80, 10),
))

# Frame 3: full power — enormous fireball at orb tip, mage leans forward
put_frame(strip, 3, make_frame(
    cx=CX - 6, foot_y=FOOT,
    left_hand_x=CX - 8, left_hand_y=FOOT - 118,
    staff_top_x=CX + 50, staff_top_y=FOOT - 172,
    right_hand_x=CX + 16, right_hand_y=FOOT - 118,
    hat_tilt=5, orb_bright=1.0,
    orb_color=FIRA_ORB,
    fireball_x=CX + 50, fireball_y=FOOT - 172, fireball_r=22,
    fire_spiral_cx=CX + 50, fire_spiral_cy=FOOT - 172,
    fire_spiral_r=30, fire_spiral_arms=4, fire_spiral_phase=0.8,
    fire_particles_cx=CX + 50, fire_particles_cy=FOOT - 172,
    fire_particles_count=24, fire_particles_spread=50,
    fire_particles_phase=0.6,
    eye_color=(255, 80, 10),
    body_sway=5,
))

# Frame 4: massive fireball launches — huge fire burst in top-right
put_frame(strip, 4, make_frame(
    cx=CX - 6, foot_y=FOOT,
    left_hand_x=CX - 8, left_hand_y=FOOT - 118,
    staff_top_x=CX + 50, staff_top_y=FOOT - 172,
    right_hand_x=CX + 16, right_hand_y=FOOT - 118,
    hat_tilt=5, orb_bright=1.0,
    orb_color=FIRA_ORB,
    fire_burst_x=CX + 100, fire_burst_y=FOOT - 148,
    fire_burst_size=38, fire_burst_power=1.0,
    fire_particles_cx=CX + 100, fire_particles_cy=FOOT - 148,
    fire_particles_count=20, fire_particles_spread=45,
    fire_particles_phase=0.9,
    eye_color=(255, 80, 10),
    body_sway=5,
))

# Frame 5: heavy follow-through — mage pushed back, embers everywhere
put_frame(strip, 5, make_frame(
    cx=CX + 4, foot_y=FOOT + 2,
    left_hand_x=CX - 20, left_hand_y=FOOT - 105,
    staff_top_x=CX - 28, staff_top_y=FOOT - 185,
    right_hand_x=CX + 25, right_hand_y=FOOT - 100,
    hat_tilt=2, orb_bright=0.60,
    orb_color=FIRA_ORB,
    fire_particles_cx=CX, fire_particles_cy=FOOT - 130,
    fire_particles_count=12, fire_particles_spread=35,
    fire_particles_phase=1.5,
    body_sway=-4,
))

save_strip(strip, "cast_fira.png")


# ══════════════════════════════════════════════════════════════════════════════
# Final report
# ══════════════════════════════════════════════════════════════════════════════
print("\nAll 6 extended mage animations generated successfully.")
print("Output directory:", OUT_DIR)

animations_generated = [
    "advance.png  (4 frames, 1024x256) — levitation + arcane rune ring",
    "defer.png    (4 frames, 1024x256) — cloak wrap + arcane barrier",
    "cast_fire.png (6 frames, 1536x256) — fire spell with spiral flames",
    "cast_ice.png (6 frames, 1536x256) — ice spell with crystals + blizzard",
    "cast_lightning.png (6 frames, 1536x256) — lightning bolt from sky",
    "cast_fira.png (6 frames, 1536x256) — powered fire, massive fireball",
]
print("\nGenerated:")
for a in animations_generated:
    print(f"  {a}")
