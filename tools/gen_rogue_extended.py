#!/usr/bin/env python3
"""
Generate EXTENDED Rogue animation strips for Cowardly Irregular.

Battle state sprites:
  advance.png   1024x256  (4 frames) — deep crouch, daggers cross, speed burst
  defer.png     1024x256  (4 frames) — fade into shadows, semi-transparent

Ability-specific animations:
  steal.png     1536x256  (6 frames) — dash, reach, grab, snatch, retreat, examine
  backstab.png  1536x256  (6 frames) — vanish, appear, thrust, flash, withdraw, flip
  mug.png       1536x256  (6 frames) — dash+slash+grab combo
  flee.png      1024x256  (4 frames) — turn, smoke bomb, sprint, gone

Frame size: 256x256 pixels per frame, transparent background.
Art style: SNES-style pixel art, 2x2 super-pixels.
Rogue design: dark leather, green cloak, dual daggers, bandana.

OUTPUT: /home/struktured/projects/cowardly-irregular-sprite-gen/assets/sprites/jobs/rogue/
"""

import math
import os
import numpy as np
from PIL import Image

OUT_DIR = "/home/struktured/projects/cowardly-irregular-sprite-gen/assets/sprites/jobs/rogue"
TMP_DIR = "/home/struktured/projects/cowardly-irregular-sprite-gen/tmp"
os.makedirs(OUT_DIR, exist_ok=True)
os.makedirs(TMP_DIR, exist_ok=True)

# ─── PALETTE ──────────────────────────────────────────────────────────────────
# Matches gen_rogue_sprites.py exactly

TRANSP       = (0,   0,   0,   0)

C_OUTLINE    = (26,  24,  32,  255)
C_DARK_EDGE  = (20,  18,  26,  255)

C_SKIN_D     = (150, 100, 70,  255)
C_SKIN_M     = (200, 140, 100, 255)
C_SKIN_L     = (230, 175, 135, 255)

C_HAIR_D     = (30,  22,  18,  255)
C_HAIR_M     = (55,  38,  28,  255)
C_HAIR_H     = (80,  58,  42,  255)

C_BAND_D     = (30,  35,  38,  255)
C_BAND_M     = (45,  55,  60,  255)
C_BAND_H     = (65,  80,  85,  255)

C_LEATH_D    = (42,  28,  18,  255)
C_LEATH_M    = (72,  52,  34,  255)
C_LEATH_H    = (105, 78,  52,  255)
C_LEATH_HL   = (140, 108, 76,  255)

C_CHAR_D     = (28,  28,  34,  255)
C_CHAR_M     = (42,  42,  52,  255)
C_CHAR_H     = (62,  62,  76,  255)

C_PURP_D     = (30,  18,  42,  255)
C_PURP_M     = (50,  30,  68,  255)

C_CLK_D      = (18,  42,  18,  255)
C_CLK_M      = (28,  72,  28,  255)
C_CLK_H      = (40,  100, 40,  255)
C_CLK_HL     = (60,  130, 55,  255)

C_DAG_D      = (80,  88,  100, 255)
C_DAG_M      = (130, 140, 160, 255)
C_DAG_H      = (185, 195, 215, 255)
C_DAG_HL     = (220, 228, 245, 255)

C_HILT_D     = (38,  28,  22,  255)
C_HILT_M     = (62,  46,  34,  255)

C_BELT_D     = (35,  25,  18,  255)
C_BELT_M     = (58,  44,  32,  255)
C_BUCKLE     = (160, 148, 100, 255)

C_SHADOW     = (20,  15,  28,  80)
C_SHADOW2    = (20,  15,  28,  40)

C_SMOKE_D    = (50,  45,  55,  180)
C_SMOKE_M    = (80,  75,  88,  120)
C_SMOKE_L    = (120, 115, 130, 60)

C_SPARK_Y    = (255, 220, 80,  255)
C_SPARK_W    = (255, 255, 200, 255)
C_SPARK_R    = (220, 60,  40,  255)   # blood/impact red
C_SPARK_O    = (255, 140, 30,  255)   # orange energy

C_TRAIL_D    = (100, 80,  120, 180)   # purple motion trail
C_TRAIL_L    = (160, 130, 190, 80)

C_SPEED_D    = (80,  60,  140, 200)   # deep purple speed aura
C_SPEED_L    = (150, 120, 220, 100)   # lighter speed glow
C_SPEED_W    = (200, 180, 255, 60)    # speed line white-purple

C_SHADOW_BODY = (20, 15, 28, 140)     # semi-transparent body (for defer)
C_SHADOW_FADE = (20, 15, 28, 70)

C_GOLD_H     = (220, 190, 80,  255)   # stolen loot sparkle
C_GOLD_M     = (180, 150, 50,  255)
C_GOLD_D     = (120, 90,  20,  255)

C_POUCH_D    = (45,  30,  20,  255)
C_POUCH_M    = (75,  55,  38,  255)


# ─── DRAWING PRIMITIVES ───────────────────────────────────────────────────────

def pp(arr, x, y, color):
    """Place one 2x2 super-pixel, clips silently at [0,256)."""
    for dy in range(2):
        for dx in range(2):
            px_, py_ = x + dx, y + dy
            if 0 <= px_ < 256 and 0 <= py_ < 256:
                arr[py_, px_] = color


def pp1(arr, x, y, color):
    """Place a single 1x1 pixel."""
    if 0 <= x < 256 and 0 <= y < 256:
        arr[y, x] = color


def hline(arr, x, y, w, color, step=2):
    for i in range(0, w, step):
        pp(arr, x + i, y, color)


def vline(arr, x, y, h, color, step=2):
    for i in range(0, h, step):
        pp(arr, x, y + i, color)


def rect_fill(arr, x, y, w, h, color):
    for row in range(y, y + h, 2):
        for col in range(x, x + w, 2):
            pp(arr, col, row, color)


def draw_line(arr, x0, y0, x1, y1, color, thick=2):
    """Bresenham thick line using super-pixels."""
    dx = x1 - x0
    dy = y1 - y0
    dist = math.hypot(dx, dy) or 1
    steps = max(int(dist) + 1, 2)
    nx = -dy / dist
    ny = dx / dist
    half = thick // 2
    for i in range(steps):
        t = i / (steps - 1)
        cx = int(x0 + dx * t) & ~1
        cy = int(y0 + dy * t) & ~1
        for off in range(-half, half + 1, 2):
            xi = int(cx + nx * off) & ~1
            yi = int(cy + ny * off) & ~1
            pp(arr, xi, yi, color)


def blend_px(arr, x, y, color):
    """Alpha-blend color over existing pixel."""
    if not (0 <= x < 256 and 0 <= y < 256):
        return
    bg = tuple(arr[y, x])
    src_a = color[3] / 255.0
    bg_a = bg[3] / 255.0
    out_a = src_a + bg_a * (1.0 - src_a)
    if out_a < 0.001:
        return
    nr = int((color[0] * src_a + bg[0] * bg_a * (1.0 - src_a)) / out_a)
    ng = int((color[1] * src_a + bg[1] * bg_a * (1.0 - src_a)) / out_a)
    nb = int((color[2] * src_a + bg[2] * bg_a * (1.0 - src_a)) / out_a)
    arr[y, x] = (nr, ng, nb, int(out_a * 255))


def new_frame():
    return np.zeros((256, 256, 4), dtype=np.uint8)


# ─── GROUND SHADOW ────────────────────────────────────────────────────────────

def draw_shadow(arr, cx, y, w=22, dy_offset=0):
    sy = y + dy_offset
    for sx in range(-w, w + 1, 2):
        af = max(0.0, 1.0 - (abs(sx) / w) ** 1.3)
        alpha = int(80 * af)
        for row_off in range(0, 4, 2):
            nx_, ny_ = cx + sx, sy + row_off
            if 0 <= nx_ < 256 and 0 <= ny_ < 256 and arr[ny_, nx_, 3] < 10:
                arr[ny_, nx_] = (20, 15, 28, alpha)


# ─── CHARACTER ANATOMY CONSTANTS ──────────────────────────────────────────────

CX    = 128
FEET  = 172
HEAD  = 82
NECK  = 100
SHLDR = 104
WAIST = 138
HIP   = 148

LSHLDR_X = 110
RSHLDR_X = 146
TORSO_L  = 112
TORSO_R  = 144
HEAD_L   = 114
HEAD_R   = 142


# ─── BODY DRAWING FUNCTIONS ───────────────────────────────────────────────────

def draw_head(arr, cx=CX, head_y=HEAD, dy=0, lean_x=0):
    """Draw the rogue head: angular face, bandana, dark hair."""
    hx = cx + lean_x
    hy = head_y + dy

    rect_fill(arr, hx - 10, hy,      24, 6, C_HAIR_M)
    rect_fill(arr, hx - 12, hy + 2,  28, 4, C_HAIR_D)
    pp(arr, hx - 12, hy,     C_HAIR_D)
    pp(arr, hx + 14, hy,     C_HAIR_D)

    rect_fill(arr, hx - 8,  hy + 6,  18, 14, C_SKIN_M)
    rect_fill(arr, hx - 8,  hy + 16, 18, 4,  C_SKIN_D)
    pp(arr, hx - 4, hy + 8,  C_SKIN_L)
    pp(arr, hx + 4, hy + 8,  C_SKIN_L)
    pp(arr, hx - 4, hy + 10, C_SKIN_L)

    pp(arr, hx - 4, hy + 10, C_OUTLINE)
    pp(arr, hx + 2, hy + 10, C_OUTLINE)
    pp(arr, hx - 2, hy + 10, C_SKIN_L)
    pp(arr, hx + 4, hy + 10, C_SKIN_L)

    pp(arr, hx - 2, hy + 16, C_OUTLINE)
    pp(arr, hx,     hy + 16, C_OUTLINE)
    pp(arr, hx + 2, hy + 16, C_SKIN_D)
    pp(arr, hx,     hy + 13, C_SKIN_D)

    rect_fill(arr, hx - 10, hy + 4, 22, 6, C_BAND_M)
    hline(arr, hx - 10, hy + 4, 22, C_BAND_H)
    hline(arr, hx - 10, hy + 8, 22, C_BAND_D)
    pp(arr, hx - 4, hy + 6, C_BAND_H)
    pp(arr, hx + 2, hy + 6, C_BAND_H)

    pp(arr, hx - 10, hy + 10, C_HAIR_M)
    pp(arr, hx - 10, hy + 12, C_HAIR_M)
    pp(arr, hx + 8,  hy + 10, C_HAIR_M)

    pp(arr, hx - 10, hy + 4,  C_OUTLINE)
    pp(arr, hx + 8,  hy + 4,  C_OUTLINE)
    pp(arr, hx - 10, hy + 18, C_OUTLINE)
    pp(arr, hx + 8,  hy + 18, C_OUTLINE)
    pp(arr, hx - 8,  hy + 20, C_OUTLINE)
    pp(arr, hx + 6,  hy + 20, C_OUTLINE)


