#!/usr/bin/env python3
"""
Generate fighter DEFEND and CAST animation strips.
256x256 frames, 4 frames per strip = 1024x256 PNG.

Strategy:
  1. Start from idle frame 1 as base (head/torso/legs fully intact).
  2. Erase the diagonal sword blade using the 6 steel-exclusive palette entries
     plus grip-skin pixels in the handle zone.
  3. Paint new arm shapes and sword poses DIRECTLY ON TOP of the intact body —
     no arm-region erasure that would hollow out the torso.
  4. 2x2 "super-pixels" throughout to match SNES art density.
"""

import math
from PIL import Image
import numpy as np

# ─── PALETTE (exact hex extracted from idle.png) ────────────────────────────

def c(r, g, b, a=255):
    return (r, g, b, a)

C_OUTLINE = c(0x24, 0x22, 0x34)    # dark purple-black outline
C_VDARK   = c(0x22, 0x1c, 0x1a)    # near-black
C_DBROWN  = c(0x32, 0x2b, 0x28)    # dark leather brown
C_DRED    = c(0x73, 0x17, 0x2d)    # dark crimson armor
C_MRED    = c(0x9d, 0x31, 0x23)    # mid red armor
C_BRED    = c(0xb4, 0x20, 0x2a)    # bright red
C_ORANGE  = c(0xfa, 0x6a, 0x0a)    # orange highlight
C_GOLD    = c(0xf9, 0xa3, 0x1b)    # gold trim

# Steel — appear ONLY on the sword, never on body/hair/skin/boots
C_SDARK   = c(0x4c, 0x4e, 0x56)
C_SMID    = c(0x7d, 0x81, 0x90)
C_SLIGHT  = c(0xae, 0xb3, 0xcc)
C_SGRAY   = c(0x5d, 0x62, 0x6e)
C_SBGRAY  = c(0x33, 0x39, 0x41)
C_SBLUE   = c(0x36, 0x3d, 0x4d)

C_PURPLE  = c(0x40, 0x33, 0x53)    # purple ground shadow
C_SKIN_D  = c(0xbb, 0x75, 0x47)    # dark skin
C_SKIN_M  = c(0xe9, 0xb5, 0xa3)    # mid skin
C_SKIN_L  = c(0xf4, 0xd2, 0x9c)    # light skin

C_WHITE   = c(0xff, 0xff, 0xff)

# Magic (CAST only)
C_MGLOW1  = c(0x60, 0xa0, 0xff)
C_MGLOW2  = c(0xa0, 0xc8, 0xff)
C_MGLOW3  = c(0xd0, 0xe8, 0xff)
C_MSPARK  = c(0xff, 0xff, 0xa0)

TRANSP    = (0, 0, 0, 0)

SWORD_ONLY_RGB = {
    (0x4c, 0x4e, 0x56),
    (0x7d, 0x81, 0x90),
    (0xae, 0xb3, 0xcc),
    (0x5d, 0x62, 0x6e),
    (0x33, 0x39, 0x41),
    (0x36, 0x3d, 0x4d),
}

# ─── DRAWING PRIMITIVES ──────────────────────────────────────────────────────

def pp(arr, x, y, color):
    """Place one 2×2 super-pixel. Clips silently at [0,256)."""
    for dy in range(2):
        for dx in range(2):
            px, py = x + dx, y + dy
            if 0 <= px < 256 and 0 <= py < 256:
                arr[py, px] = color


def arm(arr, x0, y0, x1, y1, c_main, c_hi):
    """
    Draw an armored arm segment.  Uses a 3-wide strip (6px rendered) with
    a highlight centre stripe to look like a rounded vambrace.
    """
    dx, dy = x1 - x0, y1 - y0
    dist   = math.hypot(dx, dy)
    if dist < 1:
        return
    # Perpendicular unit vector
    nx, ny = -dy / dist, dx / dist
    steps  = max(int(dist / 2) + 1, 2)
    for i in range(steps):
        t  = i / (steps - 1)
        cx = int(x0 + t * dx) & ~1
        cy = int(y0 + t * dy) & ~1
        # 3 stripes: outer-dark, mid, highlight-centre
        ox = int(nx * 4) & ~1;  oy = int(ny * 4) & ~1
        mx = int(nx * 2) & ~1;  my = int(ny * 2) & ~1
        pp(arr, cx + ox, cy + oy, C_OUTLINE)
        pp(arr, cx + mx, cy + my, c_main)
        pp(arr, cx,      cy,      c_hi)
        pp(arr, cx - mx, cy - my, c_main)
        pp(arr, cx - ox, cy - oy, C_OUTLINE)


