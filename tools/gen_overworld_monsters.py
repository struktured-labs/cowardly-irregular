#!/usr/bin/env python3
"""
Generate SNES-style overworld monster sprite sheets for Cowardly Irregular.

Sheet layout per monster (RPG Maker / classic JRPG convention):
  Row 0: walk_down  (4 frames, left-foot, neutral, right-foot, neutral)
  Row 1: walk_left  (4 frames)
  Row 2: walk_right (4 frames, mirrored from left)
  Row 3: walk_up    (4 frames)

Frame size: 32x32 pixels
Sheet size: 128x128 pixels per monster

Output: assets/sprites/monsters/overworld/<monster_id>.png
"""

from PIL import Image, ImageDraw
import os
import math

FRAME = 32
COLS = 4
ROWS = 4
SHEET_W = FRAME * COLS   # 128
SHEET_H = FRAME * ROWS   # 128

OUT_DIR = "/home/struktured/projects/cowardly-irregular-sprite-gen/assets/sprites/monsters/overworld"
os.makedirs(OUT_DIR, exist_ok=True)

# ──────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────

def new_frame():
    return Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))

def new_sheet():
    return Image.new("RGBA", (SHEET_W, SHEET_H), (0, 0, 0, 0))

def place(sheet, frame, col, row):
    sheet.paste(frame, (col * FRAME, row * FRAME), frame)

def shade(c, f):
    r, g, b, a = c
    return (min(255, max(0, int(r*f))), min(255, max(0, int(g*f))), min(255, max(0, int(b*f))), a)

def outline(c):
    return shade(c, 0.25)

def hi(c):
    return shade(c, 1.5)

def px(draw, x, y, c):
    """Draw a single pixel."""
    draw.point((x, y), fill=c)

def rect(draw, x, y, w, h, c):
    draw.rectangle([x, y, x+w-1, y+h-1], fill=c)

def hline(draw, x, y, w, c):
    draw.line([(x, y), (x+w-1, y)], fill=c)

def vline(draw, x, y, h, c):
    draw.line([(x, y), (x, y+h-1)], fill=c)

def ellipse(draw, x, y, w, h, c, ol=None):
    if ol:
        draw.ellipse([x-1, y-1, x+w, y+h], fill=ol)
    draw.ellipse([x, y, x+w-1, y+h-1], fill=c)

def mirror_frame(frame):
    """Horizontally flip a frame (for right-facing from left-facing)."""
    return frame.transpose(Image.FLIP_LEFT_RIGHT)

def build_walk_rows(draw_down_fn, draw_left_fn):
    """
    Given callables that return 4 frames each for down and left directions,
    build all 4 rows of the sheet.
    Returns list of (col, row, frame) tuples.
    """
    cells = []
    down_frames = draw_down_fn()
    left_frames = draw_left_fn()
    right_frames = [mirror_frame(f) for f in left_frames]
    # Up: reuse down frames with slight modification handled inside
    # For simplicity, up is drawn by the same down_fn variant
    up_frames = draw_down_fn(facing="up")

    for col, f in enumerate(down_frames):
        cells.append((col, 0, f))
    for col, f in enumerate(left_frames):
        cells.append((col, 1, f))
    for col, f in enumerate(right_frames):
        cells.append((col, 2, f))
    for col, f in enumerate(up_frames):
        cells.append((col, 3, f))
    return cells

def assemble(cells):
    sheet = new_sheet()
    for col, row, frame in cells:
        place(sheet, frame, col, row)
    return sheet

# ──────────────────────────────────────────────────────────────
# SLIME
# Small green blob. Squish on step frames (0,2), stretch on neutral (1,3).
# Palette: dark outline, mid green, bright green highlight, white eye dots.
# ──────────────────────────────────────────────────────────────

SLIME_DARK  = (20,  80,  20,  255)
SLIME_MID   = (60, 160,  60,  255)
SLIME_HI    = (120, 220, 100, 255)
SLIME_SHEEN = (200, 255, 180, 255)
SLIME_OL    = (10,  40,  10,  255)
SLIME_EYE   = (255, 255, 255, 255)
SLIME_PUPIL = (20,  40,  20,  255)

