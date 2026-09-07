#!/usr/bin/env python3
"""
Cleric extended sprite generator for Cowardly Irregular.
Generates 5 additional animation strips not covered by gen_cleric_sprites.py:
  - advance.png  (4 frames, 1024x256)  Battle state: raising staff for divine power
  - defer.png    (4 frames, 1024x256)  Battle state: kneeling in prayer/shield
  - heal.png     (6 frames, 1536x256)  Ability: Cure/Cura healing spell
  - raise.png    (6 frames, 1536x256)  Ability: Resurrection — dramatic holy pillar
  - buff.png     (4 frames, 1024x256)  Ability: Protect/Shell buff

All frames: 256x256 px, transparent background, SNES 16-bit pixel art.
Character proportions match gen_cleric_sprites.py exactly.
"""

from PIL import Image
import numpy as np
import math
import os

OUT_DIR = "/home/struktured/projects/cowardly-irregular-sprite-gen/assets/sprites/jobs/cleric"
os.makedirs(OUT_DIR, exist_ok=True)

# ─── PALETTE (identical to gen_cleric_sprites.py) ────────────────────────────
OUTLINE      = (30, 18, 18, 255)
OUTLINE_SOFT = (55, 38, 38, 255)

SKIN_HILIT   = (255, 225, 190, 255)
SKIN_LIGHT   = (245, 205, 160, 255)
SKIN_MID     = (215, 170, 120, 255)
SKIN_DARK    = (170, 120,  75, 255)
SKIN_SHADOW  = (130,  85,  50, 255)

HAIR_HILIT   = (210, 165, 100, 255)
HAIR_LIGHT   = (185, 138,  78, 255)
HAIR_MID     = (148, 105,  52, 255)
HAIR_DARK    = (108,  72,  30, 255)

ROBE_HILIT   = (255, 252, 246, 255)
ROBE_LIGHT   = (242, 238, 224, 255)
ROBE_MID     = (220, 214, 196, 255)
ROBE_DARK    = (190, 182, 160, 255)
ROBE_SHADOW  = (155, 146, 124, 255)
ROBE_DEEP    = (118, 110,  90, 255)

RED_HILIT    = (240,  80,  80, 255)
RED_TRIM     = (204,  28,  44, 255)
RED_MID      = (168,  18,  32, 255)
RED_DARK     = (120,  10,  20, 255)

GOLD_HILIT   = (255, 228,  90, 255)
GOLD_LIGHT   = (235, 195,  55, 255)
GOLD_MID     = (205, 160,  28, 255)
GOLD_DARK    = (155, 112,  10, 255)
GOLD_DEEP    = (105,  72,   5, 255)

PINK_HILIT   = (255, 200, 205, 255)
PINK_LIGHT   = (238, 175, 180, 255)
PINK_MID     = (210, 142, 148, 255)
PINK_DARK    = (168, 102, 108, 255)

STAFF_HILIT  = (215, 175, 118, 255)
STAFF_LIGHT  = (192, 152,  90, 255)
STAFF_MID    = (155, 118,  65, 255)
STAFF_DARK   = (115,  82,  40, 255)
STAFF_DEEP   = ( 78,  52,  22, 255)

ORB_HILIT    = (255, 252, 210, 255)
ORB_LIGHT    = (252, 240, 145, 255)
ORB_MID      = (225, 195,  62, 255)
ORB_DARK     = (168, 135,  18, 255)
ORB_CORE     = (255, 255, 240, 255)

BOOT_HILIT   = (218, 195, 155, 255)
BOOT_LIGHT   = (195, 168, 125, 255)
BOOT_MID     = (162, 132,  92, 255)
BOOT_DARK    = (120,  95,  62, 255)
BOOT_DEEP    = ( 82,  60,  35, 255)

HOLY_PURE    = (255, 255, 255, 255)
HOLY_A       = (255, 252, 220, 240)
HOLY_B       = (255, 238, 160, 200)
HOLY_C       = (255, 215,  90, 140)
HOLY_D       = (240, 175,  40,  80)

# Healing green-gold palette (for Cure/Cura)
HEAL_BRIGHT  = (180, 255, 160, 255)
HEAL_LIGHT   = (140, 230, 120, 220)
HEAL_MID     = (100, 195,  85, 180)
HEAL_DARK    = ( 60, 148,  55, 140)
HEAL_GLOW    = (200, 255, 180, 100)

# Resurrection pure white/gold
RAISE_WHITE  = (255, 255, 255, 255)
RAISE_CREAM  = (255, 250, 225, 220)
RAISE_GOLD   = (255, 232, 100, 200)
RAISE_DIVINE = (240, 200,  60, 160)

# Barrier/buff colors (pale blue-gold)
BARRIER_EDGE = (210, 235, 255, 200)
BARRIER_MID  = (180, 215, 255, 140)
BARRIER_GLOW = (160, 200, 255,  80)

TRANS = (0, 0, 0, 0)

# ─── CHARACTER LAYOUT (identical to gen_cleric_sprites.py) ───────────────────
CX_BODY   = 122
FEET_Y    = 163
HEAD_H    = 30
TORSO_H   = 32
LROBE_H   = 34
TOTAL_H   = 98

HEAD_TOP  = FEET_Y - TOTAL_H      # 65
TORSO_TOP = HEAD_TOP + HEAD_H     # 95
LROBE_TOP = TORSO_TOP + TORSO_H   # 127
LROBE_BOT = LROBE_TOP + LROBE_H   # 161

STAFF_X          = CX_BODY + 20
STAFF_ORB_DEFAULT = HEAD_TOP - 22

# ─── PIXEL PRIMITIVES ────────────────────────────────────────────────────────

def new_frame():
    return np.zeros((256, 256, 4), dtype=np.uint8)

def sp(a, x, y, c):
    if 0 <= x < 256 and 0 <= y < 256:
        a[y, x] = c

def blend_sp(a, x, y, c):
    if 0 <= x < 256 and 0 <= y < 256:
        src_a = c[3] / 255.0
        dst_a = a[y, x, 3] / 255.0
        if src_a <= 0:
            return
        out_a = src_a + dst_a * (1 - src_a)
        if out_a < 0.001:
            return
        r = int((c[0] * src_a + a[y,x,0] * dst_a * (1-src_a)) / out_a)
        g = int((c[1] * src_a + a[y,x,1] * dst_a * (1-src_a)) / out_a)
        b = int((c[2] * src_a + a[y,x,2] * dst_a * (1-src_a)) / out_a)
        a[y, x] = (min(255,r), min(255,g), min(255,b), int(out_a*255))

def hline(a, x0, x1, y, c):
    for x in range(x0, x1+1):
        sp(a, x, y, c)

def vline(a, x, y0, y1, c):
    for y in range(y0, y1+1):
        sp(a, x, y, c)

def disk(a, cx, cy, r, c):
    for dy in range(-r, r+1):
        for dx in range(-r, r+1):
            if dx*dx + dy*dy <= r*r:
                sp(a, cx+dx, cy+dy, c)

def ring(a, cx, cy, r, thickness, c):
    for dy in range(-r-thickness, r+thickness+1):
        for dx in range(-r-thickness, r+thickness+1):
            d2 = dx*dx + dy*dy
            if (r-thickness)**2 <= d2 <= (r+thickness)**2:
                sp(a, cx+dx, cy+dy, c)

