"""
Overworld walking sprite sheets for: guardian, ninja, summoner, speculator.
128x128 canvas, 4x4 grid of 32x32 frames.

Layout:
  Row 0: walk_down  (front-facing) — 4 frames
  Row 1: walk_left                 — 4 frames
  Row 2: walk_right                — 4 frames
  Row 3: walk_up   (back-facing)   — 4 frames

Walk cycle per row: stand, right-stride, stand, left-stride
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


# ═══════════════════════════════════════════════════════════════════════════════
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  GUARDIAN                                                                ║
# ║  Bronze/gold full plate armor, great helm with visor, gold crest         ║
# ╚══════════════════════════════════════════════════════════════════════════╝
# ═══════════════════════════════════════════════════════════════════════════════

def gen_guardian():
    BR  = (158, 128,  46, 255)  # bronze main
    BRD = (107,  82,  26, 255)  # bronze dark
    BRH = (204, 168,  77, 255)  # bronze highlight
    GD  = (217, 204, 102, 255)  # gold accent
    GDD = (150, 130,  60, 255)  # gold dark
    VD  = ( 20,  15,   8, 255)  # visor interior dark
    SK  = (214, 179, 140, 255)  # skin (wrists only)
    SKD = (173, 138, 102, 255)  # skin shadow
    LC  = (138, 112,  41, 255)  # leg bronze
    LCD = ( 92,  71,  20, 255)  # leg dark
    BC  = (117,  92,  36, 255)  # boot bronze
    BCM = ( 71,  56,  20, 255)  # boot darker

    img = Image.new("RGBA", (128, 128), T)
    px = img.load()

    # ── FRONT VIEW ────────────────────────────────────────────────────────

    def helmet_front(ox, oy):
        dp(px, ox, oy, [
            # Gold crest above helmet
            (15,1,OL),(16,1,OL),
            (14,2,OL),(15,2,GD),(16,2,GD),(17,2,OL),
            (14,3,OL),(15,3,GD),(16,3,GD),(17,3,OL),
            # Helmet outline
            (11,4,OL),(12,4,OL),(13,4,OL),(14,4,OL),(15,4,OL),(16,4,OL),(17,4,OL),(18,4,OL),(19,4,OL),(20,4,OL),
            (10,5,OL),(10,6,OL),(10,7,OL),(10,8,OL),(10,9,OL),(10,10,OL),(10,11,OL),
            (21,5,OL),(21,6,OL),(21,7,OL),(21,8,OL),(21,9,OL),(21,10,OL),(21,11,OL),
            (11,12,OL),(12,12,OL),(13,12,OL),(14,12,OL),(15,12,OL),(16,12,OL),(17,12,OL),(18,12,OL),(19,12,OL),(20,12,OL),
            # Bronze fill
            *[(x,y,BR)  for y in range(5,12) for x in range(11,21)],
            # Highlight top-left quarter
            *[(x,y,BRH) for y in range(5,8)  for x in range(12,16)],
            # Shadow bottom-right
            *[(x,y,BRD) for y in range(9,12) for x in range(16,21)],
            *[(x,y,BRD) for y in range(5,12) for x in [19,20]],
            # Gold visor frame bars
            *[(x,7,GD) for x in range(11,21)],
            *[(x,9,GD) for x in range(11,21)],
            # Visor interior dark slit
            *[(x,8,VD) for x in range(12,20)],
            # Subtle eye glints in visor
            (14,8,GDD),(15,8,GDD),(16,8,GDD),(17,8,GDD),
            # Nasal guard center bar
            (15,5,GDD),(16,5,GDD),(15,6,GDD),(16,6,GDD),
            # Chin guard row
            *[(x,11,BRD) for x in range(12,20)],
        ])

    def body_front(ox, oy):
        dp(px, ox, oy, [
            # Gorget (neck armor)
            (14,13,BRD),(15,13,BR),(16,13,BR),(17,13,BRD),
            # Wide plate body outline (cleric-width)
            (10,13,OL),(10,14,OL),(10,15,OL),(10,16,OL),(10,17,OL),(10,18,OL),(10,19,OL),(10,20,OL),(10,21,OL),(10,22,OL),
            (21,13,OL),(21,14,OL),(21,15,OL),(21,16,OL),(21,17,OL),(21,18,OL),(21,19,OL),(21,20,OL),(21,21,OL),(21,22,OL),
            *[(x,13,OL) for x in range(11,21)],
            *[(x,22,OL) for x in range(11,21)],
            # Bronze plate fill
            *[(x,y,BR)  for y in range(14,22) for x in range(11,21)],
            # Breastplate highlight centre
            *[(x,y,BRH) for y in range(14,19) for x in range(13,18)],
            # Shadow edges
            *[(x,y,BRD) for y in range(14,22) for x in [11,20]],
            # Gold shoulder yoke trim
            *[(x,14,GD) for x in range(12,20)],
            # Gold belt
            *[(x,20,GD)  for x in range(12,20)],
            *[(x,21,GDD) for x in range(12,20)],
            # Centre breastplate ridge
            (15,15,GDD),(15,16,GDD),(15,17,GDD),(15,18,GDD),(15,19,GDD),
            (16,15,GDD),(16,16,GDD),(16,17,GDD),(16,18,GDD),(16,19,GDD),
            # Pauldron shoulder extension hints
            (9,14,OL),(9,15,OL),(10,14,BRH),(10,15,BRH),
            (22,14,OL),(22,15,OL),(21,14,BRH),(21,15,BRH),
        ])

    # ── BACK VIEW ─────────────────────────────────────────────────────────

    def helmet_back(ox, oy):
        dp(px, ox, oy, [
            # Crest back (still visible)
            (15,1,OL),(16,1,OL),
            (14,2,OL),(15,2,BRH),(16,2,BRH),(17,2,OL),
            (14,3,OL),(15,3,GD),(16,3,GD),(17,3,OL),
            # Helmet outline
            (11,4,OL),(12,4,OL),(13,4,OL),(14,4,OL),(15,4,OL),(16,4,OL),(17,4,OL),(18,4,OL),(19,4,OL),(20,4,OL),
            (10,5,OL),(10,6,OL),(10,7,OL),(10,8,OL),(10,9,OL),(10,10,OL),(10,11,OL),
            (21,5,OL),(21,6,OL),(21,7,OL),(21,8,OL),(21,9,OL),(21,10,OL),(21,11,OL),
            (11,12,OL),(12,12,OL),(13,12,OL),(14,12,OL),(15,12,OL),(16,12,OL),(17,12,OL),(18,12,OL),(19,12,OL),(20,12,OL),
            # Back fill (darker bronze)
            *[(x,y,BRD) for y in range(5,12) for x in range(11,21)],
            *[(x,y,BR)  for y in range(5,10) for x in range(13,19)],
            # Back ventilation slits
            *[(x,7,GDD) for x in range(13,19)],
            *[(x,9,GDD) for x in range(13,19)],
        ])

    def body_back(ox, oy):
        dp(px, ox, oy, [
            (14,13,BRD),(15,13,BRD),(16,13,BRD),(17,13,BRD),
            (10,13,OL),(10,14,OL),(10,15,OL),(10,16,OL),(10,17,OL),(10,18,OL),(10,19,OL),(10,20,OL),(10,21,OL),(10,22,OL),
            (21,13,OL),(21,14,OL),(21,15,OL),(21,16,OL),(21,17,OL),(21,18,OL),(21,19,OL),(21,20,OL),(21,21,OL),(21,22,OL),
            *[(x,13,OL) for x in range(11,21)],
            *[(x,22,OL) for x in range(11,21)],
            # Back plate darker
            *[(x,y,BRD) for y in range(14,22) for x in range(11,21)],
            *[(x,y,BR)  for y in range(14,20) for x in range(13,19)],
            # Spine ridge highlight
            *[(x,y,BRH) for y in range(14,20) for x in [15,16]],
            # Gold belt
            *[(x,20,GD)  for x in range(12,20)],
            *[(x,21,GDD) for x in range(12,20)],
        ])

    # ── SIDE L VIEW ───────────────────────────────────────────────────────

    def helmet_side_L(ox, oy):
        dp(px, ox, oy, [
            # Crest (thin profile from side)
            (15,2,OL),(16,2,OL),(15,3,GD),(16,3,GD),(17,3,OL),
            # Side helmet outline
            (12,4,OL),(13,4,OL),(14,4,OL),(15,4,OL),(16,4,OL),(17,4,OL),(18,4,OL),(19,4,OL),
            (11,5,OL),(11,6,OL),(11,7,OL),(11,8,OL),(11,9,OL),(11,10,OL),(11,11,OL),
            (20,5,OL),(20,6,OL),(20,7,OL),(20,8,OL),(20,9,OL),(20,10,OL),(20,11,OL),
            (12,12,OL),(13,12,OL),(14,12,OL),(15,12,OL),(16,12,OL),(17,12,OL),(18,12,OL),(19,12,OL),
            # Bronze fill
            *[(x,y,BR)  for y in range(5,12) for x in range(12,20)],
            *[(x,y,BRH) for y in range(5,9)  for x in range(15,19)],  # back lighter
            *[(x,y,BRD) for y in range(5,12) for x in range(12,14)],  # front darker
            # Brow and cheek ridges (gold)
            *[(x,6,GD)  for x in range(13,19)],
            *[(x,10,GD) for x in range(13,19)],
            # Visor edge on front-left face
            (12,7,GD),(12,8,GD),(12,9,GD),
            # Faceplate protrudes left slightly
            (11,7,BR),(10,7,BRD),(10,8,OL),(11,8,BR),
        ])

    def body_side_L(ox, oy):
        dp(px, ox, oy, [
            (14,13,BRD),(15,13,BR),(16,13,BRD),
            (12,13,OL),(12,14,OL),(12,15,OL),(12,16,OL),(12,17,OL),(12,18,OL),(12,19,OL),(12,20,OL),(12,21,OL),(12,22,OL),
            (20,13,OL),(20,14,OL),(20,15,OL),(20,16,OL),(20,17,OL),(20,18,OL),(20,19,OL),(20,20,OL),(20,21,OL),(20,22,OL),
            *[(x,13,OL) for x in range(13,20)],
            *[(x,22,OL) for x in range(13,20)],
            *[(x,y,BR)  for y in range(14,22) for x in range(13,20)],
            *[(x,y,BRH) for y in range(14,19) for x in range(17,20)],
            *[(x,y,BRD) for y in range(14,22) for x in [13,14]],
            *[(x,14,GD) for x in range(13,20)],
            *[(x,20,GD) for x in range(13,20)],
        ])

    # ── SIDE R VIEW ───────────────────────────────────────────────────────

    def helmet_side_R(ox, oy):
        dp(px, ox, oy, [
            # Crest
            (15,2,OL),(16,2,OL),(14,3,GD),(15,3,GD),(14,3,OL),
            (14,3,OL),(15,3,GD),(16,3,GD),(17,3,OL),
            # Side helmet outline
            (12,4,OL),(13,4,OL),(14,4,OL),(15,4,OL),(16,4,OL),(17,4,OL),(18,4,OL),(19,4,OL),
            (11,5,OL),(11,6,OL),(11,7,OL),(11,8,OL),(11,9,OL),(11,10,OL),(11,11,OL),
            (20,5,OL),(20,6,OL),(20,7,OL),(20,8,OL),(20,9,OL),(20,10,OL),(20,11,OL),
            (12,12,OL),(13,12,OL),(14,12,OL),(15,12,OL),(16,12,OL),(17,12,OL),(18,12,OL),(19,12,OL),
            # Bronze fill
            *[(x,y,BR)  for y in range(5,12) for x in range(12,20)],
            *[(x,y,BRH) for y in range(5,9)  for x in range(12,16)],  # front lighter
            *[(x,y,BRD) for y in range(5,12) for x in range(18,20)],  # back darker
            # Brow and cheek ridges
            *[(x,6,GD)  for x in range(13,19)],
            *[(x,10,GD) for x in range(13,19)],
            # Visor edge on front-right face
            (19,7,GD),(19,8,GD),(19,9,GD),
            # Faceplate protrudes right slightly
            (20,7,BR),(21,7,BRD),(21,8,OL),(20,8,BR),
        ])

    def body_side_R(ox, oy):
        dp(px, ox, oy, [
            (15,13,BR),(16,13,BR),(17,13,BRD),
            (11,13,OL),(11,14,OL),(11,15,OL),(11,16,OL),(11,17,OL),(11,18,OL),(11,19,OL),(11,20,OL),(11,21,OL),(11,22,OL),
            (20,13,OL),(20,14,OL),(20,15,OL),(20,16,OL),(20,17,OL),(20,18,OL),(20,19,OL),(20,20,OL),(20,21,OL),(20,22,OL),
            *[(x,13,OL) for x in range(12,20)],
            *[(x,22,OL) for x in range(12,20)],
            *[(x,y,BR)  for y in range(14,22) for x in range(12,20)],
            *[(x,y,BRH) for y in range(14,19) for x in range(12,14)],
            *[(x,y,BRD) for y in range(14,22) for x in [18,19]],
            *[(x,14,GD) for x in range(12,20)],
            *[(x,20,GD) for x in range(12,20)],
        ])

    SC, SCD = BR, BRD  # bronze plate arm sleeves

    # ── ASSEMBLY ──────────────────────────────────────────────────────────
    front_arm_offsets = [(0,0),(1,0),(0,0),(0,1)]
    side_arm_phases   = [0,-1,0,1]

    leg_fns_front = [
        lambda ox,oy: _legs_stand_front(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_stride_right_front(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_stand_front(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_stride_left_front(px,ox,oy,LC,LCD,BC,BCM),
    ]
    for col in range(4):
        ox, oy = frame_origin(col, 0)
        body_front(ox, oy)
        lo, ro = front_arm_offsets[col]
        _arm_left_front(px,ox,oy,SC,SCD,SK,SKD,y_off=lo)
        _arm_right_front(px,ox,oy,SC,SCD,SK,SKD,y_off=ro)
        helmet_front(ox, oy)
        leg_fns_front[col](ox, oy)

    leg_fns_L = [
        lambda ox,oy: _legs_side_stand_L(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_side_forward_L(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_side_stand_L(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_side_back_L(px,ox,oy,LC,LCD,BC,BCM),
    ]
    for col in range(4):
        ox, oy = frame_origin(col, 1)
        body_side_L(ox, oy)
        _arm_side_L(px,ox,oy,SC,SCD,SK,SKD,phase=side_arm_phases[col])
        helmet_side_L(ox, oy)
        leg_fns_L[col](ox, oy)

    leg_fns_R = [
        lambda ox,oy: _legs_side_stand_R(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_side_forward_R(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_side_stand_R(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_side_back_R(px,ox,oy,LC,LCD,BC,BCM),
    ]
    for col in range(4):
        ox, oy = frame_origin(col, 2)
        body_side_R(ox, oy)
        _arm_side_R(px,ox,oy,SC,SCD,SK,SKD,phase=side_arm_phases[col])
        helmet_side_R(ox, oy)
        leg_fns_R[col](ox, oy)

    leg_fns_back = [
        lambda ox,oy: _legs_stand_back(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_stride_right_back(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_stand_back(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_stride_left_back(px,ox,oy,LC,LCD,BC,BCM),
    ]
    for col in range(4):
        ox, oy = frame_origin(col, 3)
        body_back(ox, oy)
        lo, ro = front_arm_offsets[col]
        _arm_left_back(px,ox,oy,SC,SCD,SK,SKD,y_off=lo)
        _arm_right_back(px,ox,oy,SC,SCD,SK,SKD,y_off=ro)
        helmet_back(ox, oy)
        leg_fns_back[col](ox, oy)

    out_path  = os.path.join(OUT_DIR, "guardian_overworld.png")
    prev_path = os.path.join(OUT_DIR, "guardian_overworld_4x.png")
    save_with_preview(img, out_path, prev_path, "GUARDIAN")


# ═══════════════════════════════════════════════════════════════════════════════
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  NINJA                                                                   ║
# ║  All-black suit, tight bandana/mask, only icy eyes visible, white sash  ║
# ╚══════════════════════════════════════════════════════════════════════════╝
# ═══════════════════════════════════════════════════════════════════════════════

def gen_ninja():
    DN  = ( 31,  31,  46, 255)  # dark navy main
    DND = ( 15,  15,  26, 255)  # very dark
    DNH = ( 56,  56,  82, 255)  # highlight
    SK  = (199, 163, 122, 255)  # skin
    SKD = (158, 128,  92, 255)  # skin shadow
    EY  = (140, 185, 210, 255)  # icy blue eyes
    WS  = (235, 235, 235, 255)  # white sash
    WSS = (190, 190, 190, 255)  # sash shadow
    LC  = ( 26,  26,  38, 255)  # leg color
    LCD = ( 13,  13,  20, 255)  # leg dark
    BC  = ( 13,  13,  20, 255)  # boot near-black
    BCM = ( 26,  26,  38, 255)  # boot mid

    img = Image.new("RGBA", (128, 128), T)
    px = img.load()

    # ── FRONT VIEW ────────────────────────────────────────────────────────

    def head_front(ox, oy):
        """Bandana covers forehead+lower face; icy eyes visible in slit."""
        dp(px, ox, oy, [
            # Head outline
            (11,4,OL),(12,4,OL),(13,4,OL),(14,4,OL),(15,4,OL),(16,4,OL),(17,4,OL),(18,4,OL),(19,4,OL),(20,4,OL),
            (10,5,OL),(10,6,OL),(10,7,OL),(10,8,OL),(10,9,OL),(10,10,OL),(10,11,OL),
            (21,5,OL),(21,6,OL),(21,7,OL),(21,8,OL),(21,9,OL),(21,10,OL),(21,11,OL),
            (11,12,OL),(12,12,OL),(13,12,OL),(14,12,OL),(15,12,OL),(16,12,OL),(17,12,OL),(18,12,OL),(19,12,OL),(20,12,OL),
            # Bandana forehead (y=5..6)
            *[(x,y,DN)  for y in range(5,7)  for x in range(11,21)],
            *[(x,6,DNH) for x in range(13,19)],  # highlight fold
            # Skin eye zone (y=7..8)
            *[(x,y,SK)  for y in range(7,9)  for x in range(11,21)],
            *[(x,8,SKD) for x in range(17,21)],
            # Eyes (two pixels wide, prominent)
            (13,7,OL),(14,7,EY),(15,7,EY),(14,8,OL),(15,8,OL),
            (17,7,OL),(18,7,EY),(19,7,EY),(18,8,OL),(19,8,OL),
            # Lower face mask (y=9..11)
            *[(x,y,DN)  for y in range(9,12)  for x in range(11,21)],
            *[(x,y,DND) for y in range(9,12)  for x in [11,20]],
            *[(x,9,DNH) for x in range(13,19)],  # top fold of mask
            *[(x,11,DND) for x in range(12,20)], # chin shadow
        ])

    def body_front(ox, oy):
        """Slim dark body, white sash at waist."""
        dp(px, ox, oy, [
            (14,13,SKD),(15,13,SK),(16,13,SK),(17,13,SKD),
            # Slim outline (rogue-width)
            (11,13,OL),(11,14,OL),(11,15,OL),(11,16,OL),(11,17,OL),(11,18,OL),(11,19,OL),(11,20,OL),(11,21,OL),(11,22,OL),
            (20,13,OL),(20,14,OL),(20,15,OL),(20,16,OL),(20,17,OL),(20,18,OL),(20,19,OL),(20,20,OL),(20,21,OL),(20,22,OL),
            *[(x,13,OL) for x in range(12,20)],
            *[(x,22,OL) for x in range(12,20)],
            # Dark fill
            *[(x,y,DN)  for y in range(14,22) for x in range(12,20)],
            *[(x,y,DND) for y in range(14,22) for x in [12,19]],
            # White sash
            *[(x,17,WS)  for x in range(13,19)],
            *[(x,18,WSS) for x in range(13,19)],
            (12,17,OL),(19,17,OL),(12,18,OL),(19,18,OL),
        ])

    # ── BACK VIEW ─────────────────────────────────────────────────────────

    def head_back(ox, oy):
        """Back of ninja head — all bandana with knot visible."""
        dp(px, ox, oy, [
            (11,4,OL),(12,4,OL),(13,4,OL),(14,4,OL),(15,4,OL),(16,4,OL),(17,4,OL),(18,4,OL),(19,4,OL),(20,4,OL),
            (10,5,OL),(10,6,OL),(10,7,OL),(10,8,OL),(10,9,OL),(10,10,OL),(10,11,OL),
            (21,5,OL),(21,6,OL),(21,7,OL),(21,8,OL),(21,9,OL),(21,10,OL),(21,11,OL),
            (11,12,OL),(12,12,OL),(13,12,OL),(14,12,OL),(15,12,OL),(16,12,OL),(17,12,OL),(18,12,OL),(19,12,OL),(20,12,OL),
            # All bandana
            *[(x,y,DN)  for y in range(5,12) for x in range(11,21)],
            *[(x,y,DND) for y in range(8,12) for x in range(14,18)],
            # Bandana knot at center-back
            (14,5,DNH),(15,5,DNH),(16,5,DNH),(17,5,DNH),
            (14,6,DNH),(15,6,DNH),(16,6,DNH),(17,6,DNH),
            (13,6,DND),(18,6,DND),
        ])

    def body_back(ox, oy):
        dp(px, ox, oy, [
            (14,13,DND),(15,13,DND),(16,13,DND),(17,13,DND),
            (11,13,OL),(11,14,OL),(11,15,OL),(11,16,OL),(11,17,OL),(11,18,OL),(11,19,OL),(11,20,OL),(11,21,OL),(11,22,OL),
            (20,13,OL),(20,14,OL),(20,15,OL),(20,16,OL),(20,17,OL),(20,18,OL),(20,19,OL),(20,20,OL),(20,21,OL),(20,22,OL),
            *[(x,13,OL) for x in range(12,20)],
            *[(x,22,OL) for x in range(12,20)],
            *[(x,y,DND) for y in range(14,22) for x in range(12,20)],
            *[(x,y,DN)  for y in range(14,20) for x in range(14,18)],
            # White sash
            *[(x,17,WS)  for x in range(13,19)],
            *[(x,18,WSS) for x in range(13,19)],
            (12,17,OL),(19,17,OL),(12,18,OL),(19,18,OL),
        ])

    # ── SIDE L VIEW ───────────────────────────────────────────────────────

    def head_side_L(ox, oy):
        dp(px, ox, oy, [
            (12,4,OL),(13,4,OL),(14,4,OL),(15,4,OL),(16,4,OL),(17,4,OL),(18,4,OL),(19,4,OL),
            (11,5,OL),(11,6,OL),(11,7,OL),(11,8,OL),(11,9,OL),(11,10,OL),(11,11,OL),
            (20,5,OL),(20,6,OL),(20,7,OL),(20,8,OL),(20,9,OL),(20,10,OL),(20,11,OL),
            (12,12,OL),(13,12,OL),(14,12,OL),(15,12,OL),(16,12,OL),(17,12,OL),(18,12,OL),(19,12,OL),
            # Bandana fill
            *[(x,y,DN)  for y in range(5,12) for x in range(12,20)],
            *[(x,y,DNH) for y in range(5,8)  for x in range(15,19)],
            *[(x,y,DND) for y in range(5,12) for x in range(12,14)],
            # Skin eye strip (y=7..8, facing-front side = low x)
            *[(x,y,SK)  for y in range(7,9)  for x in range(12,16)],
            # Eye
            (12,7,OL),(13,7,EY),(13,8,OL),
            # Faceplate protrudes left (full-mask look)
            (11,7,DN),(10,7,DND),(10,8,OL),(11,8,DN),
        ])

    def body_side_L(ox, oy):
        dp(px, ox, oy, [
            (14,13,SKD),(15,13,SK),(16,13,SKD),
            (12,13,OL),(12,14,OL),(12,15,OL),(12,16,OL),(12,17,OL),(12,18,OL),(12,19,OL),(12,20,OL),(12,21,OL),(12,22,OL),
            (20,13,OL),(20,14,OL),(20,15,OL),(20,16,OL),(20,17,OL),(20,18,OL),(20,19,OL),(20,20,OL),(20,21,OL),(20,22,OL),
            *[(x,13,OL) for x in range(13,20)],
            *[(x,22,OL) for x in range(13,20)],
            *[(x,y,DN)  for y in range(14,22) for x in range(13,20)],
            *[(x,y,DND) for y in range(14,22) for x in [13,19]],
            # White sash
            *[(x,17,WS)  for x in range(13,20)],
            (12,17,OL),(20,17,OL),
        ])

    # ── SIDE R VIEW ───────────────────────────────────────────────────────

    def head_side_R(ox, oy):
        dp(px, ox, oy, [
            (12,4,OL),(13,4,OL),(14,4,OL),(15,4,OL),(16,4,OL),(17,4,OL),(18,4,OL),(19,4,OL),
            (11,5,OL),(11,6,OL),(11,7,OL),(11,8,OL),(11,9,OL),(11,10,OL),(11,11,OL),
            (20,5,OL),(20,6,OL),(20,7,OL),(20,8,OL),(20,9,OL),(20,10,OL),(20,11,OL),
            (12,12,OL),(13,12,OL),(14,12,OL),(15,12,OL),(16,12,OL),(17,12,OL),(18,12,OL),(19,12,OL),
            # Bandana fill
            *[(x,y,DN)  for y in range(5,12) for x in range(12,20)],
            *[(x,y,DND) for y in range(5,12) for x in range(18,20)],
            *[(x,y,DNH) for y in range(5,8)  for x in range(12,15)],
            # Skin eye strip (y=7..8, facing-front side = high x)
            *[(x,y,SK)  for y in range(7,9)  for x in range(16,20)],
            # Eye
            (18,7,OL),(19,7,EY),(19,8,OL),
            # Faceplate protrudes right
            (20,7,DN),(21,7,DND),(21,8,OL),(20,8,DN),
        ])

    def body_side_R(ox, oy):
        dp(px, ox, oy, [
            (15,13,SK),(16,13,SK),(17,13,SKD),
            (11,13,OL),(11,14,OL),(11,15,OL),(11,16,OL),(11,17,OL),(11,18,OL),(11,19,OL),(11,20,OL),(11,21,OL),(11,22,OL),
            (20,13,OL),(20,14,OL),(20,15,OL),(20,16,OL),(20,17,OL),(20,18,OL),(20,19,OL),(20,20,OL),(20,21,OL),(20,22,OL),
            *[(x,13,OL) for x in range(12,20)],
            *[(x,22,OL) for x in range(12,20)],
            *[(x,y,DN)  for y in range(14,22) for x in range(12,20)],
            *[(x,y,DND) for y in range(14,22) for x in [12,19]],
            # White sash
            *[(x,17,WS)  for x in range(12,20)],
            (11,17,OL),(20,17,OL),
        ])

    SC, SCD = DN, DND  # dark navy sleeve

    # ── ASSEMBLY ──────────────────────────────────────────────────────────
    front_arm_offsets = [(0,0),(1,0),(0,0),(0,1)]
    side_arm_phases   = [0,-1,0,1]

    leg_fns_front = [
        lambda ox,oy: _legs_stand_front(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_stride_right_front(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_stand_front(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_stride_left_front(px,ox,oy,LC,LCD,BC,BCM),
    ]
    for col in range(4):
        ox, oy = frame_origin(col, 0)
        body_front(ox, oy)
        lo, ro = front_arm_offsets[col]
        _arm_left_front(px,ox,oy,SC,SCD,SK,SKD,y_off=lo)
        _arm_right_front(px,ox,oy,SC,SCD,SK,SKD,y_off=ro)
        head_front(ox, oy)
        leg_fns_front[col](ox, oy)

    leg_fns_L = [
        lambda ox,oy: _legs_side_stand_L(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_side_forward_L(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_side_stand_L(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_side_back_L(px,ox,oy,LC,LCD,BC,BCM),
    ]
    for col in range(4):
        ox, oy = frame_origin(col, 1)
        body_side_L(ox, oy)
        _arm_side_L(px,ox,oy,SC,SCD,SK,SKD,phase=side_arm_phases[col])
        head_side_L(ox, oy)
        leg_fns_L[col](ox, oy)

    leg_fns_R = [
        lambda ox,oy: _legs_side_stand_R(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_side_forward_R(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_side_stand_R(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_side_back_R(px,ox,oy,LC,LCD,BC,BCM),
    ]
    for col in range(4):
        ox, oy = frame_origin(col, 2)
        body_side_R(ox, oy)
        _arm_side_R(px,ox,oy,SC,SCD,SK,SKD,phase=side_arm_phases[col])
        head_side_R(ox, oy)
        leg_fns_R[col](ox, oy)

    leg_fns_back = [
        lambda ox,oy: _legs_stand_back(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_stride_right_back(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_stand_back(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_stride_left_back(px,ox,oy,LC,LCD,BC,BCM),
    ]
    for col in range(4):
        ox, oy = frame_origin(col, 3)
        body_back(ox, oy)
        lo, ro = front_arm_offsets[col]
        _arm_left_back(px,ox,oy,SC,SCD,SK,SKD,y_off=lo)
        _arm_right_back(px,ox,oy,SC,SCD,SK,SKD,y_off=ro)
        head_back(ox, oy)
        leg_fns_back[col](ox, oy)

    out_path  = os.path.join(OUT_DIR, "ninja_overworld.png")
    prev_path = os.path.join(OUT_DIR, "ninja_overworld_4x.png")
    save_with_preview(img, out_path, prev_path, "NINJA")


# ═══════════════════════════════════════════════════════════════════════════════
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  SUMMONER                                                                ║
# ║  Emerald green ceremonial robes, gold circlet, green-tinted long hair    ║
# ╚══════════════════════════════════════════════════════════════════════════╝
# ═══════════════════════════════════════════════════════════════════════════════

def gen_summoner():
    GR  = ( 51, 128,  87, 255)  # emerald green
    GRD = ( 31,  82,  51, 255)  # green dark
    GRH = ( 87, 173, 128, 255)  # green highlight
    GD  = (230, 194,  51, 255)  # gold circlet
    GDD = (165, 128,  26, 255)  # gold dark
    SK  = (224, 189, 153, 255)  # skin
    SKD = (184, 153, 122, 255)  # skin shadow
    HR  = ( 66,  97,  66, 255)  # green-tinted hair
    HRD = ( 41,  61,  41, 255)  # hair dark
    EY  = ( 92, 184, 138, 255)  # emerald eyes
    PK  = (230, 180, 175, 255)  # cheek blush
    LC  = ( 46, 112,  77, 255)  # leg green
    LCD = ( 26,  71,  46, 255)  # leg dark
    BC  = ( 51,  82,  56, 255)  # boot dark green
    BCM = ( 31,  51,  36, 255)  # boot darker

    img = Image.new("RGBA", (128, 128), T)
    px = img.load()

    # ── FRONT VIEW ────────────────────────────────────────────────────────

    def head_front(ox, oy):
        dp(px, ox, oy, [
            # Head outline
            (11,4,OL),(12,4,OL),(13,4,OL),(14,4,OL),(15,4,OL),(16,4,OL),(17,4,OL),(18,4,OL),(19,4,OL),(20,4,OL),
            (10,5,OL),(10,6,OL),(10,7,OL),(10,8,OL),(10,9,OL),(10,10,OL),(10,11,OL),
            (21,5,OL),(21,6,OL),(21,7,OL),(21,8,OL),(21,9,OL),(21,10,OL),(21,11,OL),
            (11,12,OL),(12,12,OL),(13,12,OL),(14,12,OL),(15,12,OL),(16,12,OL),(17,12,OL),(18,12,OL),(19,12,OL),(20,12,OL),
            # Skin fill
            *[(x,y,SK)  for y in range(5,12) for x in range(11,21)],
            *[(x,y,SKD) for y in range(9,12) for x in range(17,21)],
            # Eyes
            (13,7,OL),(14,7,EY),(14,8,OL),
            (17,7,OL),(18,7,EY),(18,8,OL),
            # Cheek and mouth
            (13,9,PK),(14,9,PK),(17,9,PK),(18,9,PK),
            (15,10,OL),(16,10,OL),
            # Gold circlet at y=4 (overwrites top outline row)
            *[(x,4,GD) for x in range(12,20)],
            (11,4,GDD),(20,4,GDD),
            (15,3,GD),(16,3,GD),  # circlet centre gem above hairline
            # Restore side outline pixels
            (11,4,OL),(20,4,OL),
            # Hair framing face sides
            (10,5,HR),(10,6,HR),(10,7,HR),(10,8,HR),(10,9,HR),
            (21,5,HR),(21,6,HR),(21,7,HR),(21,8,HR),(21,9,HR),
            (10,5,OL),(10,10,OL),(21,5,OL),(21,10,OL),
        ])

    def body_front(ox, oy):
        """Wide emerald green robes (cleric-style)."""
        dp(px, ox, oy, [
            (14,13,SKD),(15,13,SK),(16,13,SK),(17,13,SKD),
            # Wide robe outline
            (10,13,OL),(10,14,OL),(10,15,OL),(10,16,OL),(10,17,OL),(10,18,OL),(10,19,OL),(10,20,OL),(10,21,OL),(10,22,OL),
            (21,13,OL),(21,14,OL),(21,15,OL),(21,16,OL),(21,17,OL),(21,18,OL),(21,19,OL),(21,20,OL),(21,21,OL),(21,22,OL),
            *[(x,13,OL) for x in range(11,21)],
            *[(x,22,OL) for x in range(11,21)],
            # Emerald fill
            *[(x,y,GR)  for y in range(14,22) for x in range(11,21)],
            # Centre fold
            *[(x,y,GRD) for y in range(14,22) for x in [15,16]],
            # Edge shadows
            *[(x,y,GRD) for y in range(14,22) for x in [11,20]],
            # Gold collar
            *[(x,13,GD) for x in range(13,19)],
            # Gold hem
            *[(x,22,GD)  for x in range(12,20)],
            *[(x,21,GDD) for x in range(13,19)],
        ])

    # ── BACK VIEW ─────────────────────────────────────────────────────────

    def head_back(ox, oy):
        dp(px, ox, oy, [
            (11,4,OL),(12,4,OL),(13,4,OL),(14,4,OL),(15,4,OL),(16,4,OL),(17,4,OL),(18,4,OL),(19,4,OL),(20,4,OL),
            (10,5,OL),(10,6,OL),(10,7,OL),(10,8,OL),(10,9,OL),(10,10,OL),(10,11,OL),
            (21,5,OL),(21,6,OL),(21,7,OL),(21,8,OL),(21,9,OL),(21,10,OL),(21,11,OL),
            (11,12,OL),(12,12,OL),(13,12,OL),(14,12,OL),(15,12,OL),(16,12,OL),(17,12,OL),(18,12,OL),(19,12,OL),(20,12,OL),
            # Hair (back)
            *[(x,y,HR)  for y in range(5,12) for x in range(11,21)],
            *[(x,y,HRD) for y in range(7,12) for x in range(13,19)],
            # Circlet visible from back
            *[(x,4,GD) for x in range(12,20)],
            (11,4,GDD),(20,4,GDD),(11,4,OL),(20,4,OL),
        ])

    def body_back(ox, oy):
        dp(px, ox, oy, [
            (14,13,HRD),(15,13,HR),(16,13,HR),(17,13,HRD),
            (10,13,OL),(10,14,OL),(10,15,OL),(10,16,OL),(10,17,OL),(10,18,OL),(10,19,OL),(10,20,OL),(10,21,OL),(10,22,OL),
            (21,13,OL),(21,14,OL),(21,15,OL),(21,16,OL),(21,17,OL),(21,18,OL),(21,19,OL),(21,20,OL),(21,21,OL),(21,22,OL),
            *[(x,13,OL) for x in range(11,21)],
            *[(x,22,OL) for x in range(11,21)],
            *[(x,y,GRD) for y in range(14,22) for x in range(11,21)],
            *[(x,y,GR)  for y in range(14,20) for x in [15,16]],
            *[(x,22,GD)  for x in range(12,20)],
            *[(x,21,GDD) for x in range(13,19)],
        ])

    # ── SIDE L VIEW ───────────────────────────────────────────────────────

    def head_side_L(ox, oy):
        dp(px, ox, oy, [
            (12,4,OL),(13,4,OL),(14,4,OL),(15,4,OL),(16,4,OL),(17,4,OL),(18,4,OL),(19,4,OL),
            (11,5,OL),(11,6,OL),(11,7,OL),(11,8,OL),(11,9,OL),(11,10,OL),(11,11,OL),
            (20,5,OL),(20,6,OL),(20,7,OL),(20,8,OL),(20,9,OL),(20,10,OL),(20,11,OL),
            (12,12,OL),(13,12,OL),(14,12,OL),(15,12,OL),(16,12,OL),(17,12,OL),(18,12,OL),(19,12,OL),
            *[(x,y,SK)  for y in range(5,12) for x in range(12,20)],
            *[(x,y,SKD) for y in range(8,12) for x in range(17,20)],
            # Nose protrudes left
            (11,7,SK),(10,7,SK),(10,8,OL),(11,8,OL),
            # Eye
            (13,6,OL),(14,6,EY),(14,7,OL),
            (13,9,PK),
            (14,10,OL),
            # Circlet
            *[(x,4,GD) for x in range(12,20)],
            (11,4,GDD),(20,4,GDD),(11,4,OL),(20,4,OL),
            # Hair on back side
            (20,5,HR),(20,6,HR),(20,7,HR),(20,8,HR),
            (20,5,OL),(20,9,OL),
        ])

    def body_side_L(ox, oy):
        dp(px, ox, oy, [
            (14,13,SKD),(15,13,SK),(16,13,SKD),
            (12,13,OL),(12,14,OL),(12,15,OL),(12,16,OL),(12,17,OL),(12,18,OL),(12,19,OL),(12,20,OL),(12,21,OL),(12,22,OL),
            (20,13,OL),(20,14,OL),(20,15,OL),(20,16,OL),(20,17,OL),(20,18,OL),(20,19,OL),(20,20,OL),(20,21,OL),(20,22,OL),
            *[(x,13,OL) for x in range(13,20)],
            *[(x,22,OL) for x in range(13,20)],
            *[(x,y,GR)  for y in range(14,22) for x in range(13,20)],
            *[(x,y,GRD) for y in range(14,22) for x in [13,19]],
            *[(x,22,GD) for x in range(13,20)],
        ])

    # ── SIDE R VIEW ───────────────────────────────────────────────────────

    def head_side_R(ox, oy):
        dp(px, ox, oy, [
            (12,4,OL),(13,4,OL),(14,4,OL),(15,4,OL),(16,4,OL),(17,4,OL),(18,4,OL),(19,4,OL),
            (11,5,OL),(11,6,OL),(11,7,OL),(11,8,OL),(11,9,OL),(11,10,OL),(11,11,OL),
            (20,5,OL),(20,6,OL),(20,7,OL),(20,8,OL),(20,9,OL),(20,10,OL),(20,11,OL),
            (12,12,OL),(13,12,OL),(14,12,OL),(15,12,OL),(16,12,OL),(17,12,OL),(18,12,OL),(19,12,OL),
            *[(x,y,SK)  for y in range(5,12) for x in range(12,20)],
            *[(x,y,SKD) for y in range(8,12) for x in range(12,15)],
            # Nose protrudes right
            (20,7,SK),(21,7,SK),(21,8,OL),(20,8,OL),
            # Eye
            (17,6,OL),(18,6,EY),(18,7,OL),
            (18,9,PK),
            (17,10,OL),
            # Circlet
            *[(x,4,GD) for x in range(12,20)],
            (11,4,GDD),(20,4,GDD),(11,4,OL),(20,4,OL),
            # Hair on back side
            (11,5,HR),(11,6,HR),(11,7,HR),(11,8,HR),
            (11,5,OL),(11,9,OL),
        ])

    def body_side_R(ox, oy):
        dp(px, ox, oy, [
            (15,13,SK),(16,13,SK),(17,13,SKD),
            (11,13,OL),(11,14,OL),(11,15,OL),(11,16,OL),(11,17,OL),(11,18,OL),(11,19,OL),(11,20,OL),(11,21,OL),(11,22,OL),
            (20,13,OL),(20,14,OL),(20,15,OL),(20,16,OL),(20,17,OL),(20,18,OL),(20,19,OL),(20,20,OL),(20,21,OL),(20,22,OL),
            *[(x,13,OL) for x in range(12,20)],
            *[(x,22,OL) for x in range(12,20)],
            *[(x,y,GR)  for y in range(14,22) for x in range(12,20)],
            *[(x,y,GRD) for y in range(14,22) for x in [12,19]],
            *[(x,22,GD) for x in range(12,20)],
        ])

    SC, SCD = GR, GRD  # green robe sleeves

    # ── ASSEMBLY ──────────────────────────────────────────────────────────
    front_arm_offsets = [(0,0),(1,0),(0,0),(0,1)]
    side_arm_phases   = [0,-1,0,1]

    leg_fns_front = [
        lambda ox,oy: _legs_stand_front(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_stride_right_front(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_stand_front(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_stride_left_front(px,ox,oy,LC,LCD,BC,BCM),
    ]
    for col in range(4):
        ox, oy = frame_origin(col, 0)
        body_front(ox, oy)
        lo, ro = front_arm_offsets[col]
        _arm_left_front(px,ox,oy,SC,SCD,SK,SKD,y_off=lo)
        _arm_right_front(px,ox,oy,SC,SCD,SK,SKD,y_off=ro)
        head_front(ox, oy)
        leg_fns_front[col](ox, oy)

    leg_fns_L = [
        lambda ox,oy: _legs_side_stand_L(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_side_forward_L(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_side_stand_L(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_side_back_L(px,ox,oy,LC,LCD,BC,BCM),
    ]
    for col in range(4):
        ox, oy = frame_origin(col, 1)
        body_side_L(ox, oy)
        _arm_side_L(px,ox,oy,SC,SCD,SK,SKD,phase=side_arm_phases[col])
        head_side_L(ox, oy)
        leg_fns_L[col](ox, oy)

    leg_fns_R = [
        lambda ox,oy: _legs_side_stand_R(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_side_forward_R(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_side_stand_R(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_side_back_R(px,ox,oy,LC,LCD,BC,BCM),
    ]
    for col in range(4):
        ox, oy = frame_origin(col, 2)
        body_side_R(ox, oy)
        _arm_side_R(px,ox,oy,SC,SCD,SK,SKD,phase=side_arm_phases[col])
        head_side_R(ox, oy)
        leg_fns_R[col](ox, oy)

    leg_fns_back = [
        lambda ox,oy: _legs_stand_back(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_stride_right_back(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_stand_back(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_stride_left_back(px,ox,oy,LC,LCD,BC,BCM),
    ]
    for col in range(4):
        ox, oy = frame_origin(col, 3)
        body_back(ox, oy)
        lo, ro = front_arm_offsets[col]
        _arm_left_back(px,ox,oy,SC,SCD,SK,SKD,y_off=lo)
        _arm_right_back(px,ox,oy,SC,SCD,SK,SKD,y_off=ro)
        head_back(ox, oy)
        leg_fns_back[col](ox, oy)

    out_path  = os.path.join(OUT_DIR, "summoner_overworld.png")
    prev_path = os.path.join(OUT_DIR, "summoner_overworld_4x.png")
    save_with_preview(img, out_path, prev_path, "SUMMONER")


# ═══════════════════════════════════════════════════════════════════════════════
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  SPECULATOR                                                              ║
# ║  Charcoal suit, grey swept hair, gold coin accent, brown leather boots  ║
# ╚══════════════════════════════════════════════════════════════════════════╝
# ═══════════════════════════════════════════════════════════════════════════════

def gen_speculator():
    CH  = ( 77,  77,  87, 255)  # charcoal suit
    CHD = ( 46,  46,  51, 255)  # charcoal dark
    CHH = (117, 117, 128, 255)  # charcoal highlight
    SH  = (218, 210, 195, 255)  # shirt/collar (light)
    SHD = (175, 168, 155, 255)  # shirt shadow
    GD  = (224, 194,  51, 255)  # gold coin accent
    GDD = (150, 128,  26, 255)  # gold dark
    SK  = (214, 179, 140, 255)  # skin
    SKD = (173, 138, 102, 255)  # skin shadow
    HR  = ( 71,  71,  71, 255)  # grey hair
    HRD = ( 41,  41,  41, 255)  # hair dark
    EY  = ( 80, 100, 130, 255)  # grey-blue eyes
    LC  = ( 66,  66,  77, 255)  # leg charcoal
    LCD = ( 41,  41,  46, 255)  # leg dark
    BC  = ( 56,  46,  36, 255)  # boot brown leather
    BCM = ( 31,  26,  20, 255)  # boot dark

    img = Image.new("RGBA", (128, 128), T)
    px = img.load()

    # ── FRONT VIEW ────────────────────────────────────────────────────────

    def head_front(ox, oy):
        """Neat swept grey hair, confident grey-blue eyes."""
        dp(px, ox, oy, [
            # Head outline
            (11,4,OL),(12,4,OL),(13,4,OL),(14,4,OL),(15,4,OL),(16,4,OL),(17,4,OL),(18,4,OL),(19,4,OL),(20,4,OL),
            (10,5,OL),(10,6,OL),(10,7,OL),(10,8,OL),(10,9,OL),(10,10,OL),(10,11,OL),
            (21,5,OL),(21,6,OL),(21,7,OL),(21,8,OL),(21,9,OL),(21,10,OL),(21,11,OL),
            (11,12,OL),(12,12,OL),(13,12,OL),(14,12,OL),(15,12,OL),(16,12,OL),(17,12,OL),(18,12,OL),(19,12,OL),(20,12,OL),
            # Skin fill
            *[(x,y,SK)  for y in range(5,12) for x in range(11,21)],
            *[(x,y,SKD) for y in range(9,12) for x in range(17,21)],
            # Eyes
            (13,7,OL),(14,7,EY),(14,8,OL),
            (17,7,OL),(18,7,EY),(18,8,OL),
            # Thin brow (gives calculating look)
            (13,6,HRD),(14,6,HRD),(15,6,HRD),
            (17,6,HRD),(18,6,HRD),(19,6,HRD),
            # Slight smirk
            (15,10,OL),(16,10,OL),(17,10,SKD),
            # Grey swept hair top
            *[(x,4,HR) for x in range(11,21)],
            *[(x,5,HR) for x in range(11,14)],
            *[(x,5,HR) for x in range(17,21)],
            (11,6,HRD),(12,6,HRD),(19,6,HRD),(20,6,HRD),
            # Side hair locks
            (10,5,HR),(10,6,HR),(10,7,HR),
            (21,5,HR),(21,6,HR),(21,7,HR),
            (10,5,OL),(10,8,OL),(21,5,OL),(21,8,OL),
        ])

    def body_front(ox, oy):
        """Sharp charcoal vest, white shirt, gold coin pocket."""
        dp(px, ox, oy, [
            # White collar at neck
            (14,13,SH),(15,13,SH),(16,13,SH),(17,13,SH),
            (13,13,SKD),(18,13,SKD),
            # Slim body outline (bard-width)
            (11,13,OL),(11,14,OL),(11,15,OL),(11,16,OL),(11,17,OL),(11,18,OL),(11,19,OL),(11,20,OL),(11,21,OL),(11,22,OL),
            (20,13,OL),(20,14,OL),(20,15,OL),(20,16,OL),(20,17,OL),(20,18,OL),(20,19,OL),(20,20,OL),(20,21,OL),(20,22,OL),
            *[(x,13,OL) for x in range(12,20)],
            *[(x,22,OL) for x in range(12,20)],
            # Charcoal vest fill
            *[(x,y,CH)  for y in range(14,22) for x in range(12,20)],
            *[(x,y,CHD) for y in range(14,22) for x in [12,19]],
            # White shirt visible centre
            *[(x,y,SH)  for y in range(14,20) for x in [15,16]],
            *[(x,y,SHD) for y in range(17,22) for x in [15,16]],
            # Gold coin/pocket watch left breast
            (13,15,GD),(14,15,GD),(13,16,GD),(14,16,GD),
            (12,15,GDD),(12,16,GDD),
            # Gold buttons centre
            (15,14,GD),(15,16,GD),(15,18,GD),(15,20,GD),
            # Gold shoulder trim
            *[(x,14,GD) for x in range(13,15)],
            *[(x,14,GD) for x in range(17,19)],
        ])

    # ── BACK VIEW ─────────────────────────────────────────────────────────

    def head_back(ox, oy):
        dp(px, ox, oy, [
            (11,4,OL),(12,4,OL),(13,4,OL),(14,4,OL),(15,4,OL),(16,4,OL),(17,4,OL),(18,4,OL),(19,4,OL),(20,4,OL),
            (10,5,OL),(10,6,OL),(10,7,OL),(10,8,OL),(10,9,OL),(10,10,OL),(10,11,OL),
            (21,5,OL),(21,6,OL),(21,7,OL),(21,8,OL),(21,9,OL),(21,10,OL),(21,11,OL),
            (11,12,OL),(12,12,OL),(13,12,OL),(14,12,OL),(15,12,OL),(16,12,OL),(17,12,OL),(18,12,OL),(19,12,OL),(20,12,OL),
            # Hair back
            *[(x,y,HR)  for y in range(5,12) for x in range(11,21)],
            *[(x,y,HRD) for y in range(7,12) for x in range(13,19)],
            # Collar hint
            (14,12,SH),(15,12,SH),(16,12,SH),(17,12,SH),
        ])

    def body_back(ox, oy):
        dp(px, ox, oy, [
            (14,13,HRD),(15,13,HR),(16,13,HR),(17,13,HRD),
            (11,13,OL),(11,14,OL),(11,15,OL),(11,16,OL),(11,17,OL),(11,18,OL),(11,19,OL),(11,20,OL),(11,21,OL),(11,22,OL),
            (20,13,OL),(20,14,OL),(20,15,OL),(20,16,OL),(20,17,OL),(20,18,OL),(20,19,OL),(20,20,OL),(20,21,OL),(20,22,OL),
            *[(x,13,OL) for x in range(12,20)],
            *[(x,22,OL) for x in range(12,20)],
            *[(x,y,CHD) for y in range(14,22) for x in range(12,20)],
            *[(x,y,CH)  for y in range(14,20) for x in range(14,18)],
        ])

    # ── SIDE L VIEW ───────────────────────────────────────────────────────

    def head_side_L(ox, oy):
        dp(px, ox, oy, [
            (12,4,OL),(13,4,OL),(14,4,OL),(15,4,OL),(16,4,OL),(17,4,OL),(18,4,OL),(19,4,OL),
            (11,5,OL),(11,6,OL),(11,7,OL),(11,8,OL),(11,9,OL),(11,10,OL),(11,11,OL),
            (20,5,OL),(20,6,OL),(20,7,OL),(20,8,OL),(20,9,OL),(20,10,OL),(20,11,OL),
            (12,12,OL),(13,12,OL),(14,12,OL),(15,12,OL),(16,12,OL),(17,12,OL),(18,12,OL),(19,12,OL),
            *[(x,y,SK)  for y in range(5,12) for x in range(12,20)],
            *[(x,y,SKD) for y in range(8,12) for x in range(16,20)],
            # Nose protrudes left
            (11,7,SK),(10,7,SK),(10,8,OL),(11,8,OL),
            # Eye
            (13,6,OL),(14,6,EY),(14,7,OL),
            # Brow
            (13,5,HRD),(14,5,HRD),
            (14,10,OL),
            # Hair swept top and back
            *[(x,4,HR) for x in range(12,20)],
            (20,5,HR),(20,6,HR),
            (20,5,OL),(20,7,OL),
        ])

    def body_side_L(ox, oy):
        dp(px, ox, oy, [
            (14,13,SHD),(15,13,SH),(16,13,SHD),
            (12,13,OL),(12,14,OL),(12,15,OL),(12,16,OL),(12,17,OL),(12,18,OL),(12,19,OL),(12,20,OL),(12,21,OL),(12,22,OL),
            (20,13,OL),(20,14,OL),(20,15,OL),(20,16,OL),(20,17,OL),(20,18,OL),(20,19,OL),(20,20,OL),(20,21,OL),(20,22,OL),
            *[(x,13,OL) for x in range(13,20)],
            *[(x,22,OL) for x in range(13,20)],
            *[(x,y,CH)  for y in range(14,22) for x in range(13,20)],
            *[(x,y,CHD) for y in range(14,22) for x in [13,19]],
            *[(x,y,SH)  for y in range(14,19) for x in [16,17]],
        ])

    # ── SIDE R VIEW ───────────────────────────────────────────────────────

    def head_side_R(ox, oy):
        dp(px, ox, oy, [
            (12,4,OL),(13,4,OL),(14,4,OL),(15,4,OL),(16,4,OL),(17,4,OL),(18,4,OL),(19,4,OL),
            (11,5,OL),(11,6,OL),(11,7,OL),(11,8,OL),(11,9,OL),(11,10,OL),(11,11,OL),
            (20,5,OL),(20,6,OL),(20,7,OL),(20,8,OL),(20,9,OL),(20,10,OL),(20,11,OL),
            (12,12,OL),(13,12,OL),(14,12,OL),(15,12,OL),(16,12,OL),(17,12,OL),(18,12,OL),(19,12,OL),
            *[(x,y,SK)  for y in range(5,12) for x in range(12,20)],
            *[(x,y,SKD) for y in range(8,12) for x in range(12,15)],
            # Nose protrudes right
            (20,7,SK),(21,7,SK),(21,8,OL),(20,8,OL),
            # Eye
            (17,6,OL),(18,6,EY),(18,7,OL),
            # Brow
            (17,5,HRD),(18,5,HRD),
            (17,10,OL),
            # Hair swept top and back
            *[(x,4,HR) for x in range(12,20)],
            (11,5,HR),(11,6,HR),
            (11,5,OL),(11,7,OL),
        ])

    def body_side_R(ox, oy):
        dp(px, ox, oy, [
            (15,13,SH),(16,13,SH),(17,13,SHD),
            (11,13,OL),(11,14,OL),(11,15,OL),(11,16,OL),(11,17,OL),(11,18,OL),(11,19,OL),(11,20,OL),(11,21,OL),(11,22,OL),
            (20,13,OL),(20,14,OL),(20,15,OL),(20,16,OL),(20,17,OL),(20,18,OL),(20,19,OL),(20,20,OL),(20,21,OL),(20,22,OL),
            *[(x,13,OL) for x in range(12,20)],
            *[(x,22,OL) for x in range(12,20)],
            *[(x,y,CH)  for y in range(14,22) for x in range(12,20)],
            *[(x,y,CHD) for y in range(14,22) for x in [12,19]],
            *[(x,y,SH)  for y in range(14,19) for x in [13,14]],
        ])

    SC, SCD = CH, CHD  # charcoal suit sleeves

    # ── ASSEMBLY ──────────────────────────────────────────────────────────
    front_arm_offsets = [(0,0),(1,0),(0,0),(0,1)]
    side_arm_phases   = [0,-1,0,1]

    leg_fns_front = [
        lambda ox,oy: _legs_stand_front(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_stride_right_front(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_stand_front(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_stride_left_front(px,ox,oy,LC,LCD,BC,BCM),
    ]
    for col in range(4):
        ox, oy = frame_origin(col, 0)
        body_front(ox, oy)
        lo, ro = front_arm_offsets[col]
        _arm_left_front(px,ox,oy,SC,SCD,SK,SKD,y_off=lo)
        _arm_right_front(px,ox,oy,SC,SCD,SK,SKD,y_off=ro)
        head_front(ox, oy)
        leg_fns_front[col](ox, oy)

    leg_fns_L = [
        lambda ox,oy: _legs_side_stand_L(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_side_forward_L(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_side_stand_L(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_side_back_L(px,ox,oy,LC,LCD,BC,BCM),
    ]
    for col in range(4):
        ox, oy = frame_origin(col, 1)
        body_side_L(ox, oy)
        _arm_side_L(px,ox,oy,SC,SCD,SK,SKD,phase=side_arm_phases[col])
        head_side_L(ox, oy)
        leg_fns_L[col](ox, oy)

    leg_fns_R = [
        lambda ox,oy: _legs_side_stand_R(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_side_forward_R(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_side_stand_R(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_side_back_R(px,ox,oy,LC,LCD,BC,BCM),
    ]
    for col in range(4):
        ox, oy = frame_origin(col, 2)
        body_side_R(ox, oy)
        _arm_side_R(px,ox,oy,SC,SCD,SK,SKD,phase=side_arm_phases[col])
        head_side_R(ox, oy)
        leg_fns_R[col](ox, oy)

    leg_fns_back = [
        lambda ox,oy: _legs_stand_back(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_stride_right_back(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_stand_back(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_stride_left_back(px,ox,oy,LC,LCD,BC,BCM),
    ]
    for col in range(4):
        ox, oy = frame_origin(col, 3)
        body_back(ox, oy)
        lo, ro = front_arm_offsets[col]
        _arm_left_back(px,ox,oy,SC,SCD,SK,SKD,y_off=lo)
        _arm_right_back(px,ox,oy,SC,SCD,SK,SKD,y_off=ro)
        head_back(ox, oy)
        leg_fns_back[col](ox, oy)

    out_path  = os.path.join(OUT_DIR, "speculator_overworld.png")
    prev_path = os.path.join(OUT_DIR, "speculator_overworld_4x.png")
    save_with_preview(img, out_path, prev_path, "SPECULATOR")


# ═══════════════════════════════════════════════════════════════════════════════
#  MAIN
# ═══════════════════════════════════════════════════════════════════════════════
if __name__ == "__main__":
    print("=== Generating GUARDIAN overworld sprite ===")
    gen_guardian()

    print("=== Generating NINJA overworld sprite ===")
    gen_ninja()

    print("=== Generating SUMMONER overworld sprite ===")
    gen_summoner()

    print("=== Generating SPECULATOR overworld sprite ===")
    gen_speculator()

    print("\nAll 4 advanced overworld sprite sheets complete.")