def draw_slime_body(draw, cx, cy, squish=False):
    """Draw slime centered at cx, cy. squish=True for compressed step."""
    if squish:
        w, h = 14, 10
    else:
        w, h = 12, 13

    # Outline
    draw.ellipse([cx-w-1, cy-h-1, cx+w+1, cy+h+1], fill=SLIME_OL)
    # Body
    draw.ellipse([cx-w, cy-h, cx+w, cy+h], fill=SLIME_MID)
    # Highlight
    draw.ellipse([cx-w+2, cy-h+1, cx-1, cy-h//2], fill=SLIME_HI)
    draw.ellipse([cx-w+4, cy-h+2, cx-3, cy-h+5], fill=SLIME_SHEEN)
    # Eyes
    ey = cy - h//2 + 1
    draw.ellipse([cx-5, ey, cx-2, ey+3], fill=SLIME_EYE)
    draw.ellipse([cx+2, ey, cx+5, ey+3], fill=SLIME_EYE)
    draw.point((cx-4, ey+1), fill=SLIME_PUPIL)
    draw.point((cx+3, ey+1), fill=SLIME_PUPIL)

def slime_frames(facing="down"):
    frames = []
    # 4 walk frames: step-L, neutral, step-R, neutral
    squish_pattern = [True, False, True, False]
    bob_pattern    = [0, -1, 0, -1]
    for i in range(4):
        f = new_frame()
        d = ImageDraw.Draw(f)
        cy = 22 + bob_pattern[i]
        draw_slime_body(d, 16, cy, squish=squish_pattern[i])
        frames.append(f)
    return frames

def gen_slime():
    cells = []
    for row, facing in enumerate(["down", "left", "right", "up"]):
        sq = [True, False, True, False]
        bob = [0, -1, 0, -1]
        for col in range(4):
            f = new_frame()
            d = ImageDraw.Draw(f)
            cy = 22 + bob[col]
            draw_slime_body(d, 16, cy, squish=sq[col])
            cells.append((col, row, f))
    return assemble(cells)

# ──────────────────────────────────────────────────────────────
# BAT
# Small purple/brown bat, hovers. Wing flap = wings up vs down.
# ──────────────────────────────────────────────────────────────

BAT_BODY  = (90,  50, 100, 255)
BAT_WING  = (70,  30,  80, 255)
BAT_HI    = (140, 100, 150, 255)
BAT_OL    = (30,  10,  40, 255)
BAT_EYE   = (255, 200,  50, 255)
BAT_FANG  = (240, 240, 240, 255)

def draw_bat(draw, cx, cy, wings_up=False, facing="down"):
    # Body — small oval
    draw.ellipse([cx-4, cy-4, cx+4, cy+4], fill=BAT_OL)
    draw.ellipse([cx-3, cy-4, cx+3, cy+4], fill=BAT_BODY)
    draw.ellipse([cx-2, cy-5, cx+2, cy-2], fill=BAT_HI)  # head top

    # Wings
    wing_y = cy - 2 if wings_up else cy + 2
    # Left wing
    lw = [(cx-3, cy), (cx-12, wing_y-4), (cx-14, wing_y+3), (cx-5, cy+2)]
    rw = [(cx+3, cy), (cx+12, wing_y-4), (cx+14, wing_y+3), (cx+5, cy+2)]
    draw.polygon(lw, fill=BAT_OL)
    lw_inner = [(cx-3, cy), (cx-11, wing_y-3), (cx-13, wing_y+2), (cx-5, cy+1)]
    draw.polygon(lw_inner, fill=BAT_WING)
    draw.polygon(rw, fill=BAT_OL)
    rw_inner = [(cx+3, cy), (cx+11, wing_y-3), (cx+13, wing_y+2), (cx+5, cy+1)]
    draw.polygon(rw_inner, fill=BAT_WING)

    # Eyes (visible on down/side, dots on up)
    if facing != "up":
        draw.point((cx-2, cy-3), fill=BAT_EYE)
        draw.point((cx+2, cy-3), fill=BAT_EYE)
    # Fang
    if facing in ("down", "left", "right"):
        draw.point((cx-1, cy+3), fill=BAT_FANG)
        draw.point((cx+1, cy+3), fill=BAT_FANG)

def gen_bat():
    cells = []
    # Bats hover 2px higher on up-wing frames
    hover = [14, 12, 14, 12]
    wings_up = [False, True, False, True]
    for row, facing in enumerate(["down", "left", "right", "up"]):
        for col in range(4):
            f = new_frame()
            d = ImageDraw.Draw(f)
            cy = hover[col]
            draw_bat(d, 16, cy, wings_up=wings_up[col], facing=facing)
            # Mirror left col for right row
            if facing == "right":
                f = mirror_frame(f)
            cells.append((col, row, f))
    return assemble(cells)

# ──────────────────────────────────────────────────────────────
# GOBLIN
# Small green humanoid, hunched, crude club. Shuffling walk.
# ──────────────────────────────────────────────────────────────

GOB_SKIN  = (80, 150,  60, 255)
GOB_HI    = (120, 200, 90, 255)
GOB_OL    = (30,  60,  20, 255)
GOB_EYE   = (255, 220, 50, 255)
GOB_CLOTH = (100,  60,  30, 255)
GOB_CLUB  = (100,  70,  40, 255)
GOB_CLUB_HI=(140, 110,  70, 255)
GOB_TOOTH = (230, 230, 180, 255)

def draw_goblin_down(draw, cx, cy, step=0):
    """step: 0=left foot forward, 1=neutral, 2=right foot forward, 3=neutral"""
    # Body (torso, hunched — shift upper body forward)
    # Legs
    foot_offsets = [(-3, 4, 3, 0), (-1, 2, 1, 2), (3, 4, -3, 0), (-1, 2, 1, 2)]
    lx, ly, rx, ry = foot_offsets[step]

    # Left leg
    draw.rectangle([cx-4+lx, cy+8, cx-2+lx, cy+11+ly], fill=GOB_OL)
    draw.rectangle([cx-3+lx, cy+8, cx-1+lx, cy+11+ly], fill=GOB_SKIN)
    # Right leg
    draw.rectangle([cx+2+rx, cy+8, cx+4+rx, cy+11+ry], fill=GOB_OL)
    draw.rectangle([cx+1+rx, cy+8, cx+3+rx, cy+11+ry], fill=GOB_SKIN)
    # Feet
    draw.rectangle([cx-5+lx, cy+11+ly, cx-1+lx, cy+13+ly], fill=GOB_OL)
    draw.rectangle([cx+1+rx, cy+11+ry, cx+5+rx, cy+13+ry], fill=GOB_OL)

    # Loin cloth
    draw.rectangle([cx-4, cy+6, cx+4, cy+9], fill=GOB_OL)
    draw.rectangle([cx-3, cy+6, cx+3, cy+9], fill=GOB_CLOTH)

    # Torso (hunched, lean forward)
    draw.rectangle([cx-4, cy-1, cx+4, cy+7], fill=GOB_OL)
    draw.rectangle([cx-3, cy, cx+3, cy+7], fill=GOB_SKIN)

    # Head
    draw.ellipse([cx-5, cy-10, cx+5, cy+1], fill=GOB_OL)
    draw.ellipse([cx-4, cy-9, cx+4, cy], fill=GOB_SKIN)
    # Ears
    draw.ellipse([cx-7, cy-7, cx-4, cy-4], fill=GOB_OL)
    draw.ellipse([cx-6, cy-7, cx-4, cy-5], fill=GOB_SKIN)
    draw.ellipse([cx+4, cy-7, cx+7, cy-4], fill=GOB_OL)
    draw.ellipse([cx+4, cy-7, cx+6, cy-5], fill=GOB_SKIN)

    # Eyes
    draw.point((cx-2, cy-5), fill=GOB_EYE)
    draw.point((cx+2, cy-5), fill=GOB_EYE)

    # Teeth
    draw.rectangle([cx-2, cy-2, cx-1, cy-1], fill=GOB_TOOTH)
    draw.rectangle([cx+1, cy-2, cx+2, cy-1], fill=GOB_TOOTH)

    # Club (right hand)
    club_x = cx + 7
    club_y = cy + 1 + (1 if step in (0,2) else 0)
    draw.rectangle([club_x, club_y+2, club_x+2, club_y+9], fill=GOB_OL)
    draw.rectangle([club_x+1, club_y+2, club_x+2, club_y+9], fill=GOB_CLUB)
    draw.ellipse([club_x-1, club_y-1, club_x+4, club_y+4], fill=GOB_OL)
    draw.ellipse([club_x, club_y, club_x+3, club_y+3], fill=GOB_CLUB_HI)

def draw_goblin_side(draw, cx, cy, step=0):
    """Side-facing goblin."""
    foot_x = [0, 1, 0, -1]
    bob = [0, -1, 0, -1]
    bx = foot_x[step]
    by = bob[step]

    # Legs (two visible, front and back)
    draw.rectangle([cx-2+bx, cy+8, cx+0+bx, cy+12], fill=GOB_OL)
    draw.rectangle([cx-1+bx, cy+8, cx+0+bx, cy+12], fill=GOB_SKIN)
    draw.rectangle([cx+1-bx, cy+8, cx+3-bx, cy+11], fill=GOB_OL)
    draw.rectangle([cx+1-bx, cy+8, cx+2-bx, cy+11], fill=GOB_SKIN)
    # Foot
    draw.rectangle([cx-3+bx, cy+12, cx+1+bx, cy+14], fill=GOB_OL)

    # Cloth
    draw.rectangle([cx-3, cy+6, cx+3, cy+9], fill=GOB_OL)
    draw.rectangle([cx-2, cy+6, cx+2, cy+9], fill=GOB_CLOTH)

    # Body
    draw.rectangle([cx-3, cy-1, cx+3, cy+7], fill=GOB_OL)
    draw.rectangle([cx-2, cy, cx+2, cy+7], fill=GOB_SKIN)

    # Head
    draw.ellipse([cx-4, cy-10, cx+4, cy+1], fill=GOB_OL)
    draw.ellipse([cx-3, cy-9, cx+3, cy], fill=GOB_SKIN)
    # Ear (one visible)
    draw.ellipse([cx+3, cy-7, cx+6, cy-4], fill=GOB_OL)
    draw.ellipse([cx+3, cy-7, cx+5, cy-5], fill=GOB_SKIN)
    # Eye
    draw.point((cx+1, cy-5), fill=GOB_EYE)

    # Club
    draw.rectangle([cx+4, cy+by, cx+6, cy+7+by], fill=GOB_OL)
    draw.rectangle([cx+4, cy+by, cx+5, cy+7+by], fill=GOB_CLUB)
    draw.ellipse([cx+3, cy-2+by, cx+8, cy+3+by], fill=GOB_OL)
    draw.ellipse([cx+4, cy-1+by, cx+7, cy+2+by], fill=GOB_CLUB_HI)

def draw_goblin_up(draw, cx, cy, step=0):
    """Back-facing goblin."""
    foot_offsets = [(-3, 4, 3, 0), (-1, 2, 1, 2), (3, 4, -3, 0), (-1, 2, 1, 2)]
    lx, ly, rx, ry = foot_offsets[step]
    draw.rectangle([cx-4+lx, cy+8, cx-2+lx, cy+11+ly], fill=GOB_OL)
    draw.rectangle([cx-3+lx, cy+8, cx-1+lx, cy+11+ly], fill=GOB_SKIN)
    draw.rectangle([cx+2+rx, cy+8, cx+4+rx, cy+11+ry], fill=GOB_OL)
    draw.rectangle([cx+1+rx, cy+8, cx+3+rx, cy+11+ry], fill=GOB_SKIN)
    draw.rectangle([cx-5+lx, cy+11+ly, cx-1+lx, cy+13+ly], fill=GOB_OL)
    draw.rectangle([cx+1+rx, cy+11+ry, cx+5+rx, cy+13+ry], fill=GOB_OL)
    draw.rectangle([cx-4, cy+6, cx+4, cy+9], fill=GOB_OL)
    draw.rectangle([cx-3, cy+6, cx+3, cy+9], fill=GOB_CLOTH)
    draw.rectangle([cx-4, cy-1, cx+4, cy+7], fill=GOB_OL)
    draw.rectangle([cx-3, cy, cx+3, cy+7], fill=GOB_SKIN)
    draw.ellipse([cx-5, cy-10, cx+5, cy+1], fill=GOB_OL)
    draw.ellipse([cx-4, cy-9, cx+4, cy], fill=GOB_SKIN)
    # No face details visible from back
    # Spiky back of head
    draw.rectangle([cx-2, cy-11, cx-1, cy-9], fill=GOB_OL)
    draw.rectangle([cx+1, cy-11, cx+2, cy-9], fill=GOB_OL)

def gen_goblin():
    cells = []
    for col in range(4):
        f = new_frame(); d = ImageDraw.Draw(f)
        draw_goblin_down(d, 14, 16, step=col)
        cells.append((col, 0, f))
    for col in range(4):
        f = new_frame(); d = ImageDraw.Draw(f)
        draw_goblin_side(d, 14, 16, step=col)
        cells.append((col, 1, f))
    for col in range(4):
        f = new_frame(); d = ImageDraw.Draw(f)
        fr = mirror_frame(cells[4+col][2])  # mirror left for right
        cells.append((col, 2, fr))
    for col in range(4):
        f = new_frame(); d = ImageDraw.Draw(f)
        draw_goblin_up(d, 14, 16, step=col)
        cells.append((col, 3, f))
    return assemble(cells)

# ──────────────────────────────────────────────────────────────
# WOLF
# Gray/brown canine, 4-legged trot. Head bob.
# ──────────────────────────────────────────────────────────────

WOLF_FUR   = (110, 100,  90, 255)
WOLF_DARK  = ( 70,  60,  50, 255)
WOLF_HI    = (160, 145, 130, 255)
WOLF_OL    = ( 40,  30,  20, 255)
WOLF_BELLY = (180, 165, 140, 255)
WOLF_EYE   = (220, 160,  20, 255)
WOLF_NOSE  = ( 50,  30,  20, 255)
WOLF_TONGUE= (200,  80,  80, 255)

def draw_wolf_side(draw, cx, cy, step=0):
    """Wolf in side view, trotting."""
    # Leg positions vary by trot step
    # step 0: L-front/R-back forward; step 1: neutral; step 2: R-front/L-back forward; step 3: neutral
    bob = [0, -1, 0, -1]
    by = bob[step]

    leg_fwd = 3
    leg_bk = 2
    if step == 0:
        lfx, lbx = leg_fwd, -leg_bk
    elif step == 2:
        lfx, lbx = -leg_bk, leg_fwd
    else:
        lfx, lbx = 0, 0

    # Body
    body_x, body_y = cx - 8, cy + by
    draw.ellipse([body_x-1, body_y-4-1, body_x+17, body_y+6], fill=WOLF_OL)
    draw.ellipse([body_x, body_y-4, body_x+16, body_y+5], fill=WOLF_FUR)
    # Belly
    draw.ellipse([body_x+2, body_y+1, body_x+12, body_y+5], fill=WOLF_BELLY)

    # Head
    hx, hy = cx + 7, cy - 5 + by
    draw.ellipse([hx-4, hy-5, hx+6, hy+4], fill=WOLF_OL)
    draw.ellipse([hx-3, hy-4, hx+5, hy+3], fill=WOLF_FUR)
    # Snout
    draw.ellipse([hx+2, hy-1, hx+7, hy+3], fill=WOLF_OL)
    draw.ellipse([hx+3, hy, hx+7, hy+2], fill=WOLF_BELLY)
    draw.point((hx+6, hy), fill=WOLF_NOSE)
    # Eye
    draw.point((hx, hy-2), fill=WOLF_EYE)
    # Ear
    draw.polygon([(hx-1, hy-4), (hx-3, hy-8), (hx+2, hy-5)], fill=WOLF_OL)
    draw.polygon([(hx-1, hy-4), (hx-2, hy-7), (hx+1, hy-5)], fill=WOLF_FUR)

    # Tail
    tx = cx - 8
    tail_bob = [2, 0, 2, 0]
    ty = cy - 2 + tail_bob[step]
    draw.line([(tx, cy+by), (tx-4, ty)], fill=WOLF_OL, width=3)
    draw.line([(tx, cy+by), (tx-4, ty)], fill=WOLF_FUR, width=2)

    # Front legs
    draw.rectangle([cx+3+lfx, cy+5+by, cx+5+lfx, cy+13+by], fill=WOLF_OL)
    draw.rectangle([cx+3+lfx, cy+5+by, cx+4+lfx, cy+12+by], fill=WOLF_DARK)
    # Back legs
    draw.rectangle([cx-5+lbx, cy+5+by, cx-3+lbx, cy+13+by], fill=WOLF_OL)
    draw.rectangle([cx-5+lbx, cy+5+by, cx-4+lbx, cy+12+by], fill=WOLF_DARK)

def draw_wolf_down(draw, cx, cy, step=0):
    """Wolf from front/below — shows face and two front paws."""
    bob = [0, -1, 0, -1]
    by = bob[step]
    paw_spread = [3, 2, 3, 2]
    ps = paw_spread[step]

    # Body mass
    draw.ellipse([cx-7, cy-2+by, cx+7, cy+9+by], fill=WOLF_OL)
    draw.ellipse([cx-6, cy-2+by, cx+6, cy+8+by], fill=WOLF_FUR)
    draw.ellipse([cx-4, cy+2+by, cx+4, cy+8+by], fill=WOLF_BELLY)

    # Head
    draw.ellipse([cx-6, cy-12+by, cx+6, cy+0+by], fill=WOLF_OL)
    draw.ellipse([cx-5, cy-11+by, cx+5, cy-1+by], fill=WOLF_FUR)
    # Snout
    draw.ellipse([cx-3, cy-4+by, cx+3, cy+1+by], fill=WOLF_OL)
    draw.ellipse([cx-2, cy-4+by, cx+2, cy], fill=WOLF_BELLY)
    draw.ellipse([cx-1, cy-2+by, cx+1, cy+by], fill=WOLF_NOSE)
    # Eyes
    draw.point((cx-3, cy-7+by), fill=WOLF_EYE)
    draw.point((cx+3, cy-7+by), fill=WOLF_EYE)
    # Ears
    draw.polygon([(cx-5, cy-10+by), (cx-7, cy-14+by), (cx-2, cy-11+by)], fill=WOLF_OL)
    draw.polygon([(cx+5, cy-10+by), (cx+7, cy-14+by), (cx+2, cy-11+by)], fill=WOLF_OL)

    # Paws
    draw.ellipse([cx-ps-4, cy+9+by, cx-ps, cy+13+by], fill=WOLF_OL)
    draw.ellipse([cx-ps-3, cy+9+by, cx-ps, cy+12+by], fill=WOLF_DARK)
    draw.ellipse([cx+ps, cy+9+by, cx+ps+4, cy+13+by], fill=WOLF_OL)
    draw.ellipse([cx+ps, cy+9+by, cx+ps+3, cy+12+by], fill=WOLF_DARK)

def draw_wolf_up(draw, cx, cy, step=0):
    """Wolf from back."""
    bob = [0, -1, 0, -1]
    by = bob[step]
    paw_spread = [3, 2, 3, 2]
    ps = paw_spread[step]

    draw.ellipse([cx-7, cy-2+by, cx+7, cy+9+by], fill=WOLF_OL)
    draw.ellipse([cx-6, cy-2+by, cx+6, cy+8+by], fill=WOLF_FUR)

    # Head (back)
    draw.ellipse([cx-6, cy-12+by, cx+6, cy+0+by], fill=WOLF_OL)
    draw.ellipse([cx-5, cy-11+by, cx+5, cy-1+by], fill=WOLF_DARK)
    # Ears
    draw.polygon([(cx-5, cy-10+by), (cx-7, cy-14+by), (cx-2, cy-11+by)], fill=WOLF_OL)
    draw.polygon([(cx-5, cy-10+by), (cx-6, cy-13+by), (cx-2, cy-11+by)], fill=WOLF_FUR)
    draw.polygon([(cx+5, cy-10+by), (cx+7, cy-14+by), (cx+2, cy-11+by)], fill=WOLF_OL)
    draw.polygon([(cx+5, cy-10+by), (cx+6, cy-13+by), (cx+2, cy-11+by)], fill=WOLF_FUR)

    # Tail
    draw.line([(cx, cy), (cx+3, cy-5+by)], fill=WOLF_OL, width=3)
    draw.line([(cx, cy), (cx+3, cy-5+by)], fill=WOLF_FUR, width=2)

    # Paws
    draw.ellipse([cx-ps-4, cy+9+by, cx-ps, cy+13+by], fill=WOLF_OL)
    draw.ellipse([cx-ps-3, cy+9+by, cx-ps, cy+12+by], fill=WOLF_DARK)
    draw.ellipse([cx+ps, cy+9+by, cx+ps+4, cy+13+by], fill=WOLF_OL)
    draw.ellipse([cx+ps, cy+ps+8, cx+ps+3, cy+12+by], fill=WOLF_DARK)

def gen_wolf():
    cells = []
    for col in range(4):
        f = new_frame(); d = ImageDraw.Draw(f)
        draw_wolf_down(d, 16, 18, step=col)
        cells.append((col, 0, f))
    left_frames = []
    for col in range(4):
        f = new_frame(); d = ImageDraw.Draw(f)
        draw_wolf_side(d, 16, 16, step=col)
        cells.append((col, 1, f))
        left_frames.append(f)
    for col in range(4):
        fr = mirror_frame(left_frames[col])
        cells.append((col, 2, fr))
    for col in range(4):
        f = new_frame(); d = ImageDraw.Draw(f)
        draw_wolf_up(d, 16, 18, step=col)
        cells.append((col, 3, f))
    return assemble(cells)

# ──────────────────────────────────────────────────────────────
# SPIDER
# Dark brown/black, 8 legs, scuttling movement.
# ──────────────────────────────────────────────────────────────

SPD_BODY  = ( 60,  30,  20, 255)
SPD_LEG   = ( 50,  25,  15, 255)
SPD_HI    = ( 90,  55,  35, 255)
SPD_OL    = ( 20,  10,   5, 255)
SPD_EYE   = (255,  80,  20, 255)

def draw_spider(draw, cx, cy, step=0, facing="down"):
    bob = [0, 1, 0, -1]
    by = bob[step]
    leg_up = [True, False, True, False]
    lu = leg_up[step]

    # Abdomen (large rear body)
    draw.ellipse([cx-8, cy+2+by, cx+8, cy+11+by], fill=SPD_OL)
    draw.ellipse([cx-7, cy+3+by, cx+7, cy+10+by], fill=SPD_BODY)
    draw.ellipse([cx-4, cy+3+by, cx, cy+6+by], fill=SPD_HI)

    # Cephalothorax (head/front body)
    draw.ellipse([cx-5, cy-4+by, cx+5, cy+4+by], fill=SPD_OL)
    draw.ellipse([cx-4, cy-3+by, cx+4, cy+3+by], fill=SPD_BODY)

    # Eyes
    if facing in ("down", "left", "right"):
        for ex, ey in [(-3, -2), (-1, -3), (1, -3), (3, -2)]:
            draw.point((cx+ex, cy+ey+by), fill=SPD_EYE)

    # 8 legs (4 per side) — alternate up/down by step
    leg_configs = [
        # (start_angle, length, spread) for each of 4 legs per side
        (-6, 8, 10),
        (-2, 9, 12),
        (2, 9, 12),
        (6, 8, 10),
    ]
    for i, (oy, length, spread) in enumerate(leg_configs):
        raise_offset = 2 if (lu == (i % 2 == 0)) else -2
        # Left legs
        sx, sy = cx - 4, cy + oy + by
        ex_l = sx - spread
        ey_l = sy + raise_offset
        draw.line([(sx, sy), ((sx+ex_l)//2, sy - 3 + raise_offset), (ex_l, ey_l + 4)],
                  fill=SPD_OL, width=2)
        draw.line([(sx, sy), ((sx+ex_l)//2, sy - 3 + raise_offset), (ex_l, ey_l + 4)],
                  fill=SPD_LEG, width=1)
        # Right legs
        sx, sy = cx + 4, cy + oy + by
        ex_r = sx + spread
        draw.line([(sx, sy), ((sx+ex_r)//2, sy - 3 + raise_offset), (ex_r, ey_l + 4)],
                  fill=SPD_OL, width=2)
        draw.line([(sx, sy), ((sx+ex_r)//2, sy - 3 + raise_offset), (ex_r, ey_l + 4)],
                  fill=SPD_LEG, width=1)

def gen_spider():
    cells = []
    for row, facing in enumerate(["down", "left", "right", "up"]):
        for col in range(4):
            f = new_frame()
            d = ImageDraw.Draw(f)
            draw_spider(d, 16, 14, step=col, facing=facing)
            if facing == "right":
                f = mirror_frame(f)
            cells.append((col, row, f))
    return assemble(cells)

# ──────────────────────────────────────────────────────────────
# SKELETON
# White bone figure, rattling walk. Simple skull + ribcage.
# ──────────────────────────────────────────────────────────────

SKL_BONE  = (220, 220, 200, 255)
SKL_HI    = (255, 255, 240, 255)
SKL_OL    = ( 80,  80,  60, 255)
SKL_DARK  = (160, 160, 140, 255)
SKL_EYE   = (20,  10,   5, 255)

def draw_skeleton_down(draw, cx, cy, step=0):
    bob = [0, -1, 0, -1]
    by = bob[step]
    foot_offsets = [(-3, 3, 3, -2), (0, 0, 0, 0), (3, 3, -3, -2), (0, 0, 0, 0)]
    lx, ly, rx, ry = foot_offsets[step]

    # Left leg
    draw.rectangle([cx-5+lx, cy+9, cx-2+lx, cy+14+ly], fill=SKL_OL)
    draw.rectangle([cx-4+lx, cy+9, cx-2+lx, cy+13+ly], fill=SKL_BONE)
    # Left foot
    draw.ellipse([cx-6+lx, cy+13+ly, cx-1+lx, cy+15+ly], fill=SKL_OL)
    draw.ellipse([cx-5+lx, cy+13+ly, cx-1+lx, cy+15+ly], fill=SKL_DARK)

    # Right leg
    draw.rectangle([cx+2+rx, cy+9, cx+5+rx, cy+14+ry], fill=SKL_OL)
    draw.rectangle([cx+2+rx, cy+9, cx+4+rx, cy+13+ry], fill=SKL_BONE)
    draw.ellipse([cx+1+rx, cy+13+ry, cx+6+rx, cy+15+ry], fill=SKL_OL)
    draw.ellipse([cx+1+rx, cy+13+ry, cx+5+rx, cy+15+ry], fill=SKL_DARK)

    # Pelvis
    draw.ellipse([cx-4, cy+7, cx+4, cy+11], fill=SKL_OL)
    draw.ellipse([cx-3, cy+7, cx+3, cy+10], fill=SKL_BONE)

    # Ribcage (3 pairs of ribs)
    draw.rectangle([cx-4, cy-2+by, cx+4, cy+8+by], fill=SKL_OL)
    draw.rectangle([cx-3, cy-1+by, cx+3, cy+7+by], fill=SKL_BONE)
    for rib_y in range(3):
        ry2 = cy + 0 + rib_y*3 + by
        draw.line([(cx-3, ry2), (cx-5, ry2+1)], fill=SKL_OL, width=1)
        draw.line([(cx+3, ry2), (cx+5, ry2+1)], fill=SKL_OL, width=1)

    # Skull
    draw.ellipse([cx-5, cy-12+by, cx+5, cy+1+by], fill=SKL_OL)
    draw.ellipse([cx-4, cy-11+by, cx+4, cy], fill=SKL_BONE)
    draw.ellipse([cx-3, cy-11+by, cx+0, cy-9+by], fill=SKL_HI)  # highlight

    # Eye sockets
    draw.ellipse([cx-4, cy-7+by, cx-1, cy-4+by], fill=SKL_OL)
    draw.ellipse([cx+1, cy-7+by, cx+4, cy-4+by], fill=SKL_OL)
    draw.point((cx-3, cy-6+by), fill=SKL_EYE)
    draw.point((cx+2, cy-6+by), fill=SKL_EYE)

    # Jaw
    draw.rectangle([cx-3, cy-2+by, cx+3, cy-0+by], fill=SKL_OL)
    draw.rectangle([cx-2, cy-2+by, cx+2, cy-1+by], fill=SKL_DARK)
    # Teeth
    for tx in [-2, 0, 2]:
        draw.rectangle([cx+tx-0, cy-2+by, cx+tx+1, cy-1+by], fill=SKL_BONE)

    # Arms
    arm_swing = [2, 0, -2, 0]
    ax = arm_swing[step]
    draw.line([(cx-3, cy+by), (cx-8, cy+4+ax+by)], fill=SKL_OL, width=2)
    draw.line([(cx-3, cy+by), (cx-7, cy+4+ax+by)], fill=SKL_BONE, width=1)
    draw.line([(cx+3, cy+by), (cx+8, cy+4-ax+by)], fill=SKL_OL, width=2)
    draw.line([(cx+3, cy+by), (cx+7, cy+4-ax+by)], fill=SKL_BONE, width=1)

def draw_skeleton_side(draw, cx, cy, step=0):
    bob = [0, -1, 0, -1]
    by = bob[step]
    leg_fwd = [2, 0, -2, 0]
    lf = leg_fwd[step]

    # Legs (two visible) — front leg shifts by lf, back leg shifts opposite
    # Each leg is 2px wide; we draw outline then inner fill
    f_cx = cx - 1 + lf   # front leg center x
    b_cx = cx + 2 - lf   # back leg center x
    draw.rectangle([f_cx-1, cy+9, f_cx+1, cy+15], fill=SKL_OL)
    draw.rectangle([f_cx-1, cy+9, f_cx, cy+14], fill=SKL_BONE)
    draw.rectangle([b_cx-1, cy+9, b_cx+1, cy+14], fill=SKL_OL)
    draw.rectangle([b_cx-1, cy+9, b_cx, cy+13], fill=SKL_BONE)

    # Pelvis
    draw.ellipse([cx-3, cy+7, cx+3, cy+11], fill=SKL_OL)
    draw.ellipse([cx-2, cy+7, cx+2, cy+10], fill=SKL_BONE)

    # Ribcage
    draw.rectangle([cx-2, cy-2+by, cx+3, cy+8+by], fill=SKL_OL)
    draw.rectangle([cx-1, cy-1+by, cx+2, cy+7+by], fill=SKL_BONE)
    for rib_y in range(3):
        ry2 = cy + 0 + rib_y*3 + by
        draw.line([(cx+2, ry2), (cx+5, ry2+1)], fill=SKL_OL, width=1)

    # Skull
    draw.ellipse([cx-4, cy-12+by, cx+5, cy+1+by], fill=SKL_OL)
    draw.ellipse([cx-3, cy-11+by, cx+4, cy], fill=SKL_BONE)
    # Eye socket (side view: one eye)
    draw.ellipse([cx+0, cy-7+by, cx+3, cy-4+by], fill=SKL_OL)
    # Jaw
    draw.rectangle([cx-1, cy-2+by, cx+4, cy-0+by], fill=SKL_OL)
    draw.rectangle([cx, cy-2+by, cx+3, cy-1+by], fill=SKL_DARK)

    # Arm (visible one)
    arm_bob = [3, 0, -3, 0]
    draw.line([(cx+2, cy+by), (cx+7, cy+5+arm_bob[step]+by)], fill=SKL_OL, width=2)
    draw.line([(cx+2, cy+by), (cx+6, cy+5+arm_bob[step]+by)], fill=SKL_BONE, width=1)

def gen_skeleton():
    cells = []
    for col in range(4):
        f = new_frame(); d = ImageDraw.Draw(f)
        draw_skeleton_down(d, 16, 14, step=col)
        cells.append((col, 0, f))
    left_frames = []
    for col in range(4):
        f = new_frame(); d = ImageDraw.Draw(f)
        draw_skeleton_side(d, 14, 14, step=col)
        cells.append((col, 1, f))
        left_frames.append(f)
    for col in range(4):
        fr = mirror_frame(left_frames[col])
        cells.append((col, 2, fr))
    # Up = back of skull visible, same skeleton structure
    for col in range(4):
        f = new_frame(); d = ImageDraw.Draw(f)
        draw_skeleton_down(d, 16, 14, step=col)
        # Flip for back view — just darken the skull top
        d2 = ImageDraw.Draw(f)
        d2.ellipse([12, 3, 20, 10], fill=SKL_DARK)  # back of skull
        cells.append((col, 3, f))
    return assemble(cells)

# ──────────────────────────────────────────────────────────────
# GHOST
# Translucent white/blue-white, floating. Alpha for transparency.
# ──────────────────────────────────────────────────────────────

GHO_BODY  = (200, 210, 255, 180)
GHO_HI    = (240, 245, 255, 220)
GHO_DARK  = (150, 160, 210, 160)
GHO_OL    = (100, 110, 180, 200)
GHO_EYE   = ( 20,  10,  60, 240)
GHO_GLOW  = (180, 190, 255, 100)

def draw_ghost(draw, cx, cy, step=0, facing="down"):
    drift = [0, -1, 0, 1]
    dx = drift[step]
    bob = [0, -1, 0, -1]
    by = bob[step]

    # Glow aura
    draw.ellipse([cx-11+dx, cy-13+by, cx+11+dx, cy+10+by], fill=GHO_GLOW)

    # Main body — rounded top, wispy bottom
    draw.ellipse([cx-8+dx, cy-12+by, cx+8+dx, cy+3+by], fill=GHO_OL)
    draw.ellipse([cx-7+dx, cy-11+by, cx+7+dx, cy+2+by], fill=GHO_BODY)

    # Lower wispy tendrils (3 wavy points)
    t_y = cy + 3 + by
    for tx, tw in [(cx-5+dx, 3), (cx+dx, 4), (cx+5+dx, 3)]:
        wave = 1 if step % 2 == 0 else -1
        draw.ellipse([tx-tw//2, t_y, tx+tw//2, t_y+4+wave], fill=GHO_DARK)
        draw.ellipse([tx-tw//2+1, t_y, tx+tw//2, t_y+3+wave], fill=GHO_BODY)

    # Highlight
    draw.ellipse([cx-5+dx, cy-10+by, cx-1+dx, cy-6+by], fill=GHO_HI)

    # Face
    if facing in ("down", "left", "right"):
        # Eyes — dark hollow sockets
        draw.ellipse([cx-5+dx, cy-7+by, cx-1+dx, cy-3+by], fill=GHO_OL)
        draw.ellipse([cx+1+dx, cy-7+by, cx+5+dx, cy-3+by], fill=GHO_OL)
        draw.ellipse([cx-4+dx, cy-6+by, cx-2+dx, cy-4+by], fill=GHO_EYE)
        draw.ellipse([cx+2+dx, cy-6+by, cx+4+dx, cy-4+by], fill=GHO_EYE)
        # Mouth — wavy
        for mx in range(-2, 3):
            my = 0 if mx % 2 == 0 else 1
            draw.point((cx + mx + dx, cy - 1 + my + by), fill=GHO_OL)

def gen_ghost():
    cells = []
    for row, facing in enumerate(["down", "left", "right", "up"]):
        for col in range(4):
            f = new_frame()
            d = ImageDraw.Draw(f)
            draw_ghost(d, 16, 18, step=col, facing=facing)
            if facing == "right":
                f = mirror_frame(f)
            cells.append((col, row, f))
    return assemble(cells)

# ──────────────────────────────────────────────────────────────
# IMP
# Small red winged demon. Fluttery walk.
# ──────────────────────────────────────────────────────────────

IMP_SKIN  = (180,  40,  40, 255)
IMP_HI    = (220,  90,  70, 255)
IMP_OL    = ( 80,  15,  15, 255)
IMP_DARK  = (120,  20,  20, 255)
IMP_WING  = (140,  30,  30, 255)
IMP_EYE   = (255, 230,  20, 255)
IMP_HORN  = (220, 180,  40, 255)
IMP_TAIL  = (160,  35,  35, 255)
IMP_TOOTH = (240, 240, 200, 255)

def draw_imp(draw, cx, cy, step=0, facing="down"):
    bob = [0, -1, 0, -1]
    by = bob[step]
    wings_up = [True, False, True, False][step]

    # Wings (behind body)
    wing_tip_y = cy - 8 + by if wings_up else cy - 2 + by
    # Left wing
    lw = [(cx-2, cy-2+by), (cx-12, wing_tip_y-3), (cx-14, wing_tip_y+4), (cx-4, cy+3+by)]
    draw.polygon(lw, fill=IMP_OL)
    lw_i = [(cx-2, cy-2+by), (cx-11, wing_tip_y-2), (cx-13, wing_tip_y+3), (cx-4, cy+3+by)]
    draw.polygon(lw_i, fill=IMP_WING)
    # Right wing
    rw = [(cx+2, cy-2+by), (cx+12, wing_tip_y-3), (cx+14, wing_tip_y+4), (cx+4, cy+3+by)]
    draw.polygon(rw, fill=IMP_OL)
    rw_i = [(cx+2, cy-2+by), (cx+11, wing_tip_y-2), (cx+13, wing_tip_y+3), (cx+4, cy+3+by)]
    draw.polygon(rw_i, fill=IMP_WING)

    # Tail
    tail_curve = [1, 0, -1, 0][step]
    tx = cx - 5
    draw.line([(tx, cy+5+by), (tx-4, cy+9+by+tail_curve), (tx-5, cy+12+by+tail_curve*2)],
              fill=IMP_OL, width=2)
    draw.line([(tx, cy+5+by), (tx-3, cy+9+by+tail_curve), (tx-4, cy+12+by+tail_curve*2)],
              fill=IMP_TAIL, width=1)
    # Tail spike
    draw.polygon([(tx-5, cy+11+by+tail_curve*2), (tx-8, cy+10+by+tail_curve*2),
                  (tx-5, cy+14+by+tail_curve*2)], fill=IMP_OL)
    draw.polygon([(tx-5, cy+11+by+tail_curve*2), (tx-7, cy+11+by+tail_curve*2),
                  (tx-5, cy+13+by+tail_curve*2)], fill=IMP_HORN)

    # Body
    draw.ellipse([cx-5, cy-1+by, cx+5, cy+8+by], fill=IMP_OL)
    draw.ellipse([cx-4, cy+by, cx+4, cy+7+by], fill=IMP_SKIN)
    draw.ellipse([cx-3, cy+by, cx, cy+3+by], fill=IMP_HI)

    # Legs
    foot_l = [(-2, 2), (0, 0), (2, 2), (0, 0)][step]
    foot_r = [(2, 2), (0, 0), (-2, 2), (0, 0)][step]
    lx_off, ly_off = foot_l
    rx_off, ry_off = foot_r
    draw.rectangle([cx-4+lx_off, cy+7+by, cx-2+lx_off, cy+12+ly_off+by], fill=IMP_OL)
    draw.rectangle([cx-3+lx_off, cy+7+by, cx-1+lx_off, cy+11+ly_off+by], fill=IMP_DARK)
    draw.rectangle([cx+2+rx_off, cy+7+by, cx+4+rx_off, cy+12+ry_off+by], fill=IMP_OL)
    draw.rectangle([cx+1+rx_off, cy+7+by, cx+3+rx_off, cy+11+ry_off+by], fill=IMP_DARK)

    # Head
    draw.ellipse([cx-5, cy-10+by, cx+5, cy+2+by], fill=IMP_OL)
    draw.ellipse([cx-4, cy-9+by, cx+4, cy+1+by], fill=IMP_SKIN)
    draw.ellipse([cx-3, cy-9+by, cx, cy-6+by], fill=IMP_HI)

    # Horns
    draw.polygon([(cx-3, cy-9+by), (cx-5, cy-14+by), (cx-1, cy-9+by)], fill=IMP_OL)
    draw.polygon([(cx-3, cy-9+by), (cx-4, cy-13+by), (cx-1, cy-9+by)], fill=IMP_HORN)
    draw.polygon([(cx+3, cy-9+by), (cx+5, cy-14+by), (cx+1, cy-9+by)], fill=IMP_OL)
    draw.polygon([(cx+3, cy-9+by), (cx+4, cy-13+by), (cx+1, cy-9+by)], fill=IMP_HORN)

    # Face
    if facing in ("down", "left", "right"):
        draw.point((cx-2, cy-5+by), fill=IMP_EYE)
        draw.point((cx+2, cy-5+by), fill=IMP_EYE)
        # Fangs
        draw.point((cx-1, cy-1+by), fill=IMP_TOOTH)
        draw.point((cx+1, cy-1+by), fill=IMP_TOOTH)

def gen_imp():
    cells = []
    for row, facing in enumerate(["down", "left", "right", "up"]):
        for col in range(4):
            f = new_frame()
            d = ImageDraw.Draw(f)
            draw_imp(d, 16, 18, step=col, facing=facing)
            if facing == "right":
                f = mirror_frame(f)
            cells.append((col, row, f))
    return assemble(cells)

# ──────────────────────────────────────────────────────────────
# TROLL
# Large green/gray hulking figure. Heavy stomp, hunched.
# Fills more of the 32x32 frame due to size.
# ──────────────────────────────────────────────────────────────

TRL_SKIN  = ( 80, 130,  70, 255)
TRL_HI    = (120, 180, 100, 255)
TRL_OL    = ( 30,  55,  25, 255)
TRL_DARK  = ( 55,  90,  50, 255)
TRL_EYE   = (200, 180,  20, 255)
TRL_TOOTH = (210, 200, 170, 255)
TRL_NAIL  = ( 60,  50,  30, 255)

def draw_troll_down(draw, cx, cy, step=0):
    stomp = [2, 0, 2, 0]
    bob = [0, -1, 0, -1]
    by = bob[step]
    st = stomp[step]

    # Legs — big thick stumps
    lleg_drop = st if step in (0,) else 0
    rleg_drop = st if step in (2,) else 0

    draw.rectangle([cx-9, cy+8, cx-2, cy+15+lleg_drop], fill=TRL_OL)
    draw.rectangle([cx-8, cy+8, cx-3, cy+14+lleg_drop], fill=TRL_SKIN)
    draw.rectangle([cx+2, cy+8, cx+9, cy+15+rleg_drop], fill=TRL_OL)
    draw.rectangle([cx+3, cy+8, cx+8, cy+14+rleg_drop], fill=TRL_SKIN)

    # Feet
    draw.ellipse([cx-11, cy+13+lleg_drop, cx-1, cy+17+lleg_drop], fill=TRL_OL)
    draw.ellipse([cx-10, cy+13+lleg_drop, cx-2, cy+16+lleg_drop], fill=TRL_DARK)
    draw.ellipse([cx+1, cy+13+rleg_drop, cx+11, cy+17+rleg_drop], fill=TRL_OL)
    draw.ellipse([cx+2, cy+13+rleg_drop, cx+10, cy+16+rleg_drop], fill=TRL_DARK)

    # Body — wide barrel chest
    draw.ellipse([cx-10, cy-5+by, cx+10, cy+10+by], fill=TRL_OL)
    draw.ellipse([cx-9, cy-4+by, cx+9, cy+9+by], fill=TRL_SKIN)
    draw.ellipse([cx-7, cy-4+by, cx-1, cy+by], fill=TRL_HI)

    # Head — big and low
    draw.ellipse([cx-8, cy-14+by, cx+8, cy+1+by], fill=TRL_OL)
    draw.ellipse([cx-7, cy-13+by, cx+7, cy], fill=TRL_SKIN)
    draw.ellipse([cx-5, cy-12+by, cx-1, cy-8+by], fill=TRL_HI)

    # Ears
    draw.ellipse([cx-11, cy-10+by, cx-6, cy-5+by], fill=TRL_OL)
    draw.ellipse([cx-10, cy-9+by, cx-7, cy-6+by], fill=TRL_SKIN)
    draw.ellipse([cx+6, cy-10+by, cx+11, cy-5+by], fill=TRL_OL)
    draw.ellipse([cx+7, cy-9+by, cx+10, cy-6+by], fill=TRL_SKIN)

    # Eyes
    draw.ellipse([cx-5, cy-8+by, cx-1, cy-5+by], fill=TRL_OL)
    draw.ellipse([cx-4, cy-7+by, cx-2, cy-6+by], fill=TRL_EYE)
    draw.ellipse([cx+1, cy-8+by, cx+5, cy-5+by], fill=TRL_OL)
    draw.ellipse([cx+2, cy-7+by, cx+4, cy-6+by], fill=TRL_EYE)

    # Nose
    draw.ellipse([cx-2, cy-4+by, cx+2, cy-1+by], fill=TRL_OL)
    draw.ellipse([cx-1, cy-3+by, cx+1, cy-2+by], fill=TRL_DARK)

    # Mouth / tusk
    draw.rectangle([cx-4, cy-2+by, cx+4, cy+0+by], fill=TRL_OL)
    draw.rectangle([cx-3, cy-2+by, cx+3, cy-1+by], fill=TRL_DARK)
    draw.rectangle([cx-3, cy-3+by, cx-2, cy-1+by], fill=TRL_TOOTH)
    draw.rectangle([cx+2, cy-3+by, cx+3, cy-1+by], fill=TRL_TOOTH)

    # Arms
    arm_swing = [3, 0, -3, 0]
    ax = arm_swing[step]
    draw.ellipse([cx-14, cy-1+ax+by, cx-7, cy+7+ax+by], fill=TRL_OL)
    draw.ellipse([cx-13, cy+ax+by, cx-8, cy+6+ax+by], fill=TRL_SKIN)
    draw.ellipse([cx+7, cy-1-ax+by, cx+14, cy+7-ax+by], fill=TRL_OL)
    draw.ellipse([cx+8, cy-ax+by, cx+13, cy+6-ax+by], fill=TRL_SKIN)
    # Knuckles
    for kx in [-12, -10, -8]:
        draw.point((cx+kx, cy+6+ax+by), fill=TRL_NAIL)
    for kx in [8, 10, 12]:
        draw.point((cx+kx, cy+6-ax+by), fill=TRL_NAIL)

def draw_troll_side(draw, cx, cy, step=0):
    stomp = [2, 0, 2, 0]
    bob = [0, -1, 0, -1]
    by = bob[step]

    # Front leg
    lf = [3, 0, -3, 0][step]
    draw.rectangle([cx+1+lf, cy+8, cx+6+lf, cy+15], fill=TRL_OL)
    draw.rectangle([cx+2+lf, cy+8, cx+5+lf, cy+14], fill=TRL_SKIN)
    # Back leg
    draw.rectangle([cx-6-lf//2, cy+8, cx-1-lf//2, cy+14], fill=TRL_OL)
    draw.rectangle([cx-5-lf//2, cy+8, cx-2-lf//2, cy+13], fill=TRL_DARK)

    # Body
    draw.ellipse([cx-8, cy-4+by, cx+8, cy+10+by], fill=TRL_OL)
    draw.ellipse([cx-7, cy-3+by, cx+7, cy+9+by], fill=TRL_SKIN)

    # Head
    draw.ellipse([cx-4, cy-14+by, cx+8, cy+2+by], fill=TRL_OL)
    draw.ellipse([cx-3, cy-13+by, cx+7, cy+1+by], fill=TRL_SKIN)
    # Snout
    draw.ellipse([cx+5, cy-5+by, cx+10, cy+1+by], fill=TRL_OL)
    draw.ellipse([cx+6, cy-4+by, cx+9, cy], fill=TRL_SKIN)
    draw.point((cx+8, cy-3+by), fill=TRL_DARK)
    # Eye
    draw.ellipse([cx+1, cy-9+by, cx+5, cy-6+by], fill=TRL_OL)
    draw.ellipse([cx+2, cy-8+by, cx+4, cy-7+by], fill=TRL_EYE)
    # Ear
    draw.ellipse([cx-5, cy-11+by, cx-1, cy-6+by], fill=TRL_OL)
    draw.ellipse([cx-4, cy-10+by, cx-2, cy-7+by], fill=TRL_SKIN)

    # Arm (front)
    arm_bob = [4, 0, -4, 0]
    draw.ellipse([cx+6, cy+2+arm_bob[step]+by, cx+13, cy+8+arm_bob[step]+by], fill=TRL_OL)
    draw.ellipse([cx+7, cy+3+arm_bob[step]+by, cx+12, cy+7+arm_bob[step]+by], fill=TRL_SKIN)

def def_troll_up(draw, cx, cy, step=0):
    """Troll back view."""
    bob = [0, -1, 0, -1]
    by = bob[step]
    draw_troll_down(draw, cx, cy, step=step)  # reuse, mostly same
    # Cover face with back of head
    draw.ellipse([cx-7, cy-13+by, cx+7, cy], fill=TRL_OL)
    draw.ellipse([cx-6, cy-12+by, cx+6, cy-1+by], fill=TRL_DARK)
    draw.ellipse([cx-4, cy-11+by, cx-1, cy-8+by], fill=TRL_SKIN)  # subtle highlight

def gen_troll():
    cells = []
    for col in range(4):
        f = new_frame(); d = ImageDraw.Draw(f)
        draw_troll_down(d, 16, 13, step=col)
        cells.append((col, 0, f))
    left_frames = []
    for col in range(4):
        f = new_frame(); d = ImageDraw.Draw(f)
        draw_troll_side(d, 14, 13, step=col)
        cells.append((col, 1, f))
        left_frames.append(f)
    for col in range(4):
        fr = mirror_frame(left_frames[col])
        cells.append((col, 2, fr))
    for col in range(4):
        f = new_frame(); d = ImageDraw.Draw(f)
        def_troll_up(d, 16, 13, step=col)
        cells.append((col, 3, f))
    return assemble(cells)

# ──────────────────────────────────────────────────────────────
# SNAKE
# Green/brown serpent. S-curve slithering walk.
# ──────────────────────────────────────────────────────────────

SNK_BODY  = ( 60, 140,  50, 255)
SNK_BELLY = (140, 200, 100, 255)
SNK_OL    = ( 25,  60,  20, 255)
SNK_HI    = (100, 190,  80, 255)
SNK_EYE   = (255, 220,  30, 255)
SNK_TONGUE= (200,  40,  40, 255)
SNK_PATTERN=(40,  100,  35, 255)

def draw_snake_down(draw, cx, cy, step=0):
    """Top-down snake view, S-curve."""
    # S-curve body: head at top, tail coils
    # Phase shifts the wave
    phase = [0, 4, 8, 12][step]

    # Draw body as a series of ellipses along a sine wave
    body_len = 20
    for i in range(body_len):
        t = i / body_len
        # S-curve: x oscillates
        wave_x = int(math.sin((t * math.pi * 2) + phase * 0.3) * 6)
        bx = cx + wave_x
        by_pos = cy - 10 + int(t * 22)
        # Width tapers from head to tail
        width = max(1, int(4 - t * 2))
        draw.ellipse([bx-width, by_pos-1, bx+width, by_pos+2], fill=SNK_OL)
        draw.ellipse([bx-width+1, by_pos, bx+width-1, by_pos+1], fill=SNK_BODY)
        # Pattern
        if i % 4 == 0 and i > 0:
            draw.ellipse([bx-width+1, by_pos, bx+width-2, by_pos+1], fill=SNK_PATTERN)

    # Head
    hx = cx + int(math.sin(phase * 0.3) * 6)
    hy = cy - 10
    draw.ellipse([hx-4, hy-4, hx+4, hy+4], fill=SNK_OL)
    draw.ellipse([hx-3, hy-3, hx+3, hy+3], fill=SNK_BODY)
    draw.ellipse([hx-2, hy-3, hx, hy-1], fill=SNK_HI)
    # Eyes
    draw.point((hx-2, hy-1), fill=SNK_EYE)
    draw.point((hx+2, hy-1), fill=SNK_EYE)
    # Tongue
    if step % 2 == 0:
        draw.line([(hx, hy+3), (hx-2, hy+5)], fill=SNK_TONGUE, width=1)
        draw.line([(hx, hy+3), (hx+2, hy+5)], fill=SNK_TONGUE, width=1)

def draw_snake_side(draw, cx, cy, step=0):
    """Side view snake — horizontal S-curve."""
    phase = [0, 4, 8, 12][step]

    body_len = 22
    for i in range(body_len):
        t = i / body_len
        wave_y = int(math.sin((t * math.pi * 2) + phase * 0.3) * 5)
        bx = cx + 10 - int(t * 22)
        by_pos = cy + 2 + wave_y
        width = max(1, int(4 - t * 2))
        draw.ellipse([bx-1, by_pos-width, bx+2, by_pos+width], fill=SNK_OL)
        draw.ellipse([bx, by_pos-width+1, bx+1, by_pos+width-1], fill=SNK_BODY)
        if i % 4 == 0 and i > 0:
            draw.point((bx, by_pos), fill=SNK_PATTERN)

    # Head (right side, facing left)
    hx = cx + 10
    hy = cy + 2 + int(math.sin(phase * 0.3) * 5)
    draw.ellipse([hx-2, hy-4, hx+5, hy+4], fill=SNK_OL)
    draw.ellipse([hx-1, hy-3, hx+4, hy+3], fill=SNK_BODY)
    draw.point((hx+2, hy-2), fill=SNK_EYE)
    # Tongue
    if step % 2 == 0:
        draw.line([(hx+4, hy), (hx+7, hy-2)], fill=SNK_TONGUE, width=1)
        draw.line([(hx+4, hy), (hx+7, hy+2)], fill=SNK_TONGUE, width=1)

def gen_snake():
    cells = []
    for col in range(4):
        f = new_frame(); d = ImageDraw.Draw(f)
        draw_snake_down(d, 16, 16, step=col)
        cells.append((col, 0, f))
    left_frames = []
    for col in range(4):
        f = new_frame(); d = ImageDraw.Draw(f)
        draw_snake_side(d, 16, 16, step=col)
        cells.append((col, 1, f))
        left_frames.append(f)
    for col in range(4):
        fr = mirror_frame(left_frames[col])
        cells.append((col, 2, fr))
    # Up: just use down frames (snake slithering away)
    for col in range(4):
        f = new_frame(); d = ImageDraw.Draw(f)
        draw_snake_down(d, 16, 16, step=col)
        cells.append((col, 3, f))
    return assemble(cells)

# ──────────────────────────────────────────────────────────────
# MAIN: Generate all 10 monsters
# ──────────────────────────────────────────────────────────────

GENERATORS = {
    "slime":    gen_slime,
    "bat":      gen_bat,
    "goblin":   gen_goblin,
    "wolf":     gen_wolf,
    "spider":   gen_spider,
    "skeleton": gen_skeleton,
    "ghost":    gen_ghost,
    "imp":      gen_imp,
    "troll":    gen_troll,
    "snake":    gen_snake,
}

def main():
    print(f"Generating overworld monster sprites -> {OUT_DIR}")
    results = {}
    for monster_id, gen_fn in GENERATORS.items():
        out_path = os.path.join(OUT_DIR, f"{monster_id}.png")
        try:
            sheet = gen_fn()
            w, h = sheet.size
            assert w == SHEET_W and h == SHEET_H, \
                f"{monster_id}: expected {SHEET_W}x{SHEET_H}, got {w}x{h}"
            sheet.save(out_path, "PNG")
            results[monster_id] = ("OK", f"{w}x{h}")
            print(f"  {monster_id:12s}  {w}x{h}  -> {out_path}")
        except Exception as e:
            results[monster_id] = ("FAIL", str(e))
            print(f"  {monster_id:12s}  FAILED: {e}")

    print()
    ok = sum(1 for v in results.values() if v[0] == "OK")
    print(f"Done: {ok}/{len(GENERATORS)} sprites generated successfully.")
    if ok < len(GENERATORS):
        print("Failures:")
        for mid, (status, msg) in results.items():
            if status != "OK":
                print(f"  {mid}: {msg}")
        raise SystemExit(1)

if __name__ == "__main__":
    main()
