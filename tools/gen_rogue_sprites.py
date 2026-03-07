#!/usr/bin/env python3
"""
Generate ALL 9 Rogue animation strips for Cowardly Irregular.

Frame size: 256x256 pixels per frame, transparent background.
Art style: SNES-style pixel art, 2x2 super-pixels, character ~65px wide x 90px tall,
           positioned center-bottom (character feet near row 175).

Rogue design:
  - Dark leather armor: deep brown/charcoal with purple-black accents
  - Short dark green cloak thrown back over one shoulder
  - Dual curved daggers (silver blades, dark handles)
  - Lean athletic build, crouched ready-to-strike stance
  - Bandana/headband over dark hair, sharp angular face
  - Leather bracers and buckled boots
  - Ground shadow at y=175

Outputs (all to assets/sprites/jobs/rogue/):
  idle.png     512x256   (2 frames)
  walk.png    1536x256   (6 frames)
  attack.png  1536x256   (6 frames)
  hit.png     1024x256   (4 frames)
  dead.png    1024x256   (4 frames)
  cast.png    1024x256   (4 frames)
  defend.png  1024x256   (4 frames)
  item.png    1024x256   (4 frames)
  victory.png 1024x256   (4 frames)
"""

import math
import os
import numpy as np
from PIL import Image

OUT_DIR = "/home/struktured/projects/cowardly-irregular/assets/sprites/jobs/rogue"
TMP_DIR = "/home/struktured/projects/cowardly-irregular/tmp"
os.makedirs(OUT_DIR, exist_ok=True)
os.makedirs(TMP_DIR, exist_ok=True)

# ─── PALETTE ─────────────────────────────────────────────────────────────────
# All RGBA tuples

TRANSP       = (0,   0,   0,   0)

# Outlines
C_OUTLINE    = (26,  24,  32,  255)   # near-black purple-black
C_DARK_EDGE  = (20,  18,  26,  255)   # deepest shadow

# Skin
C_SKIN_D     = (150, 100, 70,  255)   # dark skin / shadow
C_SKIN_M     = (200, 140, 100, 255)   # mid skin tone
C_SKIN_L     = (230, 175, 135, 255)   # light skin highlight

# Hair (dark)
C_HAIR_D     = (30,  22,  18,  255)
C_HAIR_M     = (55,  38,  28,  255)
C_HAIR_H     = (80,  58,  42,  255)

# Bandana (dark teal/charcoal)
C_BAND_D     = (30,  35,  38,  255)
C_BAND_M     = (45,  55,  60,  255)
C_BAND_H     = (65,  80,  85,  255)

# Leather armor (deep brown)
C_LEATH_D    = (42,  28,  18,  255)   # #2a1c12
C_LEATH_M    = (72,  52,  34,  255)   # #483422
C_LEATH_H    = (105, 78,  52,  255)   # #694e34
C_LEATH_HL   = (140, 108, 76,  255)   # highlight

# Charcoal chest plate
C_CHAR_D     = (28,  28,  34,  255)
C_CHAR_M     = (42,  42,  52,  255)
C_CHAR_H     = (62,  62,  76,  255)

# Purple-black accents
C_PURP_D     = (30,  18,  42,  255)
C_PURP_M     = (50,  30,  68,  255)

# Dark green cloak
C_CLK_D      = (18,  42,  18,  255)   # #122a12
C_CLK_M      = (28,  72,  28,  255)   # #1c481c
C_CLK_H      = (40,  100, 40,  255)   # #286428
C_CLK_HL     = (60,  130, 55,  255)   # edge highlight

# Silver daggers
C_DAG_D      = (80,  88,  100, 255)   # dark steel
C_DAG_M      = (130, 140, 160, 255)   # mid steel
C_DAG_H      = (185, 195, 215, 255)   # bright steel
C_DAG_HL     = (220, 228, 245, 255)   # specular highlight

# Dagger handle (wrapped leather)
C_HILT_D     = (38,  28,  22,  255)
C_HILT_M     = (62,  46,  34,  255)

# Belt / buckles
C_BELT_D     = (35,  25,  18,  255)
C_BELT_M     = (58,  44,  32,  255)
C_BUCKLE     = (160, 148, 100, 255)   # tarnished brass

# Ground shadow
C_SHADOW     = (20,  15,  28,  80)
C_SHADOW2    = (20,  15,  28,  40)

# Effect colors
C_SMOKE_D    = (50,  45,  55,  180)
C_SMOKE_M    = (80,  75,  88,  120)
C_SMOKE_L    = (120, 115, 130, 60)
C_SPARK_Y    = (255, 220, 80,  255)
C_SPARK_W    = (255, 255, 200, 255)
C_TRAIL_D    = (100, 80,  120, 180)   # purple motion trail
C_TRAIL_L    = (160, 130, 190, 80)

# Item pouch color
C_POUCH_D    = (45,  30,  20,  255)
C_POUCH_M    = (75,  55,  38,  255)

# Poison vial
C_VIAL_D     = (30,  80,  30,  255)
C_VIAL_M     = (50,  140, 50,  255)
C_VIAL_H     = (100, 200, 80,  255)
C_VIAL_GL    = (160, 240, 120, 200)


# ─── DRAWING PRIMITIVES ──────────────────────────────────────────────────────

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


# ─── GROUND SHADOW ───────────────────────────────────────────────────────────

def draw_shadow(arr, cx, y, w=22, dy_offset=0):
    sy = y + dy_offset
    for sx in range(-w, w + 1, 2):
        af = max(0.0, 1.0 - (abs(sx) / w) ** 1.3)
        alpha = int(80 * af)
        for row_off in range(0, 4, 2):
            nx_, ny_ = cx + sx, sy + row_off
            if 0 <= nx_ < 256 and 0 <= ny_ < 256 and arr[ny_, nx_, 3] < 10:
                arr[ny_, nx_] = (20, 15, 28, alpha)


# ─── CHARACTER ANATOMY CONSTANTS ─────────────────────────────────────────────
# Character is centered around x=128, feet at y=172
# Total character height ~90px, width ~60px

CX    = 128   # horizontal center
FEET  = 172   # y of feet (ground)
HEAD  = 82    # y of top of head
NECK  = 100   # y of neck base
SHLDR = 104   # y of shoulders
WAIST = 138   # y of waist/belt
HIP   = 148   # y of hips

# Horizontal landmarks
LSHLDR_X = 110   # left shoulder (character's left, our right)
RSHLDR_X = 146   # right shoulder (character's right, our left)
TORSO_L  = 112   # left edge of torso
TORSO_R  = 144   # right edge of torso
HEAD_L   = 114   # left edge of head
HEAD_R   = 142   # right edge of head


# ─── BODY DRAWING FUNCTIONS ──────────────────────────────────────────────────

def draw_head(arr, cx=CX, head_y=HEAD, dy=0, lean_x=0):
    """Draw the rogue head: angular face, bandana, dark hair."""
    hx = cx + lean_x
    hy = head_y + dy

    # Hair (back, visible above bandana)
    rect_fill(arr, hx - 10, hy,      24, 6, C_HAIR_M)
    rect_fill(arr, hx - 12, hy + 2,  28, 4, C_HAIR_D)
    pp(arr, hx - 12, hy,     C_HAIR_D)
    pp(arr, hx + 14, hy,     C_HAIR_D)

    # Face/skin (angular, slightly square jaw)
    rect_fill(arr, hx - 8,  hy + 6,  18, 14, C_SKIN_M)
    # Jaw slightly wider
    rect_fill(arr, hx - 8,  hy + 16, 18, 4,  C_SKIN_D)
    # Cheek highlights
    pp(arr, hx - 4, hy + 8,  C_SKIN_L)
    pp(arr, hx + 4, hy + 8,  C_SKIN_L)
    pp(arr, hx - 4, hy + 10, C_SKIN_L)

    # Eyes (sharp, narrow — confident)
    pp(arr, hx - 4, hy + 10, C_OUTLINE)
    pp(arr, hx + 2, hy + 10, C_OUTLINE)
    # Eye highlights
    pp(arr, hx - 2, hy + 10, C_SKIN_L)
    pp(arr, hx + 4, hy + 10, C_SKIN_L)

    # Smirk / mouth (slightly asymmetric, cocky)
    pp(arr, hx - 2, hy + 16, C_OUTLINE)
    pp(arr, hx,     hy + 16, C_OUTLINE)
    pp(arr, hx + 2, hy + 16, C_SKIN_D)

    # Nose bridge
    pp(arr, hx,     hy + 13, C_SKIN_D)

    # Bandana (wraps forehead, knot tied in back)
    rect_fill(arr, hx - 10, hy + 4, 22, 6, C_BAND_M)
    hline(arr, hx - 10, hy + 4, 22, C_BAND_H)
    hline(arr, hx - 10, hy + 8, 22, C_BAND_D)
    # Bandana texture (horizontal stripe)
    pp(arr, hx - 4, hy + 6, C_BAND_H)
    pp(arr, hx + 2, hy + 6, C_BAND_H)

    # Hair sides (below bandana, swept back)
    pp(arr, hx - 10, hy + 10, C_HAIR_M)
    pp(arr, hx - 10, hy + 12, C_HAIR_M)
    pp(arr, hx + 8,  hy + 10, C_HAIR_M)

    # Outline the head
    pp(arr, hx - 10, hy + 4,  C_OUTLINE)
    pp(arr, hx + 8,  hy + 4,  C_OUTLINE)
    pp(arr, hx - 10, hy + 18, C_OUTLINE)
    pp(arr, hx + 8,  hy + 18, C_OUTLINE)
    pp(arr, hx - 8,  hy + 20, C_OUTLINE)
    pp(arr, hx + 6,  hy + 20, C_OUTLINE)


