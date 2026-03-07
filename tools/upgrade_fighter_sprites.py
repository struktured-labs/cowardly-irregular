#!/usr/bin/env python3
"""
Fighter sprite animation upgrade: expand frame counts for smoother animation.

Target frame counts (256x256 frames each):
  idle    : 2 → 4  (1024x256)
  walk    : 6 → 8  (2048x256)
  attack  : 6 → 8  (2048x256)
  hit     : 4 → 6  (1536x256)
  dead    : 4 → 6  (1536x256)
  cast    : 4 → 6  (1536x256)
  victory : 4 → 6  (1536x256)
  defend  : 4  (unchanged)
  item    : 4  (unchanged)

Strategy for pixel-art smoothness:
  - Insert 1-2 in-between frames between existing keyframes by shifting body
    parts only 2-3px and rotating the sword only 5-10 degrees per step.
  - Pixel art principle: NO color blending (destroys palette).
    Instead use integer-snapped offsets: lerp(a,b,t) -> round to nearest 2px.
  - The existing generators produce the keyframes; we insert tweened frames
    using the same pixel-manipulation primitives.
"""

import math
import sys
from pathlib import Path
import numpy as np
from PIL import Image

ASSET_DIR = Path("/home/struktured/projects/cowardly-irregular/assets/sprites/jobs/fighter")
IDLE_PATH = ASSET_DIR / "idle.png"
FRAME_W = 256
FRAME_H = 256

# ── Palette (exact from idle.png) ─────────────────────────────────────────────
TRANSPARENT = (0, 0, 0, 0)
C_OUTLINE   = (36, 34, 52, 255)
C_VDARK     = (34, 28, 26, 255)
C_DBROWN    = (50, 43, 40, 255)
C_CRIMSON   = (115, 23, 45, 255)
C_RUST      = (157, 49, 35, 255)
C_RED2      = (180, 32, 42, 255)
C_ORANGE    = (250, 106, 10, 255)
C_ORANGE2   = (249, 163, 27, 255)
C_METAL_DK  = (51, 57, 65, 255)
C_METAL     = (76, 78, 86, 255)
C_METAL_MD  = (93, 98, 110, 255)
C_SILVER    = (125, 129, 144, 255)
C_SILVER2   = (174, 179, 204, 255)
C_LEATHER   = (121, 103, 85, 255)
C_LEATHER2  = (160, 134, 98, 255)
C_SKIN_D    = (113, 65, 59, 255)
C_SKIN_M    = (187, 117, 71, 255)
C_SKIN_L    = (233, 181, 163, 255)
C_HAIR_D    = (34, 28, 26, 255)
C_HAIR      = (79, 53, 36, 255)
C_PURPLE_D  = (64, 51, 83, 255)

SWORD_STEEL = {
    (174, 179, 204), (125, 129, 144), (76, 78, 86),
    (93, 98, 110),   (51, 57, 65),    (54, 61, 77),
    (36, 34, 52),
}

# ── Load idle ─────────────────────────────────────────────────────────────────
_idle_img = Image.open(IDLE_PATH).convert("RGBA")
_idle_np  = np.array(_idle_img, dtype=np.uint8)
IDLE_F1   = _idle_np[:, :FRAME_W, :].copy()
IDLE_F2   = _idle_np[:, FRAME_W:FRAME_W*2, :].copy()

IDLE_SWORD_ANGLE = 218
IDLE_HILT_X = 136
IDLE_HILT_Y = 90
BODY_CX  = 103
HIP_Y    = 136
SHADOW_Y = 160

# ── Pixel helpers ─────────────────────────────────────────────────────────────
def pp(arr, x, y, color):
    """2x2 super-pixel."""
    if color[3] == 0:
        return
    for dy in range(2):
        for dx in range(2):
            px, py = x + dx, y + dy
            if 0 <= px < FRAME_W and 0 <= py < FRAME_H:
                arr[py, px] = color

def snap2(v):
    """Round to nearest even integer (2x2 pixel grid)."""
    return int(round(v / 2)) * 2

def lerp_snap(a, b, t):
    """Lerp and snap to 2px grid."""
    return snap2(a + (b - a) * t)

def lerp_angle(a, b, t):
    """Lerp angle with wrap-around handling."""
    diff = b - a
    while diff > 180: diff -= 360
    while diff < -180: diff += 360
    result = a + diff * t
    while result < 0: result += 360
    while result >= 360: result -= 360
    return result

# ── Sword renderer ────────────────────────────────────────────────────────────
def sword_at_angle(arr, hilt_x, hilt_y, angle_deg, blade_len=52):
    """Draw serrated broadsword from hilt in direction angle_deg."""
    rad = math.radians(angle_deg)
    bx = math.cos(rad)
    by = -math.sin(rad)
    px_ = -by
    py_ = bx
    steps = blade_len // 2
    for i in range(steps):
        t = i / max(steps - 1, 1)
        width = 3 if t < 0.15 else (2 if t < 0.85 else 1)
        cx = snap2(hilt_x + bx * i * 2)
        cy = snap2(hilt_y + by * i * 2)
        ox = snap2(px_ * (width + 1))
        oy = snap2(py_ * (width + 1))
        pp(arr, cx + ox, cy + oy, C_OUTLINE)
        pp(arr, cx - ox, cy - oy, C_OUTLINE)
        for w in range(-width + 1, width):
            bpx = snap2(cx + px_ * w)
            bpy = snap2(cy + py_ * w)
            c = (C_METAL if abs(w) == width - 1
                 else C_SILVER2 if w == 0
                 else C_SILVER if w > 0 else C_METAL_MD)
            pp(arr, bpx, bpy, c)
        if i % 5 == 2 and 2 < i < steps - 2:
            sx = snap2(cx + px_ * (width + 1))
            sy = snap2(cy + py_ * (width + 1))
            pp(arr, sx, sy, C_METAL_DK)
    # Crossguard
    gx, gy = hilt_x, hilt_y
    for k in range(-7, 8, 2):
        kx = snap2(gx + px_ * k)
        ky = snap2(gy + py_ * k)
        c = (C_SILVER2 if abs(k) <= 2 else C_SILVER if abs(k) <= 4 else C_METAL)
        pp(arr, kx, ky, c)
    pp(arr, snap2(gx + px_ * -8), snap2(gy + py_ * -8), C_OUTLINE)
    pp(arr, snap2(gx + px_ * 8),  snap2(gy + py_ * 8),  C_OUTLINE)
    # Handle
    for i in range(1, 6):
        hpx = snap2(hilt_x - bx * i * 2)
        hpy = snap2(hilt_y - by * i * 2)
        c = C_LEATHER if i % 2 == 0 else C_DBROWN
        pp(arr, hpx - 2, hpy, c)
        pp(arr, hpx,     hpy, c)
    # Pommel
    ppx = snap2(hilt_x - bx * 12)
    ppy = snap2(hilt_y - by * 12)
    pp(arr, ppx - 2, ppy,     C_METAL)
    pp(arr, ppx,     ppy,     C_METAL)
    pp(arr, ppx - 2, ppy + 2, C_OUTLINE)
    pp(arr, ppx,     ppy + 2, C_OUTLINE)


