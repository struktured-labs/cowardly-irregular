"""
Overworld walking sprite sheets for the 5 meta jobs:
scriptweaver, time_mage, necromancer, bossbinder, skiptrotter.

128x128 canvas, 4x4 grid of 32x32 frames.

Layout:
  Row 0: walk_down  (front-facing)
  Row 1: walk_left
  Row 2: walk_right
  Row 3: walk_up   (back-facing)

Walk cycle per row: stand, right-stride, stand, left-stride

Meta jobs are game-rule-manipulators. Each has a distinctive silhouette:
  scriptweaver  - green code-robes, floating cursor glow, glasses
  time_mage     - blue-gold robes, clock face on chest, hourglass above head
  necromancer   - purple-black robes, skull hood, bone staff
  bossbinder    - red-black armor, chains on arms, dark helm
  skiptrotter   - rainbow cape, portal glow at feet, map in hand
"""

import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from gen_overworld_jobs import (
    put, frame_origin, dp, save_with_preview, T, OL, OUT_DIR,
    _legs_stand_front, _legs_stride_right_front, _legs_stride_left_front,
    _legs_stand_back, _legs_stride_right_back, _legs_stride_left_back,
    _legs_side_stand_L, _legs_side_forward_L, _legs_side_back_L,
    _legs_side_stand_R, _legs_side_forward_R, _legs_side_back_R,
    _arm_left_front, _arm_right_front,
    _arm_left_back, _arm_right_back,
    _arm_side_L, _arm_side_R,
)

from PIL import Image


# ─────────────────────────────────────────────────────────────────────────
# GENERIC ROBED META JOB — parameterized by palette + accent
# ─────────────────────────────────────────────────────────────────────────