def draw_head_alert(arr, cx=CX, dy=0, lean_x=0):
    """Head slightly tilted forward, eyes narrowed — alert state."""
    draw_head(arr, cx, HEAD, dy, lean_x)
    # Override eyes to be slightly more narrowed
    hx = cx + lean_x
    hy = HEAD + dy
    pp(arr, hx - 4, hy + 10, C_OUTLINE)
    pp(arr, hx - 2, hy + 10, C_OUTLINE)
    pp(arr, hx + 2, hy + 10, C_OUTLINE)
    pp(arr, hx + 4, hy + 10, C_OUTLINE)


def draw_torso(arr, cx=CX, dy=0, lean_x=0):
    """Draw rogue torso: charcoal chest plate, leather shoulder straps, belt."""
    tx = cx + lean_x
    ty = SHLDR + dy

    # Main torso body (dark leather armor)
    rect_fill(arr, tx - 14, ty,      30, 18, C_LEATH_M)
    rect_fill(arr, tx - 12, ty + 2,  26, 14, C_CHAR_M)   # center charcoal

    # Chest plate highlight
    pp(arr, tx - 6, ty + 4, C_CHAR_H)
    pp(arr, tx - 4, ty + 4, C_CHAR_H)
    pp(arr, tx - 2, ty + 4, C_CHAR_H)
    pp(arr, tx,     ty + 4, C_CHAR_H)

    # Shoulder strap (diagonal across chest — character's right shoulder)
    for i in range(5):
        pp(arr, tx - 8 + i * 2, ty + i * 2, C_LEATH_H)

    # Purple-black accent stripe down center
    vline(arr, tx - 2, ty + 2, 14, C_PURP_M)
    vline(arr, tx,     ty + 2, 14, C_PURP_D)

    # Belt
    rect_fill(arr, tx - 14, ty + 16, 30, 6, C_BELT_M)
    hline(arr, tx - 14, ty + 16, 30, C_BELT_D)
    hline(arr, tx - 14, ty + 20, 30, C_BELT_D)
    # Belt buckle (slightly off-center, tarnished brass)
    pp(arr, tx - 2, ty + 16, C_BUCKLE)
    pp(arr, tx,     ty + 16, C_BUCKLE)
    pp(arr, tx - 2, ty + 18, C_BUCKLE)

    # Cloak draped over left shoulder (character's left = our right side)
    rect_fill(arr, tx + 6, ty - 2, 10, 14, C_CLK_M)
    hline(arr, tx + 6,  ty - 2,  10, C_CLK_H)
    vline(arr, tx + 14, ty - 2,  12, C_CLK_D)
    pp(arr, tx + 6,  ty + 12, C_CLK_D)

    # Torso outlines
    pp(arr, tx - 14, ty,      C_OUTLINE)
    pp(arr, tx + 14, ty,      C_OUTLINE)
    pp(arr, tx - 14, ty + 22, C_OUTLINE)
    pp(arr, tx + 14, ty + 22, C_OUTLINE)


def draw_legs_idle(arr, cx=CX, dy=0):
    """Crouched ready stance: legs slightly bent, weight forward."""
    tx = cx
    ty = WAIST + dy

    # Left leg (forward leg, slightly more forward/lower)
    rect_fill(arr, tx - 14, ty,      12, 12, C_LEATH_M)   # thigh
    rect_fill(arr, tx - 14, ty + 10, 10, 12, C_CHAR_M)    # shin
    # Boot
    rect_fill(arr, tx - 16, ty + 20, 14, 8, C_LEATH_D)
    hline(arr, tx - 16, ty + 20, 14, C_LEATH_H)           # boot highlight
    # Buckle on boot
    pp(arr, tx - 8, ty + 22, C_BUCKLE)

    # Right leg (back leg, slightly raised)
    rect_fill(arr, tx + 2,  ty - 2,  12, 12, C_LEATH_M)   # thigh (higher)
    rect_fill(arr, tx + 2,  ty + 8,  10, 12, C_CHAR_M)    # shin
    # Boot
    rect_fill(arr, tx + 2,  ty + 18, 14, 8, C_LEATH_D)
    hline(arr, tx + 2,  ty + 18, 14, C_LEATH_H)
    pp(arr, tx + 8,  ty + 20, C_BUCKLE)

    # Knee pads (leather rounds)
    pp(arr, tx - 12, ty + 10, C_LEATH_H)
    pp(arr, tx + 4,  ty + 8,  C_LEATH_H)

    # Leg shadows
    pp(arr, tx - 14, ty + 28, C_OUTLINE)
    pp(arr, tx + 2,  ty + 26, C_OUTLINE)


def draw_legs_walk(arr, cx, dy, frame_idx):
    """6-frame walk cycle: stealthy prowl, low center of gravity."""
    tx = cx
    ty = WAIST + dy

    # Walk cycle: alternating front/back leg positions
    # frame 0,4: left leg forward, right leg back
    # frame 1,5: both feet near together (mid-stride)
    # frame 2: right leg forward, left leg back
    # frame 3: both feet near together (mid-stride)

    stride = 10
    lift   = 4

    if frame_idx % 2 == 0:  # extended stride
        leg_offset = stride if (frame_idx % 4 < 2) else -stride
        # Front leg
        lf_x = tx - 14 + leg_offset
        lb_x = tx + 2 - leg_offset
        # Front leg low/extended
        rect_fill(arr, lf_x, ty,      12, 10, C_LEATH_M)
        rect_fill(arr, lf_x, ty + 8,  10, 12, C_CHAR_M)
        rect_fill(arr, lf_x - 2, ty + 18, 14, 8, C_LEATH_D)
        hline(arr, lf_x - 2, ty + 18, 14, C_LEATH_H)
        # Back leg raised slightly
        rect_fill(arr, lb_x, ty - lift, 12, 10, C_LEATH_M)
        rect_fill(arr, lb_x, ty + 6 - lift, 10, 12, C_CHAR_M)
        rect_fill(arr, lb_x, ty + 16 - lift, 14, 8, C_LEATH_D)
        hline(arr, lb_x, ty + 16 - lift, 14, C_LEATH_H)
    else:  # mid-stride — feet close together
        rect_fill(arr, tx - 14, ty + 2, 12, 10, C_LEATH_M)
        rect_fill(arr, tx - 14, ty + 10, 10, 12, C_CHAR_M)
        rect_fill(arr, tx - 16, ty + 20, 14, 8, C_LEATH_D)
        hline(arr, tx - 16, ty + 20, 14, C_LEATH_H)
        rect_fill(arr, tx + 2,  ty,     12, 10, C_LEATH_M)
        rect_fill(arr, tx + 2,  ty + 8, 10, 12, C_CHAR_M)
        rect_fill(arr, tx + 2,  ty + 18, 14, 8, C_LEATH_D)
        hline(arr, tx + 2, ty + 18, 14, C_LEATH_H)

    # Knee highlights
    pp(arr, tx - 10, ty + 8, C_LEATH_H)
    pp(arr, tx + 6,  ty + 6, C_LEATH_H)