def knuckle(arr, fx, fy, glow=None):
    """3×3 super-pixel fist with optional glow aura."""
    pp(arr, fx - 2, fy - 2, C_OUTLINE)
    pp(arr, fx,     fy - 2, C_SKIN_L)
    pp(arr, fx + 2, fy - 2, C_OUTLINE)
    pp(arr, fx - 2, fy,     C_SKIN_D)
    pp(arr, fx,     fy,     C_SKIN_M)
    pp(arr, fx + 2, fy,     C_SKIN_D)
    pp(arr, fx - 2, fy + 2, C_OUTLINE)
    pp(arr, fx,     fy + 2, C_SKIN_D)
    pp(arr, fx + 2, fy + 2, C_OUTLINE)
    if glow is not None:
        for ox, oy in [(-4,0),(6,0),(0,-4),(0,6),(-4,-4),(6,-4),(-4,6),(6,6)]:
            gx, gy = fx + ox, fy + oy
            if 0 <= gx < 256 and 0 <= gy < 256:
                arr[gy, gx] = glow


# ─── SWORD SHAPES ────────────────────────────────────────────────────────────

def sword_vertical(arr, cx, ty, blade_len=52):
    """
    Vertical guard sword.
    cx       : x-centre of blade
    ty       : y of blade tip (above head)
    blade_len: pixel length of blade section only
    """
    # Tip (tapers to 1 sp)
    pp(arr, cx,   ty,     C_SLIGHT)
    pp(arr, cx,   ty + 2, C_SMID)

    # Blade body: outline | dark | mid | light | edge
    for seg in range(4, blade_len, 2):
        y = ty + seg
        pp(arr, cx - 4, y, C_OUTLINE)
        pp(arr, cx - 2, y, C_SDARK)
        pp(arr, cx,     y, C_SMID)
        pp(arr, cx + 2, y, C_SLIGHT)
        pp(arr, cx + 4, y, C_SGRAY)

    # Serrations on left edge
    for seg in range(10, blade_len - 6, 10):
        y = ty + seg
        pp(arr, cx - 6, y,     C_SDARK)
        pp(arr, cx - 6, y + 2, C_SDARK)

    # Cross-guard
    gy = ty + blade_len
    for gx in range(cx - 14, cx + 16, 2):
        pp(arr, gx, gy,     C_SMID)
        pp(arr, gx, gy + 2, C_SDARK)
    pp(arr, cx - 14, gy, C_SDARK)
    pp(arr, cx + 14, gy, C_SDARK)
    pp(arr, cx - 2,  gy, C_SLIGHT)    # centre highlight

    # Handle
    hy = gy + 4
    for i in range(3):
        pp(arr, cx - 2, hy + i * 2, C_DBROWN)
        pp(arr, cx,     hy + i * 2, C_DBROWN)
    pp(arr, cx - 2, hy + 2, C_OUTLINE)   # wrap band
    pp(arr, cx,     hy + 2, C_OUTLINE)

    # Pommel
    py2 = hy + 6
    pp(arr, cx - 2, py2,     C_SDARK)
    pp(arr, cx,     py2,     C_SDARK)
    pp(arr, cx - 2, py2 + 2, C_OUTLINE)
    pp(arr, cx,     py2 + 2, C_OUTLINE)


def sword_diagonal_up_right(arr, hx, hy, length=52):
    """
    Sword mid-raise: ~45° with blade going upper-right.
    hx, hy = handle/pommel position (lower-left end).
    """
    steps = length // 2
    for i in range(steps):
        bx, by = hx + i, hy - i
        pp(arr, bx - 2, by + 2, C_OUTLINE)
        pp(arr, bx - 2, by,     C_SDARK)
        pp(arr, bx,     by,     C_SMID)
        pp(arr, bx + 2, by - 2, C_SLIGHT)
        if i % 5 == 0 and 4 < i < steps - 4:
            pp(arr, bx - 4, by + 4, C_SDARK)    # serration

    # Diagonal crossguard
    for k in range(-4, 5):
        pp(arr, hx + k * 2, hy - k * 2 + 2, C_SMID)
    pp(arr, hx - 8, hy + 8, C_SDARK)
    pp(arr, hx + 8, hy - 8, C_SDARK)

    # Handle (lower-left of guard)
    for k in range(3):
        pp(arr, hx - 2 - k * 2, hy + k * 2,     C_DBROWN)
        pp(arr, hx - k * 2,     hy + k * 2 + 2, C_DBROWN)