def render_robed_meta_job(
    out_name: str,
    ROBE, ROBE_D, ROBE_H,     # main robe color, dark, highlight
    HAT,  HAT_D,              # hat/hood color, dark
    ACC,  ACC_GLOW,           # accent color and its glow variant
    SKIN, SKIN_D,             # skin, shadow
    EYE,                      # eye color
    BC, BCM,                  # boot main, shadow
    draw_accent_front,        # fn(px, ox, oy): draws job-specific front accent
    draw_accent_back=None,    # optional: back accent
    draw_accent_side=None,    # optional: side accent
    hood_style: str = "pointed",  # "pointed" or "flat"
):
    """Shared robed-mage template for scriptweaver, time_mage, necromancer."""
    img = Image.new("RGBA", (128, 128), T)
    px = img.load()

    LC, LCD = ROBE, ROBE_D

    # ────────── Hood / Hat ──────────
    def hood_front(ox, oy):
        if hood_style == "pointed":
            dp(px, ox, oy, [
                (15,0,OL),(16,0,OL),
                (14,1,OL),(15,1,HAT),(16,1,HAT),(17,1,OL),
                (13,2,OL),(14,2,HAT),(15,2,HAT_D),(16,2,HAT),(17,2,OL),
                (12,3,OL),(13,3,HAT),(14,3,HAT_D),(15,3,HAT_D),(16,3,HAT),(17,3,HAT),(18,3,OL),
                (11,4,OL),(12,4,HAT),(13,4,HAT),(14,4,HAT_D),(15,4,HAT_D),(16,4,HAT),(17,4,HAT),(18,4,HAT),(19,4,OL),
                (10,5,OL),(11,5,HAT_D),(12,5,HAT),(13,5,HAT),(14,5,HAT),(15,5,HAT_D),(16,5,HAT),(17,5,HAT),(18,5,HAT_D),(19,5,HAT),(20,5,OL),
                (9,6,OL),(10,6,HAT_D),(11,6,HAT_D),(12,6,HAT_D),(13,6,HAT_D),(14,6,HAT_D),(15,6,HAT_D),(16,6,HAT_D),(17,6,HAT_D),(18,6,HAT_D),(19,6,HAT_D),(20,6,HAT_D),(21,6,OL),
                (9,7,OL),(21,7,OL),
            ])
        else:
            dp(px, ox, oy, [
                # Flat hood rim
                (10,4,OL),(11,4,HAT),(12,4,HAT),(13,4,HAT),(14,4,HAT),(15,4,HAT_D),(16,4,HAT_D),(17,4,HAT),(18,4,HAT),(19,4,HAT),(20,4,HAT),(21,4,OL),
                (10,5,OL),(11,5,HAT),(12,5,HAT_D),(13,5,HAT_D),(14,5,HAT_D),(15,5,HAT_D),(16,5,HAT_D),(17,5,HAT_D),(18,5,HAT_D),(19,5,HAT_D),(20,5,HAT),(21,5,OL),
                (10,6,OL),(11,6,HAT_D),(12,6,HAT_D),(13,6,HAT_D),(14,6,HAT_D),(15,6,HAT_D),(16,6,HAT_D),(17,6,HAT_D),(18,6,HAT_D),(19,6,HAT_D),(20,6,HAT_D),(21,6,OL),
                (9,7,OL),(21,7,OL),
            ])

    def head_front(ox, oy):
        dp(px, ox, oy, [
            (11,7,OL),(12,7,OL),(13,7,OL),(14,7,OL),(15,7,OL),(16,7,OL),(17,7,OL),(18,7,OL),(19,7,OL),(20,7,OL),
            (10,8,OL),(10,9,OL),(10,10,OL),(10,11,OL),
            (21,8,OL),(21,9,OL),(21,10,OL),(21,11,OL),
            (11,12,OL),(12,12,OL),(13,12,OL),(14,12,OL),(15,12,OL),(16,12,OL),(17,12,OL),(18,12,OL),(19,12,OL),(20,12,OL),
            *[(x,y,SKIN_D) for y in range(8,12) for x in range(11,21)],  # face shadowed by hood
            *[(x,y,SKIN)   for y in range(9,12) for x in range(13,19)],
            (13,9,OL),(14,9,EYE),(14,10,OL),
            (17,9,OL),(18,9,EYE),(18,10,OL),
        ])

    def body_front(ox, oy):
        dp(px, ox, oy, [
            (14,13,SKIN_D),(15,13,SKIN),(16,13,SKIN),(17,13,SKIN_D),
            (10,13,OL),(10,14,OL),(10,15,OL),(10,16,OL),(10,17,OL),(10,18,OL),(10,19,OL),(10,20,OL),(10,21,OL),(10,22,OL),
            (21,13,OL),(21,14,OL),(21,15,OL),(21,16,OL),(21,17,OL),(21,18,OL),(21,19,OL),(21,20,OL),(21,21,OL),(21,22,OL),
            *[(x,13,OL) for x in range(11,21)],
            *[(x,22,OL) for x in range(11,21)],
            *[(x,y,ROBE)   for y in range(14,22) for x in range(11,21)],
            *[(x,y,ROBE_H) for y in range(14,18) for x in [13,14,15]],
            *[(x,y,ROBE_D) for y in range(14,22) for x in [11,20]],
        ])

    def hood_back(ox, oy):
        if hood_style == "pointed":
            dp(px, ox, oy, [
                (15,0,OL),(16,0,OL),
                (14,1,OL),(15,1,HAT_D),(16,1,HAT_D),(17,1,OL),
                (13,2,OL),(14,2,HAT_D),(15,2,HAT_D),(16,2,HAT_D),(17,2,OL),
                (12,3,OL),(13,3,HAT_D),(14,3,HAT_D),(15,3,HAT_D),(16,3,HAT_D),(17,3,HAT_D),(18,3,OL),
                (11,4,OL),(12,4,HAT_D),(13,4,HAT_D),(14,4,HAT_D),(15,4,HAT_D),(16,4,HAT_D),(17,4,HAT_D),(18,4,HAT_D),(19,4,OL),
                (10,5,OL),(11,5,HAT_D),(12,5,HAT_D),(13,5,HAT_D),(14,5,HAT_D),(15,5,HAT_D),(16,5,HAT_D),(17,5,HAT_D),(18,5,HAT_D),(19,5,HAT_D),(20,5,OL),
                (9,6,OL),*[(x,6,HAT_D) for x in range(10,21)],(21,6,OL),
                (9,7,OL),(21,7,OL),
            ])
        else:
            dp(px, ox, oy, [
                (10,4,OL),*[(x,4,HAT_D) for x in range(11,21)],(21,4,OL),
                (10,5,OL),*[(x,5,HAT_D) for x in range(11,21)],(21,5,OL),
                (10,6,OL),*[(x,6,HAT_D) for x in range(11,21)],(21,6,OL),
                (9,7,OL),(21,7,OL),
            ])

    def head_back(ox, oy):
        dp(px, ox, oy, [
            (11,7,OL),(12,7,OL),(13,7,OL),(14,7,OL),(15,7,OL),(16,7,OL),(17,7,OL),(18,7,OL),(19,7,OL),(20,7,OL),
            (10,8,OL),(10,9,OL),(10,10,OL),(10,11,OL),
            (21,8,OL),(21,9,OL),(21,10,OL),(21,11,OL),
            (11,12,OL),*[(x,12,OL) for x in range(12,20)],(20,12,OL),
            *[(x,y,HAT_D) for y in range(8,12) for x in range(11,21)],   # hood seen from back
        ])

    def body_back(ox, oy):
        dp(px, ox, oy, [
            (10,13,OL),(10,14,OL),(10,15,OL),(10,16,OL),(10,17,OL),(10,18,OL),(10,19,OL),(10,20,OL),(10,21,OL),(10,22,OL),
            (21,13,OL),(21,14,OL),(21,15,OL),(21,16,OL),(21,17,OL),(21,18,OL),(21,19,OL),(21,20,OL),(21,21,OL),(21,22,OL),
            *[(x,13,OL) for x in range(11,21)],
            *[(x,22,OL) for x in range(11,21)],
            *[(x,y,ROBE_D) for y in range(14,22) for x in range(11,21)],
            *[(x,y,ROBE)   for y in range(14,20) for x in [15,16]],
        ])

    def head_side(ox, oy, facing_L: bool):
        # head narrower for side view
        dp(px, ox, oy, [
            (12,7,OL),(13,7,OL),(14,7,OL),(15,7,OL),(16,7,OL),(17,7,OL),(18,7,OL),(19,7,OL),
            (11,8,OL),(11,9,OL),(11,10,OL),(11,11,OL),
            (20,8,OL),(20,9,OL),(20,10,OL),(20,11,OL),
            (12,12,OL),*[(x,12,OL) for x in range(13,20)],
            *[(x,y,SKIN_D) for y in range(8,12) for x in range(12,20)],
            *[(x,y,SKIN)   for y in range(9,12) for x in range(13,19)],
        ])
        # hood side — flat rim (simpler for sides)
        dp(px, ox, oy, [
            (12,6,OL),*[(x,6,HAT_D) for x in range(13,20)],(20,6,OL),
            (12,7,HAT_D),(20,7,HAT_D),
        ])
        # eye facing
        if facing_L:
            dp(px, ox, oy, [(13,9,OL),(14,9,EYE),(14,10,OL)])
            dp(px, ox, oy, [(11,9,SKIN),(10,9,SKIN),(10,10,OL),(11,10,OL)])  # nose L
        else:
            dp(px, ox, oy, [(17,9,OL),(18,9,EYE),(18,10,OL)])
            dp(px, ox, oy, [(20,9,SKIN),(21,9,SKIN),(21,10,OL),(20,10,OL)])  # nose R

    def body_side(ox, oy):
        dp(px, ox, oy, [
            (14,13,SKIN_D),(15,13,SKIN),(16,13,SKIN),(17,13,SKIN_D),
            (12,13,OL),(12,14,OL),(12,15,OL),(12,16,OL),(12,17,OL),(12,18,OL),(12,19,OL),(12,20,OL),(12,21,OL),(12,22,OL),
            (20,13,OL),(20,14,OL),(20,15,OL),(20,16,OL),(20,17,OL),(20,18,OL),(20,19,OL),(20,20,OL),(20,21,OL),(20,22,OL),
            *[(x,13,OL) for x in range(13,20)],
            *[(x,22,OL) for x in range(13,20)],
            *[(x,y,ROBE)   for y in range(14,22) for x in range(13,20)],
            *[(x,y,ROBE_D) for y in range(14,22) for x in [13,19]],
        ])

    # ────────── Render 16 frames ──────────
    FRONT_ROW, LEFT_ROW, RIGHT_ROW, BACK_ROW = 0, 1, 2, 3
    phases = ["stand", "stride_r", "stand", "stride_l"]

    # Row 0: Front (walk_down)
    for col, phase in enumerate(phases):
        ox, oy = frame_origin(col, FRONT_ROW)
        hood_front(ox, oy)
        head_front(ox, oy)
        body_front(ox, oy)
        draw_accent_front(px, ox, oy)
        if phase == "stand":
            _legs_stand_front(px, ox, oy, LC, LCD, BC, BCM)
        elif phase == "stride_r":
            _legs_stride_right_front(px, ox, oy, LC, LCD, BC, BCM)
        else:
            _legs_stride_left_front(px, ox, oy, LC, LCD, BC, BCM)

    # Row 3: Back (walk_up)
    for col, phase in enumerate(phases):
        ox, oy = frame_origin(col, BACK_ROW)
        hood_back(ox, oy)
        head_back(ox, oy)
        body_back(ox, oy)
        if draw_accent_back:
            draw_accent_back(px, ox, oy)
        if phase == "stand":
            _legs_stand_back(px, ox, oy, LC, LCD, BC, BCM)
        elif phase == "stride_r":
            _legs_stride_right_back(px, ox, oy, LC, LCD, BC, BCM)
        else:
            _legs_stride_left_back(px, ox, oy, LC, LCD, BC, BCM)

    # Row 1: Left
    for col, phase in enumerate(phases):
        ox, oy = frame_origin(col, LEFT_ROW)
        head_side(ox, oy, facing_L=True)
        body_side(ox, oy)
        if draw_accent_side:
            draw_accent_side(px, ox, oy, facing_L=True)
        if phase == "stand":
            _legs_side_stand_L(px, ox, oy, LC, LCD, BC, BCM)
        elif phase == "stride_r":
            _legs_side_forward_L(px, ox, oy, LC, LCD, BC, BCM)
        else:
            _legs_side_back_L(px, ox, oy, LC, LCD, BC, BCM)

    # Row 2: Right
    for col, phase in enumerate(phases):
        ox, oy = frame_origin(col, RIGHT_ROW)
        head_side(ox, oy, facing_L=False)
        body_side(ox, oy)
        if draw_accent_side:
            draw_accent_side(px, ox, oy, facing_L=False)
        if phase == "stand":
            _legs_side_stand_R(px, ox, oy, LC, LCD, BC, BCM)
        elif phase == "stride_r":
            _legs_side_forward_R(px, ox, oy, LC, LCD, BC, BCM)
        else:
            _legs_side_back_R(px, ox, oy, LC, LCD, BC, BCM)

    # Save
    out_path  = os.path.join(OUT_DIR, f"{out_name}_overworld.png")
    prev_path = os.path.join(OUT_DIR, f"{out_name}_overworld_4x.png")
    save_with_preview(img, out_path, prev_path, out_name.upper())