def draw_head_alert(arr, cx=CX, dy=0, lean_x=0):
    """Head slightly tilted forward, eyes narrowed — alert state."""
    draw_head(arr, cx, HEAD, dy, lean_x)
    hx = cx + lean_x
    hy = HEAD + dy
    pp(arr, hx - 4, hy + 10, C_OUTLINE)
    pp(arr, hx - 2, hy + 10, C_OUTLINE)
    pp(arr, hx + 2, hy + 10, C_OUTLINE)
    pp(arr, hx + 4, hy + 10, C_OUTLINE)


def draw_head_smirk(arr, cx=CX, dy=0, lean_x=0):
    """Head with wider smirk — cocky/victorious expression."""
    draw_head(arr, cx, HEAD, dy, lean_x)
    hx = cx + lean_x
    hy = HEAD + dy
    # Wider smirk
    pp(arr, hx - 4, hy + 16, C_OUTLINE)
    pp(arr, hx - 2, hy + 16, C_OUTLINE)
    pp(arr, hx,     hy + 16, C_OUTLINE)
    pp(arr, hx + 2, hy + 16, C_SKIN_L)


def draw_head_turned(arr, cx=CX, dy=0):
    """Head turned away (flee/turning to run)."""
    hx = cx
    hy = HEAD + dy

    rect_fill(arr, hx - 6, hy,      20, 6, C_HAIR_M)
    rect_fill(arr, hx - 8, hy + 2,  22, 4, C_HAIR_D)

    # Face mostly showing back/side
    rect_fill(arr, hx - 4,  hy + 6,  14, 14, C_SKIN_M)
    rect_fill(arr, hx - 4,  hy + 16, 14, 4,  C_SKIN_D)
    # Only one visible eye
    pp(arr, hx + 2, hy + 10, C_OUTLINE)

    rect_fill(arr, hx - 8, hy + 4, 18, 6, C_BAND_M)
    hline(arr, hx - 8, hy + 4, 18, C_BAND_H)

    # Hair (more visible)
    pp(arr, hx - 8, hy + 10, C_HAIR_M)
    pp(arr, hx - 8, hy + 12, C_HAIR_D)
    pp(arr, hx + 8, hy + 10, C_HAIR_M)


def draw_torso(arr, cx=CX, dy=0, lean_x=0):
    """Draw rogue torso: charcoal chest plate, leather shoulder straps, belt."""
    tx = cx + lean_x
    ty = SHLDR + dy

    rect_fill(arr, tx - 14, ty,      30, 18, C_LEATH_M)
    rect_fill(arr, tx - 12, ty + 2,  26, 14, C_CHAR_M)

    pp(arr, tx - 6, ty + 4, C_CHAR_H)
    pp(arr, tx - 4, ty + 4, C_CHAR_H)
    pp(arr, tx - 2, ty + 4, C_CHAR_H)
    pp(arr, tx,     ty + 4, C_CHAR_H)

    for i in range(5):
        pp(arr, tx - 8 + i * 2, ty + i * 2, C_LEATH_H)

    vline(arr, tx - 2, ty + 2, 14, C_PURP_M)
    vline(arr, tx,     ty + 2, 14, C_PURP_D)

    rect_fill(arr, tx - 14, ty + 16, 30, 6, C_BELT_M)
    hline(arr, tx - 14, ty + 16, 30, C_BELT_D)
    hline(arr, tx - 14, ty + 20, 30, C_BELT_D)
    pp(arr, tx - 2, ty + 16, C_BUCKLE)
    pp(arr, tx,     ty + 16, C_BUCKLE)
    pp(arr, tx - 2, ty + 18, C_BUCKLE)

    rect_fill(arr, tx + 6, ty - 2, 10, 14, C_CLK_M)
    hline(arr, tx + 6,  ty - 2,  10, C_CLK_H)
    vline(arr, tx + 14, ty - 2,  12, C_CLK_D)
    pp(arr, tx + 6,  ty + 12, C_CLK_D)

    pp(arr, tx - 14, ty,      C_OUTLINE)
    pp(arr, tx + 14, ty,      C_OUTLINE)
    pp(arr, tx - 14, ty + 22, C_OUTLINE)
    pp(arr, tx + 14, ty + 22, C_OUTLINE)


def draw_torso_turned(arr, cx=CX, dy=0):
    """Torso turned to the side (flee pose)."""
    tx = cx
    ty = SHLDR + dy

    # Narrower torso visible (side view)
    rect_fill(arr, tx - 8,  ty,      20, 18, C_LEATH_M)
    rect_fill(arr, tx - 6,  ty + 2,  16, 14, C_CHAR_M)

    pp(arr, tx - 2, ty + 4, C_CHAR_H)
    pp(arr, tx,     ty + 4, C_CHAR_H)

    rect_fill(arr, tx - 8,  ty + 16, 20, 6, C_BELT_M)
    hline(arr, tx - 8, ty + 16, 20, C_BELT_D)
    pp(arr, tx - 2, ty + 16, C_BUCKLE)

    # Cloak streaming behind (to the left since turning right)
    rect_fill(arr, tx - 18, ty - 4,  14, 18, C_CLK_M)
    hline(arr, tx - 18, ty - 4, 14, C_CLK_H)
    vline(arr, tx - 18, ty - 4, 18, C_CLK_D)
    pp(arr, tx - 14, ty + 12, C_CLK_D)

    pp(arr, tx - 8,  ty,      C_OUTLINE)
    pp(arr, tx + 10, ty,      C_OUTLINE)


def draw_legs_idle(arr, cx=CX, dy=0):
    """Crouched ready stance: legs slightly bent, weight forward."""
    tx = cx
    ty = WAIST + dy

    rect_fill(arr, tx - 14, ty,      12, 12, C_LEATH_M)
    rect_fill(arr, tx - 14, ty + 10, 10, 12, C_CHAR_M)
    rect_fill(arr, tx - 16, ty + 20, 14, 8, C_LEATH_D)
    hline(arr, tx - 16, ty + 20, 14, C_LEATH_H)
    pp(arr, tx - 8, ty + 22, C_BUCKLE)

    rect_fill(arr, tx + 2,  ty - 2,  12, 12, C_LEATH_M)
    rect_fill(arr, tx + 2,  ty + 8,  10, 12, C_CHAR_M)
    rect_fill(arr, tx + 2,  ty + 18, 14, 8, C_LEATH_D)
    hline(arr, tx + 2,  ty + 18, 14, C_LEATH_H)
    pp(arr, tx + 8,  ty + 20, C_BUCKLE)

    pp(arr, tx - 12, ty + 10, C_LEATH_H)
    pp(arr, tx + 4,  ty + 8,  C_LEATH_H)

    pp(arr, tx - 14, ty + 28, C_OUTLINE)
    pp(arr, tx + 2,  ty + 26, C_OUTLINE)


def draw_legs_deep_crouch(arr, cx=CX, dy=0):
    """Deep crouch — knees wide, heels raised, ready to spring."""
    tx = cx
    ty = WAIST + dy

    # Thighs angled outward
    rect_fill(arr, tx - 18, ty,      14, 8, C_LEATH_M)
    rect_fill(arr, tx - 18, ty + 6,  12, 10, C_CHAR_M)
    # Shin — shin pulled back under body
    rect_fill(arr, tx - 14, ty + 14, 10, 10, C_CHAR_M)
    # Boot tip raised
    rect_fill(arr, tx - 18, ty + 22, 12, 6,  C_LEATH_D)
    hline(arr, tx - 18, ty + 22, 12, C_LEATH_H)
    pp(arr, tx - 10, ty + 24, C_BUCKLE)

    rect_fill(arr, tx + 4,  ty - 2,  14, 8, C_LEATH_M)
    rect_fill(arr, tx + 4,  ty + 6,  12, 10, C_CHAR_M)
    rect_fill(arr, tx + 4,  ty + 14, 10, 10, C_CHAR_M)
    rect_fill(arr, tx + 6,  ty + 22, 12, 6,  C_LEATH_D)
    hline(arr, tx + 6, ty + 22, 12, C_LEATH_H)
    pp(arr, tx + 12, ty + 24, C_BUCKLE)

    # Knee pad highlights
    pp(arr, tx - 14, ty + 8,  C_LEATH_H)
    pp(arr, tx + 6,  ty + 6,  C_LEATH_H)


