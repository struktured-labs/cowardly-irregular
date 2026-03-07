#!/usr/bin/env python3
"""
Generate fighter VICTORY and ITEM animation strips.
Each strip is 1024x256 (4 frames x 256x256).

Sprite structure (idle.png frame 1, 256x256):
  Character spans cols 50-155, rows 66-163
  Head:          cols 84-118,  rows 66-104
  Torso:         cols 92-145,  rows 93-130
  LEFT arm (sword arm from body's left / viewer's right):
    Upper arm connector: cols 92-103, rows 93-115 (orange/red armored arm)
    Extended arm + blade: cols 48-91, rows 93-163 (leftward extension)
  Right arm of body (viewer's left, character's right):
    cols 116-145, rows 93-135 (tucked against body)
  Legs:          cols 88-138,  rows 130-163
"""

import math
from PIL import Image, ImageDraw
import numpy as np

SRC_IDLE    = "/home/struktured/projects/cowardly-irregular/assets/sprites/jobs/fighter/idle.png"
OUT_VICTORY = "/home/struktured/projects/cowardly-irregular/assets/sprites/jobs/fighter/victory.png"
OUT_ITEM    = "/home/struktured/projects/cowardly-irregular/assets/sprites/jobs/fighter/item.png"

# ── Exact palette from idle.png ───────────────────────────────────────────────
TRANSPARENT   = (0,   0,   0,   0)
C_OUTLINE     = (36,  34,  52,  255)   # #242234
C_DARK_WARM   = (50,  43,  40,  255)   # #322B28
C_CRIMSON     = (115, 23,  45,  255)   # #73172D
C_RED         = (157, 49,  35,  255)   # #9D3123
C_RED2        = (180, 32,  42,  255)   # #B4202A
C_ORANGE      = (250, 106, 10,  255)   # #FA6A0A
C_ORANGE2     = (249, 163, 27,  255)   # #F9A31B
C_PURPLE_D    = (64,  51,  83,  255)   # #403353
C_PURPLE2     = (54,  61,  77,  255)   # #363D4D
C_METAL       = (76,  78,  86,  255)   # #4C4E56
C_SILVER      = (125, 129, 144, 255)   # #7D8190
C_SILVER2     = (174, 179, 204, 255)   # #AEB3CC
C_SKIN_D      = (113, 65,  59,  255)   # #71413B
C_SKIN_M      = (187, 117, 71,  255)   # #BB7547
C_SKIN_L      = (233, 181, 163, 255)   # #E9B5A3
C_SKIN_LL     = (244, 210, 156, 255)   # #F4D29C
C_HAIR        = (79,  53,  36,  255)   # #4F3524
C_HAIR2       = (141, 88,  68,  255)   # #8D5844
C_LEATHER     = (160, 134, 98,  255)   # #A08662
C_LEATHER2    = (228, 210, 170, 255)   # #E4D2AA
C_ITEM_GLOW   = (254, 243, 192, 255)   # #FEF3C0
C_ITEM_BRIGHT = (249, 163, 27,  255)   # #F9A31B
C_ITEM_CORE   = (255, 255, 230, 255)

# ── Pixel helpers ─────────────────────────────────────────────────────────────

def px(img, x, y, c):
    if 0 <= x < img.width and 0 <= y < img.height:
        img.putpixel((x, y), c)

def rect(img, x, y, w, h, c):
    draw = ImageDraw.Draw(img)
    draw.rectangle([x, y, x+w-1, y+h-1], fill=c)

def hline(img, x, y, w, c):
    for i in range(w):
        px(img, x+i, y, c)

def vline(img, x, y, h, c):
    for i in range(h):
        px(img, x, y+i, c)

def blend_over(img, x, y, c):
    """Alpha-composite color c over existing pixel."""
    if not (0 <= x < img.width and 0 <= y < img.height):
        return
    bg = img.getpixel((x, y))
    na = c[3] / 255.0
    ba = bg[3] / 255.0
    out_a = na + ba * (1 - na)
    if out_a < 0.001:
        return
    nr = int((c[0]*na + bg[0]*ba*(1-na)) / out_a)
    ng = int((c[1]*na + bg[1]*ba*(1-na)) / out_a)
    nb = int((c[2]*na + bg[2]*ba*(1-na)) / out_a)
    img.putpixel((x, y), (nr, ng, nb, int(out_a*255)))