def sword_angled_down(arr, hx, hy, length=52):
    """
    Sword pointed steeply downward-left (2-down : 1-left).
    hx, hy = guard/handle position (upper-right end).
    """
    steps = length // 2
    for i in range(steps):
        bx, by = hx - i, hy + i * 2
        pp(arr, bx,     by - 2, C_OUTLINE)
        pp(arr, bx - 2, by,     C_SDARK)
        pp(arr, bx,     by,     C_SMID)
        pp(arr, bx + 2, by,     C_SLIGHT)
        if i % 5 == 0 and 4 < i < steps - 4:
            pp(arr, bx - 4, by + 2, C_SDARK)

    # Guard
    for gx in range(hx - 8, hx + 12, 2):
        pp(arr, gx, hy - 2, C_SMID)
    pp(arr, hx - 8,  hy - 2, C_SDARK)
    pp(arr, hx + 10, hy - 2, C_SDARK)

    # Handle stub above guard
    pp(arr, hx,     hy - 4, C_DBROWN)
    pp(arr, hx + 2, hy - 4, C_DBROWN)
    pp(arr, hx,     hy - 6, C_SDARK)
    pp(arr, hx + 2, hy - 6, C_SDARK)


# ─── MAGIC ORBS ──────────────────────────────────────────────────────────────

def magic_orb(arr, cx, cy, radius, stage):
    """
    stage 0 = tiny spark
    stage 1 = growing orb with corona
    stage 2 = full blast with 8 rays
    stage 3 = fading hollow ring
    """
    if stage == 0:
        pp(arr, cx,     cy,     C_WHITE)
        pp(arr, cx - 2, cy,     C_MGLOW3)
        pp(arr, cx + 2, cy,     C_MGLOW3)
        pp(arr, cx,     cy - 2, C_MGLOW3)
        pp(arr, cx,     cy + 2, C_MGLOW3)

    elif stage == 1:
        r = radius
        for dy in range(-r, r + 1, 2):
            for dx in range(-r, r + 1, 2):
                d = math.hypot(dx, dy)
                if d > r:
                    continue
                col = (C_WHITE if d < r * 0.35
                       else C_MGLOW3 if d < r * 0.65
                       else C_MGLOW2)
                pp(arr, cx + dx, cy + dy, col)
        for angle in range(0, 360, 30):
            ax = int(cx + (r + 4) * math.cos(math.radians(angle))) & ~1
            ay = int(cy + (r + 4) * math.sin(math.radians(angle))) & ~1
            pp(arr, ax, ay, C_MGLOW1)

    elif stage == 2:
        r = radius
        for dy in range(-r, r + 1, 2):
            for dx in range(-r, r + 1, 2):
                d = math.hypot(dx, dy)
                if d > r:
                    continue
                col = (C_WHITE  if d < r * 0.25
                       else C_MSPARK if d < r * 0.50
                       else C_MGLOW3 if d < r * 0.75
                       else C_MGLOW2)
                pp(arr, cx + dx, cy + dy, col)
        for angle in range(0, 360, 45):
            for dist in range(r + 2, r + 26, 2):
                ax = int(cx + dist * math.cos(math.radians(angle))) & ~1
                ay = int(cy + dist * math.sin(math.radians(angle))) & ~1
                fade = max(0, 240 - (dist - r) * 10)
                if fade > 0 and 0 <= ax < 256 and 0 <= ay < 256:
                    arr[ay, ax] = (C_MGLOW1[0], C_MGLOW1[1], C_MGLOW1[2], fade)

    elif stage == 3:
        r  = radius
        ri = max(2, r - 6)
        for dy in range(-r, r + 1, 2):
            for dx in range(-r, r + 1, 2):
                d = math.hypot(dx, dy)
                if ri <= d <= r:
                    px, py = cx + dx, cy + dy
                    fade = int(170 * (1 - (d - ri) / max(r - ri, 1)))
                    if 0 <= px < 256 and 0 <= py < 256:
                        arr[py, px] = (C_MGLOW2[0], C_MGLOW2[1],
                                       C_MGLOW2[2], fade)
        pp(arr, cx, cy, (C_MGLOW3[0], C_MGLOW3[1], C_MGLOW3[2], 100))