def draw_arm_left(arr, cx=CX, dy=0, pose='idle'):
    """Left arm (character's left, viewer's right) holding secondary dagger."""
    tx = cx
    ty = SHLDR + dy

    if pose == 'idle':
        rect_fill(arr, tx - 16, ty + 2, 8, 10, C_LEATH_M)
        pp(arr, tx - 16, ty + 2, C_OUTLINE)
        rect_fill(arr, tx - 18, ty + 10, 8, 10, C_CHAR_M)
        hline(arr, tx - 18, ty + 10, 8, C_CHAR_H)
        rect_fill(arr, tx - 18, ty + 18, 6, 6, C_SKIN_M)
        draw_dagger(arr, tx - 16, ty + 22, angle_deg=210, short=True)

    elif pose == 'cross_low':
        # Arms crossed low in front — advance ready pose
        rect_fill(arr, tx - 14, ty + 6, 8, 10, C_LEATH_M)
        rect_fill(arr, tx - 10, ty + 14, 8, 10, C_CHAR_M)
        rect_fill(arr, tx - 6,  ty + 22, 6, 6,  C_SKIN_M)
        draw_dagger(arr, tx - 4, ty + 20, angle_deg=45, short=True)

    elif pose == 'cross_high':
        # Arms crossed higher, daggers X'ed in front of chest
        rect_fill(arr, tx - 12, ty,     8, 10, C_LEATH_M)
        rect_fill(arr, tx - 8,  ty + 8, 8, 10, C_CHAR_M)
        rect_fill(arr, tx - 4,  ty + 16, 6, 6, C_SKIN_M)
        draw_dagger(arr, tx - 2, ty + 14, angle_deg=30, short=True)

    elif pose == 'sprint':
        # Pumping arm — driven back for running
        rect_fill(arr, tx - 18, ty + 4, 8, 10, C_LEATH_M)
        rect_fill(arr, tx - 22, ty + 12, 8, 10, C_CHAR_M)
        rect_fill(arr, tx - 24, ty + 20, 6, 6,  C_SKIN_M)
        draw_dagger(arr, tx - 22, ty + 24, angle_deg=240, short=True)

    elif pose == 'reach_forward':
        # Arm fully extended forward
        rect_fill(arr, tx - 14, ty + 2, 8, 8, C_LEATH_M)
        rect_fill(arr, tx - 20, ty + 8, 8, 8, C_CHAR_M)
        rect_fill(arr, tx - 26, ty + 12, 6, 6, C_SKIN_M)
        draw_dagger(arr, tx - 24, ty + 16, angle_deg=190, short=True)

    elif pose == 'guard':
        rect_fill(arr, tx - 18, ty - 2, 8, 10, C_LEATH_M)
        rect_fill(arr, tx - 14, ty + 6, 8, 10, C_CHAR_M)
        rect_fill(arr, tx - 10, ty + 14, 6, 6, C_SKIN_M)
        draw_dagger(arr, tx - 8, ty + 12, angle_deg=45, short=True)

    elif pose == 'grab':
        # Hand reaching out with fingers open (grab/steal)
        rect_fill(arr, tx - 14, ty + 2, 8, 8, C_LEATH_M)
        rect_fill(arr, tx - 20, ty + 8, 8, 8, C_CHAR_M)
        rect_fill(arr, tx - 26, ty + 12, 8, 8, C_SKIN_M)
        # Fingers splayed
        for fi in range(4):
            pp(arr, tx - 26 - fi * 2, ty + 10 + fi, C_SKIN_D)

    elif pose == 'shadow':
        # Arm wrapping cloak around body
        rect_fill(arr, tx - 16, ty + 2, 8, 10, C_CLK_M)
        rect_fill(arr, tx - 14, ty + 10, 10, 10, C_CLK_D)
        rect_fill(arr, tx - 12, ty + 18, 8, 6,  C_CLK_D)

    elif pose == 'raise':
        rect_fill(arr, tx - 14, ty - 6, 8, 12, C_LEATH_M)
        rect_fill(arr, tx - 12, ty + 4,  6, 10, C_CHAR_M)
        rect_fill(arr, tx - 10, ty + 12, 6, 6,  C_SKIN_M)
        draw_dagger(arr, tx - 8, ty + 10, angle_deg=340, short=True)

    elif pose == 'loot':
        # Holding loot bag / examining item
        rect_fill(arr, tx - 16, ty + 4, 8, 10, C_LEATH_M)
        rect_fill(arr, tx - 18, ty + 12, 8, 10, C_CHAR_M)
        rect_fill(arr, tx - 18, ty + 20, 6, 6,  C_SKIN_M)
        # Small pouch in hand
        rect_fill(arr, tx - 22, ty + 18, 10, 10, C_POUCH_M)
        hline(arr, tx - 22, ty + 18, 10, C_POUCH_D)
        pp(arr, tx - 16, ty + 20, C_GOLD_H)


def draw_arm_right(arr, cx=CX, dy=0, pose='idle'):
    """Right arm (character's right, viewer's left) holding main dagger."""
    tx = cx
    ty = SHLDR + dy

    if pose == 'idle':
        rect_fill(arr, tx + 8,  ty + 2, 8, 10, C_LEATH_M)
        pp(arr, tx + 14, ty + 2, C_OUTLINE)
        rect_fill(arr, tx + 10, ty + 10, 8, 10, C_CHAR_M)
        hline(arr, tx + 10, ty + 10, 8, C_CHAR_H)
        rect_fill(arr, tx + 12, ty + 18, 6, 6, C_SKIN_M)
        draw_dagger(arr, tx + 14, ty + 22, angle_deg=160, short=False)

    elif pose == 'cross_low':
        rect_fill(arr, tx + 6,  ty + 6, 8, 10, C_LEATH_M)
        rect_fill(arr, tx + 2,  ty + 14, 8, 10, C_CHAR_M)
        rect_fill(arr, tx - 2,  ty + 22, 6, 6,  C_SKIN_M)
        draw_dagger(arr, tx,     ty + 20, angle_deg=135)

    elif pose == 'cross_high':
        rect_fill(arr, tx + 4,  ty,     8, 10, C_LEATH_M)
        rect_fill(arr, tx,      ty + 8, 8, 10, C_CHAR_M)
        rect_fill(arr, tx - 4,  ty + 16, 6, 6, C_SKIN_M)
        draw_dagger(arr, tx - 2, ty + 14, angle_deg=150)

    elif pose == 'sprint':
        # Pumping arm — driven forward for running
        rect_fill(arr, tx + 4,  ty,    8, 10, C_LEATH_M)
        rect_fill(arr, tx + 2,  ty + 8, 8, 10, C_CHAR_M)
        rect_fill(arr, tx,      ty + 16, 6, 6, C_SKIN_M)
        draw_dagger(arr, tx + 2, ty + 20, angle_deg=160)

    elif pose == 'reach_forward':
        rect_fill(arr, tx + 10, ty,     8, 8, C_LEATH_M)
        rect_fill(arr, tx + 16, ty + 6, 8, 8, C_CHAR_M)
        rect_fill(arr, tx + 22, ty + 12, 6, 6, C_SKIN_M)
        draw_dagger(arr, tx + 24, ty + 10, angle_deg=170)

    elif pose == 'slash':
        # Arm swept in slash motion
        rect_fill(arr, tx + 4,  ty - 2, 8, 10, C_LEATH_M)
        rect_fill(arr, tx - 2,  ty + 6, 8, 10, C_CHAR_M)
        rect_fill(arr, tx - 6,  ty + 14, 6, 6, C_SKIN_M)
        draw_dagger(arr, tx - 4, ty + 12, angle_deg=145)

    elif pose == 'thrust':
        # Arm thrust directly forward
        rect_fill(arr, tx + 6,  ty + 4, 10, 8, C_LEATH_M)
        rect_fill(arr, tx + 14, ty + 6, 10, 8, C_CHAR_M)
        rect_fill(arr, tx + 22, ty + 8,  6, 6, C_SKIN_M)
        draw_dagger(arr, tx + 24, ty + 10, angle_deg=180)

    elif pose == 'guard':
        rect_fill(arr, tx + 10, ty - 2, 8, 10, C_LEATH_M)
        rect_fill(arr, tx + 6,  ty + 6,  8, 10, C_CHAR_M)
        rect_fill(arr, tx + 2,  ty + 14, 6, 6,  C_SKIN_M)
        draw_dagger(arr, tx + 4, ty + 12, angle_deg=135, short=False)

    elif pose == 'shadow':
        # Cloak wrapped around
        rect_fill(arr, tx + 8,  ty + 2, 8, 10, C_CLK_M)
        rect_fill(arr, tx + 6,  ty + 10, 10, 10, C_CLK_D)
        rect_fill(arr, tx + 4,  ty + 18, 8, 6,  C_CLK_D)

    elif pose == 'smoke_throw':
        # Arm wound up to throw
        rect_fill(arr, tx + 10, ty - 4, 8, 10, C_LEATH_M)
        rect_fill(arr, tx + 14, ty + 4, 8, 10, C_CHAR_M)
        rect_fill(arr, tx + 16, ty + 12, 6, 6,  C_SKIN_M)
        # Small smoke bomb in fist
        pp(arr, tx + 18, ty + 10, C_OUTLINE)
        pp(arr, tx + 20, ty + 8,  C_CHAR_M)
        pp(arr, tx + 20, ty + 10, C_CHAR_H)

    elif pose == 'loot':
        rect_fill(arr, tx + 8,  ty + 2, 8, 10, C_LEATH_M)
        rect_fill(arr, tx + 10, ty + 10, 8, 10, C_CHAR_M)
        rect_fill(arr, tx + 12, ty + 18, 6, 6,  C_SKIN_M)
        draw_dagger(arr, tx + 14, ty + 22, angle_deg=160, short=False)


# ─── DAGGER DRAWING ───────────────────────────────────────────────────────────