def shadow_ellipse(a, cx, y, w, h, alpha):
    for dx in range(-w, w+1):
        t = (dx/w)**2
        base_a = int(alpha * (1.0 - t))
        for dy in range(h):
            fa = max(0, base_a - dy * (alpha // h))
            blend_sp(a, cx+dx, y+dy, (36, 26, 48, fa))

def tint_region(a, x0, y0, x1, y1, dr, dg, db):
    for y in range(max(0,y0), min(256,y1+1)):
        for x in range(max(0,x0), min(256,x1+1)):
            if a[y,x,3] > 10:
                r,g,b,al = a[y,x]
                a[y,x] = (
                    int(min(255, max(0, int(r)+dr))),
                    int(min(255, max(0, int(g)+dg))),
                    int(min(255, max(0, int(b)+db))),
                    al
                )

def add_glow(arr, cx, cy, inner_r, outer_r, col_inner, col_outer, steps=6):
    for r in range(outer_r, inner_r - 1, -1):
        t = (r - inner_r) / max(1, outer_r - inner_r)
        ra = int(col_inner[0] + t * (col_outer[0] - col_inner[0]))
        ga = int(col_inner[1] + t * (col_outer[1] - col_inner[1]))
        ba = int(col_inner[2] + t * (col_outer[2] - col_inner[2]))
        aa = int(col_inner[3] + t * (col_outer[3] - col_inner[3]))
        for deg in range(0, 360, steps):
            rx = cx + int(r * math.cos(math.radians(deg)))
            ry = cy + int(r * math.sin(math.radians(deg)))
            blend_sp(arr, rx, ry, (ra, ga, ba, aa))

def add_cross_ray(arr, cx, cy, length, col):
    for r in range(1, length + 1):
        a_v = int(col[3] * (1 - r / length))
        c = (col[0], col[1], col[2], a_v)
        blend_sp(arr, cx + r, cy, c)
        blend_sp(arr, cx - r, cy, c)
        blend_sp(arr, cx, cy + r, c)
        blend_sp(arr, cx, cy - r, c)

def add_diag_rays(arr, cx, cy, length, col):
    for ang in [45, 135, 225, 315]:
        for r in range(1, length + 1):
            a_v = int(col[3] * (1 - r / length))
            rx = cx + int(r * math.cos(math.radians(ang)))
            ry = cy + int(r * math.sin(math.radians(ang)))
            blend_sp(arr, rx, ry, (col[0], col[1], col[2], a_v))

def sparkle_cluster(arr, cx, cy, radius, col, count=8):
    """Scatter small sparkle pixels in a radius."""
    for ang in range(0, 360, 360 // count):
        for r in [radius // 2, radius]:
            rx = cx + int(r * math.cos(math.radians(ang)))
            ry = cy + int(r * math.sin(math.radians(ang)))
            sp(arr, rx, ry, col)
            sp(arr, rx+1, ry, (col[0], col[1], col[2], col[3]//2))
            sp(arr, rx, ry+1, (col[0], col[1], col[2], col[3]//2))

# ─── CHARACTER COMPONENTS (copied from gen_cleric_sprites.py) ─────────────────

def draw_shadow(a, cx, y_feet):
    shadow_ellipse(a, cx, y_feet+1, 28, 5, 90)

def draw_boots(a, cx, y_feet, walk_phase=0.0):
    phase = walk_phase
    lx = cx - 12 + int(phase * 6)
    rx = cx + 8  - int(phase * 6)
    y  = y_feet

    for dx in range(-6, 4):
        sp(a, lx+dx, y,   BOOT_MID   if abs(dx) < 5 else OUTLINE)
        sp(a, lx+dx, y-1, BOOT_LIGHT if abs(dx) < 5 else OUTLINE)
    sp(a, lx-6, y,   OUTLINE)
    sp(a, lx+3,  y,   OUTLINE)
    sp(a, lx-5, y-1, BOOT_HILIT)
    sp(a, lx-4, y-1, BOOT_HILIT)
    sp(a, lx-2, y-2, BOOT_DARK)
    sp(a, lx-1, y-2, BOOT_DARK)
    sp(a, lx,   y-2, BOOT_DARK)
    for dx in range(-5, 3):
        sp(a, lx+dx, y+1, OUTLINE)

    for dx in range(-4, 7):
        sp(a, rx+dx, y,   BOOT_LIGHT  if abs(dx-1) < 5 else OUTLINE)
        sp(a, rx+dx, y-1, BOOT_HILIT  if abs(dx-1) < 4 else BOOT_LIGHT)
    sp(a, rx-4, y,   OUTLINE)
    sp(a, rx+6,  y,   OUTLINE)
    sp(a, rx+3, y-1, BOOT_HILIT)
    sp(a, rx+4, y-1, BOOT_HILIT)
    sp(a, rx+1, y-2, BOOT_DARK)
    sp(a, rx+2, y-2, BOOT_DARK)
    sp(a, rx+3, y-2, BOOT_DARK)
    for dx in range(-3, 6):
        sp(a, rx+dx, y+1, OUTLINE)

def draw_lower_robe(a, cx, y_top, y_bot, sway_x=0):
    robe_height = y_bot - y_top
    for dy in range(robe_height + 1):
        t = dy / max(1, robe_height)
        half_w = int(14 + t * 12)
        sw = int(sway_x * t * 0.5)
        for dx in range(-half_w, half_w+1):
            rx = cx + dx + sw
            if dx == -half_w or dx == half_w:
                col = OUTLINE
            elif abs(dx) == half_w - 1:
                col = ROBE_SHADOW
            elif abs(dx) >= half_w - 3:
                col = ROBE_DARK
            elif dx < -2 + sw//2:
                col = ROBE_MID
            elif dx < 2 + sw//2:
                col = ROBE_LIGHT
            else:
                col = ROBE_HILIT
            sp(a, rx, y_top + dy, col)

    for dx in range(-12, 13):
        rx = cx + dx + int(sway_x * 0.5)
        sp(a, rx, y_bot - 2, PINK_MID)
        sp(a, rx, y_bot - 1, PINK_LIGHT)
        sp(a, rx, y_bot,     PINK_HILIT)
    for dx in range(-11, 12):
        rx = cx + dx + int(sway_x * 0.5)
        sp(a, rx, y_bot + 1, OUTLINE)

    fold_x = cx + 3 + int(sway_x * 0.3)
    for dy in range(4, robe_height - 4):
        sp(a, fold_x, y_top + dy, ROBE_DARK)
    fold_x2 = cx - 6 + int(sway_x * 0.2)
    for dy in range(6, robe_height - 6):
        sp(a, fold_x2, y_top + dy, ROBE_SHADOW)

def draw_torso(a, cx, y_top, arm_pose='idle', bob=0):
    y = y_top
    torso_h = 32

    for dy in range(torso_h):
        t = dy / torso_h
        half_w = int(13 + t * 3)
        for dx in range(-half_w, half_w + 1):
            if dx == -half_w or dx == half_w:
                col = OUTLINE
            elif abs(dx) == half_w - 1:
                col = ROBE_SHADOW
            elif abs(dx) >= half_w - 3:
                col = ROBE_DARK
            elif dx < -1:
                col = ROBE_MID
            elif dx < 2:
                col = ROBE_LIGHT
            else:
                col = ROBE_HILIT
            sp(a, cx + dx, y + dy, col)

    for dy in range(2, torso_h - 2):
        sp(a, cx, y + dy, ROBE_DARK)
        sp(a, cx + 1, y + dy, ROBE_MID)

    for dx in range(-8, 9):
        sp(a, cx + dx, y + 8,  GOLD_DARK)
        sp(a, cx + dx, y + 16, GOLD_DARK)
    for dx in range(-7, 8, 3):
        sp(a, cx + dx, y + 8,  GOLD_MID)
        sp(a, cx + dx, y + 16, GOLD_MID)

    belt_y = y + torso_h - 5
    for dx in range(-11, 12):
        col = GOLD_LIGHT if abs(dx) < 9 else GOLD_DARK
        sp(a, cx + dx, belt_y,     col)
        sp(a, cx + dx, belt_y + 1, GOLD_DARK)
        sp(a, cx + dx, belt_y + 2, GOLD_DEEP)
    sp(a, cx - 1, belt_y,     GOLD_HILIT)
    sp(a, cx,     belt_y,     GOLD_HILIT)
    sp(a, cx + 1, belt_y,     GOLD_HILIT)
    sp(a, cx,     belt_y - 1, GOLD_LIGHT)
    sp(a, cx,     belt_y + 1, GOLD_MID)

    for dx in range(-5, 6):
        sp(a, cx + dx, y,     PINK_LIGHT)
        sp(a, cx + dx, y + 1, PINK_MID)

def draw_arms(a, cx, y_shoulder, arm_pose='idle'):
    lx = cx - 16
    rx = cx + 14
    sy = y_shoulder

    if arm_pose == 'idle':
        for dy in range(0, 22):
            arm_x = lx - dy // 5
            sp(a, arm_x - 1, sy + dy, OUTLINE)
            sp(a, arm_x,     sy + dy, ROBE_DARK)
            sp(a, arm_x + 1, sy + dy, ROBE_MID)
            sp(a, arm_x + 2, sy + dy, OUTLINE)
        for dx in range(-3, 3):
            sp(a, lx - 4 + dx, sy + 22, SKIN_MID)
        sp(a, lx - 5, sy + 22, OUTLINE)
        sp(a, lx - 6, sy + 22, SKIN_SHADOW)

        for dy in range(0, 22):
            arm_x = rx + dy // 6
            sp(a, arm_x - 1, sy + dy, OUTLINE)
            sp(a, arm_x,     sy + dy, ROBE_MID)
            sp(a, arm_x + 1, sy + dy, ROBE_LIGHT)
            sp(a, arm_x + 2, sy + dy, OUTLINE)
        sp(a, rx + 3, sy + 20, SKIN_LIGHT)
        sp(a, rx + 3, sy + 21, SKIN_MID)
        sp(a, rx + 4, sy + 21, SKIN_LIGHT)
        sp(a, rx + 4, sy + 22, SKIN_DARK)
        sp(a, rx + 3, sy + 22, OUTLINE)

    elif arm_pose in ('cast', 'pray'):
        for dy in range(0, 14):
            arm_x = lx + dy
            sp(a, arm_x - 1, sy + dy, OUTLINE)
            sp(a, arm_x,     sy + dy, ROBE_DARK)
            sp(a, arm_x + 1, sy + dy, ROBE_MID)
            sp(a, arm_x + 2, sy + dy, ROBE_LIGHT)
            sp(a, arm_x + 3, sy + dy, OUTLINE)
        for dy in range(0, 14):
            arm_x = rx - dy
            sp(a, arm_x - 2, sy + dy, OUTLINE)
            sp(a, arm_x - 1, sy + dy, ROBE_LIGHT)
            sp(a, arm_x,     sy + dy, ROBE_MID)
            sp(a, arm_x + 1, sy + dy, ROBE_DARK)
            sp(a, arm_x + 2, sy + dy, OUTLINE)
        for dx in range(-4, 5):
            for ddy in range(0, 5):
                sp(a, cx + dx, sy + 13 + ddy, SKIN_MID)
        sp(a, cx - 4, sy + 13, OUTLINE)
        sp(a, cx + 4, sy + 13, OUTLINE)
        sp(a, cx - 4, sy + 17, OUTLINE)
        sp(a, cx + 4, sy + 17, OUTLINE)
        sp(a, cx - 2, sy + 14, SKIN_LIGHT)
        sp(a, cx,     sy + 14, SKIN_LIGHT)
        sp(a, cx + 2, sy + 14, SKIN_LIGHT)

    elif arm_pose == 'attack':
        for dy in range(0, 8):
            arm_x = rx + 3 - dy // 2
            sp(a, arm_x - 1, sy - dy, OUTLINE)
            sp(a, arm_x,     sy - dy, ROBE_LIGHT)
            sp(a, arm_x + 1, sy - dy, ROBE_HILIT)
            sp(a, arm_x + 2, sy - dy, OUTLINE)
        sp(a, rx + 3, sy - 7, SKIN_LIGHT)
        sp(a, rx + 2, sy - 7, SKIN_MID)
        sp(a, rx + 2, sy - 8, SKIN_DARK)

        for dy in range(0, 18):
            arm_x = lx - 2 - dy // 5
            sp(a, arm_x - 1, sy + dy, OUTLINE)
            sp(a, arm_x,     sy + dy, ROBE_DARK)
            sp(a, arm_x + 1, sy + dy, ROBE_MID)
            sp(a, arm_x + 2, sy + dy, OUTLINE)

    elif arm_pose == 'hit':
        for dy in range(0, 14):
            arm_x = lx - 4 - dy // 3
            sp(a, arm_x - 1, sy + dy, OUTLINE)
            sp(a, arm_x,     sy + dy, ROBE_DARK)
            sp(a, arm_x + 1, sy + dy, ROBE_MID)
            sp(a, arm_x + 2, sy + dy, OUTLINE)
        for dy in range(0, 14):
            arm_x = rx + 2 - dy // 3
            sp(a, arm_x - 1, sy + dy, OUTLINE)
            sp(a, arm_x,     sy + dy, ROBE_LIGHT)
            sp(a, arm_x + 1, sy + dy, OUTLINE)

    elif arm_pose == 'defend':
        for dy in range(0, 18):
            arm_x = lx + dy // 2
            sp(a, arm_x - 1, sy + dy, OUTLINE)
            sp(a, arm_x,     sy + dy, ROBE_DARK)
            sp(a, arm_x + 1, sy + dy, ROBE_MID)
            sp(a, arm_x + 2, sy + dy, OUTLINE)
        for dy in range(0, 18):
            arm_x = rx - dy // 3
            sp(a, arm_x - 1, sy + dy, OUTLINE)
            sp(a, arm_x,     sy + dy, ROBE_LIGHT)
            sp(a, arm_x + 1, sy + dy, ROBE_HILIT)
            sp(a, arm_x + 2, sy + dy, OUTLINE)

    elif arm_pose == 'item':
        for dy in range(0, 20):
            arm_x = lx + dy
            sp(a, arm_x - 1, sy + dy, OUTLINE)
            sp(a, arm_x,     sy + dy, ROBE_DARK)
            sp(a, arm_x + 1, sy + dy, ROBE_MID)
            sp(a, arm_x + 2, sy + dy, OUTLINE)
        for dy in range(0, 16):
            arm_x = rx + 2 - dy // 3
            sp(a, arm_x - 1, sy - dy + 4, OUTLINE)
            sp(a, arm_x,     sy - dy + 4, ROBE_LIGHT)
            sp(a, arm_x + 1, sy - dy + 4, ROBE_HILIT)
            sp(a, arm_x + 2, sy - dy + 4, OUTLINE)
        sp(a, rx + 3, sy - 10, SKIN_LIGHT)
        sp(a, rx + 4, sy - 10, SKIN_LIGHT)
        sp(a, rx + 3, sy - 11, SKIN_MID)

    elif arm_pose == 'victory':
        for dy in range(0, 18):
            arm_x = lx - 4 - dy // 3
            sp(a, arm_x - 1, sy - dy, OUTLINE)
            sp(a, arm_x,     sy - dy, ROBE_LIGHT)
            sp(a, arm_x + 1, sy - dy, ROBE_HILIT)
            sp(a, arm_x + 2, sy - dy, OUTLINE)
        sp(a, lx - 9, sy - 17, SKIN_LIGHT)
        sp(a, lx - 8, sy - 17, SKIN_MID)
        sp(a, lx - 9, sy - 18, SKIN_SHADOW)

        for dy in range(0, 18):
            arm_x = rx + 4 + dy // 3
            sp(a, arm_x - 1, sy - dy, OUTLINE)
            sp(a, arm_x,     sy - dy, ROBE_LIGHT)
            sp(a, arm_x + 1, sy - dy, ROBE_HILIT)
            sp(a, arm_x + 2, sy - dy, OUTLINE)
        sp(a, rx + 9, sy - 17, SKIN_LIGHT)
        sp(a, rx + 8, sy - 17, SKIN_MID)
        sp(a, rx + 9, sy - 18, SKIN_SHADOW)

    elif arm_pose == 'raise_staff':
        # Both arms stretched up overhead, gripping staff high
        # Left arm up-left
        for dy in range(0, 22):
            arm_x = lx - 2 + dy // 4
            sp(a, arm_x - 1, sy - dy, OUTLINE)
            sp(a, arm_x,     sy - dy, ROBE_DARK)
            sp(a, arm_x + 1, sy - dy, ROBE_MID)
            sp(a, arm_x + 2, sy - dy, OUTLINE)
        sp(a, lx + 3, sy - 21, SKIN_LIGHT)
        sp(a, lx + 2, sy - 21, SKIN_MID)
        sp(a, lx + 3, sy - 22, SKIN_DARK)

        # Right arm up-right, gripping staff
        for dy in range(0, 22):
            arm_x = rx + 2 - dy // 5
            sp(a, arm_x - 1, sy - dy, OUTLINE)
            sp(a, arm_x,     sy - dy, ROBE_LIGHT)
            sp(a, arm_x + 1, sy - dy, ROBE_HILIT)
            sp(a, arm_x + 2, sy - dy, OUTLINE)
        sp(a, rx + 3, sy - 20, SKIN_LIGHT)
        sp(a, rx + 4, sy - 20, SKIN_LIGHT)
        sp(a, rx + 3, sy - 21, SKIN_MID)

    elif arm_pose == 'raise_staff_partial':
        # Arms mid-raise — between idle and raise_staff
        for dy in range(0, 16):
            arm_x = lx - 1 + dy // 6
            sp(a, arm_x - 1, sy - dy + 6, OUTLINE)
            sp(a, arm_x,     sy - dy + 6, ROBE_DARK)
            sp(a, arm_x + 1, sy - dy + 6, ROBE_MID)
            sp(a, arm_x + 2, sy - dy + 6, OUTLINE)

        for dy in range(0, 16):
            arm_x = rx + 2 - dy // 6
            sp(a, arm_x - 1, sy - dy + 6, OUTLINE)
            sp(a, arm_x,     sy - dy + 6, ROBE_LIGHT)
            sp(a, arm_x + 1, sy - dy + 6, ROBE_HILIT)
            sp(a, arm_x + 2, sy - dy + 6, OUTLINE)

    elif arm_pose == 'kneel_pray':
        # Arms bent inward, hands clasped, kneeling position
        for dy in range(0, 10):
            arm_x = lx + dy + 2
            sp(a, arm_x - 1, sy + dy + 4, OUTLINE)
            sp(a, arm_x,     sy + dy + 4, ROBE_DARK)
            sp(a, arm_x + 1, sy + dy + 4, ROBE_MID)
            sp(a, arm_x + 2, sy + dy + 4, OUTLINE)
        for dy in range(0, 10):
            arm_x = rx - dy - 2
            sp(a, arm_x - 2, sy + dy + 4, OUTLINE)
            sp(a, arm_x - 1, sy + dy + 4, ROBE_LIGHT)
            sp(a, arm_x,     sy + dy + 4, ROBE_MID)
            sp(a, arm_x + 1, sy + dy + 4, ROBE_DARK)
            sp(a, arm_x + 2, sy + dy + 4, OUTLINE)
        # Clasped hands lower on body
        for dx in range(-4, 5):
            for ddy in range(0, 5):
                sp(a, cx + dx, sy + 16 + ddy, SKIN_MID)
        sp(a, cx - 4, sy + 16, OUTLINE)
        sp(a, cx + 4, sy + 16, OUTLINE)
        sp(a, cx - 4, sy + 20, OUTLINE)
        sp(a, cx + 4, sy + 20, OUTLINE)
        sp(a, cx - 2, sy + 17, SKIN_LIGHT)
        sp(a, cx,     sy + 17, SKIN_LIGHT)
        sp(a, cx + 2, sy + 17, SKIN_LIGHT)

    elif arm_pose == 'extend_forward':
        # Right arm extended forward/right toward target, left balances
        for dy in range(0, 14):
            arm_x = lx - dy // 4
            sp(a, arm_x - 1, sy + dy, OUTLINE)
            sp(a, arm_x,     sy + dy, ROBE_DARK)
            sp(a, arm_x + 1, sy + dy, ROBE_MID)
            sp(a, arm_x + 2, sy + dy, OUTLINE)

        for dy in range(0, 8):
            arm_x = rx + dy + 4
            sp(a, arm_x - 1, sy + dy + 4, OUTLINE)
            sp(a, arm_x,     sy + dy + 4, ROBE_LIGHT)
            sp(a, arm_x + 1, sy + dy + 4, ROBE_HILIT)
            sp(a, arm_x + 2, sy + dy + 4, OUTLINE)
        sp(a, rx + 12, sy + 10, SKIN_LIGHT)
        sp(a, rx + 13, sy + 10, SKIN_LIGHT)
        sp(a, rx + 12, sy + 11, SKIN_MID)
        sp(a, rx + 13, sy + 11, SKIN_DARK)

    elif arm_pose == 'plant_staff':
        # Both hands gripping staff low, planting it dramatically
        for dy in range(0, 18):
            arm_x = lx + dy // 2 + 4
            sp(a, arm_x - 1, sy + dy, OUTLINE)
            sp(a, arm_x,     sy + dy, ROBE_DARK)
            sp(a, arm_x + 1, sy + dy, ROBE_MID)
            sp(a, arm_x + 2, sy + dy, OUTLINE)
        sp(a, lx + 12, sy + 17, SKIN_MID)
        sp(a, lx + 11, sy + 17, SKIN_LIGHT)

        for dy in range(0, 14):
            arm_x = rx - dy // 4
            sp(a, arm_x - 1, sy + dy, OUTLINE)
            sp(a, arm_x,     sy + dy, ROBE_LIGHT)
            sp(a, arm_x + 1, sy + dy, ROBE_HILIT)
            sp(a, arm_x + 2, sy + dy, OUTLINE)
        sp(a, rx + 1, sy + 13, SKIN_LIGHT)
        sp(a, rx + 2, sy + 13, SKIN_MID)

    elif arm_pose == 'kneel_one':
        # One knee down — right arm plants staff, left arm reaches forward
        # Left arm reaching
        for dy in range(0, 12):
            arm_x = lx + dy
            sp(a, arm_x - 1, sy + dy + 2, OUTLINE)
            sp(a, arm_x,     sy + dy + 2, ROBE_DARK)
            sp(a, arm_x + 1, sy + dy + 2, ROBE_MID)
            sp(a, arm_x + 2, sy + dy + 2, OUTLINE)
        sp(a, lx + 10, sy + 13, SKIN_LIGHT)
        sp(a, lx + 11, sy + 13, SKIN_MID)

        # Right arm down gripping staff
        for dy in range(0, 18):
            arm_x = rx + dy // 5
            sp(a, arm_x - 1, sy + dy, OUTLINE)
            sp(a, arm_x,     sy + dy, ROBE_LIGHT)
            sp(a, arm_x + 1, sy + dy, ROBE_HILIT)
            sp(a, arm_x + 2, sy + dy, OUTLINE)

    elif arm_pose == 'buff_trace':
        # Right arm traces protective symbol in the air (raised + forward)
        # Left arm steadies
        for dy in range(0, 14):
            arm_x = lx - dy // 5
            sp(a, arm_x - 1, sy + dy, OUTLINE)
            sp(a, arm_x,     sy + dy, ROBE_DARK)
            sp(a, arm_x + 1, sy + dy, ROBE_MID)
            sp(a, arm_x + 2, sy + dy, OUTLINE)

        for dy in range(0, 16):
            arm_x = rx + 4 - dy // 3
            sp(a, arm_x - 1, sy - dy + 8, OUTLINE)
            sp(a, arm_x,     sy - dy + 8, ROBE_LIGHT)
            sp(a, arm_x + 1, sy - dy + 8, ROBE_HILIT)
            sp(a, arm_x + 2, sy - dy + 8, OUTLINE)
        sp(a, rx + 6, sy - 6, SKIN_LIGHT)
        sp(a, rx + 5, sy - 6, SKIN_MID)
        sp(a, rx + 6, sy - 7, SKIN_DARK)


def draw_head(a, cx, y_top, blink=False, bob=0, look_up=False):
    y = y_top + bob
    for dy in range(2, 28):
        hw = min(17, 10 + dy // 3)
        for dx in range(-hw - 2, hw + 3):
            sp(a, cx + dx, y + dy, ROBE_DEEP)

    for dy in range(0, 28):
        if dy < 8:
            hw = 10 + dy
        elif dy < 16:
            hw = 18
        else:
            hw = max(8, 18 - (dy - 16) * 2)
        for dx in range(-hw, hw + 1):
            if dx == -hw or dx == hw:
                col = OUTLINE
            elif abs(dx) == hw - 1:
                col = ROBE_SHADOW
            elif abs(dx) >= hw - 4:
                col = ROBE_DARK
            elif dx < -3:
                col = ROBE_MID
            elif dx < 1:
                col = ROBE_LIGHT
            else:
                col = ROBE_HILIT
            sp(a, cx + dx, y + dy, col)

    for dx in range(-6, 7):
        sp(a, cx + dx, y,     ROBE_HILIT)
        sp(a, cx + dx, y + 1, ROBE_LIGHT)

    trim_y = y + 7
    chevron_positions = [(-10, 4), (0, 5), (10, 4)]
    for (tx, th) in chevron_positions:
        for dy2 in range(th):
            hw2 = th - 1 - dy2
            for dx2 in range(-hw2, hw2 + 1):
                if dy2 == 0:
                    col = RED_HILIT if abs(dx2) < 2 else RED_TRIM
                elif dy2 == th - 1:
                    col = RED_DARK
                else:
                    col = RED_TRIM if abs(dx2) < hw2 else RED_MID
                sp(a, cx + tx + dx2, trim_y + dy2, col)
        sp(a, cx + tx - th + 1, trim_y, OUTLINE)
        sp(a, cx + tx + th - 1, trim_y, OUTLINE)
        sp(a, cx + tx,          trim_y + th - 1, OUTLINE)

    gold_y = trim_y + 5
    for dx in range(-13, 14):
        sp(a, cx + dx, gold_y,     GOLD_MID if abs(dx) < 11 else GOLD_DARK)
        sp(a, cx + dx, gold_y + 1, GOLD_DARK)
    for tx in [-8, 0, 8]:
        sp(a, cx + tx, gold_y, GOLD_HILIT)

    face_y = y + 11
    # Shift face up slightly if looking up
    if look_up:
        face_y = y + 9

    face_cx = cx + 1

    for dy in range(0, 12):
        if dy < 3:
            hw_f = 7
        elif dy < 8:
            hw_f = 8
        else:
            hw_f = max(4, 8 - (dy - 8) * 2)
        for dx in range(-hw_f + 1, hw_f + 1):
            sp(a, face_cx + dx, face_y + dy, SKIN_MID)

    for dx in range(-2, 4):
        sp(a, face_cx + dx, face_y,     SKIN_LIGHT)
        sp(a, face_cx + dx, face_y + 1, SKIN_LIGHT)
    sp(a, face_cx - 1, face_y + 2, SKIN_LIGHT)
    sp(a, face_cx,     face_y + 2, SKIN_HILIT)
    sp(a, face_cx + 1, face_y + 2, SKIN_LIGHT)

    sp(a, face_cx - 5, face_y + 5, SKIN_LIGHT)
    sp(a, face_cx + 5, face_y + 5, SKIN_LIGHT)

    for dx in [-3, -2]:
        sp(a, face_cx + dx, face_y + 4, SKIN_DARK)
    for dx in [3, 4]:
        sp(a, face_cx + dx, face_y + 4, SKIN_DARK)

    eye_y = face_y + 5
    if look_up:
        eye_y = face_y + 4
    if blink:
        hline(a, face_cx - 4, face_cx - 1, eye_y, (85, 58, 38, 255))
        hline(a, face_cx + 2, face_cx + 5, eye_y, (85, 58, 38, 255))
    else:
        sp(a, face_cx - 3, eye_y,     (85, 58, 38, 255))
        sp(a, face_cx - 2, eye_y,     (90, 65, 42, 255))
        sp(a, face_cx - 3, eye_y - 1, SKIN_SHADOW)
        sp(a, face_cx - 2, eye_y - 1, SKIN_DARK)
        sp(a, face_cx - 3, eye_y + 1, SKIN_MID)
        sp(a, face_cx + 3, eye_y,     (85, 58, 38, 255))
        sp(a, face_cx + 4, eye_y,     (90, 65, 42, 255))
        sp(a, face_cx + 3, eye_y - 1, SKIN_SHADOW)
        sp(a, face_cx + 4, eye_y - 1, SKIN_DARK)
        sp(a, face_cx + 3, eye_y + 1, SKIN_MID)
        sp(a, face_cx - 3, eye_y - 1, SKIN_HILIT)
        sp(a, face_cx + 4, eye_y - 1, SKIN_HILIT)

    sp(a, face_cx,     face_y + 7, SKIN_DARK)
    sp(a, face_cx + 1, face_y + 7, SKIN_SHADOW)
    sp(a, face_cx + 1, face_y + 8, SKIN_DARK)

    sp(a, face_cx - 1, face_y + 9, SKIN_SHADOW)
    sp(a, face_cx,     face_y + 9, (195, 120, 112, 255))
    sp(a, face_cx + 1, face_y + 9, (195, 120, 112, 255))
    sp(a, face_cx + 2, face_y + 9, SKIN_SHADOW)
    sp(a, face_cx,     face_y + 10, SKIN_DARK)
    sp(a, face_cx + 1, face_y + 10, SKIN_DARK)

    for dy in range(1, 11):
        sp(a, face_cx - 7, face_y + dy, ROBE_DARK)
        sp(a, face_cx - 6, face_y + dy, SKIN_SHADOW)
    for dx in range(-4, 3):
        sp(a, face_cx + dx, face_y + 11, SKIN_SHADOW)
        sp(a, face_cx + dx, face_y + 12, SKIN_DARK)

    hair_y = face_y + 11
    for dx in range(-4, 6):
        sp(a, face_cx + dx, hair_y,     HAIR_MID)
    for dx in range(-3, 5):
        sp(a, face_cx + dx, hair_y + 1, HAIR_DARK)
    sp(a, face_cx - 7, face_y + 8,  HAIR_LIGHT)
    sp(a, face_cx - 7, face_y + 9,  HAIR_MID)
    sp(a, face_cx - 7, face_y + 10, HAIR_DARK)


def draw_staff(a, x_pole, y_top, y_bot, angle=0.0, glow=False):
    ox = x_pole + int(angle)
    oy = y_top

    for y in range(oy + 8, y_bot + 1):
        t = (y - oy) / max(1, y_bot - oy)
        px = x_pole + int(angle * (1 - t))
        sp(a, px - 2, y, OUTLINE)
        sp(a, px - 1, y, STAFF_DARK)
        sp(a, px,     y, STAFF_MID)
        sp(a, px + 1, y, STAFF_LIGHT)
        sp(a, px + 2, y, OUTLINE)

    ray_len = 8
    for angle_deg in range(0, 360, 45):
        rad = math.radians(angle_deg)
        for r in range(6, ray_len + 1):
            rx = ox + int(r * math.cos(rad))
            ry = oy + int(r * math.sin(rad))
            a_val = int(200 * (1 - (r - 6) / (ray_len - 5)))
            blend_sp(a, rx, ry, (ORB_MID[0], ORB_MID[1], ORB_MID[2], a_val))

    for angle_deg in [0, 90, 180, 270]:
        rad = math.radians(angle_deg)
        for r in range(5, 11):
            rx = ox + int(r * math.cos(rad))
            ry = oy + int(r * math.sin(rad))
            a_val = int(220 * (1 - (r - 5) / 6))
            blend_sp(a, rx, ry, (ORB_LIGHT[0], ORB_LIGHT[1], ORB_LIGHT[2], a_val))

    ring(a, ox, oy, 5, 1, GOLD_DARK)
    disk(a, ox, oy, 4, ORB_DARK)
    disk(a, ox, oy, 3, ORB_MID)
    disk(a, ox, oy, 2, ORB_LIGHT)
    disk(a, ox, oy, 1, ORB_HILIT)
    sp(a, ox, oy, ORB_CORE)
    sp(a, ox - 1, oy - 1, (255, 255, 255, 220))

    if glow:
        for r in range(8, 18):
            a_val = int(120 * (1 - (r - 8) / 10))
            col = (255, 240, 140, a_val)
            for angle_deg in range(0, 360, 8):
                rad = math.radians(angle_deg)
                rx = ox + int(r * math.cos(rad))
                ry = oy + int(r * math.sin(rad))
                blend_sp(a, rx, ry, col)

    sp(a, ox - 1, oy + 6, GOLD_DARK)
    sp(a, ox,     oy + 6, GOLD_MID)
    sp(a, ox + 1, oy + 6, GOLD_DARK)
    sp(a, ox - 1, oy + 7, OUTLINE)
    sp(a, ox,     oy + 7, GOLD_DEEP)
    sp(a, ox + 1, oy + 7, OUTLINE)


# ─── FULL CHARACTER COMPOSER (extended) ──────────────────────────────────────

def draw_cleric_frame(
    bob=0,
    walk_phase=0.0,
    arm_pose='idle',
    staff_angle=0.0,
    staff_raised=False,
    leaning=0,
    blink=False,
    shadow=True,
    staff_glow=False,
    look_up=False,
    kneeling=False,      # shift lower body down to simulate kneeling
    kneel_depth=0,       # 0..20 pixels, how low knees are
    extra_fx=None
):
    arr = new_frame()
    cx   = CX_BODY + leaning
    feet = FEET_Y + bob + kneel_depth // 2

    ht   = HEAD_TOP  + bob - kneel_depth // 4
    tt   = TORSO_TOP + bob - kneel_depth // 4
    lrt  = LROBE_TOP + bob + kneel_depth // 3
    lrb  = LROBE_BOT + bob + kneel_depth // 2

    staff_x = STAFF_X + leaning
    if staff_raised:
        orb_y = ht - 34
    else:
        orb_y = ht - 22

    if shadow:
        shadow_ellipse(arr, cx, feet + 2, 26, 4, 80)

    draw_staff(arr, staff_x, orb_y, feet + 4,
               angle=staff_angle, glow=staff_glow)

    draw_boots(arr, cx, feet, walk_phase=walk_phase)
    draw_lower_robe(arr, cx, lrt, lrb,
                    sway_x=int(walk_phase * 8))

    if arm_pose in ('idle', 'hit', 'victory', 'item', 'kneel_one'):
        draw_arms(arr, cx, tt, arm_pose=arm_pose)

    draw_torso(arr, cx, tt, arm_pose=arm_pose, bob=0)

    if arm_pose not in ('idle', 'hit', 'victory', 'item', 'kneel_one'):
        draw_arms(arr, cx, tt, arm_pose=arm_pose)

    draw_head(arr, cx, ht, blink=blink, bob=0, look_up=look_up)

    if extra_fx:
        extra_fx(arr)

    return Image.fromarray(arr, 'RGBA')


# ─── NEW ANIMATION GENERATORS ─────────────────────────────────────────────────

def gen_advance():
    """
    4-frame advance animation. Cleric raises staff high overhead,
    divine light intensifies progressively.
    F0: staff begins rising
    F1: golden light gathers at sun symbol
    F2: staff fully overhead + radiant halo forms
    F3: maximum divine power aura with full light rays
    """
    frames = []

    # F0: Begin raising staff, slight forward lean
    frames.append(draw_cleric_frame(
        bob=-1,
        arm_pose='raise_staff_partial',
        staff_angle=-2.0,
        staff_raised=False,
    ))

    # F1: Arms mid-raise, golden light gathering at orb
    def fx1(arr):
        ox = STAFF_X - 2
        oy = HEAD_TOP - 24
        add_glow(arr, ox, oy, 3, 14,
                 (255, 240, 130, 100), (255, 200, 40, 0), steps=8)
        disk(arr, ox, oy, 4, (255, 240, 160, 140))
        disk(arr, ox, oy, 2, (255, 248, 200, 180))
    frames.append(draw_cleric_frame(
        bob=-2,
        arm_pose='raise_staff_partial',
        staff_angle=-1.0,
        staff_raised=False,
        extra_fx=fx1,
    ))

    # F2: Staff overhead, halo ring forms
    def fx2(arr):
        cx_h = CX_BODY
        cy_h = HEAD_TOP - 10
        ox   = STAFF_X
        oy   = HEAD_TOP - 34
        # Halo ring
        for r in range(28, 22, -1):
            a_v = int(160 * (1 - (r - 22) / 6))
            for deg in range(0, 360, 5):
                rx = cx_h + int(r * math.cos(math.radians(deg)))
                ry = cy_h + int(r * math.sin(math.radians(deg)))
                blend_sp(arr, rx, ry, (255, 235, 120, a_v))
        # Orb glow
        add_glow(arr, ox, oy, 5, 22,
                 (255, 235, 110, 160), (255, 195, 30, 0), steps=6)
        add_cross_ray(arr, ox, oy, 16, (255, 248, 190, 160))
        disk(arr, ox, oy, 6, (255, 242, 160, 200))
        disk(arr, ox, oy, 4, HOLY_B)
        disk(arr, ox, oy, 2, HOLY_A)
        sp(arr, ox, oy, HOLY_PURE)
        tint_region(arr, CX_BODY - 42, HEAD_TOP - 8,
                    CX_BODY + 55, FEET_Y + 2, 14, 8, -4)
    frames.append(draw_cleric_frame(
        bob=-4,
        arm_pose='raise_staff',
        staff_angle=0.0,
        staff_raised=True,
        staff_glow=True,
        look_up=True,
        extra_fx=fx2,
    ))

    # F3: Peak divine power — blazing aura, full rays
    def fx3(arr):
        cx_h = CX_BODY
        cy_h = HEAD_TOP - 12
        ox   = STAFF_X
        oy   = HEAD_TOP - 34
        # Large outer aura
        add_glow(arr, ox, oy, 8, 40,
                 (255, 232, 90, 180), (255, 190, 20, 0), steps=4)
        # 8-direction rays
        for ang in range(0, 360, 45):
            for r in range(12, 38):
                a_v = int(160 * (1 - (r - 12) / 26))
                rx = ox + int(r * math.cos(math.radians(ang)))
                ry = oy + int(r * math.sin(math.radians(ang)))
                blend_sp(arr, rx, ry, (255, 245, 180, a_v))
        # Halo ring (brighter)
        for r in range(32, 24, -1):
            a_v = int(200 * (1 - (r - 24) / 8))
            for deg in range(0, 360, 4):
                rx = cx_h + int(r * math.cos(math.radians(deg)))
                ry = cy_h + int(r * math.sin(math.radians(deg)))
                blend_sp(arr, rx, ry, (255, 230, 100, a_v))
        # Gold sparkle dots on halo
        for deg in range(0, 360, 30):
            r = 30
            rx = cx_h + int(r * math.cos(math.radians(deg)))
            ry = cy_h + int(r * math.sin(math.radians(deg)))
            disk(arr, rx, ry, 2, (255, 225, 80, 200))
            sp(arr, rx, ry, GOLD_HILIT)
        # Core orb
        disk(arr, ox, oy, 8, (255, 240, 140, 210))
        disk(arr, ox, oy, 5, HOLY_B)
        disk(arr, ox, oy, 3, HOLY_A)
        sp(arr, ox, oy, HOLY_PURE)
        # Strong golden tint on cleric
        tint_region(arr, CX_BODY - 46, HEAD_TOP - 14,
                    CX_BODY + 58, FEET_Y + 3, 20, 12, -6)
    frames.append(draw_cleric_frame(
        bob=-5,
        arm_pose='raise_staff',
        staff_angle=0.0,
        staff_raised=True,
        staff_glow=True,
        look_up=True,
        extra_fx=fx3,
    ))

    return frames, (1024, 256)


def gen_defer():
    """
    4-frame defer animation. Cleric kneels in prayer, holy barrier forms.
    F0: beginning to kneel, head bows slightly
    F1: hands clasping around staff in prayer grip
    F2: kneeling + prayer pose + subtle golden barrier shimmer
    F3: serene prayer pose + barrier fully formed
    """
    frames = []

    # F0: Just starting to kneel — slight bob down, arms neutral
    frames.append(draw_cleric_frame(
        bob=4,
        arm_pose='idle',
        staff_angle=1.0,
        kneel_depth=0,
    ))

    # F1: Halfway kneeling, hands coming together
    frames.append(draw_cleric_frame(
        bob=6,
        arm_pose='kneel_pray',
        staff_angle=2.0,
        kneel_depth=8,
    ))

    # F2: Fully kneeling, prayer pose, subtle barrier shimmer
    def fx2(arr):
        cx_b = CX_BODY + 6
        cy_b = TORSO_TOP + 8
        # Subtle golden shimmer around body
        for r in range(36, 26, -2):
            a_v = int(60 * (1 - (r - 26) / 10))
            for deg in range(0, 360, 8):
                rx = cx_b + int(r * math.cos(math.radians(deg)))
                ry = cy_b + int(r * math.sin(math.radians(deg)))
                blend_sp(arr, rx, ry, (220, 240, 255, a_v))
        # Clasped hands glow
        add_glow(arr, cx_b, cy_b + 18, 2, 8,
                 (255, 242, 200, 80), (255, 220, 100, 0), steps=10)
    frames.append(draw_cleric_frame(
        bob=8,
        arm_pose='kneel_pray',
        staff_angle=3.0,
        kneel_depth=14,
        blink=False,
        extra_fx=fx2,
    ))

    # F3: Full prayer, barrier solidified
    def fx3(arr):
        cx_b = CX_BODY + 6
        cy_b = TORSO_TOP + 6
        # Full golden-white barrier arc (protective hemisphere)
        for r in range(44, 30, -2):
            a_v = int(110 * (1 - (r - 30) / 14))
            for deg in range(170, 370, 5):
                rx = cx_b + int(r * math.cos(math.radians(deg)))
                ry = cy_b + int(r * math.sin(math.radians(deg)))
                blend_sp(arr, rx, ry, (200, 228, 255, a_v))
        # Barrier edge sparkle points
        for deg in [185, 210, 235, 260, 285, 310, 335]:
            r = 43
            rx = cx_b + int(r * math.cos(math.radians(deg)))
            ry = cy_b + int(r * math.sin(math.radians(deg)))
            disk(arr, rx, ry, 2, (255, 235, 130, 200))
            sp(arr, rx, ry, GOLD_HILIT)
        # Inner glow from clasped hands
        add_glow(arr, cx_b, cy_b + 20, 3, 12,
                 (255, 245, 200, 120), (255, 220, 100, 0), steps=8)
        # Slight cool tint on cleric (protected)
        tint_region(arr, CX_BODY - 42, HEAD_TOP,
                    CX_BODY + 50, FEET_Y + 6, -4, 2, 12)
    frames.append(draw_cleric_frame(
        bob=8,
        arm_pose='kneel_pray',
        staff_angle=3.0,
        kneel_depth=16,
        blink=True,
        extra_fx=fx3,
    ))

    return frames, (1024, 256)


def gen_heal():
    """
    6-frame heal animation (Cure/Cura). Staff extended toward target,
    warm green-gold healing sparkles emanate, crescendo, then disperse.
    Different intensity can represent Cure vs Cura.
    """
    frames = []

    # F0: Cleric extends staff arm toward target (right), windup
    frames.append(draw_cleric_frame(
        bob=-1,
        arm_pose='idle',
        staff_angle=2.0,
    ))

    # F1: Right arm extends forward, staff tips toward target
    def fx1(arr):
        # Tiny warm sparkle begins at staff tip
        ox = STAFF_X + 6
        oy = HEAD_TOP - 25
        for ang in [0, 90, 180, 270]:
            r = 7
            rx = ox + int(r * math.cos(math.radians(ang)))
            ry = oy + int(r * math.sin(math.radians(ang)))
            blend_sp(arr, rx, ry, (180, 255, 150, 120))
    frames.append(draw_cleric_frame(
        bob=-2,
        arm_pose='extend_forward',
        staff_angle=5.0,
        extra_fx=fx1,
    ))

    # F2: Healing light starts flowing from orb
    def fx2(arr):
        ox = STAFF_X + 10
        oy = HEAD_TOP - 22
        add_glow(arr, ox, oy, 3, 16,
                 (160, 255, 140, 140), (100, 220, 80, 0), steps=7)
        # Upward-floating healing motes
        for sx, sy, a_v in [
            (ox + 8,  oy - 6,  160),
            (ox + 14, oy - 2,  130),
            (ox + 10, oy + 8,  110),
            (ox + 6,  oy - 12, 100),
        ]:
            disk(arr, sx, sy, 2, (160, 240, 130, a_v))
            sp(arr, sx, sy, (200, 255, 175, a_v))
    frames.append(draw_cleric_frame(
        bob=-2,
        arm_pose='extend_forward',
        staff_angle=5.0,
        extra_fx=fx2,
    ))

    # F3: Peak healing burst — most sparkles, warm green-gold crescendo
    def fx3(arr):
        ox = STAFF_X + 12
        oy = HEAD_TOP - 20
        # Large healing glow
        add_glow(arr, ox, oy, 6, 30,
                 (140, 250, 120, 160), (80, 200, 60, 0), steps=5)
        # Cross ray (green-gold)
        add_cross_ray(arr, ox, oy, 22, (160, 248, 140, 180))
        add_diag_rays(arr, ox, oy, 16, (180, 255, 150, 140))
        # Healing sparkle motes scattered
        mote_positions = [
            (ox + 10, oy - 10), (ox + 18, oy - 4), (ox + 22, oy + 6),
            (ox + 14, oy + 14), (ox + 6,  oy + 18), (ox - 4,  oy + 12),
            (ox + 8,  oy - 18), (ox + 26, oy - 8),
        ]
        for mx, my in mote_positions:
            disk(arr, mx, my, 3, (150, 235, 120, 180))
            sp(arr, mx, my, (200, 255, 175, 220))
            # sparkle cross
            for ang in [0, 90, 180, 270]:
                r = 5
                rx = mx + int(r * math.cos(math.radians(ang)))
                ry = my + int(r * math.sin(math.radians(ang)))
                blend_sp(arr, rx, ry, (180, 255, 155, 100))
        # Core burst
        disk(arr, ox, oy, 8, (160, 245, 130, 200))
        disk(arr, ox, oy, 5, HEAL_BRIGHT)
        disk(arr, ox, oy, 3, (220, 255, 210, 230))
        sp(arr, ox, oy, (255, 255, 255, 255))
        # Green tint on caster
        tint_region(arr, CX_BODY - 40, HEAD_TOP,
                    CX_BODY + 50, FEET_Y + 2, -8, 18, -10)
    frames.append(draw_cleric_frame(
        bob=-3,
        arm_pose='extend_forward',
        staff_angle=6.0,
        staff_glow=False,
        extra_fx=fx3,
    ))

    # F4: Sparkles disperse, outward ripple
    def fx4(arr):
        ox = STAFF_X + 14
        oy = HEAD_TOP - 18
        # Fading outer ring
        for r in range(28, 20, -2):
            a_v = int(80 * (1 - (r - 20) / 8))
            for deg in range(0, 360, 8):
                rx = ox + int(r * math.cos(math.radians(deg)))
                ry = oy + int(r * math.sin(math.radians(deg)))
                blend_sp(arr, rx, ry, (140, 225, 115, a_v))
        # Lingering motes drifting outward
        for mx, my in [(ox + 24, oy - 10), (ox + 18, oy + 20),
                       (ox - 4, oy + 16), (ox + 10, oy - 22)]:
            disk(arr, mx, my, 2, (160, 230, 130, 120))
            sp(arr, mx, my, (200, 255, 175, 160))
    frames.append(draw_cleric_frame(
        bob=-2,
        arm_pose='extend_forward',
        staff_angle=4.0,
        extra_fx=fx4,
    ))

    # F5: Return, peaceful afterglow
    def fx5(arr):
        ox = STAFF_X + 4
        oy = HEAD_TOP - 22
        add_glow(arr, ox, oy, 2, 8,
                 (160, 235, 130, 60), (120, 200, 100, 0), steps=12)
    frames.append(draw_cleric_frame(
        bob=-1,
        arm_pose='idle',
        staff_angle=1.0,
        extra_fx=fx5,
    ))

    return frames, (1536, 256)


def gen_raise():
    """
    6-frame Raise/resurrection spell. Most dramatic animation.
    F0: Cleric plants staff, determined pose
    F1: Drops to one knee in prayer
    F2: Holy light pillar begins erupting from ground
    F3: Blinding white flash, pillar at full height
    F4: Light resolves into divine cross/sun symbol in air
    F5: Symbol fades, cleric rises, peaceful afterglow
    """
    frames = []

    # F0: Plant staff — both hands grip it, drive it into ground
    def fx0(arr):
        # Dust/impact at base
        for dx in range(-8, 9):
            blend_sp(arr, STAFF_X + dx, FEET_Y + 4,
                     (180, 160, 130, max(0, 80 - abs(dx) * 8)))
    frames.append(draw_cleric_frame(
        bob=0,
        arm_pose='plant_staff',
        staff_angle=0.0,
        extra_fx=fx0,
    ))

    # F1: Drop to one knee in prayer
    frames.append(draw_cleric_frame(
        bob=5,
        arm_pose='kneel_one',
        staff_angle=0.0,
        kneel_depth=10,
        blink=True,
    ))

    # F2: Holy light pillar begins — faint column from ground up
    def fx2(arr):
        px = STAFF_X
        # Pillar from feet to top
        for py in range(20, FEET_Y + 8):
            t = (FEET_Y + 8 - py) / (FEET_Y + 8 - 20)
            a_v = int(100 * t)
            for dx in range(-6, 7):
                fa = max(0, a_v - abs(dx) * 12)
                blend_sp(arr, px + dx, py, (240, 235, 200, fa))
        # Base bloom
        add_glow(arr, px, FEET_Y + 2, 4, 18,
                 (255, 250, 220, 120), (255, 230, 140, 0), steps=7)
    frames.append(draw_cleric_frame(
        bob=5,
        arm_pose='kneel_one',
        staff_angle=0.0,
        kneel_depth=10,
        extra_fx=fx2,
    ))

    # F3: Blinding white flash — pillar at full height, overwhelming brightness
    def fx3(arr):
        px = STAFF_X
        # Bright white pillar
        for py in range(10, FEET_Y + 8):
            t = (FEET_Y + 8 - py) / (FEET_Y + 8 - 10)
            a_v = int(200 * t)
            for dx in range(-10, 11):
                fa = max(0, a_v - abs(dx) * 16)
                blend_sp(arr, px + dx, py, (255, 255, 248, fa))
        # Wide base bloom
        add_glow(arr, px, FEET_Y, 8, 36,
                 (255, 250, 230, 180), (255, 225, 120, 0), steps=5)
        # Pillar top burst
        add_glow(arr, px, 18, 6, 28,
                 (255, 255, 250, 200), (255, 240, 160, 0), steps=5)
        add_cross_ray(arr, px, 18, 30, (255, 255, 240, 200))
        add_diag_rays(arr, px, 18, 22, (255, 248, 200, 160))
        disk(arr, px, 18, 8, (255, 255, 255, 230))
        disk(arr, px, 18, 4, HOLY_PURE)
        # Flash tint entire caster bright
        tint_region(arr, CX_BODY - 50, HEAD_TOP - 15,
                    CX_BODY + 60, FEET_Y + 8, 30, 25, 15)
    frames.append(draw_cleric_frame(
        bob=5,
        arm_pose='kneel_one',
        staff_angle=0.0,
        kneel_depth=10,
        extra_fx=fx3,
    ))

    # F4: Light resolves — divine cross/sun symbol floating where target was
    def fx4(arr):
        sx = STAFF_X + 4
        sy = 32
        # Sun circle
        ring(arr, sx, sy, 18, 2, (255, 235, 120, 180))
        ring(arr, sx, sy, 16, 1, (255, 248, 190, 140))
        # Cross arms of divine cross
        for r in range(0, 22):
            a_v = max(0, int(200 * (1 - r / 22)))
            blend_sp(arr, sx + r, sy, (255, 248, 200, a_v))
            blend_sp(arr, sx - r, sy, (255, 248, 200, a_v))
            blend_sp(arr, sx, sy + r, (255, 248, 200, a_v))
            blend_sp(arr, sx, sy - r, (255, 248, 200, a_v))
        # 8-point rays
        for ang in range(0, 360, 45):
            for r in range(20, 32):
                a_v = int(140 * (1 - (r - 20) / 12))
                rx = sx + int(r * math.cos(math.radians(ang)))
                ry = sy + int(r * math.sin(math.radians(ang)))
                blend_sp(arr, rx, ry, (255, 240, 160, a_v))
        # Central orb
        disk(arr, sx, sy, 8, (255, 240, 160, 220))
        disk(arr, sx, sy, 5, HOLY_B)
        disk(arr, sx, sy, 3, HOLY_A)
        disk(arr, sx, sy, 1, HOLY_PURE)
        # Lingering pillar base
        for py in range(FEET_Y - 20, FEET_Y + 8):
            t = (FEET_Y + 8 - py) / 28
            a_v = int(60 * t)
            for dx in range(-4, 5):
                fa = max(0, a_v - abs(dx) * 10)
                blend_sp(arr, STAFF_X + dx, py, (255, 255, 240, fa))
    frames.append(draw_cleric_frame(
        bob=5,
        arm_pose='kneel_one',
        staff_angle=0.0,
        kneel_depth=10,
        look_up=True,
        extra_fx=fx4,
    ))

    # F5: Symbol fades, cleric begins to rise, peaceful warm glow
    def fx5(arr):
        sx = STAFF_X + 4
        sy = 32
        # Fading symbol
        ring(arr, sx, sy, 18, 1, (255, 235, 120, 80))
        for ang in range(0, 360, 45):
            for r in range(20, 28):
                a_v = int(60 * (1 - (r - 20) / 8))
                rx = sx + int(r * math.cos(math.radians(ang)))
                ry = sy + int(r * math.sin(math.radians(ang)))
                blend_sp(arr, rx, ry, (255, 238, 155, a_v))
        disk(arr, sx, sy, 5, (255, 238, 160, 100))
        disk(arr, sx, sy, 3, (255, 248, 210, 80))
        # Gentle afterglow
        add_glow(arr, STAFF_X, HEAD_TOP - 14, 2, 12,
                 (255, 245, 200, 60), (255, 228, 130, 0), steps=12)
    frames.append(draw_cleric_frame(
        bob=2,
        arm_pose='idle',
        staff_angle=1.0,
        kneel_depth=0,
        look_up=True,
        extra_fx=fx5,
    ))

    return frames, (1536, 256)


def gen_buff():
    """
    4-frame buff animation (Protect/Shell). Cleric traces protective symbol,
    barrier forms and solidifies.
    F0: Right arm raised, beginning to trace in air
    F1: Geometric protective pattern being drawn (partial)
    F2: Barrier shield shimmers and solidifies
    F3: Barrier briefly maintained, then fades
    """
    frames = []

    # F0: Arm raised, beginning to trace
    frames.append(draw_cleric_frame(
        bob=-1,
        arm_pose='buff_trace',
        staff_angle=1.0,
    ))

    # F1: Tracing — geometric pattern mid-draw
    def fx1(arr):
        tx = CX_BODY + 30
        ty = HEAD_TOP + 8
        # Partial hexagonal trace pattern
        hex_pts = []
        for i in range(6):
            ang = math.radians(i * 60 - 30)
            hx = tx + int(18 * math.cos(ang))
            hy = ty + int(18 * math.sin(ang))
            hex_pts.append((hx, hy))
        # Draw partial hex (first 4 sides of 6)
        for i in range(4):
            x0, y0 = hex_pts[i]
            x1, y1 = hex_pts[(i+1) % 6]
            steps = max(abs(x1-x0), abs(y1-y0), 1)
            for s in range(steps + 1):
                t = s / steps
                px = int(x0 + t * (x1 - x0))
                py = int(y0 + t * (y1 - y0))
                blend_sp(arr, px, py, (200, 230, 255, 200))
                blend_sp(arr, px+1, py, (200, 230, 255, 100))
        # Faint gold sparkle at fingertip
        sp(arr, CX_BODY + 38, HEAD_TOP + 4, GOLD_HILIT)
        disk(arr, CX_BODY + 38, HEAD_TOP + 4, 2, (255, 230, 130, 160))
    frames.append(draw_cleric_frame(
        bob=-2,
        arm_pose='buff_trace',
        staff_angle=0.5,
        extra_fx=fx1,
    ))

    # F2: Full protective symbol complete — barrier solidifies
    def fx2(arr):
        tx = CX_BODY + 28
        ty = HEAD_TOP + 10
        # Full hexagonal barrier
        hex_pts = []
        for i in range(6):
            ang = math.radians(i * 60 - 30)
            hx = tx + int(22 * math.cos(ang))
            hy = ty + int(22 * math.sin(ang))
            hex_pts.append((hx, hy))
        for i in range(6):
            x0, y0 = hex_pts[i]
            x1, y1 = hex_pts[(i+1) % 6]
            steps = max(abs(x1-x0), abs(y1-y0), 1)
            for s in range(steps + 1):
                t = s / steps
                px = int(x0 + t * (x1 - x0))
                py = int(y0 + t * (y1 - y0))
                sp(arr, px, py, (215, 238, 255, 230))
                sp(arr, px+1, py, (180, 220, 255, 150))
                sp(arr, px, py+1, (180, 220, 255, 150))
        # Interior fill shimmer
        for r in range(20, 12, -2):
            a_v = int(60 * (1 - (r - 12) / 8))
            for deg in range(0, 360, 8):
                rx = tx + int(r * math.cos(math.radians(deg)))
                ry = ty + int(r * math.sin(math.radians(deg)))
                blend_sp(arr, rx, ry, (190, 225, 255, a_v))
        # Gold corner sparkles at vertices
        for hx, hy in hex_pts:
            disk(arr, hx, hy, 2, (255, 228, 100, 200))
            sp(arr, hx, hy, GOLD_HILIT)
        # Interior cross pattern
        hline(arr, tx - 14, tx + 14, ty, (200, 235, 255, 100))
        for ang2 in [60, 120]:
            rad2 = math.radians(ang2)
            for r in range(-14, 15):
                rx = tx + int(r * math.cos(rad2))
                ry = ty + int(r * math.sin(rad2))
                blend_sp(arr, rx, ry, (200, 235, 255, 80))
        # Orb glow on staff boosted
        add_glow(arr, STAFF_X, HEAD_TOP - 22, 4, 16,
                 (220, 235, 255, 120), (180, 215, 255, 0), steps=7)
    frames.append(draw_cleric_frame(
        bob=-2,
        arm_pose='buff_trace',
        staff_angle=0.0,
        staff_glow=True,
        extra_fx=fx2,
    ))

    # F3: Barrier fades — brief afterimage, cleric lowers arm
    def fx3(arr):
        tx = CX_BODY + 28
        ty = HEAD_TOP + 10
        # Fading hex outline
        hex_pts = []
        for i in range(6):
            ang = math.radians(i * 60 - 30)
            hx = tx + int(22 * math.cos(ang))
            hy = ty + int(22 * math.sin(ang))
            hex_pts.append((hx, hy))
        for i in range(6):
            x0, y0 = hex_pts[i]
            x1, y1 = hex_pts[(i+1) % 6]
            steps = max(abs(x1-x0), abs(y1-y0), 1)
            for s in range(steps + 1):
                t = s / steps
                px = int(x0 + t * (x1 - x0))
                py = int(y0 + t * (y1 - y0))
                blend_sp(arr, px, py, (200, 228, 255, 100))
        # Scatter sparkles (dissipating)
        for sx, sy in [(tx + 20, ty - 12), (tx - 18, ty + 8),
                       (tx + 8, ty + 22), (tx - 10, ty - 18),
                       (tx + 22, ty + 10)]:
            disk(arr, sx, sy, 2, (200, 228, 255, 140))
            sp(arr, sx, sy, (230, 248, 255, 200))
        add_glow(arr, STAFF_X, HEAD_TOP - 22, 2, 10,
                 (210, 232, 255, 70), (180, 215, 255, 0), steps=10)
    frames.append(draw_cleric_frame(
        bob=-1,
        arm_pose='idle',
        staff_angle=0.5,
        extra_fx=fx3,
    ))

    return frames, (1024, 256)


# ─── STRIP ASSEMBLER AND MAIN ─────────────────────────────────────────────────

def save_strip(frames, strip_size, path):
    strip = Image.new("RGBA", strip_size, (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * 256, 0))
    strip.save(path)
    size_kb = os.path.getsize(path) // 1024
    print(f"  Saved: {path}  ({strip_size[0]}x{strip_size[1]}, "
          f"{len(frames)} frames, {size_kb}KB)")


def main():
    print("Generating Cleric EXTENDED sprites for Cowardly Irregular...")
    print(f"Output: {OUT_DIR}")
    print(f"Character: cx={CX_BODY}, feet_y={FEET_Y}, head_top={HEAD_TOP}")
    print(f"Tier: T1 (AI-generated procedural)\n")

    animations = [
        ("advance", gen_advance, "4-frame: raise staff, divine power aura"),
        ("defer",   gen_defer,   "4-frame: kneel in prayer, holy barrier"),
        ("heal",    gen_heal,    "6-frame: Cure/Cura healing spell"),
        ("raise",   gen_raise,   "6-frame: Resurrection, holy light pillar"),
        ("buff",    gen_buff,    "4-frame: Protect/Shell, geometric barrier"),
    ]

    for name, fn, desc in animations:
        print(f"  {name}: {desc}")
        frames, strip_size = fn()
        out_path = os.path.join(OUT_DIR, f"{name}.png")
        save_strip(frames, strip_size, out_path)

    print("\nDone. All 5 extended animations generated.")
    print("Register in data/sprite_manifest.json under party_sheets.cleric")
    print("tier: T1 (AI-generated, pending artist review)")


if __name__ == "__main__":
    main()
