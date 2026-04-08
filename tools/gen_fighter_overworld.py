"""
Fighter overworld walking sprite sheet generator.
128x128 canvas, 4x4 grid of 32x32 frames.
FF6/Chrono Trigger chibi style, hand-crafted pixel by pixel.

Layout:
  Row 0: walk_down  (front-facing) — 4 frames
  Row 1: walk_left                 — 4 frames
  Row 2: walk_right                — 4 frames
  Row 3: walk_up   (back-facing)   — 4 frames

Walk cycle per row: stand, right-stride, stand, left-stride
"""

from PIL import Image, ImageDraw
import numpy as np
import os

OUT_DIR = "/home/struktured/projects/cowardly-irregular-sprite-gen/tmp/generated/overworld"
OUT_PATH = os.path.join(OUT_DIR, "fighter_overworld.png")
PREVIEW_PATH = os.path.join(OUT_DIR, "fighter_overworld_4x.png")
os.makedirs(OUT_DIR, exist_ok=True)

# ── Palette ──────────────────────────────────────────────────────────────────
T   = (0, 0, 0, 0)
OL  = (26, 24, 32, 255)     # outline near-black

AR  = (180, 50, 40, 255)    # armor red
ARD = (120, 30, 25, 255)    # armor red dark
ARH = (220, 80, 60, 255)    # armor red highlight

LB  = (100, 65, 40, 255)    # leather
LBD = (65, 40, 25, 255)     # leather dark

SK  = (230, 190, 150, 255)  # skin
SKD = (190, 145, 110, 255)  # skin shadow

HR  = (110, 70, 40, 255)    # hair
HRD = (70, 40, 20, 255)     # hair dark

ST  = (160, 165, 175, 255)  # steel
STD = (100, 105, 115, 255)  # steel dark

BT  = (55, 35, 20, 255)     # boot dark
BTM = (80, 52, 30, 255)     # boot mid

EY  = (60, 90, 160, 255)    # eye blue

# ── Canvas ────────────────────────────────────────────────────────────────────
img = Image.new("RGBA", (128, 128), T)

def put(px, x, y, c):
    if 0 <= x < 128 and 0 <= y < 128:
        px[x, y] = c

def frame_origin(col, row):
    return col * 32, row * 32

def dp(px, ox, oy, pixels):
    for x, y, c in pixels:
        put(px, ox + x, oy + y, c)


# ─────────────────────────────────────────────────────────────────────────────
# Character is centered in a 32x32 cell.
# Grid within the cell:
#   x: 8..23 = character body width zone (16px)
#   Hair spikes: y=0..2, head: y=3..12, body: y=13..22, legs: y=23..30
# Head ~10px tall (chibi = ~40% of 30px total height)
# ─────────────────────────────────────────────────────────────────────────────

# ════════════════════════════════════════════════════════════════════
#  FRONT-FACING (walk_down) parts
# ════════════════════════════════════════════════════════════════════

def head_front(px, ox, oy):
    """10px wide round head."""
    dp(px, ox, oy, [
        # top edge
        (11,3,OL),(12,3,OL),(13,3,OL),(14,3,OL),(15,3,OL),(16,3,OL),(17,3,OL),(18,3,OL),(19,3,OL),(20,3,OL),
        # sides
        (10,4,OL),(10,5,OL),(10,6,OL),(10,7,OL),(10,8,OL),(10,9,OL),(10,10,OL),(10,11,OL),
        (21,4,OL),(21,5,OL),(21,6,OL),(21,7,OL),(21,8,OL),(21,9,OL),(21,10,OL),(21,11,OL),
        # bottom edge
        (11,12,OL),(12,12,OL),(13,12,OL),(14,12,OL),(15,12,OL),(16,12,OL),(17,12,OL),(18,12,OL),(19,12,OL),(20,12,OL),
        # fill skin
        *[(x,y,SK)  for y in range(4,12) for x in range(11,21)],
        # right-side shadow
        *[(x,y,SKD) for y in range(9,12) for x in range(18,21)],
        # eyes
        (13,7,OL),(14,7,EY),(14,8,OL),
        (17,7,OL),(18,7,EY),(18,8,OL),
        # mouth / subtle smile
        (14,10,OL),(15,10,SKD),(16,10,SKD),(17,10,OL),
    ])

def hair_front(px, ox, oy):
    """Spiky brown hair front view."""
    dp(px, ox, oy, [
        # band across y=3..5
        *[(x,3,HR)  for x in range(11,21)],
        *[(x,4,HR)  for x in range(11,21)],
        *[(x,5,HR)  for x in range(11,21)],
        (10,4,HR),(10,3,HR),(10,5,HRD),
        (21,4,HR),(21,3,HR),(21,5,HRD),
        # spike 1 (left-of-centre)
        (13,3,HR),(13,2,HR),(13,1,HRD),
        (12,2,OL),(14,1,OL),
        # spike 2 (centre)
        (15,3,HR),(16,3,HR),(15,2,HR),(16,2,HR),(15,1,HRD),(16,0,HRD),
        (14,2,OL),(17,1,OL),
        # spike 3 (right)
        (18,3,HR),(19,3,HR),(18,2,HR),(19,1,HRD),
        (17,2,OL),(20,1,OL),
        # sideburns cover head outline corners
        (10,4,HR),(10,5,HR),(21,4,HR),(21,5,HR),
    ])

