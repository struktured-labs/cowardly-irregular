#!/usr/bin/env python3
"""
Generate SNES-style pixel art monster sprite sheets for Cowardly Irregular (extended set).
Each monster: 2048x256 strip, 8 frames of 256x256.
Frame layout: 0-1 idle, 2-3 attack, 4-5 hit, 6-7 dead.

New monsters:
  Medieval: cave_rat, rat_guard, mushroom, cave_troll, shadow_knight
  Dragons:  fire_dragon, ice_dragon, lightning_dragon, shadow_dragon
"""

from PIL import Image, ImageDraw
import os
import math

FRAME_W = 256
FRAME_H = 256
TOTAL_FRAMES = 8
STRIP_W = FRAME_W * TOTAL_FRAMES
STRIP_H = FRAME_H
OUT_DIR = "/home/struktured/projects/cowardly-irregular-sprite-gen/assets/sprites/monsters"

# ──────────────────────────────────────────────
# Drawing helpers (mirrored from gen_monster_sprites.py)
# ──────────────────────────────────────────────

def new_frame():
    return Image.new("RGBA", (FRAME_W, FRAME_H), (0, 0, 0, 0))

def new_strip():
    return Image.new("RGBA", (STRIP_W, STRIP_H), (0, 0, 0, 0))

def place_frame(strip, frame, idx):
    strip.paste(frame, (idx * FRAME_W, 0), frame)

def shade(color, factor):
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