# ─── LOAD & PREPARE BASE IMAGES ──────────────────────────────────────────────

_idle_raw  = Image.open(
    "/home/struktured/projects/cowardly-irregular/assets/sprites/jobs/fighter/idle.png"
).convert("RGBA")
_idle_np   = np.array(_idle_raw, dtype=np.uint8)
IDLE_F1    = _idle_np[:, :256, :].copy()    # frame 1 only


def _erase_sword(arr):
    """
    Remove the diagonal idle sword blade and handle.

    Pass 1 — exact steel-only palette colours (whole frame).
    Pass 2 — grip skin pixels in handle zone (x 90-140, y 108-148).
    Pass 3 — all purple ground-shadow pixels in blade sweep area.
    Pass 4 — gap scan: at each leg-level row, erase the left isolated
             cluster (sword outline dots) that sits clearly separated
             from the main body by a pixel gap of >= 4.
    Pass 5 — final sweep: erase any remaining #242234 outline pixels
             that are in the far-left blade-tip zone (x < 75, y > 140).
    """
    # Pass 1: steel-exclusive colors
    for y in range(256):
        for x in range(256):
            r, g, b, a = arr[y, x]
            if a > 10 and (r, g, b) in SWORD_ONLY_RGB:
                arr[y, x] = TRANSP

    # Pass 2: grip skin
    for y in range(108, 148):
        for x in range(90, 140):
            r, g, b, a = arr[y, x]
            if a > 10 and r > 150 and g > 90 and b > 60 and r > g:
                arr[y, x] = TRANSP

    # Pass 3: purple shadow — wider sweep covers all of blade area
    for y in range(130, 170):
        for x in range(50, 160):
            if arr[y, x, 3] > 10 and tuple(arr[y, x, :3]) == (0x40, 0x33, 0x53):
                arr[y, x] = TRANSP

    # Pass 4: gap-based left-cluster erase for rows y=126-165
    for y in range(126, 166):
        non_trans = [x for x in range(50, 160) if arr[y, x, 3] > 10]
        if len(non_trans) < 2:
            continue
        # Find largest gap between consecutive non-transparent pixels
        best_gap, left_end, right_start = 0, 0, 0
        for i in range(len(non_trans) - 1):
            g = non_trans[i + 1] - non_trans[i]
            if g > best_gap:
                best_gap, left_end, right_start = g, non_trans[i], non_trans[i + 1]
        # Only erase the left cluster if gap >= 4 and it's clearly in blade zone
        if best_gap >= 4 and left_end < right_start - 4 and left_end < 95:
            for x in range(50, left_end + 2):
                if arr[y, x, 3] > 10:
                    arr[y, x] = TRANSP

    # Pass 5: blade-tip stray dots — any dark pixel isolated far left
    for y in range(140, 168):
        for x in range(50, 76):
            r, g, b, a = arr[y, x]
            if a > 10:
                # Is it surrounded by transparent on left? Then it's a stray dot.
                neighbors_solid = sum(
                    1 for dx, dy in [(-2,0),(2,0),(0,-2),(0,2)]
                    if 0 <= x+dx < 256 and 0 <= y+dy < 256
                    and arr[y+dy, x+dx, 3] > 10
                )
                if neighbors_solid <= 1:
                    arr[y, x] = TRANSP


# Build a single shared base (idle with sword removed, everything else intact).
_base    = IDLE_F1.copy()
_erase_sword(_base)
BASE_NO_SWORD = _base   # IMMUTABLE — always copy before use


def fresh():
    return BASE_NO_SWORD.copy()