def body_front(px, ox, oy):
    """Torso front view — slim waist, pauldrons."""
    dp(px, ox, oy, [
        # neck
        (14,13,SKD),(15,13,SK),(16,13,SK),(17,13,SKD),
        # pauldron left (x=9..12, torso starts at 12)
        (9,13,OL),(10,13,ST),(11,13,ST),(12,13,OL),
        (9,14,OL),(10,14,STD),(11,14,ST),(12,14,OL),
        (9,15,OL),(10,15,ST),(11,15,OL),
        # pauldron right (x=19..22)
        (19,13,OL),(20,13,ST),(21,13,ST),(22,13,OL),
        (19,14,OL),(20,14,ST),(21,14,STD),(22,14,OL),
        (20,15,OL),(21,15,ST),(22,15,OL),
        # torso outline: narrow it — 12..19
        *[(x,13,OL) for x in range(12,20)],
        (11,14,OL),(11,15,OL),(11,16,OL),(11,17,OL),(11,18,OL),(11,19,OL),(11,20,OL),(11,21,OL),(11,22,OL),
        (20,14,OL),(20,15,OL),(20,16,OL),(20,17,OL),(20,18,OL),(20,19,OL),(20,20,OL),(20,21,OL),(20,22,OL),
        *[(x,22,OL) for x in range(12,20)],
        # plate fill
        *[(x,y,AR)  for y in range(14,22) for x in range(13,19)],
        # left leather
        *[(x,y,LB)  for y in range(14,22) for x in [11,12]],
        *[(x,y,LBD) for y in range(17,22) for x in [11]],
        # right leather
        *[(x,y,LB)  for y in range(14,22) for x in [19]],
        *[(x,y,LBD) for y in range(17,22) for x in [19]],
        # plate highlights
        (13,14,ARH),(14,14,ARH),(15,14,ARH),
        (13,15,ARH),(14,15,ARH),
        # plate shadow right
        *[(x,y,ARD) for y in range(14,22) for x in [17,18]],
        # belt
        *[(x,20,ARD) for x in range(12,20)],
        (11,20,OL),(20,20,OL),
        *[(x,21,LBD) for x in range(12,20)],
        (11,21,OL),(20,21,OL),
    ])

def sword_back_right(px, ox, oy):
    """Sword hilt peeking over right shoulder."""
    dp(px, ox, oy, [
        (21,11,OL),(22,10,OL),(23,9,OL),
        (21,10,ST),(22,9,STD),
        (20,11,LBD),(19,12,LBD),
    ])

# ════════════════════════════════════════════════════════════════════
#  ARM FUNCTIONS — front, back, and side views with walk swing
# ════════════════════════════════════════════════════════════════════

def arm_left_front(px, ox, oy, y_off=0):
    """Left arm, front view. y_off: 0=rest, 1=forward swing (down)."""
    b = 16 + y_off
    dp(px, ox, oy, [
        (8,b,OL),(9,b,AR),(10,b,ARD),
        (8,b+1,OL),(9,b+1,LB),(10,b+1,LBD),
        (8,b+2,OL),(9,b+2,LB),(10,b+2,LBD),
        (8,b+3,OL),(9,b+3,SK),(10,b+3,SKD),
        (9,b+4,OL),(10,b+4,OL),
    ])

def arm_right_front(px, ox, oy, y_off=0):
    """Right arm, front view."""
    b = 16 + y_off
    dp(px, ox, oy, [
        (21,b,ARD),(22,b,AR),(23,b,OL),
        (21,b+1,LBD),(22,b+1,LB),(23,b+1,OL),
        (21,b+2,LBD),(22,b+2,LB),(23,b+2,OL),
        (21,b+3,SKD),(22,b+3,SK),(23,b+3,OL),
        (21,b+4,OL),(22,b+4,OL),
    ])

def arm_left_back(px, ox, oy, y_off=0):
    """Left arm, back view (reversed shading — we see the back of the arm)."""
    b = 16 + y_off
    dp(px, ox, oy, [
        (8,b,OL),(9,b,ARD),(10,b,AR),
        (8,b+1,OL),(9,b+1,LBD),(10,b+1,LB),
        (8,b+2,OL),(9,b+2,LBD),(10,b+2,LB),
        (8,b+3,OL),(9,b+3,SKD),(10,b+3,SK),
        (9,b+4,OL),(10,b+4,OL),
    ])

def arm_right_back(px, ox, oy, y_off=0):
    """Right arm, back view."""
    b = 16 + y_off
    dp(px, ox, oy, [
        (21,b,AR),(22,b,ARD),(23,b,OL),
        (21,b+1,LB),(22,b+1,LBD),(23,b+1,OL),
        (21,b+2,LB),(22,b+2,LBD),(23,b+2,OL),
        (21,b+3,SK),(22,b+3,SKD),(23,b+3,OL),
        (21,b+4,OL),(22,b+4,OL),
    ])

def arm_side_L(px, ox, oy, phase=0):
    """Near arm for left-facing side view. phase: 0=rest, 1=forward, -1=back."""
    if phase == 1:  # arm swings forward (toward left)
        dp(px, ox, oy, [
            (9,16,OL),(10,16,LB),(11,16,LBD),
            (9,17,OL),(10,17,LB),
            (9,18,OL),(10,18,SK),
            (9,19,OL),(10,19,OL),
        ])
    elif phase == -1:  # arm swings back
        dp(px, ox, oy, [
            (11,15,LBD),(12,15,LBD),
            (11,16,LB),(12,16,LBD),
            (11,17,SK),(12,17,OL),
            (11,18,OL),
        ])
    else:  # rest
        dp(px, ox, oy, [
            (10,16,OL),(11,16,LB),
            (10,17,OL),(11,17,LB),
            (10,18,OL),(11,18,SK),
            (10,19,OL),(11,19,OL),
        ])

def arm_side_R(px, ox, oy, phase=0):
    """Near arm for right-facing side view."""
    if phase == 1:  # arm swings forward (toward right)
        dp(px, ox, oy, [
            (20,16,LBD),(21,16,LB),(22,16,OL),
            (20,17,LB),(22,17,OL),
            (21,18,SK),(22,18,OL),
            (21,19,OL),(22,19,OL),
        ])
    elif phase == -1:  # arm swings back
        dp(px, ox, oy, [
            (19,15,LBD),(20,15,LBD),
            (19,16,LBD),(20,16,LB),
            (19,17,OL),(20,17,SK),
            (20,18,OL),
        ])
    else:  # rest
        dp(px, ox, oy, [
            (20,16,LB),(21,16,OL),
            (20,17,LB),(21,17,OL),
            (20,18,SK),(21,18,OL),
            (20,19,OL),(21,19,OL),
        ])


