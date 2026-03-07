#!/usr/bin/env python3
"""
Fighter sprite animation generator - complete rebuild with smooth transitions.

Generates: attack (6f), hit (4f), dead (4f), walk (6f), plus
re-generates defend, cast, victory, item using existing logic.

Key principles for pixel-art smoothness:
- No pixel blending (destroys palette)
- Body translation: max 3-4px per frame
- Sword angle: max 25-30 degrees per frame
- Every animation's final frame returns sword near idle rest position
- 2x2 super-pixels throughout for SNES density

Idle sprite analysis:
- Frame bounds: rows 66-163, cols 50-155
- Head: rows 66-104, cols 90-147
- Torso: rows 93-135, cols 82-147
- Legs: rows 136-163, cols 60-155
- Sword idle position: diagonal blade, upper-right (x~132, y~78) to lower-left (x~50, y~157)
- Sword hilt area: x=130-147, y=78-95 (upper part of sword in idle)
"""

import math
import sys
from pathlib import Path
from PIL import Image, ImageDraw
import numpy as np

IDLE_PATH  = "/home/struktured/projects/cowardly-irregular/assets/sprites/jobs/fighter/idle.png"
OUT_DIR    = Path("/home/struktured/projects/cowardly-irregular/assets/sprites/jobs/fighter")
FRAME_W    = 256
FRAME_H    = 256

# ── Exact palette from idle.png ──────────────────────────────────────────────
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

# Steel colors - appear ONLY on sword
SWORD_STEEL = {
    (174, 179, 204), (125, 129, 144), (76, 78, 86),
    (93, 98, 110),   (51, 57, 65),    (54, 61, 77),
    (36, 34, 52),
}

# ── Load idle sprite ──────────────────────────────────────────────────────────

_idle_img  = Image.open(IDLE_PATH).convert("RGBA")
_idle_np   = np.array(_idle_img, dtype=np.uint8)
IDLE_F1    = _idle_np[:, :FRAME_W, :].copy()
IDLE_F2    = _idle_np[:, FRAME_W:FRAME_W*2, :].copy()

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


def thick_line(arr, x0, y0, x1, y1, color, thickness=4):
    """Draw a thick anti-stepped line using 2x2 pixels."""
    dx, dy = x1 - x0, y1 - y0
    length = math.hypot(dx, dy) or 1
    nx, ny = -dy / length, dx / length
    steps = max(int(length / 2) + 1, 2)
    half = thickness // 2
    for i in range(steps):
        t = i / (steps - 1)
        cx = int(x0 + dx * t) & ~1
        cy = int(y0 + dy * t) & ~1
        for off in range(-half, half + 1, 2):
            ox = int(nx * off) & ~1
            oy = int(ny * off) & ~1
            pp(arr, cx + ox, cy + oy, color)


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
    """Draw pixels list with offset and optional darkening."""
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
    """Return pixels with x,y normalized to (0,0) origin and original min offset."""
    if not pixels:
        return [], 0, 0
    min_x = min(p[0] for p in pixels)
    min_y = min(p[1] for p in pixels)
    normed = [(x - min_x, y - min_y, c) for x, y, c in pixels]
    return normed, min_x, min_y


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


# ── Erase sword from idle base ────────────────────────────────────────────────

def _erase_sword(arr):
    """
    Remove the diagonal idle sword blade.
    Pass 1: exact steel-only palette colors (whole frame).
    Pass 2: purple ground-shadow pixels in blade sweep area.
    Pass 3: gap-based cluster erase for leftward blade tip pixels.
    Pass 4: isolated stray dots far left.
    """
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