# ═══════════════════════════════════════════════════════════════════════════════
# META JOBS
# ═══════════════════════════════════════════════════════════════════════════════

def gen_scriptweaver():
    """Green code robes, glasses, floating cursor glow above head."""
    ROBE  = ( 30,  90,  50, 255)   # terminal green
    ROBE_D = ( 18,  55,  30, 255)
    ROBE_H = ( 70, 170, 100, 255)
    HAT  = ( 25,  75,  45, 255)
    HAT_D = ( 12,  40,  22, 255)
    ACC  = ( 80, 255, 120, 255)    # phosphor green
    ACC_GLOW = (180, 255, 200, 255)
    SKIN = (210, 190, 170, 255)
    SKIN_D = (160, 140, 120, 255)
    EYE  = (180, 255, 180, 255)    # glowing green eyes
    BC, BCM = (15, 25, 18, 255), (30, 50, 35, 255)

    def accent_front(px, ox, oy):
        # Floating cursor block above head (blinking effect just uses one state)
        dp(px, ox, oy, [
            (15,0,ACC_GLOW),(16,0,ACC_GLOW),
            (15,1,ACC),(16,1,ACC),
        ])
        # Glasses
        dp(px, ox, oy, [
            (13,9,ACC),(14,9,OL),(14,10,OL),
            (17,9,ACC),(18,9,OL),(18,10,OL),
            (15,9,ACC),(16,9,ACC),  # nose bridge
        ])
        # Code glyphs on sleeves (just a few glowing pixels)
        dp(px, ox, oy, [
            (11,16,ACC),(11,17,ACC_GLOW),
            (20,16,ACC),(20,17,ACC_GLOW),
            (15,19,ACC),(16,19,ACC_GLOW),  # chest pocket code
        ])

    def accent_back(px, ox, oy):
        # cursor still floats above
        dp(px, ox, oy, [
            (15,0,ACC_GLOW),(16,0,ACC_GLOW),
            (15,1,ACC),(16,1,ACC),
        ])
        # back of robe — code waterfall down center
        dp(px, ox, oy, [
            (15,15,ACC),(16,17,ACC),(15,19,ACC),(16,21,ACC),
        ])

    def accent_side(px, ox, oy, facing_L):
        # cursor above
        dp(px, ox, oy, [
            (15,0,ACC_GLOW),(16,0,ACC_GLOW),
            (15,1,ACC),(16,1,ACC),
        ])
        # sleeve glyphs
        if facing_L:
            dp(px, ox, oy, [(13,16,ACC),(13,18,ACC)])
        else:
            dp(px, ox, oy, [(19,16,ACC),(19,18,ACC)])

    render_robed_meta_job(
        "scriptweaver",
        ROBE, ROBE_D, ROBE_H,
        HAT, HAT_D,
        ACC, ACC_GLOW,
        SKIN, SKIN_D,
        EYE,
        BC, BCM,
        accent_front,
        accent_back,
        accent_side,
        hood_style="flat",
    )