# ─── DEFEND ANIMATION ────────────────────────────────────────────────────────
#
# Idle landmark positions (from pixel analysis):
#   Right shoulder : x ≈ 138, y ≈ 96
#   Left  shoulder : x ≈  92, y ≈ 100
#   Torso centre   : x ≈ 115, y ≈ 115
#   Hip            : x ≈ 115, y ≈ 132
#
# Guard sword placed at x=106 (left of body centre, visually "in front").
# Blade tip at y=62 (above head), cross-guard at y=114.
# Legs are NOT shifted — idle stance is already a wide guard-ready position.
# Crouch feeling is achieved via arm position (arms drawn lower) only.

GUARD_CX  = 106
BLADE_TIP = 62
BLADE_LEN = 52


def make_defend_frame(fn):
    """
    fn 0  Raising sword  — diagonal ~45°, right arm bringing it up
    fn 1  Full guard     — sword vertical, both hands on hilt
    fn 2  Hold guard     — same stance, arms tensed inward 2 px
    fn 3  Brace impact   — sword tilted 4 px forward at base
    """
    arr = fresh()

    if fn == 0:
        # Sword still transitioning: ~45° diagonal, blade upper-right
        # Handle lower-left at (108, 130)
        sword_diagonal_up_right(arr, hx=108, hy=130, length=52)

        # Right arm: shoulder → handle
        arm(arr, 138, 96, 128, 114, C_MRED, C_ORANGE)
        arm(arr, 128, 114, 108, 130, C_DRED, C_MRED)
        knuckle(arr, 106, 128)

        # Left arm: reaching toward incoming grip position
        arm(arr, 92, 100, 100, 116, C_DRED, C_MRED)
        knuckle(arr, 98, 114)

    elif fn == 1:
        # Full vertical guard
        sword_vertical(arr, GUARD_CX, BLADE_TIP, BLADE_LEN)

        # Right arm: shoulder → upper grip
        arm(arr, 138, 96,  124, 106, C_MRED, C_ORANGE)
        arm(arr, 124, 106, GUARD_CX + 2, 116, C_MRED, C_ORANGE)
        knuckle(arr, GUARD_CX, 114)

        # Left arm: shoulder → lower grip
        arm(arr, 92, 100, 98, 114, C_DRED, C_MRED)
        arm(arr, 98, 114, GUARD_CX - 2, 126, C_DRED, C_MRED)
        knuckle(arr, GUARD_CX - 4, 124)

    elif fn == 2:
        # Hold guard — arms 2 px more inward (isometric tension)
        sword_vertical(arr, GUARD_CX, BLADE_TIP, BLADE_LEN)

        arm(arr, 138, 96,  122, 104, C_MRED, C_ORANGE)
        arm(arr, 122, 104, GUARD_CX + 2, 114, C_MRED, C_ORANGE)
        knuckle(arr, GUARD_CX, 112)

        arm(arr, 92, 100, 96, 112, C_DRED, C_MRED)
        arm(arr, 96, 112, GUARD_CX - 2, 122, C_DRED, C_MRED)
        knuckle(arr, GUARD_CX - 4, 120)

    elif fn == 3:
        # Brace — whole body leans 4px forward (into the guard).
        # Sword tilts slightly toward viewer (base 6px right of tip).
        # Arms are maximally compressed — elbows wide, wrists locked on hilt.
        LEAN = 4
        tip_x  = GUARD_CX + LEAN
        for seg in range(0, BLADE_LEN, 2):
            y    = BLADE_TIP + seg
            lean = (seg * 6) // BLADE_LEN      # 0 at tip → 6 at guard
            bx   = tip_x + lean
            pp(arr, bx - 4, y, C_OUTLINE)
            pp(arr, bx - 2, y, C_SDARK)
            pp(arr, bx,     y, C_SMID)
            pp(arr, bx + 2, y, C_SLIGHT)
            pp(arr, bx + 4, y, C_SGRAY)
            if seg % 10 == 0 and 6 < seg < BLADE_LEN - 6:
                pp(arr, bx - 6, y, C_SDARK)

        gy  = BLADE_TIP + BLADE_LEN
        gcx = tip_x + 6
        for gx in range(gcx - 14, gcx + 16, 2):
            pp(arr, gx, gy,     C_SMID)
            pp(arr, gx, gy + 2, C_SDARK)
        pp(arr, gcx - 14, gy, C_SDARK)
        pp(arr, gcx + 14, gy, C_SDARK)
        pp(arr, gcx - 2,  gy, C_SLIGHT)

        hy = gy + 4
        for i in range(3):
            pp(arr, gcx - 2, hy + i * 2, C_DBROWN)
            pp(arr, gcx,     hy + i * 2, C_DBROWN)
        pp(arr, gcx - 2, hy + 2, C_OUTLINE)
        pp(arr, gcx,     hy + 2, C_OUTLINE)

        py2 = hy + 6
        pp(arr, gcx - 2, py2,     C_SDARK)
        pp(arr, gcx,     py2,     C_SDARK)
        pp(arr, gcx - 2, py2 + 2, C_OUTLINE)
        pp(arr, gcx,     py2 + 2, C_OUTLINE)

        # Arms braced hard — wide-elbow locked grip, both shoulders low
        # Right arm: shoulder swept forward, elbow flared outward right
        arm(arr, 138, 98,  148, 108, C_MRED, C_ORANGE)   # upper arm flares right
        arm(arr, 148, 108, gcx + 2, 116, C_MRED, C_ORANGE)
        knuckle(arr, gcx, 114)

        # Left arm: shoulder swept forward, elbow flared outward left
        arm(arr, 92, 100, 82, 110, C_DRED, C_MRED)       # upper arm flares left
        arm(arr, 82, 110, gcx - 2, 126, C_DRED, C_MRED)
        knuckle(arr, gcx - 4, 124)

        # Reinforce the brace: dark outline cap on each arm at body edge
        for off in range(0, 6, 2):
            pp(arr, 148 + off, 108, C_OUTLINE)
            pp(arr, 80 - off,  110, C_OUTLINE)

    # Ground shadow
    for sx in range(82, 150, 2):
        pp(arr, sx, 162, C_PURPLE)

    return Image.fromarray(arr)