def erase_idle_sword_blade(arr, new_angle_deg, new_hilt_x, new_hilt_y):
    """
    Erase the idle sword's exposed blade tip pixels from arr.

    The idle sword tip extends from about x=50-100, y=130-163 (lower-left region).
    These pixels are far from the body and will be exposed when a new sword
    is drawn at a very different angle.

    We ONLY erase steel pixels in the blade TIP zone (below row 130, left of col 110)
    that are far from the new sword's path. This avoids touching the arm/body area.
    """
    # Angular difference - if small, don't erase
    angle_diff = abs(new_angle_deg - IDLE_SWORD_ANGLE) % 360
    if angle_diff > 180:
        angle_diff = 360 - angle_diff
    if angle_diff < 30:
        return  # Swords nearly coincident - no erase needed

    new_rad_loc = math.radians(new_angle_deg)
    nbx = math.cos(new_rad_loc)
    nby = -math.sin(new_rad_loc)

    # Only work in the blade tip region (lower-left, away from body)
    # This is safe to erase - it's clearly blade territory
    for y in range(120, FRAME_H):
        for x in range(40, 120):
            px = tuple(arr[y, x])
            if px[3] < 10:
                continue
            if tuple(px[:3]) not in SWORD_STEEL:
                continue

            # Check perpendicular distance from the new sword axis
            rx = x - new_hilt_x
            ry = y - new_hilt_y
            perp = abs(rx * (-nby) + ry * nbx)
            proj = rx * nbx + ry * nby  # projection along new blade

            # Erase if clearly not on new sword path
            if perp > 12 or proj < 0:
                arr[y, x] = TRANSPARENT


# ── Sword shape renderers ─────────────────────────────────────────────────────

def sword_at_angle(arr, hilt_x, hilt_y, angle_deg, blade_len=52, serrated=True):
    """
    Draw a serrated broadsword with hilt at (hilt_x, hilt_y).
    angle_deg: 0 = pointing right, 90 = pointing up, etc. (standard math angles)
    blade points FROM hilt in direction of angle_deg.

    For idle-match: idle sword goes upper-left to lower-right (blade extends left-down)
    Idle approximate: hilt ~(140, 88), blade tip ~(52, 157) → angle ≈ 225° (SW)
    """
    rad = math.radians(angle_deg)
    bx = math.cos(rad)    # blade direction unit vector
    by = -math.sin(rad)   # flip y because screen y increases downward

    # Perpendicular for width
    px_ = -by
    py_ = bx

    steps = blade_len // 2
    for i in range(steps):
        t = i / max(steps - 1, 1)
        # Blade tapers: 3px wide at hilt, 1px at tip
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
        pp(arr, cx + ox, cy + oy, C_OUTLINE)
        pp(arr, cx - ox, cy - oy, C_OUTLINE)

        # Blade colors: dark/mid/light/edge
        for w in range(-width + 1, width):
            bpx = int(cx + px_ * w) & ~1
            bpy = int(cy + py_ * w) & ~1
            if abs(w) == width - 1:
                c = C_METAL
            elif w == 0:
                c = C_SILVER2
            elif w > 0:
                c = C_SILVER
            else:
                c = C_METAL_MD
            pp(arr, bpx, bpy, c)

        # Serrations on one edge (every 5 steps along blade)
        if serrated and i % 5 == 2 and 2 < i < steps - 2:
            sx = int(cx + px_ * (width + 1)) & ~1
            sy = int(cy + py_ * (width + 1)) & ~1
            pp(arr, sx, sy, C_METAL_DK)

    # Crossguard at hilt position
    gx = hilt_x
    gy = hilt_y
    for k in range(-7, 8, 2):
        kx = int(gx + px_ * k) & ~1
        ky = int(gy + py_ * k) & ~1
        c = C_SILVER2 if abs(k) <= 2 else (C_SILVER if abs(k) <= 4 else C_METAL)
        pp(arr, kx, ky, c)
    # Guard tips
    pp(arr, int(gx + px_ * -8) & ~1, int(gy + py_ * -8) & ~1, C_OUTLINE)
    pp(arr, int(gx + px_ * 8) & ~1,  int(gy + py_ * 8) & ~1,  C_OUTLINE)

    # Handle (behind hilt, 10px)
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


