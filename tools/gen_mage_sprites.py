#!/usr/bin/env python3
"""
Mage sprite generator for Cowardly Irregular.
FF Black Mage inspired: deep blue robes, tall pointed hat, glowing cyan eyes, crystal staff.
256x256 frames, transparent background, matching fighter art style.
"""

from PIL import Image, ImageDraw
import os
import math

OUT_DIR = "/home/struktured/projects/cowardly-irregular/assets/sprites/jobs/mage"
os.makedirs(OUT_DIR, exist_ok=True)

FRAME_W = 256
FRAME_H = 256

# ── Colour palette ──────────────────────────────────────────────────────────
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

# Orb
C_ORB_CORE    = (230, 255, 255, 255)
C_ORB_MID     = (55,  215, 255, 255)
C_ORB_DK      = (8,   118, 178, 255)

# Boots
C_BOOT_LT     = (115, 85,  55,  255)
C_BOOT_MID    = (78,  56,  32,  255)
C_BOOT_DK     = (42,  28,  12,  255)

# Magic effects
C_MAGIC_WHITE = (255, 255, 255, 255)
C_MAGIC_CYAN  = (80,  220, 255, 255)
C_MAGIC_BLUE  = (20,  140, 220, 200)
C_MAGIC_FAINT = (0,   80,  160, 80)

# Potion
C_POTION_LT   = (80,  220, 100, 255)
C_POTION_MID  = (50,  170, 75,  255)
C_POTION_CORK = (140, 100, 60,  255)

TRANSPARENT   = (0, 0, 0, 0)


# ── Drawing primitives ───────────────────────────────────────────────────────

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
    """Bresenham line with optional width."""
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


# ── Staff ─────────────────────────────────────────────────────────────────────

def draw_staff(img, x0, y0, x1, y1, orb_bright=0.5):
    """Draw wooden staff from (x0,y0) bottom to (x1,y1) top with crystal orb."""
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
        # shade darker toward base
        if t > 0.8:
            col = C_STAFF_DK
        elif t > 0.4:
            col = C_STAFF_MID
        else:
            col = C_STAFF_LT
        # 2-pixel wide staff
        # perpendicular offset
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
    # Glow aura
    glow_r = int(8 + 6 * orb_bright)
    glow(img, ox, oy, glow_r, (0, 180, 230))
    # Orb body
    circle_filled(img, ox, oy, orb_r, C_ORB_DK)
    circle_filled(img, ox, oy, orb_r - 1, C_ORB_MID)
    circle_filled(img, ox, oy, orb_r - 3, (int(55 + 100 * orb_bright), 215, 255, 255))
    # Highlight
    px(img, ox - 2, oy - 2, C_ORB_CORE)
    px(img, ox - 1, oy - 2, C_ORB_CORE)
    px(img, ox - 2, oy - 1, C_ORB_CORE)
    # Outline
    circle_outline(img, ox, oy, orb_r, C_OUTLINE)


# ── Hat ───────────────────────────────────────────────────────────────────────

def draw_hat(img, brim_cx, brim_cy, tilt_px=0):
    """
    Draw pointed wizard hat.
    brim_cx, brim_cy = centre of brim.
    tilt_px = how many pixels the tip is offset horizontally from brim_cx.
    """
    hat_h = 55
    tip_x = brim_cx + tilt_px
    tip_y = brim_cy - hat_h

    # Cone body — draw row by row from tip down to brim
    for y in range(tip_y, brim_cy):
        t = (y - tip_y) / hat_h          # 0=tip, 1=brim
        half_w = max(int(t * 15), 1)
        # lean interpolates tip offset to 0 at brim
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
        # Outline edges
        px(img, cx_row - half_w - 1, y, C_OUTLINE)
        px(img, cx_row + half_w + 1, y, C_OUTLINE)

    # Tip pixel
    px(img, tip_x, tip_y, C_HAT_LT)
    px(img, tip_x, tip_y - 1, C_OUTLINE)

    # Band / ribbon near brim
    band_y = brim_cy - 6
    for by in range(band_y, band_y + 3):
        t = (by - band_y) / 2.0
        half_w = max(int((1.0 - (brim_cy - by) / hat_h) * 15), 1)
        cx_band = int(brim_cx + tilt_px * (1.0 - (brim_cy - by) / hat_h))
        for x in range(cx_band - half_w - 1, cx_band + half_w + 2):
            col = C_TRIM_LT if by == band_y else (C_TRIM_MID if by == band_y + 1 else C_TRIM_DK)
            px(img, x, by, col)

    # Brim
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


def draw_hat_on_ground(img, cx, cy, rot_deg=30):
    """Fallen hat on ground."""
    # Draw a simplified squashed hat
    a = math.radians(rot_deg)
    for i in range(-10, 25):
        bx = cx + int(math.cos(a) * i)
        by = cy + int(math.sin(a) * i)
        half_w = max(1, int(5 + (i + 10) / 5))
        perp_x = -math.sin(a)
        perp_y = math.cos(a)
        for j in range(-half_w, half_w + 1):
            fx = int(bx + perp_x * j)
            fy = int(by + perp_y * j)
            dist = abs(j) / half_w
            if dist < 0.3:
                col = C_HAT_LT
            elif dist < 0.7:
                col = C_HAT_MID
            else:
                col = C_HAT_DK
            px(img, fx, fy, col)
    # Brim
    brim_cx = cx - 8
    brim_cy = cy + 2
    hline(img, brim_cx - 18, brim_cx + 6, brim_cy, C_HAT_BRIM_LT)
    hline(img, brim_cx - 18, brim_cx + 6, brim_cy + 1, C_HAT_BRIM_MID)
    hline(img, brim_cx - 19, brim_cx + 7, brim_cy - 1, C_OUTLINE)
    hline(img, brim_cx - 19, brim_cx + 7, brim_cy + 2, C_OUTLINE)


