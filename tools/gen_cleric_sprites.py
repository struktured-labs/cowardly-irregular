#!/usr/bin/env python3
"""
Cleric sprite generator for Cowardly Irregular.
Generates all 9 animation strips in 256x256 frame format (SNES-style pixel art).

Target size: character ~70px wide, ~95px tall, positioned center-bottom within 256x256.
Matches fighter sprite scale (fighter = 106px wide including sword, body ~60px wide).

Cleric design: White Mage inspired - white/cream hooded robe, red triangular trim,
gold accents, healing staff with sun symbol, soft features.
"""

from PIL import Image
import numpy as np
import math
import os

OUT_DIR = "/home/struktured/projects/cowardly-irregular/assets/sprites/jobs/cleric"
os.makedirs(OUT_DIR, exist_ok=True)

# ─── PALETTE ────────────────────────────────────────────────────────────────
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

# Robe whites/creams
ROBE_HILIT   = (255, 252, 246, 255)
ROBE_LIGHT   = (242, 238, 224, 255)
ROBE_MID     = (220, 214, 196, 255)
ROBE_DARK    = (190, 182, 160, 255)
ROBE_SHADOW  = (155, 146, 124, 255)
ROBE_DEEP    = (118, 110,  90, 255)

# Red trim (classic White Mage triangular hood chevrons)
RED_HILIT    = (240,  80,  80, 255)
RED_TRIM     = (204,  28,  44, 255)
RED_MID      = (168,  18,  32, 255)
RED_DARK     = (120,  10,  20, 255)

# Gold accents
GOLD_HILIT   = (255, 228,  90, 255)
GOLD_LIGHT   = (235, 195,  55, 255)
GOLD_MID     = (205, 160,  28, 255)
GOLD_DARK    = (155, 112,  10, 255)
GOLD_DEEP    = (105,  72,   5, 255)

# Pink inner lining
PINK_HILIT   = (255, 200, 205, 255)
PINK_LIGHT   = (238, 175, 180, 255)
PINK_MID     = (210, 142, 148, 255)
PINK_DARK    = (168, 102, 108, 255)

# Staff (wood)
STAFF_HILIT  = (215, 175, 118, 255)
STAFF_LIGHT  = (192, 152,  90, 255)
STAFF_MID    = (155, 118,  65, 255)
STAFF_DARK   = (115,  82,  40, 255)
STAFF_DEEP   = ( 78,  52,  22, 255)

# Staff orb / sun symbol
ORB_HILIT    = (255, 252, 210, 255)
ORB_LIGHT    = (252, 240, 145, 255)
ORB_MID      = (225, 195,  62, 255)
ORB_DARK     = (168, 135,  18, 255)
ORB_CORE     = (255, 255, 240, 255)

# Boot / sandal
BOOT_HILIT   = (218, 195, 155, 255)
BOOT_LIGHT   = (195, 168, 125, 255)
BOOT_MID     = (162, 132,  92, 255)
BOOT_DARK    = (120,  95,  62, 255)
BOOT_DEEP    = ( 82,  60,  35, 255)

# Fx / holy light
HOLY_PURE    = (255, 255, 255, 255)
HOLY_A       = (255, 252, 220, 240)
HOLY_B       = (255, 238, 160, 200)
HOLY_C       = (255, 215,  90, 140)
HOLY_D       = (240, 175,  40,  80)

TRANS = (0, 0, 0, 0)

# ─── PIXEL PRIMITIVES ───────────────────────────────────────────────────────

def new_frame():
    return np.zeros((256, 256, 4), dtype=np.uint8)

def sp(a, x, y, c):
    if 0 <= x < 256 and 0 <= y < 256:
        a[y, x] = c

def blend_sp(a, x, y, c):
    """Blend color c over existing pixel."""
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
    """Tint all opaque pixels in region."""
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

# ─── CHARACTER COMPONENTS ───────────────────────────────────────────────────
# Character center: cx=128, feet at y=200
# Full height: ~95px (y 105..200)
# Body width: ~60px (x 98..158)

def draw_shadow(a, cx, y_feet):
    shadow_ellipse(a, cx, y_feet+1, 28, 5, 90)

def draw_boots(a, cx, y_feet, walk_phase=0.0):
    """Sandal/boot feet visible below robe hem."""
    # walk_phase: -1..1 shifts feet
    phase = walk_phase
    lx = cx - 12 + int(phase * 6)
    rx = cx + 8  - int(phase * 6)
    y  = y_feet

    # Left boot
    for dx in range(-6, 4):
        sp(a, lx+dx, y,   BOOT_MID   if abs(dx) < 5 else OUTLINE)
        sp(a, lx+dx, y-1, BOOT_LIGHT if abs(dx) < 5 else OUTLINE)
    sp(a, lx-6, y,   OUTLINE)
    sp(a, lx+3,  y,   OUTLINE)
    sp(a, lx-5, y-1, BOOT_HILIT)
    sp(a, lx-4, y-1, BOOT_HILIT)
    # Strap detail
    sp(a, lx-2, y-2, BOOT_DARK)
    sp(a, lx-1, y-2, BOOT_DARK)
    sp(a, lx,   y-2, BOOT_DARK)
    # Toe shadow
    for dx in range(-5, 3):
        sp(a, lx+dx, y+1, OUTLINE)

    # Right boot (front - slightly brighter)
    for dx in range(-4, 7):
        sp(a, rx+dx, y,   BOOT_LIGHT  if abs(dx-1) < 5 else OUTLINE)
        sp(a, rx+dx, y-1, BOOT_HILIT  if abs(dx-1) < 4 else BOOT_LIGHT)
    sp(a, rx-4, y,   OUTLINE)
    sp(a, rx+6,  y,   OUTLINE)
    sp(a, rx+3, y-1, BOOT_HILIT)
    sp(a, rx+4, y-1, BOOT_HILIT)
    # Strap
    sp(a, rx+1, y-2, BOOT_DARK)
    sp(a, rx+2, y-2, BOOT_DARK)
    sp(a, rx+3, y-2, BOOT_DARK)
    # Toe shadow
    for dx in range(-3, 6):
        sp(a, rx+dx, y+1, OUTLINE)