def legs_stand_front(px, ox, oy):
    """Standing legs front view — feet together, clearly separated."""
    dp(px, ox, oy, [
        # left thigh (x=11..14)
        (11,23,OL),(12,23,AR),(13,23,AR),(14,23,OL),
        (11,24,OL),(12,24,ARD),(13,24,AR),(14,24,OL),
        # right thigh (x=17..20)
        (17,23,OL),(18,23,AR),(19,23,AR),(20,23,OL),
        (17,24,OL),(18,24,AR),(19,24,ARD),(20,24,OL),
        # gap at x=15..16 = crotch seam
        (15,23,OL),(16,23,OL),
        # left shin
        (11,25,OL),(12,25,LB),(13,25,LB),(14,25,OL),
        (11,26,OL),(12,26,LB),(13,26,LB),(14,26,OL),
        # right shin
        (17,25,OL),(18,25,LB),(19,25,LB),(20,25,OL),
        (17,26,OL),(18,26,LB),(19,26,LB),(20,26,OL),
        # left boot
        (10,27,OL),(11,27,BT),(12,27,BT),(13,27,BT),(14,27,BT),(15,27,OL),
        (10,28,OL),(11,28,BTM),(12,28,BT),(13,28,BT),(14,28,BT),(15,28,OL),
        (10,29,OL),(11,29,OL),(12,29,OL),(13,29,OL),(14,29,OL),(15,29,OL),
        # right boot
        (16,27,OL),(17,27,BT),(18,27,BT),(19,27,BT),(20,27,BT),(21,27,OL),
        (16,28,OL),(17,28,BT),(18,28,BT),(19,28,BT),(20,28,BTM),(21,28,OL),
        (16,29,OL),(17,29,OL),(18,29,OL),(19,29,OL),(20,29,OL),(21,29,OL),
    ])

def legs_stride_right_front(px, ox, oy):
    """Right leg forward+down, left leg back+up — maximum spread."""
    dp(px, ox, oy, [
        # RIGHT leg forward: shift right leg DOWN by 2 and right by 1
        (18,23,OL),(19,23,AR),(20,23,AR),(21,23,OL),
        (18,24,OL),(19,24,AR),(20,24,ARD),(21,24,OL),
        (18,25,OL),(19,25,LB),(20,25,LB),(21,25,OL),
        (18,26,OL),(19,26,LB),(20,26,LB),(21,26,OL),
        (17,27,OL),(18,27,OL),(19,27,BT),(20,27,BT),(21,27,BT),(22,27,OL),
        (17,28,OL),(18,28,BT),(19,28,BTM),(20,28,BT),(21,28,BT),(22,28,OL),
        (17,29,OL),(18,29,OL),(19,29,OL),(20,29,OL),(21,29,OL),(22,29,OL),
        # LEFT leg back: shift UP by 2 and left by 1 (shorter = receding)
        (9,22,OL),(10,22,AR),(11,22,ARD),(12,22,OL),
        (9,23,OL),(10,23,ARD),(11,23,ARD),(12,23,OL),
        (9,24,OL),(10,24,LBD),(11,24,LBD),(12,24,OL),
        (9,25,OL),(10,25,LBD),(11,25,LBD),(12,25,OL),
        (9,26,OL),(10,26,BT),(11,26,BT),(12,26,OL),
        (9,27,OL),(10,27,OL),(11,27,OL),(12,27,OL),
    ])

def legs_stride_left_front(px, ox, oy):
    """Left leg forward+down, right leg back+up — maximum spread."""
    dp(px, ox, oy, [
        # LEFT leg forward: shift left leg DOWN and left by 1
        (9,23,OL),(10,23,AR),(11,23,AR),(12,23,OL),
        (9,24,OL),(10,24,ARD),(11,24,AR),(12,24,OL),
        (9,25,OL),(10,25,LB),(11,25,LB),(12,25,OL),
        (9,26,OL),(10,26,LB),(11,26,LB),(12,26,OL),
        (8,27,OL),(9,27,OL),(10,27,BT),(11,27,BT),(12,27,BT),(13,27,OL),
        (8,28,OL),(9,28,BT),(10,28,BTM),(11,28,BT),(12,28,BT),(13,28,OL),
        (8,29,OL),(9,29,OL),(10,29,OL),(11,29,OL),(12,29,OL),(13,29,OL),
        # RIGHT leg back: shift UP and right by 1
        (19,22,OL),(20,22,AR),(21,22,ARD),(22,22,OL),
        (19,23,OL),(20,23,ARD),(21,23,ARD),(22,23,OL),
        (19,24,OL),(20,24,LBD),(21,24,LBD),(22,24,OL),
        (19,25,OL),(20,25,LBD),(21,25,LBD),(22,25,OL),
        (19,26,OL),(20,26,BT),(21,26,BT),(22,26,OL),
        (19,27,OL),(20,27,OL),(21,27,OL),(22,27,OL),
    ])


# ════════════════════════════════════════════════════════════════════
#  BACK-FACING (walk_up) parts
# ════════════════════════════════════════════════════════════════════