def draw_dagger(arr, hx, hy, angle_deg=160, short=False):
    """Draw a curved dagger. hx,hy = grip position."""
    blade_len = 16 if short else 22
    rad = math.radians(angle_deg)
    bx_dir = math.cos(rad)
    by_dir = math.sin(rad)

    # Handle
    grip_len = 8
    for i in range(0, grip_len, 2):
        gx = int(hx - bx_dir * i) & ~1
        gy = int(hy - by_dir * i) & ~1
        pp(arr, gx - 2, gy, C_HILT_D)
        pp(arr, gx,     gy, C_HILT_M)
    pp(arr, int(hx - bx_dir * grip_len) & ~1 - 2,
           int(hy - by_dir * grip_len) & ~1,
           C_OUTLINE)

    # Guard
    px_dir = -by_dir
    py_dir = bx_dir
    for k in (-4, -2, 0, 2, 4):
        gx = int(hx + px_dir * k) & ~1
        gy = int(hy + py_dir * k) & ~1
        pp(arr, gx, gy, C_DAG_M)
    pp(arr, int(hx + px_dir * (-4)) & ~1, int(hy + py_dir * (-4)) & ~1, C_DAG_D)
    pp(arr, int(hx + px_dir * 4) & ~1,    int(hy + py_dir * 4) & ~1,    C_DAG_D)

    # Blade
    curve = 0.15
    for i in range(0, blade_len, 2):
        t = i / blade_len
        curve_off = curve * t * t * 6
        bpx = int(hx + bx_dir * i + px_dir * curve_off) & ~1
        bpy = int(hy + by_dir * i + py_dir * curve_off) & ~1
        taper = 1 if t > 0.7 else 0

        pp(arr, bpx - 2 + taper, bpy, C_DAG_D)
        pp(arr, bpx,             bpy, C_DAG_M)
        pp(arr, bpx + 2 - taper, bpy, C_DAG_H)
        if t < 0.5:
            pp(arr, bpx + 4, bpy, C_DAG_HL)

    tip_x = int(hx + bx_dir * blade_len) & ~1
    tip_y = int(hy + by_dir * blade_len) & ~1
    pp(arr, tip_x, tip_y, C_DAG_H)
    pp(arr, tip_x + 2, tip_y, C_DAG_HL)


def draw_dagger_standalone(arr, hx, hy, angle_deg=160):
    draw_dagger(arr, hx, hy, angle_deg, short=False)


# ─── EFFECT HELPERS ───────────────────────────────────────────────────────────