def draw_lower_robe(a, cx, y_top, y_bot, sway_x=0):
    """Flowing lower robe from waist down to hem."""
    # Robe broadens from waist (~28px wide) to hem (~52px wide)
    robe_height = y_bot - y_top
    for dy in range(robe_height + 1):
        t = dy / max(1, robe_height)
        half_w = int(14 + t * 12)  # 14 to 26 px
        sw = int(sway_x * t * 0.5) # sway increases toward hem
        for dx in range(-half_w, half_w+1):
            rx = cx + dx + sw
            # Color shading: left side shadow, right side highlight, center fold
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

    # Pink inner lining at hem bottom (3 rows)
    for dx in range(-12, 13):
        rx = cx + dx + int(sway_x * 0.5)
        sp(a, rx, y_bot - 2, PINK_MID)
        sp(a, rx, y_bot - 1, PINK_LIGHT)
        sp(a, rx, y_bot,     PINK_HILIT)
    for dx in range(-11, 12):
        rx = cx + dx + int(sway_x * 0.5)
        sp(a, rx, y_bot + 1, OUTLINE)

    # Robe fold/crease detail
    fold_x = cx + 3 + int(sway_x * 0.3)
    for dy in range(4, robe_height - 4):
        sp(a, fold_x, y_top + dy, ROBE_DARK)
    fold_x2 = cx - 6 + int(sway_x * 0.2)
    for dy in range(6, robe_height - 6):
        sp(a, fold_x2, y_top + dy, ROBE_SHADOW)


def draw_torso(a, cx, y_top, arm_pose='idle', bob=0):
    """Upper body robe torso, ~28px wide, ~32px tall."""
    y = y_top
    torso_h = 32

    for dy in range(torso_h):
        t = dy / torso_h
        half_w = int(13 + t * 3)  # slight flare
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

    # Center seam
    for dy in range(2, torso_h - 2):
        sp(a, cx, y + dy, ROBE_DARK)
        sp(a, cx + 1, y + dy, ROBE_MID)

    # Gold embroidery lines (2 rows)
    for dx in range(-8, 9):
        sp(a, cx + dx, y + 8,  GOLD_DARK)
        sp(a, cx + dx, y + 16, GOLD_DARK)
    # Gold dots
    for dx in range(-7, 8, 3):
        sp(a, cx + dx, y + 8,  GOLD_MID)
        sp(a, cx + dx, y + 16, GOLD_MID)

    # Gold belt at bottom of torso
    belt_y = y + torso_h - 5
    for dx in range(-11, 12):
        col = GOLD_LIGHT if abs(dx) < 9 else GOLD_DARK
        sp(a, cx + dx, belt_y,     col)
        sp(a, cx + dx, belt_y + 1, GOLD_DARK)
        sp(a, cx + dx, belt_y + 2, GOLD_DEEP)
    # Belt buckle / sun clasp
    sp(a, cx - 1, belt_y,     GOLD_HILIT)
    sp(a, cx,     belt_y,     GOLD_HILIT)
    sp(a, cx + 1, belt_y,     GOLD_HILIT)
    sp(a, cx,     belt_y - 1, GOLD_LIGHT)
    sp(a, cx,     belt_y + 1, GOLD_MID)

    # Pink inner collar visible at top
    for dx in range(-5, 6):
        sp(a, cx + dx, y,     PINK_LIGHT)
        sp(a, cx + dx, y + 1, PINK_MID)


def draw_arms(a, cx, y_shoulder, arm_pose='idle'):
    """Draw arms in various poses. Staff held in right hand."""
    lx = cx - 16   # left shoulder x
    rx = cx + 14   # right shoulder x
    sy = y_shoulder

    if arm_pose == 'idle':
        # Left arm: relaxed, hanging with slight bend
        for dy in range(0, 22):
            arm_x = lx - dy // 5
            sp(a, arm_x - 1, sy + dy, OUTLINE)
            sp(a, arm_x,     sy + dy, ROBE_DARK)
            sp(a, arm_x + 1, sy + dy, ROBE_MID)
            sp(a, arm_x + 2, sy + dy, OUTLINE)
        # Left hand
        for dx in range(-3, 3):
            sp(a, lx - 4 + dx, sy + 22, SKIN_MID)
        sp(a, lx - 5, sy + 22, OUTLINE)
        sp(a, lx - 6, sy + 22, SKIN_SHADOW)

        # Right arm: holding staff, arm down
        for dy in range(0, 22):
            arm_x = rx + dy // 6
            sp(a, arm_x - 1, sy + dy, OUTLINE)
            sp(a, arm_x,     sy + dy, ROBE_MID)
            sp(a, arm_x + 1, sy + dy, ROBE_LIGHT)
            sp(a, arm_x + 2, sy + dy, OUTLINE)
        # Right hand gripping staff
        sp(a, rx + 3, sy + 20, SKIN_LIGHT)
        sp(a, rx + 3, sy + 21, SKIN_MID)
        sp(a, rx + 4, sy + 21, SKIN_LIGHT)
        sp(a, rx + 4, sy + 22, SKIN_DARK)
        sp(a, rx + 3, sy + 22, OUTLINE)

    elif arm_pose == 'cast' or arm_pose == 'pray':
        # Both arms raised forward, hands clasped at chest
        # Left arm across body
        for dy in range(0, 14):
            arm_x = lx + dy
            sp(a, arm_x - 1, sy + dy, OUTLINE)
            sp(a, arm_x,     sy + dy, ROBE_DARK)
            sp(a, arm_x + 1, sy + dy, ROBE_MID)
            sp(a, arm_x + 2, sy + dy, ROBE_LIGHT)
            sp(a, arm_x + 3, sy + dy, OUTLINE)
        # Right arm across body (mirrored)
        for dy in range(0, 14):
            arm_x = rx - dy
            sp(a, arm_x - 2, sy + dy, OUTLINE)
            sp(a, arm_x - 1, sy + dy, ROBE_LIGHT)
            sp(a, arm_x,     sy + dy, ROBE_MID)
            sp(a, arm_x + 1, sy + dy, ROBE_DARK)
            sp(a, arm_x + 2, sy + dy, OUTLINE)
        # Clasped hands center
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
        # Right arm swings up/forward with staff
        for dy in range(0, 8):
            arm_x = rx + 3 - dy // 2
            sp(a, arm_x - 1, sy - dy, OUTLINE)
            sp(a, arm_x,     sy - dy, ROBE_LIGHT)
            sp(a, arm_x + 1, sy - dy, ROBE_HILIT)
            sp(a, arm_x + 2, sy - dy, OUTLINE)
        sp(a, rx + 3, sy - 7, SKIN_LIGHT)
        sp(a, rx + 2, sy - 7, SKIN_MID)
        sp(a, rx + 2, sy - 8, SKIN_DARK)

        # Left arm counterbalances back
        for dy in range(0, 18):
            arm_x = lx - 2 - dy // 5
            sp(a, arm_x - 1, sy + dy, OUTLINE)
            sp(a, arm_x,     sy + dy, ROBE_DARK)
            sp(a, arm_x + 1, sy + dy, ROBE_MID)
            sp(a, arm_x + 2, sy + dy, OUTLINE)

    elif arm_pose == 'hit':
        # Arms thrown back/out in recoil
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
        # Both hands raise staff up defensively
        # Left hand grips low
        for dy in range(0, 18):
            arm_x = lx + dy // 2
            sp(a, arm_x - 1, sy + dy, OUTLINE)
            sp(a, arm_x,     sy + dy, ROBE_DARK)
            sp(a, arm_x + 1, sy + dy, ROBE_MID)
            sp(a, arm_x + 2, sy + dy, OUTLINE)
        # Right hand grips high
        for dy in range(0, 18):
            arm_x = rx - dy // 3
            sp(a, arm_x - 1, sy + dy, OUTLINE)
            sp(a, arm_x,     sy + dy, ROBE_LIGHT)
            sp(a, arm_x + 1, sy + dy, ROBE_HILIT)
            sp(a, arm_x + 2, sy + dy, OUTLINE)

    elif arm_pose == 'item':
        # Left arm reaches across to belt pouch
        for dy in range(0, 20):
            arm_x = lx + dy
            sp(a, arm_x - 1, sy + dy, OUTLINE)
            sp(a, arm_x,     sy + dy, ROBE_DARK)
            sp(a, arm_x + 1, sy + dy, ROBE_MID)
            sp(a, arm_x + 2, sy + dy, OUTLINE)
        # Right arm raised holding item
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
        # Both arms raised high in celebration
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


