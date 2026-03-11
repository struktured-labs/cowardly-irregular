#!/usr/bin/env python3
"""
gen_bard_extended.py — Bard extended battle animation generator for Cowardly Irregular.

Generates ALL missing bard battle-state and ability-specific animation strips:
  advance.png        (4 frames, 1024x256)  — dramatic performance pose w/ musical notes
  defer.png          (4 frames, 1024x256)  — graceful bow / stepping back
  battle_hymn.png    (6 frames, 1536x256)  — rousing war song, party attack buff
  lullaby.png        (6 frames, 1536x256)  — sleep-inducing song, enemy debuff
  discord.png        (6 frames, 1536x256)  — harsh dissonant blast, confusion/damage
  inspiring_melody.png (6 frames, 1536x256) — healing support melody

Bard design:
  - Rich gold/amber doublet with ornate trim
  - Half-cape draped over left shoulder (deep crimson/burgundy)
  - Feathered cap (tilted beret with red plume feather)
  - Lute/mandolin as primary instrument
  - Lighter, elegant build vs Fighter
  - Ground feet near y=190 in 256x256 frame

Output: /home/struktured/projects/cowardly-irregular-sprite-gen/assets/sprites/jobs/bard/
"""

import math
import os
from PIL import Image

OUT_DIR = "/home/struktured/projects/cowardly-irregular-sprite-gen/assets/sprites/jobs/bard"
os.makedirs(OUT_DIR, exist_ok=True)

FRAME_W = 256
FRAME_H = 256
TRANSPARENT = (0, 0, 0, 0)

# ── Bard Palette ──────────────────────────────────────────────────────────────

C_OUTLINE     = (18,  14,  22,  255)   # near-black purple-tinted

# Skin
C_SKIN_LT     = (238, 205, 165, 255)
C_SKIN_MID    = (210, 172, 130, 255)
C_SKIN_DK     = (165, 128,  90, 255)

# Gold doublet / vest
C_GOLD_HL     = (255, 235, 145, 255)   # bright highlight
C_GOLD_LT     = (235, 200,  90, 255)   # warm gold
C_GOLD_MID    = (195, 158,  52, 255)   # mid gold
C_GOLD_DK     = (140, 108,  28, 255)   # shadow gold
C_GOLD_SH     = ( 90,  68,  12, 255)   # deepest shadow

# Crimson cape
C_CAPE_LT     = (210,  55,  55, 255)
C_CAPE_MID    = (165,  30,  30, 255)
C_CAPE_DK     = (110,  12,  12, 255)

# Feathered cap (dark burgundy beret)
C_CAP_LT      = (148,  28,  48, 255)
C_CAP_MID     = (110,  15,  30, 255)
C_CAP_DK      = ( 68,   5,  15, 255)

# Red plume feather
C_FEATHER_LT  = (255, 100,  60, 255)
C_FEATHER_MID = (220,  55,  30, 255)
C_FEATHER_DK  = (155,  22,  10, 255)

# Lute (warm chestnut wood)
C_LUTE_LT     = (200, 148,  80, 255)
C_LUTE_MID    = (155, 102,  44, 255)
C_LUTE_DK     = ( 98,  58,  18, 255)
C_LUTE_NECK   = (125,  82,  32, 255)
C_LUTE_STRINGS= (210, 210, 185, 255)  # ivory strings
C_LUTE_SOUNDHOLE = (40, 24, 8, 255)

# Trim / buttons
C_TRIM_LT     = (232, 220, 168, 255)  # cream/ivory
C_TRIM_MID    = (188, 165, 110, 255)
C_TRIM_DK     = (130, 108,  62, 255)

# Boots (dark brown leather)
C_BOOT_LT     = (120,  80,  48, 255)
C_BOOT_MID    = ( 82,  52,  26, 255)
C_BOOT_DK     = ( 48,  28,  10, 255)

# Hair (warm chestnut)
C_HAIR_LT     = (155, 100,  45, 255)
C_HAIR_MID    = (110,  65,  20, 255)
C_HAIR_DK     = ( 68,  35,   8, 255)

# Ground shadow
C_SHADOW      = ( 18,  12,  28,  80)

# Musical note effect colours
C_NOTE_GOLD   = (255, 225,  60, 255)   # warm golden note
C_NOTE_OUTLINE= ( 80,  55,   0, 255)
C_NOTE_RED    = (255,  80,  60, 255)   # battle hymn note
C_NOTE_BLUE   = ( 80, 140, 255, 255)   # lullaby note
C_NOTE_PURPLE = (160,  60, 220, 255)   # lullaby dreamy
C_NOTE_BLACK  = ( 20,  10,  10, 255)   # discord harsh
C_NOTE_GREEN  = (100, 220,  80, 255)   # inspiring melody
C_NOTE_WHITE  = (240, 248, 255, 255)   # healing glow

# ZZZ sleep symbols
C_ZZZ         = (100, 160, 255, 255)

# Discord jagged wave
C_DISCORD_R   = (220,  30,  20, 255)
C_DISCORD_B   = ( 20,  10,  10, 255)


# ── Drawing Primitives ────────────────────────────────────────────────────────

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
        dx_max = int(math.sqrt(max(0, r * r - dy * dy)))
        for dx in range(-dx_max, dx_max + 1):
            px(img, cx + dx, cy + dy, color)

def circle_outline(img, cx, cy, r, color):
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            d2 = dx * dx + dy * dy
            if (r - 1) ** 2 < d2 <= r * r:
                px(img, cx + dx, cy + dy, color)