def draw_speed_lines(arr, cx, cy, count=6, length=30, angle_base=180):
    """Horizontal speed lines emanating left — motion blur effect."""
    for i in range(count):
        y_off = (i - count // 2) * 8
        x_start = cx - 10
        alpha_start = 180
        for x in range(0, length, 4):
            alpha = max(0, int(alpha_start * (1.0 - x / length)))
            col = (*C_SPEED_W[:3], alpha)
            blend_px(arr, x_start - x, cy + y_off, col)
            blend_px(arr, x_start - x, cy + y_off + 2, col)


def draw_motion_trail(arr, cx, cy, frames_behind=3, alpha_start=120):
    """Ghost trail of the character behind current position (to the left)."""
    for t in range(1, frames_behind + 1):
        offset = t * 12
        alpha = max(0, int(alpha_start * (1.0 - t / (frames_behind + 1))))
        col = (*C_TRAIL_D[:3], alpha)
        # Draw a rough silhouette ghost
        for dy in range(-30, 30, 4):
            for dx in range(-14, 14, 4):
                sx = cx - offset + dx
                sy = cy + dy
                if 0 <= sx < 256 and 0 <= sy < 256:
                    # Only place where character pixels would be
                    if abs(dx) < 12 and abs(dy) < 28:
                        blend_px(arr, sx, sy, col)


def draw_shadow_tendrils(arr, cx, cy, count=8, alpha=100):
    """Shadow tendrils curling up from feet — stealth/shadow effect."""
    for i in range(count):
        angle = math.radians(-90 + (i - count // 2) * 15)
        for dist in range(0, 30, 4):
            curve = math.sin(dist * 0.2 + i) * 8
            sx = int(cx + math.cos(angle) * dist * 0.5 + curve) & ~1
            sy = int(cy - dist) & ~1
            a = max(0, int(alpha * (1.0 - dist / 30.0)))
            blend_px(arr, sx, sy, (20, 15, 35, a))


def draw_sparkle_burst(arr, cx, cy, color, count=8, radius=14):
    """Star-burst sparkle effect (loot pickup, item use)."""
    for i in range(count):
        angle = i * (2 * math.pi / count)
        for dist in range(2, radius, 4):
            sx = int(cx + dist * math.cos(angle)) & ~1
            sy = int(cy + dist * math.sin(angle)) & ~1
            alpha = max(0, int(200 * (1.0 - dist / radius)))
            blend_px(arr, sx, sy, (*color[:3], alpha))
    pp(arr, cx, cy, C_SPARK_W)


def draw_smoke_puff(arr, cx, cy, radius=14, alpha_max=180):
    """Small smoke puff (smoke bomb, flee)."""
    for dy in range(-radius, radius + 1, 2):
        for dx in range(-radius, radius + 1, 2):
            d = math.hypot(dx, dy)
            if d > radius:
                continue
            t = d / radius
            col_base = C_SMOKE_D if t < 0.4 else C_SMOKE_M if t < 0.75 else C_SMOKE_L
            alpha = int(alpha_max * (1.0 - t * t))
            blend_px(arr, cx + dx, cy + dy, (*col_base[:3], alpha))


def draw_blood_effect(arr, cx, cy, count=6):
    """Small red splatter pixels — backstab critical hit."""
    for i in range(count):
        angle = math.radians(i * (360 / count) + 15)
        dist = 6 + (i % 3) * 4
        sx = int(cx + dist * math.cos(angle)) & ~1
        sy = int(cy + dist * math.sin(angle)) & ~1
        pp(arr, sx, sy, C_SPARK_R)
        # Smaller drop further out
        sx2 = int(cx + (dist + 6) * math.cos(angle)) & ~1
        sy2 = int(cy + (dist + 6) * math.sin(angle)) & ~1
        blend_px(arr, sx2, sy2, (*C_SPARK_R[:3], 140))


def draw_shadow_cloak(arr, cx, cy, alpha=140):
    """Draw a semi-transparent character outline (shadow/fading state)."""
    # Fill body area with shadow tint
    for dy in range(-50, 30, 2):
        for dx in range(-16, 16, 2):
            sx = cx + dx
            sy = cy + dy
            if 0 <= sx < 256 and 0 <= sy < 256:
                d_from_center = abs(dx) / 16.0
                edge_alpha = int(alpha * max(0, 1.0 - d_from_center ** 2))
                blend_px(arr, sx, sy, (15, 10, 25, edge_alpha))


def draw_gold_coins(arr, cx, cy, count=3):
    """Small scattered gold coins (stolen loot)."""
    offsets = [(-8, 0), (0, -6), (10, 4)]
    for i in range(min(count, len(offsets))):
        ox, oy = offsets[i]
        sx, sy = cx + ox, cy + oy
        pp(arr, sx, sy,     C_GOLD_H)
        pp(arr, sx + 2, sy, C_GOLD_M)
        pp(arr, sx, sy + 2, C_GOLD_D)
        pp(arr, sx + 2, sy + 2, C_GOLD_M)
        blend_px(arr, sx - 2, sy, (*C_SPARK_Y[:3], 120))


# ─── ADVANCE ANIMATION (4 frames) ─────────────────────────────────────────────
# Rogue drops into deep crouch, daggers cross, speed burst

def make_advance_frame(fn):
    arr = new_frame()

    # F0: slight crouch — first anticipation
    # F1: daggers drawn out + crouch deepens
    # F2: daggers crossed in front + purple speed aura
    # F3: full sprint-ready pose + motion blur trails behind

    lean  = [0, 2, 4, 6][fn]
    dy    = [0, 2, 4, 4][fn]   # crouch deepens (body lowers)
    cx    = CX + lean

    draw_torso(arr, cx, dy)

    ty = WAIST + dy

    if fn == 0:
        # Slight crouch — standard idle legs
        draw_legs_idle(arr, cx, dy)
        draw_arm_left(arr, cx, dy, pose='idle')
        draw_arm_right(arr, cx, dy, pose='idle')

    elif fn == 1:
        # Daggers drawn back — pre-cross stance
        draw_legs_deep_crouch(arr, cx, dy)
        # Right arm pulling dagger back
        tys = SHLDR + dy
        rect_fill(arr, cx + 8,  tys + 2, 8, 10, C_LEATH_M)
        rect_fill(arr, cx + 10, tys + 10, 8, 10, C_CHAR_M)
        rect_fill(arr, cx + 12, tys + 18, 6, 6,  C_SKIN_M)
        draw_dagger(arr, cx + 14, ty - 6, angle_deg=200)
        # Left arm mirrors
        rect_fill(arr, cx - 14, tys + 2, 8, 10, C_LEATH_M)
        rect_fill(arr, cx - 16, tys + 10, 8, 10, C_CHAR_M)
        rect_fill(arr, cx - 16, tys + 18, 6, 6,  C_SKIN_M)
        draw_dagger(arr, cx - 14, ty - 4, angle_deg=340, short=True)

    elif fn == 2:
        # Daggers crossed X in front — power pose
        draw_legs_deep_crouch(arr, cx, dy)
        draw_arm_left(arr, cx, dy, pose='cross_high')
        draw_arm_right(arr, cx, dy, pose='cross_high')
        # Cross spark at intersection
        sx = cx
        sy = SHLDR + dy + 14
        pp(arr, sx - 2, sy - 2, C_SPEED_D)
        pp(arr, sx + 2, sy - 2, C_SPEED_D)
        pp(arr, sx - 2, sy + 2, C_SPEED_L)
        pp(arr, sx + 2, sy + 2, C_SPEED_L)
        pp(arr, sx,     sy - 4, C_SPEED_W)
        pp(arr, sx,     sy + 4, C_SPEED_W)
        # Speed aura rings
        for r in range(8, 24, 6):
            for ai in range(0, 360, 30):
                ax = int(cx + r * math.cos(math.radians(ai))) & ~1
                ay = int(SHLDR + dy + 10 + r * math.sin(math.radians(ai * 0.6))) & ~1
                alpha = max(0, 100 - r * 4)
                blend_px(arr, ax, ay, (*C_SPEED_L[:3], alpha))

    elif fn == 3:
        # Full sprint-ready + motion blur trails
        draw_legs_deep_crouch(arr, cx, dy)
        draw_arm_left(arr, cx, dy, pose='cross_low')
        draw_arm_right(arr, cx, dy, pose='cross_low')

        # Motion blur ghost trails (3 behind)
        for t in range(1, 4):
            off = t * 10
            alpha = max(0, 90 - t * 25)
            ghost_col = (*C_TRAIL_D[:3], alpha)
            # Rough torso ghost
            for gy in range(SHLDR + dy - 10, WAIST + dy + 30, 4):
                for gx in range(-16, 16, 4):
                    blend_px(arr, cx - off + gx, gy, ghost_col)

        # Speed lines to the left
        draw_speed_lines(arr, cx - 16, SHLDR + dy + 10, count=5, length=40)

        # Bright aura edge
        for ai in range(0, 360, 20):
            for r in (18, 20, 22):
                ax = int(cx + r * 0.8 * math.cos(math.radians(ai))) & ~1
                ay = int(SHLDR + dy + 15 + r * math.sin(math.radians(ai))) & ~1
                blend_px(arr, ax, ay, (*C_SPEED_W[:3], 60))

    draw_head_alert(arr, cx, dy)
    draw_shadow(arr, cx, FEET, w=20 + fn * 2, dy_offset=dy)

    return Image.fromarray(arr, 'RGBA')


def gen_advance():
    frames = [make_advance_frame(i) for i in range(4)]
    strip = Image.new('RGBA', (1024, 256), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * 256, 0))
    return strip


# ─── DEFER ANIMATION (4 frames) ───────────────────────────────────────────────
# Rogue fades into shadows — cloak wraps, body becomes semi-transparent

def make_defer_frame(fn):
    arr = new_frame()

    # F0: step back, head lowered
    # F1: cloak wraps around body
    # F2: shadow tendrils emerge, body darkens
    # F3: mostly hidden in shadows (very dark, semi-transparent)

    lean  = [-2, -4, -6, -8][fn]
    dy    = [0,  2,  4,  6][fn]
    cx    = CX + lean

    if fn == 0:
        # Normal pose stepping back
        draw_torso(arr, cx, dy)
        draw_legs_idle(arr, cx, dy)
        draw_arm_left(arr, cx, dy, pose='idle')
        draw_arm_right(arr, cx, dy, pose='idle')
        draw_head_alert(arr, cx, dy)

    elif fn == 1:
        # Cloak starts to wrap around — arms pulling cloak inward
        draw_torso(arr, cx, dy)
        draw_legs_idle(arr, cx, dy)
        draw_arm_left(arr, cx, dy, pose='shadow')
        draw_arm_right(arr, cx, dy, pose='shadow')
        draw_head(arr, cx, HEAD, dy)
        # Extra cloak spread
        tys = SHLDR + dy
        rect_fill(arr, cx - 20, tys - 4, 14, 24, C_CLK_D)
        hline(arr, cx - 20, tys - 4, 14, C_CLK_M)
        rect_fill(arr, cx + 8, tys - 4,  14, 24, C_CLK_D)

    elif fn == 2:
        # Body darkening — draw dark overlay
        draw_torso(arr, cx, dy)
        draw_legs_idle(arr, cx, dy)
        draw_arm_left(arr, cx, dy, pose='shadow')
        draw_arm_right(arr, cx, dy, pose='shadow')
        draw_head(arr, cx, HEAD, dy)

        # Dark shadow wash over body
        for gy in range(HEAD + dy, FEET + dy, 2):
            for gx in range(cx - 20, cx + 20, 2):
                if 0 <= gx < 256 and 0 <= gy < 256:
                    blend_px(arr, gx, gy, (10, 8, 20, 80))

        # Shadow tendrils from feet
        draw_shadow_tendrils(arr, cx, FEET + dy, count=7, alpha=120)

        # Cloak fully wrapped
        tys = SHLDR + dy
        rect_fill(arr, cx - 22, tys - 6, 16, 30, C_CLK_D)
        rect_fill(arr, cx + 6,  tys - 6, 16, 30, C_CLK_D)

    elif fn == 3:
        # Mostly in shadows — very dark, semi-transparent
        # Draw character shapes with heavily reduced alpha
        draw_torso(arr, cx, dy)
        draw_legs_idle(arr, cx, dy)
        draw_head(arr, cx, HEAD, dy)

        # Heavy dark shadow wash — body barely visible
        for gy in range(HEAD + dy - 4, FEET + dy + 4, 2):
            for gx in range(cx - 22, cx + 22, 2):
                if 0 <= gx < 256 and 0 <= gy < 256:
                    blend_px(arr, gx, gy, (8, 5, 18, 160))

        # Shadow tendrils heavy
        draw_shadow_tendrils(arr, cx, FEET + dy, count=10, alpha=160)
        draw_shadow_tendrils(arr, cx - 6, FEET + dy - 4, count=6, alpha=100)
        draw_shadow_tendrils(arr, cx + 4, FEET + dy - 2, count=6, alpha=100)

        # Cloak fully enveloping — large dark mass
        tys = SHLDR + dy
        rect_fill(arr, cx - 24, tys - 8, 20, 36, C_CLK_D)
        rect_fill(arr, cx + 4,  tys - 8, 20, 36, C_CLK_D)
        # Just barely visible eyes gleaming in shadow
        hx = cx
        hy = HEAD + dy
        pp(arr, hx - 4, hy + 10, (80, 200, 80, 200))    # faint green gleam
        pp(arr, hx + 2, hy + 10, (80, 200, 80, 200))

    draw_shadow(arr, cx, FEET, w=16 + fn * 2, dy_offset=dy)

    return Image.fromarray(arr, 'RGBA')


def gen_defer():
    frames = [make_defer_frame(i) for i in range(4)]
    strip = Image.new('RGBA', (1024, 256), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * 256, 0))
    return strip


# ─── STEAL ANIMATION (6 frames) ───────────────────────────────────────────────
# Quick dash forward, reach, grab, snatch, retreat, examine loot

def make_steal_frame(fn):
    arr = new_frame()

    # F0: quick dash forward (motion blur)
    # F1: hand reaches toward target
    # F2: grabbing motion with sparkle
    # F3: snatching back
    # F4: retreating
    # F5: examining loot with smirk

    lean  = [8,  14, 14, 10, 4, 0][fn]
    dy    = [-2, -4, -2,  0, 0, 0][fn]
    cx    = CX + lean

    draw_torso(arr, cx, dy)
    tys = SHLDR + dy

    if fn == 0:
        # Dash forward — lunging pose, motion blur
        ty = WAIST + dy
        rect_fill(arr, cx - 20, ty,     12, 10, C_LEATH_M)
        rect_fill(arr, cx - 22, ty + 8, 12, 12, C_CHAR_M)
        rect_fill(arr, cx - 24, ty + 18, 16, 8, C_LEATH_D)
        hline(arr, cx - 24, ty + 18, 16, C_LEATH_H)
        rect_fill(arr, cx + 2,  ty - 4, 12, 10, C_LEATH_M)
        rect_fill(arr, cx + 4,  ty + 4, 10, 12, C_CHAR_M)
        rect_fill(arr, cx + 4,  ty + 14, 14, 8, C_LEATH_D)
        hline(arr, cx + 4, ty + 14, 14, C_LEATH_H)
        # Arms pumping
        draw_arm_left(arr, cx, dy, pose='sprint')
        draw_arm_right(arr, cx, dy, pose='sprint')
        # Motion blur trails
        for t in range(1, 4):
            off = t * 12
            alpha = max(0, 80 - t * 22)
            for gy in range(tys - 10, WAIST + dy + 28, 4):
                for gx in range(-14, 14, 4):
                    blend_px(arr, cx - off + gx, gy, (*C_TRAIL_D[:3], alpha))
        draw_head_alert(arr, cx, dy, lean_x=-2)

    elif fn == 1:
        # Reach out — right arm fully extended forward-right (toward target)
        draw_legs_idle(arr, cx, dy)
        # Right arm reaching far forward
        rect_fill(arr, cx + 4,  tys,     8, 8, C_LEATH_M)
        rect_fill(arr, cx + 12, tys + 4, 8, 8, C_CHAR_M)
        rect_fill(arr, cx + 20, tys + 8, 8, 8, C_SKIN_M)
        # Hand / fingers extended
        pp(arr, cx + 28, tys + 8,  C_SKIN_M)
        pp(arr, cx + 30, tys + 6,  C_SKIN_D)
        pp(arr, cx + 30, tys + 10, C_SKIN_D)
        # Left arm with dagger guard
        draw_arm_left(arr, cx, dy, pose='guard')
        draw_head_alert(arr, cx, dy)

    elif fn == 2:
        # Grab — hand closed on item, sparkle
        draw_legs_idle(arr, cx, dy)
        rect_fill(arr, cx + 4,  tys,     8, 8, C_LEATH_M)
        rect_fill(arr, cx + 12, tys + 4, 8, 8, C_CHAR_M)
        rect_fill(arr, cx + 20, tys + 8, 8, 8, C_SKIN_M)
        # Closed fist
        rect_fill(arr, cx + 26, tys + 7, 8, 8, C_SKIN_D)
        pp(arr, cx + 26, tys + 6, C_OUTLINE)
        pp(arr, cx + 32, tys + 6, C_OUTLINE)
        # Sparkle at grab point
        draw_sparkle_burst(arr, cx + 30, tys + 6, C_GOLD_H, count=6, radius=12)
        draw_arm_left(arr, cx, dy, pose='guard')
        draw_head_alert(arr, cx, dy)

    elif fn == 3:
        # Snatch back — arm pulling back with loot
        draw_legs_idle(arr, cx, dy)
        rect_fill(arr, cx + 4,  tys + 2, 8, 10, C_LEATH_M)
        rect_fill(arr, cx + 8,  tys + 10, 8, 10, C_CHAR_M)
        rect_fill(arr, cx + 10, tys + 18, 6, 6,  C_SKIN_M)
        # Small loot glint in hand
        pp(arr, cx + 12, tys + 16, C_GOLD_H)
        pp(arr, cx + 14, tys + 14, C_GOLD_M)
        draw_arm_left(arr, cx, dy, pose='guard')
        draw_head_alert(arr, cx, dy)

    elif fn == 4:
        # Retreating dash backward
        ty = WAIST + dy
        rect_fill(arr, cx - 14, ty,      12, 10, C_LEATH_M)
        rect_fill(arr, cx - 14, ty + 8,  10, 12, C_CHAR_M)
        rect_fill(arr, cx - 16, ty + 18, 14, 8,  C_LEATH_D)
        hline(arr, cx - 16, ty + 18, 14, C_LEATH_H)
        rect_fill(arr, cx + 2,  ty - 2,  12, 10, C_LEATH_M)
        rect_fill(arr, cx + 2,  ty + 6,  10, 12, C_CHAR_M)
        rect_fill(arr, cx + 2,  ty + 16, 14, 8,  C_LEATH_D)
        hline(arr, cx + 2, ty + 16, 14, C_LEATH_H)
        draw_arm_left(arr, cx, dy, pose='loot')
        draw_arm_right(arr, cx, dy, pose='idle')
        draw_head_alert(arr, cx, dy, lean_x=2)

    elif fn == 5:
        # Examining loot — smirk, holding item up slightly
        draw_legs_idle(arr, cx, dy)
        draw_arm_left(arr, cx, dy, pose='loot')
        draw_arm_right(arr, cx, dy, pose='idle')
        # Gold coins scatter
        draw_gold_coins(arr, cx - 20, tys + 22, count=3)
        # Small sparkles above held loot
        blend_px(arr, cx - 24, tys + 10, (*C_GOLD_H[:3], 180))
        blend_px(arr, cx - 20, tys + 6,  (*C_GOLD_H[:3], 120))
        draw_head_smirk(arr, cx, dy)

    draw_shadow(arr, cx, FEET, w=20, dy_offset=dy)

    return Image.fromarray(arr, 'RGBA')


def gen_steal():
    frames = [make_steal_frame(i) for i in range(6)]
    strip = Image.new('RGBA', (1536, 256), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * 256, 0))
    return strip