def draw_thick_line(img, x0, y0, x1, y1, color, thickness=2):
    dx = x1 - x0
    dy = y1 - y0
    length = math.sqrt(dx*dx + dy*dy) or 1
    px_ = -dy / length
    py_ =  dx / length
    steps = max(int(length) + 1, 2)
    for i in range(steps):
        t = i / (steps - 1)
        cx = x0 + dx * t
        cy = y0 + dy * t
        for off in range(-thickness//2, thickness//2 + 1):
            xi = int(cx + px_ * off)
            yi = int(cy + py_ * off)
            px(img, xi, yi, color)

def erase_pixel_if_arm(img, x, y, arm_mask):
    """Erase pixel if it is marked as arm in the mask."""
    if arm_mask[y, x]:
        px(img, x, y, TRANSPARENT)

# ── Load idle frame ───────────────────────────────────────────────────────────

def load_idle():
    img = Image.open(SRC_IDLE).convert("RGBA")
    return img.crop((0, 0, 256, 256))

# ── Build precise arm mask ────────────────────────────────────────────────────

def build_arm_mask(idle_arr):
    """
    Return a boolean 256x256 mask where True = pixel belongs to the
    left sword arm (the arm extending leftward that holds the sword).

    Conservative strategy: only erase the pure left-extension zone
    (cols 48-91, rows 93-165). The arm connector at cols 92+ stays
    because we will draw the new raised arm ON TOP of the existing body.
    This preserves the body/torso completely.
    """
    h, w = idle_arr.shape[:2]
    mask = np.zeros((h, w), dtype=bool)

    # Only erase the horizontally-extended arm/blade area
    # (everything to the left of col 92 that belongs to the arm)
    for row in range(93, 166):
        for col in range(48, 92):
            if idle_arr[row, col, 3] > 128:
                mask[row, col] = True

    return mask

# ── Draw limb segments ────────────────────────────────────────────────────────

def draw_arm(img, x0, y0, x1, y1, col_mid, col_dark, col_light, thickness=5):
    """Draw an arm segment with highlight/shadow shading."""
    dx = x1 - x0
    dy = y1 - y0
    length = math.sqrt(dx*dx + dy*dy) or 1
    # Perpendicular (for width/shading)
    nx = -dy / length
    ny =  dx / length
    steps = max(int(length) + 1, 2)
    half = thickness // 2

    for i in range(steps):
        t = i / (steps - 1)
        cx = x0 + dx * t
        cy = y0 + dy * t
        for off in range(-half, half + 1):
            xi = int(cx + nx * off)
            yi = int(cy + ny * off)
            if off == -half:
                c = col_light
            elif off == half:
                c = col_dark
            else:
                c = col_mid
            px(img, xi, yi, c)

def draw_armored_shoulder(img, sx, sy):
    """Draw the left shoulder pauldron for victory poses.
    Drawn over existing shoulder area (sx-4..sx+5, sy-4..sy+3).
    """
    rect(img, sx-4, sy-3, 10, 6, C_RED)
    hline(img, sx-3, sy-4, 8,  C_ORANGE)
    hline(img, sx-4, sy+3, 10, C_CRIMSON)
    px(img, sx-4, sy-3, C_OUTLINE)
    px(img, sx+5, sy-3, C_OUTLINE)
    px(img, sx-4, sy+3, C_OUTLINE)
    px(img, sx+5, sy+3, C_OUTLINE)
    px(img, sx,   sy-2, C_ORANGE2)
    px(img, sx+1, sy-1, C_ORANGE)

# ── Sword rendering ───────────────────────────────────────────────────────────

def draw_sword(img, hilt_x, hilt_y, angle_deg, blade_len=38, add_glow=False):
    """
    Draw a sword with hilt at (hilt_x, hilt_y) pointing in angle_deg
    (measured from straight up = 0, clockwise positive).
    """
    # Convert: 0 = up means angle from +Y upward = -90 degrees in screen coords
    rad = math.radians(angle_deg) - math.pi/2

    bx = math.cos(rad)
    by = math.sin(rad)

    # Grip (below hilt, going opposite direction)
    grip_len = 7
    for i in range(grip_len):
        gx = int(hilt_x - bx * i)
        gy = int(hilt_y - by * i)
        rect(img, gx-1, gy-1, 3, 3, C_HAIR)
        px(img, gx, gy, C_LEATHER2)
    px(img, int(hilt_x - bx*grip_len),
            int(hilt_y - by*grip_len), C_OUTLINE)

    # Crossguard (perpendicular to blade, at hilt)
    px_  = -by
    py_  =  bx
    for offset in range(-5, 6):
        gx = int(hilt_x + px_ * offset)
        gy = int(hilt_y + py_ * offset)
        if abs(offset) == 5:
            px(img, gx, gy, C_LEATHER2)
        elif abs(offset) == 4:
            px(img, gx, gy, C_LEATHER)
        else:
            px(img, gx, gy, C_LEATHER)
            if offset in (-2, -1, 0, 1, 2):
                px(img, gx, gy-1, C_LEATHER2)

    # Blade
    for i in range(blade_len + 1):
        t = i / max(blade_len, 1)
        bpx = int(hilt_x + bx * i)
        bpy = int(hilt_y + by * i)

        # Taper: 2px wide at base, 1px at tip
        width = 2 if t < 0.85 else 1

        px(img, bpx,   bpy,   C_SILVER2)
        px(img, bpx+1, bpy,   C_SILVER)
        if width == 2:
            px(img, bpx,   bpy+1, C_METAL)
            # Edge highlight
            ex = int(bpx + px_)
            ey = int(bpy + py_)
            px(img, ex, ey, C_SILVER)

    # Tip
    tip_x = int(hilt_x + bx * (blade_len + 1))
    tip_y = int(hilt_y + by * (blade_len + 1))
    px(img, tip_x, tip_y, C_SILVER2)

    # Sword glow aura for frames 2+
    if add_glow:
        for i in range(0, blade_len, 3):
            gpx = int(hilt_x + bx * i)
            gpy = int(hilt_y + by * i)
            glow_r = 3 + (i * 2) // blade_len
            alpha = max(0, 60 - (i * 40) // blade_len)
            for gr in range(1, glow_r+1):
                a = max(0, alpha - gr*15)
                if a > 0:
                    blend_over(img, gpx-gr, gpy,    (*C_ORANGE2[:3], a))
                    blend_over(img, gpx+gr, gpy,    (*C_ORANGE2[:3], a))
                    blend_over(img, gpx,    gpy-gr, (*C_ORANGE2[:3], a))
                    blend_over(img, gpx,    gpy+gr, (*C_ORANGE2[:3], a))
        # Tip sparkle
        alpha = 180
        for d in range(1, 6):
            a = max(0, alpha - d*32)
            blend_over(img, tip_x+d, tip_y,   (*C_ITEM_GLOW[:3], a))
            blend_over(img, tip_x-d, tip_y,   (*C_ITEM_GLOW[:3], a))
            blend_over(img, tip_x,   tip_y+d, (*C_ITEM_GLOW[:3], a))
            blend_over(img, tip_x,   tip_y-d, (*C_ITEM_GLOW[:3], a))

# ── Victory pose arm ─────────────────────────────────────────────────────────

def draw_victory_arm(img, shoulder_x, shoulder_y,
                     elbow_x, elbow_y, hand_x, hand_y,
                     sword_angle, blade_len, add_glow=False):
    """Draw shoulder pauldron + upper arm + forearm + hand + sword.

    The shoulder fill bridge is drawn first across the full shoulder-to-upper-arm
    zone to eliminate any gap between the raised arm and the body.
    """
    # ── Step 1: Shoulder pauldron and bridge ─────────────────────────────────
    draw_armored_shoulder(img, shoulder_x, shoulder_y)

    # Hard-coded anchor fill: paint the shoulder socket region with armor
    # to ensure no transparency gap where arm meets body.
    # Body's shoulder is at cols 92-103, rows 92-102 (from idle analysis).
    # Fill this zone solidly before drawing the arm on top.
    for row in range(shoulder_y - 8, shoulder_y + 6):
        for col in range(shoulder_x - 6, shoulder_x + 6):
            existing = img.getpixel((col, row)) if (0<=col<256 and 0<=row<256) else None
            if existing and existing[3] > 128:
                # Tint existing body pixels with armor orange to blend arm in
                r, g, b, a = existing
                nr = min(255, r + 30)
                ng = min(255, g + 10)
                img.putpixel((col, row), (nr, ng, b, a))

    # Compute the direction from shoulder toward elbow for the bridge
    dx = elbow_x - shoulder_x
    dy = elbow_y - shoulder_y
    length = math.sqrt(dx*dx + dy*dy) or 1

    # Paint a 10px-wide armor bridge for first 16px along arm direction
    bridge_steps = min(16, int(length))
    for i in range(bridge_steps):
        t = i / max(length, 1)
        bx = int(shoulder_x + dx * t)
        by = int(shoulder_y + dy * t)
        nx = -dy / length
        ny =  dx / length
        for off in range(-5, 6):
            xi = int(bx + nx * off)
            yi = int(by + ny * off)
            if abs(off) == 5:
                c = C_OUTLINE
            elif abs(off) == 4:
                c = C_CRIMSON
            elif abs(off) == 3:
                c = C_RED
            else:
                c = C_ORANGE if abs(off) <= 1 else C_RED
            px(img, xi, yi, c)

    # ── Step 2: Full upper arm (shoulder → elbow) ────────────────────────────
    draw_arm(img, shoulder_x, shoulder_y, elbow_x, elbow_y,
             C_RED, C_CRIMSON, C_ORANGE, thickness=6)

    # Elbow joint cap
    rect(img, elbow_x-3, elbow_y-3, 7, 7, C_RED)
    px(img, elbow_x,   elbow_y,   C_ORANGE)
    px(img, elbow_x+1, elbow_y-1, C_ORANGE2)
    px(img, elbow_x-1, elbow_y+1, C_CRIMSON)

    # ── Step 3: Forearm (elbow → hand): exposed skin ─────────────────────────
    draw_arm(img, elbow_x, elbow_y, hand_x, hand_y,
             C_SKIN_M, C_SKIN_D, C_SKIN_L, thickness=4)

    # ── Step 4: Fist ─────────────────────────────────────────────────────────
    rect(img, hand_x-2, hand_y-2, 6, 7, C_SKIN_M)
    hline(img, hand_x-1, hand_y-3, 4, C_SKIN_L)
    hline(img, hand_x-1, hand_y-2, 4, C_SKIN_L)
    px(img, hand_x-2, hand_y+4, C_SKIN_D)
    px(img, hand_x+3, hand_y+4, C_SKIN_D)
    # Outline corners
    px(img, hand_x-2, hand_y-2, C_OUTLINE)
    px(img, hand_x+3, hand_y-2, C_OUTLINE)

    # ── Step 5: Sword ─────────────────────────────────────────────────────────
    draw_sword(img, hand_x+1, hand_y-4, sword_angle, blade_len, add_glow)

# ── Build a victory frame ─────────────────────────────────────────────────────

def build_victory_frame(idle_frame, idle_arr, arm_mask, frame_idx):
    """
    Frame 0: 45° raise — sword pointing upper-right diagonal
    Frame 1: 20° — sword mostly vertical, slight right lean
    Frame 2: 3°  — sword nearly straight up (full extension, glow starts)
    Frame 3: 5°  — hold with slight upward bounce
    """
    out = idle_frame.copy()
    out_arr = np.array(out)

    # Erase LEFT arm (sword arm) from the copy
    for row in range(256):
        for col in range(256):
            if arm_mask[row, col]:
                out_arr[row, col] = [0, 0, 0, 0]

    out = Image.fromarray(out_arr)

    # Left shoulder anchor — precisely measured from idle body analysis:
    # Body top at col 98 starts at row 92 (first opaque pixel after arm erasure).
    # Anchoring here eliminates the floating gap between arm and body.
    shoulder_x = 98
    shoulder_y = 92   # body top at col 98, flush connection point

    if frame_idx == 0:
        # Frame 0: arm just starting to lift — elbow swings rightward and slightly
        # downward from the shoulder (arm was at rest horizontally, now pivoting up).
        # Elbow is right of and level with shoulder; hand is upper-right.
        elbow_x = shoulder_x + 18
        elbow_y = shoulder_y + 4    # elbow drops slightly right/down first
        hand_x  = elbow_x + 12
        hand_y  = elbow_y - 14     # hand already angling upward
        sword_angle = 60            # sword points upper-right
        blade_len   = 32
        add_glow    = False

    elif frame_idx == 1:
        # Mid-raise: elbow high, ~25° from vertical.
        elbow_x = shoulder_x + 10
        elbow_y = shoulder_y - 18
        hand_x  = elbow_x + 5
        hand_y  = elbow_y - 20
        sword_angle = 25
        blade_len   = 38
        add_glow    = False

    elif frame_idx == 2:
        # Full extension: arm nearly vertical, glow on.
        elbow_x = shoulder_x + 3
        elbow_y = shoulder_y - 20
        hand_x  = elbow_x + 1
        hand_y  = elbow_y - 20
        sword_angle = 4
        blade_len   = 44
        add_glow    = True

    else:  # frame_idx == 3
        # Victory hold with 6px upward bounce.
        bounced = Image.new("RGBA", (256, 256), TRANSPARENT)
        bounced.paste(out, (0, -6))
        out = bounced
        shoulder_y -= 6
        elbow_x = shoulder_x + 3
        elbow_y = shoulder_y - 20
        hand_x  = elbow_x + 1
        hand_y  = elbow_y - 18
        sword_angle = 8
        blade_len   = 44
        add_glow    = True

    draw_victory_arm(out, shoulder_x, shoulder_y,
                     elbow_x, elbow_y, hand_x, hand_y,
                     sword_angle, blade_len, add_glow)
    return out

# ── Potion ────────────────────────────────────────────────────────────────────

def draw_potion(img, x, y, glow=False):
    """Draw a SNES-style potion, 12 wide x 18 tall total.
    At 256x256 frame scale this is clearly visible as an item.
    """
    # Cork (wide stopper at top)
    rect(img, x+3, y-3, 6,  3, C_LEATHER)
    hline(img, x+4, y-4, 4, C_LEATHER2)
    hline(img, x+2, y-2, 8, C_OUTLINE)
    px(img, x+3, y-3, C_OUTLINE)
    px(img, x+8, y-3, C_OUTLINE)

    # Neck
    rect(img, x+3, y,   6, 4, C_SILVER)
    px(img, x+3, y,   C_OUTLINE)
    px(img, x+8, y,   C_OUTLINE)
    px(img, x+3, y+3, C_OUTLINE)
    px(img, x+8, y+3, C_OUTLINE)
    hline(img, x+4, y+1, 4, C_SILVER2)  # neck highlight

    # Body colors — vivid green so it reads clearly against red/dark armor
    if glow:
        body  = (80,  230, 140, 255)
        shade = (40,  130, 75,  255)
        hilit = (180, 255, 210, 255)
        liq   = (120, 255, 170, 255)
        liq2  = (160, 255, 200, 255)  # inner glow bright spot
    else:
        body  = (55,  175, 100, 255)
        shade = (28,  90,  52,  255)
        hilit = (110, 215, 155, 255)
        liq   = (70,  200, 120, 255)
        liq2  = liq

    bw = 12
    bh = 13

    # Outer body silhouette (rounded shoulder effect via corner outlines)
    rect(img, x,      y+4, bw,   bh,   body)
    # Top corners cut
    px(img, x,      y+4, C_OUTLINE)
    px(img, x+bw-1, y+4, C_OUTLINE)
    px(img, x,      y+4+bh-1, C_OUTLINE)
    px(img, x+bw-1, y+4+bh-1, C_OUTLINE)

    # Left highlight column
    vline(img, x+1,    y+4, bh, hilit)
    px(img, x+2, y+4, hilit)
    # Right shadow column
    vline(img, x+bw-1, y+4, bh, shade)
    vline(img, x+bw-2, y+5, bh-2, shade)
    # Bottom shadow row
    hline(img, x,      y+4+bh-1, bw, shade)

    # Liquid fill interior
    rect(img, x+3,    y+5, bw-6, bh-3, liq)
    # Inner bright spot (glow/shimmer)
    px(img, x+4, y+6, liq2)
    px(img, x+4, y+7, liq2)
    px(img, x+5, y+6, liq2)

    # Full outline border
    for i in range(bw):
        px(img, x+i, y+4,       C_OUTLINE)  # top
        px(img, x+i, y+4+bh-1,  C_OUTLINE)  # bottom
    for i in range(bh):
        px(img, x,      y+4+i, C_OUTLINE)   # left
        px(img, x+bw-1, y+4+i, C_OUTLINE)   # right

    if glow:
        # Strong visible glow ring around entire potion
        potcx = x + bw//2
        potcy = y + 4 + bh//2
        for r in range(12, 3, -1):
            alpha = max(0, 80 - r*7)
            for angle_i in range(24):
                angle = angle_i * (2*math.pi/24)
                gx = int(potcx + r * math.cos(angle))
                gy = int(potcy + r * math.sin(angle))
                blend_over(img, gx, gy, (*C_ITEM_GLOW[:3], alpha))
        # Extra bright inner halo
        for r in range(4, 1, -1):
            alpha = max(0, 120 - r*30)
            for angle_i in range(16):
                angle = angle_i * (2*math.pi/16)
                gx = int(potcx + r * math.cos(angle))
                gy = int(potcy + r * math.sin(angle))
                blend_over(img, gx, gy, (180, 255, 210, alpha))

def draw_sparkle(img, cx, cy, intensity=1.0):
    """Large 8-axis sparkle burst — must be clearly visible at SNES scale.
    Total extent: 14px arms + 3px core + 16px outer glow = ~35px wide.
    """
    # Bright 5x5 solid core
    rect(img, cx-3, cy-3, 7, 7, (*C_ITEM_BRIGHT[:3], int(220*intensity)))
    rect(img, cx-2, cy-2, 5, 5, (*C_ITEM_GLOW[:3],   int(240*intensity)))
    rect(img, cx-1, cy-1, 3, 3, (255, 255, 255,       int(255*intensity)))
    px(img, cx, cy, (255, 255, 255, 255))

    # 4 cardinal arms — 14 pixels long, thick (2px) at base tapering to 1px
    for d in range(1, 15):
        a = max(0, int((230 - d*16)*intensity))
        col = C_ITEM_GLOW if d < 7 else C_ITEM_BRIGHT
        # Horizontal arm (2px tall at base)
        px(img, cx+d, cy,   (*col[:3], a))
        px(img, cx-d, cy,   (*col[:3], a))
        px(img, cx,   cy+d, (*col[:3], a))
        px(img, cx,   cy-d, (*col[:3], a))
        if d < 6:  # fat base
            px(img, cx+d, cy+1, (*col[:3], max(0, a-60)))
            px(img, cx+d, cy-1, (*col[:3], max(0, a-60)))
            px(img, cx-d, cy+1, (*col[:3], max(0, a-60)))
            px(img, cx-d, cy-1, (*col[:3], max(0, a-60)))
            px(img, cx+1, cy+d, (*col[:3], max(0, a-60)))
            px(img, cx-1, cy+d, (*col[:3], max(0, a-60)))
            px(img, cx+1, cy-d, (*col[:3], max(0, a-60)))
            px(img, cx-1, cy-d, (*col[:3], max(0, a-60)))

    # 4 diagonal arms — 9 pixels long
    for d in range(1, 10):
        a = max(0, int((190 - d*20)*intensity))
        px(img, cx+d, cy-d, (*C_ITEM_GLOW[:3], a))
        px(img, cx-d, cy-d, (*C_ITEM_GLOW[:3], a))
        px(img, cx+d, cy+d, (*C_ITEM_GLOW[:3], a))
        px(img, cx-d, cy+d, (*C_ITEM_GLOW[:3], a))

    # Soft outer glow ring at radius 16
    for angle_i in range(24):
        angle = angle_i * (2*math.pi/24)
        gx = int(cx + 16 * math.cos(angle))
        gy = int(cy + 16 * math.sin(angle))
        blend_over(img, gx, gy, (*C_ITEM_GLOW[:3], int(50*intensity)))
    # Second ring at radius 11
    for angle_i in range(20):
        angle = angle_i * (2*math.pi/20)
        gx = int(cx + 11 * math.cos(angle))
        gy = int(cy + 11 * math.sin(angle))
        blend_over(img, gx, gy, (*C_ITEM_GLOW[:3], int(90*intensity)))

# ── Item right arm (character's right = viewer's left) ───────────────────────
#
# In idle, the right side arm (viewer left) is tucked at cols 116-145, rows 93-135.
# We erase this region and redraw the arm in the desired pose.
#
# However, erasing cols 116-145 would destroy part of the torso.
# Approach: only erase the RIGHTMOST column range that is clearly arm, not torso.
# The torso body is roughly cols 92-118. The arm extension beyond 118 is safe to erase.
# For the arm connector at cols 116-118, we only erase pixels that are skin-colored.

def build_right_arm_erase_mask(idle_arr):
    """
    Mark pixels that belong to the right arm (viewer's left side of character).
    These are skin/armored pixels at cols 116-145, rows 93-135,
    specifically those NOT part of the torso/chest.
    """
    mask = np.zeros((256, 256), dtype=bool)
    # Safe zone: cols 119-145 are clearly arm territory at rows 93-135
    for row in range(93, 136):
        for col in range(119, 146):
            if idle_arr[row, col, 3] > 128:
                mask[row, col] = True
    # At cols 116-118, only erase skin-toned pixels (arm, not torso plate)
    for row in range(93, 130):
        for col in range(116, 119):
            r, g, b, a = idle_arr[row, col]
            if a < 128:
                continue
            # Skin-like (arm) vs dark armor (torso)
            # Skin: r>150, g>100, b>60
            # Also orange arm accents
            if (r > 150 and g > 100 and b > 60) or (r > 220 and g > 80 and b < 80):
                mask[row, col] = True
    return mask

def draw_item_arm(img, shoulder_x, shoulder_y,
                  elbow_x, elbow_y, hand_x, hand_y):
    """Draw right arm segment for item animation."""
    # Small pauldron on this side
    rect(img, shoulder_x-2, shoulder_y-2, 7, 4, C_RED)
    hline(img, shoulder_x-1, shoulder_y-3, 5, C_ORANGE)

    # Upper arm
    draw_arm(img, shoulder_x, shoulder_y, elbow_x, elbow_y,
             C_RED, C_CRIMSON, C_ORANGE, thickness=4)
    # Elbow
    rect(img, elbow_x-2, elbow_y-2, 5, 5, C_SKIN_M)
    px(img, elbow_x, elbow_y, C_SKIN_L)

    # Forearm
    draw_arm(img, elbow_x, elbow_y, hand_x, hand_y,
             C_SKIN_M, C_SKIN_D, C_SKIN_L, thickness=4)

    # Hand
    rect(img, hand_x-2, hand_y-2, 6, 6, C_SKIN_M)
    hline(img, hand_x-1, hand_y-3, 4, C_SKIN_L)
    px(img, hand_x-2, hand_y+3, C_SKIN_D)

# ── Build an item frame ───────────────────────────────────────────────────────

def build_item_frame(idle_frame, idle_arr, right_arm_mask, frame_idx):
    """
    Frame 0: reaching into belt
    Frame 1: item just pulled out (small potion, no glow)
    Frame 2: item held up glowing
    Frame 3: item used, sparkle, arm returning
    """
    out = idle_frame.copy()
    out_arr = np.array(out)

    # Erase right arm
    for row in range(256):
        for col in range(256):
            if right_arm_mask[row, col]:
                out_arr[row, col] = [0, 0, 0, 0]

    out = Image.fromarray(out_arr)

    # Right shoulder anchor (viewer's left side of character body)
    # In idle, shoulder is at approximately col 120, row 98
    shoulder_x = 120
    shoulder_y = 98

    # Belt/pouch position
    belt_x = 132
    belt_y = 122

    if frame_idx == 0:
        # Arm reaches down and to the right, hand dipping into belt pouch.
        # Elbow is close to body, hand drops toward waist-right area.
        elbow_x = shoulder_x + 8
        elbow_y = shoulder_y + 12
        hand_x  = belt_x + 4     # ~136, waist level
        hand_y  = belt_y - 2     # ~120
        draw_item_arm(out, shoulder_x, shoulder_y, elbow_x, elbow_y, hand_x, hand_y)
        # Draw a small pouch/belt indicator at the hand destination
        rect(out, hand_x-1, hand_y+1, 5, 4, C_LEATHER)
        hline(out, hand_x,   hand_y,   3, C_LEATHER2)
        px(out, hand_x-1, hand_y+1, C_OUTLINE)
        px(out, hand_x+3, hand_y+1, C_OUTLINE)
        px(out, hand_x-1, hand_y+4, C_OUTLINE)
        px(out, hand_x+3, hand_y+4, C_OUTLINE)

    elif frame_idx == 1:
        # Arm swings forward-up, pulling item from pouch.
        # Arm extended right, hand at mid-high level. Potion clearly held.
        elbow_x = shoulder_x + 16
        elbow_y = shoulder_y + 4
        hand_x  = elbow_x + 12
        hand_y  = elbow_y - 10
        draw_item_arm(out, shoulder_x, shoulder_y, elbow_x, elbow_y, hand_x, hand_y)
        # Potion just pulled — no full glow yet, but draw with faint warmth hint
        draw_potion(out, hand_x + 2, hand_y - 20, glow=False)
        # Tiny hint glow (just 2px warmth around the bottle)
        pot_cx = hand_x + 2 + 6   # bottle centre x
        pot_cy = hand_y - 20 + 10 # bottle centre y
        for d in range(1, 4):
            blend_over(out, pot_cx+d, pot_cy,  (*C_ITEM_GLOW[:3], 35))
            blend_over(out, pot_cx-d, pot_cy,  (*C_ITEM_GLOW[:3], 35))
            blend_over(out, pot_cx,   pot_cy+d,(*C_ITEM_GLOW[:3], 35))
            blend_over(out, pot_cx,   pot_cy-d,(*C_ITEM_GLOW[:3], 35))

    elif frame_idx == 2:
        # Arm fully extended forward-up, item held high, glowing brightly.
        elbow_x = shoulder_x + 20
        elbow_y = shoulder_y - 6
        hand_x  = elbow_x + 12
        hand_y  = elbow_y - 16
        draw_item_arm(out, shoulder_x, shoulder_y, elbow_x, elbow_y, hand_x, hand_y)
        # Glowing potion above hand — centred in clear space
        draw_potion(out, hand_x + 2, hand_y - 22, glow=True)

    else:  # frame_idx == 3
        # Item consumed: arm lowering, open hand, sparkle where potion was.
        elbow_x = shoulder_x + 14
        elbow_y = shoulder_y + 2
        hand_x  = elbow_x + 8
        hand_y  = elbow_y - 8
        draw_item_arm(out, shoulder_x, shoulder_y, elbow_x, elbow_y, hand_x, hand_y)
        # Sparkle above the frame-3 hand, where the item was just consumed.
        # Hand in frame 3 is at (~142, ~92). Sparkle just above and right.
        sparkle_cx = hand_x + 4    # ~146 — over extended open hand
        sparkle_cy = hand_y - 14   # ~78 — above hand, in open air
        draw_sparkle(out, sparkle_cx, sparkle_cy, intensity=1.0)

    return out

# ── Assemble strip ────────────────────────────────────────────────────────────

def assemble_strip(frames, out_path):
    assert len(frames) == 4
    strip = Image.new("RGBA", (1024, 256), TRANSPARENT)
    for i, frame in enumerate(frames):
        assert frame.size == (256, 256), f"Frame {i}: {frame.size}"
        strip.paste(frame, (i*256, 0))
    strip.save(out_path, "PNG")
    print(f"  Saved: {out_path}")

# ── Verify output ─────────────────────────────────────────────────────────────

def verify_strip(path, expected_frames=4):
    img = Image.open(path).convert("RGBA")
    assert img.size == (1024, 256), f"Expected 1024x256, got {img.size}"
    arr = np.array(img)
    # Check each frame has some non-transparent pixels
    for i in range(expected_frames):
        frame = arr[:, i*256:(i+1)*256, :]
        opaque = (frame[:, :, 3] > 128).sum()
        assert opaque > 100, f"Frame {i} has too few opaque pixels: {opaque}"
        print(f"  Frame {i}: {opaque} opaque pixels — OK")
    print(f"  Dimensions: {img.size} — OK")

# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    idle_frame = load_idle()
    idle_arr   = np.array(idle_frame)

    print("Building arm masks...")
    left_arm_mask  = build_arm_mask(idle_arr)
    right_arm_mask = build_right_arm_erase_mask(idle_arr)
    print(f"  Left arm mask: {left_arm_mask.sum()} pixels")
    print(f"  Right arm mask: {right_arm_mask.sum()} pixels")

    print("\nGenerating VICTORY animation (4 frames)...")
    victory_frames = [
        build_victory_frame(idle_frame, idle_arr, left_arm_mask, i)
        for i in range(4)
    ]
    assemble_strip(victory_frames, OUT_VICTORY)
    print("Verifying victory strip...")
    verify_strip(OUT_VICTORY)

    print("\nGenerating ITEM animation (4 frames)...")
    item_frames = [
        build_item_frame(idle_frame, idle_arr, right_arm_mask, i)
        for i in range(4)
    ]
    assemble_strip(item_frames, OUT_ITEM)
    print("Verifying item strip...")
    verify_strip(OUT_ITEM)

    print("\nDone.")

if __name__ == "__main__":
    main()