def draw_arm_left(arr, cx=CX, dy=0, pose='idle'):
    """Left arm (character's left, viewer's right) holding dagger."""
    tx = cx
    ty = SHLDR + dy

    if pose == 'idle':
        # Arm bent, dagger held low pointing slightly outward
        # Upper arm
        rect_fill(arr, tx - 16, ty + 2, 8, 10, C_LEATH_M)
        pp(arr, tx - 16, ty + 2, C_OUTLINE)
        # Forearm / bracer
        rect_fill(arr, tx - 18, ty + 10, 8, 10, C_CHAR_M)
        hline(arr, tx - 18, ty + 10, 8, C_CHAR_H)  # bracer highlight
        # Wrist / hand
        rect_fill(arr, tx - 18, ty + 18, 6, 6, C_SKIN_M)
        # Dagger (left hand — angled outward-down)
        draw_dagger(arr, tx - 16, ty + 22, angle_deg=210, short=True)

    elif pose == 'walk':
        # Arm swings slightly
        rect_fill(arr, tx - 16, ty + 4, 8, 10, C_LEATH_M)
        rect_fill(arr, tx - 16, ty + 12, 8, 10, C_CHAR_M)
        rect_fill(arr, tx - 16, ty + 20, 6, 6, C_SKIN_M)
        draw_dagger(arr, tx - 14, ty + 24, angle_deg=200, short=True)

    elif pose == 'guard':
        # Arm raised, dagger crossed in X-block
        rect_fill(arr, tx - 18, ty - 2, 8, 10, C_LEATH_M)
        rect_fill(arr, tx - 14, ty + 6,  8, 10, C_CHAR_M)
        rect_fill(arr, tx - 10, ty + 14, 6, 6, C_SKIN_M)
        draw_dagger(arr, tx - 8, ty + 12, angle_deg=45, short=True)

    elif pose == 'raise':
        # Arm raised up (victory / cast)
        rect_fill(arr, tx - 14, ty - 6, 8, 12, C_LEATH_M)
        rect_fill(arr, tx - 12, ty + 4,  6, 10, C_CHAR_M)
        rect_fill(arr, tx - 10, ty + 12, 6, 6,  C_SKIN_M)
        draw_dagger(arr, tx - 8, ty + 10, angle_deg=340, short=True)

    elif pose == 'reach':
        # Arm reaching forward (item use)
        rect_fill(arr, tx - 16, ty + 2, 8, 8, C_LEATH_M)
        rect_fill(arr, tx - 20, ty + 8, 8, 8, C_CHAR_M)
        rect_fill(arr, tx - 24, ty + 14, 6, 6, C_SKIN_M)


def draw_arm_right(arr, cx=CX, dy=0, pose='idle'):
    """Right arm (character's right, viewer's left) holding main dagger."""
    tx = cx
    ty = SHLDR + dy

    if pose == 'idle':
        # Arm bent at elbow, dagger held ready pointing outward
        # Upper arm (dark leather pauldron)
        rect_fill(arr, tx + 8,  ty + 2, 8, 10, C_LEATH_M)
        pp(arr, tx + 14, ty + 2, C_OUTLINE)
        # Forearm / bracer
        rect_fill(arr, tx + 10, ty + 10, 8, 10, C_CHAR_M)
        hline(arr, tx + 10, ty + 10, 8, C_CHAR_H)
        # Wrist / hand
        rect_fill(arr, tx + 12, ty + 18, 6, 6, C_SKIN_M)
        # Main dagger
        draw_dagger(arr, tx + 14, ty + 22, angle_deg=160, short=False)

    elif pose == 'walk':
        rect_fill(arr, tx + 8,  ty + 2, 8, 10, C_LEATH_M)
        rect_fill(arr, tx + 10, ty + 10, 8, 10, C_CHAR_M)
        rect_fill(arr, tx + 12, ty + 18, 6, 6,  C_SKIN_M)
        draw_dagger(arr, tx + 14, ty + 22, angle_deg=150, short=False)

    elif pose == 'guard':
        # Arm raised, crossing for X-block
        rect_fill(arr, tx + 10, ty - 2, 8, 10, C_LEATH_M)
        rect_fill(arr, tx + 6,  ty + 6,  8, 10, C_CHAR_M)
        rect_fill(arr, tx + 2,  ty + 14, 6, 6,  C_SKIN_M)
        draw_dagger(arr, tx + 4, ty + 12, angle_deg=135, short=False)

    elif pose == 'raise':
        # Arm lowered (other arm is raised in victory)
        rect_fill(arr, tx + 8,  ty + 4, 8, 10, C_LEATH_M)
        rect_fill(arr, tx + 10, ty + 12, 8, 10, C_CHAR_M)
        rect_fill(arr, tx + 12, ty + 20, 6, 6,  C_SKIN_M)
        draw_dagger(arr, tx + 14, ty + 24, angle_deg=170, short=False)

    elif pose == 'reach':
        # Main arm extended for item hold
        rect_fill(arr, tx + 10, ty,     8, 8, C_LEATH_M)
        rect_fill(arr, tx + 14, ty + 6, 8, 8, C_CHAR_M)
        rect_fill(arr, tx + 18, ty + 12, 6, 6, C_SKIN_M)


# ─── DAGGER DRAWING ──────────────────────────────────────────────────────────

def draw_dagger(arr, hx, hy, angle_deg=160, short=False):
    """
    Draw a curved dagger.
    hx, hy = hand/grip position.
    angle_deg = direction blade points (0=right, 90=down, 180=left).
    short = secondary dagger (slightly shorter blade).
    """
    blade_len = 16 if short else 22
    rad = math.radians(angle_deg)
    bx_dir = math.cos(rad)
    by_dir = math.sin(rad)

    # Handle (grip, wrapped leather)
    grip_len = 8
    for i in range(0, grip_len, 2):
        gx = int(hx - bx_dir * i) & ~1
        gy = int(hy - by_dir * i) & ~1
        pp(arr, gx - 2, gy, C_HILT_D)
        pp(arr, gx,     gy, C_HILT_M)
    # Handle outline
    pp(arr, int(hx - bx_dir * grip_len) & ~1 - 2,
           int(hy - by_dir * grip_len) & ~1,
           C_OUTLINE)

    # Guard (small crosspiece perpendicular to blade)
    px_dir = -by_dir
    py_dir = bx_dir
    for k in (-4, -2, 0, 2, 4):
        gx = int(hx + px_dir * k) & ~1
        gy = int(hy + py_dir * k) & ~1
        pp(arr, gx, gy, C_DAG_M)
    pp(arr, int(hx + px_dir * (-4)) & ~1, int(hy + py_dir * (-4)) & ~1, C_DAG_D)
    pp(arr, int(hx + px_dir * 4) & ~1,    int(hy + py_dir * 4) & ~1,    C_DAG_D)

    # Blade (slightly curved — offset increases toward tip)
    curve = 0.15
    for i in range(0, blade_len, 2):
        t = i / blade_len
        # Curve applied perpendicular to blade direction
        curve_off = curve * t * t * 6
        bpx = int(hx + bx_dir * i + px_dir * curve_off) & ~1
        bpy = int(hy + by_dir * i + py_dir * curve_off) & ~1
        taper = 1 if t > 0.7 else 0

        pp(arr, bpx - 2 + taper, bpy, C_DAG_D)
        pp(arr, bpx,             bpy, C_DAG_M)
        pp(arr, bpx + 2 - taper, bpy, C_DAG_H)
        if t < 0.5:
            pp(arr, bpx + 4, bpy, C_DAG_HL)  # edge glint

    # Blade tip
    tip_x = int(hx + bx_dir * blade_len) & ~1
    tip_y = int(hy + by_dir * blade_len) & ~1
    pp(arr, tip_x, tip_y, C_DAG_H)
    pp(arr, tip_x + 2, tip_y, C_DAG_HL)


def draw_dagger_standalone(arr, hx, hy, angle_deg=160):
    """Draw a dagger without the hand (scattered/dropped state)."""
    draw_dagger(arr, hx, hy, angle_deg, short=False)


# ─── FULL CHARACTER POSES ─────────────────────────────────────────────────────

def build_idle_base(dy=0, lean_x=0, eye_variant=0):
    """Standard crouched idle pose."""
    arr = new_frame()
    draw_torso(arr, CX, dy, lean_x)
    draw_legs_idle(arr, CX, dy)
    draw_arm_left(arr, CX, dy, pose='idle')
    draw_arm_right(arr, CX, dy, pose='idle')
    draw_head(arr, CX, HEAD, dy, lean_x)
    draw_shadow(arr, CX + lean_x, FEET, w=22, dy_offset=dy)
    return arr


def build_walk_base(frame_idx, dy=0):
    """Walk cycle frame."""
    arr = new_frame()
    draw_torso(arr, CX, dy)
    draw_legs_walk(arr, CX, dy, frame_idx)
    draw_arm_left(arr, CX, dy, pose='walk')
    draw_arm_right(arr, CX, dy, pose='walk')
    draw_head(arr, CX, HEAD, dy)
    draw_shadow(arr, CX, FEET, w=20, dy_offset=dy)
    return arr


# ─── IDLE ANIMATION (2 frames) ───────────────────────────────────────────────

def gen_idle():
    frames = []

    # Frame 0: standard idle, weight neutral
    arr0 = build_idle_base(dy=0)
    frames.append(Image.fromarray(arr0, 'RGBA'))

    # Frame 1: slight weight shift — bob down 2px, cloak shifts
    arr1 = build_idle_base(dy=2, lean_x=0)
    # Add cloak flutter (1 extra pixel out)
    tx = CX
    ty = SHLDR + 2
    pp(arr1, tx + 16, ty, C_CLK_M)
    pp(arr1, tx + 16, ty + 2, C_CLK_D)
    frames.append(Image.fromarray(arr1, 'RGBA'))

    strip = Image.new('RGBA', (512, 256), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * 256, 0))
    return strip


# ─── WALK ANIMATION (6 frames) ───────────────────────────────────────────────

def gen_walk():
    frames = []
    # Bob pattern: down 0, -2, 0, -2, 0, -2
    bob = [0, -2, 0, -2, 0, -2]
    for i in range(6):
        arr = build_walk_base(i, dy=bob[i])
        frames.append(Image.fromarray(arr, 'RGBA'))

    strip = Image.new('RGBA', (1536, 256), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * 256, 0))
    return strip