# ─── BACKSTAB ANIMATION (6 frames) ────────────────────────────────────────────
# Critical backstab — vanish, reappear behind, thrust, flash, withdraw, flip back

def make_backstab_frame(fn):
    arr = new_frame()

    # F0: vanish (fade to shadow — body half-transparent)
    # F1: appear behind target (dark smoke puff at new position)
    # F2: daggers thrust forward — both weapons striking
    # F3: critical hit flash (bright yellow/white burst)
    # F4: daggers withdraw with blood effect
    # F5: flip back to starting position

    lean  = [0,  -16, -14, -14, -10, 2][fn]
    dy    = [0,   0,  -4,  -2,   0, -2][fn]
    cx    = CX + lean

    if fn == 0:
        # Vanish — draw character with dark overlay (fading out)
        draw_torso(arr, cx, dy)
        draw_legs_idle(arr, cx, dy)
        draw_arm_left(arr, cx, dy, pose='idle')
        draw_arm_right(arr, cx, dy, pose='idle')
        draw_head_alert(arr, cx, dy)
        # Dark shadow wash over everything
        for gy in range(HEAD + dy - 4, FEET + dy + 4, 2):
            for gx in range(cx - 20, cx + 20, 2):
                if 0 <= gx < 256 and 0 <= gy < 256:
                    blend_px(arr, gx, gy, (10, 5, 20, 140))
        # Shadow wisps leaving the body
        draw_shadow_tendrils(arr, cx, FEET + dy, count=8, alpha=100)

    elif fn == 1:
        # Reappear behind — smoke puff at new position
        draw_smoke_puff(arr, cx, HEAD + dy + 10, radius=24, alpha_max=160)
        # Character emerging from smoke (partially visible)
        draw_torso(arr, cx, dy)
        draw_legs_idle(arr, cx, dy)
        draw_arm_left(arr, cx, dy, pose='idle')
        draw_arm_right(arr, cx, dy, pose='reach_forward')
        draw_head_alert(arr, cx, dy)
        # Dark tint (just emerged)
        for gy in range(HEAD + dy - 4, FEET + dy + 4, 2):
            for gx in range(cx - 20, cx + 20, 2):
                if 0 <= gx < 256 and 0 <= gy < 256:
                    blend_px(arr, gx, gy, (10, 5, 20, 60))

    elif fn == 2:
        # Both daggers thrust forward — powerful double-strike
        draw_torso(arr, cx, dy)
        ty = WAIST + dy
        # Forward lunge legs
        rect_fill(arr, cx - 20, ty,     12, 10, C_LEATH_M)
        rect_fill(arr, cx - 22, ty + 8, 12, 12, C_CHAR_M)
        rect_fill(arr, cx - 24, ty + 18, 16, 8, C_LEATH_D)
        hline(arr, cx - 24, ty + 18, 16, C_LEATH_H)
        rect_fill(arr, cx + 2,  ty - 4, 12, 10, C_LEATH_M)
        rect_fill(arr, cx + 4,  ty + 4, 10, 12, C_CHAR_M)
        rect_fill(arr, cx + 4,  ty + 14, 14, 8, C_LEATH_D)
        hline(arr, cx + 4, ty + 14, 14, C_LEATH_H)
        # Both arms thrusting forward hard
        draw_arm_left(arr, cx, dy, pose='reach_forward')
        draw_arm_right(arr, cx, dy, pose='thrust')
        draw_head_alert(arr, cx, dy)

    elif fn == 3:
        # Critical hit flash — bright burst
        draw_torso(arr, cx, dy)
        draw_legs_idle(arr, cx, dy)
        draw_arm_left(arr, cx, dy, pose='reach_forward')
        draw_arm_right(arr, cx, dy, pose='thrust')
        # Large critical flash burst (yellow-white)
        hit_x = cx + 40
        hit_y = SHLDR + dy + 10
        for r in range(2, 30, 4):
            for ai in range(0, 360, 20):
                ax = int(hit_x + r * math.cos(math.radians(ai))) & ~1
                ay = int(hit_y + r * math.sin(math.radians(ai))) & ~1
                alpha = max(0, 200 - r * 8)
                col = C_SPARK_W if r < 14 else C_SPARK_Y
                blend_px(arr, ax, ay, (*col[:3], alpha))
        pp(arr, hit_x, hit_y, C_SPARK_W)
        pp(arr, hit_x + 2, hit_y, C_SPARK_W)
        pp(arr, hit_x, hit_y + 2, C_SPARK_W)
        # CRIT text-like pixel pattern (simplified star shape)
        for ai in (0, 45, 90, 135, 180, 225, 270, 315):
            ax = int(hit_x + 6 * math.cos(math.radians(ai))) & ~1
            ay = int(hit_y + 6 * math.sin(math.radians(ai))) & ~1
            pp(arr, ax, ay, C_SPARK_Y)
        draw_head_alert(arr, cx, dy)

    elif fn == 4:
        # Withdraw daggers — blood effect (red pixels)
        draw_torso(arr, cx, dy)
        draw_legs_idle(arr, cx, dy)
        # Arms pulling back
        tys = SHLDR + dy
        rect_fill(arr, cx + 2,  tys + 2, 8, 10, C_LEATH_M)
        rect_fill(arr, cx + 4,  tys + 10, 8, 10, C_CHAR_M)
        rect_fill(arr, cx + 6,  tys + 18, 6, 6,  C_SKIN_M)
        draw_dagger(arr, cx + 8, tys + 22, angle_deg=165)
        rect_fill(arr, cx - 14, tys + 2, 8, 10, C_LEATH_M)
        rect_fill(arr, cx - 14, tys + 10, 8, 10, C_CHAR_M)
        rect_fill(arr, cx - 14, tys + 18, 6, 6,  C_SKIN_M)
        draw_dagger(arr, cx - 12, tys + 22, angle_deg=200, short=True)
        # Blood splatter where target is (forward-right)
        draw_blood_effect(arr, cx + 36, tys + 12, count=8)
        draw_head_alert(arr, cx, dy)

    elif fn == 5:
        # Flip back — mid-air flip returning to position
        # Character body slightly diagonal/rotated
        cx_f = CX + 2
        tys = SHLDR + dy
        ty = WAIST + dy
        # Body at slight tilt (jumping back)
        draw_torso(arr, cx_f, dy - 6)  # slightly elevated
        # Legs tucked up for flip
        rect_fill(arr, cx_f - 12, ty - 4, 12, 8,  C_LEATH_M)
        rect_fill(arr, cx_f + 2,  ty - 6, 12, 8,  C_LEATH_M)
        rect_fill(arr, cx_f - 14, ty + 4, 10, 6,  C_CHAR_M)
        rect_fill(arr, cx_f + 2,  ty + 2, 10, 6,  C_CHAR_M)
        # Boots up (tucked)
        rect_fill(arr, cx_f - 12, ty + 8, 12, 6,  C_LEATH_D)
        rect_fill(arr, cx_f + 2,  ty + 6, 12, 6,  C_LEATH_D)
        draw_arm_left(arr, cx_f, dy - 6, pose='raise')
        draw_arm_right(arr, cx_f, dy - 6, pose='idle')
        draw_head_alert(arr, cx_f, dy - 6)
        # Motion trail from flip
        for t in range(1, 3):
            off = t * 14
            for gy in range(tys - 10, ty + 20, 4):
                for gx in range(-14, 14, 4):
                    blend_px(arr, cx_f + off + gx, gy, (*C_TRAIL_D[:3], 50 - t * 15))
        draw_shadow(arr, cx_f, FEET, w=18, dy_offset=dy - 2)
        return Image.fromarray(arr, 'RGBA')

    draw_shadow(arr, cx, FEET, w=20, dy_offset=dy)

    return Image.fromarray(arr, 'RGBA')


def gen_backstab():
    frames = [make_backstab_frame(i) for i in range(6)]
    strip = Image.new('RGBA', (1536, 256), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * 256, 0))
    return strip


# ─── MUG ANIMATION (6 frames) ─────────────────────────────────────────────────
# Attack+steal combo — dash, slash, grab, pull back with loot, dodge, land