def draw_head(a, cx, y_top, blink=False, bob=0):
    """
    Draw hooded head: white hood with red triangular trim chevrons,
    face visible below brow, brown hair peeking.
    """
    y = y_top + bob
    # Hood is ~32px wide at widest, ~30px tall

    # Hood back/cape shadow (behind face)
    for dy in range(2, 28):
        hw = min(17, 10 + dy // 3)
        for dx in range(-hw - 2, hw + 3):
            sp(a, cx + dx, y + dy, ROBE_DEEP)

    # Hood main body
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

    # Hood top highlight
    for dx in range(-6, 7):
        sp(a, cx + dx, y,     ROBE_HILIT)
        sp(a, cx + dx, y + 1, ROBE_LIGHT)

    # ─── Red triangular trim chevrons (classic White Mage) ───
    # Three chevron triangles across hood brow at dy=7
    trim_y = y + 7
    chevron_positions = [(-10, 4), (0, 5), (10, 4)]  # (center_x_offset, height)
    for (tx, th) in chevron_positions:
        # Draw filled downward-pointing triangle
        for dy2 in range(th):
            hw2 = th - 1 - dy2  # wider at top, point at bottom
            for dx2 in range(-hw2, hw2 + 1):
                if dy2 == 0:
                    col = RED_HILIT if abs(dx2) < 2 else RED_TRIM
                elif dy2 == th - 1:
                    col = RED_DARK
                else:
                    col = RED_TRIM if abs(dx2) < hw2 else RED_MID
                sp(a, cx + tx + dx2, trim_y + dy2, col)
        # Outline
        sp(a, cx + tx - th + 1, trim_y, OUTLINE)
        sp(a, cx + tx + th - 1, trim_y, OUTLINE)
        sp(a, cx + tx,          trim_y + th - 1, OUTLINE)

    # Gold band below red trim
    gold_y = trim_y + 5
    for dx in range(-13, 14):
        sp(a, cx + dx, gold_y,     GOLD_MID if abs(dx) < 11 else GOLD_DARK)
        sp(a, cx + dx, gold_y + 1, GOLD_DARK)
    # Gold dot accents
    for tx in [-8, 0, 8]:
        sp(a, cx + tx, gold_y, GOLD_HILIT)

    # ─── Face area ─────────────────────────────────────────────
    face_y = y + 11
    face_cx = cx + 1  # very slightly right (facing right)

    # Face skin base
    for dy in range(0, 12):
        if dy < 3:
            hw_f = 7
        elif dy < 8:
            hw_f = 8
        else:
            hw_f = max(4, 8 - (dy - 8) * 2)
        for dx in range(-hw_f + 1, hw_f + 1):
            col = SKIN_MID
            sp(a, face_cx + dx, face_y + dy, col)

    # Face highlights (forehead, cheeks)
    for dx in range(-2, 4):
        sp(a, face_cx + dx, face_y,     SKIN_LIGHT)
        sp(a, face_cx + dx, face_y + 1, SKIN_LIGHT)
    sp(a, face_cx - 1, face_y + 2, SKIN_LIGHT)
    sp(a, face_cx,     face_y + 2, SKIN_HILIT)
    sp(a, face_cx + 1, face_y + 2, SKIN_LIGHT)

    # Cheek highlights
    sp(a, face_cx - 5, face_y + 5, SKIN_LIGHT)
    sp(a, face_cx + 5, face_y + 5, SKIN_LIGHT)

    # Eye shadows / upper brow
    for dx in [-3, -2]:
        sp(a, face_cx + dx, face_y + 4, SKIN_DARK)
    for dx in [3, 4]:
        sp(a, face_cx + dx, face_y + 4, SKIN_DARK)

    # Eyes (warm brown, gentle)
    eye_y = face_y + 5
    if blink:
        # Eyes closed - lines
        hline(a, face_cx - 4, face_cx - 1, eye_y, (85, 58, 38, 255))
        hline(a, face_cx + 2, face_cx + 5, eye_y, (85, 58, 38, 255))
    else:
        # Left eye
        sp(a, face_cx - 3, eye_y,     (85, 58, 38, 255))
        sp(a, face_cx - 2, eye_y,     (90, 65, 42, 255))
        sp(a, face_cx - 3, eye_y - 1, SKIN_SHADOW)  # brow
        sp(a, face_cx - 2, eye_y - 1, SKIN_DARK)
        sp(a, face_cx - 3, eye_y + 1, SKIN_MID)     # lower lid
        # Right eye
        sp(a, face_cx + 3, eye_y,     (85, 58, 38, 255))
        sp(a, face_cx + 4, eye_y,     (90, 65, 42, 255))
        sp(a, face_cx + 3, eye_y - 1, SKIN_SHADOW)
        sp(a, face_cx + 4, eye_y - 1, SKIN_DARK)
        sp(a, face_cx + 3, eye_y + 1, SKIN_MID)
        # Eye highlights (sparkle)
        sp(a, face_cx - 3, eye_y - 1, SKIN_HILIT)
        sp(a, face_cx + 4, eye_y - 1, SKIN_HILIT)

    # Nose (gentle bump)
    sp(a, face_cx,     face_y + 7, SKIN_DARK)
    sp(a, face_cx + 1, face_y + 7, SKIN_SHADOW)
    sp(a, face_cx + 1, face_y + 8, SKIN_DARK)

    # Mouth (slight peaceful smile)
    sp(a, face_cx - 1, face_y + 9, SKIN_SHADOW)
    sp(a, face_cx,     face_y + 9, (195, 120, 112, 255))  # lip color
    sp(a, face_cx + 1, face_y + 9, (195, 120, 112, 255))
    sp(a, face_cx + 2, face_y + 9, SKIN_SHADOW)
    sp(a, face_cx,     face_y + 10, SKIN_DARK)
    sp(a, face_cx + 1, face_y + 10, SKIN_DARK)

    # Face shadow (left side and chin)
    for dy in range(1, 11):
        sp(a, face_cx - 7, face_y + dy, ROBE_DARK)
        sp(a, face_cx - 6, face_y + dy, SKIN_SHADOW)
    for dx in range(-4, 3):
        sp(a, face_cx + dx, face_y + 11, SKIN_SHADOW)
        sp(a, face_cx + dx, face_y + 12, SKIN_DARK)

    # ─── Hair peeking from hood ────────────────────────────────
    hair_y = face_y + 11
    for dx in range(-4, 6):
        sp(a, face_cx + dx, hair_y,     HAIR_MID)
    for dx in range(-3, 5):
        sp(a, face_cx + dx, hair_y + 1, HAIR_DARK)
    # Sides of hood with hair color
    sp(a, face_cx - 7, face_y + 8,  HAIR_LIGHT)
    sp(a, face_cx - 7, face_y + 9,  HAIR_MID)
    sp(a, face_cx - 7, face_y + 10, HAIR_DARK)


def draw_staff(a, x_pole, y_top, y_bot, angle=0.0, glow=False):
    """
    Draw staff pole + sun/star orb at top.
    x_pole: x center of staff at grip level
    y_top: y of orb center
    y_bot: y of staff butt
    angle: lean in pixels (orb offset from x_pole at y_top)
    """
    # Calculate orb position
    ox = x_pole + int(angle)
    oy = y_top

    # Staff pole (4px wide with shading)
    for y in range(oy + 8, y_bot + 1):
        # Interpolate x position from orb to butt
        t = (y - oy) / max(1, y_bot - oy)
        px = x_pole + int(angle * (1 - t))
        sp(a, px - 2, y, OUTLINE)
        sp(a, px - 1, y, STAFF_DARK)
        sp(a, px,     y, STAFF_MID)
        sp(a, px + 1, y, STAFF_LIGHT)
        sp(a, px + 2, y, OUTLINE)

    # ─── Sun / Star orb ────────────────────────────────────────
    # Outer rays (8-pointed star)
    ray_len = 8
    for angle_deg in range(0, 360, 45):
        rad = math.radians(angle_deg)
        for r in range(6, ray_len + 1):
            rx = ox + int(r * math.cos(rad))
            ry = oy + int(r * math.sin(rad))
            a_val = int(200 * (1 - (r - 6) / (ray_len - 5)))
            blend_sp(a, rx, ry, (ORB_MID[0], ORB_MID[1], ORB_MID[2], a_val))

    # Cardinal rays (longer)
    for angle_deg in [0, 90, 180, 270]:
        rad = math.radians(angle_deg)
        for r in range(5, 11):
            rx = ox + int(r * math.cos(rad))
            ry = oy + int(r * math.sin(rad))
            a_val = int(220 * (1 - (r - 5) / 6))
            blend_sp(a, rx, ry, (ORB_LIGHT[0], ORB_LIGHT[1], ORB_LIGHT[2], a_val))

    # Orb outer ring
    ring(a, ox, oy, 5, 1, GOLD_DARK)
    # Orb body
    disk(a, ox, oy, 4, ORB_DARK)
    disk(a, ox, oy, 3, ORB_MID)
    disk(a, ox, oy, 2, ORB_LIGHT)
    disk(a, ox, oy, 1, ORB_HILIT)
    sp(a, ox, oy, ORB_CORE)

    # Shine dot
    sp(a, ox - 1, oy - 1, (255, 255, 255, 220))

    if glow:
        # Glow halo around orb
        for r in range(8, 18):
            a_val = int(120 * (1 - (r - 8) / 10))
            col = (255, 240, 140, a_val)
            for angle_deg in range(0, 360, 8):
                rad = math.radians(angle_deg)
                rx = ox + int(r * math.cos(rad))
                ry = oy + int(r * math.sin(rad))
                blend_sp(a, rx, ry, col)

    # Junction between orb and staff
    sp(a, ox - 1, oy + 6, GOLD_DARK)
    sp(a, ox,     oy + 6, GOLD_MID)
    sp(a, ox + 1, oy + 6, GOLD_DARK)
    sp(a, ox - 1, oy + 7, OUTLINE)
    sp(a, ox,     oy + 7, GOLD_DEEP)
    sp(a, ox + 1, oy + 7, OUTLINE)


# ─── FULL CHARACTER COMPOSER ─────────────────────────────────────────────────
# Target: character body from y=105 (hood top) to y=200 (feet)
# cx=128, staff at cx+18

CX_BODY   = 122   # body center x
FEET_Y    = 163   # foot bottom y — matches fighter's feet baseline (y=163)
HEAD_H    = 30    # head height
TORSO_H   = 32    # torso height
LROBE_H   = 34    # lower robe height
TOTAL_H   = 98    # total character height

# Derived y positions (from top):
# HEAD_TOP  = FEET_Y - TOTAL_H     = 65
# TORSO_TOP = HEAD_TOP + HEAD_H    = 95
# LROBE_TOP = TORSO_TOP + TORSO_H  = 127
# LROBE_BOT = LROBE_TOP + LROBE_H  = 161  (2px above FEET_Y to show boots)

HEAD_TOP  = FEET_Y - TOTAL_H
TORSO_TOP = HEAD_TOP + HEAD_H
LROBE_TOP = TORSO_TOP + TORSO_H
LROBE_BOT = LROBE_TOP + LROBE_H

STAFF_X   = CX_BODY + 20   # staff held slightly right of body
STAFF_ORB_DEFAULT = HEAD_TOP - 22  # orb above hood

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
    extra_fx=None  # callable(arr) for special effects
):
    """
    Compose a full cleric frame.
    All y positions are adjusted by bob.
    leaning: horizontal shift of entire character for recoil.
    """
    arr = new_frame()
    cx   = CX_BODY + leaning
    feet = FEET_Y + bob

    ht   = HEAD_TOP  + bob
    tt   = TORSO_TOP + bob
    lrt  = LROBE_TOP + bob
    lrb  = LROBE_BOT + bob

    # Staff parameters
    staff_x = STAFF_X + leaning
    if staff_raised:
        orb_y = ht - 28
    else:
        orb_y = ht - 22

    # Ground shadow
    if shadow:
        shadow_ellipse(arr, cx, feet + 2, 26, 4, 80)

    # 1. Draw back of staff (behind character body)
    draw_staff(arr, staff_x, orb_y, feet + 4,
               angle=staff_angle, glow=staff_glow)

    # 2. Feet (visible below robe hem)
    draw_boots(arr, cx, feet, walk_phase=walk_phase)

    # 3. Lower robe
    draw_lower_robe(arr, cx, lrt, lrb,
                    sway_x=int(walk_phase * 8))

    # 4. Arms (behind torso for 'idle', in front for 'cast')
    if arm_pose in ('idle', 'hit', 'victory', 'item'):
        draw_arms(arr, cx, tt, arm_pose=arm_pose)

    # 5. Torso
    draw_torso(arr, cx, tt, arm_pose=arm_pose, bob=0)

    # 6. Arms in front of torso
    if arm_pose not in ('idle', 'hit', 'victory', 'item'):
        draw_arms(arr, cx, tt, arm_pose=arm_pose)

    # 7. Head
    draw_head(arr, cx, ht, blink=blink, bob=0)

    # 8. Extra effects (glow, impact flash, etc.)
    if extra_fx:
        extra_fx(arr)

    return Image.fromarray(arr, 'RGBA')