def head_back(px, ox, oy):
    """Back of head — all hair."""
    dp(px, ox, oy, [
        (11,3,OL),(12,3,OL),(13,3,OL),(14,3,OL),(15,3,OL),(16,3,OL),(17,3,OL),(18,3,OL),(19,3,OL),(20,3,OL),
        (10,4,OL),(10,5,OL),(10,6,OL),(10,7,OL),(10,8,OL),(10,9,OL),(10,10,OL),(10,11,OL),
        (21,4,OL),(21,5,OL),(21,6,OL),(21,7,OL),(21,8,OL),(21,9,OL),(21,10,OL),(21,11,OL),
        (11,12,OL),(12,12,OL),(13,12,OL),(14,12,OL),(15,12,OL),(16,12,OL),(17,12,OL),(18,12,OL),(19,12,OL),(20,12,OL),
        *[(x,y,HR)  for y in range(4,12) for x in range(11,21)],
        *[(x,y,HRD) for y in range(6,11) for x in range(13,18)],
        (11,4,HRD),(12,4,HRD),(19,4,HRD),(20,4,HRD),
    ])

def hair_back(px, ox, oy):
    """Spiky hair — back spikes pointing up."""
    dp(px, ox, oy, [
        *[(x,3,HR) for x in range(11,21)],
        *[(x,4,HR) for x in range(11,21)],
        (10,3,HR),(10,4,HR),
        (21,3,HR),(21,4,HR),
        (13,3,HR),(13,2,HR),(13,1,HRD),(12,2,OL),(14,1,OL),
        (15,2,HR),(16,2,HR),(15,1,HRD),(16,0,HRD),(14,2,OL),(17,1,OL),
        (18,3,HR),(19,3,HR),(18,2,HR),(19,1,HRD),(17,2,OL),(20,1,OL),
    ])

def body_back(px, ox, oy):
    """Torso from behind — backplate + sword on back."""
    dp(px, ox, oy, [
        (14,13,HRD),(15,13,HR),(16,13,HR),(17,13,HRD),
        # pauldrons — tucked just outside torso edge so they attach cleanly
        # left pauldron (x=9..12, torso starts at 12)
        (9,13,OL),(10,13,ST),(11,13,ST),(12,13,OL),
        (9,14,OL),(10,14,STD),(11,14,ST),(12,14,OL),
        (9,15,OL),(10,15,ST),(11,15,OL),
        # right pauldron (x=19..22)
        (19,13,OL),(20,13,ST),(21,13,ST),(22,13,OL),
        (19,14,OL),(20,14,ST),(21,14,STD),(22,14,OL),
        (19,15,OL),(20,15,ST),(21,15,OL),
        # torso outline
        *[(x,13,OL) for x in range(12,20)],
        (11,14,OL),(11,15,OL),(11,16,OL),(11,17,OL),(11,18,OL),(11,19,OL),(11,20,OL),(11,21,OL),(11,22,OL),
        (20,14,OL),(20,15,OL),(20,16,OL),(20,17,OL),(20,18,OL),(20,19,OL),(20,20,OL),(20,21,OL),(20,22,OL),
        *[(x,22,OL) for x in range(12,20)],
        # backplate fill (darker)
        *[(x,y,ARD) for y in range(14,22) for x in range(12,20)],
        # centre spine stripe
        *[(x,y,AR)  for y in range(14,20) for x in [15,16]],
        # leather at edges
        *[(x,y,LBD) for y in range(14,22) for x in [11]],
        *[(x,y,LBD) for y in range(14,22) for x in [19]],
        # belt
        *[(x,20,ARD) for x in range(12,20)],
        (11,20,OL),(20,20,OL),
        # sword on back — diagonal (pommel upper-left, tip lower-right)
        (15,13,OL),(16,12,OL),            # pommel tip
        (14,14,STD),(15,14,ST),           # blade upper
        (13,15,STD),(14,15,ST),(15,15,ST),
        (13,16,STD),(14,16,ST),
        # cross-guard (horizontal)
        (12,14,OL),(13,14,ST),(14,14,OL),
        (15,15,OL),
        # grip wrap
        (12,15,LBD),(12,16,LBD),(12,17,LBD),
    ])

def legs_stand_back(px, ox, oy):
    """Standing legs back view."""
    dp(px, ox, oy, [
        (11,23,OL),(12,23,ARD),(13,23,ARD),(14,23,OL),
        (11,24,OL),(12,24,ARD),(13,24,ARD),(14,24,OL),
        (17,23,OL),(18,23,ARD),(19,23,ARD),(20,23,OL),
        (17,24,OL),(18,24,ARD),(19,24,ARD),(20,24,OL),
        (15,23,OL),(16,23,OL),
        (11,25,OL),(12,25,LBD),(13,25,LBD),(14,25,OL),
        (11,26,OL),(12,26,LBD),(13,26,LBD),(14,26,OL),
        (17,25,OL),(18,25,LBD),(19,25,LBD),(20,25,OL),
        (17,26,OL),(18,26,LBD),(19,26,LBD),(20,26,OL),
        (10,27,OL),(11,27,BT),(12,27,BT),(13,27,BT),(14,27,BT),(15,27,OL),
        (10,28,OL),(11,28,BTM),(12,28,BT),(13,28,BT),(14,28,BT),(15,28,OL),
        (10,29,OL),(11,29,OL),(12,29,OL),(13,29,OL),(14,29,OL),(15,29,OL),
        (16,27,OL),(17,27,BT),(18,27,BT),(19,27,BT),(20,27,BT),(21,27,OL),
        (16,28,OL),(17,28,BT),(18,28,BT),(19,28,BT),(20,28,BTM),(21,28,OL),
        (16,29,OL),(17,29,OL),(18,29,OL),(19,29,OL),(20,29,OL),(21,29,OL),
    ])