def draw_shadow(draw, cx, cy, rx, ry, alpha=80):
    draw.ellipse([cx-rx, cy-ry//3, cx+rx, cy+ry//3], fill=(0, 0, 0, alpha))


# ──────────────────────────────────────────────
# CAVE RAT
# ──────────────────────────────────────────────

RAT_FUR    = (110, 90, 70, 255)
RAT_FUR_D  = (60,  45, 32, 255)
RAT_FUR_L  = (170, 150, 120, 255)
RAT_EYE    = (220, 30, 30, 255)
RAT_NOSE   = (200, 100, 100, 255)
RAT_INNER  = (190, 130, 130, 255)
RAT_TOOTH  = (240, 235, 200, 255)
RAT_TAIL   = (150, 110, 90, 255)

def draw_rat(draw, cx, cy, bob=0, lunge=False, hit=False, dead=False):
    fur = (200, 90, 90, 220) if hit else RAT_FUR
    ol  = outline_color(fur)

    cy = cy + bob

    draw_shadow(draw, cx, cy + 38, 28, 7)

    if dead:
        # Splayed on side
        draw.ellipse([cx-40, cy+10, cx+40, cy+32], fill=RAT_FUR_D)
        draw.ellipse([cx-36, cy+12, cx+36, cy+30], fill=fur)
        # Head to side
        draw.ellipse([cx+28, cy+5, cx+55, cy+28], fill=RAT_FUR_D)
        draw.ellipse([cx+30, cy+7, cx+53, cy+26], fill=fur)
        # X eyes
        for ex in [cx+40]:
            draw.line([(ex-4, cy+12),(ex+4, cy+20)], fill=RAT_FUR_D, width=2)
            draw.line([(ex+4, cy+12),(ex-4, cy+20)], fill=RAT_FUR_D, width=2)
        # Tail trailing left
        draw.arc([cx-70, cy+18, cx-20, cy+30], 0, 180, fill=RAT_TAIL, width=4)
        return

    lunge_x = 20 if lunge else 0

    # Tail — long and curling
    tail_pts = [
        (cx - 28 + lunge_x, cy + 20),
        (cx - 55 + lunge_x, cy + 10),
        (cx - 68 + lunge_x, cy - 5),
        (cx - 60 + lunge_x, cy - 18),
    ]
    draw.line(tail_pts, fill=RAT_TAIL, width=6)

    # Body — low elongated oval
    rx_body, ry_body = 32, 20
    draw.ellipse([cx - rx_body - 3 + lunge_x, cy - ry_body - 3,
                  cx + rx_body + 3 + lunge_x, cy + ry_body + 3], fill=ol)
    draw.ellipse([cx - rx_body + lunge_x, cy - ry_body,
                  cx + rx_body + lunge_x, cy + ry_body], fill=fur)
    # Belly lighter
    draw.ellipse([cx - 18 + lunge_x, cy - 8, cx + 18 + lunge_x, cy + 14], fill=RAT_FUR_L)

    # Four stubby legs
    for lx, ly in [(cx - 20 + lunge_x, cy + 14), (cx - 5 + lunge_x, cy + 16),
                   (cx + 10 + lunge_x, cy + 14), (cx + 22 + lunge_x, cy + 16)]:
        draw.rectangle([lx, ly, lx + 7, ly + 12], fill=RAT_FUR_D)

    # Head
    head_cx = cx + 30 + lunge_x
    head_cy = cy - 5
    draw.ellipse([head_cx - 20, head_cy - 16, head_cx + 20, head_cy + 14], fill=ol)
    draw.ellipse([head_cx - 17, head_cy - 13, head_cx + 17, head_cy + 11], fill=fur)
    draw.ellipse([head_cx - 12, head_cy - 9, head_cx + 2, head_cy + 1], fill=highlight(fur))

    # Ears — round and pink inside
    for ex, ey in [(head_cx - 10, head_cy - 18), (head_cx + 6, head_cy - 20)]:
        draw.ellipse([ex - 8, ey - 8, ex + 8, ey + 8], fill=RAT_FUR_D)
        draw.ellipse([ex - 5, ey - 5, ex + 5, ey + 5], fill=RAT_INNER)

    # Snout
    draw.ellipse([head_cx + 8, head_cy - 4, head_cx + 20, head_cy + 8], fill=shade(fur, 0.75))
    draw.ellipse([head_cx + 12, head_cy - 1, head_cx + 18, head_cy + 5], fill=RAT_NOSE)

    # Eye — beady red
    draw.ellipse([head_cx - 4, head_cy - 10, head_cx + 6, head_cy], fill=(10, 5, 5, 255))
    draw.ellipse([head_cx - 2, head_cy - 8, head_cx + 4, head_cy - 2], fill=RAT_EYE)
    draw.rectangle([head_cx, head_cy - 7, head_cx + 2, head_cy - 4], fill=(255, 220, 220, 200))

    # Teeth
    draw.polygon([(head_cx + 8, head_cy + 2), (head_cx + 11, head_cy + 9), (head_cx + 14, head_cy + 2)], fill=RAT_TOOTH)

    # Whiskers
    for wy in [head_cy - 2, head_cy + 2]:
        draw.line([(head_cx + 17, wy), (head_cx + 32, wy - 3)], fill=RAT_FUR_L, width=1)
        draw.line([(head_cx + 17, wy), (head_cx + 32, wy + 3)], fill=RAT_FUR_L, width=1)


def rat_idle(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    bob = -3 if frame_idx == 0 else 3
    draw_rat(d, 100, 175, bob=bob)
    return img

def rat_attack(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_rat(d, 90, 175, lunge=(frame_idx == 1))
    if frame_idx == 1:
        for i in range(3):
            d.line([(155+i*12, 160+i*4), (195+i*12, 168+i*4)], fill=(180, 150, 100, 100), width=2)
    return img

def rat_hit(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_rat(d, 85, 175, hit=True)
    flash = Image.new("RGBA", (FRAME_W, FRAME_H), (0, 0, 0, 0))
    fd = ImageDraw.Draw(flash)
    fd.ellipse([40, 130, 210, 220], fill=(255, 200, 200, 55))
    return Image.alpha_composite(img, flash)

def rat_dead(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_rat(d, 100, 170, dead=True)
    return img

def make_cave_rat():
    strip = new_strip()
    frames = [rat_idle(0), rat_idle(1), rat_attack(0), rat_attack(1),
              rat_hit(0), rat_hit(1), rat_dead(0), rat_dead(1)]
    for i, f in enumerate(frames):
        place_frame(strip, f, i)
    return strip


# ──────────────────────────────────────────────
# RAT GUARD
# ──────────────────────────────────────────────

RG_FUR     = (90, 75, 60, 255)
RG_FUR_D   = (45, 35, 25, 255)
RG_FUR_L   = (150, 130, 105, 255)
RG_EYE     = (230, 40, 40, 255)
RG_ARMOR   = (130, 130, 145, 255)
RG_ARMOR_D = (70, 70, 85, 255)
RG_ARMOR_L = (200, 200, 215, 255)
RG_SPEAR   = (160, 120, 60, 255)
RG_SPEAR_D = (90, 65, 28, 255)
RG_BLADE   = (210, 215, 225, 255)
RG_BLADE_D = (100, 105, 115, 255)
RG_NOSE    = (190, 110, 110, 255)
RG_TOOTH   = (240, 235, 205, 255)

def draw_rat_guard(draw, cx, cy, bob=0, attack=False, hit=False, dead=False):
    fur  = (200, 100, 80, 220) if hit else RG_FUR
    armc = (180, 100, 80, 200) if hit else RG_ARMOR
    ol   = outline_color(fur)

    feet_y = cy + bob

    draw_shadow(draw, cx, feet_y + 5, 38, 10)

    if dead:
        hy = feet_y - 20
        draw.ellipse([cx - 50, hy - 18, cx + 50, hy + 18], fill=RG_ARMOR_D)
        draw.ellipse([cx - 46, hy - 14, cx + 46, hy + 14], fill=armc)
        draw.ellipse([cx + 30, hy - 34, cx + 62, hy - 8], fill=RG_FUR_D)
        draw.ellipse([cx + 33, hy - 31, cx + 59, hy - 11], fill=fur)
        for ex in [cx + 46]:
            draw.line([(ex-4, hy-24),(ex+4, hy-16)], fill=RG_FUR_D, width=2)
            draw.line([(ex+4, hy-24),(ex-4, hy-16)], fill=RG_FUR_D, width=2)
        # Spear fallen
        draw.line([(cx - 60, hy),(cx + 30, hy - 50)], fill=RG_SPEAR_D, width=6)
        draw.line([(cx - 58, hy),(cx + 28, hy - 48)], fill=RG_SPEAR, width=4)
        draw.polygon([(cx + 28, hy - 48),(cx + 38, hy - 68),(cx + 18, hy - 48)], fill=RG_BLADE_D)
        draw.polygon([(cx + 30, hy - 50),(cx + 38, hy - 66),(cx + 20, hy - 50)], fill=RG_BLADE)
        return

    # Legs — upright, wearing crude greaves
    leg_h = 50
    for lx in [cx - 18, cx + 4]:
        draw.rectangle([lx, feet_y - leg_h, lx + 18, feet_y], fill=RG_FUR_D)
        draw.rectangle([lx + 2, feet_y - leg_h + 2, lx + 16, feet_y - 2], fill=fur)
        # Greave
        draw.rectangle([lx - 2, feet_y - 28, lx + 20, feet_y], fill=RG_ARMOR_D)
        draw.rectangle([lx, feet_y - 26, lx + 18, feet_y - 2], fill=armc)
        draw.rectangle([lx + 2, feet_y - 26, lx + 4, feet_y - 2], fill=RG_ARMOR_L)
        # Feet (big rat paws)
        draw.ellipse([lx - 5, feet_y - 10, lx + 24, feet_y + 8], fill=RG_FUR_D)
        draw.ellipse([lx - 3, feet_y - 8, lx + 22, feet_y + 6], fill=fur)

    # Body / chest armor
    bw, bh = 50, 55
    bx, by = cx - bw // 2, feet_y - leg_h - bh
    draw.rectangle([bx - 4, by - 4, bx + bw + 4, by + bh + 4], fill=RG_ARMOR_D)
    draw.rectangle([bx, by, bx + bw, by + bh], fill=armc)
    # Armor highlight stripe
    draw.rectangle([bx + 4, by + 4, bx + 8, by + bh - 4], fill=RG_ARMOR_L)
    # Belt
    draw.rectangle([bx, by + bh - 14, bx + bw, by + bh - 6], fill=RG_FUR_D)

    # Spear arm
    spear_top_x = cx + bw // 2 + 20
    if attack:
        # Thrusting forward
        spear_x1, spear_y1 = cx + bw // 2 + 12, by + 20
        spear_x2, spear_y2 = cx + bw // 2 + 75, by - 20
        arm_end = (cx + bw // 2 + 20, by + 30)
    else:
        spear_x1, spear_y1 = cx + bw // 2 + 8, by + bh
        spear_x2, spear_y2 = cx + bw // 2 + 18, by - 55
        arm_end = (cx + bw // 2 + 14, by + bh - 10)

    # Arm
    draw.rectangle([cx + bw // 2 - 2, by + 10, arm_end[0] + 14, arm_end[1] + 5], fill=RG_FUR_D)
    draw.rectangle([cx + bw // 2, by + 12, arm_end[0] + 12, arm_end[1] + 3], fill=fur)

    # Spear shaft
    draw.line([(spear_x1, spear_y1), (spear_x2, spear_y2)], fill=RG_SPEAR_D, width=7)
    draw.line([(spear_x1, spear_y1), (spear_x2, spear_y2)], fill=RG_SPEAR, width=5)
    # Spear tip
    tip_dx = spear_x2 - spear_x1
    tip_dy = spear_y2 - spear_y1
    norm = math.sqrt(tip_dx**2 + tip_dy**2)
    tip_nx, tip_ny = tip_dx/norm, tip_dy/norm
    tip_px, tip_py = -tip_ny, tip_nx
    draw.polygon([
        (int(spear_x2 + tip_nx*16), int(spear_y2 + tip_ny*16)),
        (int(spear_x2 + tip_px*7), int(spear_y2 + tip_py*7)),
        (int(spear_x2 - tip_px*7), int(spear_y2 - tip_py*7)),
    ], fill=RG_BLADE_D)
    draw.polygon([
        (int(spear_x2 + tip_nx*14), int(spear_y2 + tip_ny*14)),
        (int(spear_x2 + tip_px*5), int(spear_y2 + tip_py*5)),
        (int(spear_x2 - tip_px*5), int(spear_y2 - tip_py*5)),
    ], fill=RG_BLADE)

    # Left arm (shield or hanging)
    draw.rectangle([bx - 24, by + 8, bx + 2, by + bh - 6], fill=RG_FUR_D)
    draw.rectangle([bx - 22, by + 10, bx, by + bh - 8], fill=fur)
    # Small shield
    draw.ellipse([bx - 34, by + 12, bx - 6, by + bh - 8], fill=RG_ARMOR_D)
    draw.ellipse([bx - 32, by + 14, bx - 8, by + bh - 10], fill=armc)
    draw.rectangle([bx - 22, by + 16, bx - 18, by + bh - 12], fill=RG_ARMOR_L)

    # Head — rat-shaped with helmet
    head_r_x, head_r_y = 22, 18
    hx, hy = cx, by - head_r_y - 2
    # Helmet
    draw.ellipse([hx - head_r_x - 5, hy - head_r_y - 8, hx + head_r_x + 5, hy + 4], fill=RG_ARMOR_D)
    draw.ellipse([hx - head_r_x - 3, hy - head_r_y - 6, hx + head_r_x + 3, hy + 2], fill=armc)
    draw.rectangle([hx - 3, hy - head_r_y - 6, hx + 3, hy + 2], fill=RG_ARMOR_L)
    # Face below helmet
    draw.ellipse([hx - head_r_x, hy - 2, hx + head_r_x, hy + head_r_y + 6], fill=ol)
    draw.ellipse([hx - head_r_x + 2, hy, hx + head_r_x - 2, hy + head_r_y + 4], fill=fur)
    # Snout
    draw.ellipse([hx + 8, hy + 2, hx + head_r_x + 4, hy + 14], fill=shade(fur, 0.75))
    draw.ellipse([hx + 12, hy + 5, hx + head_r_x + 1, hy + 11], fill=RG_NOSE)
    # Eye
    draw.ellipse([hx - 5, hy - 2, hx + 5, hy + 8], fill=(10, 5, 5, 255))
    draw.ellipse([hx - 3, hy, hx + 3, hy + 6], fill=RG_EYE)
    draw.rectangle([hx + 1, hy + 1, hx + 3, hy + 4], fill=(255, 220, 220, 200))
    # Teeth
    draw.polygon([(hx + 8, hy + 10), (hx + 11, hy + 17), (hx + 14, hy + 10)], fill=RG_TOOTH)
    # Ear (one visible, helmet covers other)
    draw.ellipse([hx - head_r_x - 4, hy - 14, hx - head_r_x + 8, hy - 2], fill=RG_FUR_D)
    draw.ellipse([hx - head_r_x - 2, hy - 12, hx - head_r_x + 6, hy - 4], fill=shade(RG_NOSE, 1.1))
    # Whiskers
    for wy in [hy + 6, hy + 10]:
        draw.line([(hx + 20, wy), (hx + 38, wy - 2)], fill=RG_FUR_L, width=1)
        draw.line([(hx + 20, wy), (hx + 38, wy + 3)], fill=RG_FUR_L, width=1)

    # Tail
    draw.arc([cx - 65, feet_y - 20, cx - 20, feet_y + 10], 0, 180, fill=RG_FUR_D, width=5)


def rat_guard_idle(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    bob = -3 if frame_idx == 0 else 3
    draw_rat_guard(d, 108, 215, bob=bob)
    return img

def rat_guard_attack(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    cx = 108 + (15 if frame_idx == 1 else 0)
    draw_rat_guard(d, cx, 215, attack=(frame_idx == 1))
    if frame_idx == 1:
        for i in range(3):
            d.line([(175+i*14, 80+i*6),(215+i*14, 90+i*6)], fill=(200,210,230,100), width=2)
    return img

def rat_guard_hit(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_rat_guard(d, 93, 215, hit=True)
    flash = Image.new("RGBA", (FRAME_W, FRAME_H), (0, 0, 0, 0))
    fd = ImageDraw.Draw(flash)
    fd.ellipse([40, 60, 210, 230], fill=(255, 200, 200, 55))
    return Image.alpha_composite(img, flash)

def rat_guard_dead(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_rat_guard(d, 108, 215, dead=True)
    return img

def make_rat_guard():
    strip = new_strip()
    frames = [rat_guard_idle(0), rat_guard_idle(1),
              rat_guard_attack(0), rat_guard_attack(1),
              rat_guard_hit(0), rat_guard_hit(1),
              rat_guard_dead(0), rat_guard_dead(1)]
    for i, f in enumerate(frames):
        place_frame(strip, f, i)
    return strip


# ──────────────────────────────────────────────
# MUSHROOM (Fungoid)
# ──────────────────────────────────────────────

MUSH_CAP     = (210, 45, 35, 255)
MUSH_CAP_D   = (130, 22, 15, 255)
MUSH_CAP_L   = (240, 120, 100, 255)
MUSH_SPOT    = (245, 240, 220, 255)
MUSH_SPOT_D  = (200, 195, 175, 255)
MUSH_STEM    = (210, 195, 160, 255)
MUSH_STEM_D  = (155, 140, 105, 255)
MUSH_STEM_L  = (240, 230, 210, 255)
MUSH_EYE     = (30, 20, 10, 255)
MUSH_SPORE   = (200, 180, 100, 180)
MUSH_GILL    = (180, 160, 120, 200)

def draw_mushroom(draw, cx, cy, bob=0, puff=False, hit=False, dead=False):
    cap_col  = (200, 90, 80, 220) if hit else MUSH_CAP
    stem_col = (220, 140, 130, 220) if hit else MUSH_STEM
    ol       = outline_color(cap_col)

    feet_y = cy + bob

    draw_shadow(draw, cx, feet_y + 10, 36, 9)

    if dead:
        # Slumped flat, cap collapsed
        draw.ellipse([cx - 55, feet_y - 12, cx + 55, feet_y + 12], fill=MUSH_CAP_D)
        draw.ellipse([cx - 50, feet_y - 8, cx + 50, feet_y + 8], fill=cap_col)
        # Stem stub
        draw.rectangle([cx - 10, feet_y - 30, cx + 10, feet_y], fill=MUSH_STEM_D)
        draw.rectangle([cx - 8, feet_y - 28, cx + 8, feet_y - 2], fill=stem_col)
        # Spots scattered
        for sx, sy in [(cx - 30, feet_y - 5), (cx + 15, feet_y - 3), (cx - 5, feet_y - 6)]:
            draw.ellipse([sx - 6, sy - 4, sx + 6, sy + 4], fill=MUSH_SPOT_D)
            draw.ellipse([sx - 4, sy - 3, sx + 4, sy + 3], fill=MUSH_SPOT)
        return

    # Stubby legs
    for lx in [cx - 14, cx + 4]:
        draw.rectangle([lx, feet_y - 24, lx + 14, feet_y], fill=MUSH_STEM_D)
        draw.rectangle([lx + 2, feet_y - 22, lx + 12, feet_y - 2], fill=stem_col)
        draw.ellipse([lx - 4, feet_y - 8, lx + 20, feet_y + 8], fill=MUSH_STEM_D)
        draw.ellipse([lx - 2, feet_y - 6, lx + 18, feet_y + 6], fill=stem_col)

    # Stem / body
    stem_w, stem_h = 36, 50
    sx0, sy0 = cx - stem_w // 2, feet_y - 24 - stem_h
    draw.rectangle([sx0 - 3, sy0 - 3, sx0 + stem_w + 3, sy0 + stem_h + 3], fill=MUSH_STEM_D)
    draw.rectangle([sx0, sy0, sx0 + stem_w, sy0 + stem_h], fill=stem_col)
    draw.rectangle([sx0 + 4, sy0 + 4, sx0 + 8, sy0 + stem_h - 4], fill=MUSH_STEM_L)
    # Gills under cap edge
    draw.rectangle([sx0 - 6, sy0 - 4, sx0 + stem_w + 6, sy0 + 6], fill=MUSH_GILL)

    # Arms — stubby stem-tendrils
    for ax, ay, aw, ah in [(sx0 - 20, sy0 + 12, 20, 12), (sx0 + stem_w, sy0 + 12, 20, 12)]:
        draw.ellipse([ax, ay, ax + aw, ay + ah], fill=MUSH_STEM_D)
        draw.ellipse([ax + 2, ay + 2, ax + aw - 2, ay + ah - 2], fill=stem_col)

    # Eyes on stem
    eye_y = sy0 + 18
    for ex in [cx - 8, cx + 2]:
        draw.ellipse([ex - 6, eye_y - 6, ex + 6, eye_y + 6], fill=MUSH_EYE)
        draw.ellipse([ex - 4, eye_y - 4, ex + 4, eye_y + 4], fill=(60, 40, 20, 255))
        draw.rectangle([ex - 1, eye_y - 4, ex + 1, eye_y - 1], fill=(255, 255, 240, 200))

    # Mouth — grumpy line
    draw.arc([cx - 10, eye_y + 8, cx + 10, eye_y + 18], 200, 340, fill=MUSH_STEM_D, width=2)

    # Cap — wide dome
    cap_rx, cap_ry = 58, 42
    cap_cx, cap_cy = cx, sy0 - cap_ry + 12
    # Puff slightly bigger when attacking
    if puff:
        cap_rx += 6
        cap_ry += 4
    draw.ellipse([cap_cx - cap_rx - 4, cap_cy - cap_ry - 4,
                  cap_cx + cap_rx + 4, cap_cy + cap_ry + 4], fill=ol)
    draw.ellipse([cap_cx - cap_rx, cap_cy - cap_ry,
                  cap_cx + cap_rx, cap_cy + cap_ry], fill=cap_col)
    # Highlight
    draw.ellipse([cap_cx - cap_rx + 8, cap_cy - cap_ry + 8,
                  cap_cx - 10, cap_cy - 8], fill=MUSH_CAP_L)

    # Spots
    for spx, spy, spr in [
        (cx - 20, cap_cy - 20, 9),
        (cx + 18, cap_cy - 16, 8),
        (cx, cap_cy + 2, 7),
        (cx - 35, cap_cy + 5, 6),
        (cx + 30, cap_cy + 8, 5),
    ]:
        draw.ellipse([spx - spr - 1, spy - spr - 1, spx + spr + 1, spy + spr + 1], fill=MUSH_SPOT_D)
        draw.ellipse([spx - spr, spy - spr, spx + spr, spy + spr], fill=MUSH_SPOT)

    # Spore cloud if puffing
    if puff:
        for i in range(6):
            ang = math.radians(i * 60)
            px = cx + int((cap_rx + 14) * math.cos(ang))
            py = cap_cy + int((cap_ry + 10) * math.sin(ang))
            r = 8 + (i % 2) * 4
            draw.ellipse([px - r, py - r, px + r, py + r], fill=MUSH_SPORE)


def mushroom_idle(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    bob = -3 if frame_idx == 0 else 3
    draw_mushroom(d, 118, 205, bob=bob)
    return img

def mushroom_attack(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_mushroom(d, 118, 205, puff=(frame_idx == 1))
    if frame_idx == 1:
        # Spore particles flying right
        for i in range(5):
            px = 185 + i * 14
            py = 140 + (i % 3) * 8
            d.ellipse([px - 6, py - 6, px + 6, py + 6], fill=(*MUSH_SPORE[:3], 160 - i*20))
    return img

def mushroom_hit(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_mushroom(d, 103, 205, hit=True)
    flash = Image.new("RGBA", (FRAME_W, FRAME_H), (0, 0, 0, 0))
    fd = ImageDraw.Draw(flash)
    fd.ellipse([40, 50, 210, 225], fill=(255, 200, 180, 55))
    return Image.alpha_composite(img, flash)

def mushroom_dead(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_mushroom(d, 118, 205, dead=True)
    return img

def make_mushroom():
    strip = new_strip()
    frames = [mushroom_idle(0), mushroom_idle(1),
              mushroom_attack(0), mushroom_attack(1),
              mushroom_hit(0), mushroom_hit(1),
              mushroom_dead(0), mushroom_dead(1)]
    for i, f in enumerate(frames):
        place_frame(strip, f, i)
    return strip


# ──────────────────────────────────────────────
# CAVE TROLL (boss-tier, fills frame)
# ──────────────────────────────────────────────

CT_SKIN    = (95, 120, 65, 255)
CT_SKIN_D  = (48, 62, 28, 255)
CT_SKIN_L  = (160, 190, 110, 255)
CT_EYE     = (255, 80, 0, 255)
CT_PUPIL   = (30, 10, 0, 255)
CT_FANG    = (230, 225, 185, 255)
CT_CLOTH   = (80, 55, 22, 255)
CT_CLOTH_D = (45, 28, 8, 255)
CT_NAIL    = (105, 85, 38, 255)
CT_CLUB    = (115, 80, 35, 255)
CT_CLUB_D  = (62, 42, 14, 255)
CT_ROCK_D  = (80, 68, 50, 255)

def draw_cave_troll(draw, cx, bob=0, swing=False, hit=False, dead=False):
    skin = (200, 130, 80, 220) if hit else CT_SKIN
    ol   = outline_color(skin)

    feet_y = 240 + bob

    draw_shadow(draw, cx, feet_y + 6, 80, 18)

    if dead:
        hy = feet_y - 35
        draw.ellipse([cx - 90, hy - 28, cx + 90, hy + 28], fill=CT_SKIN_D)
        draw.ellipse([cx - 85, hy - 24, cx + 85, hy + 24], fill=skin)
        # Head
        draw.ellipse([cx + 48, hy - 52, cx + 100, hy - 8], fill=CT_SKIN_D)
        draw.ellipse([cx + 51, hy - 49, cx + 97, hy - 11], fill=skin)
        for ex in [cx + 65, cx + 80]:
            draw.line([(ex-5, hy-32),(ex+5, hy-22)], fill=CT_SKIN_D, width=2)
            draw.line([(ex+5, hy-32),(ex-5, hy-22)], fill=CT_SKIN_D, width=2)
        # Club
        draw.rectangle([cx - 80, hy - 10, cx - 30, hy + 4], fill=CT_CLUB_D)
        draw.rectangle([cx - 78, hy - 8, cx - 32, hy + 2], fill=CT_CLUB)
        return

    # Very thick legs
    leg_h = 78
    for lx in [cx - 34, cx + 8]:
        draw.rectangle([lx, feet_y - leg_h, lx + 34, feet_y], fill=CT_SKIN_D)
        draw.rectangle([lx + 3, feet_y - leg_h + 3, lx + 31, feet_y - 3], fill=skin)
        # Cloth wrapping
        draw.rectangle([lx, feet_y - leg_h, lx + 34, feet_y - leg_h + 22], fill=CT_CLOTH)
        # Big foot
        draw.ellipse([lx - 8, feet_y - 12, lx + 46, feet_y + 14], fill=CT_SKIN_D)
        draw.ellipse([lx - 6, feet_y - 10, lx + 44, feet_y + 12], fill=skin)
        for ni in range(4):
            nx = lx + 2 + ni * 10
            draw.rectangle([nx, feet_y + 6, nx + 8, feet_y + 15], fill=CT_NAIL)

    # Loincloth
    draw.polygon([
        (cx - 42, feet_y - leg_h - 4), (cx + 42, feet_y - leg_h - 4),
        (cx + 32, feet_y - 50), (cx, feet_y - 42), (cx - 32, feet_y - 50)
    ], fill=CT_CLOTH_D)
    draw.polygon([
        (cx - 38, feet_y - leg_h - 2), (cx + 38, feet_y - leg_h - 2),
        (cx + 28, feet_y - 52), (cx, feet_y - 44), (cx - 28, feet_y - 52)
    ], fill=CT_CLOTH)

    # Massive barrel chest
    bw, bh = 105, 95
    bx, by = cx - bw // 2, feet_y - leg_h - bh
    draw.rectangle([bx - 5, by - 5, bx + bw + 5, by + bh + 5], fill=CT_SKIN_D)
    draw.rectangle([bx, by, bx + bw, by + bh], fill=skin)
    draw.ellipse([bx + 8, by + 8, bx + 40, by + 38], fill=CT_SKIN_L)
    # Chest scars / texture
    for i in range(3):
        sx = bx + 20 + i * 24
        draw.arc([sx, by + 15, sx + 16, by + 28], 0, 180, fill=CT_SKIN_D, width=3)

    # Left arm — hanging massive
    draw.rectangle([bx - 38, by + 12, bx + 6, by + 95], fill=CT_SKIN_D)
    draw.rectangle([bx - 36, by + 14, bx + 4, by + 93], fill=skin)
    draw.ellipse([bx - 44, by + 88, bx + 10, by + 112], fill=CT_SKIN_D)
    draw.ellipse([bx - 42, by + 90, bx + 8, by + 110], fill=skin)
    for ni in range(4):
        nx = bx - 38 + ni * 11
        draw.rectangle([nx, by + 107, nx + 9, by + 116], fill=CT_NAIL)

    # Right arm — swings with attack or hangs
    if swing:
        draw.rectangle([bx + bw - 6, by - 42, bx + bw + 46, by + 42], fill=CT_SKIN_D)
        draw.rectangle([bx + bw - 4, by - 40, bx + bw + 44, by + 40], fill=skin)
        # Giant spiked club raised
        club_cx = bx + bw + 22
        club_cy = by - 70
        draw.rectangle([club_cx - 8, club_cy, club_cx + 8, by + 8], fill=CT_CLUB_D)
        draw.rectangle([club_cx - 6, club_cy + 2, club_cx + 6, by + 6], fill=CT_CLUB)
        for i in range(6):
            ang = math.radians(i * 60)
            sx = club_cx + int(24 * math.cos(ang))
            sy = club_cy + 18 + int(24 * math.sin(ang))
            draw.polygon([(sx, sy), (sx + int(12*math.cos(ang)), sy + int(12*math.sin(ang))),
                          (sx + int(12*math.cos(ang+0.4)), sy + int(12*math.sin(ang+0.4)))],
                         fill=CT_ROCK_D)
        draw.ellipse([club_cx - 24, club_cy - 6, club_cx + 24, club_cy + 42], fill=CT_CLUB_D)
        draw.ellipse([club_cx - 22, club_cy - 4, club_cx + 22, club_cy + 40], fill=CT_CLUB)
        draw.ellipse([club_cx - 12, club_cy - 2, club_cx, club_cy + 10], fill=highlight(CT_CLUB))
    else:
        draw.rectangle([bx + bw - 6, by + 12, bx + bw + 44, by + 95], fill=CT_SKIN_D)
        draw.rectangle([bx + bw - 4, by + 14, bx + bw + 42, by + 93], fill=skin)
        draw.ellipse([bx + bw - 10, by + 88, bx + bw + 48, by + 112], fill=CT_SKIN_D)
        draw.ellipse([bx + bw - 8, by + 90, bx + bw + 46, by + 110], fill=skin)
        for ni in range(4):
            nx = bx + bw - 4 + ni * 11
            draw.rectangle([nx, by + 107, nx + 9, by + 116], fill=CT_NAIL)
        # Club dragged at side
        cx2 = bx + bw + 28
        draw.rectangle([cx2 - 6, by + 80, cx2 + 6, feet_y - 8], fill=CT_CLUB_D)
        draw.rectangle([cx2 - 4, by + 82, cx2 + 4, feet_y - 10], fill=CT_CLUB)
        draw.ellipse([cx2 - 18, feet_y - 50, cx2 + 18, feet_y - 12], fill=CT_CLUB_D)
        draw.ellipse([cx2 - 16, feet_y - 48, cx2 + 16, feet_y - 14], fill=CT_CLUB)

    # Big ugly head
    head_r = 48
    hx, hy = cx, by - head_r + 10
    draw.ellipse([hx - head_r - 5, hy - head_r - 5, hx + head_r + 5, hy + head_r + 5], fill=CT_SKIN_D)
    draw.ellipse([hx - head_r, hy - head_r, hx + head_r, hy + head_r], fill=skin)
    draw.ellipse([hx - head_r + 6, hy - head_r + 6, hx - 5, hy - 5], fill=CT_SKIN_L)

    # Brow ridge — massive
    draw.ellipse([hx - head_r + 3, hy - head_r//2 - 10,
                  hx + head_r - 3, hy - head_r//2 + 14], fill=CT_SKIN_D)

    # Ears (huge, floppy)
    for sign in [-1, 1]:
        ex = hx + sign * head_r
        draw.ellipse([ex - 18, hy - 14, ex + 18, hy + 22], fill=CT_SKIN_D)
        draw.ellipse([ex - 15, hy - 11, ex + 15, hy + 19], fill=skin)

    # Sunken eyes (glowing orange-red)
    for ex in [hx - 18, hx + 8]:
        draw.ellipse([ex - 11, hy - 16, ex + 11, hy + 2], fill=(20, 10, 5, 255))
        draw.ellipse([ex - 9, hy - 14, ex + 9, hy], fill=CT_EYE)
        draw.ellipse([ex - 4, hy - 12, ex + 4, hy - 5], fill=CT_PUPIL)
        draw.rectangle([ex - 2, hy - 13, ex + 1, hy - 8], fill=(255, 210, 190, 180))

    # Nose — huge
    draw.ellipse([hx - 12, hy - 6, hx + 12, hy + 14], fill=CT_SKIN_D)
    draw.ellipse([hx - 10, hy - 4, hx + 10, hy + 12], fill=shade(skin, 0.82))
    draw.rectangle([hx - 9, hy + 2, hx - 4, hy + 10], fill=(28, 14, 6, 160))
    draw.rectangle([hx + 4, hy + 2, hx + 9, hy + 10], fill=(28, 14, 6, 160))

    # Mouth (massive with tusks)
    draw.arc([hx - 20, hy + 12, hx + 20, hy + 28], 5, 175, fill=CT_SKIN_D, width=3)
    for tx, tw in [(hx - 12, 8), (hx + 4, 8)]:
        draw.polygon([(tx, hy + 14), (tx + tw//2, hy + 28), (tx + tw, hy + 14)], fill=CT_FANG)
    # Lower tusks
    for tx in [hx - 15, hx + 8]:
        draw.polygon([(tx, hy + 26), (tx - 4, hy + 42), (tx + 6, hy + 28)], fill=CT_FANG)

    # Rock-wart bumps on head
    for wx, wy in [(hx - 28, hy - 32), (hx + 20, hy - 25), (hx + 35, hy - 5)]:
        draw.ellipse([wx - 5, wy - 5, wx + 5, wy + 5], fill=CT_SKIN_D)
        draw.ellipse([wx - 3, wy - 3, wx + 3, wy + 3], fill=CT_ROCK_D)

    # Hair tufts
    for hi in range(-2, 3):
        hxp = hx + hi * 12
        draw.polygon([(hxp, hy - head_r), (hxp - 5, hy - head_r - 18), (hxp + 5, hy - head_r - 18)],
                     fill=CT_SKIN_D)


def cave_troll_idle(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    bob = -4 if frame_idx == 0 else 4
    draw_cave_troll(d, 118, bob=bob)
    return img

def cave_troll_attack(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    cx = 108 + (18 if frame_idx == 1 else 0)
    draw_cave_troll(d, cx, swing=(frame_idx == 1))
    if frame_idx == 1:
        for i in range(4):
            d.line([(185+i*14, 60+i*10),(230+i*14, 75+i*10)],
                   fill=(200, 180, 100, 120 - i*20), width=3)
    return img

def cave_troll_hit(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_cave_troll(d, 100, hit=True)
    flash = Image.new("RGBA", (FRAME_W, FRAME_H), (0, 0, 0, 0))
    fd = ImageDraw.Draw(flash)
    fd.ellipse([20, 20, 236, 248], fill=(255, 200, 180, 60))
    return Image.alpha_composite(img, flash)

def cave_troll_dead(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_cave_troll(d, 118, dead=True)
    return img

def make_cave_troll():
    strip = new_strip()
    frames = [cave_troll_idle(0), cave_troll_idle(1),
              cave_troll_attack(0), cave_troll_attack(1),
              cave_troll_hit(0), cave_troll_hit(1),
              cave_troll_dead(0), cave_troll_dead(1)]
    for i, f in enumerate(frames):
        place_frame(strip, f, i)
    return strip


# ──────────────────────────────────────────────
# SHADOW KNIGHT (boss-tier)
# ──────────────────────────────────────────────

SK_ARMOR    = (28, 24, 38, 255)
SK_ARMOR_D  = (10, 8, 16, 255)
SK_ARMOR_L  = (60, 55, 80, 255)
SK_EDGE     = (100, 90, 130, 255)
SK_EYE      = (220, 40, 40, 255)
SK_CAPE     = (38, 12, 50, 255)
SK_CAPE_D   = (18, 5, 24, 255)
SK_CAPE_L   = (80, 30, 100, 255)
SK_SWORD    = (160, 155, 175, 255)
SK_SWORD_D  = (60, 58, 72, 255)
SK_SHADOW   = (20, 10, 35, 160)
SK_GLOW     = (180, 30, 30, 200)

def draw_shadow_knight(draw, cx, bob=0, strike=False, hit=False, dead=False):
    armor = (100, 60, 60, 220) if hit else SK_ARMOR
    ol    = SK_ARMOR_D

    feet_y = 238 + bob

    draw_shadow(draw, cx, feet_y + 6, 70, 16)
    # Extra shadow aura
    draw.ellipse([cx - 85, feet_y - 12, cx + 85, feet_y + 20], fill=(*SK_SHADOW[:3], 60))

    if dead:
        hy = feet_y - 30
        # Armor pile
        draw.rectangle([cx - 55, hy - 10, cx + 55, hy + 14], fill=SK_ARMOR_D)
        draw.rectangle([cx - 52, hy - 8, cx + 52, hy + 12], fill=armor)
        # Helmet
        draw.ellipse([cx + 30, hy - 40, cx + 75, hy - 5], fill=SK_ARMOR_D)
        draw.ellipse([cx + 33, hy - 37, cx + 72, hy - 8], fill=armor)
        # Eyes faded
        for ex in [cx + 46, cx + 62]:
            draw.ellipse([ex - 4, hy - 24, ex + 4, hy - 16], fill=(80, 15, 15, 150))
        # Sword on ground
        draw.line([(cx - 70, hy + 5), (cx + 20, hy - 55)], fill=SK_SWORD_D, width=7)
        draw.line([(cx - 68, hy + 5), (cx + 18, hy - 53)], fill=SK_SWORD, width=4)
        # Cape splayed
        draw.polygon([
            (cx - 55, hy),(cx - 20, hy - 8),(cx, hy),(cx - 20, hy + 20),(cx - 55, hy + 16)
        ], fill=SK_CAPE_D)
        return

    # Cape — tattered, behind everything (drawn first)
    cape_offset = 15 if strike else 0
    cape_pts = [
        (cx + 32, feet_y - 165),
        (cx + 52 + cape_offset, feet_y - 100),
        (cx + 60 + cape_offset, feet_y - 30),
        (cx + 40 + cape_offset, feet_y),
        (cx + 10, feet_y - 10),
        (cx - 10, feet_y - 12),
        (cx - 44, feet_y),
        (cx - 62, feet_y - 24),
        (cx - 58, feet_y - 100),
        (cx - 32, feet_y - 165),
    ]
    draw.polygon(cape_pts, fill=SK_CAPE_D)
    # Tattered hem
    for i in range(0, len(cape_pts) - 2, 2):
        x1, y1 = cape_pts[i]
        x2, y2 = cape_pts[i+1]
        mx, my = (x1+x2)//2, (y1+y2)//2
        draw.polygon([(x1, y1), (mx, my + 18), (x2, y2)], fill=SK_CAPE_D)
    # Cape inner lighter
    inner_cape = [
        (cx + 28, feet_y - 160), (cx + 46, feet_y - 90), (cx + 48, feet_y - 35),
        (cx + 18, feet_y - 8), (cx, feet_y - 10), (cx - 18, feet_y - 10),
        (cx - 48, feet_y - 35), (cx - 46, feet_y - 90), (cx - 28, feet_y - 160),
    ]
    draw.polygon(inner_cape, fill=SK_CAPE)

    # Greaved legs
    leg_h = 80
    for lx in [cx - 30, cx + 6]:
        draw.rectangle([lx, feet_y - leg_h, lx + 28, feet_y], fill=SK_ARMOR_D)
        draw.rectangle([lx + 2, feet_y - leg_h + 2, lx + 26, feet_y - 2], fill=armor)
        draw.rectangle([lx + 4, feet_y - leg_h + 4, lx + 8, feet_y - 4], fill=SK_ARMOR_L)
        draw.rectangle([lx + 18, feet_y - leg_h + 4, lx + 22, feet_y - 4], fill=SK_ARMOR_L)
        # Sabatons
        draw.ellipse([lx - 6, feet_y - 12, lx + 36, feet_y + 10], fill=SK_ARMOR_D)
        draw.ellipse([lx - 4, feet_y - 10, lx + 34, feet_y + 8], fill=armor)

    # Torso plate
    bw, bh = 72, 88
    bx, by = cx - bw // 2, feet_y - leg_h - bh
    draw.rectangle([bx - 5, by - 5, bx + bw + 5, by + bh + 5], fill=SK_ARMOR_D)
    draw.rectangle([bx, by, bx + bw, by + bh], fill=armor)
    # Breastplate ridges
    for ry in range(by + 10, by + bh - 10, 16):
        draw.rectangle([bx + 4, ry, bx + bw - 4, ry + 4], fill=SK_ARMOR_L)
    draw.rectangle([bx + 6, by + 6, bx + 10, by + bh - 6], fill=SK_EDGE)

    # Left pauldron + arm
    draw.ellipse([bx - 30, by - 8, bx + 16, by + 24], fill=SK_ARMOR_D)
    draw.ellipse([bx - 28, by - 6, bx + 14, by + 22], fill=armor)
    draw.rectangle([bx - 22, by + 18, bx + 4, by + bh - 2], fill=SK_ARMOR_D)
    draw.rectangle([bx - 20, by + 20, bx + 2, by + bh - 4], fill=armor)
    # Left gauntlet
    draw.ellipse([bx - 24, by + bh - 8, bx + 6, by + bh + 16], fill=SK_ARMOR_D)
    draw.ellipse([bx - 22, by + bh - 6, bx + 4, by + bh + 14], fill=armor)

    # Right pauldron + sword arm
    draw.ellipse([bx + bw - 16, by - 8, bx + bw + 30, by + 24], fill=SK_ARMOR_D)
    draw.ellipse([bx + bw - 14, by - 6, bx + bw + 28, by + 22], fill=armor)
    if strike:
        # Sword arm swinging down-right
        draw.rectangle([bx + bw - 4, by + 8, bx + bw + 28, by + 55], fill=SK_ARMOR_D)
        draw.rectangle([bx + bw - 2, by + 10, bx + bw + 26, by + 53], fill=armor)
        # Sword extended
        sx1, sy1 = bx + bw + 22, by + 52
        sx2, sy2 = bx + bw + 78, by + 120
        draw.line([(sx1, sy1), (sx2, sy2)], fill=SK_SWORD_D, width=9)
        draw.line([(sx1, sy1), (sx2, sy2)], fill=SK_SWORD, width=6)
        # Crossguard
        draw.line([(sx1 - 14, sy1 - 10), (sx1 + 14, sy1 + 10)], fill=SK_SWORD_D, width=7)
        draw.line([(sx1 - 12, sy1 - 8), (sx1 + 12, sy1 + 8)], fill=SK_SWORD, width=5)
        # Dark energy effect
        for i in range(3):
            draw.ellipse([sx2 - 12+i*6, sy2 - 12+i*6, sx2 + 12-i*6, sy2 + 12-i*6],
                         fill=(*SK_GLOW[:3], 140 - i*30))
    else:
        draw.rectangle([bx + bw - 4, by + 15, bx + bw + 28, by + bh - 2], fill=SK_ARMOR_D)
        draw.rectangle([bx + bw - 2, by + 17, bx + bw + 26, by + bh - 4], fill=armor)
        draw.ellipse([bx + bw - 8, by + bh - 8, bx + bw + 30, by + bh + 16], fill=SK_ARMOR_D)
        draw.ellipse([bx + bw - 6, by + bh - 6, bx + bw + 28, by + bh + 14], fill=armor)
        # Sword at side, point down
        sx = bx + bw + 16
        draw.line([(sx, by + bh + 10), (sx + 4, feet_y - 10)], fill=SK_SWORD_D, width=9)
        draw.line([(sx, by + bh + 10), (sx + 4, feet_y - 10)], fill=SK_SWORD, width=6)
        draw.line([(sx - 12, by + bh + 8), (sx + 12, by + bh + 20)], fill=SK_SWORD_D, width=7)
        draw.line([(sx - 10, by + bh + 10), (sx + 10, by + bh + 18)], fill=SK_SWORD, width=5)

    # Helmet — full coverage great helm
    head_r = 36
    hx, hy = cx, by - head_r + 12
    draw.ellipse([hx - head_r - 5, hy - head_r - 8,
                  hx + head_r + 5, hy + head_r + 5], fill=SK_ARMOR_D)
    draw.ellipse([hx - head_r - 3, hy - head_r - 6,
                  hx + head_r + 3, hy + head_r + 3], fill=armor)
    # Visor slit
    draw.rectangle([hx - 20, hy - 8, hx + 20, hy + 2], fill=SK_ARMOR_D)
    # Eyes glowing red through visor
    for ex in [hx - 12, hx + 5]:
        draw.ellipse([ex - 6, hy - 7, ex + 6, hy + 1], fill=(*SK_EYE[:3], 40))
        draw.ellipse([ex - 4, hy - 5, ex + 4, hy - 1], fill=SK_EYE)
        draw.ellipse([ex - 2, hy - 4, ex + 2, hy - 2], fill=(255, 180, 180, 255))
    # Helmet highlight and crest
    draw.rectangle([hx - 3, hy - head_r - 8, hx + 3, hy - head_r + 6], fill=SK_ARMOR_L)
    draw.rectangle([hx - 5, hy - head_r - 6, hx + 5, hy - head_r + 4], fill=SK_EDGE)
    # Pauldron ridges on helmet base
    draw.rectangle([hx - head_r - 4, hy + 3, hx + head_r + 4, hy + 8], fill=SK_ARMOR_D)
    draw.rectangle([hx - head_r - 2, hy + 5, hx + head_r + 2, hy + 6], fill=SK_ARMOR_L)

    # Dark aura wisps around entire figure
    for i in range(4):
        ang = math.radians(i * 90 + bob * 4)
        ax = cx + int(78 * math.cos(ang))
        ay = (hy + feet_y) // 2 + int(80 * math.sin(ang))
        draw.ellipse([ax - 10, ay - 18, ax + 10, ay + 18], fill=(*SK_SHADOW[:3], 50))


def shadow_knight_idle(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    bob = -4 if frame_idx == 0 else 4
    draw_shadow_knight(d, 115, bob=bob)
    return img

def shadow_knight_attack(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    cx = 100 + (16 if frame_idx == 1 else 0)
    draw_shadow_knight(d, cx, strike=(frame_idx == 1))
    if frame_idx == 1:
        for i in range(4):
            d.ellipse([180 + i*12, 165 + i*8, 205 + i*12, 188 + i*8],
                      fill=(*SK_GLOW[:3], 120 - i*22))
    return img

def shadow_knight_hit(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_shadow_knight(d, 100, hit=True)
    flash = Image.new("RGBA", (FRAME_W, FRAME_H), (0, 0, 0, 0))
    fd = ImageDraw.Draw(flash)
    fd.ellipse([20, 20, 236, 248], fill=(255, 200, 200, 60))
    return Image.alpha_composite(img, flash)

def shadow_knight_dead(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_shadow_knight(d, 115, dead=True)
    return img

def make_shadow_knight():
    strip = new_strip()
    frames = [shadow_knight_idle(0), shadow_knight_idle(1),
              shadow_knight_attack(0), shadow_knight_attack(1),
              shadow_knight_hit(0), shadow_knight_hit(1),
              shadow_knight_dead(0), shadow_knight_dead(1)]
    for i, f in enumerate(frames):
        place_frame(strip, f, i)
    return strip


# ──────────────────────────────────────────────
# DRAGON BASE HELPERS
# ──────────────────────────────────────────────

def draw_dragon_base(draw, cx, cy, body_col, body_d, body_l,
                     wing_col, wing_d, eye_col, horn_col, breath_col,
                     breath_col2, hit=False, dead=False, breath=False,
                     wing_up=True, lurk=False):
    """Generic dragon drawing — caller sets all colours."""
    bc = (200, 100, 80, 220) if hit else body_col
    ol = body_d

    draw_shadow(draw, cx, cy + 108, 95, 22)

    if dead:
        # Collapsed heap
        draw.ellipse([cx - 100, cy + 50, cx + 100, cy + 95], fill=ol)
        draw.ellipse([cx - 96, cy + 54, cx + 96, cy + 91], fill=bc)
        # Head drooped to side
        draw.ellipse([cx + 60, cy + 20, cx + 115, cy + 65], fill=ol)
        draw.ellipse([cx + 63, cy + 23, cx + 112, cy + 62], fill=bc)
        # X eyes
        for ex in [cx + 80, cx + 98]:
            draw.line([(ex-5, cy+32),(ex+5, cy+44)], fill=ol, width=3)
            draw.line([(ex+5, cy+32),(ex-5, cy+44)], fill=ol, width=3)
        # Wings crumpled
        draw.polygon([(cx - 90, cy + 55), (cx - 130, cy + 10), (cx - 60, cy + 50)],
                     fill=wing_d)
        draw.polygon([(cx - 86, cy + 55), (cx - 126, cy + 14), (cx - 62, cy + 52)],
                     fill=wing_col)
        return

    wing_y_offset = -30 if wing_up else 20

    # Wings — large, fill frame sides
    wing_w = 108
    # Left wing
    lw_pts = [
        (cx - 30, cy - 10),
        (cx - wing_w - 18, cy + wing_y_offset - 10),
        (cx - wing_w - 28, cy + wing_y_offset + 50),
        (cx - wing_w, cy + 70),
        (cx - 40, cy + 50),
    ]
    draw.polygon(lw_pts, fill=wing_d)
    lw_in = [(x+4 if x < cx else x, y+4) for x,y in lw_pts]
    draw.polygon(lw_in, fill=wing_col)
    # Wing membrane veins
    draw.line([(cx-30, cy-10), (cx-wing_w-28, cy+wing_y_offset+50)], fill=wing_d, width=3)
    draw.line([(cx-30, cy-10), (cx-wing_w-10, cy+70)], fill=wing_d, width=2)
    draw.line([(cx-30, cy-10), (cx-70, cy+70)], fill=wing_d, width=2)

    # Right wing
    rw_pts = [
        (cx + 30, cy - 10),
        (cx + wing_w + 18, cy + wing_y_offset - 10),
        (cx + wing_w + 28, cy + wing_y_offset + 50),
        (cx + wing_w, cy + 70),
        (cx + 40, cy + 50),
    ]
    draw.polygon(rw_pts, fill=wing_d)
    rw_in = [(x-4 if x > cx else x, y+4) for x,y in rw_pts]
    draw.polygon(rw_in, fill=wing_col)
    draw.line([(cx+30, cy-10), (cx+wing_w+28, cy+wing_y_offset+50)], fill=wing_d, width=3)
    draw.line([(cx+30, cy-10), (cx+wing_w+10, cy+70)], fill=wing_d, width=2)
    draw.line([(cx+30, cy-10), (cx+70, cy+70)], fill=wing_d, width=2)

    # Body — big oval
    rx_b, ry_b = 68, 52
    draw.ellipse([cx - rx_b - 5, cy + 20 - 5, cx + rx_b + 5, cy + 20 + ry_b * 2 + 5], fill=ol)
    draw.ellipse([cx - rx_b, cy + 20, cx + rx_b, cy + 20 + ry_b * 2], fill=bc)
    draw.ellipse([cx - rx_b + 8, cy + 26, cx - 20, cy + 50], fill=body_l)

    # Belly scales (lighter rows)
    for by_s in range(cy + 40, cy + 20 + ry_b * 2 - 10, 16):
        draw.ellipse([cx - 36, by_s, cx + 36, by_s + 12], fill=body_l)

    # Legs
    for lx, ldir in [(cx - 48, -1), (cx + 22, 1)]:
        draw.rectangle([lx, cy + 20 + ry_b + 20, lx + 30, cy + 20 + ry_b + 75], fill=ol)
        draw.rectangle([lx + 3, cy + 20 + ry_b + 23, lx + 27, cy + 20 + ry_b + 72], fill=bc)
        # Claws
        claw_y = cy + 20 + ry_b + 75
        for ci in range(3):
            claw_x = lx + 4 + ci * 9
            draw.polygon([(claw_x, claw_y), (claw_x + ldir * 10, claw_y + 14),
                          (claw_x + 7, claw_y)], fill=ol)
            draw.polygon([(claw_x+1, claw_y+1), (claw_x + ldir * 8, claw_y + 12),
                          (claw_x + 6, claw_y+1)], fill=horn_col)

    # Tail — curling
    tail_pts = [(cx + rx_b - 10, cy + 20 + ry_b + 40),
                (cx + rx_b + 30, cy + 20 + ry_b + 60),
                (cx + rx_b + 55, cy + 20 + ry_b + 40),
                (cx + rx_b + 50, cy + 20 + ry_b + 10)]
    draw.line(tail_pts, fill=ol, width=20)
    draw.line(tail_pts, fill=bc, width=15)
    # Tail spike
    draw.polygon([tail_pts[-1],
                  (tail_pts[-1][0] + 16, tail_pts[-1][1] - 22),
                  (tail_pts[-1][0] + 5, tail_pts[-1][1] + 5)],
                 fill=ol)
    draw.polygon([(tail_pts[-1][0]+1, tail_pts[-1][1]+1),
                  (tail_pts[-1][0] + 14, tail_pts[-1][1] - 20),
                  (tail_pts[-1][0] + 4, tail_pts[-1][1] + 4)],
                 fill=horn_col)

    # Neck
    neck_x1, neck_y1 = cx - 22, cy + 22
    neck_x2, neck_y2 = cx - 55, cy - 35
    draw.line([(neck_x1, neck_y1), (neck_x2, neck_y2)], fill=ol, width=30)
    draw.line([(neck_x1, neck_y1), (neck_x2, neck_y2)], fill=bc, width=24)
    # Neck spines
    for i in range(4):
        t = i / 3
        nsx = int(neck_x1 + t * (neck_x2 - neck_x1))
        nsy = int(neck_y1 + t * (neck_y2 - neck_y1)) - 10
        draw.polygon([(nsx-5, nsy), (nsx, nsy-16), (nsx+5, nsy)], fill=ol)
        draw.polygon([(nsx-3, nsy), (nsx, nsy-13), (nsx+3, nsy)], fill=horn_col)

    # Head
    hcx, hcy = cx - 70, cy - 58
    draw.ellipse([hcx - 34, hcy - 22, hcx + 34, hcy + 22], fill=ol)
    draw.ellipse([hcx - 31, hcy - 19, hcx + 31, hcy + 19], fill=bc)
    # Snout elongated
    draw.ellipse([hcx + 10, hcy - 12, hcx + 52, hcy + 12], fill=ol)
    draw.ellipse([hcx + 12, hcy - 10, hcx + 50, hcy + 10], fill=bc)
    # Nostril
    draw.ellipse([hcx + 36, hcy - 6, hcx + 46, hcy + 2], fill=ol)
    # Horns
    for hx_off, hx_dir in [(-20, -1), (10, 1)]:
        draw.polygon([
            (hcx + hx_off, hcy - 18),
            (hcx + hx_off + hx_dir * 12, hcy - 52),
            (hcx + hx_off + hx_dir * 4, hcy - 18),
        ], fill=ol)
        draw.polygon([
            (hcx + hx_off + 1, hcy - 17),
            (hcx + hx_off + hx_dir * 10, hcy - 49),
            (hcx + hx_off + hx_dir * 3, hcy - 17),
        ], fill=horn_col)
    # Eye (vertical slit)
    draw.ellipse([hcx - 16, hcy - 12, hcx + 4, hcy + 8], fill=(10, 5, 5, 255))
    draw.ellipse([hcx - 13, hcy - 9, hcx + 1, hcy + 5], fill=eye_col)
    draw.rectangle([hcx - 7, hcy - 9, hcx - 5, hcy + 5], fill=(10, 5, 5, 255))
    draw.rectangle([hcx - 4, hcy - 10, hcx - 2, hcy + 4], fill=(255, 240, 220, 200))
    # Teeth
    for tx in range(hcx + 14, hcx + 50, 10):
        draw.polygon([(tx, hcy + 10), (tx + 5, hcy + 22), (tx + 9, hcy + 10)], fill=body_l)

    # Breath attack
    if breath:
        bx_start, by_start = hcx + 50, hcy + 2
        for i in range(6):
            bx = bx_start + i * 14
            by_c = by_start + int(3 * math.sin(i * 0.8))
            r = 18 - i * 1.5
            alpha = 220 - i * 25
            col = breath_col if i < 3 else breath_col2
            draw.ellipse([bx - r, by_c - r * 0.7, bx + r, by_c + r * 0.7],
                         fill=(*col[:3], int(alpha)))
        # Core glow
        draw.ellipse([bx_start - 8, by_start - 6, bx_start + 8, by_start + 6],
                     fill=(255, 255, 220, 240))


# ──────────────────────────────────────────────
# FIRE DRAGON
# ──────────────────────────────────────────────

FD_BODY    = (185, 50, 20, 255)
FD_BODY_D  = (100, 22, 8, 255)
FD_BODY_L  = (240, 160, 80, 255)
FD_WING    = (150, 35, 15, 200)
FD_WING_D  = (80, 15, 5, 200)
FD_EYE     = (255, 200, 0, 255)
FD_HORN    = (220, 165, 55, 255)
FD_BREATH  = (255, 120, 0, 255)
FD_BREATH2 = (255, 60, 0, 255)

def fire_dragon_idle(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    bob = -5 if frame_idx == 0 else 5
    draw_dragon_base(d, 128, 70 + bob,
                     FD_BODY, FD_BODY_D, FD_BODY_L,
                     FD_WING, FD_WING_D, FD_EYE, FD_HORN,
                     FD_BREATH, FD_BREATH2,
                     wing_up=(frame_idx == 0))
    return img

def fire_dragon_attack(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_dragon_base(d, 118, 70,
                     FD_BODY, FD_BODY_D, FD_BODY_L,
                     FD_WING, FD_WING_D, FD_EYE, FD_HORN,
                     FD_BREATH, FD_BREATH2,
                     wing_up=True, breath=(frame_idx == 1))
    if frame_idx == 1:
        # Extra fire glow
        for i in range(4):
            d.ellipse([15 + i*8, 125 + i*6, 55 + i*8, 155 + i*6],
                      fill=(*FD_BREATH[:3], 100 - i*18))
    return img

def fire_dragon_hit(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_dragon_base(d, 118, 70,
                     FD_BODY, FD_BODY_D, FD_BODY_L,
                     FD_WING, FD_WING_D, FD_EYE, FD_HORN,
                     FD_BREATH, FD_BREATH2, hit=True)
    flash = Image.new("RGBA", (FRAME_W, FRAME_H), (0, 0, 0, 0))
    fd = ImageDraw.Draw(flash)
    fd.ellipse([10, 10, 246, 246], fill=(255, 200, 180, 70))
    return Image.alpha_composite(img, flash)

def fire_dragon_dead(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_dragon_base(d, 128, 70,
                     FD_BODY, FD_BODY_D, FD_BODY_L,
                     FD_WING, FD_WING_D, FD_EYE, FD_HORN,
                     FD_BREATH, FD_BREATH2, dead=True)
    return img

def make_fire_dragon():
    strip = new_strip()
    frames = [fire_dragon_idle(0), fire_dragon_idle(1),
              fire_dragon_attack(0), fire_dragon_attack(1),
              fire_dragon_hit(0), fire_dragon_hit(1),
              fire_dragon_dead(0), fire_dragon_dead(1)]
    for i, f in enumerate(frames):
        place_frame(strip, f, i)
    return strip


# ──────────────────────────────────────────────
# ICE DRAGON
# ──────────────────────────────────────────────

ID_BODY    = (100, 170, 215, 255)
ID_BODY_D  = (50, 95, 135, 255)
ID_BODY_L  = (200, 235, 255, 255)
ID_WING    = (80, 148, 195, 180)
ID_WING_D  = (40, 80, 120, 180)
ID_EYE     = (200, 240, 255, 255)
ID_HORN    = (220, 240, 255, 255)
ID_BREATH  = (160, 220, 255, 255)
ID_BREATH2 = (220, 245, 255, 255)

def draw_ice_dragon_extras(draw, cx, cy, wing_up=True):
    """Add ice-specific crystal spines."""
    # Crystal spines along back
    spine_pts = [
        (cx - 18, cy + 10), (cx - 30, cy + 18), (cx - 42, cy + 28),
        (cx - 28, cy - 8), (cx - 14, cy - 25),
    ]
    for sx, sy in spine_pts:
        h = 18 + (sx % 8)
        draw.polygon([(sx - 5, sy), (sx, sy - h), (sx + 5, sy)], fill=ID_BODY_D)
        draw.polygon([(sx - 3, sy), (sx, sy - h + 4), (sx + 3, sy)], fill=ID_HORN)

def ice_dragon_idle(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    bob = -5 if frame_idx == 0 else 5
    draw_dragon_base(d, 128, 70 + bob,
                     ID_BODY, ID_BODY_D, ID_BODY_L,
                     ID_WING, ID_WING_D, ID_EYE, ID_HORN,
                     ID_BREATH, ID_BREATH2,
                     wing_up=(frame_idx == 0))
    draw_ice_dragon_extras(d, 128, 70 + bob, wing_up=(frame_idx == 0))
    return img

def ice_dragon_attack(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_dragon_base(d, 118, 70,
                     ID_BODY, ID_BODY_D, ID_BODY_L,
                     ID_WING, ID_WING_D, ID_EYE, ID_HORN,
                     ID_BREATH, ID_BREATH2,
                     wing_up=True, breath=(frame_idx == 1))
    draw_ice_dragon_extras(d, 118, 70)
    if frame_idx == 1:
        # Frost crystals emanating
        for i in range(5):
            ang = math.radians(-10 + i * 8)
            fx = int(58 + i * 22 * math.cos(ang))
            fy = int(132 + i * 22 * math.sin(ang))
            size = 8 - i
            d.polygon([(fx, fy - size), (fx + size, fy), (fx, fy + size), (fx - size, fy)],
                      fill=(*ID_HORN[:3], 200 - i * 30))
    return img

def ice_dragon_hit(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_dragon_base(d, 118, 70,
                     ID_BODY, ID_BODY_D, ID_BODY_L,
                     ID_WING, ID_WING_D, ID_EYE, ID_HORN,
                     ID_BREATH, ID_BREATH2, hit=True)
    draw_ice_dragon_extras(d, 118, 70)
    flash = Image.new("RGBA", (FRAME_W, FRAME_H), (0, 0, 0, 0))
    fd = ImageDraw.Draw(flash)
    fd.ellipse([10, 10, 246, 246], fill=(200, 230, 255, 70))
    return Image.alpha_composite(img, flash)

def ice_dragon_dead(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_dragon_base(d, 128, 70,
                     ID_BODY, ID_BODY_D, ID_BODY_L,
                     ID_WING, ID_WING_D, ID_EYE, ID_HORN,
                     ID_BREATH, ID_BREATH2, dead=True)
    return img

def make_ice_dragon():
    strip = new_strip()
    frames = [ice_dragon_idle(0), ice_dragon_idle(1),
              ice_dragon_attack(0), ice_dragon_attack(1),
              ice_dragon_hit(0), ice_dragon_hit(1),
              ice_dragon_dead(0), ice_dragon_dead(1)]
    for i, f in enumerate(frames):
        place_frame(strip, f, i)
    return strip


# ──────────────────────────────────────────────
# LIGHTNING DRAGON
# ──────────────────────────────────────────────

LD_BODY    = (200, 185, 55, 255)
LD_BODY_D  = (110, 98, 20, 255)
LD_BODY_L  = (245, 240, 160, 255)
LD_WING    = (155, 80, 200, 200)
LD_WING_D  = (90, 40, 130, 200)
LD_EYE     = (200, 240, 255, 255)
LD_HORN    = (245, 245, 100, 255)
LD_BREATH  = (200, 200, 255, 255)
LD_BREATH2 = (255, 255, 100, 255)
LD_BOLT    = (255, 250, 150, 255)

def draw_lightning_bolts(draw, cx, cy, count=5):
    """Draw crackling lightning arcs around the dragon."""
    for i in range(count):
        ang = math.radians(i * 72 + 18)
        dist = 80 + (i % 2) * 20
        bx1 = cx + int(50 * math.cos(ang))
        by1 = cy + int(50 * math.sin(ang))
        bx2 = cx + int(dist * math.cos(ang))
        by2 = cy + int(dist * math.sin(ang))
        # Jagged bolt
        pts = [(bx1, by1)]
        steps = 4
        for s in range(1, steps):
            t = s / steps
            mx = int(bx1 + t*(bx2-bx1)) + (8 if s%2==0 else -8)
            my = int(by1 + t*(by2-by1)) + (8 if s%2==1 else -8)
            pts.append((mx, my))
        pts.append((bx2, by2))
        draw.line(pts, fill=(*LD_BOLT[:3], 160), width=3)
        draw.line(pts, fill=(255, 255, 255, 220), width=1)
        # Spark at tip
        draw.ellipse([bx2 - 4, by2 - 4, bx2 + 4, by2 + 4], fill=(*LD_BOLT[:3], 200))

def lightning_dragon_idle(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    bob = -5 if frame_idx == 0 else 5
    draw_dragon_base(d, 128, 70 + bob,
                     LD_BODY, LD_BODY_D, LD_BODY_L,
                     LD_WING, LD_WING_D, LD_EYE, LD_HORN,
                     LD_BREATH, LD_BREATH2,
                     wing_up=(frame_idx == 0))
    draw_lightning_bolts(d, 128, 140 + bob, count=4 if frame_idx==0 else 5)
    return img

def lightning_dragon_attack(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_dragon_base(d, 118, 70,
                     LD_BODY, LD_BODY_D, LD_BODY_L,
                     LD_WING, LD_WING_D, LD_EYE, LD_HORN,
                     LD_BREATH, LD_BREATH2,
                     wing_up=True, breath=(frame_idx == 1))
    draw_lightning_bolts(d, 118, 140, count=6)
    if frame_idx == 1:
        # Massive bolt firing right
        bolt_pts = [(55, 132)]
        for i in range(6):
            bx = 55 + i * 28
            by = 132 + (10 if i%2==0 else -10)
            bolt_pts.append((bx, by))
        d.line(bolt_pts, fill=(*LD_BOLT[:3], 220), width=5)
        d.line(bolt_pts, fill=(255, 255, 255, 240), width=2)
    return img

def lightning_dragon_hit(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_dragon_base(d, 118, 70,
                     LD_BODY, LD_BODY_D, LD_BODY_L,
                     LD_WING, LD_WING_D, LD_EYE, LD_HORN,
                     LD_BREATH, LD_BREATH2, hit=True)
    draw_lightning_bolts(d, 118, 140, count=3)
    flash = Image.new("RGBA", (FRAME_W, FRAME_H), (0, 0, 0, 0))
    fd = ImageDraw.Draw(flash)
    fd.ellipse([10, 10, 246, 246], fill=(255, 255, 200, 70))
    return Image.alpha_composite(img, flash)

def lightning_dragon_dead(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_dragon_base(d, 128, 70,
                     LD_BODY, LD_BODY_D, LD_BODY_L,
                     LD_WING, LD_WING_D, LD_EYE, LD_HORN,
                     LD_BREATH, LD_BREATH2, dead=True)
    return img

def make_lightning_dragon():
    strip = new_strip()
    frames = [lightning_dragon_idle(0), lightning_dragon_idle(1),
              lightning_dragon_attack(0), lightning_dragon_attack(1),
              lightning_dragon_hit(0), lightning_dragon_hit(1),
              lightning_dragon_dead(0), lightning_dragon_dead(1)]
    for i, f in enumerate(frames):
        place_frame(strip, f, i)
    return strip


# ──────────────────────────────────────────────
# SHADOW DRAGON
# ──────────────────────────────────────────────

SD_BODY    = (45, 20, 65, 255)
SD_BODY_D  = (15, 5, 25, 255)
SD_BODY_L  = (110, 55, 150, 255)
SD_WING    = (30, 10, 48, 210)
SD_WING_D  = (10, 2, 18, 210)
SD_EYE     = (200, 0, 255, 255)
SD_HORN    = (80, 40, 110, 255)
SD_BREATH  = (120, 0, 200, 255)
SD_BREATH2 = (60, 0, 100, 255)
SD_VOID    = (20, 0, 40, 200)
SD_AURA    = (55, 0, 90, 120)

def draw_shadow_dragon_aura(draw, cx, cy):
    """Shadowy void tendrils and aura."""
    # Outer void glow
    for r in [105, 90, 75]:
        alpha = 30 + (105 - r)
        draw.ellipse([cx - r, cy - r + 20, cx + r, cy + r + 80],
                     fill=(*SD_VOID[:3], alpha))
    # Shadow tendrils
    for i in range(6):
        ang = math.radians(i * 60)
        dist = 95
        tx = cx + int(dist * math.cos(ang))
        ty = cy + 70 + int(dist * 0.5 * math.sin(ang))
        pts = [(cx, cy + 70)]
        for s in range(1, 5):
            t = s / 4
            mx = int(cx + t*(tx-cx)) + (12 if s%2==0 else -12)
            my = int(cy + 70 + t*(ty-cy-70)) + (6 if s%2==1 else -6)
            pts.append((mx, my))
        pts.append((tx, ty))
        draw.line(pts, fill=(*SD_AURA[:3], 80), width=4)

def shadow_dragon_idle(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    bob = -5 if frame_idx == 0 else 5
    draw_shadow_dragon_aura(d, 128, 70 + bob)
    draw_dragon_base(d, 128, 70 + bob,
                     SD_BODY, SD_BODY_D, SD_BODY_L,
                     SD_WING, SD_WING_D, SD_EYE, SD_HORN,
                     SD_BREATH, SD_BREATH2,
                     wing_up=(frame_idx == 0))
    return img

def shadow_dragon_attack(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_shadow_dragon_aura(d, 118, 70)
    draw_dragon_base(d, 118, 70,
                     SD_BODY, SD_BODY_D, SD_BODY_L,
                     SD_WING, SD_WING_D, SD_EYE, SD_HORN,
                     SD_BREATH, SD_BREATH2,
                     wing_up=True, breath=(frame_idx == 1))
    if frame_idx == 1:
        # Void pulse expanding outward
        for i in range(4):
            r = 14 + i * 16
            d.ellipse([55 + (i*4) - r, 132 - r, 55 + (i*4) + r, 132 + r],
                      fill=(*SD_AURA[:3], 100 - i*18))
    return img

def shadow_dragon_hit(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_shadow_dragon_aura(d, 118, 70)
    draw_dragon_base(d, 118, 70,
                     SD_BODY, SD_BODY_D, SD_BODY_L,
                     SD_WING, SD_WING_D, SD_EYE, SD_HORN,
                     SD_BREATH, SD_BREATH2, hit=True)
    flash = Image.new("RGBA", (FRAME_W, FRAME_H), (0, 0, 0, 0))
    fd = ImageDraw.Draw(flash)
    fd.ellipse([10, 10, 246, 246], fill=(200, 180, 255, 65))
    return Image.alpha_composite(img, flash)

def shadow_dragon_dead(frame_idx):
    img = new_frame()
    d = ImageDraw.Draw(img)
    draw_dragon_base(d, 128, 70,
                     SD_BODY, SD_BODY_D, SD_BODY_L,
                     SD_WING, SD_WING_D, SD_EYE, SD_HORN,
                     SD_BREATH, SD_BREATH2, dead=True)
    # Fading void wisps
    for i in range(3):
        d.ellipse([60 + i*30, 120 + i*10, 100 + i*30, 160 + i*10],
                  fill=(*SD_AURA[:3], 60 - i*15))
    return img

def make_shadow_dragon():
    strip = new_strip()
    frames = [shadow_dragon_idle(0), shadow_dragon_idle(1),
              shadow_dragon_attack(0), shadow_dragon_attack(1),
              shadow_dragon_hit(0), shadow_dragon_hit(1),
              shadow_dragon_dead(0), shadow_dragon_dead(1)]
    for i, f in enumerate(frames):
        place_frame(strip, f, i)
    return strip


# ──────────────────────────────────────────────
# GENERATE ALL EXTENDED SPRITES
# ──────────────────────────────────────────────

MONSTERS_EXTENDED = [
    ("cave_rat",        make_cave_rat),
    ("rat_guard",       make_rat_guard),
    ("mushroom",        make_mushroom),
    ("cave_troll",      make_cave_troll),
    ("shadow_knight",   make_shadow_knight),
    ("fire_dragon",     make_fire_dragon),
    ("ice_dragon",      make_ice_dragon),
    ("lightning_dragon", make_lightning_dragon),
    ("shadow_dragon",   make_shadow_dragon),
]

if __name__ == "__main__":
    import sys
    targets = sys.argv[1:] if len(sys.argv) > 1 else [m[0] for m in MONSTERS_EXTENDED]
    monster_map = {m[0]: m[1] for m in MONSTERS_EXTENDED}

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

    print("\nAll extended monster sprites generated successfully.")
