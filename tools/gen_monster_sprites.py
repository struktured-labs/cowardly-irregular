#!/usr/bin/env python3
"""
Generate SNES-style pixel art monster sprite sheets for Cowardly Irregular.
Each monster: 2048x256 strip, 8 frames of 256x256.
Frame layout: 0-1 idle, 2-3 attack, 4-5 hit, 6-7 dead.
"""

from PIL import Image, ImageDraw
import os
import math

FRAME_W = 256
FRAME_H = 256
TOTAL_FRAMES = 8
STRIP_W = FRAME_W * TOTAL_FRAMES
STRIP_H = FRAME_H
OUT_DIR = "/home/struktured/projects/cowardly-irregular/assets/sprites/monsters"

# ──────────────────────────────────────────────
# Drawing helpers
# ──────────────────────────────────────────────

def new_frame():
    return Image.new("RGBA", (FRAME_W, FRAME_H), (0, 0, 0, 0))

def new_strip():
    return Image.new("RGBA", (STRIP_W, STRIP_H), (0, 0, 0, 0))

def place_frame(strip, frame, idx):
    strip.paste(frame, (idx * FRAME_W, 0), frame)

def draw_ellipse_aa(draw, bbox, fill, outline=None, width=2):
    """Draw ellipse with outline for SNES pixel art look."""
    if outline:
        draw.ellipse(bbox, fill=outline)
        inner = (bbox[0]+width, bbox[1]+width, bbox[2]-width, bbox[3]-width)
        draw.ellipse(inner, fill=fill)
    else:
        draw.ellipse(bbox, fill=fill)

def draw_poly_aa(draw, points, fill, outline=None):
    if outline:
        draw.polygon(points, fill=outline)
    draw.polygon(points, fill=fill)

def shade(color, factor):
    """Darken or lighten an RGBA color by factor (0.0-2.0)."""
    r, g, b, a = color
    return (
        min(255, max(0, int(r * factor))),
        min(255, max(0, int(g * factor))),
        min(255, max(0, int(b * factor))),
        a
    )

def outline_color(fill):
    return shade(fill, 0.3)

def highlight(fill):
    return shade(fill, 1.5)

def draw_pixel_rect(draw, x, y, w, h, color):
    draw.rectangle([x, y, x+w-1, y+h-1], fill=color)