# ─── HOLY LIGHT HELPERS ─────────────────────────────────────────────────────

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


# ─── ANIMATION GENERATORS ───────────────────────────────────────────────────

def gen_idle():
    f0 = draw_cleric_frame(bob=0, arm_pose='idle', staff_angle=0.0)
    f1 = draw_cleric_frame(bob=-1, arm_pose='idle', staff_angle=0.5)
    return [f0, f1], (512, 256)


def gen_walk():
    data = [
        # bob, walk_phase, staff_angle
        (-2, -0.7,  1.5),  # F0 left foot forward
        (-3, -0.3,  0.8),  # F1 passing, rise
        (-2,  0.0,  0.0),  # F2 contact
        (-1,  0.4, -0.8),  # F3 right foot forward
        (-2,  0.7, -1.5),  # F4 right stride
        (-1,  0.0,  0.0),  # F5 contact recover
    ]
    frames = []
    for bob, phase, s_ang in data:
        f = draw_cleric_frame(bob=bob, walk_phase=phase,
                               arm_pose='idle', staff_angle=s_ang)
        frames.append(f)
    return frames, (1536, 256)


def gen_attack():
    frames = []

    # F0: Wind-up - staff pulled back
    frames.append(draw_cleric_frame(bob=0, arm_pose='idle', staff_angle=-5.0))

    # F1: Step, begin swing
    def fx1(arr):
        pass
    frames.append(draw_cleric_frame(bob=-2, arm_pose='attack', staff_angle=-2.0))

    # F2: IMPACT - staff forward, holy burst
    def fx2(arr):
        bx = STAFF_X + 12
        by = HEAD_TOP - 30
        add_glow(arr, bx, by, 3, 22, HOLY_A, (HOLY_D[0], HOLY_D[1], HOLY_D[2], 0), steps=5)
        add_cross_ray(arr, bx, by, 18, (255, 248, 200, 200))
        disk(arr, bx, by, 5, HOLY_B)
        disk(arr, bx, by, 3, HOLY_A)
        disk(arr, bx, by, 1, HOLY_PURE)
    frames.append(draw_cleric_frame(bob=-4, arm_pose='attack',
                                     staff_angle=4.0, staff_raised=True,
                                     extra_fx=fx2))

    # F3: Follow-through, fading light
    def fx3(arr):
        bx = STAFF_X + 14
        by = HEAD_TOP - 28
        add_glow(arr, bx, by, 2, 10,
                 (255, 240, 160, 120), (255, 220, 80, 0), steps=8)
    frames.append(draw_cleric_frame(bob=-2, arm_pose='attack',
                                     staff_angle=7.0, staff_raised=True,
                                     extra_fx=fx3))

    # F4: Recover
    frames.append(draw_cleric_frame(bob=-1, arm_pose='idle', staff_angle=3.0))

    # F5: Rest
    frames.append(draw_cleric_frame(bob=0, arm_pose='idle', staff_angle=0.0))

    return frames, (1536, 256)