def shadow_row(arr, cx, y, half_w, alpha=72):
    for sx in range(-half_w, half_w + 1, 2):
        fade = 1.0 - (abs(sx) / half_w) ** 1.3
        a = int(alpha * max(0, fade))
        for off in range(0, 4, 2):
            nx, ny = cx + sx, y + off
            if 0 <= nx < FRAME_W and 0 <= ny < FRAME_H:
                if arr[ny, nx, 3] < 10:
                    arr[ny, nx] = (36, 34, 52, a)


def _erase_sword(arr):
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
            g = non_trans[i+1] - non_trans[i]
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
                    if 0 <= x+ddx < FRAME_W and 0 <= y+ddy < FRAME_H
                    and arr[y+ddy, x+ddx, 3] > 10
                )
                if neighbors <= 1:
                    arr[y, x] = TRANSPARENT


_base_nosword = IDLE_F1.copy()
_erase_sword(_base_nosword)


def fresh_frame():
    return _base_nosword.copy()


def _shift_body(arr, dx, dy, upper_only=False):
    """Shift entire body (or just upper body) by (dx, dy) pixels."""
    shifted = np.zeros_like(arr)
    if upper_only:
        shifted[136:] = arr[136:]
        y0_src = max(66, 66 - dy)
        y1_src = min(136, 136 - dy)
        y0_dst = max(66, 66 + dy)
        y1_dst = min(136, 136 + dy)
        x0_src = max(0, -dx)
        x1_src = min(FRAME_W, FRAME_W - dx)
        x0_dst = max(0, dx)
        x1_dst = min(FRAME_W, FRAME_W + dx)
        copy_h = min(y1_src - y0_src, y1_dst - y0_dst, 70)
        copy_w = min(x1_src - x0_src, x1_dst - x0_dst, FRAME_W)
        if copy_h > 0 and copy_w > 0:
            shifted[y0_dst:y0_dst+copy_h, x0_dst:x0_dst+copy_w] = \
                arr[y0_src:y0_src+copy_h, x0_src:x0_src+copy_w]
    else:
        x0_src = max(0, -dx)
        dst_x  = max(0, dx)
        cw     = min(FRAME_W - abs(dx), FRAME_W)
        y0_src = max(0, -dy)
        dst_y  = max(0, dy)
        ch     = min(FRAME_H - abs(dy), FRAME_H)
        if ch > 0 and cw > 0:
            shifted[dst_y:dst_y+ch, dst_x:dst_x+cw] = \
                arr[y0_src:y0_src+ch, x0_src:x0_src+cw]
    return shifted


# ════════════════════════════════════════════════════════════════════════════
# IDLE — expand 2 → 4 frames
# ════════════════════════════════════════════════════════════════════════════
# Existing:  F0=base, F1=bob up 1px
# New:       F0=base, F1=half-bob (0.5px→snap to 0, add subtle sword sway)
#            F2=full bob, F3=return halfway
# Each transition: 1px body bob, sword sways ±3° from idle

def generate_idle():
    """
    4-frame idle with breathing cycle and subtle sword sway.

    Built using the walk frame generator (which renders cleanly from extracted
    body part pixels) at zero stride so legs are centered. Bob varies 0→-1→-2→-1
    for a smooth breathing cycle, and the sword sways ±3-5° per step.

    F0: rest (bob=0, sword at idle angle 218°)
    F1: rise phase 1 (bob=-1, sword sways to 221°)
    F2: peak (bob=-2, sword sways to 223°)
    F3: descend (bob=-1, sword returns to 221°)
    """
    # At zero stride both legs sit at BODY_CX (centered). We use the right leg
    # as "front" at centre — this matches the walk neutral-cross frame appearance.
    bob_levels   = [0, -1, -2, -1]
    sword_angles = [IDLE_SWORD_ANGLE, IDLE_SWORD_ANGLE + 3,
                    IDLE_SWORD_ANGLE + 5, IDLE_SWORD_ANGLE + 3]
    frames = []
    for bob, sword_ang in zip(bob_levels, sword_angles):
        arr = np.zeros((FRAME_H, FRAME_W, 4), dtype=np.uint8)
        # Back leg (darken slightly)
        blit_pixels(arr, _ll_norm, dx=BODY_CX - _ll_w//2,
                    dy=HIP_Y + bob, darken=DARK)
        # Upper body (includes sword steel at idle angle — drawn then overwritten)
        blit_pixels(arr, _upper_body, dx=0, dy=bob)
        # Front leg (full brightness, overlaps body bottom)
        blit_pixels(arr, _rl_norm, dx=BODY_CX - _rl_w//2,
                    dy=HIP_Y + bob, darken=1.0)
        # Ground shadow (narrow — no stride width)
        shadow_row(arr, BODY_CX, SHADOW_Y + bob, 20)
        # The upper_body blit includes the idle sword pixels (steel colors).
        # Erase only the specific steel-exclusive colors that never appear on
        # the body — exclude C_OUTLINE=(36,34,52) which is shared with body edges.
        # Target only the blade's unique colors in the lower-left blade zone.
        BLADE_ONLY = {(174, 179, 204), (125, 129, 144), (93, 98, 110),
                      (51, 57, 65), (76, 78, 86)}
        for y in range(100, FRAME_H):
            for x in range(40, 160):
                r, g, b, a = arr[y, x]
                if a > 10 and (r, g, b) in BLADE_ONLY:
                    arr[y, x] = TRANSPARENT
        sword_at_angle(arr, IDLE_HILT_X, IDLE_HILT_Y + bob, sword_ang, 52)
        frames.append(Image.fromarray(arr, 'RGBA'))

    strip = Image.new("RGBA", (FRAME_W * 4, FRAME_H), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * FRAME_W, 0))
    return strip