def draw_shadow(draw, cx, cy, rx, ry, alpha=80):
    shadow = (0, 0, 0, alpha)
    draw.ellipse([cx-rx, cy-ry//3, cx+rx, cy+ry//3], fill=shadow)

# ──────────────────────────────────────────────
# SNES pixel art outline helper
# Draws shape then dark outline around it
# ──────────────────────────────────────────────

def px_circle(draw, cx, cy, r, fill, ol_width=3):
    ol = outline_color(fill)
    draw.ellipse([cx-r-ol_width, cy-r-ol_width, cx+r+ol_width, cy+r+ol_width], fill=ol)
    draw.ellipse([cx-r, cy-r, cx+r, cy+r], fill=fill)
    # highlight
    hl = highlight(fill)
    draw.ellipse([cx-r//2, cy-r//2, cx-r//5, cy-r//5], fill=hl)

def px_ellipse(draw, cx, cy, rx, ry, fill, ol_width=3):
    ol = outline_color(fill)
    draw.ellipse([cx-rx-ol_width, cy-ry-ol_width, cx+rx+ol_width, cy+ry+ol_width], fill=ol)
    draw.ellipse([cx-rx, cy-ry, cx+rx, cy+ry], fill=fill)
    hl = highlight(fill)
    draw.ellipse([cx-rx//2, cy-ry//2, cx-rx//5, cy-ry//5], fill=hl)

def px_rect(draw, x, y, w, h, fill, ol_width=2):
    ol = outline_color(fill)
    draw.rectangle([x-ol_width, y-ol_width, x+w+ol_width, y+h+ol_width], fill=ol)
    draw.rectangle([x, y, x+w, y+h], fill=fill)

# ──────────────────────────────────────────────
# SLIME
# ──────────────────────────────────────────────

SLIME_BODY   = (64, 180, 80, 255)
SLIME_DARK   = (30, 100, 45, 255)
SLIME_LIGHT  = (140, 230, 140, 255)
SLIME_SHEEN  = (200, 255, 200, 180)
SLIME_EYE    = (255, 255, 255, 255)
SLIME_PUPIL  = (20, 60, 20, 255)

def draw_slime(draw, cx, cy, squish_y=0, hit=False, dead=False):
    """cx, cy = centre of slime body."""
    body_col = (220, 60, 60, 200) if hit else SLIME_BODY
    rx = 62
    ry = 52 + squish_y
    base_y = cy + 10

    # Shadow
    draw_shadow(draw, cx, base_y + ry - 5, rx - 10, 10)

    # Outline
    ol = outline_color(body_col)
    draw.ellipse([cx-rx-4, base_y-ry-4, cx+rx+4, base_y+ry+4], fill=ol)
    # Body blob
    draw.ellipse([cx-rx, base_y-ry, cx+rx, base_y+ry], fill=body_col)
    # Inner highlight blob
    draw.ellipse([cx-rx+8, base_y-ry+6, cx+20, base_y-ry//3], fill=SLIME_LIGHT)
    # Sheen dot
    draw.ellipse([cx-30, base_y-ry+10, cx-10, base_y-ry+25], fill=SLIME_SHEEN)

    if dead:
        # Splat — flat puddle
        return

    # Eyes
    eye_y = base_y - ry//2 + 8
    for ex in [cx-18, cx+10]:
        draw.ellipse([ex-8, eye_y-9, ex+8, eye_y+9], fill=SLIME_EYE)
        draw.ellipse([ex-5, eye_y-6, ex+5, eye_y+6], fill=SLIME_PUPIL)
        # Pupils glint
        draw.ellipse([ex-2, eye_y-5, ex+1, eye_y-2], fill=(255,255,255,200))

    # Mouth smile
    for i in range(-12, 13, 3):
        my = base_y + ry//4 + abs(i)//3
        draw.rectangle([cx+i, my, cx+i+2, my+2], fill=SLIME_DARK)


def slime_idle(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    bob = -4 if frame_idx == 0 else 4
    draw_slime(d, 128, 115 + bob, squish_y=bob//2)
    return img

def slime_attack(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    # Lunge right, elongate horizontally
    stretch = 12 if frame_idx == 1 else 0
    cx = 128 + (20 if frame_idx == 1 else 0)
    draw_slime(d, cx, 118, squish_y=-stretch//3)
    # Speed lines
    if frame_idx == 1:
        for i in range(3):
            sy = 90 + i*20
            d.line([(20, sy), (80, sy+5)], fill=(180,230,180,120), width=2)
    return img

def slime_hit(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_slime(d, 128, 118, squish_y=8, hit=True)
    # Flash overlay
    flash = Image.new("RGBA", (FRAME_W, FRAME_H), (255,255,255,0))
    fd = ImageDraw.Draw(flash)
    fd.ellipse([60,60,200,180], fill=(255,200,200,60))
    img = Image.alpha_composite(img, flash)
    return img

def slime_dead(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    # Flat puddle
    cx, cy = 128, 185
    d.ellipse([cx-75, cy-22, cx+75, cy+22], fill=outline_color(SLIME_BODY))
    d.ellipse([cx-70, cy-18, cx+70, cy+18], fill=SLIME_BODY)
    d.ellipse([cx-50, cy-12, cx+10, cy-2], fill=SLIME_LIGHT)
    # X eyes floating above
    for ex in [cx-20, cx+15]:
        d.line([(ex-7, cy-40), (ex+7, cy-26)], fill=SLIME_DARK, width=3)
        d.line([(ex+7, cy-40), (ex-7, cy-26)], fill=SLIME_DARK, width=3)
    return img

def make_slime():
    strip = new_strip()
    frames = [
        slime_idle(0), slime_idle(1),
        slime_attack(0), slime_attack(1),
        slime_hit(0), slime_hit(1),
        slime_dead(0), slime_dead(1),
    ]
    for i, f in enumerate(frames):
        place_frame(strip, f, i)
    return strip


# ──────────────────────────────────────────────
# BAT
# ──────────────────────────────────────────────

BAT_BODY   = (55, 25, 75, 255)
BAT_WING   = (80, 40, 100, 255)
BAT_WING_M = (100, 55, 120, 255)
BAT_EYE    = (220, 30, 30, 255)
BAT_FANG   = (240, 240, 240, 255)
BAT_DARK   = (25, 10, 35, 255)

def draw_bat(draw, cx, cy, wing_up=True, hit=False, dead=False, dive=False):
    body_col = (200,80,80,220) if hit else BAT_BODY

    spread = -40 if wing_up else 40
    wing_tip_y = cy + spread

    # Shadow
    draw_shadow(draw, cx, cy+65, 55, 12)

    # Wings (polygons)
    ol = BAT_DARK
    # Left wing
    lwing = [(cx-10, cy), (cx-90, cy-15+spread//2), (cx-105, wing_tip_y+15), (cx-70, cy+20), (cx-15, cy+15)]
    draw.polygon(lwing, fill=ol)
    lwing_in = [(cx-10, cy), (cx-86, cy-12+spread//2), (cx-99, wing_tip_y+12), (cx-67, cy+17), (cx-15, cy+12)]
    draw.polygon(lwing_in, fill=BAT_WING)
    # Wing membrane detail
    draw.line([(cx-10, cy), (cx-105, wing_tip_y+15)], fill=BAT_WING_M, width=2)
    draw.line([(cx-10, cy), (cx-80, wing_tip_y+30)], fill=BAT_WING_M, width=1)

    # Right wing
    rwing = [(cx+10, cy), (cx+90, cy-15+spread//2), (cx+105, wing_tip_y+15), (cx+70, cy+20), (cx+15, cy+15)]
    draw.polygon(rwing, fill=ol)
    rwing_in = [(cx+10, cy), (cx+86, cy-12+spread//2), (cx+99, wing_tip_y+12), (cx+67, cy+17), (cx+15, cy+12)]
    draw.polygon(rwing_in, fill=BAT_WING)
    draw.line([(cx+10, cy), (cx+105, wing_tip_y+15)], fill=BAT_WING_M, width=2)
    draw.line([(cx+10, cy), (cx+80, wing_tip_y+30)], fill=BAT_WING_M, width=1)

    if dead:
        # Body flat on ground
        draw.ellipse([cx-28, cy+30, cx+28, cy+60], fill=ol)
        draw.ellipse([cx-24, cy+33, cx+24, cy+57], fill=body_col)
        # X eyes
        for ex in [cx-8, cx+6]:
            draw.line([(ex-5,cy+40),(ex+5,cy+50)], fill=BAT_EYE, width=2)
            draw.line([(ex+5,cy+40),(ex-5,cy+50)], fill=BAT_EYE, width=2)
        return

    # Body
    draw.ellipse([cx-26, cy-22, cx+26, cy+28], fill=ol)
    draw.ellipse([cx-22, cy-18, cx+22, cy+24], fill=body_col)
    # Head
    draw.ellipse([cx-18, cy-40, cx+18, cy-8], fill=ol)
    draw.ellipse([cx-14, cy-36, cx+14, cy-12], fill=body_col)
    # Ears
    draw.polygon([(cx-14, cy-36),(cx-22, cy-58),(cx-5, cy-38)], fill=BAT_DARK)
    draw.polygon([(cx+14, cy-36),(cx+22, cy-58),(cx+5, cy-38)], fill=BAT_DARK)
    draw.polygon([(cx-12, cy-37),(cx-18, cy-54),(cx-6, cy-39)], fill=BAT_WING)
    draw.polygon([(cx+12, cy-37),(cx+18, cy-54),(cx+6, cy-39)], fill=BAT_WING)

    # Eyes
    for ex in [cx-7, cx+4]:
        draw.ellipse([ex-5, cy-30, ex+5, cy-20], fill=BAT_EYE)
        draw.ellipse([ex-2, cy-29, ex+3, cy-22], fill=(255,60,60,255))
        draw.rectangle([ex-1, cy-28, ex+1, cy-24], fill=(255,255,255,200))

    if not hit:
        # Fangs
        draw.polygon([(cx-7, cy-15),(cx-4, cy-4),(cx-1, cy-15)], fill=BAT_FANG)
        draw.polygon([(cx+1, cy-15),(cx+4, cy-4),(cx+7, cy-15)], fill=BAT_FANG)


def bat_idle(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_bat(d, 128, 110, wing_up=(frame_idx==0))
    return img

def bat_attack(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    cx = 128 + (30 if frame_idx==1 else 0)
    cy = 110 + (20 if frame_idx==1 else 0)
    draw_bat(d, cx, cy, wing_up=True, dive=(frame_idx==1))
    if frame_idx==1:
        for i in range(4):
            d.line([(20+i*5, 90+i*8),(60+i*5, 100+i*8)], fill=(150,80,180,100), width=2)
    return img

def bat_hit(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    cx = 128 + (-15 if frame_idx==0 else -25)
    draw_bat(d, cx, 110, wing_up=False, hit=True)
    flash = Image.new("RGBA", (FRAME_W, FRAME_H), (0,0,0,0))
    fd = ImageDraw.Draw(flash)
    fd.ellipse([60,60,200,190], fill=(255,200,200,50))
    img = Image.alpha_composite(img, flash)
    return img

def bat_dead(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_bat(d, 128, 150, dead=True)
    return img

def make_bat():
    strip = new_strip()
    frames = [bat_idle(0), bat_idle(1), bat_attack(0), bat_attack(1),
              bat_hit(0), bat_hit(1), bat_dead(0), bat_dead(1)]
    for i,f in enumerate(frames): place_frame(strip, f, i)
    return strip


# ──────────────────────────────────────────────
# GOBLIN
# ──────────────────────────────────────────────

GOB_SKIN   = (80, 130, 50, 255)
GOB_SKIN_D = (45, 80, 25, 255)
GOB_CLOTH  = (120, 80, 30, 255)
GOB_CLOTH_D= (70, 45, 15, 255)
GOB_CLUB   = (100, 65, 25, 255)
GOB_CLUB_D = (55, 35, 10, 255)
GOB_EYE    = (255, 180, 0, 255)
GOB_PUPIL  = (20, 10, 0, 255)
GOB_TOOTH  = (230, 220, 180, 255)

def draw_goblin(draw, cx, cy_offset=0, arm_up=False, hit=False, dead=False):
    cy_base = 195 + cy_offset
    skin = (200,80,80,220) if hit else GOB_SKIN

    # Shadow
    draw_shadow(draw, cx, cy_base+2, 38, 10)

    if dead:
        # Lying flat
        body_y = cy_base - 20
        draw.ellipse([cx-45, body_y-20, cx+45, body_y+20], fill=GOB_SKIN_D)
        draw.ellipse([cx-40, body_y-16, cx+40, body_y+16], fill=GOB_SKIN)
        draw.ellipse([cx-22, body_y-28, cx+22, body_y-8], fill=GOB_SKIN_D)
        draw.ellipse([cx-18, body_y-26, cx+18, body_y-10], fill=GOB_SKIN)
        for ex in [cx-8, cx+4]:
            draw.line([(ex-5,body_y-20),(ex+5,body_y-12)], fill=GOB_SKIN_D, width=2)
            draw.line([(ex+5,body_y-20),(ex-5,body_y-12)], fill=GOB_SKIN_D, width=2)
        return

    # Legs
    leg_h = 36
    for lx in [cx-16, cx+6]:
        draw.rectangle([lx, cy_base-leg_h, lx+18, cy_base], fill=GOB_SKIN_D)
        draw.rectangle([lx+2, cy_base-leg_h+2, lx+16, cy_base-2], fill=GOB_CLOTH_D)
        # Feet
        draw.ellipse([lx-4, cy_base-8, lx+22, cy_base+6], fill=GOB_SKIN_D)
        draw.ellipse([lx-2, cy_base-6, lx+20, cy_base+4], fill=GOB_SKIN)

    # Body
    bw, bh = 54, 52
    bx, by = cx - bw//2, cy_base - leg_h - bh
    draw.rectangle([bx-3, by-3, bx+bw+3, by+bh+3], fill=GOB_SKIN_D)
    draw.rectangle([bx, by, bx+bw, by+bh], fill=GOB_CLOTH)
    # Belt
    draw.rectangle([bx, by+bh-14, bx+bw, by+bh-6], fill=GOB_SKIN_D)
    # Belly
    draw.ellipse([bx+8, by+bh//3, bx+bw-8, by+bh-10], fill=skin)

    # Head
    head_r = 28
    hx, hy = cx, by - head_r - 4
    draw.ellipse([hx-head_r-3, hy-head_r-3, hx+head_r+3, hy+head_r+3], fill=GOB_SKIN_D)
    draw.ellipse([hx-head_r, hy-head_r, hx+head_r, hy+head_r], fill=skin)
    # Highlight
    draw.ellipse([hx-head_r+4, hy-head_r+4, hx, hy-4], fill=highlight(skin))
    # Ears
    draw.ellipse([hx-head_r-8, hy-8, hx-head_r+8, hy+14], fill=GOB_SKIN_D)
    draw.ellipse([hx-head_r-5, hy-5, hx-head_r+6, hy+11], fill=skin)
    draw.ellipse([hx+head_r-8, hy-8, hx+head_r+8, hy+14], fill=GOB_SKIN_D)
    draw.ellipse([hx+head_r-6, hy-5, hx+head_r+5, hy+11], fill=skin)
    # Eyes
    for ex in [hx-11, hx+4]:
        draw.ellipse([ex-7, hy-9, ex+7, hy+4], fill=(20,20,20,255))
        draw.ellipse([ex-5, hy-7, ex+5, hy+2], fill=GOB_EYE)
        draw.ellipse([ex-2, hy-5, ex+2, hy-1], fill=GOB_PUPIL)
        draw.rectangle([ex-1, hy-6, ex+1, hy-3], fill=(255,255,255,200))
    # Nose
    draw.ellipse([hx-5, hy+2, hx+5, hy+10], fill=GOB_SKIN_D)
    draw.rectangle([hx-4, hy+4, hx-2, hy+8], fill=(40,20,10,150))
    draw.rectangle([hx+2, hy+4, hx+4, hy+8], fill=(40,20,10,150))
    # Mouth/teeth
    draw.arc([hx-10, hy+8, hx+10, hy+18], 10, 170, fill=GOB_SKIN_D, width=2)
    draw.polygon([(hx-8, hy+10),(hx-5, hy+16),(hx-2, hy+10)], fill=GOB_TOOTH)
    draw.polygon([(hx+2, hy+10),(hx+5, hy+16),(hx+8, hy+10)], fill=GOB_TOOTH)

    # Club arm
    if arm_up:
        # Right arm raised
        draw.rectangle([bx+bw-4, by-3, bx+bw+20, by+22], fill=GOB_SKIN_D)
        draw.rectangle([bx+bw-2, by-1, bx+bw+18, by+20], fill=skin)
        # Club up
        club_x = bx + bw + 8
        club_y = by - 50
        draw.rectangle([club_x-5, club_y, club_x+5, by+5], fill=GOB_CLUB_D)
        draw.rectangle([club_x-3, club_y+2, club_x+3, by+3], fill=GOB_CLUB)
        draw.ellipse([club_x-12, club_y-8, club_x+12, club_y+20], fill=GOB_CLUB_D)
        draw.ellipse([club_x-10, club_y-6, club_x+10, club_y+18], fill=GOB_CLUB)
    else:
        # Arm at side
        draw.rectangle([bx+bw-4, by+20, bx+bw+20, by+bh+5], fill=GOB_SKIN_D)
        draw.rectangle([bx+bw-2, by+22, bx+bw+18, by+bh+3], fill=skin)
        # Club at side
        club_x = bx + bw + 14
        draw.rectangle([club_x-5, by+bh-15, club_x+5, cy_base-leg_h+10], fill=GOB_CLUB_D)
        draw.rectangle([club_x-3, by+bh-13, club_x+3, cy_base-leg_h+8], fill=GOB_CLUB)
        draw.ellipse([club_x-10, cy_base-leg_h+5, club_x+10, cy_base-leg_h+28], fill=GOB_CLUB_D)
        draw.ellipse([club_x-8, cy_base-leg_h+7, club_x+8, cy_base-leg_h+26], fill=GOB_CLUB)
    # Left arm
    draw.rectangle([bx-20, by+15, bx+4, by+bh], fill=GOB_SKIN_D)
    draw.rectangle([bx-18, by+17, bx+2, by+bh-2], fill=skin)


def goblin_idle(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    bob = -3 if frame_idx == 0 else 3
    draw_goblin(d, 118, bob)
    return img

def goblin_attack(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    cx = 118 + (18 if frame_idx==1 else 0)
    draw_goblin(d, cx, cy_offset=0, arm_up=(frame_idx==1))
    return img

def goblin_hit(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_goblin(d, 118 - 15, hit=True)
    flash = Image.new("RGBA", (FRAME_W, FRAME_H), (0,0,0,0))
    fd = ImageDraw.Draw(flash)
    fd.ellipse([50, 60, 210, 220], fill=(255,200,200,50))
    img = Image.alpha_composite(img, flash)
    return img

def goblin_dead(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_goblin(d, 118, dead=True)
    return img

def make_goblin():
    strip = new_strip()
    frames = [goblin_idle(0), goblin_idle(1), goblin_attack(0), goblin_attack(1),
              goblin_hit(0), goblin_hit(1), goblin_dead(0), goblin_dead(1)]
    for i,f in enumerate(frames): place_frame(strip, f, i)
    return strip


# ──────────────────────────────────────────────
# WOLF
# ──────────────────────────────────────────────

WOLF_FUR   = (110, 100, 85, 255)
WOLF_DARK  = (55, 48, 38, 255)
WOLF_LIGHT = (185, 175, 155, 255)
WOLF_EYE   = (220, 180, 20, 255)
WOLF_PUPIL = (20, 10, 0, 255)
WOLF_FANG  = (240, 235, 220, 255)
WOLF_NOSE  = (40, 28, 22, 255)
WOLF_TONGUE= (200, 80, 80, 255)

def draw_wolf(draw, cx, bob=0, lunge=False, hit=False, dead=False):
    fur = (200,90,90,220) if hit else WOLF_FUR

    cy_body = 165 + bob

    # Shadow
    draw_shadow(draw, cx, 205, 65, 12)

    if dead:
        # Lying sideways
        draw.ellipse([cx-70, 180, cx+70, 215], fill=WOLF_DARK)
        draw.ellipse([cx-65, 183, cx+65, 212], fill=fur)
        # Legs sticking up
        draw.rectangle([cx-20, 165, cx-5, 190], fill=WOLF_DARK)
        draw.rectangle([cx+5, 160, cx+20, 188], fill=WOLF_DARK)
        # Head to side
        draw.ellipse([cx+45, 175, cx+80, 205], fill=WOLF_DARK)
        draw.ellipse([cx+48, 178, cx+77, 202], fill=fur)
        draw.line([(cx+54, 188),(cx+56, 192)], fill=(255,255,255,200), width=2)
        return

    lean = 25 if lunge else 0

    # Tail
    tail_pts = [(cx-55+lean, cy_body-5), (cx-90+lean, cy_body-40), (cx-75+lean, cy_body-55)]
    draw.line(tail_pts, fill=WOLF_DARK, width=9)
    draw.line(tail_pts, fill=fur, width=6)
    # Tail tip
    draw.ellipse([cx-80+lean, cy_body-62, cx-66+lean, cy_body-48], fill=WOLF_LIGHT)

    # Body
    bw, bh = 85, 55
    bx, by = cx - bw//2 + lean//2, cy_body - bh//2
    draw.ellipse([bx-4, by-4, bx+bw+4, by+bh+4], fill=WOLF_DARK)
    draw.ellipse([bx, by, bx+bw, by+bh], fill=fur)
    # Belly lighter patch
    draw.ellipse([bx+10, by+bh//3, bx+bw-10, by+bh-5], fill=WOLF_LIGHT)

    # Legs (4)
    leg_w = 14
    for lxi, lx in enumerate([cx-40+lean, cx-18+lean, cx+5+lean, cx+28+lean]):
        lleg_y = by + bh - 5
        draw.rectangle([lx, lleg_y, lx+leg_w, lleg_y+38], fill=WOLF_DARK)
        draw.rectangle([lx+2, lleg_y+2, lx+leg_w-2, lleg_y+36], fill=fur)
        # Paws
        draw.ellipse([lx-4, lleg_y+32, lx+leg_w+4, lleg_y+46], fill=WOLF_DARK)
        draw.ellipse([lx-2, lleg_y+34, lx+leg_w+2, lleg_y+44], fill=WOLF_LIGHT)

    # Neck / head
    neck_x = cx + 30 + lean
    draw.ellipse([neck_x-14, cy_body-bh//2-22, neck_x+14, cy_body-bh//2+18], fill=WOLF_DARK)
    draw.ellipse([neck_x-11, cy_body-bh//2-18, neck_x+11, cy_body-bh//2+14], fill=fur)

    # Head
    head_cx = neck_x + 18
    head_cy = cy_body - bh//2 - 15
    draw.ellipse([head_cx-28, head_cy-22, head_cx+28, head_cy+24], fill=WOLF_DARK)
    draw.ellipse([head_cx-25, head_cy-18, head_cx+25, head_cy+20], fill=fur)
    # Snout
    draw.ellipse([head_cx+5, head_cy-4, head_cx+34, head_cy+18], fill=WOLF_DARK)
    draw.ellipse([head_cx+8, head_cy-2, head_cx+32, head_cy+16], fill=WOLF_LIGHT)
    # Nose
    draw.ellipse([head_cx+22, head_cy-4, head_cx+34, head_cy+4], fill=WOLF_NOSE)
    draw.rectangle([head_cx+26, head_cy-2, head_cx+30, head_cy+6], fill=(60,30,25,200))
    # Eyes
    for ey_off in [-10, 6]:
        ey = head_cy - 5
        ex = head_cx + ey_off
        draw.ellipse([ex-6, ey-7, ex+6, ey+7], fill=(20,10,0,255))
        draw.ellipse([ex-4, ey-5, ex+4, ey+5], fill=WOLF_EYE)
        draw.ellipse([ex-1, ey-3, ex+2, ey], fill=WOLF_PUPIL)
    # Ears
    draw.polygon([(head_cx-20, head_cy-18),(head_cx-30, head_cy-46),(head_cx-8, head_cy-20)], fill=WOLF_DARK)
    draw.polygon([(head_cx-18, head_cy-20),(head_cx-26, head_cy-40),(head_cx-9, head_cy-21)], fill=fur)
    draw.polygon([(head_cx+5, head_cy-14),(head_cx, head_cy-42),(head_cx+16, head_cy-14)], fill=WOLF_DARK)
    draw.polygon([(head_cx+6, head_cy-16),(head_cx+1, head_cy-37),(head_cx+14, head_cy-16)], fill=fur)

    if lunge:
        # Show fangs
        draw.polygon([(head_cx+10, head_cy+12),(head_cx+14, head_cy+22),(head_cx+18, head_cy+12)], fill=WOLF_FANG)
        draw.polygon([(head_cx+20, head_cy+12),(head_cx+24, head_cy+20),(head_cx+28, head_cy+12)], fill=WOLF_FANG)
        # Tongue
        draw.ellipse([head_cx+13, head_cy+18, head_cx+27, head_cy+28], fill=WOLF_TONGUE)
    else:
        # Closed mouth
        draw.line([(head_cx+9, head_cy+14),(head_cx+32, head_cy+14)], fill=WOLF_DARK, width=2)


def wolf_idle(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_wolf(d, 110, bob=(-3 if frame_idx==0 else 3))
    return img

def wolf_attack(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_wolf(d, 110 + (20 if frame_idx==1 else 0), lunge=(frame_idx==1))
    return img

def wolf_hit(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_wolf(d, 110 - 18, hit=True)
    flash = Image.new("RGBA",(FRAME_W,FRAME_H),(0,0,0,0))
    fd=ImageDraw.Draw(flash)
    fd.ellipse([30,60,220,210], fill=(255,200,180,50))
    img = Image.alpha_composite(img, flash)
    return img

def wolf_dead(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_wolf(d, 110, dead=True)
    return img

def make_wolf():
    strip = new_strip()
    frames = [wolf_idle(0), wolf_idle(1), wolf_attack(0), wolf_attack(1),
              wolf_hit(0), wolf_hit(1), wolf_dead(0), wolf_dead(1)]
    for i,f in enumerate(frames): place_frame(strip, f, i)
    return strip


# ──────────────────────────────────────────────
# SPIDER
# ──────────────────────────────────────────────

SPIDER_BODY = (35, 25, 40, 255)
SPIDER_LEG  = (55, 40, 65, 255)
SPIDER_EYE  = (200, 30, 30, 255)
SPIDER_ABDOMEN = (55, 35, 65, 255)
SPIDER_SPOT = (180, 120, 20, 255)
SPIDER_FANG = (120, 200, 80, 255)  # venomous green tint

def draw_spider(draw, cx, cy, rear_high=False, hit=False, dead=False):
    body_col = (200,80,80,220) if hit else SPIDER_BODY
    ab_col   = (200,80,80,220) if hit else SPIDER_ABDOMEN

    # Shadow
    draw_shadow(draw, cx, cy+65, 72, 14)

    if dead:
        # Legs curled up, body flat
        draw.ellipse([cx-35, cy+30, cx+35, cy+60], fill=SPIDER_BODY)
        draw.ellipse([cx-32, cy+32, cx+32, cy+58], fill=ab_col)
        # Curled legs
        for i, angle_deg in enumerate(range(-150, 60, 45)):
            angle = math.radians(angle_deg)
            lx = cx + int(50 * math.cos(angle))
            ly = cy + 45 + int(20 * math.sin(angle))
            draw.line([(cx, cy+45), (lx, ly)], fill=SPIDER_LEG, width=4)
        return

    ab_y_off = -20 if rear_high else 0

    # Abdomen (rear larger bulb)
    ab_cx, ab_cy = cx - 35, cy + ab_y_off
    draw.ellipse([ab_cx-28, ab_cy-22, ab_cx+28, ab_cy+30], fill=outline_color(ab_col))
    draw.ellipse([ab_cx-24, ab_cy-18, ab_cx+24, ab_cy+26], fill=ab_col)
    # Abdomen marking
    draw.ellipse([ab_cx-10, ab_cy-8, ab_cx+10, ab_cy+12], fill=SPIDER_SPOT)
    draw.ellipse([ab_cx-6, ab_cy-4, ab_cx+6, ab_cy+8], fill=outline_color(SPIDER_SPOT))

    # Cephalothorax (front body)
    draw.ellipse([cx-22, cy-18, cx+22, cy+22], fill=outline_color(body_col))
    draw.ellipse([cx-18, cy-14, cx+18, cy+18], fill=body_col)
    # Highlight
    draw.ellipse([cx-14, cy-12, cx-4, cy-4], fill=shade(body_col, 1.8))

    # 8 Legs (4 per side)
    leg_angles_left  = [-140, -115, -85, -55]
    leg_angles_right = [  -40,  -15,  15,  45]
    for i, ang_deg in enumerate(leg_angles_left):
        ang = math.radians(ang_deg)
        knee_x = cx + int(45 * math.cos(ang))
        knee_y = cy + int(45 * math.sin(ang))
        tip_x  = knee_x + int(35 * math.cos(ang - 0.4))
        tip_y  = knee_y + int(35 * math.sin(ang + 0.3))
        draw.line([(cx, cy), (knee_x, knee_y)], fill=SPIDER_LEG, width=5)
        draw.line([(knee_x, knee_y), (tip_x, tip_y)], fill=SPIDER_LEG, width=4)
        # Joints
        draw.ellipse([knee_x-4, knee_y-4, knee_x+4, knee_y+4], fill=outline_color(SPIDER_LEG))
    for ang_deg in leg_angles_right:
        ang = math.radians(ang_deg)
        knee_x = cx + int(45 * math.cos(ang))
        knee_y = cy + int(45 * math.sin(ang))
        tip_x  = knee_x + int(35 * math.cos(ang + 0.4))
        tip_y  = knee_y + int(35 * math.sin(ang + 0.3))
        draw.line([(cx, cy), (knee_x, knee_y)], fill=SPIDER_LEG, width=5)
        draw.line([(knee_x, knee_y), (tip_x, tip_y)], fill=SPIDER_LEG, width=4)
        draw.ellipse([knee_x-4, knee_y-4, knee_x+4, knee_y+4], fill=outline_color(SPIDER_LEG))

    # Eyes (4 pairs = 8 eyes in rows)
    eye_positions = [(-10,-10),(-3,-12),(3,-10),(9,-8),
                     (-8,-4), (-2,-5),(4,-4),(9,-3)]
    for ex, ey in eye_positions:
        ex += cx; ey += cy
        draw.ellipse([ex-3, ey-3, ex+3, ey+3], fill=(30,15,35,255))
        draw.ellipse([ex-2, ey-2, ex+2, ey+2], fill=SPIDER_EYE)

    # Fangs / chelicerae
    draw.polygon([(cx-8, cy+14),(cx-12, cy+26),(cx-4, cy+22)], fill=outline_color(SPIDER_FANG))
    draw.polygon([(cx-7, cy+15),(cx-11, cy+24),(cx-4, cy+21)], fill=SPIDER_FANG)
    draw.polygon([(cx+4, cy+14),(cx+8, cy+26),(cx+12, cy+22)], fill=outline_color(SPIDER_FANG))
    draw.polygon([(cx+5, cy+15),(cx+9, cy+24),(cx+11, cy+21)], fill=SPIDER_FANG)
    # Venom drip
    draw.ellipse([cx-10, cy+25, cx-6, cy+30], fill=(80,220,60,200))
    draw.ellipse([cx+7, cy+25, cx+11, cy+30], fill=(80,220,60,200))


def spider_idle(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_spider(d, 118, 120 + (-4 if frame_idx==0 else 4))
    return img

def spider_attack(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    cx = 118 + (22 if frame_idx==1 else 0)
    draw_spider(d, cx, 118, rear_high=(frame_idx==1))
    if frame_idx==1:
        # Web strand
        for i in range(3):
            d.line([(cx+20, 118),(cx+80+i*12, 60+i*8)], fill=(220,220,200,100), width=1)
    return img

def spider_hit(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_spider(d, 100, 118, hit=True)
    flash = Image.new("RGBA",(FRAME_W,FRAME_H),(0,0,0,0))
    fd=ImageDraw.Draw(flash)
    fd.ellipse([40,60,210,200], fill=(255,200,200,50))
    img = Image.alpha_composite(img, flash)
    return img

def spider_dead(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_spider(d, 118, 150, dead=True)
    return img

def make_spider():
    strip = new_strip()
    frames = [spider_idle(0), spider_idle(1), spider_attack(0), spider_attack(1),
              spider_hit(0), spider_hit(1), spider_dead(0), spider_dead(1)]
    for i,f in enumerate(frames): place_frame(strip, f, i)
    return strip


# ──────────────────────────────────────────────
# SKELETON
# ──────────────────────────────────────────────

SKEL_BONE  = (220, 215, 195, 255)
SKEL_BONE_D= (140, 135, 115, 255)
SKEL_RUSTY = (140, 90, 40, 255)
SKEL_RUSTY_D=(80, 50, 20, 255)
SKEL_EYE   = (80, 180, 220, 255)  # eerie blue glow

def draw_skeleton(draw, cx, bob=0, swing=False, hit=False, dead=False):
    bone = (200, 100, 100, 220) if hit else SKEL_BONE
    dark = SKEL_BONE_D

    cy_feet = 210 + bob

    # Shadow
    draw_shadow(draw, cx, cy_feet+2, 40, 10)

    if dead:
        # Scattered bones pile
        pile_y = cy_feet - 15
        draw.ellipse([cx-25, pile_y-15, cx+25, pile_y+15], fill=dark)
        draw.ellipse([cx-20, pile_y-12, cx+20, pile_y+12], fill=bone)
        # Ribs sticking out
        for i in range(-3, 4, 2):
            draw.line([(cx+i*8, pile_y-10),(cx+i*8+10, pile_y-25)], fill=bone, width=4)
        # Skull
        draw.ellipse([cx-18, pile_y-40, cx+18, pile_y-12], fill=dark)
        draw.ellipse([cx-15, pile_y-38, cx+15, pile_y-14], fill=bone)
        draw.rectangle([cx-8, pile_y-20, cx-2, pile_y-14], fill=(20,20,20,255))
        draw.rectangle([cx+2, pile_y-20, cx+8, pile_y-14], fill=(20,20,20,255))
        draw.rectangle([cx-6, pile_y-13, cx+6, pile_y-10], fill=(20,20,20,255))
        return

    # Legs (fibula/tibia style)
    for lx in [cx-14, cx+6]:
        draw.rectangle([lx, cy_feet-50, lx+10, cy_feet], fill=dark)
        draw.rectangle([lx+2, cy_feet-48, lx+8, cy_feet-2], fill=bone)
        # Knee knob
        draw.ellipse([lx-2, cy_feet-52, lx+14, cy_feet-38], fill=dark)
        draw.ellipse([lx, cy_feet-50, lx+12, cy_feet-40], fill=bone)
        # Foot
        draw.ellipse([lx-4, cy_feet-6, lx+18, cy_feet+8], fill=dark)
        draw.ellipse([lx-2, cy_feet-4, lx+16, cy_feet+6], fill=bone)

    # Pelvis
    draw.ellipse([cx-22, cy_feet-58, cx+22, cy_feet-38], fill=dark)
    draw.ellipse([cx-18, cy_feet-55, cx+18, cy_feet-40], fill=bone)

    # Ribcage
    rib_y = cy_feet - 60
    for ry in range(rib_y-55, rib_y, 12):
        draw.arc([cx-22, ry, cx+22, ry+18], 180, 360, fill=dark, width=4)
        draw.arc([cx-20, ry+1, cx+20, ry+17], 180, 360, fill=bone, width=2)
    # Spine
    draw.rectangle([cx-3, rib_y-60, cx+3, cy_feet-55], fill=dark)
    for sy in range(rib_y-56, cy_feet-50, 8):
        draw.ellipse([cx-4, sy, cx+4, sy+6], fill=bone)

    # Arms
    arm_right_angle = -60 if swing else -120
    # Left arm
    draw.line([(cx-20, rib_y+5),(cx-45, rib_y+35),(cx-50, rib_y+62)], fill=dark, width=6)
    draw.line([(cx-20, rib_y+5),(cx-43, rib_y+33),(cx-48, rib_y+60)], fill=bone, width=4)
    # Elbow knob
    draw.ellipse([cx-47, rib_y+30, cx-37, rib_y+40], fill=bone)
    # Right arm (swings with attack)
    ang = math.radians(arm_right_angle)
    elbow_x = cx + 20 + int(30 * math.cos(ang))
    elbow_y = rib_y + 5 + int(30 * math.sin(ang))
    sword_x = elbow_x + int(30 * math.cos(ang - 0.3))
    sword_y = elbow_y + int(30 * math.sin(ang - 0.3))
    draw.line([(cx+20, rib_y+5),(elbow_x, elbow_y),(sword_x, sword_y)], fill=dark, width=6)
    draw.line([(cx+20, rib_y+5),(elbow_x, elbow_y),(sword_x, sword_y)], fill=bone, width=4)
    draw.ellipse([elbow_x-5, elbow_y-5, elbow_x+5, elbow_y+5], fill=bone)
    # Rusty sword
    blade_end_x = sword_x + int(55 * math.cos(ang - 0.5))
    blade_end_y = sword_y + int(55 * math.sin(ang - 0.5))
    # Guard
    gx1 = sword_x + int(8*math.cos(ang+1.5))
    gy1 = sword_y + int(8*math.sin(ang+1.5))
    gx2 = sword_x - int(8*math.cos(ang+1.5))
    gy2 = sword_y - int(8*math.sin(ang+1.5))
    draw.line([(gx1,gy1),(gx2,gy2)], fill=SKEL_RUSTY_D, width=8)
    draw.line([(gx1,gy1),(gx2,gy2)], fill=SKEL_RUSTY, width=5)
    # Blade
    draw.line([(sword_x, sword_y),(blade_end_x, blade_end_y)], fill=SKEL_RUSTY_D, width=7)
    draw.line([(sword_x, sword_y),(blade_end_x, blade_end_y)], fill=SKEL_RUSTY, width=4)

    # Skull
    skull_y = rib_y - 46
    draw.ellipse([cx-22, skull_y, cx+22, skull_y+44], fill=dark)
    draw.ellipse([cx-18, skull_y+3, cx+18, skull_y+41], fill=bone)
    # Highlight
    draw.ellipse([cx-14, skull_y+4, cx-2, skull_y+14], fill=highlight(bone))
    # Jaw
    draw.rectangle([cx-14, skull_y+32, cx+14, skull_y+45], fill=dark)
    draw.rectangle([cx-12, skull_y+33, cx+12, skull_y+44], fill=bone)
    # Teeth
    for tx in range(cx-10, cx+12, 6):
        draw.rectangle([tx, skull_y+38, tx+4, skull_y+46], fill=dark)
    # Eye sockets
    for ex in [cx-10, cx+4]:
        draw.ellipse([ex-7, skull_y+12, ex+7, skull_y+26], fill=(15,15,15,255))
        draw.ellipse([ex-5, skull_y+14, ex+5, skull_y+24], fill=SKEL_EYE)
        draw.ellipse([ex-2, skull_y+16, ex+2, skull_y+20], fill=(200,240,255,200))


def skeleton_idle(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_skeleton(d, 115, bob=(-3 if frame_idx==0 else 3))
    return img

def skeleton_attack(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    cx = 115 + (20 if frame_idx==1 else 0)
    draw_skeleton(d, cx, swing=(frame_idx==1))
    return img

def skeleton_hit(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_skeleton(d, 100, hit=True)
    flash = Image.new("RGBA",(FRAME_W,FRAME_H),(0,0,0,0))
    fd=ImageDraw.Draw(flash)
    fd.ellipse([40,40,210,230], fill=(255,200,200,50))
    img = Image.alpha_composite(img, flash)
    return img

def skeleton_dead(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_skeleton(d, 115, dead=True)
    return img

def make_skeleton():
    strip = new_strip()
    frames = [skeleton_idle(0), skeleton_idle(1), skeleton_attack(0), skeleton_attack(1),
              skeleton_hit(0), skeleton_hit(1), skeleton_dead(0), skeleton_dead(1)]
    for i,f in enumerate(frames): place_frame(strip, f, i)
    return strip


# ──────────────────────────────────────────────
# GHOST
# ──────────────────────────────────────────────

GHOST_BODY  = (200, 225, 250, 180)
GHOST_GLOW  = (150, 200, 255, 120)
GHOST_DARK  = (80,  110, 160, 200)
GHOST_EYE   = (20,  20,  50,  220)
GHOST_AURA  = (180, 210, 255, 60)

def draw_ghost(draw, cx, cy, sway=0, attack=False, hit=False, dead=False):
    body     = (220, 120, 120, 195) if hit else GHOST_BODY
    body_d   = shade(body, 0.65)
    s = sway  # shorthand

    # Outer ethereal glow halos — concentric soft ellipses
    for r_off, alpha in [(30, 22), (20, 35), (10, 50)]:
        draw.ellipse([cx-58-r_off+s, cy-80-r_off, cx+58+r_off+s, cy+62+r_off],
                     fill=(180, 215, 255, alpha))

    if dead:
        # Three dissolving wisp blobs, clearly visible
        wisp_col = (170, 205, 255, 170)
        wisp_col2 = (200, 225, 255, 120)
        for i, (wx_off, wy_off, wr, wh) in enumerate([
            (-30, 30,  22, 38),
            (  0, 15,  18, 32),
            ( 28, 38,  14, 24),
        ]):
            wx = cx + wx_off + s
            wy = cy + wy_off
            draw.ellipse([wx-wr, wy-wh, wx+wr, wy+wh], fill=wisp_col)
            draw.ellipse([wx-wr+4, wy-wh+6, wx+wr-4, wy+wh-6], fill=wisp_col2)
        # Faint face remnants
        for ex in [cx-12+s, cx+8+s]:
            draw.ellipse([ex-5, cy+10, ex+5, cy+20], fill=(120, 160, 220, 110))
        return

    # ── Body: proper ghost sheet silhouette ──────────────────────────
    # Built as a polygon: dome top, tapered sides, wavy hem at bottom.
    # All coords relative to (cx+s, cy).

    w_top  = 52   # half-width at dome equator
    w_mid  = 48   # half-width at body mid
    w_bot  = 50   # half-width at hem start
    top_y  = cy - 68   # top of dome
    dome_y = cy - 30   # dome equator
    mid_y  = cy + 10   # body mid
    hem_y  = cy + 42   # hem start (top of wave zone)
    wave_y = cy + 58   # wave amplitude centre

    # Build hem wave across bottom (left to right)
    hem_pts_bottom = []
    steps = 14
    for i in range(steps + 1):
        t = i / steps
        wx = (cx + s - w_bot) + int(2 * w_bot * t)
        wy = wave_y + int(14 * math.sin(math.pi * 2.5 * t))
        hem_pts_bottom.append((wx, wy))

    # Full outline polygon (clockwise):
    # left side going up → dome arc (approximated) → right side going down → hem wave
    left_side  = [(cx + s - w_bot, hem_y), (cx + s - w_mid, mid_y), (cx + s - w_top, dome_y)]
    dome_arc   = []
    for a in range(180, -1, -10):   # semicircle top (left to right)
        rad = math.radians(a)
        px = cx + s + int(w_top * math.cos(rad))
        py = top_y + int((dome_y - top_y) * (1 - abs(math.sin(rad))))
        dome_arc.append((px, py))
    right_side = [(cx + s + w_top, dome_y), (cx + s + w_mid, mid_y), (cx + s + w_bot, hem_y)]

    full_poly = left_side + dome_arc + right_side + list(reversed(hem_pts_bottom))

    # Draw dark outline pass first
    outline_poly = [(x + (2 if x > cx+s else -2), y + 2) for x,y in full_poly]
    draw.polygon(outline_poly, fill=body_d)
    # Main body fill
    draw.polygon(full_poly, fill=body)

    # Interior shading — darker lower half
    lower_shade = [
        (cx + s - w_mid, mid_y),
        (cx + s + w_mid, mid_y),
        (cx + s + w_bot, hem_y),
    ] + list(reversed(hem_pts_bottom)) + [
        (cx + s - w_bot, hem_y),
    ]
    draw.polygon(lower_shade, fill=shade(body, 0.78))

    # Highlight streak on upper-left dome
    hl_pts = [
        (cx + s - 28, top_y + 8),
        (cx + s - 38, dome_y - 12),
        (cx + s - 18, dome_y - 20),
        (cx + s - 10, top_y + 10),
    ]
    draw.polygon(hl_pts, fill=(230, 240, 255, 90))

    # ── Arms (wispy elongated blobs) ──────────────────────────────────
    arm_col  = shade(body, 0.88)
    arm_col2 = shade(body, 0.70)
    if attack:
        # Both arms stretch right toward target
        for ax, ay, aw, ah in [
            (cx + s + 50,  cy,      42, 18),
            (cx + s + 80,  cy + 5,  30, 13),
            (cx + s + 100, cy + 8,  22, 10),
        ]:
            draw.ellipse([ax-aw, ay-ah, ax+aw, ay+ah], fill=arm_col)
        # Glowing fingertip
        draw.ellipse([cx+s+116, cy+2, cx+s+130, cy+16], fill=(200, 230, 255, 200))
        draw.ellipse([cx+s+120, cy+5, cx+s+126, cy+13], fill=(240, 248, 255, 240))
    else:
        # Arms drape at each side
        draw.ellipse([cx+s-95, cy-2,  cx+s-52, cy+22], fill=arm_col)
        draw.ellipse([cx+s-110, cy+4, cx+s-80, cy+18], fill=arm_col2)
        draw.ellipse([cx+s+52,  cy-2,  cx+s+95, cy+22], fill=arm_col)
        draw.ellipse([cx+s+80,  cy+4,  cx+s+110, cy+18], fill=arm_col2)

    # ── Face ──────────────────────────────────────────────────────────
    face_y = cy - 22
    # Eye sockets — hollow dark ovals with blue glow inside
    for ex in [cx + s - 14, cx + s + 8]:
        draw.ellipse([ex-11, face_y-12, ex+11, face_y+10], fill=(8, 12, 28, 230))
        draw.ellipse([ex-8,  face_y-9,  ex+8,  face_y+7],  fill=GHOST_EYE)
        draw.ellipse([ex-5,  face_y-6,  ex+5,  face_y+4],  fill=(70, 95, 175, 200))
        draw.ellipse([ex-2,  face_y-4,  ex+2,  face_y],    fill=(210, 228, 255, 230))

    # Mouth — wavy pixel row
    mouth_y = cy + 2
    for mx in range(-13, 14, 3):
        my = mouth_y + int(6 * math.sin(math.radians(mx * 28)))
        draw.rectangle([cx + s + mx - 1, my, cx + s + mx + 1, my + 3], fill=GHOST_DARK)


def ghost_idle(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    sway = -6 if frame_idx==0 else 6
    cy_bob = -4 if frame_idx==0 else 4
    draw_ghost(d, 128, 115 + cy_bob, sway=sway)
    return img

def ghost_attack(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    cx_off = 18 if frame_idx==1 else 0
    draw_ghost(d, 128+cx_off, 115, attack=(frame_idx==1))
    if frame_idx==1:
        # Ethereal blast
        for i in range(4):
            d.ellipse([190+i*8, 100+i*5, 220+i*8, 125+i*5], fill=(150,200,255, 80-i*15))
    return img

def ghost_hit(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_ghost(d, 115, 118, hit=True)
    flash = Image.new("RGBA",(FRAME_W,FRAME_H),(0,0,0,0))
    fd=ImageDraw.Draw(flash)
    fd.ellipse([50,40,220,220], fill=(255,230,200,70))
    img = Image.alpha_composite(img, flash)
    return img

def ghost_dead(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_ghost(d, 128, 130, dead=True)
    return img

def make_ghost():
    strip = new_strip()
    frames = [ghost_idle(0), ghost_idle(1), ghost_attack(0), ghost_attack(1),
              ghost_hit(0), ghost_hit(1), ghost_dead(0), ghost_dead(1)]
    for i,f in enumerate(frames): place_frame(strip, f, i)
    return strip


# ──────────────────────────────────────────────
# IMP
# ──────────────────────────────────────────────

IMP_SKIN   = (180, 40, 30, 255)
IMP_SKIN_D = (110, 20, 15, 255)
IMP_WING   = (140, 30, 25, 200)
IMP_WING_V = (90,  15, 12, 200)
IMP_HORN   = (220, 200, 60, 255)
IMP_EYE    = (240, 220, 0, 255)
IMP_PUPIL  = (30, 0, 0, 255)
IMP_FIRE   = (255, 140, 0, 255)
IMP_FIRE2  = (255, 60, 0, 255)

def draw_imp(draw, cx, cy, wing_anim=False, cast=False, hit=False, dead=False):
    skin = (220, 120, 80, 220) if hit else IMP_SKIN

    # Shadow
    draw_shadow(draw, cx, cy+72, 30, 8)

    if dead:
        # Flattened
        draw.ellipse([cx-35, cy+45, cx+35, cy+65], fill=IMP_SKIN_D)
        draw.ellipse([cx-30, cy+47, cx+30, cy+63], fill=skin)
        for ex in [cx-8, cx+4]:
            draw.line([(ex-4, cy+50),(ex+4, cy+58)], fill=IMP_SKIN_D, width=2)
            draw.line([(ex+4, cy+50),(ex-4, cy+58)], fill=IMP_SKIN_D, width=2)
        # Horns still visible
        draw.polygon([(cx-12, cy+50),(cx-18, cy+36),(cx-6, cy+50)], fill=IMP_HORN)
        draw.polygon([(cx+6, cy+50),(cx+12, cy+36),(cx+18, cy+50)], fill=IMP_HORN)
        return

    wing_spread = 50 if wing_anim else 40

    # Wings
    for sign, wx_base in [(-1, cx-15), (1, cx+15)]:
        tip_x = cx + sign * (wing_spread + 45)
        tip_y = cy - 30
        wing_pts = [
            (wx_base, cy-10),
            (tip_x, tip_y),
            (tip_x + sign*5, cy+20),
            (wx_base, cy+20)
        ]
        draw.polygon(wing_pts, fill=IMP_WING_V)
        inner_pts = [
            (wx_base, cy-8),
            (tip_x - sign*4, tip_y+4),
            (tip_x + sign*2, cy+16),
            (wx_base, cy+16)
        ]
        draw.polygon(inner_pts, fill=IMP_WING)
        # Wing ribs
        draw.line([(wx_base, cy),(tip_x, tip_y)], fill=IMP_WING_V, width=2)
        draw.line([(wx_base, cy+10),(tip_x+sign*4, cy+15)], fill=IMP_WING_V, width=1)

    # Body
    bw, bh = 38, 48
    bx, by = cx-bw//2, cy-bh//2
    draw.rectangle([bx-3, by-3, bx+bw+3, by+bh+3], fill=IMP_SKIN_D)
    draw.rectangle([bx, by, bx+bw, by+bh], fill=skin)
    # Belly lighter spot
    draw.ellipse([bx+6, by+bh//3, bx+bw-6, by+bh-6], fill=shade(skin, 1.3))

    # Legs/tail
    for lx in [cx-10, cx+4]:
        draw.rectangle([lx, cy+bh//2-5, lx+10, cy+bh//2+32], fill=IMP_SKIN_D)
        draw.rectangle([lx+2, cy+bh//2-3, lx+8, cy+bh//2+30], fill=skin)
        draw.ellipse([lx-3, cy+bh//2+26, lx+14, cy+bh//2+38], fill=IMP_SKIN_D)
    # Tail
    draw.arc([cx+8, cy+20, cx+48, cy+55], 180, 50, fill=IMP_SKIN_D, width=5)
    draw.arc([cx+9, cy+21, cx+47, cy+54], 180, 50, fill=skin, width=3)
    draw.ellipse([cx+42, cy+28, cx+54, cy+40], fill=IMP_SKIN_D)
    draw.ellipse([cx+44, cy+30, cx+52, cy+38], fill=skin)

    # Head
    head_r = 24
    hx, hy = cx, by - 6
    draw.ellipse([hx-head_r-3, hy-head_r-3, hx+head_r+3, hy+head_r+3], fill=IMP_SKIN_D)
    draw.ellipse([hx-head_r, hy-head_r, hx+head_r, hy+head_r], fill=skin)
    draw.ellipse([hx-head_r+4, hy-head_r+4, hx, hy-4], fill=highlight(skin))

    # Horns
    draw.polygon([(hx-12, hy-head_r+4),(hx-18, hy-head_r-22),(hx-5, hy-head_r+2)], fill=shade(IMP_HORN,0.7))
    draw.polygon([(hx-11, hy-head_r+4),(hx-16, hy-head_r-20),(hx-6, hy-head_r+3)], fill=IMP_HORN)
    draw.polygon([(hx+5, hy-head_r+4),(hx+18, hy-head_r-22),(hx+11, hy-head_r+2)], fill=shade(IMP_HORN,0.7))
    draw.polygon([(hx+6, hy-head_r+4),(hx+16, hy-head_r-20),(hx+10, hy-head_r+3)], fill=IMP_HORN)

    # Eyes
    for ex in [hx-9, hx+3]:
        draw.ellipse([ex-7, hy-8, ex+7, hy+5], fill=(20,5,0,255))
        draw.ellipse([ex-5, hy-6, ex+5, hy+3], fill=IMP_EYE)
        draw.ellipse([ex-2, hy-4, ex+2, hy+1], fill=IMP_PUPIL)
        draw.rectangle([ex-1, hy-5, ex+1, hy-2], fill=(255,255,200,200))

    # Mouth (grin)
    draw.arc([hx-10, hy+5, hx+10, hy+16], 15, 165, fill=IMP_SKIN_D, width=2)
    # Tiny fangs
    draw.polygon([(hx-7, hy+7),(hx-5, hy+13),(hx-3, hy+7)], fill=(240,230,200,200))
    draw.polygon([(hx+3, hy+7),(hx+5, hy+13),(hx+7, hy+7)], fill=(240,230,200,200))

    if cast:
        # Fireball in hand
        fx, fy = cx+55, cy-15
        for r in [22, 16, 10]:
            alpha = 200 - r*5
            col = IMP_FIRE if r > 12 else IMP_FIRE2
            draw.ellipse([fx-r, fy-r, fx+r, fy+r], fill=(*col[:3], alpha))
        # Fire glow
        draw.ellipse([fx-8, fy-8, fx+8, fy+8], fill=(255,240,100,240))


def imp_idle(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    bob = -4 if frame_idx==0 else 4
    draw_imp(d, 128, 115+bob, wing_anim=(frame_idx==0))
    return img

def imp_attack(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    cx = 128 + (12 if frame_idx==1 else 0)
    draw_imp(d, cx, 112, wing_anim=True, cast=(frame_idx==1))
    return img

def imp_hit(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_imp(d, 112, 118, hit=True)
    flash = Image.new("RGBA",(FRAME_W,FRAME_H),(0,0,0,0))
    fd=ImageDraw.Draw(flash)
    fd.ellipse([50,50,210,210], fill=(255,200,180,55))
    img = Image.alpha_composite(img, flash)
    return img

def imp_dead(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_imp(d, 128, 115, dead=True)
    return img

def make_imp():
    strip = new_strip()
    frames = [imp_idle(0), imp_idle(1), imp_attack(0), imp_attack(1),
              imp_hit(0), imp_hit(1), imp_dead(0), imp_dead(1)]
    for i,f in enumerate(frames): place_frame(strip, f, i)
    return strip


# ──────────────────────────────────────────────
# TROLL
# ──────────────────────────────────────────────

TROLL_SKIN   = (80, 110, 55, 255)
TROLL_SKIN_D = (45, 65, 28, 255)
TROLL_CLOTH  = (90, 60, 30, 255)
TROLL_CLOTH_D= (50, 32, 12, 255)
TROLL_EYE    = (255, 60, 0, 255)
TROLL_PUPIL  = (30, 10, 0, 255)
TROLL_FANG   = (230, 220, 180, 255)
TROLL_NAIL   = (100, 80, 35, 255)
TROLL_ROCK   = (130, 115, 95, 255)
TROLL_ROCK_D = (70, 60, 45, 255)

def draw_troll(draw, cx, bob=0, swing=False, hit=False, dead=False):
    skin = (200, 120, 80, 220) if hit else TROLL_SKIN

    cy_feet = 215 + bob

    # Shadow
    draw_shadow(draw, cx, cy_feet+4, 65, 16)

    if dead:
        # Collapsed heap
        hy = cy_feet - 30
        draw.ellipse([cx-70, hy-20, cx+70, hy+25], fill=TROLL_SKIN_D)
        draw.ellipse([cx-65, hy-17, cx+65, hy+22], fill=skin)
        # Head
        draw.ellipse([cx+30, hy-40, cx+75, hy-5], fill=TROLL_SKIN_D)
        draw.ellipse([cx+33, hy-37, cx+72, hy-8], fill=skin)
        for ex in [cx+43, cx+58]:
            draw.line([(ex-5, hy-25),(ex+5, hy-17)], fill=TROLL_SKIN_D, width=2)
            draw.line([(ex+5, hy-25),(ex-5, hy-17)], fill=TROLL_SKIN_D, width=2)
        return

    # Legs — thick and powerful
    for lx in [cx-26, cx+8]:
        draw.rectangle([lx, cy_feet-72, lx+26, cy_feet], fill=TROLL_SKIN_D)
        draw.rectangle([lx+2, cy_feet-70, lx+24, cy_feet-2], fill=skin)
        # Cloth wrappings
        draw.rectangle([lx, cy_feet-72, lx+26, cy_feet-58], fill=TROLL_CLOTH)
        # Foot
        draw.ellipse([lx-6, cy_feet-10, lx+36, cy_feet+10], fill=TROLL_SKIN_D)
        draw.ellipse([lx-4, cy_feet-8, lx+34, cy_feet+8], fill=skin)
        # Toenails
        for ni in range(3):
            nx = lx + 3 + ni*9
            draw.rectangle([nx, cy_feet+2, nx+7, cy_feet+10], fill=TROLL_NAIL)

    # Loincloth
    draw.polygon([
        (cx-32, cy_feet-75), (cx+34, cy_feet-75),
        (cx+28, cy_feet-45), (cx, cy_feet-38), (cx-28, cy_feet-45)
    ], fill=TROLL_CLOTH_D)
    draw.polygon([
        (cx-28, cy_feet-73), (cx+30, cy_feet-73),
        (cx+24, cy_feet-47), (cx, cy_feet-40), (cx-24, cy_feet-47)
    ], fill=TROLL_CLOTH)

    # Body — massive barrel chest
    bw, bh = 85, 80
    bx, by = cx - bw//2, cy_feet - 72 - bh
    draw.rectangle([bx-4, by-4, bx+bw+4, by+bh+4], fill=TROLL_SKIN_D)
    draw.rectangle([bx, by, bx+bw, by+bh], fill=skin)
    # Chest hair/texture
    for i in range(4):
        hx = bx + 15 + i*15
        draw.arc([hx, by+10, hx+12, by+22], 0, 180, fill=TROLL_SKIN_D, width=2)

    # Arms — big and imposing
    arm_y = by + 15
    # Left arm hangs
    draw.rectangle([bx-28, arm_y, bx+6, arm_y+68], fill=TROLL_SKIN_D)
    draw.rectangle([bx-26, arm_y+2, bx+4, arm_y+66], fill=skin)
    # Left hand/fist
    draw.ellipse([bx-32, arm_y+62, bx+8, arm_y+82], fill=TROLL_SKIN_D)
    draw.ellipse([bx-30, arm_y+64, bx+6, arm_y+80], fill=skin)
    for ni in range(4):
        nx = bx - 28 + ni*9
        draw.rectangle([nx, arm_y+79, nx+7, arm_y+86], fill=TROLL_NAIL)

    # Right arm (possibly swinging)
    if swing:
        # Raised holding a rock
        draw.rectangle([bx+bw-6, by-30, bx+bw+30, by+35], fill=TROLL_SKIN_D)
        draw.rectangle([bx+bw-4, by-28, bx+bw+28, by+33], fill=skin)
        # Rock
        rock_x, rock_y = bx+bw+14, by-48
        draw.polygon([
            (rock_x, rock_y-22), (rock_x+22, rock_y-8),
            (rock_x+18, rock_y+14), (rock_x-10, rock_y+16),
            (rock_x-18, rock_y+2)
        ], fill=TROLL_ROCK_D)
        draw.polygon([
            (rock_x+2, rock_y-20), (rock_x+20, rock_y-6),
            (rock_x+16, rock_y+12), (rock_x-8, rock_y+14),
            (rock_x-16, rock_y+4)
        ], fill=TROLL_ROCK)
        draw.ellipse([rock_x-6, rock_y-12, rock_x+2, rock_y-4], fill=highlight(TROLL_ROCK))
    else:
        draw.rectangle([bx+bw-6, arm_y, bx+bw+28, arm_y+68], fill=TROLL_SKIN_D)
        draw.rectangle([bx+bw-4, arm_y+2, bx+bw+26, arm_y+66], fill=skin)
        draw.ellipse([bx+bw-10, arm_y+62, bx+bw+32, arm_y+82], fill=TROLL_SKIN_D)
        draw.ellipse([bx+bw-8, arm_y+64, bx+bw+30, arm_y+80], fill=skin)
        for ni in range(4):
            nx = bx+bw-6+ni*9
            draw.rectangle([nx, arm_y+79, nx+7, arm_y+86], fill=TROLL_NAIL)

    # Head — big and ugly
    head_r = 38
    hx, hy = cx, by - head_r + 8
    draw.ellipse([hx-head_r-4, hy-head_r-4, hx+head_r+4, hy+head_r+4], fill=TROLL_SKIN_D)
    draw.ellipse([hx-head_r, hy-head_r, hx+head_r, hy+head_r], fill=skin)
    draw.ellipse([hx-head_r+5, hy-head_r+5, hx-4, hy-4], fill=highlight(skin))

    # Brow ridge
    draw.ellipse([hx-head_r+2, hy-head_r//2-8, hx+head_r-2, hy-head_r//2+10], fill=TROLL_SKIN_D)

    # Ears (big, floppy)
    draw.ellipse([hx-head_r-14, hy-10, hx-head_r+12, hy+20], fill=TROLL_SKIN_D)
    draw.ellipse([hx-head_r-11, hy-7, hx-head_r+10, hy+17], fill=skin)
    draw.ellipse([hx+head_r-12, hy-10, hx+head_r+14, hy+20], fill=TROLL_SKIN_D)
    draw.ellipse([hx+head_r-10, hy-7, hx+head_r+11, hy+17], fill=skin)

    # Eyes (sunken)
    for ex in [hx-14, hx+6]:
        draw.ellipse([ex-9, hy-14, ex+9, hy+2], fill=(20,10,5,255))
        draw.ellipse([ex-7, hy-12, ex+7, hy], fill=TROLL_EYE)
        draw.ellipse([ex-3, hy-10, ex+3, hy-4], fill=TROLL_PUPIL)
        draw.rectangle([ex-1, hy-11, ex+1, hy-7], fill=(255,200,180,180))

    # Nose — big bulbous
    draw.ellipse([hx-10, hy-4, hx+10, hy+12], fill=TROLL_SKIN_D)
    draw.ellipse([hx-8, hy-2, hx+8, hy+10], fill=shade(skin, 0.85))
    draw.rectangle([hx-7, hy+2, hx-3, hy+8], fill=(30,15,8,150))
    draw.rectangle([hx+3, hy+2, hx+7, hy+8], fill=(30,15,8,150))

    # Mouth (tusks/fangs)
    draw.arc([hx-16, hy+8, hx+16, hy+22], 5, 175, fill=TROLL_SKIN_D, width=3)
    draw.polygon([(hx-10, hy+10),(hx-7, hy+22),(hx-3, hy+10)], fill=TROLL_FANG)
    draw.polygon([(hx+3, hy+10),(hx+7, hy+22),(hx+10, hy+10)], fill=TROLL_FANG)
    # Lower tusks curling up
    draw.polygon([(hx-12, hy+20),(hx-16, hy+32),(hx-8, hy+22)], fill=TROLL_FANG)
    draw.polygon([(hx+8, hy+20),(hx+12, hy+32),(hx+16, hy+22)], fill=TROLL_FANG)

    # Hair (tufts)
    for hxi in range(-3, 4, 2):
        hxp = hx + hxi*7
        draw.polygon([(hxp, hy-head_r),(hxp-4, hy-head_r-15),(hxp+4, hy-head_r-15)], fill=TROLL_SKIN_D)


def troll_idle(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_troll(d, 110, bob=(-4 if frame_idx==0 else 4))
    return img

def troll_attack(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    cx = 110 + (22 if frame_idx==1 else 0)
    draw_troll(d, cx, swing=(frame_idx==1))
    return img

def troll_hit(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_troll(d, 95, hit=True)
    flash = Image.new("RGBA",(FRAME_W,FRAME_H),(0,0,0,0))
    fd=ImageDraw.Draw(flash)
    fd.ellipse([20,20,230,240], fill=(255,200,180,55))
    img = Image.alpha_composite(img, flash)
    return img

def troll_dead(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_troll(d, 110, dead=True)
    return img

def make_troll():
    strip = new_strip()
    frames = [troll_idle(0), troll_idle(1), troll_attack(0), troll_attack(1),
              troll_hit(0), troll_hit(1), troll_dead(0), troll_dead(1)]
    for i,f in enumerate(frames): place_frame(strip, f, i)
    return strip


# ──────────────────────────────────────────────
# SNAKE
# ──────────────────────────────────────────────

SNAKE_SCALE  = (55, 120, 45, 255)
SNAKE_SCALE_D= (28, 68, 20, 255)
SNAKE_BELLY  = (200, 190, 120, 255)
SNAKE_EYE    = (255, 200, 0, 255)
SNAKE_PUPIL  = (20, 0, 0, 255)
SNAKE_TONGUE = (220, 30, 50, 255)
SNAKE_PATTERN= (40, 90, 30, 255)

def draw_snake_body_coil(draw, cx, cy, coil_open=False, hit=False, dead=False):
    scale = (200, 100, 80, 220) if hit else SNAKE_SCALE

    # Shadow
    draw_shadow(draw, cx, cy+65, 70, 14)

    if dead:
        # Uncoiled, lying flat
        pts = []
        for i in range(20):
            t = i / 19.0
            x = cx - 80 + int(160 * t)
            y = cy + 50 + int(12 * math.sin(t * math.pi * 3))
            pts.append((x, y))
        for i in range(len(pts)-1):
            x0,y0 = pts[i]
            x1,y1 = pts[i+1]
            draw.line([(x0,y0),(x1,y1)], fill=SNAKE_SCALE_D, width=18)
        for i in range(len(pts)-1):
            x0,y0 = pts[i]
            x1,y1 = pts[i+1]
            draw.line([(x0,y0),(x1,y1)], fill=scale, width=14)
        # Dead head to side
        draw.ellipse([cx+70, cy+40, cx+105, cy+65], fill=SNAKE_SCALE_D)
        draw.ellipse([cx+73, cy+43, cx+102, cy+62], fill=scale)
        draw.ellipse([cx+90, cy+43, cx+96, cy+50], fill=SNAKE_EYE)
        draw.ellipse([cx+92, cy+45, cx+95, cy+49], fill=SNAKE_PUPIL)
        return

    # Coiled body
    coil_r = 62
    num_pts = 40
    for loop in range(2):
        r = coil_r - loop * 18
        pts = []
        for i in range(num_pts+1):
            angle = math.radians(360 * i / num_pts - 90)
            px = cx + int(r * math.cos(angle))
            py = cy + 50 + int(r * 0.45 * math.sin(angle))
            pts.append((px, py))
        # Draw outline
        for i in range(len(pts)-1):
            draw.line([(pts[i][0], pts[i][1]),(pts[i+1][0], pts[i+1][1])],
                      fill=SNAKE_SCALE_D, width=22-loop*4)
        # Draw fill
        for i in range(len(pts)-1):
            draw.line([(pts[i][0], pts[i][1]),(pts[i+1][0], pts[i+1][1])],
                      fill=scale, width=18-loop*4)
        # Scale pattern (diamond shapes)
        for i in range(0, num_pts, 3):
            px, py = pts[i]
            draw.ellipse([px-5, py-3, px+5, py+3], fill=SNAKE_PATTERN)

    # Belly coil (lighter)
    for i in range(num_pts//2, num_pts+1, 2):
        px, py = pts[i]
        draw.ellipse([px-7, py-4, px+7, py+4], fill=SNAKE_BELLY)

    # Head — reared up or lunging
    if coil_open:
        head_cx, head_cy = cx + 15, cy - 20
        neck_end = (cx + 5, cy + 10)
    else:
        head_cx, head_cy = cx, cy - 15
        neck_end = (cx - 10, cy + 15)

    # Neck
    draw.line([neck_end, (head_cx, head_cy)], fill=SNAKE_SCALE_D, width=22)
    draw.line([neck_end, (head_cx, head_cy)], fill=scale, width=18)

    # Head
    draw.ellipse([head_cx-20, head_cy-16, head_cx+28, head_cy+16], fill=SNAKE_SCALE_D)
    draw.ellipse([head_cx-17, head_cy-13, head_cx+25, head_cy+13], fill=scale)
    # Top highlight
    draw.ellipse([head_cx-12, head_cy-10, head_cx+2, head_cy-2], fill=highlight(scale))

    # Eye
    draw.ellipse([head_cx+2, head_cy-9, head_cx+14, head_cy+3], fill=(20,10,0,255))
    draw.ellipse([head_cx+4, head_cy-7, head_cx+12, head_cy+1], fill=SNAKE_EYE)
    draw.ellipse([head_cx+6, head_cy-5, head_cx+10, head_cy-1], fill=SNAKE_PUPIL)
    draw.rectangle([head_cx+7, head_cy-5, head_cx+9, head_cy-2], fill=(255,255,200,200))

    # Tongue (forked)
    tx, ty = head_cx + 25, head_cy + 2
    draw.line([(head_cx+18, head_cy+2),(tx, ty)], fill=SNAKE_TONGUE, width=3)
    draw.line([(tx, ty),(tx+10, ty-6)], fill=SNAKE_TONGUE, width=2)
    draw.line([(tx, ty),(tx+10, ty+6)], fill=SNAKE_TONGUE, width=2)

    # Hooded flare when attacking
    if coil_open:
        draw.ellipse([head_cx-28, head_cy-26, head_cx+36, head_cy+26], fill=(80,140,60,80))
        draw.arc([head_cx-26, head_cy-24, head_cx+34, head_cy+24], 200, 340, fill=SNAKE_SCALE_D, width=4)


def snake_idle(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    bob = -4 if frame_idx==0 else 4
    draw_snake_body_coil(d, 118, 90+bob)
    return img

def snake_attack(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_snake_body_coil(d, 118, 90, coil_open=(frame_idx==1))
    if frame_idx==1:
        for i in range(3):
            d.line([(160+i*15, 70+i*5),(200+i*15, 80+i*5)], fill=(100,180,80,100), width=2)
    return img

def snake_hit(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_snake_body_coil(d, 100, 90, hit=True)
    flash = Image.new("RGBA",(FRAME_W,FRAME_H),(0,0,0,0))
    fd=ImageDraw.Draw(flash)
    fd.ellipse([30,50,220,210], fill=(255,200,180,50))
    img = Image.alpha_composite(img, flash)
    return img

def snake_dead(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_snake_body_coil(d, 118, 80, dead=True)
    return img

def make_snake():
    strip = new_strip()
    frames = [snake_idle(0), snake_idle(1), snake_attack(0), snake_attack(1),
              snake_hit(0), snake_hit(1), snake_dead(0), snake_dead(1)]
    for i,f in enumerate(frames): place_frame(strip, f, i)
    return strip


# ──────────────────────────────────────────────
# GENERATE ALL SPRITES
# ──────────────────────────────────────────────

MONSTERS = [
    ("slime",    make_slime),
    ("bat",      make_bat),
    ("goblin",   make_goblin),
    ("wolf",     make_wolf),
    ("spider",   make_spider),
    ("skeleton", make_skeleton),
    ("ghost",    make_ghost),
    ("imp",      make_imp),
    ("troll",    make_troll),
    ("snake",    make_snake),
]

if __name__ == "__main__":
    import sys
    targets = sys.argv[1:] if len(sys.argv) > 1 else [m[0] for m in MONSTERS]
    monster_map = {m[0]: m[1] for m in MONSTERS}

    os.makedirs(OUT_DIR, exist_ok=True)

    for monster_id in targets:
        if monster_id not in monster_map:
            print(f"Unknown monster: {monster_id}")
            continue
        out_path = os.path.join(OUT_DIR, f"{monster_id}.png")
        print(f"Generating {monster_id}...", end=" ", flush=True)
        strip = monster_map[monster_id]()
        strip.save(out_path, "PNG")
        print(f"saved to {out_path} [{strip.size[0]}x{strip.size[1]}]")

    print("\nAll monster sprites generated successfully.")