def legs_stride_right_back(px, ox, oy):
    dp(px, ox, oy, [
        (18,23,OL),(19,23,ARD),(20,23,AR),(21,23,OL),
        (18,24,OL),(19,24,ARD),(20,24,AR),(21,24,OL),
        (18,25,OL),(19,25,LBD),(20,25,LB),(21,25,OL),
        (18,26,OL),(19,26,LBD),(20,26,LB),(21,26,OL),
        (17,27,OL),(18,27,OL),(19,27,BT),(20,27,BT),(21,27,BT),(22,27,OL),
        (17,28,OL),(18,28,BT),(19,28,BTM),(20,28,BT),(21,28,BT),(22,28,OL),
        (17,29,OL),(18,29,OL),(19,29,OL),(20,29,OL),(21,29,OL),(22,29,OL),
        (9,22,OL),(10,22,ARD),(11,22,ARD),(12,22,OL),
        (9,23,OL),(10,23,ARD),(11,23,ARD),(12,23,OL),
        (9,24,OL),(10,24,LBD),(11,24,LBD),(12,24,OL),
        (9,25,OL),(10,25,LBD),(11,25,LBD),(12,25,OL),
        (9,26,OL),(10,26,BT),(11,26,BT),(12,26,OL),
        (9,27,OL),(10,27,OL),(11,27,OL),(12,27,OL),
    ])

def legs_stride_left_back(px, ox, oy):
    dp(px, ox, oy, [
        (9,23,OL),(10,23,AR),(11,23,ARD),(12,23,OL),
        (9,24,OL),(10,24,AR),(11,24,ARD),(12,24,OL),
        (9,25,OL),(10,25,LB),(11,25,LBD),(12,25,OL),
        (9,26,OL),(10,26,LB),(11,26,LBD),(12,26,OL),
        (8,27,OL),(9,27,OL),(10,27,BT),(11,27,BT),(12,27,BT),(13,27,OL),
        (8,28,OL),(9,28,BT),(10,28,BTM),(11,28,BT),(12,28,BT),(13,28,OL),
        (8,29,OL),(9,29,OL),(10,29,OL),(11,29,OL),(12,29,OL),(13,29,OL),
        (19,22,OL),(20,22,ARD),(21,22,ARD),(22,22,OL),
        (19,23,OL),(20,23,ARD),(21,23,ARD),(22,23,OL),
        (19,24,OL),(20,24,LBD),(21,24,LBD),(22,24,OL),
        (19,25,OL),(20,25,LBD),(21,25,LBD),(22,25,OL),
        (19,26,OL),(20,26,BT),(21,26,BT),(22,26,OL),
        (19,27,OL),(20,27,OL),(21,27,OL),(22,27,OL),
    ])


# ════════════════════════════════════════════════════════════════════
#  SIDE-FACING parts — narrower profile
# ════════════════════════════════════════════════════════════════════

def head_side_L(px, ox, oy):
    """Side head, facing LEFT. Nose protrudes left."""
    dp(px, ox, oy, [
        (12,3,OL),(13,3,OL),(14,3,OL),(15,3,OL),(16,3,OL),(17,3,OL),(18,3,OL),(19,3,OL),
        (11,4,OL),(11,5,OL),(11,6,OL),(11,7,OL),(11,8,OL),(11,9,OL),(11,10,OL),(11,11,OL),
        (20,4,OL),(20,5,OL),(20,6,OL),(20,7,OL),(20,8,OL),(20,9,OL),(20,10,OL),(20,11,OL),
        (12,12,OL),(13,12,OL),(14,12,OL),(15,12,OL),(16,12,OL),(17,12,OL),(18,12,OL),(19,12,OL),
        *[(x,y,SK)  for y in range(4,12) for x in range(12,20)],
        *[(x,y,SKD) for y in range(8,12) for x in range(17,20)],
        # nose protrudes left
        (11,7,SK),(10,7,SK),(10,8,OL),(11,8,OL),
        # eye (left side only, facing left)
        (13,6,OL),(14,6,EY),(14,7,OL),
        # mouth
        (13,10,OL),(14,10,SKD),
    ])

def head_side_R(px, ox, oy):
    """Side head, facing RIGHT."""
    dp(px, ox, oy, [
        (12,3,OL),(13,3,OL),(14,3,OL),(15,3,OL),(16,3,OL),(17,3,OL),(18,3,OL),(19,3,OL),
        (11,4,OL),(11,5,OL),(11,6,OL),(11,7,OL),(11,8,OL),(11,9,OL),(11,10,OL),(11,11,OL),
        (20,4,OL),(20,5,OL),(20,6,OL),(20,7,OL),(20,8,OL),(20,9,OL),(20,10,OL),(20,11,OL),
        (12,12,OL),(13,12,OL),(14,12,OL),(15,12,OL),(16,12,OL),(17,12,OL),(18,12,OL),(19,12,OL),
        *[(x,y,SK)  for y in range(4,12) for x in range(12,20)],
        *[(x,y,SKD) for y in range(8,12) for x in range(12,15)],
        # nose protrudes right
        (20,7,SK),(21,7,SK),(21,8,OL),(20,8,OL),
        # eye (right side only)
        (17,6,OL),(18,6,EY),(18,7,OL),
        (18,10,OL),(17,10,SKD),
    ])

def hair_side_L(px, ox, oy):
    """Side hair facing LEFT — forward spike."""
    dp(px, ox, oy, [
        *[(x,3,HR) for x in range(12,20)],
        *[(x,4,HR) for x in range(12,20)],
        *[(x,5,HR) for x in range(12,20)],
        (11,3,HR),(11,4,HR),(11,5,HRD),
        # top spikes
        (13,3,HR),(13,2,HR),(13,1,HRD),(12,2,OL),(14,1,OL),
        (16,2,HR),(16,1,HRD),(15,2,OL),(17,1,OL),
        (19,2,HR),(19,1,HRD),(18,2,OL),(20,1,OL),
        # forward spike (facing left = spike goes left/down)
        (11,5,HR),(10,5,HR),(10,6,HRD),(11,6,HR),(9,5,OL),(9,6,OL),(10,7,OL),
        (20,3,HR),(20,4,HR),
    ])