# ─── CAST ANIMATION ──────────────────────────────────────────────────────────
#
# Fighter channels magic through the off-hand (left arm) while the sword
# hangs low at the right side.
#
# Left shoulder : x ≈ 92, y ≈ 100
# Sword-arm     : right side, handle at x ≈ 138, y ≈ 130–132
# Magic hand    : extends to x ≈ 62-72, y ≈ 90-94

def make_cast_frame(fn):
    """
    fn 0  Raising hand / sword mid-drop  — tiny spark at palm
    fn 1  Hand extended, orb gathering   — medium glow at hand
    fn 2  Full cast / arm thrust         — large burst
    fn 3  Follow-through / retracting    — fading ring
    """
    arr = fresh()

    # Slight forward lean for frames 1-2
    lean = [0, 2, 4, 2][fn]

    sh_x = 92 + lean    # left (cast) shoulder
    sh_y = 100

    # ── Sword: right arm lowers and holds the sword at side ──────────────
    if fn == 0:
        # Sword still transitioning downward at ~45°, blade upper-right
        sword_diagonal_up_right(arr, hx=110 + lean, hy=126, length=48)
        arm(arr, 140 + lean, 96,  126 + lean, 112, C_MRED, C_ORANGE)
        arm(arr, 126 + lean, 112, 110 + lean, 126, C_DRED, C_MRED)
        knuckle(arr, 108 + lean, 124)
    else:
        # Sword fully lowered, pointing steeply downward-left
        sword_angled_down(arr, hx=138 + lean, hy=130, length=50)
        arm(arr, 140 + lean, 96,  138 + lean, 116, C_DRED, C_MRED)
        arm(arr, 138 + lean, 116, 138 + lean, 130, C_DRED, C_MRED)
        knuckle(arr, 136 + lean, 128)

    # ── Left (cast) arm ──────────────────────────────────────────────────
    if fn == 0:
        hand_x, hand_y = 88 + lean, 96
        arm(arr, sh_x, sh_y,      sh_x - 2, 104, C_DRED, C_MRED)
        arm(arr, sh_x - 2, 104,   hand_x,   hand_y, C_MRED, C_ORANGE)
        knuckle(arr, hand_x, hand_y)
        magic_orb(arr, hand_x - 6, hand_y - 2, 6, 0)

    elif fn == 1:
        elbow_x, elbow_y = sh_x - 8, 108
        hand_x,  hand_y  = 72 + lean, 94
        arm(arr, sh_x, sh_y,      elbow_x, elbow_y, C_DRED, C_MRED)
        arm(arr, elbow_x, elbow_y, hand_x, hand_y,  C_MRED, C_ORANGE)
        knuckle(arr, hand_x, hand_y, glow=C_MGLOW2)
        magic_orb(arr, hand_x - 12, hand_y - 4, 12, 1)

    elif fn == 2:
        hand_x, hand_y = 62 + lean, 92
        arm(arr, sh_x, sh_y,       sh_x - 14, 96, C_MRED, C_ORANGE)
        arm(arr, sh_x - 14, 96,    hand_x,   hand_y, C_MRED, C_ORANGE)
        knuckle(arr, hand_x, hand_y, glow=C_MGLOW1)
        magic_orb(arr, hand_x - 18, hand_y - 4, 18, 2)

    elif fn == 3:
        hand_x, hand_y = 80 + lean, 96
        arm(arr, sh_x, sh_y,      sh_x - 6, 104, C_DRED, C_MRED)
        arm(arr, sh_x - 6, 104,   hand_x,   hand_y, C_MRED, C_ORANGE)
        knuckle(arr, hand_x, hand_y, glow=C_MGLOW3)
        magic_orb(arr, hand_x - 10, hand_y - 2, 10, 3)

    # Ground shadow
    for sx in range(82 + lean, 150 + lean, 2):
        pp(arr, sx, 162, C_PURPLE)

    return Image.fromarray(arr)


