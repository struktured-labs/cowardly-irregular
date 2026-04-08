"""
Overworld walking sprite sheet generator for: cleric, mage, rogue, bard.
128x128 canvas, 4x4 grid of 32x32 frames. Same approach as gen_fighter_overworld.py.

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
os.makedirs(OUT_DIR, exist_ok=True)

T  = (0, 0, 0, 0)      # transparent
OL = (26, 24, 32, 255)  # outline near-black


def put(px, x, y, c):
    if 0 <= x < 128 and 0 <= y < 128:
        px[x, y] = c


def frame_origin(col, row):
    return col * 32, row * 32


def dp(px, ox, oy, pixels):
    for x, y, c in pixels:
        put(px, ox + x, oy + y, c)


# ─────────────────────────────────────────────────────────────────────────────
# SHARED LEG HELPERS  (called with per-character leg colors)
# Body zone: x 8..23, head y 3..12, body y 13..22, legs y 23..30
# ─────────────────────────────────────────────────────────────────────────────

def _legs_stand_front(px, ox, oy, LC, LCD, BC, BCM):
    """Generic standing legs, front view."""
    dp(px, ox, oy, [
        (11,23,OL),(12,23,LC),(13,23,LC),(14,23,OL),
        (11,24,OL),(12,24,LCD),(13,24,LC),(14,24,OL),
        (17,23,OL),(18,23,LC),(19,23,LC),(20,23,OL),
        (17,24,OL),(18,24,LC),(19,24,LCD),(20,24,OL),
        (15,23,OL),(16,23,OL),
        (11,25,OL),(12,25,LC),(13,25,LC),(14,25,OL),
        (11,26,OL),(12,26,LC),(13,26,LC),(14,26,OL),
        (17,25,OL),(18,25,LC),(19,25,LC),(20,25,OL),
        (17,26,OL),(18,26,LC),(19,26,LC),(20,26,OL),
        (10,27,OL),(11,27,BC),(12,27,BC),(13,27,BC),(14,27,BC),(15,27,OL),
        (10,28,OL),(11,28,BCM),(12,28,BC),(13,28,BC),(14,28,BC),(15,28,OL),
        (10,29,OL),(11,29,OL),(12,29,OL),(13,29,OL),(14,29,OL),(15,29,OL),
        (16,27,OL),(17,27,BC),(18,27,BC),(19,27,BC),(20,27,BC),(21,27,OL),
        (16,28,OL),(17,28,BC),(18,28,BC),(19,28,BC),(20,28,BCM),(21,28,OL),
        (16,29,OL),(17,29,OL),(18,29,OL),(19,29,OL),(20,29,OL),(21,29,OL),
    ])


def _legs_stride_right_front(px, ox, oy, LC, LCD, BC, BCM):
    dp(px, ox, oy, [
        (18,23,OL),(19,23,LC),(20,23,LC),(21,23,OL),
        (18,24,OL),(19,24,LC),(20,24,LCD),(21,24,OL),
        (18,25,OL),(19,25,LC),(20,25,LC),(21,25,OL),
        (18,26,OL),(19,26,LC),(20,26,LC),(21,26,OL),
        (17,27,OL),(18,27,OL),(19,27,BC),(20,27,BC),(21,27,BC),(22,27,OL),
        (17,28,OL),(18,28,BC),(19,28,BCM),(20,28,BC),(21,28,BC),(22,28,OL),
        (17,29,OL),(18,29,OL),(19,29,OL),(20,29,OL),(21,29,OL),(22,29,OL),
        (9,22,OL),(10,22,LC),(11,22,LCD),(12,22,OL),
        (9,23,OL),(10,23,LCD),(11,23,LCD),(12,23,OL),
        (9,24,OL),(10,24,LCD),(11,24,LCD),(12,24,OL),
        (9,25,OL),(10,25,LCD),(11,25,LCD),(12,25,OL),
        (9,26,OL),(10,26,BC),(11,26,BC),(12,26,OL),
        (9,27,OL),(10,27,OL),(11,27,OL),(12,27,OL),
    ])


def _legs_stride_left_front(px, ox, oy, LC, LCD, BC, BCM):
    dp(px, ox, oy, [
        (9,23,OL),(10,23,LC),(11,23,LC),(12,23,OL),
        (9,24,OL),(10,24,LCD),(11,24,LC),(12,24,OL),
        (9,25,OL),(10,25,LC),(11,25,LC),(12,25,OL),
        (9,26,OL),(10,26,LC),(11,26,LC),(12,26,OL),
        (8,27,OL),(9,27,OL),(10,27,BC),(11,27,BC),(12,27,BC),(13,27,OL),
        (8,28,OL),(9,28,BC),(10,28,BCM),(11,28,BC),(12,28,BC),(13,28,OL),
        (8,29,OL),(9,29,OL),(10,29,OL),(11,29,OL),(12,29,OL),(13,29,OL),
        (19,22,OL),(20,22,LC),(21,22,LCD),(22,22,OL),
        (19,23,OL),(20,23,LCD),(21,23,LCD),(22,23,OL),
        (19,24,OL),(20,24,LCD),(21,24,LCD),(22,24,OL),
        (19,25,OL),(20,25,LCD),(21,25,LCD),(22,25,OL),
        (19,26,OL),(20,26,BC),(21,26,BC),(22,26,OL),
        (19,27,OL),(20,27,OL),(21,27,OL),(22,27,OL),
    ])


def _legs_stand_back(px, ox, oy, LC, LCD, BC, BCM):
    dp(px, ox, oy, [
        (11,23,OL),(12,23,LCD),(13,23,LCD),(14,23,OL),
        (11,24,OL),(12,24,LCD),(13,24,LCD),(14,24,OL),
        (17,23,OL),(18,23,LCD),(19,23,LCD),(20,23,OL),
        (17,24,OL),(18,24,LCD),(19,24,LCD),(20,24,OL),
        (15,23,OL),(16,23,OL),
        (11,25,OL),(12,25,LCD),(13,25,LCD),(14,25,OL),
        (11,26,OL),(12,26,LCD),(13,26,LCD),(14,26,OL),
        (17,25,OL),(18,25,LCD),(19,25,LCD),(20,25,OL),
        (17,26,OL),(18,26,LCD),(19,26,LCD),(20,26,OL),
        (10,27,OL),(11,27,BC),(12,27,BC),(13,27,BC),(14,27,BC),(15,27,OL),
        (10,28,OL),(11,28,BCM),(12,28,BC),(13,28,BC),(14,28,BC),(15,28,OL),
        (10,29,OL),(11,29,OL),(12,29,OL),(13,29,OL),(14,29,OL),(15,29,OL),
        (16,27,OL),(17,27,BC),(18,27,BC),(19,27,BC),(20,27,BC),(21,27,OL),
        (16,28,OL),(17,28,BC),(18,28,BC),(19,28,BC),(20,28,BCM),(21,28,OL),
        (16,29,OL),(17,29,OL),(18,29,OL),(19,29,OL),(20,29,OL),(21,29,OL),
    ])


def _legs_stride_right_back(px, ox, oy, LC, LCD, BC, BCM):
    dp(px, ox, oy, [
        (18,23,OL),(19,23,LCD),(20,23,LC),(21,23,OL),
        (18,24,OL),(19,24,LCD),(20,24,LC),(21,24,OL),
        (18,25,OL),(19,25,LCD),(20,25,LC),(21,25,OL),
        (18,26,OL),(19,26,LCD),(20,26,LC),(21,26,OL),
        (17,27,OL),(18,27,OL),(19,27,BC),(20,27,BC),(21,27,BC),(22,27,OL),
        (17,28,OL),(18,28,BC),(19,28,BCM),(20,28,BC),(21,28,BC),(22,28,OL),
        (17,29,OL),(18,29,OL),(19,29,OL),(20,29,OL),(21,29,OL),(22,29,OL),
        (9,22,OL),(10,22,LCD),(11,22,LCD),(12,22,OL),
        (9,23,OL),(10,23,LCD),(11,23,LCD),(12,23,OL),
        (9,24,OL),(10,24,LCD),(11,24,LCD),(12,24,OL),
        (9,25,OL),(10,25,LCD),(11,25,LCD),(12,25,OL),
        (9,26,OL),(10,26,BC),(11,26,BC),(12,26,OL),
        (9,27,OL),(10,27,OL),(11,27,OL),(12,27,OL),
    ])


def _legs_stride_left_back(px, ox, oy, LC, LCD, BC, BCM):
    dp(px, ox, oy, [
        (9,23,OL),(10,23,LC),(11,23,LCD),(12,23,OL),
        (9,24,OL),(10,24,LC),(11,24,LCD),(12,24,OL),
        (9,25,OL),(10,25,LC),(11,25,LCD),(12,25,OL),
        (9,26,OL),(10,26,LC),(11,26,LCD),(12,26,OL),
        (8,27,OL),(9,27,OL),(10,27,BC),(11,27,BC),(12,27,BC),(13,27,OL),
        (8,28,OL),(9,28,BC),(10,28,BCM),(11,28,BC),(12,28,BC),(13,28,OL),
        (8,29,OL),(9,29,OL),(10,29,OL),(11,29,OL),(12,29,OL),(13,29,OL),
        (19,22,OL),(20,22,LCD),(21,22,LCD),(22,22,OL),
        (19,23,OL),(20,23,LCD),(21,23,LCD),(22,23,OL),
        (19,24,OL),(20,24,LCD),(21,24,LCD),(22,24,OL),
        (19,25,OL),(20,25,LCD),(21,25,LCD),(22,25,OL),
        (19,26,OL),(20,26,BC),(21,26,BC),(22,26,OL),
        (19,27,OL),(20,27,OL),(21,27,OL),(22,27,OL),
    ])


def _legs_side_stand_L(px, ox, oy, LC, LCD, BC, BCM):
    dp(px, ox, oy, [
        (11,23,OL),(12,23,LC),(13,23,LC),(14,23,OL),
        (11,24,OL),(12,24,LCD),(13,24,LC),(14,24,OL),
        (11,25,OL),(12,25,LC),(13,25,LC),(14,25,OL),
        (11,26,OL),(12,26,LC),(13,26,LC),(14,26,OL),
        (10,27,OL),(11,27,BC),(12,27,BC),(13,27,BC),(14,27,BC),(15,27,OL),
        (10,28,OL),(11,28,BCM),(12,28,BC),(13,28,BC),(14,28,BC),(15,28,BC),(16,28,OL),
        (10,29,OL),(11,29,OL),(12,29,OL),(13,29,OL),(14,29,OL),(15,29,OL),(16,29,OL),
        (15,24,OL),(16,24,LCD),(17,24,LCD),(18,24,OL),
        (15,25,OL),(16,25,LCD),(17,25,LCD),(18,25,OL),
        (15,26,OL),(16,26,LCD),(17,26,LCD),(18,26,OL),
        (15,27,OL),(16,27,BC),(17,27,BC),(18,27,BC),(19,27,OL),
        (15,28,OL),(16,28,BC),(17,28,BC),(18,28,BC),(19,28,OL),
        (15,29,OL),(16,29,OL),(17,29,OL),(18,29,OL),(19,29,OL),
    ])


def _legs_side_stand_R(px, ox, oy, LC, LCD, BC, BCM):
    dp(px, ox, oy, [
        (17,23,OL),(18,23,LC),(19,23,LC),(20,23,OL),
        (17,24,OL),(18,24,LC),(19,24,LCD),(20,24,OL),
        (17,25,OL),(18,25,LC),(19,25,LC),(20,25,OL),
        (17,26,OL),(18,26,LC),(19,26,LC),(20,26,OL),
        (16,27,OL),(17,27,BC),(18,27,BC),(19,27,BC),(20,27,BC),(21,27,OL),
        (16,28,OL),(17,28,BC),(18,28,BCM),(19,28,BC),(20,28,BC),(21,28,OL),
        (16,29,OL),(17,29,OL),(18,29,OL),(19,29,OL),(20,29,OL),(21,29,OL),
        (13,24,OL),(14,24,LCD),(15,24,LCD),(16,24,OL),
        (13,25,OL),(14,25,LCD),(15,25,LCD),(16,25,OL),
        (13,26,OL),(14,26,LCD),(15,26,LCD),(16,26,OL),
        (12,27,OL),(13,27,BC),(14,27,BC),(15,27,BC),(16,27,OL),
        (12,28,OL),(13,28,BC),(14,28,BC),(15,28,BC),(16,28,OL),
        (12,29,OL),(13,29,OL),(14,29,OL),(15,29,OL),(16,29,OL),
    ])


def _legs_side_forward_L(px, ox, oy, LC, LCD, BC, BCM):
    dp(px, ox, oy, [
        (9,24,OL),(10,24,LC),(11,24,LC),(12,24,OL),
        (9,25,OL),(10,25,LCD),(11,25,LC),(12,25,OL),
        (9,26,OL),(10,26,LC),(11,26,LC),(12,26,OL),
        (9,27,OL),(10,27,LC),(11,27,LC),(12,27,OL),
        (8,28,OL),(9,28,OL),(10,28,BC),(11,28,BC),(12,28,BC),(13,28,OL),
        (7,29,OL),(8,29,BC),(9,29,BCM),(10,29,BC),(11,29,BC),(12,29,OL),(13,29,OL),
        (16,23,OL),(17,23,LCD),(18,23,LCD),(19,23,OL),
        (16,24,OL),(17,24,LCD),(18,24,LCD),(19,24,OL),
        (16,25,OL),(17,25,LCD),(18,25,LCD),(19,25,OL),
        (16,26,OL),(17,26,BC),(18,26,BC),(19,26,OL),
        (16,27,OL),(17,27,OL),(18,27,OL),(19,27,OL),
    ])


def _legs_side_back_L(px, ox, oy, LC, LCD, BC, BCM):
    dp(px, ox, oy, [
        (12,23,OL),(13,23,LC),(14,23,LC),(15,23,OL),
        (12,24,OL),(13,24,LCD),(14,24,LC),(15,24,OL),
        (12,25,OL),(13,25,LC),(14,25,LC),(15,25,OL),
        (12,26,OL),(13,26,LC),(14,26,LC),(15,26,OL),
        (11,27,OL),(12,27,BC),(13,27,BC),(14,27,BC),(15,27,OL),
        (11,28,OL),(12,28,BCM),(13,28,BC),(14,28,BC),(15,28,BC),(16,28,OL),
        (11,29,OL),(12,29,OL),(13,29,OL),(14,29,OL),(15,29,OL),(16,29,OL),
        (17,23,OL),(18,23,LCD),(19,23,LCD),(20,23,OL),
        (17,24,OL),(18,24,LCD),(19,24,LCD),(20,24,OL),
        (17,25,OL),(18,25,LCD),(19,25,LCD),(20,25,OL),
        (17,26,OL),(18,26,BC),(19,26,BC),(20,26,OL),
        (17,27,OL),(18,27,OL),(19,27,OL),(20,27,OL),
    ])


def _legs_side_forward_R(px, ox, oy, LC, LCD, BC, BCM):
    dp(px, ox, oy, [
        (19,24,OL),(20,24,LC),(21,24,LC),(22,24,OL),
        (19,25,OL),(20,25,LC),(21,25,LCD),(22,25,OL),
        (19,26,OL),(20,26,LC),(21,26,LC),(22,26,OL),
        (19,27,OL),(20,27,LC),(21,27,LC),(22,27,OL),
        (19,28,OL),(20,28,OL),(21,28,BC),(22,28,BC),(23,28,BC),(24,28,OL),
        (19,29,OL),(20,29,BC),(21,29,BCM),(22,29,BC),(23,29,BC),(24,29,OL),
        (12,23,OL),(13,23,LCD),(14,23,LCD),(15,23,OL),
        (12,24,OL),(13,24,LCD),(14,24,LCD),(15,24,OL),
        (12,25,OL),(13,25,LCD),(14,25,LCD),(15,25,OL),
        (12,26,OL),(13,26,BC),(14,26,BC),(15,26,OL),
        (12,27,OL),(13,27,OL),(14,27,OL),(15,27,OL),
    ])


def _legs_side_back_R(px, ox, oy, LC, LCD, BC, BCM):
    dp(px, ox, oy, [
        (16,23,OL),(17,23,LC),(18,23,LC),(19,23,OL),
        (16,24,OL),(17,24,LCD),(18,24,LC),(19,24,OL),
        (16,25,OL),(17,25,LC),(18,25,LC),(19,25,OL),
        (16,26,OL),(17,26,LC),(18,26,LC),(19,26,OL),
        (15,27,OL),(16,27,BC),(17,27,BC),(18,27,BC),(19,27,BC),(20,27,OL),
        (15,28,OL),(16,28,OL),(17,28,BC),(18,28,BCM),(19,28,BC),(20,28,BC),(21,28,OL),
        (15,29,OL),(16,29,OL),(17,29,OL),(18,29,OL),(19,29,OL),(20,29,OL),(21,29,OL),
        (11,23,OL),(12,23,LCD),(13,23,LCD),(14,23,OL),
        (11,24,OL),(12,24,LCD),(13,24,LCD),(14,24,OL),
        (11,25,OL),(12,25,LCD),(13,25,LCD),(14,25,OL),
        (11,26,OL),(12,26,BC),(13,26,BC),(14,26,OL),
        (11,27,OL),(12,27,OL),(13,27,OL),(14,27,OL),
    ])


# ─────────────────────────────────────────────────────────────────────────────
# SHARED ARM HELPERS  (SC=sleeve color, SCD=sleeve dark, SK=skin, SKD=skin dark)
# ─────────────────────────────────────────────────────────────────────────────

def _arm_left_front(px, ox, oy, SC, SCD, SK, SKD, y_off=0):
    """Left arm, front view. y_off: 0=rest, 1=forward swing (down)."""
    b = 16 + y_off
    dp(px, ox, oy, [
        (8,b,OL),(9,b,SC),(10,b,SCD),
        (8,b+1,OL),(9,b+1,SC),(10,b+1,SCD),
        (8,b+2,OL),(9,b+2,SCD),(10,b+2,SCD),
        (8,b+3,OL),(9,b+3,SK),(10,b+3,SKD),
        (9,b+4,OL),(10,b+4,OL),
    ])

def _arm_right_front(px, ox, oy, SC, SCD, SK, SKD, y_off=0):
    """Right arm, front view."""
    b = 16 + y_off
    dp(px, ox, oy, [
        (21,b,SCD),(22,b,SC),(23,b,OL),
        (21,b+1,SCD),(22,b+1,SC),(23,b+1,OL),
        (21,b+2,SCD),(22,b+2,SCD),(23,b+2,OL),
        (21,b+3,SKD),(22,b+3,SK),(23,b+3,OL),
        (21,b+4,OL),(22,b+4,OL),
    ])

def _arm_left_back(px, ox, oy, SC, SCD, SK, SKD, y_off=0):
    """Left arm, back view (reversed shading)."""
    b = 16 + y_off
    dp(px, ox, oy, [
        (8,b,OL),(9,b,SCD),(10,b,SC),
        (8,b+1,OL),(9,b+1,SCD),(10,b+1,SC),
        (8,b+2,OL),(9,b+2,SCD),(10,b+2,SCD),
        (8,b+3,OL),(9,b+3,SKD),(10,b+3,SK),
        (9,b+4,OL),(10,b+4,OL),
    ])

def _arm_right_back(px, ox, oy, SC, SCD, SK, SKD, y_off=0):
    """Right arm, back view."""
    b = 16 + y_off
    dp(px, ox, oy, [
        (21,b,SC),(22,b,SCD),(23,b,OL),
        (21,b+1,SC),(22,b+1,SCD),(23,b+1,OL),
        (21,b+2,SCD),(22,b+2,SCD),(23,b+2,OL),
        (21,b+3,SK),(22,b+3,SKD),(23,b+3,OL),
        (21,b+4,OL),(22,b+4,OL),
    ])

def _arm_side_L(px, ox, oy, SC, SCD, SK, SKD, phase=0):
    """Near arm for left-facing side view. phase: 0=rest, 1=forward, -1=back."""
    if phase == 1:
        dp(px, ox, oy, [
            (9,16,OL),(10,16,SC),(11,16,SCD),
            (9,17,OL),(10,17,SCD),
            (9,18,OL),(10,18,SK),
            (9,19,OL),(10,19,OL),
        ])
    elif phase == -1:
        dp(px, ox, oy, [
            (11,15,SCD),(12,15,SCD),
            (11,16,SC),(12,16,SCD),
            (11,17,SK),(12,17,OL),
            (11,18,OL),
        ])
    else:
        dp(px, ox, oy, [
            (10,16,OL),(11,16,SC),
            (10,17,OL),(11,17,SCD),
            (10,18,OL),(11,18,SK),
            (10,19,OL),(11,19,OL),
        ])

def _arm_side_R(px, ox, oy, SC, SCD, SK, SKD, phase=0):
    """Near arm for right-facing side view."""
    if phase == 1:
        dp(px, ox, oy, [
            (20,16,SCD),(21,16,SC),(22,16,OL),
            (20,17,SCD),(22,17,OL),
            (21,18,SK),(22,18,OL),
            (21,19,OL),(22,19,OL),
        ])
    elif phase == -1:
        dp(px, ox, oy, [
            (19,15,SCD),(20,15,SCD),
            (19,16,SCD),(20,16,SC),
            (19,17,OL),(20,17,SK),
            (20,18,OL),
        ])
    else:
        dp(px, ox, oy, [
            (20,16,SC),(21,16,OL),
            (20,17,SCD),(21,17,OL),
            (20,18,SK),(21,18,OL),
            (20,19,OL),(21,19,OL),
        ])


# ═══════════════════════════════════════════════════════════════════════════
#  SAVE + UPSCALE helper
# ═══════════════════════════════════════════════════════════════════════════

def save_with_preview(img, out_path, preview_path, job_name):
    img.save(out_path)
    print(f"Saved: {out_path}")

    preview = img.resize((512, 512), Image.NEAREST)
    draw = ImageDraw.Draw(preview)
    for i in range(1, 4):
        draw.line([(i*128, 0), (i*128, 511)], fill=(80,80,80,180), width=1)
        draw.line([(0, i*128), (511, i*128)], fill=(80,80,80,180), width=1)
    labels = ["walk_down (front)", "walk_left", "walk_right", "walk_up (back)"]
    for row, lbl in enumerate(labels):
        draw.text((2, row*128+2), f"{job_name}: {lbl}", fill=(255,255,200,220))
    for row in range(4):
        for col in range(4):
            draw.text((col*128+2, row*128+118), str(col), fill=(200,200,255,200))
    preview.save(preview_path)
    print(f"Saved preview: {preview_path}")

    # Validate
    img_v = Image.open(out_path)
    assert img_v.size == (128, 128), f"Size mismatch: {img_v.size}"
    assert img_v.mode == "RGBA"
    arr = np.array(img_v)
    transparent_px = int(np.sum(arr[:,:,3] == 0))
    opaque_px      = int(np.sum(arr[:,:,3] == 255))
    total = 128*128
    print(f"Transparent: {transparent_px}/{total} ({100*transparent_px/total:.1f}%)")
    print(f"Opaque:      {opaque_px}/{total} ({100*opaque_px/total:.1f}%)")
    all_ok = True
    for row in range(4):
        for col in range(4):
            fx, fy = col*32, row*32
            frame = arr[fy:fy+32, fx:fx+32]
            opaque = int(np.sum(frame[:,:,3] == 255))
            tag = "OK" if opaque >= 60 else "WARN"
            if opaque < 60:
                all_ok = False
            print(f"  ({col},{row}): {opaque:3d} opaque  {tag}")
    if all_ok:
        print(f"\n{job_name}: All 16 frames validated OK.\n")
    else:
        print(f"\n{job_name}: WARNING — some frames may be sparse.\n")


# ═══════════════════════════════════════════════════════════════════════════════
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  CLERIC                                                                  ║
# ║  White hooded robes, golden tiara, staff, gentle expression              ║
# ╚══════════════════════════════════════════════════════════════════════════╝
# ═══════════════════════════════════════════════════════════════════════════════

def gen_cleric():
    # Palette
    WH  = (240, 235, 225, 255)   # white robe
    WHD = (200, 195, 185, 255)   # robe shadow
    WHH = (255, 252, 245, 255)   # robe highlight
    GD  = (200, 170,  60, 255)   # gold trim
    GDD = (140, 110,  30, 255)   # gold dark
    SK  = (230, 190, 150, 255)   # skin
    SKD = (190, 145, 110, 255)   # skin shadow
    PK  = (230, 180, 180, 255)   # soft pink cheek/lips
    HR  = (210, 205, 215, 255)   # silver-white hair
    HRD = (160, 155, 165, 255)   # hair shadow
    EY  = ( 80, 120, 180, 255)   # eye blue
    ST  = (180, 185, 200, 255)   # staff metal
    LC  = WH                     # leg color = robe
    LCD = WHD
    BC  = (100,  95,  85, 255)   # boot (sandal dark)
    BCM = (130, 125, 115, 255)   # boot mid

    img = Image.new("RGBA", (128, 128), T)
    px = img.load()

    # ── HEAD front ────────────────────────────────────────────────────────
    def head_front(ox, oy):
        dp(px, ox, oy, [
            # head outline
            (11,4,OL),(12,4,OL),(13,4,OL),(14,4,OL),(15,4,OL),(16,4,OL),(17,4,OL),(18,4,OL),(19,4,OL),(20,4,OL),
            (10,5,OL),(10,6,OL),(10,7,OL),(10,8,OL),(10,9,OL),(10,10,OL),(10,11,OL),
            (21,5,OL),(21,6,OL),(21,7,OL),(21,8,OL),(21,9,OL),(21,10,OL),(21,11,OL),
            (11,12,OL),(12,12,OL),(13,12,OL),(14,12,OL),(15,12,OL),(16,12,OL),(17,12,OL),(18,12,OL),(19,12,OL),(20,12,OL),
            *[(x,y,SK)  for y in range(5,12) for x in range(11,21)],
            *[(x,y,SKD) for y in range(9,12) for x in range(18,21)],
            # eyes
            (13,7,OL),(14,7,EY),(14,8,OL),
            (17,7,OL),(18,7,EY),(18,8,OL),
            # blush
            (13,9,PK),(14,9,PK),(17,9,PK),(18,9,PK),
            # mouth
            (15,10,OL),(16,10,OL),
        ])

    # Hood front — frames over head
    def hood_front(ox, oy):
        dp(px, ox, oy, [
            # hood brim across top of head y=3..5
            *[(x,3,WH) for x in range(10,22)],
            *[(x,4,WH) for x in range(10,22)],
            (9,4,OL),(9,5,OL),(9,6,OL),(22,4,OL),(22,5,OL),(22,6,OL),
            # hood sides draping down past head
            (9,5,WHD),(9,6,WHD),(9,7,WHD),(9,8,WHD),(9,9,WHD),
            (22,5,WHD),(22,6,WHD),(22,7,WHD),(22,8,WHD),(22,9,WHD),
            # cowl top peak
            (11,3,OL),(12,3,WH),(13,3,WH),(14,3,WH),(15,2,WH),(16,2,WH),(17,3,WH),(18,3,WH),(19,3,OL),
            (14,1,OL),(15,1,WH),(16,1,WHH),(17,1,OL),
            (15,0,OL),(16,0,OL),
            # tiara/crown row y=4
            *[(x,4,GD)  for x in range(12,20)],
            (11,4,GDD),(20,4,GDD),
            # tiara gem centre
            (15,3,GD),(16,3,GD),(15,4,GD),(16,4,GD),
            # tiara outline
            (11,4,OL),(20,4,OL),
        ])

    # Body front — robes (wide, flowing)
    def body_front(ox, oy):
        dp(px, ox, oy, [
            # neck
            (14,13,SKD),(15,13,SK),(16,13,SK),(17,13,SKD),
            # robe outline wide
            (10,13,OL),(10,14,OL),(10,15,OL),(10,16,OL),(10,17,OL),(10,18,OL),(10,19,OL),(10,20,OL),(10,21,OL),(10,22,OL),
            (21,13,OL),(21,14,OL),(21,15,OL),(21,16,OL),(21,17,OL),(21,18,OL),(21,19,OL),(21,20,OL),(21,21,OL),(21,22,OL),
            *[(x,13,OL) for x in range(11,21)],
            *[(x,22,OL) for x in range(11,21)],
            # robe fill
            *[(x,y,WH)  for y in range(14,22) for x in range(11,21)],
            # centre fold shadow
            *[(x,y,WHD) for y in range(14,22) for x in [15,16]],
            # left shadow edge
            *[(x,y,WHD) for y in range(14,22) for x in [11]],
            # right shadow edge
            *[(x,y,WHD) for y in range(14,22) for x in [20]],
            # gold hem at bottom
            *[(x,22,GD)  for x in range(12,20)],
            *[(x,21,GDD) for x in range(13,19)],
        ])

    # Staff front (held on right, crosses body)
    def staff_front(ox, oy):
        dp(px, ox, oy, [
            # thin vertical staff at x=22
            (22,10,ST),(22,11,ST),(22,12,ST),(22,13,ST),(22,14,ST),(22,15,ST),(22,16,ST),
            (22,17,ST),(22,18,ST),(22,19,ST),(22,20,ST),(22,21,ST),
            (23,10,OL),(23,11,OL),(21,10,OL),(21,22,OL),
            # glowing orb top
            (22,8,GD),(22,9,GD),(23,8,GD),(21,8,GD),
            (22,7,OL),(23,7,OL),(21,7,OL),(22,10,OL),
        ])

    # Hood back
    def hood_back(ox, oy):
        dp(px, ox, oy, [
            *[(x,3,WH)  for x in range(10,22)],
            *[(x,4,WH)  for x in range(10,22)],
            *[(x,5,WH)  for x in range(10,22)],
            (9,4,OL),(9,5,OL),(9,6,OL),(22,4,OL),(22,5,OL),(22,6,OL),
            (9,5,WHD),(9,6,WHD),(9,7,WHD),(9,8,WHD),(22,5,WHD),(22,6,WHD),(22,7,WHD),(22,8,WHD),
            (14,2,WH),(15,2,WHH),(16,2,WHH),(17,2,WH),
            (14,1,OL),(13,2,OL),(13,3,OL),(18,2,OL),(18,3,OL),(17,1,OL),
            # hair braid visible below hood
            *[(x,y,HR)  for y in range(6,12) for x in range(12,20)],
            *[(x,y,HRD) for y in range(8,12) for x in range(14,18)],
            (11,4,OL),(12,4,WH),(13,4,WH),(18,4,WH),(19,4,WH),(20,4,OL),
        ])

    def head_back(ox, oy):
        dp(px, ox, oy, [
            (11,4,OL),(12,4,OL),(13,4,OL),(14,4,OL),(15,4,OL),(16,4,OL),(17,4,OL),(18,4,OL),(19,4,OL),(20,4,OL),
            (10,5,OL),(10,6,OL),(10,7,OL),(10,8,OL),(10,9,OL),(10,10,OL),(10,11,OL),
            (21,5,OL),(21,6,OL),(21,7,OL),(21,8,OL),(21,9,OL),(21,10,OL),(21,11,OL),
            (11,12,OL),(12,12,OL),(13,12,OL),(14,12,OL),(15,12,OL),(16,12,OL),(17,12,OL),(18,12,OL),(19,12,OL),(20,12,OL),
            *[(x,y,HR)  for y in range(5,12) for x in range(11,21)],
            *[(x,y,HRD) for y in range(7,12) for x in range(13,19)],
        ])

    def body_back(ox, oy):
        dp(px, ox, oy, [
            (14,13,HRD),(15,13,HR),(16,13,HR),(17,13,HRD),
            (10,13,OL),(10,14,OL),(10,15,OL),(10,16,OL),(10,17,OL),(10,18,OL),(10,19,OL),(10,20,OL),(10,21,OL),(10,22,OL),
            (21,13,OL),(21,14,OL),(21,15,OL),(21,16,OL),(21,17,OL),(21,18,OL),(21,19,OL),(21,20,OL),(21,21,OL),(21,22,OL),
            *[(x,13,OL) for x in range(11,21)],
            *[(x,22,OL) for x in range(11,21)],
            *[(x,y,WHD) for y in range(14,22) for x in range(11,21)],
            # back centre highlight stripe
            *[(x,y,WH)  for y in range(14,20) for x in [15,16]],
            *[(x,22,GD)  for x in range(12,20)],
            *[(x,21,GDD) for x in range(13,19)],
        ])

    # Side head L
    def head_side_L(ox, oy):
        dp(px, ox, oy, [
            (12,4,OL),(13,4,OL),(14,4,OL),(15,4,OL),(16,4,OL),(17,4,OL),(18,4,OL),(19,4,OL),
            (11,5,OL),(11,6,OL),(11,7,OL),(11,8,OL),(11,9,OL),(11,10,OL),(11,11,OL),
            (20,5,OL),(20,6,OL),(20,7,OL),(20,8,OL),(20,9,OL),(20,10,OL),(20,11,OL),
            (12,12,OL),(13,12,OL),(14,12,OL),(15,12,OL),(16,12,OL),(17,12,OL),(18,12,OL),(19,12,OL),
            *[(x,y,SK)  for y in range(5,12) for x in range(12,20)],
            *[(x,y,SKD) for y in range(8,12) for x in range(17,20)],
            # nose protrudes left
            (11,7,SK),(10,7,SK),(10,8,OL),(11,8,OL),
            # eye
            (13,6,OL),(14,6,EY),(14,7,OL),
            (13,9,PK),
            (14,10,OL),
        ])

    def hood_side_L(ox, oy):
        dp(px, ox, oy, [
            *[(x,3,WH) for x in range(11,21)],
            *[(x,4,WH) for x in range(11,21)],
            (10,4,OL),(10,5,OL),(10,6,OL),(10,7,OL),(21,4,OL),(21,5,OL),(21,6,OL),
            (10,5,WHD),(10,6,WHD),(10,7,WHD),(10,8,WHD),
            (21,5,WHD),(21,6,WHD),
            # cowl fold left-side
            (12,2,WH),(13,2,WH),(11,3,WH),(11,4,WH),
            (11,2,OL),(13,1,OL),
            *[(x,4,GD) for x in range(12,20)],
            (11,4,GDD),(20,4,GDD),
        ])

    def body_side_L(ox, oy):
        dp(px, ox, oy, [
            (14,13,SKD),(15,13,SK),(16,13,SKD),
            (12,13,OL),(12,14,OL),(12,15,OL),(12,16,OL),(12,17,OL),(12,18,OL),(12,19,OL),(12,20,OL),(12,21,OL),(12,22,OL),
            (20,13,OL),(20,14,OL),(20,15,OL),(20,16,OL),(20,17,OL),(20,18,OL),(20,19,OL),(20,20,OL),(20,21,OL),(20,22,OL),
            *[(x,13,OL) for x in range(13,20)],
            *[(x,22,OL) for x in range(13,20)],
            *[(x,y,WH)  for y in range(14,22) for x in range(13,20)],
            *[(x,y,WHD) for y in range(14,22) for x in [13]],
            *[(x,y,WHD) for y in range(14,22) for x in [19]],
            *[(x,22,GD)  for x in range(13,20)],
            # staff side
            (21,12,ST),(21,13,ST),(21,14,ST),(21,15,ST),(21,16,ST),(21,17,ST),(21,18,ST),(21,19,ST),(21,20,ST),(21,21,ST),
            (22,12,OL),(20,12,OL),(21,22,OL),
        ])

    def head_side_R(ox, oy):
        dp(px, ox, oy, [
            (12,4,OL),(13,4,OL),(14,4,OL),(15,4,OL),(16,4,OL),(17,4,OL),(18,4,OL),(19,4,OL),
            (11,5,OL),(11,6,OL),(11,7,OL),(11,8,OL),(11,9,OL),(11,10,OL),(11,11,OL),
            (20,5,OL),(20,6,OL),(20,7,OL),(20,8,OL),(20,9,OL),(20,10,OL),(20,11,OL),
            (12,12,OL),(13,12,OL),(14,12,OL),(15,12,OL),(16,12,OL),(17,12,OL),(18,12,OL),(19,12,OL),
            *[(x,y,SK)  for y in range(5,12) for x in range(12,20)],
            *[(x,y,SKD) for y in range(8,12) for x in range(12,15)],
            (20,7,SK),(21,7,SK),(21,8,OL),(20,8,OL),
            (17,6,OL),(18,6,EY),(18,7,OL),
            (18,9,PK),
            (17,10,OL),
        ])

    def hood_side_R(ox, oy):
        dp(px, ox, oy, [
            *[(x,3,WH) for x in range(11,21)],
            *[(x,4,WH) for x in range(11,21)],
            (10,4,OL),(10,5,OL),(21,4,OL),(21,5,OL),(21,6,OL),(21,7,OL),
            (10,5,WHD),(21,5,WHD),(21,6,WHD),(21,7,WHD),(21,8,WHD),
            (19,2,WH),(20,2,WH),(20,3,WH),(20,4,WH),
            (20,2,OL),(20,1,OL),(18,1,OL),
            *[(x,4,GD) for x in range(12,20)],
            (11,4,GDD),(20,4,GDD),
        ])

    def body_side_R(ox, oy):
        dp(px, ox, oy, [
            (15,13,SK),(16,13,SK),(17,13,SKD),
            (11,13,OL),(11,14,OL),(11,15,OL),(11,16,OL),(11,17,OL),(11,18,OL),(11,19,OL),(11,20,OL),(11,21,OL),(11,22,OL),
            (20,13,OL),(20,14,OL),(20,15,OL),(20,16,OL),(20,17,OL),(20,18,OL),(20,19,OL),(20,20,OL),(20,21,OL),(20,22,OL),
            *[(x,13,OL) for x in range(12,20)],
            *[(x,22,OL) for x in range(12,20)],
            *[(x,y,WH)  for y in range(14,22) for x in range(12,20)],
            *[(x,y,WHD) for y in range(14,22) for x in [12]],
            *[(x,y,WHD) for y in range(14,22) for x in [19]],
            *[(x,22,GD)  for x in range(12,20)],
            # staff right side
            (10,12,ST),(10,13,ST),(10,14,ST),(10,15,ST),(10,16,ST),(10,17,ST),(10,18,ST),(10,19,ST),(10,20,ST),(10,21,ST),
            (9,12,OL),(11,12,OL),(10,22,OL),
        ])

    # Arm colors: white robe sleeves with skin hands
    SC, SCD = WH, WHD

    # ── DRAW 16 FRAMES ──────────────────────────────────────────────────────
    # ROW 0: walk_down — arm swing: opposite to legs
    front_arm_offsets = [(0,0),(1,0),(0,0),(0,1)]
    leg_fns_front = [
        lambda ox,oy: _legs_stand_front(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_stride_right_front(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_stand_front(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_stride_left_front(px,ox,oy,LC,LCD,BC,BCM),
    ]
    for col in range(4):
        ox, oy = frame_origin(col, 0)
        hood_front(ox, oy)
        head_front(ox, oy)
        body_front(ox, oy)
        staff_front(ox, oy)
        lo, ro = front_arm_offsets[col]
        _arm_left_front(px,ox,oy,SC,SCD,SK,SKD,y_off=lo)
        _arm_right_front(px,ox,oy,SC,SCD,SK,SKD,y_off=ro)
        leg_fns_front[col](ox, oy)

    # ROW 1: walk_left
    side_arm_phases = [0,-1,0,1]
    leg_fns_L = [
        lambda ox,oy: _legs_side_stand_L(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_side_forward_L(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_side_stand_L(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_side_back_L(px,ox,oy,LC,LCD,BC,BCM),
    ]
    for col in range(4):
        ox, oy = frame_origin(col, 1)
        hood_side_L(ox, oy)
        head_side_L(ox, oy)
        body_side_L(ox, oy)
        _arm_side_L(px,ox,oy,SC,SCD,SK,SKD,phase=side_arm_phases[col])
        leg_fns_L[col](ox, oy)

    # ROW 2: walk_right
    leg_fns_R = [
        lambda ox,oy: _legs_side_stand_R(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_side_forward_R(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_side_stand_R(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_side_back_R(px,ox,oy,LC,LCD,BC,BCM),
    ]
    for col in range(4):
        ox, oy = frame_origin(col, 2)
        hood_side_R(ox, oy)
        head_side_R(ox, oy)
        body_side_R(ox, oy)
        _arm_side_R(px,ox,oy,SC,SCD,SK,SKD,phase=side_arm_phases[col])
        leg_fns_R[col](ox, oy)

    # ROW 3: walk_up
    leg_fns_back = [
        lambda ox,oy: _legs_stand_back(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_stride_right_back(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_stand_back(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_stride_left_back(px,ox,oy,LC,LCD,BC,BCM),
    ]
    for col in range(4):
        ox, oy = frame_origin(col, 3)
        hood_back(ox, oy)
        head_back(ox, oy)
        body_back(ox, oy)
        lo, ro = front_arm_offsets[col]
        _arm_left_back(px,ox,oy,SC,SCD,SK,SKD,y_off=lo)
        _arm_right_back(px,ox,oy,SC,SCD,SK,SKD,y_off=ro)
        leg_fns_back[col](ox, oy)

    out_path  = os.path.join(OUT_DIR, "cleric_overworld.png")
    prev_path = os.path.join(OUT_DIR, "cleric_overworld_4x.png")
    save_with_preview(img, out_path, prev_path, "CLERIC")


# ═══════════════════════════════════════════════════════════════════════════════
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  MAGE                                                                    ║
# ║  Tall pointed blue wizard hat, deep blue robes, glowing cyan staff tip   ║
# ╚══════════════════════════════════════════════════════════════════════════╝
# ═══════════════════════════════════════════════════════════════════════════════

def gen_mage():
    DB  = ( 30,  50, 130, 255)   # deep blue
    DBD = ( 20,  35,  90, 255)   # deep blue dark
    LB  = ( 60,  80, 180, 255)   # lighter blue
    CY  = (100, 220, 255, 255)   # cyan glow
    DK  = ( 20,  25,  40, 255)   # dark face shadow
    SK  = (200, 180, 160, 255)   # muted skin (shadowed under hat)
    SKD = (150, 130, 110, 255)
    EY  = (180, 230, 255, 255)   # pale glowing eye
    ST  = (160, 170, 180, 255)   # staff metal
    STD = (100, 110, 120, 255)
    LC  = DB
    LCD = DBD
    BC  = ( 15,  20,  35, 255)   # boot dark
    BCM = ( 30,  40,  60, 255)

    img = Image.new("RGBA", (128, 128), T)
    px = img.load()

    def hat_front(ox, oy):
        """Tall pointed blue wizard hat — hat tip reaches y=0 or above."""
        dp(px, ox, oy, [
            # Hat tip (very top)
            (15,0,OL),(16,0,OL),
            (14,1,OL),(15,1,DB),(16,1,DB),(17,1,OL),
            (13,2,OL),(14,2,DB),(15,2,LB),(16,2,DB),(17,2,OL),
            (12,3,OL),(13,3,DB),(14,3,LB),(15,3,LB),(16,3,DB),(17,3,DB),(18,3,OL),
            (11,4,OL),(12,4,DB),(13,4,LB),(14,4,LB),(15,4,LB),(16,4,DB),(17,4,DB),(18,4,DB),(19,4,OL),
            # hat brim row y=5 (wider)
            (10,5,OL),(11,5,DBD),(12,5,DB),(13,5,DB),(14,5,LB),(15,5,LB),(16,5,DB),(17,5,DB),(18,5,DBD),(19,5,DB),(20,5,OL),
            # brim underside y=6
            (9,6,OL),(10,6,DBD),(11,6,DBD),(12,6,DBD),(13,6,DBD),(14,6,DBD),(15,6,DBD),(16,6,DBD),(17,6,DBD),(18,6,DBD),(19,6,DBD),(20,6,DBD),(21,6,OL),
            (9,7,OL),(21,7,OL),
        ])

    def head_front(ox, oy):
        dp(px, ox, oy, [
            (11,7,OL),(12,7,OL),(13,7,OL),(14,7,OL),(15,7,OL),(16,7,OL),(17,7,OL),(18,7,OL),(19,7,OL),(20,7,OL),
            (10,8,OL),(10,9,OL),(10,10,OL),(10,11,OL),
            (21,8,OL),(21,9,OL),(21,10,OL),(21,11,OL),
            (11,12,OL),(12,12,OL),(13,12,OL),(14,12,OL),(15,12,OL),(16,12,OL),(17,12,OL),(18,12,OL),(19,12,OL),(20,12,OL),
            *[(x,y,DK)  for y in range(8,12) for x in range(11,21)],   # dark shadowed face
            *[(x,y,SK)  for y in range(9,12) for x in range(13,19)],   # slight skin centre
            # eyes glow faintly under hat shadow
            (13,9,OL),(14,9,EY),(14,10,OL),
            (17,9,OL),(18,9,EY),(18,10,OL),
        ])

    def body_front(ox, oy):
        dp(px, ox, oy, [
            (14,13,SKD),(15,13,SK),(16,13,SK),(17,13,SKD),
            # robe wide
            (10,13,OL),(10,14,OL),(10,15,OL),(10,16,OL),(10,17,OL),(10,18,OL),(10,19,OL),(10,20,OL),(10,21,OL),(10,22,OL),
            (21,13,OL),(21,14,OL),(21,15,OL),(21,16,OL),(21,17,OL),(21,18,OL),(21,19,OL),(21,20,OL),(21,21,OL),(21,22,OL),
            *[(x,13,OL) for x in range(11,21)],
            *[(x,22,OL) for x in range(11,21)],
            *[(x,y,DB)  for y in range(14,22) for x in range(11,21)],
            *[(x,y,LB)  for y in range(14,18) for x in [13,14,15]],    # lighter front panel
            *[(x,y,DBD) for y in range(14,22) for x in [11,20]],
        ])

    def staff_front(ox, oy):
        """Staff at right side, glowing cyan orb tip."""
        dp(px, ox, oy, [
            (22,9,ST),(22,10,ST),(22,11,ST),(22,12,ST),(22,13,ST),(22,14,ST),(22,15,ST),(22,16,ST),(22,17,ST),(22,18,ST),(22,19,ST),(22,20,ST),
            (23,9,OL),(21,9,OL),(22,21,OL),
            # cyan orb
            (21,7,OL),(22,7,CY),(23,7,CY),(24,7,OL),
            (21,8,CY),(22,8,CY),(23,8,CY),(24,8,OL),(20,8,OL),
            (21,9,OL),(22,9,CY),(23,9,CY),(24,9,OL),
        ])

    def hat_back(ox, oy):
        dp(px, ox, oy, [
            (15,0,OL),(16,0,OL),
            (14,1,OL),(15,1,DB),(16,1,DB),(17,1,OL),
            (13,2,OL),(14,2,DB),(15,2,DB),(16,2,DB),(17,2,OL),
            (12,3,OL),(13,3,DBD),(14,3,DB),(15,3,DB),(16,3,DB),(17,3,DBD),(18,3,OL),
            (11,4,OL),(12,4,DBD),(13,4,DB),(14,4,DB),(15,4,DB),(16,4,DB),(17,4,DB),(18,4,DBD),(19,4,OL),
            (10,5,OL),(11,5,DBD),(12,5,DBD),(13,5,DB),(14,5,DB),(15,5,DB),(16,5,DB),(17,5,DB),(18,5,DBD),(19,5,DBD),(20,5,OL),
            (9,6,OL),(10,6,DBD),(11,6,DBD),(12,6,DBD),(13,6,DBD),(14,6,DBD),(15,6,DBD),(16,6,DBD),(17,6,DBD),(18,6,DBD),(19,6,DBD),(20,6,DBD),(21,6,OL),
            (9,7,OL),(21,7,OL),
        ])

    def head_back(ox, oy):
        dp(px, ox, oy, [
            (11,7,OL),(12,7,OL),(13,7,OL),(14,7,OL),(15,7,OL),(16,7,OL),(17,7,OL),(18,7,OL),(19,7,OL),(20,7,OL),
            (10,8,OL),(10,9,OL),(10,10,OL),(10,11,OL),
            (21,8,OL),(21,9,OL),(21,10,OL),(21,11,OL),
            (11,12,OL),(12,12,OL),(13,12,OL),(14,12,OL),(15,12,OL),(16,12,OL),(17,12,OL),(18,12,OL),(19,12,OL),(20,12,OL),
            *[(x,y,DK)  for y in range(8,12) for x in range(11,21)],
        ])

    def body_back(ox, oy):
        dp(px, ox, oy, [
            (14,13,DK),(15,13,DK),(16,13,DK),(17,13,DK),
            (10,13,OL),(10,14,OL),(10,15,OL),(10,16,OL),(10,17,OL),(10,18,OL),(10,19,OL),(10,20,OL),(10,21,OL),(10,22,OL),
            (21,13,OL),(21,14,OL),(21,15,OL),(21,16,OL),(21,17,OL),(21,18,OL),(21,19,OL),(21,20,OL),(21,21,OL),(21,22,OL),
            *[(x,13,OL) for x in range(11,21)],
            *[(x,22,OL) for x in range(11,21)],
            *[(x,y,DBD) for y in range(14,22) for x in range(11,21)],
            *[(x,y,DB)  for y in range(14,20) for x in [14,15,16,17]],
        ])

    def hat_side_L(ox, oy):
        dp(px, ox, oy, [
            (15,0,OL),(16,0,OL),
            (14,1,OL),(15,1,DB),(16,1,OL),
            (13,2,OL),(14,2,DB),(15,2,DB),(16,2,OL),
            (12,3,OL),(13,3,DB),(14,3,LB),(15,3,DB),(16,3,OL),
            (11,4,OL),(12,4,DB),(13,4,LB),(14,4,DB),(15,4,DB),(16,4,OL),(17,4,OL),
            (10,5,OL),(11,5,DB),(12,5,DB),(13,5,DB),(14,5,DB),(15,5,DB),(16,5,DB),(17,5,DB),(18,5,OL),
            (9,6,OL),(10,6,DBD),(11,6,DBD),(12,6,DBD),(13,6,DBD),(14,6,DBD),(15,6,DBD),(16,6,DBD),(17,6,DBD),(18,6,DBD),(19,6,OL),
            (9,7,OL),(19,7,OL),
        ])

    def hat_side_R(ox, oy):
        dp(px, ox, oy, [
            (15,0,OL),(16,0,OL),
            (15,1,OL),(16,1,DB),(17,1,OL),
            (14,2,OL),(15,2,DB),(16,2,DB),(17,2,OL),
            (14,3,OL),(15,3,DB),(16,3,LB),(17,3,DB),(18,3,OL),
            (13,4,OL),(14,4,DB),(15,4,DB),(16,4,LB),(17,4,DB),(18,4,DB),(19,4,OL),
            (12,5,OL),(13,5,DB),(14,5,DB),(15,5,DB),(16,5,DB),(17,5,DB),(18,5,DB),(19,5,DB),(20,5,OL),
            (11,6,OL),(12,6,DBD),(13,6,DBD),(14,6,DBD),(15,6,DBD),(16,6,DBD),(17,6,DBD),(18,6,DBD),(19,6,DBD),(20,6,DBD),(21,6,OL),
            (11,7,OL),(21,7,OL),
        ])

    def head_side_L(ox, oy):
        dp(px, ox, oy, [
            (12,7,OL),(13,7,OL),(14,7,OL),(15,7,OL),(16,7,OL),(17,7,OL),(18,7,OL),(19,7,OL),
            (11,8,OL),(11,9,OL),(11,10,OL),(11,11,OL),
            (20,8,OL),(20,9,OL),(20,10,OL),(20,11,OL),
            (12,12,OL),(13,12,OL),(14,12,OL),(15,12,OL),(16,12,OL),(17,12,OL),(18,12,OL),(19,12,OL),
            *[(x,y,DK)  for y in range(8,12) for x in range(12,20)],
            *[(x,y,SK)  for y in range(9,12) for x in range(13,17)],
            (11,8,DK),(10,8,DK),(10,9,OL),(11,9,OL),
            (13,9,OL),(14,9,EY),(14,10,OL),
        ])

    def head_side_R(ox, oy):
        dp(px, ox, oy, [
            (12,7,OL),(13,7,OL),(14,7,OL),(15,7,OL),(16,7,OL),(17,7,OL),(18,7,OL),(19,7,OL),
            (11,8,OL),(11,9,OL),(11,10,OL),(11,11,OL),
            (20,8,OL),(20,9,OL),(20,10,OL),(20,11,OL),
            (12,12,OL),(13,12,OL),(14,12,OL),(15,12,OL),(16,12,OL),(17,12,OL),(18,12,OL),(19,12,OL),
            *[(x,y,DK)  for y in range(8,12) for x in range(12,20)],
            *[(x,y,SK)  for y in range(9,12) for x in range(14,18)],
            (20,8,DK),(21,8,DK),(21,9,OL),(20,9,OL),
            (17,9,OL),(18,9,EY),(18,10,OL),
        ])

    def body_side_L(ox, oy):
        dp(px, ox, oy, [
            (14,13,SKD),(15,13,SK),(16,13,SKD),
            (12,13,OL),(12,14,OL),(12,15,OL),(12,16,OL),(12,17,OL),(12,18,OL),(12,19,OL),(12,20,OL),(12,21,OL),(12,22,OL),
            (20,13,OL),(20,14,OL),(20,15,OL),(20,16,OL),(20,17,OL),(20,18,OL),(20,19,OL),(20,20,OL),(20,21,OL),(20,22,OL),
            *[(x,13,OL) for x in range(13,20)],
            *[(x,22,OL) for x in range(13,20)],
            *[(x,y,DB)  for y in range(14,22) for x in range(13,20)],
            *[(x,y,DBD) for y in range(14,22) for x in [13,19]],
            # staff
            (21,12,ST),(21,13,ST),(21,14,ST),(21,15,ST),(21,16,ST),(21,17,ST),(21,18,ST),(21,19,ST),(21,20,ST),(21,21,ST),
            (22,12,OL),(20,22,OL),(21,22,OL),
            (21,10,CY),(22,10,CY),(21,11,CY),(22,11,OL),(20,10,OL),
        ])

    def body_side_R(ox, oy):
        dp(px, ox, oy, [
            (15,13,SK),(16,13,SK),(17,13,SKD),
            (11,13,OL),(11,14,OL),(11,15,OL),(11,16,OL),(11,17,OL),(11,18,OL),(11,19,OL),(11,20,OL),(11,21,OL),(11,22,OL),
            (20,13,OL),(20,14,OL),(20,15,OL),(20,16,OL),(20,17,OL),(20,18,OL),(20,19,OL),(20,20,OL),(20,21,OL),(20,22,OL),
            *[(x,13,OL) for x in range(12,20)],
            *[(x,22,OL) for x in range(12,20)],
            *[(x,y,DB)  for y in range(14,22) for x in range(12,20)],
            *[(x,y,DBD) for y in range(14,22) for x in [12,19]],
            # staff
            (10,12,ST),(10,13,ST),(10,14,ST),(10,15,ST),(10,16,ST),(10,17,ST),(10,18,ST),(10,19,ST),(10,20,ST),(10,21,ST),
            (9,12,OL),(11,12,OL),(10,22,OL),
            (9,10,CY),(10,10,CY),(9,11,CY),(10,11,OL),(11,10,OL),
        ])

    # Arm colors: dark blue robe sleeves
    SC, SCD = DB, DBD

    # ── DRAW 16 FRAMES ──────────────────────────────────────────────────────
    front_arm_offsets = [(0,0),(1,0),(0,0),(0,1)]
    side_arm_phases = [0,-1,0,1]
    leg_fns_front = [
        lambda ox,oy: _legs_stand_front(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_stride_right_front(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_stand_front(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_stride_left_front(px,ox,oy,LC,LCD,BC,BCM),
    ]
    for col in range(4):
        ox, oy = frame_origin(col, 0)
        body_front(ox, oy)
        staff_front(ox, oy)
        lo, ro = front_arm_offsets[col]
        _arm_left_front(px,ox,oy,SC,SCD,SK,SKD,y_off=lo)
        _arm_right_front(px,ox,oy,SC,SCD,SK,SKD,y_off=ro)
        hat_front(ox, oy)
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
        hat_side_L(ox, oy)
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
        hat_side_R(ox, oy)
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
        hat_back(ox, oy)
        head_back(ox, oy)
        leg_fns_back[col](ox, oy)

    out_path  = os.path.join(OUT_DIR, "mage_overworld.png")
    prev_path = os.path.join(OUT_DIR, "mage_overworld_4x.png")
    save_with_preview(img, out_path, prev_path, "MAGE")


# ═══════════════════════════════════════════════════════════════════════════════
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  ROGUE                                                                   ║
# ║  Deep hood, dark cloak, lean crouched build, amber eyes                  ║
# ╚══════════════════════════════════════════════════════════════════════════╝
# ═══════════════════════════════════════════════════════════════════════════════

def gen_rogue():
    DN  = ( 30,  30,  50, 255)   # dark navy cloak
    DND = ( 18,  18,  32, 255)   # very dark
    DB  = ( 60,  45,  30, 255)   # dark brown leather
    DBD = ( 38,  28,  18, 255)
    SP  = ( 90,  60,  80, 255)   # dusty purple scarf
    SPD = ( 60,  38,  55, 255)
    AM  = (200, 160,  60, 255)   # amber eyes
    SK  = (175, 145, 110, 255)   # muted skin (barely visible)
    SKD = (130, 100,  75, 255)
    LC  = DN
    LCD = DND
    BC  = ( 25,  20,  15, 255)   # dark boot
    BCM = ( 40,  32,  24, 255)

    img = Image.new("RGBA", (128, 128), T)
    px = img.load()

    def hood_front(ox, oy):
        """Deep hood — face mostly in shadow, only eyes glow."""
        dp(px, ox, oy, [
            # hood outer shape
            *[(x,2,DN)  for x in range(12,20)],
            *[(x,3,DN)  for x in range(11,21)],
            *[(x,4,DN)  for x in range(10,22)],
            (10,3,OL),(10,4,OL),(10,5,OL),(10,6,OL),(10,7,OL),(10,8,OL),(10,9,OL),
            (21,3,OL),(21,4,OL),(21,5,OL),(21,6,OL),(21,7,OL),(21,8,OL),(21,9,OL),
            (11,2,OL),(19,2,OL),(11,1,OL),(12,1,OL),(13,1,OL),(14,1,OL),(15,1,OL),(16,1,OL),(17,1,OL),(18,1,OL),(19,1,OL),
            # inner shadow of hood (face area dark)
            *[(x,y,DND) for y in range(5,12) for x in range(11,21)],
            *[(x,y,SK)  for y in range(8,11) for x in range(13,19)],
            # scarf across lower face y=10..12
            *[(x,y,SP)  for y in range(10,13) for x in range(12,20)],
            *[(x,y,SPD) for y in range(11,13) for x in range(14,18)],
            (11,10,OL),(11,11,OL),(11,12,OL),(20,10,OL),(20,11,OL),(20,12,OL),
            # amber eyes only visible
            (13,8,OL),(14,8,AM),(15,8,AM),(14,9,OL),(15,9,OL),
            (16,8,OL),(17,8,AM),(18,8,AM),(17,9,OL),(18,9,OL),
            # hood top peak
            (14,0,OL),(15,0,DN),(16,0,DN),(17,0,OL),
            (10,4,DN),(10,5,DN),(10,6,DN),(10,7,DN),(10,8,DN),
            (21,4,DN),(21,5,DN),(21,6,DN),(21,7,DN),(21,8,DN),
        ])

    def body_front(ox, oy):
        """Lean torso, slightly narrower than standard."""
        dp(px, ox, oy, [
            (14,13,SKD),(15,13,SK),(16,13,SK),(17,13,SKD),
            # cloak outline slightly narrower
            (11,13,OL),(11,14,OL),(11,15,OL),(11,16,OL),(11,17,OL),(11,18,OL),(11,19,OL),(11,20,OL),(11,21,OL),(11,22,OL),
            (20,13,OL),(20,14,OL),(20,15,OL),(20,16,OL),(20,17,OL),(20,18,OL),(20,19,OL),(20,20,OL),(20,21,OL),(20,22,OL),
            *[(x,13,OL) for x in range(12,20)],
            *[(x,22,OL) for x in range(12,20)],
            *[(x,y,DN)  for y in range(14,22) for x in range(12,20)],
            *[(x,y,DND) for y in range(14,22) for x in [12,19]],
            # leather belt strap
            *[(x,19,DB)  for x in range(13,19)],
            *[(x,20,DBD) for x in range(13,19)],
            (12,19,OL),(19,19,OL),(12,20,OL),(19,20,OL),
            # cape asymmetry — right side slightly longer hint
            (10,18,DN),(10,19,DN),(10,20,DND),(10,21,OL),
        ])

    def hood_back(ox, oy):
        dp(px, ox, oy, [
            *[(x,2,DN)  for x in range(12,20)],
            *[(x,3,DN)  for x in range(11,21)],
            *[(x,4,DN)  for x in range(10,22)],
            (10,3,OL),(10,4,OL),(10,5,OL),(10,6,OL),(10,7,OL),(10,8,OL),(10,9,OL),
            (21,3,OL),(21,4,OL),(21,5,OL),(21,6,OL),(21,7,OL),(21,8,OL),(21,9,OL),
            (11,2,OL),(19,2,OL),(11,1,OL),(19,1,OL),
            *[(x,y,DND) for y in range(5,12) for x in range(11,21)],
            (14,0,OL),(15,0,DN),(16,0,DN),(17,0,OL),
            # faint hood texture back
            (13,6,DN),(14,6,DN),(17,6,DN),(18,6,DN),
        ])

    def body_back(ox, oy):
        dp(px, ox, oy, [
            (14,13,DND),(15,13,DND),(16,13,DND),(17,13,DND),
            (11,13,OL),(11,14,OL),(11,15,OL),(11,16,OL),(11,17,OL),(11,18,OL),(11,19,OL),(11,20,OL),(11,21,OL),(11,22,OL),
            (20,13,OL),(20,14,OL),(20,15,OL),(20,16,OL),(20,17,OL),(20,18,OL),(20,19,OL),(20,20,OL),(20,21,OL),(20,22,OL),
            *[(x,13,OL) for x in range(12,20)],
            *[(x,22,OL) for x in range(12,20)],
            *[(x,y,DND) for y in range(14,22) for x in range(12,20)],
            *[(x,y,DN)  for y in range(14,20) for x in [14,15,16,17]],
            *[(x,19,DB)  for x in range(13,19)],
            (12,19,OL),(19,19,OL),
        ])

    def hood_side_L(ox, oy):
        dp(px, ox, oy, [
            *[(x,3,DN)  for x in range(11,21)],
            *[(x,4,DN)  for x in range(10,21)],
            (10,3,OL),(10,4,OL),(10,5,OL),(10,6,OL),(10,7,OL),(10,8,OL),
            (20,3,OL),(20,4,OL),(20,5,OL),(20,6,OL),
            (11,2,OL),(12,2,DN),(13,2,DN),(10,3,DN),
            *[(x,y,DND) for y in range(5,12) for x in range(11,20)],
            *[(x,y,SK)  for y in range(8,11) for x in range(12,16)],
            *[(x,y,SP)  for y in range(10,13) for x in range(12,19)],
            (11,10,OL),(19,10,OL),(11,12,OL),
            # nose protrudes left under hood
            (10,8,SKD),(9,8,SKD),(9,9,OL),(10,9,OL),
            (12,8,OL),(13,8,AM),(14,8,AM),(13,9,OL),
        ])

    def hood_side_R(ox, oy):
        dp(px, ox, oy, [
            *[(x,3,DN)  for x in range(11,21)],
            *[(x,4,DN)  for x in range(11,22)],
            (11,3,OL),(11,4,OL),(11,5,OL),(11,6,OL),(11,7,OL),(11,8,OL),
            (21,3,OL),(21,4,OL),(21,5,OL),(21,6,OL),(21,7,OL),(21,8,OL),
            (20,2,OL),(19,2,DN),(18,2,DN),(21,3,DN),
            *[(x,y,DND) for y in range(5,12) for x in range(12,21)],
            *[(x,y,SK)  for y in range(8,11) for x in range(16,20)],
            *[(x,y,SP)  for y in range(10,13) for x in range(13,20)],
            (12,10,OL),(20,10,OL),(20,12,OL),
            (21,8,SKD),(22,8,SKD),(22,9,OL),(21,9,OL),
            (18,8,OL),(17,8,AM),(17,9,OL),
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
            *[(x,19,DB)  for x in range(13,20)],
            (12,19,OL),(20,19,OL),
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
            *[(x,19,DB)  for x in range(12,20)],
            (11,19,OL),(20,19,OL),
        ])

    # Arm colors: dark navy cloak sleeves
    SC, SCD = DN, DND

    # ── DRAW 16 FRAMES ──────────────────────────────────────────────────────
    front_arm_offsets = [(0,0),(1,0),(0,0),(0,1)]
    side_arm_phases = [0,-1,0,1]
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
        hood_front(ox, oy)
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
        hood_side_L(ox, oy)
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
        hood_side_R(ox, oy)
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
        hood_back(ox, oy)
        leg_fns_back[col](ox, oy)

    out_path  = os.path.join(OUT_DIR, "rogue_overworld.png")
    prev_path = os.path.join(OUT_DIR, "rogue_overworld_4x.png")
    save_with_preview(img, out_path, prev_path, "ROGUE")


# ═══════════════════════════════════════════════════════════════════════════════
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  BARD                                                                    ║
# ║  Feathered beret, gold-olive doublet, lute on back, jaunty pose          ║
# ╚══════════════════════════════════════════════════════════════════════════╝
# ═══════════════════════════════════════════════════════════════════════════════

def gen_bard():
    OL2 = OL
    OV  = (120, 130,  60, 255)   # olive
    OVD = ( 80,  88,  38, 255)   # olive dark
    GD  = (190, 160,  50, 255)   # gold trim
    GDD = (130, 105,  25, 255)
    CR  = (230, 220, 200, 255)   # cream shirt
    CRD = (190, 178, 158, 255)
    RF  = (200,  40,  40, 255)   # red feather
    RFD = (140,  20,  20, 255)
    SK  = (230, 190, 150, 255)
    SKD = (190, 145, 110, 255)
    HR  = (160, 120,  60, 255)   # warm brown hair
    HRD = (110,  75,  35, 255)
    EY  = ( 60, 100,  60, 255)   # green eyes
    LT  = ( 90,  65,  35, 255)   # lute wood
    LTD = ( 60,  40,  20, 255)
    LC  = OV
    LCD = OVD
    BC  = ( 55,  40,  20, 255)
    BCM = ( 80,  60,  35, 255)

    img = Image.new("RGBA", (128, 128), T)
    px = img.load()

    def head_front(ox, oy):
        dp(px, ox, oy, [
            (11,4,OL),(12,4,OL),(13,4,OL),(14,4,OL),(15,4,OL),(16,4,OL),(17,4,OL),(18,4,OL),(19,4,OL),(20,4,OL),
            (10,5,OL),(10,6,OL),(10,7,OL),(10,8,OL),(10,9,OL),(10,10,OL),(10,11,OL),
            (21,5,OL),(21,6,OL),(21,7,OL),(21,8,OL),(21,9,OL),(21,10,OL),(21,11,OL),
            (11,12,OL),(12,12,OL),(13,12,OL),(14,12,OL),(15,12,OL),(16,12,OL),(17,12,OL),(18,12,OL),(19,12,OL),(20,12,OL),
            *[(x,y,SK)  for y in range(5,12) for x in range(11,21)],
            *[(x,y,SKD) for y in range(9,12) for x in range(17,21)],
            (13,7,OL),(14,7,EY),(14,8,OL),
            (17,7,OL),(18,7,EY),(18,8,OL),
            # smirking mouth
            (14,10,SKD),(15,10,OL),(16,10,OL),(17,10,OL),(18,10,SKD),
            (14,11,OL),
        ])

    def hat_front(ox, oy):
        """Tilted beret — sits left-leaning, feather pokes up-right."""
        dp(px, ox, oy, [
            # beret body tilted: wider on left
            (10,4,OL),(11,4,GD),(12,4,OV),(13,4,OV),(14,4,OV),(15,4,OV),(16,4,OV),(17,4,OV),(18,4,GD),(19,4,OL),
            (10,3,OL),(11,3,OV),(12,3,OV),(13,3,OV),(14,3,OV),(15,3,OV),(16,3,OV),(17,3,OV),(18,3,OV),(19,3,OL),
            (11,2,OL),(12,2,OV),(13,2,OV),(14,2,OV),(15,2,OV),(16,2,OV),(17,2,OV),(18,2,OL),
            (12,1,OL),(13,1,OV),(14,1,OV),(15,1,OV),(16,1,OL),
            # brim undershadow
            (10,5,GDD),(11,5,GD),(12,5,GD),(13,5,GD),(14,5,GD),(15,5,GD),(16,5,GD),(17,5,GD),(18,5,GDD),(19,5,GD),
            (9,5,OL),(20,5,OL),
            # red feather — upper right
            (18,0,OL),(19,0,RF),(20,0,RF),(21,0,OL),
            (19,1,RF),(20,1,RFD),(21,1,OL),
            (20,2,RFD),(20,3,RFD),(21,2,OL),
        ])

    def hair_front(ox, oy):
        dp(px, ox, oy, [
            # sideburns peeking under beret
            (10,5,HR),(10,6,HR),(10,7,HR),(10,8,HRD),
            (21,5,HR),(21,6,HR),(21,7,HR),(21,8,HRD),
            (10,5,OL),(10,9,OL),(21,5,OL),(21,9,OL),
        ])

    def body_front(ox, oy):
        dp(px, ox, oy, [
            (14,13,SKD),(15,13,SK),(16,13,SK),(17,13,SKD),
            # doublet — slightly narrower shoulders
            (11,13,OL),(11,14,OL),(11,15,OL),(11,16,OL),(11,17,OL),(11,18,OL),(11,19,OL),(11,20,OL),(11,21,OL),(11,22,OL),
            (20,13,OL),(20,14,OL),(20,15,OL),(20,16,OL),(20,17,OL),(20,18,OL),(20,19,OL),(20,20,OL),(20,21,OL),(20,22,OL),
            *[(x,13,OL) for x in range(12,20)],
            *[(x,22,OL) for x in range(12,20)],
            # olive doublet
            *[(x,y,OV)  for y in range(14,22) for x in range(12,20)],
            *[(x,y,OVD) for y in range(14,22) for x in [12,19]],
            # cream shirt visible centre
            *[(x,y,CR)  for y in range(14,20) for x in [15,16]],
            *[(x,y,CRD) for y in range(17,22) for x in [15,16]],
            # gold button row
            (15,14,GD),(15,16,GD),(15,18,GD),(15,20,GD),
            # gold trim edges
            *[(x,14,GD) for x in range(13,15)],
            *[(x,14,GD) for x in range(17,19)],
            *[(x,22,GD) for x in range(13,19)],
            # cape sash right-side accent
            (20,15,OV),(20,16,OV),(20,17,OV),(21,15,OVD),(21,16,OVD),(21,17,OVD),(21,15,OL),
        ])

    def lute_back_hint(ox, oy):
        """Small lute peeking over left shoulder from back."""
        dp(px, ox, oy, [
            # round body
            (8,15,OL),(9,15,LT),(10,15,LT),(11,15,OL),
            (8,16,OL),(9,16,LTD),(10,16,LT),(11,16,OL),
            (8,17,OL),(9,17,LT),(10,17,OL),
            # neck
            (9,13,OL),(10,13,LT),(10,14,LT),(9,14,OL),
        ])

    def head_back(ox, oy):
        dp(px, ox, oy, [
            (11,4,OL),(12,4,OL),(13,4,OL),(14,4,OL),(15,4,OL),(16,4,OL),(17,4,OL),(18,4,OL),(19,4,OL),(20,4,OL),
            (10,5,OL),(10,6,OL),(10,7,OL),(10,8,OL),(10,9,OL),(10,10,OL),(10,11,OL),
            (21,5,OL),(21,6,OL),(21,7,OL),(21,8,OL),(21,9,OL),(21,10,OL),(21,11,OL),
            (11,12,OL),(12,12,OL),(13,12,OL),(14,12,OL),(15,12,OL),(16,12,OL),(17,12,OL),(18,12,OL),(19,12,OL),(20,12,OL),
            *[(x,y,HR)  for y in range(5,12) for x in range(11,21)],
            *[(x,y,HRD) for y in range(7,12) for x in range(13,19)],
        ])

    def hat_back(ox, oy):
        dp(px, ox, oy, [
            (10,4,OL),(11,4,OVD),(12,4,OVD),(13,4,OVD),(14,4,OVD),(15,4,OVD),(16,4,OVD),(17,4,OVD),(18,4,OVD),(19,4,OL),
            (10,3,OL),(11,3,OVD),(12,3,OV),(13,3,OV),(14,3,OV),(15,3,OV),(16,3,OV),(17,3,OV),(18,3,OVD),(19,3,OL),
            (11,2,OL),(12,2,OV),(13,2,OV),(14,2,OV),(15,2,OV),(16,2,OV),(17,2,OL),
            (12,1,OL),(13,1,OV),(14,1,OV),(15,1,OL),
            (9,5,OL),(10,5,GDD),(11,5,GDD),(12,5,GDD),(13,5,GDD),(14,5,GDD),(15,5,GDD),(16,5,GDD),(17,5,GDD),(18,5,GDD),(19,5,GDD),(20,5,OL),
            # feather back right
            (18,0,OL),(19,0,RFD),(20,0,RFD),(21,0,OL),
            (19,1,RFD),(20,1,RFD),(21,1,OL),
        ])

    def body_back(ox, oy):
        dp(px, ox, oy, [
            (14,13,HRD),(15,13,HR),(16,13,HR),(17,13,HRD),
            (11,13,OL),(11,14,OL),(11,15,OL),(11,16,OL),(11,17,OL),(11,18,OL),(11,19,OL),(11,20,OL),(11,21,OL),(11,22,OL),
            (20,13,OL),(20,14,OL),(20,15,OL),(20,16,OL),(20,17,OL),(20,18,OL),(20,19,OL),(20,20,OL),(20,21,OL),(20,22,OL),
            *[(x,13,OL) for x in range(12,20)],
            *[(x,22,OL) for x in range(12,20)],
            *[(x,y,OVD) for y in range(14,22) for x in range(12,20)],
            *[(x,y,OV)  for y in range(14,20) for x in [14,15,16,17]],
            *[(x,22,GD)  for x in range(13,19)],
            # lute peeking left shoulder
            (8,15,OL),(9,15,LT),(10,15,LT),(11,15,OL),
            (8,16,OL),(9,16,LTD),(10,16,LT),(11,16,OL),
            (8,17,OL),(9,17,LT),(10,17,OL),
            (9,13,OL),(10,13,LT),(10,14,LT),(9,14,OL),
        ])

    def head_side_L(ox, oy):
        dp(px, ox, oy, [
            (12,4,OL),(13,4,OL),(14,4,OL),(15,4,OL),(16,4,OL),(17,4,OL),(18,4,OL),(19,4,OL),
            (11,5,OL),(11,6,OL),(11,7,OL),(11,8,OL),(11,9,OL),(11,10,OL),(11,11,OL),
            (20,5,OL),(20,6,OL),(20,7,OL),(20,8,OL),(20,9,OL),(20,10,OL),(20,11,OL),
            (12,12,OL),(13,12,OL),(14,12,OL),(15,12,OL),(16,12,OL),(17,12,OL),(18,12,OL),(19,12,OL),
            *[(x,y,SK)  for y in range(5,12) for x in range(12,20)],
            *[(x,y,SKD) for y in range(8,12) for x in range(16,20)],
            (11,7,SK),(10,7,SK),(10,8,OL),(11,8,OL),
            (13,6,OL),(14,6,EY),(14,7,OL),
            (13,10,OL),(14,10,SKD),
        ])

    def hat_side_L(ox, oy):
        dp(px, ox, oy, [
            (11,4,OL),(12,4,GD),(13,4,OV),(14,4,OV),(15,4,OV),(16,4,OV),(17,4,OV),(18,4,GD),(19,4,OL),
            (10,3,OL),(11,3,OV),(12,3,OV),(13,3,OV),(14,3,OV),(15,3,OV),(16,3,OV),(17,3,OV),(18,3,OL),
            (11,2,OL),(12,2,OV),(13,2,OV),(14,2,OV),(15,2,OV),(16,2,OV),(17,2,OL),
            (12,1,OL),(13,1,OV),(14,1,OV),(15,1,OL),
            (10,5,GDD),(11,5,GD),(12,5,GD),(13,5,GD),(14,5,GD),(15,5,GD),(16,5,GD),(17,5,GD),(18,5,GDD),(19,5,GD),(20,5,OL),(9,5,OL),
            # feather toward left face
            (10,1,OL),(11,1,RF),(11,2,RF),(10,2,RF),(10,3,OL),(11,3,OL),
            (10,0,OL),(11,0,RFD),(12,0,OL),
        ])

    def hat_side_R(ox, oy):
        dp(px, ox, oy, [
            (11,4,OL),(12,4,GDD),(13,4,OV),(14,4,OV),(15,4,OV),(16,4,OV),(17,4,OV),(18,4,GD),(19,4,OL),
            (11,3,OL),(12,3,OV),(13,3,OV),(14,3,OV),(15,3,OV),(16,3,OV),(17,3,OV),(18,3,OV),(19,3,OL),
            (12,2,OL),(13,2,OV),(14,2,OV),(15,2,OV),(16,2,OV),(17,2,OV),(18,2,OL),
            (13,1,OL),(14,1,OV),(15,1,OV),(16,1,OL),
            (9,5,OL),(10,5,GDD),(11,5,GD),(12,5,GD),(13,5,GD),(14,5,GD),(15,5,GD),(16,5,GD),(17,5,GD),(18,5,GDD),(19,5,GDD),(20,5,OL),
            # feather upper right
            (19,0,OL),(20,0,RF),(21,0,RF),(22,0,OL),
            (20,1,RF),(21,1,RFD),(22,1,OL),
            (21,2,RFD),(22,2,OL),
        ])

    def body_side_L(ox, oy):
        dp(px, ox, oy, [
            (14,13,SKD),(15,13,SK),(16,13,SKD),
            (12,13,OL),(12,14,OL),(12,15,OL),(12,16,OL),(12,17,OL),(12,18,OL),(12,19,OL),(12,20,OL),(12,21,OL),(12,22,OL),
            (20,13,OL),(20,14,OL),(20,15,OL),(20,16,OL),(20,17,OL),(20,18,OL),(20,19,OL),(20,20,OL),(20,21,OL),(20,22,OL),
            *[(x,13,OL) for x in range(13,20)],
            *[(x,22,OL) for x in range(13,20)],
            *[(x,y,OV)  for y in range(14,22) for x in range(13,20)],
            *[(x,y,OVD) for y in range(14,22) for x in [13,19]],
            *[(x,y,CR)  for y in range(14,19) for x in [16,17]],
            *[(x,22,GD) for x in range(13,20)],
            # lute on back (left side)
            (8,16,OL),(9,16,LT),(10,16,LT),(11,16,OL),
            (8,17,OL),(9,17,LTD),(10,17,LT),(11,17,OL),
            (8,18,OL),(9,18,LT),(10,18,OL),
            (9,14,OL),(10,14,LT),(10,15,LT),(9,15,OL),
        ])

    def body_side_R(ox, oy):
        dp(px, ox, oy, [
            (15,13,SK),(16,13,SK),(17,13,SKD),
            (11,13,OL),(11,14,OL),(11,15,OL),(11,16,OL),(11,17,OL),(11,18,OL),(11,19,OL),(11,20,OL),(11,21,OL),(11,22,OL),
            (20,13,OL),(20,14,OL),(20,15,OL),(20,16,OL),(20,17,OL),(20,18,OL),(20,19,OL),(20,20,OL),(20,21,OL),(20,22,OL),
            *[(x,13,OL) for x in range(12,20)],
            *[(x,22,OL) for x in range(12,20)],
            *[(x,y,OV)  for y in range(14,22) for x in range(12,20)],
            *[(x,y,OVD) for y in range(14,22) for x in [12,19]],
            *[(x,y,CR)  for y in range(14,19) for x in [13,14]],
            *[(x,22,GD) for x in range(12,20)],
        ])

    def head_side_R(ox, oy):
        dp(px, ox, oy, [
            (12,4,OL),(13,4,OL),(14,4,OL),(15,4,OL),(16,4,OL),(17,4,OL),(18,4,OL),(19,4,OL),
            (11,5,OL),(11,6,OL),(11,7,OL),(11,8,OL),(11,9,OL),(11,10,OL),(11,11,OL),
            (20,5,OL),(20,6,OL),(20,7,OL),(20,8,OL),(20,9,OL),(20,10,OL),(20,11,OL),
            (12,12,OL),(13,12,OL),(14,12,OL),(15,12,OL),(16,12,OL),(17,12,OL),(18,12,OL),(19,12,OL),
            *[(x,y,SK)  for y in range(5,12) for x in range(12,20)],
            *[(x,y,SKD) for y in range(8,12) for x in range(12,15)],
            # nose protrudes right
            (20,7,SK),(21,7,SK),(21,8,OL),(20,8,OL),
            # eye
            (17,6,OL),(18,6,EY),(18,7,OL),
            (18,10,OL),(17,10,SKD),
        ])

    # Arm colors: olive doublet sleeves
    SC, SCD = OV, OVD

    # ── DRAW 16 FRAMES ──────────────────────────────────────────────────────
    front_arm_offsets = [(0,0),(1,0),(0,0),(0,1)]
    side_arm_phases = [0,-1,0,1]
    leg_fns_front = [
        lambda ox,oy: _legs_stand_front(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_stride_right_front(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_stand_front(px,ox,oy,LC,LCD,BC,BCM),
        lambda ox,oy: _legs_stride_left_front(px,ox,oy,LC,LCD,BC,BCM),
    ]
    for col in range(4):
        ox, oy = frame_origin(col, 0)
        hair_front(ox, oy)
        body_front(ox, oy)
        lute_back_hint(ox, oy)
        lo, ro = front_arm_offsets[col]
        _arm_left_front(px,ox,oy,SC,SCD,SK,SKD,y_off=lo)
        _arm_right_front(px,ox,oy,SC,SCD,SK,SKD,y_off=ro)
        hat_front(ox, oy)
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
        hat_side_L(ox, oy)
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
        hat_side_R(ox, oy)
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
        hat_back(ox, oy)
        head_back(ox, oy)
        leg_fns_back[col](ox, oy)

    out_path  = os.path.join(OUT_DIR, "bard_overworld.png")
    prev_path = os.path.join(OUT_DIR, "bard_overworld_4x.png")
    save_with_preview(img, out_path, prev_path, "BARD")


# ═══════════════════════════════════════════════════════════════════════════════
#  MAIN
# ═══════════════════════════════════════════════════════════════════════════════
if __name__ == "__main__":
    print("=== Generating CLERIC overworld sprite ===")
    gen_cleric()

    print("=== Generating MAGE overworld sprite ===")
    gen_mage()

    print("=== Generating ROGUE overworld sprite ===")
    gen_rogue()

    print("=== Generating BARD overworld sprite ===")
    gen_bard()

    print("\nAll 4 overworld sprite sheets complete.")