# ─── ATTACK ANIMATION (6 frames) ─────────────────────────────────────────────
# Quick dash forward, double dagger slash, motion trail

def make_attack_frame(fn):
    arr = new_frame()

    # Frame progression:
    # F0: ready crouch (wind-up, daggers pulled back)
    # F1: dash forward lunge (body tilts forward)
    # F2: first slash arc (right dagger sweeps left-to-right)
    # F3: cross-slash peak (left dagger completes X pattern)
    # F4: follow-through (body extended, daggers low)
    # F5: recovery (returning to guard stance)

    lean = [0, 6, 10, 10, 6, 2][fn]
    dy   = [0, -2, -4, -2, 0, 0][fn]
    cx   = CX + lean

    # Draw base body
    draw_torso(arr, cx, dy)

    # Frame-specific leg positions
    if fn == 0:
        draw_legs_idle(arr, cx, dy)
    elif fn in (1, 2, 3):
        # Lunging — front foot extended forward
        tx = cx
        ty = WAIST + dy
        rect_fill(arr, tx - 20, ty,     12, 10, C_LEATH_M)  # front thigh extended
        rect_fill(arr, tx - 22, ty + 8, 12, 12, C_CHAR_M)
        rect_fill(arr, tx - 24, ty + 18, 16, 8, C_LEATH_D)
        hline(arr, tx - 24, ty + 18, 16, C_LEATH_H)
        rect_fill(arr, tx + 2,  ty - 4, 12, 10, C_LEATH_M)  # back leg bent
        rect_fill(arr, tx + 4,  ty + 4, 10, 12, C_CHAR_M)
        rect_fill(arr, tx + 4,  ty + 14, 14, 8, C_LEATH_D)
        hline(arr, tx + 4, ty + 14, 14, C_LEATH_H)
    elif fn == 4:
        tx = cx
        ty = WAIST + dy
        rect_fill(arr, tx - 18, ty + 2, 12, 10, C_LEATH_M)
        rect_fill(arr, tx - 18, ty + 10, 12, 12, C_CHAR_M)
        rect_fill(arr, tx - 20, ty + 20, 14, 8, C_LEATH_D)
        hline(arr, tx - 20, ty + 20, 14, C_LEATH_H)
        rect_fill(arr, tx + 2,  ty,     12, 10, C_LEATH_M)
        rect_fill(arr, tx + 2,  ty + 8, 10, 12, C_CHAR_M)
        rect_fill(arr, tx + 2,  ty + 18, 14, 8, C_LEATH_D)
        hline(arr, tx + 2, ty + 18, 14, C_LEATH_H)
    else:  # fn == 5
        draw_legs_idle(arr, cx, dy)

    # Arm and dagger positions per frame
    ty = SHLDR + dy
    if fn == 0:
        # Wind-up: both arms pulled back
        rect_fill(arr, cx + 6,  ty + 2, 8, 10, C_LEATH_M)
        rect_fill(arr, cx + 8,  ty + 10, 8, 10, C_CHAR_M)
        rect_fill(arr, cx + 10, ty + 18, 6, 6,  C_SKIN_M)
        draw_dagger(arr, cx + 12, ty + 22, angle_deg=200)
        rect_fill(arr, cx - 14, ty + 4, 8, 10, C_LEATH_M)
        rect_fill(arr, cx - 16, ty + 12, 8, 10, C_CHAR_M)
        rect_fill(arr, cx - 16, ty + 20, 6, 6,  C_SKIN_M)
        draw_dagger(arr, cx - 14, ty + 24, angle_deg=230, short=True)

    elif fn == 1:
        # Dash: arms forward, daggers angled forward-down
        rect_fill(arr, cx + 4,  ty,     8, 10, C_LEATH_M)
        rect_fill(arr, cx + 2,  ty + 8, 8, 10, C_CHAR_M)
        rect_fill(arr, cx,      ty + 16, 6, 6,  C_SKIN_M)
        draw_dagger(arr, cx + 2, ty + 20, angle_deg=180)
        rect_fill(arr, cx - 16, ty + 2, 8, 10, C_LEATH_M)
        rect_fill(arr, cx - 18, ty + 10, 8, 10, C_CHAR_M)
        rect_fill(arr, cx - 18, ty + 18, 6, 6,  C_SKIN_M)
        draw_dagger(arr, cx - 16, ty + 22, angle_deg=190, short=True)

    elif fn == 2:
        # Right dagger sweeping — right arm extended out-left diagonally
        rect_fill(arr, cx + 2,  ty,     8, 8, C_LEATH_M)
        rect_fill(arr, cx - 4,  ty + 6, 8, 8, C_CHAR_M)
        rect_fill(arr, cx - 8,  ty + 12, 6, 6, C_SKIN_M)
        draw_dagger(arr, cx - 6, ty + 14, angle_deg=150)
        # Left arm starting cross
        rect_fill(arr, cx - 14, ty,     8, 10, C_LEATH_M)
        rect_fill(arr, cx - 14, ty + 8, 8, 8,  C_CHAR_M)
        rect_fill(arr, cx - 12, ty + 14, 6, 6, C_SKIN_M)
        draw_dagger(arr, cx - 10, ty + 16, angle_deg=120, short=True)
        # Slash trail on right dagger
        for t in range(1, 4):
            bx = cx - 6 - t * 4
            by = ty + 14 - t * 2
            alpha = 100 - t * 28
            if alpha > 0:
                for j in range(0, 16, 4):
                    blend_px(arr, bx + j, by, (*C_TRAIL_D[:3], alpha))

    elif fn == 3:
        # Cross-slash peak — both daggers at X
        # Right dagger upper-left, left dagger upper-right — they've just crossed
        rect_fill(arr, cx - 2,  ty - 2, 8, 8, C_LEATH_M)
        rect_fill(arr, cx - 6,  ty + 4, 8, 8, C_CHAR_M)
        rect_fill(arr, cx - 8,  ty + 10, 6, 6, C_SKIN_M)
        draw_dagger(arr, cx - 6, ty + 8, angle_deg=130)
        rect_fill(arr, cx - 12, ty - 2, 8, 8, C_LEATH_M)
        rect_fill(arr, cx - 8,  ty + 4, 8, 8, C_CHAR_M)
        rect_fill(arr, cx - 4,  ty + 10, 6, 6, C_SKIN_M)
        draw_dagger(arr, cx - 2, ty + 8, angle_deg=50, short=True)
        # Cross-sparks at intersection
        sx = cx - 4
        sy = ty + 8
        pp(arr, sx - 2, sy - 2, C_SPARK_Y)
        pp(arr, sx + 2, sy - 2, C_SPARK_Y)
        pp(arr, sx - 2, sy + 2, C_SPARK_W)
        pp(arr, sx + 2, sy + 2, C_SPARK_W)
        pp(arr, sx,     sy - 4, C_SPARK_W)
        pp(arr, sx,     sy + 4, C_SPARK_Y)

    elif fn == 4:
        # Follow-through: arms sweeping down, daggers low
        rect_fill(arr, cx + 4,  ty + 6, 8, 10, C_LEATH_M)
        rect_fill(arr, cx + 4,  ty + 14, 8, 10, C_CHAR_M)
        rect_fill(arr, cx + 4,  ty + 22, 6, 6,  C_SKIN_M)
        draw_dagger(arr, cx + 6, ty + 26, angle_deg=160)
        rect_fill(arr, cx - 14, ty + 4, 8, 10, C_LEATH_M)
        rect_fill(arr, cx - 14, ty + 12, 8, 10, C_CHAR_M)
        rect_fill(arr, cx - 14, ty + 20, 6, 6,  C_SKIN_M)
        draw_dagger(arr, cx - 12, ty + 24, angle_deg=200, short=True)
        # Fading motion trails
        for t in range(1, 3):
            alpha = 70 - t * 30
            for j in range(0, 20, 4):
                blend_px(arr, cx + j - 8, ty + 14 + t * 4, (*C_TRAIL_L[:3], alpha))

    else:  # fn == 5 — recovery
        draw_arm_left(arr, cx, dy, pose='idle')
        draw_arm_right(arr, cx, dy, pose='idle')

    draw_head_alert(arr, cx, dy)
    draw_shadow(arr, cx, FEET, w=22, dy_offset=dy)

    return Image.fromarray(arr, 'RGBA')


def gen_attack():
    frames = [make_attack_frame(i) for i in range(6)]
    strip = Image.new('RGBA', (1536, 256), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * 256, 0))
    return strip


# ─── HIT ANIMATION (4 frames) ────────────────────────────────────────────────
# Quick dodge/recoil, stumble, recover