def make_mug_frame(fn):
    arr = new_frame()

    # F0: dash forward with intent
    # F1: dagger slash (attack motion)
    # F2: impact + other hand grabbing simultaneously
    # F3: pulling back with loot (slash residue)
    # F4: flip/dodge backward
    # F5: land with stolen goods + smirk

    lean  = [10, 14, 14, 8, 2, 0][fn]
    dy    = [-2, -4, -2,  0, -4, 0][fn]
    cx    = CX + lean

    draw_torso(arr, cx, dy)
    tys = SHLDR + dy
    ty  = WAIST + dy

    if fn == 0:
        # Dash forward — forward lunge legs
        rect_fill(arr, cx - 20, ty,     12, 10, C_LEATH_M)
        rect_fill(arr, cx - 22, ty + 8, 12, 12, C_CHAR_M)
        rect_fill(arr, cx - 24, ty + 18, 16, 8, C_LEATH_D)
        hline(arr, cx - 24, ty + 18, 16, C_LEATH_H)
        rect_fill(arr, cx + 2,  ty - 4, 12, 10, C_LEATH_M)
        rect_fill(arr, cx + 4,  ty + 4, 10, 12, C_CHAR_M)
        rect_fill(arr, cx + 4,  ty + 14, 14, 8, C_LEATH_D)
        hline(arr, cx + 4, ty + 14, 14, C_LEATH_H)
        draw_arm_left(arr, cx, dy, pose='sprint')
        draw_arm_right(arr, cx, dy, pose='sprint')
        draw_head_alert(arr, cx, dy, lean_x=-2)
        # Motion blur
        for t in range(1, 3):
            off = t * 10
            alpha = max(0, 70 - t * 25)
            for gy in range(tys - 8, ty + 24, 4):
                for gx in range(-14, 14, 4):
                    blend_px(arr, cx - off + gx, gy, (*C_TRAIL_D[:3], alpha))

    elif fn == 1:
        # Slash — right arm sweeping, momentum
        rect_fill(arr, cx - 18, ty,      12, 10, C_LEATH_M)
        rect_fill(arr, cx - 20, ty + 8,  12, 12, C_CHAR_M)
        rect_fill(arr, cx - 22, ty + 18, 14, 8,  C_LEATH_D)
        hline(arr, cx - 22, ty + 18, 14, C_LEATH_H)
        rect_fill(arr, cx + 2,  ty - 2,  12, 10, C_LEATH_M)
        rect_fill(arr, cx + 4,  ty + 6,  10, 12, C_CHAR_M)
        rect_fill(arr, cx + 4,  ty + 16, 14, 8,  C_LEATH_D)
        hline(arr, cx + 4, ty + 16, 14, C_LEATH_H)
        draw_arm_left(arr, cx, dy, pose='guard')
        draw_arm_right(arr, cx, dy, pose='slash')
        # Slash trail arc
        for t in range(1, 4):
            for ai in range(120, 180, 12):
                r = 20 + t * 4
                ax = int(cx + r * math.cos(math.radians(ai))) & ~1
                ay = int(tys + 12 + r * math.sin(math.radians(ai))) & ~1
                alpha = max(0, 100 - t * 28)
                blend_px(arr, ax, ay, (*C_TRAIL_D[:3], alpha))
        draw_head_alert(arr, cx, dy)

    elif fn == 2:
        # Impact + grab — dagger hit + free hand grabs simultaneously
        draw_legs_idle(arr, cx, dy)
        # Right arm at impact extension (slash follow-through)
        rect_fill(arr, cx + 2,  tys + 2, 8, 8,  C_LEATH_M)
        rect_fill(arr, cx - 4,  tys + 8, 8, 8,  C_CHAR_M)
        rect_fill(arr, cx - 8,  tys + 14, 6, 6, C_SKIN_M)
        draw_dagger(arr, cx - 6, tys + 12, angle_deg=145)
        # Left arm reaching out to grab
        draw_arm_left(arr, cx, dy, pose='grab')
        # Impact sparks (slash hit)
        sx = cx - 4
        sy = tys + 12
        for ai in range(0, 360, 45):
            for dist in range(4, 16, 4):
                ax = int(sx + dist * math.cos(math.radians(ai))) & ~1
                ay = int(sy + dist * math.sin(math.radians(ai))) & ~1
                col = C_SPARK_Y if (ai // 45) % 2 == 0 else C_SPARK_W
                alpha = max(0, 180 - dist * 12)
                blend_px(arr, ax, ay, (*col[:3], alpha))
        # Loot sparkle on grab side
        draw_sparkle_burst(arr, cx - 28, tys + 14, C_GOLD_H, count=6, radius=10)
        draw_head_alert(arr, cx, dy)

    elif fn == 3:
        # Pull back — both arms bringing in the haul
        draw_legs_idle(arr, cx, dy)
        # Right arm with dagger returning
        rect_fill(arr, cx + 6,  tys + 2, 8, 10, C_LEATH_M)
        rect_fill(arr, cx + 8,  tys + 10, 8, 10, C_CHAR_M)
        rect_fill(arr, cx + 10, tys + 18, 6, 6,  C_SKIN_M)
        draw_dagger(arr, cx + 12, tys + 22, angle_deg=160)
        # Left arm with loot pulled to chest
        rect_fill(arr, cx - 14, tys + 4, 8, 10, C_LEATH_M)
        rect_fill(arr, cx - 14, tys + 12, 8, 10, C_CHAR_M)
        rect_fill(arr, cx - 14, tys + 20, 6, 6,  C_SKIN_M)
        # Loot pouch in hand, gold visible
        rect_fill(arr, cx - 18, tys + 18, 10, 10, C_POUCH_M)
        hline(arr, cx - 18, tys + 18, 10, C_POUCH_D)
        pp(arr, cx - 14, tys + 20, C_GOLD_H)
        pp(arr, cx - 12, tys + 22, C_GOLD_M)
        draw_head_alert(arr, cx, dy)

    elif fn == 4:
        # Flip/dodge backward — body airborne, leaping back
        # Elevated position
        dy_flip = dy - 8
        draw_torso(arr, cx, dy_flip)
        ty_flip = WAIST + dy_flip
        rect_fill(arr, cx - 12, ty_flip - 4, 12, 8,  C_LEATH_M)
        rect_fill(arr, cx + 2,  ty_flip - 6, 12, 8,  C_LEATH_M)
        rect_fill(arr, cx - 14, ty_flip + 4, 10, 6,  C_CHAR_M)
        rect_fill(arr, cx + 2,  ty_flip + 2, 10, 6,  C_CHAR_M)
        rect_fill(arr, cx - 12, ty_flip + 8, 12, 6,  C_LEATH_D)
        rect_fill(arr, cx + 2,  ty_flip + 6, 12, 6,  C_LEATH_D)
        draw_arm_right(arr, cx, dy_flip, pose='idle')
        draw_arm_left(arr, cx, dy_flip, pose='loot')
        draw_head_alert(arr, cx, dy_flip)
        # Jump arc trail
        for t in range(1, 3):
            off = t * 12
            for gy in range(SHLDR + dy_flip - 8, WAIST + dy_flip + 16, 4):
                for gx in range(-14, 14, 4):
                    blend_px(arr, cx + off + gx, gy, (*C_TRAIL_L[:3], 50 - t * 15))
        draw_shadow(arr, cx, FEET, w=16, dy_offset=dy)
        return Image.fromarray(arr, 'RGBA')

    elif fn == 5:
        # Land — feet hit ground, loot held up triumphantly
        draw_legs_idle(arr, cx, dy)
        draw_arm_right(arr, cx, dy, pose='idle')
        # Left arm raised with loot (showing it off)
        rect_fill(arr, cx - 14, tys - 4, 8, 12, C_LEATH_M)
        rect_fill(arr, cx - 12, tys + 6, 6, 10, C_CHAR_M)
        rect_fill(arr, cx - 10, tys + 14, 6, 6,  C_SKIN_M)
        # Loot pouch held high
        rect_fill(arr, cx - 14, tys - 10, 12, 12, C_POUCH_M)
        hline(arr, cx - 14, tys - 10, 12, C_POUCH_D)
        pp(arr, cx - 10, tys - 6, C_GOLD_H)
        pp(arr, cx - 8,  tys - 4, C_GOLD_H)
        # Sparkles from loot
        blend_px(arr, cx - 8, tys - 14, (*C_GOLD_H[:3], 180))
        blend_px(arr, cx - 4, tys - 16, (*C_SPARK_Y[:3], 150))
        blend_px(arr, cx - 12, tys - 16, (*C_SPARK_W[:3], 120))
        # Landing dust puff
        draw_smoke_puff(arr, cx, FEET + dy, radius=10, alpha_max=80)
        draw_head_smirk(arr, cx, dy)

    draw_shadow(arr, cx, FEET, w=20, dy_offset=dy)

    return Image.fromarray(arr, 'RGBA')


def gen_mug():
    frames = [make_mug_frame(i) for i in range(6)]
    strip = Image.new('RGBA', (1536, 256), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * 256, 0))
    return strip


# ─── FLEE ANIMATION (4 frames) ────────────────────────────────────────────────
# Turn, smoke bomb, sprint, gone