# In idle, the sword's hilt (handle grip area) is at approximately:
# x=130-145, y=86-100 (upper portion), blade extends lower-left
# The angle in idle: hilt at (136, 90), tip at ~(52, 157)
# dx = 52-136 = -84, dy = 157-90 = 67
# angle = atan2(67, -84) ≈ 141° from +x axis in screen coords
# In our convention (angle_deg=0→right, +CCW in math space):
#   atan2(-screen_dy, dx) because screen y is flipped
#   atan2(-67, -84) = atan2(67,84) reflected = ~180+atan2(67,84) = ~180+38.6 = ~218.6°
IDLE_SWORD_ANGLE = 218   # approximately — blade extends lower-left
IDLE_HILT_X = 136
IDLE_HILT_Y = 90


# ── Body parts extraction ─────────────────────────────────────────────────────

# Upper body: head + torso + arms INCLUDING sword steel pixels.
# We keep everything for walk (sword stays at idle position).
_upper_body_raw = extract_pixels(IDLE_F1, 66, 135, 0, 255)
_upper_body = _upper_body_raw  # full upper body, all colors - for walk

# Upper body for attack/hit/dead: we use the full idle frame as base array
# and then draw the new sword on top. This avoids gap issues entirely.
# _upper_body_nosword is only needed for legs extraction compatibility.
_upper_body_nosword = [(x, y, c) for x, y, c in _upper_body_raw
                       if tuple(c[:3]) not in SWORD_STEEL]

# Legs
_left_leg_raw  = extract_pixels(IDLE_F1, 136, 163, 60, 116)
_left_leg      = [(x, y, c) for x, y, c in _left_leg_raw
                  if tuple(c[:3]) not in SWORD_STEEL]
_right_leg_raw = extract_pixels(IDLE_F1, 136, 163, 90, 155)

_ll_norm, _ll_ox, _ll_oy = normalize_pixels(_left_leg)
_rl_norm, _rl_ox, _rl_oy = normalize_pixels(_right_leg_raw)
_ll_w = max(p[0] for p in _ll_norm) + 1 if _ll_norm else 1
_rl_w = max(p[0] for p in _rl_norm) + 1 if _rl_norm else 1

print(f"Body: upper={len(_upper_body)}px, "
      f"ll={len(_ll_norm)}px(w={_ll_w}), rl={len(_rl_norm)}px(w={_rl_w})")


# ── Helper: blend_over for alpha compositing ──────────────────────────────────

def blend_over_img(img, x, y, c):
    """Alpha-composite color c over existing pixel in PIL Image."""
    if not (0 <= x < img.width and 0 <= y < img.height):
        return
    bg = img.getpixel((x, y))
    na = c[3] / 255.0
    ba = bg[3] / 255.0
    out_a = na + ba * (1 - na)
    if out_a < 0.001:
        return
    nr = int((c[0] * na + bg[0] * ba * (1 - na)) / out_a)
    ng = int((c[1] * na + bg[1] * ba * (1 - na)) / out_a)
    nb = int((c[2] * na + bg[2] * ba * (1 - na)) / out_a)
    img.putpixel((x, y), (nr, ng, nb, int(out_a * 255)))


# ════════════════════════════════════════════════════════════════════════════════
# WALK ANIMATION (6 frames, 1536x256)
# ════════════════════════════════════════════════════════════════════════════════
# Same logic as gen_fighter_walk_release.py but with smoother stride

BODY_CX  = 103
HIP_Y    = 136
SHADOW_Y = 160
STRIDE   = 14    # slightly reduced from 16 for smoother appearance
DARK     = 0.52