def gen_hit():
    frames = []

    # F0: Impact - flash red
    def fx0(arr):
        tint_region(arr, CX_BODY - 40, HEAD_TOP,
                    CX_BODY + 45, FEET_Y + 2, 70, -15, -15)
    frames.append(draw_cleric_frame(bob=1, arm_pose='hit',
                                     leaning=-5, staff_angle=8.0,
                                     extra_fx=fx0))

    # F1: Stagger
    def fx1(arr):
        tint_region(arr, CX_BODY - 45, HEAD_TOP,
                    CX_BODY + 42, FEET_Y + 3, 35, -8, -8)
    frames.append(draw_cleric_frame(bob=3, arm_pose='hit',
                                     leaning=-9, staff_angle=12.0,
                                     extra_fx=fx1))

    # F2: Wince (blink)
    frames.append(draw_cleric_frame(bob=2, arm_pose='hit',
                                     leaning=-6, staff_angle=8.0,
                                     blink=True))

    # F3: Recover
    frames.append(draw_cleric_frame(bob=0, arm_pose='idle',
                                     leaning=-2, staff_angle=2.0))

    return frames, (1024, 256)


def gen_dead():
    frames = []

    # F0: Collapse beginning
    frames.append(draw_cleric_frame(bob=5, arm_pose='hit',
                                     leaning=-3, staff_angle=6.0))

    # F1: Falling fast
    frames.append(draw_cleric_frame(bob=10, arm_pose='hit',
                                     leaning=-10, staff_angle=14.0))

    # F2: Nearly flat
    frames.append(draw_cleric_frame(bob=18, arm_pose='hit',
                                     leaning=-18, staff_angle=22.0))

    # F3: Completely fallen - custom horizontal layout
    arr = new_frame()
    body_y   = FEET_Y + 16
    body_cx  = CX_BODY - 15

    # Ground shadow
    shadow_ellipse(arr, body_cx + 5, body_y + 8, 38, 5, 90)

    # Fallen robe body (horizontal)
    for x in range(body_cx - 30, body_cx + 28):
        t = (x - (body_cx - 30)) / 58.0
        rh = int(10 + 4 * math.sin(t * math.pi))
        for dy in range(-rh, rh + 1):
            if abs(dy) == rh:
                col = OUTLINE
            elif abs(dy) >= rh - 1:
                col = ROBE_SHADOW
            elif abs(dy) >= rh - 3:
                col = ROBE_DARK
            elif dy < 0:
                col = ROBE_MID
            else:
                col = ROBE_LIGHT
            sp(arr, x, body_y + dy, col)

    # Hood on left (fallen)
    hx = body_cx - 22
    hy = body_y - 8
    for dy in range(-9, 10):
        for dx in range(-10, 11):
            if abs(dx) + abs(dy) < 14:
                col = ROBE_LIGHT
                if abs(dx) + abs(dy) > 10:
                    col = OUTLINE
                elif dy < -3:
                    col = ROBE_HILIT
                elif abs(dx) > 6:
                    col = ROBE_SHADOW
                sp(arr, hx + dx, hy + dy, col)
    # Red chevrons on fallen hood
    for tx, th in [(-5, 3), (0, 3), (5, 3)]:
        for dy2 in range(th):
            hw2 = th - 1 - dy2
            for dx2 in range(-hw2, hw2 + 1):
                sp(arr, hx + tx + dx2, hy + 2 + dy2, RED_TRIM)

    # Pink hem visible
    for x in range(body_cx, body_cx + 22):
        sp(arr, x, body_y + 10, PINK_MID)
        sp(arr, x, body_y + 11, PINK_LIGHT)

    # Gold belt area
    for x in range(body_cx - 5, body_cx + 10):
        sp(arr, x, body_y - 1, GOLD_MID)
        sp(arr, x, body_y,     GOLD_DARK)

    # Staff fallen to right (horizontal)
    staff_y = body_y + 14
    for x in range(body_cx - 15, body_cx + 48):
        sp(arr, x, staff_y - 1, STAFF_LIGHT)
        sp(arr, x, staff_y,     STAFF_MID)
        sp(arr, x, staff_y + 1, STAFF_DARK)
        sp(arr, x, staff_y + 2, OUTLINE)
    # Sun orb at right end
    sox = body_cx + 44
    soy = staff_y - 4
    disk(arr, sox, soy, 6, ORB_MID)
    disk(arr, sox, soy, 4, ORB_LIGHT)
    disk(arr, sox, soy, 2, ORB_HILIT)
    sp(arr, sox, soy, ORB_CORE)
    # Fallen orb rays
    for ang in [0, 45, 90, 135, 180, 225, 270, 315]:
        rad = math.radians(ang)
        for r in range(7, 12):
            rx = sox + int(r * math.cos(rad))
            ry = soy + int(r * math.sin(rad))
            blend_sp(arr, rx, ry, (ORB_DARK[0], ORB_DARK[1], ORB_DARK[2], 120))

    frames.append(Image.fromarray(arr, 'RGBA'))

    return frames, (1024, 256)