def gen_time_mage():
    """Blue-gold robes, clock face on chest, hourglass above pointed hat."""
    ROBE  = ( 35,  50, 140, 255)   # deep indigo
    ROBE_D = ( 20,  30,  90, 255)
    ROBE_H = ( 80, 120, 210, 255)
    HAT  = ( 35,  50, 140, 255)
    HAT_D = ( 20,  30,  90, 255)
    ACC  = (230, 200,  80, 255)    # gold
    ACC_GLOW = (255, 235, 150, 255)
    SKIN = (220, 195, 170, 255)
    SKIN_D = (170, 145, 125, 255)
    EYE  = (200, 180, 255, 255)
    BC, BCM = (20, 20, 40, 255), (35, 35, 65, 255)

    def accent_front(px, ox, oy):
        # Gold band on hat
        dp(px, ox, oy, [
            (11,5,ACC),(12,5,ACC),(13,5,ACC),(14,5,ACC),
            (17,5,ACC),(18,5,ACC),(19,5,ACC),(20,5,ACC),
            (15,5,ACC_GLOW),(16,5,ACC_GLOW),
        ])
        # Clock face on chest — circle of gold with dark center
        dp(px, ox, oy, [
            (14,16,ACC),(15,16,ACC),(16,16,ACC),(17,16,ACC),
            (13,17,ACC),(14,17,OL),(15,17,ACC_GLOW),(16,17,OL),(17,17,ACC),(18,17,ACC),  # 12 / 6 marks
            (13,18,ACC),(14,18,OL),(17,18,OL),(18,18,ACC),
            (14,19,ACC),(15,19,ACC),(16,19,ACC),(17,19,ACC),
        ])
        # Gold robe trim
        dp(px, ox, oy, [
            (11,22,ACC),(20,22,ACC),
            (12,22,ACC),(19,22,ACC),
        ])

    def accent_back(px, ox, oy):
        # Gold band
        dp(px, ox, oy, [
            *[(x,5,ACC) for x in range(11,21)],
        ])
        # Gold trim on hem
        dp(px, ox, oy, [
            *[(x,22,ACC) for x in range(11,21)],
        ])

    def accent_side(px, ox, oy, facing_L):
        dp(px, ox, oy, [
            *[(x,6,ACC) for x in range(13,20)],
            *[(x,22,ACC) for x in range(13,20)],
        ])

    render_robed_meta_job(
        "time_mage",
        ROBE, ROBE_D, ROBE_H,
        HAT, HAT_D,
        ACC, ACC_GLOW,
        SKIN, SKIN_D,
        EYE,
        BC, BCM,
        accent_front,
        accent_back,
        accent_side,
        hood_style="pointed",
    )