def make_flee_frame(fn):
    arr = new_frame()

    # F0: turn away — body rotating 180
    # F1: smoke bomb throw — tossed at feet behind (toward viewer)
    # F2: sprinting away with speed lines (back to viewer)
    # F3: gone — only smoke cloud remains at original spot

    if fn == 0:
        # Turning pose — body mid-rotation, one side visible
        cx = CX
        dy = 0
        draw_torso_turned(arr, cx, dy)
        tys = SHLDR + dy
        ty  = WAIST + dy
        # Mid-stride turning legs
        rect_fill(arr, cx - 10, ty,      12, 10, C_LEATH_M)
        rect_fill(arr, cx - 10, ty + 8,  10, 12, C_CHAR_M)
        rect_fill(arr, cx - 12, ty + 18, 14, 8,  C_LEATH_D)
        hline(arr, cx - 12, ty + 18, 14, C_LEATH_H)
        rect_fill(arr, cx + 4,  ty - 2,  12, 10, C_LEATH_M)
        rect_fill(arr, cx + 4,  ty + 6,  10, 12, C_CHAR_M)
        rect_fill(arr, cx + 4,  ty + 16, 14, 8,  C_LEATH_D)
        hline(arr, cx + 4, ty + 16, 14, C_LEATH_H)
        # One arm visible swinging
        rect_fill(arr, cx + 4,  tys + 2, 8, 10, C_LEATH_M)
        rect_fill(arr, cx + 6,  tys + 10, 8, 10, C_CHAR_M)
        rect_fill(arr, cx + 8,  tys + 18, 6, 6,  C_SKIN_M)
        draw_dagger(arr, cx + 10, tys + 22, angle_deg=160)
        # Other arm starting turn motion
        rect_fill(arr, cx - 10, tys + 4, 8, 8, C_LEATH_M)
        rect_fill(arr, cx - 8,  tys + 10, 8, 8, C_CHAR_M)
        draw_head_turned(arr, cx, dy)
        draw_shadow(arr, cx, FEET, w=20, dy_offset=dy)

    elif fn == 1:
        # Smoke bomb throw — facing away, arm flung back toward viewer
        cx = CX
        dy = -2
        draw_torso_turned(arr, cx, dy)
        tys = SHLDR + dy
        ty  = WAIST + dy
        # Running legs
        rect_fill(arr, cx - 14, ty + 2,  12, 10, C_LEATH_M)
        rect_fill(arr, cx - 14, ty + 10, 10, 12, C_CHAR_M)
        rect_fill(arr, cx - 16, ty + 20, 14, 8,  C_LEATH_D)
        hline(arr, cx - 16, ty + 20, 14, C_LEATH_H)
        rect_fill(arr, cx + 2,  ty - 4,  12, 10, C_LEATH_M)
        rect_fill(arr, cx + 4,  ty + 4,  10, 12, C_CHAR_M)
        rect_fill(arr, cx + 4,  ty + 14, 14, 8,  C_LEATH_D)
        hline(arr, cx + 4, ty + 14, 14, C_LEATH_H)
        # Arm flung back (toward viewer/left) throwing smoke bomb
        rect_fill(arr, cx - 10, tys - 2, 8, 12, C_LEATH_M)
        rect_fill(arr, cx - 14, tys + 8, 8, 10, C_CHAR_M)
        rect_fill(arr, cx - 16, tys + 16, 6, 6,  C_SKIN_M)
        # Smoke bomb in midair (small dark sphere at feet area)
        bx = cx - 10
        by = FEET + dy - 10
        pp(arr, bx, by, C_OUTLINE)
        pp(arr, bx + 2, by - 2, C_CHAR_M)
        pp(arr, bx + 2, by, C_CHAR_H)
        # Small puff starting
        draw_smoke_puff(arr, bx, by + 4, radius=8, alpha_max=100)
        # Other arm running pump
        rect_fill(arr, cx + 2, tys + 2, 8, 10, C_LEATH_M)
        rect_fill(arr, cx + 2, tys + 10, 8, 10, C_CHAR_M)
        draw_head_turned(arr, cx, dy)
        draw_shadow(arr, cx, FEET, w=18, dy_offset=dy)

    elif fn == 2:
        # Sprinting away — back fully to viewer, speed lines
        cx = CX - 4   # slightly off-center for run pose
        dy = -2
        draw_torso_turned(arr, cx, dy)
        tys = SHLDR + dy
        ty  = WAIST + dy
        # Full sprint legs (wide stride)
        rect_fill(arr, cx - 18, ty,      12, 10, C_LEATH_M)
        rect_fill(arr, cx - 18, ty + 8,  10, 14, C_CHAR_M)
        rect_fill(arr, cx - 20, ty + 20, 14, 8,  C_LEATH_D)
        hline(arr, cx - 20, ty + 20, 14, C_LEATH_H)
        rect_fill(arr, cx + 6,  ty - 6,  12, 10, C_LEATH_M)
        rect_fill(arr, cx + 8,  ty + 2,  10, 10, C_CHAR_M)
        rect_fill(arr, cx + 8,  ty + 10, 14, 8,  C_LEATH_D)
        hline(arr, cx + 8, ty + 10, 14, C_LEATH_H)
        # Arms pumping (from behind view — just silhouettes)
        rect_fill(arr, cx - 12, tys + 2, 8, 10, C_LEATH_M)
        rect_fill(arr, cx - 14, tys + 10, 8, 10, C_CHAR_M)
        rect_fill(arr, cx + 6,  tys - 4, 8, 10, C_LEATH_M)
        rect_fill(arr, cx + 8,  tys + 4, 8, 10, C_CHAR_M)
        # Cloak streaming behind (to the right of running direction)
        rect_fill(arr, cx + 14, tys - 8,  18, 28, C_CLK_M)
        vline(arr, cx + 30, tys - 8, 28, C_CLK_D)
        hline(arr, cx + 14, tys - 8, 18, C_CLK_H)
        # Hair visible from back
        rect_fill(arr, cx - 8, HEAD + dy,  20, 10, C_HAIR_D)
        # Bandana knot at back of head
        pp(arr, cx + 4, HEAD + dy + 2, C_BAND_M)
        # Speed lines to the left (direction of movement)
        draw_speed_lines(arr, cx - 16, SHLDR + dy + 12, count=5, length=50)
        # Ghost motion trail
        for t in range(1, 4):
            off = t * 14
            alpha = max(0, 70 - t * 20)
            for gy in range(HEAD + dy, FEET + dy, 4):
                for gx in range(-14, 14, 4):
                    blend_px(arr, cx + off + gx, gy, (*C_TRAIL_D[:3], alpha))
        draw_shadow(arr, cx, FEET, w=16, dy_offset=dy)

    elif fn == 3:
        # Gone — only smoke cloud, no character
        # Large smoke explosion where character was
        smoke_cx = CX
        smoke_cy = SHLDR + 20
        # Big smoke cloud
        for dy_ in range(-30, 30, 2):
            for dx_ in range(-30, 30, 2):
                d = math.hypot(dx_, dy_)
                if d > 30:
                    continue
                t = d / 30.0
                col = (C_SMOKE_D if t < 0.3
                       else C_SMOKE_M if t < 0.65
                       else C_SMOKE_L)
                alpha = int(col[3] * (1.0 - t * 0.5))
                actual_col = (*col[:3], alpha)
                wobble = math.sin(math.atan2(dy_, max(dx_, 0.01)) * 4) * 5
                if d < 30 + wobble:
                    blend_px(arr, smoke_cx + dx_, smoke_cy + dy_, actual_col)
        # Tendrils drifting up
        for ti in range(8):
            angle = math.radians(-90 + (ti - 4) * 20)
            for dist in range(30, 50, 4):
                ax = int(smoke_cx + dist * math.cos(angle) * 0.4) & ~1
                ay = int(smoke_cy - dist) & ~1
                alpha = max(0, 90 - (dist - 30) * 5)
                blend_px(arr, ax, ay, (*C_SMOKE_L[:3], alpha))
        # Ground shadow (no character, just smoke area)
        for sx in range(-20, 20, 2):
            blend_px(arr, smoke_cx + sx, FEET, (20, 15, 28, 40))

    return Image.fromarray(arr, 'RGBA')


def gen_flee():
    frames = [make_flee_frame(i) for i in range(4)]
    strip = Image.new('RGBA', (1024, 256), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * 256, 0))
    return strip


# ─── VALIDATION ───────────────────────────────────────────────────────────────

def validate_strip(path, expected_w, expected_h, expected_frames):
    img = Image.open(path).convert('RGBA')
    assert img.size == (expected_w, expected_h), \
        f"  ERROR: {path} size {img.size} != ({expected_w},{expected_h})"
    assert img.mode == 'RGBA', f"  ERROR: {path} mode {img.mode}"
    arr = np.array(img)
    frame_w = expected_w // expected_frames
    results = []
    for fi in range(expected_frames):
        frame = arr[:, fi * frame_w:(fi + 1) * frame_w, :]
        npx = int((frame[:, :, 3] > 10).sum())
        results.append(npx)
        assert npx >= 200, \
            f"  ERROR: {path} frame {fi} has only {npx} opaque pixels (expected >= 200)"
    assert arr[0, 0, 3] == 0, f"  ERROR: {path} background not transparent"
    return results


# ─── MAIN ─────────────────────────────────────────────────────────────────────

ANIMATIONS = [
    # (name, gen_fn, width, height, n_frames)
    ('advance',   gen_advance,   1024, 256, 4),
    ('defer',     gen_defer,     1024, 256, 4),
    ('steal',     gen_steal,     1536, 256, 6),
    ('backstab',  gen_backstab,  1536, 256, 6),
    ('mug',       gen_mug,       1536, 256, 6),
    ('flee',      gen_flee,      1024, 256, 4),
]


def main():
    print("=" * 64)
    print("Generating EXTENDED Rogue sprite strips")
    print(f"Output: {OUT_DIR}")
    print("=" * 64)

    all_pass = True
    for name, gen_fn, exp_w, exp_h, n_frames in ANIMATIONS:
        print(f"\n[{name.upper()}] {n_frames} frames -> {exp_w}x{exp_h}...")
        strip = gen_fn()
        assert strip.size == (exp_w, exp_h), \
            f"Generated strip size mismatch: {strip.size} != ({exp_w},{exp_h})"
        out_path = os.path.join(OUT_DIR, f"{name}.png")
        strip.save(out_path, 'PNG')
        print(f"  Saved: {out_path}")

        try:
            pixel_counts = validate_strip(out_path, exp_w, exp_h, n_frames)
            for fi, npx in enumerate(pixel_counts):
                print(f"  Frame {fi}: {npx:6d} opaque pixels  [PASS]")
            print(f"  Dimensions: {exp_w}x{exp_h}  [PASS]")
            print(f"  Background: transparent  [PASS]")
        except AssertionError as e:
            print(str(e))
            all_pass = False

        # 3x preview saved to tmp
        preview = strip.resize((exp_w * 3, exp_h * 3), Image.NEAREST)
        preview.save(os.path.join(TMP_DIR, f"rogue_{name}_3x.png"))
        print(f"  Preview: {TMP_DIR}/rogue_{name}_3x.png")

    print("\n" + "=" * 64)
    if all_pass:
        print("ALL STRIPS PASS VALIDATION")
    else:
        print("SOME STRIPS FAILED — check output above")
    print("=" * 64)


if __name__ == "__main__":
    main()