# ════════════════════════════════════════════════════════════════════════════
# WALK — expand 6 → 8 frames (add half-step frames for smoother stride)
# ════════════════════════════════════════════════════════════════════════════

def extract_pixels(arr, y0, y1, x0=0, x1=255):
    result = []
    for row in range(y0, min(y1+1, FRAME_H)):
        for col in range(x0, min(x1+1, FRAME_W)):
            px = tuple(arr[row, col])
            if px[3] > 10:
                result.append((col, row, px))
    return result

def blit_pixels(arr, pixels, dx=0, dy=0, darken=1.0):
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
    if not pixels:
        return [], 0, 0
    min_x = min(p[0] for p in pixels)
    min_y = min(p[1] for p in pixels)
    normed = [(x - min_x, y - min_y, c) for x, y, c in pixels]
    return normed, min_x, min_y

# Extract leg parts from idle for walk
_upper_body = extract_pixels(IDLE_F1, 66, 135, 0, 255)
_left_leg_raw  = extract_pixels(IDLE_F1, 136, 163, 60, 116)
_left_leg      = [(x, y, c) for x, y, c in _left_leg_raw
                  if tuple(c[:3]) not in SWORD_STEEL]
_right_leg_raw = extract_pixels(IDLE_F1, 136, 163, 90, 155)

_ll_norm, _ll_ox, _ll_oy = normalize_pixels(_left_leg)
_rl_norm, _rl_ox, _rl_oy = normalize_pixels(_right_leg_raw)
_ll_w = max(p[0] for p in _ll_norm) + 1 if _ll_norm else 1
_rl_w = max(p[0] for p in _rl_norm) + 1 if _rl_norm else 1

DARK   = 0.52
STRIDE = 14

def get_leg(t): return _ll_norm if t == 'll' else _rl_norm
def get_lw(t):  return _ll_w    if t == 'll' else _rl_w