def draw_line(img, x0, y0, x1, y1, color, width=1):
    """Bresenham line with optional width."""
    dx = abs(x1 - x0)
    dy = abs(y1 - y0)
    sx = 1 if x0 < x1 else -1
    sy = 1 if y0 < y1 else -1
    err = dx - dy
    cx_cur, cy_cur = x0, y0
    pts = []
    for _ in range(max(dx, dy) * 2 + 2):
        pts.append((cx_cur, cy_cur))
        if cx_cur == x1 and cy_cur == y1:
            break
        e2 = 2 * err
        if e2 > -dy:
            err -= dy
            cx_cur += sx
        if e2 < dx:
            err += dx
            cy_cur += sy
    for (bx, by) in pts:
        for wx in range(-(width // 2), (width // 2) + 1):
            px(img, bx + wx, by, color)


def alpha_blend(img, x, y, color_rgb, alpha):
    """Blend color_rgb onto pixel at (x,y) with given alpha 0..255."""
    if not (0 <= x < img.width and 0 <= y < img.height):
        return
    r, g, b = color_rgb
    er, eg, eb, ea = img.getpixel((x, y))
    t = alpha / 255.0
    if ea == 0:
        img.putpixel((x, y), (r, g, b, alpha))
    else:
        nr = int(er + (r - er) * t * 0.7)
        ng = int(eg + (g - eg) * t * 0.7)
        nb = int(eb + (b - eb) * t * 0.7)
        img.putpixel((x, y), (nr, ng, nb, 255))


def glow(img, cx, cy, r_max, color_rgb, strength=0.8):
    """Soft radial glow by alpha blending."""
    r, g, b = color_rgb
    for dy in range(-r_max, r_max + 1):
        for dx in range(-r_max, r_max + 1):
            dist = math.sqrt(dx * dx + dy * dy)
            if dist <= r_max:
                t = 1.0 - dist / r_max
                a = int(180 * t * t * strength)
                alpha_blend(img, cx + dx, cy + dy, (r, g, b), a)


# ── Strip helpers ─────────────────────────────────────────────────────────────

def make_strip(n_frames):
    return Image.new("RGBA", (FRAME_W * n_frames, FRAME_H), TRANSPARENT)

def put_frame(strip, frame_idx, frame_img):
    strip.paste(frame_img, (frame_idx * FRAME_W, 0))

def save_strip(strip, name):
    path = os.path.join(OUT_DIR, name)
    strip.save(path, "PNG")
    size_kb = os.path.getsize(path) // 1024
    print(f"  Saved {path}  ({strip.width}x{strip.height}, {size_kb}KB)")
    return path


# ── Bard Body Parts ───────────────────────────────────────────────────────────

CX   = FRAME_W // 2   # 128
FOOT = FRAME_H - 66   # 190


def draw_ground_shadow(img, cx, foot_y, w=28):
    """Elliptical ground shadow."""
    for dy in range(-4, 5):
        t = 1.0 - abs(dy) / 4.5
        half_w = int(w * t)
        a = int(70 * t)
        for dx in range(-half_w, half_w + 1):
            alpha_blend(img, cx + dx, foot_y + dy, (18, 12, 28), a)


def draw_boots(img, cx, foot_y, spread=10, lean=0):
    """Two leather boots."""
    for side in (-1, 1):
        bx = cx + side * spread + (lean if side == 1 else 0)
        # Boot shaft
        for y in range(foot_y - 20, foot_y + 1):
            t = (y - (foot_y - 20)) / 20.0
            half_w = max(1, int(4 + t * 2))
            for x in range(bx - half_w, bx + half_w + 1):
                dist = abs(x - bx) / max(half_w, 1)
                col = C_BOOT_LT if dist < 0.35 else (C_BOOT_MID if dist < 0.7 else C_BOOT_DK)
                px(img, x, y, col)
            px(img, bx - half_w - 1, y, C_OUTLINE)
            px(img, bx + half_w + 1, y, C_OUTLINE)
        # Sole / toe cap
        toe_w = 8
        hline(img, bx - toe_w, bx + toe_w, foot_y, C_BOOT_MID)
        hline(img, bx - toe_w, bx + toe_w, foot_y - 1, C_BOOT_LT)
        hline(img, bx - toe_w - 1, bx + toe_w + 1, foot_y + 1, C_OUTLINE)
        px(img, bx - toe_w - 1, foot_y, C_OUTLINE)
        px(img, bx + toe_w + 1, foot_y, C_OUTLINE)


def draw_legs(img, cx, foot_y, spread=10, lean=0):
    """Slim bard legs in dark trousers."""
    for side in (-1, 1):
        bx = cx + side * spread + (lean if side == 1 else 0)
        leg_top = foot_y - 40
        for y in range(leg_top, foot_y - 18):
            t = (y - leg_top) / 22.0
            hw = int(4 + t * 1.5)
            for x in range(bx - hw, bx + hw + 1):
                dist = abs(x - bx) / max(hw, 1)
                col = C_GOLD_DK if dist < 0.4 else C_GOLD_SH
                px(img, x, y, col)
            px(img, bx - hw - 1, y, C_OUTLINE)
            px(img, bx + hw + 1, y, C_OUTLINE)


def draw_doublet(img, cx, waist_y, hem_y, sway=0, bob=0):
    """Gold doublet/vest — narrower than mage robes, more tailored."""
    hem_y = hem_y + bob
    for y in range(waist_y, hem_y + 1):
        t = (y - waist_y) / max(hem_y - waist_y, 1)
        half_w = int(10 + 10 * t)
        row_cx = cx + int(sway * t * 0.4)
        for x in range(row_cx - half_w, row_cx + half_w + 1):
            dist = abs(x - row_cx) / max(half_w, 1)
            if dist < 0.15:
                col = C_GOLD_HL
            elif dist < 0.40:
                col = C_GOLD_LT
            elif dist < 0.65:
                col = C_GOLD_MID
            elif dist < 0.85:
                col = C_GOLD_DK
            else:
                col = C_GOLD_SH
            px(img, x, y, col)
        px(img, row_cx - half_w - 1, y, C_OUTLINE)
        px(img, row_cx + half_w + 1, y, C_OUTLINE)
    # Button row down center
    for y in range(waist_y + 4, hem_y - 2, 8):
        circle_filled(img, cx, y, 2, C_TRIM_MID)
        circle_outline(img, cx, y, 2, C_OUTLINE)
    # Hem trim
    for dy in range(0, 3):
        t = (hem_y - waist_y + dy - 2) / max(hem_y - waist_y, 1)
        half_w = int(10 + 10 * t)
        col = [C_TRIM_DK, C_TRIM_MID, C_TRIM_LT][dy]
        hline(img, cx - half_w, cx + half_w, hem_y - 2 + dy, col)


def draw_chest_shoulders(img, cx, chest_y, sway=0):
    """Upper chest and shoulder area."""
    for y in range(chest_y, chest_y + 22):
        t = (y - chest_y) / 21.0
        half_w = int(12 + t * 5)
        row_cx = cx + sway
        for x in range(row_cx - half_w, row_cx + half_w + 1):
            dist = abs(x - row_cx) / max(half_w, 1)
            if dist < 0.25:
                col = C_GOLD_LT
            elif dist < 0.6:
                col = C_GOLD_MID
            else:
                col = C_GOLD_DK
            px(img, x, y, col)
        px(img, row_cx - half_w - 1, y, C_OUTLINE)
        px(img, row_cx + half_w + 1, y, C_OUTLINE)
    # Collar trim
    collar_y = chest_y + 1
    hline(img, cx - 9 + sway, cx + 9 + sway, collar_y,     C_TRIM_LT)
    hline(img, cx - 10 + sway, cx + 10 + sway, collar_y + 1, C_TRIM_MID)
    hline(img, cx - 10 + sway, cx + 10 + sway, collar_y + 2, C_TRIM_DK)


def draw_cape(img, cx, chest_y, foot_y, sway=0, flare=0):
    """Half-cape draped over left shoulder. flare = extra sweep for movement."""
    # Cape hangs from left shoulder, drapes down-right
    cape_top_x = cx - 14 + sway
    cape_top_y = chest_y + 4
    cape_hem_x = cx - 24 + sway - flare
    cape_hem_y = foot_y - 30

    n_rows = cape_hem_y - cape_top_y
    for i in range(n_rows + 1):
        t = i / max(n_rows, 1)
        y = cape_top_y + i
        # Cape drapes: left edge sweeps out, right edge stays near body
        left_x  = int(cape_top_x + (cape_hem_x - cape_top_x) * t) - int(10 * t)
        right_x = int(cape_top_x + 6 + sway + flare * t * 0.3)
        if left_x >= right_x:
            left_x = right_x - 2
        for x in range(left_x, right_x + 1):
            dist = (x - left_x) / max(right_x - left_x, 1)
            if dist < 0.2:
                col = C_CAPE_DK
            elif dist < 0.6:
                col = C_CAPE_MID
            else:
                col = C_CAPE_LT
            px(img, x, y, col)
        px(img, left_x - 1, y, C_OUTLINE)
        px(img, right_x + 1, y, C_OUTLINE)
    # Cape hem highlight
    for dx in range(-2, 6):
        px(img, cape_hem_x + dx, cape_hem_y,     C_CAPE_LT)
        px(img, cape_hem_x + dx, cape_hem_y + 1, C_CAPE_DK)
    hline(img, cape_hem_x - 3, cape_hem_x + 7, cape_hem_y - 1, C_OUTLINE)
    hline(img, cape_hem_x - 3, cape_hem_x + 7, cape_hem_y + 2, C_OUTLINE)


def draw_arm(img, shoulder_x, shoulder_y, hand_x, hand_y, lit=True):
    """Robed arm from shoulder to hand position."""
    dx = hand_x - shoulder_x
    dy = hand_y - shoulder_y
    length = math.sqrt(dx * dx + dy * dy)
    if length < 1:
        return
    steps = max(int(length * 1.2), 2)
    for i in range(steps + 1):
        t = i / steps
        ax = int(shoulder_x + dx * t)
        ay = int(shoulder_y + dy * t)
        half_w = max(1, int(5 - t * 2))
        for w in range(-half_w, half_w + 1):
            dist = abs(w) / max(half_w, 1)
            if lit:
                col = C_GOLD_LT if dist < 0.25 else (C_GOLD_MID if dist < 0.6 else C_GOLD_DK)
            else:
                col = C_GOLD_MID if dist < 0.4 else C_GOLD_DK
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
    """Small skin-toned hand."""
    circle_filled(img, hx, hy, 4, C_SKIN_MID)
    px(img, hx - 1, hy - 1, C_SKIN_LT)
    px(img, hx,     hy - 1, C_SKIN_LT)
    circle_outline(img, hx, hy, 4, C_OUTLINE)


def draw_face(img, cx, cy, eyes_open=True, happy=False, wince=False):
    """Charismatic bard face — skin-toned, expressive."""
    face_r = 11
    # Face base
    circle_filled(img, cx, cy, face_r, C_SKIN_MID)
    circle_filled(img, cx - 2, cy - 1, face_r - 3, C_SKIN_LT)  # highlight
    circle_outline(img, cx, cy, face_r, C_OUTLINE)
    circle_outline(img, cx, cy, face_r + 1, C_OUTLINE)

    ey = cy + 2
    if wince:
        # Wincing X eyes
        lx, rx = cx - 4, cx + 3
        px(img, lx - 1, ey - 1, C_OUTLINE); px(img, lx + 1, ey - 1, C_OUTLINE)
        px(img, lx,     ey,     C_OUTLINE)
        px(img, lx - 1, ey + 1, C_OUTLINE); px(img, lx + 1, ey + 1, C_OUTLINE)
        px(img, rx - 1, ey - 1, C_OUTLINE); px(img, rx + 1, ey - 1, C_OUTLINE)
        px(img, rx,     ey,     C_OUTLINE)
        px(img, rx - 1, ey + 1, C_OUTLINE); px(img, rx + 1, ey + 1, C_OUTLINE)
    elif happy:
        # Wide bright eyes + slight smile
        for side in (-1, 1):
            ex = cx + side * 4
            hline(img, ex - 2, ex + 2, ey, C_OUTLINE)
            hline(img, ex - 1, ex + 1, ey - 1, (80, 60, 30, 255))
        # Smile
        smile_y = cy + 5
        hline(img, cx - 3, cx + 3, smile_y, C_OUTLINE)
        px(img, cx - 4, smile_y - 1, C_OUTLINE)
        px(img, cx + 4, smile_y - 1, C_OUTLINE)
    elif eyes_open:
        # Standard expressive eyes
        for side in (-1, 1):
            ex = cx + side * 4
            hline(img, ex - 2, ex + 2, ey, C_OUTLINE)
            px(img, ex - 1, ey - 1, (80, 60, 30, 255))
            px(img, ex,     ey - 1, (80, 60, 30, 255))
    else:
        # Closed / sleeping
        for side in (-1, 1):
            ex = cx + side * 4
            hline(img, ex - 2, ex + 2, ey, C_OUTLINE)


def draw_hair(img, cx, cy, tilt=0):
    """Short chestnut hair peeking out below the cap."""
    # Side tufts
    for dx in range(-14, -8):
        py_base = cy + 8
        col = C_HAIR_MID if dx > -12 else C_HAIR_DK
        vline(img, cx + dx + tilt, py_base, py_base + 5, col)
    for dx in range(8, 14):
        py_base = cy + 8
        vline(img, cx + dx + tilt, py_base, py_base + 4, C_HAIR_DK)
    # Outline around hair
    for dx in [-14, 13]:
        px(img, cx + dx + tilt, cy + 8, C_OUTLINE)


def draw_feathered_cap(img, cx, cy, tilt=0):
    """
    Tilted burgundy beret with red plume feather.
    cx,cy = center of face. Cap sits above and slightly tilted right.
    tilt = extra rightward shift.
    """
    cap_cx = cx + 3 + tilt
    cap_cy = cy - 12

    # Beret body (elliptical blob, tilted)
    for dy in range(-6, 7):
        t = 1.0 - (abs(dy) / 6.0) ** 0.7
        half_w = int(15 * t)
        row_cx = cap_cx + int(tilt * 0.3)
        for dx in range(-half_w, half_w + 1):
            dist = abs(dx) / max(half_w, 1)
            if dist < 0.35:
                col = C_CAP_LT
            elif dist < 0.7:
                col = C_CAP_MID
            else:
                col = C_CAP_DK
            px(img, row_cx + dx, cap_cy + dy, col)
        px(img, row_cx - half_w - 1, cap_cy + dy, C_OUTLINE)
        px(img, row_cx + half_w + 1, cap_cy + dy, C_OUTLINE)
    # Cap brim / band
    band_y = cap_cy + 5
    hline(img, cap_cx - 14, cap_cx + 14, band_y,     C_TRIM_MID)
    hline(img, cap_cx - 15, cap_cx + 15, band_y + 1, C_TRIM_DK)
    hline(img, cap_cx - 15, cap_cx + 15, band_y - 1, C_OUTLINE)
    hline(img, cap_cx - 15, cap_cx + 15, band_y + 2, C_OUTLINE)
    # Cap button/pompom at top
    circle_filled(img, cap_cx, cap_cy - 6, 3, C_CAPE_MID)
    circle_outline(img, cap_cx, cap_cy - 6, 3, C_OUTLINE)

    # Red plume feather — arcs up-left from cap right side
    feather_base_x = cap_cx + 12
    feather_base_y = cap_cy - 2
    for i in range(28):
        t = i / 27.0
        angle = math.radians(-70 + t * 50)   # sweeps from -70deg to -20deg
        r = 5 + i * 1.1
        fx = int(feather_base_x + math.cos(angle) * r * 0.5)
        fy = int(feather_base_y + math.sin(angle) * r)
        col = C_FEATHER_LT if t < 0.3 else (C_FEATHER_MID if t < 0.7 else C_FEATHER_DK)
        px(img, fx, fy, col)
        # Feather barbs
        if i % 4 == 0 and i > 4:
            barb_len = int(4 * (1 - t))
            perp_angle = angle + math.pi / 2
            for b in range(barb_len):
                bx = int(fx + math.cos(perp_angle) * b)
                by = int(fy + math.sin(perp_angle) * b)
                px(img, bx, by, C_FEATHER_MID if b < barb_len // 2 else C_FEATHER_DK)
    # Feather outline tip
    px(img, feather_base_x - 1, feather_base_y - 1, C_OUTLINE)


def draw_lute(img, body_x, body_y, neck_angle=0.0, strum=False, raised=False):
    """
    Draw a lute/mandolin.
    body_x, body_y = center of lute body.
    neck_angle = rotation of neck in radians from vertical (0 = straight up).
    strum = slightly tilted/animated for strumming.
    raised = lute raised higher (for dramatic raises).
    """
    # Lute body (pear-shaped)
    for dy in range(-16, 17):
        t = dy / 16.0
        # Pear: wider at bottom, narrower at top
        if t < 0:
            half_w = int(12 * (1 - t * t * 0.4))
        else:
            half_w = int(12 + 3 * (1 - (1 - t) ** 2))
        if half_w < 1:
            half_w = 1
        for dx in range(-half_w, half_w + 1):
            dist = abs(dx) / half_w
            if dist < 0.25:
                col = C_LUTE_LT
            elif dist < 0.6:
                col = C_LUTE_MID
            else:
                col = C_LUTE_DK
            px(img, body_x + dx, body_y + dy + (2 if strum else 0), col)
        px(img, body_x - half_w - 1, body_y + dy + (2 if strum else 0), C_OUTLINE)
        px(img, body_x + half_w + 1, body_y + dy + (2 if strum else 0), C_OUTLINE)

    # Sound hole
    sh_y = body_y + 4 + (2 if strum else 0)
    circle_filled(img, body_x, sh_y, 4, C_LUTE_SOUNDHOLE)
    circle_outline(img, body_x, sh_y, 4, C_OUTLINE)
    circle_outline(img, body_x, sh_y, 5, C_LUTE_DK)

    # Strings (4 strings across the body)
    str_top = body_y - 14 + (2 if strum else 0)
    str_bot = body_y + 14 + (2 if strum else 0)
    for i in range(4):
        sx = body_x - 4 + i * 3
        vline(img, sx, str_top, str_bot, C_LUTE_STRINGS)

    # Neck (extends upward from top of body)
    neck_top_x = body_x
    neck_top_y = body_y - 16 + (2 if strum else 0)
    neck_len = 32
    neck_end_x = int(neck_top_x + math.sin(neck_angle) * neck_len)
    neck_end_y = neck_top_y - int(math.cos(neck_angle) * neck_len)
    if raised:
        neck_end_y -= 10
        neck_end_x -= 5
    draw_line(img, neck_top_x - 1, neck_top_y, neck_end_x - 1, neck_end_y, C_LUTE_MID, width=2)
    draw_line(img, neck_top_x,     neck_top_y, neck_end_x,     neck_end_y, C_LUTE_LT, width=1)
    draw_line(img, neck_top_x + 1, neck_top_y, neck_end_x + 1, neck_end_y, C_LUTE_DK, width=1)
    # Fret dots
    for fi in range(3):
        t = (fi + 1) / 4.0
        fx = int(neck_top_x + (neck_end_x - neck_top_x) * t)
        fy = int(neck_top_y + (neck_end_y - neck_top_y) * t)
        px(img, fx, fy, C_TRIM_MID)
    # Pegbox at top of neck
    circle_filled(img, neck_end_x, neck_end_y, 4, C_LUTE_DK)
    circle_outline(img, neck_end_x, neck_end_y, 4, C_OUTLINE)
    px(img, neck_end_x - 1, neck_end_y - 1, C_LUTE_MID)


# ── Musical Effect Helpers ────────────────────────────────────────────────────

def draw_musical_note(img, x, y, color, outline_col, size=1):
    """
    Draw a pixel-art musical note (♪) at position (x, y).
    size=1 is about 8x10 pixels.
    """
    # Note head (filled circle)
    r = size + 1
    circle_filled(img, x, y, r, color)
    circle_outline(img, x, y, r, outline_col)
    # Note stem (up-right)
    stem_h = 7 * size
    stem_x = x + r
    for sy in range(y - stem_h, y + 1):
        px(img, stem_x, sy, color)
        px(img, stem_x + 1, sy, color)
    px(img, stem_x - 1, y - stem_h, outline_col)
    px(img, stem_x + 2, y - stem_h, outline_col)
    # Note flag
    flag_y = y - stem_h
    for fx in range(0, 6 * size):
        fy = flag_y + fx // 2
        px(img, stem_x + fx, fy, color)
        px(img, stem_x + fx, fy + 1, color)


def draw_double_note(img, x, y, color, outline_col):
    """
    Draw a double musical note (♫) — two joined noteheads.
    """
    # Left note
    circle_filled(img, x, y, 3, color)
    circle_outline(img, x, y, 3, outline_col)
    # Right note
    circle_filled(img, x + 9, y - 4, 3, color)
    circle_outline(img, x + 9, y - 4, 3, outline_col)
    # Connecting beam (top)
    beam_y = y - 9
    hline(img, x + 3, x + 12, beam_y,     color)
    hline(img, x + 3, x + 12, beam_y + 1, color)
    hline(img, x + 2, x + 13, beam_y - 1, outline_col)
    # Left stem
    vline(img, x + 3, beam_y, y, color)
    vline(img, x + 4, beam_y, y, color)
    # Right stem
    vline(img, x + 12, beam_y, y - 4, color)
    vline(img, x + 13, beam_y, y - 4, color)


def draw_zzz(img, x, y, size=1, color=None):
    """Draw a floating ZZZ sleep symbol."""
    if color is None:
        color = C_ZZZ
    outline = (20, 40, 80, 255)
    scales = [1.8, 1.3, 1.0]
    offsets = [(0, 0), (10, -12), (18, -22)]
    for i, (ox, oy) in enumerate(offsets):
        s = max(1, int(scales[i] * size))
        bx, by = x + ox, y + oy
        # Z shape: top hline, diagonal, bottom hline
        hline(img, bx, bx + 5 * s, by,          color)
        hline(img, bx, bx + 5 * s, by + 1,      color)
        draw_line(img, bx + 5 * s, by + 1, bx, by + 4 * s, color)
        hline(img, bx, bx + 5 * s, by + 4 * s,   color)
        hline(img, bx, bx + 5 * s, by + 4 * s + 1, color)
        # Outline the Z
        for ox2, oy2 in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
            hline(img, bx + ox2, bx + 5 * s + ox2, by + oy2, outline)
            hline(img, bx + ox2, bx + 5 * s + ox2, by + 4 * s + 1 + oy2, outline)


def draw_jagged_wave(img, cx, cy, n_spikes=8, r=28, intensity=1.0):
    """
    Harsh jagged sound-wave for discord. Angular spikes radiating outward.
    """
    for i in range(n_spikes):
        angle = math.radians(i * 360 / n_spikes)
        # Alternating spike lengths for harsh irregularity
        r_inner = int(r * 0.3)
        r_outer = int(r * (0.8 + 0.4 * ((i % 3) / 2.0)) * intensity)
        xi = cx + int(math.cos(angle) * r_inner)
        yi = cy + int(math.sin(angle) * r_inner)
        xo = cx + int(math.cos(angle) * r_outer)
        yo = cy + int(math.sin(angle) * r_outer)
        col = C_DISCORD_R if i % 2 == 0 else C_DISCORD_B
        draw_line(img, xi, yi, xo, yo, col, width=2)
        # Perpendicular jag at tip
        perp = angle + math.pi / 2
        jag_len = int(5 * intensity)
        for ji in range(-jag_len, jag_len + 1):
            jx = xo + int(math.cos(perp) * ji)
            jy = yo + int(math.sin(perp) * ji)
            px(img, jx, jy, col)
    # Center core
    circle_filled(img, cx, cy, int(5 * intensity), C_DISCORD_B)
    circle_outline(img, cx, cy, int(5 * intensity), C_DISCORD_R)


def draw_lullaby_notes(img, cx, cy, n_notes=5, radius=30, phase=0.0, alpha_mult=1.0):
    """Soft floating blue/purple notes drifting outward."""
    for i in range(n_notes):
        angle = math.radians(phase + i * 360 / n_notes)
        r = radius + (i % 2) * 8
        nx = cx + int(math.cos(angle) * r)
        ny = cy + int(math.sin(angle) * r)
        col = C_NOTE_BLUE if i % 2 == 0 else C_NOTE_PURPLE
        out = (10, 20, 60, 255) if i % 2 == 0 else (40, 10, 60, 255)
        draw_musical_note(img, nx, ny, col, out, size=1)
        # Sparkle
        for ang2 in [45, 135, 225, 315]:
            a2 = math.radians(ang2)
            sx, sy = nx + int(math.cos(a2) * 6), ny + int(math.sin(a2) * 6)
            px(img, sx, sy, C_NOTE_WHITE)


def draw_healing_aura(img, cx, cy, r_max=35, density=12):
    """Rising golden-green healing particles spiraling upward."""
    for i in range(density):
        angle = math.radians(i * 360 / density)
        r = int(r_max * (0.5 + 0.5 * ((i % 3) / 2.0)))
        nx = cx + int(math.cos(angle) * r)
        ny = cy + int(math.sin(angle) * r) - 10  # offset upward
        col = C_NOTE_GOLD if i % 3 == 0 else C_NOTE_GREEN
        out = (40, 60, 10, 255) if col == C_NOTE_GREEN else C_NOTE_OUTLINE
        circle_filled(img, nx, ny, 2, col)
        circle_outline(img, nx, ny, 2, out)
        # Light shaft upward
        for ly in range(1, 8):
            a = max(0, 200 - ly * 25)
            alpha_blend(img, nx, ny - ly, (220, 248, 180), a)


def draw_battle_note_burst(img, cx, cy, radius=30, n=8, phase=0.0):
    """Aggressive red-gold notes for battle hymn."""
    for i in range(n):
        angle = math.radians(phase + i * 360 / n)
        r = radius + (i % 2) * 6
        nx = cx + int(math.cos(angle) * r)
        ny = cy + int(math.sin(angle) * r)
        col = C_NOTE_RED if i % 2 == 0 else C_NOTE_GOLD
        out = C_NOTE_OUTLINE
        if i % 2 == 0:
            draw_musical_note(img, nx, ny, col, out, size=1)
        else:
            draw_double_note(img, nx - 7, ny, col, out)
        # Energy trail inward
        steps = 5
        for s in range(steps):
            t = s / steps
            tx = int(nx + (cx - nx) * t)
            ty = int(ny + (cy - ny) * t)
            a = int(140 * (1 - t))
            alpha_blend(img, tx, ty, (220, 120, 30), a)


# ── Full Frame Builder ────────────────────────────────────────────────────────

def make_frame(
    cx=None, foot_y=None,
    # Body pose
    sway=0, bob=0, lean=0,
    # Arms
    left_hand_x=None, left_hand_y=None,
    right_hand_x=None, right_hand_y=None,
    # Cap / face
    hat_tilt=0, eyes_open=True, happy=False, wince=False,
    # Cape
    cape_flare=0,
    # Lute
    lute_x=None, lute_y=None,
    lute_neck_angle=0.0, lute_strum=False, lute_raised=False,
    lute_visible=True,
    # Effects (added on top)
    effects=None,   # list of callables (img) -> None
    # Dead
    dead=False, dead_rot=0.0,
    bow_depth=0,    # bow animation (0=none, positive=bowing deeper)
):
    """Build and return a single 256x256 bard frame."""
    img = Image.new("RGBA", (FRAME_W, FRAME_H), TRANSPARENT)

    if cx is None:
        cx = CX
    if foot_y is None:
        foot_y = FOOT

    # Dead/collapsed special case
    if dead:
        _draw_dead_frame(img, cx, foot_y, dead_rot)
        return img

    # Derived layout positions
    rcx    = cx + sway
    waist_y = foot_y - 64
    hem_y   = foot_y - 22
    chest_y = waist_y - 20
    face_cy = chest_y - 14

    # Lute defaults (resting at left side)
    lx = lute_x if lute_x is not None else cx - 35 + sway
    ly = lute_y if lute_y is not None else waist_y + 10

    # Hand defaults
    lhx = left_hand_x  if left_hand_x  is not None else cx - 32 + sway
    lhy = left_hand_y  if left_hand_y  is not None else waist_y + 5
    rhx = right_hand_x if right_hand_x is not None else cx + 24 + sway
    rhy = right_hand_y if right_hand_y is not None else waist_y + 8

    # Shoulder anchors
    lshx = rcx - 18
    rshx = rcx + 18
    shy  = chest_y + 8

    # Bowing transform — shifts body forward/down
    bow_cx_off  = -bob // 2
    bow_face_off = bow_depth

    # ── Draw order: back-to-front ─────────────────────────────────────────────

    # 1. Ground shadow
    draw_ground_shadow(img, cx, foot_y + 2, w=26)

    # 2. Cape (behind body)
    draw_cape(img, rcx, chest_y, foot_y, sway=sway, flare=cape_flare)

    # 3. Lute body (may be behind or in front depending on pose — behind by default)
    if lute_visible and not lute_raised:
        draw_lute(img, lx + bob_lx_off(bow_depth), ly, lute_neck_angle, lute_strum)

    # 4. Legs + boots
    draw_legs(img, rcx, foot_y, spread=11, lean=lean)
    draw_boots(img, rcx, foot_y, spread=11, lean=lean)

    # 5. Doublet
    draw_doublet(img, rcx, waist_y + bob, hem_y, sway=sway, bob=bob)

    # 6. Chest + shoulders
    draw_chest_shoulders(img, rcx, chest_y + bow_face_off // 3, sway=sway)

    # 7. Left arm
    draw_arm(img, lshx, shy + bow_face_off // 3, lhx, lhy, lit=False)
    draw_hand(img, lhx, lhy)

    # 8. Right arm
    draw_arm(img, rshx, shy + bow_face_off // 3, rhx, rhy, lit=True)
    draw_hand(img, rhx, rhy)

    # 9. Raised lute (in front of body when raised)
    if lute_visible and lute_raised:
        draw_lute(img, lx, ly, lute_neck_angle, lute_strum, raised=True)

    # 10. Face + hair
    draw_hair(img, rcx, face_cy - bow_face_off, tilt=hat_tilt)
    draw_face(img, rcx, face_cy - bow_face_off, eyes_open=eyes_open, happy=happy, wince=wince)

    # 11. Cap + feather
    draw_feathered_cap(img, rcx, face_cy - bow_face_off, tilt=hat_tilt)

    # 12. Effects overlay
    if effects:
        for eff in effects:
            eff(img)

    return img


def bob_lx_off(bow_depth):
    """Lute X offset when bowing."""
    return -bow_depth // 4


def _draw_dead_frame(img, cx, foot_y, rot):
    """Bard collapsed on ground."""
    cos_r = math.cos(rot)
    sin_r = math.sin(rot)
    body_h = 75
    pivot_x = cx
    pivot_y = foot_y - 5
    perp_x = cos_r
    perp_y = sin_r

    def body_pt(t):
        return (pivot_x + sin_r * body_h * t,
                pivot_y - cos_r * body_h * t)

    def robe_hw(t):
        return 5 + 15 * max(0.0, 1.0 - t) ** 0.6

    n_seg = 48
    poly_left, poly_right = [], []
    for i in range(n_seg + 1):
        t = i / n_seg
        bx, by = body_pt(t)
        hw = robe_hw(t)
        poly_left.append((bx - perp_x * hw, by - perp_y * hw))
        poly_right.append((bx + perp_x * hw, by + perp_y * hw))
    poly = poly_left + list(reversed(poly_right))

    all_y = [p[1] for p in poly]
    min_y = max(0, int(min(all_y)) - 1)
    max_y = min(FRAME_H - 1, int(max(all_y)) + 1)

    def scanline_xs(scan_y, polygon):
        xs = []
        n = len(polygon)
        for i in range(n):
            x0, y0 = polygon[i]
            x1, y1 = polygon[(i + 1) % n]
            if (y0 <= scan_y < y1) or (y1 <= scan_y < y0):
                if abs(y1 - y0) < 0.001:
                    continue
                t_i = (scan_y - y0) / (y1 - y0)
                xs.append(x0 + t_i * (x1 - x0))
        xs.sort()
        return xs

    for sy in range(min_y, max_y + 1):
        xs = scanline_xs(sy + 0.5, poly)
        for k in range(0, len(xs) - 1, 2):
            xl, xr = int(xs[k]), int(xs[k + 1])
            for sx_i in range(xl, xr + 1):
                rel_x = sx_i - pivot_x
                rel_y = sy - pivot_y
                t_axis = (rel_x * sin_r - rel_y * cos_r) / body_h
                t_axis = max(0.0, min(1.0, t_axis))
                hw = robe_hw(t_axis)
                trans = rel_x * perp_x + rel_y * perp_y
                dist = abs(trans) / max(hw, 1)
                if dist < 0.2:
                    col = C_GOLD_LT
                elif dist < 0.55:
                    col = C_GOLD_MID
                elif dist < 0.80:
                    col = C_GOLD_DK
                else:
                    col = C_GOLD_SH
                px(img, sx_i, sy, col)

    n = len(poly)
    for i in range(n):
        x0, y0 = poly[i]
        x1, y1 = poly[(i + 1) % n]
        draw_line(img, int(x0), int(y0), int(x1), int(y1), C_OUTLINE)

    # Head at top end
    head_x = int(pivot_x + sin_r * body_h)
    head_y = int(pivot_y - cos_r * body_h)
    draw_face(img, head_x, head_y, eyes_open=False)
    # Feathered cap fallen nearby
    draw_feathered_cap(img, head_x + 8, head_y + 5, tilt=5)
    # Lute lying on ground
    draw_lute(img, pivot_x + 12, pivot_y - 10, neck_angle=math.pi * 0.25)
    # Ground shadow
    draw_ground_shadow(img, pivot_x, foot_y + 2, w=35)


# ══════════════════════════════════════════════════════════════════════════════
# Animation: advance.png  — 4 frames, 1024x256
# Dramatic performance pose, musical notes appear, crescendo.
# ══════════════════════════════════════════════════════════════════════════════
print("Generating advance.png ...")
strip = make_strip(4)

# Frame 0: Dramatic arm raise begins — lute lifts, right arm gestures up
put_frame(strip, 0, make_frame(
    cx=CX, foot_y=FOOT,
    sway=2,
    left_hand_x=CX - 28, left_hand_y=FOOT - 75,
    right_hand_x=CX + 28, right_hand_y=FOOT - 105,
    lute_x=CX - 30, lute_y=FOOT - 68,
    lute_neck_angle=0.15,
    hat_tilt=2, happy=True,
    effects=[
        lambda img: draw_musical_note(img, CX + 55, FOOT - 90, C_NOTE_GOLD, C_NOTE_OUTLINE, size=1),
    ]
))

# Frame 1: Strum lute powerfully, body leans forward
put_frame(strip, 1, make_frame(
    cx=CX, foot_y=FOOT,
    sway=4, bob=2, lean=3,
    left_hand_x=CX - 22, left_hand_y=FOOT - 70,
    right_hand_x=CX + 26, right_hand_y=FOOT - 95,
    lute_x=CX - 25, lute_y=FOOT - 72,
    lute_neck_angle=0.2, lute_strum=True,
    hat_tilt=4, happy=True,
    effects=[
        lambda img: draw_musical_note(img, CX + 58, FOOT - 88, C_NOTE_GOLD, C_NOTE_OUTLINE, size=1),
        lambda img: draw_musical_note(img, CX + 45, FOOT - 110, C_NOTE_GOLD, C_NOTE_OUTLINE, size=1),
    ]
))

# Frame 2: Visible musical notes/sound waves emanating outward
put_frame(strip, 2, make_frame(
    cx=CX, foot_y=FOOT,
    sway=5, lean=4,
    left_hand_x=CX - 20, left_hand_y=FOOT - 68,
    right_hand_x=CX + 28, right_hand_y=FOOT - 92,
    lute_x=CX - 22, lute_y=FOOT - 72,
    lute_neck_angle=0.22, lute_strum=True,
    hat_tilt=5, happy=True,
    effects=[
        lambda img: draw_battle_note_burst(img, CX + 60, FOOT - 80, radius=22, n=6, phase=0),
    ]
))

# Frame 3: Full crescendo — lute raised high, swirling notes
put_frame(strip, 3, make_frame(
    cx=CX, foot_y=FOOT,
    sway=3, lean=2,
    left_hand_x=CX - 18, left_hand_y=FOOT - 90,
    right_hand_x=CX + 22, right_hand_y=FOOT - 108,
    lute_x=CX - 20, lute_y=FOOT - 95,
    lute_neck_angle=0.1, lute_raised=True,
    hat_tilt=3, happy=True,
    effects=[
        lambda img: draw_battle_note_burst(img, CX + 65, FOOT - 75, radius=28, n=8, phase=20),
        lambda img: draw_musical_note(img, CX + 40, FOOT - 118, C_NOTE_GOLD, C_NOTE_OUTLINE, size=1),
        lambda img: draw_double_note(img, CX + 55, FOOT - 128, C_NOTE_GOLD, C_NOTE_OUTLINE),
    ]
))

save_strip(strip, "advance.png")


# ══════════════════════════════════════════════════════════════════════════════
# Animation: defer.png  — 4 frames, 1024x256
# Graceful bow / stepping back, observing pose.
# ══════════════════════════════════════════════════════════════════════════════
print("Generating defer.png ...")
strip = make_strip(4)

# Frame 0: Slight bow, cape begins to sweep
put_frame(strip, 0, make_frame(
    cx=CX, foot_y=FOOT,
    sway=-2, bow_depth=6,
    left_hand_x=CX - 30, left_hand_y=FOOT - 70,
    right_hand_x=CX + 28, right_hand_y=FOOT - 68,
    lute_x=CX - 32, lute_y=FOOT - 65,
    lute_neck_angle=0.1,
    hat_tilt=-2, eyes_open=True, happy=True,
    cape_flare=4,
))

# Frame 2: Deeper bow with cape flourish
put_frame(strip, 1, make_frame(
    cx=CX, foot_y=FOOT,
    sway=-4, bow_depth=16,
    left_hand_x=CX - 32, left_hand_y=FOOT - 55,
    right_hand_x=CX + 30, right_hand_y=FOOT - 52,
    lute_x=CX - 35, lute_y=FOOT - 58,
    lute_neck_angle=0.18,
    hat_tilt=-5, eyes_open=False,
    cape_flare=10,
))

# Frame 3: Stepping back, rising from bow
put_frame(strip, 2, make_frame(
    cx=CX - 5, foot_y=FOOT,
    sway=-3, bow_depth=8, lean=-4,
    left_hand_x=CX - 35, left_hand_y=FOOT - 64,
    right_hand_x=CX + 20, right_hand_y=FOOT - 72,
    lute_x=CX - 38, lute_y=FOOT - 62,
    lute_neck_angle=0.12,
    hat_tilt=-3, eyes_open=True,
    cape_flare=6,
))

# Frame 4: Observing pose — lute at rest, watching others
put_frame(strip, 3, make_frame(
    cx=CX - 8, foot_y=FOOT,
    sway=-5, lean=-6,
    left_hand_x=CX - 38, left_hand_y=FOOT - 70,
    right_hand_x=CX + 14, right_hand_y=FOOT - 78,
    lute_x=CX - 42, lute_y=FOOT - 66,
    lute_neck_angle=0.08,
    hat_tilt=-4, eyes_open=True, happy=False,
    cape_flare=3,
))

save_strip(strip, "defer.png")


# ══════════════════════════════════════════════════════════════════════════════
# Animation: battle_hymn.png — 6 frames, 1536x256
# Rousing war song — party attack buff. Energetic, martial. Reds and golds.
# ══════════════════════════════════════════════════════════════════════════════
print("Generating battle_hymn.png ...")
strip = make_strip(6)

# Frame 0: Raise lute high — wind-up
put_frame(strip, 0, make_frame(
    cx=CX, foot_y=FOOT, sway=2,
    left_hand_x=CX - 20, left_hand_y=FOOT - 90,
    right_hand_x=CX + 24, right_hand_y=FOOT - 98,
    lute_x=CX - 22, lute_y=FOOT - 85,
    lute_neck_angle=0.12, lute_raised=True,
    hat_tilt=3, happy=True,
))

# Frame 1: Begin aggressive strumming — leaning forward
put_frame(strip, 1, make_frame(
    cx=CX, foot_y=FOOT, sway=5, bob=3, lean=5,
    left_hand_x=CX - 18, left_hand_y=FOOT - 82,
    right_hand_x=CX + 26, right_hand_y=FOOT - 88,
    lute_x=CX - 20, lute_y=FOOT - 80,
    lute_neck_angle=0.25, lute_strum=True,
    hat_tilt=5, happy=True,
))

# Frame 2: Red-orange musical notes burst outward
put_frame(strip, 2, make_frame(
    cx=CX, foot_y=FOOT, sway=6, lean=6,
    left_hand_x=CX - 16, left_hand_y=FOOT - 80,
    right_hand_x=CX + 26, right_hand_y=FOOT - 85,
    lute_x=CX - 18, lute_y=FOOT - 78,
    lute_neck_angle=0.28, lute_strum=True,
    hat_tilt=5, happy=True,
    effects=[
        lambda img: draw_battle_note_burst(img, CX + 68, FOOT - 72, radius=25, n=8, phase=0),
    ]
))

# Frame 3: Notes swirl around — representing reaching party
put_frame(strip, 3, make_frame(
    cx=CX, foot_y=FOOT, sway=5, lean=4,
    left_hand_x=CX - 18, left_hand_y=FOOT - 82,
    right_hand_x=CX + 24, right_hand_y=FOOT - 88,
    lute_x=CX - 20, lute_y=FOOT - 80,
    lute_neck_angle=0.22, lute_strum=True,
    hat_tilt=4, happy=True,
    effects=[
        lambda img: draw_battle_note_burst(img, CX + 65, FOOT - 70, radius=30, n=10, phase=18),
        lambda img: draw_battle_note_burst(img, CX - 50, FOOT - 68, radius=18, n=6, phase=30),
    ]
))

# Frame 4: Triumphant pose — standing tall
put_frame(strip, 4, make_frame(
    cx=CX, foot_y=FOOT, sway=2,
    left_hand_x=CX - 22, left_hand_y=FOOT - 88,
    right_hand_x=CX + 28, right_hand_y=FOOT - 102,
    lute_x=CX - 24, lute_y=FOOT - 85,
    lute_neck_angle=0.1, lute_raised=True,
    hat_tilt=2, happy=True,
    effects=[
        lambda img: draw_musical_note(img, CX + 55, FOOT - 105, C_NOTE_RED, C_NOTE_OUTLINE, size=1),
        lambda img: draw_double_note(img, CX + 58, FOOT - 118, C_NOTE_GOLD, C_NOTE_OUTLINE),
    ]
))

# Frame 5: Return to ready — settling back
put_frame(strip, 5, make_frame(
    cx=CX, foot_y=FOOT, sway=0,
    left_hand_x=CX - 32, left_hand_y=FOOT - 72,
    right_hand_x=CX + 24, right_hand_y=FOOT - 75,
    lute_x=CX - 34, lute_y=FOOT - 68,
    lute_neck_angle=0.08,
    hat_tilt=0, happy=True,
    effects=[
        lambda img: draw_musical_note(img, CX + 48, FOOT - 90, C_NOTE_GOLD, C_NOTE_OUTLINE, size=1),
    ]
))

save_strip(strip, "battle_hymn.png")


# ══════════════════════════════════════════════════════════════════════════════
# Animation: lullaby.png — 6 frames, 1536x256
# Sleep-inducing song — enemy debuff. Soft, dreamy. Cool blues and purples.
# ══════════════════════════════════════════════════════════════════════════════
print("Generating lullaby.png ...")
strip = make_strip(6)

# Frame 0: Gentle cradling of lute, soft stance
put_frame(strip, 0, make_frame(
    cx=CX, foot_y=FOOT, sway=-2,
    left_hand_x=CX - 30, left_hand_y=FOOT - 68,
    right_hand_x=CX + 20, right_hand_y=FOOT - 72,
    lute_x=CX - 32, lute_y=FOOT - 65,
    lute_neck_angle=0.05,
    hat_tilt=-1, eyes_open=True,
))

# Frame 1: Soft plucking motion — slight tilt, relaxed
put_frame(strip, 1, make_frame(
    cx=CX, foot_y=FOOT, sway=-3, bob=1,
    left_hand_x=CX - 28, left_hand_y=FOOT - 70,
    right_hand_x=CX + 22, right_hand_y=FOOT - 68,
    lute_x=CX - 30, lute_y=FOOT - 67,
    lute_neck_angle=0.04, lute_strum=True,
    hat_tilt=-2, eyes_open=True,
))

# Frame 2: Blue-purple dreamy notes float out
put_frame(strip, 2, make_frame(
    cx=CX, foot_y=FOOT, sway=-3,
    left_hand_x=CX - 28, left_hand_y=FOOT - 70,
    right_hand_x=CX + 22, right_hand_y=FOOT - 68,
    lute_x=CX - 30, lute_y=FOOT - 67,
    lute_neck_angle=0.04, lute_strum=True,
    hat_tilt=-2, eyes_open=True,
    effects=[
        lambda img: draw_lullaby_notes(img, CX + 62, FOOT - 68, n_notes=4, radius=22, phase=0),
    ]
))

# Frame 3: Notes drift toward enemies with sparkle-star effects
put_frame(strip, 3, make_frame(
    cx=CX, foot_y=FOOT, sway=-2,
    left_hand_x=CX - 30, left_hand_y=FOOT - 68,
    right_hand_x=CX + 20, right_hand_y=FOOT - 72,
    lute_x=CX - 32, lute_y=FOOT - 65,
    lute_neck_angle=0.05,
    hat_tilt=-1, eyes_open=True,
    effects=[
        lambda img: draw_lullaby_notes(img, CX + 70, FOOT - 65, n_notes=5, radius=28, phase=36),
        lambda img: draw_lullaby_notes(img, CX + 40, FOOT - 85, n_notes=3, radius=14, phase=72),
    ]
))

# Frame 4: ZZZ symbols appear — enemies falling asleep
put_frame(strip, 4, make_frame(
    cx=CX, foot_y=FOOT, sway=-2,
    left_hand_x=CX - 30, left_hand_y=FOOT - 68,
    right_hand_x=CX + 20, right_hand_y=FOOT - 70,
    lute_x=CX - 32, lute_y=FOOT - 65,
    lute_neck_angle=0.04,
    hat_tilt=-2, eyes_open=True,
    effects=[
        lambda img: draw_lullaby_notes(img, CX + 68, FOOT - 62, n_notes=4, radius=20, phase=54),
        lambda img: draw_zzz(img, CX + 68, FOOT - 95, size=1),
        lambda img: draw_zzz(img, CX + 82, FOOT - 112, size=1),
    ]
))

# Frame 5: Quiet finished pose — gentle smile, notes fading
put_frame(strip, 5, make_frame(
    cx=CX, foot_y=FOOT, sway=-1,
    left_hand_x=CX - 30, left_hand_y=FOOT - 68,
    right_hand_x=CX + 20, right_hand_y=FOOT - 72,
    lute_x=CX - 32, lute_y=FOOT - 65,
    lute_neck_angle=0.05,
    hat_tilt=-1, eyes_open=True, happy=True,
    effects=[
        lambda img: draw_musical_note(img, CX + 55, FOOT - 80, C_NOTE_BLUE, (10, 20, 60, 255), size=1),
        lambda img: draw_zzz(img, CX + 70, FOOT - 100, size=1),
    ]
))

save_strip(strip, "lullaby.png")


# ══════════════════════════════════════════════════════════════════════════════
# Animation: discord.png — 6 frames, 1536x256
# Harsh dissonant blast — enemy confusion/damage. Harsh angular red/black.
# ══════════════════════════════════════════════════════════════════════════════
print("Generating discord.png ...")
strip = make_strip(6)

# Frame 0: Wild dramatic pose — bard goes into harsh stance
put_frame(strip, 0, make_frame(
    cx=CX, foot_y=FOOT, sway=6, lean=5,
    left_hand_x=CX - 16, left_hand_y=FOOT - 68,
    right_hand_x=CX + 30, right_hand_y=FOOT - 110,
    lute_x=CX - 18, lute_y=FOOT - 65,
    lute_neck_angle=0.35,
    hat_tilt=7, happy=True,
    cape_flare=8,
))

# Frame 1: Aggressive discordant strum — extreme lean
put_frame(strip, 1, make_frame(
    cx=CX, foot_y=FOOT, sway=8, lean=8, bob=2,
    left_hand_x=CX - 14, left_hand_y=FOOT - 65,
    right_hand_x=CX + 32, right_hand_y=FOOT - 105,
    lute_x=CX - 16, lute_y=FOOT - 62,
    lute_neck_angle=0.4, lute_strum=True,
    hat_tilt=8, wince=False, happy=True,
    cape_flare=12,
))

# Frame 2: Jagged harsh red-black sound waves explode outward
put_frame(strip, 2, make_frame(
    cx=CX, foot_y=FOOT, sway=8, lean=8,
    left_hand_x=CX - 14, left_hand_y=FOOT - 65,
    right_hand_x=CX + 32, right_hand_y=FOOT - 105,
    lute_x=CX - 16, lute_y=FOOT - 62,
    lute_neck_angle=0.4, lute_strum=True,
    hat_tilt=8, happy=True,
    cape_flare=12,
    effects=[
        lambda img: draw_jagged_wave(img, CX + 68, FOOT - 72, n_spikes=9, r=28, intensity=1.0),
    ]
))

# Frame 3: Chaotic visual noise — multiple wave bursts
put_frame(strip, 3, make_frame(
    cx=CX, foot_y=FOOT, sway=7, lean=6,
    left_hand_x=CX - 16, left_hand_y=FOOT - 66,
    right_hand_x=CX + 30, right_hand_y=FOOT - 100,
    lute_x=CX - 18, lute_y=FOOT - 63,
    lute_neck_angle=0.38, lute_strum=True,
    hat_tilt=7, happy=True,
    cape_flare=10,
    effects=[
        lambda img: draw_jagged_wave(img, CX + 70, FOOT - 70, n_spikes=10, r=32, intensity=1.2),
        lambda img: draw_jagged_wave(img, CX + 55, FOOT - 90, n_spikes=6,  r=16, intensity=0.8),
    ]
))

# Frame 4: Enemies recoil — jagged notes, bard smirking
put_frame(strip, 4, make_frame(
    cx=CX, foot_y=FOOT, sway=5, lean=4,
    left_hand_x=CX - 20, left_hand_y=FOOT - 68,
    right_hand_x=CX + 28, right_hand_y=FOOT - 96,
    lute_x=CX - 22, lute_y=FOOT - 65,
    lute_neck_angle=0.3,
    hat_tilt=5, happy=True,
    cape_flare=6,
    effects=[
        lambda img: draw_jagged_wave(img, CX + 65, FOOT - 65, n_spikes=8, r=22, intensity=0.8),
        lambda img: [draw_line(img, CX + 70 + i * 8, FOOT - 80, CX + 74 + i * 8, FOOT - 92, C_DISCORD_R, width=2) for i in range(3)],
    ]
))

# Frame 5: Smirking recovery — hat tilted, cape settles
put_frame(strip, 5, make_frame(
    cx=CX, foot_y=FOOT, sway=2, lean=2,
    left_hand_x=CX - 28, left_hand_y=FOOT - 70,
    right_hand_x=CX + 24, right_hand_y=FOOT - 80,
    lute_x=CX - 30, lute_y=FOOT - 67,
    lute_neck_angle=0.12,
    hat_tilt=4, happy=True,
    cape_flare=2,
    effects=[
        lambda img: draw_musical_note(img, CX + 52, FOOT - 85, C_DISCORD_R, C_DISCORD_B, size=1),
    ]
))

save_strip(strip, "discord.png")


# ══════════════════════════════════════════════════════════════════════════════
# Animation: inspiring_melody.png — 6 frames, 1536x256
# Inspiring support song — party heal/morale. Warm gold and soft green.
# ══════════════════════════════════════════════════════════════════════════════
print("Generating inspiring_melody.png ...")
strip = make_strip(6)

# Frame 0: Gentle strum start — relaxed open stance
put_frame(strip, 0, make_frame(
    cx=CX, foot_y=FOOT, sway=0,
    left_hand_x=CX - 30, left_hand_y=FOOT - 72,
    right_hand_x=CX + 22, right_hand_y=FOOT - 76,
    lute_x=CX - 32, lute_y=FOOT - 68,
    lute_neck_angle=0.06,
    hat_tilt=0, eyes_open=True, happy=True,
))

# Frame 1: Melodic flowing motion — slight sway, eyes half-closed
put_frame(strip, 1, make_frame(
    cx=CX, foot_y=FOOT, sway=-2, bob=1,
    left_hand_x=CX - 28, left_hand_y=FOOT - 74,
    right_hand_x=CX + 22, right_hand_y=FOOT - 75,
    lute_x=CX - 30, lute_y=FOOT - 70,
    lute_neck_angle=0.08, lute_strum=True,
    hat_tilt=-1, eyes_open=True, happy=True,
))

# Frame 2: Golden-green healing notes spiral upward
put_frame(strip, 2, make_frame(
    cx=CX, foot_y=FOOT, sway=-2,
    left_hand_x=CX - 28, left_hand_y=FOOT - 74,
    right_hand_x=CX + 22, right_hand_y=FOOT - 76,
    lute_x=CX - 30, lute_y=FOOT - 70,
    lute_neck_angle=0.08, lute_strum=True,
    hat_tilt=-1, eyes_open=True, happy=True,
    effects=[
        lambda img: draw_healing_aura(img, CX + 55, FOOT - 68, r_max=28, density=10),
    ]
))

# Frame 3: Notes become light particles showering down
put_frame(strip, 3, make_frame(
    cx=CX, foot_y=FOOT, sway=-1,
    left_hand_x=CX - 30, left_hand_y=FOOT - 72,
    right_hand_x=CX + 20, right_hand_y=FOOT - 76,
    lute_x=CX - 32, lute_y=FOOT - 68,
    lute_neck_angle=0.07,
    hat_tilt=-1, eyes_open=True, happy=True,
    effects=[
        lambda img: draw_healing_aura(img, CX + 58, FOOT - 65, r_max=35, density=14),
        lambda img: [
            circle_filled(img, CX + 48 + i * 12, FOOT - 105 + i * 5, 2, C_NOTE_GREEN)
            for i in range(4)
        ],
        lambda img: [
            circle_filled(img, CX + 42 + i * 14, FOOT - 112 + i * 6, 2, C_NOTE_GOLD)
            for i in range(3)
        ],
    ]
))

# Frame 4: Warm glow effect — surrounding bard in golden light
put_frame(strip, 4, make_frame(
    cx=CX, foot_y=FOOT, sway=1,
    left_hand_x=CX - 28, left_hand_y=FOOT - 76,
    right_hand_x=CX + 24, right_hand_y=FOOT - 80,
    lute_x=CX - 30, lute_y=FOOT - 72,
    lute_neck_angle=0.08, lute_raised=True,
    hat_tilt=1, eyes_open=True, happy=True,
    effects=[
        lambda img: glow(img, CX, FOOT - 80, 50, (220, 235, 140), strength=0.5),
        lambda img: draw_healing_aura(img, CX + 60, FOOT - 62, r_max=30, density=12),
        lambda img: draw_double_note(img, CX + 50, FOOT - 108, C_NOTE_GREEN, (20, 60, 10, 255)),
    ]
))

# Frame 5: Peaceful finish pose — soft smile, lute lowered
put_frame(strip, 5, make_frame(
    cx=CX, foot_y=FOOT, sway=0,
    left_hand_x=CX - 30, left_hand_y=FOOT - 70,
    right_hand_x=CX + 22, right_hand_y=FOOT - 74,
    lute_x=CX - 32, lute_y=FOOT - 66,
    lute_neck_angle=0.05,
    hat_tilt=0, eyes_open=True, happy=True,
    effects=[
        lambda img: draw_musical_note(img, CX + 50, FOOT - 85, C_NOTE_GREEN, (20, 60, 10, 255), size=1),
        lambda img: draw_musical_note(img, CX + 62, FOOT - 96, C_NOTE_GOLD, C_NOTE_OUTLINE, size=1),
    ]
))

save_strip(strip, "inspiring_melody.png")


# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════
print("\nAll bard extended animations complete.")
print(f"Output directory: {OUT_DIR}")
generated = [
    "advance.png (4 frames, 1024x256)",
    "defer.png (4 frames, 1024x256)",
    "battle_hymn.png (6 frames, 1536x256)",
    "lullaby.png (6 frames, 1536x256)",
    "discord.png (6 frames, 1536x256)",
    "inspiring_melody.png (6 frames, 1536x256)",
]
for g in generated:
    print(f"  {g}")