# ── Robes ─────────────────────────────────────────────────────────────────────

def draw_robes(img, cx, waist_y, hem_y, bob=0, sway=0):
    """
    Draw bell-shaped robes.
    cx = horizontal centre, waist_y = top of robe, hem_y = bottom of robe.
    bob = extra vertical bob (adds to hem_y), sway = horizontal sway of hem.
    """
    hem_y = hem_y + bob
    sway_cx = cx + sway

    for y in range(waist_y, hem_y + 1):
        t = (y - waist_y) / max(hem_y - waist_y, 1)
        # Bell flare: starts narrow at waist, widens at hem
        half_w = int(7 + 25 * (t ** 0.7))
        half_w = min(half_w, 30)
        row_cx = cx + int(sway * t * 0.5)  # sway increases toward hem

        xl = row_cx - half_w
        xr = row_cx + half_w

        for x in range(xl + 1, xr):
            dist = abs(x - row_cx) / half_w
            # Three-tone shading: lit center, mid sides, dark edges
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

        # Fold detail lines
        if t > 0.2 and t < 0.9:
            if (y % 8) < 2:
                fold_x_l = row_cx - int(half_w * 0.5)
                fold_x_r = row_cx + int(half_w * 0.5)
                px(img, fold_x_l, y, C_ROBE_FOLD)
                px(img, fold_x_r, y, C_ROBE_FOLD)
                if (y % 8) == 0:
                    px(img, fold_x_l - 1, y, C_ROBE_DK)
                    px(img, fold_x_r + 1, y, C_ROBE_DK)

    # Hem trim (horizontal band at hem)
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

    # Vertical center trim stripe
    for y in range(waist_y + 12, hem_y - 5):
        if (y % 3) < 2:
            px(img, cx,     y, C_TRIM_MID)
            px(img, cx + 1, y, C_TRIM_LT if (y % 3) == 0 else C_TRIM_MID)

    return xl, xr  # return robe edges at hem for boot positioning


# ── Boots ─────────────────────────────────────────────────────────────────────

def draw_boots(img, cx, foot_y, spread=10, bob=0):
    """Draw two brown leather boots at feet."""
    foot_y = foot_y + bob
    for side in (-1, 1):
        bx = cx + side * spread
        # Boot shaft
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
        # Boot sole / toe
        sole_y = foot_y
        toe_w = int(8 + (1 if side == -1 else 0))  # left boot slightly wider
        hline(img, bx - toe_w, bx + toe_w, sole_y, C_BOOT_MID)
        hline(img, bx - toe_w, bx + toe_w, sole_y - 1, C_BOOT_LT)
        hline(img, bx - toe_w - 1, bx + toe_w + 1, sole_y + 1, C_OUTLINE)
        px(img, bx - toe_w - 1, sole_y, C_OUTLINE)
        px(img, bx + toe_w + 1, sole_y, C_OUTLINE)


# ── Body / chest / shoulders ──────────────────────────────────────────────────