# ─── BUILD STRIPS & SAVE ─────────────────────────────────────────────────────

DEFEND_PATH = ("/home/struktured/projects/cowardly-irregular/"
               "assets/sprites/jobs/fighter/defend.png")
CAST_PATH   = ("/home/struktured/projects/cowardly-irregular/"
               "assets/sprites/jobs/fighter/cast.png")
TMP         = "/home/struktured/projects/cowardly-irregular/tmp"


def build_strip(frames):
    strip = Image.new("RGBA", (1024, 256), TRANSP)
    for i, f in enumerate(frames):
        strip.paste(f, (i * 256, 0))
    return strip


print("Generating DEFEND frames...")
defend_frames = [make_defend_frame(i) for i in range(4)]
defend_strip  = build_strip(defend_frames)

print("Generating CAST frames...")
cast_frames = [make_cast_frame(i) for i in range(4)]
cast_strip  = build_strip(cast_frames)

defend_strip.save(DEFEND_PATH)
cast_strip.save(CAST_PATH)
print(f"Saved {DEFEND_PATH}")
print(f"Saved {CAST_PATH}")

# Preview images
defend_strip.resize((4096, 1024), Image.NEAREST).save(f"{TMP}/defend_v4_4x.png")
cast_strip.resize((4096,   1024), Image.NEAREST).save(f"{TMP}/cast_v4_4x.png")

for fi, frame in enumerate(defend_frames):
    frame.resize((1024, 1024), Image.NEAREST).save(
        f"{TMP}/defend_f{fi+1}_v4_4x.png")
for fi, frame in enumerate(cast_frames):
    frame.resize((1024, 1024), Image.NEAREST).save(
        f"{TMP}/cast_f{fi+1}_v4_4x.png")

# ─── VALIDATION ──────────────────────────────────────────────────────────────
print("\n=== VALIDATION ===")
all_ok = True
for path, name in [(DEFEND_PATH, "defend"), (CAST_PATH, "cast")]:
    img  = Image.open(path)
    assert img.size == (1024, 256), f"Wrong size: {img.size}"
    assert img.mode == "RGBA",      f"Wrong mode: {img.mode}"
    farr = np.array(img)
    for fi in range(4):
        fm   = farr[:, fi * 256:(fi + 1) * 256, :]
        npx  = int((fm[:, :, 3] > 10).sum())
        # Legs (y=130-168) must have pixels — verifies no accidental leg erasure
        leg_px = int((fm[130:168, :, 3] > 10).sum())
        ok     = npx >= 3000 and leg_px >= 200
        if not ok:
            all_ok = False
        status = "PASS" if ok else "FAIL"
        print(f"  {name} f{fi+1}: total={npx:5d}  leg_px={leg_px:4d}  [{status}]")
    print(f"  {name}.png  size={img.size}")

assert all_ok, "One or more frames failed validation"
print("\nAll frames PASS.")