def hair_side_R(px, ox, oy):
    """Side hair facing RIGHT."""
    dp(px, ox, oy, [
        *[(x,3,HR) for x in range(12,20)],
        *[(x,4,HR) for x in range(12,20)],
        *[(x,5,HR) for x in range(12,20)],
        (20,3,HR),(20,4,HR),(20,5,HRD),
        (13,3,HR),(13,2,HR),(13,1,HRD),(12,2,OL),(14,1,OL),
        (16,2,HR),(16,1,HRD),(15,2,OL),(17,1,OL),
        (19,2,HR),(19,1,HRD),(18,2,OL),(20,1,OL),
        # forward spike (facing right = spike goes right/down)
        (20,5,HR),(21,5,HR),(21,6,HRD),(20,6,HR),(22,5,OL),(22,6,OL),(21,7,OL),
        (11,3,HR),(11,4,HR),
    ])

def body_side_L(px, ox, oy):
    """Torso side view, facing left. Thinner profile (8px wide)."""
    dp(px, ox, oy, [
        (14,13,SKD),(15,13,SK),(16,13,SKD),
        # pauldron at right shoulder (back, now at right)
        (19,13,OL),(20,13,ST),(21,13,OL),
        (19,14,OL),(20,14,STD),(21,14,OL),
        (19,15,OL),(20,15,ST),(21,15,OL),
        # torso left edge
        (12,13,OL),(12,14,OL),(12,15,OL),(12,16,OL),(12,17,OL),(12,18,OL),(12,19,OL),(12,20,OL),(12,21,OL),(12,22,OL),
        # torso right edge
        (19,13,OL),(19,14,OL),(19,15,OL),(19,16,OL),(19,17,OL),(19,18,OL),(19,19,OL),(19,20,OL),(19,21,OL),(19,22,OL),
        # top/bottom
        *[(x,13,OL) for x in range(13,19)],
        *[(x,22,OL) for x in range(13,19)],
        # plate fill
        *[(x,y,AR)  for y in range(14,22) for x in range(14,19)],
        # front shadow (left edge = front of body facing left)
        *[(x,y,ARD) for y in range(14,22) for x in [13]],
        # rear leather
        *[(x,y,LBD) for y in range(14,22) for x in [18]],
        # plate highlight strip
        (15,14,ARH),(16,14,ARH),(17,14,ARH),
        (15,15,ARH),
        # shadow on far right
        *[(x,y,ARD) for y in range(14,22) for x in [17,18]],
        # belt
        *[(x,20,ARD) for x in range(13,19)],
        (12,20,OL),(19,20,OL),
    ])

def body_side_R(px, ox, oy):
    """Torso side view, facing right."""
    dp(px, ox, oy, [
        (15,13,SK),(16,13,SK),(17,13,SKD),
        # pauldron at left shoulder (back, now at left)
        (10,13,OL),(11,13,ST),(12,13,OL),
        (10,14,OL),(11,14,STD),(12,14,OL),
        (10,15,OL),(11,15,ST),(12,15,OL),
        (12,13,OL),(12,14,OL),(12,15,OL),(12,16,OL),(12,17,OL),(12,18,OL),(12,19,OL),(12,20,OL),(12,21,OL),(12,22,OL),
        (19,13,OL),(19,14,OL),(19,15,OL),(19,16,OL),(19,17,OL),(19,18,OL),(19,19,OL),(19,20,OL),(19,21,OL),(19,22,OL),
        *[(x,13,OL) for x in range(13,19)],
        *[(x,22,OL) for x in range(13,19)],
        *[(x,y,AR)  for y in range(14,22) for x in range(13,19)],
        *[(x,y,ARD) for y in range(14,22) for x in [18]],
        *[(x,y,LBD) for y in range(14,22) for x in [13]],
        (14,14,ARH),(15,14,ARH),(16,14,ARH),
        (14,15,ARH),
        *[(x,y,ARD) for y in range(14,22) for x in [13,14]],
        *[(x,20,ARD) for x in range(13,19)],
        (12,20,OL),(19,20,OL),
    ])

def legs_side_stand_L(px, ox, oy):
    """Side-view standing, facing left."""
    dp(px, ox, oy, [
        # front leg (x=12..15, slightly left)
        (11,23,OL),(12,23,AR),(13,23,AR),(14,23,OL),
        (11,24,OL),(12,24,ARD),(13,24,AR),(14,24,OL),
        (11,25,OL),(12,25,LB),(13,25,LB),(14,25,OL),
        (11,26,OL),(12,26,LB),(13,26,LB),(14,26,OL),
        (10,27,OL),(11,27,BT),(12,27,BT),(13,27,BT),(14,27,BT),(15,27,OL),
        (10,28,OL),(11,28,BTM),(12,28,BT),(13,28,BT),(14,28,BT),(15,28,BT),(16,28,OL),
        (10,29,OL),(11,29,OL),(12,29,OL),(13,29,OL),(14,29,OL),(15,29,OL),(16,29,OL),
        # back leg slightly right/darker
        (15,24,OL),(16,24,ARD),(17,24,ARD),(18,24,OL),
        (15,25,OL),(16,25,LBD),(17,25,LBD),(18,25,OL),
        (15,26,OL),(16,26,LBD),(17,26,LBD),(18,26,OL),
        (15,27,OL),(16,27,BT),(17,27,BT),(18,27,BT),(19,27,OL),
        (15,28,OL),(16,28,BT),(17,28,BT),(18,28,BT),(19,28,OL),
        (15,29,OL),(16,29,OL),(17,29,OL),(18,29,OL),(19,29,OL),
    ])