def _gen_walk_frame(front_type, front_cx, back_type, back_cx, bob):
    arr = np.zeros((FRAME_H, FRAME_W, 4), dtype=np.uint8)
    fw = get_lw(front_type)
    bw = get_lw(back_type)
    fox = front_cx - fw // 2
    box = back_cx - bw // 2
    blit_pixels(arr, get_leg(back_type),  dx=box, dy=HIP_Y + bob, darken=DARK)
    blit_pixels(arr, _upper_body,          dx=0,   dy=bob)
    blit_pixels(arr, get_leg(front_type), dx=fox, dy=HIP_Y + bob, darken=1.0)
    shadow_row(arr, BODY_CX, SHADOW_Y + bob, 20 + abs(front_cx - back_cx) // 3)
    return Image.fromarray(arr, 'RGBA')


def generate_walk():
    """
    8-frame walk cycle. Existing 6 frames had pattern:
      F0: right fwd (stride)
      F1: mid (body up)
      F2: left fwd (stride)
      F3: mid (body up)
      F4, F5: repeat

    New 8-frame cycle inserts half-stride frames between each major pose:
      F0: right fwd full stride
      F1: quarter-stride transition
      F2: mid (body up, feet cross)
      F3: left fwd full stride
      F4: quarter-stride transition (mirror)
      F5: mid (body up, feet cross mirror)
      F6: right fwd full stride again (cycle)
      F7: quarter-stride transition

    This creates a complete 8-frame walk loop with smoother leg movement.
    """
    S = STRIDE
    Q = STRIDE // 2  # quarter stride

    # (front_type, front_cx, back_type, back_cx, bob)
    walk_data = [
        ('ll', BODY_CX - S,     'rl', BODY_CX + S,     0),   # F0: left leg fwd full
        ('ll', BODY_CX - Q,     'rl', BODY_CX + Q,    -1),   # F1: transition in (half-step)
        ('ll', BODY_CX - Q//2,  'rl', BODY_CX + Q//2, -2),   # F2: mid, body up
        ('rl', BODY_CX - S,     'll', BODY_CX + S,     0),   # F3: right leg fwd full
        ('rl', BODY_CX - Q,     'll', BODY_CX + Q,    -1),   # F4: transition
        ('rl', BODY_CX - Q//2,  'll', BODY_CX + Q//2, -2),   # F5: mid, body up (mirror)
        ('ll', BODY_CX - S,     'rl', BODY_CX + S,     0),   # F6: left fwd again (loop)
        ('ll', BODY_CX - Q,     'rl', BODY_CX + Q,    -1),   # F7: transition
    ]

    frames = [_gen_walk_frame(*d) for d in walk_data]
    strip = Image.new("RGBA", (FRAME_W * 8, FRAME_H), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * FRAME_W, 0))
    return strip


# ════════════════════════════════════════════════════════════════════════════
# ATTACK — expand 6 → 8 frames
# ════════════════════════════════════════════════════════════════════════════
# Original 6: F0 windup-start, F1 windup-peak, F2 swing-start, F3 slash-peak,
#             F4 follow-through, F5 recovery
# New 8:      Add tween between F1→F2 and F3→F4 (the two sharpest transitions)
# F0: windup begins  (160°, body 0,-2)
# F1: windup halfway (130°, body -1,-2.5)
# F2: windup peak    (110°, body -2,-3)
# F3: swing starts   (60°,  body 2,-1)
# F4: slash mid      (30°,  body 3,0)
# F5: slash peak     (15°,  body 4,0)
# F6: follow-through (-25°, body 3,1)
# F7: recovery       (210°, body 1,0)

_attack_frames_data_8 = [
    # (body_dx, body_dy, hilt_x, hilt_y, sword_angle, blade_len)
    (0,  -2,  134, 82,  160, 50),   # F0: windup begins
    (-1, -2,  131, 79,  130, 51),   # F1: windup halfway (new tween)
    (-2, -3,  128, 76,  110, 52),   # F2: windup peak
    (2,  -1,  132, 80,   60, 52),   # F3: swing starts
    (3,   0,  135, 84,   30, 53),   # F4: slash mid (new tween)
    (4,   0,  138, 88,   15, 54),   # F5: slash peak
    (3,   1,  136, 96,  -25, 54),   # F6: follow-through
    (1,   0,  136, 90,  210, 52),   # F7: recovery
]


def _gen_attack_frame(fdata):
    body_dx, body_dy, hilt_x, hilt_y, sword_angle, blade_len = fdata
    arr = IDLE_F1.copy()
    if body_dx != 0 or body_dy != 0:
        shifted = np.zeros_like(arr)
        src_y0 = max(66, 66 - body_dy)
        src_y1 = min(136, 136 - body_dy)
        dst_y0 = max(66, 66 + body_dy)
        dst_y1 = min(136, 136 + body_dy)
        src_x0 = max(0, -body_dx)
        src_x1 = min(FRAME_W, FRAME_W - body_dx)
        dst_x0 = max(0, body_dx)
        dst_x1 = min(FRAME_W, FRAME_W + body_dx)
        copy_h = min(src_y1 - src_y0, dst_y1 - dst_y0, 70)
        copy_w = min(src_x1 - src_x0, dst_x1 - dst_x0, FRAME_W)
        if copy_h > 0 and copy_w > 0:
            shifted[136:] = arr[136:]
            shifted[dst_y0:dst_y0+copy_h, dst_x0:dst_x0+copy_w] = \
                arr[src_y0:src_y0+copy_h, src_x0:src_x0+copy_w]
            arr = shifted
        shadow_row(arr, BODY_CX + body_dx // 2, SHADOW_Y, 22)
    else:
        shadow_row(arr, BODY_CX, SHADOW_Y, 22)
    # Erase idle sword steel that would conflict
    _erase_sword(arr)
    sword_at_angle(arr, hilt_x + body_dx, hilt_y + body_dy, sword_angle, blade_len)
    return Image.fromarray(arr, 'RGBA')


def generate_attack():
    frames = [_gen_attack_frame(fd) for fd in _attack_frames_data_8]
    strip = Image.new("RGBA", (FRAME_W * 8, FRAME_H), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * FRAME_W, 0))
    return strip


# ════════════════════════════════════════════════════════════════════════════
# HIT — expand 4 → 6 frames
# ════════════════════════════════════════════════════════════════════════════
# Original 4: F0 impact, F1 max-recoil, F2 recovery, F3 steady
# New 6:      F0 pre-impact(0), F1 impact, F2 max-recoil, F3 recovery-start,
#             F4 recovery-mid, F5 steady
# This gives: subtle anticipation → snap → peak → smooth multi-step recovery

_hit_frames_data_6 = [
    # (body_dx, body_dy, hilt_x, hilt_y, sword_angle, blade_len)
    (1,   0,  137, 91,  212, 50),   # F0: pre-impact micro-lean (new)
    (4,   1,  140, 94,  200, 50),   # F1: impact
    (6,   2,  142, 98,  195, 48),   # F2: max recoil
    (4,   1,  140, 94,  200, 50),   # F3: recovery start (mirror of F1)
    (2,   0,  137, 91,  208, 51),   # F4: recovery mid (new tween)
    (1,   0,  136, 90,  215, 52),   # F5: almost idle
]


def _gen_hit_frame(fdata):
    body_dx, body_dy, hilt_x, hilt_y, sword_angle, blade_len = fdata
    arr = IDLE_F1.copy()
    if body_dx != 0 or body_dy != 0:
        shifted = np.zeros_like(arr)
        src_x0 = max(0, -body_dx)
        dst_x0 = max(0, body_dx)
        cw = min(FRAME_W - abs(body_dx), FRAME_W)
        src_y0 = max(0, -body_dy)
        dst_y0 = max(0, body_dy)
        ch = min(FRAME_H - abs(body_dy), FRAME_H)
        if ch > 0 and cw > 0:
            shifted[dst_y0:dst_y0+ch, dst_x0:dst_x0+cw] = \
                arr[src_y0:src_y0+ch, src_x0:src_x0+cw]
        arr = shifted
    shadow_row(arr, BODY_CX + body_dx // 2, SHADOW_Y + body_dy // 2, 22)
    _erase_sword(arr)
    sword_at_angle(arr, hilt_x + body_dx, hilt_y + body_dy, sword_angle, blade_len)
    return Image.fromarray(arr, 'RGBA')


def generate_hit():
    frames = [_gen_hit_frame(fd) for fd in _hit_frames_data_6]
    strip = Image.new("RGBA", (FRAME_W * 6, FRAME_H), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * FRAME_W, 0))
    return strip


# ════════════════════════════════════════════════════════════════════════════
# DEAD — expand 4 → 6 frames
# ════════════════════════════════════════════════════════════════════════════
# Original 4: F0 buckle(15°), F1 falling(40°), F2 collapse(70°), F3 prone(85°)
# New 6:      Insert tween between each major step:
#   F0: stagger(15°)
#   F1: fall early(27°)  [new tween between F0→F1]
#   F2: falling(40°)
#   F3: collapse early(55°) [new tween between F2→F3]
#   F4: collapse(70°)
#   F5: prone(85°)

_dead_frames_data_6 = [
    # (tilt_deg, slide_x, slide_y, shadow_x, blade_len)
    (15,   2,  4,  170, 50),   # F0: buckle
    (27,   5,  6,  165, 48),   # F1: early fall (new tween)
    (40,   8,  8,  160, 46),   # F2: falling
    (55,  14, 11,  152, 43),   # F3: collapse early (new tween)
    (70,  20, 14,  145, 40),   # F4: collapse
    (85,  28, 20,  130, 36),   # F5: prone
]

_FOOT_X = 110
_FOOT_Y = 162

def _gen_dead_frame(fdata, frame_idx):
    tilt, slide_x, slide_y, shadow_x, blade_len = fdata
    arr = np.zeros((FRAME_H, FRAME_W, 4), dtype=np.uint8)
    _full_body = extract_pixels(IDLE_F1, 66, 163, 50, 155)
    piv_x = _FOOT_X + slide_x
    piv_y = _FOOT_Y - slide_y // 2
    rad = math.radians(tilt)
    cos_a, sin_a = math.cos(rad), math.sin(rad)
    for x, y, c in _full_body:
        rx = x - _FOOT_X
        ry = y - _FOOT_Y
        nx = snap2(rx * cos_a - ry * sin_a + piv_x)
        ny = snap2(rx * sin_a + ry * cos_a + piv_y)
        if 0 <= nx < FRAME_W - 1 and 0 <= ny < FRAME_H - 1:
            arr[ny, nx] = c
            arr[ny+1, nx] = c
            arr[ny, nx+1] = c
            arr[ny+1, nx+1] = c
    # Rotated sword hilt
    rhx = IDLE_HILT_X - _FOOT_X
    rhy = IDLE_HILT_Y - _FOOT_Y
    nhx = snap2(rhx * cos_a - rhy * sin_a + piv_x)
    nhy = snap2(rhx * sin_a + rhy * cos_a + piv_y)
    sword_tilt = tilt * 0.8
    sword_angle_final = IDLE_SWORD_ANGLE + sword_tilt
    if 0 <= nhx < FRAME_W and 0 <= nhy < FRAME_H:
        sword_at_angle(arr, nhx, nhy, sword_angle_final, blade_len)
    if frame_idx < 5:
        shadow_row(arr, shadow_x, SHADOW_Y - slide_y // 3, 16 + tilt // 4)
    else:
        shadow_row(arr, shadow_x + 15, SHADOW_Y, 35)
    return Image.fromarray(arr, 'RGBA')


def generate_dead():
    frames = [_gen_dead_frame(fd, i) for i, fd in enumerate(_dead_frames_data_6)]
    strip = Image.new("RGBA", (FRAME_W * 6, FRAME_H), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * FRAME_W, 0))
    return strip


# ════════════════════════════════════════════════════════════════════════════
# CAST — expand 4 → 6 frames
# ════════════════════════════════════════════════════════════════════════════
# We rebuild cast inline using the same approach as gen_fighter_defend_cast.py
# but with 6 frames:
#  F0: stance (no magic)
#  F1: hand rising, tiny spark (new)
#  F2: orb growing (was F1)
#  F3: full orb (was F2, peak)
#  F4: orb released, arm extended, fading ring (new tween)
#  F5: recovery, faint ring (was F3)

# Import the cast generation logic inline
def _make_cast_frame_6(fn, BASE_NO_SWORD_CAST, pp_fn):
    """6-frame cast animation."""
    import math
    C_OUTLINE_L = (36, 34, 52, 255)
    C_MRED = (157, 49, 35, 255)
    C_DRED = (115, 23, 45, 255)
    C_MGLOW1 = (96, 160, 255, 255)
    C_MGLOW2 = (160, 200, 255, 255)
    C_MGLOW3 = (208, 232, 255, 255)
    C_MSPARK = (255, 255, 160, 255)
    C_WHITE  = (255, 255, 255, 255)
    C_PURPLE = (64, 51, 83, 255)
    C_SKIN_D = (113, 65, 59, 255)
    C_SKIN_M = (187, 117, 71, 255)
    C_SKIN_L = (233, 181, 163, 255)
    TRANSP   = (0, 0, 0, 0)

    def local_arm(arr, x0, y0, x1, y1, c_main, c_hi):
        dx, dy = x1-x0, y1-y0
        dist = math.hypot(dx, dy)
        if dist < 1: return
        nx, ny = -dy/dist, dx/dist
        steps = max(int(dist/2)+1, 2)
        for i in range(steps):
            t = i/(steps-1)
            cx = snap2(x0 + t*dx)
            cy = snap2(y0 + t*dy)
            ox = snap2(nx*4); oy = snap2(ny*4)
            mx = snap2(nx*2); my = snap2(ny*2)
            pp_fn(arr, cx+ox, cy+oy, C_OUTLINE_L)
            pp_fn(arr, cx+mx, cy+my, c_main)
            pp_fn(arr, cx,    cy,    c_hi)
            pp_fn(arr, cx-mx, cy-my, c_main)
            pp_fn(arr, cx-ox, cy-oy, C_OUTLINE_L)

    def local_knuckle(arr, fx, fy, glow=None):
        pp_fn(arr, fx-2, fy-2, C_OUTLINE_L)
        pp_fn(arr, fx,   fy-2, C_SKIN_L)
        pp_fn(arr, fx+2, fy-2, C_OUTLINE_L)
        pp_fn(arr, fx-2, fy,   C_SKIN_D)
        pp_fn(arr, fx,   fy,   C_SKIN_M)
        pp_fn(arr, fx+2, fy,   C_SKIN_D)
        pp_fn(arr, fx-2, fy+2, C_OUTLINE_L)
        pp_fn(arr, fx,   fy+2, C_SKIN_D)
        pp_fn(arr, fx+2, fy+2, C_OUTLINE_L)
        if glow is not None:
            for ox, oy in [(-4,0),(6,0),(0,-4),(0,6),(-4,-4),(6,-4),(-4,6),(6,6)]:
                gx, gy = fx+ox, fy+oy
                if 0 <= gx < 256 and 0 <= gy < 256:
                    arr[gy, gx] = glow

    def local_orb(arr, cx, cy, radius, stage):
        if stage == 0:  # tiny spark
            pp_fn(arr, cx, cy, C_WHITE)
            pp_fn(arr, cx-2, cy, C_MGLOW3)
            pp_fn(arr, cx+2, cy, C_MGLOW3)
            pp_fn(arr, cx, cy-2, C_MGLOW3)
            pp_fn(arr, cx, cy+2, C_MGLOW3)
        elif stage == 1:  # small growing orb
            r = radius
            for dy in range(-r, r+1, 2):
                for dx in range(-r, r+1, 2):
                    d = math.hypot(dx, dy)
                    if d > r: continue
                    col = (C_WHITE if d < r*0.4 else C_MGLOW3 if d < r*0.7 else C_MGLOW2)
                    pp_fn(arr, cx+dx, cy+dy, col)
            for angle in range(0, 360, 60):
                ax = snap2(cx + (r+2)*math.cos(math.radians(angle)))
                ay = snap2(cy + (r+2)*math.sin(math.radians(angle)))
                pp_fn(arr, ax, ay, C_MGLOW1)
        elif stage == 2:  # full gathering orb
            r = radius
            for dy in range(-r, r+1, 2):
                for dx in range(-r, r+1, 2):
                    d = math.hypot(dx, dy)
                    if d > r: continue
                    col = (C_WHITE if d < r*0.35
                           else C_MGLOW3 if d < r*0.65 else C_MGLOW2)
                    pp_fn(arr, cx+dx, cy+dy, col)
            for angle in range(0, 360, 30):
                ax = snap2(cx + (r+4)*math.cos(math.radians(angle)))
                ay = snap2(cy + (r+4)*math.sin(math.radians(angle)))
                pp_fn(arr, ax, ay, C_MGLOW1)
        elif stage == 3:  # full blast
            r = radius
            for dy in range(-r, r+1, 2):
                for dx in range(-r, r+1, 2):
                    d = math.hypot(dx, dy)
                    if d > r: continue
                    col = (C_WHITE if d < r*0.25
                           else C_MSPARK if d < r*0.5
                           else C_MGLOW3 if d < r*0.75 else C_MGLOW2)
                    pp_fn(arr, cx+dx, cy+dy, col)
            for angle in range(0, 360, 45):
                for dist in range(r+2, r+26, 2):
                    ax = snap2(cx + dist*math.cos(math.radians(angle)))
                    ay = snap2(cy + dist*math.sin(math.radians(angle)))
                    fade = max(0, 240 - (dist-r)*10)
                    if fade > 0 and 0 <= ax < 256 and 0 <= ay < 256:
                        arr[ay, ax] = (C_MGLOW1[0], C_MGLOW1[1], C_MGLOW1[2], fade)
        elif stage == 4:  # released - shrinking corona
            r = radius
            ri = max(2, r - 4)
            for dy in range(-r, r+1, 2):
                for dx in range(-r, r+1, 2):
                    d = math.hypot(dx, dy)
                    if ri <= d <= r:
                        px_c, py_c = cx+dx, cy+dy
                        fade = int(200 * (1 - (d-ri)/max(r-ri, 1)))
                        if 0 <= px_c < 256 and 0 <= py_c < 256:
                            arr[py_c, px_c] = (C_MGLOW2[0], C_MGLOW2[1], C_MGLOW2[2], fade)
        elif stage == 5:  # fading ring
            r = radius
            ri = max(2, r - 6)
            for dy in range(-r, r+1, 2):
                for dx in range(-r, r+1, 2):
                    d = math.hypot(dx, dy)
                    if ri <= d <= r:
                        px_c, py_c = cx+dx, cy+dy
                        fade = int(130 * (1 - (d-ri)/max(r-ri, 1)))
                        if 0 <= px_c < 256 and 0 <= py_c < 256:
                            arr[py_c, px_c] = (C_MGLOW2[0], C_MGLOW2[1], C_MGLOW2[2], fade)

    arr = BASE_NO_SWORD_CAST.copy()
    SWORD_ONLY_RGB = {(51,57,65),(76,78,86),(93,98,110),(125,129,144),(174,179,204),(54,61,77)}

    # Sword-down helper (lowered left arm with sword pointing down)
    def sword_angled_down_local(arr, hx, hy, length=50):
        steps = length // 2
        for i in range(steps):
            bx, by = hx - i, hy + i*2
            pp_fn(arr, bx,     by-2, C_OUTLINE_L)
            pp_fn(arr, bx-2,   by,   (51,57,65,255))
            pp_fn(arr, bx,     by,   (76,78,86,255))
            pp_fn(arr, bx+2,   by,   (125,129,144,255))
        for gx in range(hx-8, hx+12, 2):
            pp_fn(arr, gx, hy-2, (76,78,86,255))
        pp_fn(arr, hx-8, hy-2, (51,57,65,255))
        pp_fn(arr, hx+10, hy-2, (51,57,65,255))
        pp_fn(arr, hx, hy-4, C_DBROWN)
        pp_fn(arr, hx+2, hy-4, C_DBROWN)

    # Frame-specific lean values
    lean_map = [0, 1, 2, 4, 3, 2]
    lean = lean_map[min(fn, 5)]
    sh_x = 92 + lean
    sh_y = 100

    # Right arm (sword arm lowered)
    if fn == 0:
        # Frame 0: sword at diagonal, transitioning down
        local_arm(arr, 140+lean, 96, 126+lean, 112, C_MRED, C_ORANGE)
        local_arm(arr, 126+lean, 112, 110+lean, 126, C_DRED, C_MRED)
        local_knuckle(arr, 108+lean, 124)
        sword_at_angle(arr, 110+lean, 126, 160, 48)
    else:
        sword_angled_down_local(arr, hx=138+lean, hy=130, length=50)
        local_arm(arr, 140+lean, 96, 138+lean, 116, C_DRED, C_MRED)
        local_arm(arr, 138+lean, 116, 138+lean, 130, C_DRED, C_MRED)
        local_knuckle(arr, 136+lean, 128)

    # Left (cast) arm and magic effect
    if fn == 0:
        # Stance: arm at rest, no magic
        hand_x, hand_y = 90+lean, 100
        local_arm(arr, sh_x, sh_y, sh_x-2, 104, C_DRED, C_MRED)
        local_arm(arr, sh_x-2, 104, hand_x, hand_y, C_MRED, C_ORANGE)
        local_knuckle(arr, hand_x, hand_y)
    elif fn == 1:
        # Rising hand, tiny spark
        hand_x, hand_y = 88+lean, 96
        local_arm(arr, sh_x, sh_y, sh_x-2, 104, C_DRED, C_MRED)
        local_arm(arr, sh_x-2, 104, hand_x, hand_y, C_MRED, C_ORANGE)
        local_knuckle(arr, hand_x, hand_y)
        local_orb(arr, hand_x-6, hand_y-2, 6, 0)
    elif fn == 2:
        # Hand extended, orb growing
        elbow_x, elbow_y = sh_x-8, 108
        hand_x, hand_y = 72+lean, 94
        local_arm(arr, sh_x, sh_y, elbow_x, elbow_y, C_DRED, C_MRED)
        local_arm(arr, elbow_x, elbow_y, hand_x, hand_y, C_MRED, C_ORANGE)
        local_knuckle(arr, hand_x, hand_y, glow=C_MGLOW2)
        local_orb(arr, hand_x-12, hand_y-4, 12, 2)
    elif fn == 3:
        # Full cast / blast
        hand_x, hand_y = 62+lean, 92
        local_arm(arr, sh_x, sh_y, sh_x-14, 96, C_MRED, C_ORANGE)
        local_arm(arr, sh_x-14, 96, hand_x, hand_y, C_MRED, C_ORANGE)
        local_knuckle(arr, hand_x, hand_y, glow=C_MGLOW1)
        local_orb(arr, hand_x-18, hand_y-4, 18, 3)
    elif fn == 4:
        # Just released - orb expanding corona
        hand_x, hand_y = 65+lean, 92
        local_arm(arr, sh_x, sh_y, sh_x-12, 97, C_MRED, C_ORANGE)
        local_arm(arr, sh_x-12, 97, hand_x, hand_y, C_MRED, C_ORANGE)
        local_knuckle(arr, hand_x, hand_y, glow=C_MGLOW2)
        local_orb(arr, hand_x-16, hand_y-4, 14, 4)
    elif fn == 5:
        # Follow-through, fading ring
        hand_x, hand_y = 80+lean, 96
        local_arm(arr, sh_x, sh_y, sh_x-6, 104, C_DRED, C_MRED)
        local_arm(arr, sh_x-6, 104, hand_x, hand_y, C_MRED, C_ORANGE)
        local_knuckle(arr, hand_x, hand_y, glow=C_MGLOW3)
        local_orb(arr, hand_x-10, hand_y-2, 10, 5)

    # Ground shadow
    for sx in range(82+lean, 150+lean, 2):
        pp_fn(arr, sx, 162, C_PURPLE_D)

    return Image.fromarray(arr)


def generate_cast():
    base = IDLE_F1.copy()
    _erase_sword(base)
    SWORD_ONLY_RGB = {(51,57,65),(76,78,86),(93,98,110),(125,129,144),(174,179,204),(54,61,77)}
    frames = [_make_cast_frame_6(i, base, pp) for i in range(6)]
    strip = Image.new("RGBA", (FRAME_W * 6, FRAME_H), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * FRAME_W, 0))
    return strip


# ════════════════════════════════════════════════════════════════════════════
# VICTORY — expand 4 → 6 frames
# ════════════════════════════════════════════════════════════════════════════
# Original 4: F0 arm starts rising (sword 60°), F1 mid-raise (25°),
#             F2 full extension (4°, glow), F3 hold with bounce
# New 6:      F0 just starting (90°, no glow), F1 mid-way (50°),
#             F2 near-vertical (25°), F3 full extension peak (4°, glow),
#             F4 slight bounce (8°, glow), F5 hold extended (6°, glow sustained)

def _gen_victory_frame_6(idle_frame, arm_mask, frame_idx):
    """6-frame victory animation with smoother sword raise arc."""
    import math as _math
    C_RED   = (157, 49, 35, 255)
    C_RED2  = (180, 32, 42, 255)
    C_CRIMSON = (115, 23, 45, 255)
    C_ORANGE_V = (250, 106, 10, 255)
    C_ORANGE2V = (249, 163, 27, 255)
    C_ITEM_GLOW = (254, 243, 192, 255)
    C_SILVER_V  = (125, 129, 144, 255)
    C_SILVER2_V = (174, 179, 204, 255)
    C_METAL_V   = (76, 78, 86, 255)
    C_HAIR_V    = (79, 53, 36, 255)
    C_LEATHER_V = (160, 134, 98, 255)
    C_LEATHER2_V = (228, 210, 170, 255)

    out = idle_frame.copy()
    out_arr = np.array(out)
    for row in range(256):
        for col in range(256):
            if arm_mask[row, col]:
                out_arr[row, col] = [0, 0, 0, 0]
    out = Image.fromarray(out_arr)

    shoulder_x = 98
    shoulder_y = 92

    # Sword raise arc: 90° → 50° → 25° → 4° → 8° → 6°
    arc = [
        (90,  32, False),  # F0: arm barely started
        (50,  36, False),  # F1: mid raise
        (25,  40, False),  # F2: near vertical
        (4,   44, True),   # F3: full extension, glow on
        (8,   44, True),   # F4: slight bounce
        (6,   44, True),   # F5: hold
    ]
    sword_angle, blade_len, add_glow = arc[frame_idx]

    # Elbow and hand positions along the raise arc (interpolated)
    elbow_positions = [
        (shoulder_x+20, shoulder_y+6),   # F0: arm low-right
        (shoulder_x+15, shoulder_y+0),   # F1
        (shoulder_x+10, shoulder_y-12),  # F2
        (shoulder_x+3,  shoulder_y-20),  # F3
        (shoulder_x+3,  shoulder_y-20),  # F4 same
        (shoulder_x+3,  shoulder_y-20),  # F5 same
    ]
    hand_positions = [
        (shoulder_x+32, shoulder_y-8),   # F0
        (shoulder_x+24, shoulder_y-22),  # F1
        (shoulder_x+10, shoulder_y-34),  # F2
        (shoulder_x+4,  shoulder_y-40),  # F3
        (shoulder_x+4,  shoulder_y-38),  # F4 bounce
        (shoulder_x+4,  shoulder_y-40),  # F5
    ]

    elbow_x, elbow_y = elbow_positions[frame_idx]
    hand_x, hand_y = hand_positions[frame_idx]

    if frame_idx == 5:
        # hold frame: slight whole-body bounce
        bounced = Image.new("RGBA", (256, 256), TRANSPARENT)
        bounced.paste(out, (0, -4))
        out = bounced
        shoulder_y -= 4
        elbow_x, elbow_y = elbow_x, elbow_y - 4
        hand_x, hand_y = hand_x, hand_y - 4

    # Draw arm
    def _draw_victory_arm_simple(img, sx, sy, ex, ey, hx, hy, sang, blen, glow):
        # Shoulder pauldron
        from PIL import ImageDraw
        draw = ImageDraw.Draw(img)
        draw.rectangle([sx-4, sy-3, sx+5, sy+3], fill=C_RED)
        for x_i in range(sx-3, sx+5):
            img.putpixel((x_i, sy-4), C_ORANGE_V)
        # Upper arm
        _draw_segment(img, sx, sy, ex, ey, C_RED, C_CRIMSON, C_ORANGE_V, 6)
        # Elbow
        draw.rectangle([ex-3, ey-3, ex+3, ey+3], fill=C_RED)
        img.putpixel((ex, ey), C_ORANGE_V)
        # Forearm
        _draw_segment(img, ex, ey, hx, hy, C_SKIN_M, C_SKIN_D, C_SKIN_L, 4)
        # Fist
        draw.rectangle([hx-2, hy-2, hx+3, hy+4], fill=C_SKIN_M)
        for x_i in range(hx-1, hx+3):
            img.putpixel((x_i, hy-3), C_SKIN_L)
        # Sword
        _draw_sword_pil(img, hx+1, hy-4, sang, blen, glow)

    def _draw_segment(img, x0, y0, x1, y1, col_mid, col_dark, col_light, thickness):
        dx = x1 - x0; dy = y1 - y0
        length = math.hypot(dx, dy) or 1
        nx = -dy / length; ny = dx / length
        steps = max(int(length) + 1, 2)
        half = thickness // 2
        for i in range(steps):
            t = i / (steps - 1)
            cx = int(x0 + dx * t); cy = int(y0 + dy * t)
            for off in range(-half, half + 1):
                xi = int(cx + nx * off); yi = int(cy + ny * off)
                if off == -half: c = col_light
                elif off == half: c = col_dark
                else: c = col_mid
                if 0 <= xi < 256 and 0 <= yi < 256:
                    img.putpixel((xi, yi), c)

    def _draw_sword_pil(img, hx, hy, angle_deg, bl, add_glow):
        rad = math.radians(angle_deg) - math.pi/2
        bx_ = math.cos(rad); by_ = math.sin(rad)
        for i in range(bl + 1):
            t = i / max(bl, 1)
            bpx = int(hx + bx_ * i); bpy = int(hy + by_ * i)
            if 0 <= bpx < 256 and 0 <= bpy < 256:
                img.putpixel((bpx, bpy), C_SILVER2_V)
            if 0 <= bpx+1 < 256 and 0 <= bpy < 256:
                img.putpixel((bpx+1, bpy), C_SILVER_V)
            if t < 0.85:
                if 0 <= bpx < 256 and 0 <= bpy+1 < 256:
                    img.putpixel((bpx, bpy+1), C_METAL_V)
        if add_glow:
            for i in range(0, bl, 3):
                gpx = int(hx + bx_ * i); gpy = int(hy + by_ * i)
                for gr in range(1, 4):
                    a = max(0, 50 - gr*15)
                    if a > 0:
                        for ox2, oy2 in [(-gr,0),(gr,0),(0,-gr),(0,gr)]:
                            gx2, gy2 = gpx+ox2, gpy+oy2
                            if 0 <= gx2 < 256 and 0 <= gy2 < 256:
                                existing = img.getpixel((gx2, gy2))
                                if existing[3] < 10:
                                    img.putpixel((gx2, gy2), (*C_ORANGE2V[:3], a))

    _draw_victory_arm_simple(out, shoulder_x, shoulder_y,
                             elbow_x, elbow_y, hand_x, hand_y,
                             sword_angle, blade_len, add_glow)
    return out


def generate_victory():
    idle_frame = Image.fromarray(IDLE_F1, 'RGBA')
    arm_mask = np.zeros((256, 256), dtype=bool)
    for row in range(93, 166):
        for col in range(48, 92):
            if IDLE_F1[row, col, 3] > 128:
                arm_mask[row, col] = True

    frames = [_gen_victory_frame_6(idle_frame, arm_mask, i) for i in range(6)]
    strip = Image.new("RGBA", (FRAME_W * 6, FRAME_H), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * FRAME_W, 0))
    return strip