def gen_cast():
    frames = []

    # F0: Prayer pose, small glow forming
    def fx0(arr):
        gx = CX_BODY + 2
        gy = TORSO_TOP - 5
        add_glow(arr, gx, gy, 2, 8,
                 (255, 245, 200, 80), (255, 230, 100, 0), steps=10)
    frames.append(draw_cleric_frame(bob=-1, arm_pose='cast',
                                     staff_angle=1.0, extra_fx=fx0))

    # F1: Glow building
    def fx1(arr):
        gx = CX_BODY + 2
        gy = TORSO_TOP - 8
        add_glow(arr, gx, gy, 3, 16,
                 (255, 240, 170, 140), (255, 210, 80, 0), steps=7)
        disk(arr, gx, gy, 4, (255, 245, 200, 160))
        disk(arr, gx, gy, 2, HOLY_B)
        sp(arr, gx, gy, HOLY_A)
    frames.append(draw_cleric_frame(bob=-2, arm_pose='cast',
                                     staff_angle=0.5, extra_fx=fx1))

    # F2: FULL BURST - brilliant golden healing light
    def fx2(arr):
        gx = CX_BODY + 2
        gy = TORSO_TOP - 12
        # Outer glow
        add_glow(arr, gx, gy, 8, 32,
                 (255, 235, 100, 170), (255, 200, 40, 0), steps=5)
        # Cross rays
        add_cross_ray(arr, gx, gy, 26, (255, 248, 190, 180))
        # 45-deg rays
        for ang in [45, 135, 225, 315]:
            for r in range(1, 20):
                a_v = int(150 * (1 - r / 20))
                rx = gx + int(r * math.cos(math.radians(ang)))
                ry = gy + int(r * math.sin(math.radians(ang)))
                blend_sp(arr, rx, ry, (255, 240, 160, a_v))
        # Core
        disk(arr, gx, gy, 8, (255, 235, 130, 200))
        disk(arr, gx, gy, 5, HOLY_C)
        disk(arr, gx, gy, 3, HOLY_B)
        disk(arr, gx, gy, 1, HOLY_PURE)
        # Golden tint on character
        tint_region(arr, CX_BODY - 40, HEAD_TOP - 5,
                    CX_BODY + 48, FEET_Y + 2, 22, 12, -5)
    frames.append(draw_cleric_frame(bob=-3, arm_pose='cast',
                                     staff_angle=0.0, staff_glow=True,
                                     extra_fx=fx2))

    # F3: Fade, serene
    def fx3(arr):
        gx = CX_BODY + 14
        gy = TORSO_TOP - 5
        add_glow(arr, gx, gy, 2, 10,
                 (255, 245, 190, 60), (255, 230, 120, 0), steps=12)
    frames.append(draw_cleric_frame(bob=-1, arm_pose='idle',
                                     staff_angle=0.0, extra_fx=fx3))

    return frames, (1024, 256)