def make_hit_frame(fn):
    arr = new_frame()

    # F0: impact — jerked backward, body tilts back
    # F1: recoil peak — leaning back, one arm flung out
    # F2: stumble — off-balance, knee buckling
    # F3: recover — straightening back up

    lean  = [-4, -8, -6, -2][fn]
    dy    = [0, -2,  2,  0][fn]
    cx    = CX + lean

    draw_torso(arr, cx, dy, lean_x=0)

    ty = WAIST + dy
    # Legs vary by frame
    if fn == 0:
        draw_legs_idle(arr, cx, dy)
    elif fn == 1:
        # Staggering back — feet wide
        rect_fill(arr, cx - 20, ty,     12, 10, C_LEATH_M)
        rect_fill(arr, cx - 20, ty + 8, 10, 12, C_CHAR_M)
        rect_fill(arr, cx - 22, ty + 18, 14, 8, C_LEATH_D)
        hline(arr, cx - 22, ty + 18, 14, C_LEATH_H)
        rect_fill(arr, cx + 6,  ty + 2, 12, 10, C_LEATH_M)
        rect_fill(arr, cx + 6,  ty + 10, 10, 12, C_CHAR_M)
        rect_fill(arr, cx + 6,  ty + 20, 14, 8, C_LEATH_D)
        hline(arr, cx + 6, ty + 20, 14, C_LEATH_H)
    elif fn == 2:
        # Knee buckle — left knee drops
        rect_fill(arr, cx - 14, ty + 4, 12, 10, C_LEATH_M)
        rect_fill(arr, cx - 14, ty + 12, 10, 16, C_CHAR_M)
        rect_fill(arr, cx - 16, ty + 26, 14, 8,  C_LEATH_D)
        hline(arr, cx - 16, ty + 26, 14, C_LEATH_H)
        rect_fill(arr, cx + 2,  ty,     12, 10, C_LEATH_M)
        rect_fill(arr, cx + 2,  ty + 8, 10, 12, C_CHAR_M)
        rect_fill(arr, cx + 2,  ty + 18, 14, 8, C_LEATH_D)
        hline(arr, cx + 2, ty + 18, 14, C_LEATH_H)
    else:  # fn == 3
        draw_legs_idle(arr, cx, dy)

    # Arms
    tys = SHLDR + dy
    if fn in (0, 1):
        # Arms flung back / guard broken
        rect_fill(arr, cx + 8,  tys - 4, 8, 12, C_LEATH_M)
        rect_fill(arr, cx + 12, tys + 6, 8, 10, C_CHAR_M)
        rect_fill(arr, cx + 14, tys + 14, 6, 6, C_SKIN_M)
        draw_dagger(arr, cx + 16, tys + 18, angle_deg=120)
        rect_fill(arr, cx - 18, tys - 2, 8, 10, C_LEATH_M)
        rect_fill(arr, cx - 20, tys + 6, 8, 10,  C_CHAR_M)
        rect_fill(arr, cx - 20, tys + 14, 6, 6,  C_SKIN_M)
        draw_dagger(arr, cx - 18, tys + 18, angle_deg=250, short=True)
    else:
        draw_arm_left(arr, cx, dy, pose='idle')
        draw_arm_right(arr, cx, dy, pose='idle')

    # Hit flash (white outline flicker on frames 0,1)
    if fn in (0, 1):
        intensity = 1 if fn == 0 else 0
        # Quick bright outline along character edge
        for y_ in range(SHLDR, HIP, 4):
            for x_ in range(cx - 18, cx + 18, 4):
                if arr[y_ + dy, x_, 3] > 128:
                    alpha_flash = 150 if fn == 0 else 60
                    blend_px(arr, x_ - 2, y_ + dy, (255, 220, 200, alpha_flash))

    draw_head(arr, cx, HEAD, dy)
    draw_shadow(arr, cx, FEET, w=18, dy_offset=dy)

    return Image.fromarray(arr, 'RGBA')


def gen_hit():
    frames = [make_hit_frame(i) for i in range(4)]
    strip = Image.new('RGBA', (1024, 256), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * 256, 0))
    return strip


# ─── DEAD ANIMATION (4 frames) ───────────────────────────────────────────────
# Stumble, fall to knees, collapse, daggers scatter

def make_dead_frame(fn):
    arr = new_frame()

    # F0: stumble — body tilted 15° forward, arms windmilling
    # F1: fall to knees — kneeling pose
    # F2: collapse forward — torso horizontal, face down
    # F3: final collapse — fully prone, daggers scattered nearby

    if fn == 0:
        # Stumbling forward
        cx = CX + 4
        dy = 4
        draw_torso(arr, cx, dy)
        ty = WAIST + dy
        # Knees bending forward
        rect_fill(arr, cx - 12, ty,      12, 10, C_LEATH_M)
        rect_fill(arr, cx - 14, ty + 8,  12, 12, C_CHAR_M)
        rect_fill(arr, cx - 16, ty + 18, 14, 8,  C_LEATH_D)
        hline(arr, cx - 16, ty + 18, 14, C_LEATH_H)
        rect_fill(arr, cx + 2,  ty - 2,  12, 10, C_LEATH_M)
        rect_fill(arr, cx + 2,  ty + 6,  10, 12, C_CHAR_M)
        rect_fill(arr, cx + 2,  ty + 16, 14, 8,  C_LEATH_D)
        hline(arr, cx + 2, ty + 16, 14, C_LEATH_H)
        # Arms flailing
        tys = SHLDR + dy
        rect_fill(arr, cx + 10, tys - 4, 8, 12, C_LEATH_M)
        rect_fill(arr, cx + 14, tys + 6, 6, 10, C_CHAR_M)
        rect_fill(arr, cx + 16, tys + 14, 6, 6, C_SKIN_M)
        draw_dagger(arr, cx + 18, tys + 16, angle_deg=80)
        rect_fill(arr, cx - 18, tys - 2, 8, 10, C_LEATH_M)
        rect_fill(arr, cx - 20, tys + 6, 8, 10, C_CHAR_M)
        rect_fill(arr, cx - 20, tys + 14, 6, 6, C_SKIN_M)
        draw_dagger(arr, cx - 18, tys + 18, angle_deg=280, short=True)
        draw_head(arr, cx, HEAD, dy, lean_x=2)
        draw_shadow(arr, cx, FEET, w=20, dy_offset=dy)

    elif fn == 1:
        # Kneeling — character dropped to both knees
        cx = CX
        dy = 8  # character is lower overall
        draw_torso(arr, cx, dy)
        ty = WAIST + dy
        # Both knees on ground, shins flat
        rect_fill(arr, cx - 14, ty,      14, 8,  C_LEATH_M)  # left thigh
        rect_fill(arr, cx - 14, ty + 6,  14, 8,  C_LEATH_D)  # left shin (folded)
        rect_fill(arr, cx,      ty - 2,  14, 8,  C_LEATH_M)  # right thigh
        rect_fill(arr, cx,      ty + 4,  14, 8,  C_LEATH_D)  # right shin
        # Boots visible along ground
        rect_fill(arr, cx - 16, ty + 12, 16, 6,  C_LEATH_D)
        hline(arr, cx - 16, ty + 12, 16, C_LEATH_H)
        rect_fill(arr, cx - 2,  ty + 10, 16, 6,  C_LEATH_D)
        hline(arr, cx - 2, ty + 10, 16, C_LEATH_H)
        # Arms dropped, hands near ground
        tys = SHLDR + dy
        rect_fill(arr, cx + 8,  tys + 6, 8, 10, C_LEATH_M)
        rect_fill(arr, cx + 10, tys + 14, 8, 10, C_CHAR_M)
        rect_fill(arr, cx + 12, tys + 22, 6, 6,  C_SKIN_M)
        draw_dagger(arr, cx + 14, tys + 26, angle_deg=140)
        rect_fill(arr, cx - 16, tys + 4, 8, 10, C_LEATH_M)
        rect_fill(arr, cx - 16, tys + 12, 8, 10, C_CHAR_M)
        rect_fill(arr, cx - 16, tys + 20, 6, 6,  C_SKIN_M)
        draw_dagger(arr, cx - 14, tys + 24, angle_deg=220, short=True)
        draw_head(arr, cx, HEAD, dy + 4, lean_x=0)
        draw_shadow(arr, cx, FEET, w=24, dy_offset=dy)

    elif fn == 2:
        # Collapsed forward — body tilted, head down
        cx = CX
        dy = 10
        # Draw torso horizontal (rotated) — simplified as wide rect
        rect_fill(arr, cx - 22, WAIST + dy - 4, 44, 12, C_LEATH_M)
        rect_fill(arr, cx - 20, WAIST + dy - 2, 40, 8,  C_CHAR_M)
        hline(arr, cx - 22, WAIST + dy - 4, 44, C_LEATH_H)
        # Cloak spread
        rect_fill(arr, cx + 8,  WAIST + dy - 8, 16, 12, C_CLK_M)
        vline(arr, cx + 22, WAIST + dy - 8, 12, C_CLK_D)
        # Legs splayed behind
        ty = WAIST + dy
        rect_fill(arr, cx - 10, ty + 6,  10, 14, C_LEATH_D)
        rect_fill(arr, cx + 2,  ty + 4,  10, 14, C_LEATH_D)
        rect_fill(arr, cx - 12, ty + 18, 14, 6,  C_LEATH_D)
        rect_fill(arr, cx + 2,  ty + 16, 14, 6,  C_LEATH_D)
        # Arms spread
        rect_fill(arr, cx - 26, WAIST + dy - 2, 10, 8, C_LEATH_M)
        rect_fill(arr, cx + 16, WAIST + dy - 2, 10, 8, C_LEATH_M)
        # Head face-down
        rect_fill(arr, cx - 8, WAIST + dy - 14, 18, 12, C_HAIR_D)
        rect_fill(arr, cx - 6, WAIST + dy - 10, 14, 8,  C_BAND_D)
        # Daggers starting to fall from hands
        draw_dagger(arr, cx - 22, WAIST + dy + 4, angle_deg=240)
        draw_dagger(arr, cx + 16, WAIST + dy,     angle_deg=300, short=True)
        # Shadow large
        draw_shadow(arr, cx, FEET, w=28, dy_offset=dy)

    else:  # fn == 3 — fully prone, daggers scattered
        cx = CX
        # Character fully flat — draw as horizontal shape near ground
        ground_y = FEET - 18
        # Body
        rect_fill(arr, cx - 28, ground_y - 8, 56, 10, C_LEATH_M)
        rect_fill(arr, cx - 26, ground_y - 6, 52, 6,  C_CHAR_M)
        hline(arr, cx - 28, ground_y - 8, 56, C_LEATH_H)
        # Belt
        hline(arr, cx - 10, ground_y - 8, 20, C_BELT_M)
        pp(arr, cx - 2, ground_y - 8, C_BUCKLE)
        # Head (silhouette)
        rect_fill(arr, cx - 28, ground_y - 18, 16, 12, C_HAIR_D)
        rect_fill(arr, cx - 26, ground_y - 14, 12, 6,  C_BAND_D)
        pp(arr, cx - 18, ground_y - 10, C_SKIN_D)
        # Cloak
        rect_fill(arr, cx + 8,  ground_y - 12, 20, 10, C_CLK_M)
        # Legs
        rect_fill(arr, cx + 14, ground_y - 2,  24, 8, C_LEATH_D)
        rect_fill(arr, cx + 16, ground_y + 4,  16, 6, C_LEATH_D)
        # Daggers scattered
        draw_dagger_standalone(arr, cx - 16, ground_y - 24, angle_deg=45)
        draw_dagger_standalone(arr, cx + 22, ground_y - 20, angle_deg=120)
        # Large death shadow
        draw_shadow(arr, cx, FEET, w=32, dy_offset=0)

    return Image.fromarray(arr, 'RGBA')