# ════════════════════════════════════════════════════════════════════════════
# VALIDATION
# ════════════════════════════════════════════════════════════════════════════

def validate_strip(strip, name, expected_frames, expected_w, expected_h=FRAME_H):
    assert strip.width  == expected_w, f"{name}: width {strip.width} != {expected_w}"
    assert strip.height == expected_h, f"{name}: height {strip.height} != {expected_h}"
    arr = np.array(strip)
    for i in range(expected_frames):
        frame = arr[:, i * FRAME_W:(i+1) * FRAME_W, :]
        opaque = int((frame[:, :, 3] > 10).sum())
        assert opaque >= 500, f"{name} frame {i}: only {opaque} opaque pixels"
    print(f"  {name}: {expected_w}x{expected_h}, {expected_frames} frames — PASS")


# ════════════════════════════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════════════════════════════

def main():
    print("=== Fighter sprite animation upgrade (expanded frame counts) ===\n")

    print("Generating IDLE (4 frames, 1024x256)...")
    idle = generate_idle()
    idle.save(ASSET_DIR / "idle.png")
    validate_strip(idle, "idle", 4, FRAME_W * 4)

    print("Generating WALK (8 frames, 2048x256)...")
    walk = generate_walk()
    walk.save(ASSET_DIR / "walk.png")
    validate_strip(walk, "walk", 8, FRAME_W * 8)

    print("Generating ATTACK (8 frames, 2048x256)...")
    attack = generate_attack()
    attack.save(ASSET_DIR / "attack.png")
    validate_strip(attack, "attack", 8, FRAME_W * 8)

    print("Generating HIT (6 frames, 1536x256)...")
    hit = generate_hit()
    hit.save(ASSET_DIR / "hit.png")
    validate_strip(hit, "hit", 6, FRAME_W * 6)

    print("Generating DEAD (6 frames, 1536x256)...")
    dead = generate_dead()
    dead.save(ASSET_DIR / "dead.png")
    validate_strip(dead, "dead", 6, FRAME_W * 6)

    print("Generating CAST (6 frames, 1536x256)...")
    cast = generate_cast()
    cast.save(ASSET_DIR / "cast.png")
    validate_strip(cast, "cast", 6, FRAME_W * 6)

    print("Generating VICTORY (6 frames, 1536x256)...")
    victory = generate_victory()
    victory.save(ASSET_DIR / "victory.png")
    validate_strip(victory, "victory", 6, FRAME_W * 6)

    print("\n=== Final dimension check ===")
    expected = {
        "idle.png":    (1024, 256),
        "walk.png":    (2048, 256),
        "attack.png":  (2048, 256),
        "hit.png":     (1536, 256),
        "dead.png":    (1536, 256),
        "cast.png":    (1536, 256),
        "victory.png": (1536, 256),
        "defend.png":  (1024, 256),
        "item.png":    (1024, 256),
    }
    all_ok = True
    for fname, (ew, eh) in expected.items():
        fpath = ASSET_DIR / fname
        if not fpath.exists():
            print(f"  MISSING: {fname}")
            all_ok = False
            continue
        img = Image.open(fpath)
        ok = img.size == (ew, eh)
        status = "PASS" if ok else f"FAIL (got {img.size})"
        print(f"  {fname}: {ew}x{eh} — {status}")
        if not ok:
            all_ok = False

    print("\nAll done." if all_ok else "\nSome checks FAILED.")
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