def gen_defend():
    frames = []

    # F0: Begin raising staff
    frames.append(draw_cleric_frame(bob=0, arm_pose='defend', staff_angle=-2.0))

    # F1: Staff raised, shield forming
    def fx1(arr):
        cx_sh = CX_BODY + 16
        cy_sh = HEAD_TOP + 2
        for r in range(28, 18, -2):
            a_v = int(80 * (1 - (r - 18) / 10))
            for deg in range(190, 350, 6):
                rx = cx_sh + int(r * math.cos(math.radians(deg)))
                ry = cy_sh + int(r * math.sin(math.radians(deg)))
                blend_sp(arr, rx, ry, (200, 238, 255, a_v))
    frames.append(draw_cleric_frame(bob=-1, arm_pose='defend',
                                     staff_raised=True, staff_angle=0.0,
                                     extra_fx=fx1))

    # F2: Full divine shield
    def fx2(arr):
        cx_sh = CX_BODY + 16
        cy_sh = HEAD_TOP
        # Shield arc
        for r in range(38, 22, -2):
            a_v = int(150 * (1 - (r - 22) / 16))
            for deg in range(185, 355, 4):
                rx = cx_sh + int(r * math.cos(math.radians(deg)))
                ry = cy_sh + int(r * math.sin(math.radians(deg)))
                blend_sp(arr, rx, ry, (175, 228, 255, a_v))
        # Gold sparkle points on edge
        for deg in [200, 225, 250, 275, 300, 325]:
            r = 38
            rx = cx_sh + int(r * math.cos(math.radians(deg)))
            ry = cy_sh + int(r * math.sin(math.radians(deg)))
            disk(arr, rx, ry, 2, (255, 228, 90, 200))
            sp(arr, rx, ry, GOLD_HILIT)
    frames.append(draw_cleric_frame(bob=-2, arm_pose='defend',
                                     staff_raised=True, staff_angle=0.0,
                                     extra_fx=fx2))

    # F3: Held stance, shield dimming
    def fx3(arr):
        cx_sh = CX_BODY + 16
        cy_sh = HEAD_TOP + 2
        for r in range(32, 22, -3):
            a_v = int(50 * (1 - (r - 22) / 10))
            for deg in range(190, 350, 8):
                rx = cx_sh + int(r * math.cos(math.radians(deg)))
                ry = cy_sh + int(r * math.sin(math.radians(deg)))
                blend_sp(arr, rx, ry, (200, 240, 255, a_v))
    frames.append(draw_cleric_frame(bob=-1, arm_pose='defend',
                                     staff_raised=True, staff_angle=0.0,
                                     extra_fx=fx3))

    return frames, (1024, 256)