def gen_dead():
    frames = [make_dead_frame(i) for i in range(4)]
    strip = Image.new('RGBA', (1024, 256), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * 256, 0))
    return strip


# ─── CAST ANIMATION (4 frames) ───────────────────────────────────────────────
# Throw smoke bomb, smoke cloud effect

def draw_smoke_cloud(arr, cx, cy, radius, stage):
    """
    Stage 0: tiny puff
    Stage 1: growing cloud with wispy tendrils
    Stage 2: full smoke burst
    Stage 3: dissipating cloud
    """
    if stage == 0:
        for dy_ in range(-4, 6, 2):
            for dx_ in range(-4, 6, 2):
                d = math.hypot(dx_, dy_)
                if d < 4:
                    pp(arr, cx + dx_, cy + dy_, C_SMOKE_D)

    elif stage == 1:
        for dy_ in range(-radius, radius + 1, 2):
            for dx_ in range(-radius, radius + 1, 2):
                d = math.hypot(dx_, dy_)
                if d > radius:
                    continue
                col = C_SMOKE_D if d < radius * 0.4 else C_SMOKE_M
                pp(arr, cx + dx_, cy + dy_, col)
        # Wispy tendrils
        for angle_i in range(0, 360, 60):
            for dist in range(radius, radius + 12, 4):
                ax = int(cx + dist * math.cos(math.radians(angle_i))) & ~1
                ay = int(cy + dist * math.sin(math.radians(angle_i))) & ~1
                alpha = max(0, 100 - (dist - radius) * 10)
                if alpha > 0:
                    blend_px(arr, ax, ay, (*C_SMOKE_M[:3], alpha))

    elif stage == 2:
        for dy_ in range(-radius, radius + 1, 2):
            for dx_ in range(-radius, radius + 1, 2):
                d = math.hypot(dx_, dy_)
                if d > radius:
                    continue
                col = (C_SMOKE_D if d < radius * 0.3
                       else C_SMOKE_M if d < radius * 0.65
                       else C_SMOKE_L)
                # Make cloud blobby/irregular
                wobble = math.sin(math.atan2(dy_, dx_) * 3) * radius * 0.15
                if d < radius + wobble:
                    pp(arr, cx + dx_, cy + dy_, col)
        # Wide tendrils in 6 directions
        for angle_i in range(0, 360, 60):
            for dist in range(radius, radius + 20, 4):
                ax = int(cx + dist * math.cos(math.radians(angle_i))) & ~1
                ay = int(cy + dist * math.sin(math.radians(angle_i))) & ~1
                alpha = max(0, 120 - (dist - radius) * 7)
                if alpha > 0:
                    blend_px(arr, ax, ay, (*C_SMOKE_L[:3], alpha))

    elif stage == 3:
        # Dissipating: hollow ring of smoke
        inner_r = max(2, radius - 10)
        for dy_ in range(-radius, radius + 1, 2):
            for dx_ in range(-radius, radius + 1, 2):
                d = math.hypot(dx_, dy_)
                if inner_r <= d <= radius:
                    fade = int(120 * (1.0 - (d - inner_r) / max(radius - inner_r, 1)))
                    bpx = cx + dx_
                    bpy = cy + dy_
                    if 0 <= bpx < 256 and 0 <= bpy < 256:
                        blend_px(arr, bpx, bpy, (*C_SMOKE_M[:3], fade))


def make_cast_frame(fn):
    arr = new_frame()

    lean = [0, 4, 6, 2][fn]
    dy   = [0, -2, -2, 0][fn]
    cx   = CX + lean

    draw_torso(arr, cx, dy)
    draw_legs_idle(arr, cx, dy)

    tys = SHLDR + dy
    if fn == 0:
        # Reaching into pouch for smoke bomb
        # Right arm reaching down to belt
        rect_fill(arr, cx + 8,  tys + 4, 8, 10, C_LEATH_M)
        rect_fill(arr, cx + 10, tys + 12, 8, 10, C_CHAR_M)
        rect_fill(arr, cx + 12, tys + 20, 6, 6,  C_SKIN_M)
        # Left arm out for balance
        rect_fill(arr, cx - 14, tys + 2, 8, 10, C_LEATH_M)
        rect_fill(arr, cx - 16, tys + 10, 8, 10, C_CHAR_M)
        rect_fill(arr, cx - 16, tys + 18, 6, 6,  C_SKIN_M)
        draw_dagger(arr, cx - 14, tys + 22, angle_deg=200, short=True)
        # Tiny smoke bomb in right hand — small dark sphere
        pp(arr, cx + 14, tys + 20, C_OUTLINE)
        pp(arr, cx + 16, tys + 18, C_CHAR_M)
        pp(arr, cx + 16, tys + 20, C_CHAR_H)

    elif fn == 1:
        # Winding up throw — arm back
        rect_fill(arr, cx + 10, tys - 2, 8, 10, C_LEATH_M)
        rect_fill(arr, cx + 14, tys + 6, 8, 10, C_CHAR_M)
        rect_fill(arr, cx + 16, tys + 14, 6, 6,  C_SKIN_M)
        # Smoke bomb in throwing hand
        pp(arr, cx + 18, tys + 12, C_OUTLINE)
        pp(arr, cx + 20, tys + 10, C_CHAR_M)
        pp(arr, cx + 20, tys + 12, C_CHAR_H)
        # Left arm with dagger out for guard
        rect_fill(arr, cx - 14, tys + 2, 8, 10, C_LEATH_M)
        rect_fill(arr, cx - 16, tys + 10, 8, 10, C_CHAR_M)
        rect_fill(arr, cx - 16, tys + 18, 6, 6,  C_SKIN_M)
        draw_dagger(arr, cx - 14, tys + 22, angle_deg=160, short=True)

    elif fn == 2:
        # Release — arm thrust forward, smoke bomb just launched
        rect_fill(arr, cx + 2,  tys,    8, 8, C_LEATH_M)
        rect_fill(arr, cx - 2,  tys + 6, 8, 8, C_CHAR_M)
        rect_fill(arr, cx - 4,  tys + 12, 6, 6, C_SKIN_M)
        # Left arm braced
        rect_fill(arr, cx - 16, tys + 2, 8, 10, C_LEATH_M)
        rect_fill(arr, cx - 16, tys + 10, 8, 10, C_CHAR_M)
        rect_fill(arr, cx - 16, tys + 18, 6, 6,  C_SKIN_M)
        draw_dagger(arr, cx - 14, tys + 22, angle_deg=170, short=True)
        # Smoke cloud erupts to the right and ahead of character
        smoke_cx = cx + 40
        smoke_cy = tys + 10
        draw_smoke_cloud(arr, smoke_cx, smoke_cy, radius=18, stage=2)

    elif fn == 3:
        # Aftermath — arm lowering, smoke dissipating
        rect_fill(arr, cx + 4,  tys + 4, 8, 10, C_LEATH_M)
        rect_fill(arr, cx + 4,  tys + 12, 8, 10, C_CHAR_M)
        rect_fill(arr, cx + 4,  tys + 20, 6, 6,  C_SKIN_M)
        draw_arm_left(arr, cx, dy, pose='idle')
        draw_dagger(arr, cx + 6, tys + 24, angle_deg=160)
        # Residual smoke dissipating
        smoke_cx = cx + 44
        smoke_cy = tys + 8
        draw_smoke_cloud(arr, smoke_cx, smoke_cy, radius=14, stage=3)

    draw_head_alert(arr, cx, dy)
    draw_shadow(arr, cx, FEET, w=22, dy_offset=dy)

    return Image.fromarray(arr, 'RGBA')