# (front_type, front_cx, back_type, back_cx, bob)
_walk_frames_data = [
    ('ll', BODY_CX - STRIDE,      'rl', BODY_CX + STRIDE,      0),   # F0: right fwd
    ('ll', BODY_CX - STRIDE // 2, 'rl', BODY_CX + STRIDE // 2, -2),  # F1: mid, body up
    ('rl', BODY_CX - STRIDE,      'll', BODY_CX + STRIDE,      0),   # F2: left fwd
    ('rl', BODY_CX - STRIDE // 2, 'll', BODY_CX + STRIDE // 2, -2),  # F3: mid, body up
    ('ll', BODY_CX - STRIDE,      'rl', BODY_CX + STRIDE,      0),   # F4: right fwd (repeat)
    ('ll', BODY_CX - STRIDE // 2, 'rl', BODY_CX + STRIDE // 2, -2),  # F5: mid (repeat)
]


def get_leg(t): return _ll_norm if t == 'll' else _rl_norm
def get_lw(t):  return _ll_w    if t == 'll' else _rl_w


def _gen_walk_frame(fdata):
    ft, fcx, bt, bcx, bob = fdata
    arr = np.zeros((FRAME_H, FRAME_W, 4), dtype=np.uint8)

    fw = get_lw(ft)
    bw = get_lw(bt)
    fox = fcx - fw // 2
    box = bcx - bw // 2

    # Layer 1: back leg (darkened, behind body)
    blit_pixels(arr, get_leg(bt), dx=box, dy=HIP_Y + bob, darken=DARK)
    # Layer 2: upper body WITH sword at idle position (no extra sword draw needed)
    blit_pixels(arr, _upper_body, dx=0, dy=bob)
    # Layer 3: front leg (drawn over body to appear in front)
    blit_pixels(arr, get_leg(ft), dx=fox, dy=HIP_Y + bob, darken=1.0)
    # Ground shadow
    shadow_row(arr, BODY_CX, SHADOW_Y + bob, 20 + abs(fcx - bcx) // 3)

    return Image.fromarray(arr, 'RGBA')


def generate_walk():
    frames = [_gen_walk_frame(fd) for fd in _walk_frames_data]
    strip = Image.new("RGBA", (FRAME_W * 6, FRAME_H), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * FRAME_W, 0))
    return strip


# ════════════════════════════════════════════════════════════════════════════════
# ATTACK ANIMATION (6 frames, 1536x256)
# ════════════════════════════════════════════════════════════════════════════════
#
# Arc: The fighter raises sword from idle (lower-left) to upper-right windup,
#      then sweeps it down-right in a powerful diagonal slash.
#
# Frame-by-frame plan (all angles in our convention: 0=right, +CCW):
#
#   F0: WINDUP START  — sword rises from idle toward upper-right
#       Hilt moves slightly up, angle transitions from idle (218°) toward (140°)
#       Body leans back 2px. Movement: gradual, subtle.
#
#   F1: WINDUP PEAK   — sword at ~100° (almost straight up, slightly right)
#       Hilt at (136, 84), body leans back 4px total.
#       Max windup — this is the "big" pose transition.
#
#   F2: SWING START   — sword starts coming forward at ~60° (upper-right)
#       Body lunges forward 3px. Hilt moves right.
#
#   F3: SWING MID     — sword at ~20° (nearly horizontal, pointing right)
#       Body at max forward lunge. This is peak slash power.
#
#   F4: FOLLOW-THROUGH — sword past horizontal at ~-30° (pointing right-down)
#       Body still forward, starting to come back.
#
#   F5: RECOVERY      — sword has swept through to ~200° (idle-ish direction)
#       Body returns toward neutral. Sword back near idle position.
#       Smooth return: sword angle ~210°, 8° away from idle (218°).
#
# Body offsets (dx, dy) relative to idle position:
#   F0: (0, -2)   — slight rise
#   F1: (-2, -3)  — lean back
#   F2: (2, -1)   — lunge forward
#   F3: (4, 0)    — full lunge
#   F4: (3, 1)    — follow
#   F5: (1, 0)    — near-idle recovery
#
# Hilt positions (absolute):
#   Idle: (136, 90)
#   F0: hilt rises toward upper shoulder → (134, 82)
#   F1: windup peak, arm raised          → (128, 76)
#   F2: swing starts forward-right       → (132, 80)
#   F3: sword horizontal, arm extended   → (138, 88)
#   F4: follow-through, arm coming down  → (136, 96)
#   F5: recovery, back near idle         → (136, 90) ← matches idle exactly

_attack_frames_data = [
    # (body_dx, body_dy, hilt_x, hilt_y, sword_angle, blade_len)
    (0,  -2,  134, 82,  160, 50),   # F0: windup begins (sword ~160°, upper-left)
    (-2, -3,  128, 76,  110, 52),   # F1: windup peak (sword ~110°, almost straight up)
    (2,  -1,  132, 80,   60, 52),   # F2: swing starts (sword ~60°, upper-right)
    (4,   0,  138, 88,   15, 54),   # F3: slash peak   (sword ~15°, nearly horizontal right)
    (3,   1,  136, 96,  -25, 54),   # F4: follow-through (sword ~-25°, right-down)
    (1,   0,  136, 90,  210, 52),   # F5: recovery - sword back near idle (218°)
]


def _gen_attack_frame(fdata):
    body_dx, body_dy, hilt_x, hilt_y, sword_angle, blade_len = fdata

    # Start from full idle frame - this preserves body integrity perfectly.
    # Then shift the entire frame by (body_dx, body_dy) if needed.
    arr = IDLE_F1.copy()

    if body_dx != 0 or body_dy != 0:
        # Shift upper body by (body_dx, body_dy), keep legs in place
        shifted = np.zeros_like(arr)
        # Shift rows 66-135 (upper body)
        src_y0 = max(66, 66 - body_dy)
        src_y1 = min(136, 136 - body_dy)
        dst_y0 = max(66, 66 + body_dy)
        dst_y1 = min(136, 136 + body_dy)
        # Simple horizontal/vertical shift of upper body region
        src_x0 = max(0, -body_dx)
        src_x1 = min(FRAME_W, FRAME_W - body_dx)
        dst_x0 = max(0, body_dx)
        dst_x1 = min(FRAME_W, FRAME_W + body_dx)
        copy_h = min(src_y1 - src_y0, dst_y1 - dst_y0, 70)
        copy_w = min(src_x1 - src_x0, dst_x1 - dst_x0, FRAME_W)
        if copy_h > 0 and copy_w > 0:
            # Keep lower body (legs) from original
            shifted[136:] = arr[136:]
            # Shift upper body
            shifted[dst_y0:dst_y0+copy_h, dst_x0:dst_x0+copy_w] = \
                arr[src_y0:src_y0+copy_h, src_x0:src_x0+copy_w]
            arr = shifted
        # Ground shadow with adjustment
        shadow_row(arr, BODY_CX + body_dx // 2, SHADOW_Y, 22)
    else:
        shadow_row(arr, BODY_CX, SHADOW_Y, 22)

    # Erase idle sword blade where it won't be covered by the new sword
    erase_idle_sword_blade(arr, sword_angle, hilt_x + body_dx, hilt_y + body_dy)

    # Draw new sword on top (overwrites remaining idle sword pixels)
    sword_at_angle(arr, hilt_x + body_dx, hilt_y + body_dy, sword_angle, blade_len)

    return Image.fromarray(arr, 'RGBA')


def generate_attack():
    frames = [_gen_attack_frame(fd) for fd in _attack_frames_data]
    strip = Image.new("RGBA", (FRAME_W * 6, FRAME_H), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * FRAME_W, 0))
    return strip


# ════════════════════════════════════════════════════════════════════════════════
# HIT ANIMATION (4 frames, 1024x256)
# ════════════════════════════════════════════════════════════════════════════════
#
# Fighter takes a hit and recoils, then recovers.
#
# F0: Impact  — body lurches backward-right 4px, head snaps back 2px, sword swings out
#               Character squishes down slightly (crouches on impact)
# F1: Recoil  — body moves back 6px total, slight rotation (head forward now), sword lower
#               Body at maximum recoil position
# F2: Recovery — body comes back 3px, sword returns toward idle
# F3: Steady  — body back near idle, sword back to idle angle
#
# Subtle: on impact, the fighter's body leans back → body_dx positive (right),
# sword swings away from body to absorb impact visually.

_hit_frames_data = [
    # (body_dx, body_dy, hilt_x, hilt_y, sword_angle, blade_len, head_tilt)
    (4,   1, 140, 94,  200, 50, 0),   # F0: impact - body right+down, sword swings right
    (6,   2, 142, 98,  195, 48, 0),   # F1: max recoil - body furthest right
    (3,   1, 138, 92,  205, 50, 0),   # F2: recovery halfway
    (1,   0, 136, 90,  215, 52, 0),   # F3: almost idle, sword near idle angle (218)
]


def _gen_hit_frame(fdata):
    body_dx, body_dy, hilt_x, hilt_y, sword_angle, blade_len, _ = fdata

    # Start from full idle frame
    arr = IDLE_F1.copy()

    if body_dx != 0 or body_dy != 0:
        shifted = np.zeros_like(arr)
        # Shift entire body (upper + lower) for hit recoil
        src_x0 = max(0, -body_dx)
        dst_x0 = max(0, body_dx)
        copy_w = min(FRAME_W - abs(body_dx), FRAME_W)
        src_y0 = max(0, -body_dy)
        dst_y0 = max(0, body_dy)
        copy_h = min(FRAME_H - abs(body_dy), FRAME_H)
        if copy_h > 0 and copy_w > 0:
            shifted[dst_y0:dst_y0+copy_h, dst_x0:dst_x0+copy_w] = \
                arr[src_y0:src_y0+copy_h, src_x0:src_x0+copy_w]
        arr = shifted

    shadow_row(arr, BODY_CX + body_dx // 2, SHADOW_Y + body_dy // 2, 22)

    # Draw new sword on top (overwrites idle sword where they overlap)
    sword_at_angle(arr, hilt_x + body_dx, hilt_y + body_dy, sword_angle, blade_len)

    return Image.fromarray(arr, 'RGBA')


def generate_hit():
    frames = [_gen_hit_frame(fd) for fd in _hit_frames_data]
    strip = Image.new("RGBA", (FRAME_W * 4, FRAME_H), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * FRAME_W, 0))
    return strip


# ════════════════════════════════════════════════════════════════════════════════
# DEAD ANIMATION (4 frames, 1024x256)
# ════════════════════════════════════════════════════════════════════════════════
#
# Fighter falls down, ending in a prone position.
# The fall should be a smooth arc, not a teleport.
#
# Strategy: rotate the entire character gradually using pixel-level rotation
# around the hip/feet pivot point.
#
# F0: Staggers — knees buckle, body dips 6px down, tilts 15° forward (right)
# F1: Falling  — body tilts 40° forward, slides right 8px
# F2: Collapse — body at 70° tilt, nearly horizontal, slides right 20px
# F3: Prone    — body at 85° (nearly horizontal), resting on ground
#
# Implementation: take the idle body region and rotate it around the foot center.

def _rotate_pixels(pixels, pivot_x, pivot_y, angle_deg, arr):
    """Rotate pixels by angle_deg around pivot, blit to arr."""
    rad = math.radians(angle_deg)
    cos_a = math.cos(rad)
    sin_a = math.sin(rad)
    for x, y, c in pixels:
        # Translate to pivot
        rx = x - pivot_x
        ry = y - pivot_y
        # Rotate
        nx = int(rx * cos_a - ry * sin_a + pivot_x) & ~1
        ny = int(rx * sin_a + ry * cos_a + pivot_y) & ~1
        if 0 <= nx < FRAME_W and 0 <= ny < FRAME_H:
            arr[ny, nx] = c


# Extract full character pixels (upper body + legs) for rotation
_full_body = extract_pixels(IDLE_F1, 66, 163, 50, 155)
_full_body_nosword = [(x, y, c) for x, y, c in _full_body
                      if tuple(c[:3]) not in SWORD_STEEL]

# Foot pivot: center bottom of character (approximately where feet meet ground)
_FOOT_X = 110   # x center of feet
_FOOT_Y = 162   # y at ground level

# Fall parameters: (tilt_angle_deg, body_slide_x, body_slide_y)
# Positive tilt = rotating clockwise (falling to the right/forward)
_dead_frames_data = [
    (15,   2,  4,   170, 50),   # F0: buckle - slight tilt, body sinks
    (40,   8,  8,   160, 46),   # F1: falling - 40° tilt
    (70,  20, 14,   145, 40),   # F2: collapse - 70° tilt
    (85,  28, 20,   130, 36),   # F3: prone - 85° nearly horizontal
]
# (tilt_deg, slide_x, slide_y, shadow_x, sword_tilt_extra)


def _gen_dead_frame(fdata, frame_idx):
    tilt, slide_x, slide_y, shadow_x, blade_len = fdata
    arr = np.zeros((FRAME_H, FRAME_W, 4), dtype=np.uint8)

    # Pivot point adjusted for slide
    piv_x = _FOOT_X + slide_x
    piv_y = _FOOT_Y - slide_y // 2

    # Rotate full body (including sword steel) around pivot - no gaps
    for x, y, c in _full_body:
        # Translate to pivot
        rx = x - _FOOT_X
        ry = y - _FOOT_Y
        # Rotate (positive = clockwise in screen coords)
        rad = math.radians(tilt)
        nx = int(rx * math.cos(rad) - ry * math.sin(rad) + piv_x) & ~1
        ny = int(rx * math.sin(rad) + ry * math.cos(rad) + piv_y) & ~1
        if 0 <= nx < FRAME_W - 1 and 0 <= ny < FRAME_H - 1:
            arr[ny, nx] = c
            arr[ny + 1, nx] = c     # 2x2 fill to avoid gaps in rotated sprites
            arr[ny, nx + 1] = c
            arr[ny + 1, nx + 1] = c

    # Draw sword at correspondingly rotated angle
    # Idle sword angle 218°, as fighter falls forward sword also rotates
    sword_tilt = tilt * 0.8  # sword follows body rotation somewhat
    sword_angle_final = IDLE_SWORD_ANGLE + sword_tilt
    # Sword hilt also rotates around pivot
    rad = math.radians(tilt)
    rhx = IDLE_HILT_X - _FOOT_X
    rhy = IDLE_HILT_Y - _FOOT_Y
    nhx = int(rhx * math.cos(rad) - rhy * math.sin(rad) + piv_x)
    nhy = int(rhx * math.sin(rad) + rhy * math.cos(rad) + piv_y)
    if 0 <= nhx < FRAME_W and 0 <= nhy < FRAME_H:
        sword_at_angle(arr, nhx, nhy, sword_angle_final, blade_len)

    # Shadow stretches as character falls
    if frame_idx < 3:
        shadow_row(arr, shadow_x, SHADOW_Y - slide_y // 3, 16 + tilt // 4)
    else:
        # Prone shadow — long and horizontal
        shadow_row(arr, shadow_x + 15, SHADOW_Y, 35)

    return Image.fromarray(arr, 'RGBA')


def generate_dead():
    frames = [_gen_dead_frame(fd, i) for i, fd in enumerate(_dead_frames_data)]
    strip = Image.new("RGBA", (FRAME_W * 4, FRAME_H), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * FRAME_W, 0))
    return strip


# ════════════════════════════════════════════════════════════════════════════════
# RE-RUN EXISTING GENERATORS (defend, cast, victory, item)
# ════════════════════════════════════════════════════════════════════════════════

def run_existing_generators():
    """Re-execute the existing generation scripts to rebuild defend/cast/victory/item."""
    import subprocess
    scripts = [
        "/home/struktured/projects/cowardly-irregular/tools/gen_fighter_defend_cast.py",
        "/home/struktured/projects/cowardly-irregular/tools/gen_fighter_victory_item.py",
    ]
    for script in scripts:
        print(f"  Running {Path(script).name}...")
        result = subprocess.run([sys.executable, script],
                                capture_output=True, text=True)
        if result.returncode != 0:
            print(f"    ERROR: {result.stderr[-500:]}")
        else:
            # Print last few lines of stdout for validation results
            lines = result.stdout.strip().split('\n')
            for l in lines[-8:]:
                print(f"    {l}")


# ════════════════════════════════════════════════════════════════════════════════
# IDLE — re-generate to ensure breathing bob is consistent
# ════════════════════════════════════════════════════════════════════════════════

def generate_idle():
    """
    Idle: 2 frames.
    F0: base idle pose (from idle.png frame 1 directly)
    F1: subtle 1px breathing bob (body up 1px, feet stay)
    """
    # Frame 0: use idle frame 1 directly
    f0 = Image.fromarray(IDLE_F1, 'RGBA')

    # Frame 1: shift upper body (rows 66-135) up 1px, keep legs in place
    f1_arr = IDLE_F1.copy()
    # Shift rows 66-135 up by 1px
    shifted = f1_arr.copy()
    shifted[65:135, :] = f1_arr[66:136, :]
    shifted[65, :] = 0  # clear the freed row at top of shift range

    f1 = Image.fromarray(shifted, 'RGBA')

    strip = Image.new("RGBA", (FRAME_W * 2, FRAME_H), (0, 0, 0, 0))
    strip.paste(f0, (0, 0))
    strip.paste(f1, (FRAME_W, 0))
    return strip


# ════════════════════════════════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════════════════════════════════

def validate_strip(strip, name, expected_frames, expected_w, expected_h=FRAME_H):
    assert strip.width  == expected_w, f"{name}: width {strip.width} != {expected_w}"
    assert strip.height == expected_h, f"{name}: height {strip.height} != {expected_h}"
    arr = np.array(strip)
    for i in range(expected_frames):
        frame = arr[:, i * FRAME_W:(i + 1) * FRAME_W, :]
        opaque = int((frame[:, :, 3] > 10).sum())
        assert opaque >= 500, f"{name} frame {i}: only {opaque} opaque pixels"
    print(f"  {name}: {expected_w}x{expected_h}, {expected_frames} frames — PASS")


def main():
    print("=== Fighter sprite animation regeneration ===\n")

    print("Generating IDLE (2 frames)...")
    idle_strip = generate_idle()
    idle_path = OUT_DIR / "idle.png"
    idle_strip.save(idle_path)
    validate_strip(idle_strip, "idle", 2, FRAME_W * 2)

    print("Generating WALK (6 frames)...")
    walk_strip = generate_walk()
    walk_path = OUT_DIR / "walk.png"
    walk_strip.save(walk_path)
    validate_strip(walk_strip, "walk", 6, FRAME_W * 6)

    print("Generating ATTACK (6 frames)...")
    attack_strip = generate_attack()
    attack_path = OUT_DIR / "attack.png"
    attack_strip.save(attack_path)
    validate_strip(attack_strip, "attack", 6, FRAME_W * 6)

    print("Generating HIT (4 frames)...")
    hit_strip = generate_hit()
    hit_path = OUT_DIR / "hit.png"
    hit_strip.save(hit_path)
    validate_strip(hit_strip, "hit", 4, FRAME_W * 4)

    print("Generating DEAD (4 frames)...")
    dead_strip = generate_dead()
    dead_path = OUT_DIR / "dead.png"
    dead_strip.save(dead_path)
    validate_strip(dead_strip, "dead", 4, FRAME_W * 4)

    print("\nRunning existing generators for DEFEND, CAST, VICTORY, ITEM...")
    run_existing_generators()

    print("\n=== Dimension verification ===")
    expected = {
        "idle.png":    (512,  256),
        "walk.png":    (1536, 256),
        "attack.png":  (1536, 256),
        "hit.png":     (1024, 256),
        "dead.png":    (1024, 256),
        "defend.png":  (1024, 256),
        "cast.png":    (1024, 256),
        "victory.png": (1024, 256),
        "item.png":    (1024, 256),
    }
    all_ok = True
    for fname, (ew, eh) in expected.items():
        fpath = OUT_DIR / fname
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

    print("\nAll done." if all_ok else "\nSome checks FAILED — review above.")


if __name__ == "__main__":
    main()