def gen_necromancer():
    """Purple-black robes, skull visible in hood, bone accents."""
    ROBE  = ( 55,  30,  75, 255)   # deep purple
    ROBE_D = ( 30,  15,  45, 255)
    ROBE_H = ( 95,  60, 130, 255)
    HAT  = ( 20,  15,  25, 255)    # near-black hood
    HAT_D = ( 10,   8,  15, 255)
    ACC  = (230, 220, 200, 255)    # bone white
    ACC_GLOW = (180,  60, 230, 255)  # purple magic glow
    SKIN = (200, 200, 205, 255)    # pale corpse skin
    SKIN_D = (150, 150, 160, 255)
    EYE  = (200,  80, 255, 255)    # purple glowing eyes
    BC, BCM = (15, 10, 20, 255), (30, 20, 40, 255)

    def accent_front(px, ox, oy):
        # Skull-like face — hollow cheeks, darker sockets
        dp(px, ox, oy, [
            (13,8,OL),(13,9,OL),(13,10,HAT_D),  # left socket shadow
            (18,8,OL),(18,9,OL),(18,10,HAT_D),  # right socket shadow
            # glowing eyes
            (14,9,EYE),(18,9,EYE),
            # Teeth hint under mouth
            (14,11,ACC),(15,11,OL),(16,11,ACC),(17,11,OL),
        ])
        # Bone staff implied — sleeve accents
        dp(px, ox, oy, [
            (10,14,ACC),(10,15,ACC),(10,16,ACC),  # bone trim on edge
            (21,14,ACC),(21,15,ACC),(21,16,ACC),
        ])
        # Purple magic orb hovering at belt
        dp(px, ox, oy, [
            (15,19,ACC_GLOW),(16,19,ACC_GLOW),
            (15,20,ACC_GLOW),(16,20,ACC_GLOW),
        ])

    def accent_back(px, ox, oy):
        # Skull design on back of hood
        dp(px, ox, oy, [
            (14,8,ACC),(15,8,ACC),(16,8,ACC),(17,8,ACC),
            (13,9,ACC),(14,9,OL),(15,9,ACC),(16,9,ACC),(17,9,OL),(18,9,ACC),
            (14,10,ACC),(15,10,ACC),(16,10,ACC),(17,10,ACC),
        ])
        # purple magic trail down back
        dp(px, ox, oy, [
            (15,16,ACC_GLOW),(16,18,ACC_GLOW),(15,20,ACC_GLOW),
        ])

    def accent_side(px, ox, oy, facing_L):
        # glowing purple orb
        if facing_L:
            dp(px, ox, oy, [(12,15,ACC_GLOW),(12,16,ACC_GLOW)])
        else:
            dp(px, ox, oy, [(19,15,ACC_GLOW),(19,16,ACC_GLOW)])

    render_robed_meta_job(
        "necromancer",
        ROBE, ROBE_D, ROBE_H,
        HAT, HAT_D,
        ACC, ACC_GLOW,
        SKIN, SKIN_D,
        EYE,
        BC, BCM,
        accent_front,
        accent_back,
        accent_side,
        hood_style="pointed",
    )