def gen_cast():
    frames = [make_cast_frame(i) for i in range(4)]
    strip = Image.new('RGBA', (1024, 256), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * 256, 0))
    return strip


# ─── DEFEND ANIMATION (4 frames) ─────────────────────────────────────────────
# Cross daggers in X-block, sparks

def make_defend_frame(fn):
    arr = new_frame()

    # F0: raising daggers to guard position
    # F1: full X-block, daggers crossed
    # F2: impact — sparks fly from crossed blades
    # F3: hold guard (slight compression from impact)

    lean = [0, -2, -2, -2][fn]
    dy   = [0, -2, -2, -2][fn]
    cx   = CX + lean

    draw_torso(arr, cx, dy)

    # Crouched guard legs — wider stance
    ty = WAIST + dy
    rect_fill(arr, cx - 18, ty,      14, 12, C_LEATH_M)
    rect_fill(arr, cx - 18, ty + 10, 12, 12, C_CHAR_M)
    rect_fill(arr, cx - 20, ty + 20, 16, 8,  C_LEATH_D)
    hline(arr, cx - 20, ty + 20, 16, C_LEATH_H)
    rect_fill(arr, cx + 4,  ty,      14, 12, C_LEATH_M)
    rect_fill(arr, cx + 4,  ty + 10, 12, 12, C_CHAR_M)
    rect_fill(arr, cx + 4,  ty + 20, 16, 8,  C_LEATH_D)
    hline(arr, cx + 4, ty + 20, 16, C_LEATH_H)

    tys = SHLDR + dy
    if fn == 0:
        # Arms rising into guard
        draw_arm_left(arr, cx, dy, pose='idle')
        draw_arm_right(arr, cx, dy, pose='idle')

    elif fn == 1:
        # Full X-block above chest level
        # Left arm up-right
        rect_fill(arr, cx - 12, tys - 4, 8, 12, C_LEATH_M)
        rect_fill(arr, cx - 8,  tys + 6, 8, 10, C_CHAR_M)
        rect_fill(arr, cx - 4,  tys + 14, 6, 6,  C_SKIN_M)
        draw_dagger(arr, cx - 2, tys + 12, angle_deg=45, short=True)
        # Right arm up-left
        rect_fill(arr, cx + 4,  tys - 4, 8, 12, C_LEATH_M)
        rect_fill(arr, cx,      tys + 6, 8, 10, C_CHAR_M)
        rect_fill(arr, cx - 4,  tys + 14, 6, 6,  C_SKIN_M)
        draw_dagger(arr, cx - 6, tys + 10, angle_deg=135)

    elif fn == 2:
        # Same as fn==1 but compressed 2px down + sparks
        tys2 = tys + 2
        rect_fill(arr, cx - 12, tys2 - 4, 8, 12, C_LEATH_M)
        rect_fill(arr, cx - 8,  tys2 + 6, 8, 10, C_CHAR_M)
        rect_fill(arr, cx - 4,  tys2 + 14, 6, 6,  C_SKIN_M)
        draw_dagger(arr, cx - 2, tys2 + 12, angle_deg=45, short=True)
        rect_fill(arr, cx + 4,  tys2 - 4, 8, 12, C_LEATH_M)
        rect_fill(arr, cx,      tys2 + 6, 8, 10, C_CHAR_M)
        rect_fill(arr, cx - 4,  tys2 + 14, 6, 6,  C_SKIN_M)
        draw_dagger(arr, cx - 6, tys2 + 10, angle_deg=135)
        # Spark burst at the X intersection
        sx = cx - 2
        sy = tys2 + 10
        for angle_i in range(0, 360, 30):
            for dist in range(2, 14, 4):
                ax = int(sx + dist * math.cos(math.radians(angle_i))) & ~1
                ay = int(sy + dist * math.sin(math.radians(angle_i))) & ~1
                alpha = max(0, 200 - dist * 16)
                col = C_SPARK_Y if (angle_i // 30) % 2 == 0 else C_SPARK_W
                blend_px(arr, ax, ay, (*col[:3], alpha))

    elif fn == 3:
        # Hold guard — same as fn==1, slightly forward lean
        draw_arm_left(arr, cx, dy, pose='guard')
        draw_arm_right(arr, cx, dy, pose='guard')

    draw_head_alert(arr, cx, dy, lean_x=lean)
    draw_shadow(arr, cx, FEET, w=24, dy_offset=dy)

    return Image.fromarray(arr, 'RGBA')


def gen_defend():
    frames = [make_defend_frame(i) for i in range(4)]
    strip = Image.new('RGBA', (1024, 256), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * 256, 0))
    return strip


# ─── ITEM ANIMATION (4 frames) ───────────────────────────────────────────────
# Quick hand into belt pouch, pull out vial, toss up, use/consume