def gen_item():
    frames = []

    # F0: Reach to belt
    frames.append(draw_cleric_frame(bob=0, arm_pose='item', staff_angle=2.0))

    # F1: Hold up potion bottle
    def fx1(arr):
        px = CX_BODY + 28
        py = HEAD_TOP + 10
        # Potion body
        for dx in range(-4, 5):
            for dy in range(-10, 6):
                if abs(dx) == 4 or dy == -10 or dy == 5:
                    sp(arr, px + dx, py + dy, OUTLINE)
                else:
                    # Green potion
                    bright = 1.0 - abs(dx) / 5
                    g = int(160 + 40 * bright)
                    sp(arr, px + dx, py + dy, (60, g, 80, 210))
        # Bottle neck
        for dy in range(-14, -10):
            sp(arr, px - 1, py + dy, OUTLINE)
            sp(arr, px,     py + dy, (80, 180, 100, 190))
            sp(arr, px + 1, py + dy, OUTLINE)
        # Cork
        sp(arr, px - 1, py - 14, STAFF_MID)
        sp(arr, px,     py - 14, STAFF_LIGHT)
        sp(arr, px + 1, py - 14, STAFF_MID)
        # Highlight on bottle
        sp(arr, px - 3, py - 7, (150, 230, 160, 220))
        sp(arr, px - 3, py - 6, (150, 230, 160, 180))
        sp(arr, px - 2, py - 7, (120, 210, 130, 160))
    frames.append(draw_cleric_frame(bob=-2, arm_pose='item',
                                     staff_angle=2.0, extra_fx=fx1))

    # F2: Applying/tipping potion
    def fx2(arr):
        px = CX_BODY + 30
        py = HEAD_TOP + 8
        # Slightly tilted bottle
        for dx in range(-4, 5):
            for dy in range(-9, 6):
                if abs(dx) == 4 or dy == -9 or dy == 5:
                    sp(arr, px + dx, py + dy - dx//3, OUTLINE)
                else:
                    sp(arr, px + dx, py + dy - dx//3, (50, 145, 70, 200))
        # Dripping liquid
        for drop_dy in range(6, 18, 3):
            drop_a = max(20, 180 - drop_dy * 8)
            blend_sp(arr, px - 1, py + drop_dy, (100, 200, 120, drop_a))
            blend_sp(arr, px,     py + drop_dy, (80, 180, 100, drop_a))
    frames.append(draw_cleric_frame(bob=-2, arm_pose='item',
                                     staff_angle=1.0, extra_fx=fx2))

    # F3: Sparkle (used)
    def fx3(arr):
        for sx, sy in [(CX_BODY + 18, HEAD_TOP + 5),
                       (CX_BODY + 8,  HEAD_TOP + 15),
                       (CX_BODY + 28, HEAD_TOP + 20),
                       (CX_BODY + 12, TORSO_TOP + 5)]:
            sp(arr, sx, sy, GOLD_HILIT)
            for ang in [0, 90, 180, 270]:
                rx = sx + int(5 * math.cos(math.radians(ang)))
                ry = sy + int(5 * math.sin(math.radians(ang)))
                sp(arr, rx, ry, (255, 240, 140, 180))
                rx2 = sx + int(3 * math.cos(math.radians(ang + 45)))
                ry2 = sy + int(3 * math.sin(math.radians(ang + 45)))
                sp(arr, rx2, ry2, (255, 235, 120, 140))
    frames.append(draw_cleric_frame(bob=-1, arm_pose='idle',
                                     staff_angle=0.0, extra_fx=fx3))

    return frames, (1024, 256)


def gen_victory():
    frames = []

    # F0: Begin raising arms
    frames.append(draw_cleric_frame(bob=-2, arm_pose='victory',
                                     staff_raised=False, staff_angle=2.0))

    # F1: Arms up, small glow
    def fx1(arr):
        gx = STAFF_X + 4
        gy = HEAD_TOP - 20
        add_glow(arr, gx, gy, 3, 12,
                 (255, 238, 130, 120), (255, 210, 60, 0), steps=8)
    frames.append(draw_cleric_frame(bob=-4, arm_pose='victory',
                                     staff_raised=True, staff_angle=0.0,
                                     extra_fx=fx1))

    # F2: Peak - brilliant warm golden celebration glow
    def fx2(arr):
        gx = STAFF_X + 4
        gy = HEAD_TOP - 26
        # Large warm radial
        add_glow(arr, gx, gy, 6, 36,
                 (255, 238, 100, 180), (255, 195, 30, 0), steps=5)
        # Radial rays
        for ang in range(0, 360, 25):
            for r in range(14, 34):
                a_v = int(150 * (1 - (r - 14) / 20))
                rx = gx + int(r * math.cos(math.radians(ang)))
                ry = gy + int(r * math.sin(math.radians(ang)))
                blend_sp(arr, rx, ry, (255, 245, 175, a_v))
        disk(arr, gx, gy, 8, (255, 235, 120, 210))
        disk(arr, gx, gy, 5, HOLY_B)
        disk(arr, gx, gy, 3, HOLY_A)
        sp(arr, gx, gy, HOLY_PURE)
        # Warm tint on whole character
        tint_region(arr, CX_BODY - 45, HEAD_TOP - 10,
                    CX_BODY + 55, FEET_Y + 3, 16, 8, -4)
    frames.append(draw_cleric_frame(bob=-5, arm_pose='victory',
                                     staff_raised=True, staff_angle=0.0,
                                     staff_glow=True, extra_fx=fx2))

    # F3: Peaceful rest glow
    def fx3(arr):
        gx = STAFF_X + 4
        gy = HEAD_TOP - 24
        add_glow(arr, gx, gy, 3, 14,
                 (255, 240, 155, 80), (255, 220, 80, 0), steps=10)
    frames.append(draw_cleric_frame(bob=-3, arm_pose='victory',
                                     staff_raised=True, staff_angle=1.0,
                                     extra_fx=fx3))

    return frames, (1024, 256)


# ─── STRIP ASSEMBLER AND MAIN ────────────────────────────────────────────────

def save_strip(frames, strip_size, path):
    strip = Image.new("RGBA", strip_size, (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * 256, 0))
    strip.save(path)
    print(f"  Saved: {path}  ({strip_size[0]}x{strip_size[1]}, {len(frames)} frames)")


def main():
    print("Generating Cleric sprites for Cowardly Irregular...")
    print(f"Output: {OUT_DIR}")
    print(f"Character: cx={CX_BODY}, feet_y={FEET_Y}, head_top={HEAD_TOP}")
    print(f"Total char height: {TOTAL_H}px, width: ~60px\n")

    animations = [
        ("idle",    gen_idle),
        ("walk",    gen_walk),
        ("attack",  gen_attack),
        ("hit",     gen_hit),
        ("dead",    gen_dead),
        ("cast",    gen_cast),
        ("defend",  gen_defend),
        ("item",    gen_item),
        ("victory", gen_victory),
    ]

    for name, fn in animations:
        print(f"  {name}...")
        frames, strip_size = fn()
        out_path = f"{OUT_DIR}/{name}.png"
        save_strip(frames, strip_size, out_path)

    print("\nDone.")


if __name__ == "__main__":
    main()