def gen_bossbinder():
    """Red-black armor, chain accents, intimidating visor helm."""
    ROBE  = (130,  30,  35, 255)   # dark crimson
    ROBE_D = ( 80,  15,  20, 255)
    ROBE_H = (180,  60,  65, 255)
    HAT  = ( 30,  20,  25, 255)    # black helm
    HAT_D = ( 15,  10,  15, 255)
    ACC  = (170, 170, 180, 255)    # steel chains
    ACC_GLOW = (220,  90,  90, 255)  # blood-red glow
    SKIN = (195, 165, 140, 255)
    SKIN_D = (145, 120, 100, 255)
    EYE  = (255,  80,  80, 255)    # red eye glow from visor
    BC, BCM = (20, 15, 20, 255), (40, 30, 35, 255)

    def accent_front(px, ox, oy):
        # Visor slit — glowing red under helm
        dp(px, ox, oy, [
            (12,9,OL),(13,9,EYE),(14,9,EYE),(15,9,OL),(16,9,OL),(17,9,EYE),(18,9,EYE),(19,9,OL),
        ])
        # Chains crossing chest (X pattern)
        dp(px, ox, oy, [
            (12,14,ACC),(13,15,ACC),(14,16,ACC),(15,17,ACC),(16,17,ACC),(17,16,ACC),(18,15,ACC),(19,14,ACC),
            (19,18,ACC),(18,19,ACC),(13,19,ACC),(12,18,ACC),
        ])
        # Chain links at waist
        dp(px, ox, oy, [
            (14,21,ACC),(15,21,OL),(16,21,ACC),(17,21,OL),
        ])

    def accent_back(px, ox, oy):
        # Cape clasp and chain trail
        dp(px, ox, oy, [
            (14,13,ACC),(15,13,ACC),(16,13,ACC),(17,13,ACC),
            (15,15,ACC),(16,15,ACC),
            (15,17,ACC),(16,17,ACC),
            (15,19,ACC),(16,19,ACC),
        ])

    def accent_side(px, ox, oy, facing_L):
        # shoulder chain
        if facing_L:
            dp(px, ox, oy, [(13,14,ACC),(13,15,ACC),(13,18,ACC)])
        else:
            dp(px, ox, oy, [(19,14,ACC),(19,15,ACC),(19,18,ACC)])

    render_robed_meta_job(
        "bossbinder",
        ROBE, ROBE_D, ROBE_H,
        HAT, HAT_D,
        ACC, ACC_GLOW,
        SKIN, SKIN_D,
        EYE,
        BC, BCM,
        accent_front,
        accent_back,
        accent_side,
        hood_style="flat",
    )