def draw_vial(arr, vx, vy, glowing=False):
    """Draw a small poison/potion vial (8px wide x 14px tall)."""
    # Cork
    rect_fill(arr, vx + 2, vy - 4, 6, 4, C_POUCH_M)
    hline(arr, vx + 2, vy - 4, 6, C_POUCH_D)
    pp(arr, vx + 2, vy - 4, C_OUTLINE)
    pp(arr, vx + 6, vy - 4, C_OUTLINE)

    # Neck
    rect_fill(arr, vx + 2, vy, 6, 4, C_DAG_M)
    pp(arr, vx + 2, vy, C_OUTLINE)
    pp(arr, vx + 6, vy, C_OUTLINE)

    # Body
    bw, bh = 10, 10
    body_col = C_VIAL_M if glowing else C_VIAL_D
    liq_col  = C_VIAL_H if glowing else C_VIAL_M
    rect_fill(arr, vx, vy + 4, bw, bh, body_col)
    # Liquid interior
    rect_fill(arr, vx + 2, vy + 6, bw - 4, bh - 4, liq_col)
    # Highlight
    pp(arr, vx + 2, vy + 6, C_VIAL_H)
    pp(arr, vx + 2, vy + 8, C_VIAL_H)
    # Outline
    for i in range(bw):
        pp(arr, vx + i, vy + 4,       C_OUTLINE)
        pp(arr, vx + i, vy + 4 + bh - 2, C_OUTLINE)
    for i in range(bh):
        pp(arr, vx,       vy + 4 + i, C_OUTLINE)
        pp(arr, vx + bw - 2, vy + 4 + i, C_OUTLINE)

    if glowing:
        # Glow halo
        for r in range(6, 2, -1):
            alpha = max(0, 60 - r * 10)
            for angle_i in range(12):
                angle = angle_i * (2 * math.pi / 12)
                gx = int(vx + bw // 2 + r * math.cos(angle)) & ~1
                gy = int(vy + 4 + bh // 2 + r * math.sin(angle)) & ~1
                blend_px(arr, gx, gy, (*C_VIAL_GL[:3], alpha))


def make_item_frame(fn):
    arr = new_frame()

    lean = [0, 2, 4, 2][fn]
    dy   = [0, -2, -4, -2][fn]
    cx   = CX + lean

    draw_torso(arr, cx, dy)
    draw_legs_idle(arr, cx, dy)

    tys = SHLDR + dy
    if fn == 0:
        # Right arm dips to belt
        rect_fill(arr, cx + 8,  tys + 4, 8, 10, C_LEATH_M)
        rect_fill(arr, cx + 10, tys + 12, 8, 12, C_CHAR_M)
        rect_fill(arr, cx + 12, tys + 22, 6, 6,  C_SKIN_M)
        # Small pouch indicator
        rect_fill(arr, cx + 12, tys + 26, 8, 6,  C_POUCH_M)
        hline(arr, cx + 12, tys + 26, 8, C_POUCH_D)
        # Left arm with dagger held ready
        draw_arm_left(arr, cx, dy, pose='idle')

    elif fn == 1:
        # Vial pulled out, right arm swinging up
        rect_fill(arr, cx + 8,  tys,    8, 10, C_LEATH_M)
        rect_fill(arr, cx + 10, tys + 8, 8, 10, C_CHAR_M)
        rect_fill(arr, cx + 12, tys + 16, 6, 6,  C_SKIN_M)
        draw_vial(arr, cx + 14, tys + 4, glowing=False)
        draw_arm_left(arr, cx, dy, pose='idle')

    elif fn == 2:
        # Vial held up high, glowing
        rect_fill(arr, cx + 6,  tys - 4, 8, 10, C_LEATH_M)
        rect_fill(arr, cx + 8,  tys + 4, 8, 10, C_CHAR_M)
        rect_fill(arr, cx + 10, tys + 12, 6, 6,  C_SKIN_M)
        draw_vial(arr, cx + 10, tys - 12, glowing=True)
        draw_arm_left(arr, cx, dy, pose='idle')

    elif fn == 3:
        # Vial consumed — sparkle, arm returning, flash residue
        rect_fill(arr, cx + 8,  tys + 2, 8, 10, C_LEATH_M)
        rect_fill(arr, cx + 10, tys + 10, 8, 10, C_CHAR_M)
        rect_fill(arr, cx + 12, tys + 18, 6, 6,  C_SKIN_M)
        # Sparkle where vial was
        sx = cx + 16
        sy = tys - 4
        pp(arr, sx, sy, C_SPARK_W)
        for d in range(2, 14, 4):
            alpha = max(0, 180 - d * 14)
            for angle_i in range(8):
                angle = angle_i * (2 * math.pi / 8)
                gx = int(sx + d * math.cos(angle)) & ~1
                gy = int(sy + d * math.sin(angle)) & ~1
                blend_px(arr, gx, gy, (*C_VIAL_H[:3], alpha))
        draw_arm_left(arr, cx, dy, pose='idle')

    draw_head(arr, cx, HEAD, dy)
    draw_shadow(arr, cx, FEET, w=22, dy_offset=dy)

    return Image.fromarray(arr, 'RGBA')


def gen_item():
    frames = [make_item_frame(i) for i in range(4)]
    strip = Image.new('RGBA', (1024, 256), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * 256, 0))
    return strip


# ─── VICTORY ANIMATION (4 frames) ────────────────────────────────────────────
# Twirl dagger, cocky pose, flip and catch

def make_victory_frame(fn):
    arr = new_frame()

    # F0: triumphant lean-back, dagger raised
    # F1: dagger tossed up (spinning in air above)
    # F2: both arms wide — cocky pose
    # F3: catching dagger, wink/grin

    lean  = [2,  4,  0, -2][fn]
    dy    = [0, -4, -2,  0][fn]
    cx    = CX + lean

    draw_torso(arr, cx, dy)
    draw_legs_idle(arr, cx, dy)

    tys = SHLDR + dy
    if fn == 0:
        # Right arm raised, dagger pointing upward
        rect_fill(arr, cx + 6,  tys - 6, 8, 12, C_LEATH_M)
        rect_fill(arr, cx + 8,  tys + 4, 6, 10, C_CHAR_M)
        rect_fill(arr, cx + 10, tys + 12, 6, 6,  C_SKIN_M)
        draw_dagger(arr, cx + 12, tys + 10, angle_deg=290)
        # Left arm on hip
        rect_fill(arr, cx - 18, tys + 4, 8, 8,  C_LEATH_M)
        rect_fill(arr, cx - 18, tys + 10, 8, 10, C_CHAR_M)
        rect_fill(arr, cx - 16, tys + 18, 6, 6,  C_SKIN_M)
        draw_dagger(arr, cx - 14, tys + 22, angle_deg=220, short=True)

    elif fn == 1:
        # Dagger spinning in air above character
        # Arm that threw it — reaching up
        rect_fill(arr, cx + 4,  tys - 8, 8, 14, C_LEATH_M)
        rect_fill(arr, cx + 6,  tys + 4, 6, 10, C_CHAR_M)
        rect_fill(arr, cx + 8,  tys + 12, 6, 6,  C_SKIN_M)
        # Spinning dagger above (rotated at 45°)
        dagger_air_x = cx + 12
        dagger_air_y = tys - 28
        draw_dagger(arr, dagger_air_x, dagger_air_y, angle_deg=45)
        # Left arm also raised (excitement)
        rect_fill(arr, cx - 14, tys - 4, 8, 12, C_LEATH_M)
        rect_fill(arr, cx - 14, tys + 6, 8, 10, C_CHAR_M)
        rect_fill(arr, cx - 12, tys + 14, 6, 6,  C_SKIN_M)
        draw_dagger(arr, cx - 10, tys + 12, angle_deg=320, short=True)

    elif fn == 2:
        # Arms spread wide — cocky open stance
        # Right arm out-right
        rect_fill(arr, cx + 8,  tys + 2, 10, 8, C_LEATH_M)
        rect_fill(arr, cx + 16, tys + 4, 10, 8, C_CHAR_M)
        rect_fill(arr, cx + 24, tys + 6, 6, 6,  C_SKIN_M)
        draw_dagger(arr, cx + 26, tys + 8, angle_deg=90)
        # Left arm out-left
        rect_fill(arr, cx - 18, tys + 2, 10, 8, C_LEATH_M)
        rect_fill(arr, cx - 26, tys + 4, 10, 8, C_CHAR_M)
        rect_fill(arr, cx - 30, tys + 6, 6, 6,  C_SKIN_M)
        draw_dagger(arr, cx - 28, tys + 8, angle_deg=270, short=True)

    elif fn == 3:
        # Catching dagger — arm back in, confident
        rect_fill(arr, cx + 6,  tys,    8, 10, C_LEATH_M)
        rect_fill(arr, cx + 8,  tys + 8, 8, 10, C_CHAR_M)
        rect_fill(arr, cx + 10, tys + 16, 6, 6,  C_SKIN_M)
        draw_dagger(arr, cx + 12, tys + 14, angle_deg=270)
        # Small sparkle — dagger just caught
        pp(arr, cx + 16, tys + 10, C_SPARK_Y)
        pp(arr, cx + 18, tys + 8,  C_SPARK_W)
        pp(arr, cx + 14, tys + 8,  C_SPARK_Y)
        draw_arm_left(arr, cx, dy, pose='idle')

    # Head — slightly more open/happy expressions
    draw_head(arr, cx, HEAD, dy)

    draw_shadow(arr, cx, FEET, w=22, dy_offset=dy)

    return Image.fromarray(arr, 'RGBA')


def gen_victory():
    frames = [make_victory_frame(i) for i in range(4)]
    strip = Image.new('RGBA', (1024, 256), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * 256, 0))
    return strip


# ─── SAVE STRIPS ─────────────────────────────────────────────────────────────

ANIMATIONS = [
    ('idle',    gen_idle,    512,  256, 2),
    ('walk',    gen_walk,   1536,  256, 6),
    ('attack',  gen_attack, 1536,  256, 6),
    ('hit',     gen_hit,    1024,  256, 4),
    ('dead',    gen_dead,   1024,  256, 4),
    ('cast',    gen_cast,   1024,  256, 4),
    ('defend',  gen_defend, 1024,  256, 4),
    ('item',    gen_item,   1024,  256, 4),
    ('victory', gen_victory, 1024, 256, 4),
]


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
            f"  ERROR: {path} frame {fi} has only {npx} opaque pixels"
    assert arr[0, 0, 3] == 0, f"  ERROR: {path} background not transparent"
    return results


def main():
    print("=" * 60)
    print("Generating Rogue sprite strips")
    print("=" * 60)

    all_pass = True
    for name, gen_fn, exp_w, exp_h, n_frames in ANIMATIONS:
        print(f"\n[{name.upper()}] generating {n_frames} frames -> {exp_w}x{exp_h}...")
        strip = gen_fn()
        assert strip.size == (exp_w, exp_h), \
            f"Generated strip size mismatch: {strip.size} != ({exp_w},{exp_h})"
        out_path = os.path.join(OUT_DIR, f"{name}.png")
        strip.save(out_path, 'PNG')
        print(f"  Saved: {out_path}")

        # Validate
        try:
            pixel_counts = validate_strip(out_path, exp_w, exp_h, n_frames)
            for fi, npx in enumerate(pixel_counts):
                print(f"  Frame {fi}: {npx:5d} opaque pixels  [PASS]")
            print(f"  Dimensions: {exp_w}x{exp_h}  [PASS]")
            print(f"  Background: transparent  [PASS]")
        except AssertionError as e:
            print(str(e))
            all_pass = False

        # Save 3x preview to tmp
        preview = strip.resize((exp_w * 3, exp_h * 3), Image.NEAREST)
        preview.save(os.path.join(TMP_DIR, f"rogue_{name}_3x.png"))

    print("\n" + "=" * 60)
    if all_pass:
        print("ALL STRIPS PASS VALIDATION")
    else:
        print("SOME STRIPS FAILED — check output above")
    print("=" * 60)


if __name__ == "__main__":
    main()