def legs_side_stand_R(px, ox, oy):
    """Side-view standing, facing right."""
    dp(px, ox, oy, [
        (17,23,OL),(18,23,AR),(19,23,AR),(20,23,OL),
        (17,24,OL),(18,24,AR),(19,24,ARD),(20,24,OL),
        (17,25,OL),(18,25,LB),(19,25,LB),(20,25,OL),
        (17,26,OL),(18,26,LB),(19,26,LB),(20,26,OL),
        (16,27,OL),(17,27,BT),(18,27,BT),(19,27,BT),(20,27,BT),(21,27,OL),
        (16,28,OL),(17,28,BT),(18,28,BTM),(19,28,BT),(20,28,BT),(21,28,OL),
        (16,29,OL),(17,29,OL),(18,29,OL),(19,29,OL),(20,29,OL),(21,29,OL),
        # back leg
        (13,24,OL),(14,24,ARD),(15,24,ARD),(16,24,OL),
        (13,25,OL),(14,25,LBD),(15,25,LBD),(16,25,OL),
        (13,26,OL),(14,26,LBD),(15,26,LBD),(16,26,OL),
        (12,27,OL),(13,27,BT),(14,27,BT),(15,27,BT),(16,27,OL),
        (12,28,OL),(13,28,BT),(14,28,BT),(15,28,BT),(16,28,OL),
        (12,29,OL),(13,29,OL),(14,29,OL),(15,29,OL),(16,29,OL),
    ])

def legs_side_forward_L(px, ox, oy):
    """Walk left, front stride: left leg kicks forward (toward left/down)."""
    dp(px, ox, oy, [
        # front leg swings forward-left
        (9,24,OL),(10,24,AR),(11,24,AR),(12,24,OL),
        (9,25,OL),(10,25,ARD),(11,25,AR),(12,25,OL),
        (9,26,OL),(10,26,LB),(11,26,LB),(12,26,OL),
        (9,27,OL),(10,27,LB),(11,27,LB),(12,27,OL),
        (8,28,OL),(9,28,OL),(10,28,BT),(11,28,BT),(12,28,BT),(13,28,OL),
        (7,29,OL),(8,29,BT),(9,29,BTM),(10,29,BT),(11,29,BT),(12,29,OL),(13,29,OL),
        # back leg stays behind / up
        (16,23,OL),(17,23,ARD),(18,23,ARD),(19,23,OL),
        (16,24,OL),(17,24,LBD),(18,24,LBD),(19,24,OL),
        (16,25,OL),(17,25,LBD),(18,25,LBD),(19,25,OL),
        (16,26,OL),(17,26,BT),(18,26,BT),(19,26,OL),
        (16,27,OL),(17,27,OL),(18,27,OL),(19,27,OL),
    ])

def legs_side_back_L(px, ox, oy):
    """Walk left, back stride: left leg pushes back-right."""
    dp(px, ox, oy, [
        # front leg is slightly forward
        (12,23,OL),(13,23,AR),(14,23,AR),(15,23,OL),
        (12,24,OL),(13,24,ARD),(14,24,AR),(15,24,OL),
        (12,25,OL),(13,25,LB),(14,25,LB),(15,25,OL),
        (12,26,OL),(13,26,LB),(14,26,LB),(15,26,OL),
        (11,27,OL),(12,27,BT),(13,27,BT),(14,27,BT),(15,27,OL),
        (11,28,OL),(12,28,BTM),(13,28,BT),(14,28,BT),(15,28,BT),(16,28,OL),
        (11,29,OL),(12,29,OL),(13,29,OL),(14,29,OL),(15,29,OL),(16,29,OL),
        # back leg kicks back
        (17,23,OL),(18,23,ARD),(19,23,ARD),(20,23,OL),
        (17,24,OL),(18,24,LBD),(19,24,LBD),(20,24,OL),
        (17,25,OL),(18,25,LBD),(19,25,LBD),(20,25,OL),
        (17,26,OL),(18,26,BT),(19,26,BT),(20,26,OL),
        (17,27,OL),(18,27,OL),(19,27,OL),(20,27,OL),
    ])

def legs_side_forward_R(px, ox, oy):
    """Walk right, front stride: right leg kicks forward."""
    dp(px, ox, oy, [
        (19,24,OL),(20,24,AR),(21,24,AR),(22,24,OL),
        (19,25,OL),(20,25,AR),(21,25,ARD),(22,25,OL),
        (19,26,OL),(20,26,LB),(21,26,LB),(22,26,OL),
        (19,27,OL),(20,27,LB),(21,27,LB),(22,27,OL),
        (19,28,OL),(20,28,OL),(21,28,BT),(22,28,BT),(23,28,BT),(24,28,OL),
        (19,29,OL),(20,29,BT),(21,29,BTM),(22,29,BT),(23,29,BT),(24,29,OL),
        # back leg
        (12,23,OL),(13,23,ARD),(14,23,ARD),(15,23,OL),
        (12,24,OL),(13,24,LBD),(14,24,LBD),(15,24,OL),
        (12,25,OL),(13,25,LBD),(14,25,LBD),(15,25,OL),
        (12,26,OL),(13,26,BT),(14,26,BT),(15,26,OL),
        (12,27,OL),(13,27,OL),(14,27,OL),(15,27,OL),
    ])

def legs_side_back_R(px, ox, oy):
    """Walk right, back stride: right leg pushes back-left."""
    dp(px, ox, oy, [
        (16,23,OL),(17,23,AR),(18,23,AR),(19,23,OL),
        (16,24,OL),(17,24,ARD),(18,24,AR),(19,24,OL),
        (16,25,OL),(17,25,LB),(18,25,LB),(19,25,OL),
        (16,26,OL),(17,26,LB),(18,26,LB),(19,26,OL),
        (15,27,OL),(16,27,BT),(17,27,BT),(18,27,BT),(19,27,BT),(20,27,OL),
        (15,28,OL),(16,28,OL),(17,28,BT),(18,28,BTM),(19,28,BT),(20,28,BT),(21,28,OL),
        (15,29,OL),(16,29,OL),(17,29,OL),(18,29,OL),(19,29,OL),(20,29,OL),(21,29,OL),
        # back leg
        (11,23,OL),(12,23,ARD),(13,23,ARD),(14,23,OL),
        (11,24,OL),(12,24,LBD),(13,24,LBD),(14,24,OL),
        (11,25,OL),(12,25,LBD),(13,25,LBD),(14,25,OL),
        (11,26,OL),(12,26,BT),(13,26,BT),(14,26,OL),
        (11,27,OL),(12,27,OL),(13,27,OL),(14,27,OL),
    ])