def gen_skiptrotter():
    """Rainbow cape, running boots, map in hand, portal trails."""
    ROBE  = ( 60,  75, 120, 255)   # traveler blue
    ROBE_D = ( 35,  45,  75, 255)
    ROBE_H = (110, 130, 190, 255)
    HAT  = (110,  70, 130, 255)    # purple hood
    HAT_D = ( 70,  45,  85, 255)
    ACC  = (255, 220,  90, 255)    # gold/yellow map
    ACC_GLOW = (255, 130, 220, 255)  # pink portal glow
    SKIN = (215, 180, 150, 255)
    SKIN_D = (170, 140, 115, 255)
    EYE  = (255, 230, 130, 255)    # golden excited eyes
    BC, BCM = (100, 60, 40, 255), (70, 40, 25, 255)

    def accent_front(px, ox, oy):
        # Map in left hand — yellow square with X marks
        dp(px, ox, oy, [
            (9,16,ACC),(10,16,ACC),(11,16,OL),
            (9,17,ACC),(10,17,OL),(11,17,ACC),   # X on map
            (9,18,ACC),(10,18,ACC),(11,18,ACC),
            (9,19,OL),(10,19,OL),(11,19,OL),
        ])
        # Rainbow cape edges visible at shoulders
        dp(px, ox, oy, [
            (10,13,(255, 80, 80, 255)),  # red
            (11,13,(255,180, 60, 255)),  # orange
            (19,13,(100,200, 60, 255)),  # green
            (20,13,(80, 120,255, 255)),  # blue
            (21,13,(180, 80,220, 255)),  # violet
        ])
        # Portal swirl glow at feet (tiny)
        dp(px, ox, oy, [
            (14,30,ACC_GLOW),(15,30,ACC_GLOW),(16,30,ACC_GLOW),(17,30,ACC_GLOW),
        ])

    def accent_back(px, ox, oy):
        # Full rainbow cape on back
        dp(px, ox, oy, [
            # stripes top to bottom
            *[(x,14,(255, 80, 80, 255)) for x in range(11,21)],
            *[(x,15,(255,180, 60, 255)) for x in range(11,21)],
            *[(x,16,(255,220, 90, 255)) for x in range(11,21)],
            *[(x,17,(100,200, 60, 255)) for x in range(11,21)],
            *[(x,18,( 80,120,255, 255)) for x in range(11,21)],
            *[(x,19,(180, 80,220, 255)) for x in range(11,21)],
            *[(x,20,(255,130,220, 255)) for x in range(11,21)],
        ])
        # portal glow
        dp(px, ox, oy, [
            (14,30,ACC_GLOW),(15,30,ACC_GLOW),(16,30,ACC_GLOW),(17,30,ACC_GLOW),
        ])

    def accent_side(px, ox, oy, facing_L):
        # cape flutter behind
        colors = [(255,80,80,255),(255,180,60,255),(100,200,60,255),(80,120,255,255),(180,80,220,255)]
        if facing_L:
            for i, c in enumerate(colors):
                dp(px, ox, oy, [(20+i//3, 14+i, c)])
        else:
            for i, c in enumerate(colors):
                dp(px, ox, oy, [(12-i//3, 14+i, c)])

    render_robed_meta_job(
        "skiptrotter",
        ROBE, ROBE_D, ROBE_H,
        HAT, HAT_D,
        ACC, ACC_GLOW,
        SKIN, SKIN_D,
        EYE,
        BC, BCM,
        accent_front,
        accent_back,
        accent_side,
        hood_style="flat",
    )


if __name__ == "__main__":
    print("=== Generating META JOB overworld sprites ===\n")
    print("=== SCRIPTWEAVER ===")
    gen_scriptweaver()
    print("\n=== TIME MAGE ===")
    gen_time_mage()
    print("\n=== NECROMANCER ===")
    gen_necromancer()
    print("\n=== BOSSBINDER ===")
    gen_bossbinder()
    print("\n=== SKIPTROTTER ===")
    gen_skiptrotter()
    print("\nAll 5 meta overworld sprite sheets complete.")