def draw_chest(img, cx, chest_y):
    """Draw upper robe chest/body area above main robe."""
    # Main chest block
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

    # Collar trim
    collar_y = chest_y + 1
    hline(img, cx - 8, cx + 8, collar_y, C_TRIM_LT)
    hline(img, cx - 9, cx + 9, collar_y + 1, C_TRIM_MID)
    hline(img, cx - 9, cx + 9, collar_y + 2, C_TRIM_DK)

    # Shoulder pads
    for side in (-1, 1):
        sx = cx + side * 13
        shoulder_w = 10
        for y in range(chest_y + 2, chest_y + 12):
            hline(img, sx - shoulder_w // 2, sx + shoulder_w // 2, y,
                  C_ROBE_LT if y < chest_y + 6 else C_ROBE_MID)
        # Shoulder trim
        hline(img, sx - shoulder_w // 2, sx + shoulder_w // 2, chest_y + 2, C_TRIM_MID)
        px(img, sx - shoulder_w // 2 - 1, chest_y + 2, C_OUTLINE)
        px(img, sx + shoulder_w // 2 + 1, chest_y + 2, C_OUTLINE)


# ── Face ──────────────────────────────────────────────────────────────────────

def draw_face(img, cx, cy, eyes_open=True, half_closed=False):
    """
    Draw dark shadowed face with glowing cyan eyes.
    cx, cy = centre of face circle.
    """
    face_r = 11
    # Dark face area
    circle_filled(img, cx, cy, face_r, C_FACE)
    circle_filled(img, cx, cy, face_r - 2, C_FACE_DK)
    circle_outline(img, cx, cy, face_r, C_OUTLINE)
    circle_outline(img, cx, cy, face_r + 1, C_OUTLINE)

    if eyes_open:
        ey = cy + 1
        # Left eye
        lx = cx - 4
        glow(img, lx, ey, 5, (0, 200, 240))
        hline(img, lx - 2, lx + 2, ey, C_EYE_BRIGHT)
        px(img, lx - 1, ey - 1, C_EYE_CORE)
        px(img, lx,     ey - 1, C_EYE_CORE)
        px(img, lx + 1, ey - 1, C_EYE_CORE)
        # Right eye
        rx = cx + 4
        glow(img, rx, ey, 5, (0, 200, 240))
        hline(img, rx - 2, rx + 2, ey, C_EYE_BRIGHT)
        px(img, rx - 1, ey - 1, C_EYE_CORE)
        px(img, rx,     ey - 1, C_EYE_CORE)
        px(img, rx + 1, ey - 1, C_EYE_CORE)
    elif half_closed:
        ey = cy + 2
        lx = cx - 4
        rx = cx + 4
        hline(img, lx - 1, lx + 1, ey, C_EYE_DIM)
        hline(img, rx - 1, rx + 1, ey, C_EYE_DIM)


# ── Arms ──────────────────────────────────────────────────────────────────────

def draw_arm(img, shoulder_x, shoulder_y, hand_x, hand_y, side='left'):
    """Draw a robed arm from shoulder to hand."""
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
        # Arm narrows toward hand
        half_w = max(1, int(4 - t * 2))
        for w in range(-half_w, half_w + 1):
            dist = abs(w) / max(half_w, 1)
            if side == 'left':
                col = C_ROBE_DK if dist > 0.5 else (C_ROBE_LT if dist < 0.2 else C_ROBE_MID)
            else:
                col = C_ROBE_MID if dist > 0.5 else (C_ROBE_LT if dist < 0.2 else C_ROBE_MID)
            # Offset perpendicular to arm direction
            if abs(dy) >= abs(dx):
                px(img, ax + w, ay, col)
            else:
                px(img, ax, ay + w, col)
        # Outline
        if abs(dy) >= abs(dx):
            px(img, ax - half_w - 1, ay, C_OUTLINE)
            px(img, ax + half_w + 1, ay, C_OUTLINE)
        else:
            px(img, ax, ay - half_w - 1, C_OUTLINE)
            px(img, ax, ay + half_w + 1, C_OUTLINE)


def draw_hand(img, hx, hy):
    """Draw a small pale hand."""
    circle_filled(img, hx, hy, 4, C_SKIN_MID)
    px(img, hx - 1, hy - 1, C_SKIN_LT)
    px(img, hx,     hy - 1, C_SKIN_LT)
    circle_outline(img, hx, hy, 4, C_OUTLINE)


# ── Magic effects ─────────────────────────────────────────────────────────────

def draw_magic_burst(img, cx, cy, size=25, bright=1.0):
    """Big magic explosion at (cx, cy). Fully opaque filled disc with sparks."""
    # Outer glow ring (opaque fill from dark blue to cyan)
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
                    r = int(20  + t * 0)
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

    # Spark lines
    for ang_deg in range(0, 360, 24):
        a = math.radians(ang_deg)
        r_start = int(size * 0.35)
        r_end   = int(size * 1.1)
        for r in range(r_start, r_end + 1, 1):
            sx = cx + int(math.cos(a) * r)
            sy = cy + int(math.sin(a) * r)
            t  = (r - r_start) / (r_end - r_start)
            if t < 0.5:
                col = C_MAGIC_WHITE
            else:
                col = C_MAGIC_CYAN
            px(img, sx, sy, col)

    # Hard outline ring
    circle_outline(img, cx, cy, size + 1, C_OUTLINE)


def draw_magic_circle(img, cx, cy, r, dot_every=15):
    """Draw an arcane circle (for cast wind-up)."""
    # Circle
    circle_outline(img, cx, cy, r, C_MAGIC_CYAN)
    circle_outline(img, cx, cy, r + 1, (0, 140, 200, 120))
    # Dots along circle
    for ang_deg in range(0, 360, dot_every):
        a = math.radians(ang_deg)
        dx = cx + int(math.cos(a) * r)
        dy = cy + int(math.sin(a) * r)
        px(img, dx, dy, C_EYE_CORE)


def draw_barrier(img, cx, cy, r, intensity=1.0):
    """Draw magical shield/barrier arc."""
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
    # Shimmer dots
    for ang_deg in range(-65, 66, 18):
        a = math.radians(ang_deg)
        sx = cx + int(math.cos(a) * r)
        sy = cy + int(math.sin(a) * r)
        px(img, sx, sy, C_EYE_CORE)


def draw_potion(img, px_c, py_c, raised=False):
    """Draw a green potion bottle at (px_c, py_c) top-centre."""
    # Body
    filled_rect(img, px_c - 4, py_c,      px_c + 4, py_c + 14, C_POTION_MID)
    filled_rect(img, px_c - 3, py_c + 1,  px_c + 3, py_c + 13, C_POTION_LT)
    px(img, px_c - 2, py_c + 2, (180, 255, 200, 255))  # highlight
    # Neck
    filled_rect(img, px_c - 2, py_c - 5, px_c + 2, py_c - 1, C_TRIM_MID)
    # Cork
    filled_rect(img, px_c - 2, py_c - 7, px_c + 2, py_c - 6, C_POTION_CORK)
    # Outline
    for y in range(py_c - 7, py_c + 15):
        for x in [px_c - 5, px_c + 5]:
            if py_c <= y <= py_c + 14:
                px(img, x, y, C_OUTLINE)
    hline(img, px_c - 4, px_c + 4, py_c - 1,  C_OUTLINE)
    hline(img, px_c - 4, px_c + 4, py_c + 14, C_OUTLINE)
    if raised:
        # Sparkle
        for ang_deg in [0, 45, 90, 135, 180, 225, 270, 315]:
            a = math.radians(ang_deg)
            for ri in [10, 16]:
                sx = px_c + int(math.cos(a) * ri)
                sy = py_c + int(math.sin(a) * ri)
                col = C_MAGIC_CYAN if ri == 10 else C_EYE_CORE
                px(img, sx, sy, col)


# ══════════════════════════════════════════════════════════════════════════════
# Master frame builder
# ══════════════════════════════════════════════════════════════════════════════

def make_frame(**kw):
    """
    Draw a full mage frame and return the Image.

    Key parameters (all optional with defaults):
      cx, foot_y               — anchor (centre x, foot y)
      hat_tilt                 — tip offset from hat centre (pixels)
      body_sway                — robe cx offset
      robe_bob                 — hem drop offset (positive = lower)
      boot_spread              — half-distance between boots
      chest_y                  — top of chest (computed from foot_y if not set)

      left_hand_x/y            — left hand position
      right_hand_x/y           — right hand position
      staff_top_x/y            — staff tip (orb) position
      orb_bright               — 0..1 orb brightness

      eyes_open                — bool
      half_closed              — bool (eyes half-closed for hit/daze)

      # Optional overlays
      magic_burst_x/y/size     — if set, draw explosion at that pos
      magic_circle_x/y/r       — arcane circle
      barrier                  — bool: draw shield in front
      barrier_cx/cy/r
      potion_x/y               — if set, draw potion
      potion_raised            — bool
      staff_visible            — bool (default True)

      # Dead mode
      dead                     — bool: draw collapsed mage
      dead_rot                 — angle in radians (0=upright, pi/2=fully prone)
      hat_off_x/y              — if set, hat is drawn at this position instead
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
    dead     = kw.get('dead', False)
    staff_vis= kw.get('staff_visible', True)

    if dead:
        _draw_dead(img, kw)
        return img

    # Derived positions
    rcx      = cx + sway                     # robe centre x
    waist_y  = foot_y - 108                  # top of robe
    hem_y    = foot_y - 20                   # bottom of robe (above boots)
    chest_y  = kw.get('chest_y', waist_y - 2)
    face_cy  = waist_y - 20

    # Left hand default: lower-left, holds staff
    lhx = kw.get('left_hand_x',  cx - 22)
    lhy = kw.get('left_hand_y',  waist_y + 30)
    # Right hand default: lower-right, gesture hand
    rhx = kw.get('right_hand_x', cx + 20)
    rhy = kw.get('right_hand_y', waist_y + 30)
    # Staff top default: upper-left near mage
    stx = kw.get('staff_top_x',  cx - 28)
    sty = kw.get('staff_top_y',  waist_y - 55)

    # Shoulder positions
    lshx = cx - 18
    rshy = waist_y + 5
    rshx = cx + 18

    # ── Draw order: back-to-front ─────────────────────────────────────────────

    # 1. Staff (behind body)
    if staff_vis:
        draw_staff(img, lhx, lhy, stx, sty, orb_br)

    # 2. Boots
    draw_boots(img, rcx, foot_y + bob, spread=bspr, bob=0)

    # 3. Robes
    draw_robes(img, rcx, waist_y, hem_y, bob=bob, sway=sway // 2)

    # 4. Chest / shoulders
    draw_chest(img, rcx, chest_y)

    # 5. Left arm
    draw_arm(img, lshx, rshy, lhx, lhy, side='left')
    draw_hand(img, lhx, lhy)

    # 6. Right arm
    draw_arm(img, rshx, rshy, rhx, rhy, side='right')
    draw_hand(img, rhx, rhy)

    # 7. Face
    draw_face(img, cx + 2, face_cy, eyes_open=eyes_open, half_closed=half_cl)

    # 8. Hat
    hat_off_x = kw.get('hat_off_x', None)
    if hat_off_x is not None:
        draw_hat_on_ground(img, hat_off_x, kw.get('hat_off_y', foot_y))
    else:
        draw_hat(img, cx + 1, face_cy - 13, tilt_px=hat_tilt)

    # ── Overlays ──────────────────────────────────────────────────────────────
    if 'magic_burst_x' in kw:
        draw_magic_burst(img, kw['magic_burst_x'], kw['magic_burst_y'],
                         size=kw.get('magic_burst_size', 28),
                         bright=kw.get('magic_burst_bright', 1.0))

    if 'magic_circle_x' in kw:
        draw_magic_circle(img, kw['magic_circle_x'], kw['magic_circle_y'],
                          r=kw.get('magic_circle_r', 20))

    if kw.get('barrier', False):
        bcx = kw.get('barrier_cx', cx + 35)
        bcy = kw.get('barrier_cy', waist_y + 35)
        br  = kw.get('barrier_r', 38)
        draw_barrier(img, bcx, bcy, br, intensity=kw.get('barrier_intensity', 1.0))

    if 'potion_x' in kw:
        draw_potion(img, kw['potion_x'], kw['potion_y'],
                    raised=kw.get('potion_raised', False))

    return img


def _draw_dead(img, kw):
    """
    Draw a collapsed mage. Uses a scanline polygon fill to avoid stripe artifacts.
    rot=0: standing, rot=pi/2: fully prone to the right.
    """
    cx        = kw.get('cx', FRAME_W // 2)
    foot_y    = kw.get('foot_y', FRAME_H - 30)
    rot       = kw.get('dead_rot', math.pi / 2)
    hat_off_x = kw.get('hat_off_x', None)
    hat_off_y = kw.get('hat_off_y', foot_y)

    # Body axis: pivot at feet, tip goes in direction (sin_r, -cos_r)
    cos_r  = math.cos(rot)
    sin_r  = math.sin(rot)
    body_h = 88
    pivot_x = cx
    pivot_y = foot_y - 8

    # Generate a polygon for the robe silhouette.
    # Along the body axis from t=0 (feet/wide) to t=1 (head/narrow).
    # At each t, the half-width in the perpendicular direction.
    # Perpendicular direction: (cos_r, sin_r)
    perp_x =  cos_r
    perp_y =  sin_r

    def body_pt(t):
        """Point along body axis at parameter t."""
        return (pivot_x + sin_r * body_h * t,
                pivot_y - cos_r * body_h * t)

    def robe_hw(t):
        """Half-width of robe at body parameter t (0=feet, 1=head)."""
        # Wider at hem (t=0.15..0.3), narrower at waist (t=0.5), widens again at shoulders
        return 6 + 22 * max(0.0, 1.0 - t) ** 0.55

    # Build polygon: left edge (t 0..1), right edge (t 1..0)
    n_seg = 60
    poly_left  = []
    poly_right = []
    for i in range(n_seg + 1):
        t  = i / n_seg
        bx, by = body_pt(t)
        hw = robe_hw(t)
        poly_left.append( (bx - perp_x * hw, by - perp_y * hw) )
        poly_right.append((bx + perp_x * hw, by + perp_y * hw) )

    poly = poly_left + list(reversed(poly_right))

    # Scanline fill using the polygon
    # Determine bounding box
    all_x = [p[0] for p in poly]
    all_y = [p[1] for p in poly]
    min_y = max(0,        int(min(all_y)) - 1)
    max_y = min(FRAME_H - 1, int(max(all_y)) + 1)

    def scanline_x_for_poly(scan_y, polygon):
        """Return sorted list of x intersections at scan_y."""
        intersections = []
        n = len(polygon)
        for i in range(n):
            x0, y0 = polygon[i]
            x1, y1 = polygon[(i + 1) % n]
            if (y0 <= scan_y < y1) or (y1 <= scan_y < y0):
                if abs(y1 - y0) < 0.001:
                    continue
                t_inter = (scan_y - y0) / (y1 - y0)
                xi = x0 + t_inter * (x1 - x0)
                intersections.append(xi)
        intersections.sort()
        return intersections

    for sy in range(min_y, max_y + 1):
        xs = scanline_x_for_poly(sy + 0.5, poly)
        for k in range(0, len(xs) - 1, 2):
            xl = int(xs[k])
            xr = int(xs[k + 1])
            for sx in range(xl, xr + 1):
                # Shade based on position across the body
                # Find closest point on body axis for this pixel
                rel_x = sx - pivot_x
                rel_y = sy - pivot_y
                # Project onto perpendicular to get transverse distance
                t_axis = (rel_x * sin_r - rel_y * cos_r) / body_h
                t_axis = max(0.0, min(1.0, t_axis))
                hw = robe_hw(t_axis)
                # Transverse signed distance from centre
                trans = rel_x * perp_x + rel_y * perp_y
                dist = abs(trans) / max(hw, 1)
                if dist < 0.20:
                    col = C_ROBE_LT
                elif dist < 0.55:
                    col = C_ROBE_MID
                elif dist < 0.78:
                    col = C_ROBE_FOLD
                else:
                    col = C_ROBE_DK
                px(img, sx, sy, col)

    # Outline the polygon
    n = len(poly)
    for i in range(n):
        x0, y0 = poly[i]
        x1, y1 = poly[(i + 1) % n]
        draw_line(img, int(x0), int(y0), int(x1), int(y1), C_OUTLINE)

    # Hem trim: a stripe near the feet end (t ~ 0.05..0.12)
    for t_trim in [0.05, 0.08, 0.11]:
        bx, by = body_pt(t_trim)
        hw = robe_hw(t_trim) + 1
        lx = int(bx - perp_x * hw)
        ly = int(by - perp_y * hw)
        rx = int(bx + perp_x * hw)
        ry = int(by + perp_y * hw)
        draw_line(img, lx, ly, rx, ry, C_TRIM_MID)

    # Centre stripe
    for t_stripe in [i / 40.0 for i in range(2, 39)]:
        bx, by = body_pt(t_stripe)
        c = C_TRIM_MID if int(t_stripe * 30) % 3 < 2 else C_TRIM_LT
        px(img, int(bx), int(by), c)

    # Head at top end (t=1)
    head_x = int(pivot_x + sin_r * body_h)
    head_y = int(pivot_y - cos_r * body_h)
    draw_face(img, head_x, head_y, eyes_open=False, half_closed=False)

    # Hat
    hat_tilt_dead = int(math.degrees(rot) * 0.15)
    if hat_off_x is not None:
        draw_hat_on_ground(img, hat_off_x, hat_off_y,
                           rot_deg=int(math.degrees(rot) * 0.5 + 15))
    else:
        draw_hat(img, head_x, head_y - 13, tilt_px=hat_tilt_dead)

    # Staff lying on ground nearby
    staff_y  = foot_y
    staff_x0 = pivot_x - 15
    staff_x1 = pivot_x + 65
    draw_staff(img, staff_x0, staff_y, staff_x1, staff_y - 6, orb_bright=0.1)


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
    print(f"  Saved {path}  ({strip.width}x{strip.height})")
    return path


# ══════════════════════════════════════════════════════════════════════════════
# Constant character anchor
# ══════════════════════════════════════════════════════════════════════════════
CX    = FRAME_W // 2      # 128
FOOT  = FRAME_H - 32      # 224


# ══════════════════════════════════════════════════════════════════════════════
# 1. idle.png — 2 frames
# ══════════════════════════════════════════════════════════════════════════════
print("Generating idle.png ...")
strip = make_strip(2)

# Frame 0: upright neutral pose, staff angled slightly left
put_frame(strip, 0, make_frame(
    cx=CX, foot_y=FOOT,
    left_hand_x=CX - 26, left_hand_y=FOOT - 100,
    staff_top_x=CX - 35, staff_top_y=FOOT - 185,
    right_hand_x=CX + 22, right_hand_y=FOOT - 95,
    orb_bright=0.4
))

# Frame 1: subtle bob (2px down), orb gently pulsing brighter
put_frame(strip, 1, make_frame(
    cx=CX, foot_y=FOOT + 2,
    robe_bob=2,
    left_hand_x=CX - 26, left_hand_y=FOOT - 98,
    staff_top_x=CX - 34, staff_top_y=FOOT - 182,
    right_hand_x=CX + 22, right_hand_y=FOOT - 93,
    orb_bright=0.75,
    hat_tilt=-1
))

save_strip(strip, "idle.png")


# ══════════════════════════════════════════════════════════════════════════════
# 2. walk.png — 6 frames
# ══════════════════════════════════════════════════════════════════════════════
print("Generating walk.png ...")
strip = make_strip(6)

# Walking cycle: legs stride, robes sway, staff bobs
# Left hand holds staff; right hand swings
walk_data = [
    # (cx_off, bob, sway, lhx, lhy, rhx, rhy, stx, sty, htilt, orb)
    ( 0,  0,  0,  CX-26, FOOT-100,  CX+22, FOOT-95,   CX-35, FOOT-184,  0,  0.35),
    ( 0,  3, -2,  CX-25, FOOT- 98,  CX+24, FOOT-90,   CX-33, FOOT-181, -1,  0.40),
    ( 0,  5, -4,  CX-26, FOOT- 96,  CX+26, FOOT-88,   CX-34, FOOT-178, -2,  0.35),
    ( 0,  3,  0,  CX-26, FOOT- 99,  CX+22, FOOT-92,   CX-35, FOOT-182,  0,  0.40),
    ( 0,  0,  2,  CX-27, FOOT-100,  CX+20, FOOT-95,   CX-36, FOOT-184,  1,  0.35),
    ( 0,  3,  4,  CX-26, FOOT- 98,  CX+18, FOOT-90,   CX-34, FOOT-181,  2,  0.38),
]
for i, (cx_off, bob, sway, lhx, lhy, rhx, rhy, stx, sty, htilt, orb) in enumerate(walk_data):
    put_frame(strip, i, make_frame(
        cx=CX + cx_off, foot_y=FOOT,
        robe_bob=bob, body_sway=sway,
        left_hand_x=lhx, left_hand_y=lhy,
        right_hand_x=rhx, right_hand_y=rhy,
        staff_top_x=stx, staff_top_y=sty,
        hat_tilt=htilt, orb_bright=orb
    ))

save_strip(strip, "walk.png")


# ══════════════════════════════════════════════════════════════════════════════
# 3. attack.png — 6 frames
# Staff thrust forward, magic blast from orb
# ══════════════════════════════════════════════════════════════════════════════
print("Generating attack.png ...")
strip = make_strip(6)

# Frame 0: wind-up — staff pulled back behind mage
put_frame(strip, 0, make_frame(
    cx=CX, foot_y=FOOT,
    left_hand_x=CX - 30, left_hand_y=FOOT - 95,
    staff_top_x=CX - 50, staff_top_y=FOOT - 170,
    right_hand_x=CX + 20, right_hand_y=FOOT - 100,
    hat_tilt=-3, orb_bright=0.5, body_sway=-4
))

# Frame 1: staff swings forward / levels out
put_frame(strip, 1, make_frame(
    cx=CX, foot_y=FOOT,
    left_hand_x=CX - 22, left_hand_y=FOOT - 100,
    staff_top_x=CX + 10, staff_top_y=FOOT - 155,
    right_hand_x=CX + 18, right_hand_y=FOOT - 102,
    hat_tilt=0, orb_bright=0.7, body_sway=2
))

# Frame 2: staff thrust forward, lean into it
put_frame(strip, 2, make_frame(
    cx=CX - 4, foot_y=FOOT,
    left_hand_x=CX - 14, left_hand_y=FOOT - 102,
    staff_top_x=CX + 50, staff_top_y=FOOT - 135,
    right_hand_x=CX + 14, right_hand_y=FOOT - 105,
    hat_tilt=4, orb_bright=0.95, body_sway=6
))

# Frame 3: magic burst fires from orb tip
burst_x = CX + 88
burst_y = FOOT - 138
put_frame(strip, 3, make_frame(
    cx=CX - 4, foot_y=FOOT,
    left_hand_x=CX - 14, left_hand_y=FOOT - 102,
    staff_top_x=CX + 50, staff_top_y=FOOT - 135,
    right_hand_x=CX + 14, right_hand_y=FOOT - 105,
    hat_tilt=5, orb_bright=1.0, body_sway=6,
    magic_burst_x=burst_x, magic_burst_y=burst_y, magic_burst_size=32
))

# Frame 4: recoil — pushed back slightly
put_frame(strip, 4, make_frame(
    cx=CX + 4, foot_y=FOOT + 1,
    left_hand_x=CX - 20, left_hand_y=FOOT - 100,
    staff_top_x=CX - 5, staff_top_y=FOOT - 168,
    right_hand_x=CX + 22, right_hand_y=FOOT - 97,
    hat_tilt=2, orb_bright=0.65, body_sway=-3
))

# Frame 5: recovery to normal
put_frame(strip, 5, make_frame(
    cx=CX, foot_y=FOOT,
    left_hand_x=CX - 26, left_hand_y=FOOT - 100,
    staff_top_x=CX - 35, staff_top_y=FOOT - 183,
    right_hand_x=CX + 22, right_hand_y=FOOT - 95,
    hat_tilt=0, orb_bright=0.45
))

save_strip(strip, "attack.png")


# ══════════════════════════════════════════════════════════════════════════════
# 4. hit.png — 4 frames
# ══════════════════════════════════════════════════════════════════════════════
print("Generating hit.png ...")
strip = make_strip(4)

# Frame 0: impact — pushed back/right, staggering
put_frame(strip, 0, make_frame(
    cx=CX + 10, foot_y=FOOT + 4,
    robe_bob=4,
    left_hand_x=CX - 16, left_hand_y=FOOT - 95,
    staff_top_x=CX - 32, staff_top_y=FOOT - 170,
    right_hand_x=CX + 30, right_hand_y=FOOT - 90,
    hat_tilt=-4, orb_bright=0.2, body_sway=-8,
    eyes_open=False, half_closed=True
))

# Frame 1: flinch hard — hunched, staff dropped down
put_frame(strip, 1, make_frame(
    cx=CX + 14, foot_y=FOOT + 6,
    robe_bob=6,
    left_hand_x=CX - 12, left_hand_y=FOOT - 88,
    staff_top_x=CX - 15, staff_top_y=FOOT - 155,
    right_hand_x=CX + 28, right_hand_y=FOOT - 85,
    hat_tilt=-6, orb_bright=0.15, body_sway=-10,
    eyes_open=False
))

# Frame 2: stagger — straightening slightly
put_frame(strip, 2, make_frame(
    cx=CX + 8, foot_y=FOOT + 2,
    robe_bob=2,
    left_hand_x=CX - 20, left_hand_y=FOOT - 97,
    staff_top_x=CX - 30, staff_top_y=FOOT - 172,
    right_hand_x=CX + 25, right_hand_y=FOOT - 93,
    hat_tilt=-3, orb_bright=0.25, body_sway=-5,
    eyes_open=False, half_closed=True
))

# Frame 3: recovering
put_frame(strip, 3, make_frame(
    cx=CX + 3, foot_y=FOOT,
    left_hand_x=CX - 25, left_hand_y=FOOT - 100,
    staff_top_x=CX - 34, staff_top_y=FOOT - 181,
    right_hand_x=CX + 22, right_hand_y=FOOT - 95,
    hat_tilt=-1, orb_bright=0.35
))

save_strip(strip, "hit.png")


# ══════════════════════════════════════════════════════════════════════════════
# 5. dead.png — 4 frames
# ══════════════════════════════════════════════════════════════════════════════
print("Generating dead.png ...")
strip = make_strip(4)

# Frame 0: teetering — still mostly upright but leaning
put_frame(strip, 0, make_frame(
    cx=CX, foot_y=FOOT,
    left_hand_x=CX - 30, left_hand_y=FOOT - 90,
    staff_top_x=CX - 50, staff_top_y=FOOT - 160,
    right_hand_x=CX + 28, right_hand_y=FOOT - 92,
    hat_tilt=-5, orb_bright=0.1, body_sway=-6,
    eyes_open=False, robe_bob=3
))

# Frame 1: falling — leaning far right
put_frame(strip, 1, make_frame(
    cx=CX, foot_y=FOOT,
    left_hand_x=CX + 10, left_hand_y=FOOT - 75,
    staff_top_x=CX + 40, staff_top_y=FOOT - 130,
    right_hand_x=CX + 40, right_hand_y=FOOT - 80,
    hat_tilt=-8, orb_bright=0.05, body_sway=12,
    eyes_open=False, robe_bob=8
))

# Frame 2: prone — body collapsed, ~45 degrees
put_frame(strip, 2, make_frame(
    cx=CX, foot_y=FOOT,
    dead=True, dead_rot=0.7,
    hat_off_x=None  # hat still on in this frame
))

# Frame 3: fully prone — lying flat, hat knocked off
put_frame(strip, 3, make_frame(
    cx=CX, foot_y=FOOT,
    dead=True, dead_rot=1.35,
    hat_off_x=CX + 50, hat_off_y=FOOT - 8
))

save_strip(strip, "dead.png")


# ══════════════════════════════════════════════════════════════════════════════
# 6. cast.png — 4 frames
# Both hands raised, arcane circles, magic burst
# ══════════════════════════════════════════════════════════════════════════════
print("Generating cast.png ...")
strip = make_strip(4)

# Frame 0: beginning to raise arms, orb starting to glow
put_frame(strip, 0, make_frame(
    cx=CX, foot_y=FOOT,
    left_hand_x=CX - 26, left_hand_y=FOOT - 108,
    staff_top_x=CX - 32, staff_top_y=FOOT - 190,
    right_hand_x=CX + 22, right_hand_y=FOOT - 108,
    hat_tilt=0, orb_bright=0.5
))

# Frame 1: arms at shoulder height, arcane circle forming
put_frame(strip, 1, make_frame(
    cx=CX, foot_y=FOOT,
    left_hand_x=CX - 34, left_hand_y=FOOT - 128,
    staff_top_x=CX - 30, staff_top_y=FOOT - 192,
    right_hand_x=CX + 34, right_hand_y=FOOT - 128,
    hat_tilt=1, orb_bright=0.75,
    magic_circle_x=CX, magic_circle_y=FOOT - 115, magic_circle_r=28
))

# Frame 2: arms fully raised overhead, full cast — magic burst above
put_frame(strip, 2, make_frame(
    cx=CX, foot_y=FOOT,
    left_hand_x=CX - 28, left_hand_y=FOOT - 148,
    staff_top_x=CX - 22, staff_top_y=FOOT - 196,
    right_hand_x=CX + 28, right_hand_y=FOOT - 148,
    hat_tilt=2, orb_bright=1.0,
    magic_burst_x=CX, magic_burst_y=FOOT - 170, magic_burst_size=26
))

# Frame 3: follow-through, arms coming down slightly
put_frame(strip, 3, make_frame(
    cx=CX, foot_y=FOOT,
    left_hand_x=CX - 30, left_hand_y=FOOT - 118,
    staff_top_x=CX - 28, staff_top_y=FOOT - 190,
    right_hand_x=CX + 30, right_hand_y=FOOT - 118,
    hat_tilt=1, orb_bright=0.7,
    magic_circle_x=CX, magic_circle_y=FOOT - 105, magic_circle_r=22
))

save_strip(strip, "cast.png")


# ══════════════════════════════════════════════════════════════════════════════
# 7. defend.png — 4 frames
# Staff planted, magical barrier shimmer
# ══════════════════════════════════════════════════════════════════════════════
print("Generating defend.png ...")
strip = make_strip(4)

# Frame 0: moving into guard stance
put_frame(strip, 0, make_frame(
    cx=CX, foot_y=FOOT,
    left_hand_x=CX - 20, left_hand_y=FOOT - 98,
    staff_top_x=CX - 18, staff_top_y=FOOT - 188,
    right_hand_x=CX + 18, right_hand_y=FOOT - 100,
    hat_tilt=-1, orb_bright=0.5, body_sway=-3
))

# Frame 1: staff planted firmly, leaning on it slightly
put_frame(strip, 1, make_frame(
    cx=CX - 4, foot_y=FOOT,
    left_hand_x=CX - 18, left_hand_y=FOOT - 102,
    staff_top_x=CX - 14, staff_top_y=FOOT - 192,
    right_hand_x=CX + 16, right_hand_y=FOOT - 104,
    hat_tilt=-2, orb_bright=0.7, body_sway=-5,
    barrier=True,
    barrier_cx=CX + 40, barrier_cy=FOOT - 75, barrier_r=42,
    barrier_intensity=0.6
))

# Frame 2: barrier at full brightness
put_frame(strip, 2, make_frame(
    cx=CX - 4, foot_y=FOOT,
    left_hand_x=CX - 18, left_hand_y=FOOT - 102,
    staff_top_x=CX - 14, staff_top_y=FOOT - 192,
    right_hand_x=CX + 16, right_hand_y=FOOT - 104,
    hat_tilt=-2, orb_bright=0.95, body_sway=-5,
    barrier=True,
    barrier_cx=CX + 40, barrier_cy=FOOT - 75, barrier_r=42,
    barrier_intensity=1.0
))

# Frame 3: holding the barrier
put_frame(strip, 3, make_frame(
    cx=CX - 4, foot_y=FOOT,
    left_hand_x=CX - 18, left_hand_y=FOOT - 102,
    staff_top_x=CX - 14, staff_top_y=FOOT - 192,
    right_hand_x=CX + 16, right_hand_y=FOOT - 104,
    hat_tilt=-2, orb_bright=0.80, body_sway=-5,
    barrier=True,
    barrier_cx=CX + 40, barrier_cy=FOOT - 75, barrier_r=42,
    barrier_intensity=0.8
))

save_strip(strip, "defend.png")


# ══════════════════════════════════════════════════════════════════════════════
# 8. item.png — 4 frames
# Reach into robes, pull out potion, use it, sparkle
# ══════════════════════════════════════════════════════════════════════════════
print("Generating item.png ...")
strip = make_strip(4)

# Frame 0: reaching into robe (right arm bent inward)
put_frame(strip, 0, make_frame(
    cx=CX, foot_y=FOOT,
    left_hand_x=CX - 26, left_hand_y=FOOT - 100,
    staff_top_x=CX - 35, staff_top_y=FOOT - 184,
    right_hand_x=CX + 8, right_hand_y=FOOT - 106,
    hat_tilt=0, orb_bright=0.4
))

# Frame 1: potion in hand, held at waist level
put_frame(strip, 1, make_frame(
    cx=CX, foot_y=FOOT,
    left_hand_x=CX - 26, left_hand_y=FOOT - 100,
    staff_top_x=CX - 35, staff_top_y=FOOT - 184,
    right_hand_x=CX + 24, right_hand_y=FOOT - 100,
    hat_tilt=0, orb_bright=0.4,
    potion_x=CX + 30, potion_y=FOOT - 118
))

# Frame 2: potion raised up high to use
put_frame(strip, 2, make_frame(
    cx=CX, foot_y=FOOT,
    left_hand_x=CX - 26, left_hand_y=FOOT - 100,
    staff_top_x=CX - 35, staff_top_y=FOOT - 184,
    right_hand_x=CX + 28, right_hand_y=FOOT - 128,
    hat_tilt=1, orb_bright=0.45,
    potion_x=CX + 32, potion_y=FOOT - 148
))

# Frame 3: potion used — sparkle effect
put_frame(strip, 3, make_frame(
    cx=CX, foot_y=FOOT,
    left_hand_x=CX - 26, left_hand_y=FOOT - 100,
    staff_top_x=CX - 35, staff_top_y=FOOT - 184,
    right_hand_x=CX + 26, right_hand_y=FOOT - 122,
    hat_tilt=1, orb_bright=0.5,
    potion_x=CX + 30, potion_y=FOOT - 142, potion_raised=True
))

save_strip(strip, "item.png")


# ══════════════════════════════════════════════════════════════════════════════
# 9. victory.png — 4 frames
# Staff raised triumphantly, crystal blazing
# ══════════════════════════════════════════════════════════════════════════════
print("Generating victory.png ...")
strip = make_strip(4)

# Frame 0: begin raising staff and right arm
put_frame(strip, 0, make_frame(
    cx=CX, foot_y=FOOT,
    left_hand_x=CX - 28, left_hand_y=FOOT - 108,
    staff_top_x=CX - 38, staff_top_y=FOOT - 192,
    right_hand_x=CX + 26, right_hand_y=FOOT - 108,
    hat_tilt=-2, orb_bright=0.65
))

# Frame 1: staff raised high and to the right above head
put_frame(strip, 1, make_frame(
    cx=CX, foot_y=FOOT - 2,
    left_hand_x=CX + 8, left_hand_y=FOOT - 140,
    staff_top_x=CX + 30, staff_top_y=FOOT - 218,
    right_hand_x=CX + 32, right_hand_y=FOOT - 118,
    hat_tilt=-3, orb_bright=0.85
))

# Frame 2: peak — staff high, orb blazing, right fist pumped
put_frame(strip, 2, make_frame(
    cx=CX, foot_y=FOOT - 3,
    left_hand_x=CX + 10, left_hand_y=FOOT - 145,
    staff_top_x=CX + 32, staff_top_y=FOOT - 225,
    right_hand_x=CX + 34, right_hand_y=FOOT - 128,
    hat_tilt=-4, orb_bright=1.0,
    magic_burst_x=CX + 32, magic_burst_y=FOOT - 233,
    magic_burst_size=20
))

# Frame 3: hold pose, orb sustaining glow
put_frame(strip, 3, make_frame(
    cx=CX, foot_y=FOOT - 2,
    left_hand_x=CX + 8, left_hand_y=FOOT - 142,
    staff_top_x=CX + 30, staff_top_y=FOOT - 220,
    right_hand_x=CX + 32, right_hand_y=FOOT - 118,
    hat_tilt=-3, orb_bright=0.90
))

save_strip(strip, "victory.png")


print("\nAll 9 mage animations generated successfully.")