# ═════════════════════════════════════════════════════════════════════════════
#  DRAW ALL 16 FRAMES
# ═════════════════════════════════════════════════════════════════════════════
px = img.load()

# ── ROW 0: walk_down (front) ─────────────────────────────────────────────────
#   Arm swing: when right leg forward → left arm forward (y_off=1), right arm rest
#              when left leg forward  → right arm forward (y_off=1), left arm rest
front_frames = [
    (legs_stand_front,        0, 0),   # stand
    (legs_stride_right_front, 1, 0),   # right leg fwd → left arm fwd
    (legs_stand_front,        0, 0),   # stand
    (legs_stride_left_front,  0, 1),   # left leg fwd → right arm fwd
]
for col, (leg_fn, l_off, r_off) in enumerate(front_frames):
    ox, oy = frame_origin(col, 0)
    hair_front(px, ox, oy)
    head_front(px, ox, oy)
    body_front(px, ox, oy)
    sword_back_right(px, ox, oy)
    arm_left_front(px, ox, oy, y_off=l_off)
    arm_right_front(px, ox, oy, y_off=r_off)
    leg_fn(px, ox, oy)

# ── ROW 1: walk_left ─────────────────────────────────────────────────────────
walk_left_frames = [
    (legs_side_stand_L,   0),   # stand
    (legs_side_forward_L, -1),  # front leg fwd → near arm back
    (legs_side_stand_L,   0),   # stand
    (legs_side_back_L,    1),   # front leg back → near arm fwd
]
for col, (leg_fn, arm_phase) in enumerate(walk_left_frames):
    ox, oy = frame_origin(col, 1)
    hair_side_L(px, ox, oy)
    head_side_L(px, ox, oy)
    body_side_L(px, ox, oy)
    arm_side_L(px, ox, oy, phase=arm_phase)
    leg_fn(px, ox, oy)

# ── ROW 2: walk_right ────────────────────────────────────────────────────────
walk_right_frames = [
    (legs_side_stand_R,   0),
    (legs_side_forward_R, -1),
    (legs_side_stand_R,   0),
    (legs_side_back_R,    1),
]
for col, (leg_fn, arm_phase) in enumerate(walk_right_frames):
    ox, oy = frame_origin(col, 2)
    hair_side_R(px, ox, oy)
    head_side_R(px, ox, oy)
    body_side_R(px, ox, oy)
    arm_side_R(px, ox, oy, phase=arm_phase)
    leg_fn(px, ox, oy)

# ── ROW 3: walk_up (back) ────────────────────────────────────────────────────
back_frames = [
    (legs_stand_back,        0, 0),
    (legs_stride_right_back, 1, 0),
    (legs_stand_back,        0, 0),
    (legs_stride_left_back,  0, 1),
]
for col, (leg_fn, l_off, r_off) in enumerate(back_frames):
    ox, oy = frame_origin(col, 3)
    hair_back(px, ox, oy)
    head_back(px, ox, oy)
    body_back(px, ox, oy)
    arm_left_back(px, ox, oy, y_off=l_off)
    arm_right_back(px, ox, oy, y_off=r_off)
    leg_fn(px, ox, oy)


# ═════════════════════════════════════════════════════════════════════════════
#  SAVE + UPSCALE PREVIEW
# ═════════════════════════════════════════════════════════════════════════════
img.save(OUT_PATH)
print(f"Saved: {OUT_PATH}")

preview = img.resize((512, 512), Image.NEAREST)
draw = ImageDraw.Draw(preview)
# grid lines
for i in range(1, 4):
    draw.line([(i*128, 0), (i*128, 511)], fill=(80,80,80,180), width=1)
    draw.line([(0, i*128), (511, i*128)], fill=(80,80,80,180), width=1)
# row labels
for row, lbl in enumerate(["walk_down (front)", "walk_left", "walk_right", "walk_up (back)"]):
    draw.text((2, row*128+2), lbl, fill=(255,255,200,220))
# frame numbers
for row in range(4):
    for col in range(4):
        draw.text((col*128+2, row*128+118), str(col), fill=(200,200,255,200))

preview.save(PREVIEW_PATH)
print(f"Saved preview: {PREVIEW_PATH}")

# ── Validation ────────────────────────────────────────────────────────────────
img_v = Image.open(OUT_PATH)
assert img_v.size == (128, 128)
assert img_v.mode == "RGBA"

arr = np.array(img_v)
transparent_px = int(np.sum(arr[:,:,3] == 0))
opaque_px      = int(np.sum(arr[:,:,3] == 255))
total          = 128*128
print(f"Transparent: {transparent_px}/{total} ({100*transparent_px/total:.1f}%)")
print(f"Opaque:      {opaque_px}/{total} ({100*opaque_px/total:.1f}%)")

all_ok = True
for row in range(4):
    for col in range(4):
        fx, fy = col*32, row*32
        frame = arr[fy:fy+32, fx:fx+32]
        opaque = int(np.sum(frame[:,:,3] == 255))
        tag = "OK" if opaque >= 80 else "WARN"
        if opaque < 80:
            all_ok = False
        print(f"  ({col},{row}): {opaque:3d} opaque  {tag}")

if all_ok:
    print("\nAll 16 frames validated OK.")
else:
    print("\nWARNING: some frames may be sparse.")
